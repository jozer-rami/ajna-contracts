// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AJNAOracle} from "../src/AjnaOracle.sol";

contract DeployForkScript is Script {
    function setUp() public {
        // Ensure we're using the fork
        require(block.chainid == vm.envUint("FORK_CHAIN_ID"), "Not running on fork");
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying with address:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy AjnaOracle
        AJNAOracle oracle = new AJNAOracle(
            "AJNAOracle",
            "AJNA",
            deployer, // Using deployer as initial backend signer
            "ipfs://" // Base URI for token metadata
        );

        // Test basic functionality
        oracle.addToWhitelist(deployer);
        oracle.mintWhitelisted(1, "test", "test-cid");

        vm.stopBroadcast();

        // Log deployment addresses and verify functionality
        console.log("AjnaOracle deployed to:", address(oracle));
        console.log("Initial backend signer:", deployer);
        console.log("Token 0 owner:", oracle.ownerOf(0));
        console.log("Token 0 URI:", oracle.tokenURI(0));
    }
}

// Mock ERC6551Registry for testing deployment
contract MockERC6551Registry {
    event CreateAccount(
        address implementation,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId,
        uint256 salt,
        bytes initData
    );

    function createAccount(
        address implementation,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId,
        uint256 salt,
        bytes memory initData
    ) external returns (address) {
        emit CreateAccount(implementation, chainId, tokenContract, tokenId, salt, initData);
        return address(
            uint160(uint256(keccak256(abi.encode(implementation, chainId, tokenContract, tokenId, salt, initData))))
        );
    }
} 