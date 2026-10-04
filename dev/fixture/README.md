# Frontend-owned local anvil fixture

Mock contracts matching `docs/handoffs/contracts.md`'s frozen interface exactly, used only to run
and test the Next.js app's UI flows against a real local chain before real, deployed contracts exist
(per `docs/handoffs/02-frontend.md`'s "Dependencies" section). This is not the Contracts role's
`contracts/` — it is a throwaway fixture owned by the Frontend role, kept isolated from
`contracts/`, `script/`, `deployments/`, the root `foundry.toml`, and the root `lib/` (whose
`forge-std`/`openzeppelin-contracts` it reuses read-only via relative remappings).

## Run it

```bash
# terminal 1 — start a local chain
anvil

# terminal 2 — deploy the fixture
cd dev/fixture
forge build
forge script script/Deploy.s.sol:Deploy --rpc-url http://127.0.0.1:8545 --broadcast
```

The deploy script writes `src/lib/dev/anvil-addresses.json` (repo-root-relative), matching
`deployments/<network>/addresses.json`'s schema from `contracts.md` exactly. Run the app against it:

```bash
NEXT_PUBLIC_NETWORK=anvil-local NEXT_PUBLIC_CHAIN_ID=31337 NEXT_PUBLIC_RPC_URL=http://127.0.0.1:8545 NEXT_PUBLIC_EXPLORER_URL= pnpm dev
```

`forge script`'s default deployer key (`DEPLOYER_PRIVATE_KEY` env var, falls back to anvil's own
well-known first dev-account key) starts holding all mock USDG and mock stock-token supply — import
that account into a browser wallet pointed at `http://127.0.0.1:8545` (chain id `31337`) to exercise
the UI's connect/create/deposit/rebalance/redeem flows by hand.

## What's simplified versus what `contracts.md` requires for real

- No on-chain cycle-detection walk (structurally unreachable at `MAX_DEPTH = 2` composing only
  already-registered tokens — the real Contracts implementation still needs the walk per
  `contracts.md`, since a more general depth cap could allow one).
- `executeRebalance()` only advances `lastRebalanceAt` and emits `Rebalanced`; it does not actually
  re-weight holdings. Sufficient to exercise the UI's rebalance flow, not a rebalancing algorithm.
- Oracle-freshness gating (`MAX_PRICE_STALENESS`) is not enforced — the mock oracle always reports
  `updatedAt = block.timestamp`.
- No virtual-shares/decimals-offset inflation-attack mitigation — first-deposit bootstraps shares 1:1.

None of these simplifications are load-bearing for the frontend's own contract-call shapes, which
match `contracts.md`'s frozen interface exactly.
