# ADR-0007: Table control (NSTableView-informed), phased

- **Status:** Accepted (2026-07-19, director direction). Phase 5 expansion gate #2 activated by real need: the racer list in director view and the race-result list are the named first consumers ("borderless/header-less table" or single-column with custom cells).
- **Reference model:** Apple `NSTableView`/`UITableView` — column model with resizing, row selection incl. multi-select, drag-and-drop, variable row heights, custom cell views. Outline view explicitly deferred.

## Decision — a composite control, not a solver kind

`UI table = src/controls/table.luau :: table_control.build(LuauUI, core, spec) -> { blueprint, api, dispose }` — the same composite pattern the game screens use. Internally it composes shipped primitives (VStack/HStack/ScrollView/Button/Text) with a **column-width resolver**: column widths resolve once per table width (fixed / fill-weight / percent, each with min), then every row's cells receive those widths as fixed dims — so the existing solver algebra does all layout and NO new solver kind is needed. Structural row identity rides ForEach-style keying.

### Spec shape (v1)

```luau
table_control.build(LuauUI, core, {
  columns = {            -- ordered; single-column + custom cells = a list
    { id = "name", title = "Racer", width = { type = "fill", weight = 1 }, minWidth = 80, resizable = true },
    { id = "laps", title = "Laps", width = { type = "fixed", px = 64 } },
  },
  rows = rowsReadable,   -- Readable<{T}>; key = function(item) -> string
  key = ...,
  cellFor = function(columnId, item) -> Blueprint,  -- custom controls in cells
  rowHeight = number | function(item) -> number,    -- variable heights v1
  header = true | false,             -- false = the director's headerless mode
  selection = "none" | "single" | "multi",
})
-- api: selectedKeys (Readable), select(key, {additive}), clearSelection(),
--      columnWidths (Readable), setColumnWidth(id, px), rowPath(key)
```

### Phasing

- **A (now, headless-complete):** column resolver (fixed/fill/percent + minWidth), header row (optional), keyed rows with per-row variable height, custom `cellFor` blueprints, selection none/single/multi (tap = select; multi: additive toggle semantics; keyboard Up/Down moves selection with the focus ring; Activate = select), selected-row style hint (`surface="control"`→selected accent tint via a `selected` binding prop), deterministic dumps, churn-neutral, `setColumnWidth` API (the resize MODEL — interaction comes in B).
- **B (interaction): ✅ SHIPPED (2026-07-19, ADR-0008):** mouse column-resize drag on non-button Active grip zones (engine overrides `MouseIcon` over buttons — platform research 2026-07-19) with semantic cursor requests through the platform adapter (`cursorHint = "colResize"`; actual cursor art pending an uploaded asset set — no first-party cursors exist); row drag-and-drop (pointer capture + drop indicator via `reorderable`/`onReorder(key, slot)`, drag threshold 6px, trailing-activate suppression); modifier multi-select (touch/no-meta = additive toggle, plain mouse/key = replace, ctrl/cmd = toggle, shift = range from anchor); gamepad/keyboard equivalents (grips focusable at the END of the focus order + presenter `Adjust` action: arrows/dpad/bumpers, 16px committed steps) since the virtual cursor likely ignores MouseIcon. Structural note: the table root is now `Anchor[Main[Header?, Body], ResizeWhen, DropWhen]` — row-hit paths carry `/Main/`; resize commits also re-solve the header reactively (Phase A gap fixed).
- **Deferred:** outline view (director), sticky sections, virtualization until a consumer's row count requires it (§10.5 — the racer list is ≤8 rows, results ≤8).

### Conformance/gate additions (Phase 5 gate requirements)

Use case named above; current primitives genuinely cannot express synced column widths across keyed rows without this resolver; bench scenario `table-mutation` (row churn + width change) joins the registry before the control ships to a game surface; rollback = the control is additive (no game surface depends on it yet).
