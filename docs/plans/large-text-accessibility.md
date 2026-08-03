# Large-text accessibility and resilient text layout

**Date:** 2026-08-03  
**Status:** Planned as roadmap Step 8.5, after desktop keyboard navigation and before
the performance lab.

## Purpose

LuauUI should treat the player's Roblox preferred text size as a first-class layout
input. A screen written once must remain readable, navigable, and stable at
`Medium`, `Large`, `Larger`, and `Largest`, including on a compact phone in portrait
and landscape. A theme with wider fonts or larger controls must receive the same
guarantee.

This stage covers large-text inclusive design. It does not claim screen-reader,
announcement, or full SwiftUI assistive-technology parity where Roblox exposes no
equivalent experience API.

Official platform anchors:

- [`GuiService.PreferredTextSize`](https://create.roblox.com/docs/reference/engine/classes/GuiService#PreferredTextSize)
  is read-only and can change while the experience runs. Roblox's example listens
  to its property-change signal.
- [`TextService:GetTextSizeOffsetAsync`](https://create.roblox.com/docs/reference/engine/classes/TextService#GetTextSizeOffsetAsync)
  returns the additive size offset for a font and size. It yields and can fail, so a
  live adapter must cache it and retain a safe fallback.
- Roblox text wrapping, bounds, truncation, and automatic sizing remain engine
  mechanisms. LuauUI owns the deterministic layout and overflow decisions around
  them.
- Apple's [typography guidance](https://developer.apple.com/design/human-interface-guidelines/typography)
  and [SwiftUI accessibility fundamentals](https://developer.apple.com/documentation/swiftui/accessibility-fundamentals)
  are the product benchmark: preserve hierarchy, adapt the layout at large sizes,
  and avoid hiding important content merely to preserve the compact arrangement.

Re-check current documentation and prove the behavior in the running Studio version
before implementation. Roblox is a rolling platform.

## Baseline to audit, not assume

LuauUI already has useful pieces: `Text.lineLimit`, exact/conservative text metrics,
`ViewThatFits`, adaptive composition, scroll-to-visible, theme typography metrics,
`compactLabel`, and reduced-motion facts. The live adapter also keeps the player's
preference out of `TextSize` so the engine does not receive a multiplicative scale
twice.

The current implementation is not sufficient evidence of correctness:

- `src/client/roblox_env.luau` maps the four preferences to guessed generous offsets
  and does not listen for `PreferredTextSize` changes;
- engine bounds, painted bounds, the solver's reservation, theme font metrics, and
  ten-foot scaling have not been compared across every preference and representative
  font/size;
- existing truncation choices do not guarantee that essential text remains
  available; and
- Sponsor View has not been product-verified at `Largest` on compact mobile portrait
  and landscape.

Start with a live measurement matrix. Determine one exact authority seam for solver
and paint after measuring actual Instances and `TextService`; do not blindly add an
offset to bounds that already include it. Prove that preference is applied exactly
once. A yielding offset lookup must never block first mount: use cached measured
values when ready, a conservative documented fallback when unavailable, and one
atomic re-solve when the answer changes.

## Framework behavior

### Live preferred-text contract

- Read all four enum values and subscribe to changes at the Roblox adapter edge.
- A change remeasures and reflows the mounted tree without remounting it or losing
  control state, focus, input ownership, scroll position, or async resources.
- Headless tests retain an injectable preference seam. Test values and the live
  native path must have explicit, non-overlapping authority.
- Theme fonts, weights, line heights, metrics, nine-slice chrome, ten-foot scaling,
  and preferred text compose without clipping or double application.
- Failure, warm-up, and stale async results retain conservative geometry and produce
  diagnostics rather than clipped first frames or reflow loops.

### Layout and overflow order

Use this order throughout public layouts and controls:

1. **Reflow first.** Wrap and grow, stack inline regions, reduce grid columns, choose
   a declared compact representation, or select another `ViewThatFits`/composition
   candidate.
2. **Scroll the containing region.** When all content cannot fit at once, keep the
   document/list/form self-paced and keep focused or edited content visible.
3. **Truncate only bounded secondary or identity text.** An action, instruction,
   status, error, result, or required fact must not disappear behind an ellipsis.
   Any permitted truncation must make the full string available through a consistent
   focus/hover/tap/activation or detail affordance that works for every applicable
   input class.
4. **Animate only as an engaged last resort.** An optional reveal/marquee may run
   only for the focused, hovered, or deliberately opened item after a quiet delay.
   A one-line reveal moves horizontally in the text's reading direction by default.
   It pauses at ends, follows grapheme boundaries, stops cleanly, and has a static
   full-text alternative. Reduced motion disables travel. At most one moving text
   surface may run in the active presentation, and the implementation must not create
   per-frame work for every clipped label.

Rapid serial visual presentation—replacing characters or words in place—is not a
default overflow mode. It removes self-paced reading and backtracking and adds motion
and cognitive load. It may be explored only as a separately approved, opt-in
experiment with pause, replay, backtrack, localization, reduced-motion, and human
accessibility evidence; it is not required to pass this stage.

Audit `Text`, `lineLimit`, text metrics, `ViewThatFits`, composition, `ScrollView`,
`compactLabel`, focus, and motion before adding API. If a reusable disclosure or
engaged-reveal contract is still needed, make the smallest public mechanism that
follows the API constitution. Screens declare content importance, line intent, and
layout candidates; they do not calculate overflow, animate labels, or branch on a
device name.

## Diagnostics and authoring safety

Extend the shared verification surface so a mounted text node can report its
preference, font and role, natural and actual bounds, natural and visible line count,
truncation/overflow state, chosen policy, and how the full value is reached.

Add targeted checks for:

- text or controls overlapping siblings or leaving their declared bounds;
- clipped essential text or truncated text with no full-value affordance;
- controls below the hit floor after reflow;
- focus hidden outside the current scroll viewport;
- repeated remeasurement/reflow after the preference settles; and
- more than the allowed number of active moving-text surfaces.

Intentional overlays need a declared relationship so a crude global overlap test
does not create false failures. Diagnostics must name the node, violated contract,
and likely fix.

## Rascal Rally Sponsor View proof

Rascal Rally is the production proof and must remain synchronized with every LuauUI
change. Reusable measurement, overflow, adaptation, focus, input, motion, and
diagnostic behavior belongs in LuauUI. Sponsor code owns localized content,
importance, semantic style/control choices, intended relationships, and declared
layout alternatives. Do not add game-local marquees, text measurement, responsive
geometry, input wiring, or parallel focus/scroll behavior.

Exercise the production LuauUI presenter through deterministic fixtures for role
selection, table/racer list and cards, race HUD/ticker/toasts/captions/countdown/
omens, both roles' results, and success/error/empty states. Include long display
names, long localized strings, large rosters, Studio Neutral, and Fantasy Parchment.

At every preference, and especially `Largest` on compact phone portrait and
landscape:

- essential actions and facts remain visible or reachable in a predictable scroll
  path;
- labels and controls do not overlap, and touch targets remain usable;
- focus order, keep-visible, direct manipulation, and state survive reflow;
- the results `column`/`twoLane`/`threeLane` choice responds to measured content
  rather than a device-name patch;
- permitted name/identity truncation exposes the full value consistently; and
- reduced motion provides the same information without moving text.

Reconcile the Sponsor accessibility and localization tables with the implemented
policy. Do not preserve a historical truncation rule when it hides an essential
fact at large text; record and test the corrected rule.

## Verification matrix

Headlessly sweep every public control/layout and representative composed screens at
all four preference values, both reference themes, representative short and long
locales, long unbroken names, mixed scripts, and reduced motion. Hot-swap `Medium`
to `Largest` and back while focus, editing, scroll, resources, and state are live.

In visible Studio, use the canonical device API and real adapter for:

- compact phone portrait at `Medium` and `Largest`;
- the same phone landscape at `Medium` and `Largest`;
- the 667x375 small-landscape Sponsor fixture at `Largest`;
- a representative tablet/desktop control catalog; and
- the relevant ten-foot composition, without conflating ten-foot scale with the
  player's preferred text size.

Use injected fixture values for repeatable layout coverage, but separately probe the
read-only real player setting and its change notification. Studio emulation does not
prove the operating-system/player-setting path. A physical phone at the actual
`Largest` preference, in portrait and landscape, remains `PENDING_PHYSICAL` until
run; subjective readability remains `PENDING_HUMAN`.

Pair captures with geometry, text metrics, selected layout candidate, focus/scroll,
preference source, style authority, lifecycle, and motion traces. Screenshots or
headless rectangles alone do not pass.

## Performance and gate

Register `large-text-accessibility` in the existing gate manifest before edits. Add
large-text/overflow workload rows to the Step 9 performance lab: preference changes,
long localized text, both themes, scroll/reflow churn, engaged reveal if shipped,
and teardown. Record measurement queue/cache work, re-solves, per-frame writes, and
active moving-label count. Do not trade readability, hit targets, or full-content
access for a faster profile.

The stage passes only when the canonical gate exits zero and writes
`artifacts/large-text-accessibility/gate.json`; the live preference uses measured
native behavior exactly once and updates while mounted; public controls/layouts pass
the large-text matrix; Sponsor View remains excellent and usable in compact mobile
portrait and landscape; full essential text is reachable; motion is bounded and
reduced-motion-safe; relevant LuauUI/RascalRally suites and prior gates are green;
both documentation sets are current; and required fresh UI, architecture, platform,
and phase-gate findings are resolved. Physical/human rows may remain honestly pending
with one prepared review build and checklist.
