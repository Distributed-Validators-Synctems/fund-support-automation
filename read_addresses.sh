#!/bin/bash

cd $(dirname "$0")

source ./utils.sh

echo "Starting new cashback calculation: "`date`" ========================="

while read -r address; do
    echo "Processing address $address..."
    source ./commission_cashback.sh \
        $address \
        "${DATA_DIR}${address}.json"  
done < $ADDRESSES_FILE