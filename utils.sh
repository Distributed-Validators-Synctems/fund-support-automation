#!/bin/bash

if [ -f "../notification.sh" ]; then
    source '../notification.sh'
fi

DATA_DIR="../data/"
LOCK_FILE="./lock"
WITHDRAW_ADDRESSES_FILE="../withdraw_addresses"
ADDRESSES_FILE="../addresses"
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

    local CONTROL_TIME=$(date -d "-180 seconds")
    local BLOCK_TIME=$(date -d "${LATEST_BLOCK_TIME}")

    if [[ "$BLOCK_TIME" < "$CONTROL_TIME" ]];
    then
        notify_chain_not_growing $CHAIN_ID
        exit
    fi 
}

notify_chain_node_not_reachable () {
    local NODE=$1

    local MESSAGE=$(cat <<-EOF
<b>[Error] Chain node is not reachable</b>
'Node URL <b>$NODE</b>' is not reachable. Please examine <b>debug.log</b>.
EOF
)
    notify "${MESSAGE}"
}

notify_chain_not_growing () {
    local CHAIN_ID=$1

    local MESSAGE=$(cat <<-EOF
<b>[Error] Chain height is not growing</b>
'<b>$CHAIN_ID</b>' chain height is not growing, something wrong, please check. Please examine <b>debug.log</b>.
EOF
)
    notify "${MESSAGE}"
}

notify_chain_syncing () {
    local CHAIN_ID=$1

    local MESSAGE=$(cat <<-EOF
<b>[Notice] Chain is still syncing</b>
'<b>$CHAIN_ID</b>' chain is still catching up. Please examine <b>debug.log</b>.
EOF
)
    notify "${MESSAGE}"
}

notify_signing_failed () {
    local CHAIN_ID=$1

    local MESSAGE=$(cat <<-EOF
<b>[Error] Transaction signing error</b>
Tokens distribution processing for chain '<b>$CHAIN_ID</b>' was locked due to signing error. Please examine <b>debug.log</b>.
EOF
)
    notify "${MESSAGE}"
}

notify_broadcast_failed () {
    local CHAIN_ID=$1

    local MESSAGE=$(cat <<-EOF
<b>[Warning] Transaction boradcast was failed</b>
Tokens distribution processing for chain '<b>$CHAIN_ID</b>' was failed. Unable to broadcast transaction to the network. Please examine <b>debug.log</b>.
EOF
)
    notify "${MESSAGE}"
}

notify_distribution_failed () {
    local CHAIN_ID=$1

    local MESSAGE=$(cat <<-EOF
<b>[Error] Distribution processing was locked</b>
Tokens distribution processing for chain '<b>$CHAIN_ID</b>' was locked due to error. Please examine <b>debug.log</b>.
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
