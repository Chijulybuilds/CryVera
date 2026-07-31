# VeriBridge architecture

Ethereum is the canonical settlement chain. Collateral and strategy positions remain on Ethereum; only a locked ownership receipt is represented on another chain.

## Accounting boundary

`VeriBridgeVault` is the sole source of truth for issued shares: `RBT.totalSupply()` is the canonical share supply. The vault derives the current portfolio value from its accounted idle collateral and each strategy's live `totalAssets()` report. The exchange rate is therefore value per fixed RBT share; harvests change value, never RBT balances.

The vault intentionally excludes unsolicited ERC-20 transfers from `accountedIdle`. This prevents donation/inflation attacks from affecting deposit pricing. Virtual assets and shares provide a bounded initial rate and protect the empty-vault rounding edge case.

`PositionManager` is historical and allocation metadata only. It is not ownership accounting and never authorizes redemption, which is essential because RBT is transferable.

## Modules

- `AssetRegistry`: supported collateral and feed metadata.
- `OracleManager`: Chainlink price validation and normalization.
- `RBT`: permit-enabled receipt token; only the vault can mint or burn it.
- `VeriBridgeVault`: custody accounting, share issue/burn, valuation, allocation and redemption.
- `StrategyManager`: permissioned router only; it has no user balances, shares, or strategy asset ledger.
- `BaseStrategy`: boundary for Aave, Morpho, Lido, or future adapters. An adapter knows only protocol capital and its manager.
- `CCIPSender`/`CCIPReceiver`: official Chainlink CCIP endpoints. Canonical senders lock RBT; satellite senders burn wrapped RBT. Receivers validate the CCIP router, the configured source lane/sender, and a unique message id before minting or releasing.

## Deployment order

1. Deploy `RBT`, `StrategyManager(admin)`, `AssetRegistry`, and `OracleManager`.
2. Deploy `VeriBridgeVault` with those addresses.
3. Call `RBT.setVault(vault)` and `StrategyManager.setVault(vault)` once.
4. Deploy and register audited strategy adapters, then activate them.
5. Deploy CCIP endpoints and `WrappedRBT` per satellite. Configure `WrappedRBT.setBridges(receiver, sender)` once; configure each allowed CCIP lane and the canonical release receiver once.

The deployment admin should be a timelock/multisig, while guardians have only pause/emergency authority. A deployment must configure Chainlink feed heartbeats/bounds and CCIP chain selectors from the current official network directory.
