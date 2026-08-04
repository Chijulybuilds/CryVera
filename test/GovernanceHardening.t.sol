// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {TimelockBatchExecutor} from "../src/governance/TimeLockBatchExecutor.sol";
import {GovernanceConfigurator} from "../src/governance/GovernanceConfigurator.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

contract TargetContract {
    uint256 public value;

    function set(uint256 x) external {
        value = x;
    }
}

contract GovernanceHardeningTest is Test {
    function testBatchExecutorRejectsUnapprovedTarget() public {
        TimelockBatchExecutor executor = new TimelockBatchExecutor(address(this));
        TargetContract target = new TargetContract();

        TimelockBatchExecutor.Call[] memory calls = new TimelockBatchExecutor.Call[](1);
        calls[0] = TimelockBatchExecutor.Call({
            target: address(target), value: 0, data: abi.encodeWithSelector(target.set.selector, 7)
        });

        vm.expectRevert();
        executor.executeBatch(calls, keccak256("batch"));
    }

    function testGovernanceConfiguratorTransfersProxyAdminOwnership() public {
        GovernanceConfigurator configurator = new GovernanceConfigurator(address(this));
        ProxyAdmin proxyAdmin = new ProxyAdmin(address(configurator));

        configurator.transferProxyAdminOwnership(address(proxyAdmin), address(0xBEEF));

        assertEq(proxyAdmin.owner(), address(0xBEEF));
    }
}
