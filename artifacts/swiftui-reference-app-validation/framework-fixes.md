# Framework fixes and findings — swiftui-reference-app-validation (RA-7)

Living ledger, updated as proofs land. Two sections: **fixed this stage** (bounded,
compatible, shipped with API/tests/docs/live proof) and **findings** (evidence-backed
follow-on candidates; the proofs ship the declared honest approximation instead).

## Fixed this stage

| Fix | Evidence |
|---|---|
| **Grid measure is now a fixed point of its own report** — the measured width omitted the `minColumnWidth` floor (so a hug parent's re-offer dropped a column and added a row: the 200px shape) and a partial last row reported a trailing gap arrange never paints (the 2px shape). Fixed in the grid measure branch only; 7 new tests incl. a frozen byte-identical guard; mutation-proved both halves; `check_flat_baseline` reports zero rect drift; consumer sweep in the fix report | `tests/grid_measure_arrange.spec.luau`; api.md Grid `minColumnWidth` contract paragraph; minimized repro preserved in the spec |
| **A hug ScrollView now measures the scrollbar its own arrange reserves** — arrange subtracts `scrollBarReserve` from the cross axis when the scroll axis overflows, so a content-hugging shelf reported a cross size it could not reproduce: every chip in ref_wardrobe's category row overflowed by exactly 8px on the live phone row while every headless sweep stayed blind (the fake target publishes no bar thickness — the twin gap is called out in the spec's header). Fixed in the scroll measure branch with the same fixed-point rule as the Grid fix; 5 pins incl. the no-bar and content-fits guards; failing-first on both live shapes | `tests/scroll_bar_measure.spec.luau`; found by matrix row wardrobe/compact-phone-portrait |
| **A Stage never classifies into a decoration slot** — Fantasy Parchment's whole-art `control` recipe painted its paper plate OVER the ViewportFrame (the mannequin vanished; captures wardrobe-parchment-real vs -stage-fixed). The renderer pins `chrome_slots.NO_SLOT` on Stage creation, so no package recipe can cover the scene while stroke/corners modifiers still decorate the box edge; pinned in tests/stage.spec.luau | live A/B captures 2026-08-08; suite 3824 |
| **`UI.Stage` engine-content leaf** (ViewportFrame adoption): schema class, adapter (owned WorldModel + Camera, mediated `setCamera`/`setLighting`/`contentRoot`), `controller.stageHost`, seam-owned authority set (`Ambient`/`LightColor`/`LightDirection`/`CurrentCamera`), headless recording twin, conformance registration, api.md section, +22 tests, 2 mutation proofs | `docs/research/2026-08-08-viewportframe-engine-facts.md`; live E3: Wardrobe place renders + live re-dress + per-frame camera writes (captures wardrobe-live-1..3) |

## Findings (follow-on candidates, ordered by observed cost)

1. **`compactLabel` is construction-only** — hit by two proofs independently:
   a phase-bearing button cannot declare a phase-correct compact form (Glade: a
   pending purchase rendered its idle compact word), and the compact form can
   never follow a live locale flip (Sipworks). Candidate: reactive or per-state
   `compactLabel`.
2. **`newLabel.title` accepts only a literal string** — a localized icon+title
   label cannot bind its title; consumers fall back to bound `UI.Text` and lose
   the icon pairing (Glade §8 affordance; Foyer nav items resolve at build
   locale). Candidate: accept `Bound<string>` like `Button.label` does.
3. **A `Region` form that measures 0×0 at first solve never materializes its
   structural children** — a `ForEach` as a direct Region form stayed empty when
   items arrived later; presents as "the lane silently vanished" (Glade).
   Candidate: a solver diagnostic naming the empty-form condition.
4. **A row-factory error inside `ForEach` during `presenter.refresh()` is
   swallowed** — the same throw at present time is loud (Glade, via a
   `newLabel` throw producing zero rows silently). Candidate: route refresh-time
   factory errors through the same quarantine/diagnostic path as present-time.
5. **`newStepper`'s readout is a memo over the value only** — a locale-bearing
   `format` closure goes stale on locale flip (Sipworks). Candidate: readout
   memo keyed on the format identity too, or a `Bound` format seam.
6. **The presentation channel is path-based** — a screen-level author cannot
   express a per-node "pop" without hardcoding mounted paths; Sipworks' stamp
   pop shipped as a fade for this reason (also: `setPresentationTransform`
   scale is uniform and size animation is motion-authority-forbidden, so the
   fade is the *correct* current answer — the finding is about ergonomics).
7. **Example-drift scan coverage** — `check_example_drift_cli` scans only
   `examples/gallery/examples`; `examples/reference` is not yet scanned, and
   R2's role vocabulary lacks the legal Button `role = destructive|cancel`.
   Lead TODO this stage (scan extension is bounded and lands before gate close).
8. **Scenario-step payload convention is easy to miss** — the Bindable bridge
   takes ONE colon-joined string (`"equip:item-id"`); a two-argument Invoke
   silently drops the payload. Cost: one live-debug round. Candidate: the
   `step` wrapper could error on a non-nil second argument.
9. **Composite controls inside proofs need explicit dispose ownership**
    (`newLabel`/`newTextInput`/`newPicker` in loops) — easy to leak; the
    ownership idiom (`scope:own(control.dispose)`) is applied throughout the
    proofs but is boilerplate a future `ownedBy(scope)` option could fold in.

10. **`controls.popup.triggerHeight` (40) exceeds `controls.table.rowHeight`
    for pointer rows (36)** — no popup menu fits a dense table row; the solver
    reported the 4px overlap on every pointer viewport (Cartwheel §6, row menu
    replaced with an inline button). Candidate: a compact trigger metric or a
    row-hosted popup variant.
11. **Masked/secure text entry is absent** — no secure mode on
    `TextField`/`newTextInput` (engine `TextBox` has no public masking; parity
    §3.6 records the platform half). Cartwheel ships the declared visible
    variant with a permanent on-screen caution. Candidate: engine-capability
    probe + a shadow-value model spike, or a standing recorded exception.
12. **Semantic icon coverage** — the framework icon set is 12 names; a
    namespaced `ns:name` without package art may not draw the documented
    ASCII-safe fallback in practice (Cartwheel measured "resolves to nothing";
    the Foyer/Wardrobe live sessions showed circle buttons reading as text —
    legible, but which fallback actually painted needs one live check).
    Reconcile api.md's claim with measured behavior at the matrix pass.

13. **A `fill`-width ScrollView contributes 0 to a HUG parent's measure** —
    minimized: `HStack{ ScrollView(x, width=fill, 9 chips), circleButton }` in a
    bounded screen solves the row at 52px and the shelf at 0×54 (canvas 624).
    The fill contract says the desired contribution is CONTENT; for a scroll
    node it contributes nothing, so a hug row collapses onto its non-fill
    children and the shelf vanishes. Live cost: the Wardrobe category row
    painted a 0-wide shelf on desktop until the row declared fill width (the
    honest declaration anyway). Candidate: make the fill contribution of a
    scroll node its content extent, capped at the offer.

## Fix 4b (recorded via the Fixed table but named here for the count): namespaced-icon ASCII floor

`package.iconGlyph` now derives a glyph for `ns:name` icon names (known table →
namespace-stripped match → first letter uppercased), and `resolveIcon`'s floor
routes through it — the documented ASCII fallback exists instead of drawing
full labels into 44px discs. Tests: `tests/icon_ns_glyph.spec.luau` (5 cases).
This closes finding 12 below (phase-gate review m-3: the fix had shipped but
the ledger still listed the finding as open and the stage counted "four"
bounded fixes; the true count of bounded fixes this stage is SIX — Stage
NO_SLOT, Grid measure fixed point, ScrollView bar measure, icon ASCII floor,
park-corpse guards, ZStack fill-axis diagnostic).

## Fix 5 (live matrix, 2026-08-08): the corpse-in-the-pool crash

**Found:** driving ref_glade's axes live — install Fantasy Parchment on the
mounted tree, then switch sections: the mount crashed with "The Parent property
of <path> is locked, current parent: NULL". Deterministic; the unthemed control
run of the same navigation is clean, and theme-first-on-an-empty-pool is clean.

**Cause:** the renderer's removal loop visits `handles` in hash order and
`parkEligible` refuses clip hosts, so a host is always DESTROYED — and when the
loop reaches the host before its descendants, engine Destroy propagation kills
the descendants' instances while they still await their own park. Every write
`park` makes is legal on a destroyed instance (`Parent = nil` included), so the
pool collected corpses stamped with the CURRENT chrome epoch; the epoch/hint
gates both passed and `adopt`'s non-nil Parent write threw arbitrarily later,
crashing the mount of an unrelated surface. The theme install matters only
because its metrics change forces a remount wave over a full pool.

**Fix (`src/client/screen_target.luau`):** two guards at seams the park
contract already owns ("park refuses what cannot travel"): `parkEligible`
refuses an instance whose Parent is already nil (a live handle is ALWAYS
parented at park time), and `adopt` pcall-guards the Parent write — the one
seam that can still detect a destroyed instance — refusing the adoption and
restoring the parked identity so the caller's discard tears it down as parked.

**Tests:** `tests/instance_park_corpse.spec.luau` (3 cases, source anchors —
the class cannot execute headless: screen_target is engine-only and the fake
target deliberately models no parenting; anchors follow adaptive.spec's
established pattern). Mutation-proved: deleting either guard reddens its case.
Suite 3830.

**Live A/B:** pre-fix, `navigate → theme:fantasy_parchment → navigate` crashed
on the first section switch (twice, two different instances). Post-fix the same
sequence plus a full four-section sweep under the theme runs clean, 0
diagnostics settled (capture `glade-parchment-postfix`). Places rebuilt from
fixed source; the >200k `Source` cap on live patching is bypassed via
`ScriptEditorService:UpdateSourceAsync` (recorded as a session truth).

## Fix 6 (burn-down finding 14, 2026-08-08): ZStack overflow diagnostic ignores fill axes

**Cause:** arrange's zstack branch compared the child's MEASURE against the box
and then granted a `fill` axis exactly `availW`/`availH` thirty lines later —
and `resolveAxis` answers `fill` with CONTENT, so a fill page scroller (whose
content is what it exists to be taller than) was reported as painting outside a
box it can never leave, on every screen; the 8px width half was the scroll
measure's honest bar reserve meeting the same false comparison. Three proofs
carried `overflow = "clip"` purely to silence it — a consumer workaround, now
removed (p1 `Sections`, p3 `PaneBody`; p1 `Body_<id>` keeps its clip because it
is a `canvasGroup`, which clips by engine rule, with the comment rewritten to
the honest rationale — as do all of p2's canvasGroup hosts).

**Fix (`src/layout/solver.luau`):** the overflow comparison is per-axis and
skips any axis the child does not size itself on (`fill` → granted, not
measured). The diagnostic stays live for hug/fixed/percent axes — that is the
overlap signal the device matrix depends on.

**Tests:** `tests/zstack_fill_diagnostic.spec.luau` — the minimized live shape
(fill scroller with 900px content in a 300px stack → 0 diagnostics) plus two
negative controls (a hug child genuinely bigger still reports; a fill-WIDTH
child still reports its oversize HEIGHT). Mutation-proved: reverting the axis
gate reddens the fill case with "expected 1 to be 0"; the p1/p3 five-shape
matrix pins now ride the solver fix instead of the removed clips. Suite 3833.

## Findings that stay findings

14. ~~The ZStack overflow diagnostic false-positives on every `fill` child~~ —
    **PROMOTED TO FIX 6 (below) same day**, per the stage rule that a proof-side
    silencer is a consumer workaround. See Fix 6.
15. **`align` is overloaded across the parent/child boundary** (FOLLOW-ON
    PROPOSAL, deliberately not fixed at gate close) —
    `child.align or node.align`: a container's own `align` (for ITS children)
    is also read by its PARENT as the container's cross-axis alignment, so
    `HStack{ align = "stretch" }` silently stretched the row itself and
    defeated its `percent` cap. No separate "how my parent aligns me" channel
    exists for flow-stack children. Candidate: split the channels (crossAlign
    vs align) with a compatible default.

16. **ScrollView bar-reserve measure gates on the OFFER, not the resolved main
    size** (architecture review F5) — `measure` adds the bar when
    `mainSum + gaps > mainOffer`, but arrange reserves it when content exceeds
    the node's RESOLVED main size; a fixed/percent/minMax main axis smaller
    than the offer with content between the two reproduces the original
    "cross size it cannot reproduce" bug in miniature. No proof or example
    hits the shape today. Candidate: compare against the resolved main size in
    measure (the same fixed-point rule, one comparator deeper).
17. **`controller.stageHost` is nil for three distinct reasons** (architecture
    review F3) — no seam, not mounted, and a typo'd path all answer the same
    nil with no diagnostic; the wardrobe proof's `adapter.paths()` fallback
    only exists on the fake target. Candidate: a did-you-mean diagnostic on
    unknown paths, mirroring UI's unknown-property behavior.

18. **`CFrame.lookAt` collinear-with-up is unguarded** (platform review N2) —
    a top-down stage camera hits an engine-underspecified degenerate case; the
    shared normalizer refuses only coincident position/lookAt. Candidate: pick
    a safe up vector when the look direction is near-parallel to +Y, in
    stage_content so both adapters agree. Documented in the ViewportFrame
    research addendum.
19. **`keyboardFirst`'s RbxCameraKeypress unbind is one-shot** (platform
    review N5) — bound in build(), never re-asserted if camera input rebinds,
    never restored at teardown; fine for one-scenario sessions (how every row
    ran), wrong across scenarios in one client session. Candidate: re-assert
    on CameraInput enable and restore on dispose.

20. **`SEAM_OWNED` is a promise about the ADAPTER, not the consumer**
    (architecture review F8) — `contentRoot()` hands back the WorldModel
    parented under the framework-owned ViewportFrame; a consumer walking
    `.Parent` off it reaches the frame and can write `Ambient` silently. The
    authority gate catches bespoke writes in framework code; consumer-side
    containment would need a wrapper or a parent-severed content root.
    Recorded as the Stage contract's documented trust boundary rather than
    simulated as enforcement.

21. **Grid uniform-cell measure and arrange can disagree about column width
    inside an overflowing scroller** (live matrix 2026-08-09, wardrobe compact
    + parchment + xa) — a width-coupled cell height (aspect-on-fill thumbnail)
    measured at one column width and arranged at another (the y-scroller's bar
    reserve narrows the cross axis at arrange), so the Picked plate painted
    29px past its measured box. Same fixed-point family as the shipped Grid
    and ScrollView measure fixes, one corner deeper: the true cure is
    measuring scroller children at the reserve-reduced cross width (two-pass,
    interacts with finding 16). The proof carries a width-independent cell
    height, which removes the disagreement by construction and is
    design-honest for a card grid.

22. ~~Glade detail pane overflows under xa with a selection open~~ — **FIXED
    same day**: three texts in the detail rows (supply name, caption, trailing
    verb; plus the visitor row's name) asked NATURAL width under the 1.4x
    locale — lineLimit caps LINES, never the width a text asks for (the
    recorded p2-caption class, hit a third time). Names/captions now take fill
    shares and truncate through their declared discloses; the verb is
    metric-capped (`METRICS.affordanceMin/Max`). NEW PIN: the locale x width x
    selection sweep the five-shape matrix pin structurally could not see
    (`glade_spec` "the sweep the matrix pin could not see") — 2 locales x 5
    widths with the detail OPEN, 0 diagnostics.

23. **Outline indicator art** (scroll-indicator round, 2026-08-09) — the
    engine scrollbar is a single tintable image set, so a theme-colored thumb
    can vanish over live WORLD content behind a transparent surface (found:
    Foyer's feed over the sky — thumb and backdrop both light). The policy
    round fixed DISCOVERABILITY (auto indicators flash on mount and follow
    scrolling); full any-backdrop CONTRAST needs LuauUI's own bar images with
    a baked outline, through the same Open Cloud pipeline as the icon set.

## Approximations shipped as declared (per capability ledger §A — not defects)

Hero/shared-element transition (materialize modal), 3D perspective card flip
(width-collapse), UI-over-UI blur (translucent surfaces), area-fill charts
(banded strips), swipe rows (visible affordances), rapid text morph (bound text).
