// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAssetRegistry} from "../interfaces/IAssetRegistry.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IRBT} from "../interfaces/IRBT.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IStrategyManager} from "../interfaces/IStrategyManager.sol";
import {IPositionManager} from "../interfaces/IPositionManager.sol";
import {AssetTypes} from "../types/Asset.sol";
import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title VeriBridgeVault
/// @notice Ethereum's canonical settlement and sole share-accounting contract.
/// @dev RBT supply equals vault shares. Strategy values are read live; the router never mirrors them.
contract VeriBridgeVault is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// ============================================================================
    /// CONSTANTS
    /// ============================================================================
    uint256 public constant VIRTUAL_ASSETS = 1e18;
    uint256 public constant VIRTUAL_SHARES = 1e18;
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    /// ============================================================================
    /// IMMUTABLES (Stored in Bytecode - Occupy No Storage Slots)
    /// ============================================================================
    IAssetRegistry public immutable assetRegistry;
    IOracle public immutable oracle;
    IRBT public immutable rbt;
    IStrategyManager public immutable strategyManager;

    /// ============================================================================
    /// STORAGE LAYOUT ANNOTATIONS (SLOTS 0 - 2)
    /// ============================================================================
    /// @dev Slot 0: Optional position manager for user tracking on the vault.
    IPositionManager public positionManager;

    /// @dev Slot 1: Global deposit pause sentinel state.
    bool public depositsPaused;

    /// @dev Slot 2: Accounted custody only; unsolicited token donations are excluded.
    mapping(address => uint256) private s_idleAssets;

    /**
     * @param admin address that controls the Vault system
     * @param guardian address only involved in pausing of vault systems and actions
     * @param registry address of AseetRegistry showing supported assets as of deployment
     * @param oracle_ address of the oracle contract
     * @param rbt_ address of the RBT token contract
     * @param strategymanager address of the strategy manager contract
     */
    constructor(
        address admin,
        address guardian,
        address registry,
        address oracle_,
        address rbt_,
        address strategymanager
    ) {
        if (
            admin == address(0) || guardian == address(0) || registry == address(0) || oracle_ == address(0)
                || rbt_ == address(0) || strategymanager == address(0)
        ) revert Errors.ZeroAddress();
        assetRegistry = IAssetRegistry(registry);
        oracle = IOracle(oracle_);
        rbt = IRBT(rbt_);
        strategyManager = IStrategyManager(strategymanager);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GUARDIAN_ROLE, guardian);
    }

    modifier whenDepositsOpen() {
        if (depositsPaused || paused()) revert Errors.DepositPaused();
        _;
    }

    function deposit(address asset, uint256 assets, address receiver)
        external
        nonReentrant
        whenDepositsOpen
        returns (uint256 shares)
    {
        if (assets == 0 || receiver == address(0)) revert Errors.ZeroAmount();
        if (!assetRegistry.isSupported(asset)) {
            revert Errors.AssetNotSupported(asset);
        }
        uint256 assetsBefore = totalAssets();
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        IERC20(asset).safeTransferFrom(msg.sender, address(this), assets);
        uint256 AmountOfAssetreceived = IERC20(asset).balanceOf(address(this)) - balanceBefore;
        if (AmountOfAssetreceived != assets) {
            revert Errors.InsufficientReceived(assets, AmountOfAssetreceived);
        }
        uint256 value = _value(asset, AmountOfAssetreceived);
        shares = Math.mulDiv(value, totalShares() + VIRTUAL_SHARES, assetsBefore + VIRTUAL_ASSETS);
        if (shares == 0) revert Errors.ZeroAmount();
        s_idleAssets[asset] += AmountOfAssetreceived;
        rbt.mint(receiver, shares);

        emit Events.Deposited(msg.sender, receiver, asset, AmountOfAssetreceived, shares);
    }

    /// @notice Deposits collateral, mints RBT, records the user's strategy position,
    /// and immediately allocates the deposited collateral to the selected strategy.
    ///
    /// @dev The strategy must accept the exact deposited asset.
    /// The Vault remains the sole authority for share/RBT accounting.
    /// PositionManager only records ownership/strategy metadata.
    function depositAndAllocate(address asset, uint256 assets, address receiver, uint256 strategyId)
        external
        nonReentrant
        whenDepositsOpen
        returns (uint256 shares)
    {
        if (assets == 0 || receiver == address(0)) {
            revert Errors.ZeroAmount();
        }
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
        uint256 AmountOfAssetreceived = IERC20(asset).balanceOf(address(this)) - balanceBefore;
        if (AmountOfAssetreceived != assets) {
            revert Errors.InsufficientReceived(assets, AmountOfAssetreceived);
        }
        uint256 value = _value(asset, AmountOfAssetreceived);
        shares = Math.mulDiv(value, totalShares() + VIRTUAL_SHARES, assetsBefore + VIRTUAL_ASSETS);
        if (shares == 0) {
            revert Errors.ZeroAmount();
        }
        s_idleAssets[asset] += AmountOfAssetreceived;
        rbt.mint(receiver, shares);

        if (address(positionManager) != address(0)) {
            positionManager.recordDeposit(receiver, strategyId, shares);
        }

        s_idleAssets[asset] -= AmountOfAssetreceived;

        IERC20(asset).forceApprove(address(strategyManager), AmountOfAssetreceived);

        uint256 allocated = strategyManager.depositToStrategy(strategy, AmountOfAssetreceived);

        // Clear approval immediately after use.
        IERC20(asset).forceApprove(address(strategyManager), 0);

        if (allocated != AmountOfAssetreceived) {
            revert Errors.StrategyDepositFailed();
        }

        emit Events.Deposited(msg.sender, receiver, asset, AmountOfAssetreceived, shares);

        emit Events.Allocated(strategyId, strategy, allocated);
    }

    /// @notice Invests already-accounted vault custody. No user balance is ever held in the router or a strategy.
    function allocate(uint256 strategyId, uint256 assets)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
        whenNotPaused
    {
        address strategy = strategyManager.getStrategyAddress(strategyId);
        address asset = strategyManager.strategyAsset(strategy);
        if (!strategyManager.isActive(strategy)) {
            revert Errors.StrategyNotActive(strategy);
        }
        if (assets == 0 || assets > s_idleAssets[asset]) {
            revert Errors.InsufficientAssets();
        }

        /// s_idleAssets signifies the amount of assets siiting in the vault
        s_idleAssets[asset] -= assets;
        IERC20(asset).forceApprove(address(strategyManager), assets);
        uint256 AmountOfAssetsreceived = strategyManager.depositToStrategy(strategy, assets);
        IERC20(asset).forceApprove(address(strategyManager), 0);
        if (AmountOfAssetsreceived != assets) revert Errors.StrategyDepositFailed();
        emit Events.Allocated(strategyId, strategy, assets);
    }

    /// @notice Burns receipts and pays an exact chosen collateral amount; liquidity is pulled from matching strategies as needed.

    /**
     * @param asset Address of ERC20 to be retrieved
     * @param shares the amount of backed RBT of shares to be reddemed
     * @param receiver the address to receive the redeemed assets
     */
    function redeem(address asset, uint256 shares, address receiver)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        if (shares == 0 || receiver == address(0)) revert Errors.ZeroAmount();
        if (rbt.balanceOf(msg.sender) < shares) {
            revert Errors.InsufficientShares();
        }
        uint256 assetsBefore = totalAssets();
        uint256 value = Math.mulDiv(shares, assetsBefore + VIRTUAL_ASSETS, totalShares() + VIRTUAL_SHARES);
        assets = Math.mulDiv(value, 10 ** assetRegistry.getAsset(asset).decimals, oracle.getPrice(asset));
        if (assets == 0) revert Errors.ZeroAmount();
        _ensureLiquidity(asset, assets);
        // Effects before transfer; burn is allowance-gated and cannot be reached by bridge locks.
        rbt.burnFrom(msg.sender, shares);
        s_idleAssets[asset] -= assets;
        IERC20(asset).safeTransfer(receiver, assets);
        if (address(positionManager) != address(0)) {
            positionManager.recordRedemption(msg.sender, shares);
        }
        emit Events.Redeemed(msg.sender, receiver, asset, shares, assets);
    }

    /**
     * @param strategyId ID of the strategy to harvest
     */
    function harvest(uint256 strategyId) external nonReentrant whenNotPaused {
        address strategy = strategyManager.getStrategyAddress(strategyId);
        (uint256 beforeAssets, uint256 afterAssets) = strategyManager.harvestStrategy(strategy);
        emit Events.Harvested(strategy, beforeAssets, afterAssets);
    }

    /**
     * @notice Rescues accidentally sent non-collateral ERC-20 tokens.
     * @dev Strictly reverts if attempting to rescue supported vault collateral or RBT share receipts.
     * @param token Address of the stuck token to recover.
     * @param recipient Destination address for recovered tokens.
     * @param amount Token amount to transfer.
     */
    function rescueERC20(address token, address recipient, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        if (token == address(0) || recipient == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (amount == 0) revert Errors.ZeroAmount();

        // Invariant protection: cannot rescue RBT share receipts
        if (token == address(rbt)) revert Errors.Unauthorized();

        // Invariant protection: cannot rescue any active vault collateral asset
        if (assetRegistry.isSupported(token)) revert Errors.Unauthorized();

        IERC20(token).safeTransfer(recipient, amount);
        emit Events.TokenRescued(token, recipient, amount);
    }

    function setPositionManager(address strategymanager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (strategymanager == address(0)) revert Errors.ZeroAddress();
        positionManager = IPositionManager(strategymanager);
    }

    function pauseDeposits() external onlyRole(GUARDIAN_ROLE) {
        depositsPaused = true;
        emit Events.DepositsPaused(true);
    }

    function unpauseDeposits() external onlyRole(DEFAULT_ADMIN_ROLE) {
        depositsPaused = false;
        emit Events.DepositsPaused(false);
    }

    function pauseProtocol() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    function unpauseProtocol() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function totalShares() public view returns (uint256) {
        return rbt.totalSupply();
    }

    function totalAssets() public view returns (uint256 value) {
        // assetCount gives the total AssetSupported
        uint256 assetCount = assetRegistry.totalAssetsSupported();

        for (uint256 i; i < assetCount; ++i) {
            address asset = assetRegistry.assetAt(i);
            // gives an estimation of the current oracle price of an asset
            value += _value(asset, s_idleAssets[asset]);
        }
        uint256 count = strategyManager.strategyCount();
        for (uint256 i; i < count; ++i) {
            address strategy = strategyManager.strategyAt(i);
            value += _value(strategyManager.strategyAsset(strategy), IStrategy(strategy).totalAssets());
        }
    }

    function exchangeRate() external view returns (uint256) {
        /// share exchange rate = assets / shares
        return Math.mulDiv(totalAssets() + VIRTUAL_ASSETS, 1e18, totalShares() + VIRTUAL_SHARES);
    }

    function accountedIdle(address asset) external view returns (uint256) {
        return s_idleAssets[asset];
    }

    function previewDeposit(address asset, uint256 assets) external view returns (uint256) {
        /// preview the number of shares that will be received for a given amount of assets
        return Math.mulDiv(_value(asset, assets), totalShares() + VIRTUAL_SHARES, totalAssets() + VIRTUAL_ASSETS);
    }

    /**
     * @notice Returns the amount of assets that would be redeemed for a given number of shares.
     * @param asset Address of the asset to check.
     * @param shares Number of shares to redeem.
     * @return Amount of assets that would be received.
     */
    function previewRedeem(address asset, uint256 shares) external view returns (uint256) {
        // first converts shares to asset value
        uint256 value = Math.mulDiv(shares, totalAssets() + VIRTUAL_ASSETS, totalShares() + VIRTUAL_SHARES);
        // this returns the current oracle price of asset value
        return Math.mulDiv(value, 10 ** assetRegistry.getAsset(asset).decimals, oracle.getPrice(asset));
    }

    /**
     * @notice Ensures that the vault has sufficient liquidity for a given asset and amount.
     * @param asset Address of the asset to check.
     * @param needed Amount of the asset needed.
     */
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
