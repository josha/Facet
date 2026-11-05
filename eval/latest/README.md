# FacetBench run: Facet and Plain on one brief

Two authors built the same Roblox kart racing game from one brief: one with
Facet (`facet`), one with no UI library (`plain`). Both were Claude Opus 5.5
at medium effort, with Studio MCP as their only tool, and ran at the same
time. The runner stopped each author at 30 minutes and saved the place it had
built. The Facet author kit was built from commit `8488b68`, which vendors
Compose `bf08074`. The runner and Studio driver were Verify `5d2b41e` on
Studio 0.746. The player scripts ran on Facet's Play host with the Studio
0.746 capability fix from `963edd8`, merged to main as
`1d5a4ab`. This folder holds both saved games and
[the evidence](evidence.zip): every screenshot, the blind judgments, the
player scripts, the sanitized author results, the comparison report and the
unreached states.

**Facet wins the design comparison on all five devices, in both presentation
orders.** Facet used 1.55 times Plain's tokens, so the cost check fails. The
comparison passes 3 of 18 checks.

## Design judgment

The Sol 6.1 judge compared the two games' screenshots for each device in both
presentation orders, against the principles of the
[game UI design guide](../../skills/use-facet/references/GAME_UI_DESIGN_GUIDE.md).
Each device was judged on the states both games reached on it: tutorial,
hub, shop, garage, livery and race.

| Device | Result across both orders | Confidence | What decided it |
| --- | --- | --- | --- |
| Desktop | Facet wins | 0.95, 0.97 | Facet has working garage, livery, shop and tutorial screens. Its garage keeps kart preview, statistics, selection and test drive together, and its shop shows price and affordability. Plain's buttons for those screens leave the hub on screen. |
| Phone portrait | Facet wins | 0.95, 0.96 | The same task screens, with a calmer hub. Plain keeps the road clearer during the race. |
| Phone landscape | Facet wins | 0.86, 0.90 | Facet's shop shows price, effect and affordability. Its garage and livery previews fill the panel and push the controls below the screen. Plain has clearer race statistics and labeled touch controls. |
| Tablet | Facet wins | 0.95, 0.96 | Facet's compact menu avoids Plain's clipped navigation and its overlap with the jump control. Plain's race HUD groups readings better. |
| Console | Facet wins | 0.94, 0.95 | Facet's task screens and exits. Plain's race HUD is cleaner and leaves out the wallet. |

Before reading the judgments, the evaluator reviewed every screenshot on all
devices. Its reading matched the judge's reasons. Facet's lead comes mostly
from coverage: it built every preparation screen and Plain built none. On the race,
the one screen both games built, most presentations preferred Plain's HUD.
Facet's own weak points are dim kart previews, garage prices that overlap the
row edges, panels clipped on phones, and a race HUD that keeps the wallet on
screen.

## Reachability

The player scripts opened each state with real input on each device. Plain's
Shop, Garage and Loadout buttons exist but open nothing, so those captures show
the hub. Results were left out of judging: only Plain on the tablet showed a
results screen, after a knockout. An idle player does not finish a classic
three-lap race. [`unreachable-states.txt`](evidence.zip) lists every
unreached state.

## Cost

| | Plain | Facet |
| --- | ---: | ---: |
| Total tokens | 6.63M | 10.25M |
| Model turns | 56 | 66 |
| Tool calls | 75 | 95 |
| Play starts and stops | 11 | 17 |
| Screenshots | 5 | 7 |

Facet read about 90K characters of documentation in 15 calls. Most searches
returned 6K to 15K characters, because each call batched three or four
queries.

## Comparison checks

`facetbench compare` passes pair identity, turn latency and visual
preference. Completion and behavior fail for both arms under the current
protocol, because neither author finished early and the player scripts check
reachability, not every acceptance row. Cost fails at 1.55 times Plain's
tokens. Runtime fails on the heap-return measurement on every device, and on
phone landscape the measurement was missing. Visual coverage fails on the
results gap.

Both saved games passed the unchanged-submission check after evaluation.
