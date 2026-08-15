--!strict
--[[ THE LAZY GRID — SwiftUI's `LazyVGrid`, on the substrate that already exists.

	WHAT IT IS. A collection laid out in `columns` lanes that mounts only the
	LINES OF CELLS the viewport touches. `UI.Grid` is the eager half and stays
	exactly what it is: it measures and arranges every cell, which is what
	SwiftUI's non-lazy `Grid` does too and says of itself — it "renders all of its
	child views immediately" (parity §16 [SW-16]). The lazy grids are the ones
	that "create items only as needed" ([SW-21]), and until this module nothing in
	LuauUI did. `docs/reference/swiftui-parity.md` §4.2.2 has the full argument.

	build(LuauUI, core, spec) -> {
	  blueprint, focusGroupName (the contributed group's name),
	  scrollTop (Signal px, the engine mirror),
	  pathOf(key) -> path?, focusKey(key) -> hit path?, revealItem(key) -> path?,
	  bindNativeScroll(controller, scrollPath?) -> unbind,
	  scrollTo(controller, offset), scrollPath() -> path?,
	  debugWindow() -> { [key]: true }, dump(), dispose()
	}
	spec: { id?, items (Readable {T}), key (T) -> string,
	  columns (integer >= 1, or Readable<integer> — the CROSS-axis lane count),
	  itemExtent (px number | Readable<number> | (line, use) -> px — ONE LINE OF
	    CELLS' size along the scroll axis, NOT one cell's),
	  viewportExtent (px number or Readable<number>),
	  gap? (px between cells ACROSS a line, default 0),
	  rowGap? (px between LINES, default 0),
	  overscan? (LINES either side, default 2),
	  cell (item, ctx: { scope, index, line, lane }) -> Blueprint,
	  onActivate? ((item, meta) -> ()),
	  width? (the grid's cross-axis Dim), env? }

	── THE FOUR-INPUT STORY, AND THE ONE THING THAT FORCED IT ───────────────────

	pointer/touch: the engine ScrollingFrame owns the scroll (wheel, pan, momentum,
	elastic); the mirror slides the window and a scroll never activates a cell.
	A tap on a cell activates through the auto-composed `handleActivate`.

	keyboard/gamepad: the windowed cell hits are ONE contributed focus group,
	`axis = "horizontal"` in the band's own ROW-MAJOR document order — so ±1 is the
	cell to the left or right and Left/Right read straight off the axis. **DOWN IS
	NOT ±1, IT IS ±lanes**, which the focus graph cannot express (an axis there is
	"vertical" or "horizontal", `focus_graph.luau`), so the second axis arrives
	through the existing `navigateIntercept` seam rather than by widening the focus
	graph from inside a control. Emitting the group as `vertical` would have been
	REACHABLE and wrong in SHAPE — Down walking visually rightward — which is
	precisely the difference between the reachability axis and the paradigm axis.

	A cell whose focus target leaves the window is handled the way `newVirtualList`
	handles it, and the reason is worth keeping: the ring never has to focus an
	unmounted node, because a step into the OVERSCAN band scrolls the window, which
	materializes the next line for the step after it. The control contributes NO
	`focusMoved` for this — see the block above `handleActivate`, where mutation
	testing proved that seam dead and the intercept's own keep-visible load-bearing.

	THE FULL-CELL FOCUSABLE HIT IS NOT DECORATION. `focus_map.autoGroups` emits a
	contribution's groups and does NOT descend into it, so a focusable this control
	never NAMES is unreachable by Tab and by the D-pad alike. An earlier draft
	contributed the bundle purely to learn its mounted path and returned no groups
	at all — a focus black hole with cells in it. The hit is what gives the control
	something to name.

	── THE TWO REUSES THAT ARE THE WHOLE DESIGN ─────────────────────────────────

	1. THE WINDOWING ARITHMETIC IS `src/virtual_extents.luau`, UNCHANGED, WITH ONE
	   CHANGE OF UNIT. That module is a pure running-offset index over a list of
	   extents; it has no notion of an "item" at all, so a grid uses it by making
	   ONE ENTRY MEAN ONE LINE OF CELLS instead of one item:

	       count   = ceil(#items / lanes)
	       extents = the per-line extents
	       gap     = rowGap

	   `offsetOf`, `extentOf`, `window` and `content` then answer in line units and
	   nothing about them had to be generalized. The cell<->line mapping is plain
	   division —

	       line = floor((index - 1) / lanes) + 1
	       the cells of line L are indices (L-1)*lanes + 1 .. min(N, L*lanes)

	   — which is an INDEX TRANSFORM, not windowing: it involves no offsets, no
	   search and no extents. `slotAt`/`boundaryOffset` are the index's insertion
	   vocabulary and a grid asks neither (it has no reorder), so the interface is
	   used as-is and under-used, never widened.

	2. THE MOUNTED BAND IS A REAL `UI.Grid`. The windowed lines are a CONTIGUOUS
	   run of items starting on a line boundary, so they are exactly what a
	   row-major flow grid wraps: one `UI.Grid { columns = lanes }`, absolutely
	   positioned at `index.offsetOf(firstLine)` inside the canvas, holding the
	   window's cells in order. The column width is therefore
	   `floor((innerW - gap * (lanes - 1)) / lanes)` because that IS the flow
	   grid's formula being executed — not a copy of it that agrees today. A short
	   last line keeps its column width and stays left-aligned for the same reason:
	   the flow grid derives the column from the OFFER and the lane count, never
	   from how many cells turned up.

	   Each mounted cell is wrapped in ONE `Cell` ZStack the control owns, which is
	   what lets it (a) pin the cell to its line's extent, so the flow grid's
	   per-line natural height is the number the index already committed to,
	   (b) carry the `virtualSlot` declaration the solver's lying-extent guard
	   reads, and (c) hold the focusable hit the contributed focus group names.
	   It also makes a structural cell (`UI.When`, `UI.ForEach`) safe: those
	   splice SEVERAL children into their parent, and inside the band that would
	   shift every following cell into the wrong lane. The wrapper is what makes
	   "one item, one grid child" true by construction rather than by convention.

	── AXIS: `LazyVGrid` ONLY, AND `axis = "x"` IS REFUSED ──────────────────────

	`newVirtualList` transposes to a horizontal strip because a list's line holds
	exactly one item, so "row height" and "item width" are the same number wearing
	two names. A grid's line holds `lanes` cells and the flow grid wraps ROW-MAJOR
	ONLY: there is no column-major mode to give a `LazyHGrid` its lanes, and
	hand-rolling one here would be the second column arithmetic this design exists
	to avoid. So the axis is refused at construction and named as the remaining
	half rather than half-built. See §4.2.2 of the parity doc.

	── WHAT DIES WITH THE WINDOW, AND WHAT DOES NOT ─────────────────────────────

	A CELL'S OWN STATE DIES WHEN THE CELL LEAVES THE WINDOW — the same honesty
	`newTable { virtualized = true }` owes and states. Anything a cell must keep
	across a scroll belongs in the consumer's model, not in the cell's scope; async
	work owned through `ctx.scope` is cancelled on window exit, which is the point.

	THE TENSION THAT MADE TABLE REFUSE `rowActions` DOES NOT EXIST HERE, and the
	difference is worth stating rather than copying the refusal. Table WRAPS each
	actionable row in a composite whose lifecycle is pruned by the DATA, so a row
	scrolling out of a virtualized Table would strand its engine. This control's
	only wrapper is the `Cell` ZStack, and it lives INSIDE the window's `ForEach` —
	its lifecycle IS the window's. There is nothing to strand, so there is nothing
	to refuse, and manufacturing a refusal to look consistent would be a lie about
	the mechanism.

	── SCROLL STABILITY: THE ANCHOR IS THE ITEM, NOT THE LINE ───────────────────

	A grid has two ways to move the ground under the player, and one anchor covers
	both because it is keyed on an ITEM:

	  * THE EXTENTS RE-DERIVE (a per-line `itemExtent` reads the accessibility text
	    offset, the theme metrics, the viewport). `newVirtualList` guards this.
	  * THE LANE COUNT CHANGES. A reflow moves EVERY item to a different line, so a
	    line-keyed anchor would faithfully hold a line the player was never looking
	    at. This case is a grid's own; a list never has it, because there an item
	    IS its line.

	So the anchor is `(the key of the first item of the line under the viewport's
	leading edge, the pixel delta into that line)`, captured on every offset the
	ENGINE reports, and re-applied by finding that item's NEW line whenever the
	index changes. It writes through the bound controller — the framework's one
	programmatic scroll write — never into the mirror.

	IT IS UNCONDITIONAL HERE, where `newVirtualList` scopes it to variable extents.
	That was not a judgement about anchoring but about not moving a shipped list's
	behaviour when a row is inserted above the viewport. This control has no
	shipped behaviour to preserve, and the reflow case needs the anchor on the
	UNIFORM path, so the exception has no reason to exist.

	── WHAT THIS DELIBERATELY DOES NOT SHIP ─────────────────────────────────────

	`minColumnWidth` is refused, with a route rather than a shrug. Deriving lanes
	from a minimum cell width needs the CROSS-axis size in px, which would be a
	second measured seam beside `viewportExtent`; the framework already exports the
	flow grid's own answer as `adaptive.columnsFor(available, minColumnWidth, gap)`,
	so a consumer binds `columns` to that and gets an adaptive grid with no new
	authority in this control. Selection, reorder and row actions are not offered
	at all: a cell is the consumer's blueprint and carries its own interaction
	beyond the hit's Activate.
]]

local contribution = require("../input/contribution")
local solverLib = require("../layout/solver")
local specGuard = require("../spec_guard")
local virtual_extents = require("../virtual_extents")

local virtual_grid = {}

local VIRTUAL_GRID_KEYS = specGuard.keySet({
	"axis",
	"cell",
	"columns",
	"env",
	"gap",
	"id",
	"itemExtent",
	"items",
	"key",
	"onActivate",
	"overscan",
	"rowGap",
	"viewportExtent",
	"width",
})

-- child 1 of a `Cell` is the control's own focusable hit; the consumer's
-- blueprint is everything from 2 on. `newVirtualList`'s row has the same shape
-- and the same number, for the same reason.
local SLOT_CONTENT_FROM = 2

-- a node id is interpolated into a Lua PATTERN below, so its magic characters
-- have to be escaped first
local function patternEscape(s: string): string
	return (s:gsub("%W", "%%%0"))
end

function virtual_grid.build(LuauUI: any, core: any, spec: any)
	--[[ ── CONSTRUCTION-TIME REFUSALS ──────────────────────────────────────────
		Each one names the boundary, the legal shapes, the value it got, and WHY
		the constraint exists. The two structural refusals run BEFORE the closed-key
		guard so they explain themselves instead of being reported as unknown keys. ]]
	if spec ~= nil and spec.axis ~= nil and spec.axis ~= "y" then
		error(
			`newVirtualGrid: axis = '{tostring(spec.axis)}' is refused — this control is SwiftUI's LazyVGrid and `
				.. "there is no LazyHGrid here yet. A grid's line holds `columns` cells, and `UI.Grid` wraps "
				.. "row-major ONLY: there is no column-major mode to give a horizontal grid its lanes, and "
				.. "hand-rolling one would be a second column arithmetic beside the flow grid's. Use "
				.. "newVirtualList for a sideways strip of single items, or a UI.ScrollView over a UI.Grid when "
				.. "the collection is small enough not to need windowing.",
			0
		)
	end
	if spec ~= nil and spec.minColumnWidth ~= nil then
		error(
			"newVirtualGrid: minColumnWidth is refused — deriving the lane count from a minimum cell width needs "
				.. "the CROSS-axis size in px, which would be a second measured seam beside viewportExtent. The "
				.. "flow grid's own arithmetic is already exported: bind `columns` to a memo over "
				.. "LuauUI.adaptive.columnsFor(availableWidth, minColumnWidth, gap) and the grid re-lanes itself "
				.. "with no new authority in this control.",
			0
		)
	end
	specGuard.assertKnownKeys("newVirtualGrid", spec, VIRTUAL_GRID_KEYS, "spec")

	assert(type(spec.key) == "function", "VirtualGrid.key is required: (item) -> a stable string identity")
	assert(type(spec.cell) == "function", "VirtualGrid.cell is required: (item, ctx) -> Blueprint")
	assert(
		type(spec.items) == "table" and type((spec.items :: any).get) == "function",
		"VirtualGrid.items is required: a Readable of the collection"
	)

	local UI = LuauUI.UI
	local id = spec.id or "VirtualGrid"

	-- ── the reactive scalars ────────────────────────────────────────────────
	-- Each is `number | Readable<number>` and resolves through a pair: `xIn(use)`
	-- inside a memo (registers the dependency) and `xNow()` at an imperative call
	-- site. Reading a Readable with `:get()` inside a memo is right once and never
	-- again, which is the silent staleness this shape exists to prevent.
	local lanesSpec = spec.columns
	local lanesIsLive = type(lanesSpec) == "table" and type((lanesSpec :: any).get) == "function"
	local function validLanes(v: any): boolean
		return type(v) == "number" and v == v and v >= 1 and math.floor(v) == v
	end
	assert(
		lanesIsLive or validLanes(lanesSpec),
		`VirtualGrid.columns must be an integer >= 1, or a Readable of one — got {tostring(lanesSpec)}. It is the `
			.. "CROSS-axis lane count (SwiftUI's `columns:` on LazyVGrid), and it is the number the mounted band's "
			.. "UI.Grid is given, so a fraction or a zero has no reading as a column count."
	)
	local function lanesNow(): number
		local v = if lanesIsLive then (lanesSpec :: any):get() else lanesSpec
		assert(validLanes(v), `VirtualGrid.columns resolved to {tostring(v)} — it must stay an integer >= 1`)
		return v
	end
	local function lanesIn(use: any): number
		local v = if lanesIsLive then use(lanesSpec) else lanesSpec
		assert(validLanes(v), `VirtualGrid.columns resolved to {tostring(v)} — it must stay an integer >= 1`)
		return v
	end
	if lanesIsLive then
		lanesNow() -- fail out of build(), not three frames away inside a memo
	end

	local extentSpec = spec.itemExtent
	local extentIsLive = type(extentSpec) == "table" and type((extentSpec :: any).get) == "function"
	local extentIsPerLine = type(extentSpec) == "function"
	assert(
		extentIsPerLine or extentIsLive or (type(extentSpec) == "number" and extentSpec > 0),
		"VirtualGrid.itemExtent must be a positive number, a Readable<number>, or a function (line, use) -> px: "
			.. "ONE LINE OF CELLS' size along the scroll axis, not one cell's. A number or Readable is UNIFORM and "
			.. "windows by line x pitch; a function is a PER-LINE extent and windows by a running-offset index. "
			.. "Read live facts (the preferred-text offset, the theme metrics) through the function's second "
			.. "argument `use`, or the extents will not re-derive when they move."
	)
	local function extentNow(): number
		return if extentIsLive then (extentSpec :: any):get() else extentSpec
	end
	local function extentIn(use: any): number
		return if extentIsLive then use(extentSpec) else extentSpec
	end

	local rowGapSpec: any = if spec.rowGap ~= nil then spec.rowGap else 0
	local rowGapIsLive = type(rowGapSpec) == "table" and type(rowGapSpec.get) == "function"
	assert(
		rowGapIsLive or (type(rowGapSpec) == "number" and rowGapSpec == rowGapSpec and rowGapSpec >= 0),
		"VirtualGrid.rowGap must be a non-negative number or a Readable<number>: the gutter between LINES. It is "
			.. "the index's gap, so the canvas, the window and the mounted band all read the same number."
	)
	local function rowGapIn(use: any): number
		return if rowGapIsLive then use(rowGapSpec) else rowGapSpec
	end
	local function rowGapNow(): number
		return if rowGapIsLive then (rowGapSpec :: any):get() else rowGapSpec
	end

	local gapSpec: any = if spec.gap ~= nil then spec.gap else 0
	assert(
		type(gapSpec) == "number" and gapSpec == gapSpec and gapSpec >= 0,
		"VirtualGrid.gap must be a non-negative number: the space between cells ACROSS a line. It is handed "
			.. "straight to the mounted band's UI.Grid, whose column width is derived from it."
	)

	local viewportSpec = spec.viewportExtent
	local viewportIsLive = type(viewportSpec) == "table" and type((viewportSpec :: any).get) == "function"
	assert(
		viewportIsLive or (type(viewportSpec) == "number" and viewportSpec > 0),
		"VirtualGrid.viewportExtent must be a positive number or a Readable<number>: the scroll host's height"
	)
	local function viewportIn(use: any): number
		return if viewportIsLive then use(viewportSpec) else viewportSpec
	end
	local function viewportNow(): number
		return if viewportIsLive then (viewportSpec :: any):get() else viewportSpec
	end

	local overscan: number = spec.overscan or 2
	assert(
		type(overscan) == "number" and overscan == overscan and overscan >= 0,
		"VirtualGrid.overscan must be a non-negative number of LINES either side of the viewport"
	)

	local scope = core:scope(`virtual-grid-{id}`)

	local boundController: any = nil
	local boundScrollPath: string? = nil
	local mountedScrollPath: string? = nil

	-- ── the line index, in the one arithmetic ───────────────────────────────
	local function lineCountOf(itemCount: number, lanes: number): number
		return if itemCount <= 0 then 0 else math.ceil(itemCount / lanes)
	end

	-- the per-line extents, walked once per data/lane change. ARITHMETIC, NOT
	-- MEASUREMENT: no cell is built and nothing is measured, which is the line that
	-- keeps "measure every item at mount" refused and this accepted.
	local function extentsFor(use: any): { number }
		local items = use(spec.items) :: { any }
		local lines = lineCountOf(#items, lanesIn(use))
		local out = table.create(math.max(lines, 1))
		for line = 1, lines do
			local px = (extentSpec :: any)(line, use)
			if type(px) ~= "number" or px ~= px or px <= 0 then
				error(
					`newVirtualGrid '{id}': spec.itemExtent(line {line}) returned {tostring(px)} — a per-line `
						.. "extent must be a positive number of px (the size of ONE LINE OF CELLS along the "
						.. "scroll axis).",
					0
				)
			end
			out[line] = px
		end
		return out
	end

	--[[ THE IDENTITY CACHE. `core:memo`'s equality is observer-facing only — a
		stale mark invalidates the subtree unconditionally — so handing back the SAME
		index object when the inputs did not move has to happen in the body. It is
		what makes `observe(layoutIndex)` mean "the offsets actually changed" and
		therefore what keeps the anchor from firing on every unrelated edit. ]]
	local function sameInputs(a: any, b: any): boolean
		if a == nil or b == nil or a.gap ~= b.gap then
			return false
		end
		if not extentIsPerLine then
			return a.count == b.count and a.extent == b.extent
		end
		local x, y = a.extents, b.extents
		if #x ~= #y then
			return false
		end
		for i = 1, #x do
			if x[i] ~= y[i] then
				return false
			end
		end
		return true
	end

	local cachedInputs: any = nil
	local cachedIndex: any = nil
	local layoutIndex = scope:own(core:memo(function(use)
		local inputs: any = if extentIsPerLine
			then { extents = extentsFor(use), gap = rowGapIn(use) }
			else {
				count = lineCountOf(#(use(spec.items) :: { any }), lanesIn(use)),
				extent = extentIn(use),
				gap = rowGapIn(use),
			}
		if cachedIndex ~= nil and sameInputs(cachedInputs, inputs) then
			return cachedIndex
		end
		cachedInputs = inputs
		cachedIndex = if extentIsPerLine
			then virtual_extents.variable(inputs.extents, inputs.gap)
			else virtual_extents.uniform(inputs.count, inputs.extent, inputs.gap)
		return cachedIndex
	end))
	local function layoutNow(): any
		return layoutIndex:get() :: any
	end

	-- a per-line extent function that is always wrong must fail out of `build()`.
	-- Inside a memo the throw is quarantined and resurfaces three frames away as
	-- something unrelated, which is how a clear authoring error becomes a hunt.
	if extentIsPerLine then
		extentsFor(function(readable: any): any
			return readable:get()
		end)
	end

	local indexByKey = scope:own(core:memo(function(use)
		local map: { [string]: number } = {}
		for i, item in use(spec.items) :: { any } do
			map[spec.key(item)] = i
		end
		return map
	end))

	local scrollTop = scope:own(core:signal(0))

	local canvasDim = scope:own(core:memo(function(use)
		return { type = "fixed", px = use(layoutIndex).content }
	end))

	local clampedTop = scope:own(core:memo(function(use)
		local maxTopPx = math.max(0, use(layoutIndex).content - viewportIn(use))
		local raw = use(scrollTop)
		if type(raw) ~= "number" or raw ~= raw then
			return 0
		end
		return math.clamp(raw, 0, maxTopPx)
	end))

	local function maxTop(): number
		return math.max(0, layoutNow().content - viewportNow())
	end

	--[[ ── THE WINDOW: LINES FROM THE INDEX, CELLS BY DIVISION ─────────────────
		TWO memos over ONE computation, and the split is load-bearing rather than
		tidy. `windowItems` is handed to a `UI.ForEach`, which iterates the table it
		is given — so it must be a PURE ARRAY. Stashing the line range on the same
		table as two named fields makes the ForEach walk them as if they were items
		and index a number, which is exactly what happened when this was one memo. ]]
	local function sameRange(a: any, b: any): boolean
		return type(a) == "table" and type(b) == "table" and a.first == b.first and a.last == b.last
	end

	local windowRange = scope:own(core:memo(function(use)
		local first, last = use(layoutIndex).window(use(clampedTop), viewportIn(use), overscan)
		return { first = first, last = last }
	end, sameRange))

	local function sameWindow(a: { any }, b: { any }): boolean
		if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
			return false
		end
		for i, entry in a do
			if entry.key ~= b[i].key then
				return false
			end
		end
		return true
	end

	local windowItems = scope:own(core:memo(function(use)
		local items = use(spec.items) :: { any }
		local lanes = lanesIn(use)
		local range = use(windowRange) :: any
		local window: { any } = {}
		for line = range.first, range.last do
			for lane = 1, lanes do
				local index = (line - 1) * lanes + lane
				local item = items[index]
				if item == nil then
					break -- the last line is short; the flow grid left-aligns what is there
				end
				table.insert(window, { key = spec.key(item), item = item, index = index, lane = lane, line = line })
			end
		end
		return window
	end, sameWindow))

	-- the band's own canvas offset: the leading edge of its FIRST line
	local bandOffset = scope:own(core:memo(function(use)
		return use(layoutIndex).offsetOf((use(windowRange) :: any).first)
	end))

	local lanesDim = scope:own(core:memo(function(use)
		return lanesIn(use)
	end))

	-- ── keep-visible and reveal ─────────────────────────────────────────────
	-- the SPAN is the line's own box, never its slot: demanding the trailing
	-- gutter would scroll a line that is already fully readable.
	local function keepVisibleTarget(line: number): number?
		local ix = layoutNow()
		return solverLib.keepVisibleOffset(ix.offsetOf(line), ix.extentOf(line), clampedTop:get(), viewportNow(), ix.content)
	end

	local function lineOf(index: number): number
		return math.floor((index - 1) / lanesNow()) + 1
	end

	local function pathOf(key: string): string?
		local root = boundScrollPath or mountedScrollPath
		if root == nil then
			return nil
		end
		for _, entry in windowItems:get() :: { any } do
			if entry.key == key then
				return `{root}/Canvas/Band/W/[{key}]/Cell`
			end
		end
		return nil
	end

	local function scrollTo(controller: any, offset: number)
		local ctrl = controller or boundController
		local path = boundScrollPath or mountedScrollPath
		if ctrl ~= nil and path ~= nil then
			ctrl.scrollTo(path, { x = 0, y = math.clamp(offset, 0, maxTop()) })
		end
	end

	--[[ REACH AN ITEM THAT HAS NO PATH AT ALL. Its cell is not mounted, so there is
		nothing to focus or scroll to in the tree; the control computes the canvas
		offset from the index instead, issues the framework's one programmatic scroll
		write, and the window materializes the cell on the way through. ]]
	local function revealItem(key: string): string?
		local index = (indexByKey:get() :: { [string]: number })[key]
		if index == nil then
			return nil
		end
		local target = keepVisibleTarget(lineOf(index))
		if target ~= nil then
			scrollTo(nil, target)
		end
		return pathOf(key)
	end

	--[[ ── THE ANCHOR (see the header) ─────────────────────────────────────────
		Captured on every offset the ENGINE reports — the only moments the player
		chooses where they are — and re-applied whenever the offset table changes,
		by finding the anchored ITEM's new line. Keyed on the item so it survives a
		reflow, which a line-keyed anchor cannot. ]]
	local anchorKey: string? = nil
	local anchorDelta = 0
	scope:own(core:observe(scrollTop, function()
		local items = spec.items:get() :: { any }
		if #items == 0 then
			anchorKey = nil
			return
		end
		local ix = layoutNow()
		local top = math.clamp(clampedTop:get(), 0, maxTop())
		-- a zero-extent viewport asks the index exactly one question: which line is
		-- the leading edge in
		local line = math.clamp((ix.window(top, 0, 0)), 1, math.max(1, ix.count))
		local firstIndex = math.min((line - 1) * lanesNow() + 1, #items)
		anchorKey = spec.key(items[firstIndex])
		anchorDelta = top - ix.offsetOf(line)
	end))
	scope:own(core:observe(layoutIndex, function(ix: any)
		local key = anchorKey
		if key == nil or boundController == nil then
			return
		end
		local host = boundScrollPath or mountedScrollPath
		if host == nil then
			return
		end
		local index = (indexByKey:get() :: { [string]: number })[key]
		if index == nil then
			-- the anchored item is gone; inventing a neighbour would be a jump with
			-- extra steps
			return
		end
		local target = math.clamp(ix.offsetOf(lineOf(index)) + anchorDelta, 0, math.max(0, ix.content - viewportNow()))
		-- sub-pixel drift is not a jump, and correcting it would fight the engine's
		-- own rounding forever
		if math.abs(target - clampedTop:get()) < 0.5 then
			return
		end
		boundController.scrollTo(host, { x = 0, y = target })
	end))

	-- ── the blueprint ───────────────────────────────────────────────────────
	local function fill(): any
		return { type = "fill", weight = 1 }
	end

	local band = UI.Grid({
		id = "Band",
		--[[ ARRANGE-ONLY PLACEMENT. `anchor` + `offsetY` inside the Canchor let the
			band slide to a new line without being re-measured, which is the property
			windowing depends on: the ENGINE translates the canvas via CanvasPosition,
			so a same-window scroll costs the framework nothing. ]]
		anchor = "topLeft",
		offsetY = bandOffset,
		columns = lanesDim,
		gap = gapSpec,
		rowGap = rowGapSpec,
		width = fill(),
		children = {
			UI.ForEach({
				id = "W",
				items = windowItems,
				key = function(entry: any)
					return entry.key
				end,
				row = function(entry: any, itemScope: any)
					--[[ THE LINE IS RE-DERIVED, NEVER CLOSED OVER. `entry.line` was true
						when the window was computed; a lane-count change moves this very
						item to a different line while its key — and therefore its mounted
						subtree — survives. Reading the line back out of `indexByKey` and
						the live lane count is what keeps the cell's extent honest across a
						reflow. ]]
					local cellLine = itemScope:own(core:memo(function(use)
						local index = (use(indexByKey) :: { [string]: number })[entry.key]
						if index == nil then
							return 1 -- the cell is leaving; the unmount is in flight
						end
						return math.floor((index - 1) / lanesIn(use)) + 1
					end))
					local cellExtent = itemScope:own(core:memo(function(use)
						return use(layoutIndex).extentOf(use(cellLine))
					end))
					--[[ A FULL-CELL FOCUSABLE HIT SITS BEHIND THE CELL'S CONTENT
						(ZStack, z = tree order), which is `newVirtualList`'s row shape
						and is here for a harder reason than symmetry: a contribution
						OWNS ITS SUBTREE'S FOCUS. `focus_map.autoGroups` emits this
						control's groups and does not descend into it, so a focusable
						this control never NAMES is unreachable by Tab and by the D-pad
						alike. A grid that contributed no group would be a focus black
						hole with cells in it.

						There is no pointer or pan handler on it: the engine
						ScrollingFrame owns scrolling, and interactive cell content
						renders above and still captures its own taps. ]]
					local hit = UI.Button({
						id = "Hit",
						label = "",
						focusable = true,
						width = fill(),
						height = fill(),
					})
					return UI.ZStack({
						id = "Cell",
						width = fill(),
						height = itemScope:own(core:memo(function(use)
							return { type = "fixed", px = use(cellExtent) }
						end)),
						-- what this cell was PROMISED to be: the solver compares its
						-- content's own measure against the declaration and names both
						-- numbers when the promise is not kept
						virtualSlot = itemScope:own(core:memo(function(use)
							return {
								list = id,
								axis = "y",
								extent = use(cellExtent),
								contentFrom = SLOT_CONTENT_FROM,
							}
						end)),
						children = {
							hit,
							spec.cell(entry.item, {
								scope = itemScope,
								index = entry.index,
								line = entry.line,
								lane = entry.lane,
							}),
						},
					})
				end,
			}),
		},
	})

	local viewportDim: any = if viewportIsLive
		then scope:own(core:memo(function(use)
			return { type = "fixed", px = viewportIn(use) }
		end))
		else { type = "fixed", px = viewportSpec }

	local blueprint = UI.ScrollView({
		id = id,
		axis = "y",
		width = spec.width or fill(),
		height = viewportDim,
		-- the ScrollView must contribute no layout of its own: the band's offsets
		-- are absolute canvas offsets and assume the Canvas origin IS the content
		-- origin
		padding = 0,
		gap = 0,
		clipChildren = true,
		children = {
			UI.Anchor({
				id = "Canvas",
				-- the FULL virtual extent, a live fixed Dim: this single child is what
				-- the solver sums into contentSize, which the renderer maps to
				-- CanvasSize. With the mounted band as a direct ScrollView child the
				-- engine would get a BAND-sized canvas and the scroll range would be
				-- the window rather than the collection.
				width = fill(),
				height = canvasDim,
				children = { band },
			}),
		},
	})

	--[[ ── THE FOUR-INPUT STORY ────────────────────────────────────────────────
		pointer/touch: the engine ScrollingFrame owns scroll (wheel, pan, momentum,
		elastic); the mirror slides the window and a scroll never activates a cell.
		keyboard/gamepad: the windowed cell hits are ONE focus group and the ring
		walks them; Activate fires `onActivate`.

		THE GROUP'S AXIS IS `horizontal`, AND UP/DOWN IS AN INTERCEPT. The group's
		order is the band's own document order, which is ROW-MAJOR — so ±1 in that
		order is the cell to the left or right, and Left/Right read correctly
		straight off the axis. Down is NOT ±1: it is ±`lanes`, and emitting the
		group as `vertical` would have made Down walk visually RIGHTWARD, which is
		the exact defect `focus_map`'s layout-aware runs exist to prevent. The focus
		graph has no two-dimensional group axis (`focus_graph.luau`: an axis is
		"vertical" or "horizontal"), so the second axis arrives through the
		`navigateIntercept` seam that already exists, rather than by widening the
		focus graph from inside a control. ]]
	local hitPattern = patternEscape(id) .. "/Canvas/Band/W/%[(.-)%]/Cell/Hit$"
	local focusGroupName = `VirtualGridCells-{id}`
	local focusGraph: any = nil

	local function keyOfHit(path: string): string?
		return string.match(path, hitPattern)
	end

	local function hitPathOf(key: string): string?
		local cell = pathOf(key)
		return if cell ~= nil then `{cell}/Hit` else nil
	end

	local function itemForKey(key: string): any
		local index = (indexByKey:get() :: { [string]: number })[key]
		return if index == nil then nil else (spec.items:get() :: { any })[index]
	end

	--[[ THERE IS NO `focusMoved` HERE, AND THAT IS A MEASURED DECISION.
		`newVirtualList` contributes one to scroll the focused row into view, so this
		control was written with the same seam — and mutation testing found it DEAD:
		withholding it changed the scroll behaviour on no path at all, because the
		presenter's own keep-visible already reacts to a focus move it observes.

		THE INTERCEPT'S KEEP-VISIBLE IS NOT DEAD, and the difference is the whole
		mechanism. `navigateIntercept` moves focus PROGRAMMATICALLY, and it has to
		scroll BEFORE it lands the ring — the presenter never sees a move it did not
		route, so nothing else brings the ±lanes target into view. Removing that one
		reddens `VirtualGrid keyboard: focus past the window edge scrolls the line
		into view`; removing this one reddened nothing, which is why it is gone
		rather than kept "for symmetry". ]]
	local function handleActivate(path: string, meta: any?): boolean
		local key = keyOfHit(path)
		if key == nil then
			return false
		end
		local item = itemForKey(key)
		if item == nil then
			return false
		end
		if spec.onActivate ~= nil then
			(spec.onActivate :: any)(item, meta)
		end
		return true
	end

	-- THE SECOND AXIS. Up/Down move by a whole LINE — ±`lanes` in the data — which
	-- is the move the group's own axis cannot express. The target is inside the
	-- window whenever it is within `overscan` lines, and one line always is, so the
	-- cell it aims at is already mounted; when it is not (overscan = 0 at the very
	-- edge) the intercept declines rather than focusing a node that does not exist.
	local function navigateIntercept(direction: string): boolean
		if direction ~= "up" and direction ~= "down" then
			return false
		end
		if focusGraph == nil then
			return false
		end
		--[[ THE FOCUSED PATH IS THE ONLY THING ASKED, and deliberately so. The first
			draft also required a path this control had SEEN move (`focusMoved`), which
			read as a safety check and was a bug: the presenter's AUTO-FOCUS lands on
			the first cell without ever moving, so the very first Down a player pressed
			was silently declined. Matching the focused path against this grid's own hit
			pattern already proves the press is ours; a second piece of remembered state
			could only ever disagree with it. ]]
		local focused = focusGraph.focused:get()
		if type(focused) ~= "string" then
			return false
		end
		local key = keyOfHit(focused)
		if key == nil then
			return false -- the ring is somewhere else entirely; not our press
		end
		local items = spec.items:get() :: { any }
		local index = (indexByKey:get() :: { [string]: number })[key]
		if index == nil then
			return false
		end
		local target = index + (if direction == "down" then lanesNow() else -lanesNow())
		if target < 1 or target > #items then
			return false -- the edge of the collection: let the group's own rules answer
		end
		local targetKey = spec.key(items[target])
		-- scroll first, so a target in the overscan band is brought into view before
		-- the ring lands on it rather than after
		local scrollTarget = keepVisibleTarget(lineOf(target))
		if scrollTarget ~= nil then
			scrollTo(nil, scrollTarget)
		end
		local hit = hitPathOf(targetKey)
		if hit == nil then
			return false
		end
		focusGraph.focusOn(hit)
		return true
	end

	--[[ FOCUS GROUPS: the mounted window's cell hits as ONE group, in tree
		(document, row-major) order, re-derived on every refresh. ALSO the one place
		this control learns its own mounted path — the presenter calls this on every
		present and refresh, and it is the only seam that hands a control that path,
		which `bindNativeScroll`, `scrollTo` and the anchor all need. ]]
	local function buildFocusGroups(rootNode: any): { any }
		mountedScrollPath = rootNode.path
		local order: { string } = {}
		local function walk(node: any)
			if node.path ~= nil and string.match(node.path, hitPattern) ~= nil then
				table.insert(order, node.path)
				return -- the cell hit is a leaf for focus purposes
			end
			for _, child in node.children or {} do
				walk(child)
			end
		end
		walk(rootNode)
		if #order == 0 then
			return {}
		end
		return {
			{
				name = focusGroupName,
				axis = "horizontal",
				wrap = false,
				order = order,
			},
		}
	end

	local bundle: any = {
		focusGroups = buildFocusGroups,
		handleActivate = handleActivate,
		navigateIntercept = navigateIntercept,
		bindFocusGraph = function(graph: any)
			focusGraph = graph
		end,
	}
	blueprint = contribution.attach(blueprint, bundle)

	local function bindNativeScroll(controller: any, scrollPath: string?): () -> ()
		local path = scrollPath or mountedScrollPath
		assert(
			path ~= nil,
			"VirtualGrid.bindNativeScroll: scroll path unknown — present the control (so its mounted path is "
				.. "captured) or pass it explicitly"
		)
		local unsub = controller.observeScroll(path, function(pos: { x: number, y: number })
			scrollTop:set(pos.y)
		end)
		boundController = controller
		boundScrollPath = path
		return function()
			unsub()
			if boundController == controller then
				boundController = nil
				boundScrollPath = nil
			end
		end
	end

	local grid = {}
	grid.blueprint = blueprint
	grid.scrollTop = scrollTop
	grid.bindNativeScroll = bindNativeScroll
	grid.scrollTo = scrollTo
	grid.pathOf = pathOf
	grid.revealItem = revealItem
	grid.focusGroupName = focusGroupName

	-- reach a cell BY KEY: scroll it into view, then hand back the hit path the
	-- focus graph can aim at (nil while the control is unmounted or the key is gone)
	function grid.focusKey(key: string): string?
		local index = (indexByKey:get() :: { [string]: number })[key]
		if index == nil then
			return nil
		end
		local target = keepVisibleTarget(lineOf(index))
		if target ~= nil then
			scrollTo(nil, target)
		end
		return hitPathOf(key)
	end

	function grid.scrollPath(): string?
		return mountedScrollPath
	end

	function grid.debugWindow(): { [string]: boolean }
		local out: { [string]: boolean } = {}
		for _, entry in windowItems:get() :: { any } do
			out[entry.key] = true
		end
		return out
	end

	function grid.dump(): any
		local keys = {}
		for _, entry in windowItems:get() :: { any } do
			table.insert(keys, entry.key)
		end
		local range = windowRange:get() :: any
		local ix = layoutNow()
		return {
			id = id,
			lanes = lanesNow(),
			itemCount = #(spec.items:get() :: { any }),
			lineCount = ix.count,
			content = ix.content,
			rowGap = rowGapNow(),
			gap = gapSpec,
			overscan = overscan,
			scrollTop = clampedTop:get(),
			lines = { range.first, range.last },
			window = keys,
			itemExtentMode = if extentIsPerLine then "variable" else "uniform",
			bandOffset = bandOffset:get(),
			anchorKey = anchorKey,
		}
	end

	function grid.dispose()
		scope:dispose()
	end

	return grid
end

return virtual_grid
