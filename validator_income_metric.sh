#!/bin/bash

cd $(dirname "$0")

source ../config.sh

COIN=$1

source ./validator_income.sh $PATH_TO_SERVICE $VALIDATOR_ADDRESS $COIN $DENOM $NODE


echo "opentech_validator_commission_income{coin=\"${COIN}\"} $TOTAL_VALIDATOR_COMMISSION" > /var/lib/node_exporter/opentech_validator_commission_income.prom