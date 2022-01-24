#!/bin/bash

cd $(dirname "$0")

source ./utils.sh

PATH_TO_SERVICE=$1
VALIDATOR_ADDRESS=$2
COIN=$3
DENOM=$4
NODE=${5:-"http://localhost:26657"}

VALIDATOR_DATA_FILE="$DATA_DIR/validator_$VALIDATOR_ADDRESS.json"

CURRENT_HEIGHT=$(curl $NODE/status -s | jq ".result.sync_info.latest_block_height | tonumber")

get_height_commission () {
    local HEIGHT=$1

    local COMMISSION=$($PATH_TO_SERVICE q distribution commission \
        $VALIDATOR_ADDRESS \
        -o json --node $NODE --height $HEIGHT | \
        /usr/bin/jq ".commission[] | select(.denom | contains(\"$DENOM\")).amount | tonumber")

    if [[ $COMMISSION =~ $NUMBER_RE ]] ; then
        HEIGHT_COMMISSION=${COMMISSION}        
    else
        HEIGHT_COMMISSION=0
    fi    
}

if [ ! -f "$VALIDATOR_DATA_FILE" ]; then
    save_delegator_data $VALIDATOR_DATA_FILE $CURRENT_HEIGHT
    exit
fi

get_last_height $VALIDATOR_DATA_FILE

get_height_commission $LAST_HEIGHT
PREV_COMMISSION=$HEIGHT_COMMISSION
TOTAL_VALIDATOR_COMMISSION=0

for HEIGHT in $( eval echo {$LAST_HEIGHT..$CURRENT_HEIGHT} )
do
    get_height_commission $HEIGHT

    if (( $(echo "$HEIGHT_COMMISSION < $PREV_COMMISSION" | bc ) == 1 )); then
        PREV_COMMISSION=0
    fi

    TOTAL_VALIDATOR_COMMISSION=$(echo "$HEIGHT_COMMISSION - $PREV_COMMISSION + $TOTAL_VALIDATOR_COMMISSION" | bc -l)   
    PREV_COMMISSION=$HEIGHT_COMMISSION
done

echo `date +%T`" - Total commission for period: $TOTAL_VALIDATOR_COMMISSION. Last height: $CURRENT_HEIGHT"

save_delegator_data $VALIDATOR_DATA_FILE $CURRENT_HEIGHT
