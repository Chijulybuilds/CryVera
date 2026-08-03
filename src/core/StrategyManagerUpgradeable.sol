// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    Initializable
} from "lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {Errors} from "../libraries/Errors.sol";

contract StrategyManagerUpgradeable is
    Initializable,
    AccessControl,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    bytes32 public constant STRATEGY_ADMIN_ROLE =
        keccak256("STRATEGY_ADMIN_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    address public vault;
    uint256 private s_nextId;
    address[] private s_strategies;
    mapping(uint256 => address) private s_byId;
    mapping(address => uint256) public strategyId;
    mapping(address => bool) private s_active;
    mapping(address => bool) private s_paused;
    mapping(address => uint256) public depositCap;

    event StrategyRegistered(
        uint256 indexed id,
        address indexed strategy,
        address indexed asset,
        uint256 cap
    );
    event StrategyStatusUpdated(
        address indexed strategy,
        bool active,
        bool paused
    );
    event DepositCapUpdated(address indexed strategy, uint256 cap);

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin) public initializer {
        if (admin == address(0)) revert Errors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(STRATEGY_ADMIN_ROLE, admin);
        _grantRole(GUARDIAN_ROLE, admin);
        s_nextId = 1;
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert Errors.NotVault();
        _;
    }

    function setVault(address vault_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (vault_ == address(0)) revert Errors.ZeroAddress();
        if (vault != address(0)) revert Errors.AlreadyConfigured();
        vault = vault_;
    }

    function registerStrategy(
        address strategy,
        uint256 cap
    ) external onlyRole(STRATEGY_ADMIN_ROLE) returns (uint256 id) {
        if (strategy == address(0)) revert Errors.ZeroAddress();
        if (strategyId[strategy] != 0)
            revert Errors.StrategyAlreadyRegistered();
        if (address(IStrategy(strategy).asset()) == address(0))
            revert Errors.InvalidStrategy();
        id = s_nextId++;
        strategyId[strategy] = id;
        s_byId[id] = strategy;
        s_strategies.push(strategy);
        depositCap[strategy] = cap;
        emit StrategyRegistered(
            id,
            strategy,
            address(IStrategy(strategy).asset()),
            cap
        );
    }

    function setStrategyActive(
        address strategy,
        bool active
    ) external onlyRole(STRATEGY_ADMIN_ROLE) {
        _registered(strategy);
        s_active[strategy] = active;
        emit StrategyStatusUpdated(strategy, active, s_paused[strategy]);
    }

    function setStrategyPaused(address strategy, bool paused) external {
        if (
            !hasRole(STRATEGY_ADMIN_ROLE, msg.sender) &&
            !hasRole(GUARDIAN_ROLE, msg.sender)
        ) {
            revert Errors.Unauthorized();
        }
        _registered(strategy);
        s_paused[strategy] = paused;
        emit StrategyStatusUpdated(strategy, s_active[strategy], paused);
    }

    function setDepositCap(
        address strategy,
        uint256 cap
    ) external onlyRole(STRATEGY_ADMIN_ROLE) {
        _registered(strategy);
        depositCap[strategy] = cap;
        emit DepositCapUpdated(strategy, cap);
    }

    function depositToStrategy(
        address strategy,
        uint256 assets
    ) external onlyVault nonReentrant returns (uint256 received) {
        _enterable(strategy, assets);
        IERC20 token = IStrategy(strategy).asset();
        uint256 beforeManager = token.balanceOf(address(this));
        token.safeTransferFrom(vault, address(this), assets);
        uint256 pulled = token.balanceOf(address(this)) - beforeManager;
        if (pulled != assets)
            revert Errors.InsufficientReceived(assets, pulled);
        token.forceApprove(address(strategy), pulled);
        received = IStrategy(strategy).deposit(pulled);
        token.forceApprove(address(strategy), 0);
        if (received == 0 || received > pulled)
            revert Errors.StrategyDepositFailed();
    }

    function withdrawFromStrategy(
        address strategy,
        uint256 assets,
        address receiver
    ) external onlyVault nonReentrant returns (uint256 withdrawn) {
        _registered(strategy);
        if (receiver == address(0) || assets == 0) revert Errors.ZeroAmount();
        withdrawn = IStrategy(strategy).withdraw(assets, receiver);
        if (withdrawn > assets) revert Errors.StrategyWithdrawalFailed();
    }

    function harvestStrategy(
        address strategy
    )
        external
        onlyVault
        nonReentrant
        returns (uint256 beforeAssets, uint256 afterAssets)
    {
        _registered(strategy);
        if (s_paused[strategy]) revert Errors.StrategyIsPaused();
        return IStrategy(strategy).harvest();
    }

    function emergencyWithdraw(
        address strategy,
        address receiver
    ) external nonReentrant returns (uint256 withdrawn) {
        if (
            !hasRole(GUARDIAN_ROLE, msg.sender) &&
            !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)
        ) {
            revert Errors.Unauthorized();
        }
        _registered(strategy);
        s_active[strategy] = false;
        s_paused[strategy] = true;
        withdrawn = IStrategy(strategy).emergencyWithdraw(receiver);
        emit StrategyStatusUpdated(strategy, false, true);
    }

    function getStrategyAddress(
        uint256 id
    ) external view returns (address strategy) {
        strategy = s_byId[id];
        if (strategy == address(0)) revert Errors.StrategyNotRegistered();
    }

    function strategyCount() external view returns (uint256) {
        return s_strategies.length;
    }

    function strategyAt(uint256 index) external view returns (address) {
        return s_strategies[index];
    }

    function strategyAsset(address strategy) external view returns (address) {
        _registered(strategy);
        return address(IStrategy(strategy).asset());
    }

    function isActive(address strategy) external view returns (bool) {
        return s_active[strategy] && !s_paused[strategy];
    }

    function _registered(address strategy) private view {
        if (strategyId[strategy] == 0) revert Errors.StrategyNotRegistered();
    }

    function _enterable(address strategy, uint256 assets) private view {
        _registered(strategy);
        if (!s_active[strategy] || s_paused[strategy])
            revert Errors.StrategyNotActive(strategy);
        uint256 cap = depositCap[strategy];
        if (cap != 0 && IStrategy(strategy).totalAssets() + assets > cap) {
            revert Errors.DepositCapExceeded(
                IStrategy(strategy).totalAssets() + assets,
                cap
            );
        }
    }
}
