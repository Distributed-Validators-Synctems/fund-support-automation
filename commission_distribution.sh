#!/bin/bash

CONFIG_DIR=$1

source $CONFIG_DIR/config.sh

source ./utils.sh

TRANSACTION_OUTPUT_DIR=${1:-"${CONFIG_DIR}"}

ADDRESSES_COUNT=$(wc -l $ADDRESSES_FILE | cut -f1 -d" ")
MIN_VALIDATOR_COMMISSION=$(echo "($ADDRESSES_COUNT + 5) * $MIN_COMMISSION_TO_WITHDRAW" | bc ) #"

echo "Starting new commission distribution: "`date`" ========================="

network_up_and_synced $NODE
get_chain_id $NODE

if [ -f "$LOCK_FILE" ]; then
    echo "Distribution locked due to error. Please see debug.log"
    notify_distribution_failed $CHAIN_ID
    exit
fi

get_validator_commission $PATH_TO_SERVICE "${USE_BALANCE}" "${OWNER_ADDRESS}" "${VALIDATOR_ADDRESS}" $NODE $DENOM

if [ -z "$VALIDATOR_COMMISSION" ]
then
    echo "No validator commission"
    notify_no_commission $CHAIN_ID $VALIDATOR_ADDRESS
    exit
fi

echo "VALIDATOR_COMMISSION: $VALIDATOR_COMMISSION. MIN_VALIDATOR_COMMISSION: $MIN_VALIDATOR_COMMISSION"

if (( $(echo "$MIN_VALIDATOR_COMMISSION > $VALIDATOR_COMMISSION" | bc ) == 1 )); then
    echo "Not enough commission."
    exit
fi

COMMISSION_WITHDRAW=0
CSV_LINE="\""`date`"\";\"$MIN_COMMISSION_TO_WITHDRAW\";\"$VALIDATOR_COMMISSION\""

WITHDRAW_ADRRESSES=$(cat $WITHDRAW_ADDRESSES_FILE)

PRIMARY_ADDRESSES=$(echo "${WITHDRAW_ADRRESSES}" | jq -r '.[] | select(.primary)' | jq -s '.')
WITHDRAW_ADDRESSES_AMOUNT=$(echo "${PRIMARY_ADDRESSES}" | jq 'length - 1')
if [ "$WITHDRAW_ADDRESSES_AMOUNT" -ge "0" ]; then
    for ADDRESS_IDX in $( eval echo {0..$WITHDRAW_ADDRESSES_AMOUNT} )
    do
        ADDRESS_DATA=$(echo "${PRIMARY_ADDRESSES}" | jq ".[$ADDRESS_IDX]")

        get_withdraw_address "$ADDRESS_DATA"
        WITHDRAW_ADDRESS=$FUNC_RETURN

        get_withdraw_share "$ADDRESS_DATA"
        SHARE=$FUNC_RETURN

        COMMISSION_SHARE=$(echo "$VALIDATOR_COMMISSION * $SHARE" | bc -l | cut -f1 -d".") #"

        CSV_LINE="$CSV_LINE;\"$WITHDRAW_ADDRESS\";\"$COMMISSION_SHARE\""

        echo "PRMARY SHARE WITHDRAWAL: $WITHDRAW_ADDRESS | $SHARE | $COMMISSION_SHARE"

        COMMISSION_WITHDRAW=$(echo "$COMMISSION_SHARE + $COMMISSION_WITHDRAW" | bc)
        
        generate_send_tx $WITHDRAW_ADDRESS $COMMISSION_SHARE
    done
fi

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

COMMISSION_REMAINDER=$(echo "$VALIDATOR_COMMISSION - $COMMISSION_WITHDRAW - $VALIDATOR_COMMISSION * $BALANCE_RESERVE - $FEE" | bc -l) #"

CSV_LINE="$CSV_LINE;\"$COMMISSION_REMAINDER\""

echo "COMMISSION_WITHDRAW: $COMMISSION_WITHDRAW"
echo "COMMISSION_REMAINDER: $COMMISSION_REMAINDER"


SECONDARY_ADDRESSES=$(echo "${WITHDRAW_ADRRESSES}" | jq -r '.[] | select((.primary // false) == false)' | jq -s '.')
WITHDRAW_ADDRESSES_AMOUNT=$(echo "${SECONDARY_ADDRESSES}" | jq 'length - 1')
COMMISSION_LEFT=$COMMISSION_REMAINDER

if [ "$WITHDRAW_ADDRESSES_AMOUNT" -ge "0" ]; then
    for ADDRESS_IDX in $( eval echo {0..$WITHDRAW_ADDRESSES_AMOUNT} )
    do
        ADDRESS_DATA=$(echo "${SECONDARY_ADDRESSES}" | jq ".[$ADDRESS_IDX]")

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
fi

echo $CSV_LINE >> ${CONFIG_DIR}/payments.csv

if [[ $USE_BALANCE != "true" && $TOKENS_REDELEGATION = "true" ]]; then
    OWNER_BALANCE=$(${PATH_TO_SERVICE} q bank balances $OWNER_ADDRESS --node $NODE -o json | \
        /usr/bin/jq ".balances[] | select(.denom | contains(\"$DENOM\")).amount | tonumber")

    OWNER_REWARD=$(${PATH_TO_SERVICE} q distribution rewards $OWNER_ADDRESS $VALIDATOR_ADDRESS --node $NODE -o json | \
        /usr/bin/jq ".rewards[] | select(.denom | contains(\"$DENOM\")).amount | tonumber")

    AMOUNT_TO_DELEGATE=$(echo $OWNER_BALANCE+$OWNER_REWARD+$COMMISSION_LEFT-$TOKENS_REMAINDER-$FEE | bc | cut -f1 -d".")

    if (( $(echo "$AMOUNT_TO_DELEGATE > $MIN_COMMISSION_TO_WITHDRAW" | bc ) == 1 )); then
        echo "Redelegating remainded tokens..."
        generate_delegate_tx $OWNER_ADDRESS $VALIDATOR_ADDRESS $DENOM $AMOUNT_TO_DELEGATE
    fi    
fi

echo "Broadcasting withdrawal transaction..."
sed "s/<!#TXS_BATCH>/${TXS_BATCH}/g" ./templates/distribution-json.tmpl > ${TRANSACTION_OUTPUT_DIR}/distribution.json
sed -i "s/<!#DENOM>/${DENOM}/g" ${TRANSACTION_OUTPUT_DIR}/distribution.json
sed -i "s/<!#FEE>/${FEE}/g" ${TRANSACTION_OUTPUT_DIR}/distribution.json
sed -i "s/<!#GAS_LIMIT>/${GAS_LIMIT}/g" ${TRANSACTION_OUTPUT_DIR}/distribution.json

CMD="tx sign $TRANSACTION_OUTPUT_DIR/distribution.json 
    --from $OWNER_ADDRESS 
    --node $NODE 
    --chain-id $CHAIN_ID 
    --keyring-backend $KEYRING_BACKEND 
    --output-document $TRANSACTION_OUTPUT_DIR/signed.json"

execute_command "$CMD"
SIGN_CMD=$FUNC_RETURN

eval $SIGN_CMD

if (( $? > 0 )); then
    touch $LOCK_FILE
    notify_signing_failed $CHAIN_ID 
    exit
fi

TX_RESULT=$($PATH_TO_SERVICE tx broadcast $TRANSACTION_OUTPUT_DIR/signed.json \
    --output json \
    --chain-id $CHAIN_ID \
    --node $NODE)

echo $TX_RESULT

if (( $? > 0 )); then
    notify_broadcast_failed $CHAIN_ID
    exit
fi

TX_CODE=$(echo "${TX_RESULT}" | jq -r '.code')

if [ "$TX_CODE" -gt "0" ]; then
    RAW_LOG=$(echo "${TX_RESULT}" | jq -r '.raw_log')
    notify_broadcast_log $CHAIN_ID "$RAW_LOG"
    exit
fi 


