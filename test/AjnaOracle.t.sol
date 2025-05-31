// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {AJNAOracle} from "../src/AjnaOracle.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

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
    address private admin = address(0xADEF);
    address private implementation = address(0x1234);
    bytes32 private constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    event RitualOpened(uint256 indexed tokenId, uint256 indexed nonce, uint256 indexed sacredTimestamp);
    event CreateAccount(address implementation, uint256 chainId, address tokenContract, uint256 tokenId, uint256 salt, bytes initData);

    function setUp() public {
        backendSigner = vm.addr(backendPrivateKey);
        registry = new MockERC6551Registry();

        vm.startPrank(admin);
        oracle = new AJNAOracle(
            "AJNAOracle",
            "AJNA",
            address(registry),
            implementation,
            backendSigner,
            "ipfs://"
        );
        vm.stopPrank();
    }

    function _signVoucher(address to, uint256 nonce, uint256 deadline) internal view returns (bytes memory sig) {
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

    // Constructor & Initial State Tests
    function testInitialState() public view {
        assertEq(oracle.name(), "AJNAOracle");
        assertEq(oracle.symbol(), "AJNA");
        assertEq(address(oracle.erc6551Registry()), address(registry));
        assertEq(oracle.erc6551Implementation(), implementation);
        assertEq(oracle.backendSigner(), backendSigner);
        assertTrue(oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(oracle.hasRole(oracle.ADMIN_ROLE(), admin));
    }

    // Voucher Redemption Tests
    function testRedeemVoucher() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _signVoucher(user, 1, deadline);
        
        vm.prank(user);
        vm.expectEmit(true, true, true, false);
        emit RitualOpened(0, 1, block.timestamp);
        oracle.redeemVoucher(user, 1, deadline, sig, 1, "hash", "cid");
        
        assertEq(oracle.ownerOf(0), user);
        assertEq(oracle.tokenURI(0), "ipfs://cid");
    }

    function testRedeemVoucherExpired() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _signVoucher(user, 1, deadline);
        
        vm.warp(deadline + 1);
        vm.prank(user);
        vm.expectRevert("Voucher expired");
        oracle.redeemVoucher(user, 1, deadline, sig, 1, "hash", "cid");
    }

    function testRedeemVoucherInvalidSigner() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _signVoucher(user, 1, deadline);
        
        // Change backend signer
        vm.prank(admin);
        oracle.setBackendSigner(address(0xDEAD));
        
        vm.prank(user);
        vm.expectRevert("Invalid signature");
        oracle.redeemVoucher(user, 1, deadline, sig, 1, "hash", "cid");
    }

    function testRedeemVoucherNonceReuse() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _signVoucher(user, 1, deadline);
        
        vm.startPrank(user);
        oracle.redeemVoucher(user, 1, deadline, sig, 1, "hash", "cid");
        vm.expectRevert("Nonce already used");
        oracle.redeemVoucher(user, 1, deadline, sig, 1, "hash", "cid");
        vm.stopPrank();
    }

    // Whitelist Tests
    function testWhitelistMinting() public {
        vm.prank(admin);
        oracle.addToWhitelist(user);
        
        uint256 expectedTokenId = 0;
        uint256 expectedTimestamp = block.timestamp;
        
        vm.prank(user);
        vm.expectEmit(true, true, true, true, address(oracle));
        emit RitualOpened(expectedTokenId, 0, expectedTimestamp);
        oracle.mintWhitelisted(1, "hash", "cid");
        
        assertEq(oracle.ownerOf(expectedTokenId), user);
        assertTrue(oracle.whitelist(user));
    }

    function testWhitelistMintingUnauthorized() public {
        vm.prank(user);
        vm.expectRevert("Not whitelisted");
        oracle.mintWhitelisted(1, "hash", "cid");
    }

    function testRemoveFromWhitelist() public {
        vm.startPrank(admin);
        oracle.addToWhitelist(user);
        oracle.removeFromWhitelist(user);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert("Not whitelisted");
        oracle.mintWhitelisted(1, "hash", "cid");
        assertFalse(oracle.whitelist(user));
    }

    // Admin Functions Tests
    function testSetBaseURI() public {
        string memory newBaseURI = "https://api.example.com/";
        
        vm.prank(admin);
        oracle.setBaseURI(newBaseURI);
        
        // Mint a token and check URI
        vm.prank(admin);
        oracle.addToWhitelist(user);
        vm.prank(user);
        oracle.mintWhitelisted(1, "hash", "test-cid");
        assertEq(oracle.tokenURI(0), "https://api.example.com/test-cid");
    }

    function testSetBaseURIUnauthorized() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, ADMIN_ROLE));
        oracle.setBaseURI("https://api.example.com/");
    }

    function testSetBackendSigner() public {
        address newSigner = address(0x9876);
        
        vm.prank(admin);
        oracle.setBackendSigner(newSigner);
        assertEq(oracle.backendSigner(), newSigner);
    }

    function testSetBackendSignerUnauthorized() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, ADMIN_ROLE));
        oracle.setBackendSigner(address(0x9876));
    }

    // ERC6551 Account Creation Tests
    function testTokenBoundAccountCreation() public {
        uint256 deadline = block.timestamp + 1 days;
        bytes memory sig = _signVoucher(user, 1, deadline);
        
        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit CreateAccount(implementation, block.chainid, address(oracle), 0, 0, "");
        oracle.redeemVoucher(user, 1, deadline, sig, 1, "hash", "cid");
    }

    // Token Enumeration Tests
    function testTokenEnumeration() public {
        // Mint multiple tokens
        vm.startPrank(admin);
        oracle.addToWhitelist(user);
        vm.stopPrank();

        vm.startPrank(user);
        oracle.mintWhitelisted(1, "hash1", "cid1");
        oracle.mintWhitelisted(2, "hash2", "cid2");
        oracle.mintWhitelisted(3, "hash3", "cid3");
        vm.stopPrank();

        assertEq(oracle.totalSupply(), 3);
        assertEq(oracle.tokenOfOwnerByIndex(user, 0), 0);
        assertEq(oracle.tokenOfOwnerByIndex(user, 1), 1);
        assertEq(oracle.tokenOfOwnerByIndex(user, 2), 2);
    }

    // Token Transfer Tests
    function testTokenTransfer() public {
        address recipient = address(0x5678);
        
        // Mint and transfer a token
        vm.prank(admin);
        oracle.addToWhitelist(user);
        
        vm.prank(user);
        oracle.mintWhitelisted(1, "hash", "cid");
        
        vm.prank(user);
        oracle.transferFrom(user, recipient, 0);
        
        assertEq(oracle.ownerOf(0), recipient);
        assertEq(oracle.balanceOf(recipient), 1);
        assertEq(oracle.balanceOf(user), 0);
    }
}
