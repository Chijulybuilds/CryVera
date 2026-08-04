// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {StrategyManager} from "../src/core/StrategyManager.sol";
import {OracleManager} from "../src/core/OracleManager.sol";
import {TimelockUpgradeExecutor} from "../src/governance/TimelockUpgradeExecutor.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Errors} from "../src/libraries/Errors.sol";
import {AssetTypes} from "../src/types/Asset.sol";
import {IAssetRegistry} from "../src/interfaces/IAssetRegistry.sol";

contract MockStrategy is Test {
    IERC20 public assetToken;

    constructor(address asset_) {
        assetToken = IERC20(asset_);
    }

    function asset() external view returns (IERC20) {
        return assetToken;
    }

    function deposit(uint256) external pure returns (uint256) {
        return 0;
    }

    function withdraw(uint256 assets, address) external pure returns (uint256) {
        return assets;
    }

    function harvest() external pure returns (uint256 beforeAssets, uint256 afterAssets) {
        return (0, 0);
    }

    function emergencyWithdraw(address) external pure returns (uint256) {
        return 0;
    }

    function totalAssets() external pure returns (uint256) {
        return 0;
    }
}

contract MockAssetRegistry is IAssetRegistry {
    mapping(address => AssetTypes.AssetConfig) private assets;

    function registerAsset(address asset, address priceFeed, uint8 decimals) external override {}
    function enableAsset(address asset) external override {}
    function disableAsset(address asset) external override {}

    function getAsset(address asset) external view override returns (AssetTypes.AssetConfig memory config) {
        return assets[asset];
    }

    function isSupported(address asset) external view override returns (bool) {
        return assets[asset].asset != address(0);
    }

    function totalAssetsSupported() external view override returns (uint256) {
        return 0;
    }

    function assetAt(uint256) external view override returns (address) {
        return address(0);
    }

    function setAsset(address asset, address priceFeed) external {
        assets[asset] = AssetTypes.AssetConfig({asset: asset, priceFeed: priceFeed, decimals: 18, enabled: true});
    }
}

contract MockPriceFeed {
    uint80 public roundId;
    int256 public answer;
    uint256 public startedAt;
    uint256 public updatedAt;
    uint80 public answeredInRound;

    constructor(int256 answer_, uint256 updatedAt_) {
        answer = answer_;
        updatedAt = updatedAt_;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }
}

contract VersionedV1 {
    uint256 public version;

    function initialize() external {
        version = 1;
    }
}

contract VersionedV2 {
    uint256 public version;

    function initialize() external {
        version = 2;
    }
}

contract SecurityHardeningTest is Test {
    function testStrategyManagerRevertsWhenStrategyIsPaused() public {
        StrategyManager manager = new StrategyManager(address(this));
        address strategy = address(new MockStrategy(address(0x1234)));
        manager.setVault(address(this));
        manager.registerStrategy(strategy, 1000 ether);
        manager.setStrategyPaused(strategy, true);

        vm.expectRevert(Errors.StrategyIsPaused.selector);
        manager.withdrawFromStrategy(strategy, 1 ether, address(this));
    }

    function testOracleManagerRejectsSequencerDown() public {
        MockAssetRegistry registry = new MockAssetRegistry();
        MockPriceFeed feed = new MockPriceFeed(1000e8, block.timestamp);
        registry.setAsset(address(0xBEEF), address(feed));

        MockPriceFeed sequencer = new MockPriceFeed(0, 0);

        OracleManager oracle = new OracleManager(address(this), address(registry));
        oracle.setSequencerFeed(address(sequencer));

        vm.expectRevert(Errors.SequencerDown.selector);
        oracle.getPrice(address(0xBEEF));
    }

    function testTimelockCanUpgradeProxyThroughExecutor() public {
        address[] memory proposers = new address[](1);
        proposers[0] = address(this);
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        TimelockController timelock = new TimelockController(1 days, proposers, executors, address(this));

        ProxyAdmin proxyAdmin = new ProxyAdmin(address(this));
        VersionedV1 implV1 = new VersionedV1();
        bytes memory initData = abi.encodeCall(VersionedV1.initialize, ());
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implV1), address(proxyAdmin), initData);

        bytes32 adminSlot = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);
        address proxyAdminAddr = address(uint160(uint256(vm.load(address(proxy), adminSlot))));

        TimelockUpgradeExecutor executor = new TimelockUpgradeExecutor(address(timelock));
        ProxyAdmin(proxyAdminAddr).transferOwnership(address(executor));
        VersionedV2 implV2 = new VersionedV2();

        bytes memory data = abi.encodeCall(executor.upgradeProxy, (proxyAdminAddr, address(proxy), address(implV2)));
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("upgrade");
        bytes32 id = timelock.hashOperation(address(executor), 0, data, predecessor, salt);

        timelock.schedule(address(executor), 0, data, predecessor, salt, 1 days);

        vm.warp(block.timestamp + 2 days);
        timelock.execute(address(executor), 0, data, predecessor, salt);

        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        address currentImpl = address(uint160(uint256(vm.load(address(proxy), implementationSlot))));

        assertEq(currentImpl, address(implV2));
    }
}
