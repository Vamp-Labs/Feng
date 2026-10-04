# Creator score

Source of truth: `src/lib/hooks/use-v2-discovery-creators.ts` (`buildCreatorRows`, constants `SCORE_*`) and the formula line printed on `/leaderboard` (`src/components/leaderboard.tsx`). This page describes exactly what the code does and nothing more.

The leaderboard is computed in the visitor's browser from registry and vault reads on the active network. There is no server, no stored ranking and no off-chain input.

## Inputs per creator

Strategies are grouped by the creator address recorded in the registry, compared in lower case. For each creator the code derives:

| Field | Definition |
|---|---|
| `strategies` | Number of strategies that creator registered. |
| `aumUsd` | Sum of the USD net asset value of those strategies. Each vault's NAV is `totalAssetsUSDG` scaled by that vault's own `usdgDecimals`. A strategy whose NAV could not be read counts as 0. Sandbox and Live strategies are added together. |
| `bestReturn` | Highest `sinceInception` among the creator's strategies that have one. `sinceInception` is `sharePrice / inceptionSharePrice - 1`. If two strategies tie, the first one in registry order is kept. Undefined when no strategy has a return yet. |
| `bestSymbol`, `bestVault` | Symbol and address of the strategy that gave `bestReturn`, shown as a link. |
| `oldestCreatedAt` | Smallest registry `createdAt` timestamp (seconds) among the creator's strategies, ignoring zero values. Undefined when none is known. |

## Score

The score is a number from 0 to 100.

```
aumScore    = log10(1 + aumUsd) / log10(1 + maxAumUsd)        0 when maxAumUsd is 0
returnScore = clamp01((bestReturn - (-0.5)) / (1 - (-0.5)))    0 when bestReturn is undefined
ageScore    = clamp01((now - oldestCreatedAt) / 86400 / 30)    0 when oldestCreatedAt is undefined

score = 100 * (0.5 * aumScore + 0.3 * returnScore + 0.2 * ageScore)
```

- `maxAumUsd` is the largest `aumUsd` across all creators currently listed, so the top creator by AUM always has `aumScore = 1`.
- `returnScore` clamps the best return to the range -50% to +100%. At -50% or worse it is 0, at +100% or better it is 1, and it is linear in between (0% return gives 1/3).
- `ageScore` reaches 1 once the creator's oldest strategy is 30 days old, linear before that.
- `clamp01` limits a value to the range 0 to 1.
- `now` is the browser clock in seconds, refreshed every 60 seconds.

Constants in code: weights `{ aum: 0.5, returns: 0.3, age: 0.2 }`, return floor `-0.5`, return cap `1`, age cap `30` days.

## What the page shows

- Table columns: rank, creator (shortened address), strategies, AUM (compact USD), best return with a link to that strategy, score (rounded to a whole number with `toFixed(0)`).
- Three ranking buttons. "By AUM" sorts by `aumUsd` descending. "By best return" sorts by `bestReturn` descending, creators without a return last. "By score" sorts by `score` descending. The default is "By AUM".
- Rank is the row position in the current ordering, so it changes with the selected ranking.
- The caption under the table prints the weights and caps from the constants above: "Score, 0 to 100: 50% AUM on a log scale against the largest creator, 30% best return since inception (clamped from -50% to +100%), 20% age of the oldest strategy (full marks at 30 days). Computed in your browser from registry data."

## Known limits

- Only strategies returned by the registry (up to 200, read in pages of 50) are counted.
- AUM is a point-in-time read, not an average, so a creator can move on the board when one deposit or redeem lands.
- Best return is a single strategy's figure, not a blend across a creator's strategies.
- The score is a display aid for the demo. It is not an on-chain value and is not used by any contract.
