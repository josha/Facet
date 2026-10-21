# Sol 6.1 Medium slice, third pair

Facet passed all 13 universal checks, compared with 1 for Plain, but used
4.568 times the tokens and 3.062 times the author wall time. This pair does
not meet the efficiency or overhead targets. Passing the required checks
does not mean that all task requirements or headline rules passed.

Both arms ran fresh at source `59c540b22bf8ffefff3234709d2f850d7a674eb4`,
one task, seed 1, sequentially, with Sol 6.1 Medium. The evidence directory is
`artifacts/facetbench/slice-sol61-medium-3`. Both author transcripts completed
successfully. The saved results remain the authoritative records.

| Measurement | Plain | Facet |
| --- | ---: | ---: |
| Author status | completed | completed |
| Required run checks and budgets | fail | pass |
| Universal checks | 1 / 13 | 13 / 13 |
| Diagnostic spec checks | 23 / 49 | 34 / 49 |
| Desktop diagnostic checks | 11 / 24 | 17 / 24 |
| Phone portrait diagnostic checks | 11 / 24 | 16 / 24 |
| Strict type errors | 0 | 0 |
| Author wall time | 561.549 s | 1719.399 s |
| Total tokens | 1,929,811 | 8,815,592 |
| Uncached input tokens | 101,228 | 190,527 |
| Cached input tokens | 1,810,432 | 8,595,328 |
| Output tokens | 18,151 | 29,737 |
| Completed CLI turns | 1 | 1 |
| Observable CLI turn duration | 560.306915 s | 1718.039144 s |
| Tool calls | 72 | 166 |
| Tool time, union | 140.486 s | 1086.477 s |
| Tool errors | 4 | 16 |

Each turn duration is the observed `turn.started` to `turn.completed`
interval. It includes all tools and waits. It does not measure isolated model
thinking or internal response latency. Facet's interval is 3.066 times
Plain's. One turn per arm does not establish a latency distribution or a
cross-task confidence interval.

The token target is a ratio of at most 0.5; the wall-time target is at most
0.6. Both fail here. The lower-turn-duration goal also remains unmet.
This one-task slice cannot establish the minimum five-task headline or its
confidence bounds. Facet still fails 15 of the 49 diagnostic spec checks;
Plain fails 26. The universal and diagnostic tiers test different claims.

## Native measurements

The following values come from `scores["spec.perf.<device>.<metric>"]`
in each indexed `result.json`. They are the diagnostic spec pass, not the
separate universal pass. Both arms reported return to root on both devices.

| Device | Diagnostic metric | Plain | Facet |
| --- | --- | ---: | ---: |
| Desktop | Mount, s | 2.286 | 2.243 |
| Desktop | Final Lua heap, KB | 658 | 582 |
| Desktop | Final GUI memory, MB | 29.936 | 32.950 |
| Desktop | Heap return ratio | 1.235 | 0.812 |
| Desktop | GUI return ratio | 0.914 | 1.000 |
| Desktop | Idle frame p50 / p95, ms | 4.043 / 5.224 | 4.125 / 5.484 |
| Desktop | Active frame p50 / p95, ms | 4.066 / 5.858 | 4.065 / 5.735 |
| Desktop | Returned to root | 1 | 1 |
| Desktop | GUI object delta | 18 | 0 |
| Desktop | Total UI instance delta | 38 | 41 |
| Phone portrait | Mount, s | 2.262 | 11.928 |
| Phone portrait | Final Lua heap, KB | 707 | 574 |
| Phone portrait | Final GUI memory, MB | 28.488 | 33.582 |
| Phone portrait | Heap return ratio | 1.378 | 0.957 |
| Phone portrait | GUI return ratio | 1.244 | 1.000 |
| Phone portrait | Idle frame p50 / p95, ms | 4.028 / 5.180 | 4.162 / 5.548 |
| Phone portrait | Active frame p50 / p95, ms | 4.055 / 5.648 | 16.672 / 18.504 |
| Phone portrait | Returned to root | 1 | 1 |
| Phone portrait | GUI object delta | 24 | 0 |
| Phone portrait | Total UI instance delta | 47 | 34 |

In these diagnostic samples, Facet's final GUI memory exceeds Plain's by
10.1% on desktop and 17.9% on phone, above the 5% allowance. Phone mount
time is 5.274 times Plain's, above the 1.10 limit. Plain exceeds its own
1.05 heap return limit on both devices and GUI return limit on phone.
These finite samples and descendant counts do not establish an unbounded leak.

The separate universal pass records Facet heap return ratios of 1.149 on
desktop and 1.008 on phone. Its desktop value exceeds the 1.05 per-arm limit,
even though the diagnostic desktop sample does not. The universal pass also
records different phone mount times: 2.286 s Plain and 5.118 s Facet. Keep
the two passes separate; selecting one favorable sample would hide an unmet
target.

Frame values are `RenderStepped` deltas: they measure cadence. Earlier runs
switched between roughly 60 Hz and 240 Hz, and these windows can include
unrelated host work. The phone diagnostic active medians here are near
4.1 ms and 16.7 ms. They cannot establish causal UI frame-cost overhead.
The recorded cadence ratios exceed several configured bounds; the bounds
remain unchanged. This report makes no CPU, GPU or rendering-cost claim.

## Trace cost and judge status

The Facet author ran six full device sweeps with `tools/facet verify --tap
Shop ...` and no device filter. Their observed command intervals total
535.953 seconds, about 31% of its author wall time. These are transcript
items `item_88`, `item_108`, `item_136`, `item_147`, `item_160` and `item_172`.
They form part of tool time, not an additional cost to add to it.
Repeated `purchaseCard` clipping repair and verification contributed to
the long trace. This is evidence of iteration cost, not proof that removing
checks would preserve quality.

The completed blind judge used Sol 6.1 Medium through the OpenAI CLI.
`judgments.json` records two successful comparisons and no failed comparisons.
Plain won overall on desktop and phone portrait, consistently in both image
orders. Plain also won polish, hierarchy and consistency in all four
presentations. Facet therefore won 0/2 comparisons in this pair; the 70%
preference target is unmet.

The desktop critiques favor Plain's larger HUD, navigation targets, headings
and shop text, and its stronger visual consistency. They identify Facet's
small HUD and shop text as desktop weaknesses. The phone critiques favor
Plain's HUD hierarchy, compact grouping and consistent cards, while noting
clipped Plain shop tabs and cut-off Facet shop content. Both interfaces
obscure much of the world in their phone panels. Plain's hub dock also covers
the avatar in a judged image.

The same judge credits Facet's explicit purchase actions, wallet balances,
ownership or boost status and insufficient-funds explanations. Facet wins
fitness in three presentations, with one tie, and phone clarity in both
orders. These strengths do not erase its overall or polish losses. The
judgments concern these saved outputs on one task and seed; they do not
establish general quality or replace the behavioral checks.
The log is `artifacts/facetbench/sol61-preflight/judge-sol61-3.log`.

The [first pair](slice-sol61-medium.md) and
[second attempt](slice-sol61-medium-2.md) remain separate evidence. This
third pair does not authorize progression to the full or extended suite.
