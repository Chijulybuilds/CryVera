// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                         INTERNAL IMPORTS
//////////////////////////////////////////////////////////////*/

import {AssetTypes} from "../types/Asset.sol";

/*//////////////////////////////////////////////////////////////
                           INTERFACE
//////////////////////////////////////////////////////////////*/

/// @title IAssetRegistry
/// @author VeriBridge
/// @notice Registry of collateral assets supported by VeriBridge.
/// @dev
/// The registry acts as the single source of truth for supported
/// collateral assets and their associated metadata.
interface IAssetRegistry {
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Registers a new collateral asset. Newly registered assets
    ///         are NOT enabled by default — call `enableAsset` separately.
    /// @param asset The ERC20 token address.
    /// @param priceFeed The Chainlink price feed address for this asset.
    /// @param decimals The token's decimals (e.g. 18 for most ERC20s).
    function registerAsset(address asset, address priceFeed, uint8 decimals) external;

    /// @notice Enables deposits for a previously registered asset.
    function enableAsset(address asset) external;

    /// @notice Disables deposits for a supported asset.
    function disableAsset(address asset) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns asset metadata.
    function getAsset(address asset) external view returns (AssetTypes.AssetConfig memory);

    /// @notice Returns whether an asset is supported and enabled.
    function isSupported(address asset) external view returns (bool);

    /// @notice Returns total supported assets (enabled or disabled).
    function totalAssetsSupported() external view returns (uint256);

    /// @notice Returns asset address by index.
    function assetAt(uint256 index) external view returns (address);
}
