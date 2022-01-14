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

In order to run scripts included into this tool you will need to setup appropriate crontab rule. It is recommended to collect commission cashback collector script every 5 minutes (otherwise it is possible to catch errors in case if you are pruning old blocks. Please use `pruning = "default"` configuration option in the `app.toml` file.) 

Please use included script (`setup.sh`) to prepare tool configuration.
