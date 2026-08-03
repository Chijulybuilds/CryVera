# CryVera Governance

This document describes the governance architecture: Safe multisig as proposers, `TimelockController` enforcing a 72-hour delay, `ProxyAdmin` owned by timelock, and Transparent proxies for upgradeable contracts.

Key points:

- Use a Gnosis Safe 2-of-3 multisig for governance proposal approvals.
- Safe approves a timelock transaction to schedule an operation in `TimelockController`.
- `TimelockController` enforces a 72-hour delay before execution.
- `ProxyAdmin` owner must be the `TimelockController` to ensure upgrades require the timelock.

Deployment notes and verification steps are included in `script/deploy/GovernanceDeploy.s.sol`.
