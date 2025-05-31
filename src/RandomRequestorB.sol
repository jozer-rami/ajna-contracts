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
    event FeesReceived(uint256 amount);

    constructor(address _endpoint, uint16 _providerChainId, bytes memory _providerAddress) {
        lzEndpoint = ILayerZeroEndpoint(_endpoint);
        providerChainId = _providerChainId;
        providerAddress = _providerAddress;
    }

    /// @notice Sends a cross-chain request for randomness.
    function requestRandom() external payable {
        requestCount++;
        bytes memory payload = abi.encode(requestCount);

        // Get the required fee
        uint256 fee = _getRequiredFee(payload);
        require(msg.value >= fee, "insufficient fee");

        // Send request with exact fee
        bool success = _sendRequest(payload, fee);
        require(success, "send failed");

        // Refund excess fees
        uint256 excess = msg.value - fee;
        if (excess > 0) {
            (bool refundSuccess,) = msg.sender.call{value: excess}("");
            require(refundSuccess, "refund failed");
        }

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

    /// @notice Get the required fee for sending a request
    /// @param _payload The request payload
    /// @return The required fee in native tokens
    function _getRequiredFee(bytes memory _payload) internal view returns (uint256) {
        return 0.01 ether; // Mock fee for testing
    }

    /// @notice Send a request to the provider
    /// @param _payload The request payload
    /// @param _fee The fee to send with the request
    /// @return success Whether the send was successful
    function _sendRequest(bytes memory _payload, uint256 _fee) internal returns (bool) {
        try lzEndpoint.send{value: _fee}(
            providerChainId,
            providerAddress,
            _payload,
            payable(address(this)),
            address(0),
            bytes("")
        ) {
            return true;
        } catch {
            return false;
        }
    }

    // Function to receive ETH
    receive() external payable {
        emit FeesReceived(msg.value);
    }
}
