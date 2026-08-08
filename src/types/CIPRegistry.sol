// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library CIPRegistryLib {
    struct CIP {
        bytes32 contentHash;
        address target;
        address newImplementation;
    }
}
