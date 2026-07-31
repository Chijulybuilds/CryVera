// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IStrategyManager {
    function getStrategyAddress(uint256 strategyId) external view returns (address);
    function strategyCount() external view returns (uint256);
    function strategyAt(uint256 index) external view returns (address);
    function strategyAsset(address strategy) external view returns (address);
    function isActive(address strategy) external view returns (bool);
    function depositToStrategy(address strategy, uint256 assets) external returns (uint256 received);
    function withdrawFromStrategy(address strategy, uint256 assets, address receiver)
        external
        returns (uint256 withdrawn);
    function harvestStrategy(address strategy) external returns (uint256 assetsBefore, uint256 assetsAfter);
}
