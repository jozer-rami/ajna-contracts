// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ILayerZeroEndpoint} from "./interfaces/ILayerZeroEndpoint.sol";
import {ILayerZeroReceiver} from "./interfaces/ILayerZeroReceiver.sol";

/// @notice Contract requesting randomness from another chain.
contract RandomRequestorB is ILayerZeroReceiver {
    ILayerZeroEndpoint public immutable lzEndpoint;

    uint16 public providerChainId;
    bytes public providerAddress;

    uint64 public requestCount;

    mapping(uint64 => bytes32) public randomResults;

    event RandomRequested(uint64 indexed id);
    event RandomReceived(uint64 indexed id, bytes32 randomness);

    constructor(address _endpoint, uint16 _providerChainId, bytes memory _providerAddress) {
        lzEndpoint = ILayerZeroEndpoint(_endpoint);
        providerChainId = _providerChainId;
        providerAddress = _providerAddress;
    }

    /// @notice Sends a cross-chain request for randomness.
    function requestRandom() external payable {
        requestCount++;
        bytes memory payload = abi.encode(requestCount);
        lzEndpoint.send{value: msg.value}(
            providerChainId, providerAddress, payload, payable(msg.sender), address(0), bytes("")
        );
        emit RandomRequested(requestCount);
    }

    /// @inheritdoc ILayerZeroReceiver
    function lzReceive(
        uint16, /* _srcChainId */
        bytes calldata, /* _srcAddress */
        uint64, /* _nonce */
        bytes calldata _payload
    ) external override {
        require(msg.sender == address(lzEndpoint), "Not endpoint");
        (uint64 id, bytes32 randomness) = abi.decode(_payload, (uint64, bytes32));
        randomResults[id] = randomness;
        emit RandomReceived(id, randomness);
    }
}
