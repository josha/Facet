--!strict
--[[ row_actions_reorder — one raw pointer capture, two candidate gestures.

	WHAT THIS IS. `row_actions.composeWithReorder`, whole: the deferred-down
	arbiter Table needs when a row is BOTH `reorderable` and wrapped in
	`rowActions`, so a swipe (horizontal) and a drag-to-reorder (vertical) can
	share the one low-level capture the engine hands out (ADR-0008).

	IT SHARES NOTHING WITH THE ENGINE. `compose` is a top-level factory over two
	handler TABLES it is given; the only state it owns is one `pending` record per
	live gesture, local to the closure it returns. It never reads or writes a
	single one of `buildEngine`'s upvalues — it talks to the row through the same
	four public `_pointerHandlers` a host would.

	PUBLIC INTERFACE: `compose(rowActionsHandlers, reorderHandlers?) ->` the same
	four-member `{ onPointerDown, onPointerMove, onPointerUp, onPointerCancel }`
	shape. `row_actions.luau` re-exports it as `row_actions.composeWithReorder`,
	which is what `table.luau` calls; the export shape is unchanged.

	DEPENDS ON: `../input/row_actions_state` for `AXIS_LOCK_PX` alone — the SAME
	authored constant the row engine's own `onPointerMove` applies to itself,
	which is exactly why the arbitration lives beside it rather than in
	table.luau.

	WHY IT IS ITS OWN FILE (2026-08-14): `row_actions.luau` had to shed periphery
	to get back under the 200,000-char `Script.Source` WRITE cap Rojo live-sync
	assigns through (docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md,
	tools/check_source_size.py). ]]

local row_actions_state = require("../input/row_actions_state")

local row_actions_reorder = {}

-- ===== Task 10: reorder composition (Table integration) ====================
-- Table's own row Hit surface, when BOTH `reorderable` and `rowActions` are
-- true for a row, has two candidate owners for the SAME raw pointer capture:
-- this composite's swipe gesture (horizontal) and Table's own drag-to-reorder
-- (vertical). Both ride the identical low-level onPointerDown/Move/Up/Cancel
-- capture (ADR-0008) — the engine hands a SINGLE gesture to whichever side
-- claims it, and neither gesture alone knows the other exists. Composed here,
-- not in table.luau (the brief's own design), because the axis-lock rule —
-- "ties go vertical" (`row_actions_state.AXIS_LOCK_PX`), the SAME constant
-- this composite's own internal `onPointerMove` already applies to itself —
-- belongs with the one other place it is authored, not duplicated.
--
-- THE DEFERRED-DOWN SHAPE. The axis is unknown at down (dx = dy = 0, the same
-- "tentative accept" problem `onPointerDown`'s own header comment describes
-- for this composite alone), so down here commits to neither engine yet: it
-- tracks the raw origin and accepts the capture (mouse can never partially
-- decline once accepted — same "no third option" the header comment already
-- establishes), deferring both `rowActionsHandlers.onPointerDown` and
-- `reorderHandlers.onPointerDown` until the FIRST move that crosses the axis
-- lock, at which point exactly ONE is replayed from the ORIGINAL down
-- position (never the current one — a gesture that resolves 20px into the
-- move must still look, to whichever engine wins, like a press that just
-- happened) and owns every subsequent move/up/cancel for the rest of this
-- gesture. The OTHER engine never sees this gesture at all — never a down,
-- never a move — so neither `reorderHandlers`' own `rowDrag` nor this
-- composite's own `drag` local is ever touched by the loser, and neither can
-- misfire later from stray state.
--
-- TOUCH skips the deferral entirely: table.luau's `reorderHandlers` already
-- declines touch on the row body unconditionally (native scroll owns the
-- pan — table.luau's own native-scroll header), so a touch gesture is
-- unambiguously this composite's from the first frame.
--
-- `reorderHandlers == nil` (a Table that is not `reorderable`, or a
-- standalone caller with nothing to compose against) returns
-- `rowActionsHandlers` unchanged — a plain pass-through, zero overhead.
function row_actions_reorder.compose(rowActionsHandlers: any, reorderHandlers: any?): any
	if reorderHandlers == nil then
		return rowActionsHandlers
	end

	type Pending = {
		originX: number,
		originY: number,
		originPos: any,
		path: string,
		rectOf: (string) -> any,
		mode: "pending" | "rowActions" | "reorder",
	}
	local pending: Pending? = nil

	-- axis verdict is a pure function of dx/dy and the fixed AXIS_LOCK_PX
	-- constant alone (identical rule to this composite's own internal
	-- `onPointerMove`); called only while `mode == "pending"`.
	local function resolveAxis(pos: any)
		local p = pending :: Pending
		local dx, dy = pos.x - p.originX, pos.y - p.originY
		if dx * dx + dy * dy < row_actions_state.AXIS_LOCK_PX ^ 2 then
			return -- still accumulating toward the lock radius
		end
		-- ties go vertical (row_actions_state.axisVerdict's own rule):
		-- scrolling/reordering must never lose an ambiguous gesture.
		if math.abs(dx) > math.abs(dy) then
			p.mode = "rowActions"
			-- REDTEAM FIX (item 13, LOW): `replayed = true` (a shallow copy —
			-- `p.originPos` itself is left untouched, still the exact table a
			-- caller may be holding elsewhere) tells `onPointerDown`'s own
			-- velocity-tracker seed to skip itself here (see its own big
			-- comment): this replay's POSITION is correct (the true origin,
			-- still needed for `drag.originX/Y`'s own clamp math) but its
			-- TIME is not (this dispatcher has no clock of its own, by
			-- design), so seeding the tracker from it would corrupt a
			-- release-velocity computed shortly after the axis resolves.
			rowActionsHandlers.onPointerDown(
				p.path,
				{ x = p.originPos.x, y = p.originPos.y, pointerType = p.originPos.pointerType, replayed = true },
				p.rectOf
			)
		else
			p.mode = "reorder"
			-- REPLAYED at the origin (see header comment). reorder's own down
			-- handler re-runs its handle-zone/touch decline checks here too —
			-- both moot in practice (touch never reaches this branch; the
			-- handle zone is checked by Table BEFORE this dispatcher ever
			-- runs), so this is a harmless re-check on the way to seeding
			-- `rowDrag`.
			reorderHandlers.onPointerDown(p.path, p.originPos, p.rectOf)
		end
	end

	local function onPointerDown(path: string, pos: any, rectOf: (string) -> any): boolean?
		if pending ~= nil then
			return false -- a capture is already live; never steal
		end
		if pos.pointerType == "touch" then
			pending = {
				originX = pos.x,
				originY = pos.y,
				originPos = pos,
				path = path,
				rectOf = rectOf,
				mode = "rowActions",
			}
			local accepted = rowActionsHandlers.onPointerDown(path, pos, rectOf)
			if accepted == false then
				pending = nil
			end
			return accepted
		end
		pending = {
			originX = pos.x,
			originY = pos.y,
			originPos = pos,
			path = path,
			rectOf = rectOf,
			mode = "pending",
		}
		return true
	end

	local function onPointerMove(path: string, pos: any, rectOf: (string) -> any)
		if pending == nil then
			return
		end
		if pending.mode == "pending" then
			resolveAxis(pos)
		end
		if pending.mode == "rowActions" then
			rowActionsHandlers.onPointerMove(path, pos, rectOf)
		elseif pending.mode == "reorder" then
			reorderHandlers.onPointerMove(path, pos, rectOf)
		end
	end

	local function onPointerUp(path: string, pos: any, rectOf: (string) -> any)
		if pending == nil then
			return
		end
		local mode = pending.mode
		pending = nil
		if mode == "rowActions" then
			rowActionsHandlers.onPointerUp(path, pos, rectOf)
		elseif mode == "reorder" then
			reorderHandlers.onPointerUp(path, pos, rectOf)
		end
		-- "pending" (never crossed the lock radius — a tap): neither engine
		-- was ever told a down, so neither is told an up.
	end

	local function onPointerCancel(path: string, reason: string?): boolean?
		if pending == nil then
			return nil
		end
		local mode = pending.mode
		pending = nil
		if mode == "rowActions" then
			return rowActionsHandlers.onPointerCancel(path, reason)
		elseif mode == "reorder" then
			return reorderHandlers.onPointerCancel(path, reason)
		end
		return nil
	end

	return {
		onPointerDown = onPointerDown,
		onPointerMove = onPointerMove,
		onPointerUp = onPointerUp,
		onPointerCancel = onPointerCancel,
	}
end

return row_actions_reorder
