# SwiftUI parity round 2 — mission brief

The binding, full-length statement of the mission. The `/goal` prompt is a summary
and points here; where the two differ, this file wins.

Scope: `withAnimation`, layout vocabulary, indicators & controls, examples, a
parity-doc rewrite, and test-suite efficiency.

## Context — read these first, in order

1. Root `CLAUDE.md` — note the "Facet and Rascal Rally move together" rule; it binds every phase below.
2. `GameStudio/ENGINEERING.md` and `GameStudio/MODELS.md`.
3. `GameStudio/ui/Facet/docs/reference/swiftui-parity.md` — current parity inventory and its verdict taxonomy (Covered / Partial / Composable / Missing).
4. `GameStudio/ui/Facet/docs/plans/swiftui-parity-next.md` — the governing roadmap. This mission implements slices of investments 5, 6, 7, and 9 and closes gaps that doc already names (`withAnimation`, `layoutPriority`, container-relative conditions, sensory feedback).
5. `GameStudio/ui/Facet/docs/lessons/` — skim titles; read any that touch the solver, perf, or gates before the relevant phase.

All framework work happens in `GameStudio/ui/Facet/`; consumer work in
`games/RascalRally/` ships in the same phase as the framework change that
requires it. Tests: `./run-tests.sh` from the Facet folder (~3.8k cases; keep
green). Gates: `tools/lune/gate` via `tools/gate.sh <phase>`;
`tools/prior_gates.sh` re-runs predecessors. When any check greps suite output,
match `✓` lines exactly — a grep that can't fail proves nothing.

## Decisions already made — do not re-litigate

- `withAnimation`: implement, at the presentation/paint layer (see Phase 1 constraints).
- LazyVStack/LazyHStack: thin authoring sugar over the existing virtualized collection substrate. Do NOT build a second virtualizer.
- Grid/GridRow: add a SwiftUI-style aligned-column grid API without breaking existing `UI.Grid` callers.
- Indeterminate progress: yes — both a bar mode and a circular spinner.
- Label: audit against SwiftUI and close only gaps a real scenario needs (YAGNI).
- `sensoryFeedback`: a modifier that emits through the existing semantic feedback bus. Facet still plays nothing itself. One opt-in client haptics adapter, default off.
- Table: add pointer double-click primary action; verify/finish modifier-key multi-select.
- `layoutPriority`: implement (it is already on the roadmap, investment 6).
- `containerRelativeFrame`: implement a scoped form (axis + fraction, count/span for paging) measured against the nearest container viewport, not the immediate parent.
- buttonStyle/toggleStyle/pickerStyle protocols: DO NOT implement. The roadmap already decided native Roblox StyleSheets + theme packages own visual styling. Document the mapping in the parity doc instead.
- Parity doc: rewrite as one fresh coherent draft, not a patch set.
- Test suite: measure first, add a fast tier, consolidate only with mutation-proof, rendered-canary proposal only (no build without approval).

## Standing quality bar (every phase)

- TDD. Full suite green at each phase end; no skipped tests.
- New interactive behavior gets a four-input proof (pointer, touch, keyboard, gamepad) and a conformance-registry entry.
- All motion honors reduced motion; pick decorative-vs-informational deliberately and write it down.
- Player-visible text survives ~1.4x pseudo-localization expansion — wrap or auto-fit, never clip.
- Blueprint schema stays strict: every new public property registered; unknown properties still rejected; exported Luau types updated.
- Every new public API appears in at least one gallery scenario that `examples_gallery.spec` executes headlessly.
- Rascal Rally rider: each phase, inspect affected callers; update or add game-side compatibility test/evidence proving the live consumer is current. No game behavior change without separate authorization.
- Phase end: dispatch fresh-context verifier subagents — `facet-architecture-verifier` every phase, `facet-reactive-runtime-verifier` for Phase 1, `facet-phase-gate-verifier` at each milestone — and fix findings before moving on.

## Showcase rule — new content must be reachable in-experience

This applies to Phase 4 and to any later change that adds or renames an example
or scenario. A demo that needs a workspace-attribute edit plus a republish to
reach is NOT shipped.

The showcase place already switches both the demo and the theme in-game
(`examples/gallery/client/demo_picker.luau`, `theme_picker.luau`). So:

1. Register scenarios in the explicit ordered list `ORDER` in
   `examples/gallery/scenarios/init.luau` (unknown names fail loudly — good).
2. Register anything a human should be able to pick from the in-experience
   picker in `demo_picker.DEMOS` in `examples/gallery/client/demo_picker.luau`
   — `{ id, title, blurb, kind = "fixture" | "example", module }`. Keep the
   catalogue order deliberate and blurbs short enough for a 360px phone.
3. Update `tests/gallery_demo_picker.spec.luau` (the picker model is pure and
   asserted there) and `tests/examples_gallery.spec.luau` (headless execution).
4. Rebuild the places: `tools/build_places.sh` from the library root. It emits
   `examples/places/Facet-Showcase.rbxl` (plus the per-example places and the
   performance lab) using `rojo build` only — it never publishes. Commit the
   rebuilt `.rbxl` so the checked-in showcase is current.
5. Device canary: at least one compact view including the 320x640 sweep, driven
   through the in-experience picker, not through an attribute.

## Phase 0 — verify the map (cheap)

The current-state claims below came from a scout pass; confirm each in source before building on it:

- `ProgressView` is determinate-bar only (`src/controls/progress_view.luau`).
- `Label` exists with titleAndIcon/titleOnly/iconOnly presentations (`src/controls/label.luau`).
- Table selection: confirm whether Shift-click ranges and Cmd/Ctrl-click toggles are actually shipped or were deferred ("Phase B") — record the truth, it scopes Phase 3. **The two scouts disagreed on this one. Do not guess; read the source.**
- No `layoutPriority`, no `containerRelativeFrame` (only percent-of-parent dims), no Lazy stacks, no GridRow, no `withAnimation` (motion animates values, not property changes; structural transitions exist in `src/render/transitions.luau`).
- Feedback bus taxonomy in `src/present/feedback.luau`.

Then write `docs/plans/swiftui-parity-round2.md`: one short design section per
phase. Have an opus subagent adversarially review the Phase 1 (`withAnimation`)
design before any implementation.

## Phase 1 — withAnimation [Milestone M1]

Goal: `UI.withAnimation(classOrSpec, fn)` — state changes applied inside `fn`
animate their visual consequences.

Non-negotiable design constraints:

- The architecture principle stands: motion drives presentation, never solver geometry. `withAnimation` tags the transaction; the renderer/presentation layer animates from the previous committed frame to the new one (position, size, transparency, adapter-owned paint). Solver output stays exact and instant; hit-testing and focus use solved geometry, never in-flight visuals. Prior art: the row-actions presentation slide.
- Interruption re-targets with velocity preservation (existing spring behavior). Deterministic completion and cancellation; `onSettle`-style hooks.
- Nested/overlapping `withAnimation`: define the rule (innermost wins per changed value is the default position), document it, test it.
- Structural insert/remove inside `withAnimation` defers to the existing transition system — do not build a second one.
- Reduced motion, instance-recycling interplay, and teardown neutrality all tested.

Perf evidence: run the perf lab scenes before/after; budgets hold; the off-path
cost of the feature (no animation active) must be ~zero per the five PURE rules.

Escalation: if something genuinely cannot work without solver participation,
stop and present the conflict with two options — do not erode the principle
silently.

## Phase 2 — layout vocabulary [M1]

- Stacks parity audit: HStack/VStack/ZStack vs SwiftUI (alignment options, spacing semantics, the ZStack items the parity doc marks Partial). Close what is cheap; document intentional divergences.
- GridRow: rows declare cells, columns align across rows, cell span supported. Extend `UI.Grid` or add a sibling container — choose whichever leaves existing Grid callers untouched.
- LazyVStack/LazyHStack as wrappers over the virtualization substrate. If the substrate cannot host a general lazy stack cheaply, document the gap precisely and stop — that is an acceptable phase outcome.
- `layoutPriority`: solver-integrated compression order — when the main axis is short, lower-priority children compress/truncate first. Define interplay with hug/fill/minMax dims and ViewThatFits. Ensure solver memo keys cover the new input (the cache key must cover what it caches).
- `containerRelativeFrame`: scoped form per the decisions above.

Perf: incremental layout must stay incremental; run the layout perf scenes
before/after.

## Phase 3 — indicators, label, feedback, table clicks [M2]

- ProgressView indeterminate bar + Spinner control. Use existing theme slots; no new styling system. Decide the reduced-motion policy for a loading indicator deliberately (it conveys information) and document it.
- Label: close audited gaps only where a gallery scenario or reference app needs them.
- `sensoryFeedback(bp, { trigger, event })`: on trigger-value change, emit the named semantic event through the presenter feedback bus. Add one opt-in client adapter mapping bus events to Roblox haptics (verify current HapticService/HapticEffect API support on touch and gamepad; degrade silently where absent). Default off.
- Table: (a) finish or confirm modifier-key selection per Phase 0 findings; (b) `onPrimaryAction` — double-click on pointer, Return on keyboard, A/Cross on gamepad, single activate on touch (document that divergence). Four-input rule applies.

## Phase 4 — examples [M2]

Update existing gallery scenarios where natural (playlist table for table
clicks; motion scenario for `withAnimation`; `adaptive_controls` for
`layoutPriority`/`containerRelativeFrame`; a loading scenario for indeterminate
progress + spinner + `sensoryFeedback`). Add new scenarios only where no natural
home exists. Every new/changed scenario runs headlessly in
`examples_gallery.spec`, plus a Studio device-matrix canary for at least one
compact view — include the 320x640 sweep.

Then apply the **Showcase rule** above in full: register, test, rebuild
`examples/places/Facet-Showcase.rbxl` with `tools/build_places.sh`, commit it,
and prove the new content is selectable in-experience.

## Phase 5 — parity doc rewrite [M3]

Rewrite `docs/reference/swiftui-parity.md` from scratch as one coherent draft.
Keep the verdict taxonomy and the honest-summary section. Every claim carries
evidence (test file or source path). Explicitly record this round's decisions:
no *Style protocols (native StyleSheets own paint), Lazy stacks are
virtualization sugar, `sensoryFeedback` is a semantic bus event. Update the
milestone/status table in `swiftui-parity-next.md` to match reality.

## Phase 6 — test-suite efficiency [M3]

In order:

1. Measure: time every spec file; publish a slowest-20 table in the plan doc.
2. Tier: add a fast tier (target <25% of full runtime; smoke + core + the areas this mission touched) for inner-loop use. Full suite remains the gate default. Nothing deleted at this step.
3. Consolidate: audit overlap (matrix-expansion specs, near-duplicate layout specs). Merge or parameterize only where a mutation test proves coverage is preserved — intentionally break the guarded code, watch the surviving test fail, restore. A check must bite before you trust it.
4. Rendered tests: a one-page PROPOSAL (no implementation) for a small rendered-canary set in Studio built on the existing `tools/studio/matrix_capture.sh` + `tools/check_matrix_rows.py` path — which scenarios, how many captures, gates-only cadence. Present for approval.

## Subagent routing

Follow `GameStudio/MODELS.md`. Defaults: haiku for exploration/searches, sonnet
for mechanical implementation, test-writing, and doc drafting from an approved
design, opus (main/you) for design, solver/renderer integration, and review. One
task per subagent.

## Milestones

M1 = Phases 1–2, M2 = 3–4, M3 = 5–6. At each milestone: full suite green,
relevant gates pass, `prior_gates.sh` re-run clean (watch for a stale lock from
an earlier aborted run — clear it, don't work around it), fresh-context RED-TEAM
`code-reviewer` dispatch, confirmed findings fixed, report per
`GameStudio/STUDIO.md`.
