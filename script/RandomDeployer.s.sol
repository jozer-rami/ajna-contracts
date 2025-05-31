// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {RandomProviderA} from "../src/RandomProviderA.sol";
import {RandomRequestorB} from "../src/RandomRequestorB.sol";

/// @notice Deploys the randomness example contracts on their respective chains.
/// The script expects the following environment variables to be set:
///
/// ROLE                 - "provider" or "requestor" to choose which contract to deploy.
/// PROVIDER_ENDPOINT    - LayerZero endpoint for the provider chain.
/// REQUESTOR_ENDPOINT   - LayerZero endpoint for the requestor chain.
/// PROVIDER_CHAIN_ID    - LayerZero chain id of the provider chain.
/// REQUESTOR_CHAIN_ID   - LayerZero chain id of the requestor chain.
/// PYTH_ENTROPY         - Pyth entropy contract address on the provider chain.
/// PROVIDER_ADDRESS     - Address of the already deployed provider contract (required when ROLE=requestor).
/// REQUESTOR_ADDRESS    - Address of the already deployed requestor contract (required when ROLE=provider).
///
/// Example usage:
///
/// ```bash
/// ROLE=provider \
/// PROVIDER_ENDPOINT=<provider lz endpoint> \
/// REQUESTOR_CHAIN_ID=<requestor chain id> \
/// REQUESTOR_ADDRESS=<requestor address> \
/// PYTH_ENTROPY=<pyth entropy address on base> \
/// forge script script/RandomDeployer.s.sol:RandomDeployer --rpc-url <base_rpc_url> --private-key <key>
/// ```
///
/// ```bash
/// ROLE=requestor \
/// REQUESTOR_ENDPOINT=<requestor lz endpoint> \
/// PROVIDER_CHAIN_ID=<provider chain id> \
/// PROVIDER_ADDRESS=<provider address> \
/// forge script script/RandomDeployer.s.sol:RandomDeployer --rpc-url <worldchain_rpc_url> --private-key <key>
/// ```
contract RandomDeployer is Script {
    function run() external {
        string memory role = vm.envString("ROLE");
        vm.startBroadcast();

        if (keccak256(bytes(role)) == keccak256("provider")) {
            address endpoint = vm.envAddress("PROVIDER_ENDPOINT");
            address entropy = vm.envAddress("PYTH_ENTROPY");
            uint16 requestorChainId = uint16(vm.envUint("REQUESTOR_CHAIN_ID"));
            address requestorAddr = vm.envAddress("REQUESTOR_ADDRESS");

            new RandomProviderA(endpoint, entropy, requestorChainId, abi.encodePacked(requestorAddr));
        } else if (keccak256(bytes(role)) == keccak256("requestor")) {
            address endpoint = vm.envAddress("REQUESTOR_ENDPOINT");
            uint16 providerChainId = uint16(vm.envUint("PROVIDER_CHAIN_ID"));
            address providerAddr = vm.envAddress("PROVIDER_ADDRESS");

            new RandomRequestorB(endpoint, providerChainId, abi.encodePacked(providerAddr));
        } else {
            revert("ROLE must be provider or requestor");
        }

        vm.stopBroadcast();
    }
}

