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
	  axis? ("y" default = LazyVGrid | "x" = LazyHGrid; construction-only),
	  columns (integer >= 1, or Readable<integer> — the CROSS-axis lane count),
	  itemExtent (px number | Readable<number> | (line, use) -> px — ONE LINE OF
	    CELLS' size along the scroll axis, NOT one cell's),
	  viewportExtent (px number or Readable<number>),
	  gap? (px between cells ACROSS a line, default 0),
	  rowGap? (px between LINES, default 0),
	  overscan? (LINES either side, default 2),
	  cell (item, ctx: { scope, index, line, lane }) -> Blueprint,
	  onActivate? ((item, meta) -> ()),
	  width? (the cross-axis Dim — `axis = "y"` ONLY; on `axis = "x"` the width IS
	    the scroll axis and the cross axis is the height, which fills), env? }

	── THE FOUR-INPUT STORY, AND THE ONE THING THAT FORCED IT ───────────────────

	pointer/touch: the engine ScrollingFrame owns the scroll (wheel, pan, momentum,
	elastic); the mirror slides the window and a scroll never activates a cell.
	A tap on a cell activates through the auto-composed `handleActivate`.

	keyboard/gamepad: the windowed cell hits are ONE contributed focus group that
	declares BOTH of the things a grid's ring needs — its LANE AXIS and its LANE
	COUNT. The band's own document order walks a line's lanes before it moves to
	the next line, so ±1 is always a step ACROSS a line: on `axis = "y"` the group
	is `horizontal` (row-major: the cell left or right), on `axis = "x"` it is
	`vertical` (column-major: the cell above or below). **THE PERPENDICULAR STEP IS
	NOT ±1, IT IS ±lanes** — a whole line — and since ADR-0030 the focus graph
	expresses that directly: `NavigationGroup.columns` tells it the order is LINES
	of `lanes` LANES, and `focus_graph.navigateDirection` answers the perpendicular
	direction itself. Emitting the other axis instead would have been REACHABLE and
	wrong in SHAPE — the perpendicular key walking one cell instead of one line —
	which is precisely the difference between the reachability axis and the
	paradigm axis.

	This control used to catch that key with a `navigateIntercept` and do the
	±lanes arithmetic itself. It no longer contributes one at all; the block above
	`bundle` records what went with it and why nothing replaced it.

	A cell whose focus target leaves the window is handled the way `newVirtualList`
	handles it, and the reason is worth keeping: the ring never has to focus an
	unmounted node, because a step into the OVERSCAN band scrolls the window, which
	materializes the next line for the step after it. The control contributes NO
	`focusMoved` for this — see the block above `handleActivate`.

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

	── TWO AXES: `LazyVGrid` AND `LazyHGrid`, ON THE SAME ARITHMETIC ────────────

	`axis = "y"` (default) is SwiftUI's `LazyVGrid` — lanes across the width, lines
	advancing down. `axis = "x"` is `LazyHGrid` — lanes down the height, lines
	advancing rightward.

	THIS USED TO BE A REFUSAL, AND WHAT LIFTED IT WAS NOT IN THIS FILE. The refusal
	said: a grid's line holds `columns` cells and `UI.Grid` wraps ROW-MAJOR ONLY, so
	a horizontal grid had no lane mechanism to inherit, and hand-rolling one here
	would be the second lane arithmetic reuse 2 below exists to avoid. `UI.Grid`
	now has `flow = "column"` — a MODE of its one flow arithmetic, proven as an
	exact transpose (`tests/grid_column_flow.spec.luau`) — so the horizontal band is
	a real `UI.Grid` on exactly the same terms the vertical one is, and the control
	gained an axis without gaining any arithmetic at all.

	THE INDEX NEEDED NOTHING. `virtual_extents` is a prefix sum over numbers; the
	word "item" appears nowhere in its interface and neither does "row". It served
	the vertical grid by making one entry mean one LINE, and it serves this one the
	same way, with the extents now measured along x.

	Everything above and below is written in the vocabulary of the default vertical
	axis — "line extent", "the viewport" — and on `axis = "x"` each of those words
	turns a quarter turn. The axis-neutral names are `itemExtent` and
	`viewportExtent`; `scrollTop` keeps its name and mirrors CanvasPosition.X.

	    axis = "y" (default)              axis = "x"
	    lanes across the WIDTH            lanes down the HEIGHT
	    `width` is the cross dim          `width` is REFUSED (it is the scroll axis;
	                                      the cross axis is the height and it fills)
	    band = UI.Grid (row-major)        band = UI.Grid { flow = "column" }
	    focus group axis "horizontal"     focus group axis "vertical"
	    graph answers Up/Down = ±lanes    graph answers Left/Right = ±lanes

	THE LAST TWO ROWS ARE THE PART THAT IS NOT A MECHANICAL TRANSPOSE, and it is
	worth stating rather than deriving twice. A grid's ring is two-dimensional, and
	the group says so: it declares its LANE AXIS and its LANE COUNT, and the graph
	derives the perpendicular from the pair (ADR-0030). Which axis is which follows
	one rule: THE GROUP'S AXIS IS THE LANE AXIS, ALWAYS PERPENDICULAR TO THE SCROLL
	— because document order walks a line's lanes before it moves to the next line.
	So a vertical grid declares `horizontal` and a horizontal grid declares
	`vertical`. `newVirtualList` transposes the OTHER way (`vertical` on y,
	`horizontal` on x), because a list's line holds one item and its document order
	IS its scroll axis; copying the list's answer here would be REACHABLE and wrong
	in SHAPE, with Right stepping one cell down instead of a whole line. A list
	declares no `columns` at all, which is what keeps the two transposes from ever
	being the same statement.

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
	if spec ~= nil and spec.axis ~= nil and spec.axis ~= "y" and spec.axis ~= "x" then
		error(
			`newVirtualGrid: axis = '{tostring(spec.axis)}' is not an axis. It is "y" (SwiftUI's LazyVGrid — lanes `
				.. 'across the width, lines advancing down; the default) or "x" (LazyHGrid — lanes down the height, '
				.. "lines advancing rightward). It is CONSTRUCTION-ONLY, exactly as `ScrollView.axis` is: a reactive "
				.. "scroll axis would rebuild the engine's native scroll state mid-gesture.",
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
	local axis: string = spec.axis or "y"
	local isX = axis == "x"
	--[[ `width` IS THE CROSS AXIS, AND ONLY A VERTICAL GRID HAS ONE THERE. On
		`axis = "x"` the width IS the scroll axis — `viewportExtent` declares it — so
		accepting both would be two answers to one dim, and letting either win
		silently is the class this file refuses aliases for. The cross axis of a
		horizontal grid is its HEIGHT and it fills: wrap the strip in a box of the
		height you want. (`newVirtualList` refuses the identical pair for the
		identical reason.) ]]
	if isX then
		assert(
			spec.width == nil,
			'newVirtualGrid.width is an axis="y" field (there, width is the CROSS axis the lanes divide). On '
				.. 'axis="x" the width IS the scroll axis — declare it as viewportExtent. The cross axis of a '
				.. "horizontal grid is its height, which fills its container; wrap the grid to fix it."
		)
	end

	--[[ ── THE AXIS SEAM ───────────────────────────────────────────────────────
		Everything above this line is one-dimensional arithmetic that does not care
		which way the grid runs — offsets, line indices, lane division. These four
		helpers are the ONLY place the axis turns into a coordinate or a dim name,
		and every write below goes through one of them, so "which way does this grid
		scroll" is answered once rather than per call site. Same seam, same four
		shapes, as `newVirtualList`'s. ]]
	-- A FRESH `fill` DIM PER NODE, never one shared table: a dim is a VALUE, and one
	-- shared constant on the canvas, the band and every cell at once is a trap the
	-- first time anything treats a dim as its own.
	local function fill(): any
		return { type = "fill", weight = 1 }
	end
	-- the main-axis component of an engine point
	local function mainOf(point: any): any
		return if isX then point.x else point.y
	end
	-- ...and an {x,y} carrying `value` on the main axis: what `controller.scrollTo`
	-- takes
	local function vec(value: number): { x: number, y: number }
		return if isX then { x = value, y = 0 } else { x = 0, y = value }
	end
	-- given the dim that belongs on the SCROLL axis and the dim that belongs ACROSS
	-- it, which is the `width` and which the `height`
	local function widthOf(main: any, cross: any): any
		return if isX then main else cross
	end
	local function heightOf(main: any, cross: any): any
		return if isX then cross else main
	end

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
		return solverLib.keepVisibleOffset(
			ix.offsetOf(line),
			ix.extentOf(line),
			clampedTop:get(),
			viewportNow(),
			ix.content
		)
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
			ctrl.scrollTo(path, vec(math.clamp(offset, 0, maxTop())))
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
		boundController.scrollTo(host, vec(target))
	end))

	-- ── the blueprint ───────────────────────────────────────────────────────
	local band = UI.Grid({
		id = "Band",
		--[[ ARRANGE-ONLY PLACEMENT. `anchor` + the main-axis offset inside the Canvas
			let the band slide to a new line without being re-measured, which is the
			property windowing depends on: the ENGINE translates the canvas via
			CanvasPosition, so a same-window scroll costs the framework nothing. ]]
		anchor = "topLeft",
		offsetX = if isX then bandOffset else nil,
		offsetY = if isX then nil else bandOffset,
		--[[ AND THIS ONE LINE IS THE WHOLE OF THE HORIZONTAL GRID'S LAYOUT. Under
			`flow = "column"` the flow grid divides its lanes down the HEIGHT and
			advances its lines rightward, which is exactly what a `LazyHGrid` band is
			— so the lane extent is `floor((innerH - gap * (lanes - 1)) / lanes)`
			because that formula is EXECUTING, not because a copy of it agrees today.
			`columns` is the lane count in both directions and needs no translation.
			The band FILLS the cross axis and takes its main extent from its lines. ]]
		flow = if isX then "column" else nil,
		columns = lanesDim,
		gap = gapSpec,
		rowGap = rowGapSpec,
		width = widthOf(nil, fill()),
		height = heightOf(nil, fill()),
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
					local extentDim = itemScope:own(core:memo(function(use)
						return { type = "fixed", px = use(cellExtent) }
					end))
					return UI.ZStack({
						id = "Cell",
						-- the cell is its LINE's extent along the scroll axis and fills
						-- its lane across it — which lane, and how wide, is the band
						-- grid's business
						width = widthOf(extentDim, fill()),
						height = heightOf(extentDim, fill()),
						-- what this cell was PROMISED to be: the solver compares its
						-- content's own measure against the declaration and names both
						-- numbers when the promise is not kept
						virtualSlot = itemScope:own(core:memo(function(use)
							return {
								list = id,
								axis = axis,
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
		axis = axis,
		width = widthOf(viewportDim, spec.width or fill()),
		height = heightOf(viewportDim, fill()),
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
				width = widthOf(canvasDim, fill()),
				height = heightOf(canvasDim, fill()),
				children = { band },
			}),
		},
	})

	--[[ ── THE FOUR-INPUT STORY ────────────────────────────────────────────────
		pointer/touch: the engine ScrollingFrame owns scroll (wheel, pan, momentum,
		elastic); the mirror slides the window and a scroll never activates a cell.
		keyboard/gamepad: the windowed cell hits are ONE focus group and the ring
		walks them; Activate fires `onActivate`.

		THE GROUP'S AXIS IS THE LANE AXIS, AND `columns` IS THE PERPENDICULAR. The
		group's order is the band's own document order, which walks a line's lanes
		first — so ±1 in that order is always the neighbouring cell ACROSS the line,
		and the keys along the lane axis read correctly straight off it. The
		perpendicular key is NOT ±1: it is ±`lanes`, and the group says so by
		declaring `columns` (ADR-0030). The graph does the line arithmetic; this
		control does none.

		WHICH AXIS IS WHICH FLIPS WITH THE SCROLL, and it flips the OPPOSITE way from
		`newVirtualList`'s. A vertical grid's lanes run across, so the group is
		`horizontal` and the graph answers Up/Down by a line; a horizontal grid's
		lanes run down, so the group is `vertical` and the line pair is Left/Right. A
		list transposes the other way because its line holds ONE item, which makes its
		document order its scroll axis — and it declares no `columns`, so its ring
		stays one-dimensional. Copying a list's answer here is reachable and wrong in
		shape: every cell stays focusable while the perpendicular key walks one cell
		instead of a whole line. ]]
	local hitPattern = patternEscape(id) .. "/Canvas/Band/W/%[(.-)%]/Cell/Hit$"
	local focusGroupName = `VirtualGridCells-{id}`

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

		THE OTHER HALF OF THAT FINDING HAS SINCE GONE THE SAME WAY. While the
		perpendicular key was a `navigateIntercept`, the intercept had to scroll for
		itself: `focusOn` is a move the presenter never routed, so nothing else
		brought the ±lanes target into view, and neutering the presenter's
		keep-visible reddened only the Left/Right case. Now that the GRAPH makes that
		move, both axes are routed moves and both are kept visible by the one shared
		substrate — which is why deleting the intercept deleted a keep-visible too,
		and added none. ]]
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

	--[[ FOCUS GROUPS: the mounted window's cell hits as ONE group, in tree
		(document) order — row-major on `axis = "y"`, column-major on `axis = "x"`,
		because that is the order the band's own `UI.Grid` mounts them in —
		re-derived on every refresh. ALSO the one place
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
				-- the LANE axis, always perpendicular to the scroll: document order
				-- walks a line's lanes before it moves to the next line
				axis = if isX then "vertical" else "horizontal",
				--[[ ...AND THE LANE COUNT, WHICH IS THE OTHER HALF OF THE SAME SENTENCE
					(ADR-0030). With `columns` declared, the graph reads this order as LINES
					of `lanes` LANES and answers the perpendicular direction itself, by a
					whole line. That is what a `navigateIntercept` used to do here by hand.

					`lanesNow()` is read at DERIVATION time, beside the order it describes,
					which is what keeps the two from disagreeing: a lane-count change relays
					every item onto a different line, so the mounted key sequence changes,
					so the band re-mounts and this function runs again. The rectangle
					invariant holds because the window is a contiguous run of items starting
					on a LINE BOUNDARY — only its last line can be short, and only when it
					is the collection's own last line. ]]
				columns = lanesNow(),
				wrap = false,
				order = order,
			},
		}
	end

	--[[ THERE IS NO `navigateIntercept` HERE ANY MORE, AND ITS DELETION IS THE POINT
		(ADR-0030). Both grids used to declare a 1-D group along the lanes and then
		catch the perpendicular key — Up/Down on `axis = "y"`, Left/Right on
		`axis = "x"` — converting it to ±`lanes` and calling `focusGraph.focusOn`.
		Two intercepts differing only in a direction pair is the shape a general
		mechanism is owed, and `columns` above is that mechanism.

		WHAT WENT WITH IT, AND WHY NOTHING REPLACED IT. The intercept had to scroll
		before it landed the ring, because `focusOn` is a move the presenter never
		routed and therefore never keeps visible. A move the GRAPH makes is routed:
		`navigateDirection` is followed by `handle.focusMoved`, whose first act is the
		shared `controller.scrollToVisible` — the same substrate that has always
		brought a Right-off-the-end-of-a-line into view (`tests/virtual_grid_input`,
		"Right off the END of a line"). So the keep-visible did not move into this
		file, it stopped being this file's problem.

		It also stopped being possible to aim at an unmounted cell. The intercept
		computed its target in the WHOLE collection and then asked whether that cell
		happened to be mounted; the graph can only reach what is in the order, which
		is the mounted window and nothing else. ]]
	local bundle: any = {
		focusGroups = buildFocusGroups,
		handleActivate = handleActivate,
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
			scrollTop:set(mainOf(pos))
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
			axis = axis,
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
