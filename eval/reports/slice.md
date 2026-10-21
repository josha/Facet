# FacetBench slice

This saved Opus measurement holds one run per arm on the racing-hub slice, seed 1, with
`eval/slice.json`. Both arms use Claude Opus 5.5 (`claude-opus-5-5`) at medium
effort through the Claude Code CLI, the same wall budget of 3,600 seconds, the
same scoped Studio MCP tools and the same disallowed tools (web search, web
fetch and subagents). The Facet arm also receives the Facet author kit.

One seed per arm does not establish a general quality, cost or speed claim.
The Plain run is reused from an earlier fresh run with the same starter, brief
and checks; the Facet run is fresh on the kit of Facet at the merge of
josha/Facet#147.

These numbers do not measure the Sol agent or prove the behavior of later
Facet changes.

## Results

| Measure | Plain | Facet |
| --- | --- | --- |
| Run status | completed | completed, passed |
| Agent wall time | 1,147 s | 2,007 s |
| Total tokens | 16.8M | 14.4M |
| Output tokens | 114,803 | 68,017 |
| Cost | $7.44 | $5.98 |
| Universal checks, desktop | 0% | 100% |
| Universal checks, phone portrait | 0% | 100% |
| Spec checks | 61% | 67% |
| Mount, desktop | 6.2 s | 2.2 s |
| Mount, phone portrait | 2.2 s | 2.2 s |
| Reads of Facet or tool source | n/a | 3 (the Verify audit) |

The Facet agent spent 851 seconds in the model and 1,155 seconds in tools,
mostly `verify` sweeps and Studio checks.

## Screenshot judge

The judge compares the captures of both arms on each device. It chose Plain on
desktop (confidence 0.88) and on phone portrait (confidence 0.62).

- Desktop: Plain has a stronger neon identity, a nine-item shop grid with
  currency icons and shortfall lines, and dock tiles with status. Facet has a
  flat look, a shop that shows about two cards in a short scroll area, a faint
  HUD, small text and empty panel space.
- Phone portrait: the judge credits Plain with larger touch targets, panel
  tabs and shortfall text, and faults Plain's HUD for stale values (0 Coins and
  `LV --` while the panels show the wallet) and its slightly clipped cards.
  Facet shows live values, but its dock captions crowd or clip, its panels
  have weak visual identity, and unfinished quests look actionable.

Both image orders support these arm assignments in
`artifacts/facetbench/slice/judgments.json`. The phone confidence is 0.62 in
one order and 0.60 in the other. No human calibration is recorded here.

## Runtime evidence limits

The saved idle frame p50 Facet/plain ratios are 0.998 on desktop and 0.996
on phone portrait; p95 ratios are 0.937 and 1.010. These are single Studio
samples on two simulated devices. They do not establish a five-device or
physical-device frame-cost bound.

Retained-memory evidence is missing. Facet records `returned = 0` on both
devices and has no heap or GUI memory return ratios. Its desktop mounted GUI
memory sample is zero. Plain's desktop heap return ratio is 1.212, above the
1.05 own-baseline limit. The saved run therefore does not prove the required
retained-memory bound. See each arm's `result.json` and `checks/perf.json`.

## Places

- [Plain](places/racing-hub-slice-plain.rbxl)
- [Facet](places/racing-hub-slice-facet.rbxl)

Each place is built from the arm's final workspace with Rojo.
