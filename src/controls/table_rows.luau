--!strict
local Compose = require("../vendor/compose/core")
-- Row content and pointer gestures. Table supplies shared state through Deps;
-- this module does not import the table implementation.

local specGuard = require("../spec_guard")
local rowCapability = require("../row_capability")
local row_actions = require("./row_actions")
-- the axis-lock constant only (never a decision instance) — see the row Hit's
-- own dispatcher below for why this file has to know the radius
local row_actions_state = require("../input/row_actions_state")
local interactionTokens = require("../input/interaction_tokens")

local table_rows = {}

-- Only the column fields read by this builder belong in this interface.
export type Column = {
	id: string,
	cell: ((item: any) -> any)?,
	value: ((item: any) -> string)?,
	sortable: boolean?,
	disclose: boolean?,
	alignment: { h: string?, v: string? }?,
	[string]: any,
}

-- Shared gesture state lets the table cancel a drag or suppress its final activation.
export type Gesture = {
	drag: any,
	suppressActivate: string?,
}

-- Table supplies the model, geometry, and interaction services used by its rows.
export type Deps = {
	Facet: any,
	core: any,
	UI: any,
	spec: any,
	tableId: string,
	columns: { Column },
	-- the control's own api table, held by REFERENCE: its methods are assigned
	-- after this builder is constructed, and a gesture only ever calls one at
	-- dispatch time (`api.rowKeyForPath`)
	api: any,
	rowGesture: Gesture,
	selectionMode: string,
	virtualized: boolean,
	HANDLE_GUTTER: number,
	ROW_ART: any,
	ALIGN_H: { [string]: string },
	ALIGN_V: { [string]: string },
	cellPadding: any,
	cellsEditPadding: any,
	editingSignal: any,
	selectedKeys: any,
	dragging: any,
	ghostText: any,
	ghostCount: any,
	rowBox: any,
	layoutIndex: any,
	rowActionsByKey: { [string]: any },
	rowActionsCoordinator: any,
	rowHeightOf: (any, any?) -> number,
	capFor: (any, number) -> number,
	columnDim: (Column) -> any,
	columnHidden: (Column) -> any,
	-- is edit mode reachable at all on this table (the consumer holds the signal,
	-- or the control auto-shows its toggle) — a build-time union
	canEditMode: boolean,
	-- the shared cell the HEADER BAND reads its edit-mode gutter out of; written
	-- here, owned by `table.luau`, spent by `table_header.band` (see
	-- `noteEditGutter` below for why the number is taken rather than re-derived)
	rowEditGutter: any,
	-- The table's Compose owner releases the final gutter subscription.
	owner: any,
	-- the ONE environment `table.luau` resolved (`spec.env`, else the one
	-- published against the core): a wrapped row's tray must not resolve its
	-- metrics against a different one than the row box did
	surfaceEnvironment: any,
	grabbedKey: any,
	itemForKey: (string) -> any?,
	applyDragPosition: ({ x: number, y: number }) -> (),
	clearPointerDrag: () -> (),
	liveDragRects: (any) -> (any, any),
	cancelDrag: () -> (),
}

-- Task 10: the closed key set for whatever `spec.rowActions(item)` returns
-- for a single row — the same three fields `UI.RowActions` itself exposes
-- besides `content`/`coordinator`/`env`/`editing` (Table supplies those
-- four). Checked per row, at build, so a typo names the offending row rather
-- than surfacing as a silently-ignored option (constitution §4).
local ROW_ACTIONS_RESULT_KEYS = specGuard.keySet({ "leading", "trailing", "fullSwipe" })

-- The collection calls blueprint; pointer handlers remain private to each row.
function table_rows.new(deps: Deps)
	local Facet = deps.Facet
	local core = deps.core
	local UI = deps.UI
	local spec = deps.spec
	local tableId = deps.tableId
	local columns = deps.columns
	local api = deps.api
	local rowGesture = deps.rowGesture
	local selectionMode = deps.selectionMode
	local virtualized = deps.virtualized
	local HANDLE_GUTTER = deps.HANDLE_GUTTER
	local ROW_ART = deps.ROW_ART
	local ALIGN_H = deps.ALIGN_H
	local ALIGN_V = deps.ALIGN_V
	local cellPadding = deps.cellPadding
	local cellsEditPadding = deps.cellsEditPadding
	local editingSignal = deps.editingSignal
	local selectedKeys = deps.selectedKeys
	local dragging = deps.dragging
	local ghostText = deps.ghostText
	local ghostCount = deps.ghostCount
	local rowBox = deps.rowBox
	local layoutIndex = deps.layoutIndex
	local rowActionsByKey = deps.rowActionsByKey
	local rowActionsCoordinator = deps.rowActionsCoordinator
	local rowHeightOf = deps.rowHeightOf
	local capFor = deps.capFor
	local columnDim = deps.columnDim
	local columnHidden = deps.columnHidden
	local canEditMode = deps.canEditMode
	local owner = deps.owner
	local surfaceEnvironment = deps.surfaceEnvironment
	local grabbedKey = deps.grabbedKey
	local itemForKey = deps.itemForKey
	local applyDragPosition = deps.applyDragPosition
	local clearPointerDrag = deps.clearPointerDrag
	local liveDragRects = deps.liveDragRects
	local cancelDrag = deps.cancelDrag
	-- The header reads the row wrapper's edit gutter so their columns stay aligned.
	-- Rebinding releases the previous observer; the table owner releases the last one.
	local rowEditGutter = deps.rowEditGutter
	local unbindEditGutter: (() -> ())? = nil
	local function noteEditGutter(source: any)
		if source == nil then
			return
		end
		if unbindEditGutter ~= nil then
			unbindEditGutter()
		end
		unbindEditGutter = owner.watchStatic(source, function()
			rowEditGutter:set(source:peek())
		end)
		rowEditGutter:set(source:peek())
	end
	-- the edit-mode ≡ handle reuses the row-drag closures; forward-declared for
	-- the same reason it always was (it is built after them and read by the
	-- blueprint below)
	local handleDragHandlers

	-- cell content priority: column.cell -> column.value (default Text) ->
	-- the legacy table-wide spec.cellFor
	--
	-- `lineCap` is this ROW's line limit (see rowBoxFor). It applies to the default
	-- Text cell — the one the table itself authors and is therefore answerable for.
	-- A `cell`/`cellFor` blueprint belongs to the consumer, who may put a scrolling
	-- panel or an image in there; the table caps what it makes, not what it is given.
	local function cellContentFor(column: Column, item: any, lineCap: any): any
		local current = if not Compose.isReadable(item) then Compose.cell(item) else item
		if column.cell ~= nil then
			return (column.cell :: any)(current)
		end
		if column.value ~= nil then
			return UI.Text({
				id = "Value",
				text = if Compose.isReadable(current)
					then function(use)
						return tostring((column.value :: any)(use(current)))
					end
					else tostring((column.value :: any)(current)),
				textSize = "controls.table.cellTextSize",
				lineLimit = lineCap,
				disclose = if column.disclose == true then true else nil,
			})
		end
		assert(spec.cellFor ~= nil, `Table '{tableId}': column '{column.id}' has no cell/value and no spec.cellFor`)
		return (spec.cellFor :: any)(column.id, current)
	end

	-- press→drag promotion, from the SHARED token table —
	-- the value is the same 6 px this control has always used, sourced from the
	-- one place a device round retunes it. The POINTER token is the right one
	-- here even on a touch device: the row body declines the capture on touch
	-- (the native ScrollingFrame owns the pan), so touch reorder rides the
	-- edit-mode ≡ handle, which presents its position as a mouse pointer.
	local DRAG_THRESHOLD = interactionTokens.promotionPx("pointer")

	-- while editing, a press landing in the LEADING handle gutter belongs to
	-- the ≡ grip: DECLINE (return false) so the grip's own began (which the
	-- engine may deliver before or after this one) takes the capture
	-- (live-found 2026-07-20: the row hit won the race and the handle drag
	-- never started). Extracted (Task 10) so the composed row-actions
	-- dispatcher's own Hit handler can run the IDENTICAL check BEFORE it ever
	-- defers to the axis lock — a wrapped, reorderable, editing row must keep
	-- this exact decline, unchanged, ahead of any row-actions gesture.
	local function isHandleZonePress(path: string, pos: any, rectOf: (string) -> any): boolean
		if not (editingSignal:peek() and string.match(path, "/Row/Hit$") ~= nil) then
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
				rowGesture.suppressActivate = nil
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
				for _, candidate in spec.rows:peek() do
					if spec.key(candidate) == rowKey then
						item = candidate
					end
				end
				rowGesture.drag = {
					rowKey = rowKey,
					item = item,
					startY = pos.y,
					active = false,
					-- THE LOOKUP, NOT THE ANSWER (device report 2026-07-28, gallery
					-- example 02 on a physical phone: "when I pick up a row it
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
				if rowGesture.drag == nil then
					return
				end
				if not rowGesture.drag.active then
					if math.abs(pos.y - rowGesture.drag.startY) < DRAG_THRESHOLD then
						return
					end
					rowGesture.drag.active = true
					-- armed at threshold: an Activated for the origin row is
					-- a drag artifact, whichever side of InputEnded it lands
					rowGesture.suppressActivate = path
					-- dragging a SELECTED row picks up the whole selection
					-- (document order); an unselected row drags alone
					local selected = selectedKeys:peek()
					local group: { string } = {}
					if selectionMode ~= "none" and selected[rowGesture.drag.rowKey] == true then
						for _, item in spec.rows:peek() do
							local key = spec.key(item)
							if selected[key] == true then
								table.insert(group, key)
							end
						end
					end
					if #group < 2 then
						group = { rowGesture.drag.rowKey }
					end
					rowGesture.drag.keys = group
					ghostText:set((spec.dragLabel or spec.key)(rowGesture.drag.item))
					ghostCount:set(#group)
					dragging:set(true)
				end
				applyDragPosition(pos)
			end,
			onPointerUp = function(_path: string, pos: any)
				if rowGesture.drag == nil then
					return
				end
				local drag = rowGesture.drag
				rowGesture.drag = nil
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
					for _, item in spec.rows:peek() do
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

	-- Uniform rows share their geometry derivations. Item-dependent heights keep
	-- per-row formulas so replacements still update without remounting controls.
	local uniformHeight, uniformCap
	if type(spec.rowHeight) ~= "function" then
		Compose.withOwner(owner, function()
			uniformHeight = Compose.formula(function(use)
				return { type = "fixed", px = rowHeightOf(nil, use(rowBox)) }
			end)
			uniformCap = Compose.formula(function(use)
				local box = use(rowBox)
				return capFor(box, rowHeightOf(nil, box))
			end)
		end)
	end

	local function rowBlueprint(entry: any, itemScope: any, currentItem: any): any
		itemScope = Compose.currentOwner()
		local item = entry
		local current = currentItem
		local rowKey = spec.key(item)
		local function selectionValue(use)
			return use(selectedKeys)[rowKey] == true or use(grabbedKey) == rowKey
		end
		local rowSelected = if not canEditMode
			then selectionValue
			else Compose.withOwner(itemScope, function()
				return Compose.formula(selectionValue)
			end)
		-- Theme and text-size changes update shared or item-specific row geometry.
		local heightDim = uniformHeight
			or Compose.withOwner(itemScope, function()
				return Compose.formula(function(use)
					return { type = "fixed", px = rowHeightOf(if current then use(current) else item, use(rowBox)) }
				end)
			end)
		-- ...and the cap the cells are measured against IS this row's height: see
		-- rowBoxFor. This is what makes a cell physically unable to paint outside the
		-- row it belongs to, whoever chose the height.
		local cellCap = uniformCap
			or Compose.withOwner(itemScope, function()
				return Compose.formula(function(use)
					local box = use(rowBox)
					return capFor(box, rowHeightOf(if current then use(current) else item, box))
				end)
			end)
		local cells = {}
		for _, column in columns do
			local alignment = column.alignment or {}
			table.insert(
				cells,
				UI.ZStack({
					id = `Cell-{column.id}`,
					width = columnDim(column),
					-- ADAPT-18: this column is collapsed at the current width, so the
					-- cell keeps its (zero-width) box and its whole subtree leaves
					-- paint, focus order and hit-testing at once. `table.luau`'s
					-- `columnHidden` carries the reasoning and the three alternatives
					-- it beats.
					hidden = columnHidden(column),
					height = { type = "fill", weight = 1 },
					padding = { left = cellPadding, right = cellPadding },
					alignV = ALIGN_V[alignment.v or "center"],
					alignH = ALIGN_H[alignment.h or "leading"],
					children = { cellContentFor(column, current or item, cellCap) },
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
					"UI.Table",
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
			-- Suppress the Activated event that follows a horizontal swipe. Both pointer
			-- handlers measure from the same origin and use the shared axis-lock threshold.
			local swipeGesture: { originX: number, originY: number, horizontal: boolean }? = nil
			hitOnPointerDown = function(path: string, pos: any, rectOf: (string) -> any)
				-- the handle-zone decline runs FIRST, exactly as it does for
				-- an unwrapped reorderable row — a press in the ≡ gutter must
				-- never be deferred into the axis lock at all.
				if dragHandlers ~= nil and isHandleZonePress(path, pos, rectOf) then
					return false
				end
				-- A new gesture clears stale suppression. Cancellation also clears it;
				-- keyboard and gamepad activation must never consume a pointer suppression.
				rowGesture.suppressActivate = nil
				local accepted = composedRef.onPointerDown(path, pos, rectOf)
				swipeGesture = if accepted == false
					then nil
					else { originX = pos.x, originY = pos.y, horizontal = false }
				return accepted
			end
			hitOnPointerMove = function(path: string, pos: any, rectOf: (string) -> any)
				-- This record tracks one pointer sequence. rowGesture tracks the whole table.
				local swipe = swipeGesture
				if swipe ~= nil and not swipe.horizontal then
					local dx, dy = pos.x - swipe.originX, pos.y - swipe.originY
					if dx * dx + dy * dy >= row_actions_state.AXIS_LOCK_PX ^ 2 and math.abs(dx) > math.abs(dy) then
						swipe.horizontal = true
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
						rowGesture.suppressActivate = path
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
				-- A CANCELLED GESTURE HAS NO ARTIFACT COMING (2026-08-13). The engine
				-- fires no `Activated` for a capture it
				-- took away — the Roblox menu opening, this row unmounting, a
				-- scroll stealing the gesture — so an arm left standing here has
				-- nothing of its own left to swallow and would spend itself on
				-- the next producer that carries no pointer-down: measured as a
				-- dead gamepad A on the very row the player just swiped.
				-- `cancelDrag` clears it on the reorder half for this reason.
				rowGesture.suppressActivate = nil
				return composedRef.onPointerCancel(path, reason)
			end
		end

		local rowChildren = {
			UI.Button({
				id = "Hit",
				label = "",
				selected = rowSelected,
				-- Selection, reorder and row actions each require a keyboard/gamepad focus stop.
				-- Read-only rows without an action do not.
				focusable = selectionMode ~= "none" or spec.reorderable == true or rowActionsResult ~= nil,
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
		-- Editable selection rows show a mark in the leading gutter. Reorder rows use
		-- that space for the drag handle. Only mount the mark when edit mode has an
		-- authored route; a structural region still costs a node while its branch is absent.
		if spec.reorderable ~= true and selectionMode ~= "none" and canEditMode then
			table.insert(
				rowChildren,
				UI.When({
					id = "EditWhen",
					condition = editingSignal,
					thenView = function()
						local selected = rowSelected
						return UI.ZStack({
							id = "SelectZone",
							alignH = "start",
							-- THE GUTTER STARTS AT THE CARD, NOT AT THE ROW — the same
							-- measured inset the handle zone below pays, for the same
							-- reason (director report 2026-07-28, defect 4)
							margin = { left = ROW_ART.left },
							width = { type = "fixed", px = HANDLE_GUTTER },
							height = { type = "fill", weight = 1 },
							children = {
								UI.Text({
									id = "SelectMark",
									-- The edit marker reads the same selection state as the row.
									text = Compose.withOwner(itemScope, function()
										return Compose.formula(function(use)
											return if use(selected) then "◉" else "◯"
										end)
									end),
									textSize = "control",
									-- the GLYPH carries the state, not a colour: `content`
									-- is the resting role and the only other legal one here
									-- is `secondary`, which would recede an affordance the
									-- mode exists to show
									role = "content",
									alignH = "center",
									alignV = "center",
								}),
							},
						})
					end,
				})
			)
		end
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
		-- Virtual rows follow the layout index without rebuilding their controls.
		-- A departing key may no longer have a slot; its offset then defaults to zero.
		local slotOffset = if not virtualized
			then nil
			else Compose.withOwner(itemScope, function()
				return Compose.formula(function(use)
					local layout = use(layoutIndex) :: any
					local slot = layout.slotOf[rowKey]
					return if slot == nil then 0 else layout.ix.offsetOf(slot)
				end)
			end)
		local rowBp = UI.ZStack({
			id = "Row",
			anchor = if virtualized then "topLeft" else nil,
			offsetY = slotOffset,
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
		local rowActionsApi = row_actions.build(Facet, core, {
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
			env = surfaceEnvironment,
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

		-- Replacing a row wrapper releases any prior instance for that item.
		local staleInstance = rowActionsByKey[rowKey]
		if staleInstance ~= nil then
			staleInstance.dispose()
		end
		rowActionsByKey[rowKey] = rowActionsApi
		noteEditGutter(rowActionsApi.editGutterPx)

		return rowActionsApi.blueprint
	end

	-- Collapsed-column details use the same cell content rules as mounted rows.
	return { blueprint = rowBlueprint, cellContent = cellContentFor }
end

return table_rows
