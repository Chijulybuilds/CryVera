// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {Errors} from "../libraries/Errors.sol";

/// @notice Base adapter boundary. Implementations integrate one external protocol and never identify users.
abstract contract BaseStrategy is IStrategy, ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public immutable override asset;
    address public immutable manager;
    bool public emergencyMode;

    event StrategyDeposit(uint256 assets);
    event StrategyWithdrawal(address indexed receiver, uint256 assets);
    event StrategyHarvest(uint256 assetsBefore, uint256 assetsAfter);
    event EmergencyExit(address indexed receiver, uint256 assets);

    constructor(address manager_, IERC20 asset_) {
        if (manager_ == address(0) || address(asset_) == address(0)) revert Errors.ZeroAddress();
        manager = manager_;
        asset = asset_;
    }
    modifier onlyManager() {
        if (msg.sender != manager) revert Errors.Unauthorized();
        _;
    }

    function deposit(uint256 assets) external onlyManager nonReentrant returns (uint256 received) {
        if (emergencyMode || assets == 0) revert Errors.StrategyIsPaused();
        uint256 beforeBalance = asset.balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), assets);
        received = asset.balanceOf(address(this)) - beforeBalance;
        if (received != assets) revert Errors.InsufficientReceived(assets, received);
        _deploy(received);
        emit StrategyDeposit(received);
    }

    function withdraw(uint256 assets, address receiver) external onlyManager nonReentrant returns (uint256 withdrawn) {
        if (receiver == address(0) || assets == 0) revert Errors.ZeroAmount();
        _freeFunds(assets);
        uint256 beforeBalance = asset.balanceOf(receiver);
        asset.safeTransfer(receiver, assets);
        withdrawn = asset.balanceOf(receiver) - beforeBalance;
        if (withdrawn != assets) revert Errors.InsufficientReceived(assets, withdrawn);
        emit StrategyWithdrawal(receiver, withdrawn);
    }

    function harvest() external onlyManager nonReentrant returns (uint256 assetsBefore, uint256 assetsAfter) {
        if (emergencyMode) revert Errors.StrategyIsPaused();
        assetsBefore = totalAssets();
        _harvest();
        assetsAfter = totalAssets();
        emit StrategyHarvest(assetsBefore, assetsAfter);
    }

    function emergencyWithdraw(address receiver) external onlyManager nonReentrant returns (uint256 withdrawn) {
        if (receiver == address(0)) revert Errors.ZeroAddress();
        emergencyMode = true;
        _emergencyExit();
        withdrawn = asset.balanceOf(address(this));
        asset.safeTransfer(receiver, withdrawn);
        emit EmergencyExit(receiver, withdrawn);
    }
    function totalAssets() public view virtual returns (uint256);
    function _deploy(uint256 assets) internal virtual;
    function _freeFunds(uint256 assets) internal virtual;
    function _harvest() internal virtual;
    function _emergencyExit() internal virtual;
}
