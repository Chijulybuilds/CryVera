// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/*//////////////////////////////////////////////////////////////
                           SHARE ACCOUNTING
//////////////////////////////////////////////////////////////*/

/// @title Shares Library
/// @author VeriBridge
/// @notice Utility library for converting between assets and shares.
/// @dev Implements ERC-4626 style accounting.
library Shares {
    using Math for uint256;

    /// @notice Converts deposited assets into vault shares.
    function toShares(uint256 assets, uint256 totalShares, uint256 totalAssets) internal pure returns (uint256) {
        if (totalShares == 0 || totalAssets == 0) {
            return assets;
        }
        return assets.mulDiv(totalShares, totalAssets);
    }

    /// @notice Converts vault shares into redeemable assets.
    function toAssets(uint256 shares, uint256 totalShares, uint256 totalAssets) internal pure returns (uint256) {
        if (totalShares == 0 || totalAssets == 0) {
            return shares;
        }
        return shares.mulDiv(totalAssets, totalShares);
    }

    /// @notice Returns the current exchange rate between shares and assets.
    function exchangeRate(uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        if (totalShares == 0 || totalAssets == 0) {
            return 1e18;
        }

        return totalAssets.mulDiv(1e18, totalShares);
    }
}
