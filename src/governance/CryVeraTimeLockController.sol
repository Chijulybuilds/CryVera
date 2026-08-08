// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title CryVeraTimelock
/// @notice Governance timelock for delayed protocol administration.
contract CryVeraTimelock is TimelockController {
    /**
     * @param minDelay Minimum amount of time before a scheduled operation
     * can be executed which here will be 1 day
     * @param proposers Addresses allowed to schedule operations.(Safe Address)
     * @param executors Addresses allowed to execute ready operations.
     * @param admin Temporary/default admin of the Timelock itself.
     */
    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        TimelockController(minDelay, proposers, executors, admin)
    {}
}
