# ADR-0013 — Input auto-wiring: the presenter composes a control's four-input story from mounted contributions

Date: 2026-07-21 · Status: **Accepted** (finalized by the lead after all work packages landed) · Spec: ui_todo.md §0, design §9/§12.1 · Fixes: `artifacts/input-adaptation-audit/wp-a-framework.md`, `wp-b-composites.md`

## Context

ui_todo §0 (the director's standing principle): *every control must ship the right
interaction for ALL four input classes — pointer, touch, keyboard, gamepad — WITH NO
CONSUMER WIRING.* The audit found the opposite: the presenter auto-*builds* every screen's
action context and bindings (Navigate/Activate/Cancel across keyboard + gamepad) but routes
everything to opaque consumer callbacks (`opts.onActivate` / `navigationGroups` /
`onNavigateIntercept` / `onFocusNav` / `onGeometry` / `keepVisibleOffset`). Every consumer
re-plumbs the same six hooks by hand (canonical hand-wiring:
`examples/gallery/examples/02_playlist_table.luau:273-316`). Mounting a Table or TextInput
yielded no keyboard/gamepad story on its own; nothing read a control's declared behavior.

## Decision

Introduce an **input-contribution seam** at the presenter ⇄ mounted-control boundary.

1. **Contribution bundle.** A composite attaches an input-contribution bundle to its
   blueprint ROOT node via `src/input/contribution.luau` (`attach(rootBlueprint, bundle)` /
   `read(node)`). Bundle shape (all optional): `{ focusGroups(rootNode) -> NavigationGroup[],
   handleActivate(path, meta) -> boolean, navigateIntercept(direction) -> boolean,
   focusMoved(path), syncGeometry(rectOf), keepVisibleOffset: Readable<number>?,
   bindActionSystem(actionSystem) }`. The bundle rides a single reserved prop
   (`__inputContribution`) as a plain (non-Readable) value, so `mount` copies it verbatim
   onto the mounted node and it survives — and, being neither a Readable, a layout input, a
   `BINDING_PROP`, nor a named render/style prop, it stays entirely out of the
   layout / render / mount-dump paths (the renderer only pushes `BINDING_PROPS` +
   explicitly-named props to the adapter).

2. **Presenter auto-composition.** At `makeHandle` (and re-derived each `refresh`) the
   presenter walks the mounted tree, collects the bundles in document order, and composes:
   - **navigation groups** — absent `opts.navigationGroups` + ≥1 contribution with
     `focusGroups` → an auto groups function (contributions emit their groups at their tree
     position; standalone focusables between them form flat vertical groups; grips defer
     last), re-derived on every refresh. No contributions → today's flat ring, unchanged.
   - **Activate dispatch** — absent `opts.onActivate`, on tap/Activate at path P:
     (1) `props.onActivate` on the node at P; (2) a `Toggle` whose `value` is a settable
     signal flips (finally implementing contract "Activate flips value"); (3) the
     **longest path-prefix** contribution whose `handleActivate` returns true; (4) no-op.
   - **navigate intercept** — absent `opts.onNavigateIntercept`, chains contributions'
     `navigateIntercept` (first true consumes).
   - **focus-move report** — absent `opts.onFocusNav`, routes to the longest-prefix
     contribution's `focusMoved`.
   - **geometry** — feeds every contribution's `syncGeometry` at initial render +
     refresh, and `opts.onGeometry` too when present. The one seam here that is
     ADDITIVE rather than an override: solved rects are a notification, so one
     listener's interest never cancels another's (a consumer asking where its own
     node landed must not silently disable a composed Table's scroll-into-view).
   - **keep-visible** — absent `opts.keepVisibleOffset`, observes ALL contributions'
     `keepVisibleOffset` readables and applies the **max**.
   - **action-system binding** — always calls every contribution's `bindActionSystem`
     (idempotent).

3. **New leaf prop.** `UI.Button`/`UI.Toggle` gain an `onActivate(path, meta)` prop (the
   per-node effect the presenter dispatches to). It flows through the existing static-prop
   path (no blueprint validation change; no adapter write).

4. **Wired composites.** TextInput (`focusGroups` = its one-field group, `handleActivate`,
   `syncGeometry`, `keepVisibleOffset`, `bindActionSystem`), Table (`focusGroups` =
   `buildFocusGroups`, `handleActivate`, `navigateIntercept` = `handleGrabNavigate`,
   `focusMoved` = `handleFocusMoved`), PopupButton (`handleActivate`), VirtualList (an empty
   bundle — it advertises no input capabilities yet; a later WP owns its story).

## Key design points

- **Per-opt override (hard back-compat rule).** Every consumer-passed `present()` opt wins
  over its auto counterpart, per-opt, so all existing consumers and the full suite stay
  green unchanged. TextInput injects `spec.actionSystem` (back-compat) *and* is bound by the
  presenter; a first-writer guard (`actionSystemRef`) means the edit-mode sink context is
  never double-created.
- **`navigationGroups = false` (new sentinel).** Forces the flat ring, ignoring
  contributions. Needed by a legacy flat-list consumer (e.g. `tests/table.spec.luau`'s
  harness) whose story is grip-in-ring, wrap-around, and shift+Navigate reorder — behaviors
  the Table's grouped `buildFocusGroups` deliberately does not express (it omits the header
  grip and routes reorder through grab mode). Grouped nav is the correct default for a bare
  Table (ui_todo §0); `false` is the explicit opt-out.
- **Longest-prefix dispatch.** Activate and focus-move route to the contribution whose root
  path is the longest path-prefix of the target; ties resolve deterministically by prefix
  length. This lets nested composites coexist and matches how the controls already scope
  their own path patterns.

## Consequences

- Mounting Button/Toggle/TextInput/Table on a bare screen (zero `present` opts) yields the
  full pointer/touch/keyboard/gamepad story (`tests/auto_input.spec.luau`, +15 cases; suite
  377 → 392).
- Grip resize (`handleAdjust`) and shift-reorder (`handleReorderNav`) are intentionally
  OUTSIDE the bundle shape — they stay `opts.onAdjust` / `opts.onReorderNav` driven: the
  Adjust action binds horizontal keys only when a screen opts in, so a non-modal screen never
  shadows gameplay arrow/bumper bindings (`presenter.luau`, Adjust block). Recorded as a
  justified exception in the audit disposition.
- The examples still hand-wire (out of scope here); a later WP simplifies them to zero opts.
- VirtualList's empty contribution was a placeholder at decision time; the follow-up WP
  (same day) landed its full four-input story (`tests/virtual_list_input.spec.luau`) —
  wheel/touch-pan scroll, windowed focus groups with scroll-into-view, Return/ButtonA
  activation — all through this seam.

## Enforcement and siblings (landed the same day)

- **Per-control-per-input conformance** enforces this ADR permanently:
  `tests/conformance/controls_registry.luau` rows declare `inputProofs` per input class
  (explicit `false` for non-interactive rows) and `tools/lune/check_registration.luau` fails
  any interactive control that cannot cite a registered device-true case for all four
  classes — a control can no longer pass while mouse-only. The scaffold stamps new controls
  with a contribution stub + four failing per-class spec cases.
- **ADR-0014 (first-responder model)** builds on this seam for real avatar games: passive
  HUD surfaces, engage/resign transitions, the 3000+ engaged-modal band, and the
  UI-only-place scoping of `gamepad_contention.disableLegacyControls` (director direction
  2026-07-21; `docs/research/2026-07-21-first-responder-platform-research.md`).

## Alternatives considered

- **Editing `table.spec` to grouped nav** instead of the `false` sentinel — rejected: it
  would drop real coverage (grip-resize reachability, shift-reorder, wrap-around) that the
  grouped path does not express. The `false` opt-out keeps that coverage and makes the
  harness's flat-ring contract explicit.
- **Hoisting the bundle to a dedicated mounted-node field** (editing `src/mount.luau`) —
  rejected as more invasive than a reserved, inert static prop that the render/layout/dump
  paths already ignore.

## Follow-up — the remaining framework-layer screen cells (WP-1/2/3/4)

The contribution seam above closes the composite cells. Four framework-layer cells that a
PLAIN screen (no contributions) still leaves on `CW`/`MISSING` are closed here, all in
`src/present/presenter.luau`, all test-first (`tests/auto_input_screens.spec.luau`).

1. **WP-1 — auto navigation groups from LAYOUT STRUCTURE.** The auto-groups discovery (Decision
   2's "navigation groups" bullet) is extended: when no `opts.navigationGroups` and **no**
   contribution provides `focusGroups`, the presenter now inspects the mounted LAYOUT. If the
   tree contains an `HStack` or `Grid` with ≥2 focusables it derives groups (`layoutGroups`,
   re-run each refresh): an `HStack` of focusables → one horizontal group (`entry="nearest"`,
   uncontained so stacked rows read as a loose column-preserving 2D board via fallthrough); a
   `Grid` → per-row horizontal groups linked by declared `up`/`down` exits and `containment=true`
   (`entry="nearest"` preserves the column; left/right stay in the row) — real grid 2D nav.
   Standalone focusables between blocks collapse to vertical groups; grips defer last, unchanged.
   The **engage gate** (`hasHorizontalStructure`) is load-bearing: a screen with no horizontal
   container/grid keeps the byte-identical FLAT ring (wrap-at-ends), so the many tests that
   depend on flat-ring behavior are untouched. This moves the FocusGraph keyboard/gamepad
   "2D groups CW rider" for plain layout screens to AUTO (e.g. a Grid tile board / HStack row
   gets D-pad 2D nav with zero opts). Grid column count reads `props.columns`; a
   `minColumnWidth`-only Grid (count is layout-solved, unknown to the focus derivation) falls
   back to a single row — a documented limitation, acceptable until a solved-geometry seam exists.

2. **WP-2 — modal outside-tap = Cancel.** `presentModal` gains `opts.outsideTapCancel`
   (default **true**). While ≥1 modal is presented, `onNodeTap` checks the TOP modal first: a
   tap whose path is not a segment-aligned prefix of the top modal's blueprint id (a) never
   routes to a lower handle and (b) dismisses the top modal (platform sheet dismiss). This
   fixes the audited clickthrough (a tap on the base screen while a modal was up routed to the
   base handle). Back-compat is per-modal and per-scrim: a scrim/close affordance living INSIDE
   the modal blueprint is owned by it and routes normally; `outsideTapCancel=false` restores the
   legacy clickthrough. Moves Presenter modal pointer/touch Cancel from `CW` toward AUTO for the
   common "sheet over a screen" shape (a bespoke visible scrim is still the consumer's to draw).

3. **WP-3 — modal keyboard Cancel (see Justified exceptions).** No new key binding — Escape is
   engine-reserved. The modal focus ring already reaches every focusable, so a declared close
   Button is keyboard/gamepad-activatable end-to-end; a regression test proves it
   (`deviceKey "Return"` on the navigated-to close button dismisses the modal and restores
   focus). The one framework-layer `MISSING` cell stays MISSING **by platform necessity** and is
   recorded as a justified exception rather than closed with a substitute key.

4. **WP-4 — `Facet.inputHint(core, env, action)`** (`src/input/hint.luau`). A reactive hint
   memo tracking `env.preferredInput` and `action.preferredBinding(preferredInput)` (displayName
   → keyCode/uiButton → `""`). It is the minimal affordance for the audit's "hint text MISSING"
   sub-affordance: consumers mount `UI.Text{ text = Facet.inputHint(...) }` instead of
   hand-deriving a memo. It **never** injects visible UI and never auto-mounts anywhere — purely
   a label source; the caller owns and disposes the memo. A preferredInput flip re-labels the
   same Text node with no remount (reuses the ADR-0004 phase-1 no-remount property).

## Justified exceptions (framework Cancel/back on keyboard)

Not every input-class cell can be FRAMEWORK-AUTOMATIC; one is a hard platform limit and is
recorded here rather than papered over:

- **Modal keyboard/mouse Cancel via a reserved key is impossible.** `Escape` is permanently
  bound to the Roblox CoreGui menu — the engine VirtualInput refuses it outright (verified live
  2026-07-19, **D1**; `presenter.luau` comments the deliberate non-binding). The framework does
  **not** invent a substitute Cancel key (any choice would shadow gameplay or feel arbitrary).
  The **sanctioned modal dismissal affordances** are therefore:
  - **gamepad** — `Cancel` → `ButtonB`, AUTO (dismisses the top modal; PS Circle maps to ButtonB);
  - **pointer/touch** — outside-tap dismiss (WP-2, default on), plus any consumer scrim;
  - **keyboard** — a **focusable close affordance** inside the modal (a "Cancel"/"Close" Button),
    reachable by the auto focus ring and Activate-dismissable via `Return`/`ButtonA` (WP-3).
  A keyboard-only user always has a path out of a modal (navigate to the close button, Return);
  it just is not a single reserved key, and cannot be, per D1. Screens that present a modal
  should always include a visible close affordance for exactly this reason.
