// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy
} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// @notice Small governance helper that forwards an upgrade call to ProxyAdmin.
contract TimelockUpgradeExecutor is Ownable {
    constructor(address timelock) Ownable(timelock) {
        require(timelock != address(0), "zero timelock");
    }

    function upgradeProxy(address proxyAdmin, address proxy, address implementation) external onlyOwner {
        require(proxyAdmin != address(0), "zero proxy admin");
        require(proxy != address(0), "zero proxy");
        require(implementation != address(0), "zero implementation");
        ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(payable(proxy)), implementation, "");
    }
}
