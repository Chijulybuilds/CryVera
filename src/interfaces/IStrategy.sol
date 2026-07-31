// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                         EXTERNAL IMPORTS
//////////////////////////////////////////////////////////////*/

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/*//////////////////////////////////////////////////////////////
                          INTERNAL IMPORTS
//////////////////////////////////////////////////////////////*/

/*//////////////////////////////////////////////////////////////
                           INTERFACE
//////////////////////////////////////////////////////////////*/

/// @title IStrategy
/// @author VeriBridge
/// @notice Standard interface implemented by every yield strategy supported
///         by the VeriBridge protocol.
/// @dev
/// A strategy is responsible only for managing capital deposited by the
/// StrategyManager. Every implementation (Aave, Morpho, Lido, etc.)
/// must expose the same public API, allowing the StrategyManager to
/// interact with strategies without protocol-specific logic.
interface IStrategy {
    function asset() external view returns (IERC20);
    function totalAssets() external view returns (uint256);
    function deposit(uint256 assets) external returns (uint256 received);
    function withdraw(uint256 assets, address receiver) external returns (uint256 withdrawn);
    function harvest() external returns (uint256 assetsBefore, uint256 assetsAfter);
    function emergencyWithdraw(address receiver) external returns (uint256 withdrawn);
}
