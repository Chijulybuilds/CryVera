// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {OracleManagerUpgradeable} from "../src/core/OracleManagerUpgradeable.sol";
import {AssetRegistry} from "../src/core/AssetRegistry.sol";

contract OracleManagerUpgradeTest is Test {
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

    function testOracleManagerUpgradePreservesRegistry() public {
        AssetRegistry registry = new AssetRegistry(deployer);

        OracleManagerUpgradeable implV1 = new OracleManagerUpgradeable();
        bytes memory initData =
            abi.encodeWithSelector(OracleManagerUpgradeable.initialize.selector, deployer, address(registry));

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implV1), deployer, initData);

        OracleManagerUpgradeable proxied = OracleManagerUpgradeable(address(proxy));
        assertEq(address(proxied.i_registry()), address(registry));

        OracleManagerUpgradeable implV2 = new OracleManagerUpgradeable();
        bytes32 adminSlot = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);
        bytes32 adminAddressBytes = vm.load(address(proxy), adminSlot);
        address proxyAdminAddr = address(uint160(uint256(adminAddressBytes)));
        ProxyAdmin(proxyAdminAddr)
            .upgradeAndCall(ITransparentUpgradeableProxy(payable(address(proxy))), address(implV2), "");

        assertEq(address(OracleManagerUpgradeable(address(proxy)).i_registry()), address(registry));
    }
}
