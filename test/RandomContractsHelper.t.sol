// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {RandomProviderA} from "../src/RandomProviderA.sol";
import {RandomRequestorB} from "../src/RandomRequestorB.sol";
import {ILayerZeroEndpoint} from "../src/interfaces/ILayerZeroEndpoint.sol";
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
}

contract EndpointV1Wrapper is ILayerZeroEndpoint {
    ILayerZeroEndpointV2 public immutable v2;
    mapping(uint16 => address) public receivers;

    constructor(address _v2) {
        v2 = ILayerZeroEndpointV2(_v2);
    }

    function setReceiver(uint16 _chainId, address receiver) external {
        receivers[_chainId] = receiver;
    }

    function send(
        uint16 _dstChainId,
        bytes calldata, /* _destination */
        bytes calldata _payload,
        address payable _refundAddress,
        address, /* _zroPaymentAddress */
        bytes calldata /* _adapterParams */
    ) external payable override {
        address receiver = receivers[_dstChainId];
        require(receiver != address(0), "unknown dst");
        ILayerZeroEndpointV2.MessagingParams memory params = ILayerZeroEndpointV2.MessagingParams({
            dstEid: uint32(_dstChainId),
            receiver: bytes32(uint256(uint160(receiver))),
            message: _payload,
            options: bytes(""),
            payInLzToken: false
        });
        v2.send{value: msg.value}(params, _refundAddress);
    }
}

contract RandomContractsHelperTest is TestHelperOz5 {
    EndpointV1Wrapper endpointA;
    EndpointV1Wrapper endpointB;
    MockPythEntropy entropy;
    RandomProviderA provider;
    RandomRequestorB requestor;

    function setUp() public virtual override {
        super.setUp();
        setUpEndpoints(2, LibraryType.SimpleMessageLib);

        endpointA = new EndpointV1Wrapper(address(endpoints[1]));
        endpointB = new EndpointV1Wrapper(address(endpoints[2]));
        entropy = new MockPythEntropy();

        requestor = new RandomRequestorB(address(endpointB), 1, abi.encodePacked(address(0)));
        provider = new RandomProviderA(address(endpointA), address(entropy), 2, abi.encodePacked(address(requestor)));

        endpointB.setReceiver(1, address(provider));
        endpointA.setReceiver(2, address(requestor));
    }

    function testRequestRandomFlow() public {
        requestor.requestRandom();
        verifyPackets(1, addressToBytes32(address(provider)));
        verifyPackets(2, addressToBytes32(address(requestor)));

        bytes32 expected = keccak256(abi.encode(uint64(1)));
        assertEq(requestor.requestCount(), 1);
        assertEq(requestor.randomResults(1), expected);
    }
}
