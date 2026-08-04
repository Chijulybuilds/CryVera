// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VeriBridgeVault} from "../src/core/VeriBridgeVault.sol";
import {StrategyManager} from "../src/core/StrategyManager.sol";
import {RBT} from "../src/token/RBT.sol";
import {IAssetRegistry} from "../src/interfaces/IAssetRegistry.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";
import {IStrategy} from "../src/interfaces/IStrategy.sol";
import {AssetTypes} from "../src/types/Asset.sol";

contract MockToken is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockRegistry is IAssetRegistry {
    address public asset;

    constructor(address asset_) {
        asset = asset_;
    }
    function registerAsset(address, address, uint8) external {}
    function enableAsset(address) external {}
    function disableAsset(address) external {}

    function getAsset(address a) external view returns (AssetTypes.AssetConfig memory) {
        require(a == asset);
        return AssetTypes.AssetConfig(a, address(1), 6, true);
    }

    function isSupported(address a) external view returns (bool) {
        return a == asset;
    }

    function totalAssetsSupported() external pure returns (uint256) {
        return 1;
    }

    function assetAt(uint256) external view returns (address) {
        return asset;
    }
}

contract MockOracle is IOracle {
    function getPrice(address) external pure returns (uint256) {
        return 1e18;
    }

    function hasPriceFeed(address) external pure returns (bool) {
        return true;
    }

    function getPriceFeed(address) external pure returns (address) {
        return address(1);
    }

    function isPriceValid(address) external pure returns (bool) {
        return true;
    }

    function getStalenessThreshold(address) external pure returns (uint256) {
        return 1;
    }

    function getPriceBounds(address) external pure returns (uint256, uint256) {
        return (0, 0);
    }
    function setStalenessThreshold(address, uint256) external {}
    function setPriceBounds(address, uint256, uint256) external {}
    function clearPriceBounds(address) external {}
    function setSequencerFeed(address) external {}
    function setSequencerGracePeriod(uint256) external {}
    function syncPriceFeed(address) external {}
}

contract MockStrategy is IStrategy {
    IERC20 public immutable override asset;
    address public immutable manager;
    uint256 public managed;

    constructor(address manager_, IERC20 asset_) {
        manager = manager_;
        asset = asset_;
    }
    modifier onlyManager() {
        require(msg.sender == manager);
        _;
    }

    function totalAssets() external view returns (uint256) {
        return managed;
    }

    function deposit(uint256 assets) external onlyManager returns (uint256) {
        asset.transferFrom(msg.sender, address(this), assets);
        managed += assets;
        return assets;
    }

    function withdraw(uint256 assets, address receiver) external onlyManager returns (uint256) {
        if (assets > managed) assets = managed;
        managed -= assets;
        asset.transfer(receiver, assets);
        return assets;
    }

    function harvest() external onlyManager returns (uint256, uint256) {
        return (managed, managed);
    }

    function emergencyWithdraw(address receiver) external onlyManager returns (uint256) {
        uint256 x = managed;
        managed = 0;
        asset.transfer(receiver, x);
        return x;
    }
}

    contract VeriBridgeVaultTest is Test {
        address internal alice = makeAddr("alice");
        MockToken internal usdc;
        RBT internal rbt;
        StrategyManager internal manager;
        VeriBridgeVault internal vault;

        function setUp() public {
            usdc = new MockToken();
            rbt = new RBT(address(this));
            manager = new StrategyManager(address(this));
            vault = new VeriBridgeVault(
                address(this),
                address(this),
                address(new MockRegistry(address(usdc))),
                address(new MockOracle()),
                address(rbt),
                address(manager)
            );
            rbt.setVault(address(vault));
            manager.setVault(address(vault));
            MockStrategy strategy = new MockStrategy(address(manager), IERC20(address(usdc)));
            manager.registerStrategy(address(strategy), 0);
            manager.setStrategyActive(address(strategy), true);
            usdc.mint(alice, 2_000e6);
            vm.prank(alice);
            usdc.approve(address(vault), type(uint256).max);
        }

        function testDepositAndAllocateMintsFixedReceiptsAndDonationDoesNotChangeRate() public {
            vm.prank(alice);
            uint256 shares = vault.depositAndAllocate(address(usdc), 1_000e6, alice, 1);
            assertEq(shares, 1_000e18);
            uint256 rate = vault.exchangeRate();
            usdc.mint(address(vault), 500e6);
            assertEq(vault.exchangeRate(), rate);
            assertEq(rbt.balanceOf(alice), shares);
        }

        function testOnlyVaultCanMintRbt() public {
            vm.expectRevert();
            rbt.mint(alice, 1);
        }
    }
