--!strict
-- Table control, Phase A (ADR-0007; NSTableView-informed). A COMPOSITE over
-- shipped primitives: every row is a ZStack [whole-row hit Button, HStack of
-- cells]; cells in every row (and the optional header) share the same column
-- dim specs, so the solver aligns columns without any new layout kind.
-- Column resize (the MODEL: setColumnWidth) works by overriding a column to a
-- fixed dim and remounting rows (cheap at list sizes; per-pixel drag preview
-- is Phase B adapter work). Selection: none | single | multi (activate
-- toggles additively in multi — the touch idiom). MODIFIER-KEY SEMANTICS
-- SHIPPED: Shift-click extends a range from the anchor and Cmd/Ctrl-click
-- toggles one row (`api.select`'s "range"/"toggle" modes below, driven by the
-- activate meta the adapter fills in, wired to real keys in screen_target and
-- covered in tests/table.spec.luau). This header said "Phase B" for both of
-- them long after they landed, the implementation comment 1800 lines below said
-- otherwise, and the stale half reached a mission brief as fact — see
-- docs/lessons/a-header-comment-describes-the-path-it-was-written-for.md.
-- Variable row heights via rowHeight(item). Headerless mode for
-- borderless lists (director's racer-list case). Custom cells: cellFor
-- returns any Blueprint — nested interactive controls stay live because cell
-- content renders ABOVE the row hit and non-active nodes pass taps through.
--
-- NATIVE SCROLL (native-substrate §4/§6). The body is a UI.ScrollView — an
-- engine ScrollingFrame on the live adapter. Rows flow at their NATURAL
-- document positions (no hand-rolled offset, no row-park cull); the solver's
-- scroll-axis content sum becomes CanvasSize, and the ENGINE owns the live
-- offset (wheel, touch drag, momentum, elastic, bars), clipping partial rows
-- natively. The old per-row -scrollOffset arrange trick, the wheel handler, and
-- the touch-pan handler are RETIRED (native §4). scrollTop is now the engine
-- CanvasPosition MIRROR: written only by the mirror wiring (api.bindNativeScroll
-- after present feeds controller.observeScroll -> scrollTop) or a test. Touch on
-- the row body DECLINES the pointer capture so the native scroll owns the pan;
-- reorder on touch rides the edit-mode ≡ handle. Keyboard/gamepad scroll-into-
-- view and reorder drag math read the mirror to stay canvas-correct while
-- scrolled, and keep-visible issues the framework's ONE programmatic scroll
-- write, controller.scrollTo(scrollPath, {x,y}). Engine-free; Lune-tested in
-- tests/table.spec.luau (windowing/selection/reorder decisions stay pure).

local contribution = require("../input/contribution")
local interactionTokens = require("../input/interaction_tokens")
local solverLib = require("../layout/solver")
local themeSnapshot = require("../themes/snapshot")
local specGuard = require("../spec_guard")
local rowCapability = require("../row_capability")
local row_actions = require("./row_actions")
-- the axis-lock constant only (never a decision instance): the row Hit's own
-- dispatch has to know whether a gesture it forwarded became a SWIPE, and the
-- lock radius is the one authored fact that answers it. Same require, for the
-- same reason, as `virtual_list.luau`'s host dispatcher.
local row_actions_state = require("../input/row_actions_state")

-- a node id is interpolated into a Lua PATTERN below, so its magic characters
-- have to be escaped first. Module scope, not per-instance: it is a pure
-- function of its argument and every `build()` used to allocate its own
-- (Step 5.5 cleanup ledger C-06).
local function patternEscape(s: string): string
	return (s:gsub("%W", "%%%0"))
end

-- Task 10: row_actions.build's own wrapper interposes a known
-- `RowActions-<rowKey>/Content/` segment between a wrapped row's `[key@v]/`
-- ForEach slot and its own `Row/...` tree (row_actions.luau: root Anchor
-- `id`, one child ZStack `id = "Content"`, `content` — this row's OWN
-- blueprint — mounted inside it). `<rowKey>` makes the id UNIQUE per row —
-- two row_actions instances sharing one literal id (a first-shipped version
-- of this wiring used the constant "RowActions" for every row) corrupted
-- each other's in-flight gesture state the moment a second row's live drag
-- claimed the shared coordinator away from the first: the composite's own
-- `patternEscape(id)`-based path matching (its own header comment: an id is
-- interpolated into a Lua pattern) silently assumes local uniqueness, which
-- a shared literal violates. Every row-relative path pattern below this
-- point is anchored assuming `Row/...` sits DIRECTLY under `[key@v]/` — true
-- for every unwrapped row, false by exactly this one segment for a wrapped
-- one. Stripping it here, once (pattern, not a literal, since the id varies
-- per row), keeps every one of those patterns correct for both without
-- duplicating any of them; a never-wrapped table (no `spec.rowActions`)
-- never has the segment to strip, so this is a no-op for every path in the
-- common case.
local ROW_ACTIONS_PATH_INFIX = "/RowActions%-[^/]+/Content/"
local function derowActionsPath(path: string): string
	return (string.gsub(path, ROW_ACTIONS_PATH_INFIX, "/", 1))
end

local table_control = {}

-- SwiftUI-shaped column (director round 5, developer.apple.com/documentation/
-- swiftui/table): columns OWN their content and presentation, like TableColumn.
export type Column = {
	id: string,
	title: string?,
	-- width sugar: a NUMBER is fixed px (SwiftUI .width(60)); {min, ideal,
	-- max} is a minMax band (SwiftUI .width(min:ideal:max:)); full Dim tables
	-- (fixed | fill | percent | minMax) pass through unchanged
	width: any,
	minWidth: number?,
	resizable: boolean?,
	-- per-column cell alignment (SwiftUI TableColumnAlignment); vertical
	-- CENTER and horizontal LEADING are the defaults
	alignment: { h: ("leading" | "center" | "trailing")?, v: ("top" | "center" | "bottom")? }?,
	-- cell content, in priority order: `cell(item)` (custom Blueprint, like
	-- TableColumn's content closure), `value(item)` (default Text cell, like
	-- TableColumn(value:) — also marks the column sortable), spec.cellFor
	cell: ((item: any) -> any)?,
	value: ((item: any) -> string)?,
	sortable: boolean?, -- opt a `cell` column into sorting explicitly
	-- FULL-VALUE DISCLOSURE for table-authored text (Step 8.5 LT-G2): the
	-- default `value` cell and the header title are Texts the TABLE authors, so
	-- a consumer had no way to declare their identity strings disclosable. A
	-- column carrying `disclose = true` passes the declaration to both; a
	-- custom `cell` blueprint declares it on its own Text instead.
	disclose: boolean?,
}

-- the column boundary's closed key set (§4 — refused, never swallowed);
-- built below once specGuard is in scope

export type Spec = {
	id: string?,
	columns: { Column },
	rows: any, -- Readable<{T}>
	key: (any) -> string,
	-- legacy table-wide cell factory; optional when every column carries
	-- its own `cell`/`value` (the SwiftUI shape)
	cellFor: ((columnId: string, item: any) -> any)?,
	-- OPTIONAL, and leaving it out is the recommended shape (director, 2026-07-27).
	-- Absent, the table derives the row height from the theme's own per-paradigm row
	-- description and the live text scale — taller under touch so a row clears the
	-- target floor, taller again when the player raises their text preference. Set,
	-- a number or a per-item function still wins; the cell line cap is re-derived
	-- from whatever height won, so an authored row cannot overflow either.
	rowHeight: (number | (any) -> number)?,
	header: boolean?,
	selection: ("none" | "single" | "multi")?,
	gap: number?,
	-- OWNER-HELD sort binding (SwiftUI Table(sortOrder:)): a Signal holding
	-- nil | { column: string, ascending: boolean }. Tapping a sortable
	-- column's header cycles it (new column -> ascending, same -> flips);
	-- the table NEVER sorts the data — the owner observes and re-sorts rows.
	sortOrder: any?,
	height: any?, -- root height dim (default fill); pass a Readable fixed dim
	-- to make the table hug its content (content-hugging docked panels)
	-- WHO OWNS THE SCROLLING (director report 2026-07-27, playlist in landscape:
	-- "just the table scrolls. really the whole view should scroll, as it's
	-- unusable having just the table scroll").
	--
	-- Default TRUE: the table owns a viewport, its rows scroll inside it, and the
	-- page around it does not move. That is right when the table IS the screen.
	--
	-- FALSE makes the table a BLOCK: every row lays out, the body clips nothing,
	-- and the height defaults to content — so a host that wraps it in its own
	-- ScrollView scrolls the whole page, header and filter included. On a short
	-- landscape viewport the title, filter and hint ate 45-55% of the screen and
	-- the rows were left a 144px window that was the only thing that could move.
	--
	-- It is a CHOICE and not an inference because both are legitimate: a mail
	-- app's list owns its viewport, a settings page's small table does not.
	scrolls: boolean?,
	rowGap: (number | string)?, -- vertical space between row cards; a number or a
	-- theme metric name ("xs".."xl" or a dotted path such as "controls.table.rowGap"),
	-- exactly like `cellPadding` below. Default 0 (the drop indicator centers in the
	-- gap) — cards with hairline strokes need >= 2.
	--
	-- IT TAKES A METRIC NAME BECAUSE IT IS USED IN ARITHMETIC (example-quality-pass,
	-- 2026-08-06). `cellPadding` has accepted one since it shipped, because it is
	-- only ever handed to a blueprint prop and the solver resolves it. `rowGap` is
	-- also read in Luau — cumulative row tops, the content extent, and the drop
	-- slot — so a metric name here used to reach `cum += height + rowGap` and throw
	-- "attempt to perform arithmetic on number and string". It resolves against the
	-- live snapshot now, so the two spellings behave identically and a themed table
	-- gap is expressible at all.
	cellPadding: (number | string)?, -- horizontal cell inset; number or theme metric name (default "s")
	-- Phase B: row drag-and-drop — rows stay in place while dragging; a ghost
	-- chip and drop line carry the affordance (director round 2). Dragging a
	-- SELECTED row moves the whole selection as a contiguous block (director:
	-- rows 1,3,5 selected, drag 3, drop after 2 -> 2,1,3,5,4); an unselected
	-- row drags alone. onReorder(keys, toIndex): keys in DOCUMENT order;
	-- toIndex = 0-based insertion slot among the rows NOT being dragged —
	-- consumers remove all keys then insert the block at toIndex + 1.
	-- Drops that reproduce the current order are suppressed.
	reorderable: boolean?,
	onReorder: ((keys: { string }, toIndex: number) -> ())?,
	dragLabel: ((item: any) -> string)?, -- ghost chip text (default: the key)
	-- THE PRIMARY ACTION (parity round 2 §3.4). THE NAME IS OURS: SwiftUI has no
	-- `onPrimaryAction` symbol — it delivers this verb as the `primaryAction:`
	-- argument of `contextMenu(forSelectionType:menu:primaryAction:)`, whose
	-- documented gesture model is what the dispatch below implements.
	-- "Open this row" — the verb that is NOT selection. Reachable on all four
	-- inputs with no invented gesture (see the primary-action block below for the
	-- gesture table, Apple's own words, and the cost of the touch rule). Absent =
	-- the table has no primary action and every gesture below behaves exactly as
	-- it does today.
	onPrimaryAction: ((item: any, key: string) -> ())?,
	-- touch-scroll design (2026-07-20): owner-held edit-mode signal. When it is
	-- nil the table manages its own (api.editing), and auto-shows an Edit/Done
	-- toggle whenever edit mode is the ONLY route to a capability this table
	-- declares — `reorderable`, or a selectable table that declares
	-- `onPrimaryAction` (gated to non-mouse input when `env` is provided). The
	-- full predicate, the principle behind it, and what Apple does and does not
	-- document about `EditButton` are at THE AUTO EDIT/DONE TOGGLE below.
	editing: any?,
	env: any?, -- optional environment for input-aware affordances
	-- Task 10 (row-actions Table integration). Per-item callback: return
	-- `{ leading?, trailing?, fullSwipe? }` (the same shape `newRowActions`
	-- itself takes, minus `content`/`coordinator`/`env`/`editing` — Table
	-- supplies all four) to wrap that row in a swipeable action tray; `nil`
	-- (the common case) leaves the row completely unwrapped — no extra
	-- Instance, no extra subscription (see row_actions.luau's own "TRUE
	-- INERT PASSTHROUGH" — this is that same guarantee, one level up). Every
	-- wrapped row shares ONE coordinator (at most one open tray at a time
	-- across the whole table) and Table's own `editing` signal (the edit-mode
	-- leading minus and the reorder ≡ handle can both show at once — see
	-- row_actions.luau Task 9).
	rowActions: ((
		item: any
	) -> {
		leading: { any }?, -- { newRowActions.ActionSpec }
		trailing: { any }?,
		fullSwipe: (boolean | { leading: boolean?, trailing: boolean? })?,
	}?)?,
}

-- CLOSED SPEC (constitution §4; ARCH-1). Exactly the fields this control
-- reads — an unknown one is an authoring mistake, never a silent no-op.
-- the COLUMN boundary's closed key set (§4, architecture review F-4)
local COLUMN_KEYS = specGuard.keySet({
	"id",
	"title",
	"width",
	"minWidth",
	"resizable",
	"alignment",
	"cell",
	"value",
	"sortable",
	"disclose",
})

-- Task 10: the closed key set for whatever `spec.rowActions(item)` returns
-- for a single row — the same three fields `newRowActions` itself exposes
-- besides `content`/`coordinator`/`env`/`editing` (Table supplies those
-- four). Checked per row, at build, so a typo names the offending row rather
-- than surfacing as a silently-ignored option (constitution §4; ARCH-1).
local ROW_ACTIONS_RESULT_KEYS = specGuard.keySet({ "leading", "trailing", "fullSwipe" })

local TABLE_KEYS = specGuard.keySet({
	"cellFor",
	"cellPadding",
	"columns",
	"dragLabel",
	"editing",
	"env",
	"gap",
	"header",
	"height",
	"id",
	"key",
	"onPrimaryAction",
	"onReorder",
	"reorderable",
	"rowActions",
	-- PER-ROW CAPABILITY OPT-OUTS (parity round 3, item C). Positive polarity;
	-- see src/row_capability.luau for why, and for the SwiftUI inverse mapping.
	"rowDeletable",
	"rowGap",
	"rowHeight",
	"rowMovable",
	"rowSelectable",
	"rows",
	"scrolls",
	"selection",
	"sortOrder",
})

function table_control.build(LuauUI: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("newTable", spec, TABLE_KEYS, "spec")
	--[[ PER-ROW OPT-OUTS MAY ONLY SUBTRACT (parity round 3, item C) — a
		predicate narrowing a capability this table does not have would be an
		accepted property that does nothing (constitution §4). ]]
	rowCapability.assertNarrowsSomething(
		"newTable",
		"rowSelectable",
		spec.rowSelectable,
		spec.selection ~= nil and spec.selection ~= "none",
		'selection is absent or "none", so no row is selectable to begin with',
		'Declare selection = "single" or "multi", or drop spec.rowSelectable.'
	)
	rowCapability.assertNarrowsSomething(
		"newTable",
		"rowMovable",
		spec.rowMovable,
		spec.reorderable == true and spec.onReorder ~= nil,
		"reorderable/onReorder are absent, so no row moves at all",
		"Declare reorderable = true and an onReorder handler, or drop spec.rowMovable."
	)
	rowCapability.assertNarrowsSomething(
		"newTable",
		"rowDeletable",
		spec.rowDeletable,
		spec.rowActions ~= nil,
		"rowActions is absent, so no row carries a destructive action to refuse",
		"Declare a rowActions callback returning a destructive action, or drop spec.rowDeletable."
	)
	local UI = LuauUI.UI
	local scope = core:scope(`Table-{spec.id or "table"}`)
	local tableId = spec.id or "Table"
	local selectionMode = spec.selection or "none"

	-- THE ROW BOX: HOW TALL A ROW IS, AND HOW MANY LINES FIT IN IT ---------------
	--
	-- Both halves of the same answer, derived together and in ONE place, because
	-- they have to agree: a row of a known height that lets its cells measure taller
	-- is a row whose content paints through its neighbours. That is exactly the
	-- defect a device pass found (2026-07-27, iPhone, Glossy Touch and Pixel Quest):
	-- `rowHeight = 48` with an uncapped `UI.Text` cell, "Drift City Nights" wrapping
	-- to three lines in the 136px the name column gets at 393pt, and 54px of text
	-- painted across two 48px row plates. It did not reproduce in the emulator
	-- because it takes only a few pixels of extra text width to turn two lines into
	-- three — which is the point: a fixed row with no line cap has no slack at all,
	-- so ANY difference between the emulator and the device is visible damage.
	--
	-- THE HEIGHT IS A DESCRIPTION, NOT A NUMBER (director ask, same report: "we
	-- likely want taller table cells on mobile for touch targeting. that seems like
	-- the paradigm adaptation luauui should handle"). The theme says how many lines
	-- a row holds per input paradigm and what floor it may not go under
	-- (`controls.table.rowLines` / `.rowHeight`, derived in themes/snapshot); this
	-- adds the two things only the LIVE environment knows — the ten-foot typography
	-- scale and the accessibility text OFFSET the engine applies on top — and turns
	-- the description into pixels. So a player who raises their text preference gets
	-- taller rows rather than clipped ones, and a touch session gets a row that
	-- clears the target floor without any screen asking for it.
	--
	-- THE LINE CAP FALLS OUT OF THE HEIGHT: whatever the height ends up being, the
	-- cap is how many whole lines fit inside it, floored at one. That is what makes
	-- overflow impossible by construction instead of by tuning — including for a
	-- consumer who pins `rowHeight` by hand, whose cells are capped to THEIR row.
	local function rowBoxFor(metrics: any, classes: any, textScale: number, textOffset: number): any
		local family: any = metrics.controls.table
		local cellSize = family.cellTextSize * textScale + textOffset
		local lineBox = math.ceil(cellSize * metrics.type.body.lineHeight)
		local padV = family.rowPadding
		local touch = if type(classes) == "table" and classes.touch == true then true else false
		local paradigm = if touch then "touch" else "pointer"
		local floor = family.rowHeight[paradigm]
		local height = math.max(floor, family.rowLines[paradigm] * lineBox + 2 * padV)
		return { height = height, lineBox = lineBox, padV = padV }
	end
	-- the authored override wins on HEIGHT (a consumer who pins a row height means
	-- it) but never on the cap, which is re-derived from whichever height won
	local function capFor(box: any, height: number): number
		return math.max(1, math.floor((height - 2 * box.padV) / box.lineBox))
	end
	-- a garbage `themeMetrics` fact falls back to neutral rather than erroring —
	-- the same guard, for the same reason, as the presenter's `metricsNow`
	-- (§8.2: a broken adapter fact must never leak past the seam that reads it)
	local function metricsOr(raw: any): any
		local family = if type(raw) == "table" and type(raw.controls) == "table" then raw.controls.table else nil
		-- the derived keys specifically (`snapshot.resolve` computes rowHeight /
		-- rowLines / rowPadding), not just "a table family exists": a hand-built
		-- metrics table is exactly the shape that would have them missing
		local ok = type(family) == "table"
			and type(family.rowHeight) == "table"
			and type(family.rowLines) == "table"
			and type(family.rowPadding) == "number"
			and type(raw.type) == "table"
			and type(raw.type.body) == "table"
		return if ok then raw else themeSnapshot.neutral()
	end
	local function finite(raw: any, fallback: number): number
		return if type(raw) == "number" and raw == raw and raw ~= math.huge then raw else fallback
	end
	local rowBox = scope:own(core:memo(function(use)
		local env = spec.env
		if env == nil then
			-- headless / no-environment consumers: the neutral package at authored
			-- size and a pointer paradigm, which is what the suite has always solved
			return rowBoxFor(themeSnapshot.neutral(), nil, 1, 0)
		end
		return rowBoxFor(
			metricsOr(use(env:get("themeMetrics"))),
			use(env:get("interactionClasses")),
			finite(use(env:get("typographyScale")), 1),
			finite(use(env:get("preferredTextOffset")), 0)
		)
	end))
	-- THE one row-gap answer, in pixels, live. A metric NAME resolves against the
	-- current snapshot on every read, so a theme swap moves the gutter without a
	-- rebuild; a number passes through unchanged; absent stays 0.
	local rowGapPx = scope:own(core:memo(function(use)
		local declared = spec.rowGap
		if type(declared) == "number" then
			return declared
		end
		if type(declared) ~= "string" then
			return 0
		end
		local env = spec.env
		local snap = if env == nil then themeSnapshot.neutral() else metricsOr(use(env:get("themeMetrics")))
		return themeSnapshot.resolveNumber(snap, declared) or 0
	end))
	-- THE one row-height answer. Every seam that reasons about row geometry — the
	-- blueprint, the cumulative tops, the content extent, the drop slot and
	-- keep-visible — comes through here, so the model and the paint can never
	-- disagree about how tall a row is. `box` is passed in from inside a memo so the
	-- read subscribes; elsewhere the current value is right.
	local function rowHeightOf(item: any, box: any?): number
		local live: any = box or rowBox:get()
		local declared = spec.rowHeight
		local pinned = if type(declared) == "function"
			then (declared :: any)(item)
			elseif type(declared) == "number" then declared
			else nil
		if pinned == nil then
			return live.height
		end
		-- AN AUTHORED HEIGHT WINS, BUT NEVER BELOW ONE LINE OF ITS OWN CELL TEXT.
		-- Not a compromise — the alternative is unreachable. A row cannot be shorter
		-- than the single line it is obliged to draw (the cap floors at one line: it
		-- is a limit, not an eraser), so a pin below that does not produce a shorter
		-- row, it produces the exact overflow this whole change exists to remove.
		-- It only ever binds when the player has RAISED their text preference, which
		-- is precisely when honouring a stale pixel count would be the wrong answer;
		-- at the shipped text size every height any consumer has ever pinned clears
		-- it, so nothing that works today moves by a pixel.
		return math.max(pinned, live.lineBox + 2 * live.padV)
	end

	-- selection state: { [rowKey]: true }
	local selectedKeys = scope:own(core:signal({} :: { [string]: boolean }))
	-- edit mode (touch-scroll design 2026-07-20): owner-held signal, or an
	-- internal one when the owner does not supply it (api.editing either way).
	-- While editing, rows grow a trailing ≡ handle; on touch, ONLY the handle
	-- starts a reorder — the row body always pans the scroll.
	local editingSignal = spec.editing or scope:own(core:signal(false))
	--[[ HOISTED TWICE (parity round 3, then again 2026-08-14 for `rowDeletable`):
		this used to sit ~170 lines below the capability gates in `api.select` and
		`api.moveRow`, and it now sits above `rowBlueprint` too — the `deletable`
		thunk handed to `row_actions.build` closes over it. A local declared LATER
		in the file is NOT an upvalue: it binds a nil GLOBAL and calls it
		(`docs/lessons/later-locals-are-not-upvalues.md` — and the delete gate walked
		straight into that lesson before this move). It depends only on `spec`,
		already in scope, so it can sit as high as its first reader needs. ]]
	local function itemForKey(rowKey: string): any?
		for _, item in spec.rows:get() :: { any } do
			if spec.key(item) == rowKey then
				return item
			end
		end
		return nil
	end

	-- Task 10: ONE row-actions coordinator per table (`row_actions.
	-- newCoordinator`, Task 7), shared by every wrapped row so at most one
	-- tray is open across the whole list — built only when `spec.rowActions`
	-- is actually used (a table that never wraps a row pays nothing).
	-- `bindScroll` (any scroll closes the open tray, iOS parity) is wired
	-- after present through the same seam `bindNativeScroll` uses (both feed
	-- off the identical `controller.observeScroll`).
	local rowActionsCoordinator: any = if spec.rowActions ~= nil then row_actions.newCoordinator(core) else nil
	-- Task 10: per-row-key row_actions instance ({ blueprint, dispose, _open,
	-- _close, _isOpen, ... } — row_actions.build's own return). `core:scope()`
	-- (what row_actions.build calls internally) is an INDEPENDENT root, never
	-- an implicit child of anything — unlike `selectedMemoByKey`'s own
	-- `scope:child(...)` entries, nothing disposes one of these for free, so
	-- Table owns the full lifecycle explicitly: built in `rowBlueprint`,
	-- pruned by the SAME `spec.rows` observer that already prunes
	-- `selectedMemoByKey` below (never a second rows observer — brief), and
	-- swept on the table's own `dispose()`.
	local rowActionsByKey: { [string]: any } = {}
	-- gamepad grab mode (2026-07-20): A/Cross on a focused row while editing
	-- GRABS it; d-pad up/down steps the row (or the selected block) one slot
	-- per press through onReorder; A again drops. Cleared on leaving edit.
	local grabbedKey = scope:own(core:signal(nil :: string?))
	-- pre-grab snapshot (matrix §C; UI-PARADIGM-002): { block, slot } captured
	-- when a grab begins, so a mid-grab gamepad-capability loss can revert the
	-- list order to pre-grab (CANCEL). Cleared on drop.
	local grabOrigin: any = nil
	-- scrollTop: the body's engine CanvasPosition MIRROR (native-substrate
	-- NS-A2). The body is a native ScrollingFrame; the ENGINE owns the live
	-- offset (wheel, touch drag, momentum, elastic, bars) and reports it back
	-- through observeScroll, wired by api.bindNativeScroll after present. Rows
	-- flow at their natural document positions (no hand-rolled offset); the
	-- engine translates them via CanvasPosition. Reorder drag math and
	-- keep-visible read this mirror to stay canvas-correct while scrolled.
	local scrollTop = scope:own(core:signal(0))
	-- native scroll seam state: the keep-visible controller + the mounted body
	-- path, wired by api.bindNativeScroll (the control cannot reach the renderer
	-- controller at build time). mountedRoot is captured in buildFocusGroups.
	local boundController: any = nil
	local boundScrollPath: string? = nil
	local mountedRoot: string? = nil
	-- key -> cumulative top (px) in document order, for offsets and culling
	local rowTops = scope:own(core:memo(function(use)
		local tops: { [string]: number } = {}
		local cum = 0
		-- `use`d, not read: a derived row height moves every top below it, so a
		-- theme swap or an accessibility text change has to re-derive these
		local box = use(rowBox)
		for _, item in use(spec.rows) :: { any } do
			tops[spec.key(item)] = cum
			cum += rowHeightOf(item, box) + use(rowGapPx)
		end
		return tops
	end))
	local function contentHeight(): number
		local total = 0
		local n = 0
		local box = rowBox:get()
		for _, item in spec.rows:get() :: { any } do
			total += rowHeightOf(item, box)
			n += 1
		end
		return total + math.max(0, n - 1) * rowGapPx:get()
	end
	local function clampScroll(value: number, bodyHeight: number): number
		return math.clamp(value, 0, math.max(0, contentHeight() - bodyHeight))
	end
	--[[ THE AUTO EDIT/DONE TOGGLE, AND THE PRINCIPLE BEHIND IT ===================

		THE PREDICATE, IN WORDS: the toggle appears when this table declares ANY
		capability that is reachable ONLY in edit mode, and the consumer has not
		taken the `editing` signal over. It is a UNION over the edit-mode-only
		capability set, not a rule about any one feature — when a future capability
		becomes edit-mode-only it joins by adding one named clause below, and
		nothing about this decision has to be re-derived.

		THE SET, TODAY, IS EXACTLY TWO (audited against every `editingSignal` read
		in this file, 2026-08-13):

		  * REORDER — the ≡ handle is `condition = editingSignal` and is the only
		    touch route to a reorder (a touch drag on the row body is declined so
		    the native scroll can own the pan), and gamepad grab mode refuses
		    outright unless `editingSignal` is true. Declared by `reorderable`.
		  * TOUCH SELECTION — under Apple's rule (THE PRIMARY ACTION, below) a plain
		    touch tap on a table that declares `onPrimaryAction` OPENS the row and
		    never selects, so touch selection lives in edit mode and nowhere else.
		    Declared by `selection ~= "none"` TOGETHER WITH `onPrimaryAction`:
		    either alone leaves selection reachable by a plain tap.

		WHAT IS NOT IN THE SET, and why the union is a judgement rather than a
		reflex: `spec.rowActions`' edit-mode leading minus (row_actions.luau Task 9)
		shows in edit mode too, but it is a SECOND route to a destructive action the
		swipe tray already reaches in normal mode on every input — an affordance,
		not a capability. Only "no other route exists" earns a clause here.

		THE SECOND CLAUSE WAS MISSING UNTIL 2026-08-13, and the omission was a
		reachability HOLE rather than a nicety: moving touch selection into edit
		mode RELOCATED the four-input failure instead of removing it, because a
		`selection = "single"|"multi"` + `onPrimaryAction` + NOT-`reorderable` table
		had no route into edit mode at all, so its own `selection` was unreachable
		on touch entirely.

		AUTO-SHOWING IT IS OURS, NOT APPLE'S — and that is worth stating plainly,
		because the reverse is the easy assumption. `EditButton` is a control the
		developer PLACES BY HAND (Apple's own example puts one in a `.toolbar` with
		no condition on it), and Apple documents NO rule for when it should appear;
		it is also iOS/iPadOS/Mac Catalyst/visionOS only. What Apple does condition
		on declared capabilities is the CONTENT of edit mode, not the button:
		"Because the `ForEach` in the above example defines behaviors for
		`onDelete(perform:)` and `onMove(perform:)`, the editable list displays the
		delete and move UI when the user taps Edit" (EditButton), and "a `List` with
		a `ForEach` that's configured with the `onDelete(perform:)` or
		`onMove(perform:)` modifier provides controls to delete or move list items
		while in edit mode. On devices without an attached keyboard and mouse or
		trackpad, people can make multiple selections in lists only when edit mode
		is active" (EditMode). So the capability→edit-mode half is Apple's and is
		exactly the principle above; the auto-SHOW is our own, and it is forced by a
		bar SwiftUI does not carry: our four-input rule makes every declared verb
		reachable on every input, and a consumer who simply forgot to place a toggle
		would otherwise ship a table whose `selection` no finger can reach.

		THE THREE SHAPES THAT MUST NOT GROW A BUTTON are the predicate read
		backwards, and each is a case in tests/table_input.spec.luau: `selection =
		"none"` (edit mode is the only route to nothing), no `onPrimaryAction` (a
		plain tap still selects in normal mode — the shipped RascalRally racer
		list), and a consumer-held `spec.editing` (their affordance, their
		business).

		`showAutoToggle` then gates the whole thing on INPUT. Keyed off the LIVE
		interaction-class set (ADR-0015), never preferredInput alone: any session
		where touch or gamepad is live needs the edit affordance, even while the
		engine still reports a KeyboardAndMouse preference (director repro
		2026-07-21: physical pad, stale preference). A mouse user reaches both
		capabilities without it — they drag rows directly and a plain click selects
		— so a mouse-only session shows nothing. Without an `env` the table cannot
		know the input, so the toggle always shows.
	]]
	local reorderNeedsEditMode = spec.reorderable == true
	local touchSelectionNeedsEditMode = selectionMode ~= "none" and spec.onPrimaryAction ~= nil
	-- the union, plus the consumer's escape. ADD A CLAUSE, NEVER A SPECIAL CASE.
	local autoEditRoute = spec.editing == nil and (reorderNeedsEditMode or touchSelectionNeedsEditMode)
	local showAutoToggle = if autoEditRoute
		then (if spec.env ~= nil
			then scope:own(core:memo(function(use)
				local classes = use(spec.env:get("interactionClasses"))
				return classes.touch == true or classes.gamepad == true
			end))
			else scope:own(core:signal(true)))
		else scope:own(core:signal(false))
	scope:own(core:observe(editingSignal, function(on)
		if on ~= true then
			grabbedKey:set(nil)
		end
	end))
	local editToggleLabel = scope:own(core:memo(function(use)
		return if use(editingSignal) then "Done" else "Edit"
	end))
	-- edit mode insets every row's cells into a LEADING gutter for the ≡
	-- handle (iOS list-edit convention; director 2026-07-20)
	local HANDLE_GUTTER = 32
	-- THE ROW'S ART RESERVES ROOM AND THE CELLS HAVE TO HONOUR IT (director round
	-- 10, found live 2026-07-26 on a phone).
	--
	-- A row is a full-bleed hit `Button` with the cell stack as its SIBLING, not
	-- its child — it has to be, because a Button's content may hold no focusable
	-- and a rating cell is five of them. That shape is fine for input and wrong
	-- for paint: the renderer adds a slot's `chromeInsets` to the padding of the
	-- node that CARRIES the slot, and the node carrying it here (the hit button)
	-- has no children, so the reservation was inert. The cells then laid out
	-- against the row's raw rect while the theme painted its selection card
	-- inside that rect, so under every package with a real border — Glossy Touch,
	-- Pixel Quest, Compact Pointer — the first cell's text started OUTSIDE the
	-- card it was supposed to sit in, and Compact's rating cell ran off the other
	-- end. Studio Neutral and Classic Desktop reserve nothing, which is exactly
	-- why they looked right and hid this for so long.
	--
	-- Reading the reservation as a theme METRIC is what makes this theme-agnostic:
	-- it resolves per solve, so a package swap re-insets the cells with no
	-- rebuild, and it is ZERO for every flat package, so flat geometry does not
	-- move by a pixel. `selection` is the slot because the hit button always
	-- carries a `selected` prop, which is what `chrome_slots.classify` routes on.
	local ROW_ART = {
		top = "chromeInsets.selection.top",
		right = "chromeInsets.selection.right",
		bottom = "chromeInsets.selection.bottom",
		left = "chromeInsets.selection.left",
	}
	local cellsEditPadding = scope:own(core:memo(function(use)
		if not use(editingSignal) then
			return ROW_ART
		end
		-- edit mode adds the leading ≡ gutter ON TOP of the art's own inset.
		--
		-- It used to REPLACE it, because "a metric name and a number cannot be
		-- added here (the metric resolves at solve time)". That is no longer true:
		-- `snapshot.resolveSides` grew multi-metric sides on 2026-07-27 (for the
		-- header's two stacked gutters) and every entry may be a number or a metric
		-- name. Replacing meant that under every skinned package the first cell was
		-- under-inset by exactly the card's carved border — 16px under Pixel Quest.
		return {
			top = ROW_ART.top,
			right = ROW_ART.right,
			bottom = ROW_ART.bottom,
			left = { ROW_ART.left, HANDLE_GUTTER },
		}
	end))
	-- column width overrides from resizing: { [columnId]: px }
	local widthOverrides = scope:own(core:signal({} :: { [string]: number }))
	-- bumping this remounts rows (resize commits; documented Phase A cost)
	local widthsVersion = scope:own(core:signal(0))
	-- Phase B resize drag: preview guide line state (commit happens on release)
	local resizing = scope:own(core:signal(false))
	local previewX = scope:own(core:signal(0))
	local resizeDrag: any = nil
	-- Phase B row drag: drop indicator state; commits via spec.onReorder.
	-- suppression is armed at the drag THRESHOLD (not on release) and keyed to
	-- the origin row's path, so it neither depends on the engine's unspecified
	-- Activated-vs-InputEnded ordering nor leaks to taps on other rows.
	local dragging = scope:own(core:signal(false))
	local indicatorY = scope:own(core:signal(0))
	-- drag affordance: the row STAYS in place (director round 2 — removing it
	-- made the table jump); the ghost chip + drop line carry the "picked up"
	-- read, and the drop converts full-list slots to the post-removal contract
	local ghostText = scope:own(core:signal(""))
	local ghostCount = scope:own(core:signal(1))
	local ghostX = scope:own(core:signal(0))
	local ghostY = scope:own(core:signal(0))
	local rowDrag: any = nil
	-- COLUMN SELECTION (director 2026-07-29: "focusable header, A selects the column
	-- and left/right resizes"). The same arm-then-navigate vocabulary the row grab
	-- already speaks, one level up: Activate on a focused header SELECTS the column,
	-- and while it is selected the stick acts on it — Left/Right resizes, Up/Down
	-- cycles its sort. It exists as a first-class STATE rather than as a resize mode
	-- because selecting a column is the thing you will want to hang the rest of the
	-- column verbs off later.
	local selectedColumn = scope:own(core:signal(nil :: string?))
	local stepColumnWidth -- assigned with the resize model below
	local suppressActivatePath: string? = nil
	local cancelDrag: () -> () -- assigned with the drag handlers below
	-- range anchor (NSTableView semantics): the last non-range select
	local selectionAnchor: string? = nil
	-- latest solved geometry, fed by the presenter's syncGeometry each
	-- refresh; scroll-into-view (keyboard/gamepad focus moves) reads the
	-- body height from it (ui_todo §0 — Table body scroll on every input)
	local lastRectOf: ((string) -> any)? = nil
	-- The renderer controller, handed over by the contribution's `bindController`.
	-- A row drag ANNOUNCES itself through this (`setPointerDrag`) so the scroll
	-- host that carries the table can autoscroll for it. The table owns no
	-- scrolling policy of its own: the thing that has to move is usually not its
	-- own Body but a page it merely sits inside, and that page belongs to the
	-- consumer's screen (device report 2026-07-29).
	local renderController: any = nil

	local api = {} :: any

	local tableIdPattern = patternEscape(tableId)

	-- width sugar -> Dim (see Column.width); columns are normalized into
	-- shallow clones so the caller's tables are never mutated
	local function normalizeWidth(width: any): any
		if type(width) == "number" then
			return { type = "fixed", px = width }
		end
		if type(width) == "table" and width.type == nil then
			-- partial bands are valid ({min} alone): preferred falls back explicitly
			return {
				type = "minMax",
				min = width.min,
				preferred = width.ideal or width.min or width.max,
				max = width.max,
			}
		end
		return width
	end
	local columns: { Column } = {}
	for _, column in spec.columns do
		-- STRICT AT THE COLUMN BOUNDARY TOO (architecture review F-4; §4). The
		-- top-level spec has always refused unknown keys; columns silently
		-- swallowed them — and `disclose` is exactly the key whose silent typo
		-- (`disclos = true`) removes an accessibility guarantee with no error.
		specGuard.assertKnownKeys(`newTable column '{tostring(column.id)}'`, column, COLUMN_KEYS, "column")
		assert(
			column.disclose == nil or type(column.disclose) == "boolean",
			`Table '{tableId}': column '{tostring(column.id)}'.disclose expects boolean, got {typeof(column.disclose)}`
		)
		-- column ids become path segments (Cell-{id}, Head-{id}) — a "/" would
		-- corrupt path routing everywhere downstream
		assert(
			not string.find(column.id, "/", 1, true),
			`Table '{tableId}': column id '{column.id}' must be path-safe (no "/")`
		)
		-- content is not optional: fail at BUILD (ADR-0010), not first render —
		-- an empty rows list must not mask a content-less column
		assert(
			column.cell ~= nil or column.value ~= nil or spec.cellFor ~= nil,
			`Table '{tableId}': column '{column.id}' has no cell/value and no spec.cellFor`
		)
		local clone = table.clone(column)
		clone.width = normalizeWidth(clone.width)
		table.insert(columns, clone)
	end

	-- SwiftUI alignment terms -> solver terms
	local ALIGN_H: { [string]: string } = { leading = "start", center = "center", trailing = "end" }
	local ALIGN_V: { [string]: string } = { top = "start", center = "center", bottom = "end" }

	-- cell content priority: column.cell -> column.value (default Text) ->
	-- the legacy table-wide spec.cellFor
	--
	-- `lineCap` is this ROW's line limit (see rowBoxFor). It applies to the default
	-- Text cell — the one the table itself authors and is therefore answerable for.
	-- A `cell`/`cellFor` blueprint belongs to the consumer, who may put a scrolling
	-- panel or an image in there; the table caps what it makes, not what it is given.
	local function cellContentFor(column: Column, item: any, lineCap: any): any
		if column.cell ~= nil then
			return (column.cell :: any)(item)
		end
		if column.value ~= nil then
			return UI.Text({
				id = "Value",
				text = tostring((column.value :: any)(item)),
				textSize = "controls.table.cellTextSize",
				lineLimit = lineCap,
				disclose = if column.disclose == true then true else nil,
			})
		end
		assert(spec.cellFor ~= nil, `Table '{tableId}': column '{column.id}' has no cell/value and no spec.cellFor`)
		return (spec.cellFor :: any)(column.id, item)
	end

	local function resolveDim(column: Column, overrides: { [string]: number }): any
		local override = overrides[column.id]
		if override ~= nil then
			return { type = "fixed", px = math.max(override, column.minWidth or 24) }
		end
		local dim = column.width
		if dim.type == "percent" and column.minWidth then
			local clone = table.clone(dim)
			clone.min = column.minWidth
			return clone
		end
		return dim
	end

	local function columnDim(column: Column): any
		return resolveDim(column, widthOverrides:get())
	end

	-- header cells track resize commits reactively (width is a measure-dirty
	-- dynamic prop): the header re-solves in place, no remount needed
	local headerDims: { [string]: any } = {}
	local function headerDim(column: Column): any
		if headerDims[column.id] == nil then
			headerDims[column.id] = scope:own(core:memo(function(use)
				return resolveDim(column, use(widthOverrides))
			end))
		end
		return headerDims[column.id]
	end

	-- per-row-key selected memos, each in its own child scope so removed
	-- keys can be pruned (registry-neutral under row churn); row remounts
	-- from width changes reuse live entries
	local selectedMemoByKey: { [string]: { scope: any, memo: any } } = {}
	local function selectedMemo(rowKey: string): any
		local cached = selectedMemoByKey[rowKey]
		if cached == nil then
			local memoScope = scope:child(`sel-{rowKey}`)
			cached = {
				scope = memoScope,
				memo = memoScope:own(core:memo(function(use)
					-- a grabbed row shows the selected treatment (gamepad
					-- grab-mode visual)
					return use(selectedKeys)[rowKey] == true or use(grabbedKey) == rowKey
				end)),
			}
			selectedMemoByKey[rowKey] = cached
		end
		return cached.memo
	end

	-- prune stale per-key memos when rows change. This runs before the rows'
	-- DERIVED consumers (keyedItems -> ForEach) because the core fires a
	-- written signal's own observers before its downstream memos' observers —
	-- removed keys dispose before their rows unmount, live keys untouched.
	-- selection and the range anchor prune with them: removed rows must never
	-- linger as phantom selections nor pre-select a re-added key.
	scope:own(core:observe(spec.rows, function(items)
		local live: { [string]: boolean } = {}
		for _, item in items do
			live[spec.key(item)] = true
		end
		for rowKey, entry in selectedMemoByKey do
			if not live[rowKey] then
				entry.scope:dispose()
				selectedMemoByKey[rowKey] = nil
			end
		end
		-- Task 10: a vanished row's row_actions wrapper disposes HERE — before
		-- the ForEach itself unmounts the row (this observer's own comment,
		-- above: "removed keys dispose before their rows unmount") — so a
		-- commit racing a data refresh (the row's key removed mid-gesture)
		-- sets the wrapper's `disposed` guard before anything else in this
		-- same reactive flush can act on it. `core:scope()`-rooted (see
		-- `rowActionsByKey`'s own comment), so nothing else would free it.
		for rowKey, instance in rowActionsByKey do
			if not live[rowKey] then
				instance.dispose()
				rowActionsByKey[rowKey] = nil
			end
		end
		local current = selectedKeys:get()
		local pruned: { [string]: boolean }? = nil
		for rowKey in current do
			if not live[rowKey] then
				pruned = pruned or table.clone(current);
				(pruned :: any)[rowKey] = nil
			end
		end
		if pruned ~= nil then
			selectedKeys:set(pruned)
		end
		if selectionAnchor ~= nil and not live[selectionAnchor :: string] then
			selectionAnchor = nil
		end
		-- the dragged row vanished from the data mid-drag: the drag is moot
		if rowDrag ~= nil and rowDrag.active and not live[rowDrag.rowKey] then
			cancelDrag()
		end
	end))

	-- ForEach items: key carries the widths version so a committed resize
	-- remounts rows with the new dims (pure moves/selection never remount)
	local keyedItems = scope:own(core:memo(function(use)
		local version = use(widthsVersion)
		local out = {}
		for _, item in use(spec.rows) do
			table.insert(out, { item = item, tableKey = `{spec.key(item)}@{version}` })
		end
		return out
	end))

	local rowKeyForPath: { [string]: string } = {}

	-- press→drag promotion, from the SHARED token table (ADR-0022 D5, SF-D3) —
	-- the value is the same 6 px this control has always used, sourced from the
	-- one place a device round retunes it. The POINTER token is the right one
	-- here even on a touch device: the row body declines the capture on touch
	-- (the native ScrollingFrame owns the pan), so touch reorder rides the
	-- edit-mode ≡ handle, which presents its position as a mouse pointer.
	local DRAG_THRESHOLD = interactionTokens.promotionPx("pointer")
	local function rowGapNow(): number
		return rowGapPx:get()
	end

	-- insertion slot from a body-relative pointer y over the FULL list (the
	-- dragged row stays in place): the count of rows whose midpoint sits
	-- above it; the drop converts to the post-removal contract. The returned
	-- boundary centers the indicator in the row gap.
	local function insertSlotAt(relY: number): (number, number)
		local cum = 0
		local slot = 0
		for _, item in spec.rows:get() do
			local height = rowHeightOf(item)
			if relY > cum + height / 2 then
				slot += 1
				cum += height + rowGapNow()
			else
				break
			end
		end
		local boundary = if slot == 0 then 0 else cum - rowGapNow() / 2
		return slot, boundary
	end

	-- retract the drag announcement (see `renderController` above). EVERY exit
	-- goes through here — drop, cancel, capability loss — because a stale drag
	-- point would leave a scroll host autoscrolling with nothing being dragged.
	local function clearPointerDrag()
		if renderController ~= nil and type(renderController.setPointerDrag) == "function" then
			renderController.setPointerDrag(nil)
		end
	end

	-- full drag reset (invalid drop, external cancel, lifted row vanished)
	function cancelDrag()
		rowDrag = nil
		dragging:set(false)
		suppressActivatePath = nil
		clearPointerDrag()
	end

	-- the edit-mode handle reorders on EVERY pointer type: it reuses the row
	-- drag closures but presents the position as a mouse pointer so the
	-- touch->pan routing in the row-body handlers never triggers
	local handleDragHandlers -- assigned after rowPointerHandlers

	-- the drag's geometry AS IT IS NOW, in the same WINDOW space the pointer
	-- arrives in. Re-asked on every move and on the drop, because a table is not
	-- nailed to the screen for the length of a gesture: the shipped playlist
	-- example is a BLOCK table inside a scrolling page, and one touch both drags
	-- the row handle and pans that page. Falls back to the pickup-frame rects only
	-- when a path stops resolving (a row unmounting under a live capture).
	local function liveDragRects(drag: any): (any, any)
		local rootRect, bodyRect = drag.rootRect, drag.bodyRect
		if drag.rectOf ~= nil and drag.rootPath ~= nil then
			local root = drag.rectOf(drag.rootPath)
			local body = drag.rectOf(drag.rootPath .. "/Main/Body")
			if root ~= nil then
				rootRect = root
			end
			if body ~= nil then
				bodyRect = body
			end
		end
		return rootRect, bodyRect
	end

	-- THE DRAG'S WHOLE VISIBLE ANSWER FOR ONE POINTER POINT: drop slot, drop line,
	-- ghost. Extracted from `onPointerMove` because the pointer is no longer the
	-- only thing that moves the drag — edge autoscroll moves the CANVAS under a
	-- finger that is standing still, and the verdict has to be recomputed from the
	-- same point against the new geometry, in the SAME frame (the correctness core
	-- VirtualList's SF-L2 stepper spells out: a tick-late re-resolve lags about two
	-- rows at the top speed).
	local function applyDragPosition(pos: { x: number, y: number })
		if rowDrag == nil then
			return
		end
		rowDrag.pointer = { x = pos.x, y = pos.y }
		-- TELL THE SCROLL HOSTS. A reorder that can only reach the rows already on
		-- screen is not a reorder, and the host that has to move is usually the page
		-- above this table, not its own Body — so the table publishes the drag point
		-- and a re-resolve callback, and whichever ScrollView the point is at the
		-- edge of decides whether to scroll (ScrollView `autoscroll`).
		if renderController ~= nil and type(renderController.setPointerDrag) == "function" then
			renderController.setPointerDrag({
				pos = rowDrag.pointer,
				-- SAME FRAME, SAME POINT: after the canvas moves under a finger that is
				-- standing still, the ghost and the drop verdict are both stale until
				-- this re-runs (the correctness core SF-L2 spells out — a tick-late
				-- re-resolve lags about two rows at the top speed).
				refresh = function()
					if rowDrag ~= nil and rowDrag.active and rowDrag.pointer ~= nil then
						applyDragPosition(rowDrag.pointer)
					end
				end,
			})
		end
		local rootRect, bodyRect = liveDragRects(rowDrag)
		-- canvas-relative pointer y: add the scroll mirror so the drop slot
		-- is correct even while the body is natively scrolled (native §4)
		local slot, boundaryY = insertSlotAt(pos.y - bodyRect.y + scrollTop:get())
		rowDrag.slot = slot
		-- the drop indicator lives OUTSIDE the scroll region (root overlay),
		-- so translate the canvas boundary back to viewport space by the mirror
		indicatorY:set(bodyRect.y - rootRect.y + boundaryY - scrollTop:get())
		ghostX:set(pos.x - rootRect.x + 16)
		ghostY:set(pos.y - rootRect.y - 13)
	end

	-- while editing, a press landing in the LEADING handle gutter belongs to
	-- the ≡ grip: DECLINE (return false) so the grip's own began (which the
	-- engine may deliver before or after this one) takes the capture
	-- (live-found 2026-07-20: the row hit won the race and the handle drag
	-- never started). Extracted (Task 10) so the composed row-actions
	-- dispatcher's own Hit handler can run the IDENTICAL check BEFORE it ever
	-- defers to the axis lock — a wrapped, reorderable, editing row must keep
	-- this exact decline, unchanged, ahead of any row-actions gesture.
	local function isHandleZonePress(path: string, pos: any, rectOf: (string) -> any): boolean
		if not (editingSignal:get() and string.match(path, "/Row/Hit$") ~= nil) then
			return false
		end
		-- THE GRAB ZONE IS READ, NOT RE-DERIVED (director report 2026-07-28).
		-- This used to be `rowRect.x + HANDLE_GUTTER`, which stopped
		-- describing where the ≡ actually is the moment the zone moved
		-- inboard by the row card's carved border — so under a skinned
		-- package the declined band and the painted grip were 16px apart.
		-- Asking for the zone's own rect is the same "one verdict for
		-- measure and paint" rule the rest of this file runs on; the
		-- arithmetic stays only as the fallback for the frame before the
		-- zone is solved.
		local rowPath = string.match(path, "^(.*)/Hit$")
		local zoneRect = if rowPath ~= nil then rectOf(rowPath .. "/EditWhen/then/HandleZone") else nil
		if zoneRect ~= nil then
			return pos.x <= zoneRect.x + zoneRect.w
		end
		local rowRect = rectOf(path)
		return rowRect ~= nil and pos.x <= rowRect.x + HANDLE_GUTTER
	end

	local function rowPointerHandlers(): any
		if spec.reorderable ~= true then
			return nil
		end
		return {
			onPointerDown = function(path: string, pos: any, rectOf: (string) -> any)
				if isHandleZonePress(path, pos, rectOf) then
					return false
				end
				-- TOUCH on the row body DECLINES the capture (return false) so the
				-- native ScrollingFrame owns the pan-scroll (native §4 — the
				-- hand-rolled touch-pan is retired). Reorder on touch rides the
				-- edit-mode ≡ handle; MOUSE keeps the direct drag below.
				if pos.pointerType == "touch" then
					return false
				end
				-- a fresh press clears any stale drag-artifact suppression
				suppressActivatePath = nil
				local rowKey = api.rowKeyForPath(path)
				local rootPath = string.match(path, "^(.*)/Main/Body/")
				local bodyRect = rootPath and rectOf(rootPath .. "/Main/Body")
				local rootRect = rootPath and rectOf(rootPath)
				if rowKey == nil or bodyRect == nil or rootRect == nil then
					return
				end
				-- REDTEAM FIX (item 2, MAJOR; final-review-findings.md).
				-- Hoisted here from `handleDragHandlers` below (deleted there
				-- as a redundant duplicate) — THIS function is the one funnel
				-- both a plain reorderable row's own Hit press AND the
				-- edit-mode ≡ handle's press (`handleDragHandlers`'s own
				-- `base = rowPointerHandlers()`) share, but it is ALSO what
				-- `row_actions.composeWithReorder` replays into once a
				-- composed BODY-drag gesture resolves "reorder" (this
				-- function is the `reorderHandlers` it is handed — see
				-- `rowBlueprint` below) — a path the tray-close guard used to
				-- never reach, so dragging a wrapped+reorderable row's own
				-- BODY (not the ≡ handle) out from under an open tray left it
				-- visually stranded. Same for the gamepad/keyboard grab
				-- branch in `api.handleActivate` below, which never went
				-- through either copy at all — closed there directly instead,
				-- at its own entry point, for the identical reason.
				local rowActionsInstance = rowActionsByKey[rowKey]
				if rowActionsInstance ~= nil and rowActionsInstance._isOpen() then
					rowActionsInstance._close()
				end
				local item
				for _, candidate in spec.rows:get() do
					if spec.key(candidate) == rowKey then
						item = candidate
					end
				end
				rowDrag = {
					rowKey = rowKey,
					item = item,
					startY = pos.y,
					active = false,
					-- THE LOOKUP, NOT THE ANSWER (device report 2026-07-28, gallery
					-- example 02 on an iPhone 15 Pro: "when I pick up a row it
					-- doesn't always appear under my finger, the picked up chip
					-- moves up as I scroll down"). These used to be the rects
					-- themselves, read once here. A table can MOVE ON SCREEN
					-- mid-drag — the shipped example is a BLOCK table in a
					-- scrolling page, and on touch the very gesture that drags the
					-- handle also pans that page — so a rect read at pickup
					-- describes where the table WAS, and every frame after the
					-- first the ghost, the drop line and the drop verdict were off
					-- by the page's scroll offset. Keep the live lookup instead and
					-- ask it again on every move; `rootRect`/`bodyRect` below are
					-- the pickup-frame FALLBACK for the case the paths stop
					-- resolving mid-drag (a row that unmounts under a live capture).
					rootPath = rootPath,
					rectOf = rectOf,
					bodyRect = bodyRect,
					rootRect = rootRect,
					slot = 0,
				}
			end,
			onPointerMove = function(path: string, pos: any)
				if rowDrag == nil then
					return
				end
				if not rowDrag.active then
					if math.abs(pos.y - rowDrag.startY) < DRAG_THRESHOLD then
						return
					end
					rowDrag.active = true
					-- armed at threshold: an Activated for the origin row is
					-- a drag artifact, whichever side of InputEnded it lands
					suppressActivatePath = path
					-- dragging a SELECTED row picks up the whole selection
					-- (document order); an unselected row drags alone
					local selected = selectedKeys:get()
					local group: { string } = {}
					if selectionMode ~= "none" and selected[rowDrag.rowKey] == true then
						for _, item in spec.rows:get() do
							local key = spec.key(item)
							if selected[key] == true then
								table.insert(group, key)
							end
						end
					end
					if #group < 2 then
						group = { rowDrag.rowKey }
					end
					rowDrag.keys = group
					ghostText:set((spec.dragLabel or spec.key)(rowDrag.item))
					ghostCount:set(#group)
					dragging:set(true)
				end
				applyDragPosition(pos)
			end,
			onPointerUp = function(_path: string, pos: any)
				if rowDrag == nil then
					return
				end
				local drag = rowDrag
				rowDrag = nil
				clearPointerDrag()
				if not drag.active then
					return
				end
				dragging:set(false)
				-- valid drop: inside the table, dragged keys still present. The rect is
				-- re-read here for the same reason the move re-reads it — the table may
				-- have travelled since pickup, and a stale rect rejects a drop the
				-- player made squarely inside the list.
				local rootRect = liveDragRects(drag)
				local inside = pos.x >= rootRect.x
					and pos.x <= rootRect.x + rootRect.w
					and pos.y >= rootRect.y
					and pos.y <= rootRect.y + rootRect.h
				if inside and spec.onReorder then
					local draggedSet: { [string]: boolean } = {}
					for _, key in drag.keys do
						draggedSet[key] = true
					end
					-- refresh the group against the CURRENT document order
					-- (rows may have churned mid-drag)
					local currentKeys: { [string]: number } = {}
					local ordered: { string } = {}
					local dragKeys: { string } = {}
					local remaining: { string } = {}
					local index0 = 0
					local draggedAboveSlot = 0
					for _, item in spec.rows:get() do
						local key = spec.key(item)
						table.insert(ordered, key)
						if draggedSet[key] then
							table.insert(dragKeys, key)
							if index0 < drag.slot then
								draggedAboveSlot += 1
							end
						else
							table.insert(remaining, key)
						end
						index0 += 1
					end
					local _ = currentKeys
					if #dragKeys > 0 then
						-- full-list slot -> post-removal slot (dragged rows
						-- above the insertion point no longer count)
						local slot = drag.slot - draggedAboveSlot
						-- suppress drops that reproduce the current order
						-- (the documented consumer splice, precomputed)
						local predicted = table.clone(remaining)
						for offset, key in dragKeys do
							table.insert(predicted, slot + offset, key)
						end
						local identical = #predicted == #ordered
						if identical then
							for i, key in predicted do
								if ordered[i] ~= key then
									identical = false
									break
								end
							end
						end
						if not identical then
							spec.onReorder(dragKeys, slot)
						end
					end
				end
			end,
			onPointerCancel = function(_path: string, _reason: string?)
				-- row removed by data churn, root teardown, or a system
				-- interrupt (Roblox menu opened mid-drag): abort, no commit
				cancelDrag()
				return nil
			end,
		}
	end

	-- cells inset content horizontally and center it vertically by default
	-- (director hand-test 2026-07-20: content sat flush at the cell origin);
	-- vertical centering rides the ZStack's inherited alignV, so a consumer
	-- blueprint can still override its own alignV
	-- horizontal content inset per cell: the theme's small step unless the
	-- caller pins a number (which opts that value out of theming)
	local cellPadding = spec.cellPadding or "s"

	function handleDragHandlers(): any
		local base = rowPointerHandlers()
		local function asMouse(pos: any): any
			return { x = pos.x, y = pos.y, pointerType = "mouse" }
		end
		return {
			-- REDTEAM FIX (item 2, MAJOR; final-review-findings.md). The
			-- handle-zone tray-close used to live HERE (item 10's own fix,
			-- prior review round) — but `base` (`rowPointerHandlers()`) now
			-- does the identical close itself, at the ONE funnel every entry
			-- point (a plain reorderable row's Hit press, this handle's own
			-- press, AND the composed body-drag replay) shares, so a second
			-- copy here would only ever run twice, never cover a path the
			-- shared one does not already reach. Deleted, not duplicated.
			onPointerDown = function(path: string, pos: any, rectOf: (string) -> any)
				base.onPointerDown(path, asMouse(pos), rectOf)
			end,
			onPointerMove = function(path: string, pos: any)
				base.onPointerMove(path, asMouse(pos))
			end,
			onPointerUp = function(path: string, pos: any)
				base.onPointerUp(path, asMouse(pos))
			end,
			onPointerCancel = base.onPointerCancel,
		}
	end

	local function rowBlueprint(entry: any, itemScope: any): any
		local item = entry.item
		local rowKey = spec.key(item)
		-- rows flow at their NATURAL document positions inside the native scroll
		-- host — no per-row offset (native §4). The engine owns the offset via
		-- CanvasPosition; partial rows crop through the ScrollingFrame's clip.
		--
		-- BOTH ARE PER ROW AND BOTH ARE REACTIVE, and they are memos on the ROW's own
		-- scope, which the ForEach disposes with the row: `rowHeight` may be a
		-- function of the item, so one table-wide answer would be a guess, and the
		-- derived height moves under a theme swap or an accessibility text change —
		-- which must RE-SOLVE the rows in place, never rebuild them (a rebuild would
		-- drop selection, focus and any live in-cell control).
		local heightDim = itemScope:own(core:memo(function(use)
			return { type = "fixed", px = rowHeightOf(item, use(rowBox)) }
		end))
		-- ...and the cap the cells are measured against IS this row's height: see
		-- rowBoxFor. This is what makes a cell physically unable to paint outside the
		-- row it belongs to, whoever chose the height.
		local cellCap = itemScope:own(core:memo(function(use)
			local box = use(rowBox)
			return capFor(box, rowHeightOf(item, box))
		end))
		local cells = {}
		for _, column in columns do
			local alignment = column.alignment or {}
			table.insert(
				cells,
				UI.ZStack({
					id = `Cell-{column.id}`,
					width = columnDim(column),
					height = { type = "fill", weight = 1 },
					padding = { left = cellPadding, right = cellPadding },
					alignV = ALIGN_V[alignment.v or "center"],
					alignH = ALIGN_H[alignment.h or "leading"],
					children = { cellContentFor(column, item, cellCap) },
				})
			)
		end
		local dragHandlers = rowPointerHandlers()

		-- Task 10: does THIS row wrap in a swipeable action tray? Checked
		-- once, at this row's own mount (the composite's ActionSpec list is
		-- itself a build-time-only fact — same rule row_actions.luau's own
		-- `actionsById` comment states), and validated with the row's own key
		-- in the message so a typo in a five-thousand-row table names the one
		-- row responsible.
		local rowActionsResult: any = nil
		if spec.rowActions ~= nil then
			rowActionsResult = spec.rowActions(item)
			if rowActionsResult ~= nil then
				specGuard.assertKnownKeys(
					"newTable",
					rowActionsResult,
					ROW_ACTIONS_RESULT_KEYS,
					`spec.rowActions result (row '{rowKey}')`
				)
			end
		end

		-- Hit's own handlers: the plain reorder-only wiring (unchanged,
		-- zero-cost) when this row has no actions, or a forward-declared pair
		-- of thin dispatch stubs backfilled once the row_actions instance
		-- exists below (a row_actions instance needs `content` — this WHOLE
		-- row, Hit included — to already exist, so the composed dispatcher
		-- itself cannot exist yet at Hit-build time; `composedRef` is filled
		-- in before `rowBlueprint` returns, long before any real pointer
		-- event could ever reach these stubs — the same forward-declare-then-
		-- backfill shape `handleDragHandlers` above already uses).
		local hitOnPointerDown, hitOnPointerMove, hitOnPointerUp, hitOnPointerCancel
		local composedRef: any = nil
		if rowActionsResult == nil then
			hitOnPointerDown = dragHandlers and dragHandlers.onPointerDown
			hitOnPointerMove = dragHandlers and dragHandlers.onPointerMove
			hitOnPointerUp = dragHandlers and dragHandlers.onPointerUp
			hitOnPointerCancel = dragHandlers and dragHandlers.onPointerCancel
		else
			--[[ A SWIPE IS UNDONE BY ITS OWN RELEASE, unless this remembers it
				(redteam BLOCKER, 2026-08-13). A row's `Hit` is a real engine
				`GuiButton`, so the SAME pointer sequence that swipes it also ends
				in a native `Activated` on it — "whichever side of `InputEnded` it
				lands" (the identical fact `onPointerMove`'s reorder arm and
				`virtual_list.luau`'s `suppressActivatePath` both already record).
				Table armed the suppression only for a MOUSE REORDER drag, which a
				horizontal swipe never becomes: the axis lock hands the gesture to
				`row_actions` instead. So the swipe's own Activated arrived
				unsuppressed and `api.handleActivate` answered it as a tap —
				landing AFTER `InputEnded` it found the tray open and CLOSED it (the
				tray vanished the instant it appeared), landing BEFORE it found no
				tray yet and fired the row's primary action (the swipe played the
				track it was meant to offer a Remove for). Measured on both edges
				and both pointer kinds before the fix.

				`horizontal` is the whole state: did this gesture cross the axis
				lock sideways, i.e. did `row_actions` take it. The rule is the two
				lines below — a pure function of dx/dy against the ONE authored
				constant, ties going vertical — applied here rather than asked of
				`row_actions`, exactly as `virtual_list.luau`'s `hostedResolveAxis`
				applies it in its own host dispatcher. It is deliberately not a
				second copy of the DECISION (`row_actions_state.new(...)` instances
				stay inside the composite): both engines that resolve this gesture
				— `composeWithReorder`'s `resolveAxis` for mouse, the composite's
				own `onPointerMove` for touch — measure from the SAME origin (this
				down) with the SAME constant, so this verdict is theirs. ]]
			local swipeGesture: { originX: number, originY: number, horizontal: boolean }? = nil
			hitOnPointerDown = function(path: string, pos: any, rectOf: (string) -> any)
				-- the handle-zone decline runs FIRST, exactly as it does for
				-- an unwrapped reorderable row — a press in the ≡ gutter must
				-- never be deferred into the axis lock at all.
				if dragHandlers ~= nil and isHandleZonePress(path, pos, rectOf) then
					return false
				end
				--[[ A NEW GESTURE MAKES ANY PENDING SUPPRESSION STALE (the reason
					`virtual_list.luau`'s own hosted dispatcher clears it here too):
					a release that produces no Activated at all — the up landing off
					the button — leaves the arm below with nothing left to clear it.

					THIS IS THE WEAKEST OF THE FOUR CLEARS, NOT THE ONLY ONE, and
					the first draft of it carried a premise that is simply false
					(redteam NEW-2, 2026-08-13): "a real Activated always fires
					between a pointer-up and the next pointer-down, so a still-live
					suppression can never legitimately survive to see another down."
					TWO ACTIVATE PRODUCERS CARRY NO POINTER-DOWN AT ALL — an IAS
					device Activate (gamepad A / keyboard Return, `meta.source ==
					"action"`), and the minimum-target hit expander, a SEPARATE
					`GuiButton` whose press produces no pointer event on this row's
					`Hit` at all (`screen_target.luau`'s `pointerActivateMeta`).
					Either of them can reach `handleActivate` while an arm from a
					silently-ended swipe is still live, and be eaten by it: measured
					on a swipe cancelled mid-gesture (0 -> 0 primary actions where
					13fd3c6 gave 0 -> 1) and on a swipe with a silent release
					(the tray stayed open under a device press that must close it).
					So the arm is cleared on a CANCEL too, and `handleActivate`
					refuses to spend it on a device Activate at all. ]]
				suppressActivatePath = nil
				local accepted = composedRef.onPointerDown(path, pos, rectOf)
				swipeGesture = if accepted == false
					then nil
					else { originX = pos.x, originY = pos.y, horizontal = false }
				return accepted
			end
			hitOnPointerMove = function(path: string, pos: any, rectOf: (string) -> any)
				local gesture = swipeGesture
				if gesture ~= nil and not gesture.horizontal then
					local dx, dy = pos.x - gesture.originX, pos.y - gesture.originY
					if dx * dx + dy * dy >= row_actions_state.AXIS_LOCK_PX ^ 2 and math.abs(dx) > math.abs(dy) then
						gesture.horizontal = true
						-- ARMED AT THE LOCK, NOT AT THE RELEASE, and that is the
						-- difference between fixing one of the two orders and
						-- fixing both: an Activated that lands BEFORE
						-- `InputEnded` has already been dispatched by the time
						-- any `onPointerUp` could arm anything. The reorder half
						-- arms at ITS threshold for the identical reason
						-- (`rowPointerHandlers.onPointerMove` above). Armed once
						-- and left armed through the release: it is cleared by
						-- the one POINTER Activate it swallows, by the cancel
						-- below, by a device Activate, or by the next down.
						suppressActivatePath = path
					end
				end
				composedRef.onPointerMove(path, pos, rectOf)
			end
			hitOnPointerUp = function(path: string, pos: any, rectOf: (string) -> any)
				swipeGesture = nil
				composedRef.onPointerUp(path, pos, rectOf)
			end
			hitOnPointerCancel = function(path: string, reason: string?)
				swipeGesture = nil
				-- A CANCELLED GESTURE HAS NO ARTIFACT COMING (redteam NEW-2,
				-- 2026-08-13). The engine fires no `Activated` for a capture it
				-- took away — the Roblox menu opening, this row unmounting, a
				-- scroll stealing the gesture — so an arm left standing here has
				-- nothing of its own left to swallow and would spend itself on
				-- the next producer that carries no pointer-down: measured as a
				-- dead gamepad A on the very row the player just swiped.
				-- `cancelDrag` clears it on the reorder half for this reason.
				suppressActivatePath = nil
				return composedRef.onPointerCancel(path, reason)
			end
		end

		local rowChildren = {
			UI.Button({
				id = "Hit",
				label = "",
				selected = selectedMemo(rowKey),
				-- reorderable rows must be focusable even with selection off:
				-- gamepad/keyboard reorder is focus + grab (UI-PARADIGM-001),
				-- and the auto Edit/Done toggle must never be a navigation
				-- dead end (live-drive regression 2026-07-21)
				focusable = selectionMode ~= "none" or spec.reorderable == true,
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				onPointerDown = hitOnPointerDown,
				onPointerMove = hitOnPointerMove,
				onPointerUp = hitOnPointerUp,
				onPointerCancel = hitOnPointerCancel,
			}),
			UI.HStack({
				id = "Cells",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				gap = spec.gap or 0,
				padding = cellsEditPadding,
				children = cells,
			}),
		}
		if spec.reorderable == true then
			-- edit-mode reorder handle (touch-scroll design): a trailing ≡
			-- grip; drags on it ALWAYS reorder, any pointer type
			local handleDrag = handleDragHandlers()
			table.insert(
				rowChildren,
				UI.When({
					id = "EditWhen",
					condition = editingSignal,
					thenView = function()
						-- LEADING gutter: a visible ≡ glyph under a grab zone.
						--
						-- THE GUTTER STARTS AT THE CARD, NOT AT THE ROW (director
						-- report 2026-07-28, defect 4: "pixel quest playlist table
						-- drag icon overflows row on the left in edit mode").
						-- Measured live: the row rect began at x=16 and the row's
						-- card art at x=28, so a handle pinned to the raw row rect
						-- drew its ≡ 12px outside the card it belongs to. The cells
						-- pay this inset and the header pays it; this was the one
						-- element of a row that did not.
						return UI.ZStack({
							id = "HandleZone",
							alignH = "start",
							margin = { left = ROW_ART.left },
							width = { type = "fixed", px = HANDLE_GUTTER },
							height = { type = "fill", weight = 1 },
							children = {
								UI.Text({
									id = "HandleGlyph",
									text = "≡",
									textSize = "control",
									role = "secondary",
									alignH = "center",
									alignV = "center",
								}),
								UI.Grip({
									id = "Handle",
									focusable = false,
									width = { type = "fill", weight = 1 },
									height = { type = "fill", weight = 1 },
									onPointerDown = handleDrag.onPointerDown,
									onPointerMove = handleDrag.onPointerMove,
									onPointerUp = handleDrag.onPointerUp,
									onPointerCancel = handleDrag.onPointerCancel,
								}),
							},
						})
					end,
				})
			)
		end
		local rowBp = UI.ZStack({
			id = "Row",
			width = { type = "fill", weight = 1 },
			height = heightDim,
			children = rowChildren,
		})

		if rowActionsResult == nil then
			return rowBp
		end

		-- Task 10: wrap. `externalGesture = true` whenever this row is ALSO
		-- reorderable (Hit above already carries the composed dispatcher;
		-- the composite's own internal Content/Hit Grip would never receive
		-- a single event even if it existed — see row_actions.luau's own
		-- Spec.externalGesture comment). CORRECTED (redteam item 15, LOW):
		-- this used to say the composite "must not ALSO wire its own
		-- competing Content Grip," which undersold the truth — the Grip
		-- mounted regardless, merely unwired, a genuine extra Active
		-- (hit-testable) Instance per wrapped+reorderable row nothing here
		-- disclosed. row_actions.luau now OMITS that node entirely under
		-- `externalGesture`, so a wrapped+reorderable row costs exactly one
		-- fewer Instance than it used to (proven by
		-- table.spec.luau's own "mounts NO internal Content/Hit Grip"
		-- case — whichever perf/instance-count accounting Task 11 later
		-- adds should reflect this). A non-reorderable wrapped row leaves
		-- `externalGesture` false: no composition needed, the composite's
		-- own internal Grip is the row's only pointer surface, exactly
		-- Tasks 3-9's shipped shape.
		local rowActionsApi = row_actions.build(LuauUI, core, {
			id = "RowActions-" .. rowKey,
			-- Task 10: restores the row's normal list-flow width — `content`
			-- (rowBp, its own "Row" node) is ITSELF `width = fill`, which has
			-- nothing intrinsic to measure against once it sits inside a
			-- content-sized composite root (row_actions.luau's own `width`
			-- field comment). Byte-identical to an unwrapped row's own prop.
			width = { type = "fill", weight = 1 },
			content = rowBp,
			leading = rowActionsResult.leading,
			trailing = rowActionsResult.trailing,
			fullSwipe = rowActionsResult.fullSwipe,
			coordinator = rowActionsCoordinator,
			-- Task 9 composition (brief: "pass Table's own editing straight
			-- through"): a destructive-carrying row shows BOTH the edit-mode
			-- leading minus (row_actions' own) and the reorder ≡ handle
			-- (Table's own, in EditWhen above) at once while editing.
			editing = editingSignal,
			env = spec.env,
			-- `rowDeletable`, threaded across `spec.rowActions`' own callback
			-- boundary (director ruling, parity round 3): row_actions has no notion
			-- of an item, so THIS side — which owns both the item and the predicate
			-- — resolves the verdict and the composite evaluates it at commit time
			-- inside its one destructive funnel. `rowCapability.allows` is the same
			-- fail-closed reading `rowSelectable`/`rowMovable` use.
			deletable = if spec.rowDeletable ~= nil
				then function()
					return rowCapability.allows(spec.rowDeletable, itemForKey(rowKey))
				end
				else nil,
			externalGesture = dragHandlers ~= nil,
		})
		composedRef = if dragHandlers ~= nil
			then row_actions.composeWithReorder(rowActionsApi._pointerHandlers, dragHandlers)
			else rowActionsApi._pointerHandlers

		-- a stale prior instance under the SAME rowKey (a resize-triggered
		-- remount — `keyedItems`' own key embeds `widthsVersion`, so a
		-- committed resize mounts a FRESH `itemScope`/tableKey for every row
		-- while the row's own semantic key stays live) is disposed here:
		-- `core:scope()` is an independent root (see `rowActionsByKey`'s own
		-- comment) with nothing else to free it, and the `spec.rows` pruning
		-- observer never sees this key go dark across a resize.
		local staleInstance = rowActionsByKey[rowKey]
		if staleInstance ~= nil then
			staleInstance.dispose()
		end
		rowActionsByKey[rowKey] = rowActionsApi

		return rowActionsApi.blueprint
	end

	-- resize grip (Phase B): a non-button, cursor-hinted pointer zone on the
	-- right edge of a resizable header cell; drag previews a guide line and
	-- commits through the Phase A model (setColumnWidth) on release
	local function gripFor(column: Column): any
		return UI.Grip({
			id = "Grip",
			cursorHint = "colResize",
			-- POINTER ONLY NOW. The grip used to be focusable so a gamepad could
			-- Adjust-resize from it, which meant two focus stops per column (sort
			-- hit, then a 4px divider) and nothing that could ever mean "this
			-- column". The column's focus stop is its HEADER; see `selectedColumn`.
			focusable = false,
			alignH = "end",
			width = { type = "fixed", px = "s" },
			height = { type = "fill", weight = 1 },
			onPointerDown = function(path: string, pos: any, rectOf: (string) -> any)
				local cellPath = string.match(path, "^(.*)/Grip$")
				local rootPath = string.match(path, "^(.*)/Main/Header/")
				local cellRect = cellPath and rectOf(cellPath)
				local rootRect = rootPath and rectOf(rootPath)
				if cellRect == nil or rootRect == nil then
					return
				end
				resizeDrag = {
					columnId = column.id,
					startX = pos.x,
					startWidth = cellRect.w,
					relX = cellRect.x - rootRect.x,
					minWidth = column.minWidth or 24,
					width = cellRect.w,
				}
				previewX:set(resizeDrag.relX + resizeDrag.width)
				resizing:set(true)
			end,
			onPointerMove = function(_path: string, pos: any)
				if resizeDrag == nil then
					return
				end
				resizeDrag.width = math.max(resizeDrag.minWidth, resizeDrag.startWidth + pos.x - resizeDrag.startX)
				previewX:set(resizeDrag.relX + resizeDrag.width)
			end,
			onPointerUp = function()
				if resizeDrag == nil then
					return
				end
				local drag = resizeDrag
				resizeDrag = nil
				resizing:set(false)
				api.setColumnWidth(drag.columnId, drag.width)
			end,
			onPointerCancel = function()
				resizeDrag = nil
				resizing:set(false)
			end,
		})
	end

	-- a column sorts when the owner holds a sortOrder binding AND the column
	-- carries `value` (TableColumn(value:) semantics) or opts in via sortable
	local function isSortable(column: Column): boolean
		return spec.sortOrder ~= nil and (column.value ~= nil or column.sortable == true)
	end

	local children = {}
	if spec.header ~= false then
		local headerCells = {}
		for _, column in columns do
			-- full-contrast title (the secondary tint was unreadable over
			-- world backgrounds — director hand-test 2026-07-20), inset via
			-- its own margin (the header cell stays unpadded so the resize
			-- grip sits at the TRUE column boundary), centered like the cells
			-- ...AND IT HONOURS THE COLUMN'S OWN ALIGNMENT (F-27), through the SAME
			-- ALIGN_H mapping the cells use: a `alignment = { h = "trailing" }`
			-- numeric column used to show a left-aligned heading over
			-- right-aligned numbers — a partially-honoured property, which reads
			-- as a layout bug rather than an unsupported option.
			--
			-- The alignment is spent as a TEXT alignment inside a title box that
			-- fills the header cell minus the cell inset on both sides, rather
			-- than as the cells' container `alignH`, for two reasons: the header
			-- cell itself must stay unpadded (the resize grip sits at the TRUE
			-- column boundary), and a ZStack child's FAR margin is not spent by
			-- end-alignment — so a margin-inset hug title would have sat flush
			-- against the column edge while its cells sat 8px in.
			--
			-- ...and a TRAILING title has to clear the sort mark, which lives at
			-- the same edge of the same ZStack. `sortMarkMargin` is the theme's own
			-- reserve for that glyph ("keeps the ▲/▼ clear"), so a sortable trailing
			-- column spends it as the title's trailing inset instead of the cell
			-- inset — measured, not by luck: at 8px the two were 1px apart under
			-- Studio Neutral's 11px mark, which is a collision in any package whose
			-- mark is wider.
			local headAlignment = column.alignment or {}
			local titleTrailingInset = if headAlignment.h == "trailing" and isSortable(column)
				then "controls.table.sortMarkMargin"
				else cellPadding
			local title = UI.Text({
				id = "Title",
				text = column.title or column.id,
				textSize = "label",
				width = { type = "fill", weight = 1 },
				margin = { left = cellPadding, right = titleTrailingInset },
				textAlign = ALIGN_H[headAlignment.h or "leading"],
				-- ONE LINE, ALWAYS. A two-word title ("Track Name") that wrapped
				-- would push the header band down by a whole line the moment a
				-- column got narrow, and a heading that reflows out of alignment
				-- with its own column is worse than an ellipsis. The band FLOORS at
				-- `headerHeight` and grows to fit that one line (see the Head-<id>
				-- box below), so a raised text preference makes the header taller
				-- rather than making the title overflow it.
				lineLimit = 1,
				-- the column's disclosure declaration covers the title it caps
				-- (Step 8.5 LT-G2)
				disclose = if column.disclose == true then true else nil,
			})
			local headerChildren = {}
			-- ONE FOCUS STOP PER COLUMN, AND IT IS THE HEADER (director 2026-07-29).
			-- It mounts for a sortable column OR a resizable one, because both verbs
			-- now come through the same selectable handle: a pointer TAP still sorts
			-- (the universal convention, unchanged), while a device Activate selects
			-- the column and hands Left/Right and Up/Down to it.
			local columnHandle = isSortable(column) or column.resizable == true
			if columnHandle then
				-- the sort hit fills the header cell (under title/grip). Under
				-- THE COLUMN HANDLE. It fills the header cell under the title and
				-- the mark, and it is the column's single focus stop: it joins the
				-- contributed "headers" NavigationGroup (buildFocusGroups) as a
				-- leading horizontal group. A pointer tap on it sorts; a device
				-- Activate selects the column (see handleActivate).
				local columnId = column.id
				table.insert(
					headerChildren,
					UI.Button({
						id = "Column",
						label = "",
						focusable = true,
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
					})
				)
				table.insert(headerChildren, title)
				if isSortable(column) then
					table.insert(
						headerChildren,
						UI.Text({
							id = "SortMark",
							text = scope:own(core:memo(function(use)
								local order = use(spec.sortOrder)
								if order == nil or order.column ~= columnId then
									return ""
								end
								return if order.ascending then "▲" else "▼"
							end)),
							textSize = "controls.table.sortMarkTextSize",
							alignH = "end",
							margin = { right = "controls.table.sortMarkMargin" },
						})
					)
				end
			else
				table.insert(headerChildren, title)
			end
			if column.resizable == true then
				table.insert(headerChildren, gripFor(column))
			end
			table.insert(
				headerCells,
				UI.ZStack({
					id = `Head-{column.id}`,
					width = headerDim(column),
					-- A FLOOR, NOT A CAP (director 2026-08-06: "the edit button
					-- overlaps the heading at largest text"; and the standing ask,
					-- "if height is the issue why can't we make the whole table have
					-- more height as text size increases"). This was `fixed`, so at
					-- the Largest text preference a ONE-LINE title measured 34px
					-- inside a 28px box and painted straight out of it — over the
					-- toolbar above and the first row below. The solver had been
					-- saying so all along: `Head-<id>/Title` reported "overflows its
					-- zstack by 0x6px ... give the box room — a `minMax` FLOOR rather
					-- than a fixed CAP". This is that floor. The token is what a
					-- header band should never be SHORTER than; the live text facts
					-- decide how much taller it has to be, so the header grows with
					-- the preference and the band below it moves down with it.
					-- Same defect class as the row box (§3 of paradigm_table.spec):
					-- a fixed px height against unfixed content.
					height = { type = "minMax", min = "controls.table.headerHeight" },
					alignV = "center",
					children = headerChildren,
				})
			)
		end
		table.insert(
			children,
			UI.HStack({
				id = "Header",
				width = { type = "fill", weight = 1 },
				gap = spec.gap or 0,
				-- THE HEADER IS NOT A ROW, but its columns have to line up with the
				-- rows' columns, so it pays the same horizontal reservation the row
				-- art costs (see ROW_ART). It carries no card of its own and so no
				-- vertical inset. Zero under every flat package.
				--
				-- ...AND THE SAME GLOW GUTTER THE ROWS' VIEWPORT PAYS (2026-07-27).
				-- The rows live in a ScrollView, and a clipper insets its content by
				-- at least `chromeBleed` or the package's shadow is cut at its edge.
				-- The header is OUTSIDE that viewport, so without this it stayed put
				-- while the rows moved in and the columns came apart by exactly the
				-- bleed. A multi-metric side ADDS its entries on every solve, which
				-- is what lets one declaration mean "clear the viewport's glow
				-- gutter AND then the row card's carved border" — two gutters at two
				-- nesting levels, so they genuinely stack.
				padding = {
					left = { ROW_ART.left, "chromeBleed" },
					right = { ROW_ART.right, "chromeBleed" },
				},
				children = headerCells,
			})
		)
	end
	-- THE BODY IS A VIEWPORT OR A BLOCK (see `spec.scrolls`). As a block it is a
	-- plain stack: no ScrollingFrame, no clip, and a content height — so the rows
	-- simply lay out and whatever the host scrolls carries them. Nesting a
	-- scroller inside a scrolling page is the thing this avoids: a vertical drag
	-- over the rows would be ambiguous, and the inner one always wins.
	local bodySpec: any = {
		id = "Body",
		width = { type = "fill", weight = 1 },
		height = if spec.scrolls == false then { type = "content" } else { type = "fill", weight = 1 },
		-- the blueprint takes the DECLARED value: a metric name resolves in the
		-- solver against the same live snapshot `rowGapPx` reads, so the painted
		-- gutter and the arithmetic can never disagree
		gap = spec.rowGap or 0,
	}
	if spec.scrolls ~= false then
		bodySpec.axis = "y"
		-- native scroll + clip host (native-substrate NS-A2): the adapter
		-- mounts a ScrollingFrame; the ENGINE owns the offset (wheel, touch
		-- pan, momentum), the solver's content sum becomes CanvasSize, and
		-- partial rows crop. No hand-rolled wheel handler (native §4).
		bodySpec.clipChildren = true
	end
	table.insert(
		children,
		(if spec.scrolls == false then UI.VStack else UI.ScrollView)({
			id = bodySpec.id,
			width = bodySpec.width,
			height = bodySpec.height,
			gap = bodySpec.gap,
			axis = bodySpec.axis,
			clipChildren = bodySpec.clipChildren,
			children = {
				UI.ForEach({
					id = "Rows",
					items = keyedItems,
					key = function(entry)
						return entry.tableKey
					end,
					row = rowBlueprint,
				}),
			},
		})
	)

	-- THE TOOLBAR GOES FIRST, IN THE FLOW (director round 12; see the block's own
	-- note). `Main` is a VStack, so a row inserted at the front pushes the header
	-- and the body down by exactly its height instead of covering them.
	table.insert(
		children,
		1,
		UI.When({
			id = "ToggleWhen",
			-- built-in Edit/Done affordance (touch-scroll design): shown
			-- automatically when edit mode is the ONLY route to a
			-- capability this table declares (reordering, or touch
			-- selection on a table that declares `onPrimaryAction`), the
			-- OWNER supplied no editing signal, and a non-mouse class is
			-- live (mouse users scroll with the wheel, drag directly and
			-- select by plain click, so they never need edit mode). The
			-- whole predicate and its principle are written out at THE AUTO
			-- EDIT/DONE TOGGLE, above. Without an env the table cannot know
			-- the input, so the toggle always shows.
			--
			-- IT IS A TOOLBAR ROW, NOT A FLOATING BADGE (director round 12,
			-- 2026-07-27: "the edit button is overlapping the table in all
			-- themes"). It used to be an ANCHOR child of the table root,
			-- pinned to the top-right corner and consuming no height —
			-- which was invisible only because it was 24px tall and the
			-- header band it covered was 28. Once the button was allowed to
			-- grow for a theme's own frame (round 10) it became 34-68px tall
			-- and sat on top of the header AND the first row, in every
			-- package. An affordance that overlaps the content it acts on is
			-- a floating badge; this is a toolbar, so it takes a row and the
			-- table lays out beneath it.
			condition = showAutoToggle,
			thenView = function()
				return UI.HStack({
					id = "Toolbar",
					width = { type = "fill", weight = 1 },
					children = {
						UI.Spacer({}),
						UI.Button({
							id = "EditToggle",
							label = editToggleLabel,
							-- WHAT IT SAYS WHEN THE TOOLBAR IS TOO NARROW FOR A WORD
							-- (director, 2026-07-27). This is the button the whole
							-- `compactLabel` feature came from: under fantasy-parchment
							-- its reserved column equalled the drawn text to the pixel,
							-- and a one-pixel disagreement broke "Done" into "Don"/"e".
							-- Round 6 made that an honest ellipsis; this makes it a
							-- pencil instead, because a button with something better
							-- to say must not fall back to the "…".
							--
							-- ONE mark for both states, not a pencil that becomes a
							-- tick: `compactLabel` is deliberately NOT reactive,
							-- because a reactive value skips `schema.checkValue`
							-- entirely and a brand-new closed grammar cannot afford an
							-- unvalidated door (enum-props-accept-any-string). The mark
							-- means "this is the editing affordance", true either way.
							--
							-- It costs nothing while there IS room: the ladder's first
							-- rung is the full label, and this toggle grows to fit its
							-- word in all nine packages today (56 -> 108 under Glossy
							-- Touch), so the shipped look does not move.
							compactLabel = { icon = "edit" },
							surface = "control",
							padding = "controls.table.editTogglePadding",
							-- A FLOOR, NOT A CAGE (director round 10, found live
							-- 2026-07-26). These were `fixed`, so the box could not grow
							-- for the theme's own chrome: a package that skins `control`
							-- with inset-bearing art reserves those insets INSIDE the 56px
							-- and lifts the label into what is left. Under Glossy Touch
							-- (contentInsets 14 a side) "Edit" was drawn in 16px and read
							-- as "E"; under Pixel Quest (16 a side) the plate came back
							-- EMPTY. The token is what the button should never be smaller
							-- than — the theme decides how much bigger it has to be.
							width = { type = "minMax", min = "controls.table.editToggleWidth" },
							height = { type = "minMax", min = "controls.table.editToggleHeight" },
						}),
					},
				})
			end,
		})
	)

	-- root: an Anchor so drag guides overlay the content without joining any
	-- stack flow; all regular content lives under /Main
	local blueprint = UI.Anchor({
		id = tableId,
		width = { type = "fill", weight = 1 },
		-- a block table sizes to its rows so the HOST's scroller can move them;
		-- a viewport table fills the space it was given and scrolls inside it
		height = spec.height or (if spec.scrolls == false then { type = "content" } else { type = "fill", weight = 1 }),
		children = {
			UI.VStack({
				id = "Main",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				gap = "controls.table.rowGap",
				children = children,
			}),

			UI.When({
				id = "ResizeWhen",
				condition = resizing,
				thenView = function()
					return UI.Box({
						id = "ResizeLine",
						anchor = "topLeft",
						offsetX = previewX,
						surface = "accent",
						width = { type = "fixed", px = "controls.table.indicatorThickness" },
						height = { type = "fill", weight = 1 },
					})
				end,
			}),
			UI.When({
				id = "DropWhen",
				condition = dragging,
				thenView = function()
					return UI.Box({
						id = "DropLine",
						anchor = "topLeft",
						offsetY = indicatorY,
						surface = "accent",
						width = { type = "fill", weight = 1 },
						height = { type = "fixed", px = "controls.table.indicatorThickness" },
					})
				end,
			}),
			UI.When({
				id = "GhostWhen",
				condition = dragging,
				thenView = function()
					-- the "picked up" ghost: a CHIP STACK follows the pointer.
					-- Multiplicity is visual (director round 3): up to three
					-- chips, each 2px behind-and-offset from the one in front
					-- (drag 2 -> 2 chips, drag 5 -> 3 chips); the front chip
					-- carries the label. The standing pattern for dragging
					-- multiple items anywhere, never a "+N" suffix.
					local chips = {}
					local count = math.min(ghostCount:get(), 3)
					-- back-to-front: the deepest chip first so the front chip
					-- paints last (deterministic z = tree-walk order)
					for i = count, 1, -1 do
						local offset = (i - 1) * 2
						table.insert(
							chips,
							UI.ZStack({
								id = `Chip{i}`,
								margin = { top = offset, left = offset },
								width = { type = "fixed", px = "controls.table.ghostWidth" },
								height = { type = "fixed", px = "controls.table.ghostHeight" },
								padding = { left = "s" },
								alignV = "center",
								surface = "chip",
								children = if i == 1
									then { UI.Text({ id = "Label", text = ghostText, textSize = "label" }) }
									else {},
							})
						)
					end
					return UI.ZStack({
						id = "DragGhost",
						anchor = "topLeft",
						offsetX = ghostX,
						offsetY = ghostY,
						width = { type = "fixed", px = "controls.table.ghostStackWidth" },
						height = { type = "fixed", px = "controls.table.ghostStackHeight" },
						children = chips,
					})
				end,
			}),
		},
	})

	api.selectedKeys = selectedKeys

	local function orderedKeys(): { string }
		local keys = {}
		for _, item in spec.rows:get() do
			table.insert(keys, spec.key(item))
		end
		return keys
	end

	local function rangeKeys(fromKey: string, toKey: string): { [string]: boolean }
		local keys = orderedKeys()
		local fromIndex = table.find(keys, fromKey)
		local toIndex = table.find(keys, toKey)
		if fromIndex == nil or toIndex == nil then
			return { [toKey] = true }
		end
		local selectedRange = {}
		for i = math.min(fromIndex, toIndex), math.max(fromIndex, toIndex) do
			selectedRange[keys[i]] = true
		end
		return selectedRange
	end

	-- the moving block for a grabbed row: the selection (document order) when the
	-- grabbed row is selected, else the grabbed row alone (mirrors
	-- handleGrabNavigate). Used to snapshot the pre-grab origin for §C revert.
	local function computeGrabBlock(grabbed: string): ({ string }, { [string]: boolean })
		local selected = selectedKeys:get()
		local block: { string } = {}
		if selectionMode ~= "none" and selected[grabbed] == true then
			for _, item in spec.rows:get() :: { any } do
				local key = spec.key(item)
				if selected[key] == true then
					table.insert(block, key)
				end
			end
		end
		if #block < 1 then
			block = { grabbed }
		end
		local blockSet: { [string]: boolean } = {}
		for _, key in block do
			blockSet[key] = true
		end
		if blockSet[grabbed] ~= true then
			block = { grabbed }
			blockSet = { [grabbed] = true }
		end
		return block, blockSet
	end

	-- post-removal slot of a block: staying rows above the block's first row
	local function stayingAbove(blockSet: { [string]: boolean }): number
		local above = 0
		local seen = false
		for _, item in spec.rows:get() :: { any } do
			if blockSet[spec.key(item)] then
				seen = true
			elseif not seen then
				above += 1
			end
		end
		return above
	end

	-- select modes (Phase B): "toggle" flips membership, "range" extends from
	-- the anchor, "replace" selects exactly this row. Default (no opts): the
	-- Phase A idioms — single replaces, multi toggles additively (touch).
	function api.select(rowKey: string, opts: { mode: string? }?)
		if selectionMode == "none" then
			return
		end
		--[[ PER-ROW OPT-OUT, AT THE FUNNEL AND ABOVE THE MODE BRANCH.
			`api.select` has four branches below (single, replace, range,
			additive toggle) and every pointer/key/pad path in this control
			routes through this one function. Gating here rather than inside a
			branch is deliberate: a guard on the single-select branch alone
			would pass a naive test and leak on the touch idiom's toggle. ]]
		if not rowCapability.allows(spec.rowSelectable, itemForKey(rowKey)) then
			return
		end
		local mode = opts and opts.mode
		if selectionMode == "single" then
			selectedKeys:set({ [rowKey] = true })
			selectionAnchor = rowKey
			return
		end
		if mode == "replace" then
			selectedKeys:set({ [rowKey] = true })
			selectionAnchor = rowKey
		elseif mode == "range" then
			selectedKeys:set(rangeKeys(selectionAnchor or rowKey, rowKey))
		else -- additive toggle (touch idiom and the Phase A default)
			local next = table.clone(selectedKeys:get())
			if next[rowKey] then
				next[rowKey] = nil
			else
				next[rowKey] = true
			end
			selectedKeys:set(next)
			selectionAnchor = rowKey
		end
	end

	function api.clearSelection()
		selectedKeys:set({})
		selectionAnchor = nil
	end

	--[[ ===== THE PRIMARY ACTION (parity round 2 §3.4) =========================
		SELECTING a row and OPENING it are two different verbs, and a table that
		can only say one of them is a table you cannot build a detail screen on.
		`onPrimaryAction` is the second verb, and it is reachable on all four
		inputs with NO invented gesture:

		  pointer    double-click                       (the desktop idiom)
		  keyboard   Return on the focused row          (meta.source == "action")
		  gamepad    A / Cross on the focused row       (same seam — the presenter
		                                                 binds both to Activate)
		  touch      a plain SINGLE TAP on any row; edit mode is where touch
		             selection lives instead

		THE NAME IS OURS, THE TOUCH RULE IS APPLE'S. SwiftUI has no
		`onPrimaryAction` symbol at all — it delivers this verb as the
		`primaryAction:` argument of
		`contextMenu(forSelectionType:menu:primaryAction:)`, whose documentation
		is the rule implemented here, verbatim: "In macOS, a single click on a row
		in a selectable container selects that row, and a double click performs
		the primary action. In iOS and iPadOS, tapping on the row activates the
		primary action. To select a row without performing an action, either enter
		edit mode or hold shift or command on a keyboard while tapping the row."

		EDIT MODE IS THE TOUCH SELECTION MODE, and that is the half that makes the
		first half affordable — `EditMode`: "On devices without an attached
		keyboard and mouse or trackpad, people can make multiple selections in
		lists only when edit mode is active"; HIG Lists and tables: "In iOS and
		iPadOS, people must enter an edit mode before they can select table
		items". So in edit mode a tap TOGGLES selection and never opens — which
		hands back `multi`'s tap-to-DESELECT gesture in the one mode a phone
		player is deliberately in to manage selection. REACHING that mode is not
		left to chance: because touch selection is edit-mode-only, declaring
		`onPrimaryAction` on a selectable table is itself enough to auto-show
		Table's Edit/Done toggle on a non-mouse session (THE AUTO EDIT/DONE TOGGLE,
		above — the toggle follows the capability set, and this is one of its two
		members). `spec.editing` / `api.editing` remains the seam for a consumer who
		would rather own the affordance.

		THE COST IS REAL AND DELIBERATE, NOT AN OVERSIGHT. With a primary action
		declared, touch loses tap-to-select in NORMAL mode entirely — including
		the SINGLE selection iOS 16+ would otherwise allow ("When people make a
		single selection by tapping or clicking, the selected cell changes its
		appearance… To enable multiple selections with tap gestures, put the list
		into edit mode"): declaring the action is exactly what makes a list retreat
		into edit mode for selection. Apple accepts that trade; so do we. THE
		COROLLARY IS THE AUTHOR'S CALL: if a table's dominant touch use is
		SELECTING rather than OPENING, the right move is not to declare
		`onPrimaryAction` on it at all — with no action declared every gesture
		below behaves exactly as it always did, on every input.

		A double-TAP was never a candidate, and that avoidance was right: HIG
		Gestures documents double tap as ZOOM, and watchOS explicitly warns that
		it conflicts with list navigation.

		Two things the rule deliberately does NOT do:
		  * A modified click (Shift / Cmd / Ctrl) is a SELECTION gesture. It never
		    opens, on any input, even if it happens to land twice inside the
		    double-click window.
		  * A touch tap that opens does NOT touch the selection at all — it
		    neither adds, replaces, nor clears. Opening is not a selection verb,
		    and a selection made in edit mode survives the taps that open rows.
	]]
	-- Windows and macOS both default to 500 ms; nothing on the platform exposes
	-- the player's own setting, so this is the honest shared default rather than
	-- a number invented for this control.
	local DOUBLE_CLICK_WINDOW_S = 0.5
	-- The presenter's own `now` arrives through `bindMotion` (contribution.luau:
	-- "the same source the motion clock uses"), so a scripted suite and the live
	-- client read the same clock. `os.clock` is the bare-mount fallback, exactly
	-- as renderer.luau's own tap-echo window does it.
	local nowFn: () -> number = os.clock
	local lastClickKey: string? = nil
	local lastClickAt: number = 0

	local function firePrimaryAction(rowKey: string): boolean
		local handler = spec.onPrimaryAction
		if handler == nil then
			return false
		end
		local item = itemForKey(rowKey)
		if item == nil then
			-- the row left the data between the gesture and the dispatch; there is
			-- nothing to open, and inventing an item would be worse than nothing
			return false
		end
		handler(item, rowKey)
		return true
	end

	-- A SECOND CLICK IS ONLY A DOUBLE CLICK ON THE SAME ROW, INSIDE THE WINDOW.
	-- Consuming the pair (rather than leaving the timestamp standing) is what
	-- keeps a TRIPLE click from being two double clicks — the third press starts
	-- a fresh pair instead of firing again.
	local function consumeDoubleClick(rowKey: string): boolean
		local at = nowFn()
		if lastClickKey == rowKey and (at - lastClickAt) <= DOUBLE_CLICK_WINDOW_S then
			lastClickKey = nil
			lastClickAt = 0
			return true
		end
		lastClickKey = rowKey
		lastClickAt = at
		return false
	end

	-- routes a presenter activate; returns true when the path was a row hit.
	-- meta (pointer kind + held modifiers) picks the device-correct semantics:
	-- touch/no-meta = additive toggle, plain mouse/key = replace,
	-- ctrl/cmd = toggle, shift = range.
	local function isResizableId(columnId: string): boolean
		for _, column in columns do
			if column.id == columnId then
				return column.resizable == true
			end
		end
		return false
	end

	local function isSortableId(columnId: string): boolean
		for _, column in columns do
			if column.id == columnId then
				return isSortable(column)
			end
		end
		return false
	end

	-- SwiftUI semantics: a new column sorts ascending, the same column flips. The
	-- data owner observes the binding and re-sorts — the table never does.
	local function cycleSort(columnId: string)
		local current = spec.sortOrder:get()
		local ascending = if current ~= nil and current.column == columnId then not current.ascending else true
		spec.sortOrder:set({ column = columnId, ascending = ascending })
	end

	function api.handleActivate(path: string, meta: any?): boolean
		-- the built-in Edit/Done toggle flips edit mode
		if string.match(path, `/{tableIdPattern}/Main/ToggleWhen/then/Toolbar/EditToggle$`) ~= nil then
			editingSignal:set(not editingSignal:get())
			return true
		end
		--[[ gamepad/keyboard A on a focused row while editing = grab/drop —
			ON A TABLE THAT CAN ACTUALLY REORDER, and nothing else (redteam item 3,
			HIGH; 2026-08-13). This branch used to ask only "editing, and a device
			Activate", which was true of exactly one kind of table when it was
			written. Widening the auto Edit/Done toggle put a NON-reorderable
			selectable table with an `onPrimaryAction` into edit mode for the first
			time — and every keyboard Return and every gamepad A on one of its rows
			then dead-ended here, into a grab it can never perform: `grabbedKey`
			set on a table with no `onReorder` to move anything, the row left
			phantom-grabbed, `return true` swallowing the Activate, and the primary
			action unreachable on both devices for as long as edit mode lasted.
			The two `spec` reads below are the SAME pair the one function that
			actually moves a row already demands (`moveRow`: "reorderable ~= true
			or onReorder == nil" declines), so a table that fails them falls
			through to the ordinary device path here exactly as it does outside
			edit mode. ]]
		if
			editingSignal:get()
			and meta ~= nil
			and meta.source == "action"
			and spec.reorderable == true
			and spec.onReorder ~= nil
		then
			local rowKey = api.rowKeyForPath(path)
			if rowKey ~= nil then
				-- REDTEAM FIX (item 2, MAJOR; final-review-findings.md). The
				-- pointer paths (`rowPointerHandlers`'s own funnel) close an
				-- open tray before a reorder can engage; this device-input
				-- grab branch is a THIRD, wholly separate way to start the
				-- identical reorder and never went through either copy —
				-- grabbing a row via gamepad/keyboard left its tray visually
				-- stranded exactly like the pointer half of this same finding.
				-- Closed the same way, at this branch's own entry point,
				-- BEFORE the grab itself engages.
				local rowActionsInstance = rowActionsByKey[rowKey]
				if rowActionsInstance ~= nil and rowActionsInstance._isOpen() then
					rowActionsInstance._close()
				end
				if grabbedKey:get() == rowKey then
					grabbedKey:set(nil) -- drop
					grabOrigin = nil
				else
					grabbedKey:set(rowKey) -- grab: snapshot the pre-grab origin (§C revert)
					local block, blockSet = computeGrabBlock(rowKey)
					grabOrigin = { block = block, slot = stayingAbove(blockSet) }
				end
				return true
			end
		end
		-- THE COLUMN HANDLE ANSWERS TO TWO DIFFERENT VERBS, BY INPUT (director
		-- 2026-07-29). A POINTER tap on a header sorts it — that convention is
		-- older than this table and breaking it would be gratuitous. A DEVICE
		-- Activate SELECTS the column instead, because a stick has nowhere else to
		-- put "resize this" and a selected column is the handle the rest of the
		-- column verbs will hang off. `meta.source == "action"` is the same seam the
		-- row grab already uses to tell the two apart.
		local headColumn = string.match(path, `/{tableIdPattern}/Main/Header/Head%-(.-)/Column$`)
		if headColumn ~= nil then
			if meta ~= nil and meta.source == "action" then
				selectedColumn:set(if selectedColumn:get() == headColumn then nil else headColumn)
				return true
			end
			if spec.sortOrder ~= nil and isSortableId(headColumn) then
				cycleSort(headColumn)
				return true
			end
			return true -- a resize-only header still consumes its own tap
		end
		local rowKey = api.rowKeyForPath(path)
		if rowKey == nil then
			-- REDTEAM FIX (item 11, MEDIUM). `rowKeyForPath` only ever
			-- recognizes a row's OWN `Row/Hit` or reorder-handle path — a
			-- path inside a wrapped row's TRAY, MENU, or edit-mode minus
			-- (row_actions.luau's own mounted structure) matches neither, so
			-- it always fell through to here and returned `false`. That is
			-- harmless when `api.handleActivate` is reached the NORMAL way
			-- (the presenter's own longest-prefix contribution walk finds
			-- row_actions' own `handleActivate` directly, deeper than
			-- Table's) — but a caller who hands the presenter `opts.onActivate`
			-- (presenter.luau's own documented consumer-override seam: "wins
			-- outright") bypasses that walk ENTIRELY, and `tbl.api.handleActivate`
			-- itself is the natural thing to reach for as that override —
			-- which used to silently swallow every tray/menu/minus tap for
			-- every wrapped row on the whole table. `RowActions-<key>` is
			-- Table's OWN chosen root id for a wrapped row (`row_actions.build`'s
			-- own `id` prop, above) — a path under it names its row
			-- unambiguously, so forward straight into that row's own
			-- dispatch via the `_handleActivate` seam it exposes for exactly
			-- this.
			local wrappedKey = string.match(path, `/{tableIdPattern}/Main/Body/Rows/%[.-@%d+%]/RowActions%-(.-)/`)
			if wrappedKey ~= nil then
				local rowActionsInstance = rowActionsByKey[wrappedKey]
				if rowActionsInstance ~= nil then
					return rowActionsInstance._handleActivate(path, meta)
				end
			end
			return false
		end
		--[[ THE DRAG-ARTIFACT TEST RUNS FIRST, ahead of the tap-to-close below,
			and the order is load-bearing (redteam BLOCKER, 2026-08-13). A gesture
			that swiped this row arms the suppression on its own path; the
			Activated the engine then delivers for that same gesture is NOT a tap
			and must not be read as one by ANY branch. Below the close block it
			was never reached in the case that matters — the swipe had just left
			the tray open, so "an open tray means the tap means close" fired on the
			swipe's own artifact and shut the tray in the frame it appeared. ]]
		if suppressActivatePath ~= nil then
			--[[ ...AND IT IS A POINTER'S ARTIFACT, so only a POINTER may spend it
				(redteam NEW-2, 2026-08-13). A drag or a swipe is a pointer gesture
				and the stray `Activated` it leaves behind is a pointer's
				(`screen_target.luau`'s `pointerActivateMeta`: `source ==
				"pointer"`). An IAS device Activate — gamepad A, keyboard Return,
				`source == "action"` — cannot be that artifact under any ordering:
				it carries no pointer at all, and by the time the action system
				dispatches one the gesture's own `Activated` has either already
				arrived (and cleared this) or is never coming. Swallowing it cost
				the player a dead press on the row they had just swiped — the whole
				visible symptom of NEW-2, on both of its reachable paths. ]]
			local deviceActivate = meta ~= nil and meta.source == "action"
			local suppressed = path == suppressActivatePath and not deviceActivate
			-- one decision either way: the origin row's drag-artifact activate
			-- is swallowed; an activate on any OTHER row — or from any device —
			-- is genuine and clears
			suppressActivatePath = nil
			if suppressed then
				return true
			end
		end
		-- Task 10 (iOS tap-to-close, director round). A tap landing on a
		-- wrapped row's own content while THAT row's own tray is open closes
		-- it and consumes the tap — no select, no activate. row_actions' own
		-- `outsideDismiss` already closes it for a tap OUTSIDE this row (any
		-- sibling, or elsewhere on screen); a tap on the SAME row's content is
		-- an INSIDE tap by that check (the path sits under the composite's
		-- own `rootPath`), so it never fires there — this is the one case the
		-- composite genuinely cannot see for itself (it has no notion of
		-- "Table's own row hit"), hence handled here instead.
		local rowActionsInstance = rowActionsByKey[rowKey]
		if rowActionsInstance ~= nil and rowActionsInstance._isOpen() then
			rowActionsInstance._close()
			return true
		end
		if meta == nil or meta.pointer == "touch" then
			--[[ TOUCH, APPLE'S RULE (see the primary-action block above): a plain
				tap ACTIVATES whenever a primary action is declared, and EDIT MODE
				is the selection mode. The tap never falls through to `api.select`
				on the way — including when the row left the data between gesture
				and dispatch, where selecting a row nobody can see would be worse
				than nothing.

				"EDIT MODE IS THE SELECTION MODE" NEEDS A SELECTION TO BE ABOUT
				(redteam item 6, MEDIUM; 2026-08-13). `selection = "none"` +
				`reorderable` is a legal, shipped shape — edit mode there exists to
				put the ≡ handles up, and there is nothing to select. Yielding the
				tap to selection anyway handed it to `api.select`, whose FIRST line
				returns for `"none"`: the tap did nothing whatsoever, on a row whose
				primary action worked perfectly one Edit press earlier. A pure
				regression — the predicate this replaced (before edit mode reached
				these tables) opened the row in both modes. So: edit mode may take
				the tap away from the primary action only when it has a selection
				to give it to. ]]
			if spec.onPrimaryAction ~= nil and (selectionMode == "none" or not editingSignal:get()) then
				firePrimaryAction(rowKey)
				return true
			end
			api.select(rowKey)
		elseif meta.toggle then
			api.select(rowKey, { mode = "toggle" })
		elseif meta.shift then
			api.select(rowKey, { mode = "range" })
		else
			api.select(rowKey, { mode = "replace" })
			-- A DEVICE Activate IS the primary action (Return / ButtonA on the
			-- focused row); a MOUSE click only is when it completes a double click.
			-- `meta.source == "action"` is the same seam the row grab and the
			-- header's two verbs already use to tell a device press from a tap.
			if spec.onPrimaryAction ~= nil then
				local device = meta.source == "action" or meta.pointer == "keyboard" or meta.pointer == "gamepad"
				if device or consumeDoubleClick(rowKey) then
					firePrimaryAction(rowKey)
				end
			end
		end
		return true
	end

	-- row hit paths look like <root>/<tableId>/Main/Body/Rows/[<key>@<v>]/Row/Hit
	-- gamepad grab-mode navigation: while a row is grabbed, d-pad up/down
	-- steps it (or the whole selected block when the grabbed row is selected)
	-- one slot per press through the standard onReorder contract. Returns
	-- true when the direction was consumed (the presenter then skips the
	-- focus move — the row keeps focus because row paths are key-based).
	function api.handleGrabNavigate(direction: string): boolean
		-- A SELECTED COLUMN TAKES THE STICK FIRST (director 2026-07-29). Left/Right
		-- resizes it, Up/Down cycles its sort — the two things you can do to a
		-- column — and nothing else moves while it holds the selection, exactly as
		-- a grabbed row owns Up/Down.
		local column = selectedColumn:get()
		if column ~= nil then
			if direction == "left" or direction == "right" then
				-- swallowed either way: a selection OWNS the stick, so a column with
				-- nothing to resize sits still rather than letting focus slide off
				-- the thing the player just selected
				stepColumnWidth(column, if direction == "right" then 1 else -1)
				return true
			end
			if (direction == "up" or direction == "down") and spec.sortOrder ~= nil and isSortableId(column) then
				cycleSort(column)
				return true
			end
			-- a selected column swallows the rest of the stick rather than letting
			-- focus wander off the thing the player is editing
			return true
		end
		local grabbed = grabbedKey:get()
		if grabbed == nil or editingSignal:get() ~= true or spec.onReorder == nil then
			return false
		end
		if direction ~= "up" and direction ~= "down" then
			return false
		end
		-- the moving block: the selection (document order) when the grabbed
		-- row is selected, else the grabbed row alone
		local selected = selectedKeys:get()
		local block: { string } = {}
		if selectionMode ~= "none" and selected[grabbed] == true then
			for _, item in spec.rows:get() :: { any } do
				local key = spec.key(item)
				if selected[key] == true then
					table.insert(block, key)
				end
			end
		end
		if #block < 1 then
			block = { grabbed }
		end
		local blockSet: { [string]: boolean } = {}
		for _, key in block do
			blockSet[key] = true
		end
		if blockSet[grabbed] ~= true then
			block = { grabbed }
			blockSet = { [grabbed] = true }
		end
		-- current post-removal slot = staying rows above the block's first row
		local stayingAbove = 0
		local stayingTotal = 0
		local seenBlock = false
		for _, item in spec.rows:get() :: { any } do
			local key = spec.key(item)
			if blockSet[key] then
				seenBlock = true
			else
				stayingTotal += 1
				if not seenBlock then
					stayingAbove += 1
				end
			end
		end
		local target = stayingAbove + (if direction == "down" then 1 else -1)
		if target < 0 or target > stayingTotal then
			return true -- consumed at the edge (no wrap while grabbed)
		end
		spec.onReorder(block, target)
		return true
	end

	-- gamepad/keyboard focus map (2026-07-20): the table's mounted subtree as
	-- NavigationGroups — the Edit toggle (when shown) then one HORIZONTAL
	-- group per row, document order: [row hit, ...focusable cell content].
	-- entry="nearest" keeps the column when stepping between rows. Feed the
	-- result to present({ navigationGroups = function(root) ... }).
	--
	-- A ROW IS ITS WHOLE MOUNTED SUBTREE, NOT ITS `Row` NODE (parity round 3,
	-- owed row 8, 2026-08-13). A row that declares `spec.rowActions` is WRAPPED:
	-- `row_actions.build`'s root Anchor sits between the ForEach slot and this
	-- row's own `Row`, and the tray `When`s plus the edit-mode minus are that
	-- wrapper's OTHER children — siblings of `Row`, not descendants. This walk
	-- used to anchor on `Row`, so every focusable the wrapper owns landed in NO
	-- group at all; and a contribution owns its subtree's focus
	-- (`focus_map.autoGroups` emits a contribution's groups and does not descend
	-- into it), so a focusable this function never names is unreachable by Tab
	-- AND by the d-pad. The player-visible defect: swipe a row open with a
	-- finger and no key or pad direction reaches what you revealed, and in edit
	-- mode the minus — the ONLY delete affordance a touch player has — was
	-- unreachable to a keyboard and a pad outright.
	--
	-- THE ROW'S OWN CONTENT STAYS FIRST, and the affordances are appended in edge
	-- order (leading, then trailing). Index 1 of a row group is not a detail: it
	-- is where EVERY vertical entry into a row lands (`focus_graph.enterGroup` —
	-- a perpendicular entry is ORDINAL nearest, and the group above a row has one
	-- stop, so `fromIndex` is 1), so ordering the group by pure left-to-right
	-- geometry would have put the edit-mode MINUS — a Delete button — under the
	-- ring the moment a pad walked down into an editing table. Measured: it
	-- reddened `examples_gallery`'s own end-to-end pad case, which pressed A
	-- expecting to grab a row. The row's own activate is its primary verb and
	-- keeps the primary stop.
	--
	-- The cost, stated rather than hidden: a LEADING affordance is reached by
	-- continuing RIGHT off the row rather than by pressing Left toward where it
	-- is painted. Only one edge can be revealed at a time (the open-edge policy),
	-- so the walk is never ambiguous — but the honest repair is per-row `exit.up`
	-- /`exit.down` declarations, which would free the group array for edge-side
	-- groups the way `newVirtualList` uses them (its row group is VERTICAL, so a
	-- horizontal strip of buttons cannot be spliced into it at all and its hosted
	-- tray needs a group of its own). That is a navigation-model change for
	-- every table, not a reachability fix, and it is not taken here.
	function api.buildFocusGroups(rootNode: any): { any }
		-- capture the mounted root so bindNativeScroll can default the scroll path
		-- to <root>/Main/Body (the presenter calls this on every present/refresh)
		mountedRoot = rootNode.path
		local groups: { any } = {}
		local rowsInOrder: { { key: string, order: { string } } } = {}
		local rowByKey: { [string]: { key: string, order: { string } } } = {}
		local togglePath: string? = nil
		-- header nav paths per column (document/column order): the leading
		-- horizontal "headers" group carries ONE stop per column — the column
		-- handle. It used to carry two (the sort hit, then a 4px divider), which
		-- made Right walk name-sort -> name-grip -> next-column, and gave a stick
		-- no way to say "this column". Selecting it is now the thing you do, and
		-- Left/Right acts ON it (director 2026-07-29).
		local headerHandleByCol: { [string]: string } = {}
		local FOCUSABLE_CLASSES: { [string]: boolean } = { Button = true, Toggle = true }
		local function focusableIn(node: any, out: { string })
			if FOCUSABLE_CLASSES[node.class] and not (node.props and node.props.focusable == false) then
				table.insert(out, node.path)
			elseif node.class == "Grip" and node.props and node.props.focusable == true then
				table.insert(out, node.path)
			end
			for _, child in node.children or {} do
				focusableIn(child, out)
			end
		end
		-- the wrapper's children, in the order this group walks them (see the
		-- header comment: the row first, then its affordances by edge). These four
		-- ids are row_actions.luau's own (`trayId`, the `Content` ZStack,
		-- `EditAffordanceWhen`); every one is `When`-gated but `Content`, so a row
		-- nobody has swiped and no edit mode has reached contributes exactly what
		-- it always did.
		local WRAPPER_CHILD_ORDER = { "Content", "EditAffordanceWhen", "TrayLeadingWhen", "TrayTrailingWhen" }
		local function wrappedRowFocusables(wrapper: any, out: { string })
			for _, id in WRAPPER_CHILD_ORDER do
				for _, child in wrapper.children or {} do
					if string.match(child.path or "", `/{id}$`) ~= nil then
						focusableIn(child, out)
					end
				end
			end
		end
		local function walk(node: any)
			if string.match(node.path or "", "/ToggleWhen/then/Toolbar/EditToggle$") ~= nil then
				togglePath = node.path
			end
			local headCol = string.match(node.path or "", "/Main/Header/Head%-(.-)/Column$")
			if headCol ~= nil then
				headerHandleByCol[headCol] = node.path
			end
			-- A WRAPPED row is anchored on the wrapper (its whole subtree is the
			-- row); an unwrapped one on `Row`, exactly as before. The two are
			-- mutually exclusive by construction — `Row` sits under `Content`
			-- inside the wrapper — and `derowActionsPath` is what lets the
			-- unwrapped pattern keep matching a wrapped row's `Row` node for
			-- every OTHER caller in this file (see its own comment); it is
			-- deliberately not used for the wrapper itself, whose real mounted
			-- path is what focus navigation needs.
			local wrappedKey = string.match(node.path or "", "/Rows/%[(.-)@%d+%]/RowActions%-[^/]+$")
			local rowKey = wrappedKey or string.match(derowActionsPath(node.path or ""), "/Rows/%[(.-)@%d+%]/Row$")
			if rowKey ~= nil then
				local order: { string } = {}
				if wrappedKey ~= nil then
					wrappedRowFocusables(node, order)
				else
					focusableIn(node, order)
				end
				if #order > 0 then
					local entry = { key = rowKey, order = order }
					table.insert(rowsInOrder, entry)
					rowByKey[rowKey] = entry
				end
				return -- row subtree fully collected
			end
			for _, child in node.children or {} do
				walk(child)
			end
		end
		walk(rootNode)
		-- rows in DOCUMENT order (the mounted children follow it, but a
		-- reorder may be mid-flight: trust the data)
		local ordered: { { key: string, order: { string } } } = {}
		for _, item in spec.rows:get() :: { any } do
			local entry = rowByKey[spec.key(item)]
			if entry ~= nil then
				table.insert(ordered, entry)
			end
		end
		if #ordered == 0 then
			ordered = rowsInOrder
		end
		-- leading horizontal "headers" group, one stop per column. Activate on a
		-- focused header SELECTS that column; while selected, Left/Right resizes and
		-- Up/Down cycles its sort. Adjust (bumpers) still resizes the focused column
		-- without selecting it. Down exits to the rows/first group, Up from a row
		-- re-enters it (ui_todo §0).
		local headerNav: { string } = {}
		for _, column in columns do
			if headerHandleByCol[column.id] ~= nil then
				table.insert(headerNav, headerHandleByCol[column.id])
			end
		end
		if #headerNav > 0 then
			table.insert(groups, { name = "headers", axis = "horizontal", entry = "nearest", order = headerNav })
		end
		if togglePath ~= nil then
			table.insert(groups, { name = "toolbar", axis = "horizontal", entry = "first", order = { togglePath } })
		end
		for _, entry in ordered do
			table.insert(groups, {
				name = `row:{entry.key}`,
				axis = "horizontal",
				entry = "nearest",
				order = entry.order,
			})
		end
		return groups
	end

	api.grabbedKey = grabbedKey
	-- the selected column (nil when none). Public so a consumer can paint the
	-- selection and, later, hang column-wide verbs off it.
	api.selectedColumn = selectedColumn

	function api.rowKeyForPath(path: string): string?
		-- Task 10: strip a wrapped row's `RowActions/Content/` infix first —
		-- see `derowActionsPath`'s own comment.
		local clean = derowActionsPath(path)
		local encoded = string.match(clean, `/{tableIdPattern}/Main/Body/Rows/%[(.-)%]/Row/Hit$`)
			or string.match(clean, `/{tableIdPattern}/Main/Body/Rows/%[(.-)%]/Row/EditWhen/then/HandleZone/Handle$`)
		if encoded == nil then
			return nil
		end
		return (string.match(encoded, "^(.*)@%d+$"))
	end

	-- routes a presenter Adjust (keyboard arrows / dpad / bumpers) when focus
	-- sits on a resize grip: one committed step per press, min-clamped.
	-- rectOf seeds the first step of a fill column from its rendered width.
	local ADJUST_STEP = 16
	-- ONE step, whoever asked for it: the focused-header Adjust (bumpers) and the
	-- selected column's Left/Right both land here, so they can never disagree about
	-- the step, the floor, or where the first step starts from.
	function stepColumnWidth(columnId: string, dir: number, rectOf: ((string) -> any)?, headerPath: string?): boolean
		for _, column in columns do
			if column.id == columnId then
				if column.resizable ~= true then
					return false
				end
				local current = widthOverrides:get()[columnId]
				-- the FIRST step of a `fill` column starts from its rendered width,
				-- not from its minimum: seeded from live geometry when a caller has
				-- it, else from the last solve the presenter fed us
				local read = rectOf or lastRectOf
				-- the header's own path when the caller has one (Adjust knows the
				-- focused node), else derived from the mounted root. `mountedRoot` is
				-- only captured when the presenter asks for focus groups, so a
				-- surface running the legacy flat ring has none — which is exactly
				-- the case that regressed to the minimum width.
				local cellPath = headerPath
					or (if mountedRoot ~= nil then `{mountedRoot}/Main/Header/Head-{columnId}` else nil)
				if current == nil and read ~= nil and cellPath ~= nil then
					local cellRect = read(cellPath)
					current = cellRect and cellRect.w
				end
				if current == nil then
					current = column.minWidth or 24
				end
				api.setColumnWidth(columnId, math.max(column.minWidth or 24, current + dir * ADJUST_STEP))
				return true
			end
		end
		return false
	end

	function api.handleAdjust(path: string, dir: number, rectOf: ((string) -> any)?): boolean
		local columnId = string.match(path, `/{tableIdPattern}/Main/Header/Head%-(.-)/Column$`)
		if columnId == nil then
			return false
		end
		return stepColumnWidth(columnId, dir, rectOf, (string.match(path, "^(.*)/Column$")))
	end

	-- the focusable header resize grips (matrix §B-Table; UI-PARADIGM-001): the
	-- presenter binds the Adjust keys DYNAMICALLY, only while a declared target
	-- holds focus, so a bare Table never shadows gameplay bumpers off-grip. Every
	-- rendered resizable-column grip is a target (they carry focusable=true).
	function api.adjustTargets(rootNode: any): { [string]: boolean }
		local targets: { [string]: boolean } = {}
		local function walk(node: any)
			-- RESIZABLE ONLY. Every column now has a header handle, but binding
			-- Adjust on a header that cannot resize would shadow gameplay bumpers
			-- for nothing — which is the exact guarantee this seam exists to keep
			-- (matrix §B-Table: no Adjust key bound while focus sits off a target).
			local headCol = string.match(node.path or "", "/Main/Header/Head%-(.-)/Column$")
			if headCol ~= nil and isResizableId(headCol) then
				targets[node.path] = true
			end
			for _, child in node.children or {} do
				walk(child)
			end
		end
		walk(rootNode)
		return targets
	end

	-- Apple table model (director round 2): keyboard/gamepad navigation moves
	-- the SELECTION with focus. The presenter reports navigation-driven focus
	-- moves via onFocusNav; screens route them here. Pointer taps do NOT go
	-- through this (their selection semantics ride the activate meta).
	-- scroll the focused row into the body viewport when a keyboard/gamepad
	-- focus move lands it outside the clip band (ui_todo §0 — Table body scroll
	-- on every input; pointer wheel/touch-pan are unchanged). Works off document
	-- row tops + the current scroll (offset-independent, so it is correct even
	-- across un-refreshed multi-step nav); only the body HEIGHT comes from the
	-- last solved geometry. Minimal scroll, both directions.
	local function scrollRowIntoView(path: string, rowKey: string)
		if lastRectOf == nil then
			return
		end
		local root = string.match(path, "^(.*)/Main/Body/")
		if root == nil then
			return
		end
		local bodyRect = (lastRectOf :: any)(root .. "/Main/Body")
		if bodyRect == nil then
			return
		end
		local rowTop = rowTops:get()[rowKey]
		if rowTop == nil then
			return
		end
		local item
		for _, candidate in spec.rows:get() do
			if spec.key(candidate) == rowKey then
				item = candidate
				break
			end
		end
		if item == nil then
			return
		end
		local rowHeight = rowHeightOf(item)
		local offset = scrollTop:get()
		-- ONE implementation of the minimum-distance rule (A-SV2). The SPAN comes
		-- from the model (a culled row has no solved rect for the renderer's shared
		-- substrate to read); only the clamp is shared, and it used to be written
		-- separately here, in VirtualList, and in the renderer.
		local newOffset = solverLib.keepVisibleOffset(rowTop, rowHeight, offset, bodyRect.h) or offset
		if newOffset ~= offset then
			-- issue the framework's ONE programmatic scroll write: CanvasPosition
			-- through the bound controller (native §4). The engine echoes it back
			-- to the scrollTop mirror; a no-op when unbound (no engine to scroll).
			local target = clampScroll(newOffset, bodyRect.h)
			local scrollPath = boundScrollPath or (root .. "/Main/Body")
			if boundController ~= nil then
				boundController.scrollTo(scrollPath, { x = 0, y = target })
			end
		end
	end

	-- Cancel (B / Escape) releases a selected column. Routed through the
	-- contribution so the presenter offers it BEFORE its own modal-dismiss, the
	-- same order the row grab's cancel takes.
	function api.handleCancel(_focusedPath: string?): boolean
		if selectedColumn:get() ~= nil then
			selectedColumn:set(nil)
			return true
		end
		return false
	end

	-- ...and moving focus off the header releases it too: a selection that
	-- outlived the thing it was pointing at would keep swallowing the stick.
	local function releaseColumnOnFocusLeave(path: string)
		local held = selectedColumn:get()
		if held == nil then
			return
		end
		if string.match(path, `/{tableIdPattern}/Main/Header/Head%-(.-)/Column$`) ~= held then
			selectedColumn:set(nil)
		end
	end

	function api.handleFocusMoved(path: string): boolean
		-- selection follows focus into ANY node of a row — hit, cell content,
		-- stars — not just the row hit (director 2026-07-20: focusing a star
		-- and stepping to the next row must move the selection too)
		releaseColumnOnFocusLeave(path)
		local rowKey = api.rowKeyForPath(path) or string.match(path, `/{tableIdPattern}/Main/Body/Rows/%[(.-)@%d+%]/`)
		if rowKey == nil then
			return false
		end
		-- scroll-into-view runs for every selection mode (even "none": a focusable
		-- in-cell control can step off-screen); selection follows only when set
		scrollRowIntoView(path, rowKey)
		if selectionMode ~= "none" then
			api.select(rowKey, { mode = "replace" })
		end
		return true
	end

	-- model-level reorder: move a row by delta and report the POST-removal
	-- insertion slot through spec.onReorder (the keyboard/gamepad-reachable
	-- path; no-op moves at the edges are suppressed)
	function api.moveRow(rowKey: string, delta: number): boolean
		if spec.reorderable ~= true or spec.onReorder == nil or delta == 0 then
			return false
		end
		local keys = orderedKeys()
		local i = table.find(keys, rowKey)
		if i == nil then
			return false
		end
		--[[ THE MOVE FUNNEL. Table has FIVE ways to start a reorder (pointer
			pickup, the edit-mode handle, the gamepad grab, this verb, and the
			composed body-drag replay) and this is the one they all resolve
			through — `:1015-1030` records this file being bitten by "a third,
			wholly separate way to start the identical reorder" that missed a
			guard, which is why the gate is here.

			SOURCE **AND** DESTINATION. `moveDisabled`'s source-vs-destination
			question is one Apple does not document (its page is an abstract and
			a declaration, no discussion), so LuauUI decides: a pinned row holds
			its INDEX. A move that would displace one is refused, because
			otherwise "pinned" would mean "cannot be dragged but can be shoved",
			which is not what an author means by it. ]]
		if not rowCapability.allows(spec.rowMovable, itemForKey(rowKey)) then
			return false
		end
		if spec.rowMovable ~= nil then
			local lo = math.min(i, i + delta)
			local hi = math.max(i, i + delta)
			for at = lo, hi do
				local other = keys[at]
				if
					other ~= nil
					and other ~= rowKey
					and not rowCapability.allows(spec.rowMovable, itemForKey(other))
				then
					return false
				end
			end
		end
		-- POST-removal slot (matches the pointer drag): final 1-based position
		-- is i + delta, so the remaining-above count is i + delta - 1
		local slot = i + delta - 1
		if slot < 0 or slot > #keys - 1 or slot == i - 1 then
			return false
		end
		(spec.onReorder :: any)({ rowKey }, slot)
		return true
	end

	-- routes a presenter shift+Navigate when focus sits on a row hit
	function api.handleReorderNav(path: string, dir: number): boolean
		local rowKey = api.rowKeyForPath(path)
		if rowKey == nil then
			return false
		end
		return api.moveRow(rowKey, dir)
	end

	function api.setColumnWidth(columnId: string, px: number)
		for _, column in columns do
			if column.id == columnId then
				if column.resizable ~= true then
					return
				end
				local overrides = table.clone(widthOverrides:get())
				overrides[columnId] = px
				widthOverrides:set(overrides)
				widthsVersion:set(widthsVersion:get() + 1)
				return
			end
		end
	end

	function api.columnWidthOverrides()
		return widthOverrides:get()
	end

	-- the unbind a skipped subscription still owes its caller
	local function NOOP() end
	-- the path of the nearest ScrollView ANCESTOR of this table's mounted root —
	-- the thing that actually moves a block table's rows. `controller.
	-- scrollHostFor` is the renderer's one answer to that question (it reads the
	-- host map `structuralSync` already threads down the live-path walk); a
	-- controller stub without it, or a table mounted under nothing that scrolls,
	-- answers nil and the caller simply binds nothing.
	local function hostScrollPathOf(controller: any): string?
		if mountedRoot == nil or type(controller.scrollHostFor) ~= "function" then
			return nil
		end
		local host = controller.scrollHostFor(mountedRoot)
		return if type(host) == "table" then host.path else nil
	end

	-- native scroll mirror wiring (native-substrate NS-A2). Controls cannot reach
	-- the renderer controller at build time, so the consumer/presenter calls this
	-- after present(): it feeds controller.observeScroll(bodyPath) -> scrollTop
	-- (the engine CanvasPosition mirror) and hands the same controller to
	-- keep-visible for its programmatic scrollTo writes. `scrollPath` defaults to
	-- `api.scrollPath()`; pass it explicitly for a standalone mount. Returns an
	-- unbind that stops the mirror.
	--
	-- A BLOCK TABLE HAS NO MIRROR AND STILL HAS A TRAY TO CLOSE (ruling 3,
	-- director 2026-08-13). Under `scrolls = false` there is no ScrollingFrame of
	-- this table's own to observe, so `api.scrollPath()` is nil and the mirror is
	-- skipped — but the rows still MOVE, carried by whatever scrolls above them,
	-- and "any scroll closes the open tray" has to follow the movement rather
	-- than the ownership. `controller.scrollHostFor` answers exactly that (its own
	-- comment already names "a block Table inside a scrolling page" as the shipped
	-- shape), so the tray-close binds to the real scrolling ancestor. Before this,
	-- both were bound to `<root>/Main/Body` — a plain VStack the renderer elides —
	-- and a page scroll left the tray open, which is the reported symptom.
	function api.bindNativeScroll(controller: any, scrollPath: string?): () -> ()
		assert(
			scrollPath ~= nil or mountedRoot ~= nil,
			"Table.bindNativeScroll: scroll path unknown — present the table (so its mounted path is captured) or pass it explicitly"
		)
		-- THIS table's own canvas: nil for a block table, which has none.
		local path = scrollPath or api.scrollPath()
		local unsub = if path ~= nil
			then controller.observeScroll(path, function(pos: { x: number, y: number })
				scrollTop:set(pos.y)
			end)
			else NOOP
		boundController = controller
		boundScrollPath = path
		-- Task 10: any scroll closes the currently-open row-actions tray
		-- (iOS parity, row_actions.newCoordinator's own `bindScroll` doc) —
		-- wired through the identical seam, the same `controller.
		-- observeScroll` call, one line below the mirror it shares a
		-- controller/path with. `nil` for a table with no `spec.rowActions`.
		local trayPath = path or hostScrollPathOf(controller)
		local unsubCoordinatorScroll = if rowActionsCoordinator ~= nil and trayPath ~= nil
			then rowActionsCoordinator.bindScroll(controller, trayPath)
			else nil
		return function()
			unsub()
			if unsubCoordinatorScroll ~= nil then
				unsubCoordinatorScroll()
			end
			if boundController == controller then
				boundController = nil
				boundScrollPath = nil
			end
		end
	end
	-- the mounted native-scroll host path (nil until first presented/refreshed,
	-- and nil FOREVER for a block table — see `bindNativeScroll` above: under
	-- `scrolls = false` the Body is a plain VStack, so publishing it named a node
	-- that never scrolls and that the renderer elides outright)
	function api.scrollPath(): string?
		if spec.scrolls == false then
			return nil
		end
		return if mountedRoot ~= nil then mountedRoot .. "/Main/Body" else nil
	end

	-- deterministic diagnostic summary (§10.2 control contract dump form;
	-- uniform seam: every composite control exposes dump())
	local function dump()
		local sort = spec.sortOrder and spec.sortOrder:get() or nil
		-- SORTED, because `selectedKeys` is a SET and a set's iteration order is
		-- not stable across runs: an unsorted array would make the dump
		-- non-deterministic the moment a second row was selected.
		local selected: { string } = {}
		for key, on in selectedKeys:get() do
			if on then
				table.insert(selected, key)
			end
		end
		table.sort(selected)
		return {
			schema = "luauui-table-dump/1",
			id = spec.id or "Table",
			columns = (function()
				local out = {}
				for _, column in columns do
					table.insert(out, { id = column.id, override = widthOverrides:get()[column.id] })
				end
				return out
			end)(),
			rowCount = #(spec.rows:get() :: { any }),
			selection = selectionMode,
			sortOrder = if sort then { column = sort.column, ascending = sort.ascending } else nil,
			-- THE LIVE INTERACTION STATE A BUG REPORT NEEDS (playbook §2.5).
			-- VirtualList's dump carried every one of its equivalents; Table's
			-- carried none, so the largest control in the library described only
			-- its construction. Additive keys — nothing above moved.
			selectedKeys = selected,
			grabbedKey = grabbedKey:get(),
			editing = editingSignal:get(),
			scrollTop = scrollTop:get(),
			dragging = dragging:get(),
			reorderable = spec.reorderable == true,
			rootPath = mountedRoot,
		}
	end

	api.editing = editingSignal

	-- hot-switch in-flight transition semantics (matrix §C; UI-PARADIGM-002).
	-- A device arriving or leaving mid-gesture must never strand an interaction
	-- in a state the now-live class cannot exit — CANCEL cleanly reverts to the
	-- pre-gesture snapshot; CARRY simply lets the newly-live class ALSO gain its
	-- idiom (grab keeps following Navigate; scroll offset survives; edit-mode
	-- persists while touch or gamepad stays live). Keyed off the LIVE
	-- interaction-class set (ADR-0015), never preferredInput alone.
	if spec.env ~= nil then
		scope:own(core:observe(spec.env:get("interactionClasses"), function(classes)
			if type(classes) ~= "table" then
				return
			end
			-- pointer drag / grip resize CANCEL: pointer capability gone mid-capture,
			-- so no release event can arrive — revert to origin (reuse the existing
			-- invalid-drop reset). Never a stuck ghost row or preview line. Rows stay
			-- in place during a pointer drag, so cancelDrag alone reverts the reorder.
			if classes.pointer ~= true then
				if rowDrag ~= nil and rowDrag.active then
					cancelDrag()
				end
				if resizeDrag ~= nil then
					resizeDrag = nil
					resizing:set(false)
				end
			end
			-- gamepad grab-mode CANCEL: no discrete Navigate/Activate source
			-- (gamepad or keyboard) survives to step or drop the grabbed row, so
			-- revert the list order to pre-grab and clear the grab. (A live keyboard
			-- can still step/drop, so grab CARRIES then.)
			if grabbedKey:get() ~= nil and classes.gamepad ~= true and classes.keyboard ~= true then
				if grabOrigin ~= nil and spec.onReorder ~= nil then
					(spec.onReorder :: any)(grabOrigin.block, grabOrigin.slot)
				end
				grabOrigin = nil
				grabbedKey:set(nil)
			end
			-- touch edit-mode CANCEL to pure pointer: the auto Edit/Done toggle
			-- unmounts when neither touch nor gamepad is live (ADR-0015). A
			-- CONTROL-OWNED editing signal must reset with it, or the ≡ grips linger
			-- (or, for a selectable primary-action table, the row taps keep toggling
			-- selection instead of opening) with no way to exit — a wedge. The
			-- condition is `autoEditRoute`, the toggle's OWN predicate, so widening
			-- which tables auto-show the button widens which ones can be rescued from
			-- it by exactly the same set. An OWNER-held signal is the owner's
			-- business — never touched here (and `autoEditRoute` is false then).
			if autoEditRoute and editingSignal:get() == true and classes.touch ~= true and classes.gamepad ~= true then
				editingSignal:set(false)
			end
		end))
	end

	return {
		-- attach the input contribution so the presenter auto-wires the table's
		-- keyboard/gamepad story (2D groups, row select, grab-mode reorder,
		-- selection-follows-focus, grip-resize Adjust) with no consumer opts
		-- (ADR-0013; matrix §B-Table UI-PARADIGM-001). shift-reorder
		-- (handleReorderNav) stays opt-driven — it is outside this seam's shape.
		blueprint = contribution.attach(blueprint, {
			focusGroups = api.buildFocusGroups,
			handleActivate = api.handleActivate,
			navigateIntercept = api.handleGrabNavigate,
			focusMoved = api.handleFocusMoved,
			-- bare-Table column resize (matrix §B-Table): the presenter binds the
			-- Adjust keys only while a resize grip holds focus, then routes the
			-- adjust here. lastRectOf seeds the first step of a fill column from its
			-- rendered width. opts.onAdjust still wins per-opt (back-compat).
			handleCancel = api.handleCancel,
			adjustTargets = api.adjustTargets,
			handleAdjust = function(path, dir)
				return api.handleAdjust(path, dir, lastRectOf)
			end,
			-- capture solved geometry each refresh so keyboard/gamepad focus moves
			-- can scroll a clipped row into the body viewport (scrollRowIntoView)
			syncGeometry = function(rectOf)
				lastRectOf = rectOf
			end,
			-- the render controller: edge autoscroll has to steer a scroll host the
			-- table may not own (a block table's page), and only the controller can
			-- name it. Re-called on every structural sync; assignment is idempotent.
			bindController = function(controller)
				renderController = controller
			end,
			-- THE CLOCK, FOR ONE MEASUREMENT ONLY (parity round 2 §3.4): the
			-- double-click window. Table animates nothing, so it takes the `now`
			-- half of this seam and ignores the clock itself — that is exactly what
			-- the ADDITIVE second argument is for (contribution.luau: "the same
			-- source the motion clock uses"). Without a presenter (a bare-mounted
			-- Table in a spec) `nowFn` stays `os.clock`, so the gesture still works;
			-- with one, a scripted `now` makes the window deterministic.
			bindMotion = function(_clock: any, now: (() -> number)?)
				if now ~= nil then
					nowFn = now
				end
			end,
		}),
		api = api,
		dump = dump,
		dispose = function()
			-- Task 10: every row_actions instance is an INDEPENDENT
			-- `core:scope()` root (see `rowActionsByKey`'s own comment) —
			-- `scope:dispose()` below tears down everything Table itself
			-- owns, but nothing cascades into these on its own.
			for rowKey, instance in rowActionsByKey do
				instance.dispose()
				rowActionsByKey[rowKey] = nil
			end
			scope:dispose()
		end,
	}
end

return table_control
