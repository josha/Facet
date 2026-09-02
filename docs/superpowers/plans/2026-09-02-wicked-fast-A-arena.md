# Wicked Fast — Plan A: arena workloads + attribution — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give FacetBench a position primitive and two game-UI stress workloads (`nameplates`, `damage_fountain`), measure facet vs vide on them in Lune + Studio, and attribute a nameplates `tick` so Plan B (the Facet fixes) is chosen by a profile, not a guess.

**Architecture:** The scene DSL (`runner/lune/lib/scene.luau`) grows a `canvas` node kind, `x`/`y` props legal only on canvas children, and an `updateItems` bulk step. Every adapter maps `canvas` to its own free-position container idiom (Facet → `UI.Anchor` with `anchor/offsetX/offsetY`; the Roblox-instance rivals → a `Frame` with no `UIListLayout` and a bound `Position`). Workloads are pure seeded generators (`build(size, rng)` + `script(size, rng)`), cycle-safe over two passes, with a spec each.

**Tech Stack:** Luau under Lune 0.10.x (`lune run …`), stylua 2.5.2, rojo (place build), Roblox Studio via the MCP bridge for the live matrix. Facet is consumed from the sibling checkout `../Facet/src`.

**Spec:** `GameStudio/ui/Facet/docs/superpowers/specs/2026-09-02-facet-wicked-fast-design.md` (Part 1 + Part 2 step 0).

## Global Constraints

- Repo for every task in this plan: `/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/FacetBench` (its own git repo; `cd` there first; commit with plain `git add <paths> && git commit`). HEAD at plan time: `f38add27`.
- Gate for every commit: `tools/check.sh` from the repo root (stylua → `lune run tests/run` → check_adapters/runner/schema/baselines/bare_loops → rojo build). Quick loop while iterating: `lune run tests/run` and `stylua --check .` (stylua excludes `tools/profile`).
- Never a wall-time assertion in a spec. Never shim a rival: a framework that cannot express positioning idiomatically declares the capability missing.
- No Facet source change in this plan (Plan B owns Facet). If a Facet bug blocks a task, write it in the task report as a follow-up and stop that task.
- Every scene-DSL change updates `scene.luau`'s types AND validators AND every adapter (`facet`, `vide`, `fusion`, `react`, `blend`, `_fixture`); `flux` stays unsupported via its existing missing `reactive`/`keyedList`.
- Canvas coordinates are integer px from the canvas's top-left; a canvas's design size in these workloads is 1280×720 (the headless viewport `frameworks/facet/adapter.luau:209`).
- Coding style: match the surrounding file's comment density and idiom (`--!strict`, `local function`, template strings).

---

### Task 1: Scene DSL — `canvas` kind, `x`/`y` props, `updateItems` step

**Files:**
- Modify: `runner/lune/lib/scene.luau:7-26` (types + `NODE_KINDS`), `:45-97` (`validate`), `:119-149` (`simulateStep`), `:170-198` (`validateSteps`)
- Test: `tests/scene.spec.luau` (append)

**Interfaces:**
- Produces: `SceneNode.kind` may be `"canvas"`; a canvas may carry `children` and numeric `props.width`/`props.height`; a direct child of a canvas (or the `template` root of a `list` that is a direct child of a canvas) carries `props.x` and `props.y` (`PropValue`, both required together). New `Step` variant `{ kind = "updateItems", listState: string, updates: { { key: string, fields: { [string]: any } } } }`. Every adapter in Tasks 2–7 consumes exactly these shapes.

- [ ] **Step 1: Write the failing tests** — append to `tests/scene.spec.luau`:

```lua
-- canvas kind + x/y placement rules (design 2026-09-02 §1.1)
do
	local canvasSpec = {
		state = { plates = { { key = "p1", x = 10, y = 20 } } },
		root = {
			kind = "canvas",
			id = "Root",
			props = { width = 1280, height = 720 },
			children = {
				{ kind = "label", id = "Title", props = { text = "hud", x = 4, y = 4 } },
				{
					kind = "list",
					id = "Plates",
					itemsState = "plates",
					template = {
						kind = "panel",
						id = "Plate",
						props = { x = { item = "x" }, y = { item = "y" } },
						children = { { kind = "label", id = "Name", props = { text = "n" } } },
					},
				},
			},
		},
	}
	assert(scene.validate(canvasSpec) == true, "a canvas with positioned children validates")

	-- a canvas child with no x/y is refused
	local noPos = {
		state = {},
		root = { kind = "canvas", id = "R", children = { { kind = "label", id = "L", props = { text = "t" } } } },
	}
	local ok, err = pcall(scene.validate, noPos)
	assert(not ok and string.find(tostring(err), "x/y", 1, true), `canvas child without x/y must be refused, got {tostring(err)}`)

	-- x/y outside a canvas are refused
	local strayPos = {
		state = {},
		root = { kind = "panel", id = "R", children = { { kind = "label", id = "L", props = { text = "t", x = 1, y = 1 } } } },
	}
	ok, err = pcall(scene.validate, strayPos)
	assert(not ok and string.find(tostring(err), "x/y", 1, true), `x/y under a panel must be refused, got {tostring(err)}`)

	-- x without y is refused
	local half = {
		state = {},
		root = { kind = "canvas", id = "R", children = { { kind = "label", id = "L", props = { text = "t", x = 1 } } } },
	}
	ok, err = pcall(scene.validate, half)
	assert(not ok and string.find(tostring(err), "x/y", 1, true), `x without y must be refused, got {tostring(err)}`)

	-- direction on a canvas is refused (it is a panel-only word)
	local dir = { state = {}, root = { kind = "canvas", id = "R", direction = "vertical", children = {} } }
	ok = pcall(scene.validate, dir)
	assert(not ok, "direction on a canvas must be refused")

	-- updateItems: legal on live keys, refused on a dead key, refused with a non-table fields
	assert(scene.validateSteps(canvasSpec, {
		{ kind = "updateItems", listState = "plates", updates = { { key = "p1", fields = { x = 11, y = 21 } } } },
	}) == true)
	ok, err = pcall(scene.validateSteps, canvasSpec, {
		{ kind = "removeItem", listState = "plates", key = "p1" },
		{ kind = "updateItems", listState = "plates", updates = { { key = "p1", fields = { x = 1, y = 1 } } } },
		{ kind = "addItem", listState = "plates", item = { key = "p1", x = 0, y = 0 } },
	})
	assert(not ok and string.find(tostring(err), "not live", 1, true), `updateItems on a dead key must be refused, got {tostring(err)}`)
	ok = pcall(scene.validateSteps, canvasSpec, {
		{ kind = "updateItems", listState = "plates", updates = { { key = "p1" } } },
	})
	assert(not ok, "an update without a fields table must be refused")
	ok = pcall(scene.validateSteps, canvasSpec, {
		{ kind = "updateItems", listState = "nope", updates = {} },
	})
	assert(not ok, "updateItems on a non-list state must be refused")
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/FacetBench && lune run tests/scene.spec`
Expected: FAIL at "a canvas with positioned children validates" (`unknown kind canvas`).

- [ ] **Step 3: Implement** in `runner/lune/lib/scene.luau`:

Types (replace lines 7-26):
```lua
export type SceneNode = {
	kind: "panel" | "label" | "image" | "bar" | "list" | "canvas",
	id: string, -- unique across the scene
	direction: ("vertical" | "horizontal")?, -- panel only (default "vertical")
	-- label: text/textSize; image: image; bar: value; canvas: width/height (px);
	-- x/y (px from the canvas's top-left): ONLY on a direct child of a canvas, or
	-- on the template root of a list that is a direct child of a canvas
	props: { [string]: PropValue }?,
	children: { SceneNode }?, -- panel and canvas
	itemsState: string?, -- list only: state id holding { Item }
	template: SceneNode?, -- list only: row template; ItemRefs legal here only
}
export type Item = { key: string, [string]: any }
export type SceneSpec = { state: { [string]: any }, root: SceneNode }
export type ItemUpdate = { key: string, fields: { [string]: any } }
export type Step =
	{ kind: "setState", id: string, value: any }
	| { kind: "updateItem", listState: string, key: string, field: string, value: any }
	-- one FRAME of field writes across many live keys, reconciled once (the
	-- nameplate tick); semantically the listed updateItems applied together
	| { kind: "updateItems", listState: string, updates: { ItemUpdate } }
	| { kind: "addItem", listState: string, item: Item }
	| { kind: "removeItem", listState: string, key: string }
	| { kind: "reorder", listState: string, order: { string } }
	| { kind: "noop" }

local NODE_KINDS = { panel = true, label = true, image = true, bar = true, list = true, canvas = true }
```

`walk` gains a `positioned` flag (true for the direct children of a canvas, and for a list's template root when that list is a direct child of a canvas):
```lua
local function walk(node: any, fn: (any, boolean, boolean) -> (), inTemplate: boolean, positioned: boolean)
	fn(node, inTemplate, positioned)
	local childrenPositioned = node.kind == "canvas"
	if node.children then
		for _, child in node.children do
			walk(child, fn, inTemplate, childrenPositioned)
		end
	end
	if node.template then
		-- the template root stands where the list stands: positioned iff the list is
		walk(node.template, fn, true, positioned)
	end
end
```

In `validate`'s callback (signature becomes `function(node, inTemplate, positioned)`), replace the two `children`/`direction` asserts and add the placement rule:
```lua
		assert(node.children == nil or node.kind == "panel" or node.kind == "canvas", "children only on panel/canvas")
		assert(node.direction == nil or node.kind == "panel", "direction only on panel")
		-- PLACEMENT: x/y are a canvas-child idiom and nothing else. A canvas child
		-- without them has no place to be; x/y anywhere else would be silently
		-- ignored by every stack adapter, i.e. a measured prop nobody applied.
		local props = node.props or {}
		local hasX, hasY = props.x ~= nil, props.y ~= nil
		if node.kind == "list" then
			assert(not hasX and not hasY, `x/y belong on {node.id}'s template root, not the list`)
		elseif positioned then
			assert(hasX and hasY, `canvas child {node.id} needs both x/y props`)
		else
			assert(not hasX and not hasY, `x/y on {node.id}, which is not a canvas child`)
		end
```
The `walk(spec.root, function(node, inTemplate) … end, false)` call becomes `walk(spec.root, function(node, inTemplate, positioned) … end, false, false)`.

`simulateStep` gains, before the `reorder` branch:
```lua
	elseif st.kind == "updateItems" then
		local list = live[st.listState]
		for j, u in st.updates do
			assert(list.has[u.key], `{where}: updateItems[{j}] '{u.key}' is not live in {st.listState}`)
		end
```

`validateSteps`'s type pass gains, before the `addItem` branch:
```lua
		elseif st.kind == "updateItems" then
			assert(listStates[st.listState], `step {i}: updateItems on non-list state`)
			assert(type(st.updates) == "table", `step {i}: updates required`)
			for j, u in st.updates do
				assert(type(u.key) == "string", `step {i}: updates[{j}].key must be string`)
				assert(type(u.fields) == "table", `step {i}: updates[{j}].fields must be a table`)
			end
```

- [ ] **Step 4: Run tests**

Run: `lune run tests/scene.spec && lune run tests/run`
Expected: both PASS (the existing workloads have no canvas, so nothing else moves).

- [ ] **Step 5: stylua + commit**

```bash
stylua runner/lune/lib/scene.luau tests/scene.spec.luau
git add runner/lune/lib/scene.luau tests/scene.spec.luau
git commit -m "feat(scene): canvas kind, x/y placement rule, updateItems bulk step"
```

---

### Task 2: `_fixture` adapter learns canvas + updateItems + `positioned`

**Files:**
- Modify: `frameworks/_fixture/adapter.luau:66-86` (`mount` walk), `:88-156` (`applyStep`), `:204` (capabilities)
- Test: `tests/fixture_adapter.spec.luau` (append)

**Interfaces:**
- Consumes: Task 1's shapes.
- Produces: `capabilities.positioned = true`; `updateItems` burns `#updates` field writes then `#rows` (same closing burn every list step pays).

- [ ] **Step 1: Failing test** — append to `tests/fixture_adapter.spec.luau`:

```lua
-- canvas + updateItems (design 2026-09-02 §1.1): the cost model must count a
-- canvas like a panel and burn once per bulk-updated key
do
	assert(a.capabilities.positioned == true, "_fixture must declare positioned")
	local spec = {
		state = { plates = { { key = "p1", x = 1, y = 2 }, { key = "p2", x = 3, y = 4 } } },
		root = {
			kind = "canvas",
			id = "R",
			children = {
				{
					kind = "list",
					id = "Plates",
					itemsState = "plates",
					template = { kind = "label", id = "Name", props = { text = "n", x = { item = "x" }, y = { item = "y" } } },
				},
			},
		},
	}
	local h = a.mount(spec, nil)
	assert(a.liveCount(h) == 1 + 2, `canvas root + 2 rows, got {a.liveCount(h)}`)
	local before = a.snapshot(h)
	a.applyStep(h, {
		kind = "updateItems",
		listState = "plates",
		updates = { { key = "p1", fields = { x = 9, y = 9 } }, { key = "p2", fields = { x = 8, y = 8 } } },
	})
	local after = a.snapshot(h)
	assert(before ~= after, "updateItems must change the snapshot")
	assert(string.find(after, '"x":9', 1, true) and string.find(after, '"x":8', 1, true), "both keys must carry the new x")
	a.unmount(h)
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `lune run tests/fixture_adapter.spec`
Expected: FAIL at "_fixture must declare positioned".

- [ ] **Step 3: Implement**

`countNodes` already counts any node with `children` (verify at `frameworks/_fixture/adapter.luau` top; if it keys on `kind == "panel"`, change the condition to `node.children ~= nil`). In `applyStep`, add before the `addItem` branch:
```lua
		elseif step.kind == "updateItems" then
			local byKey: { [string]: any } = {}
			for _, row in rows do
				byKey[row.key] = row
			end
			for _, u in step.updates do
				local row = byKey[u.key]
				assert(row, `fixture: updateItems '{u.key}' is not live in {step.listState}`)
				row.item = deepCopy(row.item)
				for field, value in u.fields :: { [string]: any } do
					row.item[field] = value
				end
				burn(1)
			end
```
Capabilities: `{ reactive = true, keyedList = true, headless = true, styling = true, positioned = true }`.

- [ ] **Step 4: Run tests** — `lune run tests/fixture_adapter.spec && lune run tests/run` → PASS.

- [ ] **Step 5: Commit**

```bash
stylua frameworks/_fixture/adapter.luau tests/fixture_adapter.spec.luau
git add frameworks/_fixture/adapter.luau tests/fixture_adapter.spec.luau
git commit -m "feat(_fixture): canvas, updateItems, positioned capability"
```

---

### Task 3: Facet adapter — `canvas` → `UI.Anchor`, x/y → offsets, `updateItems`

**Files:**
- Modify: `frameworks/facet/adapter.luau:48-92` (`toBlueprint`), `:281-332` (`applyStep`), `:439` (capabilities)
- Test: `tests/facet_adapter.spec.luau` (append)
- Reference: `../Facet/docs/reference/api.md` "Anchor"; `../Facet/examples/gallery/scenarios/sponsor_markers.luau:80-115` (the ForEach-under-Anchor marker idiom); `../Facet/src/blueprint_schema.luau:754-780` (`anchor`/`offsetX`/`offsetY` are shared reactive number props, dirty class `arrange`).

**Interfaces:**
- Produces: `capabilities.positioned = true`. A headless mount of a canvas scene records rects on the fake target, so `snapshot()` changes when x/y move.

- [ ] **Step 1: Failing test** — append to `tests/facet_adapter.spec.luau`:

```lua
-- canvas → UI.Anchor; x/y → offsetX/offsetY; updateItems moves rects in ONE refresh
do
	assert(a.capabilities.positioned == true, "facet must declare positioned")
	local spec = {
		state = { plates = { { key = "p1", x = 100, y = 50, name = "A" }, { key = "p2", x = 300, y = 80, name = "B" } } },
		root = {
			kind = "canvas",
			id = "Root",
			props = { width = 1280, height = 720 },
			children = {
				{
					kind = "list",
					id = "Plates",
					itemsState = "plates",
					template = {
						kind = "panel",
						id = "Plate",
						props = { x = { item = "x" }, y = { item = "y" } },
						children = { { kind = "label", id = "Name", props = { text = { item = "name" } } } },
					},
				},
			},
		},
	}
	local h = a.mount(spec, nil)
	local function plateRect(key: string): any
		for _, path in h.target.paths() do
			local node = h.target.node(path)
			if string.find(path, `Plate-{key}`, 1, true) and node.rect ~= nil then
				return node.rect
			end
		end
		error(`no rect for plate {key}`)
	end
	local r1 = plateRect("p1")
	assert(r1.x == 100 and r1.y == 50, `p1 must sit at its x/y, got {r1.x},{r1.y}`)
	local solvesBefore = h.controller.stats().solves
	a.applyStep(h, {
		kind = "updateItems",
		listState = "plates",
		updates = { { key = "p1", fields = { x = 140, y = 60 } }, { key = "p2", fields = { x = 310, y = 90 } } },
	})
	local r1b, r2b = plateRect("p1"), plateRect("p2")
	assert(r1b.x == 140 and r1b.y == 60, `p1 must move, got {r1b.x},{r1b.y}`)
	assert(r2b.x == 310 and r2b.y == 90, `p2 must move, got {r2b.x},{r2b.y}`)
	assert(h.controller.stats().solves == solvesBefore + 1, "a bulk update is ONE solve")
	a.unmount(h)
end
```
`target.paths()` / `target.node(path).rect` are the fake target's read API (`../Facet/tests/lib/fake_target.luau:308`, the same walk `snapshot` uses at `adapter.luau:348`). If the rect the fake target records is offset by a container (a non-zero parent origin), assert the DELTA (+40,+10 / +10,+10) instead of the absolute — but the assertion stays. If `controller.stats().solves` is not the field name, read `../Facet/src/render/renderer.luau:579-630` (the stats record) and use the solve counter it exposes; do not drop the assertion.

- [ ] **Step 2: Run to verify it fails** — `lune run tests/facet_adapter.spec` → FAIL at "facet must declare positioned".

- [ ] **Step 3: Implement** in `toBlueprint`. Add a placement helper above it and thread it through every kind:

```lua
-- x/y are a canvas-child idiom (scene.validate guarantees they appear nowhere
-- else): the child anchors at the canvas's top-left and its offsets are the
-- bound scalars — the "minimap-dot / name-tag" shape api.md documents, an
-- ARRANGE-only update per move, never a re-measure.
local function withPlacement(ctx: any, itemCtx: any, node: any, bp: { [string]: any }): { [string]: any }
	local props = node.props or {}
	if props.x ~= nil then
		bp.anchor = "topLeft"
		bp.offsetX = resolveProp(ctx, itemCtx, props.x)
		bp.offsetY = resolveProp(ctx, itemCtx, props.y)
	end
	return bp
end
```
Then in `toBlueprint`: every `return Facet.UI.X({...})` becomes `return Facet.UI.X(withPlacement(ctx, itemCtx, node, {...}))`, and the new kind:
```lua
	elseif node.kind == "canvas" then
		local children = {}
		for i, child in node.children or {} do
			children[i] = toBlueprint(ctx, child, itemCtx, scope, idSuffix)
		end
		local props = node.props or {}
		local bp: { [string]: any } = { id = id, children = children }
		if props.width ~= nil then
			bp.width = { type = "fixed", px = props.width }
		end
		if props.height ~= nil then
			bp.height = { type = "fixed", px = props.height }
		end
		return Facet.UI.Anchor(withPlacement(ctx, itemCtx, node, bp))
```
For the `list` kind the ForEach itself gets no placement (validate forbids x/y on it); its rows are built through `toBlueprint(ctx, node.template, …)` so the template root picks up `withPlacement` on its own — the ForEach-under-Anchor idiom needs nothing else.

`applyStep`, before the `addItem` branch:
```lua
	elseif step.kind == "updateItems" then
		local byKey = ctx.itemSignals[step.listState]
		for _, u in step.updates do
			local fields = byKey[u.key]
			assert(fields, `facet: updateItems '{u.key}' is not live in {step.listState}`)
			for field, value in u.fields :: { [string]: any } do
				local signal = fields[field]
				assert(signal, `facet: item {u.key} has no field '{field}'`)
				signal:set(value)
			end
		end
```
(the single `h.controller.refresh()` at the end of `applyStep` is the one reconciliation.)

Capabilities: add `positioned = true`. Add `"x"`/`"y"` nowhere in `SNAP_PROPS` — position lands as a rect and rects are already snapshotted (`:351-354`).

- [ ] **Step 4: Run** — `lune run tests/facet_adapter.spec && lune run tests/run && lune run tools/check_adapters` → PASS. If the Anchor refuses `offsetX` bound to a signal, or the rect does not land at x/y, STOP and report (Facet-side; Plan B territory) — do not patch Facet here.

- [ ] **Step 5: Commit**

```bash
stylua frameworks/facet/adapter.luau tests/facet_adapter.spec.luau
git add frameworks/facet/adapter.luau tests/facet_adapter.spec.luau
git commit -m "feat(facet adapter): canvas → UI.Anchor, x/y offsets, updateItems in one refresh"
```

---

### Task 4: Vide adapter — canvas Frame, bound `Position`, `updateItems`

**Files:**
- Modify: `frameworks/vide/adapter.luau:54-69` (add `positionProp`), `:83-128` (`buildList` — no `UIListLayout` when positioned), `:130-179` (`buildNode`), `:240-318` (`applyStep`), `:383` (capabilities)
- Test: `tests/vide_adapter.spec.luau` (append)

**Interfaces:**
- Consumes: Task 1 shapes. `resolveSource(ctx, itemCtx, v)` returns a literal or a vide source function (`:23-33`).
- Produces: `capabilities.positioned = true`.

- [ ] **Step 1: Failing test** — append to `tests/vide_adapter.spec.luau`:

```lua
assert(a.capabilities.positioned == true, "vide must declare positioned (a bound Position is its idiom)")
```

- [ ] **Step 2: Run** — `lune run tests/vide_adapter.spec` → FAIL.

- [ ] **Step 3: Implement**

After `barSizeProp`:
```lua
-- A positioned child binds `Position` to the pair of sources — vide's own
-- spelling of "this property is derived": any property accepts a function and
-- it re-evaluates when a source it read changes (NOTES.md binding choices).
local function positionProp(ctx: any, itemCtx: any, x: any, y: any): any
	local rx = resolveSource(ctx, itemCtx, x)
	local ry = resolveSource(ctx, itemCtx, y)
	if type(rx) == "function" or type(ry) == "function" then
		return function(): UDim2
			local px = if type(rx) == "function" then (rx :: any)() else rx
			local py = if type(ry) == "function" then (ry :: any)() else ry
			return UDim2.fromOffset(px, py)
		end
	end
	return UDim2.fromOffset(rx, ry)
end

-- merges the canvas-child placement into a props table, if the node has one
local function withPosition(ctx: any, itemCtx: any, node: any, props: { [any]: any }): { [any]: any }
	local p = node.props or {}
	if p.x ~= nil then
		props.Position = positionProp(ctx, itemCtx, p.x, p.y)
	end
	return props
end
```
`buildNode` signature becomes `(ctx, node, itemCtx, positioned: boolean?)`; each kind's props table is wrapped in `withPosition(ctx, itemCtx, node, {...})`; panel children are built with `positioned = false`; new kind:
```lua
	elseif node.kind == "canvas" then
		local p = node.props or {}
		local props: { [any]: any } = withPosition(ctx, itemCtx, node, {
			Name = node.id,
			BackgroundTransparency = 1,
			Size = if p.width ~= nil then UDim2.fromOffset(p.width, p.height) else UDim2.fromScale(1, 1),
		})
		for _, child in node.children or {} do
			table.insert(props, buildNode(ctx, child, itemCtx, true))
		end
		return ctx.vide.create("Frame")(props)
	elseif node.kind == "list" then
		return buildList(ctx, node, positioned == true)
```
`buildList(ctx, node, positioned)`: when `positioned`, the container is `Size = UDim2.fromScale(1, 1)` with NO `UIListLayout` child and the row `apply` binds only `LayoutOrder` as before (harmless without a layout); the row's own template root carries the bound `Position` via `withPosition`. When not positioned, unchanged.

`applyStep`, before `addItem`:
```lua
	elseif step.kind == "updateItems" then
		local list = ctx.lists[step.listState]
		assert(list, `vide: unknown list {tostring(step.listState)}`)
		-- N synchronous source writes: vide has no batch here by design (see the
		-- flush note above) — each write re-evaluates the bound Position at once
		for _, u in step.updates do
			local shell = list.byKey[u.key]
			assert(shell, `vide: updateItems '{u.key}' is not live in {step.listState}`)
			for field, value in u.fields :: { [string]: any } do
				local fieldSource = shell.fields[field]
				assert(fieldSource, `vide: item {u.key} has no field '{field}'`)
				fieldSource(value)
			end
		end
```
Capabilities: add `positioned = true`.

- [ ] **Step 4: Run** — `lune run tests/vide_adapter.spec && lune run tests/run` → PASS (live-only: the Studio drive in Task 12 is the behavioral proof).

- [ ] **Step 5: Commit**

```bash
stylua frameworks/vide/adapter.luau tests/vide_adapter.spec.luau
git add frameworks/vide/adapter.luau tests/vide_adapter.spec.luau
git commit -m "feat(vide adapter): canvas Frame with bound Position, updateItems"
```

---

### Task 5: Fusion adapter — canvas Frame, `Computed` Position, `updateItems`

**Files:**
- Modify: `frameworks/fusion/adapter.luau:72-82` (add `positionProp` after `barSizeProp`), `:168-190` (`buildList`), `:201-250` (`buildNode`), `:334-400` (`applyStep`), capabilities line (grep `capabilities =`)
- Test: `tests/fusion_adapter.spec.luau` (append `assert(a.capabilities.positioned == true)`)

**Interfaces:** consumes `resolveSource(ctx, itemCtx, v)` + `isState(v)` (`:60-82`), `withExtra(props, extra)` (`:109`).

- [ ] **Step 1: Failing test** — append: `assert(a.capabilities.positioned == true, "fusion must declare positioned")`. Run `lune run tests/fusion_adapter.spec` → FAIL.

- [ ] **Step 2: Implement**

```lua
local function positionProp(ctx: any, scope: any, itemCtx: any, x: any, y: any): any
	local rx = resolveSource(ctx, itemCtx, x)
	local ry = resolveSource(ctx, itemCtx, y)
	if isState(rx) or isState(ry) then
		return scope:Computed(function(use: any): UDim2
			local px = if isState(rx) then use(rx) else rx
			local py = if isState(ry) then use(ry) else ry
			return UDim2.fromOffset(px, py)
		end)
	end
	return UDim2.fromOffset(rx, ry)
end

local function withPosition(ctx: any, scope: any, itemCtx: any, node: any, props: { [any]: any }): { [any]: any }
	local p = node.props or {}
	if p.x ~= nil then
		props.Position = positionProp(ctx, scope, itemCtx, p.x, p.y)
	end
	return props
end
```
`buildNode(ctx, scope, node, itemCtx, extraProps, positioned: boolean?)`: wrap each kind's props in `withPosition(ctx, scope, itemCtx, node, withExtra({...}, extraProps))`; canvas kind:
```lua
	elseif node.kind == "canvas" then
		local p = node.props or {}
		local children: { any } = {}
		for _, child in node.children or {} do
			table.insert(children, buildNode(ctx, scope, child, itemCtx, nil, true))
		end
		return scope:New("Frame")(withPosition(ctx, scope, itemCtx, node, withExtra({
			Name = node.id,
			BackgroundTransparency = 1,
			Size = if p.width ~= nil then UDim2.fromOffset(p.width, p.height) else UDim2.fromScale(1, 1),
			[Fusion.Children] = children,
		}, extraProps)))
	elseif node.kind == "list" then
		return buildList(ctx, scope, node, extraProps, positioned == true)
```
`buildList(..., positioned)`: when positioned, `Size = UDim2.fromScale(1, 1)` and `[Fusion.Children] = { forResult }` (no `UIListLayout`).

`applyStep` `updateItems` branch (before `addItem`):
```lua
	elseif step.kind == "updateItems" then
		local list = ctx.lists[step.listState]
		assert(list, `fusion: unknown list {tostring(step.listState)}`)
		for _, u in step.updates do
			local shell = list.byKey[u.key]
			assert(shell, `fusion: updateItems '{u.key}' is not live in {step.listState}`)
			for field, value in u.fields :: { [string]: any } do
				local fieldValue = shell.fields[field]
				assert(fieldValue, `fusion: item {u.key} has no field '{field}'`)
				fieldValue:set(value)
			end
		end
```
Capabilities: add `positioned = true`.

- [ ] **Step 3: Run** — `lune run tests/fusion_adapter.spec && lune run tests/run` → PASS.

- [ ] **Step 4: Commit**

```bash
stylua frameworks/fusion/adapter.luau tests/fusion_adapter.spec.luau
git add frameworks/fusion/adapter.luau tests/fusion_adapter.spec.luau
git commit -m "feat(fusion adapter): canvas Frame with Computed Position, updateItems"
```

---

### Task 6: React adapter — canvas Frame, Position from props, `updateItems`

**Files:**
- Modify: `frameworks/react/adapter.luau:63-66` (add `positionProp`), `:114-142` (`buildListElement`), `:144-205` (`buildNode`), `:327-409` (`applyStep`), capabilities line
- Test: `tests/react_adapter.spec.luau` (append `assert(a.capabilities.positioned == true)`)

**Interfaces:** consumes `resolveValue(model, item, v)` (`:35-44`), `withExtra`.

- [ ] **Step 1: Failing test** — append the capability assert; run `lune run tests/react_adapter.spec` → FAIL.

- [ ] **Step 2: Implement**

```lua
local function positionProp(model: any, item: any, x: any, y: any): UDim2
	return UDim2.fromOffset(resolveValue(model, item, x), resolveValue(model, item, y))
end

local function withPosition(model: any, item: any, node: any, props: { [any]: any }): { [any]: any }
	local p = node.props or {}
	if p.x ~= nil then
		props.Position = positionProp(model, item, p.x, p.y)
	end
	return props
end
```
`buildNode(ctx, node, model, item, extraProps, positioned: boolean?)`: wrap each kind's props; canvas:
```lua
	elseif node.kind == "canvas" then
		local p = node.props or {}
		local children: { any } = {}
		for _, child in node.children or {} do
			table.insert(children, buildNode(ctx, child, model, item, nil, true))
		end
		return React.createElement(
			"Frame",
			withPosition(model, item, node, withExtra({
				Name = node.id,
				BackgroundTransparency = 1,
				Size = if p.width ~= nil then UDim2.fromOffset(p.width, p.height) else UDim2.fromScale(1, 1),
			}, extraProps)),
			children
		)
	elseif node.kind == "list" then
		return buildListElement(ctx, node, model, extraProps, positioned == true)
```
`buildListElement(..., positioned)`: when positioned, no `UIListLayout` child and `Size = UDim2.fromScale(1, 1)`. The row component (`registerListTemplates`, `:227`) already re-renders when `props.item` identity changes — `updateItems` must therefore clone-and-replace each touched item (the memo-correctness rule in the `updateItem` comment `:346-357`):
```lua
	elseif step.kind == "updateItems" then
		local list = model.lists[step.listState]
		assert(list, `react: unknown list {tostring(step.listState)}`)
		for _, u in step.updates do
			local old = list.byKey[u.key]
			assert(old, `react: updateItems '{u.key}' is not live in {step.listState}`)
			local updated = table.clone(old)
			for field, value in u.fields :: { [string]: any } do
				updated[field] = value
			end
			list.byKey[u.key] = updated
		end
```
(the one `h.root:render(...)` at the end is react's single reconciliation.) Capabilities: add `positioned = true`.

- [ ] **Step 3: Run** — `lune run tests/react_adapter.spec && lune run tests/run` → PASS.

- [ ] **Step 4: Commit**

```bash
stylua frameworks/react/adapter.luau tests/react_adapter.spec.luau
git add frameworks/react/adapter.luau tests/react_adapter.spec.luau
git commit -m "feat(react adapter): canvas Frame, Position from item props, updateItems"
```

---

### Task 7: Blend adapter — canvas Frame, `Blend.Computed` Position, `updateItems`

**Files:**
- Modify: `frameworks/blend/adapter.luau:77-82` (add `positionProp`), `:154-179` (`buildList`), `:181-231` (`buildNode`), `:387-` (`applyStep`), capabilities line
- Test: `tests/blend_adapter.spec.luau` (append `assert(a.capabilities.positioned == true)`)

**Interfaces:** consumes `resolveState(ctx, itemCtx, v)` (returns a `Blend.State` or literal), `withExtra`. `Blend.Computed(a, b, fn)` is variadic (`frameworks/blend/vendor/quenty/@quenty/blend/src/Shared/Blend/Blend.lua:163`).

- [ ] **Step 1: Failing test** — append the capability assert; run → FAIL.

- [ ] **Step 2: Implement**

```lua
local function positionProp(ctx: any, itemCtx: any, x: any, y: any): any
	return ctx.Blend.Computed(resolveState(ctx, itemCtx, x), resolveState(ctx, itemCtx, y), function(px: any, py: any): UDim2
		return UDim2.fromOffset(px, py)
	end)
end

local function withPosition(ctx: any, itemCtx: any, node: any, props: { [any]: any }): { [any]: any }
	local p = node.props or {}
	if p.x ~= nil then
		props.Position = positionProp(ctx, itemCtx, p.x, p.y)
	end
	return props
end
```
`buildNode(ctx, node, itemCtx, extraProps, positioned: boolean?)`; canvas kind mirrors Task 5 with `Blend.New("Frame")` and children inserted into the props array (blend's idiom, `:200-202`); `buildList(ctx, node, extraProps, positioned)` drops the `UIListLayout` and uses `Size = UDim2.fromScale(1, 1)` when positioned. `updateItems`:
```lua
	elseif step.kind == "updateItems" then
		local list = ctx.lists[step.listState]
		assert(list, `blend: unknown list {tostring(step.listState)}`)
		for _, u in step.updates do
			local shell = list.byKey[u.key]
			assert(shell, `blend: updateItems '{u.key}' is not live in {step.listState}`)
			for field, value in u.fields :: { [string]: any } do
				local fieldValue = shell.fields[field]
				assert(fieldValue, `blend: item {u.key} has no field '{field}'`)
				fieldValue.Value = value
			end
		end
```
Capabilities: add `positioned = true`.

- [ ] **Step 3: Run** — `lune run tests/blend_adapter.spec && lune run tests/run` → PASS.

- [ ] **Step 4: Commit**

```bash
stylua frameworks/blend/adapter.luau tests/blend_adapter.spec.luau
git add frameworks/blend/adapter.luau tests/blend_adapter.spec.luau
git commit -m "feat(blend adapter): canvas Frame with Computed Position, updateItems"
```

---

### Task 8: `nameplates` workload

**Files:**
- Create: `workloads/nameplates.luau`
- Create: `tests/nameplates.spec.luau`
- Modify: `workloads/registry.luau` (add line), `tests/run.luau:11` (add `"./nameplates.spec"`), `tests/flux_adapter.spec.luau:45` (add `"nameplates"` to the unsupported loop)
- Reference: `workloads/killfeed_nameplates.luau` (`churnQueue`, stash discipline)

**Interfaces:**
- Produces: `{ name = "nameplates", requires = { "reactive", "keyedList", "positioned" }, sizes = { S = 50, M = 120, L = 250 }, build, script }`. Item fields: `key, name, level, hp, cast, x, y`. List state id `"plates"`. Step kinds used: `updateItems` (420), `updateItem` (90: 60 hp + 30 level), `addItem`+`removeItem` (60), `noop` (30).

- [ ] **Step 1: Write the failing spec** — `tests/nameplates.spec.luau`:

```lua
--!strict
local Prng = require("../runner/lune/lib/prng")
local scene = require("../runner/lune/lib/scene")
local helpers = require("./helpers")
local workloads = require("../workloads/registry")

local wl = workloads.nameplates()
assert(wl.name == "nameplates")
assert(wl.sizes.S == 50 and wl.sizes.M == 120 and wl.sizes.L == 250)
assert(table.find(wl.requires, "positioned") ~= nil, "nameplates needs the positioned capability")

-- determinism
assert(helpers.deepEqual(wl.build("S", Prng.new(1)), wl.build("S", Prng.new(1))), "build must be deterministic")
assert(helpers.deepEqual(wl.script("S", Prng.new(2)), wl.script("S", Prng.new(2))), "script must be deterministic")

for _, size in { "S", "M", "L" } do
	local n = wl.sizes[size]
	local spec = wl.build(size :: any, Prng.new(1))
	local steps = wl.script(size :: any, Prng.new(2))
	assert(scene.validate(spec) == true)
	assert(scene.validateSteps(spec, steps) == true, `{size}: script must be cycle-safe`)

	-- shape: canvas root, one plate list, 6 nodes per plate, all plates live at mount
	assert(spec.root.kind == "canvas" and spec.root.props.width == 1280 and spec.root.props.height == 720)
	assert(#spec.state.plates == n, `{size}: {n} plates at mount, got {#spec.state.plates}`)
	local template = spec.root.children[1].template
	local nodes = 0
	local function count(node: any)
		nodes += 1
		for _, c in node.children or {} do
			count(c)
		end
	end
	count(template)
	assert(nodes == 6, `a plate is 6 nodes, got {nodes}`)
	for _, item in spec.state.plates do
		assert(item.x >= 0 and item.x <= 1280 and item.y >= 0 and item.y <= 720, "plates start inside the canvas")
		assert(item.x % 1 == 0 and item.y % 1 == 0, "positions are integer px")
	end

	-- exact kind mix (20 slots x 30 blocks)
	assert(#steps == 600)
	local counts: { [string]: number } = {}
	local liveCount = n
	local floor = n - n // 5
	local minLive, maxLive = n, n
	for _, st in steps do
		counts[st.kind] = (counts[st.kind] or 0) + 1
		if st.kind == "updateItems" then
			assert(st.listState == "plates")
			assert(#st.updates == liveCount, `{size}: a tick must move EVERY live plate ({liveCount}), got {#st.updates}`)
			for _, u in st.updates do
				assert(u.fields.x ~= nil and u.fields.y ~= nil, "a tick writes x and y")
				assert(u.fields.x >= 0 and u.fields.x <= 1280 and u.fields.y >= 0 and u.fields.y <= 720, "projection stays inside the canvas")
				assert(u.fields.x % 1 == 0 and u.fields.y % 1 == 0, "projection is integer px")
			end
		elseif st.kind == "addItem" then
			liveCount += 1
		elseif st.kind == "removeItem" then
			liveCount -= 1
		elseif st.kind == "updateItem" then
			assert(st.field == "hp" or st.field == "level", `{size}: updateItem field {st.field}`)
		end
		minLive = math.min(minLive, liveCount)
		maxLive = math.max(maxLive, liveCount)
	end
	assert(counts.updateItems == 420, `{size}: 14 ticks x 30 = 420, got {counts.updateItems}`)
	assert(counts.updateItem == 90, `{size}: 2 hp + 1 threat per block = 90, got {counts.updateItem}`)
	assert((counts.addItem or 0) + (counts.removeItem or 0) == 60, `{size}: 2 churn slots x 30 = 60`)
	assert(counts.addItem == counts.removeItem, `{size}: churn must return membership to the initial set`)
	assert(counts.noop == 30)
	assert(liveCount == n, `{size}: the script must end with every plate live`)
	assert(minLive >= floor, `{size}: live plates fell to {minLive}, floor is {floor}`)
	assert(maxLive == n, `{size}: live plates never exceed the initial set`)

	-- the all-dirty class must dominate the script (tick is the p50)
	assert(counts.updateItems / #steps == 0.7)

	-- a tick actually moves plates: consecutive ticks disagree on at least one x
	local firstTick, secondTick
	for _, st in steps do
		if st.kind == "updateItems" then
			if firstTick == nil then
				firstTick = st
			elseif secondTick == nil then
				secondTick = st
				break
			end
		end
	end
	assert(firstTick.updates[1].key == secondTick.updates[1].key)
	assert(firstTick.updates[1].fields.x ~= secondTick.updates[1].fields.x or firstTick.updates[1].fields.y ~= secondTick.updates[1].fields.y, "the camera must move between ticks")
end

return true
```

- [ ] **Step 2: Run** — `lune run tests/nameplates.spec` → FAIL (`workloads.nameplates` is nil).

- [ ] **Step 3: Implement** `workloads/nameplates.luau`:

```lua
--!strict
--[[ NAMEPLATES — the all-dirty class. 50–250 world-anchored plates whose screen
	position changes EVERY tick (a seeded pinhole camera orbits a field of units),
	plus range enter/leave churn, hp waves and a threat flip. 70 % of the script is
	the tick, so a matrix `stepP50Ms` for this workload IS the "every plate moved"
	number — the shape a WoW-style nameplate layer, a minimap, or any world-space
	label HUD pays per frame.

	Design spec: Facet docs/superpowers/specs/2026-09-02-facet-wicked-fast-design.md §1.3 ]]

local CANVAS_W, CANVAS_H = 1280, 720
local BLOCKS = 30
local SLOTS = 20
local TICK_SLOTS = 14 -- slots 1..14
-- slots 15,16 hp; 17 threat; 18,19 churn; 20 noop
local CHURN_SLOTS_PER_BLOCK = 2

-- world: units on a 200x200 plane, camera on a ring of radius 90 at height 40
-- looking at the origin; yaw advances per tick, pitch bobs. Focal length is a
-- plain scale so x,y land in the canvas for every unit in front of the camera.
local WORLD_HALF = 100
local CAM_RADIUS = 90
local CAM_HEIGHT = 40
local FOCAL = 520
local YAW_STEP = 0.02

local function clamp(v: number, lo: number, hi: number): number
	return if v < lo then lo elseif v > hi then hi else v
end

-- projects a world point into integer canvas px; a point behind or beside the
-- camera is clamped to the canvas edge (removal is the churn's job, not the
-- projector's — every live plate moves every tick, which is the class)
local function project(wx: number, wy: number, wz: number, yaw: number, pitch: number): (number, number)
	local cx, cz = CAM_RADIUS * math.cos(yaw), CAM_RADIUS * math.sin(yaw)
	local cy = CAM_HEIGHT
	-- camera-space: forward = toward the origin
	local dx, dy, dz = wx - cx, wy - cy, wz - cz
	local fx, fz = -math.cos(yaw), -math.sin(yaw)
	local depth = dx * fx + dz * fz
	local right = dx * -fz + dz * fx
	local up = dy + depth * math.sin(pitch)
	if depth < 1 then
		depth = 1
	end
	local sx = CANVAS_W / 2 + FOCAL * right / depth
	local sy = CANVAS_H / 2 - FOCAL * up / depth
	return math.floor(clamp(sx, 0, CANVAS_W)), math.floor(clamp(sy, 0, CANVAS_H))
end

local function makeUnits(n: number, rng: any): { any }
	local units = table.create(n)
	for i = 1, n do
		units[i] = {
			key = `u{i}`,
			name = `Unit {i}`,
			level = tostring(rng:nextInt(1, 60)),
			hp = rng:next(),
			cast = 0,
			caster = rng:next() < 0.2,
			wx = rng:nextInt(-WORLD_HALF, WORLD_HALF),
			wy = rng:nextInt(0, 4),
			wz = rng:nextInt(-WORLD_HALF, WORLD_HALF),
		}
	end
	return units
end

local function plateItem(u: any, yaw: number, pitch: number): any
	local x, y = project(u.wx, u.wy, u.wz, yaw, pitch)
	return { key = u.key, name = u.name, level = u.level, hp = u.hp, cast = u.cast, x = x, y = y }
end

local function build(size: "S" | "M" | "L", rng: any): any
	local n = if size == "S" then 50 elseif size == "M" then 120 else 250
	local units = makeUnits(n, rng)
	local plates = table.create(n)
	for i, u in units do
		plates[i] = plateItem(u, 0, 0)
	end
	return {
		state = { plates = plates },
		root = {
			kind = "canvas",
			id = "Root",
			props = { width = CANVAS_W, height = CANVAS_H },
			children = {
				{
					kind = "list",
					id = "Plates",
					itemsState = "plates",
					template = {
						kind = "panel",
						id = "Plate",
						direction = "vertical",
						props = { x = { item = "x" }, y = { item = "y" } },
						children = {
							{
								kind = "panel",
								id = "Head",
								direction = "horizontal",
								children = {
									{ kind = "label", id = "Name", props = { text = { item = "name" }, textSize = 14 } },
									{ kind = "label", id = "Level", props = { text = { item = "level" }, textSize = 12 } },
								},
							},
							{ kind = "bar", id = "Hp", props = { value = { item = "hp" } } },
							{ kind = "bar", id = "Cast", props = { value = { item = "cast" } } },
						},
					},
				},
			},
		},
	}
end

local function script(size: "S" | "M" | "L", rng: any): { any }
	local n = if size == "S" then 50 elseif size == "M" then 120 else 250
	-- the SAME units as build: build and script take independent rngs, so the
	-- unit field is regenerated from a fixed seed both sides agree on
	local units = makeUnits(n, (require("../runner/lune/lib/prng") :: any).new(1))
	local floor = n - n // 5 -- range churn never drops below 80 % live
	local steps = {}
	local yaw, pitch = 0, 0
	local tickIndex = 0

	local live: { any } = table.clone(units)
	local stash: { any } = {}
	local churnSlotsLeft = BLOCKS * CHURN_SLOTS_PER_BLOCK

	local function tick()
		tickIndex += 1
		yaw += YAW_STEP
		pitch = 0.15 * math.sin(tickIndex * 0.05)
		local updates = table.create(#live)
		for i, u in live do
			local x, y = project(u.wx, u.wy, u.wz, yaw, pitch)
			local fields: { [string]: any } = { x = x, y = y }
			if u.caster then
				u.cast = (u.cast + 0.05) % 1
				fields.cast = u.cast
			end
			updates[i] = { key = u.key, fields = fields }
		end
		table.insert(steps, { kind = "updateItems", listState = "plates", updates = updates })
	end

	--[[ RANGE CHURN, killfeed's stash-and-re-add discipline: a plate leaving range
		is removed and stashed; a later slot re-adds a stashed plate at its CURRENT
		projection. `churnSlotsLeft - #stash` starts even (60 - 0) and only a
		remove moves it (by -2), so it reaches 0 exactly; from there every slot
		re-adds, the stash ends empty, and the same keys are live again for the
		next pass (`scene.validateSteps` proves the wraparound). ]]
	local function churn()
		local drain = churnSlotsLeft <= #stash
		churnSlotsLeft -= 1
		if (not drain) and #live > floor and rng:next() < 0.5 then
			local idx = rng:nextInt(1, #live)
			local u = table.remove(live, idx)
			table.insert(stash, u)
			table.insert(steps, { kind = "removeItem", listState = "plates", key = u.key })
		elseif #stash > 0 then
			local u = table.remove(stash, 1)
			table.insert(live, u)
			table.insert(steps, { kind = "addItem", listState = "plates", item = plateItem(u, yaw, pitch) })
		else
			-- nothing stashed and the coin said "add": remove instead so the slot
			-- still does churn work (keeps the pinned 60 churn steps)
			local idx = rng:nextInt(1, #live)
			local u = table.remove(live, idx)
			table.insert(stash, u)
			table.insert(steps, { kind = "removeItem", listState = "plates", key = u.key })
		end
	end

	for _ = 1, BLOCKS do
		for slot = 1, SLOTS do
			if slot <= TICK_SLOTS then
				tick()
			elseif slot <= 16 then
				local u = live[rng:nextInt(1, #live)]
				u.hp = rng:next()
				table.insert(steps, { kind = "updateItem", listState = "plates", key = u.key, field = "hp", value = u.hp })
			elseif slot == 17 then
				local u = live[rng:nextInt(1, #live)]
				u.level = if string.sub(u.level, 1, 3) == "!! " then string.sub(u.level, 4) else `!! {u.level}`
				table.insert(steps, { kind = "updateItem", listState = "plates", key = u.key, field = "level", value = u.level })
			elseif slot <= 19 then
				churn()
			else
				table.insert(steps, { kind = "noop" })
			end
		end
	end
	return steps
end

return function()
	return {
		name = "nameplates",
		requires = { "reactive", "keyedList", "positioned" },
		sizes = { S = 50, M = 120, L = 250 },
		build = build,
		script = script,
	}
end
```

Notes for the implementer:
- The `churn()` drain arithmetic must make `addItem == removeItem` exactly and end with `#stash == 0` at every size; the spec pins it. If the coin-flip version cannot guarantee "stash ends empty" (it can: once `drain` is true every slot re-adds; before that, a remove only happens when `#live > floor`), simplify to a deterministic alternation (remove on even remaining count, add on odd) — the pinned counts are what matter, not the coin.
- `build` and `script` each receive their own `rng`; units are regenerated with `Prng.new(1)` inside `script` so both sides describe the same field. Put `local Prng = require("../runner/lune/lib/prng")` at the top of the file instead of the inline require shown above.
- After the file exists, register it: `workloads/registry.luau` gets `nameplates = require("./nameplates"),`; `tests/run.luau` gets `"./nameplates.spec",` after the killfeed line; `tests/flux_adapter.spec.luau:45` loop gets `"nameplates"`, and the flux `note` assertions still hold (flux lacks `reactive`).

- [ ] **Step 4: Run** — `lune run tests/nameplates.spec && lune run tests/run && lune run tools/check_adapters` → PASS. Then a real headless drive: `lune run runner/lune/run_matrix --frameworks facet,_fixture --workloads nameplates --sizes S --samples 50 --warmup 5 --out artifacts/nameplates-smoke.json` → both rows `status = "ok"`.

- [ ] **Step 5: Commit**

```bash
stylua workloads/nameplates.luau tests/nameplates.spec.luau workloads/registry.luau tests/run.luau tests/flux_adapter.spec.luau
git add workloads/nameplates.luau tests/nameplates.spec.luau workloads/registry.luau tests/run.luau tests/flux_adapter.spec.luau
git commit -m "feat(workloads): nameplates — the all-dirty class (every plate moves every tick)"
```

---

### Task 9: `damage_fountain` workload

**Files:**
- Create: `workloads/damage_fountain.luau`, `tests/damage_fountain.spec.luau`
- Modify: `workloads/registry.luau`, `tests/run.luau`, `tests/flux_adapter.spec.luau:45`

**Interfaces:**
- Produces: `{ name = "damage_fountain", requires = { "reactive", "keyedList", "positioned" }, sizes = { S = 30, M = 80, L = 200 }, build, script }`. List state `"numbers"`, item fields `key, text, x, y`. Script = 600 steps in triplets `addItem` (spawn), `updateItems` (rise: every live y − 4), `removeItem` (retire oldest), one item per structural step, FIFO lifetime chosen so the steady live count ≈ size, FIFO drained to empty by step 600.

- [ ] **Step 1: Failing spec** — `tests/damage_fountain.spec.luau`:

```lua
--!strict
local Prng = require("../runner/lune/lib/prng")
local scene = require("../runner/lune/lib/scene")
local helpers = require("./helpers")
local workloads = require("../workloads/registry")

local wl = workloads.damage_fountain()
assert(wl.name == "damage_fountain")
assert(wl.sizes.S == 30 and wl.sizes.M == 80 and wl.sizes.L == 200)
assert(table.find(wl.requires, "positioned") ~= nil)
assert(helpers.deepEqual(wl.build("S", Prng.new(1)), wl.build("S", Prng.new(1))))
assert(helpers.deepEqual(wl.script("S", Prng.new(2)), wl.script("S", Prng.new(2))))

for _, size in { "S", "M", "L" } do
	local n = wl.sizes[size]
	local spec = wl.build(size :: any, Prng.new(1))
	local steps = wl.script(size :: any, Prng.new(2))
	assert(scene.validate(spec) == true)
	assert(scene.validateSteps(spec, steps) == true, `{size}: script must be cycle-safe`)
	-- starts PRE-FILLED at n live numbers so the first frames already pay the
	-- steady-state bill (a fountain that starts empty measures nothing for 100 steps)
	assert(#spec.state.numbers == n, `{size}: {n} numbers at mount`)
	assert(#steps == 600)
	local counts: { [string]: number } = {}
	local live = n
	local minLive, maxLive = n, n
	for _, st in steps do
		counts[st.kind] = (counts[st.kind] or 0) + 1
		if st.kind == "addItem" then
			live += 1
			assert(st.item.x % 1 == 0 and st.item.y % 1 == 0 and st.item.x >= 0 and st.item.x <= 1280 and st.item.y >= 0 and st.item.y <= 720)
		elseif st.kind == "removeItem" then
			live -= 1
		elseif st.kind == "updateItems" then
			assert(#st.updates == live, `{size}: a rise moves every live number ({live}), got {#st.updates}`)
			for _, u in st.updates do
				assert(u.fields.y ~= nil and u.fields.x == nil, "a rise writes y only")
			end
		end
		minLive = math.min(minLive, live)
		maxLive = math.max(maxLive, live)
	end
	assert(counts.addItem == 200 and counts.removeItem == 200 and counts.updateItems == 200, `{size}: exact triplets`)
	assert(live == n, `{size}: membership must return to the mount set (got {live})`)
	assert(maxLive <= n + 1 and minLive >= n - 1, `{size}: live count must hover at n (saw {minLive}..{maxLive})`)
end

return true
```

- [ ] **Step 2: Run** → FAIL (nil workload).

- [ ] **Step 3: Implement** `workloads/damage_fountain.luau`:

```lua
--!strict
--[[ DAMAGE FOUNTAIN — per-frame structural churn in a free-position layer.
	Floating damage numbers spawn, rise, and retire EVERY frame. In a stack this
	class pays O(shifted siblings); in a canvas/anchor it should pay O(1) per
	add/remove, which isolates the framework's structural-sync cost from the
	list-shift floor nameplates cannot see. Steps stay single-kind (add | rise |
	remove) so the per-class number is legible; Studio frames mode reports the
	combined per-frame bill.

	Design spec: Facet docs/superpowers/specs/2026-09-02-facet-wicked-fast-design.md §1.4 ]]
local Prng = require("../runner/lune/lib/prng")

local CANVAS_W, CANVAS_H = 1280, 720
local TRIPLETS = 200 -- add, rise, remove ⇒ 600 steps
local RISE_PX = 4

local function spawnAt(rng: any, key: string): any
	return {
		key = key,
		text = tostring(rng:nextInt(10, 9999)),
		x = rng:nextInt(100, CANVAS_W - 100),
		y = rng:nextInt(200, CANVAS_H - 100),
	}
end

local function build(size: "S" | "M" | "L", rng: any): any
	local n = if size == "S" then 30 elseif size == "M" then 80 else 200
	local numbers = table.create(n)
	for i = 1, n do
		numbers[i] = spawnAt(rng, `d{i}`)
	end
	return {
		state = { numbers = numbers },
		root = {
			kind = "canvas",
			id = "Root",
			props = { width = CANVAS_W, height = CANVAS_H },
			children = {
				{
					kind = "list",
					id = "Numbers",
					itemsState = "numbers",
					template = {
						kind = "label",
						id = "Num",
						props = { text = { item = "text" }, textSize = 18, x = { item = "x" }, y = { item = "y" } },
					},
				},
			},
		},
	}
end

local function script(size: "S" | "M" | "L", rng: any): { any }
	local n = if size == "S" then 30 elseif size == "M" then 80 else 200
	-- the same mount set build produced (independent rngs; build's seed is 1)
	local seedRng = Prng.new(1)
	local live: { any } = table.create(n)
	for i = 1, n do
		live[i] = spawnAt(seedRng, `d{i}`)
	end
	local steps = {}
	local counter = n
	--[[ CYCLE SAFETY: every triplet adds one FRESH key and retires the OLDEST
		live key, so after 200 triplets the live set is exactly the 200 keys
		spawned in this pass — none of the mount keys. On the next pass the
		fresh keys `d{n+1..n+200}` would be re-added while still live. So the
		second half of the script retires ALL keys spawned in the first half and
		re-adds the MOUNT keys in order: the live set at step 600 equals the
		mount set, membership-identical, and the wraparound is legal. Keys
		re-added get a fresh position (a new number, same key). ]]
	local mountKeys = table.create(n)
	for i = 1, n do
		mountKeys[i] = `d{i}`
	end
	for t = 1, TRIPLETS do
		-- add
		local key
		if t <= TRIPLETS / 2 then
			counter += 1
			key = `d{counter}`
		else
			-- second half: re-add mount keys (retired by now) in original order
			key = mountKeys[((t - TRIPLETS / 2 - 1) % n) + 1]
			-- if a mount key is still live (n > 100), retire it first below
		end
		-- if the key we want to add is still live, retire it first (counts as
		-- this triplet's remove) — keeps every triplet exactly add/rise/remove
		local stillLive = nil
		for i, item in live do
			if item.key == key then
				stillLive = i
				break
			end
		end
		if stillLive ~= nil then
			table.insert(steps, { kind = "removeItem", listState = "numbers", key = key })
			table.remove(live, stillLive)
		end
		local item = spawnAt(rng, key)
		table.insert(live, item)
		table.insert(steps, { kind = "addItem", listState = "numbers", item = table.clone(item) })
		-- rise
		local updates = table.create(#live)
		for i, it in live do
			it.y = math.max(0, it.y - RISE_PX)
			updates[i] = { key = it.key, fields = { y = it.y } }
		end
		table.insert(steps, { kind = "updateItems", listState = "numbers", updates = updates })
		-- remove oldest (unless this triplet already spent its remove)
		if stillLive == nil then
			local oldest = table.remove(live, 1)
			table.insert(steps, { kind = "removeItem", listState = "numbers", key = oldest.key })
		end
	end
	return steps
end

return function()
	return {
		name = "damage_fountain",
		requires = { "reactive", "keyedList", "positioned" },
		sizes = { S = 30, M = 80, L = 200 },
		build = build,
		script = script,
	}
end
```

The implementer must make the spec's pins true: exactly 200/200/200, live count within `n−1..n+1`, and the step-600 live set == mount set (`scene.validateSteps` two-pass proves the wraparound). The sketch above needs the "re-add mount keys" arithmetic checked against `n > 100` at L (the second half has 100 triplets but 200 mount keys) — if it cannot be made exact with 200 triplets, use the simpler discipline: **every triplet retires the oldest and re-spawns THAT SAME KEY** (a fixed key pool of n, FIFO rotation): membership is the mount set at every step, live == n always, and `addItem`/`removeItem` alternate on the same key with the `updateItems` rise in between. That satisfies every pin (adjust the spec's `minLive/maxLive` to `n−1..n` in that case) and keeps the class honest (a real number pool recycles keys too). Prefer the simpler discipline unless the fresh-key one is exact.

- [ ] **Step 4: Register + run** — registry line `damage_fountain = require("./damage_fountain"),`; `tests/run.luau` add `"./damage_fountain.spec",`; flux loop add `"damage_fountain"`. `lune run tests/run && lune run tools/check_adapters` → PASS; smoke `lune run runner/lune/run_matrix --frameworks facet,_fixture --workloads damage_fountain --sizes S --samples 50 --warmup 5 --out artifacts/fountain-smoke.json` → `ok` rows.

- [ ] **Step 5: Commit**

```bash
stylua workloads/damage_fountain.luau tests/damage_fountain.spec.luau workloads/registry.luau tests/run.luau tests/flux_adapter.spec.luau
git add workloads/damage_fountain.luau tests/damage_fountain.spec.luau workloads/registry.luau tests/run.luau tests/flux_adapter.spec.luau
git commit -m "feat(workloads): damage_fountain — per-frame structural churn in a positioned layer"
```

---

### Task 10: Profile harnesses learn `updateItems` and the new workloads

**Files:**
- Modify: `tools/profile/attr.luau:102-109` (`bucketName`), `tools/profile/probe.luau:80-88` (captured step selection), `tools/profile/README.md`
- Modify: `CONTRIBUTING.md` (workload list / DSL section — add `canvas`, `x`/`y`, `updateItems`, `positioned` in the add-a-workload rules), `README.md` (workload table gets the two new rows once numbers exist — Task 11)

- [ ] **Step 1: `bucketName`** — add `elseif step.kind == "updateItems" then return \`updateItems-{step.listState}\`` before the fallback.

- [ ] **Step 2: `probe`** — the captured incremental solve picks `updateItem/hp` today. Add a 4th CLI arg `stepKind` (default `updateItem`): when `updateItems`, capture the first `updateItems` step instead:
```lua
local stepKind = process.args[4] or "updateItem"
local upd
for _, s in steps do
	if s.kind == stepKind and (stepKind ~= "updateItem" or s.field == "hp") then
		upd = s
		break
	end
end
assert(upd, `no {stepKind} step in {wlName}`)
```
Update the README usage lines for both tools.

- [ ] **Step 3: Verify** — `lune run tools/profile/attr nameplates S 1` and `lune run tools/profile/probe S nameplates 5 updateItems` both run to completion and print an `updateItems-plates` bucket / a captured solve. `stylua --check .` (profile dir is excluded, but keep the formatting anyway with `stylua tools/profile/attr.luau tools/profile/probe.luau`).

- [ ] **Step 4: Commit**

```bash
git add tools/profile/attr.luau tools/profile/probe.luau tools/profile/README.md CONTRIBUTING.md
git commit -m "feat(profile): updateItems bucket, probe captures a chosen step kind; DSL docs"
```

---

### Task 11: Lune matrix — the "before" envelope for the new workloads + chart

**Files:**
- Create: `results/lune-<date>-<facet sha>-wicked-before.json`
- Modify: `results/chart.html` (regenerated), `README.md` (numbers section gets a "wicked-fast before" block for the two workloads)

- [ ] **Step 1: Run the matrix** (foreground, background load quiet — check `uptime` first; CrashPlan paused if it is running):
```bash
lune run runner/lune/run_matrix --frameworks facet,_fixture --workloads nameplates,damage_fountain --sizes S,M,L --samples 750 --warmup 50 --retry-drift 2 --out results/lune-$(date +%F)-$(git -C ../Facet rev-parse --short HEAD)-wicked-before.json
```
Expected: 12 rows, all `ok`, drift ≤10 %.

- [ ] **Step 2: Gate** — `lune run tools/check_schema results/<file> && lune run tools/check_baselines && lune run tools/chart && tools/check.sh` → PASS.

- [ ] **Step 3: README** — under "Numbers", add a table "Wicked-fast campaign — before (Facet `<sha>`)" with `nameplates` and `damage_fountain` `stepP50Ms` at S/M/L for facet and `_fixture`.

- [ ] **Step 4: Commit**

```bash
git add results/lune-*-wicked-before.json results/chart.html README.md
git commit -m "results: wicked-fast before — nameplates + damage_fountain headless envelope"
```

---

### Task 12: Studio matrix — all six frameworks, loop + frames, S/M/L (orchestrator-driven)

This task is driven by the orchestrator (needs the Studio MCP bridge). Follow `runner/studio/DRIVING.md` exactly: stamp `FACETBENCH_MARKER`, `rojo build` → `artifacts/studio-place.rbxl`, open in Studio, Play, `FacetBenchRun:FireAllClients(json)` for `--workloads nameplates,damage_fountain --sizes S,M,L` loop and frames, scrape via `LogService:GetLogHistory()` → `lune run tools/studio_scrape` → `results/studio-<date>-<sha>-wicked-before.json`; `check_schema` + `check_baselines`; chart regenerated; write-up `docs/studio-runs/<date>-wicked-fast-before.md` with the per-framework table, the `_fixture` control, the census, and every "proven to bite" claim carrying its raw dump fragment.

Expected outcome: vide's `tick` at L is the speed target number; facet's `tick` at L is the before.

- [ ] Commit: `git add results/studio-*-wicked-before.json results/chart.html docs/studio-runs/*.md && git commit -m "results: wicked-fast before — live matrix for nameplates + damage_fountain"`

---

### Task 13: Attribution of a nameplates `tick` and a fountain add/remove at L

**Files:**
- Create: `docs/profiling/<date>-nameplates-attribution.md`

- [ ] **Step 1: Run the harnesses** (each 3× for the bimodality; report medians):
```bash
lune run tools/profile/attr nameplates L 3
lune run tools/profile/probe L nameplates 41 updateItems
lune run tools/profile/residual L nameplates
lune run tools/profile/attr damage_fountain L 3
```

- [ ] **Step 2: Write the doc** with: per-step-kind p50 for both workloads at L; the probe decomposition of one `tick` solve (build / measure / arrange / commit / rect_pass, and the "0 dirty" floor); `controller.stats()` counters per step (`measured`, `arranged`, `rectInserts`, `rectWrites`, `lastCommitVisits`, `ssVisited` if it exists); a ranked lever table mapping each measured ms to the spec's O1–O6 / W1 with the % of the tick it would remove; and the explicit statement of which spec candidates are <5 % and therefore dropped.

- [ ] **Step 3: Commit** — `git add docs/profiling/*.md && git commit -m "docs: nameplates tick + fountain churn attribution at L"`.

Output of this task = the input of Plan B (`docs/superpowers/plans/2026-09-02-wicked-fast-B-facet.md`), which is written only after this doc exists.

---

## Self-review

- Spec coverage: §1.1 DSL → Task 1; §1.2 adapters → Tasks 2–7; §1.3 → Task 8; §1.4 → Task 9; §1.5 runners/results/chart → Tasks 10–12; Part 2 step 0 → Task 13. flux honesty → Tasks 8/9 spec loop.
- Types: `updateItems` shape `{ listState, updates = { { key, fields } } }` used identically in Tasks 1–9; `positioned` capability name identical everywhere; `canvas` props `width`/`height` numeric px everywhere.
- Known open arithmetic: Task 9's fresh-key discipline is flagged with the simpler fallback; Task 8's churn coin flip has the deterministic fallback. Both are pinned by their specs, so a wrong choice cannot pass.
