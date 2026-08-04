// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                         EXTERNAL IMPORTS
//////////////////////////////////////////////////////////////*/

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Initializable} from "lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
/*//////////////////////////////////////////////////////////////
                         INTERNAL IMPORTS
//////////////////////////////////////////////////////////////*/

import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";
import {AssetTypes} from "../types/Asset.sol";
import {IAssetRegistry} from "../interfaces/IAssetRegistry.sol";

/*//////////////////////////////////////////////////////////////
                         ASSET REGISTRY
//////////////////////////////////////////////////////////////*/

/// @title VeriBridge Asset Registry
/// @author Prince Chinedu (VeriBridge)
/// @notice Upgradeable Registry responsible for managing all collateral assets
///         supported by the VeriBridge protocol.
/// @dev
/// This contract is an upgradeable implementation for the source of truth for supported assets.
/// Every asset registered here may be deposited into the canonical vault.
///
/// Responsibilities:
/// - Register collateral assets
/// - Enable / disable deposits
/// - Store asset metadata
/// - Expose asset information
///
/// This contract intentionally does NOT:
/// - Hold user funds
/// - Perform oracle calculations
/// - Manage strategies
/// - Execute vault accounting
contract AssetRegistry is AccessControl, IAssetRegistry, Initializable {
    /*//////////////////////////////////////////////////////////////
                               ROLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant REGISTRY_ADMIN_ROLE = keccak256("REGISTRY_ADMIN_ROLE");
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint8 private constant MAX_DECIMALS = 18;
    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/
    mapping(address => AssetTypes.AssetConfig) private s_assets;
    address[] private s_supportedAssets;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    /**
     * @param admin Best should be a wallet address that will be in charge of asset regeistration
     */
    function initialize(address admin) public initializer {
        if (admin == address(0)) {
            revert Errors.ZeroAddress();
        }
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRY_ADMIN_ROLE, admin);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAssetRegistry
    /// @dev Registers an asset in a disabled state. Call `enableAsset`
    ///      once you've confirmed the price feed is healthy.
    function registerAsset(address asset, address priceFeed, uint8 decimals) external onlyRole(REGISTRY_ADMIN_ROLE) {
        if (asset == address(0)) revert Errors.ZeroAddress();
        if (priceFeed == address(0)) revert Errors.ZeroAddress();
        if (decimals == 0 || decimals > MAX_DECIMALS) {
            revert Errors.InvalidDecimals(decimals);
        }
        _requireNotSupported(asset);
        _validatePriceFeed(priceFeed);
        s_assets[asset] =
            AssetTypes.AssetConfig({asset: asset, priceFeed: priceFeed, decimals: decimals, enabled: false});

        s_supportedAssets.push(asset);
        emit Events.AssetRegistered(asset, priceFeed, decimals);
    }

    /// @inheritdoc IAssetRegistry
    function enableAsset(address asset) external onlyRole(REGISTRY_ADMIN_ROLE) {
        _requireSupported(asset);

        AssetTypes.AssetConfig storage config = s_assets[asset];
        if (config.enabled) revert Errors.AssetAlreadyEnabled(asset);

        config.enabled = true;

        emit Events.AssetEnabled(asset);
    }

    /// @inheritdoc IAssetRegistry
    function disableAsset(address asset) external onlyRole(REGISTRY_ADMIN_ROLE) {
        _requireSupported(asset);
        AssetTypes.AssetConfig storage config = s_assets[asset];
        if (!config.enabled) revert Errors.AssetAlreadyDisabled(asset);
        config.enabled = false;
        emit Events.AssetDisabled(asset);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAssetRegistry
    function getAsset(address asset) external view returns (AssetTypes.AssetConfig memory) {
        _requireRegistered(asset);
        return s_assets[asset];
    }

    /// @inheritdoc IAssetRegistry
    /// @dev "Supported" here means registered AND enabled — this is the
    ///      check the Vault should use before accepting a deposit.
    function isSupported(address asset) external view returns (bool) {
        _requireRegistered(asset);
        return s_assets[asset].asset != address(0) && s_assets[asset].enabled;
    }

    /// @inheritdoc IAssetRegistry
    function totalAssetsSupported() external view returns (uint256) {
        return s_supportedAssets.length;
    }

    /// @inheritdoc IAssetRegistry
    function assetAt(uint256 index) external view returns (address) {
        if (index >= s_supportedAssets.length) {
            revert Errors.IndexOutOfBounds(index);
        }
        return s_supportedAssets[index];
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Reverts if the asset has never been registered.
    function _requireRegistered(address asset) internal view {
        if (s_assets[asset].asset == address(0)) {
            revert Errors.AssetNotRegistered(asset);
        }
    }

    /// @dev Reverts if the asset is not registered.
    ///      (Kept distinct from `_requireRegistered` for clearer error
    ///      naming at each call site — same check, different intent.)
    function _requireSupported(address asset) internal view {
        if (s_assets[asset].asset == address(0)) {
            revert Errors.AssetNotRegistered(asset);
        }
    }

    /// @dev Reverts if the asset is already registered.
    function _requireNotSupported(address asset) internal view {
        if (s_assets[asset].asset != address(0)) {
            revert Errors.AssetAlreadyRegistered(asset);
        }
    }

    /// @dev Sanity-checks that `priceFeed` behaves like a real Chainlink
    ///      aggregator before we ever store it. Catches copy-paste errors
    ///      (wrong network, wrong asset, non-contract address) at
    ///      registration time instead of at deposit time.
    function _validatePriceFeed(address priceFeed) internal view {
        try AggregatorV3Interface(priceFeed).latestRoundData() returns (
            uint80, int256 answer, uint256, uint256 updatedAt, uint80
        ) {
            if (answer <= 0) revert Errors.InvalidPriceFeed(priceFeed);
            if (updatedAt == 0) revert Errors.InvalidPriceFeed(priceFeed);
        } catch {
            revert Errors.InvalidPriceFeed(priceFeed);
        }
    }
}
