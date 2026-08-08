// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {CIPRegistryLib} from "../types/CIPRegistry.sol";

contract CIPRegistry is Initializable, AccessControl {
    bytes32 public constant CIP_ADMIN_ROLE = keccak256("CIP_ADMIN_ROLE");

    mapping(uint256 => CIPRegistryLib.CIP) public cips;
    event CIPRegistered(
        uint256 indexed cipId, bytes32 indexed contentHash, address indexed target, address newImplementation
    );

    constructor() {
        _disableInitializers();
    }
    /// @param timelock the contract address for the TimeLockController

    function initialize(address timelock) public initializer {
        require(timelock != address(0), "Zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, timelock);
        _grantRole(CIP_ADMIN_ROLE, timelock);
    }

    /**
     * @param cipId The ID of the CIP to register
     * @param contentHash The hash of the modifications being made to any contract
     * @param target The target address for the CIP
     * @param newImplementation The new implementation address for the CIP
     * @dev this proposal allows for the registration of new CIPs before timelocks and upgrade execution is being carried out.
     */
    function registerCIP(uint256 cipId, bytes32 contentHash, address target, address newImplementation)
        external
        onlyRole(CIP_ADMIN_ROLE)
    {
        cips[cipId] = CIPRegistryLib.CIP({
            contentHash: contentHash, target: target, newImplementation: newImplementation
        });

        emit CIPRegistered(cipId, contentHash, target, newImplementation);
    }

    function getCIP(uint256 cipId) external view returns (CIPRegistryLib.CIP memory) {
        return cips[cipId];
    }
}
