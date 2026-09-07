# Inherited `tint` and inherited disabled subtrees — design

Stream C of the 2026-09-07 stabilization pass
(`docs/plans/2026-09-07-facet-stabilization-plan.md` section C). This note is
written before the code, and the code follows it.

---

## 1. What is there today (the investigation)

### 1.1 `enabled`

`enabled` is declared on exactly three classes, all leaves of the interaction
model, and every one of them declares it as a `binding` prop:

| Where | What it says |
|---|---|
| `src/blueprint_schema.luau:2289` | `Button.enabled` — "false removes the control from focus and activation and paints the disabled state" |
| `src/blueprint_schema.luau:2389` | `Toggle.enabled` |
| `src/blueprint_schema.luau:2442` | `TextField.enabled` |
| `src/render/authority.luau:125,150,163` | `enabled = "binding"` for those three classes and nobody else |
| `src/render/prop_channels.luau:30` | `BINDING_PROPS.enabled` — no class restriction |

One predicate reads it off a mounted node, and everything that has to agree
about "disabled" calls that one predicate:

| Reader | Line | What it decides |
|---|---|---|
| `src/present/focus_map.luau:30` `isDisabled(node)` | `node.props.enabled == false` | the definition |
| `src/present/focus_map.luau:55` `focusWalk` | | a disabled control is not a focus stop |
| `src/present/presenter.luau:282,399` `dispatchActivate` | | Activate is consumed and does nothing — **before** the consumer override (finding V12) |
| `src/render/renderer.luau:1120` | `declNode.props.enabled == false` | a disabled drag source acquires nothing |
| `src/render/renderer.luau:1174` | `tapNode.props.enabled ~= false` | a synthesized detector tap on a disabled node taps nothing |
| `src/render/renderer.luau:3593` `controller.tapAt` | `node.props.enabled ~= false` | pointer/touch hit testing skips it |

Composite controls read the **spec** value through one shared policy,
`src/class_contract.luau:194` `enabledNow` / `:204` `enabledIn` ("WHAT `enabled`
MEANS, decided once"), and forward `spec.enabled` down to the primitive
(`slider.luau:162,267`, `stepper.luau:102,135,141`, `picker.luau:526,620`,
`disclosure_group.luau:70`, `level_picker.luau:341`). `menu.luau:847,1068` reads
a per-item `enabled` through its own `readFact`. `Grip` has **no** `enabled`
prop at all: a Slider binds the Grip's opt-in `focusable` to the control's
enabled reading instead (`slider.luau:262-267`).

Paint: `src/client/screen_props.luau:632` is the adapter branch. For a `TextBox`
it writes `TextEditable` + `Interactable`; for a `TextButton`, `Active` +
`Interactable`; then `mirrorToHitExpander`. In native-sheet mode the dim itself
is a **rule**, not a write — `sheet_model.luau:2830,2833` emit
`TextButton:NonInteractable` and `TextBox:NonInteractable` in the `disabled`
rule group at `baseExtra.disabledContentOpacity`. Nothing paints a disabled
state on a non-control node, because nothing can currently *be* disabled except
those three classes.

### 1.2 `tint`

One value vocabulary, one resolver, one claim:

| Where | What |
|---|---|
| `src/blueprint_schema.luau:1487` `TINT` | the prop spec — reactive, `dirty = { "paint" }`, `channel = "binding"` |
| `src/tokens/styling.luau:399` `checkTint` | the ONE ruling on a legal value; three readers (schema, adapter write site, docs) |
| `src/tokens/styling.luau:354` `TINT_ROLES` | the closed palette vocabulary, asserted equal to the chrome recipes' resting-tint set |
| `src/tokens/sheet_model.luau:1496` `tintColor` | theme role → `{r,g,b}`, resolved against the **active theme** |
| `src/tokens/sheet_model.luau:76` `TAGS.tintFill` | `facet-tint-fill` — the FILL a tinted Box needs is a tag, not a claim |
| `src/render/authority.luau:102,109,176,181,188` | `tint = "binding"` on `Box`, `Text`, `Image`, `Path`, `Stage` — and nowhere else |
| `src/client/screen_paint.luau:172` `applyTint` | the claim + `handle.tintFill` |
| `src/render/renderer.luau:1336` | creation-time application, deliberately LAST |

**The load-bearing fact for this design: every class that accepts a `tint`
today is `container = false`.** `Box`, `Text`, `Image`, `Path` and `Stage` are
all childless leaves (`blueprint_schema.luau:2050,2077,2192,2562,2611`). So a
tint has never had a descendant to reach, and giving it one cannot change what
any shipped screen paints.

### 1.3 How a per-subtree fact flows today

Three shapes already exist, and each answers a different question:

1. **`mount.luau:739`, the `sensoryFeedback` cascade.** `activationFeedback` is
   threaded down `mountNode` as a parameter, resolved as `own or inherited`, and
   stored on the node. Mount is the place "because this is the only walk that
   sees a blueprint's ancestors and its mounted node at the same moment". It is
   read, not observed: the declaration is frozen into the blueprint.
   `mount.luau:44` threads `STACK_PARENT` down the same way.
2. **`hidden`**, a subtree fact resolved by **path prefix** — `renderer.luau:621`
   `authoredHidden`, `focus_map.luau` `isHiddenPath`, and the solver's own
   `hiddenDepth` counter (`solver.luau:2511`). It works because "hidden" needs
   no per-node value and the solver re-derives it every solve.
3. **The environment** (`src/env/environment.luau`, `surface_env.luau`) — facts
   for a whole *surface*, not a subtree. There is no per-subtree environment
   scope, and inventing one would be a second adaptation authority
   (constitution §10).

Nothing today cascades a **reactive per-node value** down a subtree. That is
the gap this note closes.

---

## 2. Public API

Two existing property names, on the classes that can have descendants. No new
public word.

### 2.1 `enabled` on containers

`enabled` joins the shared container property set (`CONTAINER_LAYOUT` in the
schema, `ContainerProps` in the exported types), which puts it on `Screen`,
`VStack`, `HStack`, `ZStack`, `ScrollView`, `Anchor`, `Grid`, `AdaptiveStack`
and `Composition`. It keeps its exact meaning on `Button`, `Toggle` and
`TextField`, and gains one sentence: **it applies to the node's whole subtree.**

```lua
UI.VStack({ id = "Panel", enabled = paused, children = { … } })
```

`GridRow`, `Region` and `ViewThatFits` do **not** get it, for the reason they
carry no other container property (constitution E-5 and the `GridRowSpec`
comment): their children are cells / ranked forms / candidates that the parent
owns. A cascade still passes *through* them, so a disabled `Composition`
disables the buttons inside its regions.

### 2.2 `tint` on containers

`tint` joins the same shared set, with the same value vocabulary
(`styling.checkTint`), the same theme roles and the same reactivity. On a
container it paints nothing of its own — a container has no paint channel; its
plate is `surface` — so it is purely **the tint its subtree inherits**.

```lua
UI.VStack({ id = "Team", tint = { role = "accent", blend = teamHeat }, children = { … } })
```

`Button`, `Toggle` and `TextField` deliberately do **not** gain `tint`: the
`TINT` block already rules that a continuous colour on a control "would be a
second, competing authority over the affordance the state machine owns"
(`blueprint_schema.luau:1479`).

### 2.3 Precedence, decided

**Disabled is a conjunction down the tree.**

- A node is disabled when it declares `enabled = false`, **or** any ancestor
  does.
- An ancestor **cannot** re-enable a descendant that declares `enabled = false`.
  `enabled = true` on an ancestor of a node that declares `false` changes
  nothing; `enabled = true` on a descendant of a disabled ancestor changes
  nothing either. There is no `enabled = "inherit"`, and no escape hatch: a
  subtree that is off is off.
- Nearest ancestor wins over farther is therefore vacuous for `enabled` — any
  `false` anywhere on the path wins.

**Tint is a nearest-declaration cascade.**

- A node paints the tint it declares itself; failing that, the tint declared by
  its **nearest** ancestor that declares one; failing that, none.
- A nested container's `tint` replaces the outer one for its own subtree.
- The inherited tint lands on every descendant whose class paints one — `Box`,
  `Text`, `Image`, `Path`, `Stage` — and paints that class's own channel,
  exactly as if the value had been written on that node. It reaches nothing
  else, because nothing else has a channel to paint it into.
- **The cascade does not enter a control's interior.** A `Button`, `Toggle` or
  `TextField` stops it for its own subtree, for the §2.2 reason: inside a
  control, paint belongs to the role and the state machine. (Nothing stops it
  from *painting the control's siblings*; only the control's own children.)

### 2.4 What a non-control descendant looks like when disabled

Through the sheet, never through a literal. One new classification tag,
`facet-state-disabled`, joins the closed vocabulary in
`tokens/chrome_slots.luau`, minted by `sheet_model.classifyTags` from a new
`disabled` hint exactly as `errorState` is minted today. Both sheet builders
emit one rule for it in the existing `disabled` rule group:

```
.facet-state-disabled  ->  TextTransparency  = disabledContentOpacity
.facet-state-disabled  ->  ImageTransparency = disabledContentOpacity
```

`disabledContentOpacity` is already the theme-owned number the two
`:NonInteractable` rules use (`sheet_model.luau:825,2830`), so a package that
retunes it retunes this, and a package that ships its own rules can override it
by priority like any other. The three control classes keep their engine-state
rules as well; the tag's value is the same number, so nothing double-dims.

**AS BUILT: text only.** The design above also proposed an
`ImageLabel.facet-state-disabled -> ImageTransparency` rule, and the framework's
own lint refuses it: image paint is legal in a theme rule only inside a nineSlice
chrome recipe, where the slot is what makes the picture meaningful
(`themes/package.lintProperty`), and `buildPackage` lints the rules it generates by
that same test. Reaching around that would have been a special case for the
framework's own rules against a rule the framework enforces on everyone else. So a
picture inside a disabled subtree keeps its own paint, `api.md` says so, and the
answer for a picture that should dim with its panel is a `tint`.

The tag reaches the adapter through the property Facet already has for this:
`enabled`. See §3.3.

### 2.5 What the public documents will say

- `docs/reference/api.md` — the shared box/container property table gains
  `enabled` and `tint` rows, and a short **Inheritance** subsection states the
  two precedence rules above in one paragraph each.
- `docs/guide/README.md` — one capability-catalog line.
- `docs/guide/05-styling.md` — the tint cascade beside the tint section.
- `docs/guide/07-input.md` — the disabled subtree beside the focus rules.
- `CHANGELOG.md` — Added (two properties) and Changed (`enabled` now means the
  subtree).

---

## 3. Where each value is resolved

### 3.1 One authority: `src/mount.luau`

Both cascades are resolved in the mount walk, for the reason
`mount.luau:727` already gives for `sensoryFeedback`: it is the only pass that
sees a blueprint's ancestors and its mounted node at the same moment. Three more
reasons make it the right owner *here*:

- Every reader of "disabled" reads a **mounted node** — the focus map, the
  presenter, the renderer's three gates. A fact resolved anywhere else would
  have to be looked up by ancestry at each of those sites, which is six walks
  and six chances to disagree.
- Mount already owns per-node scopes and the dirty queue, so reactivity and
  teardown need no new machinery: the same `core:observe` that publishes a
  bound prop publishes a cascade change, and the same `pushDirty` wakes the
  renderer.
- Mount is engine-free, so the whole cascade is provable headlessly.

The resolved facts are stored on the mounted node as **derived fields**, never
folded into `node.props` — `props` stays "what the author declared", which is
what makes "does this node override?" answerable:

```
node.disabled        boolean?   this node is inside (or is) a disabled subtree
node.inheritedTint   tint?      the tint this node paints, when it declared none
```

Both are `nil` on an undeclared tree.

**AS BUILT, AND THE FIRST VERSION OF THIS PARAGRAPH WAS WRONG.** It claimed the
off path "pays one table read per node and stores nothing"; it in fact called
`applyInherited` on every node, which wrote four fields and returned four values
whether or not anything was declared. Measured on a 3,281-node tree that declares
neither channel, best of twelve: **1.73–1.79 ms against a 1.13–1.20 ms
baseline — about half a mount again**, for a feature that tree does not use. The
existing bench could not see it: all fifteen scenes measure an update or a churn
and none of them mounts a tree.

Two guards now make the sentence true. `applyInherited` returns immediately when
nothing above declared, nothing here declares, and nothing was resolved on a
previous pass; and the mount call site does not make the call at all in that case,
because a *fresh* node has no previous resolution, so "nothing above plus nothing
here" is the whole test there and `inherited` is itself the answer to hand down.
Interleaved A/B after both: **base 1.09–1.17, live 1.18–1.20**. `recascade` still
calls unconditionally — it runs on a flip, where the previous state is exactly
what has to be cleared. Two bench scenes, `mount-ramp` and
`mount-ramp-inherited`, now measure this so the next regression is visible.

**Reactivity.** A container's `enabled` / `tint` is an ordinary reactive prop:
mount's existing per-prop observer writes `node.props`, and a cascade hook then
recomputes the node and re-walks its subtree, pushing the declared dirty classes
for every descendant whose resolved value actually changed. The walk is
`O(subtree)` and runs only on a flip — a gesture, not a frame. No remount:
identity, focus, scroll and in-flight state survive (constitution §10, "re-solve,
never rebuild").

**AS BUILT: the stop condition is what a node HANDS DOWN, not what it wears.** The
first draft stopped the walk where the node's own derived fields had not moved,
and that is wrong for the most common case in the feature: a container that
declares its OWN tint never moves when that tint changes — its `inheritedTint` is
`nil` either way — while every descendant does. So each node also records the
record it hands its children (`node.inheritOut`), and the walk descends exactly
when that record changed by value. A node whose outgoing record is unchanged is a
subtree that cannot have changed, because every answer under it was computed from
it.

**AS BUILT: a structural region is walked THROUGH, never dirtied.** `When`,
`ForEach` and `ErrorBoundary` nodes carry no `props` and no `dirty` table — they
materialize nothing — so the walk resolves them (their children need the record)
and pushes no queue entry for them. They are also resolved at mount, not only on a
flip: a region that had never recorded an outgoing record would report "the same
answer as before" the first time an ancestor flipped, and stop the walk at its own
door with its branch still disabled.

**Structural regions.** `When` / `ForEach` / `ErrorBoundary` mount children
later, so each region node remembers the inheritance record it was handed and
hands the current one to whatever it mounts, exactly as `inheritedActivation` is
threaded today. A branch re-entered later re-inherits from the same place.

**Lifecycle.** The cascade adds no subscription and no handle: the observers are
the ones mount already owns on the declaring node's props, and the derived
fields die with the node table. Dispose mid-disabled therefore leaves nothing
behind, and the existing mounted/factoryRuns counters are untouched.

### 3.2 The disabled channel: `enabled`, resolved

`class_contract.luau` — the file that already owns "WHAT `enabled` MEANS,
decided once", and which requires nothing so every layer may read it — gains the
third spelling beside `enabledNow` / `enabledIn`:

```lua
contract.isDisabled(node)   -- the MOUNTED-NODE reading
```

`= node.disabled == true or node.props.enabled == false`. Two terms because
there are two truths: what mount resolved, and what the author declared on a
node that a hand-built test tree may never have run through mount.

`present/focus_map.luau` keeps exporting `isDisabled` (its callers do not
change) and delegates to that one function; `renderer.luau`'s three inline reads
call it too. The result is that **every** interaction path — activation, focus
entry, Tab / arrow / pad traversal, pointer, touch, keyboard, gamepad, drag
acquisition, detector taps and everything a row's or menu's secondary gesture is
routed through — is blocked by the same predicate that already blocked a
disabled Button, with no new gate anywhere.

One gap in that set is closed while we are here: `focusWalk`'s `Grip` branch
(`focus_map.luau:52`) never consulted `isDisabled`, so a focusable Grip — a
Slider's track, a Rating's strip — stayed in the focus ring. It does now.

### 3.3 The disabled channel reaching paint

`enabled` is already an emitted binding prop with an adapter branch. The
resolved value rides it:

- `render/authority.luau` gains `common.enabled = "binding"`, so a node of any
  class may carry it (the three per-class rows stay, and say the same thing).
- `renderer.applyProp` writes the **resolved** value for `enabled`
  (`not isDisabled(node)`) rather than the authored one, so a control disabled
  by an ancestor really is non-interactable in the engine.
- `renderer.applyProps` emits `enabled` at creation for a node that is disabled
  but declared nothing, which is the only case the props loop cannot see.
- `client/screen_props.luau`'s `enabled` branch keeps its `TextBox` / `TextButton`
  engine writes and additionally records `handle.disabledState` and re-syncs
  tags, so every class gets `facet-state-disabled` in native mode.
- `client/screen_target.luau`'s `syncTags` passes it into `classifyTags`, which
  is what keeps the tag in the desired set — a tag added anywhere else survives
  exactly until the next classification pass.

No new emitted property, no second state channel: the fact has one name
(`enabled`), one resolved reading (`isDisabled`), and one write site.

### 3.4 The tint channel

- `render/prop_channels.luau` gains `BINDING_PROP_CLASSES.tint = { Box, Text,
  Image, Path, Stage }` — the allowlist the renderer already uses for
  `thickness`, and the thing `check_prop_parity` view 7 pins against the
  authority manifest. A container carrying a `tint` therefore emits nothing,
  and only the five painting classes ever reach `adapter.setProp`.
- `renderer.applyProp` falls back to `node.inheritedTint` when the node declared
  none; the creation-time tint write gains the same fallback and the class gate.
- Everything downstream is unchanged: `sheet_model.tintColor` resolves the role
  against the **active theme**, the claim is recorded, a theme commit
  re-resolves it, and the `facet-tint-fill` tag still carries a Box's fill. An
  inherited tint is byte-identical to the same tint written on the node.

### 3.4a AS BUILT: the render side is a sibling module

`src/render/inherited.luau` holds the two lines of policy the renderer needs —
`resolve(node, prop, declared)`, `needsEnabledWrite(node)`, `hasTint(node)`, and a
re-export of `isDisabled` — for the reason `prop_channels`, `layout_node` and
`presentation_channel` were taken out of `renderer.luau`: the renderer is within a
couple of thousand characters of the 200,000-character `Source` write cap. Nothing
in it reads a `renderer.attach` upvalue, so the extraction is one-way by
construction. `renderer.luau` grew by 227 characters, all of them call sites.

One more render-side edit came out of the same work and is worth naming: the
refresh loop dispatched a paint entry on `BINDING_PROPS[entry.prop]`, which is the
class-BLIND set, while creation dispatched on `emitsBinding(class, prop)`, the
class-restricted one. Both now use `emitsBinding`. Without it a container carrying
a `tint` would have re-applied it against an authority it does not hold.

### 3.5 The prop channel for the container declarations

A container's `enabled` / `tint` reaches the engine only through the descendants
the cascade resolves it onto, so it is neither a `binding` prop (no adapter
write of its own, and declaring one would authorize the renderer to paint a
container's plate) nor `style`, `layout`, `handler` or `presentation`. It
declares `channel = "inherit"`, and `check_prop_parity`'s no-adapter-channel set
grows from two to three with the reason written beside it. The dirty classes are
real (`paint` / `semantics` / `navigation`), and view 1 still holds because both
props are members of `BINDING_PROPS` and the refresh loop re-applies them.

### 3.6 Focus restoration

When a subtree becomes disabled, its nodes leave the focus order, which is the
same event as a focused node being removed: `enabled` declares
`dirty = { "semantics" }` and the container's spec adds `navigation`, the
renderer bumps `structureEpoch` (`renderer.luau:2910`), the presenter rebuilds
the map, and `focus_graph` falls to the nearest surviving neighbour (the
behaviour `tests/focus.spec.luau` already pins). The new spec proves the
composed case: focus sitting inside a subtree that is switched off lands on a
legal, enabled node outside it, and re-enabling does not move it back.

---

## 4. Interaction blocking matrix

Every row is blocked by `contract.isDisabled`, at the site named.

**THIS MATRIX WAS TRUE OF ONE DERIVATION, AND THEN OF ONE KIND OF GROUP.** The
presenter builds the member set two ways: `focusWalk` for a screen with no
horizontal structure, and NAVIGATION GROUPS the moment there is an `HStack` run
or a `Grid`. The first version of this table named only `focusWalk`, and the
grouped reading had no disabled test at all. The second attempt put the test
inside the three walks that BUILD groups, which reached neither a control that
contributes its own groups (`newTable`, `newVirtualList`, `newVirtualGrid`,
`newTextInput` — a disabled list kept every row) nor a consumer-declared
`navigationGroups` map, and broke two things a builder must not decide: it
repacked an inferred grid, and it made the choice of derivation depend on the
enabled state.

It is one filter on the BUILT groups now — `filterGroupsDisabled`, beside
`filterGroupsHidden`, at the presenter's initial push and at the refresh
derivation — so the rows below are true of both readings and of every group,
however it was built.

| Path | Blocked at |
|---|---|
| Activate (semantic action: Return / Space / ButtonA) | `presenter.dispatchActivate` — consumes the verb, emits no feedback event |
| Consumer `opts.onActivate` override | same site, ahead of the override (finding V12) |
| Focus entry / initial focus | `focusWalk` (flat) **and** `filterGroupsDisabled` (grouped); `initialFocus` naming a disabled control is a refusal on both |
| Tab / Shift+Tab traversal | the same set (constitution §9: one focus map, read two ways) |
| Arrow / D-pad navigation | `filterGroupsDisabled` — no group carries the path |
| Focusable `Grip` (Slider track, Rating strip) | `focusWalk`'s Grip branch, and the group filter for every group |
| Adjust on a focused value control | consequent: the verb is bound only while focus sits on its target, and focus cannot get there |
| A control's OWN contributed groups (`newTable`, `newVirtualList`, `newVirtualGrid`, `newTextInput`) | `filterGroupsDisabled` — the builders are never asked, which is why a control need know nothing about inheritance |
| A consumer's `navigationGroups` map | `filterGroupsDisabled` — overridden for this exactly as it is for `hidden` |
| Pointer / touch tap | `controller.tapAt` |
| Pointer zones (`onPointerDown/Move/Up`) | `controller.tapAt` — the same walk routes them |
| Drag acquisition | `dragSourceEnabled[path]` |
| Drag-detector synthesized tap | `handlers.onEnd` |
| Row actions (swipe tray, flick, reorder) | the pointer routing above; the row's own engine never arms |
| An ALREADY-OPEN row tray's action buttons | `virtual_list.collectTrayFocusables` |
| Menus (long press / secondary / keyboard / gamepad triggers) | the trigger node's tap and Activate paths above |
| Engine-level press | `enabled` → `Active` / `Interactable` false on the real adapter |

**What is NOT blocked, and is not meant to be.** A surface that was already
presented — a modal, toast, menu, popover or anchored sheet — is its own mounted
root and does not inherit; see §6.

**What it COSTS, measured rather than assumed.** A `Grid` names each row group's
`up`/`down` exit by index, so a row whose every cell is disabled is still the
named neighbour and is empty — the arrows cannot cross it, and everything below is
unreachable by the pad. Measured against the branch base: `hidden` does exactly
this and always has (`A1 → A1 → A1` in both), while base `disabled` walked onto
the dead row and round 1's placement repacked around it, so no shipped version
dead-ended and this one does. It is specific to a grid's group-to-group exits: the
same content as stacked `HStack` rows is crossed cleanly (`R1/A → R3/E`), which is
the documented way around, and Tab is unaffected because linear traversal walks the
order rather than the exits. The real fix — `emitGridGroups` naming the nearest
NON-EMPTY adjacent group, which repairs `hidden` at the same time — is booked, not
taken: changing focus behaviour was out of scope for the round that found this.

**A consumer-declared `navigationGroups` map** is filtered when the surface is
presented. A STATIC array is filtered once, there; the FUNCTION form is re-derived
and so follows a reactive `enabled`. That split is pre-existing and identical for
`hidden`; `api.md` says which to reach for.

**What is painted, exactly.** One rule, `Disabled subtree text`, selecting a
`TextLabel` that carries the tag. The tag reaches the four classes that consume a
resolved `enabled` (`Button`, `Toggle`, `TextField`, `Text`) and not every node,
because writing to an elided container materializes it permanently; and a `tint`
that declares its own `transparency` claims that property and outranks the dim —
which is why a CONTAINER tint refuses `transparency` outright. All of it is in
`api.md`.

---

## 5. Files

| File | Change |
|---|---|
| `src/blueprint_schema.luau` | `enabled` + `tint` in `CONTAINER_LAYOUT`, `channel = "inherit"`, shared, documented |
| `src/blueprint.luau` | `ContainerProps` gains both fields; `CompositionSpec` if it does not intersect it |
| `src/class_contract.luau` | `contract.isDisabled(node)` beside `enabledNow` / `enabledIn` |
| `src/mount.luau` | the cascade: thread the record, resolve per node, re-walk on a flip |
| `src/present/focus_map.luau` | `isDisabled` delegates; the Grip branch honours it |
| `src/render/authority.luau` | `common.enabled = "binding"` |
| `src/render/prop_channels.luau` | `BINDING_PROP_CLASSES.tint` |
| `src/render/renderer.luau` | resolved `enabled`, inherited `tint`, the three gates via the shared predicate |
| `src/tokens/chrome_slots.luau` | `TAGS.stateDisabled` |
| `src/tokens/sheet_model.luau` | `ClassifyInput.disabled`, the tag, the two `disabled`-group rules in both builders |
| `src/client/screen_props.luau` | the `enabled` branch records `disabledState` and re-syncs tags |
| `src/client/screen_target.luau` | `syncTags` passes `disabled` |
| `tools/lune/check_prop_parity.luau` | the `inherit` channel in the no-adapter set |
| `tests/inherited_subtree.spec.luau` | new, registered in `tests/run.luau` |
| `docs/reference/api.md` | shared property rows + the Inheritance subsection |
| `docs/guide/README.md`, `05-styling.md`, `07-input.md` | catalog line + two paragraphs |
| `CHANGELOG.md` | Added / Changed under `[Unreleased]` |

`src/render/renderer.luau` is within ~2.7k characters of the 200,000 `Source`
write cap, so its share of this change is four small edits and one require, and
`python3 tools/check_source_size.py` is run before every commit that touches it.

---

## 6. What this design refuses

- **A second state channel.** No `disabledSubtree` prop, no parallel
  "effective" table, no per-control workaround. One name, one resolved reading,
  one write site.
- **A hard-coded colour.** The inherited tint is the same theme-role value the
  leaf tint already is; the disabled dim is the theme's own
  `disabledContentOpacity` through a sheet rule.
- **A per-subtree environment.** `newEnvironment` publishes *device* facts for a
  surface; a subtree scope there would be a second adaptation authority.
- **An escape hatch.** `enabled = true` under a disabled ancestor is not an
  override. A subtree that is off is off, so a screen can never present a
  control that looks live inside a panel that is not.
- **A cascade into a presented surface.** A modal, toast, menu, popover or
  anchored sheet is mounted as a fresh root and inherits neither channel. Eight
  call sites across `present/` raise those roots and only some have a presenting
  node to inherit FROM — an anchored surface has its anchor, a modal has nothing —
  so half a cascade would be a worse promise than none, and which half is a design
  question about what a modal raised from a dead panel MEANS rather than a
  plumbing change. Documented in `api.md`, pinned by a check, and dismissing what
  a panel opened stays the consumer's call.
- **A tag on every node.** The resolved `enabled` reaches the four classes that
  consume one. Writing a property to a container the renderer had elided
  materializes it permanently, and a real `Frame` per container is too much to pay
  for a tag no rule selects.
- **An inherited `transparency`.** A container's `tint` refuses it at
  construction. The alpha is not a colour, it is a per-node CLAIM: the node takes
  `TextTransparency` from the sheet and `screen_paint.releaseTint` restores the
  value without ever giving the property back. On a leaf that is a bounded
  decision about a node the author named; inherited, one declaration would leave a
  whole subtree un-dimmable for the life of the surface, silently, long after the
  tint was cleared. Refusing it costs nobody — the container form is new, so no
  screen can be relying on it — and it removes the hazard instead of documenting
  it.
- **A disabled test inside a group BUILDER.** Round 1 tried that; the walks
  answer structural questions (does this row become a group at all, what shape is
  this grid) and a state-dependent answer there repacks a board and flips a
  screen's whole derivation. Disabled is filtered on the BUILT groups, where
  `hidden` has always been filtered, which is also the only placement that reaches
  a contributed group and a consumer-declared map.
