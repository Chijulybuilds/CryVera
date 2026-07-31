// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IPositionManager} from "../interfaces/IPositionManager.sol";
import {Errors} from "../libraries/Errors.sol";

/// @notice Non-authoritative allocation and history metadata. Receipt ownership is exclusively RBT/vault state.
contract PositionManager is AccessControl, IPositionManager {
    struct PositionMetadata {
        uint256 cumulativeDepositedShares;
        uint256 cumulativeRedeemedShares;
        uint256 lastStrategyId;
        uint64 updatedAt;
    }
    address public immutable vault;
    mapping(address => PositionMetadata) private s_positions;
    mapping(address => mapping(uint256 => uint16)) public allocationBps;
    event PositionRecorded(address indexed account, uint256 indexed strategyId, uint256 shares, bool redemption);
    event AllocationRecorded(address indexed account, uint256 indexed strategyId, uint16 bps);

    constructor(address admin, address vault_) {
        if (admin == address(0) || vault_ == address(0)) revert Errors.ZeroAddress();
        vault = vault_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }
    modifier onlyVault() {
        if (msg.sender != vault) revert Errors.NotVault();
        _;
    }

    function recordDeposit(address account, uint256 strategyId, uint256 shares) external onlyVault {
        PositionMetadata storage p = s_positions[account];
        p.cumulativeDepositedShares += shares;
        p.lastStrategyId = strategyId;
        p.updatedAt = uint64(block.timestamp);
        emit PositionRecorded(account, strategyId, shares, false);
    }

    function recordRedemption(address account, uint256 shares) external onlyVault {
        PositionMetadata storage p = s_positions[account];
        p.cumulativeRedeemedShares += shares;
        p.updatedAt = uint64(block.timestamp);
        emit PositionRecorded(account, p.lastStrategyId, shares, true);
    }

    function recordAllocation(address account, uint256 strategyId, uint16 bps) external onlyVault {
        if (bps > 10_000) revert Errors.InvalidShareAmount();
        allocationBps[account][strategyId] = bps;
        emit AllocationRecorded(account, strategyId, bps);
    }

    function positionOf(address account) external view returns (PositionMetadata memory) {
        return s_positions[account];
    }
}
