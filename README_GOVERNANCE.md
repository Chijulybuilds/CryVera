# Governance Quickstart

To deploy governance infrastructure locally with Foundry:

1. Update `script/deploy/GovernanceDeploy.s.sol` to set `proposers[0]` to your Safe address.
2. Run:

```bash
forge script script/deploy/GovernanceDeploy.s.sol:GovernanceDeploy -vvvv --private-key $PRIVATE_KEY
```

3. Verify `ProxyAdmin.owner()` is the Timelock address if you transfer ownership in your deployment script.
