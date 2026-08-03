// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    Initializable
} from "lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract CIPRegistry is Initializable, AccessControl {
    bytes32 public constant CIP_ADMIN_ROLE = keccak256("CIP_ADMIN_ROLE");

    event CIPRegistered(
        uint256 indexed cipId,
        bytes32 indexed contentHash,
        address indexed target,
        address newImplementation
    );

    function initialize(address admin) public initializer {
        require(admin != address(0), "Zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CIP_ADMIN_ROLE, admin);
    }

    function registerCIP(
        uint256 cipId,
        bytes32 contentHash,
        address target,
        address newImplementation
    ) external onlyRole(CIP_ADMIN_ROLE) {
        emit CIPRegistered(cipId, contentHash, target, newImplementation);
    }
}
