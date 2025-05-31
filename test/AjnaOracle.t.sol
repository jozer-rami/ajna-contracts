// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {AJNAOracle} from "../src/AjnaOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AjnaOracleTest is Test {
    AJNAOracle public oracle;

    uint256 private backendPrivateKey = 0xA11CE;
    address private backendSigner;
    address private user = address(0xBEEF);
    address private admin = address(0xADEF);

    event RitualOpened(uint256 indexed tokenId, uint256 indexed nonce, uint256 indexed sacredTimestamp);
    event WhitelistToggled(bool enabled);

    function setUp() public {
        backendSigner = vm.addr(backendPrivateKey);

        vm.startPrank(admin);
        oracle = new AJNAOracle(
            "AJNAOracle",
            "AJNA",
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
        assertEq(oracle.backendSigner(), backendSigner);
        assertEq(oracle.owner(), admin);
        assertTrue(oracle.whitelistEnabled());
    }

    // Whitelist Toggle Tests
    function testToggleWhitelist() public {
        vm.startPrank(admin);
        
        // Toggle off
        vm.expectEmit(true, true, true, true);
        emit WhitelistToggled(false);
        oracle.toggleWhitelist();
        assertFalse(oracle.whitelistEnabled());
        
        // Toggle on
        vm.expectEmit(true, true, true, true);
        emit WhitelistToggled(true);
        oracle.toggleWhitelist();
        assertTrue(oracle.whitelistEnabled());
        
        vm.stopPrank();
    }

    function testToggleWhitelistUnauthorized() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        oracle.toggleWhitelist();
    }

    function testMintWithDisabledWhitelist() public {
        // First try minting without being whitelisted (should fail)
        vm.prank(user);
        vm.expectRevert("Not whitelisted");
        oracle.mintWhitelisted(1, "hash", "cid");

        // Disable whitelist
        vm.prank(admin);
        oracle.toggleWhitelist();

        // Now anyone should be able to mint
        vm.prank(user);
        oracle.mintWhitelisted(1, "hash", "cid");
        assertEq(oracle.ownerOf(0), user);

        // Enable whitelist again
        vm.prank(admin);
        oracle.toggleWhitelist();

        // Should fail again for non-whitelisted users
        vm.prank(user);
        vm.expectRevert("Not whitelisted");
        oracle.mintWhitelisted(2, "hash2", "cid2");
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
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
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
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        oracle.setBackendSigner(address(0x9876));
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
