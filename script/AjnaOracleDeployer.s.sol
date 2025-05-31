// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {AjnaOracle} from "../src/AjnaOracle.sol";

contract AjnaOracleDeployer is Script {
    function run() external {
        address verifier = vm.envAddress("VERIFIER_ADDRESS");
        uint256 groupId = vm.envUint("GROUP_ID");
        address registry = vm.envAddress("REGISTRY_ADDRESS");
        address implementation = vm.envAddress("ERC6551_IMPLEMENTATION");
        string memory baseUri = vm.envString("BASE_URI");

        vm.startBroadcast();
        AjnaOracle oracle = new AjnaOracle();
        oracle.initialize("AjnaOracle", "AJNA", verifier, groupId, registry, implementation, baseUri);
        vm.stopBroadcast();
    }
}
