// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            ASSET TYPES
//////////////////////////////////////////////////////////////*/

/// @title VeriBridge Asset Types
/// @author Prince_Chinedu (VeriBridge)
/// @notice Shared asset configuration used throughout the protocol.
/// @dev
/// AssetConfig represents metadata for a supported collateral asset.
/// Runtime balances are intentionally NOT stored here.
library AssetTypes {
    /*//////////////////////////////////////////////////////////////
                            STRUCTS
    //////////////////////////////////////////////////////////////*/
    struct AssetConfig {
        /// @notice ERC20 asset address.
        address asset;
        /// @notice Chainlink price feed.
        address priceFeed;
        /// @notice Token decimals.
        uint8 decimals;
        /// @notice Whether deposits are enabled.
        bool enabled;
    }
}
