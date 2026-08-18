--!strict
--[[ SAFE-AREA INSET DERIVATION AND ITS STALENESS BELT — the pure half of the
	platform adapter's `GuiService:GetInsetArea` handling (PLAT-3, redone
	2026-08-17 after review finding NEW-1).

	`src/client/roblox_env.luau` is the one file allowed to read the engine's
	inset services, and until this module existed the arithmetic that turns an
	engine rect into four edge insets lived inside it — which meant the two
	things most worth proving about it (the space conversion, and whether the
	answer can be trusted at all) could only be proved on a device. Nothing here
	touches an engine type: the caller unpacks the `Rect` and the `Vector2` at the
	seam, and this decides what they mean.

	THE SPACE CONVERSION. `GetInsetArea` answers in the SAME inset-subtracted
	space `AbsolutePosition` uses — measured on desktop, the `CoreUISafeInsets`
	rect reads (0,0)->(w, h-58) while the window is h tall — so window-space edge
	distances come from adding the legacy `GetGuiInset()` top offset back before
	subtracting.

	── THE BELT, AND WHY THE FIRST ONE COULD NOT REFUSE ANYTHING ───────────────

	`Camera.ViewportSize` and `GetInsetArea` update on DIFFERENT frames, so one
	pass through the adapter can convert an area measured against the OLD viewport
	using the NEW one. That is the defect. The first attempt at this belt tested
	the DERIVED INSET against the same viewport that derived it:

	    top + bottom < viewport.h and left + right < viewport.w

	and `fromArea` computes `bottom = viewport.h - (area.maxY + oy)`, so
	`top + bottom` is identically `viewport.h - (area.maxY - area.minY)`. The test
	reduces to "does the area have positive height", a property of the AREA ALONE:
	the viewport cancels out and cannot disagree with itself. Measured over the
	adapter's own call shape, 48 cases, ZERO refusals — including a portrait area
	read against a landscape window, which published a `bottom` reserving 96% of
	the axis. `src/env/environment.luau:354` works because the inset it re-tests
	was DERIVED UNDER AN EARLIER VIEWPORT and stored; the adapter recomputes fresh
	every pass, so that asymmetry never exists there.

	WHAT ACTUALLY DISCRIMINATES, and it is one fact: a safe area ENCODES the
	window it was measured on. Every shape the engine produces does — the desktop
	CoreUI area is (0,0)->(w, h-58), a notched portrait device area is
	(0,47)->(w, h-34) — so a viewport change ALWAYS moves the area on a platform
	that has caught up. Therefore an area that is BYTE-IDENTICAL to the one seen
	on the previous pass, arriving beside a viewport that CHANGED, is by
	construction still describing the previous viewport. That is the disagreement,
	and it is the shape the adapter really produces: the new `viewportRect` first,
	the matching area a frame or more later.

	The judgement is therefore STATEFUL and per fact key, which is the same shape
	`environment.luau`'s belt has (it re-tests a stored value against current
	facts); this one stores the area rather than the inset, because the area is
	the half that lags. A held pass publishes nothing, so the last good value
	stands — publishing zeroes was rejected: on a notched device that is a wrong
	answer that looks right, where the previous orientation's inset is at least
	the shape of a real safe area.

	AND A FIRST-PASS GUARD, because the cross-pass test has nothing to compare on
	the very first push: an area that does not FIT inside the viewport it is being
	published beside, in the same space, cannot have come from it either.
]]

local safe_insets = {}

export type Insets = { top: number, bottom: number, left: number, right: number }
export type Area = { minX: number, minY: number, maxX: number, maxY: number }
export type Viewport = { w: number, h: number }
export type GuiInset = { x: number, y: number }

-- engine area (inset-subtracted space) -> window-space edge insets
function safe_insets.fromArea(area: Area, guiInset: GuiInset, viewport: Viewport): Insets
	local ox, oy = guiInset.x, guiInset.y
	return {
		top = math.max(0, area.minY + oy),
		left = math.max(0, area.minX + ox),
		right = math.max(0, viewport.w - (area.maxX + ox)),
		bottom = math.max(0, viewport.h - (area.maxY + oy)),
	}
end

-- FIRST-PASS GUARD: could this area have been measured on this viewport at all?
-- Non-degenerate, non-negative, and contained by the window once converted into
-- window space. One pixel of slack absorbs the engine's own rounding.
local FIT_SLACK = 1
function safe_insets.areaFitsViewport(area: Area, guiInset: GuiInset, viewport: Viewport): boolean
	if area.maxX <= area.minX or area.maxY <= area.minY then
		return false
	end
	if area.minX < 0 or area.minY < 0 then
		return false
	end
	return area.maxX + guiInset.x <= viewport.w + FIT_SLACK and area.maxY + guiInset.y <= viewport.h + FIT_SLACK
end

local function sameArea(a: Area?, b: Area?): boolean
	if a == nil or b == nil then
		return false
	end
	return a.minX == b.minX and a.minY == b.minY and a.maxX == b.maxX and a.maxY == b.maxY
end

local function sameViewport(a: Viewport?, b: Viewport?): boolean
	if a == nil or b == nil then
		return false
	end
	return a.w == b.w and a.h == b.h
end

export type Belt = {
	-- "publish" when the area and the viewport agree; "hold" while the area is
	-- still describing the previous viewport
	judge: (self: Belt, key: string, area: Area, guiInset: GuiInset, viewport: Viewport) -> boolean,
	-- diagnostics: how many pushes this belt has held, per key
	held: (self: Belt) -> { [string]: number },
}

--[[ One belt per adapter binding; one record per fact key, because the three
	areas (`core`, `device`, `topbar`) lag independently. ]]
function safe_insets.newBelt(): Belt
	local lastArea: { [string]: Area } = {}
	local lastViewport: { [string]: Viewport } = {}
	local heldCount: { [string]: number } = {}
	local belt = {}

	function belt.judge(_self, key: string, area: Area, guiInset: GuiInset, viewport: Viewport): boolean
		local function hold(): boolean
			heldCount[key] = (heldCount[key] or 0) + 1
			-- the VIEWPORT is recorded even on a hold: the disagreement is with
			-- this viewport, and the next pass must compare against it rather than
			-- against the one two changes ago
			lastViewport[key] = viewport
			return false
		end
		if not safe_insets.areaFitsViewport(area, guiInset, viewport) then
			return hold()
		end
		if sameArea(lastArea[key], area) and not sameViewport(lastViewport[key], viewport) then
			return hold()
		end
		lastArea[key] = area
		lastViewport[key] = viewport
		return true
	end

	function belt.held(_self): { [string]: number }
		return table.clone(heldCount)
	end

	return belt :: any
end

return safe_insets
