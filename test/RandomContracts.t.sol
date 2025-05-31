// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ILayerZeroReceiver} from "../src/interfaces/ILayerZeroReceiver.sol";
import {ILayerZeroEndpoint} from "../src/interfaces/ILayerZeroEndpoint.sol";
import {IPythEntropy} from "../src/interfaces/IPythEntropy.sol";
import {RandomProviderA} from "../src/RandomProviderA.sol";
import {RandomRequestorB} from "../src/RandomRequestorB.sol";

contract MockLayerZeroEndpoint is ILayerZeroEndpoint {
    uint16 public chainId;
    mapping(uint16 => address) public receivers;

    constructor(uint16 _chainId) {
        chainId = _chainId;
    }

    function setReceiver(uint16 _chainId, address receiver) external {
        receivers[_chainId] = receiver;
    }

    function send(
        uint16 _dstChainId,
        bytes calldata, /* _destination */
        bytes calldata _payload,
        address payable, /* _refundAddress */
        address, /* _zroPaymentAddress */
        bytes calldata /* _adapterParams */
    ) external payable override {
        address receiver = receivers[_dstChainId];
        require(receiver != address(0), "unknown dst");
        ILayerZeroReceiver(receiver).lzReceive(chainId, abi.encode(msg.sender), 0, _payload);
    }
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
    MockLayerZeroEndpoint endpointProvider;
    MockLayerZeroEndpoint endpointRequestor;
    MockPythEntropy entropy;
    RandomProviderA provider;
    RandomRequestorB requestor;

    function setUp() public {
        endpointProvider = new MockLayerZeroEndpoint(1);
        endpointRequestor = new MockLayerZeroEndpoint(2);
        entropy = new MockPythEntropy();

        // Deploy requestor first with placeholder provider address
        requestor = new RandomRequestorB(address(endpointRequestor), 1, abi.encodePacked(address(0)));
        // Deploy provider pointing to real requestor
        provider =
            new RandomProviderA(address(endpointProvider), address(entropy), 2, abi.encodePacked(address(requestor)));

        // Configure routing in endpoints
        endpointRequestor.setReceiver(1, address(provider));
        endpointProvider.setReceiver(2, address(requestor));
    }

    function testRequestRandomFlow() public {
        requestor.requestRandom();
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
}
