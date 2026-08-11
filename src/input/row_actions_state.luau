--!strict
-- Internal pure decision module for row swipe actions (spec: docs/plans/row-actions.md).
-- Consumed by the future newRowActions composite control.
-- No Instances, no clock, no engine — every verdict is a function of inputs.

local row_actions_state = {}

row_actions_state.AXIS_LOCK_PX = 8
row_actions_state.OPEN_FRACTION = 0.5
row_actions_state.COMMIT_FRACTION = 0.6
row_actions_state.RESISTANCE = 0.55
row_actions_state.VELOCITY_PROJECT_S = 0.08

export type AxisVerdict = "pending" | "horizontal" | "vertical"
export type Edge = "leading" | "trailing"

export type Verdict = {
	target: number,
	edge: Edge?,
	commit: boolean,
}

function row_actions_state.new(opts: {
	rowWidth: number,
	leadingWidth: number,
	trailingWidth: number,
	fullSwipeLeading: boolean,
	fullSwipeTrailing: boolean,
})
	local self = {}

	function self.axisVerdict(dx: number, dy: number): AxisVerdict
		if dx * dx + dy * dy < row_actions_state.AXIS_LOCK_PX ^ 2 then
			return "pending"
		end
		-- ties go vertical: scrolling must never lose an ambiguous gesture
		return if math.abs(dx) > math.abs(dy) then "horizontal" else "vertical"
	end

	local function edgeFor(offset: number): (Edge?, number, boolean)
		if offset > 0 then
			return "leading", opts.leadingWidth, opts.fullSwipeLeading
		elseif offset < 0 then
			return "trailing", opts.trailingWidth, opts.fullSwipeTrailing
		end
		return nil, 0, false
	end

	function self.clampDrag(raw: number): number
		local _, tray, fullSwipe = edgeFor(raw)
		local mag = math.abs(raw)
		if fullSwipe or mag <= tray then
			return raw
		end
		return math.sign(raw) * (tray + (mag - tray) * row_actions_state.RESISTANCE)
	end

	function self.settle(offset: number, velocityX: number): Verdict
		local projected = offset + velocityX * row_actions_state.VELOCITY_PROJECT_S
		local edge, tray, fullSwipe = edgeFor(projected)
		if edge == nil or tray <= 0 then
			return { target = 0, edge = nil, commit = false }
		end
		local mag = math.abs(projected)
		-- REDTEAM FIX (item 8, MEDIUM): `opts.rowWidth <= 0` (an unmeasured
		-- row — geometry not solved yet, e.g. the very first frame of a
		-- gesture that started before any refresh) used to make this
		-- condition `mag >= 0`, true for ANY nonzero drag: a 1px nudge
		-- against a real, non-fullSwipe-guarded tray could "commit" at
		-- `target = sign(projected) * 0 == 0` — a phantom commit nobody
		-- dragged far enough to ask for. A commit needs a real row width to
		-- measure 60% of in the first place.
		if fullSwipe and opts.rowWidth > 0 and mag >= opts.rowWidth * row_actions_state.COMMIT_FRACTION then
			return { target = math.sign(projected) * opts.rowWidth, edge = edge, commit = true }
		end
		if mag >= tray * row_actions_state.OPEN_FRACTION then
			return { target = math.sign(projected) * tray, edge = edge, commit = false }
		end
		return { target = 0, edge = nil, commit = false }
	end

	return self
end

return row_actions_state
