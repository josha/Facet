# Surface ledger — THE BLUEPRINT LAYER (`LuauUI.UI`)

Area: `src/blueprint.luau` (1184 lines) + `src/blueprint_schema.luau` (1813 lines).
Audited 2026-08-02 against the shipped source, `docs/reference/api.md` §Blueprints
(lines 91–1194), the baseline surface (`baseline/public-surface-before.txt`) and a
live Lune probe of the constructors/modifiers. Baseline suite: 2785 pass / 0 fail
(`baseline/test-before.json`). `lune run tools/lune/check_prop_parity_cli` re-run
this session: **PASS (24 classes, 414 properties, 2 diagnosed, 448 typed fields)**.

## Reading notes that apply to every entry

- **Lifecycle, uniform.** A blueprint is a *value*, not a resource. `make()`
  (`src/blueprint.luau:393-442`) returns a `table.freeze`d node; nothing in the
  layer allocates a scope, a subscription or an instance, and nothing has a
  `dispose`. Ownership begins at `mount.luau`, which owns the node scope and the
  per-prop subscriptions it derives from `blueprint.PROP_DIRTY`
  (`src/mount.luau:502`). Leak posture at this layer: none — with the one caveat
  in **BP-F18** (the freeze is one level deep).
- **The named pattern.** Every constructor is *construction-strict, single-spec-table*:
  `UI.<Class>(spec) -> Blueprint`, funnelled through `make(class, spec)`, which
  validates every key against `blueprint_schema` (unknown key → suggestion list;
  wrong type → expected-types + detail + doc; Readable on a `reactive = false`
  prop → refusal naming the rebuild idiom; missing `required`; `children` on a
  leaf; deprecated prop → diagnostic).
- **The modifier pattern.** `UI.<mod>(blueprint, …) -> new frozen Blueprint`,
  written through `withProps` (`src/blueprint.luau:820-841`), which re-runs the
  *same* schema validation, so a modifier can never write a prop the class does
  not declare.
- Findings are tagged `BP-Fn` and collected in **§Findings index** at the end.
  Repeated findings are cross-referenced rather than restated per entry.

---

# Part A — Constructors

### `UI.Screen` — constructor (container)
- **Shipped shape:** `UI.Screen(spec: ScreenSpec) -> Blueprint`, `src/blueprint.luau:445-447`.
  Schema `blueprint_schema.luau:781-785` = `BOX ∪ CONTAINER_LAYOUT ∪ { gap, align }`.
  No required prop. Renderer maps it to `kind = "vstack"` and defaults both dims
  to `fill` (`src/render/renderer.luau:329-330, 576-578`).
- **Pattern:** construction-strict single-spec-table. Follows it exactly.
- **Callers:** `examples/gallery/scenarios/*` (39 hits); RascalRally
  `client/LuauUISponsor/ResultsScreen.luau`, `client/LuauUISettingsScreen.luau` (6 hits).
- **Lifecycle:** value; see reading notes.
- **Proof:** `tests/layout.spec.luau` throughout; api.md:217-220.
- **Findings:** BP-F13 (rejects a nil spec although it has no required prop),
  BP-F31 (schema-identical to `VStack`; the only difference is the fill default —
  candidate intentional exception).

### `UI.VStack` / `UI.HStack` — constructors (containers)
- **Shipped shape:** `blueprint.luau:448-453`; schema `blueprint_schema.luau:787-797`,
  byte-identical prop sets to `Screen`. `VStackSpec`/`HStackSpec` are both aliases
  of `ScreenSpec` (`blueprint.luau:123-124`).
- **Pattern:** construction-strict single-spec-table. No deviation.
- **Callers:** the two most-used containers after `Text`/`Box`: examples 35 + 39,
  RascalRally 24 + 23.
- **Proof:** `tests/layout.spec.luau`, `tests/layout_vocabulary.spec.luau`
  ("A-LV1: Spacer expands along the stack's main axis by default"); api.md:222-227.
- **Findings:** BP-F13, BP-F6 (api.md's shared `gap`/`align` rows are correct for
  these two and wrong for their siblings).

### `UI.ZStack` — constructor (container)
- **Shipped shape:** `blueprint.luau:454-456`; schema `:799-803` =
  `BOX ∪ CONTAINER_LAYOUT ∪ { canvasGroup }`. `canvasGroup` is `reactive = false`
  ("it decides which engine class the node IS, at creation", `:703-710`) and is read
  at instance creation (`src/render/renderer.luau:1327-1328`).
- **Pattern:** construction-strict. No deviation.
- **Callers:** examples 32; RascalRally 61 (its single most-used container).
  `UI.overlay`/`UI.background` synthesise one internally (`blueprint.luau:1142`).
- **Proof:** `tests/layout_vocabulary.spec.luau` "overlay layers content ABOVE the
  node in a ZStack"; api.md:229-259 (including the three CanvasGroup costs).
- **Findings:** none specific.

### `UI.ScrollView` — constructor (container)
- **Shipped shape:** `UI.ScrollView(spec: ScrollViewSpec?) -> Blueprint`,
  `blueprint.luau:457-467`. The **only** constructor that mutates its spec: it
  clones and defaults `clipChildren = true`. Schema `:805-842` adds
  `gap`, `axis` (`reactive = false`, enum `y|x`), `onScrollWheel`, `autoscroll`.
- **Pattern:** construction-strict + a documented default injection. Mild deviation
  (no sibling clones its spec), justified in the comment at `:458-461`.
- **Callers:** examples 20 (incl. `demo_picker.luau`, `theme_picker.luau`);
  RascalRally 2; `src/controls/virtual_list.luau`, `table.luau`.
- **Proof:** `tests/native_scroll.spec.luau`, `tests/autoscroll.spec.luau`,
  `tests/layout.spec.luau` "reports content size and scroll overflow when content
  exceeds viewport"; api.md:261-320.
- **Findings:** BP-F11 (`overflow` accepted here and overwritten by the solver),
  BP-F22 (`axis` refuses a Signal while `AdaptiveStack.axis` and `Divider.axis`
  accept one), BP-F28 (`autoscroll: { [string]: any }`), BP-F13 (it *does* accept a
  nil spec — one of only three that do).

### `UI.Anchor` — constructor (container)
- **Shipped shape:** `blueprint.luau:474-476`; schema `:844-848` = `BOX ∪ CONTAINER_LAYOUT`,
  no own props. Its contract lives on its *children* (`anchor`, `offsetX`, `offsetY`
  in `BOX`, `blueprint_schema.luau:468-494`).
- **Pattern:** construction-strict. The "props live on the children" shape is unique
  among containers but is the SwiftUI/`ZStack`-alignment idiom and is documented.
- **Callers:** examples 11; RascalRally 17 (the minimap-dot / name-tag idiom).
- **Proof:** `tests/fractional_offsets.spec.luau`; api.md:322-339.
- **Findings:** BP-F27 (`UI.offset`'s signature cannot reach the `scaleOffset`/`metric`
  forms this class's children accept).

### `UI.AdaptiveStack` — constructor (container)
- **Shipped shape:** `blueprint.luau:483-485`; schema `:904-923` =
  `BOX ∪ CONTAINER_LAYOUT ∪ { gap, align, axis }` with `axis` **reactive**
  (`dirty = {"measure"}`), which is the class's entire reason to exist.
- **Pattern:** construction-strict. No deviation.
- **Callers:** examples 5; RascalRally `client/LuauUISponsor/TableScreen.luau:151`.
- **Proof:** `tests/adaptive.spec.luau`; api.md:341-361 (asserts zero factory reruns
  across an axis flip).
- **Findings:** BP-F6 (api.md's shared `gap` and `align` rows omit this class),
  BP-F22.

### `UI.ViewThatFits` — constructor (container)
- **Shipped shape:** `blueprint.luau:491-500` — `make` then a hand-written
  "needs at least one candidate in `children`" refusal. Schema `:925-934` =
  `BOX` only: no `padding`, `surface`, `overflow`, `clipChildren`, `active`
  (probe: `UI.ViewThatFits{ padding = 4 }` → "unknown property 'padding'").
- **Pattern:** construction-strict **plus a bespoke post-`make` assertion** — the
  same sub-pattern `Region`, `Composition` and `Button` use, because `children` has
  no schema representation (see BP-F14).
- **Callers:** examples 2 (`adaptive_controls.luau:109`); RascalRally
  `client/LuauUISponsor/ResultsScreen.luau:2503`.
- **Proof:** `tests/adaptive.spec.luau`; `tests/focus_skip.spec.luau` (losing
  candidates leave focus order, both the flat ring and grouped scopes); api.md:363-398.
- **Findings:** BP-F6 (it is a container with none of the container props api.md's
  shared table promises "containers"), BP-F13, BP-F14.

### `UI.Composition` — constructor (container)
- **Shipped shape:** `blueprint.luau:528-610`. The heaviest constructor in the layer:
  `make`, then five hand-written passes — non-empty children, every child is a
  `Region`, per-group `minWidth`/`gap` metric validation against an ad-hoc inline
  `PropSpec` (`:566`), a live-`eligible`/live-`reserved` normalisation, and a full
  `compositionLib.normalize()` shape check. Schema `:944-987`: `arrangements` and
  `groups` are `required`, everything is `reactive = false`.
- **Pattern:** construction-strict + bespoke assertions, but with a **second,
  hand-rolled validation vocabulary** for nested array members that the prop schema
  cannot reach (`:562-581`). Unique; the comment states why.
- **Callers:** examples 2 (`scenarios/composition.luau:114`); RascalRally
  `client/LuauUISponsor/ResultsScreen.luau` (5 hits, the results body).
- **Proof:** `tests/composition.spec.luau` (~60 cases: "a short wide offer resolves
  the richest arrangement", "a lane that overflows steps its LEAST important region
  down first", "maxMeasure caps both axes and centres the result", rule-9 collapse
  table, "a `reserved` that is not a boolean is refused where it is written");
  api.md:400-511.
- **Findings:** BP-F10 (`CompositionArrangement` type omits the documented
  `eligible`), BP-F14.

### `UI.Region` — constructor (container)
- **Shipped shape:** `blueprint.luau:505-522` — `make`, then explicit-`id` and
  non-empty-`children` refusals. Schema `:989-1065`: `group` + `rank` required;
  the **only** class whose props omit the shared `BOX` group entirely (probe:
  `UI.Region{ width = … }` → "unknown property 'width'"); `reserved` is the one
  reactive prop (`:1053-1063`).
- **Pattern:** construction-strict + bespoke assertions. The missing `BOX` group is a
  deliberate, self-consistent narrowing (`RegionSpec`, `blueprint.luau:172-183`, does
  not extend `BoxProps`).
- **Callers:** examples 13; RascalRally `ResultsScreen.luau` (2 direct, many via a
  local helper).
- **Proof:** `tests/composition.spec.luau` (floors, ranks, `reserved`, `mayDrop`
  exclusivity, duplicate-id and second-`mayScroll` refusals); api.md:513-545.
- **Findings:** BP-F30 (recorded as an intentional exception), BP-F6 (api.md's
  container list omits it), BP-F14.

### `UI.Divider` — constructor (leaf)
- **Shipped shape:** `UI.Divider(spec: DividerSpec?) -> Blueprint`,
  `blueprint.luau:613-615`. Schema `:1067-1091` = `BOX ∪ { axis, thickness }`, both
  reactive. Orientation is inferred from the enclosing stack in the renderer
  (`src/render/renderer.luau:583`).
- **Pattern:** construction-strict, optional spec.
- **Callers:** examples 4 (`adaptive_controls.luau:146`); **no RascalRally caller**;
  no `src/controls` caller.
- **Proof:** `tests/layout_vocabulary.spec.luau`; api.md:547-563.
- **Findings:** BP-F12 (documented default "1 px" is actually
  `metrics.strokes.hairline`, and `thickness` is the one theme-owned number that
  refuses a metric name), BP-F13.

### `UI.Grid` — constructor (container)
- **Shipped shape:** `blueprint.luau:477-479`; schema `:850-902` adds `gap`, `rowGap`,
  `columns`, `minColumnWidth` (`enum = {"intrinsic"}` over `number|string`),
  `itemSizing` (`natural|uniform`), all reactive on `measure`.
- **Pattern:** construction-strict. No deviation. `columns` and `minColumnWidth` are
  documented as mutually exclusive but the exclusivity is **not** enforced at
  construction — the solver resolves it (`src/layout/solver.luau:271-327`). Recorded,
  not raised: the schema doc says "mutually exclusive" and the solver picks
  `minColumnWidth`, which is a defined answer rather than a silent drop.
- **Callers:** examples 11; RascalRally references it only in a comment
  (`client/GaragePilotScreen.luau:11`).
- **Proof:** `tests/layout_vocabulary.spec.luau` "A-LV1: Grid children with fill
  dimensions", "a minColumnWidth grid derives its column count and still fills";
  api.md:565-594.
- **Findings:** none specific.

### `UI.Text` — constructor (leaf)
- **Shipped shape:** `blueprint.luau:619-621`; schema `:1119-1226`. `text` required;
  `textSize`, `textAlign`, `lineLimit`, `tint`, `padding`, a **narrowed** `surface`
  (`badge|chip` only, `:1169-1179`), `role` (`secondary|content`), plus the two
  diagnosed props `color` and `font`.
- **Pattern:** construction-strict. The narrowed `surface` enum is the layer's model
  example of a per-class vocabulary restriction with the reasoning on the record.
- **Callers:** the single most-used constructor: examples 118, RascalRally 63.
- **Proof:** `tests/authoring.spec.luau` "Text.color is diagnosed with its
  replacement…", "Text.font is diagnosed because it reached measure but never paint";
  `tests/text_fit.spec.luau`, `tests/icon_box.spec.luau`; api.md:596-659.
- **Findings:** BP-F6 (api.md's shared `padding` row omits `Text`, while api.md's own
  modifier table at :1177 includes it), BP-F19 (both ledger entries are past their
  removal window), BP-F8 (`tint: Bound<any>`).

### `UI.Image` — constructor (leaf)
- **Shipped shape:** `blueprint.luau:622-624`; schema `:1228-1259` = `BOX ∪
  { image (optional), surface (full 8-value enum), tint, scaleMode }`.
- **Pattern:** construction-strict. No deviation.
- **Callers:** examples 9; RascalRally 6; `src/controls/async_image.luau`.
- **Proof:** `tests/async_image.spec.luau`, `tests/paint_extensions.spec.luau`
  (asserts `tint` exists on exactly Box/Text/Image/Path, `:128-131`); api.md:661-681.
- **Findings:** BP-F24 (`fill`/`crop` are declared deliberate synonyms —
  **candidate intentional exception**; the declaration is in the schema at
  `:1252-1256` and repeated in api.md:671-673, which is the right way to ship one).

### `UI.Button` — constructor (container)
- **Shipped shape:** `blueprint.luau:783-789` — `make`, then three semantic passes:
  `assertNoFocusableContent` (`:633-653`), `assertShape` (`:678-729`, the circle
  rules: icon-requires-circle, icon-names-a-real-icon, at-most-one-authored-axis,
  ≤3 space-free drawn characters), `assertCompactLabel` (`:734-781`). Schema
  `:1264-1382`: `label` required, `role`/`gap`/`align`/`shape`/`icon`/`compactLabel`/
  `enabled`/`selected`/`focusable`/`surface`/`padding`/`textSize`/`onActivate` and
  the four pointer handlers. `container = true`.
- **Pattern:** construction-strict + the layer's largest bespoke semantic block. The
  split ("the schema proves the SHAPE, `blueprint.luau` proves what the value MEANS",
  `:731-733`) is stated and consistently applied.
- **Callers:** examples 74; RascalRally 16; every composite control in `src/controls`.
- **Proof:** `tests/button_shape.spec.luau` (the accept/reject classes, geometry,
  hit square, phantom modifier rules), `tests/compact_label.spec.luau` (the ladder,
  the closed grammar, "refuses a compact form on a CONTENT button"),
  `tests/button_complete.spec.luau`; api.md:683-836.
- **Findings:** BP-F6 (api.md:163-165 calls Button a **leaf** while api.md:689 says
  "A Button takes `children`", and api.md's shared `gap`/`align`/`clipChildren`/
  `active` rows are all wrong for it).

### `UI.Toggle` — constructor (leaf)
- **Shipped shape:** `blueprint.luau:790-792`; schema `:1384-1421` = `BOX ∪
  { label (required), value, enabled, focusable, padding, textSize, onActivate }`.
- **Pattern:** construction-strict. No deviation.
- **Callers:** examples 6; RascalRally `client/LuauUISettingsScreen.luau:90`.
- **Proof:** `tests/auto_input.spec.luau` (Activate flips a settable Signal on all
  four input classes), `tests/controls_conformance.spec.luau`; api.md:838-844.
- **Findings:** none specific.

### `UI.TextField` — constructor (leaf)
- **Shipped shape:** `blueprint.luau:797-799`; schema `:1423-1491`. No required prop.
- **Pattern:** construction-strict. No deviation.
- **Callers:** `src/controls/text_input.luau:553` only. **No** example and **no**
  RascalRally caller uses the raw primitive (api.md:859 tells you not to).
- **Proof:** `tests/paradigm_textinput.spec.luau`, `tests/render_target_contract.spec.luau`;
  api.md:846-860.
- **Findings:** BP-F16 (`maxLength` and `keyboardType` are declared binding props
  whose adapter branches write nothing on a shipping client).

### `UI.Box` / `UI.Spacer` — constructors (leaves)
- **Shipped shape:** `blueprint.luau:471-473` and `:468-470`. `Box` schema `:1093-1111`
  = `BOX ∪ { surface, active, tint, canvasGroup }`; `Spacer` schema `:1113-1117` =
  `BOX` and nothing else. `UI.Spacer(spec?)` accepts a nil spec; `UI.Box(spec)` does not.
- **Pattern:** construction-strict.
- **Callers:** `Box` examples 52 / RascalRally 32; `Spacer` examples 12 /
  RascalRally 9 / `src/controls/stepper.luau:137`.
- **Proof:** `tests/layout_vocabulary.spec.luau` "A-LV1: Spacer expands along the
  stack's main axis by default" (5 cases); `tests/paint_extensions.spec.luau`;
  api.md:862-882.
- **Findings:** BP-F13 (`Spacer` optional, `Box` not, with the same "no required
  prop" justification).

### `UI.Path` — constructor (leaf)
- **Shipped shape:** `blueprint.luau:802-804`; schema `:1538-1574` = `BOX ∪
  { points (required, array, reactive/paint), thickness, closed, role
  (accent|secondary|content), tint }`.
- **Pattern:** construction-strict. No deviation.
- **Callers:** examples 7 (`scenarios/path_ring.luau:40`); RascalRally 26 (progress
  rings and gauge needles).
- **Proof:** `tests/path.spec.luau`; api.md:884-908.
- **Findings:** BP-F12 (`thickness` refuses a metric name, as on `Divider`),
  BP-F8 (`points: Bound<{ any }>`; `tint: Bound<any>`). Note that `tint.transparency`
  is refused for `Path` **at the adapter write site**, not at construction —
  documented at api.md:191-193; recorded here because it is the one place the
  `tint` grammar is class-conditional and the schema does not encode it.

### `UI.Grip` — constructor (leaf)
- **Shipped shape:** `blueprint.luau:616-618`; schema `:1493-1536` = `BOX ∪
  { cursorHint, focusable (opt-IN), four pointer handlers }`.
- **Pattern:** construction-strict. No deviation.
- **Callers:** `src/controls/slider.luau:356`, `src/controls/table.luau` (column
  resize); examples 6 (`scenarios/native_style.luau:73`). **No** RascalRally caller.
- **Proof:** `tests/pointer.spec.luau`, `tests/paradigm_table.spec.luau`,
  `tests/authoring.spec.luau` "Grip is registered as an INTERACTIVE control with a
  hit floor"; api.md:910-929.
- **Findings:** BP-F23 (`focusable` is opt-IN here and opt-OUT on the other three —
  documented at api.md:148; **candidate intentional exception**).

### `UI.When` — constructor (structural)
- **Shipped shape:** `blueprint.luau:805-807`; schema `:1577-1598` =
  `{ condition (required, `readable` type — a plain boolean is refused),
  thenView (required function), transition }`. No `BOX`, no `children`.
- **Pattern:** construction-strict. The `readable` logical type is the inverse of the
  usual rule (this prop *requires* a Signal), which is consistent and documented.
- **Callers:** examples 39; RascalRally 58 (its second most-used constructor).
- **Proof:** `tests/mount.spec.luau`, `tests/focus_structural.spec.luau`,
  `tests/authoring.spec.luau` "When.condition must be a Signal/Memo, not a plain
  boolean"; api.md:931-936.
- **Findings:** BP-F4 (every style/layout modifier applied to a `When` errors with
  "LuauUI UI.When: unknown property 'alignH'" — the author never wrote `alignH`),
  BP-F15 (`UI.draggable(UI.When{…})` is accepted and inert), BP-F25.

### `UI.ForEach` — constructor (structural)
- **Shipped shape:** `blueprint.luau:809-811`; schema `:1600-1628` =
  `{ items (required readable), key (required fn), row (required fn), transition }`.
- **Pattern:** construction-strict. No deviation. Duplicate-key detection is
  necessarily a mount-time hard error, not a construction one.
- **Callers:** examples 5; RascalRally 13.
- **Proof:** `tests/mount.spec.luau`, `tests/focus_structural.spec.luau`; api.md:938-945.
- **Findings:** BP-F29 (`row: (item: any, itemScope: any) -> Blueprint` — `itemScope`
  is a core Scope and the core exports a type for it), BP-F25.

### `UI.ErrorBoundary` — constructor (structural)
- **Shipped shape:** `blueprint.luau:1180-1182`; schema `:1630-1649` =
  `{ view (required fn), fallback (required fn) }`. Declared **last** in the file,
  detached from `When`/`ForEach` under the "structural regions (§5.4)" comment at
  `:801` — a cosmetic ordering oddity, not a contract one.
- **Pattern:** construction-strict. No deviation.
- **Callers:** `tests/error_boundary.spec.luau` only. **No** example, **no**
  `src/controls`, **no** RascalRally caller — the least-adopted public constructor
  in the layer.
- **Proof:** `tests/error_boundary.spec.luau` (4 cases: mount-time throw, later
  structural rebuild, errors inside the fallback stay hard); api.md:981-987.
- **Findings:** none specific. Adoption fact recorded for the lead.

---

# Part B — Style and structure modifiers

### `UI.shadow` — style modifier
- **Shipped shape:** `UI.shadow(bp, presetOrParams: any, style: any?) -> Blueprint`,
  `blueprint.luau:844-846` → `stylingLib.normalizeShadow` (`src/tokens/styling.luau:46-70`)
  → `withProps{ shadow = … }`.
- **Pattern:** `(blueprint, spec, style?) -> new frozen Blueprint`. The reference
  implementation the other three copy.
- **Callers:** examples 5; RascalRally `client/LuauUISponsor/RolePickScreen.luau:334`;
  `src/controls` 3.
- **Proof:** `tests/styling.spec.luau`; api.md:989-1000.
- **Findings:** BP-F2 (an unknown key in the spec is silently ignored — probe:
  `{ blurRadius = …, blur = 99 }` constructs), BP-F4, BP-F7 (no `UI.shadowData`
  although the prop is `reactive = true`), BP-F8 (`spec: any`), BP-F21 (its refusals
  are bare Lua `assert`s that leak `…/styling:53:` into the message).

### `UI.gradient` — style modifier
- **Shipped shape:** `blueprint.luau:901-904` — `assertGradientable(bp, "UI.gradient")`
  then `normalizeGradient` then `withProps`. Two construction-time walls, hoisted at
  `:877-899` so `UI.styleGroup` shares them: a value control's own chrome slot, and
  any text-bearing class (`Text|Button|Toggle|TextField`).
- **Pattern:** `(blueprint, spec, style?) -> new frozen Blueprint`, plus node-level
  refusals. Follows the family.
- **Callers:** examples 1 (`scenarios/theme_authoring.luau:726`); tests 7;
  `src/controls` 2. **No** RascalRally caller.
- **Proof:** `tests/styling.spec.luau`, `tests/paint_extensions.spec.luau`; api.md:1002-1044.
- **Findings:** BP-F2 (**verified live**: `UI.gradient(bp, { colors = {…},
  roation = 45 })` constructs and the rotation stays at the 90° default), BP-F4,
  BP-F7, BP-F8, BP-F21 (`LuauUI: UI.gradient cannot paint …` — a sixth prefix shape).

### `UI.corners` — style modifier
- **Shipped shape:** `blueprint.luau:908-910` → `normalizeCorners`
  (`src/tokens/styling.luau:87-113`) → `withProps`.
- **Pattern:** `(blueprint, spec, style?)`. Follows the family.
- **Callers:** the most-used modifier by a wide margin: examples 21, RascalRally 30.
- **Proof:** `tests/styling.spec.luau`; api.md:1046-1053.
- **Findings:** BP-F4, BP-F7, BP-F8, BP-F21. **Not** BP-F2: `normalizeCorners` does
  reject an all-unknown-key table (`:107`, "corners table must set radius or at least
  one corner"), though it does not name the offending key.

### `UI.stroke` — style modifier
- **Shipped shape:** `blueprint.luau:923-925` → `normalizeStroke`
  (`src/tokens/styling.luau:401-…`) → `withProps`.
- **Pattern:** `(blueprint, spec, style?)`. Follows the family, and is the **only**
  member whose normalizer closes its key set (`:407-412`) and refuses a Signal inside
  the spec with a `LuauUI UI.stroke:`-prefixed message naming the `strokeData` idiom
  (`:418-428`).
- **Callers:** RascalRally `client/LuauUISponsor/StartCountdown.luau:165` (3);
  `src/controls` 4; tests 5. **No** example caller (the examples use `strokeData`).
- **Proof:** `tests/styling.spec.luau`; api.md:1055-1094.
- **Findings:** BP-F4, BP-F8, BP-F21 (its unknown-key refusal is still a bare
  `assert`, so the message carries a `…/styling:408:` prefix — probe output).

### `UI.strokeData` — style-data producer
- **Shipped shape:** `UI.strokeData(spec: any, style: any?) -> any`,
  `blueprint.luau:931-933`. The only public normalizer that takes no blueprint.
- **Pattern:** **unique** in the layer — a bare `(spec, style?) -> data` producer for
  the reactive idiom `stroke = core:memo(function() return UI.strokeData(…) end)`.
- **Callers:** examples 5; RascalRally 8 (its most-used style entry point after
  `corners`); `src/controls` 7.
- **Proof:** `tests/styling.spec.luau`; api.md:1081-1094.
- **Findings:** BP-F7 (the pattern exists for `stroke` alone; `shadow`, `gradient` and
  `corners` are equally reactive and have no `*Data` sibling — probe:
  `UI.shadowData`/`UI.gradientData`/`UI.cornersData` are all `nil`), BP-F8
  (`spec: any -> any`, the only public function in the layer with `any` on both ends).

### `UI.styleGroup` — collection style modifier
- **Shipped shape:** `UI.styleGroup(spec: { shadow: any?, corners: any?, gradient: any? },
  blueprints: { Blueprint }, style: any?) -> { Blueprint }`, `blueprint.luau:960-985`.
- **Pattern:** **argument-order drift** — spec first, subject second, and it returns an
  array. Every other modifier is `(blueprint, …)`. Documented as SwiftUI `Group`
  semantics (api.md:1189-1193), so the drift is deliberate; recorded as a
  **candidate intentional exception**.
- **Callers:** `tests/styling.spec.luau:138`; `src/controls` 1. **No** example and
  **no** RascalRally caller.
- **Proof:** `tests/styling.spec.luau`; api.md:1189-1193.
- **Findings:** **BP-F1** (the spec table's key set is never validated, so
  `stroke` — the fourth style modifier — and any typo are silently dropped;
  verified live), BP-F2 (inherited through `normalizeShadow`/`normalizeGradient`),
  BP-F8.

### `UI.frame` — layout modifier
- **Shipped shape:** `UI.frame(bp, spec: FrameSpec) -> Blueprint`,
  `blueprint.luau:1035-1059`, with `FRAME_FIELDS` closed-set validation (`:1039-1048`)
  and a `frameDim` mapper (`:1020-1031`).
- **Pattern:** `(blueprint, spec)`. The **best-behaved** modifier in the layer: an
  exported spec type, a closed field set, and an error that names the modifier.
- **Callers:** RascalRally `client/LuauUISponsor/ResultsScreen.luau:3542`; tests 9;
  `src/controls` 3. **No** example caller.
- **Proof:** `tests/layout_vocabulary.spec.luau` "A-LV2: frame" — "sets fixed
  dimensions", "expresses a min/max band", "`maxWidth = \"infinity\"` fills the
  available space, like SwiftUI", "rejects an unknown frame field instead of ignoring
  it"; api.md:1176.
- **Findings:** BP-F4 (the *field* check names `UI.frame`, but the underlying
  `withProps` write on a class with no `width` reports "LuauUI UI.When: unknown
  property 'width'" — probe), BP-F9 (`FrameSpec` numbers cannot express the
  metric-name forms the `dim` type accepts).

### `UI.padding` — layout modifier
- **Shipped shape:** `UI.padding(bp, sides: Sides) -> Blueprint`, `blueprint.luau:1065-1075`,
  with a bespoke pre-check that names the modifier and prescribes the fix
  (`:1067-1073`).
- **Pattern:** `(blueprint, value)`. Follows the layout-modifier family, and is one of
  only two whose error names the modifier.
- **Callers:** examples 2 (`adaptive_controls.luau:169`); tests 7; `src/controls` 1.
  **No** RascalRally caller.
- **Proof:** `tests/layout_vocabulary.spec.luau` "padding insets a container's
  children", "padding works on a label without wrapping it", "padding accepts per-side
  values", "padding on a class that cannot inset says so", "a modifier writing a
  property the class does not have is rejected" (`:388-394`); api.md:1177.
- **Findings:** BP-F6 (api.md's shared table and api.md's modifier table disagree
  about whether `Text` accepts `padding`; the code says it does,
  `blueprint_schema.luau:1137`).

### `UI.offset` — layout modifier
- **Shipped shape:** `UI.offset(bp, x: number?, y: number?) -> Blueprint`,
  `blueprint.luau:1079-1088`.
- **Pattern:** `(blueprint, positional…)` rather than `(blueprint, spec)` — shared with
  `UI.alignment` and `UI.aspectRatio`. Internally consistent sub-family.
- **Callers:** `tests/layout_vocabulary.spec.luau:336` only. **No** example, **no**
  `src/controls`, **no** RascalRally caller.
- **Proof:** `tests/layout_vocabulary.spec.luau` "offset moves a node inside an Anchor
  without affecting siblings"; api.md:1178.
- **Findings:** BP-F27 (the signature says `number?` while the props accept
  `number | scaleOffset | metric`, and the runtime passes all three through — probe),
  BP-F4.

### `UI.aspectRatio` — layout modifier
- **Shipped shape:** `UI.aspectRatio(bp, ratio: number) -> Blueprint`,
  `blueprint.luau:1091-1098`. Validates the ratio (positive, non-NaN) with a
  modifier-named error, then writes `height = { type = "aspect", ratio }`.
- **Pattern:** `(blueprint, positional)`.
- **Callers:** examples 1 (`adaptive_controls.luau:279`); tests 7; `src/controls` 1.
  **No** RascalRally caller.
- **Proof:** `tests/layout_vocabulary.spec.luau` "aspectRatio derives the height from
  the width", "aspectRatio rejects a non-positive ratio", "A-LV4: aspectRatio against
  a fill sibling"; api.md:1179.
- **Findings:** BP-F26 (it can only ever derive the *height*, though the solver's
  `aspect` dim works on either axis, and it silently overwrites an authored `height` —
  probe: fixed/40 → aspect/1.5; covered by the documented last-writer-wins rule, so
  a NOTE), BP-F4.

### `UI.alignment` — layout modifier
- **Shipped shape:** `UI.alignment(bp, horizontal: string?, vertical: string?) -> Blueprint`,
  `blueprint.luau:1101-1110`. Writes `alignH`/`alignV`; the enum check comes from
  `withProps`.
- **Pattern:** `(blueprint, positional…)`.
- **Callers:** RascalRally `client/LuauUISponsor/ResultsScreen.luau:1091` (3);
  examples 1; `src/controls` 2.
- **Proof:** `tests/layout_vocabulary.spec.luau` "alignment sets the ZStack placement
  props", "an unknown alignment value fails at construction"; api.md:1180.
- **Findings:** BP-F4 (**the sharpest instance**: `UI.alignment(node, "center")` on a
  class without `alignH` reports "unknown property 'alignH'" — a property name the
  author never typed).

### `UI.overlay` / `UI.background` — structural modifiers
- **Shipped shape:** `UI.overlay(bp, content, align?)` / `UI.background(bp, content, align?)`,
  `blueprint.luau:1145-1175`, both through `layered` (`:1117-1143`) which
  `make("ZStack", …)` a wrapper with a derived id `<base.id>+overlay|background`,
  inherits the base's dims, and requires the base to carry an explicit `id`.
  `UI.background` additionally **rebuilds** a dimension-less content node with
  `fill`/`fill` dims (`:1161-1175`).
- **Pattern:** the only two modifiers that change **structure**. Otherwise consistent
  with each other.
- **Callers:** examples 1 each (`adaptive_controls.luau:161`, `:286`); tests 6 / 4;
  `src/controls` 1 / 2. **No** RascalRally caller.
- **Proof:** `tests/layout_vocabulary.spec.luau` "A-LV2: overlay and background" —
  "the background layer FILLS what it is backing" (`:438`), "an OVERLAY is still an
  ornament: it keeps its own size", "the base node keeps its own id inside the
  wrapper", "both modifiers require the base to carry an id"; api.md:1181-1187.
- **Findings:** **BP-F3** (`UI.background` drops the content's `meta` channel when it
  inflates the backing — verified live; no spec pins it), BP-F4.

### `UI.draggable` / `UI.dropTarget` — metadata modifiers
- **Shipped shape:** `blueprint.luau:949-955` → `dragContract.attach(bp, KEY, decl)`
  (`src/input/drag_contract.luau:184-197`). They are the **only** modifiers that write
  the internal `meta` channel rather than the prop bag; the reasoning is on the record
  at `drag_contract.luau:8-21`. Their specs are the only modifier specs with a real
  exported type (`dragContract.SourceSpec` / `TargetSpec`).
- **Pattern:** `(blueprint, spec) -> new frozen Blueprint`, meta channel. Consistent
  pair.
- **Callers:** `UI.draggable` — RascalRally `client/LuauUISponsor/HandDock.luau:371`,
  examples 1, `src/controls` 4, tests 16. `UI.dropTarget` — `src/controls/table.luau`
  (RascalRally reaches it through `newTable`'s `rowDropTarget` seam,
  `client/LuauUISponsor/PlayFlow.luau:503-523`), examples 1, tests 7.
- **Proof:** `tests/drag_public.spec.luau` (~35 cases: acquisition/promotion,
  enter/leave exactly once, predicted verdict, terminals, live geometry under a
  scrolled host, the arm→navigate→commit paradigm, `armStaging`, `grabAnchor`);
  api.md:1096-1160.
- **Findings:** BP-F15 (`attach` applies **no class gate** — it checks only that the
  argument is a blueprint, so a declaration on a structural or non-instantiated node
  is accepted and inert; verified live on `UI.When`), BP-F3 (a `draggable` node used
  as `UI.background` content loses its declaration).

---

# Part C — Shared vocabularies

### Structural-transition vocabulary (`transition` on `When`/`ForEach`) — closed grammar
- **Shipped shape:** `TRANSITION_FORMS` (7 forms) + `TRANSITION_MIRROR` +
  `TRANSITION_KEYS` (`enter|exit|class|fade`) at `blueprint_schema.luau:135-162`; the
  `transition` logical type at `:367-396`; the `TRANSITION` PropSpec
  (`reactive = false`, `channel = "structural"`) at `:720-728`, shared verbatim by
  `When` (`:1596`) and `ForEach` (`:1626`). `schema.TRANSITION_MIRROR` and
  `schema.TRANSITION_FADES` are exported for the coordinator.
- **Pattern:** closed authored vocabulary validated in `checkValue`. The model the
  other vocabularies follow.
- **Callers:** `src/render/transitions.luau`; the presenter's `presentToast`/
  `PresentOpts` reuse the same grammar (out of this area's scope).
- **Proof:** probe — `{ enter = "fade", duration = 1 }` → "unknown transition field
  'duration' (enter | exit | class | fade)"; `{ enter = "slideUp" }` → "unknown enter
  form 'slideUp' (one of fade | slide-up | …)". api.md:947-979.
- **Findings:** BP-F25 (the one semantic precondition — a fading form needs a
  `canvasGroup` node — fires at the first enter in `src/render/transitions.luau:149-164`,
  not at construction, unlike every other semantic rule in this layer;
  api.md:964-967 does not say when), BP-F21 (`LuauUI transition:` is a seventh
  error prefix).

### `tint` grammar — closed grammar
- **Shipped shape:** one ruling in `styling.checkTint`
  (`src/tokens/styling.luau:333-388`), wired into the schema as the `tint` logical
  type (`blueprint_schema.luau:399`) and read again by the adapter for a *reactive*
  value at the write site. Offered on exactly four classes via the shared `TINT`
  PropSpec (`:738-746`): `Box`, `Text`, `Image`, `Path`. Keys: `role|blend|from|
  direct|transparency`; the two forms are mutually exclusive; unknown keys are refused.
- **Pattern:** closed vocabulary with a single validator and three readers. No
  deviation.
- **Proof:** `tests/paint_extensions.spec.luau:126-131` asserts the class set both
  ways; api.md:169-215.
- **Findings:** BP-F8 (`tint: Bound<any>?` at every one of its four declaration sites —
  the grammar is fully closed at runtime and completely untyped at the boundary, which
  is the strongest `any` case in the layer), and the `Path`-refuses-`transparency`
  asymmetry recorded under `UI.Path`.

### Dimension tables (`Dim`, `Sides`) — value grammar
- **Shipped shape:** exported `Dim` / `SideValue` / `Sides` at `blueprint.luau:67-81`;
  runtime checks `dim` (`blueprint_schema.luau:215-258`) and `sides` (`:259-301`),
  over `DIM_TYPES` (7 kinds, `:93-104`) and `SIDE_KEYS`. Both accept a metric NAME in
  every numeric field, and both additionally accept a **list** of numbers/metric names
  that is summed (`:234-255`, `:278-298`).
- **Pattern:** closed logical types with a shared `metricName` ruling. No runtime
  deviation.
- **Proof:** `tests/authoring.spec.luau` "a bare number where a dimension belongs
  explains the dimension table", "an unknown dimension kind is rejected", "a bad
  padding side is rejected"; `tests/layout_vocabulary.spec.luau`; api.md:133, 137.
- **Findings:** BP-F9 (the exported types are strictly narrower than the runtime —
  the metric-list form is unexpressible, and `Dim.type: string` is an open alias over
  a closed 7-value set; `check_prop_parity` compares field *names* only,
  `tools/lune/check_prop_parity.luau:284-302`, so nothing catches it).

### Theme-metric-name grammar — value grammar
- **Shipped shape:** `metricName` (`blueprint_schema.luau:170-182`) — a spacing step
  or a dotted snapshot path, with a leading `-` negating it — reused by the `metric`
  logical type, by `dim`'s four numeric fields (`DIM_METRIC_FIELDS`, `:185`), by
  `sides`, by `scaleOffset`'s `offset`, and by `blueprint.Composition`'s inline group
  check (`blueprint.luau:566`). Resolution happens per solve in the renderer
  (`src/render/renderer.luau:404-421, 428-446`).
- **Pattern:** one predicate, many readers. The layer's cleanest shared ruling.
- **Proof:** `tests/authoring.spec.luau`, `tests/composition.spec.luau` (a metric
  `minWidth` re-arranges on a theme swap); api.md:151-161.
- **Findings:** BP-F12 (`Divider.thickness` and `Path.thickness` are the only
  theme-owned numbers in the schema declared `types = { "number" }` with no `"metric"`,
  and `Divider.thickness`'s own default *is* a metric —
  `src/render/renderer.luau:584-587` — while both the schema doc
  (`blueprint_schema.luau:1088`) and api.md:557 say "1 px").

---

# Part D — Schema, types and library metadata

### `UI.schema` (`forClass` / `propNames` / `deprecations` / …) — tooling accessor table
- **Shipped shape:** `blueprint.schema = schema` (`blueprint.luau:40`). Eleven members
  (probe): `TRANSITION_FADES`, `TRANSITION_MIRROR`, `all`, `checkValue`, `classNames`,
  `deprecations`, `forClass`, `propDirty`, `propNames`, `sharedPropNames`, `suggest`.
- **Pattern:** dot functions on a stateless module. Accessor semantics are **split**:
  `deprecations()` and `propDirty()` build a fresh table per call (probe: identity
  unstable), while `all()` and `forClass()` hand out the live authority table
  (probe: identity stable).
- **Callers:** in-repo only — `tools/lune/check_prop_parity.luau:263,406`,
  `tests/authoring.spec.luau:312,351`, `tests/paint_extensions.spec.luau:128`,
  `tests/button_shape.spec.luau:239`. No example, no game caller.
- **Proof:** `tests/authoring.spec.luau` "M0-A3: one reconciled property model"
  (5 cases, incl. "the live repository passes the property-parity check" and its two
  drift-injection cases); api.md:118-119.
- **Findings:** **BP-F5** (`all()`/`forClass()` return the live mutable tables —
  verified live: setting `UI.schema.all().Text.props.text.required = false` made
  `UI.Text{}` construct), BP-F20 (api.md advertises three of eleven members).

### Exported spec types (`UI.ButtonSpec`, `UI.ScreenSpec`, …) — public types
- **Shipped shape:** 24 `<Class>Spec` aliases plus `Blueprint`, `Readable<T>`,
  `Bound<T>`, `Metric`, `TypeRole`, `Dim`, `SideValue`, `Sides`, `PointerHandlers`,
  `BoxProps`, `ContainerProps`, `CompositionGroup`, `CompositionArrangement`,
  `RegionFloor`, `TransitionSpec`, `FrameSpec` (`blueprint.luau:28-310, 1009-1018`).
- **Pattern:** every constructor takes a named exported type, never a bare `any` —
  enforced by `check_prop_parity`'s field-set comparison and by
  `tests/authoring.spec.luau:364-381`.
- **Proof:** `check_prop_parity` PASS this session, 448 typed fields;
  `tests/authoring.spec.luau` "every class exports a spec type carrying its schema
  fields", "no public constructor takes a bare untyped spec"; api.md:116-119.
- **Findings:** BP-F8 (**the modifiers are exempt from the rule the constructors
  follow** — six public functions take `spec: any`, and the M0-A2 spec at
  `tests/authoring.spec.luau:374-381` only iterates `schema.classNames()`),
  BP-F9, BP-F10, BP-F28, BP-F29.

### `LuauUI.VERSION` — library metadata
- **Shipped shape:** `VERSION = "0.7.0"` (`src/init.luau:30`); baseline
  `public-surface-before.txt:1`.
- **Pattern:** a plain string constant, single source of truth. No deviation.
- **Proof:** `tests/api_surface.spec.luau:18-25` ("VERSION is a plain semver
  MAJOR.MINOR.PATCH") and `:27-31` (the ADR names the current version); api.md:17-22.
- **Findings:** the spec pins only `major == 0` and `minor >= 4`, so it would pass at
  `0.99.0` — recorded as weak-but-adequate proof, no finding raised.

### `LuauUI.DEPRECATIONS` — generated ledger
- **Shipped shape:** `require("@self/blueprint_schema").deprecations()` evaluated once
  at load (`src/init.luau:35-43`), typed inline. Two rows: `UI.Text.color` and
  `UI.Text.font`, both `since = "0.5.0"`, `removeNoEarlierThan = "0.6.0"`
  (`blueprint_schema.luau:1202-1223`); generation at `:1687-1718`.
- **Pattern:** derived-from-schema, sorted by class then prop. No deviation.
- **Callers:** `tests/api_surface.spec.luau`, `tests/authoring.spec.luau:189`.
- **Proof:** `tests/authoring.spec.luau` "every diagnosed property is in the ADR-0011
  ledger with all required fields"; `check_prop_parity` enforces that a diagnosed prop
  is not still wired (`tools/lune/check_prop_parity.luau:308-319`); api.md:24-37.
- **Findings:** BP-F19 (both rows are two minor versions past their own
  `removeNoEarlierThan` at `VERSION = 0.7.0`, and `src/init.luau:32-34` still says
  "Empty = nothing deprecated"; the array is also unfrozen — probe).

---

# Findings index

Severity: CRITICAL / MAJOR / MINOR / NOTE. Confidence: H / M / L.

- **BP-F1** `[MAJOR, H]` `UI.styleGroup` never validates its spec key set, so any key
  it does not know — including **`stroke`**, the fourth member of the style-modifier
  family — is silently dropped. — `src/blueprint.luau:960-985` reads only
  `spec.shadow` / `spec.gradient` / `spec.corners`; probe:
  `UI.styleGroup({ stroke = { thickness = 2 } }, { box })[1].props.stroke == nil`. —
  **Cost:** an author reaching for the collection form of `UI.stroke` gets no border
  on any element, with no error, and the singular form works — so the bug reads as a
  theme problem.
- **BP-F2** `[MAJOR, H]` `normalizeShadow` and `normalizeGradient` accept unknown spec
  keys silently, while `normalizeStroke` and `checkTint` refuse them. —
  `src/tokens/styling.luau:46-70` and `:223-260` (no key loop) vs `:407-412` and
  `:339-343`; probe: `UI.gradient(bp, { colors = {…}, roation = 45 })` constructs with
  `rotation == 90`. — **Cost:** a typo'd gradient/shadow field produces the default
  visual, which is the accepted-and-ignored class the whole strict boundary exists to
  remove — inside the two grammars that skipped it.
- **BP-F3** `[MAJOR, H]` `UI.background` **drops the content blueprint's `meta`
  channel** whenever it inflates a dimension-less backing layer. —
  `src/blueprint.luau:1161-1175` rebuilds `table.freeze{ class, id, props, children }`
  with no `meta`, unlike `withProps` at `:840` which carries it explicitly; probe:
  `UI.background(tile, UI.draggable(plate, { payload = 2 }))` →
  content `meta == nil`. — **Cost:** a drag declaration or an input contribution on
  the backing layer disappears silently, and only in the *common* case (no explicit
  width **and** height — the shape api.md:1182 and
  `tests/layout_vocabulary.spec.luau:438` document as normal). No spec pins meta
  survival through either structural modifier.
- **BP-F4** `[MAJOR, H]` Modifier errors are attributed to the **class and the internal
  prop name**, never to the modifier the author called. —
  `src/blueprint.luau:825-835` (`withProps` → `unknownPropError(bp.class, k)`); probe:
  `UI.alignment(When, "center")` → *"LuauUI UI.When: unknown property 'alignH'"*;
  `UI.aspectRatio(When, 1.5)` → *"unknown property 'height'"*;
  `UI.shadow`/`UI.corners`/`UI.stroke`/`UI.gradient`/`UI.offset`/`UI.frame` all the
  same. Only `UI.padding` (`:1069`) and `UI.frame`'s field check (`:1046`) name the
  modifier. — **Cost:** the message names a property the author never typed, on a
  class they may not have written, and lists that class's valid properties — none of
  which is the fix.
- **BP-F5** `[MAJOR, H]` `schema.all()` and `schema.forClass()` hand out the **live,
  unfrozen** authority tables. — `src/blueprint_schema.luau:1653-1659`; probe:
  `UI.schema.all().Text.props.text.required = false` then `UI.Text{}` **constructs**.
  Contrast `deprecations()`/`propDirty()`, which build fresh tables (`:1687-1718`,
  `:1672-1684`). — **Cost:** any consumer of the documented tooling seam can disable
  framework validation process-wide, and a well-meaning tool that annotates a
  `ClassSpec` mutates the shipped contract.
- **BP-F6** `[MAJOR, M]` api.md's shared-property **"Accepted on"** column and its
  Containers/Leaves list are wrong in both directions, and nothing checks them. —
  api.md:138 `gap` omits `AdaptiveStack` (`blueprint_schema.luau:909`) and `Button`
  (`:1276`); api.md:139 `align` omits the same two (`:910`, `:1277`); api.md:137
  `padding | containers, Button, Toggle, TextField` omits `Text` (`:1137`) and
  over-claims "containers" (`ViewThatFits` `:928` and `Region` `:992` have none);
  api.md:141/142 `clipChildren`/`active | containers` over-claim for `Button`,
  `ViewThatFits`, `Region`; api.md:163-165 lists **7** containers and calls `Button` a
  **leaf**, while the runtime lists **12** (probe: *"Containers: AdaptiveStack, Anchor,
  Button, Composition, Grid, HStack, Region, Screen, ScrollView, VStack, ViewThatFits,
  ZStack"*) and api.md:689 itself says "A Button takes `children`".
  `check_prop_parity` only greps for the prop **name** somewhere inside the `### UI`
  section (`tools/lune/check_prop_parity.luau:250-257`), so the accepted-on column is
  entirely unproven. — **Cost:** the one table an author reads to know where a prop is
  legal is wrong for six of its rows, and the code's own error text contradicts it.
- **BP-F7** `[MAJOR, M]` No public data producer for a **reactive** `shadow`,
  `gradient` or `corners`, although all three are `reactive = true, dirty = {"paint"}`
  (`blueprint_schema.luau:515-541`). — Probe: `UI.shadowData`, `UI.gradientData`,
  `UI.cornersData` are all `nil`; `UI.strokeData` (`src/blueprint.luau:931`) is the
  only one. The normalizers live in `src/tokens/styling`, which is not a public export.
  — **Cost:** the documented pulse idiom (api.md:1081-1094) exists for one of four
  siblings; a pulsing gradient or an animated corner radius is reachable only by
  `require`ing an internal module — a boundary violation the framework otherwise
  refuses.
- **BP-F8** `[MINOR, H]` Six public modifier boundaries take or return bare `any`, and
  five authored value grammars have no exported type. — `src/blueprint.luau:844`
  (`shadow`), `:901` (`gradient`), `:908` (`corners`), `:923` (`stroke`), `:931`
  (`strokeData(spec: any, style: any?) -> any`), plus `BoxProps.shadow/gradient/
  corners/stroke: Bound<any>?` (`:103-107`) and `tint: Bound<any>?` at all four
  declaration sites (`:195, 213, 219, 277`). Contrast the typed siblings
  `UI.frame(bp, FrameSpec)` (`:1035`) and `UI.draggable(bp, dragContract.SourceSpec)`
  (`:949`). The M0-A2 rule that forbids this only iterates class constructors
  (`tests/authoring.spec.luau:374-381`). — **Cost:** no editor completion and no type
  error for the exact grammars whose typos BP-F1/BP-F2 show are silently ignored.
- **BP-F9** `[MINOR, H]` Exported `Dim` and `Sides` are strictly **narrower** than the
  runtime schema. — The schema accepts a summed **list** of numbers/metric names in
  `px|min|max|preferred` (`blueprint_schema.luau:234-255`) and per side (`:278-298`);
  `Dim.px: (number | Metric)?` (`src/blueprint.luau:70`) and `Sides` (`:80-81`) cannot
  express it. `Dim.type: string` (`:68`) is an open alias over the closed 7-value
  `DIM_TYPES` (`:93-104`). `check_prop_parity` compares field *names* only
  (`tools/lune/check_prop_parity.luau:284-302`). — **Cost:** a documented, shipped
  authoring form type-errors; typo'd dim kinds are caught only at runtime.
- **BP-F10** `[MINOR, H]` `CompositionArrangement` omits the documented `eligible`
  field. — `src/blueprint.luau:163` = `string | { name: string, lanes: { { string } } }`;
  api.md:956 documents `eligible?`; the constructor reads it
  (`src/blueprint.luau:592`) and the normalizer legalises it
  (`src/layout/composition.luau:340-363`); probe constructed one successfully. —
  **Cost:** the documented gating form is a type error under `--!strict`.
- **BP-F11** `[MINOR, H]` `overflow` is accepted on nine container classes and drives
  **nothing**. — It is copied into the solve output (`src/layout/solver.luau:981`),
  read only to suppress an overflow diagnostic (`:1317`), **overwritten** by the solver
  on a `ScrollView` (`:1161-1163`), and otherwise reaches only the layout dump
  (`src/layout/dump.luau:17`). Probe: `UI.VStack{ overflow = "clip" }` leaves
  `clipChildren` nil. No example and no RascalRally file authors it. — **Cost:**
  `"clip"` and `"scroll"` are second public spellings of `clipChildren` and
  `UI.ScrollView` that do not do the thing they name; api.md:140 calls it "declared
  overflow handling" without saying it is declaration-only.
- **BP-F12** `[MINOR, H]` `Divider.thickness`: the documented default is wrong, and it
  is the one theme-owned number that refuses the metric-name grammar. —
  `blueprint_schema.luau:1088` and api.md:557 both say "default 1 px"; the renderer
  defaults to `metrics.strokes.hairline` (`src/render/renderer.luau:584-587`).
  `types = { "number" }` (`:1084`, and `Path.thickness` at `:1550`) rejects
  `"strokes.hairline"` even though the default *is* that metric. — **Cost:** an author
  who wants a theme-tracking rule thickness cannot say so, and the doc misdescribes
  what they get by default.
- **BP-F13** `[MINOR, H]` Optional-spec inconsistency across constructors with no
  required prop. — `ScrollView` (`src/blueprint.luau:457`), `Spacer` (`:468`) and
  `Divider` (`:613`) take `spec?`; `Screen`/`VStack`/`HStack`/`ZStack`/`Anchor`/`Grid`/
  `Box`/`ViewThatFits` have no required prop either and reject nil (probe:
  *"LuauUI UI.Screen: the constructor takes one spec table, got nil"*). — **Cost:**
  small, but the rule for "may I omit the table?" is unlearnable.
- **BP-F14** `[MINOR, H]` `id` and `children` live outside the schema, so a typo of
  either gets no suggestion and `children` has no declared type or required flag. —
  `src/blueprint.luau:405-422` handles both before the `known[k]` lookup;
  `schema.suggest` iterates `spec.props` only
  (`src/blueprint_schema.luau:1749-1762`). Probe: `UI.Text{ idd = "x" }` and
  `UI.VStack{ childern = {} }` list every valid property and never suggest `id` /
  `children`. The "children are required" rule is three hand-written constructor
  checks (`src/blueprint.luau:492-499`, `:514-520`, `:531-533`) invisible to tooling.
  — **Cost:** the two most-typed keys in the layer are the two the suggester cannot
  help with.
- **BP-F15** `[MINOR, M]` `UI.draggable` / `UI.dropTarget` apply **no class gate**. —
  `src/input/drag_contract.luau:184-197` checks only `type(bp.class) == "string"`;
  probe: `UI.draggable(UI.When{ … }, { payload = 1 })` succeeds. The renderer's
  registration site sits inside the per-instance branch of `ensureTree`
  (`src/render/renderer.luau:1380-1385`), which a structural node never reaches. —
  **Cost:** a drag declaration on `When`/`ForEach`/`ErrorBoundary` (a plausible
  mistake when wrapping a conditional card) is accepted and inert. Every other
  modifier is gated by the schema.
- **BP-F16** `[MINOR, M]` `UI.TextField{ maxLength }` and `{ keyboardType }` are
  declared binding props whose adapter branches write nothing on a shipping client. —
  `src/client/screen_target.luau:3512-3514` ("no engine property enforces this …
  data-only") and `:3498-3510` (gated on `canSetTextInputType`, false on game
  scripts). Enforcement lives in the composite's value model
  (`src/controls/text_input.luau:280-285`). api.md:848-860 says both "ride the binding
  authority" and never says the raw primitive enforces nothing (the *schema* doc does,
  `blueprint_schema.luau:1470`). — **Cost:** `UI.TextField{ maxLength = 8 }` looks like
  a limit and is not one.
- **BP-F17** `[MINOR, M]` `UI.PROP_DIRTY` and `UI.isReadable` are public and
  documented nowhere, and the registration checker structurally cannot see them. —
  baseline `public-surface-before.txt:15, 36`; `src/blueprint.luau:318, 330`;
  `tools/lune/check_registration.luau:166` scans only
  `string.gmatch(blueprintSource, "function blueprint%.(%w+)")`, so a table field or an
  `= f` assignment is invisible to the drift check that api.md claims covers "every
  `UI.*` constructor". `UI.PROP_DIRTY` is unfrozen (probe) and **is** the live map
  `src/mount.luau:502` reads. — **Cost:** two undocumented exports, one of which is a
  mutable handle on mount-time subscription behaviour.
- **BP-F18** `[MINOR, M]` Blueprint immutability is one level deep. — `make` freezes
  the node but not `props` or `children` (`src/blueprint.luau:440-441`); probe mutated
  `bp.props.surface` and `table.insert`ed into `bp.children`, both successfully.
  api.md:95-96 says "Blueprints are immutable plain tables" and the whole
  modifier-returns-a-new-blueprint contract (`src/blueprint.luau:988-992`, spec case
  "a modifier never mutates the blueprint it was given") rests on it. — **Cost:** a
  shared template blueprint reused across rows can be mutated in place, defeating the
  purity the layer advertises; the spec that "proves" immutability only checks that
  the *modifiers* do not do it.
- **BP-F19** `[MINOR, M]` Both deprecation rows are past their own removal window. —
  `UI.Text.color` / `UI.Text.font`, `since = 0.5.0`, `removeNoEarlierThan = 0.6.0`
  (`src/blueprint_schema.luau:1202-1223`), with `VERSION = "0.7.0"`
  (`src/init.luau:30`; probe printed both rows against the version). `src/init.luau:32-34`
  still comments "Empty = nothing deprecated", and `LuauUI.DEPRECATIONS` is unfrozen
  (probe). — **Cost:** ADR-0011's window is a promise the ledger has silently
  outlived; nothing in the gate notices.
- **BP-F20** `[MINOR, M]` `UI.schema` is advertised as three members and ships eleven.
  — api.md:118-119 "(`forClass`, `propNames`, `deprecations`)" vs the probe's
  `TRANSITION_FADES, TRANSITION_MIRROR, all, checkValue, classNames, deprecations,
  forClass, propDirty, propNames, sharedPropNames, suggest`. — **Cost:** eight public
  functions with no documented contract, no stated stability, and (per BP-F5) one that
  can break the framework.
- **BP-F21** `[MINOR, M]` Seven distinct error-message prefixes inside one layer. —
  `LuauUI UI.{Class}.{prop} …` (`src/blueprint.luau:366, 385`),
  `LuauUI UI.{Class}: …` (`:354, 395`), `LuauUI UI.{modifier}: …` (`:1037, 1046,
  1069, 1093, 1125`), `LuauUI: {entry} cannot …` (`:882, 892`),
  `LuauUI drag: …` (`src/input/drag_contract.luau:186`),
  `LuauUI transition: …` (`src/render/transitions.luau:157`), and bare Lua `assert`s
  that leak a source location into the text (`src/tokens/styling.luau:50, 53, 57, 92,
  100, 107, 225, 406-412` — probe output shows
  `…/LuauUI/src/tokens/styling:408: unknown stroke field 'thicknes'`). — **Cost:** the
  style modifiers, which are the most typo-prone surface, produce the least
  LuauUI-shaped errors; an agent grepping for `LuauUI UI.` misses them.
- **BP-F22** `[NOTE, H]` `axis` is one word with two reactivity answers. — Probe:
  `ScrollView.axis reactive = false` (`blueprint_schema.luau:810-816`),
  `AdaptiveStack.axis reactive = true` (`:914-921`), `Divider.axis reactive = true`
  (`:1075-1082`). Deliberate — `AdaptiveStack` exists for the reactive case — but
  api.md:263 and :361 each state only their own answer, so nothing tells an author why
  a `ScrollView` cannot flip.
- **BP-F23** `[NOTE, H]` `focusable` is one word with two polarities: opt-**OUT** on
  `Button`/`Toggle`/`TextField` (`FOCUSABLE_OPT_OUT`, `blueprint_schema.luau:748-755`),
  opt-**IN** on `Grip` (`:1504-1510`). Documented at api.md:148. **Candidate
  intentional exception.**
- **BP-F24** `[NOTE, H]` `Image.scaleMode` ships `fill` and `crop` as declared
  synonyms (`blueprint_schema.luau:1252-1256`; api.md:671-673, "Roblox's `Crop` *is*
  the cover behaviour other vocabularies call fill"). **Candidate intentional
  exception** — flagged only because it is the duplicate-vocabulary class the stage
  asked about, and it is declared in both the schema and the reference, which is the
  correct way to ship one.
- **BP-F25** `[NOTE, M]` The `transition` grammar is construction-strict about its
  shape and **not** about its one precondition. — Shape/forms/keys are checked in
  `checkValue` (`blueprint_schema.luau:367-396`), but "a fading form needs a
  `canvasGroup` node" throws at the first enter
  (`src/render/transitions.luau:149-164`). api.md:964-967 calls it "an authoring error
  that names the fix" without saying when it fires. Contrast `Button.icon` and
  `Button.compactLabel`, whose semantic rules do fire at construction.
- **BP-F26** `[NOTE, M]` `UI.aspectRatio` can only ever derive the **height** and
  silently overwrites an authored one. — `src/blueprint.luau:1091-1098`; probe:
  `fixed/40` → `aspect/1.5`. The solver's `aspect` dim works on either axis
  (`blueprint_schema.luau:103`). Covered by the documented last-writer-wins rule
  (api.md:1170-1172), hence a NOTE rather than a defect.
- **BP-F27** `[NOTE, M]` `UI.offset(bp, x: number?, y: number?)` is typed narrower than
  the props it writes. — `src/blueprint.luau:1079` vs
  `blueprint_schema.luau:477-494` (`number | scaleOffset | metric`); probe passed both
  `"s"` and `{ scale = 0.5 }` through it successfully at runtime.
- **BP-F28** `[NOTE, M]` `ScrollViewSpec.autoscroll: (boolean | { [string]: any })?`
  (`src/blueprint.luau:131`) — an untyped options bag whose keys api.md:283-285 spells
  out concretely (`bandH`, `dwellS`, `rampS`, `exitEaseS`, `vMin`, `vMax`).
- **BP-F29** `[NOTE, L]` Two more `any`s at callback boundaries:
  `ForEachSpec.row: (item: any, itemScope: any) -> Blueprint`
  (`src/blueprint.luau:302`) — `itemScope` is a core Scope with an exported type —
  and `PointerHandlers.rectOf: (string) -> any` (`:85-87`), which returns a rect.
- **BP-F30** `[NOTE, M]` `Region` is the only container whose props omit the shared
  `BOX` group (`blueprint_schema.luau:992`; probe: `UI.Region{ width = … }` refused).
  Deliberate and self-consistent (`RegionSpec`, `src/blueprint.luau:172-183`, does not
  extend `BoxProps`), recorded so api.md:133's "every rendered class" is read against
  it. **Candidate intentional exception.**
- **BP-F31** `[NOTE, M]` `Screen` and `VStack` share a byte-identical schema
  (`blueprint_schema.luau:781-796`); the only behavioural difference is the renderer
  defaulting `Screen`'s dims to `fill` (`src/render/renderer.luau:576-578`). Two
  public words for one layout behaviour plus one default. Deliberate (presenter-root
  semantics, api.md:219-220). **Candidate intentional exception.**
- **BP-F32** `[NOTE, L]` Two copies of the same "is this a Readable" predicate:
  `blueprint.isReadable` (`src/blueprint.luau:327-330`) and the schema's `readable`
  logical type (`src/blueprint_schema.luau:209-214`). Cosmetic; they agree today.

**Counts:** 7 MAJOR, 14 MINOR, 11 NOTE, 0 CRITICAL. Of the NOTEs, five (BP-F23,
BP-F24, BP-F30, BP-F31, and the `styleGroup` argument order recorded under Part B)
are flagged as candidate **intentional exceptions**, not repairs.

---

## Coverage

Every assigned item has an entry above.

**Constructors (24/24):** `Screen` ✓ · `VStack` ✓ · `HStack` ✓ · `ZStack` ✓ ·
`ScrollView` ✓ · `Anchor` ✓ · `AdaptiveStack` ✓ · `ViewThatFits` ✓ ·
`Composition` ✓ · `Region` ✓ · `Divider` ✓ · `Grid` ✓ · `Text` ✓ · `Image` ✓ ·
`Button` ✓ · `Toggle` ✓ · `TextField` ✓ · `Box` ✓ · `Spacer` ✓ · `Path` ✓ ·
`Grip` ✓ · `When` ✓ · `ForEach` ✓ · `ErrorBoundary` ✓.
(Spec-table conventions, `id`/required-prop rules, shared properties, strict schema
validation and reactive-prop acceptance are covered per entry plus in Part C and
BP-F13/F14/F22.)

**Modifiers (14/14):** `shadow` ✓ · `gradient` ✓ · `corners` ✓ · `stroke` ✓ ·
`strokeData` ✓ · `styleGroup` ✓ · `frame` ✓ · `padding` ✓ · `offset` ✓ ·
`aspectRatio` ✓ · `alignment` ✓ · `overlay` ✓ · `background` ✓ · `draggable` ✓ ·
`dropTarget` ✓ (15 with the `draggable`/`dropTarget` pair counted separately).

**Vocabularies (4/4):** structural-transition vocabulary ✓ · `tint` grammar ✓ ·
dimension tables (`Dim`/`Sides`) ✓ · theme-metric-name grammar ✓.

**Metadata (4/4):** `UI.schema` (`forClass`/`propNames`/`deprecations` and the eight
undocumented members) ✓ · exported spec types ✓ · `LuauUI.VERSION` ✓ ·
`LuauUI.DEPRECATIONS` ✓.

### Public but unassigned (reported, not audited in depth)

- **`UI.isReadable`** (`src/blueprint.luau:330`) — public per
  `baseline/public-surface-before.txt:36`, undocumented, invisible to
  `check_registration`. See BP-F17 / BP-F32.
- **`UI.PROP_DIRTY`** (`src/blueprint.luau:318`) — public per
  `baseline/public-surface-before.txt:15`, undocumented, unfrozen, and the live map
  `src/mount.luau:502` reads. See BP-F17.
- **`UI.Blueprint`** and the sixteen non-`<Class>Spec` exported types (`Readable<T>`,
  `Bound<T>`, `Metric`, `TypeRole`, `Dim`, `SideValue`, `Sides`, `PointerHandlers`,
  `BoxProps`, `ContainerProps`, `CompositionGroup`, `CompositionArrangement`,
  `RegionFloor`, `TransitionSpec`, `FrameSpec`, `Deprecation`/`PropSpec`/`ClassSpec`
  re-exported through `UI.schema`) — type-only surface with no api.md heading of its
  own; touched here only where BP-F9/F10/F28/F29 bite.
- **`src/tokens/styling`** (`normalizeShadow`/`normalizeGradient`/`normalizeCorners`/
  `normalizeStroke`/`checkTint`/`hexRgb`/`GRADIENT_ALPHA_MAX`) — not exported from
  `src/init.luau`, but it is the only route to a reactive shadow/gradient/corners
  (BP-F7), so it is a de-facto boundary. Belongs to the styling/theme area.
- **`src/input/drag_contract`** (`SourceSpec`, `TargetSpec`, `SOURCE_PROP`,
  `TARGET_PROP`, `attach`) — reached through `UI.draggable`/`UI.dropTarget`; its
  `attach` gate is BP-F15. Belongs to the input/drag area.
