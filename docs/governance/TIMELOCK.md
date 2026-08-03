# Timelock Controller

This project uses OpenZeppelin `TimelockController` with a minimum delay of 72 hours (259200 seconds). The Timelock is the owner of `ProxyAdmin` and is responsible for executing scheduled upgrades after the mandatory delay.

Proposers: Gnosis Safe (2-of-3)
Executors: address(0) (open execution) or a restricted set depending on deployment preferences.

Typical flow:

1. Safe creates and signs a transaction that calls `schedule` on the Timelock with the target, data, and salt.
2. After 72 hours, anyone (often the Safe or an executor) calls `execute` on the Timelock to perform the upgrade.
