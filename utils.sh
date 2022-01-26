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
    local CHAIN_ID=$1 

    # Send error message to notification service. "send_error_message" should be implemented in the '../notification.sh'
    if [[ $(type -t send_error_message) == function ]]; then
        send_error_message $CHAIN_ID
    fi    
}

lock_and_notify () {
    local CHAIN_ID=$1 

    touch $LOCK_FILE
    notify $CHAIN_ID 
}

catch_error_and_notify () {
    local ERROR_NO=$?
    echo "Error: $ERROR_NO"
    local CHAIN_ID=$1    
 
    if (( $ERROR_NO > 0 )); then
        notify $CHAIN_ID
        exit
    fi
}

catch_error_and_exit () {
    local ERROR_NO=$?
    echo "Error: $ERROR_NO"
    local CHAIN_ID=$1    
 
    if (( $ERROR_NO > 0 )); then
        lock_and_notify $CHAIN_ID
        exit
    fi
}