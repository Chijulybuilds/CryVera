# Upgradeability Guide

This guide explains how to make selected CryVera contracts upgradeable using OpenZeppelin Transparent proxies.

Principles:

- Only selected contracts should be upgradeable (`VeriBridgeVault`, `StrategyManager`, `OracleManager`).
- Use `Initializable` pattern and `_disableInitializers()` in implementation constructors.
- Preserve storage layout; do not reorder state variables.
- ProxyAdmin must be owned by TimelockController.

See `docs/cips/CIP-0001.md` for governance rationale.
