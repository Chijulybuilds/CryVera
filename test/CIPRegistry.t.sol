// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {CIPRegistry} from "../src/governance/CIPRegistry.sol";

contract CIPRegistryTest is Test {
    CIPRegistry public registry;
    event CIPRegistered(
        uint256 indexed cipId, bytes32 indexed contentHash, address indexed target, address newImplementation
    );

    function setUp() public {
        registry = new CIPRegistry();
        registry.initialize(address(this));
    }

    function testRegisterCIPEmitsEvent() public {
        uint256 cipId = 1;
        bytes32 contentHash = keccak256(abi.encodePacked("CIP-0001"));
        address target = address(0x1234);
        address impl = address(0x5678);

        vm.expectEmit(true, true, true, false);
        emit CIPRegistered(cipId, contentHash, target, impl);

        registry.registerCIP(cipId, contentHash, target, impl);
    }
}
