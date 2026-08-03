// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    Initializable
} from "lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";
import {AssetTypes} from "../types/Asset.sol";
import {IAssetRegistry} from "../interfaces/IAssetRegistry.sol";
import {IOracle} from "../interfaces/IOracle.sol";

contract OracleManagerUpgradeable is Initializable, AccessControl, IOracle {
    bytes32 public constant ORACLE_ADMIN_ROLE = keccak256("ORACLE_ADMIN_ROLE");

    uint256 public constant PRECISION = 1e18;
    uint256 public constant DEFAULT_STALENESS_THRESHOLD = 3600;

    struct PriceBounds {
        uint256 minPrice;
        uint256 maxPrice;
    }

    IAssetRegistry public i_registry;

    mapping(address => uint256) private s_stalenessThreshold;
    mapping(address => PriceBounds) private s_priceBounds;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin,
        address assetregistry
    ) public initializer {
        if (admin == address(0)) revert Errors.ZeroAddress();
        if (assetregistry == address(0)) revert Errors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ORACLE_ADMIN_ROLE, admin);
        i_registry = IAssetRegistry(assetregistry);
    }

    function setStalenessThreshold(
        address asset,
        uint256 threshold
    ) external onlyRole(ORACLE_ADMIN_ROLE) {
        _requireRegistered(asset);
        s_stalenessThreshold[asset] = threshold;
        emit Events.StalenessThresholdUpdated(asset, threshold);
    }

    function setPriceBounds(
        address asset,
        uint256 minPrice,
        uint256 maxPrice
    ) external onlyRole(ORACLE_ADMIN_ROLE) {
        _requireRegistered(asset);
        if (maxPrice == 0 || minPrice >= maxPrice) {
            revert Errors.InvalidPriceBounds(minPrice, maxPrice);
        }
        s_priceBounds[asset] = PriceBounds({
            minPrice: minPrice,
            maxPrice: maxPrice
        });
        emit Events.PriceBoundsUpdated(asset, minPrice, maxPrice);
    }

    function clearPriceBounds(
        address asset
    ) external onlyRole(ORACLE_ADMIN_ROLE) {
        _requireRegistered(asset);
        delete s_priceBounds[asset];
        emit Events.PriceBoundsCleared(asset);
    }

    function syncPriceFeed(address asset) external {
        AssetTypes.AssetConfig memory config = _requireRegistered(asset);
        emit Events.PriceFeedUpdated(asset, config.priceFeed);
    }

    function getPrice(address asset) external view returns (uint256 price) {
        AssetTypes.AssetConfig memory config = _requireRegistered(asset);
        return _fetchAndValidate(asset, config.priceFeed);
    }

    function hasPriceFeed(address asset) external view returns (bool) {
        (bool ok, AssetTypes.AssetConfig memory config) = _tryGetConfig(asset);
        return ok && config.priceFeed != address(0);
    }

    function getPriceFeed(address asset) external view returns (address) {
        AssetTypes.AssetConfig memory config = _requireRegistered(asset);
        return config.priceFeed;
    }

    function isPriceValid(address asset) external view returns (bool) {
        try OracleManagerUpgradeable(address(this)).getPrice(asset) returns (
            uint256
        ) {
            return true;
        } catch {
            return false;
        }
    }

    function getStalenessThreshold(
        address asset
    ) external view returns (uint256) {
        return _effectiveStalenessThreshold(asset);
    }

    function getPriceBounds(
        address asset
    ) external view returns (uint256 minPrice, uint256 maxPrice) {
        PriceBounds memory bounds = s_priceBounds[asset];
        return (bounds.minPrice, bounds.maxPrice);
    }

    function _requireRegistered(
        address asset
    ) internal view returns (AssetTypes.AssetConfig memory config) {
        config = i_registry.getAsset(asset);
        if (config.asset == address(0)) {
            revert Errors.AssetNotRegistered(asset);
        }
    }

    function _tryGetConfig(
        address asset
    ) internal view returns (bool ok, AssetTypes.AssetConfig memory config) {
        try i_registry.getAsset(asset) returns (
            AssetTypes.AssetConfig memory result
        ) {
            if (result.asset == address(0)) {
                return (false, result);
            }
            return (true, result);
        } catch {
            return (false, config);
        }
    }

    function _fetchAndValidate(
        address asset,
        address priceFeed
    ) internal view returns (uint256) {
        (, int256 answer, , uint256 updatedAt, ) = AggregatorV3Interface(
            priceFeed
        ).latestRoundData();
        if (answer <= 0) revert Errors.InvalidPrice(asset, answer);
        uint256 threshold = _effectiveStalenessThreshold(asset);
        if (block.timestamp - updatedAt > threshold) {
            revert Errors.StalePrice(asset, updatedAt, threshold);
        }
        uint8 feedDecimals = AggregatorV3Interface(priceFeed).decimals();
        uint256 normalized = _normalize(uint256(answer), feedDecimals);
        PriceBounds memory bounds = s_priceBounds[asset];
        if (bounds.maxPrice != 0) {
            if (normalized < bounds.minPrice || normalized > bounds.maxPrice) {
                revert Errors.PriceOutOfBounds(
                    asset,
                    normalized,
                    bounds.minPrice,
                    bounds.maxPrice
                );
            }
        }
        return normalized;
    }

    function _normalize(
        uint256 rawPrice,
        uint8 feedDecimals
    ) internal pure returns (uint256) {
        if (feedDecimals == 18) {
            return rawPrice;
        } else if (feedDecimals < 18) {
            return rawPrice * (10 ** (18 - feedDecimals));
        } else {
            return rawPrice / (10 ** (feedDecimals - 18));
        }
    }

    function _effectiveStalenessThreshold(
        address asset
    ) internal view returns (uint256) {
        uint256 custom = s_stalenessThreshold[asset];
        return custom == 0 ? DEFAULT_STALENESS_THRESHOLD : custom;
    }
}
