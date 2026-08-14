--!strict
-- VirtualList (design §10.5; native-substrate §4/§6; UI-RUNTIME-002,
-- UI-FOCUS-001, UI-LIFE-002): fixed-extent keyed-item virtualization riding the
-- NATIVE scroll substrate. The control root is a UI.ScrollView (engine
-- ScrollingFrame on the live adapter): the engine owns the live offset (wheel,
-- touch drag, momentum, elastic, scroll bars), and the framework owns ONLY the
-- content geometry and the windowing decision — the exact split the native
-- plan §4/§6 draws (geometry headless, scroll physics at the edge).
--
--[[ TWO AXES, ONE VIRTUALIZER (spec: docs/plans/swiftui-parity-round2.md §2.3;
	game-director decision 2026-08-12). `spec.axis` is `"y"` (a vertical list of
	rows — the DEFAULT, and what every existing caller builds) or `"x"` (a
	sideways strip of items). It is CONSTRUCTION-ONLY for the same reason
	`ScrollView.axis` is: a reactive engine scroll axis would rebuild native
	scroll state mid-gesture (constitution §16 E-6).

	READ THE REST OF THIS HEADER WITH THE AXIS IN MIND. Everything below is
	written in the vocabulary of the DEFAULT vertical axis — "row", "height",
	"top", "down" — because that is the shape every shipped consumer builds and
	the shape the prose reads best in. On `axis = "x"` every one of those words
	transposes, exactly and without exception:

	    axis = "y" (default)          axis = "x"
	    ─────────────────────         ──────────────────────
	    row height                    item width
	    viewport height               viewport width
	    canvas is full-HEIGHT         canvas is full-WIDTH
	    windowed by CanvasPosition.Y  windowed by CanvasPosition.X
	    row offsetY = (i-1)*pitch     item offsetX = (i-1)*pitch
	    focus group axis "vertical"   focus group axis "horizontal"
	    Up/Down + DPadUp/Down step    Left/Right + DPadLeft/Right step
	    autoscroll bands top/bottom   autoscroll bands left/right

	THE ARITHMETIC IS SHARED, NOT DUPLICATED: `contentIn`, `pitchIn`,
	`windowItems`, `clampedTop`, `keepVisibleTarget` and `insertSlotAt` are
	written once, in one dimension, and the axis decides only WHICH engine
	coordinate and WHICH blueprint dim they are wired to. Getting this wrong
	looks like a list that scrolls one way and windows the other.

	The axis-neutral names are `itemExtent` and `viewportExtent`. `rowHeight`
	and `viewportHeight` are DEPRECATED ALIASES of exactly those two and KEEP
	WORKING unchanged (ADR-0011: at least one MINOR of notice; both spellings
	are in `LuauUI.DEPRECATIONS`). Passing a name and its alias together is
	refused — it is one field, and two answers to it is an authoring mistake.
	Nothing else was renamed: `rowGap` is still `rowGap` (a gap is a gap, and it
	applies along whichever axis the list scrolls), and `scrollTop` is still
	`scrollTop` (see its own declaration — on `axis = "x"` it mirrors
	`CanvasPosition.X`, and the name predates the field).

	ROW ACTIONS ARE REFUSED ON A HORIZONTAL LIST, at construction. A row-actions
	tray is opened by a SIDEWAYS swipe, and a sideways swipe on a sideways list
	is already how the player scrolls it. One gesture cannot mean both, and
	picking one silently is how a gesture becomes unpredictable — so the
	combination is named and refused rather than resolved by whichever handler
	got there first.

	VARIABLE ITEM EXTENTS ARE A RECORDED GAP, NOT A HALF-BUILT SEAM. Nothing in
	this file is staged for them and no field is reserved: the window is
	`index × pitch`, which is O(1) and exact precisely BECAUSE the pitch is one
	number. §2.3 states the problem (an item's extent is only known by building
	it, which is the thing virtualization exists to avoid) and records both
	candidate designs; it does not sanction starting one. ]]
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
-- child, a full-MAIN-AXIS Anchor "Canvas" (its main-axis dim = the content
-- extent, a live memo; its cross-axis dim fills), and the windowed rows are
-- ABSOLUTELY-positioned anchor children at offsetY = (index-1)*PITCH on
-- `axis = "y"` / offsetX = (index-1)*PITCH on `axis = "x"`. The solver sums the
-- scroll axis, so contentSize == the Canvas's main-axis size == the full
-- virtual extent; the renderer maps that to CanvasSize (native-substrate
-- NS-A2). Row offsets are CANVAS offsets, engine-independent (a scroll never
-- re-arranges them — the ENGINE translates via CanvasPosition), so a
-- same-window scroll delta is now ZERO framework writes (was rect-writes-only
-- under the old Anchor+offsetY trick).
--
-- PITCH vs ROW (spec.rowGap). The slot a row occupies is `itemExtent + rowGap`
-- tall; the row's own node stays `itemExtent` tall, so the gutter is DEAD SPACE
-- that belongs to neither neighbour — exactly what a `UIListLayout.Padding`
-- gives, and exactly why the alternative (hand in the pitch AS the item extent
-- and inset the cell) is wrong: that inflates the row's HIT into the gutter, so
-- a press between two plates activates one of them. EVERY windowing number is
-- on the pitch (canvas extent, clamp, window membership, keep-visible, the
-- insertion slot, the reorder slide); the row box and the row rect are not. The
-- content extent carries no TRAILING gutter — N rows span
-- N*itemExtent + (N-1)*rowGap. `rowGap = 0` is the default and reproduces the
-- pre-field arithmetic byte for byte. On `axis = "x"` "tall" reads "wide" and
-- the gutter is the horizontal space between items; the field is not renamed
-- because a gap is a gap on either axis.
--
-- scrollTop is a MIRROR of the engine CanvasPosition ALONG THE LIST'S AXIS
-- (`.Y` on `axis = "y"`, `.X` on `axis = "x"` — the name predates the field
-- and is kept because it is public API), never a hand-managed offset. It is written ONLY by (i) the presenter/consumer wiring the engine
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
-- COMPUTES the target canvas offset on its own axis and issues the framework's
-- one programmatic
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
--
-- FOCUS POLICY (spec.focusPolicy, default "key"). A list whose ORDER changes
-- under the player asks a question a keyed list cannot answer on its own: when
-- the focused item is overtaken, does the cursor follow the ITEM or stay on the
-- SLOT?
--   * "key" (default) — the cursor follows the ITEM. Every number below is the
--     pre-field arithmetic verbatim; the policy costs an existing list nothing.
--   * "index" — the cursor stays on the SLOT. When a data update moves the
--     focused item off the slot it was focused at, focus RETARGETS to whoever
--     occupies that slot now (clamped to the last slot when the list shrank).
--     This is the answer a live standings list needs: "selection riding a
--     racer's button visibly JUMPS slots on every overtake."
-- The retarget drives BOTH halves of focus — the logical `focusedKey` AND the
-- screen's focus GRAPH, reached through the contribution's `bindFocusGraph` —
-- because two focus authorities is the split brain the policy exists to remove.
-- It DECLINES in exactly two situations: while a drag session is live (a policy
-- that re-aimed a gesture mid-flight would fight the player's hand), and when
-- the slot's new occupant fails `rowFocusable` (parking the ring on a dead row
-- is worse than the jump it prevents, so focus falls through to the item).
-- FOUR-INPUT STORY (ui_todo §0; ADR-0013), auto-composed by the presenter:
--   * pointer/touch: the engine ScrollingFrame owns wheel/pan/momentum scroll;
--     each row is a focusable Button hit whose tap routes handleActivate -> the
--     spec's item-level onActivate; the scroll host clips partial rows natively.
--     A MOUSE press that travels past the shared promotion token lifts the row
--     (reorder) or the payload (drop); a TOUCH press on the row body DECLINES
--     the capture so the native pan keeps working, which is why touch reaches
--     reorder through the non-pointer grab verbs instead (Table precedent).
--   * keyboard: a contributed focusGroups exposes the WINDOWED row hits as one
--     group along the LIST'S OWN AXIS (`vertical` on `axis = "y"`, `horizontal`
--     on `axis = "x"`) — re-derived per refresh window slide. Up/Down steps rows
--     on a vertical list, Left/Right on a horizontal one; there is ONE focus
--     map, read two ways (constitution §9), never a second order. Focus moving
--     to an off-band row scrolls it into view via the keep-visible scrollTo;
--     Return activates the focused row.
--   * gamepad: D-pad is identical to arrows (so DPadLeft/DPadRight step a
--     horizontal list) and ButtonA activates. When the list
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
-- spec: { id?, rows (Readable {T}), key (T)->string,
--   axis? ("y" | "x", default "y" — construction-only; see TWO AXES above),
--   itemExtent (px number or Readable<number> — one item's MAIN-AXIS size,
--     uniform per list; DEPRECATED ALIAS: rowHeight, still accepted, and
--     passing both is refused),
--   rowGap? (px number or Readable<number>, default 0 — the
--   gutter between item SLOTS; the pitch is itemExtent + rowGap and the item's
--   own node stays itemExtent along the axis),
--   viewportExtent (px number or Readable<number> — the scroll host's
--     MAIN-AXIS size; DEPRECATED ALIAS: viewportHeight, same rules),
--   overscan? (items, default 2),
--   cell (item, ctx: {scope}) -> Blueprint, width? (the list's width Dim —
--     axis = "y" ONLY, where width is the CROSS axis; refused on axis = "x",
--     where the width IS viewportExtent),
--   onActivate? ((item, meta) -> ()),
--   selection? ("none" | "single"), onSelect? ((item, key) -> ()),
--   selectionPaint? ("native" | "none" — "none" keeps the selection and drops
--     only the row's native `selected` state, for a list whose "chosen" is
--     carried somewhere other than the row),
--   reorderable? (boolean), onReorder? ((key, toIndex) -> ()),
--   reorderMotion? (motion class name | "instant"), motionClock? (a motion clock),
--   grabOnActivate? (boolean), dropSurface? (boolean),
--   rowDropTarget? ((item) -> { accepts?, onDrop }?),
--   rowFocusable? ((item) -> boolean), autoscroll? (boolean | autoscroll opts),
--   focusPolicy? ("key" | "index", default "key" — does the cursor follow the
--     ITEM across a re-sort, or stay on the SLOT; see FOCUS POLICY above),
--   rowActions? ((item) -> { leading?, trailing?, fullSwipe? }?) — HOSTED ROW
--     ACTIONS (see below); nil per item = that row is unwrapped. VERTICAL LISTS
--     ONLY — refused on axis = "x", because the tray's reveal gesture and the
--     list's own scroll gesture would be the same sideways swipe,
--   env? (the surface environment — Table's own `env` key, and read for the same
--     reason: the row-action tray's `buttonPad`/`buttonMinWidth` are theme facts
--     with no font component, so measuring a tray's natural width needs the live
--     `themeMetrics`. Absent degrades to the NEUTRAL snapshot, which is right
--     until a theme package moves those two metrics and then silently is not —
--     pass it on any list with `rowActions`. Nothing else in this control reads
--     it),
--   navigation? ({ name?, wrap?, containment?, entry?, exit? }) — overrides for
--     the ONE focus group this list contributes; absent = today's group verbatim }
--
-- HOSTED ROW ACTIONS (spec.rowActions; design doc
-- docs/plans/row-actions-hosted-mode-design.md). Table's own `rowActions` wraps
-- every actionable row in a `newRowActions` COMPOSITE — five extra instances per
-- row, mounted whether the row is ever touched or not. A virtualized list cannot
-- pay that: the measured cost is ~+45% steady / ~+82% fling per refresh, and the
-- rows it would be paid on are overwhelmingly rows nobody ever swipes.
--
-- So VirtualList hosts the feature instead of delegating it. A closed row mounts
-- NOTHING extra:
--   * ONE shared four-function pointer dispatcher per list, wired onto the row
--     `Hit` Button that already mounts. A closed row's whole marginal cost is
--     four static props on an existing node — no wrapper, no memo, no
--     subscription. A list with no `rowActions` declares none of them and builds
--     the byte-identical Hit it always did.
--   * The gesture/state engine (`row_actions.buildHosted` — the SAME axis lock,
--     velocity, commit ladder and one-open coordinator the composite runs, with
--     no blueprint) is built LAZILY, on the first pointer-down that lands on
--     that row. Scrolling a thousand closed rows builds zero engines.
--   * The engine paints nothing itself: it reports the slide through `onSlide`,
--     which this control mirrors into `engagedKey`/`engagedOffset` — the two
--     signals the shared tray overlay and the presentation-channel slide read.
-- `rowActions` + `reorderable` on one list is refused in v1: VirtualList's
-- reorder rides the declarative `UI.draggable` contract, and composing that with
-- the raw-handler funnel is its own task (Table does it with
-- `row_actions.composeWithReorder`, over a hit it owns outright).

local autoscrollLib = require("../input/autoscroll")
local contribution = require("../input/contribution")
local row_actions = require("./row_actions")
local row_actions_state = require("../input/row_actions_state")
local solverLib = require("../layout/solver")
local specGuard = require("../spec_guard")
local rowCapability = require("../row_capability")

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

--[[ THE HOSTED TRAY OVERLAY'S OWN PATHS — the contract between this control and
	the shared overlay (Task 4 mounts it; Task 3 named it, because a hosted engine
	is handed its tray paths at build time and measures/anchors against them from
	then on).

	ONE overlay per list, not one per row: the coordinator policy is at most one
	open row across the whole list, so a tray per row would be N-1 permanently
	dead subtrees. It sits in the canvas, AFTER the rows ForEach, so the revealed
	tray buttons are natively tappable above the row that slid off them:

	    {scrollRoot}/Canvas/RowActionsOverlay/[{key}]/RowActionsTray/TrayLeadingWhen/then/TrayLeading
	    {scrollRoot}/Canvas/RowActionsOverlay/[{key}]/RowActionsTray/TrayTrailingWhen/then/TrayTrailing

	A `UI.ForEach` OVER THE AT-MOST-ONE ENGAGED ROW, not the `UI.When` Task 3
	sketched, and the reason is engagement moving DIRECTLY from one row to
	another: swiping row B while row A is still open switches `engagedKey` A -> B
	with no nil in between (`hostedApplySlide`'s claim rule — B is driving the
	live gesture, A is merely finishing its close). A `When`'s branch factory runs
	only on false -> true, so the overlay would have kept painting A's actions
	over B's row for as long as B stayed open. A keyed region remounts on exactly
	that change, which is what a keyed region is for — and the key in the path
	also names, in any dump, which row a tray belongs to. Closed cost is identical
	(one structural Frame either way; a `[{key}]` segment is a path prefix, not a
	node — src/mount.luau's `mountForEach`).

	`RowActionsTray` is the group positioned at the engaged row's canvas offset,
	and under it sit the engine's OWN tray `When`s (`engine.trayViews` — the same
	blueprints standalone mode parents under its row root), so the `{Tray*}When/
	then/{Tray*}` shape below is row_actions' own, unchanged. The action buttons
	inside a tray are `{trayPath}/Action:{id}`, that file's convention in both
	modes. ]]
local HOSTED_OVERLAY_ID = "RowActionsOverlay"
local HOSTED_TRAY_GROUP_ID = "RowActionsTray"
-- "nothing is engaged", as ONE shared empty table: the overlay's items memo
-- answers this for the whole closed life of every hosted list, and a fresh empty
-- table per recompute would dirty the keyed region for no change at all.
local HOSTED_NO_OVERLAY: { any } = {}

--[[ EVERY FOCUSABLE BUTTON UNDER THE OVERLAY, in document order — the revealed
	tray's actions, for the focus group `buildFocusGroups` contributes. The
	eligibility rules are `focus_map.luau`'s own (`FOCUSABLE`, `focusable = false`,
	`enabled = false`, a retiring subtree), restricted to the one class a tray can
	contain: a tray action IS a `UI.Button` in both modes (row_actions' own
	`buildTray`).

	THE `Button`-ONLY TEST IS A DELIBERATE NARROWING of `focus_map.FOCUSABLE`
	(`Button`/`Toggle`/`TextField`), not a copy of it that has drifted: a tray's
	contents are this framework's own construction, and if row_actions ever put a
	focusable that is NOT a Button inside one, silently omitting it here would be
	an unreachable control — so the answer is to widen this test in the same
	commit, deliberately, rather than to have it quietly accept whatever appears.
	Module scope, not per-instance: it is a pure function of its arguments. ]]
local function collectTrayFocusables(node: any, out: { string })
	if node.retiring == true then
		return
	end
	local props = node.props
	if node.class == "Button" then
		if not (props ~= nil and (props.focusable == false or props.enabled == false)) then
			table.insert(out, node.path)
		end
		return
	end
	for _, child in node.children or {} do
		collectTrayFocusables(child, out)
	end
end

-- the closed key set for whatever `spec.rowActions(item)` returns for ONE row —
-- exactly the three fields `newRowActions` exposes besides the ones this control
-- supplies itself (`paths`/`coordinator`/`onSlide`/`onCommitHeight`/`id`).
-- Checked per row, at engine build, with the row's key in the message (§4;
-- newTable's own ROW_ACTIONS_RESULT_KEYS precedent).
local HOSTED_ROW_ACTIONS_KEYS = specGuard.keySet({ "leading", "trailing", "fullSwipe" })

-- CLOSED SPEC (constitution §4; ARCH-1). Exactly the fields this control
-- reads — an unknown one is an authoring mistake, never a silent no-op.
local VIRTUAL_LIST_KEYS = specGuard.keySet({
	"autoscroll",
	-- the scroll axis, construction-only ("y" default | "x")
	"axis",
	"cell",
	"dropSurface",
	"env",
	"focusPolicy",
	"grabOnActivate",
	"id",
	-- the canonical, axis-neutral extent names. `rowHeight` / `viewportHeight`
	-- below are their DEPRECATED ALIASES and stay in this set because they stay
	-- accepted (ADR-0011) — removing them from the set is what the removal
	-- release does, not this one.
	"itemExtent",
	"key",
	"motionClock",
	"navigation",
	"onActivate",
	"onReorder",
	"onSelect",
	"overscan",
	"reorderMotion",
	"reorderable",
	"rowActions",
	-- PER-ROW CAPABILITY OPT-OUTS (parity round 3, item C). Positive polarity,
	-- matching `rowFocusable` two lines down rather than SwiftUI's negative
	-- `moveDisabled`/`selectionDisabled`/`deleteDisabled` — see
	-- `src/row_capability.luau` for why, and for the inverse mapping.
	"rowDeletable",
	"rowDropTarget",
	"rowFocusable",
	"rowMovable",
	"rowSelectable",
	"rowGap",
	"rowHeight", -- deprecated alias of itemExtent (ADR-0011)
	"rows",
	"selection",
	"selectionPaint",
	"viewportExtent",
	"viewportHeight", -- deprecated alias of viewportExtent (ADR-0011)
	"width",
})

function virtual_list.build(LuauUI: any, core: any, spec: any)
	--[[ FLOW-WRAP DOES NOT COMPOSE WITH VIRTUALIZATION, and it says why.

		`wrap` is not in this control's closed key set, so the guard above already
		refuses it — but with a generic "unknown field" that leaves the author to
		guess whether it is a typo, an unbuilt feature, or a deliberate refusal.
		It is the third, and the reason is structural rather than a scheduling
		accident:

		this list windows by `index x itemExtent`, which is O(1) and exact
		PRECISELY because the extent is one number (see the `itemExtent` refusal
		below). A wrapped line has ragged main extents and a variable number of
		items per line, so `index x pitch` cannot say which items are on screen at
		a given scroll offset — it would need a running-offset index, which is the
		same problem `swiftui-parity.md` §4.2 records as unbuilt for variable item
		extents, with two candidate designs that each give something up and no
		screen asking for either.

		Named here rather than left generic, because a refusal that does not say
		why reads as an oversight and gets re-filed as a feature request. ]]
	if spec.wrap ~= nil then
		error(
			"LuauUI newVirtualList: spec.wrap is refused — flow-wrap and virtualization do not compose. "
				.. "This list windows by index x itemExtent, which is exact only because the extent is ONE number; "
				.. "a wrapped line has ragged extents and a variable count per line, so that arithmetic cannot say "
				.. "which items are on screen. Use UI.HStack/UI.VStack with wrap = true inside a UI.ScrollView for a "
				.. "wrapping collection that does not need windowing, or keep the list unwrapped.",
			2
		)
	end
	specGuard.assertKnownKeys("newVirtualList", spec, VIRTUAL_LIST_KEYS, "spec")
	--[[ PER-ROW OPT-OUTS MAY ONLY SUBTRACT (parity round 3, item C).
		A predicate that narrows a capability this list does not have is an
		accepted property that does nothing — constitution §4's exact
		prohibition, and the defect class the placement audit was written to
		end. Refused at construction, naming what is missing. ]]
	rowCapability.assertNarrowsSomething(
		"newVirtualList",
		"rowSelectable",
		spec.rowSelectable,
		spec.selection ~= nil and spec.selection ~= "none",
		'selection is absent or "none", so no row is selectable to begin with',
		'Declare selection = "single" (and an onSelect), or drop spec.rowSelectable.'
	)
	rowCapability.assertNarrowsSomething(
		"newVirtualList",
		"rowMovable",
		spec.rowMovable,
		spec.onReorder ~= nil,
		"onReorder is absent, so no row moves at all",
		"Declare reorderable = true and an onReorder handler, or drop spec.rowMovable."
	)
	rowCapability.assertNarrowsSomething(
		"newVirtualList",
		"rowDeletable",
		spec.rowDeletable,
		spec.rowActions ~= nil,
		"rowActions is absent, so no row carries a destructive action to refuse",
		"Declare a rowActions callback returning a destructive action, or drop spec.rowDeletable."
	)
	--[[ THE SCROLL AXIS (spec §2.3). CONSTRUCTION-ONLY, for exactly the reason
		`ScrollView.axis` is (constitution §16 E-6): the axis decides which native
		scroll state the engine holds, so a reactive one would rebuild that state
		mid-gesture — the player's finger would be mid-fling on a host that had
		just changed which way it scrolls. `"y"` is the default AND a legal
		explicit answer, and it is the pre-field control byte for byte: every
		branch below is STATIC on this value, chosen once at build. ]]
	local axis: string = spec.axis or "y"
	assert(
		axis == "y" or axis == "x",
		`VirtualList.axis must be "y" (a vertical list of rows — the default) or "x" (a sideways strip of items) — `
			.. `got '{tostring(spec.axis)}'. It is construction-only: a reactive scroll axis would rebuild the engine's `
			.. "native scroll state mid-gesture (constitution §16 E-6, the same rule ScrollView.axis follows)."
	)
	local isX = axis == "x"
	--[[ ONE FIELD, TWO NAMES (ADR-0011). `itemExtent` / `viewportExtent` are the
		canonical, axis-neutral names; `rowHeight` / `viewportHeight` are their
		DEPRECATED ALIASES and keep working unchanged for at least one MINOR —
		both spellings are registered in `LuauUI.DEPRECATIONS`, and an existing
		vertical caller needs no edit at all.

		PASSING BOTH IS REFUSED rather than resolved by precedence. They are one
		field; two answers to it means the author believes they are two, and
		whichever one silently lost would be the bug report. ]]
	local function oneOf(canonicalName: string, canonical: any, aliasName: string, alias: any): any
		if canonical ~= nil and alias ~= nil then
			error(
				`newVirtualList: {canonicalName} and {aliasName} are the SAME field under two names `
					.. `({aliasName} is the deprecated alias of {canonicalName}, ADR-0011) — pass exactly one`,
				0
			)
		end
		return if canonical ~= nil then canonical else alias
	end
	local itemExtentSpec = oneOf("itemExtent", spec.itemExtent, "rowHeight", spec.rowHeight)
	-- THE ITEM EXTENT MAY BE DERIVED, BUT IT IS ONE NUMBER FOR THE WHOLE LIST
	-- (finding F13). A Readable is accepted so an extent derived from the theme
	-- metrics snapshot (or the preferred-text offset) re-derives on a swap
	-- without rebuilding the list; what is NOT accepted is a per-item extent,
	-- because the windowing arithmetic is index×extent and a per-row wrap
	-- difference would silently mis-window at the largest text offset.
	local itemExtentIsLive = type(itemExtentSpec) == "table" and type(itemExtentSpec.get) == "function"
	assert(
		itemExtentIsLive or (type(itemExtentSpec) == "number" and itemExtentSpec > 0),
		"VirtualList.itemExtent (deprecated alias: rowHeight — both are accepted, one at a time) must be a positive "
			.. "number or a Readable<number>: ONE item's size along the list's own axis (its height on axis=\"y\", its "
			.. 'width on axis="x"), uniform per list. Derive it from the theme metrics snapshot at the call site. '
			.. "Variable item extents are a RECORDED GAP with no implementation and no reserved seam "
			.. "(docs/plans/swiftui-parity-round2.md §2.3)."
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
		"VirtualList.rowGap must be a non-negative number or a Readable<number> (the gutter between item slots ALONG "
			.. "THE LIST'S AXIS, uniform per list; the item itself stays itemExtent along that axis and the gutter is "
			.. "dead space). The name is not axis-specific on purpose: a gap is a gap on either axis."
	)
	-- THE VIEWPORT EXTENT MAY BE LIVE for the same reason itemExtent may (P5-F5):
	-- a list filling a container, or re-deriving after an environment change,
	-- hands in a Readable and BOTH consumers of the number — the host's
	-- main-axis dim (reactive, dirty=measure) and the windowing arithmetic —
	-- track it, so the painted box and the window can never disagree.
	local viewportSpec = oneOf("viewportExtent", spec.viewportExtent, "viewportHeight", spec.viewportHeight)
	local viewportIsLive = type(viewportSpec) == "table" and type(viewportSpec.get) == "function"
	assert(
		viewportIsLive or (type(viewportSpec) == "number" and viewportSpec > 0),
		"VirtualList.viewportExtent (deprecated alias: viewportHeight — both are accepted, one at a time) must be a "
			.. "positive number or a Readable<number>: the scroll host's size along the list's own axis (its height on "
			.. 'axis="y", its width on axis="x")'
	)
	assert(type(spec.key) == "function", "VirtualList.key is required")
	assert(type(spec.cell) == "function", "VirtualList.cell is required")
	--[[ `width` IS THE CROSS AXIS, and only a vertical list has one there. On
		`axis = "x"` the width IS the main axis — it is what `viewportExtent`
		declares — so accepting both would be two answers to one dim, and
		silently letting either win is the class of bug the extent aliases are
		refused for above. The cross axis of a horizontal list is its HEIGHT, and
		it FILLS: wrap the list in a box of the height you want. ]]
	if isX then
		assert(
			spec.width == nil,
			'VirtualList.width is an axis="y" field (there, width is the CROSS axis). On axis="x" the width IS the '
				.. "scroll axis — declare it as viewportExtent. The cross axis of a horizontal list is its height, "
				.. "which fills its container; wrap the list to fix it."
		)
	end
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
	--[[ THE STATE AND ITS PAINT ARE SEPARABLE (director, 2026-08-04).

		Selection normally rides the row: the list declares the native `selected`
		state and the theme paints it (`controlSelected`). But some lists carry
		"which one is chosen" somewhere that is not the row at all. Rascal Rally's
		sponsor standings is the case that asked for this — the selected racer is
		the one the CAMERA is watching, and the ruling there is that the watched row
		paints NOTHING, byte-identical to its siblings.

		`selection = "none"` cannot express that: it deletes the selection itself,
		taking `onSelect` and `selectedKey` with it. So the paint gets its own
		switch, defaulting to the behaviour every existing caller already has. ]]
	local selectionPaint: string = spec.selectionPaint or "native"
	assert(
		selectionPaint == "native" or selectionPaint == "none",
		`VirtualList.selectionPaint must be "native" or "none" (got '{tostring(spec.selectionPaint)}')`
	)
	--[[ DOES THE CURSOR FOLLOW THE ITEM OR THE SLOT? (see FOCUS POLICY in the
		header.) A closed two-value enum, construction-only: the policy decides how
		the control WIRES ITSELF to the focus graph, and a list that changed its
		mind mid-session would leave the pin holding a slot from the other policy.
		"key" is the default AND a legal explicit answer, and it is the pre-field
		behaviour byte for byte — the pin below is never even allocated. ]]
	local focusPolicy: string = spec.focusPolicy or "key"
	assert(
		focusPolicy == "key" or focusPolicy == "index",
		`VirtualList.focusPolicy must be "key" (focus follows the item across a re-sort — the default) or "index" `
			.. `(focus stays on the slot and retargets to whoever occupies it) — got '{tostring(spec.focusPolicy)}'`
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
	-- ...and the SECOND group a hosted list contributes while a row's tray is
	-- revealed (see `buildFocusGroups`). Derived from the row group's own name so
	-- two lists on one surface can never collide, and so a dump names which list a
	-- tray group belongs to.
	local hostedTrayGroupName: string = `{focusGroupName}:rowActions`
	local reorderable = spec.reorderable == true
	--[[ HOSTED ROW ACTIONS: a BUILD-TIME fact, read once (see the header). Every
		branch below is static on `hostedEnabled`, never on a live value — a list
		without the field must construct exactly the rows it always did, and a
		branch a plain list can still evaluate per row is already a cost it did
		not have.

		The v1 refusal is a hard `error`, not a degrade: both features want the
		same raw pointer capture on the same node, and silently letting one win
		would give a player a list whose rows sometimes reorder and sometimes
		reveal depending on which handler got there first. ]]
	local hostedRowActions: any = spec.rowActions
	if hostedRowActions ~= nil then
		assert(
			type(hostedRowActions) == "function",
			"VirtualList.rowActions must be a function (item) -> { leading?, trailing?, fullSwipe? }? "
				.. "(nil for a row with no actions)"
		)
		if reorderable then
			error("newVirtualList: rowActions + reorderable is unsupported (v1)", 0)
		end
		--[[ ...AND ROW ACTIONS ARE VERTICAL-ONLY, for a reason that is about the
			PLAYER'S HAND rather than about this file. A tray is revealed by a
			SIDEWAYS swipe; on a sideways list, a sideways swipe is already how the
			player scrolls. One gesture cannot mean both "scroll the list" and "open
			the tray", and whichever handler happened to claim it first would make
			the answer depend on the axis lock's tie-break — a list whose rows
			sometimes slide and sometimes scroll.

			Refused, not degraded, and refused HERE at construction rather than at
			the first swipe: an author who declares both has a design question to
			answer, and the honest place to raise it is the build. ]]
		if isX then
			error(
				'newVirtualList: rowActions is unsupported on axis = "x". A row-actions tray is opened by a SIDEWAYS '
					.. "swipe, and on a horizontal list a sideways swipe is already the scroll gesture — one gesture "
					.. "cannot mean both, and picking one silently makes the list unpredictable. Put the actions on a "
					.. 'vertical list, or reach them another way (a long-press menu, a detail view) on axis = "x".',
				0
			)
		end
	end
	local hostedEnabled = hostedRowActions ~= nil
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

	--[[ ===== THE AXIS SEAM =====================================================
		Everything above this line is one-dimensional arithmetic that does not care
		which way the list runs. These four helpers are the ONLY place the axis
		turns into a coordinate, and every write below goes through one of them —
		so "which way does this list scroll" is answered once, not per call site.

		`mainOf` reads the main-axis component of an engine/pointer point or a
		rect origin; `vec` builds the {x,y} pair the renderer's scroll and
		presentation writes take. `crossFill` and the two dim helpers keep the
		blueprint side symmetric. ]]
	--[[ A FRESH `fill` DIM PER NODE, never one shared table. Every site below used
		to write the literal inline, so a fresh table per node is the pre-field
		allocation profile byte for byte — and it is what keeps a dim a VALUE. One
		shared constant would put the same table on the canvas, on every row and on
		the drop line at once, which costs nothing today and is a trap the first
		time anything treats a dim as its own. ]]
	local function fill(): any
		return { type = "fill", weight = 1 }
	end
	-- `any`, not `number`: the drag registry's live state publishes `x`/`y` that
	-- are nil between sessions, and the one caller that can see that nil tests
	-- for it. Every other caller reads a point that always has both.
	local function mainOf(point: any): any
		return if isX then point.x else point.y
	end
	-- an {x,y} carrying `value` on the main axis and 0 on the cross axis: what
	-- `controller.scrollTo` and `setPresentationTransform` both take
	local function vec(value: number): { x: number, y: number }
		return if isX then { x = value, y = 0 } else { x = 0, y = value }
	end
	-- ...and the blueprint side: given the dim that belongs on the SCROLL axis
	-- and the dim that belongs ACROSS it, which is the `width` and which the
	-- `height`. Every node this control builds sizes itself through this pair.
	local function widthOf(main: any, cross: any): any
		return if isX then main else cross
	end
	local function heightOf(main: any, cross: any): any
		return if isX then cross else main
	end

	local function itemExtentNow(): number
		return if itemExtentIsLive then (itemExtentSpec :: any):get() else itemExtentSpec
	end
	local function itemExtentIn(use: any): number
		return if itemExtentIsLive then use(itemExtentSpec) else itemExtentSpec
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
		return itemExtentNow() + rowGapNow()
	end
	local function pitchIn(use: any): number
		return itemExtentIn(use) + rowGapIn(use)
	end
	-- ...and the CONTENT EXTENT the canvas spans: N slots with NO trailing
	-- gutter, because the gap is BETWEEN rows exactly as a UIListLayout's padding
	-- is. An empty list spans nothing.
	local function contentIn(use: any, count: number): number
		if count <= 0 then
			return 0
		end
		return count * itemExtentIn(use) + (count - 1) * rowGapIn(use)
	end
	local function contentNow(): number
		local count = #(spec.rows:get() :: { any })
		if count <= 0 then
			return 0
		end
		return count * itemExtentNow() + (count - 1) * rowGapNow()
	end

	-- id -> path-pattern piece: a row hit path looks like
	-- <root>/<id>/Canvas/W/[<key>]/Row/Hit (the Canvas anchor is the full-extent
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
	-- THE SCREEN'S FOCUS GRAPH, handed over by the presenter through the
	-- contribution's `bindFocusGraph` (never by the consumer — constitution §13:
	-- one focus authority, and it is not the caller's to wire). Only the index
	-- focus policy needs it: every other focus flow in this control REPORTS a move
	-- the graph already made. Absent (a standalone headless mount), the policy
	-- still moves the LOGICAL focus and simply has no ring to move with it.
	local focusGraph: any = nil

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
	--[[ ── THE DECLARED SLOT, HANDED TO THE SOLVER (2026-08-13) ────────────────────
		This control makes the CONSUMER responsible for predicting its own row's
		extent — `index × itemExtent` is O(1) and exact only because that extent is
		one declared number — and for the whole life of the control nothing checked
		the prediction. The perf lab's own `rows.heightFor` is the case study: it
		learned the viewport width, then the type scale, then the theme insets, each
		one AFTER a device pass caught rows painting over each other, and never
		learned the accessibility text preference at all (at `preferredTextOffset`
		4/10/14 every row overflowed its 56px slot by 11/39/59px).

		SO THE ROW CARRIES ITS OWN DECLARATION DOWN TO THE ONE PLACE THAT KNOWS THE
		TRUTH. The extent is not knowable here — it is a function of the viewport,
		the typography scale, the theme metrics and the text preference, and the
		first two are not decided until a solve — so this is not a construction
		refusal but a fact the solver checks per solve and reports through
		`controller.diagnostics()` (the channel `tests/overflow_sweep.spec.luau`
		already fails the suite on).

		ONE TABLE FOR THE WHOLE LIST, not one per row: every field is a property of
		the LIST, and the row's own identity is already its node path (`…/W/[key]/
		Row/…`), which is what the finding is filed under. A row's marginal cost is
		one prop assignment. It is a memo only because `itemExtent` may be a
		Readable; a plain number resolves it once and never again.

		IT PUBLISHES THE DECLARED EXTENT, NEVER THE ROW'S CURRENT BOX — a hosted
		row-actions commit collapse drives one row's box down its own height ladder
		on purpose, and comparing against the box would make that animation shout. ]]
	local slotDeclaration = listScope:own(core:memo(function(use)
		return {
			list = id,
			axis = axis,
			extent = itemExtentIn(use),
			-- child 1 is the control's own full-row hit Button; the consumer's cell
			-- is everything from 2 on (a cell that is a `UI.When`/`UI.ForEach`
			-- splices several children in, and they all sit after the hit)
			contentFrom = 2,
		}
	end))
	--[[ scrollTop: the engine CanvasPosition MIRROR (native-substrate NS-A2). Fed
		by bindNativeScroll (engine observer) or a test; NEVER a hand-rolled offset.

		IT IS THE OFFSET ON THE LIST'S OWN AXIS — `CanvasPosition.Y` on
		`axis = "y"`, `CanvasPosition.X` on `axis = "x"`. The NAME is vertical and
		is kept anyway, deliberately: it is public API that consumers and tests
		read by name, and renaming it would be a breaking change this field does
		not need. Read it as "the offset from the start of the canvas". ]]
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

	-- the full virtual extent as a live fixed Dim: the ScrollView's single Canvas
	-- child is this big ALONG THE SCROLL AXIS, so the solver's scroll-axis sum ==
	-- the full virtual extent and the renderer pushes it as CanvasSize (native §6).
	-- Rows mount only in the window, but the canvas always spans the whole list.
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
		-- canvas offset of slot k is (k-1)*pitch, so both halves read the pitch
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

	-- ONE definition of a row's path shape under a given root (`{root}` is the
	-- standalone `/{id}` for the public form and the mounted ScrollView path for
	-- the screen-rooted one). Every caller that needs a row or hit path goes
	-- through here, so the ForEach's `W/[{key}]` convention (src/mount.luau) is
	-- written down exactly once.
	local function rowPathUnder(root: string, key: string): string
		return `{root}/Canvas/W/[{key}]/Row`
	end
	local function pathOf(key: string): string?
		for _, entry in windowItems:get() :: { any } do
			if entry.key == key then
				return rowPathUnder(`/{id}`, key)
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
		return rowPathUnder(root, key)
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

	-- keep-visible target: the canvas offset that brings row `index` fully into
	-- the viewport, minimal scroll both directions; nil when it is already in band
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
			itemExtentNow(),
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
		-- keep-visible: compute the target canvas offset and issue the framework's ONE
		-- programmatic scroll write through the bound controller (native §4). On
		-- the engine this moves CanvasPosition and echoes back to scrollTop; the
		-- fake target echoes synchronously, so the window materializes the row.
		-- Unbound: a no-op (a standalone control with no engine to scroll).
		local target = keepVisibleTarget(index)
		if target ~= nil and boundController ~= nil and boundScrollPath ~= nil then
			boundController.scrollTo(boundScrollPath, vec(target))
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

	--[[ ===== the INDEX focus policy (focusPolicy = "index") ====================
		Focus pins to the SLOT, not to the item. Everything below is allocated ONLY
		under that policy, so a default list is byte-identical to the pre-field
		control — no pin, no observers, no graph binding.

		THE PIN IS A (key, slot) PAIR, not a bare number. A lone slot cannot tell
		"the data moved under a still-focused row" (retarget) from "focus itself
		moved and the pin has not caught up yet" (do nothing) — and in a flush where
		BOTH the rows and the focused key were written, observer order between two
		signals is not something to bet a focus jump on. The pair makes the question
		answerable: the pin applies only while it still describes the focused row.
	]]
	local pinnedKey: string? = nil
	local pinnedSlot: number? = nil
	if focusPolicy == "index" then
		listScope:own(core:observe(focusedKey, function(key: string?)
			-- EVERY focus move re-pins, this policy's own retarget included. The
			-- retarget hands focus to whoever is AT the pinned slot, so it re-pins to
			-- the same number: idempotent by construction, which beats a suppression
			-- latch that a throw mid-flight would leave stuck (a stuck latch would
			-- freeze the pin on a stale slot and then drag focus around by it).
			pinnedSlot = if key ~= nil then (indexByKey:get() :: { [string]: number })[key] else nil
			pinnedKey = if pinnedSlot ~= nil then key else nil
		end))
		listScope:own(core:observe(indexByKey, function(map: { [string]: number })
			local focused = focusedKey:get() :: string?
			local slot = pinnedSlot
			-- THE PIN APPLIES ONLY WHILE IT STILL DESCRIBES THE FOCUSED ROW. That is
			-- what makes "focus itself just moved" (do nothing — the pin catches up
			-- on the next round) distinguishable from "the data moved under a still-
			-- focused row" (retarget). It is load-bearing in a real flush: a consumer
			-- that answers the SAME data update by focusing a row explicitly is
			-- notified before this observer, and without the pair its choice would be
			-- overwritten by the previous row's slot.
			if focused == nil or slot == nil or pinnedKey ~= focused then
				return
			end
			-- REMOVAL of the focused row lands here too, and asks for the same answer
			-- (whoever holds the slot now, clamped) — so it needs no branch of its
			-- own. In practice the shared nearest-survivor rule above has already
			-- moved focus and this observer returns at the pin check; the arithmetic
			-- below agrees with it either way, which is why the ordering of the two
			-- observers is not something this policy has to depend on.
			if map[focused] == slot then
				return -- the focused row still holds its slot
			end
			-- NEVER FIGHT A LIVE GESTURE. A drag in flight owns where the player is
			-- pointing; re-aiming the ring under it would move the drop target the
			-- press was about to commit to. The pin resumes on the next data change
			-- after the session ends.
			local reg = registry()
			if reg ~= nil and reg.isActive() then
				return
			end
			local items = spec.rows:get() :: { any }
			-- CLAMP ON SHRINK: the pinned slot may no longer exist
			local landing = math.min(slot, #items)
			local occupant = if landing >= 1 then items[landing] else nil
			if occupant == nil then
				return
			end
			local occupantKey = spec.key(occupant)
			if occupantKey == focused then
				return
			end
			-- FALL THROUGH TO THE ITEM when the slot's new occupant is not
			-- focus-eligible: parking the ring where Activate can do nothing is worse
			-- than the jump the policy exists to prevent.
			if spec.rowFocusable ~= nil and spec.rowFocusable(occupant) == false then
				return
			end
			-- BOTH HALVES OF FOCUS MOVE, or the player gets a split brain: the
			-- LOGICAL key (what keep-visible and the armed paradigm read) and the
			-- GRAPH (what paints the ring and what Activate dispatches against).
			-- This is an ordinary focus move — same keep-visible, same events, same
			-- ring-visibility origin (the policy never SUMMONS a ring a touch player
			-- put away; `focusOn` leaves the origin alone).
			--
			-- THE GRAPH MOVES ONLY IF IT WAS ON THE ROW WE ARE RETARGETING FROM
			-- (live canary, 2026-08-02). The two halves can legitimately be apart
			-- before a re-sort ever happens: a tap on a focus-INELIGIBLE row still
			-- activates and still sets the logical key, while `graph.focusOn` refuses
			-- it — so the ring is elsewhere, possibly on another control entirely.
			-- Yanking it into this list would be a focus move nobody asked for. The
			-- logical retarget happens either way; only the ring is conditional.
			local fromPath = hitPathOf(focused)
			local graphWasHere = focusGraph ~= nil and fromPath ~= nil and focusGraph.focused:get() == fromPath
			pinnedKey = occupantKey
			pinnedSlot = landing
			focusKey(occupantKey)
			local hitPath = hitPathOf(occupantKey)
			if graphWasHere and hitPath ~= nil then
				focusGraph.focusOn(hitPath)
			end
		end))
	end

	-- window-space pointer -> canvas offset. The solver arranges rows in the host's
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

	-- a pointer point (window space) -> the CANVAS offset along the scroll axis.
	-- `pointerMain` is the pointer's component on that axis: its y on a vertical
	-- list, its x on a horizontal one — the caller reads it through `mainOf`, so
	-- the two never disagree about which coordinate the rect is being compared to.
	local function canvasOffsetFor(pointerMain: number): number?
		local rect = hostScreenRect()
		if type(rect) ~= "table" then
			return nil
		end
		return pointerMain - mainOf(rect) + clampedTop:get()
	end

	-- the canvas offset the insertion LINE is drawn at for a 0-based slot: the
	-- middle of the gutter above it, so the hairline reads as "between these two
	-- rows" rather than as a lid on the lower one. Clamped into the content extent
	-- so the first and last boundaries stay inside the canvas the host clips to.
	-- At rowGap 0 this is `slot * itemExtent`, clamped exactly as before.
	local function slotBoundary(slot: number): number
		local gap = rowGapNow()
		return math.clamp(slot * pitchNow() - gap / 2, 0, contentNow())
	end

	-- the insertion slot for a canvas offset: the number of whole SLOTS before it,
	-- using each slot's MIDPOINT so the line snaps to the nearer boundary. Returns
	-- the 0-based insertion slot and its canvas boundary offset.
	local function insertSlotAt(canvasY: number): (number, number)
		local pitch = pitchNow()
		local count = #(spec.rows:get() :: { any })
		local slot = math.floor((canvasY + pitch / 2) / pitch)
		slot = math.clamp(slot, 0, count)
		return slot, slotBoundary(slot)
	end

	-- the drop line rides the PRESENTATION channel, not layout: it is mounted
	-- once at canvas offset 0 and translated along the scroll axis, so a 60 Hz
	-- drag costs one presentation write per move instead of a re-solve per move.
	-- Parked far BEFORE the canvas origin when idle (the scroll host clips it)
	-- rather than unmounted, so there is no structural churn on every pickup.
	local DROP_LINE_PARK = -10000
	local function writeDropLine(y: number?)
		local ctrl = boundController
		local host = boundScrollPath or mountedScrollPath
		if ctrl == nil or host == nil or type(ctrl.setPresentationTransform) ~= "function" then
			return
		end
		ctrl.setPresentationTransform(host .. "/Canvas/DropLine", vec(if y ~= nil then y else DROP_LINE_PARK))
	end

	-- ===== reorder ===========================================================
	local function indexOfKey(key: string): number?
		return (indexByKey:get() :: { [string]: number })[key]
	end

	--[[ HOISTED (parity round 3): this used to sit ~110 lines further down, and
		the per-row capability gates in `commitReorderAt` and `toggleGrab` need
		it. A local declared LATER in the file is NOT an upvalue — it binds a nil
		global and calls it, which is exactly
		`docs/lessons/later-locals-are-not-upvalues.md`, a trap this repo has now
		been bitten by five times. It depends only on `indexOfKey` and `spec`,
		both already in scope here. ]]
	local function itemForKey(key: string): any?
		local index = indexOfKey(key)
		if index == nil then
			return nil
		end
		return (spec.rows:get() :: { any })[index]
	end

	-- move `key` so it occupies 1-based index `to` in the resulting order. A
	-- no-op is SUPPRESSED: a drop that reproduces the current order must not emit
	-- a mutation nobody asked for (the mutation lifecycle applies — a reorder is
	-- a request, and pending never means success).
	local function commitReorderAt(key: string, to: number?)
		if spec.onReorder == nil or to == nil then
			return
		end
		-- THE FUNNEL. Every drop — pointer, gamepad grab, cross-container —
		-- lands here, so a pinned row is refused once rather than at each
		-- gesture's own entry point.
		if not rowCapability.allows(spec.rowMovable, itemForKey(key)) then
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

	-- POINTER commit: the insertion LINE decides, so the LEADING half of a row
	-- (its top on a vertical list, its left on a horizontal one) means "before it"
	-- and the trailing half means "after it". Removing the dragged row first
	-- shifts every later slot up by one, which is the whole of the
	-- full-list-slot → resulting-index conversion.
	local function commitReorderFromPointer(key: string, pointerMain: number)
		local canvasY = canvasOffsetFor(pointerMain)
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
				ctrl.setPresentationTransform(path, vec(value:get()))
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
				-- the release point's component on THIS list's scroll axis: the
				-- registry publishes both (`pointerX`/`pointerY`), so a horizontal
				-- list reads the one its slots are measured along.
				local releaseMain = if info ~= nil then (if isX then info.pointerX else info.pointerY) else nil
				if info ~= nil and info.mode == "pointer" and releaseMain ~= nil then
					commitReorderFromPointer(payload.key, releaseMain)
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

	--[[ THE MODEL IS 1-D AND STAYS 1-D. `input/autoscroll.luau` owns the
		band/dwell/ramp/clamp policy along ONE axis and answers a signed delta; it
		is not axis-aware and deliberately is not made so. A horizontal host feeds
		it TRANSPOSED numbers instead — the identical move the renderer's own
		scroll-chain autoscroll makes for an `axis = "x"` host
		(`render/renderer.luau`, "the model is written for the scroll axis as a 1-D
		problem"). One policy, two wirings, no second dwell machine.

		The BAND NAME is translated on the way out for exactly the reason this
		whole change exists: the model answers "top"/"bottom" because that is the
		vocabulary it was written in, and a horizontal list publishing "top" on
		`list.autoscroll` would be a lying name in a Signal a consumer paints a
		chevron from. "left"/"right" is the spelling the renderer already accepts
		for a horizontal host, so the two agree. ]]
	local function autoscrollPoint(point: any): any
		if point == nil or not isX then
			return point
		end
		return { x = point.y, y = point.x }
	end
	local function autoscrollRect(rect: any): any
		if rect == nil or not isX then
			return rect
		end
		return { x = rect.y, y = rect.x, w = rect.h, h = rect.w }
	end
	local function autoscrollBand(): string?
		local band = autoscrollModel :: any
		band = if band ~= nil then band:band() else nil
		if band == nil or not isX then
			return band
		end
		return if band == "top" then "left" else "right"
	end

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
			pointerPos = autoscrollPoint(reg.pointerPosition()),
			hostRect = autoscrollRect(hostRect),
			canvasPos = clampedTop:get(),
			maxScroll = maxTop(),
		})
		if step.delta ~= 0 then
			ctrl.scrollTo(host, vec(clampedTop:get() + step.delta))
			-- THE FRAME-ACCURATE RE-RESOLVE (SF-L2's correctness core): the rects
			-- the session hit-tests against are the solver's, shifted by the LIVE
			-- scroll offset — so re-running the hover immediately after the write,
			-- in this same frame, is enough. A tick-based re-resolve lags about two
			-- rows at the top speed.
			reg.refreshTargets()
		end
		local current = autoscrollState:get()
		local band = autoscrollBand()
		if current.state ~= step.state or current.band ~= band then
			autoscrollState:set({ state = step.state, band = band })
		end
		return step
	end

	-- ===== hosted row actions (design doc; see the header) ====================
	-- Everything in this section is inert on a list without `spec.rowActions`:
	-- the two plain tables below are the only allocations, they are PER LIST
	-- (never per row), and nothing reactive, no coordinator and no engine is
	-- constructed unless the feature is on.

	--[[ RETENTION POLICY, stated once so nothing has to infer it:
		  * ONE engine per row KEY, built at the moment that row's gesture first
		    resolves horizontal, kept for the life of the LIST — never rebuilt per
		    scroll pass, because a windowed-out row is coming back (that is what
		    virtualization is) and rebuilding would defeat the laziness this whole
		    design exists for. Leaving one behind is safe: any scroll closes the
		    engaged row through the shared coordinator before it can leave the
		    window.
		  * The cache is DROPPED WHOLESALE on a re-present (see
		    `hostedNoticeMount`), because every engine captured its row/tray paths
		    at build and those paths name the previous mount.
		  * Disposal otherwise rides the list scope (registered below):
		    `buildHosted` opens its own independent `core:scope()`, so nothing
		    else would ever free them. ]]
	local hostedEngines: { [string]: any } = {}
	--[[ key -> whatever `spec.rowActions(item)` answered, or `false` for "this
		row has no actions". Cached because the DECIDE-and-DECLINE half runs on
		every press (an unwrapped row must not hold the capture — see the
		dispatcher) while the BUILD half is deferred to the axis lock, and calling
		a consumer callback twice per gesture to answer the same question is a
		cost with no reason.

		CACHED AGAINST THE ITEM, NOT THE KEY ALONE. `spec.rowActions(item)` is a
		function of the item, and a list's items change under a stable key all the
		time — a row locks and unlocks, ownership transfers, a race finishes. A
		key-only cache froze the FIRST press's verdict forever: a row that
		answered nil while locked stayed declined for the rest of the session, and
		a row that lost its actions kept firing them. `hostedItemByKey` records
		which item each answer was derived from, and the rows observer below drops
		the answer AND the engine the moment that identity moves. ]]
	local hostedFieldsByKey: { [string]: any } = {}
	local hostedItemByKey: { [string]: any } = {}
	--[[ mounted hit path -> row key. NEVER parsed out of a path (a data key is
		arbitrary text, so a pattern over `[{key}]` is a guess about what a key may
		contain) — CONSTRUCTED from `windowItems`, which is already this control's
		one source of truth for "which rows are mounted" (`pathOf`/`mountedRowPath`
		derive from it too). Rebuilt only when that memo's identity changes, which
		its own `sameWindow` equality makes exactly "the key sequence changed", so
		a same-window scroll rebuilds nothing and a row costs no registration
		closure at all. ]]
	local hostedKeyByHitPath: { [string]: string } = {}
	local hostedMapWindow: any = nil
	local hostedMapRoot: string? = nil

	-- ONE open row across the whole list (row_actions' own policy object, the
	-- same one Table hands its wrapped rows), and the two signals the Task 4
	-- overlay + presentation slide read: WHICH row is engaged, and by HOW MANY
	-- px. `engagedOffset` is signed exactly as the engine's own offset is
	-- (negative = revealing the trailing edge).
	--[[ SWALLOW EXACTLY ONE ACTIVATE, on this path. THREE producers, one rule:
		  * a promoted pointer drag ends with an engine Activated on the origin row
		    (whichever side of InputEnded it lands), or every reorder would also
		    read as a tap on the row it started from;
		  * a HOSTED SWIPE ends the same way, and is armed at the axis lock rather
		    than at the release — see `hostedResolveAxis` (redteam NEW-1);
		  * a tap on an OPEN hosted row means "close the tray" and nothing else —
		    iOS parity, and the alternative is a swipe-then-tap opening whatever
		    the row's `onActivate` opens.
		WHAT MAY SPEND IT is as much of the rule as where it is armed (redteam
		NEW-2, and the lesson `docs/lessons/an-arm-set-by-a-gesture-must-name-what-
		may-spend-it.md`): all three producers are POINTER gestures leaving a
		POINTER Activated behind, so a DEVICE Activate (`meta.source == "action"`,
		no pointer-down anywhere) is never it and never consumed by it. Cleared by
		the one pointer Activate it swallows, by a cancel, by a device Activate, or
		by the next down.
		Declared here rather than beside its reorder producer because the hosted
		dispatcher below is textually earlier and writes it too. ]]
	local suppressActivatePath: string? = nil

	local hostedCoordinator: any = nil
	local engagedKey: any = nil
	local engagedOffset: any = nil
	--[[ the engine's commit collapse (the height the committing row's box is
		animating down to), forwarded verbatim and composed into that row's
		`rowExtentDim` below. `hostedCommitKey == nil` = no override anywhere.

		TWO SIGNALS, NOT ONE `{ key, px }` TABLE, and the reason is fine-grained
		reactivity: EVERY mounted row's height memo has to read the key (to answer
		"is it me?"), but only the ONE committing row ever reads the px. Split, a
		collapse spring's ~20 per-frame px writes invalidate exactly one memo; as a
		single table they would have invalidated every row in the window, every
		frame of every commit. ]]
	local hostedCommitKey: any = nil
	local hostedCommitPx: any = nil
	if hostedEnabled then
		hostedCoordinator = row_actions.newCoordinator(core)
		engagedKey = listScope:own(core:signal(nil :: string?))
		engagedOffset = listScope:own(core:signal(0))
		hostedCommitKey = listScope:own(core:signal(nil :: string?))
		hostedCommitPx = listScope:own(core:signal(0))
	end

	-- ONE row's height, commit override included: the row box itself and the
	-- overlay's tray group (which fills that same box) read it through here, so a
	-- collapsing row can never leave its tray standing at the old height.
	local function hostedItemExtentIn(use: any, key: string): number
		if use(hostedCommitKey) == key then
			return use(hostedCommitPx)
		end
		return itemExtentIn(use)
	end

	-- what the PRESENTER handed this list's contribution, held so a lazily-built
	-- engine can be given the identical handoffs the moment it exists. A hosted
	-- engine has no node of its own for the presenter's contribution walk to
	-- find, so the host relays (row_actions Task 2 report, "contribution seams").
	local hostedMotionClock: any = nil
	local hostedNow: any = nil
	local hostedActionSystem: any = nil
	local hostedFocusGraph: any = nil
	local hostedPresentModal: any = nil
	local hostedDismiss: any = nil

	-- WHERE THIS ROW'S TRAY WILL MOUNT (see the path contract at the top of the
	-- file). Keyed on the row, because the overlay is a keyed region; the
	-- `{Tray*}When/then/{Tray*}` tail is row_actions' own shape, since the trays
	-- under the group ARE that engine's own `trayViews`.
	-- this row's whole overlay region — the prefix everything a revealed tray
	-- mounts sits under, and therefore the test for "is that path inside THIS
	-- row's tray"
	local function hostedOverlayRowPath(key: string): string?
		local root = mountedScrollPath
		if root == nil then
			return nil
		end
		return `{root}/Canvas/{HOSTED_OVERLAY_ID}/[{key}]`
	end

	local function hostedTrayPath(key: string, edge: string): string?
		local region = hostedOverlayRowPath(key)
		if region == nil then
			return nil
		end
		local tray = if edge == "leading" then "TrayLeading" else "TrayTrailing"
		return `{region}/{HOSTED_TRAY_GROUP_ID}/{tray}When/then/{tray}`
	end

	local function hostedKeyOfHit(path: string): string?
		local root = mountedScrollPath
		if root == nil then
			return nil -- not presented: there are no mounted paths to answer with
		end
		local window = windowItems:get() :: { any }
		if hostedMapWindow ~= window or hostedMapRoot ~= root then
			hostedMapWindow = window
			hostedMapRoot = root
			table.clear(hostedKeyByHitPath)
			for _, entry in window do
				hostedKeyByHitPath[rowPathUnder(root, entry.key) .. "/Hit"] = entry.key
			end
		end
		return hostedKeyByHitPath[path]
	end

	--[[ THE LIVE GESTURE, owned by the host. `hostedActiveKey` is the row a press
		is currently on (down .. up/cancel) and `hostedPending` is that gesture
		before its axis has resolved.

		WHY THE KEY IS HELD RATHER THAN LOOKED UP PER EVENT. A row can UNMOUNT
		mid-gesture — scrolled out from under a held finger, or removed from the
		data outright — and the adapter's own remove-then-cancel arrives AFTER the
		row is gone from the window. A path lookup would answer nil at exactly that
		moment, so the engine would never be told its gesture died: its internal
		`drag` would stay non-nil forever, and the "a non-active row may not claim"
		rule below would then refuse that row every future press. Holding the key
		makes the cancel land on the right engine no matter what the tree did, and
		it is also strictly cheaper than the lookup it replaces. ]]
	local hostedActiveKey: string? = nil
	type HostedPending = {
		key: string,
		path: string,
		originPos: any,
		rectOf: (string) -> any,
		declined: boolean,
	}
	local hostedPending: HostedPending? = nil

	--[[ THE SLIDE SEAM. The engine owns the number; this control owns only WHO is
		engaged and BY HOW MUCH, because those two are what the shared tray overlay
		and the presentation write (Task 4) are derived from. Zero means closed:
		the row disengages, which is what unmounts the overlay.

		TWO ROWS SLIDE AT ONCE, routinely. Starting a swipe on row B claims the
		coordinator, which CLOSES row A — and A's close is a spring, so for the
		next several frames A is still writing a shrinking non-zero slide while B
		is writing a growing one. Last-writer-wins would hand the tray back and
		forth between them (A's spring steps AFTER B's move, every frame).

		THE RULE, exactly as implemented: the engaged row keeps writing its own
		pixels; any OTHER row may take the tray only when it is driving the live
		gesture (`hostedActiveKey`), or when nothing is engaged at all. The second
		clause is what lets a programmatic `_open` — no gesture anywhere — engage a
		row; the first is what stops a row that is merely FINISHING ITS CLOSE from
		taking the tray back off the row the player is actually dragging. The
		engine keeps counting down its own `offset` regardless — but `hostedWriteSlide`
		below paints only the ENGAGED row, so a row that loses engagement while its
		close spring is still in flight is NOT painted through the rest of that
		flight: it snaps flat instantly, on the very frame it stops being engaged
		(pinned by `tests/virtual_list_row_actions.spec.luau`'s "r2 is flat again").
		Device-pass rider: iOS animates the previously-open row closed under it;
		hosted mode jumps it. Not fixed here — recorded for the device pass.

		Both writes ride ONE transaction so a memo over the pair can never observe
		the new row against the previous row's pixels. ]]
	--[[ SUB-PIXEL IS HOME (device bug round 2026-08-12, finding C9b). This tested
		`px ~= 0`, and a position-domain spring only reaches its target at
		`spring.luau`'s 1e-3 epsilon — 35 frames after the row has visually arrived,
		measured. `row_actions.REVEAL_EPS` is the SAME half-pixel the engine's own
		tray reveal uses, and the two must be the same number: the engagement ending
		is what clears the presentation transform, drops the shared overlay entry and
		puts the focus ring back on the row (`hostedRestoreFocusOnDisengage`), and if
		the tray's focused button unmounted first the ring would have nowhere left to
		come back from. ]]
	local HOSTED_HOME_EPS: number = (row_actions :: any).REVEAL_EPS
	local function hostedApplySlide(key: string, px: number)
		if math.abs(px) >= HOSTED_HOME_EPS then
			local engaged = engagedKey:get()
			if engaged == key then
				engagedOffset:set(px)
			elseif engaged == nil or hostedActiveKey == key then
				core:transaction(function()
					engagedKey:set(key)
					engagedOffset:set(px)
				end)
			end
		elseif engagedKey:get() == key then
			core:transaction(function()
				engagedOffset:set(0)
				engagedKey:set(nil)
			end)
		end
	end

	--[[ THE SLIDE ITSELF — the PRESENTATION CHANNEL, not a layout prop (design §3;
		ADR-0022's presentation authority, the same door the DropLine and the drag
		ghost translate through). A disengaged row declares NO reactive offset prop
		at all — that is the whole point, and it is what the floor experiment
		measured: a per-row reactive `offsetX` cost +6.7-8.8% fling on rows nobody
		swiped. Here the engaged row is translated from OUTSIDE the tree, so a
		closed row's blueprint is byte-identical to a plain list's.

		WHY IT IS RE-ASSERTED EVERY FRAME (from `bundle.syncGeometry`) rather than
		only on the signal: the renderer FORGETS a path's transform when that path
		is removed (`lastTransform` is cleared on removal — renderer.luau), so a
		row that unmounts and comes back mid-slide would otherwise be left flat
		while this control still believed it was translated. The write is
		change-gated inside the renderer, so re-asserting an unchanged transform
		costs one comparison. ]]
	local hostedSlidPath: string? = nil
	local function hostedWriteSlide()
		local ctrl = boundController
		if ctrl == nil then
			return -- not presented yet; the next sync writes it
		end
		local key = engagedKey:get()
		local px = if key ~= nil then engagedOffset:get() else 0
		local path = if key ~= nil and px ~= 0 then mountedRowPath(key) else nil
		if hostedSlidPath ~= nil and hostedSlidPath ~= path then
			-- RESTORED, not zeroed: nil clears the presentation transform outright
			-- (and decrements the renderer's own live-presentation count), so a
			-- disengaged row is exactly as untransformed as one that never slid.
			ctrl.setPresentationTransform(hostedSlidPath, nil)
			hostedSlidPath = nil
		end
		if path == nil then
			return
		end
		ctrl.setPresentationTransform(path, { x = px, y = 0 })
		hostedSlidPath = path
	end

	local function hostedApplyCommitHeight(key: string, px: number?)
		if px == nil then
			if hostedCommitKey:get() == key then
				hostedCommitKey:set(nil)
			end
			return
		end
		core:transaction(function()
			hostedCommitKey:set(key)
			hostedCommitPx:set(px)
		end)
	end

	--[[ DOES THIS ROW HAVE ACTIONS AT ALL? Answered on every press (the capture
		verdict depends on it — an unwrapped row must not hold one), cached per
		key, and deliberately SEPARATE from building the engine: the build waits
		for the axis lock, this does not. `false` is the memo for "asked, and the
		answer was no". ]]
	local function hostedFieldsFor(key: string): any?
		local cached = hostedFieldsByKey[key]
		if cached ~= nil then
			return if cached == false then nil else cached
		end
		local item = itemForKey(key)
		if item == nil then
			return nil -- not in the data; nothing to cache either
		end
		hostedItemByKey[key] = item
		local fields = hostedRowActions(item)
		if fields ~= nil then
			specGuard.assertKnownKeys(
				"newVirtualList",
				fields,
				HOSTED_ROW_ACTIONS_KEYS,
				`spec.rowActions result (row '{key}')`
			)
			if fields.leading == nil and fields.trailing == nil then
				fields = nil -- declared, but with nothing on either edge
			end
		end
		hostedFieldsByKey[key] = if fields == nil then false else fields
		return fields
	end

	-- BUILD. Called at the AXIS LOCK, never at pointer-down (see the dispatcher):
	-- a vertical pan, a fling and a tap must all cost zero engines. Returns nil
	-- for a row with no actions, a row that is not mounted, and a list that has
	-- not been presented yet (no mounted paths to hand the engine).
	local function hostedEngineFor(key: string): any?
		local existing = hostedEngines[key]
		if existing ~= nil then
			return existing
		end
		local fields = hostedFieldsFor(key)
		if fields == nil then
			return nil
		end
		local rowPath = mountedRowPath(key)
		if rowPath == nil then
			return nil
		end
		local engine = row_actions.buildHosted(LuauUI, core, {
			-- unique per row: rows sharing a coordinator must carry unique ids
			-- (row_actions' own refusal), and the id is what a dump names
			id = `{id}:{key}`,
			leading = fields.leading,
			trailing = fields.trailing,
			fullSwipe = fields.fullSwipe,
			coordinator = hostedCoordinator,
			-- the live theme metrics the tray's own natural width is measured
			-- against (`buttonPad`/`buttonMinWidth`). Optional on both sides:
			-- absent, row_actions degrades to the neutral snapshot exactly as it
			-- does for a Table row built without one.
			env = spec.env,
			paths = {
				-- the row node, NOT the cell: it is what the engine reads a live
				-- rect from (the commit threshold is a fraction of the row width)
				-- and the prefix its "is focus still inside this row" test uses.
				-- Keyed, so it is stable across every scroll the row survives.
				content = rowPath,
				trayLeading = if fields.leading ~= nil then hostedTrayPath(key, "leading") else nil,
				trayTrailing = if fields.trailing ~= nil then hostedTrayPath(key, "trailing") else nil,
			},
			onSlide = function(px: number)
				hostedApplySlide(key, px)
			end,
			onCommitHeight = function(px: number?)
				hostedApplyCommitHeight(key, px)
			end,
		})
		-- relay every presenter handoff this list has already received: an engine
		-- born mid-session must be as wired as one born at present time
		if hostedMotionClock ~= nil then
			engine.bindMotion(hostedMotionClock, hostedNow)
		end
		if boundController ~= nil then
			engine.bindController(boundController)
		end
		if hostedActionSystem ~= nil then
			engine.bindActionSystem(hostedActionSystem)
		end
		if hostedFocusGraph ~= nil then
			engine.bindFocusGraph(hostedFocusGraph)
		end
		if hostedPresentModal ~= nil then
			engine.bindPresent(hostedPresentModal, hostedDismiss)
		end
		hostedEngines[key] = engine
		-- one geometry pass immediately, so the engine has whatever rects exist
		-- before the gesture it was built for is dispatched into it
		engine.syncGeometry()
		return engine
	end

	-- the engine the LIVE gesture belongs to, by held key — never by path lookup
	-- (see `hostedActiveKey`'s own comment: the row may already be unmounted)
	local function hostedLiveEngine(): any?
		return if hostedActiveKey ~= nil then hostedEngines[hostedActiveKey] else nil
	end

	--[[ ===== THE FOCUSED ROW'S KEY SURFACE (parity round 3, owed row 9) ========
		A row's Delete/menu bindings belong to its ENGINE (`row_actions.luau`'s
		`ensureKeysContext`), and a hosted engine is born at a pointer gesture's
		AXIS LOCK — so until this, a row a keyboard-only or pad-only player had
		merely focused had no engine and therefore no binding at all. Not Delete,
		and not ButtonX/Shift+Return either, which is a pad's whole route to a
		NON-destructive action. Row actions were reachable by pointer only.

		THE LIST STANDS IN FOR THE ENGINE THAT DOES NOT EXIST YET. One context per
		LIST (never per row), binding exactly `row_actions.ROW_KEYS` — the same
		table the engine binds, so a host's spelling cannot drift from the
		control's — and materialising that ONE row's engine on the press. The
		alternative considered and refused was building an engine when focus
		ARRIVES: that is one engine per row a d-pad passes over, which is the
		laziness this whole design exists for, spent on a walk that presses
		nothing.

		WHY IT CANNOT DOUBLE-FIRE: the engine's own context is `sink = true` at
		`ROW_KEY_PRIORITY`, this one sits strictly below, and the action system
		cuts every strictly-lower context once a sink consumes
		(`src/input/actions.luau`). So the moment a row HAS an engine with focus
		inside it, the engine answers and this context never sees the key.

		ENABLED BY FOCUS, BUILT BY THE PRESS: the context is enabled only while the
		ring sits on a row hit whose row declares actions, so a TextField elsewhere
		on the screen keeps Backspace and a plain list binds nothing at all. ]]
	local hostedKeysContext: any = nil
	-- the row the ring is on, IF that row declares actions. `hostedFieldsFor` is
	-- the same cached decide-and-decline the pointer dispatcher asks on every
	-- press — it calls the consumer's callback at most once per (key, item), and
	-- it never builds anything.
	local function hostedFocusedActionableKey(): string?
		if hostedFocusGraph == nil then
			return nil
		end
		local path = hostedFocusGraph.focused:get()
		if path == nil then
			return nil
		end
		local key = hostedKeyOfHit(path)
		if key == nil then
			return nil -- the ring is not on a row hit of this list
		end
		return if hostedFieldsFor(key) ~= nil then key else nil
	end
	local function hostedRouteKey(verb: (engine: any) -> ())
		local key = hostedFocusedActionableKey()
		if key == nil then
			return
		end
		local engine = hostedEngineFor(key)
		if engine ~= nil then
			verb(engine)
		end
	end
	local function hostedEnsureKeysContext()
		if hostedActionSystem == nil or hostedKeysContext ~= nil then
			return
		end
		local ctx = hostedActionSystem.createContext({
			name = `VirtualListRowKeys-{id}`,
			-- strictly below the engine's own — see the block comment above
			priority = row_actions.ROW_KEY_PRIORITY - 1,
			sink = true,
		})
		local deleteAction = ctx.createAction("RowActionsDelete", "Bool")
		for _, binding in row_actions.ROW_KEYS.delete do
			deleteAction.bind(binding)
		end
		deleteAction.onPressed(function()
			hostedRouteKey(function(engine)
				engine.commitDestructive()
			end)
		end)
		local menuAction = ctx.createAction("RowActionsMenu", "Bool")
		for _, binding in row_actions.ROW_KEYS.menu do
			menuAction.bind(binding)
		end
		menuAction.onPressed(function()
			hostedRouteKey(function(engine)
				engine.toggleMenu()
			end)
		end)
		ctx.setEnabled(false) -- enabled only while the ring is on an actionable row
		hostedKeysContext = ctx
		listScope:own(function()
			if hostedKeysContext ~= nil then
				hostedKeysContext.destroy()
				hostedKeysContext = nil
			end
		end)
	end
	-- the same deferral row_actions' own `syncKeysEnabled` makes (Task 11b): a
	-- list nobody has ever focused a row of builds no context at all.
	local function hostedSyncKeysEnabled()
		local on = hostedFocusedActionableKey() ~= nil
		if not on and hostedKeysContext == nil then
			return
		end
		hostedEnsureKeysContext()
		if hostedKeysContext ~= nil then
			hostedKeysContext.setEnabled(on)
		end
	end

	--[[ RESOLVE THE AXIS, then build. Identical rule to the composite's own
		`onPointerMove` and to `row_actions.composeWithReorder`'s `resolveAxis`: a
		pure function of dx/dy against the one lock constant, ties go VERTICAL so
		an ambiguous gesture is never taken away from the native scroll.

		This is where the engine is BORN. Deferring past the lock is the whole
		laziness story on touch: a phone user pans and flings THROUGH rows
		constantly, and every one of those gestures starts with a pointer-down on
		a row. Building there would have made "lazy" mean "lazy until the player
		scrolls once". A tap resolves the same way — it never crosses the lock, so
		it never builds anything either. ]]
	local function hostedResolveAxis(pending: HostedPending, pos: any)
		local dx, dy = pos.x - pending.originPos.x, pos.y - pending.originPos.y
		if dx * dx + dy * dy < row_actions_state.AXIS_LOCK_PX ^ 2 then
			return -- still accumulating toward the lock radius
		end
		if math.abs(dx) <= math.abs(dy) then
			pending.declined = true -- vertical: the native scroll owns this gesture
			return
		end
		local engine = hostedEngineFor(pending.key)
		if engine == nil then
			pending.declined = true
			return
		end
		--[[ REPLAY the down at the TRUE ORIGIN, marked `replayed`. The position
			has to be the origin (the engine's own clamp math measures every later
			move against it), but the TIME is now, not then — so `replayed = true`
			tells the engine's velocity tracker to skip its seed rather than record
			a hundreds-of-px jump over one frame. Exactly the affordance
			`composeWithReorder` uses for the identical reason. ]]
		local accepted = engine.pointerHandlers.onPointerDown(pending.path, {
			x = pending.originPos.x,
			y = pending.originPos.y,
			pointerType = pending.originPos.pointerType,
			replayed = true,
		}, pending.rectOf)
		if accepted == false then
			-- the engine REFUSED the gesture (a commit still in flight, or — the
			-- bug class C1 exists for — a previous gesture whose end it never
			-- heard, leaving its own `drag` live). Go inert rather than push moves
			-- into a drag this gesture does not own: reading a delta against some
			-- earlier gesture's origin is worse than doing nothing.
			pending.declined = true
			return
		end
		--[[ A HOSTED SWIPE IS UNDONE BY ITS OWN RELEASE, unless this arms here
			(redteam NEW-1, BLOCKER, 2026-08-13). A row's `Hit` is a real engine
			`GuiButton`, so the SAME pointer sequence that swipes it also ends in a
			native `Activated` on it — "whichever side of `InputEnded` it lands",
			the fact this file's own `suppressActivatePath` declaration already
			records. The arm existed only in `onPointerUp`'s UNRESOLVED branch (a
			tap on an already-open row): a gesture that resolved HORIZONTAL — every
			real swipe — armed nothing, so `handleActivate` fell straight past the
			`engaged == key` test (which answers only `meta.source == "action"`)
			and past the `suppressActivatePath == path` test, into `spec.onActivate`.
			Worse than the Table defect it mirrors, which was order-dependent:
			measured RED on BOTH orders, BOTH edges and BOTH pointer kinds — 8 of a
			12-combination matrix. On the shipped playlist analogue that reads
			"swipe to reveal Remove, and the track plays".

			ARMED AT THE LOCK, NOT AT THE RELEASE, exactly as `table.luau`'s host
			dispatcher arms it and for the identical reason: an `Activated` that
			lands BEFORE `InputEnded` has already been dispatched by the time any
			`onPointerUp` could arm anything. THIS is the lock — the one place this
			control decides a gesture went sideways — so there is no second copy of
			the rule to keep in step. Armed once and left armed through the release:
			it is cleared by the one POINTER Activate it swallows, by a cancel, by a
			device Activate, or by the next down. ]]
		suppressActivatePath = pending.path
		hostedPending = nil
	end

	--[[ CLOSE ANOTHER ROW — the ONE way this control ever puts a row away on
		behalf of a press or an Activate somewhere else. Both the tray and the
		row's own action MENU go, because they are independent state
		(`row_actions.luau`'s `menuOpen`, and the reason `newCoordinator.claim`
		calls `_closeMenu()` alongside `_close()` on the row it claims away from —
		redteam item 7). Without the menu half, a press on another row could leave
		the first row's menu — and its `transientScope` focus trap — armed over a
		row the player had already moved on from. The coordinator's claim covers
		this ONLY for a press that becomes a gesture; a tap, or a keyboard
		Activate, never claims anything, which is exactly when this runs. ]]
	local function hostedCloseRow(key: string)
		local engine = hostedEngines[key]
		if engine == nil then
			return
		end
		engine.close()
		engine._closeMenu()
	end

	--[[ THE ONE SHARED DISPATCHER. Four functions for the whole list, allocated
		once at build: every row's `Hit` carries the SAME four values, so a row
		mounting costs four static prop reads and no closure at all. The hit's own
		path is the routing key on the DOWN (the renderer passes it to every
		handler — render/renderer.luau's pointer wiring), which is exactly why this
		can be shared: a per-row closure would exist only to remember something the
		event already carries. Every later event of that gesture routes by the HELD
		key instead, so an unmounting row cannot lose its own cancel. ]]
	local hostedDispatch = {
		onPointerDown = function(path: string, pos: any, rectOf: (string) -> any): boolean?
			--[[ A NEW GESTURE MAKES ANY PENDING SUPPRESSION STALE. `suppressActivatePath`
				is armed at the axis lock (`hostedResolveAxis`, above) and on the up of
				a same-row re-grab (`onPointerUp`, below), and is normally cleared by
				the Activate that follows it — but a release that produces no Activated
				(e.g. the up lands off the translated `Hit`) leaves it armed with
				nothing left to clear it, and it would then swallow the NEXT Activate
				on that row.

				THIS IS THE WEAKEST OF THE FOUR CLEARS, NOT THE ONLY ONE, and the
				first draft of it carried a premise that is simply false (redteam
				NEW-2, 2026-08-13 — `table.luau`'s twin comment carries the identical
				correction, because it is one rule in two controls): "a real Activated
				always fires between a pointer-up and the next pointer-down, so a
				still-live suppression can never legitimately survive to see another
				down." TWO ACTIVATE PRODUCERS CARRY NO POINTER-DOWN AT ALL — an IAS
				device Activate (gamepad A / keyboard Return, `meta.source ==
				"action"`), and the minimum-target hit expander, a SEPARATE
				`GuiButton` whose press produces no pointer event on this row's `Hit`
				at all (`screen_target.luau`'s `pointerActivateMeta`). Either of them
				can reach `handleActivate` while an arm from a silently-ended swipe is
				still live, and be eaten by it. So the arm is cleared on a CANCEL too
				(`onPointerCancel`, below), and `handleActivate` refuses to spend it
				on a device Activate at all.

				The standing rule this cost us — an arm owes three answers where it is
				set: where it is armed, what clears it, and what class of event may
				spend it — is
				`docs/lessons/an-arm-set-by-a-gesture-must-name-what-may-spend-it.md`. ]]
			suppressActivatePath = nil
			local key = hostedKeyOfHit(path)
			if key == nil then
				return false
			end
			--[[ THE IN-LIST HALF OF OUTSIDE-DISMISS. The presenter's own
				`outsideDismiss` (contributed below) answers a tap OUTSIDE this
				list's subtree — but the whole list is one contribution here, so
				every row is "inside" it and a press on a DIFFERENT row would
				never reach that path. Table gets this free precisely because its
				rows each contribute separately; a hosted list has to say it.

				ABOVE EVERY DECLINE, and that placement is the fix for a real bug
				(review round 1, F1): a press on a row that CANNOT swipe — one
				whose `rowActions(item)` answered nil, or a pen press — still
				means "put the open tray away". It used to sit below both
				`return false`s, so a mixed list (some rows actionable, some not)
				left the tray open and the row slid when the player pressed an
				actionless row, with no way back except pressing an actionable
				one. Dismissal has nothing to do with whether THIS press can
				become a gesture.

				The press is NOT swallowed (the same `consume = false` rule the
				engine's own `outsideDismiss` carries, round 7's lesson: closing
				must not eat unrelated clicks), so pressing another row still
				selects/activates it exactly as it would with nothing open. The
				same-row half rides the UP instead — see `onPointerUp`, because
				at the down it is not yet knowable whether this is a tap or a
				re-grab of the open row.

				STILL NOT COVERED (review round 1, F2 — carried, and named here
				rather than left silent): a tap on the list's own EMPTY CANVAS,
				below the last row. iOS closes there. It reaches neither seam —
				the presenter's outside-tap test says "inside this contribution"
				for the whole list, and this dispatcher only ever hears from a row
				`Hit`. Closing it needs a hit surface over the empty canvas, and
				every shape of that is a real cost or a real risk: a permanent
				`Grip` is an instance per list this whole mission exists to avoid,
				and making the Canvas itself `active` would put an input-consuming
				node between a finger and the native ScrollingFrame — a touch-scroll
				regression only a device pass could clear. Deferred to the device
				pass with that evidence, not fixed blind. ]]
			local engaged = engagedKey:get()
			if engaged ~= nil and engaged ~= key then
				hostedCloseRow(engaged)
			end
			if pos.pointerType ~= nil and pos.pointerType ~= "mouse" and pos.pointerType ~= "touch" then
				-- PEN/STYLUS/anything else: declined HERE, at the down, exactly as
				-- row_actions' own `onPointerDown` declines it. Deferring the
				-- decision to the replayed down would have meant holding the
				-- capture for the whole gesture and building an engine for a
				-- pointer class the engine then refuses — a build that can never
				-- do anything. The shipping adapter only ever emits mouse/touch,
				-- so this is a guard against a future one, not a live repro.
				return false
			end
			if hostedFieldsFor(key) == nil then
				-- DECLINE: an unwrapped row must behave exactly like a row on a
				-- list with no `rowActions` at all, and that row holds no capture.
				-- Answered from the cached spec result, NOT by building anything.
				return false
			end
			hostedActiveKey = key
			hostedPending = {
				key = key,
				path = path,
				originPos = pos,
				rectOf = rectOf,
				declined = false,
			}
			-- TENTATIVE ACCEPT, the same verdict row_actions' own `onPointerDown`
			-- returns and for the same reason: the axis is genuinely unknown at
			-- down (dx = dy = 0), and the capture model offers no way to hand one
			-- back later — a vertical verdict is honored by going inert instead.
			return true
		end,
		onPointerMove = function(path: string, pos: any, rectOf: (string) -> any)
			local pending = hostedPending
			if pending ~= nil then
				if pending.declined then
					return
				end
				hostedResolveAxis(pending, pos)
				if hostedPending ~= nil then
					return -- still pending, or declined by this very move
				end
			end
			local engine = hostedLiveEngine()
			if engine ~= nil then
				engine.pointerHandlers.onPointerMove(path, pos, rectOf)
			end
		end,
		onPointerUp = function(path: string, pos: any, rectOf: (string) -> any)
			local engine = hostedLiveEngine()
			local key = hostedActiveKey
			local unresolved = hostedPending ~= nil
			-- CLEARED UNCONDITIONALLY, both of them: this gesture is over however
			-- it ends, and a stale active key would misroute the next one
			hostedPending = nil
			hostedActiveKey = nil
			if engine ~= nil and not unresolved then
				engine.pointerHandlers.onPointerUp(path, pos, rectOf)
				return
			end
			-- unresolved (a tap, or a gesture that never left the lock radius):
			-- the engine was never told a down, so it is never told an up. But a
			-- tap on the OPEN row's own slid content means close, and means ONLY
			-- close — the activate it would otherwise fire is swallowed.
			if unresolved and key ~= nil then
				local open = hostedEngines[key]
				if open ~= nil and open._isOpen() then
					open.close()
					suppressActivatePath = path
				end
			end
		end,
		onPointerCancel = function(path: string, reason: string?): boolean?
			local engine = hostedLiveEngine()
			local unresolved = hostedPending ~= nil
			hostedPending = nil
			hostedActiveKey = nil
			-- A CANCELLED GESTURE HAS NO ARTIFACT COMING (redteam NEW-2's rule,
			-- applied to this dispatcher too): the engine fires no `Activated` for
			-- a capture it took away, so an arm left standing here would be spent
			-- on the next producer that carries no pointer-down — an IAS device
			-- Activate, or the minimum-target hit expander's own `Activated` —
			-- costing the player a dead press on the row they just swiped. Same
			-- clear, same reason, as `table.luau`'s `hitOnPointerCancel`.
			suppressActivatePath = nil
			if engine ~= nil and not unresolved then
				return engine.pointerHandlers.onPointerCancel(path, reason)
			end
			return nil
		end,
	}

	-- the engaged row's engine, or nil — the one every list-level verb (Cancel
	-- now; the overlay and outside-tap in Task 4) routes through
	local function hostedEngagedEngine(): any?
		local key = if engagedKey ~= nil then engagedKey:get() else nil
		return if key ~= nil then hostedEngines[key] else nil
	end

	--[[ FREE ONE ROW'S ENGINE, and leave no state pointing at it. `dispose()`
		releases the coordinator claim and tears the engine's own scope down, but
		it deliberately does NOT run the close ladder (row_actions.luau's own
		`dispose`), so a row disposed while REVEALED would otherwise leave
		`engagedKey`/`engagedOffset` pinned to a row that no longer exists — a
		stuck-open tray over a dead row once Task 4 paints one. Clearing them here
		is the host's job, because they are the host's signals. ]]
	local function hostedDropEngine(key: string)
		local engine = hostedEngines[key]
		hostedEngines[key] = nil
		hostedFieldsByKey[key] = nil
		hostedItemByKey[key] = nil
		if hostedActiveKey == key then
			hostedActiveKey = nil
			hostedPending = nil
		end
		if engine ~= nil then
			engine.dispose()
		end
		if engagedKey:get() == key then
			core:transaction(function()
				engagedOffset:set(0)
				engagedKey:set(nil)
			end)
		end
		if hostedCommitKey:get() == key then
			hostedCommitKey:set(nil)
		end
		-- the row is gone or rebuilding: whatever it was translated by is not a
		-- fact about anything any more
		hostedWriteSlide()
	end

	--[[ A RE-PRESENT INVALIDATES EVERY ENGINE. Each one captured its row path and
		its tray paths at BUILD time (a hosted engine owns no nodes, so it can only
		be told where to look), and those strings name the mount it was built
		under. Dismiss the surface and present again — a new screen root, a
		different id, a keyed region remounting — and every one of them points at a
		tree that no longer exists: `controller.rectOf` answers nil, the commit
		threshold can never trip, and the tray can never be measured. Nothing about
		that is recoverable in place, and it does not need to be: engines are lazy,
		so dropping the cache costs one rebuild on the next real gesture. ]]
	--[[ Called from `buildFocusGroups` — the ONE place this control learns its
		mounted path, and the presenter runs it on every present and every
		refresh. That is what makes the drop correct: the root is compared and
		RECORDED here, so a re-mount is noticed on the very next refresh whether
		or not anyone ever touches the list again, and a run where the root has
		not moved costs one string compare (`hostedMapRoot` used to be written
		only by `hostedKeyOfHit`, so this cloned the engine table on every
		refresh until the next pointer-down). Recording it also invalidates the
		path map — the map is keyed on this same root, and a stale one would
		answer with paths from the previous mount. ]]
	local function hostedNoticeMount()
		local root = mountedScrollPath
		if root == hostedMapRoot then
			return
		end
		local previousRoot = hostedMapRoot
		hostedMapRoot = root
		hostedMapWindow = nil -- force the path map to rebuild under the new root
		if previousRoot == nil then
			return -- the very first mount: nothing was built under a previous root
		end
		for key in table.clone(hostedEngines) do
			hostedDropEngine(key)
		end
	end

	--[[ THE OVERLAY'S ITEM LIST: the at-most-one engaged row, as a keyed region's
		items (see the path contract at the top of the file for why a keyed region
		and not a `When`). Recomputes only when the engagement MOVES — never per
		drag pixel, which rides `engagedOffset` and the presentation channel. ]]
	local hostedOverlayItems: any = nil
	if hostedEnabled then
		hostedOverlayItems = listScope:own(core:memo(function(use)
			local key = use(engagedKey)
			if key == nil then
				return HOSTED_NO_OVERLAY
			end
			return { { key = key } }
		end))
	end

	--[[ WHEN THE TRAY GOES AWAY, THE RING COMES BACK TO ITS ROW (fix round 1, R1).
		A revealed tray's buttons are focusables that exist only while the row is
		engaged, so closing the row while one of them holds focus is a structural
		change under the ring. The graph's own answer for a grouped scope whose
		focused path vanished is `entryFocus`, which is the FIRST focusable in the
		WHOLE SCOPE (`focus_graph.replaceGroups`) — measured: focus on r2's Delete,
		close, and the ring lands on r1's hit; on a real screen, whatever sits at
		the top of the surface. That is a teleport away from what the player was
		doing, and it happens on every close path there is (a tray tap, Cancel, a
		scroll, another row).

		So the ring is moved HERE, while both the tray and the row are still
		mounted: the engagement leaving a row whose tray holds focus puts focus on
		THAT ROW'S OWN HIT — the thing the player was working on, and what "Up
		comes back" means once the tray is gone. Only when focus is genuinely
		inside the departing row's overlay region: a player whose ring is anywhere
		else (another control, another row) is never yanked. ]]
	local hostedFocusRow: string? = nil
	local function hostedRestoreFocusOnDisengage()
		local key = engagedKey:get()
		local previous = hostedFocusRow
		hostedFocusRow = key
		if previous == nil or previous == key then
			return
		end
		local graph = hostedFocusGraph
		if graph == nil then
			return
		end
		local focused = graph.focused:get()
		local region = hostedOverlayRowPath(previous)
		if focused == nil or region == nil or string.sub(focused, 1, #region + 1) ~= region .. "/" then
			return
		end
		local hit = hitPathOf(previous)
		if hit ~= nil then
			-- ...and if the row is no longer mounted (scrolled away while open)
			-- there is nothing to put the ring on, so the graph's own survivor
			-- rule is left to answer — the same fall-through every other
			-- unmount-under-focus takes.
			graph.focusOn(hit)
		end
	end

	if hostedEnabled then
		-- the slide, written the instant the engagement or the offset moves. Both
		-- signals are written inside ONE transaction by `hostedApplySlide`, so a
		-- move that changes both still resolves to a single pair of reads.
		listScope:own(core:observe(engagedKey, hostedWriteSlide))
		listScope:own(core:observe(engagedKey, hostedRestoreFocusOnDisengage))
		listScope:own(core:observe(engagedOffset, hostedWriteSlide))
		--[[ SCROLL CLOSES THE OPEN ROW (iOS parity; `newCoordinator.bindScroll`'s
			own rule). That coordinator method takes a render controller and a path
			and rides `observeScroll` — but this list ALREADY owns the engine's
			CanvasPosition mirror as a signal (`scrollTop`, written by
			`bindNativeScroll` or by a test), and it is live before any controller
			is bound. So the coordinator's own code path is reused verbatim against
			a one-method shim over that signal, rather than a second subscription to
			the same engine scroll that could arrive later, or not at all. ]]
		listScope:own(hostedCoordinator.bindScroll({
			observeScroll = function(_path: string, onScroll: (any) -> ()): () -> ()
				return core:observe(scrollTop, function(y: any)
					onScroll({ x = 0, y = y })
				end)
			end,
		}, ""))
		--[[ THE ITEM BEHIND A TOUCHED KEY MOVED. One observer answers both halves
			of the same question, because they have one root cause — a cached
			answer outliving the item it was derived from:
			  * the row LEFT the data. A deleted key never comes back (unlike a
			    windowed-out row, which keeps its engine on purpose), and an
			    engine still holding the tray for it would pin the overlay over a
			    row that is gone.
			  * the row's ITEM CHANGED under a stable key — locked to unlocked,
			    ownership transferred, a racer finished. `spec.rowActions(item)`
			    is a function of the item, so both the cached verdict and the
			    engine built from it are now answers to an old question.
			Dropping the engine covers both directions (a row that GAINS actions
			and a row that LOSES them), and it is lazy, so the cost is one rebuild
			on the next real gesture.

			An untouched list pays NOTHING here: `hostedItemByKey` is empty until
			a press, and `indexByKey` is a memo this control already recomputes on
			every data change for its own focus pruning. ]]
		listScope:own(core:observe(spec.rows, function(items: { any })
			if next(hostedItemByKey) == nil then
				return
			end
			local index = indexByKey:get() :: { [string]: number }
			for key, item in table.clone(hostedItemByKey) do
				local at = index[key]
				if at == nil or items[at] ~= item then
					hostedDropEngine(key)
				end
			end
		end))
		-- engines are independent scope roots (`buildHosted` opens its own), so
		-- the list is what frees them
		listScope:own(function()
			for key in table.clone(hostedEngines) do
				hostedDropEngine(key)
			end
		end)
	end

	-- ===== keyboard/gamepad plumbing (ui_todo §0; mirrors Table's seams) ======
	local function keyOfHit(path: string): string?
		return (string.match(path, hitPattern))
	end

	local function select(key: string)
		if selectionMode == "none" then
			return
		end
		-- PER-ROW OPT-OUT, AT THE FUNNEL. Every tap, arrow, pad press and
		-- programmatic call routes through here, which is why the gate is here
		-- and not on the affordance: `table.luau:1015-1030` records this
		-- control family being bitten by "a third, wholly separate way to
		-- start the identical reorder" that missed a guard.
		if not rowCapability.allows(spec.rowSelectable, itemForKey(key)) then
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
					-- POINTER: the live point on THIS list's scroll axis decides the
					-- predicted slot. The registry publishes both components; reading
					-- the wrong one would draw a drop line that tracks the finger
					-- across the list instead of along it.
				elseif mainOf(state) ~= nil then
					local canvasY = canvasOffsetFor(mainOf(state))
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
		if hostedEnabled then
			--[[ A TRAY BUTTON. Its Activate arrives at the LIST's contribution
				(the overlay is the list's own subtree, and a hosted engine has no
				node for the presenter to walk to), and the engine already knows
				how to route one: `_handleActivate` matches under exactly the tray
				path this control handed it at build. Asked FIRST, and only of the
				engaged row — a tray path is never a row hit, so this can never
				shadow a row activate. ]]
			local engine = hostedEngagedEngine()
			if engine ~= nil and engine._handleActivate(path, meta) then
				return true
			end
		end
		local key = keyOfHit(path)
		if key == nil then
			return false
		end
		if hostedEnabled then
			--[[ THE ACTIVATE HALF OF THE IN-LIST DISMISS (Task 4 re-review, K1 —
				the same gap the POINTER seam was fixed for in round 1, found again
				one seam over). A keyboard Return or a gamepad ButtonA arrives here
				and NOWHERE else: it produces no pointer-down, so the shared
				dispatcher's own close block never runs, and the presenter's
				outside-dismiss cannot see it either because every row is inside the
				ONE list contribution. (Standalone rows ARE per-row contributions and
				are immune. TABLE IS NOT — it contributes `focusGroups` for the whole
				table, so the same seam is open there; it is a separate pre-existing
				defect, tracked in the Task 5 report, and deliberately not fixed from
				here.) The open tray simply stayed up while the player operated a
				different row.

				Placed directly under `keyOfHit` for the same reason the pointer half
				sits above both declines: "is this Activate on a row of this list" is
				the only precondition a dismiss has.

				THE ENGAGED ROW'S OWN ACTIVATE (fix round 1, R3). A tap on the open
				row means "put it away, and only that" — the pointer seam says so on
				the UP via `suppressActivatePath`. But that mechanism is POINTER-ONLY:
				it is armed by `onPointerUp`, and a keyboard Return produces no
				pointer event at all, so the same row answered the same verb two
				different ways depending on the device — Return activated the row AND
				left the tray standing. `meta.source == "action"` is how this file
				already tells a non-pointer Activate from a tap (the arm branch
				below), so it is what discriminates here: a non-pointer Activate on
				the open row closes it and is swallowed, exactly as the tap is. A
				POINTER Activate on that row still belongs to the pointer seam, which
				has already decided it. ]]
			local engaged = engagedKey:get()
			if engaged ~= nil then
				if engaged ~= key then
					hostedCloseRow(engaged)
				elseif meta ~= nil and meta.source == "action" then
					hostedCloseRow(engaged)
					return true
				end
			end
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
		--[[ THE DRAG/SWIPE ARTIFACT, SWALLOWED — and only a POINTER may spend it
			(redteam NEW-2's rule, applied to this control too). A promoted drag,
			a hosted swipe and a tap on an open row are all POINTER gestures, and
			the stray `Activated` each leaves behind is a pointer's
			(`screen_target.luau`'s `pointerActivateMeta`: `source == "pointer"`).
			An IAS device Activate — gamepad A, keyboard Return, `source ==
			"action"` — cannot be that artifact under any ordering: it carries no
			pointer at all, and by the time the action system dispatches one the
			gesture's own `Activated` has either already arrived (and cleared this)
			or is never coming. Swallowing it cost a dead press on the row the
			player had just swiped. ]]
		if suppressActivatePath == path then
			local deviceActivate = meta ~= nil and meta.source == "action"
			suppressActivatePath = nil
			if not deviceActivate then
				return true
			end
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
		-- a PINNED row never arms: arming it would put the player in a drag
		-- they can never legally drop, which is a worse outcome than refusing
		-- the grab outright.
		if not rowCapability.allows(spec.rowMovable, itemForKey(target)) then
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
		--[[ THE TWO DIRECTIONS THAT STEP ARE THE LIST'S OWN AXIS. Up/Down on a
			vertical list, Left/Right on a horizontal one — the same pair the
			contributed focus group declares below, because the armed cursor and
			the focus ring must walk the same order (constitution §9: ONE focus
			map, read two ways). The ORTHOGONAL pair is consumed and does nothing:
			an armed row does not wander across the list. ]]
		local forward = if isX then "right" else "down"
		local backward = if isX then "left" else "up"
		if direction ~= forward and direction ~= backward then
			return true -- consumed: an armed row does not wander off its own axis
		end
		local delta = if direction == forward then 1 else -1
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
		if hostedEnabled then
			-- an engaged row owns Cancel first: ButtonB over a revealed tray means
			-- "put it back", and the engine answers false with nothing open so
			-- Cancel still falls through to the armed session / the surface
			local engine = hostedEngagedEngine()
			if engine ~= nil and engine.handleCancel(_focused) then
				return true
			end
		end
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
		if hostedEnabled then
			-- the one place this control learns it has been (re-)mounted, and
			-- therefore the one place a hosted engine's captured paths can be
			-- known stale (see `hostedNoticeMount`)
			hostedNoticeMount()
		end
		local order: { any } = {}
		--[[ THE REVEALED TRAY'S BUTTONS, collected on the way past the overlay
			(Task 5 parity; Task 4 carried item 1). A CONTRIBUTION OWNS ITS SUBTREE'S
			FOCUS: `focus_map.autoGroups` emits this control's groups and does NOT
			descend into it, so a focusable this function never names is unreachable
			by Tab AND by the d-pad. Standalone rows get their trays into the map for
			free — nobody contributes for them, so the presenter's own document walk
			finds the buttons. (TABLE DOES NOT: it contributes `focusGroups` whose
			walk stops at each Row node, so a Table tray's buttons land in no group
			either. That is a pre-existing defect of Table's own focus contribution,
			named in the Task 5 report and deliberately not fixed from here.) A
			hosted tray lives inside the LIST's contribution, and until now the list
			named only row hits: a player could swipe a row open with a finger and
			then have no keyboard or gamepad way to reach the action they revealed. ]]
		local hostedTrayOrder: { string } = {}
		local hostedOverlayPath: string? = if hostedEnabled and mountedScrollPath ~= nil
			then `{mountedScrollPath}/Canvas/{HOSTED_OVERLAY_ID}`
			else nil
		local function walk(node: any)
			if hostedOverlayPath ~= nil and node.path == hostedOverlayPath then
				collectTrayFocusables(node, hostedTrayOrder)
				return -- the overlay holds no row hits; its buttons are collected
			end
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
		if #order == 0 and #hostedTrayOrder == 0 then
			return {}
		end
		--[[ THE ROW GROUP, exactly as it always was — plus, while a tray is
			revealed, ONE EXIT INTO IT. (A tray can only exist on a VERTICAL list —
			`rowActions` is refused on `axis = "x"` at construction — so every
			sentence in this block and the two below is about `axis = "y"`; a
			horizontal list emits the row group alone.) The tray is a SECOND group
			and never members
			of this one: this group is `axis = "vertical"` there, and splicing a
			horizontal strip of buttons into it made Left/Right dead on a
			two-action tray and made Down walk visually RIGHTWARD — the precise
			defect `focus_map.luau`'s own layout-aware runs exist to prevent
			("an HStack row of focusables navigates HORIZONTALLY").

			THE EXIT IS THE EDGE THE TRAY IS ON: a trailing tray is revealed at the
			row's right, so Right enters it; a leading tray at the left, so Left
			does. Both are ORTHOGONAL to this group's own axis, which is what makes
			them reachable at all (`focus_graph.navigateDirection`: an orthogonal
			press consults the exit map). While a tray is revealed it WINS its own
			edge over an author's own `navigation.exit` for that one direction —
			see the block comment below for the full rationale and the two
			rejected alternatives. ]]
		local rowExit: any = navigation.exit
		local rowEntry: any = navigation.entry or "nearest"
		local trayExit: any = nil
		local trayIsLeading = false
		if #hostedTrayOrder > 0 then
			local engaged = engagedKey:get()
			local leading = if engaged ~= nil then hostedTrayPath(engaged, "leading") else nil
			for _, path in hostedTrayOrder do
				if leading ~= nil and string.sub(path, 1, #leading) == leading then
					trayIsLeading = true
					break
				end
			end
			--[[ THE REVEALED TRAY WINS ITS OWN EDGE, and an author's `navigation.exit`
				for that direction is suspended for exactly as long as the tray is up
				(review round 2, X1).

				The alternative — letting the author's exit stand — was the first
				draft, and it is a trap: a list that declares `exit.right` (a very
				ordinary thing, "Right leaves this list for the detail panel") would
				make a revealed tray COMPLETELY unreachable by d-pad, because a
				contained group has no other way in. The player would swipe a row
				open with a finger and then have no non-pointer way to press what
				they revealed — the same defect this whole traversal fix exists to
				remove, reintroduced by an author doing nothing wrong.

				So the precedence is stated the way a modal's is: a tray is
				transient, player-invoked and momentary, and while it is up it owns
				the one direction that reaches it. The author's exit is not
				overwritten anywhere — it is rebuilt from `navigation.exit` on the
				very next refresh, so the frame the tray closes is the frame Right
				means "leave the list" again. Every OTHER direction the author
				declared keeps working the whole time.

				(The two rejected candidates, for the record: falling back to another
				free orthogonal direction makes the entry direction depend on what
				the author happened to declare, so no player could learn it; a
				build-time error refuses a combination that is perfectly sensible —
				and would fire on a list that never reveals a tray at all.) ]]
			local merged: any = if navigation.exit ~= nil then table.clone(navigation.exit) else {}
			if trayIsLeading then
				merged.left = hostedTrayGroupName
				trayExit = { right = focusGroupName }
			else
				merged.right = hostedTrayGroupName
				trayExit = { left = focusGroupName }
			end
			rowExit = merged
			--[[ ...and COMING BACK lands on the row the tray belongs to. Leaving the
				tray is an orthogonal entry into this group, so the entry POLICY
				decides where it lands — and "nearest" would use the tray button's own
				index (1) and drop the player on the first row of the WINDOW, a
				teleport away from the row they were working on. "restore" is
				remembered per group (`focus_graph.recordFocus`) and survives the
				per-refresh `replaceGroups`, so it is exactly the row focus left from.
				Only while a tray is revealed, and only when the author declared no
				entry of their own. ]]
			if navigation.entry == nil then
				rowEntry = "restore"
			end
		end
		--[[ THE GROUP'S AXIS IS THE LIST'S AXIS — the one line that makes arrows,
			the D-pad and `navigateIntercept` agree about which way this list runs.
			The ORDER is untouched: it is the same document-order walk of the same
			mounted row hits, so there is ONE focus map here and the axis only says
			how to read it (constitution §9). A second order — "rows down, and also
			rows right" — is precisely what this must not build. ]]
		local rowGroup: any = {
			name = focusGroupName,
			axis = if isX then "horizontal" else "vertical",
			entry = rowEntry,
			wrap = navigation.wrap,
			containment = navigation.containment,
			exit = rowExit,
			order = order,
		}
		if #hostedTrayOrder == 0 then
			return if #order == 0 then {} else { rowGroup }
		end
		--[[ THE REVEALED TRAY: its own HORIZONTAL group, CONTAINED (fix round 1,
			R2). Left/Right step between the actions — the traversal a strip of
			buttons must have, and the one a multi-action tray had none of while its
			buttons sat in the vertical row group.

			ITS ONLY EXIT IS BACK TOWARD THE ROW, in the direction the row is (out
			of a trailing tray that is Left; out of a leading tray, Right), landing
			on the engaged row through the `entry = "restore"` above.

			NO up/down exit, DELIBERATELY, and this is a considered deviation from
			the review's suggested shape. An exit along the ROW group's own axis
			bypasses its entry policy entirely (`focus_graph.enterGroup`: "entry
			along the group's own axis lands at the NEAR END"), so `exit.down` would
			put the player on the FIRST row of the window and `exit.up` on the last
			— reintroducing, by a second route, exactly the teleport R1 is about.
			Contained instead: Up/Down inside a revealed tray do nothing, and the
			two ways out are the way in (Left/Right) and Cancel, which closes the
			tray and returns focus to the row.

			THE GROUP ARRAY IS ORDERED BY THE EDGE, because an uncontained group's
			undeclared direction falls through the array in order
			(`focus_graph.exitFrom`): with the tray always last, Right out of a row
			reached a LEADING tray — on the wrong side of the row — for want of any
			other group to fall through to. Sitting the tray on the side of the row
			group that matches the edge it is painted on makes the fallthrough agree
			with the exit map instead of contradicting it. ]]
		local trayGroup: any = {
			name = hostedTrayGroupName,
			axis = "horizontal",
			entry = "nearest",
			containment = true,
			exit = trayExit,
			order = hostedTrayOrder,
		}
		--[[ A ROW GROUP WITH NOTHING IN IT IS NOT EMITTED (review round 2, X2). The
			early-out above used to be "no rows AND no tray", which made an
			empty-order group emittable the moment a tray was up with no row hit
			mounted at all. Nothing reaches that today — an engagement cannot
			outlive its own row's data, and a windowed list with rows always mounts
			some — but an empty `order` is a shape no consumer of this map should
			have to think about, and refusing to emit one costs a comparison. ]]
		if #order == 0 then
			return { trayGroup }
		end
		if trayIsLeading then
			return { trayGroup, rowGroup }
		end
		return { rowGroup, trayGroup }
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
			scrollTop:set(mainOf(pos))
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
	-- the start" and the like; keep-visible uses keepVisibleTarget/focusKey
	-- internally. The argument is the offset along the LIST'S OWN AXIS — the
	-- canvas y on `axis = "y"`, the canvas x on `axis = "x"` — and the parameter
	-- is named `offset` rather than `y` so a horizontal caller is not misled.
	local function scrollTo(controller: any, offset: number)
		local ctrl = controller or boundController
		local path = boundScrollPath or mountedScrollPath
		if ctrl ~= nil and path ~= nil then
			ctrl.scrollTo(path, vec(math.clamp(offset, 0, maxTop())))
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
	-- on the live adapter). Its single child is the Canvas anchor, which spans the
	-- FULL virtual extent along the scroll axis and fills across it; the windowed
	-- rows sit at absolute canvas offsets inside it.
	local canvasChildren: { any } = {
		UI.ForEach({
			id = "W",
			items = windowItems,
			key = function(entry: any)
				return entry.key
			end,
			row = function(entry: any, itemScope: any)
				-- per-row placement memo at the ABSOLUTE CANVAS offset
				-- (index-1)*pitch along the scroll axis — engine-independent,
				-- so a scroll never re-arranges it (the engine translates via
				-- CanvasPosition). Depends only on the index (and the one
				-- uniform item extent), not the scroll: a same-window scroll
				-- delta is zero writes. Owned by the item scope, so it dies
				-- with its row.
				local slotOffset = itemScope:own(core:memo(function(use)
					local index = (use(indexByKey) :: { [string]: number })[entry.key]
					if index == nil then
						return 0 -- row is leaving; the unmount is in flight
					end
					-- the SLOT's LEADING edge: the gutter belongs to the
					-- space between slots, never to the row that follows it
					return (index - 1) * pitchIn(use)
				end))
				--[[ THE ROW BOX. A plain list builds today's memo, unchanged and
					unconditional; a `rowActions` list builds one that also composes
					the commit collapse (the engine's own height ladder, arriving
					through `onCommitHeight`) for the ONE row committing. STATIC on
					`hostedEnabled` — the branch is chosen at build, so a plain
					list's memo body is byte-identical to what it always was, and
					every row on a hosted list reads exactly one extra signal (the
					commit KEY; the px is only read by the row it names — see
					`hostedItemExtentIn`). ]]
				local rowExtentDim = itemScope:own(core:memo(if hostedEnabled
					then function(use)
						return { type = "fixed", px = hostedItemExtentIn(use, entry.key) }
					end
					else function(use)
						return { type = "fixed", px = itemExtentIn(use) }
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
				-- selection off — or with `selectionPaint = "none"`, which keeps the
				-- state and drops only its paint — declares nothing here, and its
				-- rows are byte-identical.
				local hitProps: any = {
					id = "Hit",
					label = "",
					selected = if selectionMode == "none" or selectionPaint == "none"
						then nil
						else selectedMemo(entry.key, itemScope),
					focusable = true,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
				}
				if hostedEnabled then
					-- HOSTED ROW ACTIONS: the row's whole marginal cost, and it is
					-- four prop assignments. The VALUES are the SAME four shared
					-- functions for every row on the list — no closure, no memo, no
					-- wrapper node, and no registration hook either (the path -> key
					-- map is derived from `windowItems`, which already knows exactly
					-- which rows are mounted). A list without `spec.rowActions`
					-- never reaches this branch and builds the Hit it always did,
					-- prop for prop.
					hitProps.onPointerDown = hostedDispatch.onPointerDown
					hitProps.onPointerMove = hostedDispatch.onPointerMove
					hitProps.onPointerUp = hostedDispatch.onPointerUp
					hitProps.onPointerCancel = hostedDispatch.onPointerCancel
				end
				local hit = UI.Button(hitProps)
				if reorderable then
					hit = UI.draggable(hit, {
						payload = { kind = REORDER_KIND, key = entry.key, list = id },
						dragMotion = if reorderMotion == "instant" then "object" else reorderMotion,
						-- TOUCH DECLINES so the native ScrollingFrame keeps the pan
						-- (fighting engine momentum scroll is never winnable). Touch
						-- reaches reorder through the grab verbs — Table's precedent,
						-- which shipped the same split for the same reason.
						declineTouch = true,
						--[[ A WINDOWED-OUT ROW IS NOT A REMOVED ROW. This list unmounts
							rows it is still holding — that is what virtualization is — and
							a reorder drag deliberately SCROLLS the list, so the row being
							dragged is routinely the one that leaves the window. Without
							this, its own drag would cancel itself the moment it scrolled
							past the edge. Everything hand-authored keeps the safe default
							(vanish = end the drag); the list is the one thing that knows
							its rows come back. ]]
						recycled = true,
					})
				end
				if rowsAreTargets then
					hit = UI.dropTarget(hit, {
						accepts = rowAccepts(entry.key),
						onDrop = rowOnDrop(entry.key),
					})
				end
				-- ONE fresh cross-axis fill for this row, handed to whichever of the
				-- two dims the axis puts it on (the other takes `rowExtentDim`), so a
				-- row allocates exactly the one dim table it always did
				local rowCross = fill()
				--[[ THE ROW NODE. `anchor = "topLeft"` and the offset prop the
						axis chooses: `offsetY` places a row down a vertical canvas,
						`offsetX` places an item across a horizontal one. Both are
						ARRANGE-ONLY anchor props (blueprint_schema), so a slot move
						re-arranges one node without re-measuring it — the property
						this control's windowing has always depended on, on either
						axis. The item is `itemExtent` along the scroll axis and FILLS
						across it, which is what makes the canvas's own cross-axis fill
						the item's cross-axis size. ]]
				return UI.ZStack({
					id = "Row",
					anchor = "topLeft",
					-- what this row was PROMISED to be (see `slotDeclaration`): the
					-- solver compares the cell's own measure against it and names both
					-- numbers when the promise is not kept
					virtualSlot = slotDeclaration,
					offsetY = if isX then nil else slotOffset,
					offsetX = if isX then slotOffset else nil,
					width = widthOf(rowExtentDim, rowCross),
					height = heightOf(rowExtentDim, rowCross),
					children = { hit, spec.cell(entry.item, { scope = itemScope }) },
				})
			end,
		}),
	}
	if hostedEnabled then
		--[[ THE ONE SHARED TRAY OVERLAY (design §4; the path contract at the top of
			this file). AFTER the rows, so the revealed tray buttons sit above the
			row that slid off them and are natively tappable — the whole reason the
			overlay lives in the canvas rather than over the ScrollView.

			It carries NO paint of its own: the group is a bare Anchor (never an
			Active hit target on the live adapter — only Buttons and Grips are), so
			the strip it spans over the un-slid part of the row swallows nothing.

			The trays under it are the ENGINE's own `trayViews` — the same
			blueprints, reveal `When`s included, that a standalone row parents under
			its own root. Nothing about a tray is re-authored here, which is why the
			compactLabel ladder, the destructive role, the icons and the
			stretch-in width props are the same in both modes by construction. ]]
		table.insert(
			canvasChildren,
			UI.ForEach({
				id = HOSTED_OVERLAY_ID,
				items = hostedOverlayItems,
				key = function(entry: any)
					return entry.key
				end,
				row = function(entry: any, itemScope: any)
					local engine = hostedEngines[entry.key]
					-- VERTICAL ONLY, and unconditionally so: this whole branch is
					-- under `hostedEnabled`, which `axis = "x"` refuses at
					-- construction (see the header). `offsetY` and the fill width are
					-- therefore facts, not an axis choice left unmade.
					return UI.Anchor({
						id = HOSTED_TRAY_GROUP_ID,
						anchor = "topLeft",
						-- the engaged row's own canvas offset — the SAME slot
						-- arithmetic the row itself uses, read from the same memo,
						-- so the tray cannot drift from the row by a gap
						offsetY = itemScope:own(core:memo(function(use)
							local index = (use(indexByKey) :: { [string]: number })[entry.key]
							if index == nil then
								return 0
							end
							return (index - 1) * pitchIn(use)
						end)),
						width = { type = "fill", weight = 1 },
						-- ...and the row's own height, commit collapse included, so
						-- a committing row's tray shrinks with it
						height = itemScope:own(core:memo(function(use)
							return { type = "fixed", px = hostedItemExtentIn(use, entry.key) }
						end)),
						children = if engine ~= nil then engine.trayViews else {},
					})
				end,
			})
		)
	end
	if reorderable then
		-- the insertion indicator: one hairline, parked off-canvas until a row is
		-- lifted, translated by the presentation channel while it is.
		-- Its THICKNESS is the SHARED drop-line metric
		-- (`controls.table.indicatorThickness`, documented in the snapshot as
		-- "resize preview + drop line"): two list constructs drawing the same
		-- affordance at two thicknesses would be a theming bug, so they read one
		-- number. Thickness lands on the SCROLL axis and the indicator fills across
		-- it — a hairline lying across a vertical list, standing upright in a
		-- horizontal one.
		local lineThickness: any = { type = "fixed", px = "controls.table.indicatorThickness" }
		table.insert(
			canvasChildren,
			UI.Box({
				id = "DropLine",
				anchor = "topLeft",
				surface = "accent",
				width = widthOf(lineThickness, fill()),
				height = heightOf(lineThickness, fill()),
				offsetY = if isX then nil else DROP_LINE_PARK,
				offsetX = if isX then DROP_LINE_PARK else nil,
			})
		)
	end

	-- a LIVE viewport hands the host a Readable<dim> (dims are reactive,
	-- dirty=measure), so the painted box re-solves with the same number the
	-- windowing math reads. It sits on the SCROLL AXIS; the cross axis is
	-- `spec.width` on a vertical list (refused on a horizontal one — see the
	-- construction check) and fills otherwise.
	local viewportDim: any = if viewportIsLive
		then listScope:own(core:memo(function(use)
			return { type = "fixed", px = viewportIn(use) }
		end))
		else { type = "fixed", px = viewportSpec }
	local crossDim: any = spec.width or fill()
	local canvasCross = fill()
	local blueprint = UI.ScrollView({
		id = id,
		width = widthOf(viewportDim, crossDim),
		height = heightOf(viewportDim, crossDim),
		axis = axis,
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
				-- the FULL virtual extent (a live fixed Dim) along the scroll axis:
				-- this single child is what the solver sums into
				-- contentSize == CanvasSize (native §6). Across the axis it FILLS, so
				-- the canvas is exactly as wide (or as tall) as the viewport and the
				-- items inherit that through their own cross-axis fill.
				width = widthOf(canvasDim, canvasCross),
				height = heightOf(canvasDim, canvasCross),
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
			if hostedEnabled then
				for _, engine in hostedEngines do
					engine.bindController(controller)
				end
				-- a controller arriving (or re-arriving, after a re-present) is the
				-- first moment the slide can be painted at all
				hostedWriteSlide()
			end
		end,
	}
	if focusPolicy == "index" or hostedEnabled then
		-- the index policy is the one flow here that MOVES focus instead of
		-- reporting a move; a default list asks for nothing and is bound nothing.
		-- A hosted list ALSO relays the graph, because a hosted engine has no
		-- node of its own for the presenter's contribution walk to reach.
		bundle.bindFocusGraph = function(graph: any)
			if focusPolicy == "index" then
				focusGraph = graph
			end
			if hostedEnabled then
				hostedFocusGraph = graph
				for _, engine in hostedEngines do
					engine.bindFocusGraph(graph)
				end
				-- ...and the list's own stand-in follows the ring exactly as an
				-- engine's does (row_actions' `bindFocusGraph`, same shape)
				listScope:own(core:observe(graph.focused, hostedSyncKeysEnabled))
				hostedSyncKeysEnabled()
			end
		end
	end
	if hostedEnabled then
		--[[ THE RELAY (see `hostedEngineFor`). Every one of these is a handoff
			the presenter makes to a mounted contribution — and a hosted engine is
			deliberately node-less, so the LIST's contribution takes delivery and
			passes it on: to every engine that already exists now, and to every
			engine built later, at its own construction. Held in the locals above
			so the two paths can never diverge. ]]
		bundle.bindMotion = function(clock: any, now: (() -> number)?)
			hostedMotionClock = clock
			hostedNow = now
			for _, engine in hostedEngines do
				engine.bindMotion(clock, now)
			end
		end
		bundle.bindActionSystem = function(actionSystem: any)
			hostedActionSystem = actionSystem
			for _, engine in hostedEngines do
				engine.bindActionSystem(actionSystem)
			end
			-- the list's own stand-in needs one too (it may arrive after the focus
			-- graph did, in which case the ring is already where it is)
			hostedSyncKeysEnabled()
		end
		bundle.bindPresent = function(presentModal: any, dismiss: any)
			hostedPresentModal = presentModal
			hostedDismiss = dismiss
			for _, engine in hostedEngines do
				engine.bindPresent(presentModal, dismiss)
			end
		end
		-- the per-frame geometry pass a hosted engine needs to measure its tray
		-- naturals and the live row rect. Broadcast, idempotent, and cheap: the
		-- engines that exist are the rows a player has actually touched.
		bundle.syncGeometry = function()
			for _, engine in hostedEngines do
				engine.syncGeometry()
			end
			-- ...and re-assert the slide, which is how it survives a row that
			-- unmounted and came back (see `hostedWriteSlide`'s own comment)
			hostedWriteSlide()
		end
		--[[ OUTSIDE-TAP CLOSES THE OPEN ROW — the OUT-of-list half. The presenter
			compares the tapped path against this CONTRIBUTION's path (Zone A over
			its solved rects, and a synthesized catcher for empty space), so
			"outside" here means outside the whole list: a tap on a sibling
			control, or on nothing at all, closes the tray. The in-list half —
			another row, or the open row's own slid content — cannot come through
			here for the same reason (every row is inside this one contribution)
			and rides the shared dispatcher instead.

			`consume = false` verbatim from the engine's own seam (row-actions
			round 7: closing must never swallow an unrelated click), so the tap
			that closed the tray still does whatever it was going to do. ]]
		bundle.outsideDismiss = {
			active = listScope:own(core:memo(function(use)
				return use(engagedKey) ~= nil
			end)),
			dismiss = function()
				local engine = hostedEngagedEngine()
				if engine ~= nil then
					engine.close()
				end
			end,
			consume = false,
		}
	end
	if reorderable then
		bundle.navigateIntercept = navigateIntercept
	end
	if reorderable or rowsAreTargets or hostedEnabled then
		-- handleCancel rides with EVERY armed-paradigm participation, not just
		-- reorder (director virtual-controller round: a drop-target list armed a
		-- card and B had no cancel handler at all — the session simply survived
		-- the press) — and with an engaged row-actions tray, which Cancel closes
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
		-- HOSTED ROW ACTIONS (nil on a list without `spec.rowActions`): which row
		-- is currently revealing a tray, and by how many signed px. Published
		-- because the shared overlay and the presentation slide (Task 4) are
		-- derived from exactly these two, and a fixture proving a swipe reveal has
		-- nothing else to read.
		engagedKey = engagedKey,
		engagedOffset = engagedOffset,
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
		--[[ THE DUMP CARRIES THE AXIS-NEUTRAL NAMES ALWAYS, and the deprecated
			ones ONLY on the axis they are true of. `rowHeight` / `viewportHeight`
			are exactly `itemExtent` / `viewportExtent` on a vertical list, so an
			existing reader of either key sees the number it always saw; on a
			HORIZONTAL list they are absent rather than lying, because "the row
			height is 120" about a list of 120-px-wide items is a sentence that
			would send someone the wrong way. Nothing shipped reads them off a
			horizontal list — there were no horizontal lists until this field. ]]
		local d: any = {
			schema = "luauui-virtual-list-dump/1",
			id = id,
			axis = axis,
			itemExtent = itemExtentNow(),
			viewportExtent = viewportNow(),
			rowGap = rowGapNow(),
			overscan = overscan,
			scrollTop = clampedTop:get(),
			focusedKey = focusedKey:get(),
			selectedKey = selectedKey:get(),
			armedKey = armedKey:get(),
			dropIndex = dropIndex:get(),
			selection = selectionMode,
			-- the policy AND the slot it is holding: the two facts a "why did the
			-- ring move" bug report needs (`pinnedSlot` is nil under "key")
			focusPolicy = focusPolicy,
			pinnedSlot = pinnedSlot,
			reorderable = reorderable,
			dropSurface = isDropSurface,
			focusGroup = focusGroupName,
			autoscroll = autoscrollState:get().state,
			window = windowKeys,
			totalRows = #(spec.rows:get() :: { any }),
		}
		if not isX then
			d.rowHeight = d.itemExtent
			d.viewportHeight = d.viewportExtent
		end
		return d
	end
	--[[ TEST-ONLY (the `_` prefix says so): the two facts the hosted-mode
		laziness guarantee is made of. `engineCount` is what proves scrolling a
		list of actionable rows builds nothing, and `engagedKey` is what proves a
		gesture reached the right row. Deliberately NOT in `dump()`: a dump is a
		diagnostic a consumer may ship, and these are internals of an optimization,
		not state a consumer should be reacting to (`engagedKey` is published as a
		signal on the list for that). Answers on a plain list too, so a test can
		assert "nothing hosted" without branching. ]]
	function list._hostedDebug(): { engineCount: number, engagedKey: string? }
		local count = 0
		for _ in hostedEngines do
			count += 1
		end
		return {
			engineCount = count,
			engagedKey = if engagedKey ~= nil then engagedKey:get() else nil,
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
