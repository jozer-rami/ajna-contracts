// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { Test } from "forge-std/Test.sol";
import {RandomProviderA} from "../src/RandomProviderA.sol";
import {RandomRequestorB} from "../src/RandomRequestorB.sol";
import {ILayerZeroEndpoint} from "../src/interfaces/ILayerZeroEndpoint.sol";
import {ILayerZeroReceiver} from "../src/interfaces/ILayerZeroReceiver.sol";
import {IPythEntropy} from "../src/interfaces/IPythEntropy.sol";

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

interface ILayerZeroEndpointV2 {
    struct MessagingFee {
        uint256 nativeFee;
        uint256 lzTokenFee;
    }

    struct MessagingReceipt {
        bytes32 guid;
        uint64 nonce;
        MessagingFee fee;
    }

    struct MessagingParams {
        uint32 dstEid;
        bytes32 receiver;
        bytes message;
        bytes options;
        bool payInLzToken;
    }

    function send(MessagingParams calldata _params, address _refundAddress)
        external
        payable
        returns (MessagingReceipt memory);
    function eid() external view returns (uint32);
    function quote(MessagingParams calldata _params) external view returns (MessagingFee memory);
}

contract EndpointV1Wrapper is Test, ILayerZeroEndpoint {
    ILayerZeroEndpointV2 public immutable v2;
    mapping(uint16 => address) public receivers;
    mapping(address => bool) public isReceiver;
    mapping(address => bytes) public trustedRemoteLookup;

    constructor(address _v2) {
        v2 = ILayerZeroEndpointV2(_v2);
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

        // Mock fee for testing
        uint256 fee = 0.01 ether;
        require(msg.value >= fee, "insufficient fee");

        // Refund excess fees
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

contract RandomContractsHelperTest is TestHelperOz5 {
    address public endpointA;
    address public endpointB;
    MockPythEntropy entropy;
    RandomProviderA provider;
    RandomRequestorB requestor;

    function setUp() public virtual override {
        super.setUp();
        setUpEndpoints(2, LibraryType.SimpleMessageLib);

        endpointA = makeAddr("endpointA");
        endpointB = makeAddr("endpointB");
        entropy = new MockPythEntropy();

        // Deploy requestor first with placeholder provider address
        requestor = new RandomRequestorB(endpointB, 1, abi.encodePacked(address(0)));
        // Deploy provider pointing to real requestor
        provider = new RandomProviderA(endpointA, address(entropy), 2, abi.encodePacked(address(requestor)));
        // Update requestor's provider address
        requestor = new RandomRequestorB(endpointB, 1, abi.encodePacked(address(provider)));

        // Mock endpoint behavior for requestor -> provider
        vm.mockCall(
            endpointB,
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
            endpointA,
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
        vm.prank(endpointA);
        provider.lzReceive(1, abi.encodePacked(address(requestor)), 0, abi.encode(uint64(1)));

        // Fund all accounts
        vm.deal(address(this), 10 ether);
        vm.deal(address(provider), 1 ether);
        vm.deal(address(requestor), 1 ether);
        vm.deal(endpointA, 1 ether);
        vm.deal(endpointB, 1 ether);
    }

    function testRequestRandomFlow() public {
        requestor.requestRandom{value: 0.1 ether}();

        bytes32 expected = keccak256(abi.encode(uint64(1)));
        assertEq(requestor.requestCount(), 1);
        assertEq(requestor.randomResults(1), expected);
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
