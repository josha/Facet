# FacetBench run: Facet and Plain on one brief

Two authors built the same Roblox kart racing game from one brief: one with
Facet (`facet`), one with no UI library (`plain`). Both were Claude Opus 5.5
at medium effort, with Studio MCP as their only tool, and ran at the same
time. The runner stopped each author at 30 minutes and saved the place it had
built. The Facet author kit was built from commit `82f5f4f`, which its
`kit.json` names. This folder holds both saved games and
[the evidence](evidence.zip): every screenshot, the blind judgments, the
player scripts, the sanitized author results, the comparison report and the
unreached states.

**Plain wins the design comparison on desktop, tablet and console; Facet wins
on a portrait phone; the landscape phone splits.** Facet used 1.43 times
Plain's tokens, so the cost check fails. The comparison passes 2 of 18 checks.

These results belong to kit `82f5f4f` with Compose `85f5c18` and Verify
`f6681cd`, run on 2026-11-04. They do not measure later Facet commits. The
previous run (2026-10-29, `aa60e18`) had Facet winning four of five devices at
1.02 times Plain's tokens. In this run Facet's own cost fell from 15.9M to
12.0M tokens and Plain's fell from 15.6M to 8.35M.

## Design judgment

The Sol 6.1 judge compared the two games' screenshots for each device in both
presentation orders, against the principles of the
[game UI design guide](../../skills/use-facet/references/GAME_UI_DESIGN_GUIDE.md).
Each device was judged on the states both games reached on it, so a state one
game reached by chance does not count for it alone.

| Device | Result across both orders | What decided it |
| --- | --- | --- |
| Desktop | Plain wins | Plain's garage keeps a kart preview, statistics and actions together; its livery shows the kart with the swatches. Facet's garage pushes detail below the screen and its livery has no preview. Facet keeps the race view clearer. |
| Phone portrait | Facet wins | Facet groups primary actions at the bottom and leaves the world clear; Plain's upper area holds competing badges and navigation. |
| Phone landscape | Split (tie) | Each order preferred a different game. |
| Tablet | Plain wins | Plain shows kart previews and labeled color swatches. |
| Console | Plain wins | The same garage and livery difference as desktop. |

Before judging, the evaluator played both games on desktop. Its own reading
matched the judge's reasons: Facet led on the hub and the race view, Plain on
the garage and livery, and the shop was even.

## Reachability

The player scripts opened each state with real input on each device:
tutorial, hub, shop, garage, livery, race and results. An idle player does not
finish a classic three-lap race, so results appear only where the track vote
chose a knockout track (Plain, desktop). Other gaps:

- Facet, landscape phone: the jump button covers Shop, so Shop never opens.
- Facet, tablet: the Race button does not activate with touch.
- Facet, portrait phone: the race did not start.
- Plain, console: the Studio session was lost during the race step.

[`unreachable-states.txt`](evidence.zip) lists every unreached state.

## Cost

| | Plain | Facet |
| --- | ---: | ---: |
| Total tokens | 8.35M | 11.97M |
| Model calls | 55 | 71 |
| Play starts and stops | 14 | 9 |
| Screenshots | 9 | 10 |

Facet read about 44K characters of documentation through the FacetDocs search
helper, against about 180K in earlier pairs.

## Comparison checks

`facetbench compare` passes pair identity and turn latency. Completion,
behavior and runtime fail for both arms under the current protocol, because
neither author finished early and the player scripts check reachability, not
every acceptance row. Cost fails at 1.43 times Plain's tokens. Visual
coverage and preference fail on the results gaps and the device verdicts.

Both saved games passed the unchanged-submission check after evaluation.
