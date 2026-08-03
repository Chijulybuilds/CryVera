// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAssetRegistry} from "../interfaces/IAssetRegistry.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IRBT} from "../interfaces/IRBT.sol";
import {IStrategyManager} from "../interfaces/IStrategyManager.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IPositionManager} from "../interfaces/IPositionManager.sol";
import {AssetTypes} from "../types/Asset.sol";
import {Errors} from "../libraries/Errors.sol";

/// @title VeriBridgeVaultUpgradeable
/// @notice Upgradeable variant of the canonical Vault. Use with a TransparentUpgradeableProxy.
contract VeriBridgeVaultUpgradeable is Initializable, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    uint256 public constant VIRTUAL_ASSETS = 1e18;
    uint256 public constant VIRTUAL_SHARES = 1e18;
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    IAssetRegistry public assetRegistry;
    IOracle public oracle;
    IRBT public rbt;
    IStrategyManager public strategyManager;
    IPositionManager public positionManager;
    bool public depositsPaused;
    mapping(address => uint256) private s_idleAssets;

    event Deposited(
        address indexed payer, address indexed receiver, address indexed asset, uint256 assets, uint256 shares
    );
    event Redeemed(
        address indexed owner, address indexed receiver, address indexed asset, uint256 shares, uint256 assets
    );
    event Allocated(uint256 indexed strategyId, address indexed strategy, uint256 assets);
    event Harvested(address indexed strategy, uint256 assetsBefore, uint256 assetsAfter);
    event DepositsPaused(bool paused);

    /// @dev Prevent implementation from being initialized directly
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin,
        address guardian,
        address registry,
        address oracle_,
        address rbt_,
        address manager
    ) public initializer {
        if (
            admin == address(0) || guardian == address(0) || registry == address(0) || oracle_ == address(0)
                || rbt_ == address(0) || manager == address(0)
        ) revert Errors.ZeroAddress();
        assetRegistry = IAssetRegistry(registry);
        oracle = IOracle(oracle_);
        rbt = IRBT(rbt_);
        strategyManager = IStrategyManager(manager);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GUARDIAN_ROLE, guardian);
    }

    modifier whenDepositsOpen() {
        if (depositsPaused) revert Errors.DepositPaused();
        _;
    }

    function deposit(address asset, uint256 assets, address receiver, uint256 strategyId)
        external
        nonReentrant
        whenDepositsOpen
        returns (uint256 shares)
    {
        if (assets == 0 || receiver == address(0)) revert Errors.ZeroAmount();
        if (!assetRegistry.isSupported(asset)) {
            revert Errors.AssetNotSupported(asset);
        }
        address strategy = strategyManager.getStrategyAddress(strategyId);
        if (!strategyManager.isActive(strategy)) {
            revert Errors.StrategyNotActive(strategy);
        }
        if (strategyManager.strategyAsset(strategy) != asset) {
            revert Errors.StrategyAssetMismatch(strategy, asset);
        }
        uint256 assetsBefore = totalAssets();
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        IERC20(asset).safeTransferFrom(msg.sender, address(this), assets);
        uint256 received = IERC20(asset).balanceOf(address(this)) - balanceBefore;
        if (received != assets) {
            revert Errors.InsufficientReceived(assets, received);
        }
        uint256 value = _value(asset, received);
        shares = Math.mulDiv(value, totalShares() + VIRTUAL_SHARES, assetsBefore + VIRTUAL_ASSETS);
        if (shares == 0) revert Errors.ZeroAmount();
        s_idleAssets[asset] += received;
        rbt.mint(receiver, shares);
        if (address(positionManager) != address(0)) {
            positionManager.recordDeposit(receiver, strategyId, shares);
        }
        emit Deposited(msg.sender, receiver, asset, received, shares);
    }

    function allocate(uint256 strategyId, uint256 assets) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        address strategy = strategyManager.getStrategyAddress(strategyId);
        address asset = strategyManager.strategyAsset(strategy);
        if (!strategyManager.isActive(strategy)) {
            revert Errors.StrategyNotActive(strategy);
        }
        if (assets == 0 || assets > s_idleAssets[asset]) {
            revert Errors.InsufficientAssets();
        }
        s_idleAssets[asset] -= assets;
        IERC20(asset).forceApprove(address(strategyManager), assets);
        uint256 received = strategyManager.depositToStrategy(strategy, assets);
        IERC20(asset).forceApprove(address(strategyManager), 0);
        if (received != assets) revert Errors.StrategyDepositFailed();
        emit Allocated(strategyId, strategy, assets);
    }

    function redeem(address asset, uint256 shares, address receiver) external nonReentrant returns (uint256 assets) {
        if (shares == 0 || receiver == address(0)) revert Errors.ZeroAmount();
        if (rbt.balanceOf(msg.sender) < shares) {
            revert Errors.InsufficientShares();
        }
        uint256 assetsBefore = totalAssets();
        uint256 value = Math.mulDiv(shares, assetsBefore + VIRTUAL_ASSETS, totalShares() + VIRTUAL_SHARES);
        assets = Math.mulDiv(value, 10 ** assetRegistry.getAsset(asset).decimals, oracle.getPrice(asset));
        if (assets == 0) revert Errors.ZeroAmount();
        _ensureLiquidity(asset, assets);
        rbt.burnFrom(msg.sender, shares);
        s_idleAssets[asset] -= assets;
        IERC20(asset).safeTransfer(receiver, assets);
        if (address(positionManager) != address(0)) {
            positionManager.recordRedemption(msg.sender, shares);
        }
        emit Redeemed(msg.sender, receiver, asset, shares, assets);
    }

    function harvest(uint256 strategyId) external nonReentrant {
        address strategy = strategyManager.getStrategyAddress(strategyId);
        (uint256 beforeAssets, uint256 afterAssets) = strategyManager.harvestStrategy(strategy);
        emit Harvested(strategy, beforeAssets, afterAssets);
    }

    function setPositionManager(address manager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (manager == address(0)) revert Errors.ZeroAddress();
        positionManager = IPositionManager(manager);
    }

    function pauseDeposits() external onlyRole(GUARDIAN_ROLE) {
        depositsPaused = true;
        emit DepositsPaused(true);
    }

    function unpauseDeposits() external onlyRole(DEFAULT_ADMIN_ROLE) {
        depositsPaused = false;
        emit DepositsPaused(false);
    }

    function totalShares() public view returns (uint256) {
        return rbt.totalSupply();
    }

    function totalAssets() public view returns (uint256 value) {
        uint256 assetCount = assetRegistry.totalAssetsSupported();

        for (uint256 i; i < assetCount; ++i) {
            address asset = assetRegistry.assetAt(i);
            value += _value(asset, s_idleAssets[asset]);
        }

        uint256 count = strategyManager.strategyCount();

        for (uint256 i; i < count; ++i) {
            address strategy = strategyManager.strategyAt(i);

            value += _value(strategyManager.strategyAsset(strategy), IStrategy(strategy).totalAssets());
        }
    }

    function exchangeRate() external view returns (uint256) {
        return Math.mulDiv(totalAssets() + VIRTUAL_ASSETS, 1e18, totalShares() + VIRTUAL_SHARES);
    }

    function accountedIdle(address asset) external view returns (uint256) {
        return s_idleAssets[asset];
    }

    function previewDeposit(address asset, uint256 assets) external view returns (uint256) {
        return Math.mulDiv(_value(asset, assets), totalShares() + VIRTUAL_SHARES, totalAssets() + VIRTUAL_ASSETS);
    }

    function previewRedeem(address asset, uint256 shares) external view returns (uint256) {
        uint256 value = Math.mulDiv(shares, totalAssets() + VIRTUAL_ASSETS, totalShares() + VIRTUAL_SHARES);
        return Math.mulDiv(value, 10 ** assetRegistry.getAsset(asset).decimals, oracle.getPrice(asset));
    }

    function _ensureLiquidity(address asset, uint256 needed) private {
        uint256 idle = s_idleAssets[asset];
        if (idle >= needed) return;
        uint256 remaining = needed - idle;
        uint256 count = strategyManager.strategyCount();
        for (uint256 i; i < count && remaining != 0; ++i) {
            address strategy = strategyManager.strategyAt(i);
            if (strategyManager.strategyAsset(strategy) != asset) continue;
            uint256 request = IStrategy(strategy).totalAssets();
            if (request > remaining) request = remaining;
            if (request == 0) continue;
            uint256 got = strategyManager.withdrawFromStrategy(strategy, request, address(this));
            s_idleAssets[asset] += got;
            remaining -= got;
        }
        if (s_idleAssets[asset] < needed) revert Errors.NoLiquidity();
    }

    function _value(address asset, uint256 amount) private view returns (uint256) {
        if (amount == 0) return 0;
        AssetTypes.AssetConfig memory config = assetRegistry.getAsset(asset);
        return Math.mulDiv(amount, oracle.getPrice(asset), 10 ** config.decimals);
    }
}
