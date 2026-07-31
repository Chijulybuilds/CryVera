// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            VERIBRIDGE ERRORS
//////////////////////////////////////////////////////////////*/

/// @title VeriBridge Custom Errors
/// @author Prince_Chinedu(VeriBridge)
/// @notice Shared custom errors used throughout the protocol.
/// @dev Centralizing errors improves consistency and reduces deployment gas.

library Errors {
    /*//////////////////////////////////////////////////////////////
                            ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/
    error Unauthorized();
    error ZeroAddress();
    /*//////////////////////////////////////////////////////////////
                              VAULT
    //////////////////////////////////////////////////////////////*/

    error ZeroAmount();
    error DepositPaused();
    error VaultPaused();
    error InsufficientLiquidity();
    error AssetNotSupported(address asset);
    error WithdrawalPaused();
    error InsufficientShares();
    error InsufficientAssets();
    error UnsupportedAsset();

    /*//////////////////////////////////////////////////////////////
                            STRATEGIES
    //////////////////////////////////////////////////////////////*/

    error StrategyAlreadyExists();
    error StrategyNotFound();
    error AssetStrategyMismatch(address asset, address strategy);
    error PositionStrategyMismatch(uint256 position, uint256 id);
    error InvalidStrategy();
    error StrategyDepositFailed();
    error StrategyWithdrawalFailed();
    error InvalidAddress();
    error StrategyAlreadyRegistered();
    error StrategyNotRegistered();
    error StrategyInactive();
    error StrategyIsPaused();
    error DepositCapExceeded(uint256 requestedTotal, uint256 cap);

    /*//////////////////////////////////////////////////////////////
                          ASSET REGISTRY
    //////////////////////////////////////////////////////////////*/
    error InvalidAsset();
    error InvalidDecimals(uint8 decimals);
    error AssetAlreadyRegistered(address asset);
    error AssetNotRegistered(address asset);
    error AssetAlreadyEnabled(address asset);
    error AssetAlreadyDisabled(address asset);
    error InvalidPriceFeed(address priceFeed);
    error IndexOutOfBounds(uint256 index);
    /*//////////////////////////////////////////////////////////////
                              ORACLE
    //////////////////////////////////////////////////////////////*/
    error SequencerDown();
    error InvalidPrice(address asset, int256 price);
    error StalePrice(address asset, uint256 updatedAt, uint256 threshold);
    error PriceOutOfBounds(address asset, uint256 price, uint256 minPrice, uint256 maxPrice);
    error InvalidPriceBounds(uint256 minPrice, uint256 maxPrice);

    /*//////////////////////////////////////////////////////////////
                               TOKEN
    //////////////////////////////////////////////////////////////*/

    error MintFailed();
    error BurnFailed();

    /*//////////////////////////////////////////////////////////////
                              SHARES
    //////////////////////////////////////////////////////////////*/

    error InvalidShareAmount();
    error ShareCalculationFailed();

    /*//////////////////////////////////////////////////////////////
                               BRIDGE
    //////////////////////////////////////////////////////////////*/

    error UnsupportedChain();
    error CCIPSendFailed();
    error InvalidMessage();
    error NotVault();
    error NotBridge();
    error AlreadyConfigured();
    error InvalidFee();
    error UnauthorizedSender(uint64 sourceChainSelector, address sender);
    error MessageAlreadyProcessed(bytes32 messageId);
    error UnsupportedBridgeAction(uint8 action);
    error InsufficientReceived(uint256 expected, uint256 received);
    error StrategyNotActive(address strategy);
    error StrategyAssetMismatch(address strategy, address asset);
    error NoLiquidity();
}
