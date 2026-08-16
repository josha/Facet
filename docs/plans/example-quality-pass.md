# LuauUI tutorial gallery quality pass

**Date:** 2026-07-26
**Status:** Proposed gameplay, teaching, and visual-quality plan.

> Step 13.5's [`example-games-and-standalones.md`](example-games-and-standalones.md)
> supersedes this pass for the word dictionary, crossword-tile rules, match-3 motion,
> world-surface terminal, shared example manifest, and curated standalone places. This
> document remains the baseline for the seven tutorial lessons and the
> `example-quality-pass` evidence.

## Outcome

Every tutorial example must be understandable and playable in Roblox Studio without
reading its source. Together the seven files should feel like one designed LuauUI
product, teach the concept promised by the guide, work through the framework's
supported input paradigms, and have a deterministic reset path.

This is not a source-only cleanup. Follow
[`agent-execution-contract.md`](agent-execution-contract.md): run the real gallery
adapter in a visible Studio play session, record native/semantic input and state
traces, and pair captures with the fixture and runtime facts they show.
Drive the declared view matrix through
[`studio-device-verification.md`](studio-device-verification.md), using the current
device presets discovered at runtime rather than manual emulator clicking.
Use the public theme contract from
[`theme-packages-and-skinning.md`](theme-packages-and-skinning.md).

## Preserve the tutorial structure

`ui_todo.md` defines seven runnable files. The guide may describe more than seven
learning stages because one file teaches multiple stages. Keep the examples small and
progressive:

1. temperature converter;
2. playlist table;
3. settings sync;
4. confirmation dialog;
5. word game;
6. tile game;
7. match-3.

Do not turn an example into a reusable subsystem or production game. Extract only
logic that is genuinely framework capability.

## Framework versus example responsibility

Examples are deliberately thin consumers of LuauUI. They own tutorial copy,
deterministic fixture data, and domain/game rules such as Wordle scoring or match-3
resolution. Their UI code should select public controls and semantic theme roles,
bind state/commands, and declare intended layout alternatives. LuauUI—not each
example—owns choosing and executing layout, input paradigm, focus/navigation, hit
targets, scrolling, interaction states, accessibility, preferred-text/safe-area
adaptation, resource lifecycle, and reduced-motion behavior.

Before editing, create an ownership ledger for every custom UI helper, direct Roblox
GUI/input access, device/layout branch, and workaround found or proposed. Classify it
as example-domain logic, explicit adapter/composition wiring, or framework-owned. A
need is framework-owned when it repairs a public promise, could reasonably serve
another screen, derives from environment/input/accessibility facts, or would otherwise
duplicate adaptation/control machinery. One example is enough to expose a framework
bug.

For framework-owned needs, add the smallest general public mechanism or root-cause
fix in LuauUI with focused tests, docs, conformance/registration updates, and
real-adapter proof; then rewrite the example to consume it. Do not make an example
pass with raw `Instance` construction, direct UI input routing, platform-name
branches, imperative responsive geometry, a parallel focus graph, copied control
state, or animation that bypasses the framework model. Do not move Wordle, tile, or
match-3 rules into LuauUI merely because only one example needs them.

Completion requires no temporary UI workaround or unexplained non-declarative helper
in an example. The ledger must show that example code is content/domain logic plus
declarative LuauUI composition, with any unavoidable adapter boundary named and
justified.

## Audit all seven by playing them

Before editing, create one acceptance row per example and play each in Studio. Record:

- the lesson promised by its source header and tutorial guide;
- what the player sees at startup;
- the first action the player is expected to take;
- visible feedback for success, failure, and unavailable actions;
- completion and reset/restart;
- pointer, touch, keyboard, gamepad/ten-foot, and relevant hybrid behavior;
- phone portrait/landscape, tablet, desktop, and console/ten-foot presentation;
- current style ownership and any direct property/literal bypass;
- Studio warnings, dead controls, clipped/empty content, stale state, and teardown.

Fix every defect that prevents play, teaching, adaptation, or coherent styling. Do
not limit the implementation to the two examples already reported.

## Theme coverage and drift prevention

By this roadmap stage, native Roblox StyleSheets are the runtime paint authority. Do
not route examples back through a superseded custom paint-token system.

- Every style-authority property must come from the current native StyleSheet roles,
  rules, and tags.
- Solver-owned semantic metrics must resolve from the active package's frozen metric
  snapshot; the renderer and solver must agree on the effective font and geometry.
- Content data and game rules may be literal; colors, fonts, style radii, and
  presentation spacing may not bypass their owning system.
- Word/tile/match state colors must be semantic roles or tags, not raw RGB values in
  example code.
- A runtime package swap must visibly change palette, typography/control metrics, and
  bounded chrome across every example without editing or remounting its screen.

Add a drift check that understands property authority. A broad grep that bans every
number or string is not sufficient. It should fail on direct writes/literals for
style-owned properties, unknown semantic roles, or example adapter writes, while
allowing documented content and structural constants.

Capture all seven examples under Studio Neutral and Fantasy Parchment for every
declared layout profile. Fantasy Parchment must change font/metrics and exercise its
nine-slice chrome, not merely recolor. Pair each capture with effective
package/snapshot, actual and solved geometry, style-role/tag, decoration
layers/fallback, focus, and mount identity.

## Example 03: make optimistic synchronization visible

The current implementation exposes loopback server controls to tests but not to the
player, so an interactive user can leave a request pending without seeing the full
lesson.

A person who has never read the source must be able to:

1. distinguish the optimistic draft from authoritative server state;
2. trigger an intentionally accepted change;
3. see the optimistic value immediately while the request is pending;
4. deliver or observe acceptance and see the values reconcile;
5. trigger an intentionally rejected change;
6. see the optimistic value, rejection reason, and rollback;
7. reset the demonstration.

Use plain labels and a short visible event/status history. Keep the loopback server
deterministic; do not add networking just to teach the state transition. Verify the
lesson through pointer/touch and focus-based keyboard/gamepad interaction. Update the
source header and guide so they describe what the player actually sees.

## Example 05: a complete Wordle-like word game

Use the linked
[React/Wordle walkthrough](https://www.rozmichelle.com/react-game-design-recreating-wordle/)
for its useful decomposition of board, row, cell, keyboard, and game state—not as the
authority for exact mechanics. The article explicitly chooses to color excess
duplicate letters differently from the actual game. LuauUI's example must use the
letter-budget rule below.

Required mechanics:

- a visible six-row, five-column board at startup;
- entry into only the active row;
- submission only when five letters are present and Enter/Submit is invoked;
- a tutorial-sized local accepted-guess dictionary and separate common-solution list;
- visible rejection of short and invalid guesses without consuming a row;
- duplicate-letter scoring in two passes: exact matches consume the solution's
  letter budget before misplaced matches; excess duplicates are absent;
- submitted rows retain their evaluated state while the next row becomes active;
- on-screen keyboard state accumulates monotonically by strongest known result:
  correct beats present, present beats absent, and later weaker evidence never
  downgrades a key;
- win after the solution is submitted;
- loss after six valid incorrect guesses, with the solution revealed;
- input disabled after win/loss except for restart/dismiss actions;
- deterministic restart with a reproducible seed/solution;
- state conveyed by semantic styling and a non-color-only cue or semantic label.

Test the pure scoring and state machine independently, including multiple duplicate
patterns, invalid/short guesses, key-state precedence, row consumption, win, loss,
and restart.

Then play the mounted example through:

- physical/injected hardware letter, Backspace, and Enter paths available in Studio;
- pointer and touch activation of on-screen keys;
- keyboard focus navigation/activation of on-screen keys;
- gamepad navigation, A activation, B/cancel behavior, and ten-foot focus;
- switching among live input classes without losing the active guess.

Do not prove on-screen input by calling `typeLetter`, `submit`, or another game method
directly. Scripted methods may prepare deterministic fixtures but do not close native
input rows.

## Examples 06 and 07: actually validate the games

Play the tile game and match-3 from a fresh start through their meaningful loop.
Verify that:

- instructions and selectable state are visible;
- navigation and activation select the tile the player expects;
- invalid moves explain themselves and leave state consistent;
- valid match-3 swaps resolve matches, gravity, refill, and chained matches
  deterministically;
- the initial board is not immediately stuck or silently pre-matched unless the
  tutorial explicitly demonstrates that state;
- image pending/failure states are visible and recoverable;
- completion/progress and reset are available;
- phone and ten-foot layouts remain usable;
- rapid input and reset do not leave stale selection, focus, resources, or actions.

Add gameplay tests for every defect found. Do not infer playability from the board
algorithm alone.

## Other examples

Play examples 01, 02, and 04 through their advertised lesson and correct any
misleading copy, dead end, missing reset, style bypass, layout failure, or input
failure. Preserve their small scope.

## Delegation and verification

The Opus 5 lead owns the acceptance ledger, shared style/authority changes, gallery
integration, gate, and final evidence.

Do not pre-spawn an agent team. If delegation materially shortens the work, use
Claude Opus 5 (`claude-opus-5`) at `xhigh` for at most two simultaneous implementer
packages with precise inputs and disjoint ownership: example 03 and example 05 are the
natural independent packages. The lead should play/audit all seven examples, own
examples 06/07 fixes unless they become a genuinely sizeable independent track, and
own every shared gallery, StyleSheet, gate-manifest, framework, and integration edit.
Do not use implementer subagents to recheck work the lead can verify directly.

After integration, run the required fresh-context phase-gate verifier once. Add the
architecture verifier only if shared styling/property authority or framework code
changed, and the Roblox-platform verifier only if engine-facing behavior changed.
Use `xhigh` where supported. The phase-gate verifier must play the touched examples
through the real adapter and inspect raw artifacts and captures, not merely test
names. Resolve every requirement-affecting finding and rerun the affected evidence.

## Gate and evidence

Register `example-quality-pass` in the existing gate manifest before implementation
with honest pending checks. Flip a check to executable only when its implementation
and evidence exist. Do not recreate the gate runner.

The gate must cover:

- a checked seven-example play/teaching matrix;
- the default and alternate style coverage plus property-authority-aware drift check;
- example 03 accept, reject, rollback, and reset in live play;
- example 05 complete mechanics and four-input play;
- examples 06/07 meaningful gameplay and reset;
- layout/capture matrix for all seven examples;
- scriptable device-matrix results with the exact resolved presets/configurations and
  `VirtualInput` traces for supported keyboard/pointer paths;
- clean Studio output and lifecycle teardown;
- strictly increased, registered tests and the full green library suite;
- updated headers, tutorial guide, inventory, and buildable standalone places;
- an ownership ledger with no unresolved workaround and framework fixes proven
  through public APIs before examples consume them;
- resolved requirement-affecting verifier findings;
- exact pending physical-only rows.

Store the canonical result at `artifacts/example-quality-pass/gate.json`, with
scenario traces and captures beneath the same artifact family.

## Completion

This pass is complete only when the canonical gate exits zero; every automated Studio
row passes; the seven examples look coherent under both materially different theme
packages; each example's lesson is visible in play; the word game implements the
mechanics above; the tile and match-3 games have been played and corrected; all
standalone example places rebuild; and the final report gives exact commands,
results, artifact paths, and the final ownership-ledger disposition.

Physical-device confirmation may remain explicitly pending. It must not be described
as completed from Studio emulation.
