// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ILayerZeroEndpoint} from "./interfaces/ILayerZeroEndpoint.sol";
import {ILayerZeroReceiver} from "./interfaces/ILayerZeroReceiver.sol";
import {IPythEntropy} from "./interfaces/IPythEntropy.sol";

/// @notice Contract providing randomness via Pyth entropy service.
contract RandomProviderA is ILayerZeroReceiver {
    ILayerZeroEndpoint public immutable lzEndpoint;
    IPythEntropy public immutable entropy;

    uint16 public requestorChainId;
    bytes public requestorAddress;

    event RequestReceived(uint64 indexed id);
    event ResponseSent(uint64 indexed id, bytes32 randomness);
    event FeesReceived(uint256 amount);

    constructor(address _endpoint, address _entropy, uint16 _requestorChainId, bytes memory _requestorAddress) {
        lzEndpoint = ILayerZeroEndpoint(_endpoint);
        entropy = IPythEntropy(_entropy);
        requestorChainId = _requestorChainId;
        requestorAddress = _requestorAddress;
    }

    /// @inheritdoc ILayerZeroReceiver
    function lzReceive(
        uint16, /* _srcChainId */
        bytes calldata, /* _srcAddress */
        uint64, /* _nonce */
        bytes calldata _payload
    ) external override {
        require(msg.sender == address(lzEndpoint), "Not endpoint");
        
        uint64 id = abi.decode(_payload, (uint64));
        emit RequestReceived(id);

        uint64 entropyId = entropy.requestRandomness();
        bytes32 randomness = entropy.getRandomness(entropyId);

        bytes memory resp = abi.encode(id, randomness);
        
        // Get the required fee
        uint256 fee = _getRequiredFee(resp);
        require(address(this).balance >= fee, "insufficient fee");

        // Send response with exact fee
        bool success = _sendResponse(resp, fee);
        require(success, "send failed");

        emit ResponseSent(id, randomness);
    }

    /// @notice Get the required fee for sending a response
    /// @param _payload The response payload
    /// @return The required fee in native tokens
    function _getRequiredFee(bytes memory _payload) internal view returns (uint256) {
        return 0.01 ether; // Mock fee for testing
    }

    /// @notice Send a response to the requestor
    /// @param _payload The response payload
    /// @param _fee The fee to send with the response
    /// @return success Whether the send was successful
    function _sendResponse(bytes memory _payload, uint256 _fee) internal returns (bool) {
        try lzEndpoint.send{value: _fee}(
            requestorChainId,
            requestorAddress,
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
