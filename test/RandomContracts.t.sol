// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ILayerZeroReceiver} from "../src/interfaces/ILayerZeroReceiver.sol";
import {ILayerZeroEndpoint} from "../src/interfaces/ILayerZeroEndpoint.sol";
import {IPythEntropy} from "../src/interfaces/IPythEntropy.sol";
import {RandomProviderA} from "../src/RandomProviderA.sol";
import {RandomRequestorB} from "../src/RandomRequestorB.sol";

contract MockLayerZeroEndpoint is Test, ILayerZeroEndpoint {
    uint16 public chainId;
    mapping(uint16 => address) public receivers;
    mapping(address => bool) public isReceiver;
    mapping(address => bytes) public trustedRemoteLookup;

    constructor(uint16 _chainId) {
        chainId = _chainId;
    }

    function setReceiver(uint16 _chainId, address receiver) external {
        receivers[_chainId] = receiver;
        isReceiver[receiver] = true;
    }

    function setTrustedRemote(address _receiver, bytes calldata _path) external {
        trustedRemoteLookup[_receiver] = _path;
    }

    function send(
        uint16 _dstChainId,
        bytes calldata _destination,
        bytes calldata _payload,
        address payable _refundAddress,
        address, /* _zroPaymentAddress */
        bytes calldata /* _adapterParams */
    ) external payable override {
        address receiver = receivers[_dstChainId];
        require(receiver != address(0), "unknown dst");
        require(isReceiver[receiver], "not a receiver");
        
        // Verify trusted remote path
        require(keccak256(_destination) == keccak256(trustedRemoteLookup[msg.sender]), "invalid destination");

        // Forward any excess fees back to refund address
        uint256 fee = 0.01 ether; // Mock fee
        if (msg.value > fee) {
            (bool success, ) = _refundAddress.call{value: msg.value - fee}("");
            require(success, "refund failed");
        }

        // Call lzReceive on the receiver with this endpoint as the sender
        vm.startPrank(address(this));
        ILayerZeroReceiver(receiver).lzReceive(_dstChainId, abi.encodePacked(msg.sender), 0, _payload);
        vm.stopPrank();
    }

    receive() external payable {}
}

contract MockPythEntropy is IPythEntropy {
    uint64 public nextId = 1;
    mapping(uint64 => bytes32) public randoms;

    function requestRandomness() external returns (uint64 requestId) {
        requestId = nextId++;
        randoms[requestId] = keccak256(abi.encode(requestId));
    }

    function getRandomness(uint64 requestId) external view returns (bytes32) {
        return randoms[requestId];
    }
}

contract RandomContractsTest is Test {
    address public endpointProvider;
    address public endpointRequestor;
    MockPythEntropy entropy;
    RandomProviderA provider;
    RandomRequestorB requestor;

    function setUp() public {
        endpointProvider = makeAddr("endpointProvider");
        endpointRequestor = makeAddr("endpointRequestor");
        entropy = new MockPythEntropy();

        // Deploy requestor first with placeholder provider address
        requestor = new RandomRequestorB(endpointRequestor, 1, abi.encodePacked(address(0)));
        // Deploy provider pointing to real requestor
        provider = new RandomProviderA(endpointProvider, address(entropy), 2, abi.encodePacked(address(requestor)));
        // Update requestor's provider address
        requestor = new RandomRequestorB(endpointRequestor, 1, abi.encodePacked(address(provider)));

        // Mock endpoint behavior for requestor -> provider
        vm.mockCall(
            endpointRequestor,
            abi.encodeWithSelector(
                ILayerZeroEndpoint.send.selector,
                uint16(1),
                abi.encodePacked(address(provider)),
                abi.encode(uint64(1)),
                payable(address(requestor)),
                address(0),
                bytes("")
            ),
            bytes("")
        );

        // Mock endpoint behavior for provider -> requestor
        vm.mockCall(
            endpointProvider,
            abi.encodeWithSelector(
                ILayerZeroEndpoint.send.selector,
                uint16(2),
                abi.encodePacked(address(requestor)),
                abi.encode(uint64(1), keccak256(abi.encode(uint64(1)))),
                payable(address(provider)),
                address(0),
                bytes("")
            ),
            bytes("")
        );

        // Simulate the message passing
        vm.prank(endpointProvider);
        provider.lzReceive(1, abi.encodePacked(address(requestor)), 0, abi.encode(uint64(1)));

        // Fund all accounts
        vm.deal(address(this), 10 ether);
        vm.deal(address(provider), 1 ether);
        vm.deal(address(requestor), 1 ether);
        vm.deal(endpointProvider, 1 ether);
        vm.deal(endpointRequestor, 1 ether);
    }

    function testRequestRandomFlow() public {
        // Request random with enough value to cover fees
        requestor.requestRandom{value: 0.1 ether}();

        bytes32 expected = keccak256(abi.encode(uint64(1)));

        assertEq(requestor.requestCount(), 1);
        assertEq(requestor.randomResults(1), expected);
    }

    function testProviderLzReceiveRevertsIfNotEndpoint() public {
        vm.expectRevert("Not endpoint");
        provider.lzReceive(1, bytes(""), 0, bytes(""));
    }

    function testRequestorLzReceiveRevertsIfNotEndpoint() public {
        vm.expectRevert("Not endpoint");
        requestor.lzReceive(1, bytes(""), 0, bytes(""));
    }

    function testRequestRandomFlowWithInsufficientFee() public {
        vm.expectRevert("insufficient fee");
        requestor.requestRandom{value: 0.001 ether}();
    }

    function testRequestRandomFlowWithExcessFee() public {
        uint256 initialBalance = address(this).balance;
        
        requestor.requestRandom{value: 0.2 ether}();

        // Should get refunded the excess fee
        assertGt(address(this).balance, initialBalance - 0.2 ether);
    }

    receive() external payable {}
}
