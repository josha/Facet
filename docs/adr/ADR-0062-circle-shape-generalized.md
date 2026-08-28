# ADR-0062 — The circle doctrine: `shape = "circle"` generalizes from Button to ZStack

**Date:** 2026-08-27
**Status:** Accepted
**Number:** 0062 (0061 was already claimed by a concurrent lane's
`ADR-0061-compact-is-the-single-panel-boundary.md` in this same shared working
tree — checked at commit time per the campaign's ADR-numbering rule).
Additive — no ADR-0040 row: no prop is renamed, no default
value changes, no existing construction changes behavior. `shape` was already
a valid `UI.Button` prop; it is now also a valid `UI.ZStack` prop, and every
ZStack that predates this (none could have authored `shape` — it was refused
as an unknown prop) is untouched.
**Home:** `src/blueprint_schema.luau` (`SHAPE`, shared), `src/blueprint.luau`
(`assertCircleSquare`, shared), `src/render/authority.luau` (`common.shape`),
`src/render/layout_node.luau` (`applyCircleShape`, shared). No change to
`src/tokens/sheet_model.luau`, `src/client/screen_paint.luau` or
`src/client/screen_target.luau` — see "What did not need to change" below.
**Guards:** `tests/button_shape.spec.luau` (unchanged, still green — the
regression floor for the feature this generalizes), `tests/zstack_shape.spec.luau`
(new), `tests/reference/glade_spec.luau` ("the stray corner stroke and the
circle doctrine" — the migrated consumer).

## Context

Director's goal-prompt items 11 and 12, verbatim:

> 11. glade-corner.png: some cards carry a partial gray corner stroke. What is
>     it? Fix.
> 12. OddOverlapNotRound.png + whatisthis.png: "round" control isn't round;
>     double-draw (blue-on-gray + white-on-gray, offset). Fix at framework
>     level — circles need a better approach than what we have.

**Item 11, root-caused.** `glade-corner.png`'s stray arc is the Glade card's
own activation `UI.Button` (`overview.luau`'s `gladeCard`): declared with no
`surface`, it classifies to the `control` decoration slot **by class alone**
(`chrome_slots.classify`: *"class = Button | Toggle -> control ... including a
Button that never declared a surface"*), which paints the package's `control`
fill inside a `radii.control` corner (8px under Studio Neutral). The button's
content is edge-to-edge (`padding = 0`, a full-bleed `sceneLib.glade`), and
that content rounds **its own** box at `radii.panel` (12px, via
`UI.corners(_, "panel")`) — a **larger** radius than the button wearing it.
Because the content cuts more corner away than its container does, a sliver of
the container's own control-slot paint shows past the content's more-rounded
edge, at every corner. This is the same family the THEME task (2026-08-27,
same day, same campaign) named for a **different** arithmetic mismatch
(`spendInset`/`chromeYield`): a wrapper's own phantom paint escaping because
nothing made its geometry agree with what it wraps. Here the wrapper is a
Button no one meant to skin at all.

**Item 12, root-caused.** Both "double-draw" photographs are one
`sceneLib.ring` composite: a `UI.Path` `Track` (the grey circle), a
conditional `UI.Path` `Arc` (the coloured progress sweep — blue for nectar,
white for dew, per `supplyTint`), and one identity `mark` (a small filled
circle tinted to the assigned nectar or to dew's own hue). The "double-draw"
read is the mark **overlapping** the ring rather than sitting inside it: the
mark is a ZStack child with no `alignH`/`alignV` of its own, and neither did
the ring's outer ZStack, so `layout/solver.luau`'s own default fired —
`child.alignH or node.alignH or "start"` — pinning the mark to the ring's
**top-left corner** instead of its centre. `whatisthis.png` is the identical
defect at a smaller size: `overview.luau`'s own comment already names the
surface — *"glance-only rings, bottom-trailing on their own plate"* — a
deliberate, correctly-placed decoration, not a leaked or minimized mount. The
two miniature rings with their off-centre dots were simply unrecognisable as
what they are, which is a real cost of the defect even though the surface
itself was never in question.

**The ring itself is not the "not round" complaint's cause.** The outer
ZStack's box was already `{ width = fixed px, height = fixed px }` with the
*same literal* `spec.size` on both — a square by construction. `path_shapes.arc`
produces exact circular-arc bezier handles for a unit circle, and `UI.Path`'s
`width = UI.fill(), height = UI.fill()` maps that unit circle onto whatever
box it is given — a square box, an exact circle. The "not round" read is what
an off-centre dot overlapping a ring's own stroke looks like, not a distorted
track.

## The circle doctrine, evaluated

The brief asks Facet's real options be weighed against current platform docs,
not memory, for how a framework should guarantee a circle/ring:

- **Radius-clamped Box** (`UI.corners(box, "pill")` on an assumed-square box).
  This is what `scene.portrait`, the favourite star's disc-ish chip, and every
  small identity dot in this file already use for a **filled** circle, and it
  is right for them: a solid disc is a fill with a corner radius `>= half the
  box height`, which the engine clamps to a true circle (measured repeatedly
  this campaign — the THEME and POP tasks' own prior-truths). It only works
  when the box is ALREADY square; it enforces nothing, and a future edit that
  gives one axis a different number silently ships an ellipse-with-flat-sides
  (a stadium, not a circle) with no error at any layer. This is what shipped
  code already avoided by hand (both axes literally `spec.size`) — but by
  hand, which is exactly the class of mistake `shape = "circle"` exists to
  make structurally impossible.
- **UICorner-on-square guarantees.** This is Facet's OWN existing
  `shape = "circle"` doctrine on `UI.Button` (feature round 2026-07-26):
  the solver enforces the square (one authored axis drives the other via the
  `aspect` dimension type, already-shipped vocabulary), and the paint side is
  a phantom `.facet-shape-circle::UICorner`/`::UIStroke` StyleSheet rule that
  beats every surface corner in cascade order. **This mechanism was already
  class-agnostic where it mattered**: `sheet_model.classifyTags` and the
  phantom rules read `props.shape`/`handle.shape` with no class check
  anywhere, and `render/authority.luau`'s manifest is the only place `shape`
  was pinned to `Button` specifically. Only the SCHEMA acceptance (which
  classes may author the prop) and the SOLVER-SIDE size derivation
  (`layout_node.luau`'s per-class dispatch) were Button-only. **Decision: this
  is the doctrine, generalized rather than replaced** — see below.
- **Path2D strokes** (`UI.Path` + `path_shapes.ring`/`arc`). This is already
  the right primitive for a **stroked** ring/progress track — `Path2D` is
  stroke-only on the current engine (no fill, no `Transparency`, prior
  measured truth this campaign), which is exactly what a progress ring's
  track and sweep are. Nothing about this ADR changes it: `scene.ring` keeps
  its two `UI.Path` children unmodified. What Path2D cannot do, and was never
  asked to, is guarantee the BOX it strokes is square — that is a layout fact,
  not a paint one, and the fix belongs at the box the Path is stretched into,
  which is `shape = "circle"`'s whole job.
- **Image-based** (a nine-slice or whole-image ring asset). Rejected for the
  same reason `scene.glade`'s own header rejects uploaded art for this
  proof's stage: this stage ships no uploaded assets, and an invented asset id
  draws nothing on a real client. Also wrong in general for a **progress**
  ring specifically — an image can draw the disc, but a partial sweep from 0
  to N degrees needs either a masked image per discrete step (a sprite sheet,
  wrong granularity for a continuous spring-driven value) or a shader, neither
  of which this engine's authoring surface gives a `UI.Image` for free. Where
  Facet already ships image-based chrome (a package's nine-slice `panel`/
  `control` art) it is for RECTANGULAR chrome with a fixed border, not a
  continuously-variable arc.

**Decision: extend the existing `shape = "circle"` guarantee to `UI.ZStack`,
reusing every layer that was already class-agnostic, adding the two that
were not.** A ring/disc composite is naturally a ZStack (a stack of paint
layers over one box) — `scene.ring`'s own shape — so the class that most
needs the square guarantee is the one the guarantee did not yet reach.

### What generalized for free

- `sheet_model.classifyTags({ shape = "circle" })` → the `facet-shape-circle`
  tag, and the phantom `::UICorner`/`::UIStroke` rules it drives — no class
  parameter exists in this call at all.
- `screen_paint.luau`'s fallback-path `cornerRadiusFor(handle, radius)` and
  `screen_target.luau`'s focus-ring-float fallback (`handle.shape == "circle"`)
  — both read the handle's shape directly, never the handle's class.
- The adapter's `elseif prop == "shape" then` write site (`screen_target.luau`)
  and its `STYLE_PROP_ORDER` placement (shape before surface, before icon) —
  a per-PROP dispatch, not per-class.

### What had to move

- **`src/blueprint_schema.luau`**: `shape`'s `PropSpec` was declared inline
  inside `Button`'s `merge(...)` call. It is now a shared `SHAPE` local
  (alongside `CANVAS_GROUP`/`OPACITY`, the pattern this file already uses for
  a spec more than one class needs), referenced by both `Button` and `ZStack`
  — `tests/zstack_shape.spec.luau` pins `schema.forClass("ZStack").props.shape
  == schema.forClass("Button").props.shape` (the SAME table, not a copy that
  can drift).
- **`src/blueprint.luau`**: the "at most one of width/height" refusal lived
  inside Button's `assertShape` (which also validates the drawn label/icon
  content — Button-specific, unmoved). The refusal itself is now
  `assertCircleSquare(className, props)`, called from `assertShape("Button",
  ...)` and from `blueprint.ZStack`'s own constructor — same error text, the
  class name substituted, so a Button's existing pinned error strings
  (`tests/button_shape.spec.luau`) are byte-identical.
- **`src/render/authority.luau`**: `shape = "style"` moved from the `Button`
  class map to `common` — both classes reach the identical write site, so a
  per-class copy would have been the same entry twice. `authority.authorityFor`
  checks the class map first and falls back to `common`, so this is a pure
  reclassification: `authorityFor("Button", "shape")` still resolves to
  `"style"`, now via the fallback instead of a direct hit.
- **`src/render/layout_node.luau`**: the square-derivation block (the `aspect`
  pairing) lived inside the `class == "Button"` arm of the paint-facts
  dispatch. It is now `applyCircleShape(layoutNode, props, metrics)`, a shared
  local function called from both the `Button` arm (unchanged padding
  handling beside it) and a new `ZStack` arm (no padding default — a circular
  ZStack draws no label of its own for this file to reserve room for).

### What did NOT need to change, and stays that way on purpose

`setProp`'s per-class property chain and the fallback-path `corner()` call
sites in `src/client/screen_target.luau` and `src/client/screen_paint.luau`
apply the shape's phantom NATIVE corner (the default paint path since B-15)
unconditionally off `handle.shape`, with no further work from this ADR. The
one gap this ADR leaves open, stated rather than silently accepted: the
FALLBACK path's bespoke `corner()` writer is invoked from inside
`applySurface`'s per-surface-role branches, which fire only for a node that
already carries a decoration slot (`chrome_slots.classify` returned
non-`nil`). A `shape = "circle"` ZStack with **no surface at all** — exactly
`scene.ring`'s shape — therefore gets its square guaranteed at every layer and
its NATIVE-mode corner for free, but would not get a real fallback-mode
`UICorner` instance if `nativeStyle = false` and something painted a fill
directly on that node. This does not affect `scene.ring`: nothing on the
ring's own outer ZStack is ever filled (its children are two strokes and a
separately-cornered mark), so there is no rectangle for a missing corner to
leave square. `screen_target.luau` is size-banded (193k of 200k,
`docs/handoff/SOURCE_CAP_LEDGER.md`) and auditing `applySurface`'s full
call graph to close this narrow gap is not owed by this round's evidence —
it is recorded here as the honest boundary of what generalized, for the next
reader who puts a fill on a bare circular ZStack under the legacy paint path.

## Alternatives considered

- **A brand-new `Ring`/`ProgressRing` control** (`src/controls/`), rather than
  generalizing `shape`. Rejected: it would duplicate the square-guarantee
  machinery `UI.Button` already proved rather than reuse it, adds a new public
  surface-ledger entry and an ADR-0040-style surface-area review this round's
  evidence does not carry, and Glade's actual ring (`Track` + conditional
  `Arc` + a mark) is exactly the shape a `UI.ZStack` composes today — nothing
  about it needs a bespoke control's own props, states or focus handling.
  `shape = "circle"` on the primitive Glade was already using is the smaller,
  more honest fix.
- **Fixing the offset dot by changing the SOLVER's default ZStack child
  alignment** (e.g., defaulting to `"center"` instead of `"start"` when
  neither the parent nor the child declares one). Rejected outright: that
  default is load-bearing across the entire framework's absolute-positioned
  overlay idiom (badges, corner decorations, anchored chips), and changing it
  is a breaking behavior change to every ZStack ever authored, for a benefit
  only this one composite needed. The fix belongs on the ONE ring-drawing
  function (`scene.ring` declaring its OWN `alignH = "center", alignV =
  "center"`), which is a framework-level fix in the sense that matters here:
  it is the one function every nectar/dew ring in the proof calls, not a
  per-card patch.
- **Leaving `radii.control` and `radii.panel` equal** (a package-metrics fix
  for item 11, mirroring the THEME task's Pixel Quest correction). Rejected:
  the two radii being different is a legitimate, intentional design choice
  (a control chip and a panel/card read differently on purpose across every
  shipped package) — the defect is not that the numbers disagree, it is that
  the Button was classified into a chrome slot it was never meant to wear.
  `surface = "plain"` is the framework's own existing, already-documented
  answer to "this activation surface's entire box is covered by content that
  paints its own visuals" (`chrome_slots.luau`'s own comment, citing the
  playlist's rating stars as precedent) — applying it is the class-level fix,
  not a workaround.

## Consequences

- `examples/reference/p1_glade/ui/overview.luau`'s `gladeCard` declares
  `surface = "plain"` on its activation Button (item 11). No other Glade
  Button changes: `overview.wisps`'s `WispCard` and `detail.luau`'s
  `SupplyRow_*`/`Visitor_*` Buttons are NOT full-bleed (their content is
  padded/centred, not edge-to-edge), so they do not exhibit the radius
  mismatch and are left with their ordinary `control` chrome — a scoped fix,
  not a blanket one.
- `examples/reference/p1_glade/ui/scene.luau`'s `scene.ring` declares
  `shape = "circle"` (replacing two independently-authored fixed dimensions
  with one) and `alignH = "center", alignV = "center"` (item 12). Every
  nectar/dew ring in the proof — the overview grid's glance plate, the detail
  screen's supply rows — inherits both fixes from the one shared function.
- RascalRally: `games/RascalRally/code` has zero occurrences of `shape =` and
  does not reference `p1_glade`/`scene.ring` — grepped and confirmed clean.
  The framework-side change is additive (a previously-refused ZStack prop
  now succeeds; nothing authored before this round could have used it), so
  this is a clean negative, not an unaudited gap.
