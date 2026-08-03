// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TimelockBatchExecutor
 * @author CryVera Protocol Architecture Team
 * @notice Enables atomic batch execution of multiple governance operations in a single transaction.
 */
contract TimelockBatchExecutor is Ownable {
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    event BatchExecuted(bytes32 indexed batchId, uint256 callCount);
    event CallExecuted(address indexed target, uint256 index, bytes returnData);

    constructor(address timelockAddress) Ownable(timelockAddress) {
        require(timelockAddress != address(0), "TimelockBatchExecutor: zero timelock address");
    }

    function executeBatch(Call[] calldata calls, bytes32 batchId)
        external
        payable
        onlyOwner
        returns (bytes[] memory results)
    {
        uint256 length = calls.length;
        require(length > 0, "TimelockBatchExecutor: empty batch");

        results = new bytes[](length);

        for (uint256 i = 0; i < length; i++) {
            address target = calls[i].target;
            require(target != address(0), "TimelockBatchExecutor: zero target address");

            (bool success, bytes memory returnData) = target.call{value: calls[i].value}(calls[i].data);

            if (!success) {
                if (returnData.length > 0) {
                    assembly {
                        let returndata_size := mload(returnData)
                        revert(add(32, returnData), returndata_size)
                    }
                } else {
                    revert("TimelockBatchExecutor: call execution failed");
                }
            }

            results[i] = returnData;
            emit CallExecuted(target, i, returnData);
        }

        emit BatchExecuted(batchId, length);
    }

    receive() external payable {}
}
