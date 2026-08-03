// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";

contract Box {
    uint256 public value;

    function store(uint256 v) external {
        value = v;
    }
}

contract TimelockScheduleTest is Test {
    TimelockController public timelock;
    Box public box;
    uint256 public constant DELAY = 72 hours;

    function setUp() public {
        address[] memory proposers = new address[](1);
        proposers[0] = address(this);
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        timelock = new TimelockController(DELAY, proposers, executors, address(this));
        box = new Box();
    }

    function testScheduleAndExecute() public {
        bytes memory data = abi.encodeWithSelector(box.store.selector, 123);
        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(0);

        bytes32 id = timelock.hashOperation(address(box), 0, data, predecessor, salt);

        // schedule
        timelock.schedule(address(box), 0, data, predecessor, salt, DELAY);

        // cannot execute immediately
        vm.expectRevert();
        timelock.execute(address(box), 0, data, predecessor, salt);

        // warp past delay and execute
        vm.warp(block.timestamp + DELAY + 1);
        timelock.execute(address(box), 0, data, predecessor, salt);

        assertEq(box.value(), 123);
    }
}
