// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                         INTERNAL IMPORTS
//////////////////////////////////////////////////////////////*/

import {VaultTypes} from "../types/VaultTypes.sol";

/*//////////////////////////////////////////////////////////////
                           INTERFACE
//////////////////////////////////////////////////////////////*/

/// @title IVault
/// @author VeriBridge
/// @notice Canonical Ethereum vault interface.
/// @dev
/// The vault is responsible for custody, accounting, and share
/// issuance. It delegates yield generation to approved strategies
/// through the StrategyManager.
interface IVault {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposited(
        address indexed caller, address indexed receiver, address indexed asset, uint256 assets, uint256 shares
    );

    event Withdrawn(
        address indexed caller, address indexed receiver, address indexed asset, uint256 assets, uint256 shares
    );

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns total protocol assets.
    function totalAssets() external view returns (uint256);

    /// @notice Returns total issued shares.
    function totalShares() external view returns (uint256);

    /// @notice Returns the current exchange rate.
    function exchangeRate() external view returns (uint256);

    /// @notice Returns a user's vault position.
    function positionOf(address account) external view returns (VaultTypes.VaultPosition memory);

    /// @notice Converts assets into shares.
    function previewDeposit(uint256 assets) external view returns (uint256 shares);

    /// @notice Converts shares into assets.
    function previewRedeem(uint256 shares) external view returns (uint256 assets);

    /*//////////////////////////////////////////////////////////////
                          USER OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function deposit(VaultTypes.DepositParams calldata params) external returns (uint256 shares);

    function redeem(VaultTypes.RedeemParams calldata params) external returns (uint256 assets);
}
