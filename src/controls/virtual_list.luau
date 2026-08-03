--!strict
-- VirtualList (design §10.5; native-substrate §4/§6; UI-RUNTIME-002,
-- UI-FOCUS-001, UI-LIFE-002): fixed-height keyed-row virtualization riding the
-- NATIVE scroll substrate. The control root is a UI.ScrollView (engine
-- ScrollingFrame on the live adapter): the engine owns the live offset (wheel,
-- touch drag, momentum, elastic, scroll bars), and the framework owns ONLY the
-- content geometry and the windowing decision — the exact split the native
-- plan §4/§6 draws (geometry headless, scroll physics at the edge).
--
-- THE UNIFIED COLLECTION (ADR-0022 Decision 5, rows SF-L1/L2/L3). One construct
-- windows, selects, reorders and accepts drops at the same time, because the
-- racer-list shape needs all four AT ONCE and a second list construct would have
-- to re-derive windowing, keyed identity and keep-visible to get there. Reorder
-- and drop both ride the PUBLIC drag contract (`UI.draggable`/`UI.dropTarget`)
-- rather than a private code path, so an internal row move and a card dropped in
-- from another container are literally the same session, the same legality seam
-- and the same terminals.
--
-- CANVAS DESIGN (native §6). A native ScrollingFrame renders one Frame per
-- child, so a naive windowed list — ~15 mounted rows — would give the engine a
-- 15-row canvas, not the full virtual extent. FIX: the ScrollView holds ONE
-- child, a full-height Anchor "Canvas" (height = the content extent, a live
-- memo), and the windowed rows are ABSOLUTELY-positioned anchor children at
-- offsetY = (index-1)*PITCH. The solver sums the scroll axis, so
-- contentSize == the Canvas height == the full virtual height; the renderer
-- maps that to CanvasSize (native-substrate NS-A2). Row offsets are CANVAS
-- offsets, engine-independent (a scroll never re-arranges them — the ENGINE
-- translates via CanvasPosition), so a same-window scroll delta is now ZERO
-- framework writes (was rect-writes-only under the old Anchor+offsetY trick).
--
-- PITCH vs ROW (spec.rowGap). The slot a row occupies is `rowHeight + rowGap`
-- tall; the row's own node stays `rowHeight` tall, so the gutter is DEAD SPACE
-- that belongs to neither neighbour — exactly what a `UIListLayout.Padding`
-- gives, and exactly why the alternative (hand in the pitch AS the row height
-- and inset the cell) is wrong: that inflates the row's HIT into the gutter, so
-- a press between two plates activates one of them. EVERY windowing number is
-- on the pitch (canvas extent, clamp, window membership, keep-visible, the
-- insertion slot, the reorder slide); the row box and the row rect are not. The
-- content extent carries no TRAILING gutter — N rows span
-- N*rowHeight + (N-1)*rowGap. `rowGap = 0` is the default and reproduces the
-- pre-field arithmetic byte for byte.
--
-- scrollTop is a MIRROR of the engine CanvasPosition, never a hand-managed
-- offset. It is written ONLY by (i) the presenter/consumer wiring the engine
-- mirror — call list.bindNativeScroll(controller) after present() to feed
-- (VirtualList publishes the seam FLAT on its returned table; there is no `api`
-- member here — Table is the one that nests it. CTRL-05a)
-- controller.observeScroll(scrollPath) -> scrollTop; and (ii) headless tests
-- (scrollTop:set directly, or fake driveScroll through a bound controller). The
-- windowItems memo derives PURELY from scrollTop (clamped), so windowing stays
-- headlessly provable. There is NO wheel handler and NO touch-pan handler — the
-- retired hand-rolled scroll code (native §4): the engine scrolls, its
-- CanvasPosition flows back through the mirror.
--
-- KEEP-VISIBLE (focusKey / keyboard+gamepad scroll-into-view): the control
-- COMPUTES the target canvas y and issues the framework's one programmatic
-- scroll write, controller.scrollTo(scrollPath, {x,y}) through the bound
-- controller (a no-op when unbound). On the live engine that moves
-- CanvasPosition and echoes back through the mirror; headlessly the fake
-- target's setScrollPosition fires the observer synchronously, so the window
-- materializes the focused row the same way.
--
-- Logical focus is BY ITEM KEY: focusKey(key) scrolls the row into view,
-- materializes it, and returns its mounted path; when the focused item
-- disappears, focus moves to the nearest surviving neighbor, preferring the
-- following item (§9.3). Item state lives in the item scope and dies when a row
-- leaves the window (§10.5); cells own async resources through ctx.scope, so
-- window exit cancels them and late completions are stale (§10.3).
-- FOUR-INPUT STORY (ui_todo §0; ADR-0013), auto-composed by the presenter:
--   * pointer/touch: the engine ScrollingFrame owns wheel/pan/momentum scroll;
--     each row is a focusable Button hit whose tap routes handleActivate -> the
--     spec's item-level onActivate; the scroll host clips partial rows natively.
--     A MOUSE press that travels past the shared promotion token lifts the row
--     (reorder) or the payload (drop); a TOUCH press on the row body DECLINES
--     the capture so the native pan keeps working, which is why touch reaches
--     reorder through the non-pointer grab verbs instead (Table precedent).
--   * keyboard: a contributed focusGroups exposes the WINDOWED row hits as one
--     vertical group (re-derived per refresh window slide); Up/Down steps rows;
--     focus moving to an off-band row scrolls it into view via the keep-visible
--     scrollTo; Return activates the focused row.
--   * gamepad: D-pad is identical to arrows and ButtonA activates. When the list
--     is reorderable it contributes a navigateIntercept: while a row is ARMED,
--     Navigate moves the predicted drop target instead of focus, Activate
--     commits and Cancel cancels — the same session, the same legality.
-- build(LuauUI, core, spec) -> {
--   blueprint, focusGroupName (the contributed group's name),
--   scrollTop (Signal px, engine mirror), focusedKey (Signal key?),
--   selectedKey (Signal key?), armedKey (Signal key?), dropIndex (Signal number?),
--   autoscroll (Signal { state, band }),
--   pathOf(key) -> path?, focusKey(key) -> path?, select(key), clearSelection(),
--   toggleGrab(key?), stepAutoscroll(now) -> step?,
--   bindNativeScroll(controller, scrollPath?) -> unbind,
--   scrollTo(controller, y), scrollPath() -> path?,
--   debugWindow() -> {key=true}, dump(), dispose()
-- }
-- spec: { id?, rows (Readable {T}), key (T)->string, rowHeight (px number or
--   Readable<number>), rowGap? (px number or Readable<number>, default 0 — the
--   gutter between row SLOTS; the pitch is rowHeight + rowGap and the row's own
--   node stays rowHeight tall), viewportHeight (px number or Readable<number>),
--   overscan? (rows, default 2),
--   cell (item, ctx: {scope}) -> Blueprint, width? (row width Dim),
--   onActivate? ((item, meta) -> ()),
--   selection? ("none" | "single"), onSelect? ((item, key) -> ()),
--   reorderable? (boolean), onReorder? ((key, toIndex) -> ()),
--   reorderMotion? (motion class name | "instant"), motionClock? (a motion clock),
--   grabOnActivate? (boolean), dropSurface? (boolean),
--   rowDropTarget? ((item) -> { accepts?, onDrop }?),
--   rowFocusable? ((item) -> boolean), autoscroll? (boolean | autoscroll opts),
--   navigation? ({ name?, wrap?, containment?, entry?, exit? }) — overrides for
--     the ONE focus group this list contributes; absent = today's group verbatim }

local autoscrollLib = require("../input/autoscroll")
local contribution = require("../input/contribution")
local solverLib = require("../layout/solver")
local specGuard = require("../spec_guard")

-- a node id is interpolated into a Lua PATTERN below, so its magic characters
-- have to be escaped first. Module scope, not per-instance: it is a pure
-- function of its argument and every `build()` used to allocate its own
-- (Step 5.5 cleanup ledger C-06).
local function patternEscape(s: string): string
	return (s:gsub("%W", "%%%0"))
end

local virtual_list = {}

-- the internal reorder payload kind. Namespaced with the list id so two lists on
-- one surface can never accept each other's row moves by accident.
local REORDER_KIND = "__luauui_reorder"

-- CLOSED SPEC (constitution §4; ARCH-1). Exactly the fields this control
-- reads — an unknown one is an authoring mistake, never a silent no-op.
local VIRTUAL_LIST_KEYS = specGuard.keySet({
	"autoscroll",
	"cell",
	"dropSurface",
	"grabOnActivate",
	"id",
	"key",
	"motionClock",
	"navigation",
	"onActivate",
	"onReorder",
	"onSelect",
	"overscan",
	"reorderMotion",
	"reorderable",
	"rowDropTarget",
	"rowFocusable",
	"rowGap",
	"rowHeight",
	"rows",
	"selection",
	"viewportHeight",
	"width",
})

function virtual_list.build(LuauUI: any, core: any, spec: any)
	specGuard.assertKnownKeys("newVirtualList", spec, VIRTUAL_LIST_KEYS, "spec")
	local rowHeightSpec = spec.rowHeight
	-- ROW HEIGHT MAY BE DERIVED, BUT IT IS ONE NUMBER FOR THE WHOLE LIST
	-- (finding F13). A Readable is accepted so a height derived from the theme
	-- metrics snapshot (or the preferred-text offset) re-derives on a swap
	-- without rebuilding the list; what is NOT accepted is a per-row height,
	-- because the windowing arithmetic is index×height and a per-row wrap
	-- difference would silently mis-window at the largest text offset.
	local rowHeightIsLive = type(rowHeightSpec) == "table" and type(rowHeightSpec.get) == "function"
	assert(
		rowHeightIsLive or (type(rowHeightSpec) == "number" and rowHeightSpec > 0),
		"VirtualList.rowHeight must be a positive number or a Readable<number> (fixed-height rows, uniform per list; "
			.. "derive it from the theme metrics snapshot at the call site — variable heights are a §17 Phase 5 gate)"
	)
	--[[ THE GUTTER BETWEEN ROW SLOTS, one number for the whole list for exactly
		the reason the row height is one number: the windowing arithmetic is
		index x pitch. `newTable` has always had this field
		(`controls/table.luau`); VirtualList's absence left consumers one
		workaround — hand in the PITCH as `rowHeight` and inset the cell — which
		is wrong where it counts, because it inflates the row's HIT node into the
		gutter and a press in the dead space between two plates then activates
		one of them. Zero is the default AND a legal explicit answer, so an
		absent gap costs an existing list nothing (every number below collapses
		to its pre-field form at 0). Live for the same reason `rowHeight` is: a
		gutter derived from the theme metrics re-derives on a theme swap without
		rebuilding the list. ]]
	local rowGapSpec: any = if spec.rowGap ~= nil then spec.rowGap else 0
	local rowGapIsLive = type(rowGapSpec) == "table" and type(rowGapSpec.get) == "function"
	assert(
		rowGapIsLive or (type(rowGapSpec) == "number" and rowGapSpec == rowGapSpec and rowGapSpec >= 0),
		"VirtualList.rowGap must be a non-negative number or a Readable<number> (the vertical gutter between row "
			.. "slots, uniform per list; the row itself stays rowHeight tall and the gutter is dead space)"
	)
	-- VIEWPORT HEIGHT MAY BE LIVE for the same reason rowHeight may (P5-F5): a
	-- list filling a container, or re-deriving after an environment change,
	-- hands in a Readable and BOTH consumers of the number — the host's height
	-- dim (reactive, dirty=measure) and the windowing arithmetic — track it, so
	-- the painted box and the window can never disagree.
	local viewportSpec = spec.viewportHeight
	local viewportIsLive = type(viewportSpec) == "table" and type(viewportSpec.get) == "function"
	assert(
		viewportIsLive or (type(viewportSpec) == "number" and viewportSpec > 0),
		"VirtualList.viewportHeight must be a positive number or a Readable<number>"
	)
	assert(type(spec.key) == "function", "VirtualList.key is required")
	assert(type(spec.cell) == "function", "VirtualList.cell is required")
	local UI = LuauUI.UI
	local id = spec.id or "VirtualList"
	local function viewportIn(use: any): number
		return if viewportIsLive then use(viewportSpec) else viewportSpec
	end
	local function viewportNow(): number
		return if viewportIsLive then (viewportSpec :: any):get() else viewportSpec
	end
	local overscan: number = spec.overscan or 2
	local selectionMode: string = spec.selection or "none"
	assert(
		selectionMode == "none" or selectionMode == "single",
		`VirtualList.selection must be "none" or "single" (got '{tostring(spec.selection)}')`
	)
	-- THE ONE FOCUS GROUP THIS LIST CONTRIBUTES, declaratively adjustable (row
	-- SF-L4). A screen that composes this list beside an authored row of controls
	-- has to name the two groups to each other — "left from any row returns to the
	-- hand", "the hand's up/down enters the list" — and a group's `wrap` / `exit`
	-- are exactly the fields the contributed group had no way to carry. Rebuilding
	-- the group consumer-side is not an option: its order entries carry the live
	-- focus-skip predicates AND the active-interaction exemption, so a hand-rolled
	-- copy would silently lose both. Absent, every field resolves to today's
	-- values and the contributed group is byte-identical.
	local navigation: any = spec.navigation or {}
	assert(type(navigation) == "table", "VirtualList.navigation must be a table of navigation-group overrides")
	for key in navigation do
		assert(
			key == "name" or key == "wrap" or key == "containment" or key == "entry" or key == "exit",
			`VirtualList.navigation: unknown field '{tostring(key)}'. Valid: name, wrap, containment, entry, exit.`
		)
	end
	local focusGroupName: string = navigation.name or `vl:{id}`
	local reorderable = spec.reorderable == true
	local isDropSurface = spec.dropSurface == true or spec.rowDropTarget ~= nil
	-- ROWS ARE DRAGGABLE when they can be reordered, and DROP TARGETS when either
	-- an external payload may land on them or a sibling row may be moved onto
	-- them. Both ride the public contract; neither exists on a plain list.
	local rowsAreTargets = reorderable or isDropSurface
	local reorderMotion: string = spec.reorderMotion or "object"
	local motionClock = spec.motionClock
	local grabOnActivate = if spec.grabOnActivate ~= nil
		then spec.grabOnActivate == true
		else (reorderable and spec.onActivate == nil)

	local function rowHeightNow(): number
		return if rowHeightIsLive then (rowHeightSpec :: any):get() else rowHeightSpec
	end
	local function rowHeightIn(use: any): number
		return if rowHeightIsLive then use(rowHeightSpec) else rowHeightSpec
	end
	local function rowGapNow(): number
		return if rowGapIsLive then (rowGapSpec :: any):get() else rowGapSpec
	end
	local function rowGapIn(use: any): number
		return if rowGapIsLive then use(rowGapSpec) else rowGapSpec
	end
	-- THE PITCH: one slot, gutter included. Every windowing number is on this,
	-- and nothing that describes the ROW is (see the header).
	local function pitchNow(): number
		return rowHeightNow() + rowGapNow()
	end
	local function pitchIn(use: any): number
		return rowHeightIn(use) + rowGapIn(use)
	end
	-- ...and the CONTENT EXTENT the canvas spans: N slots with NO trailing
	-- gutter, because the gap is BETWEEN rows exactly as a UIListLayout's padding
	-- is. An empty list spans nothing.
	local function contentIn(use: any, count: number): number
		if count <= 0 then
			return 0
		end
		return count * rowHeightIn(use) + (count - 1) * rowGapIn(use)
	end
	local function contentNow(): number
		local count = #(spec.rows:get() :: { any })
		if count <= 0 then
			return 0
		end
		return count * rowHeightNow() + (count - 1) * rowGapNow()
	end

	-- id -> path-pattern piece: a row hit path looks like
	-- <root>/<id>/Canvas/W/[<key>]/Row/Hit (the Canvas anchor is the full-height
	-- scroll canvas), so escape the id for string.match reuse
	local hitPattern = patternEscape(id) .. "/Canvas/W/%[(.-)%]/Row/Hit$"

	-- THE BOUND RENDER CONTROLLER AND THE MOUNTED SCROLL PATH ARE DECLARED FIRST,
	-- above everything that reads them. `mountedScrollPath` in particular is what
	-- turns a public standalone-rooted path into the SCREEN-rooted one the
	-- renderer's registry and the focus graph key on, and it is read by helpers
	-- defined long before the native-scroll seam that writes it.
	local boundController: any = nil
	local boundScrollPath: string? = nil
	local mountedScrollPath: string? = nil

	-- ===== the drag registry seam (ADR-0022 D5) ==============================
	-- The registry belongs to the SURFACE, not to the list: a card dragged out of
	-- a hand and onto a row is one session crossing two constructs, so the list
	-- borrows the renderer's registry rather than owning one. Everything below
	-- degrades to a no-op when the list is unbound or the controller predates the
	-- registry (a standalone headless mount).
	local function registry(): any
		-- a list with no drag declarations never ASKS for the registry, so a plain
		-- list costs nothing for the feature existing (the renderer builds one
		-- lazily, on first use)
		if not rowsAreTargets or boundController == nil or type(boundController.dragRegistry) ~= "function" then
			return nil
		end
		return boundController.dragRegistry()
	end

	local listScope = core:scope(`virtual-list-{id}`)
	-- scrollTop: the engine CanvasPosition MIRROR (native-substrate NS-A2). Fed
	-- by bindNativeScroll (engine observer) or a test; NEVER a hand-rolled offset.
	local scrollTop = listScope:own(core:signal(0))
	local focusedKey = listScope:own(core:signal(nil))
	local selectedKey = listScope:own(core:signal(nil :: string?))
	local armedKey = listScope:own(core:signal(nil :: string?))
	-- the insertion slot a live reorder would commit to (1-based index in the
	-- resulting order), and the autoscroll affordance state a fixture paints
	local dropIndex = listScope:own(core:signal(nil :: number?))
	local autoscrollState = listScope:own(core:signal({ state = "idle", band = nil :: string? }))

	-- key -> 1-based index in the CURRENT data
	local indexByKey = listScope:own(core:memo(function(use)
		local map: { [string]: number } = {}
		for i, item in use(spec.rows) :: { any } do
			map[spec.key(item)] = i
		end
		return map
	end))

	-- the full virtual extent as a live fixed Dim: the ScrollView's single
	-- Canvas child is this tall, so the solver's scroll-axis sum == the full
	-- virtual height and the renderer pushes it as CanvasSize (native §6). Rows
	-- mount only in the window, but the canvas always spans the whole list.
	local canvasDim = listScope:own(core:memo(function(use)
		local count = #(use(spec.rows) :: { any })
		return { type = "fixed", px = contentIn(use, count) }
	end))

	-- scroll clamped into the content band, so garbage/overshoot mirror values
	-- cannot mount phantom windows
	local clampedTop = listScope:own(core:memo(function(use)
		local count = #(use(spec.rows) :: { any })
		local maxTopPx = math.max(0, contentIn(use, count) - viewportIn(use))
		local raw = use(scrollTop)
		if type(raw) ~= "number" or raw ~= raw then
			return 0
		end
		return math.clamp(raw, 0, maxTopPx)
	end))

	-- the window: visible rows + overscan, keyed. Equality compares the KEY
	-- SEQUENCE, so a same-window scroll delta never fires the ForEach.
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
	local windowItems = listScope:own(core:memo(function(use)
		local items = use(spec.rows) :: { any }
		local top = use(clampedTop)
		-- SLOTS, not rows: a viewport spans `viewport / pitch` whole slots and the
		-- canvas y of slot k is (k-1)*pitch, so both halves read the pitch
		local pitch = pitchIn(use)
		local firstVisible = math.floor(top / pitch) + 1
		local visibleCount = math.ceil(viewportIn(use) / pitch)
		local first = math.max(1, firstVisible - overscan)
		local last = math.min(#items, firstVisible + visibleCount - 1 + overscan)
		local window = {}
		for i = first, last do
			table.insert(window, { key = spec.key(items[i]), item = items[i] })
		end
		return window
	end, sameWindow))

	local function pathOf(key: string): string?
		for _, entry in windowItems:get() :: { any } do
			if entry.key == key then
				return `/{id}/Canvas/W/[{key}]/Row`
			end
		end
		return nil
	end
	-- the MOUNTED row-hit path (screen-prefixed), which is what the renderer's
	-- registry and the focus graph key on. `pathOf` is deliberately
	-- standalone-rooted for the public API, so the two must not be confused: a
	-- standalone path handed to the registry silently matches nothing.
	local function mountedRowPath(key: string): string?
		if pathOf(key) == nil then
			return nil -- not in the mounted window
		end
		local root = mountedScrollPath
		if root == nil then
			return nil
		end
		return `{root}/Canvas/W/[{key}]/Row`
	end
	local function hitPathOf(key: string): string?
		local path = mountedRowPath(key)
		return if path ~= nil then path .. "/Hit" else nil
	end

	-- nearest surviving neighbor, preferring the FOLLOWING item (§9.3): the
	-- item that now occupies the removed item's index is its old follower
	local lastIndexOfFocused: number? = nil
	listScope:own(core:observe(indexByKey, function(map: { [string]: number })
		-- SELECTION PRUNES WITH THE DATA: a removed row must never linger as a
		-- phantom selection, nor pre-select a key that comes back later.
		local selected = selectedKey:get()
		if selected ~= nil and map[selected] == nil then
			selectedKey:set(nil)
		end
		local armed = armedKey:get()
		if armed ~= nil and map[armed] == nil then
			armedKey:set(nil)
		end
		local focused = focusedKey:get()
		if focused == nil then
			return
		end
		if map[focused] ~= nil then
			lastIndexOfFocused = map[focused]
			return
		end
		local items = spec.rows:get() :: { any }
		if #items == 0 then
			focusedKey:set(nil)
			return
		end
		local landing = math.min(lastIndexOfFocused or 1, #items)
		local neighbor = spec.key(items[landing])
		lastIndexOfFocused = landing
		focusedKey:set(neighbor)
	end))

	-- ===== native scroll seam (native-substrate NS-A2) =======================
	-- scrollTop is written only by the engine mirror (bindNativeScroll) or a
	-- test. The control can reach the renderer's controller only AFTER present,
	-- so the consumer/presenter wires it: bindNativeScroll(controller) feeds
	-- observeScroll(scrollPath) -> scrollTop and returns an unbind. The mounted
	-- scroll path (the ScrollView IS the control root) is captured in
	-- buildFocusGroups, which the presenter calls on every refresh.
	local function maxTop(): number
		return math.max(0, contentNow() - viewportNow())
	end

	-- keep-visible target: the canvas y that brings row `index` fully into the
	-- viewport, minimal scroll both directions; nil when it is already in band
	-- keep-visible from the row INDEX, because a row outside the window is not
	-- mounted and therefore has no solved rect the renderer's substrate could read.
	-- The minimum-distance CLAMP is the shared one (A-SV2): only the span's source
	-- differs, never the arithmetic.
	-- The SPAN is the row's own box, not its slot: keep-visible owes the player a
	-- visible ROW, and demanding the trailing gutter too would scroll a row that
	-- is already fully readable.
	local function keepVisibleTarget(index: number): number?
		return solverLib.keepVisibleOffset(
			(index - 1) * pitchNow(),
			rowHeightNow(),
			clampedTop:get(),
			viewportNow(),
			contentNow()
		)
	end

	local function focusKey(key: string): string?
		local index = (indexByKey:get() :: { [string]: number })[key]
		if index == nil then
			return nil
		end
		-- keep-visible: compute the target canvas y and issue the framework's ONE
		-- programmatic scroll write through the bound controller (native §4). On
		-- the engine this moves CanvasPosition and echoes back to scrollTop; the
		-- fake target echoes synchronously, so the window materializes the row.
		-- Unbound: a no-op (a standalone control with no engine to scroll).
		local target = keepVisibleTarget(index)
		if target ~= nil and boundController ~= nil and boundScrollPath ~= nil then
			boundController.scrollTo(boundScrollPath, { x = 0, y = target })
			-- EVERY scroll write moves the drop targets, and a live session must
			-- see that on the same frame — the identical rule edge autoscroll
			-- follows, applied to the keep-visible write. Without it a keyboard or
			-- gamepad drag hit-tests the new pointer position against the rects the
			-- rows had BEFORE the scroll, and lands one row short.
			local reg = registry()
			if reg ~= nil and reg.isActive() then
				reg.refreshTargets()
			end
		end
		lastIndexOfFocused = index
		focusedKey:set(key)
		return pathOf(key)
	end

	-- window-space pointer y -> canvas y. The solver arranges rows in the host's
	-- own space and the engine shifts them by CanvasPosition, so the drop slot is
	-- only correct if the live scroll offset is added back (the same correction
	-- Table's reorder makes).
	-- the host's rect in WINDOW space. A pointer always arrives in window space,
	-- and a list nested inside another scrolled panel solves in ITS host's space,
	-- so anything comparing the two has to ask for the shifted rect.
	local function hostScreenRect(): any
		local ctrl = boundController
		local path = boundScrollPath or mountedScrollPath
		if ctrl == nil or path == nil then
			return nil
		end
		local read = if type(ctrl.screenRectOf) == "function" then ctrl.screenRectOf else ctrl.rectOf
		if type(read) ~= "function" then
			return nil
		end
		return read(path)
	end

	local function canvasYFor(pointerY: number): number?
		local rect = hostScreenRect()
		if type(rect) ~= "table" then
			return nil
		end
		return pointerY - rect.y + clampedTop:get()
	end

	-- the canvas y the insertion LINE is drawn at for a 0-based slot: the middle
	-- of the gutter above it, so the hairline reads as "between these two rows"
	-- rather than as a lid on the lower one. Clamped into the content extent so
	-- the first and last boundaries stay inside the canvas the host clips to. At
	-- rowGap 0 this is `slot * rowHeight`, clamped exactly as before.
	local function slotBoundary(slot: number): number
		local gap = rowGapNow()
		return math.clamp(slot * pitchNow() - gap / 2, 0, contentNow())
	end

	-- the insertion slot for a canvas y: the number of whole SLOTS above it, using
	-- each slot's MIDPOINT so the line snaps to the nearer boundary. Returns the
	-- 0-based insertion slot and its canvas boundary y.
	local function insertSlotAt(canvasY: number): (number, number)
		local pitch = pitchNow()
		local count = #(spec.rows:get() :: { any })
		local slot = math.floor((canvasY + pitch / 2) / pitch)
		slot = math.clamp(slot, 0, count)
		return slot, slotBoundary(slot)
	end

	-- the drop line rides the PRESENTATION channel, not layout: it is mounted
	-- once at canvas y 0 and translated, so a 60 Hz drag costs one presentation
	-- write per move instead of a re-solve per move. Parked far above the canvas
	-- when idle (the scroll host clips it) rather than unmounted, so there is no
	-- structural churn on every pickup.
	local DROP_LINE_PARK = -10000
	local function writeDropLine(y: number?)
		local ctrl = boundController
		local host = boundScrollPath or mountedScrollPath
		if ctrl == nil or host == nil or type(ctrl.setPresentationTransform) ~= "function" then
			return
		end
		ctrl.setPresentationTransform(host .. "/Canvas/DropLine", { x = 0, y = if y ~= nil then y else DROP_LINE_PARK })
	end

	-- ===== reorder ===========================================================
	local function indexOfKey(key: string): number?
		return (indexByKey:get() :: { [string]: number })[key]
	end

	-- move `key` so it occupies 1-based index `to` in the resulting order. A
	-- no-op is SUPPRESSED: a drop that reproduces the current order must not emit
	-- a mutation nobody asked for (the mutation lifecycle applies — a reorder is
	-- a request, and pending never means success).
	local function commitReorderAt(key: string, to: number?)
		if spec.onReorder == nil or to == nil then
			return
		end
		local from = indexOfKey(key)
		if from == nil then
			return
		end
		local count = #(spec.rows:get() :: { any })
		local index = math.clamp(to, 1, math.max(1, count))
		if index == from then
			return
		end
		spec.onReorder(key, index)
	end

	-- POINTER commit: the insertion LINE decides, so the top half of a row means
	-- "before it" and the bottom half means "after it". Removing the dragged row
	-- first shifts every slot below it up by one, which is the whole of the
	-- full-list-slot → resulting-index conversion.
	local function commitReorderFromPointer(key: string, pointerY: number)
		local canvasY = canvasYFor(pointerY)
		if canvasY == nil then
			return
		end
		local slot = (insertSlotAt(canvasY))
		local from = indexOfKey(key)
		if from == nil then
			return
		end
		commitReorderAt(key, slot - (if from <= slot then 1 else 0) + 1)
	end

	-- ===== reorder motion (finding F6) =======================================
	-- Rows SLIDE to their new slots; they never cross-fade. The layout offset
	-- jumps to the new slot immediately (the data is the truth), and the visual
	-- catch-up is a presentation transform springing from the old delta to zero —
	-- so the animation never re-solves and never fights the windowing math. The
	-- spring per row is RETARGETED, never recreated, so a re-sort landing on a
	-- row that is still sliding reverses smoothly.
	local slideValues: { [string]: any } = {}
	local slideUnsubs: { [string]: () -> () } = {}
	local lastIndexByKey: { [string]: number } = {}
	local function disposeSlide(key: string)
		local unsub = slideUnsubs[key]
		if unsub ~= nil then
			unsub()
			slideUnsubs[key] = nil
		end
		local value = slideValues[key]
		if value ~= nil then
			value:dispose()
			slideValues[key] = nil
		end
	end
	local function slideRow(key: string, fromDelta: number)
		if motionClock == nil or reorderMotion == "instant" or fromDelta == 0 then
			return
		end
		local value = slideValues[key]
		if value == nil then
			value = motionClock:spring(fromDelta, reorderMotion)
			slideValues[key] = value
			slideUnsubs[key] = core:observe(value, function()
				local ctrl = boundController
				local path = mountedRowPath(key)
				if ctrl == nil or path == nil or type(ctrl.setPresentationTransform) ~= "function" then
					return
				end
				ctrl.setPresentationTransform(path, { x = 0, y = value:get() })
			end)
		else
			-- keep the value where it is and re-aim: interruptibility is the whole
			-- point of a persistent spring
			value:setVelocity(value:getVelocity())
		end
		value:setTarget(0)
	end
	if reorderable then
		listScope:own(core:observe(indexByKey, function(map: { [string]: number })
			-- the slide is a SLOT delta: rows move by whole pitches, gutter included
			local pitch = pitchNow()
			for key, index in map do
				local previous = lastIndexByKey[key]
				if previous ~= nil and previous ~= index then
					slideRow(key, (previous - index) * pitch)
				end
			end
			for key in lastIndexByKey do
				if map[key] == nil then
					disposeSlide(key)
				end
			end
			lastIndexByKey = table.clone(map)
		end))
	end

	-- ===== drop targets ======================================================
	local function itemForKey(key: string): any?
		local index = indexOfKey(key)
		if index == nil then
			return nil
		end
		return (spec.rows:get() :: { any })[index]
	end

	local function rowTargetOpts(key: string): any
		local item = itemForKey(key)
		if item == nil or spec.rowDropTarget == nil then
			return nil
		end
		return spec.rowDropTarget(item)
	end

	local function rowAccepts(key: string): (payload: any) -> (boolean, string?)
		return function(payload: any): (boolean, string?)
			-- an internal row move is legal on any row of THIS list (every slot is
			-- a legal insertion point); a foreign list's move is not
			if type(payload) == "table" and payload.kind == REORDER_KIND then
				return payload.list == id and spec.onReorder ~= nil, "FOREIGN_LIST"
			end
			local opts = rowTargetOpts(key)
			if opts ~= nil and type(opts.accepts) == "function" then
				return opts.accepts(payload)
			end
			return spec.dropSurface == true, "NOT_A_DROP_SURFACE"
		end
	end

	local function rowOnDrop(key: string): (payload: any, info: any) -> ()
		return function(payload: any, info: any)
			if type(payload) == "table" and payload.kind == REORDER_KIND and payload.list == id then
				-- POINTER: the release point decides the insertion line (a target
				-- id alone cannot say "which half of the row").
				-- ARMED: the target row IS the answer — the lifted row takes its
				-- place, which is what "commit on this row" means with no pointer
				-- to read a half from.
				if info ~= nil and info.mode == "pointer" and info.pointerY ~= nil then
					commitReorderFromPointer(payload.key, info.pointerY)
				else
					commitReorderAt(payload.key, indexOfKey(key))
				end
				return
			end
			local opts = rowTargetOpts(key)
			if opts ~= nil and type(opts.onDrop) == "function" then
				local item = itemForKey(key)
				opts.onDrop(payload, {
					key = key,
					item = item,
					index = indexOfKey(key),
					targetId = info and info.targetId,
					source = info and info.source,
					mode = info and info.mode,
				})
			end
		end
	end

	-- ===== autoscroll (SF-L2) ================================================
	local autoscrollEnabled = if spec.autoscroll ~= nil then spec.autoscroll ~= false else rowsAreTargets
	local autoscrollModel = if autoscrollEnabled
		then autoscrollLib.new(if type(spec.autoscroll) == "table" then spec.autoscroll else nil)
		else nil

	-- Drive this once per frame while the surface is alive (the client's
	-- PreRender shim, alongside `clock:step`). Returns the step, or nil when the
	-- list is not autoscrolling.
	local function stepAutoscroll(now: number): any
		if autoscrollModel == nil then
			return nil
		end
		local reg = registry()
		local host = boundScrollPath or mountedScrollPath
		local ctrl = boundController
		-- NON-POINTER SCHEMES HAVE NO AUTOSCROLL PATH: focus-follows-navigation
		-- already scrolls the host, and a second dwell/band mechanism aimed at a
		-- focus ring would answer the same question twice.
		if reg == nil or ctrl == nil or host == nil or not reg.isActive() or reg.mode() ~= "pointer" then
			autoscrollModel:reset()
			if autoscrollState:get().state ~= "idle" then
				autoscrollState:set({ state = "idle", band = nil })
			end
			return nil
		end
		local hostRect = hostScreenRect()
		local step = autoscrollModel:step({
			now = now,
			pointerPos = reg.pointerPosition(),
			hostRect = hostRect,
			canvasPos = clampedTop:get(),
			maxScroll = maxTop(),
		})
		if step.delta ~= 0 then
			ctrl.scrollTo(host, { x = 0, y = clampedTop:get() + step.delta })
			-- THE FRAME-ACCURATE RE-RESOLVE (SF-L2's correctness core): the rects
			-- the session hit-tests against are the solver's, shifted by the LIVE
			-- scroll offset — so re-running the hover immediately after the write,
			-- in this same frame, is enough. A tick-based re-resolve lags about two
			-- rows at the top speed.
			reg.refreshTargets()
		end
		local current = autoscrollState:get()
		if current.state ~= step.state or current.band ~= autoscrollModel:band() then
			autoscrollState:set({ state = step.state, band = autoscrollModel:band() })
		end
		return step
	end

	-- ===== keyboard/gamepad plumbing (ui_todo §0; mirrors Table's seams) ======
	local function keyOfHit(path: string): string?
		return (string.match(path, hitPattern))
	end

	local function select(key: string)
		if selectionMode == "none" then
			return
		end
		selectedKey:set(key)
		if spec.onSelect ~= nil then
			local item = itemForKey(key)
			if item ~= nil then
				spec.onSelect(item, key)
			end
		end
	end

	-- a promoted pointer drag ends with an engine Activated on the origin row
	-- (whichever side of InputEnded it lands): swallow exactly one, or every
	-- reorder would also read as a tap on the row it started from
	local suppressActivatePath: string? = nil
	local unwatchRegistry: (() -> ())? = nil
	local function watchSession(reg: any)
		if unwatchRegistry ~= nil then
			return
		end
		unwatchRegistry = reg.onUpdate(function(state: any)
			if not state.active then
				armedKey:set(nil)
				dropIndex:set(nil)
				writeDropLine(nil)
				return
			end
			if state.mode == "pointer" and state.source ~= nil then
				suppressActivatePath = state.source
			end
			-- the drop line only means something for a move within THIS list
			local payload = state.payload
			if reorderable and type(payload) == "table" and payload.kind == REORDER_KIND and payload.list == id then
				if state.mode == "armed" then
					-- ARMED: the predicted landing IS the hovered row's slot
					local hoveredKey = if state.hovered ~= nil then keyOfHit(state.hovered) else nil
					local index = if hoveredKey ~= nil then indexOfKey(hoveredKey) else nil
					if index ~= nil then
						dropIndex:set(index)
						writeDropLine(slotBoundary(index - 1))
						return
					end
				elseif state.y ~= nil then
					local canvasY = canvasYFor(state.y)
					if canvasY ~= nil then
						local slot, boundary = insertSlotAt(canvasY)
						local from = indexOfKey(payload.key)
						dropIndex:set(if from ~= nil then slot - (if from <= slot then 1 else 0) + 1 else slot + 1)
						writeDropLine(boundary)
						return
					end
				end
			end
			dropIndex:set(nil)
			writeDropLine(nil)
		end)
	end

	-- ACTIVATE (tap / Return / ButtonA): route the focused (or tapped) row-hit
	-- path to the item-level onActivate; the row also becomes the logical focus.
	local function handleActivate(path: string, meta: any?): boolean
		local key = keyOfHit(path)
		if key == nil then
			return false
		end
		local reg = registry()
		-- ARMED: this Activate is the COMMIT half of arm→navigate→commit, and it
		-- goes through the same session's drop — legal commits, illegal rejects,
		-- exactly as a pointer release would. AIM AT THIS ROW FIRST (director
		-- virtual-controller round): committing at the session's stale aim point
		-- dropped the card wherever the pickup began — the row the player
		-- pressed A on is the drop, always.
		if reg ~= nil and reg.mode() == "armed" then
			local hitPath = hitPathOf(key)
			if hitPath ~= nil then
				reg.armTo(hitPath)
			end
			reg.commit()
			armedKey:set(nil)
			return true
		end
		if suppressActivatePath == path then
			suppressActivatePath = nil
			return true
		end
		local item = itemForKey(key)
		if item == nil then
			return false
		end
		focusedKey:set(key)
		select(key)
		-- ARM: a NON-POINTER Activate on a reorderable row lifts it (the ratified
		-- arm→navigate→commit paradigm). Pointer taps never arm — a mouse lifts by
		-- travelling past the promotion token, and a tap has to stay a tap.
		if grabOnActivate and reorderable and meta ~= nil and meta.source == "action" and reg ~= nil then
			local hitPath = hitPathOf(key)
			if hitPath ~= nil and reg.arm(hitPath) then
				armedKey:set(key)
				return true
			end
		end
		if spec.onActivate ~= nil then
			(spec.onActivate :: any)(item, meta)
		end
		return true
	end

	-- the dedicated grab action: arm the focused (or named) row, or commit the
	-- one already armed. Bind it to a key when the list also has an onActivate,
	-- so both verbs stay reachable without one shadowing the other.
	local function toggleGrab(key: string?): boolean
		local reg = registry()
		if reg == nil then
			return false
		end
		if reg.mode() == "armed" then
			reg.commit()
			armedKey:set(nil)
			return true
		end
		local target = key or focusedKey:get()
		if target == nil then
			return false
		end
		local hitPath = hitPathOf(target)
		if hitPath == nil or not reg.arm(hitPath) then
			return false
		end
		armedKey:set(target)
		return true
	end

	-- NAVIGATE while ARMED: the predicted drop target steps one eligible row,
	-- the same session re-aims at its centre, and focus does NOT move (the
	-- presenter skips its own move when this returns true).
	local function navigateIntercept(direction: string): boolean
		local reg = registry()
		if reg == nil or reg.mode() ~= "armed" then
			return false
		end
		if armedKey:get() == nil then
			-- the armed session is NOT this list's own grabbed row (a card armed
			-- elsewhere is aiming into us): normal graph navigation + the
			-- presenter's focus-follow aim own that flow — hijacking it here would
			-- pin the ring while the aim stepped invisibly (director round)
			return false
		end
		if direction ~= "up" and direction ~= "down" then
			return true -- consumed: an armed row does not wander sideways
		end
		local delta = if direction == "down" then 1 else -1
		local items = spec.rows:get() :: { any }
		local hovered = reg.interactionTarget()
		local currentIndex = if hovered ~= nil then indexOfKey(keyOfHit(hovered) or "") else nil
		if currentIndex == nil then
			currentIndex = indexOfKey(armedKey:get() or "") or 1
		end
		local next = math.clamp((currentIndex :: number) + delta, 1, math.max(1, #items))
		local nextKey = if items[next] ~= nil then spec.key(items[next]) else nil
		if nextKey == nil then
			return true
		end
		-- materialize the row first: a target outside the window has no rect, so
		-- keep-visible IS how a non-pointer drag reaches the rest of the list
		focusKey(nextKey)
		local hitPath = hitPathOf(nextKey)
		if hitPath ~= nil and boundController ~= nil then
			if boundController.rectOf(hitPath) == nil and type(boundController.refresh) == "function" then
				-- the keep-visible scroll just brought this row into the window, but
				-- it is not MOUNTED until the next structural sync — and a target
				-- with no rect cannot be aimed at. Syncing here means the predicted
				-- target moves on the press that asked for it rather than one press
				-- later, which is the difference between "the list is laggy" and a
				-- drag that tracks the stick.
				boundController.refresh()
			end
			reg.armTo(hitPath)
		end
		return true
	end

	local function handleCancel(_focused: string?): boolean
		local reg = registry()
		if reg ~= nil and reg.mode() == "armed" then
			reg.cancel("cancel")
			armedKey:set(nil)
			return true
		end
		return false
	end

	-- FOCUS-MOVE (arrows/d-pad drove graph focus onto a row hit): sync the
	-- logical focusedKey and scroll the row into view. keepVisibleTarget only
	-- yields a target when the row is out of band, so in-window steps issue no
	-- scroll; a step into the overscan buffer scrolls the window, which
	-- materializes the next row for the following step.
	local function focusMoved(path: string): boolean
		local key = keyOfHit(path)
		if key == nil then
			return false
		end
		focusKey(key)
		return true
	end

	-- FOCUS GROUPS: the mounted WINDOW's row hits as ONE vertical group, in tree
	-- (document/ascending) order. Re-derived on every refresh. ALSO captures the
	-- mounted scroll path (the ScrollView root) so bindNativeScroll can default
	-- to it — the presenter calls this on every present/refresh.
	local function buildFocusGroups(rootNode: any): { any }
		mountedScrollPath = rootNode.path
		local order: { any } = {}
		local function walk(node: any)
			if node.path ~= nil and string.match(node.path, hitPattern) ~= nil then
				local rowPath = node.path
				if spec.rowFocusable ~= nil then
					-- FOCUS-SKIP BY LIVE PREDICATE (SF-L3), evaluated at navigation
					-- time — plus the ACTIVE-INTERACTION EXEMPTION: the row a live
					-- session is aiming at never loses its focusability mid-gesture,
					-- however its own predicate flips. An illegal commit on such a row
					-- REJECTS; it does not vanish from under the gesture.
					table.insert(order, {
						id = rowPath,
						focusable = function(): boolean
							local reg = registry()
							if reg ~= nil and reg.interactionTarget() == rowPath then
								return true
							end
							local key = keyOfHit(rowPath)
							local item = if key ~= nil then itemForKey(key) else nil
							if item == nil then
								return true
							end
							return spec.rowFocusable(item) ~= false
						end,
					})
				else
					table.insert(order, rowPath)
				end
				return -- the row hit is a leaf for focus purposes
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
				axis = "vertical",
				entry = navigation.entry or "nearest",
				wrap = navigation.wrap,
				containment = navigation.containment,
				exit = navigation.exit,
				order = order,
			},
		}
	end

	-- wire the engine CanvasPosition mirror. `scrollPath` defaults to the mounted
	-- ScrollView root (captured in buildFocusGroups after present); pass it
	-- explicitly for a standalone mount that never runs the presenter. Returns an
	-- unbind that stops the mirror and clears the keep-visible controller.
	local function bindNativeScroll(controller: any, scrollPath: string?): () -> ()
		local path = scrollPath or mountedScrollPath
		assert(
			path ~= nil,
			"VirtualList.bindNativeScroll: scroll path unknown — present the control (so its mounted path is captured) or pass it explicitly"
		)
		local unsub = controller.observeScroll(path, function(pos: { x: number, y: number })
			scrollTop:set(pos.y)
		end)
		boundController = controller
		boundScrollPath = path
		if rowsAreTargets then
			local reg = registry()
			if reg ~= nil then
				watchSession(reg)
			end
			-- park the drop line the moment there is a controller to park it with
			writeDropLine(nil)
		end
		return function()
			unsub()
			if boundController == controller then
				if unwatchRegistry ~= nil then
					unwatchRegistry()
					unwatchRegistry = nil
				end
				boundController = nil
				boundScrollPath = nil
			end
		end
	end

	-- public programmatic scroll: clamp into the band and write CanvasPosition
	-- through the given (or bound) controller. Consumers use it for "scroll to
	-- top" and the like; keep-visible uses keepVisibleTarget/focusKey internally.
	local function scrollTo(controller: any, y: number)
		local ctrl = controller or boundController
		local path = boundScrollPath or mountedScrollPath
		if ctrl ~= nil and path ~= nil then
			ctrl.scrollTo(path, { x = 0, y = math.clamp(y, 0, maxTop()) })
		end
	end

	-- one row's "am I the selected one" fact, owned by the row's own scope so it
	-- dies with the row (no per-key cache to prune)
	local function selectedMemo(key: string, itemScope: any): any
		return itemScope:own(core:memo(function(use)
			return use(selectedKey) == key
		end))
	end

	-- the control root IS the native scroll host (UI.ScrollView -> ScrollingFrame
	-- on the live adapter). Its single child is the full-height Canvas anchor;
	-- the windowed rows sit at absolute canvas offsets inside it.
	local canvasChildren: { any } = {
		UI.ForEach({
			id = "W",
			items = windowItems,
			key = function(entry: any)
				return entry.key
			end,
			row = function(entry: any, itemScope: any)
				-- per-row placement memo at the ABSOLUTE CANVAS offset
				-- (index-1)*rowHeight — engine-independent, so a scroll
				-- never re-arranges it (the engine translates via
				-- CanvasPosition). Depends only on the index (and the one
				-- uniform row height), not the scroll: a same-window scroll
				-- delta is zero writes. Owned by the item scope, so it dies
				-- with its row.
				local offsetY = itemScope:own(core:memo(function(use)
					local index = (use(indexByKey) :: { [string]: number })[entry.key]
					if index == nil then
						return 0 -- row is leaving; the unmount is in flight
					end
					-- the SLOT's top: the gutter belongs to the space between
					-- slots, never to the row that follows it
					return (index - 1) * pitchIn(use)
				end))
				local rowHeightDim = itemScope:own(core:memo(function(use)
					return { type = "fixed", px = rowHeightIn(use) }
				end))
				-- a full-row focusable Button hit sits BEHIND the cell
				-- content (ZStack, z = tree order): it gives the row a
				-- focus ring and a tap-activate. There is NO pointer/pan
				-- handler now — the engine ScrollingFrame owns scrolling
				-- (native §4); the cell renders above and interactive cell
				-- content still captures its own taps (non-active hits pass
				-- through — Table parity).
				--
				-- THE DRAG DECLARATIONS RIDE THE HIT, not the row frame: the hit
				-- is the node the engine already delivers pointer input to, and
				-- it fills the row, so its rect IS the row's rect.
				-- SELECTION IS A NATIVE STATE, NOT A CONSUMER'S FILL (review
				-- R2-F6; Table parity — table.luau's row hit carries the same
				-- prop). The list owns `selectedKey`, so the list is what declares
				-- the row's `selected` state: it rides a style tag the theme paints
				-- (`controlSelected`), which is why a cell never has to reach for an
				-- ELEVATION role to say "chosen", and why a theme package can
				-- restyle selection without every consumer changing. A list with
				-- selection off declares nothing, and its rows are byte-identical.
				local hit = UI.Button({
					id = "Hit",
					label = "",
					selected = if selectionMode == "none" then nil else selectedMemo(entry.key, itemScope),
					focusable = true,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
				})
				if reorderable then
					hit = UI.draggable(hit, {
						payload = { kind = REORDER_KIND, key = entry.key, list = id },
						dragMotion = if reorderMotion == "instant" then "object" else reorderMotion,
						-- TOUCH DECLINES so the native ScrollingFrame keeps the pan
						-- (fighting engine momentum scroll is never winnable). Touch
						-- reaches reorder through the grab verbs — Table's precedent,
						-- which shipped the same split for the same reason.
						declineTouch = true,
					})
				end
				if rowsAreTargets then
					hit = UI.dropTarget(hit, {
						accepts = rowAccepts(entry.key),
						onDrop = rowOnDrop(entry.key),
					})
				end
				return UI.ZStack({
					id = "Row",
					anchor = "topLeft",
					offsetY = offsetY,
					width = { type = "fill", weight = 1 },
					height = rowHeightDim,
					children = { hit, spec.cell(entry.item, { scope = itemScope }) },
				})
			end,
		}),
	}
	if reorderable then
		-- the insertion indicator: one hairline, parked off-canvas until a row is
		-- lifted, translated by the presentation channel while it is
		table.insert(
			canvasChildren,
			UI.Box({
				id = "DropLine",
				anchor = "topLeft",
				surface = "accent",
				width = { type = "fill", weight = 1 },
				-- the SHARED drop-line metric (`controls.table.indicatorThickness`,
				-- documented in the snapshot as "resize preview + drop line"). Two
				-- list constructs drawing the same affordance at two thicknesses
				-- would be a theming bug, so they read one number.
				height = { type = "fixed", px = "controls.table.indicatorThickness" },
				offsetY = DROP_LINE_PARK,
			})
		)
	end

	local blueprint = UI.ScrollView({
		id = id,
		width = spec.width or { type = "fill", weight = 1 },
		-- a LIVE viewport hands the host a Readable<dim> (dims are reactive,
		-- dirty=measure), so the painted box re-solves with the same number the
		-- windowing math reads
		height = if viewportIsLive
			then listScope:own(core:memo(function(use)
				return { type = "fixed", px = viewportIn(use) }
			end))
			else { type = "fixed", px = viewportSpec },
		axis = "y",
		padding = 0,
		gap = 0,
		-- native scroll + clip host (native-substrate NS-A2): the adapter mounts a
		-- ScrollingFrame; descendants render inside it and partial rows crop. The
		-- solver's scroll-axis content sum becomes CanvasSize; the ENGINE owns the
		-- live offset (wheel/touch/momentum), reported back through observeScroll.
		clipChildren = true,
		children = {
			UI.Anchor({
				id = "Canvas",
				width = { type = "fill", weight = 1 },
				-- the FULL virtual height (a live fixed Dim): this single child is
				-- what the solver sums into contentSize == CanvasSize (native §6)
				height = canvasDim,
				children = canvasChildren,
			}),
		},
	})

	-- attach the input contribution so the presenter auto-composes VirtualList's
	-- four-input story with ZERO consumer opts (ui_todo §0; ADR-0013):
	-- focusGroups (windowed row hits, re-derived per refresh; also captures the
	-- mounted scroll path), handleActivate (tap/Return/ButtonA -> item onActivate,
	-- or arm/commit while reorderable), focusMoved (arrow/d-pad focus -> logical
	-- focusedKey + keep-visible scroll), and — only when the list can be
	-- reordered — navigateIntercept/handleCancel for the armed paradigm. A plain
	-- list contributes neither, so a bare screen never shadows a navigation key.
	-- No wheel/pan bundle entry: the engine ScrollingFrame scrolls, and its
	-- CanvasPosition flows back through the bindNativeScroll mirror.
	local bundle: any = {
		focusGroups = buildFocusGroups,
		handleActivate = handleActivate,
		focusMoved = focusMoved,
		bindController = function(controller: any)
			-- the registry lives on the surface, so the list only has to notice it
			if boundController == nil then
				boundController = controller
			end
			if rowsAreTargets then
				local reg = registry()
				if reg ~= nil then
					watchSession(reg)
				end
			end
		end,
	}
	if reorderable then
		bundle.navigateIntercept = navigateIntercept
	end
	if reorderable or rowsAreTargets then
		-- handleCancel rides with EVERY armed-paradigm participation, not just
		-- reorder (director virtual-controller round: a drop-target list armed a
		-- card and B had no cancel handler at all — the session simply survived
		-- the press)
		bundle.handleCancel = handleCancel
	end
	blueprint = contribution.attach(blueprint, bundle)

	local list = {
		blueprint = blueprint,
		-- the contributed group's NAME, published so a sibling group can declare an
		-- exit into this list without hardcoding the `vl:` convention
		focusGroupName = focusGroupName,
		scrollTop = scrollTop,
		focusedKey = focusedKey,
		selectedKey = selectedKey,
		armedKey = armedKey,
		dropIndex = dropIndex,
		autoscroll = autoscrollState,
		pathOf = pathOf,
		focusKey = focusKey,
		select = select,
		toggleGrab = toggleGrab,
		stepAutoscroll = stepAutoscroll,
		bindNativeScroll = bindNativeScroll,
		scrollTo = scrollTo,
	}
	function list.clearSelection()
		selectedKey:set(nil)
	end
	-- the mounted native-scroll host path (nil until first presented/refreshed)
	function list.scrollPath(): string?
		return mountedScrollPath
	end
	-- deterministic diagnostic summary (§10.2 dump form; uniform control seam)
	function list.dump()
		local windowKeys = {}
		for _, entry in windowItems:get() :: { any } do
			table.insert(windowKeys, entry.key)
		end
		return {
			schema = "luauui-virtual-list-dump/1",
			id = id,
			rowHeight = rowHeightNow(),
			rowGap = rowGapNow(),
			viewportHeight = viewportNow(),
			overscan = overscan,
			scrollTop = clampedTop:get(),
			focusedKey = focusedKey:get(),
			selectedKey = selectedKey:get(),
			armedKey = armedKey:get(),
			dropIndex = dropIndex:get(),
			selection = selectionMode,
			reorderable = reorderable,
			dropSurface = isDropSurface,
			focusGroup = focusGroupName,
			autoscroll = autoscrollState:get().state,
			window = windowKeys,
			totalRows = #(spec.rows:get() :: { any }),
		}
	end
	function list.debugWindow(): { [string]: boolean }
		local out: { [string]: boolean } = {}
		for _, entry in windowItems:get() :: { any } do
			out[entry.key] = true
		end
		return out
	end
	function list.dispose()
		if unwatchRegistry ~= nil then
			unwatchRegistry()
			unwatchRegistry = nil
		end
		for key in table.clone(slideValues) do
			disposeSlide(key)
		end
		listScope:dispose()
	end
	return list
end

return virtual_list
