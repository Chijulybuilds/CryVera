// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            VERIBRIDGE EVENTS
//////////////////////////////////////////////////////////////*/

/// @title VeriBridge Events
/// @author VeriBridge
/// @notice Shared protocol events inherited by protocol contracts.
abstract contract Events {
    /*//////////////////////////////////////////////////////////////
                              VAULT
    //////////////////////////////////////////////////////////////*/

    event Deposited(
        address indexed user, address indexed receiver, address indexed asset, uint256 assets, uint256 shares
    );
    event Withdrawn(
        address indexed user, address indexed receiver, address indexed asset, uint256 assets, uint256 shares
    );
    event VaultPaused(address indexed caller);
    event VaultUnpaused(address indexed caller);
    event AssetRegistryUpdated(address indexed registry);
    event OracleUpdated(address indexed oracle);
    event StrategyManagerUpdated(address indexed strategyManager);
    event PartialRedemption(address indexed account, uint256 requestedShares, uint256 burnedShares);

    /*//////////////////////////////////////////////////////////////
                           ASSET REGISTRY
    //////////////////////////////////////////////////////////////*/

    event AssetRegistered(address indexed asset, address indexed priceFeed, uint8 decimal);
    event AssetDisabled(address indexed asset);
    event AssetEnabled(address indexed asset);

    /*//////////////////////////////////////////////////////////////
                           STRATEGIES
    //////////////////////////////////////////////////////////////*/
    event StrategyDeposited(address indexed caller, uint256 assets);
    event StrategyWithdrawn(address indexed caller, uint256 assets);
    event YieldHarvested(uint256 previousAssets, uint256 currentAssets);

    event VaultUpdated(address indexed oldVault, address indexed newVault);
    event StrategyRegistered(
        uint256 indexed strategyId, address indexed strategy, address indexed asset, string version
    );
    event StrategyActivated(address indexed strategy);
    event StrategyDeactivated(address indexed strategy);
    event StrategyPaused(address indexed strategy);
    event StrategyUnpaused(address indexed strategy);
    event StrategyDepositCapUpdated(address indexed strategy, uint256 newCap);

    event DepositedToStrategy(
        address indexed strategy, uint256 assetsRequested, uint256 actualDeposited, uint256 sharesMinted
    );
    event WithdrawnFromStrategy(
        address indexed strategy, uint256 assetsRequested, uint256 actualWithdrawn, uint256 sharesBurned
    );
    event StrategyHarvested(address indexed strategy, uint256 yieldHarvested, uint256 pendingYieldRemaining);
    event EmergencyWithdrawTriggered(address indexed strategy, address indexed trigger);

    /*//////////////////////////////////////////////////////////////
                              TOKEN
    //////////////////////////////////////////////////////////////*/

    event SharesMinted(address indexed receiver, uint256 amount);

    event SharesBurned(address indexed owner, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                              BRIDGE
    //////////////////////////////////////////////////////////////*/

    event OwnershipBridged(
        bytes32 indexed messageId, uint64 indexed destinationChainSelector, address indexed receiver, uint256 shares
    );

    /*//////////////////////////////////////////////////////////////
                              ORACLE
    //////////////////////////////////////////////////////////////*/

    event PriceFeedUpdated(address indexed asset, address indexed feed);
    event StalenessThresholdUpdated(address indexed asset, uint256 threshold);
    event PriceBoundsUpdated(address indexed asset, uint256 minPrice, uint256 maxPrice);
    event PriceBoundsCleared(address indexed asset);
}
