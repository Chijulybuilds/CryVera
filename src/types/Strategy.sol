// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                          STRATEGY TYPES
//////////////////////////////////////////////////////////////*/

/// @title VeriBridge Strategy Types
/// @author Prince_Chinedu(VeriBridge)
/// @notice Shared strategy data structures.
library StrategyTypes {
    struct StrategyConfig {
        uint256 id;
        string name;
        string version;
        address strategy;
        address asset;
        uint256 depositCap;
        bool active;
        bool paused;
    }

    struct StrategyState {
        /// Total assets managed by this strategy (updated via internal accounting).
        uint256 totalAssets;
        /// Internal accounting shares tracked by StrategyManager.
        uint256 totalShares;
        /// Unharvested yield sitting in the underlying protocol.
        uint256 pendingYield;
        /// Lifetime harvested yield.
        uint256 totalYield;
        /// Last harvest timestamp.
        uint256 lastHarvest;
    }
}
