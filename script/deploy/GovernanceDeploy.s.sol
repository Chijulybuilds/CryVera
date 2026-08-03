// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import {
    TimelockController
} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {
    ProxyAdmin
} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy
} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract GovernanceDeploy is Script {
    function run() external {
        vm.startBroadcast();

        // 72 hours
        uint256 minDelay = 72 * 60 * 60;

        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);

        proposers[0] = msg.sender; // placeholder, replace with Safe address off-chain
        executors[0] = address(0);

        TimelockController timelock = new TimelockController(
            minDelay,
            proposers,
            executors,
            msg.sender
        );

        ProxyAdmin proxyAdmin = new ProxyAdmin(msg.sender);

        // Example of deploying a dummy implementation and proxy would go here.

        vm.stopBroadcast();
    }
}
