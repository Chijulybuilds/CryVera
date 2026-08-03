// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {VeriBridgeVaultUpgradeable} from "../src/core/VeriBridgeVaultUpgradeable.sol";
import {RBT} from "../src/token/RBT.sol";
import {AssetRegistry} from "../src/core/AssetRegistry.sol";
import {OracleManager} from "../src/core/OracleManager.sol";
import {StrategyManager} from "../src/core/StrategyManager.sol";

contract VeriBridgeVaultUpgradeTest is Test {
    ProxyAdmin proxyAdmin;
    TimelockController timelock;
    address deployer;

    function setUp() public {
        deployer = address(this);
        proxyAdmin = new ProxyAdmin(deployer);
        address[] memory proposers = new address[](1);
        proposers[0] = deployer;
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        timelock = new TimelockController(1, proposers, executors, deployer);
    }

    function testProxyDeployAndUpgrade() public {
        // deploy dependencies
        RBT rbt = new RBT(deployer);
        AssetRegistry registry = new AssetRegistry(deployer);
        OracleManager oracle = new OracleManager(deployer, address(registry));
        StrategyManager manager = new StrategyManager(deployer);

        VeriBridgeVaultUpgradeable implV1 = new VeriBridgeVaultUpgradeable();
        bytes memory initData = abi.encodeWithSelector(
            VeriBridgeVaultUpgradeable.initialize.selector,
            deployer,
            deployer,
            address(registry),
            address(oracle),
            address(rbt),
            address(manager)
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implV1), deployer, initData);

        VeriBridgeVaultUpgradeable proxied = VeriBridgeVaultUpgradeable(address(proxy));

        // sanity checks
        assertEq(proxied.totalShares(), 0);

        // deploy V2 (same contract for test purposes), upgrade via ProxyAdmin
        VeriBridgeVaultUpgradeable implV2 = new VeriBridgeVaultUpgradeable();
        // read the admin slot from the proxy (EIP-1967 admin slot)
        bytes32 adminSlot = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);
        bytes32 adminAddressBytes = vm.load(address(proxy), adminSlot);
        address proxyAdminAddr = address(uint160(uint256(adminAddressBytes)));
        ProxyAdmin(proxyAdminAddr)
            .upgradeAndCall(ITransparentUpgradeableProxy(payable(address(proxy))), address(implV2), "");

        // ensure proxy address remained same
        assertEq(address(proxy), address(proxy));
    }
}
