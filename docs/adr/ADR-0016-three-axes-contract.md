# ADR-0016 — The three-axes contract: paradigm adaptation is a per-control conformance obligation, not a Table-only pattern

Date: 2026-07-21 · Status: **Accepted** · Spec: input-paradigms expansion (prompt.md "Expansion: input paradigms"), design §8/§9 · Design authority: `artifacts/input-paradigms/affordance-matrix.md` (archived privately) (incl. its build-round Amendments) · Builds on: [`ADR-0013`](ADR-0013-input-auto-wiring.md) (contribution seam), [`ADR-0014`](ADR-0014-first-responder.md) (first responder), [`ADR-0015`](ADR-0015-interaction-classes.md) (interaction classes)

## Context

ADR-0015 established that structural affordances derive from the **live class set**
(`interactionClasses`), not `preferredInput` alone — and proved it on the Table's auto
Edit/Done toggle. But "the right interaction for every class" was, at that point, a
Table-shaped pattern held together by that control's own specs and reviewer diligence.
Nothing *structurally* required a new control to ship a hover layer on pointer, a
naked-pan-scroll on touch, an Adjust idiom on keyboard/gamepad, a defined outcome when a
device arrives mid-gesture, or a legible focus state across a room. The existing
conformance machinery (ADR-0013's `inputProofs` + `check_registration`) enforced only
**reachability** — that every verb *fires* on every class. A control could satisfy every
`inputProofs` cell and still ship a mouse-only reorder, no hover, a hairline focus ring at
3 m, or a drag that wedges when the mouse is unplugged. The affordance matrix
(`artifacts/input-paradigms/affordance-matrix.md`) named this the **paradigm axis**, the
third of three independent axes every control must satisfy:

1. **UI (layout)** — how the tree arranges per size class / `distanceProfile` (`UI-ADAPT-001`).
2. **Input (reachability)** — every verb reachable on every live class (`UI-INPUT-001/002`).
3. **Paradigm (structural idiom)** — the *shape* each class expects: direct-drag vs.
   grab-mode vs. grip; hover vs. focus ring; naked-pan vs. wheel; and the hot-switch and
   ten-foot behaviors. Previously unowned by any requirement or checker.

The matrix's Amendments record that the build round **closed every per-class GAP** (bare-Table
keyboard/gamepad resize, PopupButton outside-tap/ButtonB/focus-trap, Thumbstick1 Navigate,
the four ten-foot consumers, hover as a gated seam). The remaining risk was regression and
drift: without a conformance obligation, the next control — or a later edit — could quietly
reintroduce a paradigm gap. This ADR makes the paradigm axis a **contract every future
control inherits by construction**.

## Decision

**1. Three requirement IDs.** `UI-PARADIGM-001` (structural affordances per live class),
`UI-PARADIGM-002` (hot-switch CARRY/CANCEL transition semantics), and `UI-PARADIGM-003`
(ten-foot presentation) are added to `requirements.json` with `firstGate: "input-paradigms"`
and the matrix §A/§C/§D/§E as their falsifiable specs — peers of the `UI-INPUT-*` families,
not sub-items of them.

**2. `affordanceProofs` in the conformance registry.** Every row in
`tests/conformance/controls_registry.luau` gains an `affordanceProofs` field, the paradigm
analogue of `inputProofs`. For an interactive control it cites, **per live class**, the
spec case(s) proving that class's structural idiom (Table pointer → direct-drag + wheel;
Table touch → edit-grip + naked-pan-scroll; Table keyboard/gamepad → grab-mode + focus-gated
Adjust; etc.), plus a **`hotSwitch`** entry citing the §C in-flight-transition cases the
control owns (Table: drag/grab CANCEL + edit/grab/pan CARRY; TextInput: text-entry
CARRY/commit) — or explicit `false` for a control with no in-flight state (VirtualList,
PopupButton, Button, Toggle). Non-interactive rows declare `affordanceProofs = false`. Every
cited case must exist verbatim in a registered spec (the same string-search rule as
`inputProofs`), so the proofs cannot rot into aspiration. The proofs are drawn honestly from
the existing green specs — the five build packages' spec files
(`tests/paradigm_table.spec.luau`, `paradigm_popup.spec.luau`, `paradigm_textinput.spec.luau`,
`paradigm_input_axis.spec.luau`, `paradigm_tenfoot.spec.luau`, `paradigm_hover.spec.luau`,
`paradigm_carry.spec.luau`) plus the pre-existing `table`/`table_input`/`virtualization`/
`popup_button`/`text_input`/`auto_input` specs.

**3. Checker refusal.** `tools/lune/check_registration.luau` gains a paradigm block mirroring
its `inputProofs` enforcement (rules a/b/c). It fails: a missing `affordanceProofs` (silent
omission is impossible), `affordanceProofs = false` on an interactive control, an
uncited/unregistered case name, an interactive control missing any class idiom, or a missing
`hotSwitch` decision. Named per-class gaps live in `AFFORDANCE_GAPS` (currently empty — every
matrix GAP is closed) so the rule ships **enforcing** while any future absence stays explicit
and named, never silently weakened. The CLI reports the count of controls proving the paradigm
axis alongside the four-input count.

**4. Scaffold stamps the axis.** `tools/lune/scaffold.luau` now stamps, for a new control: an
affordance-declaration comment block naming the three axes and the per-class idioms to choose;
four failing `<Display> <class> affordance:` spec cases (distinct from the reachability cases);
a `<Display> hot-switch:` stub case (CARRY/CANCEL decision); and a registry row whose
`affordanceProofs` cites those exact stamped names. A new control is therefore born red on the
paradigm axis — the same test-first loop ADR-0013 established for reachability.

**5. The contribution seam is the uniform way in.** The paradigm behaviors ride the same
ADR-0013 bundle, extended this round with the seams that made the matrix's GAP closures
uniform rather than bespoke:
- **`adjustTargets` / `handleAdjust`** — the Adjust verb, bound *dynamically* by the presenter
  only while a declared target holds focus, so a bare screen never shadows gameplay
  arrow/bumper keys off-target (the ADR-0013 hazard that had kept Adjust `opts.onAdjust`-driven).
  This is what closed bare-Table keyboard/gamepad column resize.
- **`handleCancel` / `outsideDismiss` / `transientScope`** — transient-popup parity without
  making the control a modal: gamepad ButtonB close, outside-tap / synthesized-catcher dismiss,
  and focus trap-and-restore. This is what closed the three PopupButton parity GAPs.
Expressing these as optional bundle fields (not new `present()` opts and not modal machinery)
keeps the ADR-0013 rule intact — **mounting a control yields its whole story with zero consumer
wiring** — and keeps the per-opt override back-compat. Hover is likewise an optional adapter
seam gated on the live pointer class.

## Consequences

- The paradigm axis is now regression-proof: `check_registration` refuses any interactive
  control that cannot cite a registered structural-idiom case for all four classes and a
  hot-switch decision, in the same breath it already refuses a mouse-only control. Suite
  564 → 574 at this ADR (7 conformance/scaffold cases added, red-first); `check_registration`
  and `check_boundary` green.
- A fresh-context agent building a control gets all three axes from the scaffold and the
  playbook (`docs/extending/new-control.md` step 2.3) without prior knowledge — the stamped
  affordance cases fail until the idioms are real.
- The consumer story is unchanged and remains "nothing": every paradigm behavior is
  auto-composed from the mounted contribution. `docs/guide/07-input.md` now documents the axis
  for the curious, consumer-first.
- Known limitation (from the matrix Amendments, carried not hidden): intrinsic default text
  sizes do not take the ten-foot multiplier — only explicit `textSize` props do (the
  measure/paint agreement rule); and physical-gamepad / real-analog-axis realization stays on
  the standing `physical-device-confirmation` rider.

## Alternatives considered

- **Fold paradigm proofs into `inputProofs`** (one list per class) — rejected: it conflates
  reachability with idiom, exactly the confusion that let a reachable-but-mouse-only reorder
  pass. Two named axes make "it fires" and "it feels right" separately falsifiable, and let the
  checker report which one a control fails.
- **A prose review checklist instead of registry proofs** — rejected: the whole point of the
  ADR-0013 conformance culture is that a maintainability obligation the checker cannot see will
  drift. Cited, string-searched cases are the only form that survives a later edit.
- **New `present()` opts for Adjust/Cancel/dismiss** — rejected: that reintroduces the
  per-consumer hand-wiring ADR-0013 abolished. The contribution bundle is the single uniform
  seam; the presenter binds Adjust dynamically and synthesizes the dismiss catcher so a control
  gets the behavior by *mounting*, not by asking its caller for opts.
- **Treat the console TV as a fifth device class** — rejected (matrix §D): ten-foot is keyed on
  the *display* (`displaySize == "Large"`), independent of the input class, so a keyboard or a
  pad on a TV both earn it; `PreferredInput` keeps only three values and TV-remote input is a
  deferred, separate `/goal` reusing this same profile.
