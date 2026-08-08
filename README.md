# CryVera governance layout

The intended governance path for upgrade-sensitive components is:

Safe -> TimelockController -> ProxyAdmin -> TransparentUpgradeableProxy -> upgradeable implementation

Recommended ownership mapping:

- Vault upgrade path: Safe -> TimelockController -> ProxyAdmin
- StrategyManager upgrade path: Safe -> TimelockController -> ProxyAdmin
- OracleManager upgrade path: Safe -> TimelockController -> ProxyAdmin
- AssetRegistry upgrade path: Safe -> TimelockController -> ProxyAdmin
- Emergency pause / unpause: guardian or pauser roles, with unpause routed through governance when needed
- RBT: non-upgradeable and remains owned by its deployment path
- CIP registration: governance-governed metadata and traceability only

The deployment scaffold in script/deploy/GovernanceDeploy.s.sol is prepared for this layout by deploying a TimelockController with the Safe as the proposer/executor and a ProxyAdmin owned by the Timelock.
