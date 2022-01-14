#!/bin/bash

source ../config.sh

DELEGATOR_ADDR=$1
DELEGATOR_DATA_FILE=$2

source ./utils.sh

ADDR_LEN=$(expr length $DELEGATOR_ADDR)
if [ $ADDR_LEN -lt 1 ]; then
    exit
fi

CURRENT_HEIGHT=$(curl $NODE/status -s | jq ".result.sync_info.latest_block_height | tonumber")

get_height_reward () {
    local HEIGHT=$1
    local REWARD=$($PATH_TO_SERVICE q distribution rewards \
        $DELEGATOR_ADDR $VALIDATOR_ADDRESS \
        -o json --node $NODE --height $HEIGHT | \
        /usr/bin/jq ".rewards[] | select(.denom | contains(\"$DENOM\")).amount | tonumber")

    if [[ $REWARD =~ $NUMBER_RE ]] ; then
        HEIGHT_REWARD=${REWARD}        
    else
        HEIGHT_REWARD=0
    fi    
}

get_height_commission () {
    local HEIGHT=$1

    local COMMISSION=$($PATH_TO_SERVICE q staking validator ${VALIDATOR_ADDRESS} \
        --output json --node $NODE --height $HEIGHT | \
        /usr/bin/jq ".commission.commission_rates.rate | tonumber") 

    if [[ $COMMISSION =~ $NUMBER_RE ]] ; then
        HEIGHT_COMMISSION=${COMMISSION}        
    else
        HEIGHT_COMMISSION=0
    fi    
}

if [ ! -f "$DELEGATOR_DATA_FILE" ]; then
    save_delegator_data $DELEGATOR_DATA_FILE $CURRENT_HEIGHT
    exit
fi

get_last_height $DELEGATOR_DATA_FILE
get_total_cashback $DELEGATOR_DATA_FILE

get_height_reward $LAST_HEIGHT
PREV_REWARD=$HEIGHT_REWARD

for HEIGHT in $( eval echo {$LAST_HEIGHT..$CURRENT_HEIGHT} )
do
    get_height_reward $HEIGHT
    get_height_commission $HEIGHT
    get_total_reward $HEIGHT_REWARD $PREV_REWARD

    HEIGHT_CASHBACK=$(echo "$TOTAL_REWARD / (1 - $HEIGHT_COMMISSION) - $TOTAL_REWARD" | bc -l) #"
    TOTAL_CASHBACK=$(echo "$HEIGHT_CASHBACK + $TOTAL_CASHBACK" | bc -l) #"
    PREV_REWARD=$HEIGHT_REWARD
done

echo `date +%T`" - Total cashback for period: $TOTAL_CASHBACK. Last height: $CURRENT_HEIGHT"

save_delegator_data $DELEGATOR_DATA_FILE $CURRENT_HEIGHT $TOTAL_CASHBACK

