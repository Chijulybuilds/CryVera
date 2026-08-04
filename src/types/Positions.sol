// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Position Types
/// @notice Structure for storing position metadata
library PositionTypes {
    struct PositionMetadata {
        uint256 cumulativeDepositedShares;
        uint256 cumulativeRedeemedShares;
        uint256 lastStrategyId;
        uint64 updatedAt;
    }
}
