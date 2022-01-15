#!/bin/bash
# Copyright (C) 2021 Distributed Validators Synctems -- https://validators.network

# This script comes without warranties of any kind. Use at your own risk.

# The purpose of this script is to collect information requred for the DVS Foundation support automation script

# Supported operation systems: Debian, Ubuntu

echo "Welcome to the DVS Foundation support installation script. This script will collect all the data required to run automation."
echo "NO sensitive information will be send to 3rd party services and will be used INSIDE current server only."
echo "Please run this script under same user you are using to run blockchain node."
echo ""
echo "This script may ask you for sudo password because it is required to install additional software: curl, jq, git-core and bc"

DEFAULT_KEYRING_BACKEND="os"
DEFAULT_NODE="http://localhost:26657"
INSTALLATION_DIR="dvs-fund-support"
DVS_FOUNDATION_ADDRESS="dvs_address"

collect_settings () {
    get_rpc_node

    find_node_executable

    get_keyring_settings

    get_validator_owner_name

    echo ""
    echo "Network denomination. Please use denomination used for staking and fee payments"
    read -p "Denomination: " DENOM

    echo ""
    echo "Expected network fee without denomination. For instance: 10000"
    read -p "Fees without denomination: " FEE

    echo ""
    echo "Minimal accumulated commission to withdraw. For addresses with 0% commission."
    echo "Script will accumulate commissions per address and will make a payout once accumulated value riches this number."
    echo "Should be high enough otherwise script will pay too small amount and transaction fee will too high"
    read -p "Minimum commission to withdraw: " MIN_COMMISSION_TO_WITHDRAW

    get_fund_payment_percent 
}

show_collected_settings () {
    echo "Please carefully check that current settings are right."

    echo ""
    echo "Keyring backend: $KEYRING_BACKEND"
    if [ "$KEYRING_BACKEND" != "test" ]; then
        echo "Keyring password: $KEYRING_PASSWORD" 
    fi  
    echo "RPC node address: $NODE"
    echo "Node service full path: $PATH_TO_SERVICE" 
    echo "Validator owner key name: $OWNER_KEY_NAME" 
    echo "Minimum fee: $FEE$DENOM"
    echo "Minimum commission to withdraw: $MIN_COMMISSION_TO_WITHDRAW$DENOM" 
    echo "Chain ID: $CHAIN_ID"
    FUND_REAL_PERCENT=$(echo "$FUND_PERCENT * 100" | bc)
    echo "DVS Foundation percent: $FUND_PERCENT ($FUND_REAL_PERCENT%)"
}

get_rpc_node () {
    echo ""

    while :
    do
        read -p "RPC node address [$DEFAULT_NODE]: " NODE
        if [ -z "$NODE" ]
        then
            NODE=$DEFAULT_NODE
        fi

        NODE_STATUS_CODE=$(curl -m 1 -o /dev/null -s -w "%{http_code}\n" $NODE/status)

        if (( $NODE_STATUS_CODE == 200 )); then
            break
        fi

        echo "RPC node is not accessible. Try another URL."
    done    
}

get_fund_payment_percent () {
    echo ""
    echo "Foundation recurrent payments percent. Recommended value 0.05-0.1. Max 0.2"
    
    floatRe='^[0-9]+(\.[0-9]+)?$'    

    while :
    do
        read -p "Foundation percent: " FUND_PERCENT

        FUND_PERCENT=$(echo $FUND_PERCENT | tr "," ".")

        if [[ $FUND_PERCENT =~ $floatRe ]] && [ $(echo "$FUND_PERCENT <= 0.2" | bc ) -eq 1 ] ; then
            break
        fi

        echo "Wrong value, please enter another one."
    done    
}

get_chain_id () {
    CHAIN_ID=$(curl -s localhost:26657/status | jq -r '.result.node_info.network')
}

get_keyring_settings () {
    echo ""
    echo "Keyring backend, possible values: os, file, test. Default '$DEFAULT_KEYRING_BACKEND'"

    while :
    do
        read -p "Enter keyring backend [$DEFAULT_KEYRING_BACKEND]: " KEYRING_BACKEND
        if [ -z "$KEYRING_BACKEND" ]
        then
            KEYRING_BACKEND=$DEFAULT_KEYRING_BACKEND
        fi

        if [ "$KEYRING_BACKEND" != "test" ]; then
            echo ""
            read -p "Keyring password: " KEYRING_PASSWORD
        fi

        execute_command "keys list --keyring-backend $KEYRING_BACKEND"
        KEYS_LIST_CMD=$FUNC_RETURN
        KEYS_LIST=$(eval $KEYS_LIST_CMD 2>&1 | jq 2>/dev/null)

        if ! [ -z "$KEYS_LIST" ]
        then
            break
        fi

        echo "Wrong keyring backend or password, please try again."
    done    
}

find_node_executable () {
    echo ""
    echo "Node service name. For instance for Cosmos HUB it is \`gaiad\`, Osmosis - \`osmosisd\` etc."
    echo "Also you can provide full path to the node executable."

    while :
    do
        read -p "Node service name: " NODE_SERVICE_NAME
        if ! [ -f "$NODE_SERVICE_NAME" ]; then
            NODE_SERVICE_NAME=$(which $NODE_SERVICE_NAME)
        fi 

        SDK_VERSION=$($NODE_SERVICE_NAME version --long 2>&1 | grep cosmos_sdk_version )      

        if ! [ -z "$SDK_VERSION" ]; then
            PATH_TO_SERVICE=$NODE_SERVICE_NAME
            echo "Full path to node service is: $PATH_TO_SERVICE"
            break
        fi

        echo "Unfortunately Cosmos SDK node service executable was not found. Try another name or full path."
    done
}

get_validator_owner_name () {
    echo ""
    echo "Key name you used to create and control your validator. Please note, this is not validator address but key name."
    echo "Available keys:"

    execute_command "keys list --keyring-backend $KEYRING_BACKEND"
    KEYS_LIST_CMD=$FUNC_RETURN

    KEYS_LIST=$(eval $KEYS_LIST_CMD | jq '.[].name')

    echo $KEYS_LIST | tr " " "\n"

    while :
    do
        read -p "Validator owner key name: " OWNER_KEY_NAME

        if [[ $KEYS_LIST == *"$OWNER_KEY_NAME"* ]]; then
            break
        fi

        echo "Unfortunately this key was not found. Please choose another."
    done
}

execute_command () {
    CMD_PARAMS=$1

    CMD="$PATH_TO_SERVICE $CMD_PARAMS --output json"

    if [ "$KEYRING_BACKEND" != "test" ]; then
        CMD="echo \"$KEYRING_PASSWORD\" | $CMD"
    fi

    FUNC_RETURN=$CMD
}

install_required_software () {
    sudo apt-get install curl jq bc git-core -y

    local ERROR_NO=$?
    if (( $ERROR_NO > 0 )); then
        exit
    fi
}

get_addresses () {
    execute_command "keys show $OWNER_KEY_NAME --bech val --keyring-backend $KEYRING_BACKEND"
    VALIDATOR_ADDRESS_CMD=$FUNC_RETURN

    VALIDATOR_ADDRESS=$(eval $VALIDATOR_ADDRESS_CMD | jq -r '.address')

    execute_command "keys show $OWNER_KEY_NAME --keyring-backend $KEYRING_BACKEND"
    OWNER_ADDRESS_CMD=$FUNC_RETURN

    OWNER_ADDRESS=$(eval $OWNER_ADDRESS_CMD | jq -r '.address')
}

create_environment () {
    cat <<__CONFIG_EOF > config.sh
KEYRING_BACKEND="$KEYRING_BACKEND"
KEYRING_PASSWORD="$KEYRING_PASSWORD"
NODE="$NODE"
PATH_TO_SERVICE="$PATH_TO_SERVICE"
OWNER_KEY_NAME="$OWNER_KEY_NAME"
DENOM="$DENOM"
FEE="$FEE"
MIN_COMMISSION_TO_WITHDRAW="$MIN_COMMISSION_TO_WITHDRAW"
CHAIN_ID="$CHAIN_ID"
FUND_PERCENT="$FUND_PERCENT"
VALIDATOR_ADDRESS="$VALIDATOR_ADDRESS"
OWNER_ADDRESS="$OWNER_ADDRESS"
__CONFIG_EOF
}

create_configs () {
    cat <<__CONFIG_EOF > withdraw_addresses
[
    { "address": "$DVS_FOUNDATION_ADDRESS", "share": $FUND_PERCENT }
]
__CONFIG_EOF
    cat <<__CONFIG_EOF > addresses
$OWNER_ADDRESS
__CONFIG_EOF
}

fetch_git_repo () {
    local DIR="./fund-support-automation"
    if [[ -d $DIR ]]
    then
        cd $DIR
        git fetch
        git reset --hard HEAD
        git merge origin/main
        cd ..
    else
        git clone https://github.com/Distributed-Validators-Synctems/fund-support-automation.git
    fi    
}

add_cronjob_tasks () {
    TMPFILE=`mktemp /tmp/cron.XXXXXX`
    PWD=$(pwd)

    RAND=$(shuf -i 0-5 -n 1)8

    crontab -l > $TMPFILE

    CRON_RECORD=$(cat $TMPFILE | grep "# Commission Cashback Script")
    if [ -z "$CRON_RECORD" ]
    then
        echo "# Commission Cashback Script" >> $TMPFILE
        echo "*/5 * * * * /bin/bash $PWD/fund-support-automation/read_addresses.sh >>$PWD/fund-support-automation/commission_cashback.log 2>&1" >> $TMPFILE
    fi

    CRON_RECORD=$(cat $TMPFILE | grep "# Commission Distribution Script")
    if [ -z "$CRON_RECORD" ]
    then
        echo "# Commission Distribution Script" >> $TMPFILE
        echo "$RAND * * * * /bin/bash $PWD/fund-support-automation/distribute.sh >>$PWD/fund-support-automation/distribute.log 2>&1" >> $TMPFILE
    fi

    echo "Following crontab job configuration will be added"
    cat $TMPFILE
    
    crontab $TMPFILE
}

install_required_software

while :
do
    collect_settings
    get_chain_id
    show_collected_settings

    echo ""
    read -p "Please confirm that settings are correct (y/n): " IS_CORRECT_SETTINGS
    if [ "$IS_CORRECT_SETTINGS" = "y" ]; then
        break
    fi
done

get_addresses

mkdir -p $INSTALLATION_DIR/data
cd $INSTALLATION_DIR

create_environment
create_configs
fetch_git_repo
add_cronjob_tasks
