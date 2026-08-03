// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {StrategyManagerUpgradeable} from "../src/core/StrategyManagerUpgradeable.sol";

contract StrategyManagerUpgradeTest is Test {
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

    function testStrategyManagerUpgradePreservesState() public {
        StrategyManagerUpgradeable implV1 = new StrategyManagerUpgradeable();
        bytes memory initData = abi.encodeWithSelector(StrategyManagerUpgradeable.initialize.selector, deployer);

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implV1), deployer, initData);

        StrategyManagerUpgradeable proxied = StrategyManagerUpgradeable(address(proxy));

        // set vault and verify
        proxied.setVault(address(0xBEEF));
        assertEq(proxied.vault(), address(0xBEEF));

        // deploy V2 and upgrade via ProxyAdmin found in admin slot
        StrategyManagerUpgradeable implV2 = new StrategyManagerUpgradeable();
        bytes32 adminSlot = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);
        bytes32 adminAddressBytes = vm.load(address(proxy), adminSlot);
        address proxyAdminAddr = address(uint160(uint256(adminAddressBytes)));
        ProxyAdmin(proxyAdminAddr)
            .upgradeAndCall(ITransparentUpgradeableProxy(payable(address(proxy))), address(implV2), "");

        // state preserved
        assertEq(StrategyManagerUpgradeable(address(proxy)).vault(), address(0xBEEF));
    }
}
