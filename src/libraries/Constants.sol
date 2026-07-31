// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                         VERIBRIDGE CONSTANTS
//////////////////////////////////////////////////////////////*/

/// @title Protocol Constants
/// @author Prince_Chinedu(VeriBridge)
/// @notice Shared constants used throughout VeriBridge.
library Constants {
    /// @dev Basis points denominator (100% = 10_000).
    uint256 internal constant BASIS_POINTS = 10_000;

    /// @dev WAD precision (18 decimals).
    uint256 internal constant WAD = 1e18;

    /// @dev Oracle precision.
    uint256 internal constant ORACLE_PRECISION = 1e8;

    /// @dev Maximum oracle heartbeat before considering data stale.
    uint256 internal constant MAX_PRICE_AGE = 1 days;

    /// @dev Maximum supported strategies for V1.
    uint256 internal constant MAX_STRATEGIES = 32;
}
