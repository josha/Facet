# Acceptance ledger — `traversal-document-order` (roadmap Step 8 follow-up)

**Stage plan:** [`docs/plans/traversal-document-order.md`](../../docs/plans/traversal-document-order.md)
**Handoff:** [`docs/handoff/2026-08-03-traversal-document-order.md`](../../docs/handoff/2026-08-03-traversal-document-order.md)
**Contract:** [`docs/plans/agent-execution-contract.md`](../../docs/plans/agent-execution-contract.md) §2/§3
**Device matrix:** [`docs/plans/studio-device-verification.md`](../../docs/plans/studio-device-verification.md)
**Stage-start source:** working tree at Step 8 completion, snapshot tag
`luauui-step8-baseline` (`f1f0454`, tracked files only — Step 8 is **uncommitted**;
see `decisions.md` TDN-4). Suite floor **3079**, baseline pinned in `baseline/`.

Written before implementation. Status values are the contract's: `PASS_AUTOMATED`,
`PASS_PHYSICAL`, `PASS_HUMAN`, `FAIL_PRODUCT`, `FAIL_ENVIRONMENT`,
`PENDING_PHYSICAL`, `PENDING_HUMAN`, and `PENDING` for a row not yet attempted.
A row may not pass through an easier row: a headless order assertion does not close
a raw-input row, and a capture does not close an ordering row.

---

## The defect this stage exists to fix

Measured live in the gallery place before any edit (Step 8 artifact
`artifacts/desktop-keyboard-navigation/studio/keyboard.json`, row `DK17-H-ring`),
sixteen Tab presses from the top of the `keyboard_navigation` fixture:

```
Actions/Reset → Count/Dec → Count/Inc → List/Row1 … List/Row12 → Volume/TrackHost/Track
```

`Volume` is on screen **between** the button row and the list. Its focus stop is a
`UI.Grip`, and every focusable Grip was deferred to the end of the focus order in
four places (`focusWalk`, `focusOrder`, `autoGroups`, `layoutGroups`). The deferral
is correct for **directional** navigation — arrowing down a table should land on
rows, not on a value control's grab zone — and wrong for **Tab**, which means document
order on every platform that has ever had a Tab key.

---

## Rows

| ID | User-visible behavior | Risk while a lower test still passes | Evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| **TD-1** | Tab visits a Slider's track in its **document position** — between the button row above it and the list below it, not after all twelve rows | The order is fixed for the one measured fixture by special-casing Slider, so any other Grip-bearing control still traverses last | E1 | `tests/traversal_order.spec.luau` | suite | PASS_AUTOMATED |
| **TD-2** | The **arrows** still defer every focusable Grip to the end, exactly as before this stage | The fix is applied to the shared order, so directional navigation silently starts landing on grab zones before content | E1 | same, plus unchanged `tests/focus.spec.luau`, `navigation_groups.spec.luau`, `focus_structural.spec.luau`, `focus_skip.spec.luau`, `paradigm_table.spec.luau` | suite | PASS_AUTOMATED |
| **TD-3** | Tab and the arrows walk the **same set**: everything the arrows skip (hidden, disabled, non-focusable, retiring, losing adaptive candidates, live focus-skip predicates) Tab still skips, through the same predicates | Traversal grows a second membership source and the two disagree the first time a node is hidden — the exact defect constitution §9 names | E1 | same | suite | PASS_AUTOMATED |
| **TD-4** | **Every** focusable Grip traverses in document position — the rule is "a Grip", never "a Grip used for X" (director decision TDN-1) | A Grip's Tab position depends on why it is focusable, which is a second rule to explain and to test. The shipped focusable Grips are `newSlider`'s track and `newRating`'s strip; a bare `UI.Grip{ focusable = true }` covers the general case | E1 | same | suite | PASS_AUTOMATED |
| **TD-5** | `traversalPriority = n` moves one control without redeclaring the focus map: sort key is `(priority, document position)`, default `0`, negative pulls forward, positive pushes back | The priority is treated as an absolute index, so mixing it with document position gives an order nobody can predict | E1 | same | suite | PASS_AUTOMATED |
| **TD-6** | Two controls at the same `traversalPriority` stay in document order relative to each other | The sort is unstable, so equal-priority controls swap between presses or between runs | E1 | same | suite | PASS_AUTOMATED |
| **TD-7** | A consumer-supplied `present({ navigationGroups = … })` traverses in **exactly** its declared order — the framework adds no opinion | The rank is synthesized for a map the framework did not derive, silently reordering a hand-authored focus map | E1 | same | suite | PASS_AUTOMATED |
| **TD-8** | `traversalPriority` refuses a non-number and refuses a reactive value, naming item, field, problem, fix, and legal set (constitution §4) | A typo'd or bound priority is silently ignored, which §4 calls the defect | E1 | same | suite | PASS_AUTOMATED |
| **TD-9** | `handle.focusOrder()` returns a frozen, deterministic dump carrying `schema = "luauui-focus-order/1"`, the resolved **traversal** order with each entry's priority and live eligibility, **and** the navigation groups — the two readings side by side | The dump reports one reading, so it cannot show that traversal and the arrows differ, which is the whole diagnostic value | E1 | same | suite | PASS_AUTOMATED |
| **TD-10** | `handle.focusOrder()` is safe to call after the surface is dismissed/disposed — it returns an empty map with its schema rather than throwing | A debug overlay that outlives its surface crashes the client it was added to diagnose | E1 | same | suite | PASS_AUTOMATED |
| **TD-11** | Traversal order survives structural churn: rows mounted/unmounted between presses re-rank on the next press with no stale path and no dropped control | The rank map is computed once at present and drifts from the order it sorts | E1 | same | suite | PASS_AUTOMATED |
| **TD-12** | Modal and transient-popup scopes traverse in document order too, and still trap and restore | The rank reaches the base screen only, so a modal keeps the old deferral with nothing to see | E1 | same | suite | PASS_AUTOMATED |
| **TD-13** | Raw `Tab` driven with `VirtualInput` through the real adapter walks the `keyboard_navigation` fixture in document order — the sixteen-press log above becomes `Actions/Reset → Count/Dec → Count/Inc → Volume/TrackHost/Track → List/Row1 … List/Row12` | A headless order assertion proves the decision, never that the running adapter's focus ring follows it | E3 | `tools/studio/device_matrix.luau` mode `keyboard` + gallery scenario `keyboard_navigation` | `studio/traversal.json` + `studio/td13-fixture.png` | PASS_AUTOMATED |
| **TD-14** | The `handle.focusOrder()` dump taken **live in Studio** matches the observed focus log press for press | The dump is computed from the same code path as the behavior and agrees with itself while both disagree with the screen | E3 | same | `studio/traversal.json` | PASS_AUTOMATED |
| **TD-15** | RascalRally is audited against every changed contract, its suite is green at this source, and an affected Studio canary runs in the game's own place | The framework change is compatible in the library and broken at the one live consumer | E1 + E3 | `consumer-impact.md` + game suite + game-place canary | `consumer-impact.md`, `studio/traversal.json` row `TD15-consumer-canary` | PASS_AUTOMATED (headless + audit) / **PENDING** (game-place canary) |
| **TD-16** | The Step 8 debt folded into this stage is cleared: the three missing doc entries exist, the false avatar-priority numbers are corrected, and both stale gate checks (a renamed test name, the suite floor) are real again | The stage ships a green gate that is green because two of its checks stopped matching reality | E0 + E1 | `tools/gate.sh desktop-keyboard-navigation` + `check_docs_cli` | `gate.json`, `step8-debt.md` | PASS_AUTOMATED |
| **TD-17** | A focused Slider shows a visible focused state on its thumb, at the same ring weight every other control gets | The control declares `focusVisual = "none"` (the adapter must not paint it) and then paints something nobody can see — focus appears to vanish for one Tab press | E1 + E3 | `tests/keyboard_navigation.spec.luau` + Studio instance dump | suite, `studio/traversal.json` row `TD17-slider-focus-affordance`, `studio/td17-slider-focused.png` | PASS_AUTOMATED |
| **TD-18** | The surface takes the keyboard on the first tap on UI and gives it back on a tap outside it | A surface that claims Tab and Space can never let go, so the keyboard is captured for the rest of the session and the avatar underneath is deaf | E1 + E3 | `tests/keyboard_navigation.spec.luau` + real Studio clicks | suite, `studio/traversal.json` row `TD18-engage-and-resign` | PASS_AUTOMATED |
| **TD-19** | A surface paints a focus ring only while it actually owns input — a passive HUD paints none, engaging brings it up, resigning takes it away | The ring says "the keyboard is here" while every key goes to the avatar, and nothing can clear it because a passive surface never sees the click that should | E1 + E3 | `tests/keyboard_navigation.spec.luau` + live instance dump | suite, `studio/traversal.json` row `TD19-ring-follows-ownership`, `studio/td19-no-ring-when-passive.png` | PASS_AUTOMATED |
| **TD-20** | A surface declares where focus first appears: `initialFocus` = `"first"` (default), `"none"`, or a named control — and a typo'd id is refused rather than silently becoming "first" | Focus placement is the framework's guess on every surface, and an author who wants none, or wants a specific control, has to fight it after the fact | E1 + E3 | `tests/keyboard_navigation.spec.luau` + live drive against the real adapter | suite, `studio/traversal.json` row `TD20-initial-focus-and-release` | PASS_AUTOMATED |
| **TD-21** | When a surface is dismissed it gives focus up — identity, input, **and paint** — including while its exit transition is still playing | The view is gone and something on it still wears a focus ring, on a surface that has already stopped taking input | E1 | same | suite | PASS_AUTOMATED |
| **TD-22** | A control that paints its **own** focused state (a Slider's thumb) releases it when the surface resigns | The adapter's ring obeys the ownership rule and a control-painted one does not, so the UI looks focused while every key goes to the avatar | E1 + E3 | `tests/keyboard_navigation.spec.luau` + live click on the world | suite, `studio/traversal.json` row `TD22-self-painted-ring-releases`, `studio/td22-slider-releases.png` | PASS_AUTOMATED |
| **TD-23** | A **passive** surface defaults to no initial focus; engaged-open screens and modals still default to their first focusable | A HUD that owns no input until it is touched still claims focus on mount | E1 | same | suite | PASS_AUTOMATED |
| **TD-24** | An engaged HUD resigns on a click outside its content **wherever** that click lands, and gives back the ring, Tab/Space **and** the Adjust keys | Modal-dismissal forgiveness is applied to a cheap reversible resign, so on a surface holding a full-width control almost no click can release it — the UI keeps the keyboard with nothing on screen to explain why | E1 + E3 | `tests/keyboard_navigation.spec.luau` + live click at the exact failing point | suite, `studio/traversal.json` row `TD24-resign-has-no-forgiveness-zone`, `studio/td24-resign-near-content.png` | PASS_AUTOMATED |
| **TD-P1** | A person sits in front of the `keyboard_navigation` fixture and tabs through it, and the order reads as the form reads | Every instrument in this stage measures the order it was told to expect; the defect it exists to fix was found by a human and not by any of them | E5 | `review-packet.md` TD-P1 | director review, 2026-08-03 | **PASS_HUMAN** |
| **TD-P2** | Tab traversal on a **physical** keyboard against a real client, inheriting Step 8's open rows (DK-P1/DK-P2, DKN-1 players list, DKN-2 TextBox suppression) | Studio cannot produce the real device path; Step 8's open rows do not close by being inherited | E4 | `review-packet.md` TD-P2 | review result | PENDING_PHYSICAL |

---

## Human review — TD-P1, closed 2026-08-03

The director played the `keyboard_navigation` fixture in the gallery place and
approved **both** questions the review packet asked:

1. **Does the slider's focus ring read at a glance?** Yes. (The measurement said
   2px opaque accent on a dark thumb; only a person could say it is legible.)
2. **Does tabbing through the form feel like reading the form?** Yes — the slider
   is reached in the position it occupies on screen.

Verbatim: *"both feel good."*

This closes the E5 row and **only** that row. It is a Studio review on a desktop
window: it does not speak for a physical device, which is TD-P2 and stays
`PENDING_PHYSICAL`.

## What this stage explicitly does not claim

- **A second focus system.** The rank is a **sort key on the one order**, never a
  source of membership. `graph.traverse` still takes its members from
  `allIds(scope)` and its eligibility from the same predicate the arrows use. A
  scope with no rank map traverses exactly as it did before this stage.
- **Any change to directional navigation.** `navigateDirection` never reads the
  rank. TD-2 exists to keep that honest.
- **A traversal position that changes at runtime.** `traversalPriority` is
  construction-only. Making it reactive later is a compatible widening; the reverse
  is not, so the narrow default ships first.
- **That focus identity should follow the ring.** A resigned surface keeps its
  logical focus path on purpose — everything that follows focus (keep-visible, the
  drag aim, the selection bridge) depends on it, and re-engaging must resume where
  the player left off. TD-22 releases the PAINT, not the identity.
- **That the slider's focused treatment is the RIGHT design.** TD-17 fixes a ring
  nobody could see; whether an accent ring on the thumb is the best affordance for a
  value control (versus a glow, a thickened rail, or a moved readout) is a design
  question the director's next pass can answer. The measurement only says it is now
  visible and consistent with every other control.
- **Type-ahead, Home/End, PageUp/PageDown.** Still the named parity gaps Step 8
  left; out of scope here.
- **Step 8's environment-blocked rows.** DKN-1 (the engine will not synthesize Tab
  while the CoreGui players list is enabled) and DKN-2 (keyboard input is
  `gameProcessed` while a TextBox holds focus) are inherited unchanged, not
  reopened. TD-P2 carries them.
- **The end-to-end key drive after `keyboardNavigation` made surfaces sink.** Step 8
  left this unverified after three consecutive `execute_luau` timeouts. TD-13 is a
  fresh attempt in a fresh session; if it times out again it lands as
  `FAIL_ENVIRONMENT` with the procedure, not as a product claim.
