#!/bin/bash
# Copyright (C) 2021 Distributed Validators Synctems -- https://validators.network

# This script comes without warranties of any kind. Use at your own risk.

# The purpose of this script is to collect information requred for the DVS Foundation support automation script

# Supported operation systems: Debian, Ubuntu

# Colors
RED='\033[31m'
GREEN='\033[32m'
NC='\033[0m' # No Color

BOLD='\033[1m'
RESET_BOLD='\033[21m'
UNDERLINE='\033[4m'
RESET_UL='\033[24m'

FLOAT_RE='^[0-9]+(\.[0-9]+)?$' 

echo "*****************************************************************"
echo "*                                                               *"
echo "* Distributed Validators Synctems Foundation support automation *"
echo "*                                                               *"
echo "*****************************************************************"
echo ""
echo "Welcome to the DVS Foundation support installation script. This script will collect all the data required to run automation."
echo -e "${RED}${BOLD}NO${NC} sensitive information will be send to 3rd party services and will be used ${RED}${BOLD}INSIDE${NC} current server only."
echo "Please run this script under same user you are using to run blockchain node."
echo ""
echo -e "Script sources are avaiable on the ${UNDERLINE}https://github.com/Distributed-Validators-Synctems/fund-support-automation/${NC} repository."
echo ""
echo -e "Please aware that this tool is ${RED}${BOLD}NOT${NC} compatible with any kind of redelegation/reinvestment scripts. Please turn it off before using this tool."
echo ""
echo -e "You always can interupt setup process by pressing ${BOLD}Ctrl+C${NC}."
echo ""
echo "This script may ask you for sudo password because it is required to install additional software: curl, jq, git-core and bc"
echo "=================================================================="

DEFAULT_KEYRING_BACKEND="os"
DEFAULT_NODE="http://localhost:26657"
INSTALLATION_DIR="dvs-fund-support"

dvs_supported_chains () {
    local NODE_SERVICE=$(basename $1)

    case $NODE_SERVICE in
        saaged)
            DVS_FOUNDATION_ADDRESS="dvs_address"
            RECOMMENDED_FEE="6500"
            RECOMMENDED_MIN_COMMISSION_TO_WITHDRAW="100000"
            CHAIN_DENOM="usaage"
            return
            ;;
        sifnoded)
            DVS_FOUNDATION_ADDRESS="sif1d6l6msam5svk2vghunjl96ejx6psa0mtav2dwk"
            RECOMMENDED_FEE="130000000000000000"
            RECOMMENDED_MIN_COMMISSION_TO_WITHDRAW="1500000000000000000"
            CHAIN_DENOM="rowan"
            return
            ;;
        panacead)
            DVS_FOUNDATION_ADDRESS="panacea13lam5943597rkcg92wgsa5hmp443nuzg4lzrm2"
            RECOMMENDED_FEE="1300000"
            RECOMMENDED_MIN_COMMISSION_TO_WITHDRAW="5000000"
            CHAIN_DENOM="umed"
            return
            ;;
        umeed)
            DVS_FOUNDATION_ADDRESS="umee1nu6ds4gpfn82nazctulvs09zep6d5ctq6stl3e"
            RECOMMENDED_FEE="0"
            RECOMMENDED_MIN_COMMISSION_TO_WITHDRAW="5000000"
            CHAIN_DENOM="uumee"
            return
            ;;
        comdex)
            DVS_FOUNDATION_ADDRESS="comdex1uhrh5egfe4rt6w9qzkaka7rn56akkyeeh35dpe"
            RECOMMENDED_FEE="8750"
            RECOMMENDED_MIN_COMMISSION_TO_WITHDRAW="1000000"
            CHAIN_DENOM="ucmdx"
            return
            ;;
        starsd)
            DVS_FOUNDATION_ADDRESS="stars1tgzftjnmm9u0hhmfxame06pvy3f69fsz83uq8d"
            RECOMMENDED_FEE="7500"
            RECOMMENDED_MIN_COMMISSION_TO_WITHDRAW="1000000"
            CHAIN_DENOM="ustars"
            return
            ;;
        starnamed)
            DVS_FOUNDATION_ADDRESS="star1c5fh2hgfpwt2z3sya7flgz74w0lcqfdm69ed2e"
            RECOMMENDED_FEE="250000"
            RECOMMENDED_MIN_COMMISSION_TO_WITHDRAW="5000000"
            CHAIN_DENOM="uiov"
            return
            ;;
        rizond)
            DVS_FOUNDATION_ADDRESS="rizon1yf7k60shq3d66ryhgxdep536lfdvx3mm77jxmy"
            RECOMMENDED_FEE="6500"
            RECOMMENDED_MIN_COMMISSION_TO_WITHDRAW="2000000"
            CHAIN_DENOM="uatolo"
            return
            ;;
        mantleNode)
            DVS_FOUNDATION_ADDRESS="mantle1v2qu3lhecer8q22w2aavhgpss2aqgt45ph2zjd"
            RECOMMENDED_FEE="4000"
            RECOMMENDED_MIN_COMMISSION_TO_WITHDRAW="1000000"
            CHAIN_DENOM="umntl"
            return
            ;;
    esac

    echo -e "${RED}ERROR!${NC} This chain is not supported ($NODE_SERVICE)."
    exit 1
}

collect_settings () {
    get_rpc_node

    find_node_executable

    get_keyring_settings

    get_validator_owner_name

    echo ""
    echo "Network denomination. Please use denomination used for staking and fee payments"
    read -p "Denomination [$CHAIN_DENOM]: " DENOM
    if [ -z "$DENOM" ]; then
        DENOM=$CHAIN_DENOM
    fi

    echo ""
    echo "Expected network fee without denomination. For instance: 10000"
    read_number_value "Fees without denomination" $RECOMMENDED_FEE
    FEE=$FUNC_RETURN

    echo ""
    echo "Minimal accumulated commission to withdraw. For addresses with 0% commission."
    echo "Script will accumulate commissions per address and will make a payout once accumulated value riches this number."
    echo "Should be high enough otherwise script will pay too small amount and transaction fee will too high"
    read_number_value "Minimum commission to withdraw" $RECOMMENDED_MIN_COMMISSION_TO_WITHDRAW
    MIN_COMMISSION_TO_WITHDRAW=$FUNC_RETURN

    get_fund_payment_percent 

    activate_redelegation
}

show_collected_settings () {
    echo "*************************************************************"
    echo "*                                                           *"
    echo "*  Please carefully check that current settings are right.  *"
    echo "*                                                           *"
    echo "*************************************************************"


    echo ""
    echo "Keyring backend: $KEYRING_BACKEND"
    if [ "$KEYRING_BACKEND" != "test" ]; then
        echo "Keyring password: $KEYRING_PASSWORD" 
    fi  
    echo "RPC node address: $NODE"
    echo "Node service full path: $PATH_TO_SERVICE" 
    echo "Validator owner key name: $OWNER_KEY_NAME" 
    echo "Validator operator address: $VALIDATOR_ADDRESS"
    echo "Validator owner address: $OWNER_ADDRESS"
    echo "Minimum fee: ${FEE}${DENOM}"
    echo "Minimum commission to withdraw: ${MIN_COMMISSION_TO_WITHDRAW}${DENOM}" 
    FUND_REAL_PERCENT=$(echo "$FUND_PERCENT * 100" | bc)
    echo "Redelegate reward and commission: $TOKENS_REDELEGATION"
    if [[ $TOKENS_REDELEGATION == "true" ]]; then
        echo "Remainder amount: ${TOKENS_REMAINDER}${DENOM}"
    fi

    echo ""
    echo "*************************************************************"
    echo ""
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

        echo -e "${RED}ERROR!${NC} RPC node is not accessible. Try another URL."
    done    
}

get_fund_payment_percent () {
    echo ""
    echo "Foundation recurrent payments percent. Recommended value 0.1-0.15. Minimum 0.1, maximum 0.2"
    
 
    while :
    do
        read -p "Foundation percent: " FUND_PERCENT

        FUND_PERCENT=$(echo "$FUND_PERCENT" | xargs)

        FUND_PERCENT=$(echo $FUND_PERCENT | tr "," ".")

        if [[ $FUND_PERCENT =~ $FLOAT_RE ]] && [ $(echo "$FUND_PERCENT <= 0.2" | bc ) -eq 1 ] && [ $(echo "$FUND_PERCENT >= 0.1" | bc ) -eq 1 ]; then
            break
        fi

        echo -e "${RED}ERROR!${NC} Wrong value, please enter another one."
    done    
}

read_number_value () {
    local TITLE=$1
    local DEFAULT=$2

    if ! [ -z "$DEFAULT" ]
    then
        local TITLE="${TITLE} (${DEFAULT})"
    fi

    while :
    do
        read -p "${TITLE}: " NUMBER_VALUE

        NUMBER_VALUE=$(echo "$NUMBER_VALUE" | xargs)

        if ! [ -z "$DEFAULT" ] && [ -z "$NUMBER_VALUE" ]
        then
            NUMBER_VALUE=$DEFAULT
            break
        fi

        NUMBER_VALUE=$(echo $NUMBER_VALUE | tr "," ".")

        if [[ $NUMBER_VALUE =~ $FLOAT_RE ]] ; then
            break
        fi

        echo -e "${RED}ERROR!${NC} Wrong number value, please enter another one."
    done   

    FUNC_RETURN=$NUMBER_VALUE 
}

get_boolean_option () {
    local TEXT=$1

    while :
    do
        read -p "$TEXT (y/n): "  BOOLEAN_CHAR_VALUE

        if [ "$BOOLEAN_CHAR_VALUE" = "y" ]; then
            return 1
        fi

        if [ "$BOOLEAN_CHAR_VALUE" = "n" ]; then
            return 0
        fi

        echo -e "${RED}ERROR!${NC} Please choose 'y' or 'n'."
    done
}

activate_redelegation () {
    echo ""

    get_boolean_option "Activate tokens redelegation"
    TOKENS_REDELEGATION=$?

    if [ "$TOKENS_REDELEGATION" -eq "1" ]; then
        TOKENS_REDELEGATION="true"
        while :
        do
            echo "Remainder amount of tokens on address after redelegation."
            read -p "Remainder amount: " TOKENS_REMAINDER

            TOKENS_REMAINDER=$(echo $TOKENS_REMAINDER | tr "," ".")

            if [[ $TOKENS_REMAINDER =~ $FLOAT_RE ]] ; then
                return
            fi

            echo -e "${RED}ERROR!${NC} Wrong value, please enter another one."
        done    
    fi  

    TOKENS_REDELEGATION="false"  
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
        local KEYS_LIST_CMD=$FUNC_RETURN

        local KEYS_LIST=$(eval $KEYS_LIST_CMD |& jq '.' 2>/dev/null)

        if ! [ -z "$KEYS_LIST" ]
        then
            break
        fi

        echo -e "${RED}ERROR!${NC} Wrong keyring backend or password, please try again."
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

        local SDK_VERSION=$($NODE_SERVICE_NAME version --long 2>&1 | grep build_tags )      

        if ! [ -z "$SDK_VERSION" ]; then
            PATH_TO_SERVICE=$NODE_SERVICE_NAME
            echo "Full path to node service is: $PATH_TO_SERVICE"
            break
        fi

        echo -e "${RED}ERROR!${NC} Unfortunately Cosmos SDK node service executable was not found. Try another name or full path."
    done

    dvs_supported_chains $PATH_TO_SERVICE
}

get_validator_owner_name () {
    echo ""
    echo "Key name you used to create and control your validator. Please note, this is not validator address but key name."
    echo "Available keys:"

    execute_command "keys list --keyring-backend $KEYRING_BACKEND"
    local KEYS_LIST_CMD=$FUNC_RETURN

    local KEYS_LIST=$(eval $KEYS_LIST_CMD | jq '.[].name')

    echo -en $GREEN
    echo $KEYS_LIST | tr " " "\n"
    echo -en $NC

    while :
    do
        read -p "Validator owner key name: " OWNER_KEY_NAME

        if [[ $KEYS_LIST == *"$OWNER_KEY_NAME"* ]]; then
            break
        fi

        echo -e "${RED}ERROR!${NC} Unfortunately this key was not found. Please choose another."
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
FUND_PERCENT="$FUND_PERCENT"
VALIDATOR_ADDRESS="$VALIDATOR_ADDRESS"
OWNER_ADDRESS="$OWNER_ADDRESS"
GAS_LIMIT="350000"
TOKENS_REDELEGATION="$TOKENS_REDELEGATION"
TOKENS_REMAINDER="$TOKENS_REMAINDER"
USE_BALANCE="false"
BALANCE_RESERVE="0"
NOTIFY_NOT_GROWING_DISABLE="false"
__CONFIG_EOF
}

create_configs () {
    cat <<__CONFIG_EOF > withdraw_addresses
[
    { "address": "$DVS_FOUNDATION_ADDRESS", "share": $FUND_PERCENT, "primary": true }
]
__CONFIG_EOF
    cat <<__CONFIG_EOF > addresses
$OWNER_ADDRESS
__CONFIG_EOF
}

fetch_git_repo () {
    local DIR="./script"
    if [[ -d $DIR ]]
    then
        cd $DIR
        git fetch
        git reset --hard HEAD
        git merge origin/main
        cd ..
    else
        git clone https://github.com/Distributed-Validators-Synctems/fund-support-automation.git script
    fi    
}

add_cronjob_tasks () {
    TMPFILE=`mktemp /tmp/cron.XXXXXX`
    PWD=$(pwd)

    # It is better to run distribution script at any 8th minute within an hour, like: 18, 28, 38 etc
    # This is done to avoid cashback and distribution processes overlapping 
    RAND=$(shuf -i 0-5 -n 1)8

    crontab -l > $TMPFILE

    CRON_RECORD=$(cat $TMPFILE | grep "# DVS Fund Support")
    if [ -z "$CRON_RECORD" ]
    then
        echo "# DVS Fund Support: Commission Cashback Script" >> $TMPFILE
        echo "*/5 * * * * /bin/bash $PWD/script/read_addresses.sh $PWD >>$PWD/commission_cashback.log 2>&1" >> $TMPFILE
    fi

    CRON_RECORD=$(cat $TMPFILE | grep "# Commission Distribution Script")
    if [ -z "$CRON_RECORD" ]
    then
        echo "# DVS Fund Support: Commission Distribution Script" >> $TMPFILE
        echo "$RAND * * * * /bin/bash $PWD/script/distribute.sh $PWD >>$PWD/distribute.log 2>&1" >> $TMPFILE
    fi

    echo "Following crontab job configuration will be added"
    echo ""
    cat $TMPFILE
    
    crontab $TMPFILE
}

install_required_software

while :
do
    collect_settings
    get_addresses
    show_collected_settings

    get_boolean_option "Please confirm that settings are correct"
    IS_CORRECT_SETTINGS=$?

    if [ "$IS_CORRECT_SETTINGS" -eq "1" ]; then
        break
    fi
done

mkdir -p $INSTALLATION_DIR/data
cd $INSTALLATION_DIR

create_environment
create_configs
fetch_git_repo
add_cronjob_tasks
