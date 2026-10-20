# FacetBench slice

This historical Claude baseline holds one run per arm on the racing-hub slice, seed 1, with
`eval/slice.json`. Both arms use Claude Opus 5.5 (`claude-opus-5-5`) at medium
effort through the Claude Code CLI, the same wall budget of 3,600 seconds, the
same scoped Studio MCP tools and the same disallowed tools (web search, web
fetch and subagents). The Facet arm also receives the Facet author kit.

One seed per arm does not establish a general quality, cost or speed claim.
The Plain run is reused from an earlier fresh run with the same starter, brief
and checks; the Facet run is fresh on the kit of Facet at the merge of
josha/Facet#147.

The Sol measurement is pending. These numbers do not measure the current Sol
agent or prove the behavior of later Facet changes.

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

## How to climb

The goal is for Facet to deliver beautiful, cross-platform, themeable game UI
for fewer tokens and less time than the plain engine. On this slice, Facet is
already more correct across devices and uses fewer tokens. Time and look are the
open climbs: most Facet time is tool time, and the judge prefers the Plain look.

First establish a fresh paired Sol 6.1 Medium baseline with the current suite.
Do not compare a Sol run with the historical Claude Plain run. Then each turn
is one Facet arm run on this slice and one Facet PR:

1. Run `agent-eval run --suite eval/slice.json --seed 1 --fresh --arm facet`.
2. Read the hidden checks, the judge, the captures, the agent time per tool and
   `lute run eval/tools/internals.luau <run directory>`. Each read of Facet or
   tool source names a doc gap or a bug.
3. Fix the causes in Facet, its recipes or its tools. Do not change the eval
   to pass.
4. Rerun the Facet arm, then judge against a saved Plain run with the same
   model, effort, brief and checks.

Across three turns on this slice, the Facet arm went from hitting the 60-minute
wall with 31 to 38 source reads to finishing in 33 minutes with 14.4M tokens,
fewer than Plain, and every universal check passing.

## Hill-climbing opportunities

Each item names a Facet, tool or eval change that the run evidence supports.

1. **Buy stays enabled when the player cannot pay.** The saved `Tasks.shop` disabled
   Buy for an unaffordable item. The brief asks the server to refuse and name
   the missing currency, and six spec cases tap Buy on such items. Keep Buy
   enabled, show the shortfall in the caption and show the server's reason.
2. **Focus ring on console.** `focus-hidden` reports the HUD dock buttons
   after every console sweep, in one Composition and one ScreenGui. Reproduce
   the selection image state in Studio and fix the ring.
3. **Modal backdrop and covered actions.** With a Sheet open, the audit
   reports the HUD buttons under the modal backdrop as `action-covered`, and
   one spec case fails because Quests is covered. Decide whether controls
   under an active modal backdrop count as covered, and teach the recipe to
   close the Sheet before the next dock action.
4. **Collections in a hug panel.** The saved shop computed three columns
   from its outer width, while the native viewport and grid gutters fit two.
   It gave a 340-pixel canvas a 190-pixel viewport. Use the collection's
   published canvas extent instead of repeating its column calculation.
5. **Exit motion in captures.** A capture right after Close can catch the exit
   transition and report a backdrop finding. Wait for exit motion to settle.
6. **Live HUD state.** Plain's phone HUD showed placeholder values. Facet's
   saved HUD reads wallet cells and shows live values. Preserve that behavior;
   the judge evidence does not identify a stale-state defect in Facet.
7. **Exact wording.** Detailed briefs can specify product words such as
   "Buy for 10 Gems", "+5/s" and "Ends in M:SS". Preserve requested copy
   in that application. Keep shared recipes independent of eval copy.
8. **Visual identity.** The judge still prefers Plain's look. Give the theme
   recipe currency icons, glow strokes on primary actions, dock status tiles
   and larger HUD numbers, and size short panels to their content while Close
   keeps one place.
9. **Speed.** Cold `lint --types` took about 15 seconds. A separate source
   check reports 377 new-solver diagnostics; this does not isolate their
   contribution to latency. Reuse unchanged static work and profile the
   remaining cost. Keep native Studio evidence for engine geometry and input.
