# DVS Foundation support automation utility

This tools is intendent to be used to automate support of the DVS Foundation from different validators. 
## Main features:

1. Validator commission withdrawal
2. Distribution of the commission on different addresses with custom share
3. 0% commission for specific delegators
4. Rewards and commissions redelegation
5. Notifications in case of failure

## Supported blockchains

* Cosmos SDK based networks

## Supported operation systems and distributions

### Linux
* Ubuntu
* Debian

### Supported networks
* SifChain
* Medibloc
* Umee
* Comdex
* Stargaze
* Starname
* Rizon
* Firmachain

If you cannot find your chain in the list simply create a PR with it, or ask me directly (Telegram: https://t.me/Albert_OpenTech).

## Known issues

I found it difficult to use this tool in conjunction with node inside docker container. 
Also please aware that this tool is **NOT** compatible with any kind of redelegation/reinvestment scripts. Please turn it off before using this tool.


## Usage

In order to install all required tools simply issue following command:

`$ bash <(curl -s https://raw.githubusercontent.com/Distributed-Validators-Synctems/fund-support-automation/main/setup.sh)`

it will go through installation process and prepare configuration files.

It is recommended to collect commission cashback collector script every 5 minutes (otherwise it is possible to catch errors in case if you are pruning old blocks. Please use `pruning = "default"` configuration option in the `app.toml` file.) 

You can update configuration later by editing `address`, `config.sh` and `withdraw_addresses` files.

## Notifications

If you want to activate notifications simply create `notification.sh` in same directory as `address`, `config.sh` and `withdraw_addresses`.
And put any code into `send_error_message` functions. This function should accept `CHAIN_ID` parameter.

Example: 
```
#!/bin/bash

send_error_message () {
    local CHAIN_ID=$1 

    local ALERT_MSG=$(cat <<-EOF
<b>[Alerting] Distribution processing error</b>
Tokens distribution processing for chain '<b>$CHAIN_ID</b>' got an error. Please examine <b>debug.log</b>.
EOF
)

    curl --silent -X POST \
        -H 'Content-Type: application/json' \
        -d "{\"parse_mode\": \"html\", \"chat_id\": \"<TELEGRAM CHANNEL ID>\", \"text\": \"$ALERT_MSG\"}" \
        https://api.telegram.org/<TELEGRAM BOT ID AND KEY>/sendMessage
}

```
