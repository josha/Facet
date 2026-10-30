# FacetBench run: Facet and Plain on one brief

Two authors built the same Roblox kart racing game from one brief: one with
Facet (`facet`), one with no UI library (`plain`). Both were Claude Opus 5.5
at medium effort, with Studio MCP as their only tool, and ran at the same
time. The brief states no time limit; the runner stopped each author at 30
minutes and saved the place it had built. The Facet author kit was built from
the commit under test, and its `kit.json` names that commit. This folder holds
both saved games and [the evidence](evidence.zip): every screenshot, the blind
judgments, the sanitized author results, the comparison report and the
reachability record.

**Facet wins the design comparison on desktop, phone landscape, tablet and
console, and ties on a portrait phone.** Its blind preference passes. Both
games pass every hidden check on all five devices and reach every state. Facet
used 1.02 times Plain's tokens, so the cost check fails.

## Design judgment

A blind judge compared the two games' screenshots for each device in both
presentation orders. It scored them against the principles of the
[game UI design guide](../../skills/use-facet/references/GAME_UI_DESIGN_GUIDE.md):
player intent, attention, game identity, facts at a glance, protected play,
adaptation, continuity and truthful outcomes.

| Device | Result across both orders | What decided it |
| --- | --- | --- |
| Desktop | Facet wins | A calm hub with grouped HUD plates and one clear Enter Race action; results lead with the player's place and rewards. Plain keeps a 14-button rail and a pill strip on screen, even while racing. Plain's neon world is stronger. |
| Phone portrait | Split (tie) | Each order preferred a different game. Facet's garage kart list covers the preview and its race speed panel overlaps the touch buttons. Plain's HUD stack and save warning take the top third, and its trophy and chat buttons clip panel controls. |
| Phone landscape | Facet wins | Facet keeps position and lap in the corners and the road clear; its results lead with the player's own outcome. Plain's HUD band and nav row squeeze the garage, shop and livery panels until content clips. |
| Tablet | Facet wins | One title, Back control and compact wallet per screen. Plain repeats a two-row strip of pills and tabs on every screen, and its tab row clips. |
| Console | Facet wins | A small grouped HUD and a short dock. Plain keeps a 13-button rail and a long pill bar on screen during the race. |

## Reachability

The checker opened each state with real input on each device: tutorial, hub,
shop, garage, livery, race and results. Both games reached every state on
every device.

One Facet defect does not block a state: on a landscape phone, the Help
button sits over part of the Race button.

## Cost

| | Plain | Facet |
| --- | ---: | ---: |
| Total tokens | 15.6M | 15.9M |
| Model calls | 86 | 100 |
| Play-testing calls (Play, input, console) | 43 | 33 |
| Module writes | 28 | 38 |
| Documentation reads | 0 | 12 |
| Screenshots | 20 | 10 |

Facet took half as many screenshots and fewer play-testing calls. It wrote
more modules and read documentation once at the start.

## Comparison checks

The comparison passes 3 of 18 checks: pair identity, visual coverage and
visual preference.

| Check | Result | Why |
| --- | --- | --- |
| `visual/preference` | Pass | Facet is preferred on four devices and ties on one |
| `visual/coverage` | Pass | Both games show every state on every device |
| `cost/tokens` | Fail | 1.02 times Plain; the bar is 0.5 |
| `facet/completion`, `cost/complete-usage` | Fail | Both require the author to finish by itself; the protocol stops every author at the deadline |
| `cost/wall` | Fail | Both authors run the full 30 minutes, so the ratio is 1.0 |
| `cost/turn-latency` | Fail | 1.15 times Plain; this mostly measures the model service |
| `facet/behavior/*` (5) | Fail | The per-row player outcome checks are not written |
| `runtime/*` (5) | Fail | The memory samples come from capture passes that do not return through matching states |

## What a pass needs

1. **Checks that can measure under the protocol.** Ten of the fifteen failed
   checks cannot pass for either arm as written. Decide these before the next
   pair, without changing a pass bar:
   - Completion: the author declares the game done before the deadline, or
     completion means passing every hidden check at the deadline.
   - Wall time: measure time until the game passes every hidden check, which
     needs checks during the run.
   - Behavior: write the per-row player outcome checks (buy, equip, race,
     results).
   - Runtime: measure heap and GUI retention around an open and close of the
     same screen.
   - Turn latency: remove it or report it without a pass bar.
2. **Half of Plain's tokens.** The bar is 0.5; this pair is 1.02. Facet's
   largest costs are module writes (38 calls) and probes (26 calls).
   Smaller first writes that need fewer patches, and one scripted review pass
   in place of probes, target both.
3. **Phone portrait.** The tie comes from two Facet defects: the garage kart
   list over its preview and the race speed panel over the touch controls.
   The landscape Help button over Race is the same kind of defect.
