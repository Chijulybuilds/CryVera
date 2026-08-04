// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

/// @notice Lightweight governance helper used to transfer ProxyAdmin ownership in a controlled way.
contract GovernanceConfigurator is Ownable {
    constructor(address initialOwner) Ownable(initialOwner) {}

    function transferProxyAdminOwnership(address proxyAdmin, address newOwner) external onlyOwner {
        require(proxyAdmin != address(0), "zero proxy admin");
        require(newOwner != address(0), "zero owner");
        ProxyAdmin(proxyAdmin).transferOwnership(newOwner);
    }

    function transferOwnershipToProxyAdmin(address proxyAdmin) external onlyOwner {
        require(proxyAdmin != address(0), "zero proxy admin");
        transferOwnership(proxyAdmin);
    }
}
