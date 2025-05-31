#!/bin/bash

# Load environment variables
source .env

# Check if required environment variables are set
if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY not set in .env"
    exit 1
fi

if [ -z "$WLD_RPC_URL" ]; then
    echo "Error: WLD_RPC_URL not set in .env"
    exit 1
fi

if [ -z "$BLOCKSCOUT_API_URL" ]; then
    echo "Error: BLOCKSCOUT_API_URL not set in .env"
    exit 1
fi

# Function to deploy on fork
deploy_fork() {
    echo "Deploying on Worldcoin mainnet fork..."
    forge script script/DeployFork.s.sol:DeployForkScript \
        --rpc-url $WLD_RPC_URL \
        --broadcast \
        --verify \
        --verifier blockscout \
        --verifier-url $BLOCKSCOUT_API_URL \
        -vvvv
}

# Function to deploy on mainnet
deploy_mainnet() {
    echo "Deploying on Worldcoin mainnet..."
    forge script script/Deploy.s.sol:DeployScript \
        --rpc-url $WLD_RPC_URL \
        --broadcast \
        --verify \
        --verifier blockscout \
        --verifier-url $BLOCKSCOUT_API_URL \
        -vvvv
}

# Function to verify an already deployed contract
verify_contract() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo "Usage: $0 verify <contract_address> <contract_name>"
        exit 1
    fi

    CONTRACT_ADDRESS=$1
    CONTRACT_NAME=$2

    echo "Verifying contract $CONTRACT_NAME at address $CONTRACT_ADDRESS..."
    forge verify-contract \
        --rpc-url $WLD_RPC_URL \
        $CONTRACT_ADDRESS \
        "src/${CONTRACT_NAME}.sol:${CONTRACT_NAME}" \
        --verifier blockscout \
        --verifier-url $BLOCKSCOUT_API_URL \
        -vvvv
}

# Parse command line arguments
case "$1" in
    "fork")
        deploy_fork
        ;;
    "mainnet")
        deploy_mainnet
        ;;
    "verify")
        verify_contract "$2" "$3"
        ;;
    *)
        echo "Usage: $0 {fork|mainnet|verify <contract_address> <contract_name>}"
        exit 1
        ;;
esac 