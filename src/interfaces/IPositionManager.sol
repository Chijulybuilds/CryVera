// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPositionManager {
    function recordDeposit(address account, uint256 strategyId, uint256 shares) external;
    function recordRedemption(address account, uint256 shares) external;
    function recordAllocation(address account, uint256 strategyId, uint16 bps) external;
}
