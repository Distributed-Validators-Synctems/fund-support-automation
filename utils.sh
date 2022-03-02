#!/bin/bash

if [ -f "${CONFIG_DIR}/notification.sh" ]; then
    source ${CONFIG_DIR}/notification.sh
fi

DATA_DIR="${CONFIG_DIR}/data/"
LOCK_FILE="${CONFIG_DIR}/lock"
WITHDRAW_ADDRESSES_FILE="${CONFIG_DIR}/withdraw_addresses"
ADDRESSES_FILE="${CONFIG_DIR}/addresses"
NUMBER_RE='^[0-9]*([.][0-9]+)?$'

expect () {
    local EXPECTED=$1
    local ACTUAL=$2
    local MESSAGE=$3

    if [ "$EXPECTED" = "$ACTUAL" ]; then
        echo "✅ $MESSAGE"
    else
        echo "❌ $MESSAGE. Expected: $EXPECTED, actual: $ACTUAL"
    fi    
}

save_delegator_data () {
    local DELEGATOR_DATA_FILE=${1}
    local HEIGHT=${2:-$CURRENT_HEIGHT}
    local CASHBACK=${3:-0}    
    echo "{\"last_height\": $HEIGHT, \"total_cashback\": $CASHBACK}" > $DELEGATOR_DATA_FILE
}

get_last_height () {
    local DELEGATOR_DATA_FILE=${1}

    LAST_HEIGHT=$(cat $DELEGATOR_DATA_FILE | jq ".last_height")
}

get_total_cashback () {
    local DELEGATOR_DATA_FILE=${1}

    TOTAL_CASHBACK=$(cat $DELEGATOR_DATA_FILE | jq ".total_cashback")
}

get_withdraw_address () {
    local CHAIN_DATA=${1}

    FUNC_RETURN=$(echo $CHAIN_DATA | jq -r ".address")
}

get_withdraw_share () {
    local CHAIN_DATA=${1}

    FUNC_RETURN=$(echo $CHAIN_DATA | jq -r ".share | tonumber")
}

get_total_reward () {
    local HEIGHT_REWARD=$1
    local PREV_REWARD=$2

    if (( $(echo "$HEIGHT_REWARD < $PREV_REWARD" | bc ) == 1 )); then
	    TOTAL_REWARD=$HEIGHT_REWARD
    else
	    TOTAL_REWARD=$(echo "$HEIGHT_REWARD-$PREV_REWARD" | bc -l )
    fi
}

get_chain_id () {
    local NODE=$1

    CHAIN_ID=$(curl -s ${NODE}/status | jq -r '.result.node_info.network')
}

execute_command () {
    local CMD_PARAMS=$1

    local CMD="$PATH_TO_SERVICE $CMD_PARAMS --output json"

    if [ "$KEYRING_BACKEND" != "test" ]; then
        local CMD="echo \"$KEYRING_PASSWORD\" | $CMD"
    fi

    FUNC_RETURN=$CMD
}

notify () {
    local MESSAGE=$1 

    # Send notification message to notification service. "send_notification_message" should be implemented in the '../notification.sh'
    if [[ $(type -t send_notification_message) == function ]]; then
        send_notification_message "${MESSAGE}"
    fi    
}

lock_and_notify () {
    local CHAIN_ID=$1 

    touch $LOCK_FILE
    notify_signing_failed $CHAIN_ID 
}

network_up_and_synced () {
    local NODE=$1

    local NODE_STATUS_CODE=$(curl -m 5 -o /dev/null -s -w "%{http_code}\n" $NODE/status)

    if (( $NODE_STATUS_CODE != 200 )); then
        notify_chain_node_not_reachable $NODE
        exit
    fi

    local CHAIN_STATUS=$(curl -s ${NODE}/status)
    local CHAIN_ID=$(echo $CHAIN_STATUS | jq -r '.result.node_info.network')

    local CHAIN_SYNC_STATE=$(echo $CHAIN_STATUS | jq '.result.sync_info.catching_up')
    if [[ "$CHAIN_SYNC_STATE" == "true" ]]
    then
        
        notify_chain_syncing $CHAIN_ID
        exit
    fi

    local LATEST_BLOCK_TIME=$(echo $CHAIN_STATUS | jq -r '.result.sync_info.latest_block_time')

    local CONTROL_TIMESTAMP=$(date -d "-180 seconds" +%s)
    local BLOCK_TIMESTAMP=$(date -d "${LATEST_BLOCK_TIME}" +%s)

    if [$BLOCK_TIMESTAMP -lt $CONTROL_TIMESTAMP]
    then
        notify_chain_not_growing $CHAIN_ID "$BLOCK_TIMESTAMP" "$CONTROL_TIMESTAMP"
        exit
    fi 
}

notify_chain_node_not_reachable () {
    local NODE=$1

    local MESSAGE=$(cat <<-EOF
<b>[Error] Chain node is not reachable</b>
'Node URL <b>$NODE</b>' is not reachable. 

Hostname: <b>$(hostname)</b>

Please examine <b>debug.log</b>.
EOF
)
    notify "${MESSAGE}"
}

notify_chain_not_growing () {
    local CHAIN_ID=$1
    local BLOCK_TIME="${2}"
    local CONTROL_TIME="${3}"

    local MESSAGE=$(cat <<-EOF
<b>[Error] Chain height is not growing</b>
Chain height is not growing, something wrong, please check. 

Hostname: <b>$(hostname)</b>
Chain ID: <b>${CHAIN_ID}</b>
Chain time: <b>${BLOCK_TIME}</b>
Control time: <b>${CONTROL_TIME}</b>

Please examine <b>debug.log</b>.
EOF
)
    notify "${MESSAGE}"
}

notify_chain_syncing () {
    local CHAIN_ID=$1

    local MESSAGE=$(cat <<-EOF
<b>[Notice] Chain is still syncing</b>
Chain is still catching up. 

Hostname: <b>$(hostname)</b>
Chain ID: <b>${CHAIN_ID}</b>

Please examine <b>debug.log</b>.
EOF
)
    notify "${MESSAGE}"
}

notify_signing_failed () {
    local CHAIN_ID=$1

    local MESSAGE=$(cat <<-EOF
<b>[Error] Transaction signing error</b>
Tokens distribution processing was locked due to signing error. 

Hostname: <b>$(hostname)</b>
Chain ID: <b>${CHAIN_ID}</b>

Please examine <b>debug.log</b>.
EOF
)
    notify "${MESSAGE}"
}

notify_broadcast_failed () {
    local CHAIN_ID=$1

    local MESSAGE=$(cat <<-EOF
<b>[Warning] Transaction boradcast was failed</b>
Tokens distribution processing was failed. Unable to broadcast transaction to the network. 

Hostname: <b>$(hostname)</b>
Chain ID: <b>${CHAIN_ID}</b>

Please examine <b>debug.log</b>.
EOF
)
    notify "${MESSAGE}"
}

notify_broadcast_log () {
    local CHAIN_ID=$1
    local LOG="$2"

    local MESSAGE=$(cat <<-EOF
<b>[Error] Distribution processing was failed</b>
Tokens distribution processing was failed due to transaction error. 

Hostname: <b>$(hostname)</b>
Chain ID: <b>${CHAIN_ID}</b>
Log message: '${LOG}'.

Please examine <b>debug.log</b>.
EOF
)
    notify "${MESSAGE}"
}

notify_distribution_failed () {
    local CHAIN_ID=$1

    local MESSAGE=$(cat <<-EOF
<b>[Error] Distribution processing was locked</b>
Tokens distribution processing was locked due to error. 

Hostname: <b>$(hostname)</b>
Chain ID: <b>${CHAIN_ID}</b>

Please examine <b>debug.log</b>.
EOF
)
    notify "${MESSAGE}"
}

notify_no_commission () {
    local CHAIN_ID=$1
    local VALIDATOR_ADDRESS=$2

    local MESSAGE=$(cat <<-EOF
<b>[Notice] No validator commission</b>
Tokens distribution processing for chain '<b>$CHAIN_ID</b>' was failed due to empty validator (<b>$VALIDATOR_ADDRESS</b>) commission. Please examine <b>debug.log</b>.
EOF
)
    notify "${MESSAGE}"
}

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
