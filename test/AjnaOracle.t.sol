// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {AJNAOracle} from "../src/AjnaOracle.sol";

interface IERC6551Registry {
    function createAccount(
        address implementation,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId,
        uint256 salt,
        bytes memory initData
    ) external returns (address);
}

contract MockERC6551Registry is IERC6551Registry {
    event CreateAccount(
        address implementation, uint256 chainId, address tokenContract, uint256 tokenId, uint256 salt, bytes initData
    );

    function createAccount(
        address implementation,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId,
        uint256 salt,
        bytes memory initData
    ) external override returns (address) {
        emit CreateAccount(implementation, chainId, tokenContract, tokenId, salt, initData);
        return address(
            uint160(uint256(keccak256(abi.encode(implementation, chainId, tokenContract, tokenId, salt, initData))))
        );
    }
}

contract AjnaOracleTest is Test {
    AJNAOracle public oracle;
    MockERC6551Registry public registry;

    uint256 private backendPrivateKey = 0xA11CE;
    address private backendSigner;
    address private user = address(0xBEEF);

    function setUp() public {
        backendSigner = vm.addr(backendPrivateKey);
        registry = new MockERC6551Registry();

        oracle = new AJNAOracle();
        oracle.initialize("AJNAOracle", "AJNA", address(registry), address(1), backendSigner, "ipfs://");
    }

    function _signVoucher(address to, uint256 nonce, uint256 deadline) internal returns (bytes memory sig) {
        bytes32 structHash =
            keccak256(abi.encode(keccak256("Voucher(address to,uint256 nonce,uint256 deadline)"), to, nonce, deadline));
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("AJNAOracle")),
                keccak256(bytes("1")),
                block.chainid,
                address(oracle)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(backendPrivateKey, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function testRedeemVoucher() public {
        bytes memory sig = _signVoucher(user, 1, block.timestamp + 1 days);
        vm.prank(user);
        oracle.redeemVoucher(user, 1, block.timestamp + 1 days, sig, 1, "hash", "hello");
        assertEq(oracle.ownerOf(1), user);
    }

    function testRedeemVoucherNonceReuse() public {
        bytes memory sig = _signVoucher(user, 1, block.timestamp + 1 days);
        vm.prank(user);
        oracle.redeemVoucher(user, 1, block.timestamp + 1 days, sig, 1, "hash", "hello");
        vm.prank(user);
        vm.expectRevert("Nonce already used");
        oracle.redeemVoucher(user, 1, block.timestamp + 1 days, sig, 1, "hash", "hello");
    }

    function testWhitelistMinting() public {
        oracle.addToWhitelist(user);
        vm.prank(user);
        oracle.mintWhitelisted(1, "hash", "hello");
        assertEq(oracle.ownerOf(1), user);
    }

    function testTokenURIOnchain() public {
        bytes memory sig = _signVoucher(user, 2, block.timestamp + 1 days);
        vm.prank(user);
        oracle.redeemVoucher(user, 2, block.timestamp + 1 days, sig, 1, "hash", "hello");
        string memory uri = oracle.tokenURI(2);
        bytes memory prefix = bytes("data:application/json;base64,");
        for (uint256 i = 0; i < prefix.length; i++) {
            assertEq(bytes(uri)[i], prefix[i]);
        }
    }

    function testWhitelistMintingReverts() public {
        vm.prank(user);
        vm.expectRevert("Not whitelisted");
        oracle.mintWhitelisted(1, "hash", "hello");
    }
}
