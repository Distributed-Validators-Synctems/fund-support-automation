#!/bin/bash

source ../config.sh

source ./utils.sh

TRANSACTION_OUTPUT_DIR=${1:-"."}

ADDRESSES_COUNT=$(wc -l $ADDRESSES_FILE | cut -f1 -d" ")
MIN_VALIDATOR_COMMISSION=$(echo "($ADDRESSES_COUNT + 5) * $MIN_COMMISSION_TO_WITHDRAW" | bc ) #"

echo "Starting new commission distribution: "`date`" ========================="

if [ -f "$LOCK_FILE" ]; then
    echo "Distribution locked due to error. Please see debug.log"
    lock_and_notify $CHAIN_ID
    exit
fi

generate_send_tx () {
    local ADDRESS=$1
    local CASHBACK=$2

    local SEND_TX=$(cat ./templates/send-tx-json.tmpl | sed "s/<!#FROM_ADDRESS>/${OWNER_ADDRESS}/g")
    local SEND_TX=$(echo $SEND_TX | sed "s/<!#TO_ADDRESS>/${ADDRESS}/g")
    local SEND_TX=$(echo $SEND_TX | sed "s/<!#DENOM>/${DENOM}/g")
    local SEND_TX=$(echo $SEND_TX | sed "s/<!#AMOUNT>/${CASHBACK}/g")  

    TXS_BATCH=${TXS_BATCH},${SEND_TX}
}

generate_delegate_tx () {
    local DELEGATOR_ADDRESS=$1
    local VALIDATOR_ADDRESS=$2
    local DENOM=$3
    local AMOUNT=$4

    local DELEGATE_TX=$(cat ./templates/delegate-tx-json.tmpl | sed "s/<!#DELEGATOR_ADDRESS>/${DELEGATOR_ADDRESS}/g")
    local DELEGATE_TX=$(echo $DELEGATE_TX | sed "s/<!#VALIDATOR_ADDRESS>/${VALIDATOR_ADDRESS}/g")
    local DELEGATE_TX=$(echo $DELEGATE_TX | sed "s/<!#DENOM>/${DENOM}/g")
    local DELEGATE_TX=$(echo $DELEGATE_TX | sed "s/<!#AMOUNT>/${AMOUNT}/g")  

    TXS_BATCH=${TXS_BATCH},${DELEGATE_TX}
}

VALIDATOR_COMMISSION=$(${PATH_TO_SERVICE} q distribution commission $VALIDATOR_ADDRESS --node $NODE -o json | \
    /usr/bin/jq ".commission[] | select(.denom | contains(\"$DENOM\")).amount | tonumber")

if [ -z "$VALIDATOR_COMMISSION" ]
then
    echo "No validator commission"
    lock_and_notify $CHAIN_ID
    exit
fi

echo "VALIDATOR_COMMISSION: $VALIDATOR_COMMISSION. MIN_VALIDATOR_COMMISSION: $MIN_VALIDATOR_COMMISSION"

if (( $(echo "$MIN_VALIDATOR_COMMISSION > $VALIDATOR_COMMISSION" | bc ) == 1 )); then
    echo "Not enough commission."
    exit
fi

COMMISSION_WITHDRAW=0
TXS_BATCH=""
CSV_LINE="\""`date`"\";\"$MIN_COMMISSION_TO_WITHDRAW\";\"$VALIDATOR_COMMISSION\""
# Return accumulated commission to selected delegators
while read -r address; do
    echo "Processing address $address..."

    get_last_height "${DATA_DIR}${address}.json" 
    get_total_cashback "${DATA_DIR}${address}.json"

    echo "TOTAL_CASHBACK: $TOTAL_CASHBACK"
    CSV_LINE="$CSV_LINE;\"$address\";\"$TOTAL_CASHBACK\""

    if (( $(echo "$TOTAL_CASHBACK > $MIN_COMMISSION_TO_WITHDRAW" | bc ) == 1 )); then
        save_delegator_data "${DATA_DIR}${address}.json" $LAST_HEIGHT
        CASHBACK=$(echo $TOTAL_CASHBACK | cut -f1 -d".")
        # Do not send tokens to the same address as $OWNER_ADDRESS. But sum $CASHBACK amount.
        if [ "$address" != "$OWNER_ADDRESS" ]; then
            echo "Withdrawing CASHBACK: $CASHBACK"
            generate_send_tx $address $CASHBACK
        fi

        COMMISSION_WITHDRAW=$(echo "$CASHBACK + $COMMISSION_WITHDRAW" | bc)        
    fi      
done < $ADDRESSES_FILE

COMMISSION_REMAINDER=$(echo "$VALIDATOR_COMMISSION - $COMMISSION_WITHDRAW" | bc -l) #"

CSV_LINE="$CSV_LINE;\"$COMMISSION_REMAINDER\""

echo "COMMISSION_WITHDRAW: $COMMISSION_WITHDRAW"
echo "COMMISSION_REMAINDER: $COMMISSION_REMAINDER"

WITHDRAW_ADDRESSES_AMOUNT=$(cat $WITHDRAW_ADDRESSES_FILE | jq 'length - 1')
COMMISSION_LEFT=$COMMISSION_REMAINDER

for ADDRESS_IDX in $( eval echo {0..$WITHDRAW_ADDRESSES_AMOUNT} )
do
    ADDRESS_DATA=$(cat $WITHDRAW_ADDRESSES_FILE | jq ".[$ADDRESS_IDX]")

    get_withdraw_address "$ADDRESS_DATA"
    WITHDRAW_ADDRESS=$FUNC_RETURN

    get_withdraw_share "$ADDRESS_DATA"
    SHARE=$FUNC_RETURN

    COMMISSION_SHARE=$(echo "$COMMISSION_REMAINDER * $SHARE" | bc -l | cut -f1 -d".") #"

    CSV_LINE="$CSV_LINE;\"$WITHDRAW_ADDRESS\";\"$COMMISSION_SHARE\""

    echo "SHARE WITHDRAWAL: $WITHDRAW_ADDRESS | $SHARE | $COMMISSION_SHARE"

    COMMISSION_LEFT=$(echo "$COMMISSION_LEFT - $COMMISSION_SHARE" | bc -l) #"
    
    generate_send_tx $WITHDRAW_ADDRESS $COMMISSION_SHARE
done

echo $CSV_LINE >> payments.csv

if [ "$TOKENS_REDELEGATION" = "true" ]; then
    OWNER_BALANCE=$(${PATH_TO_SERVICE} q bank balances $OWNER_ADDRESS --node $NODE -o json | \
        /usr/bin/jq ".balances[] | select(.denom | contains(\"$DENOM\")).amount | tonumber")

    OWNER_REWARD=$(${PATH_TO_SERVICE} q distribution rewards $OWNER_ADDRESS $VALIDATOR_ADDRESS --node $NODE -o json | \
        /usr/bin/jq ".rewards[] | select(.denom | contains(\"$DENOM\")).amount | tonumber")

    AMOUNT_TO_DELEGATE=$(echo $OWNER_BALANCE+$OWNER_REWARD+$COMMISSION_LEFT-$TOKENS_REMAINDER | bc | cut -f1 -d".")

    if (( $(echo "$AMOUNT_TO_DELEGATE > $MIN_COMMISSION_TO_WITHDRAW" | bc ) == 1 )); then
        echo "Redelegating remainded tokens..."
        generate_delegate_tx $OWNER_ADDRESS $VALIDATOR_ADDRESS $DENOM $AMOUNT_TO_DELEGATE
    fi    
fi

echo "Broadcasting withdrawal transaction..."
sed "s/<!#VALIDATOR_ADDRESS>/${VALIDATOR_ADDRESS}/g" ./templates/distribution-json.tmpl > ${TRANSACTION_OUTPUT_DIR}/distribution.json
sed -i "s/<!#TXS_BATCH>/${TXS_BATCH}/g" distribution.json
sed -i "s/<!#DENOM>/${DENOM}/g" distribution.json
sed -i "s/<!#FEE>/${FEE}/g" distribution.json

CMD="tx sign $TRANSACTION_OUTPUT_DIR/distribution.json 
    --from $OWNER_ADDRESS 
    --node $NODE 
    --chain-id $CHAIN_ID 
    --keyring-backend $KEYRING_BACKEND 
    --output-document $TRANSACTION_OUTPUT_DIR/signed.json"

execute_command "$CMD"
SIGN_CMD=$FUNC_RETURN

eval $SIGN_CMD

catch_error_and_exit $CHAIN_ID

$PATH_TO_SERVICE tx broadcast $TRANSACTION_OUTPUT_DIR/signed.json \
    --chain-id $CHAIN_ID \
    --node $NODE

lock_and_notify $CHAIN_ID
