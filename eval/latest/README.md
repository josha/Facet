# Better first-attempt game UI with Facet

This work improves the skill and design guides so an author can build a useful,
distinctive game UI on the first attempt. Principles lead to the current task,
then to Facet and Compose examples and a capture-and-revise loop. The guide
connects player intent, visual identity and interaction hierarchy to concrete
HUD, inspection, collection and page patterns.

**The latest Facet game wins the complete seven-state desktop and tablet visual
comparisons in both Astra Medium presentation orders.** Judges favored labeled
filters, collection and preview together, visible livery actions and useful
information density. Phone layout and console input remain the next targets.

## Latest comparison

A fresh Astra Medium (`gpt-6-astra`, medium effort) Facet author used source
`107beff5`. The brief, acceptance requirements, seed, Studio MCP-only author
tools and 30-minute limit were unchanged. Plain is the retained original Astra
Medium game. Neither frozen game was repaired during evaluation.

Astra Medium judged all five device groups in both presentation orders: ten
requests, one attempt per order, with no retries. The exact 64 images and all
five public judgment files are in [the evidence archive](evidence.zip).

| Device | Matched states | Result across both orders |
| --- | ---: | --- |
| Desktop | 7/7 | Facet wins both |
| Phone portrait | 6/7 | Plain wins both |
| Phone landscape | 6/7 | Plain wins both |
| Tablet | 7/7 | Facet wins both |
| Console | 6/7 | Split: one win for each arm |

The states are Hub, Shop, Garage, Livery, Race, Results and Tutorial. Results
is absent from both phone comparisons because Plain's native ACCEL checks
failed. It is absent from console because the new Facet input route did not
reach Results. Console orders disagreed; this is not a consistent tie verdict.

This readout compares only the most recent Plain and Facet author runs.
Visual wins do not establish complete game acceptance, physical-device
coverage or a controlled estimate of one source change's effect.

## A concrete path to the remaining requirements

1. **Preserve the decision on compact screens.** Phone judgments identify
   dominant filters, clipped headings and tutorial content, and crowded race
   information. Retain the subject, essential facts and action; let secondary
   controls scroll. Check all seven states, including short landscape screens.
2. **Keep HUD sizing intrinsic where the parent hugs content.** The generated
   game's text helper wraps text with a scale width inside a hugging row. This
   is consistent with its offscreen Menu. The public HUD example uses intrinsic
   sizing. Confirm the cause in a focused native check, then require visible,
   reachable Menu, readouts and actions in compact previews.
3. **Resolve controller focus and cursor interaction.** The emulator delivered
   Gamepad1 events, but a pointer event also reopened Menu and disabled driving.
   Isolate that sequence, then complete queue, drive, finish and return with
   controller input alone and visible focus throughout.

These targets retain the desktop and tablet strengths and address observed
failures. They define the next checks; they do not guarantee an overall pass.

## Native input evidence

The new Facet game moved its kart with actual desktop mouse/keyboard input and
native simulated Touch on both phone orientations and tablet. Results were
observed on all four presets; return to Hub was checked on desktop. Portrait
panels needed a keyboard Menu fallback
because Menu was offscreen. Tablet race entry used Menu because native Jump
overlapped the HUD Join target. Those alternatives do not prove the blocked
touch actions work.

The separate console check recorded Gamepad1 R1, A, R2 and Thumbstick1 events,
plus MouseButton1. Menu reopened, driving became disabled and movement stayed
at zero. This mixed sequence does not establish a pure R2 defect or successful
controller-only gameplay. Plain's console panels were recovered through pointer
routes after evaluator selection errors were corrected. Both Plain
phone Race routes passed after normal tutorial Skip, but ACCEL activation and
Results did not pass. Original reports and failures remain in the archive.

## Author usage

| Author | Wall time | Total tokens, including cached input |
| --- | ---: | ---: |
| Latest Plain | 23.14 min | 2,392,800 |
| Latest Facet | 24.55 min | 8,941,988 |

Facet used 3.74 times Plain's total tokens and 1.06 times its wall time.
Uncached input was 254,222 for Facet and 87,777 for Plain. These counters are
not billing receipts. The Facet transcript shows repeated large Source writes
as a cost target. The archive includes the analysis and its limits.

## Source validation and files

All 38 runnable full-tier producers passed on clean source `107beff5`, including
package build and package status. The reference-host benchmark producer and
full Studio producer were deferred; two release producers were not selected.
Verify records a selected, narrowed result. A separate benchmark passed. Native
navigation input ownership passed all 17 reported steps. Garage Save was
checked on desktop and both phone orientations; desktop save, change and reload
also passed. These selected checks are not the full Studio suite.

- [Latest frozen Facet game](facet/game.rbxlx).
- [Latest frozen Plain game](plain/game.rbxlx).
- [Evidence](evidence.zip): exact judge images and results, native
  observations, source validation, usage, source findings and hash manifest.

The automatic post-author check ran before the complete submission was sealed
and failed. Its original result is preserved alongside the later passing
submission check. Raw model sessions and private process records are excluded.
Broad game acceptance and performance overhead remain unverified.
