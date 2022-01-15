# DVS Foundation support automation utility

This tools is intendent to be used to automate support of the DVS Foundation from different validators. 
## Main features:

1. Validator commission withdrawal
2. Distribution of the commission on different addresses with custom share
3. 0% commission for specific delegators

## Supported blockchains

* Cosmos SDK based networks

## Supported operation systems and distributions

### Linux
* Ubuntu
* Debian

## Known issues

I found it difficult to use this tool in conjunction with node inside docker container.


## Usage

In order to install all required tools simply issue following command:

`$ bash <(curl -s https://raw.githubusercontent.com/Distributed-Validators-Synctems/fund-support-automation/main/setup.sh)`

it will go through installation process and prepare configuration files.

It is recommended to collect commission cashback collector script every 5 minutes (otherwise it is possible to catch errors in case if you are pruning old blocks. Please use `pruning = "default"` configuration option in the `app.toml` file.) 

You can update configuration later by editing `address`, `config.sh` and `withdraw_addresses` files.