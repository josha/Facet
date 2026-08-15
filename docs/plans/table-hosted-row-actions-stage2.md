# Teaching `newTable` to HOST row actions — the Stage 2 scoping decision

**Asked 2026-08-15:** *why was this deferred?* It was not blocked; it was queued.
`docs/plans/unified-collection.md` names it as Stage 2 item 1 — *"Row actions on a
virtualized Table, by teaching Table to HOST rather than wrap"* — and calls it
*"the only credible path to option 2"* (one collection substrate).

**Verdict: KEEP THE REFUSAL for now.** Not because hosting is impossible — one
objection everybody expects turns out not to hold, and it is worth recording that
— but because hosting is a **mission the size of the VirtualList hosted mission
plus two extensions that mission explicitly declined to build**, and because the
version of it that would actually converge the two strategies is the version that
regresses shipped, tested capability.

This file is the decision, so the next agent starts from one rather than from the
question.

---

## What was read before deciding

Both hosting models, in full: `src/controls/table.luau`'s wrap seam
(`rowBlueprint` → `row_actions.build`, table.luau:1953-2002) and
`src/controls/virtual_list.luau`'s host (the shared dispatcher at :2324, the lazy
engine at :2034, the tray overlay at :3445, the extent seam at :1810), plus
`docs/plans/row-actions-hosted-mode-design.md` and the seven `row_actions_*`
modules.

---

## The objection that does NOT hold — recorded, because everyone will raise it

**"Table's rows are content-sized, so the commit-height collapse seam cannot
port."** False. `table.luau:1659-1661` builds

```luau
local heightDim = itemScope:own(core:memo(function(use)
    return { type = "fixed", px = rowHeightOf(item, use(rowBox)) }
end))
```

and applies it at `height = heightDim` on the `Row` ZStack (`:1927`) in **both**
the flowing and the windowed mode. *"Table's row extent is DERIVED, never
declared"* (`:616`). So VirtualList's `hostedItemExtentIn` seam (`virtual_list.luau
:1810` — "is it me?" on a key signal, "how tall?" on a px signal, two signals so a
collapse spring invalidates one memo) ports to Table **unchanged**, in both modes.

That matters: it means hosting is not structurally confined to `virtualized`, so
the "host the windowed path, wrap the flowing one" compromise is not forced by
geometry. It would be a *choice* — and it is the wrong one (see conflict 4).

---

## The cost, measured

The VirtualList hosted mission is the only real estimate available, and it is on
disk. Nine commits touched `src/controls/virtual_list.luau`:

| commit | Δ chars |
|---|---:|
| `f6214aa` rowActions seam — shared dispatcher, lazy hosted engines | +21,897 |
| `341229d` review round 1 — gesture routing, remount, touch laziness | +8,773 |
| `8b0789d` shared tray overlay + presentation slide + commit height | +12,502 |
| `14e4828` dismiss above the capture declines | +1,379 |
| `9e7857b` hosted parity + mount-identity differential proof | +4,944 |
| `85436de` focus + activate seams (review round 1) | +7,792 |
| `db52668` a revealed tray wins its own edge over an author exit | +2,107 |
| `79649d6` a hosted swipe fires onActivate, and an arm that outlived its gesture | +3,629 |
| `e725c68` a hosted row's keys exist only after a pointer swipe | +4,461 |
| **total** | **+67,484** |

Net **+1,430 lines**, plus **90 `it` blocks** across three new spec files
(`row_actions_hosted` 18, `virtual_list_row_actions` 68,
`virtual_list_row_actions_identity` 4) and six review rounds.

Against that, **Table's entire wrap integration is 84 lines / ~4,769 characters**
of `table.luau` — every line mentioning `rowActions`/`RowActions`/`ROW_ACTIONS`/
`rowDeletable`/`composeWithReorder`, including the refusal, the coordinator, the
prune, the dispose sweep and the five path patterns. That 14x ratio **is** the
economic argument for wrapping, and it is the whole reason wrapping exists.

**Where it would have to live.** `src/controls/table.luau` is **183,838** chars
against the 200,000 Source cap — **16,162 of headroom**, about a quarter of what
hosting costs. `src/controls/virtual_list.luau` is **195,074**: 2.5% from the cap
and still being added to (variable extents, Stage 2). So a hosted Table needs its
own module — which is fine and precedented (`row_actions` is already seven files)
but is a real "flag the refactor, don't smuggle it" boundary, not a detail.

---

## The four conflicts that remain

### 1. `editing` is refused by hosted mode BY NAME, and Table is the only surface that has it

`row_actions.luau:407-411`: `content`, `width`, `editing` and `externalGesture`
are refused from `HOSTED_KEYS` because each *"is a statement about a blueprint
this mode never builds"*. `VIRTUAL_LIST_KEYS` has no `editing` key at all.

Table passes `editing = editingSignal` (`table.luau:1970`) and gets from it:
`hasEditAffordance`, the `EditAffordanceWhen/then/EditAffordance` node, the
`contentOffsetX` shift and the edit gutter. Shipped and pinned by *"editing signal
shows the minus on rows with a destructive action"*, *"edit mode shows BOTH the
row_actions minus and Table's own reorder handle at once"*, and the
`padMinusTable` showcase case — which lives on the **Table** surface precisely
because the VirtualList surface cannot do it.

A hosted Table either deletes that, or `buildHosted` grows an `editing` mode that
returns an edit-affordance view the host parents (the `trayViews` shape) plus an
`onContentOffset` seam. The second is the right answer and it is **a change to the
shared engine, not to Table** — i.e. a prerequisite, not part of the port.

### 2. `reorderable + rowActions` is the capability VirtualList gave up to host

`virtual_list.luau:662` refuses it, and `:249-252` says why: *"VirtualList's
reorder rides the declarative `UI.draggable` contract, and composing that with the
raw-handler funnel is its own task (Table does it with
`row_actions.composeWithReorder`, over a hit it owns outright)."*

Table supports both today, on six named cases in `tests/table.spec.luau` (mouse
horizontal drag reveals instead of reordering; handle-drag on an open row closes
the tray first; body-drag likewise; gamepad/keyboard grab likewise; both
affordances visible at once in edit mode; a wrapped non-reorderable row still
mounts its own internal Grip).

The good news: Table owns its `Hit` outright, so this is composable — and the two
arbiters are the *same shape*. `row_actions_reorder.compose` defers the down,
resolves at `AXIS_LOCK_PX`, and replays the original down into exactly one side;
hosted's `onPointerDown` + `hostedResolveAxis` defers the down, resolves at the
same constant, and replays into the engine it builds at the lock. Merging them is
"at the vertical lock, replay into `dragHandlers` instead of going inert, by
pointer type" — Table's touch path already declines, which is exactly what
`compose` encodes.

So this is **tractable and worth doing** — but it is the task VirtualList named as
its own, and it must be built and reviewed as one, not folded in.

### 3. The tray's focus group has to compose with Table's PER-ROW HORIZONTAL group

VirtualList contributes ONE vertical group for the whole list, so the revealed
tray became a second, horizontal, contained group with its own exit map
(`virtual_list.luau:3186-3198`, exit suspension at `:3096-3160`). Table
contributes a `headers` group, a `toolbar` group **and one horizontal group per
row, because its cells are focus stops** (`docs/plans/unified-collection.md`
conflict 4). A revealed tray's buttons therefore land *inside* a row that already
owns left/right — the tray's exit map and the row's cell navigation compete for
the same axis on the same node.

Related, and it cuts both ways: Table's tray buttons land in **no** focus group
today (`virtual_list.luau:3142`), and the Activate-seam in-list dismiss is open on
Table for the same reason (`:2913`: *"TABLE IS NOT [immune] — it contributes
`focusGroups` for the whole table… a separate pre-existing defect"*). Hosting
would have to fix both, in the harder configuration. That is a feature, not an
objection — but it is unbudgeted work, and it is the part of the VirtualList
mission that took a whole review round on the easy configuration.

### 4. Hosting Table does not converge the strategies — done safely, it TRIPLES them

This is the one that decides it.

The stated purpose of Stage 2 is convergence: hosting is *"the only credible path
to option 2"*. But there are only two ways to do it:

* **Host the windowed path, keep the wrap for the flowing one.** No regression —
  the new combination is purely additive, since `virtualized + rowActions` is
  refused today. But the library then carries **three** row-actions integrations
  (standalone/wrapped, VirtualList-hosted, Table-hosted) instead of two, and every
  future row-actions change is implemented and tested twice *on the same control*.
  That is verbatim the cost `unified-collection.md` used to reject option 3:
  *"every future feature is then built two-and-a-bit times."* It moves **away**
  from convergence.
* **Host both paths.** This is the one that converges — and it is the one that
  must first pay conflicts 1, 2 and 3 in full, because the flowing Table is where
  edit mode, reorder-plus-actions and per-row cell focus all actually ship.

So: **the version that converges is the version that first has to build two things
VirtualList declined to build, and the version that avoids them does not
converge.** A refusal that says only "it is big" would be weak. This is the shape
argument, and it is why the answer is "not yet" rather than "no".

---

## Also inherited, if Table hosts: three open hosted-mode defects

Recorded in `virtual_list.luau` as carried, and Table does not have them today:

1. **A tap on the empty canvas below the last row does not close the tray**
   (`:2384-2395`) — iOS closes there. Standalone/wrapped rows get it free, because
   each row is its own contribution; a host hears only from row `Hit`s. Deferred
   to a device pass.
2. **A previously-open row snaps flat rather than animating closed** (`:1909-1916`)
   — `hostedWriteSlide` paints only the *engaged* row, so a row losing engagement
   mid-close-spring jumps on that frame. Table animates it today, because each row
   owns its own engine and spring.
3. **A vertical pan begun on a row still fires that row's `onActivate`** —
   pre-existing, awaiting a device answer.

(2) is a visible regression on a shipped Table surface, not a theoretical one.

---

## What ports for free — so the next agent does not re-derive it

* **`rowDeletable` at ONE funnel.** `doCommitAction` (`row_actions.luau:1330`,
  gate at `:1388`) is host-agnostic; both hosts thread the identical thunk
  (`table.luau:1978-1982`, `virtual_list.luau:2063-2067` — capture the KEY, resolve
  the item at commit through `itemForKey`, `rowCapability.allows` fail-closed).
  Hosting changes nothing here, and the milestone blocker stays closed.
* **`ROW_KEYS` / `ROW_KEY_PRIORITY`** (`row_actions.luau:201-208`) already have
  their host-standing-in-for-an-engine reader: `hostedEnsureKeysContext` binds one
  context per list at `PRIORITY - 1` with `sink = true` and routes to
  `hostedEngineFor`, which builds the engine at key-press time. Table would mirror
  it; the spelling cannot drift because the keys are declared once.
* **The 44px hit expander and `controller.tapAt(x, y, { within, skip })`**
  (`3eb97fb`). `forwardUnclaimedTap` is *already* inert under
  `externalGesture`/hosted (`row_actions.luau:2507-2509`) because the host owns the
  press outright — so a hosted Table row cannot break it. The `{within, skip}` pair
  would simply be re-expressed against Table's own row path
  (`…/Rows/[key@v]/Row` + `/Row/Hit`) instead of the wrapper's `Content`. The
  **header** divider band (`forwardUnclaimedGripTap`, `table.luau:2043-2049`) is
  header-scoped and untouched by row hosting — and it is the shipped precedent for
  the pattern a hosted dispatcher would reuse.
* **The commit-height seam** — see "the objection that does not hold".
* **The path vocabulary gets simpler, measurably.** Hosting deletes five
  production patterns from `table.luau` that exist only to strip or match the
  wrapper infix (`ROW_ACTIONS_PATH_INFIX` `:88`, the activate re-entry pattern
  `:2904`, the focus-walk anchor `:3180`, `derowActionsPath` `:3181`,
  `rowKeyForPath` `:3249`) plus `WRAPPER_CHILD_ORDER` `:3153`, and makes the row
  path plain. 44 hardcoded wrapper strings across 9 spec files go with it. The
  hosted vocabulary is purely *additive* (row path unchanged, one overlay region),
  which is what makes the VirtualList migration cheap and would make Table's
  expensive: the wrapper is an **infix in the row path itself**.

---

## The decision, and the order that would lift it

Keep `newTable`'s construction refusal of `virtualized + rowActions`. It is
correct, it names its reason, and it points at the alternative that works today
(`newVirtualList` hosts).

Lifting it is a mission, in this order. Each step is separately shippable and each
one is worth having on its own:

1. **`editing` in hosted mode** — extend `buildHosted` to return an edit-affordance
   view the host parents (the `trayViews` shape) and an `onContentOffset` seam for
   the gutter. Removes `editing` from the refused-by-name list. Benefits
   VirtualList too, which has no edit mode at all. *Prerequisite for any Table
   hosting that does not delete `padMinusTable`.*
2. **The reorder composition, inside the host dispatcher** — one deferred down,
   one axis lock, horizontal → build + replay into the engine, vertical → replay
   into `dragHandlers` by pointer type. This is `row_actions_reorder.compose`'s
   policy moved one layer up. It also unblocks VirtualList's own
   `reorderable + rowActions` refusal, which is the same task from the other side.
3. **The three carried hosted-mode defects** (canvas-tap close, close-animation on
   the disengaging row, vertical-pan stray activate) — fix them on VirtualList,
   where they already ship, *before* a second host inherits them.
4. **Then, and only then, Table hosts BOTH paths in one go**, in its own module,
   with the mount-identity differential
   (`virtual_list_row_actions_identity.spec.luau` is the template) and the full
   parity suite. Not the windowed path alone: hosting one path and wrapping the
   other is the shape that permanently entrenches two integrations in one control.

**What is not acceptable at any point:** a half-hosted Table. A row whose
composite is pruned by the DATA while its gesture engine is owned by the WINDOW
strands the engine, its coordinator claim and any in-flight gesture — which is the
exact defect the current refusal exists to prevent, reintroduced with a bigger
blast radius.

## See also

- `docs/plans/unified-collection.md` — Stage 2 item 1, and the five conflicts that
  killed the deeper merge.
- `docs/plans/row-actions-hosted-mode-design.md` — the accepted hosting design, and
  the instance/time measurements that chose it.
- `src/controls/table.luau:344-363` — the refusal itself.
