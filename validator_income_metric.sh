#!/bin/bash

cd $(dirname "$0")

CONFIG_DIR=$1
COIN=$2

source $CONFIG_DIR/config.sh


source ./validator_income.sh $CONFIG_DIR $PATH_TO_SERVICE $VALIDATOR_ADDRESS $COIN $DENOM $NODE


echo "opentech_validator_commission_income{coin=\"${COIN}\"} $TOTAL_VALIDATOR_COMMISSION" > /var/lib/node_exporter/opentech_validator_commission_income.prom