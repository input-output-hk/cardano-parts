# Sourcing this file will sync env vars to shell vars
# which may be mismatched in some shells, such as zsh
# when setenv() was used
eval "export $(env | grep CARDANO_NODE_SOCKET_PATH)"
eval "export $(env | grep CARDANO_NODE_NETWORK_ID)"
eval "export $(env | grep TESTNET_MAGIC)"
