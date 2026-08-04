// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                           INTERFACE
//////////////////////////////////////////////////////////////*/

/// @title IOracle
/// @author Prince_Chinedu(VeriBridge)
/// @notice Interface for retrieving asset pricing information.
/// @dev
/// Oracle implementations abstract Chainlink Price Feeds from the
/// rest of the protocol. Contracts should never interact directly
/// with AggregatorV3 feeds.
interface IOracle {
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets a custom staleness threshold (in seconds) for an asset.
    /// @dev Pass 0 to fall back to the protocol-wide default threshold.
    function setStalenessThreshold(address asset, uint256 threshold) external;

    /// @notice Sets circuit-breaker min/max price bounds for an asset.
    ///         `getPrice` reverts if the feed reports a price outside these bounds.
    function setPriceBounds(address asset, uint256 minPrice, uint256 maxPrice) external;

    /// @notice Clears circuit-breaker bounds for an asset (disables the check).
    function clearPriceBounds(address asset) external;

    /// @notice Sets the optional Chainlink sequencer feed used to pause pricing during downtime.
    function setSequencerFeed(address feed) external;

    /// @notice Sets the maximum allowed age of the sequencer heartbeat before pricing is rejected.
    function setSequencerGracePeriod(uint256 gracePeriod) external;

    /// @notice Emits `PriceFeedUpdated` for the asset's current feed, as
    ///         registered in the AssetRegistry. Pure off-chain observability
    ///         hook — the registry remains the source of truth.
    function syncPriceFeed(address asset) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the latest normalized asset price.
    /// @param asset Asset address.
    /// @return price Price normalized to protocol precision.
    function getPrice(address asset) external view returns (uint256 price);

    /// @notice Returns whether an asset has a registered price feed.
    function hasPriceFeed(address asset) external view returns (bool);

    /// @notice Returns the associated price feed.
    function getPriceFeed(address asset) external view returns (address);

    /// @notice Returns whether oracle data is valid (non-reverting check).
    function isPriceValid(address asset) external view returns (bool);

    /// @notice Returns the effective staleness threshold for an asset
    ///         (custom override, or the protocol default if unset).
    function getStalenessThreshold(address asset) external view returns (uint256);

    /// @notice Returns the configured circuit-breaker bounds for an asset.
    ///         `maxPrice == 0` means no bounds are configured.
    function getPriceBounds(address asset) external view returns (uint256 minPrice, uint256 maxPrice);
}
