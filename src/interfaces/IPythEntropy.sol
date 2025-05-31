// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IPythEntropy {
    function requestRandomness() external returns (uint64 requestId);
    function getRandomness(uint64 requestId) external view returns (bytes32 randomness);
}
