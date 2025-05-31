// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {AjnaOracle} from "../src/AjnaOracle.sol";

contract MockSemaphoreVerifier is ISemaphoreVerifier {
    function verifyProof(uint256, uint256, uint256, uint256, uint256, uint256[8] calldata) external pure override {}
}

contract MockERC6551Registry is IERC6551Registry {
    address public lastImplementation;
    uint256 public lastChainId;
    address public lastTokenContract;
    uint256 public lastTokenId;
    uint256 public lastSalt;
    bytes public lastInitData;

    function createAccount(
        address implementation,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId,
        uint256 salt,
        bytes memory initData
    ) external override returns (address) {
        lastImplementation = implementation;
        lastChainId = chainId;
        lastTokenContract = tokenContract;
        lastTokenId = tokenId;
        lastSalt = salt;
        lastInitData = initData;
        return address(0x123456);
    }
}

contract AjnaOracleTest is Test {
    AjnaOracle public oracle;
    MockSemaphoreVerifier public verifier;
    MockERC6551Registry public registry;

    address implementation = address(0x1111);
    uint256 groupId = 1;

    function setUp() public {
        verifier = new MockSemaphoreVerifier();
        registry = new MockERC6551Registry();
        oracle = new AjnaOracle();
        oracle.initialize("Ajna", "AJNA", address(verifier), groupId, address(registry), implementation, "ipfs://");
    }

    function testOpenRitual() public {
        uint256[8] memory proof;
        uint256 root = 10;
        uint256 nullifier = 20;
        uint256 cardId = 3;
        string memory birth = "hash";
        string memory cid = "meta.json";

        uint256 ts = block.timestamp;
        vm.expectEmit(true, true, true, false);
        emit AjnaOracle.RitualOpened(1, nullifier, ts);
        oracle.openRitual(proof, root, nullifier, cardId, birth, cid);

        assertEq(oracle.ownerOf(1), address(this));
        assertEq(oracle.tokenURI(1), string(abi.encodePacked("ipfs://", cid)));
        assertTrue(oracle.nullifierHashes(nullifier));
        assertEq(registry.lastTokenId(), 1);
        assertEq(registry.lastTokenContract(), address(oracle));
        assertEq(registry.lastChainId(), block.chainid);
    }

    function testOpenRitualRevertsOnReuse() public {
        uint256[8] memory proof;
        uint256 root = 1;
        uint256 nullifier = 33;

        oracle.openRitual(proof, root, nullifier, 1, "", "cid");
        vm.expectRevert("Nullifier already used");
        oracle.openRitual(proof, root, nullifier, 1, "", "cid");
    }
}
