#!/bin/bash

source ./utils.sh

test_get_total_reward () {
    get_total_reward 10 0
    expect 10 $TOTAL_REWARD "get_total_reward 10 0"

    get_total_reward 23 8
    expect 15 $TOTAL_REWARD "get_total_reward 23 8"

    get_total_reward 5 13
    expect 5 $TOTAL_REWARD "get_total_reward 5 13"
}
test_get_total_reward


