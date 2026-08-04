// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                         EXTERNAL IMPORTS
//////////////////////////////////////////////////////////////*/

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/*//////////////////////////////////////////////////////////////
                         INTERNAL IMPORTS
//////////////////////////////////////////////////////////////*/

import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";
import {AssetTypes} from "../types/Asset.sol";
import {IAssetRegistry} from "../interfaces/IAssetRegistry.sol";
import {IOracle} from "../interfaces/IOracle.sol";

/*//////////////////////////////////////////////////////////////
                         ORACLE MANAGER
//////////////////////////////////////////////////////////////*/

/// @title VeriBridge Oracle Manager
/// @author Prince Chinedu (VeriBridge)
/// @notice Normalizes and validates Chainlink price data for assets
///         registered in the AssetRegistry.
/// @dev
/// OracleManager does NOT maintain its own asset -> feed mapping.
/// The AssetRegistry is the single source of truth for which feed
/// belongs to which asset; this contract only adds a validation and
/// normalization layer on top of it:
///
/// - Staleness checks (per-asset heartbeat, with a protocol default)
/// - Circuit-breaker sanity bounds (per-asset min/max price)
/// - Normalization to protocol precision (18 decimals)
///
/// This contract intentionally does NOT:
/// - Store price feed addresses (the registry owns that)
/// - Gate on whether an asset is `enabled` (pricing must keep working
///   for disabled assets so existing positions can still be valued,
///   withdrawn, or liquidated)
/// - Hold funds, or make any external calls other than read-only
///   staticcalls to Chainlink aggregators
contract OracleManager is AccessControl, IOracle {
    /*//////////////////////////////////////////////////////////////
                               ROLES
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant ORACLE_ADMIN_ROLE = keccak256("ORACLE_ADMIN_ROLE");

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Protocol-wide price precision (18 decimals, WAD).
    uint256 public constant PRECISION = 1e18;

    /// @notice Fallback staleness threshold (seconds) for any asset
    ///         without a custom override. 1 hour is conservative for
    ///         most major Chainlink USD feeds (typically ~1h-24h
    ///         heartbeats) — tighten per-asset via `setStalenessThreshold`
    ///         for feeds with faster heartbeats.
    uint256 public constant DEFAULT_STALENESS_THRESHOLD = 3600;

    /*//////////////////////////////////////////////////////////////
                               TYPES
    //////////////////////////////////////////////////////////////*/

    //// @dev takes the address of the asset then sets the price bounds
    struct PriceBounds {
        uint256 minPrice;
        uint256 maxPrice;
    }

    /*//////////////////////////////////////////////////////////////
                            IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    IAssetRegistry public immutable i_registry;

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev 0 means "use DEFAULT_STALENESS_THRESHOLD".
    mapping(address => uint256) private s_stalenessThreshold;

    /// @dev maxPrice == 0 means "no circuit breaker configured".
    mapping(address => PriceBounds) private s_priceBounds;

    /// @notice Optional Chainlink sequencer uptime feed used to halt pricing during downtime.
    address public sequencerFeed;

    /// @notice Grace period before a stale sequencer heartbeat is treated as unhealthy.
    uint256 public sequencerGracePeriod;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address admin, address assetregistry) {
        if (admin == address(0)) revert Errors.ZeroAddress();
        if (assetregistry == address(0)) revert Errors.ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ORACLE_ADMIN_ROLE, admin);

        i_registry = IAssetRegistry(assetregistry);
        sequencerGracePeriod = 3600;
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOracle
    function setStalenessThreshold(address asset, uint256 threshold) external onlyRole(ORACLE_ADMIN_ROLE) {
        _requireRegistered(asset);

        s_stalenessThreshold[asset] = threshold;

        emit Events.StalenessThresholdUpdated(asset, threshold);
    }

    /// @inheritdoc IOracle
    function setPriceBounds(address asset, uint256 minPrice, uint256 maxPrice) external onlyRole(ORACLE_ADMIN_ROLE) {
        _requireRegistered(asset);

        if (maxPrice == 0 || minPrice >= maxPrice) {
            revert Errors.InvalidPriceBounds(minPrice, maxPrice);
        }

        s_priceBounds[asset] = PriceBounds({minPrice: minPrice, maxPrice: maxPrice});

        emit Events.PriceBoundsUpdated(asset, minPrice, maxPrice);
    }

    /// @inheritdoc IOracle
    function clearPriceBounds(address asset) external onlyRole(ORACLE_ADMIN_ROLE) {
        _requireRegistered(asset);
        delete s_priceBounds[asset];
        emit Events.PriceBoundsCleared(asset);
    }

    /// @inheritdoc IOracle
    function setSequencerFeed(address feed) external onlyRole(ORACLE_ADMIN_ROLE) {
        sequencerFeed = feed;
    }

    /// @inheritdoc IOracle
    function setSequencerGracePeriod(uint256 gracePeriod) external onlyRole(ORACLE_ADMIN_ROLE) {
        sequencerGracePeriod = gracePeriod;
    }

    /// @inheritdoc IOracle
    /// @dev Pure observability hook for off-chain indexers — re-emits
    ///      the registry's current feed for `asset`. Does not mutate
    ///      any state here.
    function syncPriceFeed(address asset) external {
        AssetTypes.AssetConfig memory config = _requireRegistered(asset);
        emit Events.PriceFeedUpdated(asset, config.priceFeed);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOracle
    /// @dev Reverts (rather than returning 0) on stale, invalid, or
    ///      out-of-bounds prices. Callers that need a non-reverting
    ///      check should use `isPriceValid` first.
    function getPrice(address asset) external view returns (uint256 price) {
        AssetTypes.AssetConfig memory config = _requireRegistered(asset);
        _validateSequencer();
        return _fetchAndValidate(asset, config.priceFeed);
    }

    /// @inheritdoc IOracle
    function hasPriceFeed(address asset) external view returns (bool) {
        (bool ok, AssetTypes.AssetConfig memory config) = _tryGetConfig(asset);
        return ok && config.priceFeed != address(0);
    }

    /// @inheritdoc IOracle
    function getPriceFeed(address asset) external view returns (address) {
        AssetTypes.AssetConfig memory config = _requireRegistered(asset);
        return config.priceFeed;
    }

    /// @inheritdoc IOracle
    /// @dev Non-reverting wrapper around `getPrice`, using `try/catch`
    ///      on an external self-call. This lets other protocol contracts
    ///      (e.g. a liquidation keeper) probe price health without
    ///      needing to wrap their own calls in try/catch.
    function isPriceValid(address asset) external view returns (bool) {
        try OracleManager(address(this)).getPrice(asset) returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }

    /// @inheritdoc IOracle
    function getStalenessThreshold(address asset) external view returns (uint256) {
        return _effectiveStalenessThreshold(asset);
    }

    /// @inheritdoc IOracle
    function getPriceBounds(address asset) external view returns (uint256 minPrice, uint256 maxPrice) {
        PriceBounds memory bounds = s_priceBounds[asset];
        return (bounds.minPrice, bounds.maxPrice);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Fetches the asset config from the registry, reverting if
    ///      the asset has never been registered. Deliberately does NOT
    ///      check `config.enabled` — see contract-level @dev notes.
    function _requireRegistered(address asset) internal view returns (AssetTypes.AssetConfig memory config) {
        config = i_registry.getAsset(asset);
        if (config.asset == address(0)) {
            revert Errors.AssetNotRegistered(asset);
        }
    }

    /// @dev Non-reverting variant of `_requireRegistered`, for views
    ///      like `hasPriceFeed` that must never revert.
    function _tryGetConfig(address asset) internal view returns (bool ok, AssetTypes.AssetConfig memory config) {
        try i_registry.getAsset(asset) returns (AssetTypes.AssetConfig memory result) {
            if (result.asset == address(0)) {
                return (false, result);
            }
            return (true, result);
        } catch {
            return (false, config);
        }
    }

    function _validateSequencer() internal view {
        if (sequencerFeed == address(0)) return;

        try AggregatorV3Interface(sequencerFeed).latestRoundData() returns (
            uint80, int256 answer, uint256, uint256 updatedAt, uint80
        ) {
            if (answer == 0) revert Errors.SequencerDown();
            if (updatedAt == 0 || block.timestamp - updatedAt > sequencerGracePeriod) {
                revert Errors.SequencerDown();
            }
        } catch {
            revert Errors.SequencerDown();
        }
    }

    /// @dev Pulls the latest round from the Chainlink feed, validates
    ///      freshness and sanity, then normalizes to 18 decimals.
    function _fetchAndValidate(address asset, address priceFeed) internal view returns (uint256) {
        (, int256 answer,, uint256 updatedAt,) = AggregatorV3Interface(priceFeed).latestRoundData();

        if (answer <= 0) {
            revert Errors.InvalidPrice(asset, answer);
        }

        uint256 threshold = _effectiveStalenessThreshold(asset);
        if (block.timestamp - updatedAt > threshold) {
            revert Errors.StalePrice(asset, updatedAt, threshold);
        }

        uint8 feedDecimals = AggregatorV3Interface(priceFeed).decimals();
        uint256 normalized = _normalize(uint256(answer), feedDecimals);

        PriceBounds memory bounds = s_priceBounds[asset];
        if (bounds.maxPrice != 0) {
            if (normalized < bounds.minPrice || normalized > bounds.maxPrice) {
                revert Errors.PriceOutOfBounds(asset, normalized, bounds.minPrice, bounds.maxPrice);
            }
        }
        return normalized;
    }

    /// @dev Normalizes a raw feed answer to `PRECISION` (18 decimals).
    function _normalize(uint256 rawPrice, uint8 feedDecimals) internal pure returns (uint256) {
        if (feedDecimals == 18) {
            return rawPrice;
        } else if (feedDecimals < 18) {
            return rawPrice * (10 ** (18 - feedDecimals));
        } else {
            return rawPrice / (10 ** (feedDecimals - 18));
        }
    }

    /// @dev Returns the per-asset override if set, else the protocol default.
    function _effectiveStalenessThreshold(address asset) internal view returns (uint256) {
        uint256 custom = s_stalenessThreshold[asset];
        return custom == 0 ? DEFAULT_STALENESS_THRESHOLD : custom;
    }
}
