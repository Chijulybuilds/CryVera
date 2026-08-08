// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy
} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract GovernanceDeploy is Script {
    function run() external {
        vm.startBroadcast();

        address safe = vm.envOr("SAFE_ADDRESS", msg.sender);
        address timelockAdmin = vm.envOr("TIMELOCK_ADMIN", safe);
        uint256 minDelay = vm.envOr("TIMELOCK_DELAY", uint256(72 * 60 * 60));

        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);

        proposers[0] = safe;
        executors[0] = safe;

        TimelockController timelock = new TimelockController(minDelay, proposers, executors, timelockAdmin);

        // The ProxyAdmin should be owned by the Timelock so upgrade proposals flow through
        // Safe -> TimelockController -> ProxyAdmin -> TransparentUpgradeableProxy.
        ProxyAdmin proxyAdmin = new ProxyAdmin(address(timelock));

        // Upgradeable implementations should be initialized with the Timelock address (or a
        // dedicated governance controller address) rather than directly with a deployer EOA.

        vm.stopBroadcast();
    }
}
