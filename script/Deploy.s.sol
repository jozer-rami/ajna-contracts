// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AJNAOracle} from "../src/AjnaOracle.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy AjnaOracle
        AJNAOracle oracle = new AJNAOracle(
            "AJNAOracle",
            "AJNA",
            vm.addr(deployerPrivateKey), // Using deployer as initial backend signer
            "ipfs://" // Base URI for token metadata
        );

        vm.stopBroadcast();

        // Log deployment addresses
        console.log("AjnaOracle deployed to:", address(oracle));
        console.log("Initial backend signer:", vm.addr(deployerPrivateKey));
    }
} 