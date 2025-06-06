// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ILayerZeroReceiver {
    function lzReceive(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload)
        external;
}
