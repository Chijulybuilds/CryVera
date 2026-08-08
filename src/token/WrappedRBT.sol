// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Errors} from "../libraries/Errors.sol";

/// @notice Non-redeemable cross-chain representation of canonical RBT.
contract WrappedRBT is ERC20, ERC20Permit, AccessControl {
    address public mintBridge;
    address public burnBridge;

    constructor(address admin, string memory name_, string memory symbol_)
        ERC20("Wrapped Receipt Base Token", "wRBT")
        ERC20Permit("Wrapped Receipt Base Token")
    {
        if (admin == address(0)) revert Errors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Configures the destination receiver that mints and the local sender that burns.
    ///         Both are immutable after setup, preventing bridge-role escalation.
    function setBridges(address mintBridge_, address burnBridge_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (mintBridge_ == address(0) || burnBridge_ == address(0)) revert Errors.ZeroAddress();
        if (mintBridge != address(0) || burnBridge != address(0)) revert Errors.AlreadyConfigured();
        mintBridge = mintBridge_;
        burnBridge = burnBridge_;
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != mintBridge) revert Errors.NotBridge();
        _mint(to, amount);
    }

    function burnFrom(address from, uint256 amount) external {
        if (msg.sender != burnBridge) revert Errors.NotBridge();
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
    }
}
