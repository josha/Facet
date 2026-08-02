--!strict
-- Pure drag-session model (corrections addendum §1: "Keep a pure Luau drag-
-- session model for payloads, legal drop targets, enter/leave, predicted
-- result, cancellation, and deterministic tests"). Roblox's UIDragDetector owns
-- cross-input drag MOTION at the adapter edge; this module owns the framework
-- POLICY the engine does not: which drop targets are legal for a payload, the
-- enter/leave hover contract, the predicted result while hovering, and honest
-- cancellation. Engine-free and non-yielding — the detector (or a headless
-- driver in tests) feeds it pointer positions in the SAME coordinate space as
-- the target rects, and reads back the hovered target and the drop verdict.
--
-- Determinism rules, all headlessly tested:
--   * Overlapping targets: the LAST match in the array wins. Later array order =
--     higher z in LuauUI's paint order, so the topmost drawn target is the one
--     the pointer is "over" — mirrors what the player sees.
--   * `accepts(payload) == false` makes a target ILLEGAL for this drag: it is
--     skipped by hit-testing, so no enter/predict fires for it.
--   * enter/leave fire EXACTLY once per hover change (leave old, then enter new).
--   * A terminal state (drop or cancel) makes the session INERT: further
--     update/drop/cancel/retarget are no-ops returning nil / an inert result.

local drag_session = {}

export type Rect = { x: number, y: number, w: number, h: number }

export type Target = {
	id: string,
	rect: Rect,
	accepts: ((payload: any) -> boolean)?, -- nil = accepts any payload
}

export type Opts = {
	payload: any,
	source: string,
	targets: { Target },
	onEnter: ((targetId: string) -> ())?,
	onLeave: ((targetId: string) -> ())?,
	-- predicted result while hovering; nil targetId = hovering no legal target
	onPredict: ((targetId: string?, payload: any) -> any)?,
}

export type DropResult = { kind: "dropped", targetId: string, payload: any } | { kind: "rejected" }

export type CancelResult = { kind: "cancelled", reason: string? }

export type State = { active: boolean, hovered: string?, source: string }

-- half-open containment [x, x+w) × [y, y+h): a point on the right/bottom edge
-- belongs to the NEXT adjacent target, so tiled rects partition the plane with
-- no double-hit ambiguity.
local function inside(rect: Rect, x: number, y: number): boolean
	return x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h
end

function drag_session.new(opts: Opts)
	local payload = opts.payload
	local source = opts.source
	local onEnter = opts.onEnter
	local onLeave = opts.onLeave
	local onPredict = opts.onPredict

	local targets: { Target } = opts.targets or {}
	local active = true
	local hovered: string? = nil
	local hasPos = false -- have we seen a pointer position yet?
	local lastX, lastY = 0, 0

	-- topmost LEGAL target under (x,y): last array match wins (paint order)
	local function hitTest(x: number, y: number): string?
		local found: string? = nil
		for _, target in targets do
			if inside(target.rect, x, y) and (target.accepts == nil or target.accepts(payload)) then
				found = target.id
			end
		end
		return found
	end

	-- move hover to `next`, firing leave(old) then enter(new) exactly once, and
	-- re-predicting on any change (including changes to/from no target).
	local function setHover(next: string?)
		if next == hovered then
			return
		end
		if hovered ~= nil and onLeave ~= nil then
			onLeave(hovered)
		end
		hovered = next
		if next ~= nil and onEnter ~= nil then
			onEnter(next)
		end
		if onPredict ~= nil then
			onPredict(next, payload)
		end
	end

	local session = {}

	-- feed the current pointer/detector position; returns the hovered legal
	-- target id (or nil when over none). No-op returning nil once inert.
	function session.update(_: any, x: number, y: number): string?
		if not active then
			return nil
		end
		hasPos, lastX, lastY = true, x, y
		setHover(hitTest(x, y))
		return hovered
	end

	-- commit the drag at (x,y). Dropped over a legal target, else rejected.
	-- Consumes the hover (does NOT fire leave — the drop resolves it) and goes
	-- inert. Inert calls return a plain rejected result.
	function session.drop(_: any, x: number, y: number): DropResult
		if not active then
			return { kind = "rejected" }
		end
		hasPos, lastX, lastY = true, x, y
		local hit = hitTest(x, y)
		active = false
		hovered = nil
		if hit ~= nil then
			return { kind = "dropped", targetId = hit, payload = payload }
		end
		return { kind = "rejected" }
	end

	-- abandon the drag. Fires leave for the currently hovered target first (so
	-- highlight teardown is symmetric with enter), then goes inert.
	function session.cancel(_: any, reason: string?): CancelResult
		if not active then
			return { kind = "cancelled", reason = reason }
		end
		if hovered ~= nil and onLeave ~= nil then
			onLeave(hovered)
		end
		hovered = nil
		active = false
		return { kind = "cancelled", reason = reason }
	end

	-- replace target geometry mid-drag (a scroll host moving under the drag
	-- shifts rects). Re-evaluates hover at the last known position, firing
	-- enter/leave as the target under the pointer changes. No-op once inert or
	-- before any position has been seen.
	function session.retarget(_: any, newTargets: { Target })
		if not active then
			return
		end
		targets = newTargets or {}
		if hasPos then
			setHover(hitTest(lastX, lastY))
		end
	end

	function session.state(_: any): State
		return { active = active, hovered = hovered, source = source }
	end

	return session
end

return drag_session
