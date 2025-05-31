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
        lzEndpoint.send(requestorChainId, requestorAddress, resp, payable(address(this)), address(0), bytes(""));
        emit ResponseSent(id, randomness);
    }
}
