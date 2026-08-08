// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Errors} from "../libraries/Errors.sol";

/// @title RBT
/// @notice Canonical, transferable receipt for VeriBridge vault shares. It has no valuation or yield logic.
contract RBT is ERC20, ERC20Permit, AccessControl {
    address public vault;

    constructor(address admin) ERC20("Receipt Base Token", "RBT") ERC20Permit("Receipt Base Token") {
        if (admin == address(0)) revert Errors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function setVault(address vault_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (vault_ == address(0)) revert Errors.ZeroAddress();
        if (vault != address(0)) revert Errors.AlreadyConfigured();
        vault = vault_;
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != vault) revert Errors.NotVault();
        _mint(to, amount);
    }

    function burnFrom(address from, uint256 amount) external {
        if (msg.sender != vault) revert Errors.NotVault();
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
    }
}
