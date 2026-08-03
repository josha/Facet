--!strict
-- Drag-to-edge autoscroll (ADR-0022 Decision 5, row SF-L2). A PURE model: it
-- owns the band/dwell/ramp/clamp policy and answers a scroll DELTA per frame.
-- It never touches a scroll host, never reads a clock, and never re-solves
-- anything — the host applies the delta through `controller.scrollTo` and then
-- re-runs the drop hit-test in the SAME frame (see `virtual_list`).
--
-- THE NUMBERS, and where they come from (ratified racer-list autoscroll spec,
-- shipping here as framework defaults with their tuning ranges):
--   bandH      40 px landscape / 44 px portrait   [32–52]
--   dwellS     0.30 s                             [0.25–0.40]
--   vMin/vMax  100 → 500 px/s, linear in penetration   [80–140] / [400–650]
--   rampS      0.15 s quad ease-out from arming
--   exitEaseS  0.08 s decay to zero on leaving the band
--
-- THE FIVE RULES THAT MAKE IT FEEL RIGHT, each independently falsifiable:
--
--  1. MEMBERSHIP IS THE POINTER POINT, never the dragged proxy's bounds. The
--     band and the drop hit-test must read the same coordinate, or the row the
--     player is scrolling toward is not the row the verdict is about.
--  2. DWELL IS WHAT MAKES A FLICK-THROUGH SAFE. 300 ms of continuous presence
--     in ONE band before anything moves; leaving both bands or crossing to the
--     other band resets the timer, jitter INSIDE a band does not. A drag that
--     sweeps past the edge on its way somewhere else therefore never arms, and
--     that falls out of the dwell rule rather than needing a velocity special
--     case.
--  3. SPEED IS LINEAR IN PENETRATION, so the player steers the rate with the
--     same finger that is already steering the drop — deeper is faster, and the
--     mapping is continuous rather than a two-speed step.
--  4. THE START RAMP IS SEPARATE FROM THE SPEED CURVE. Arming at 100 px/s
--     still reads as a jerk, so the effective velocity eases 0 → v(p) over
--     150 ms from the ARMING instant (not from each frame's penetration), and
--     eases back to 0 over 80 ms when the pointer leaves. THE SAME 80 ms EASE
--     CARRIES A DIRECT BAND CROSS: dropping from full speed one way to zero
--     the instant the finger reaches the opposite band is a hard velocity flip,
--     and "reversing direction mid-ease reads better" is the shipped ruling
--     (RascalRally `UI_SPEC_sponsor_luauui` §11 D-11, off `SponsorGesture`
--     :762-770). So the decay is a channel, not a state: it runs under
--     "exiting" AND under the fresh "dwelling" the cross starts, and arming
--     supersedes it.
--  5. THE CANVAS END CLAMPS BUT STAYS ARMED. Hitting the bottom returns a zero
--     delta while the state stays "active", so pulling back up and pushing down
--     again does not re-pay the dwell. Content with nothing to scroll
--     (`maxScroll <= 0`) is INERT — no arming, no affordance for a scroll that
--     cannot happen.
--
-- `justArmed` is true on EXACTLY the frame arming happens, once per arming: it
-- is the haptic/feedback hook (one tick at scroll-start, never per frame).
--
-- Non-pointer schemes have no autoscroll path at all: focus-follows-navigation
-- already scrolls the host, and duplicating dwell/band for a focus ring would
-- be a second mechanism answering the same question.

local specGuard = require("../spec_guard")

local autoscroll = {}

-- band height by viewport shape (ratified defaults). Portrait gets the taller
-- band because a portrait viewport has less vertical room to aim at.
local BAND_H = table.freeze({ landscape = 40, portrait = 44 })
autoscroll.BAND_H = BAND_H

local DEFAULTS = table.freeze({
	bandH = BAND_H.landscape,
	dwellS = 0.3,
	rampS = 0.15,
	exitEaseS = 0.08,
	vMin = 100,
	vMax = 500,
})
autoscroll.DEFAULTS = DEFAULTS

export type Opts = {
	bandH: number?,
	dwellS: number?,
	rampS: number?,
	exitEaseS: number?,
	vMin: number?,
	vMax: number?,
}

export type Input = {
	now: number,
	-- pointer point in the SAME space as hostRect (window space)
	pointerPos: { x: number, y: number }?,
	hostRect: { x: number, y: number, w: number, h: number }?,
	canvasPos: number, -- current scroll offset along the scroll axis
	maxScroll: number, -- the largest legal offset (0 = nothing to scroll)
}

export type Step = {
	delta: number,
	state: string, -- "idle" | "dwelling" | "active" | "exiting"
	justArmed: boolean,
}

-- the caller resolves the band from the viewport it is actually in; this is the
-- one place that decides which of the two ratified numbers that is
function autoscroll.bandForViewport(width: number, height: number): number
	if type(width) ~= "number" or type(height) ~= "number" then
		return BAND_H.landscape
	end
	return if height > width then BAND_H.portrait else BAND_H.landscape
end

local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function number(value: any, fallback: number): number
	return if isFinite(value) then value :: number else fallback
end

-- quad ease-out: fast off the mark, settling into the target rate
local function easeOutQuad(k: number): number
	local t = math.clamp(k, 0, 1)
	return 1 - (1 - t) * (1 - t)
end

-- CLOSED OPTS (constitution §4; ARCH-1). Every field here is a tuning number
-- with a default, so a typo produced the default silently — the exact shape of
-- "I changed the value and nothing happened".
local AUTOSCROLL_OPTS_KEYS = specGuard.keySet({ "bandH", "dwellS", "exitEaseS", "rampS", "vMax", "vMin" })

function autoscroll.new(opts: Opts?)
	specGuard.assertKnownKeys("newAutoscroll", opts, AUTOSCROLL_OPTS_KEYS, "opts")
	local options: Opts = opts or {}
	local bandH = math.max(1, number(options.bandH, DEFAULTS.bandH))
	local dwellS = math.max(0, number(options.dwellS, DEFAULTS.dwellS))
	local rampS = math.max(0, number(options.rampS, DEFAULTS.rampS))
	local exitEaseS = math.max(0, number(options.exitEaseS, DEFAULTS.exitEaseS))
	local vMin = math.max(0, number(options.vMin, DEFAULTS.vMin))
	local vMax = math.max(vMin, number(options.vMax, DEFAULTS.vMax))

	local state = "idle"
	local band: string? = nil -- "top" | "bottom"
	local dwellStart = 0
	local armedAt = 0
	local exitStart = 0
	local exitVelocity = 0 -- signed px/s captured on the frame the band was left
	local penetration = 0
	local lastNow: number? = nil

	-- which band the pointer point is in, and how deep (0 at the inner edge,
	-- 1 at the viewport edge). Bands never overlap: on a host shorter than two
	-- bands they meet at the midpoint instead of double-counting the middle.
	local function bandAt(
		pos: { x: number, y: number }?,
		rect: { x: number, y: number, w: number, h: number }?
	): (string?, number)
		if pos == nil or rect == nil or not isFinite(pos.x) or not isFinite(pos.y) then
			return nil, 0
		end
		if pos.x < rect.x or pos.x >= rect.x + rect.w then
			return nil, 0
		end
		if pos.y < rect.y or pos.y >= rect.y + rect.h then
			return nil, 0
		end
		local depth = math.min(bandH, rect.h / 2)
		if depth <= 0 then
			return nil, 0
		end
		local fromTop = pos.y - rect.y
		if fromTop < depth then
			return "top", math.clamp((depth - fromTop) / depth, 0, 1)
		end
		local fromBottom = rect.y + rect.h - pos.y
		if fromBottom <= depth then
			return "bottom", math.clamp((depth - fromBottom) / depth, 0, 1)
		end
		return nil, 0
	end

	local model = {}

	function model.reset(_: any)
		state = "idle"
		band = nil
		penetration = 0
		exitVelocity = 0
		lastNow = nil
	end

	-- signed effective velocity for the CURRENT state (px/s; negative = up)
	local function activeVelocity(now: number): number
		local v = vMin + (vMax - vMin) * penetration
		local ramp = if rampS > 0 then easeOutQuad((now - armedAt) / rampS) else 1
		local signed = v * ramp
		return if band == "top" then -signed else signed
	end

	-- the coast. A live `exitVelocity` decays linearly to zero over `exitEaseS`
	-- from `exitStart`, and it is deliberately INDEPENDENT of the state machine:
	-- the same decay carries "left both bands" (state "exiting") and "crossed
	-- straight to the other band" (state "dwelling", re-paying its own dwell).
	-- Self-retiring — it zeroes itself the frame the ease completes.
	local function coastVelocity(now: number): number
		if exitVelocity == 0 then
			return 0
		end
		local k = if exitEaseS > 0 then math.clamp((now - exitStart) / exitEaseS, 0, 1) else 1
		if k >= 1 then
			exitVelocity = 0
			return 0
		end
		return exitVelocity * (1 - k)
	end

	-- capture the velocity the pointer is leaving this band at, so it can coast
	local function beginCoast(now: number)
		exitVelocity = activeVelocity(now)
		exitStart = now
	end

	function model.step(_: any, input: Input): Step
		local now = number(input.now, 0)
		local previous = lastNow
		lastNow = now
		local dt = if previous == nil then 0 else math.max(0, now - previous)
		local maxScroll = number(input.maxScroll, 0)
		local canvasPos = number(input.canvasPos, 0)

		-- SHORT CONTENT IS INERT (rule 5): nothing to scroll means no dwell, no
		-- arming, and no affordance the player could believe in.
		if maxScroll <= 0 then
			model:reset()
			return { delta = 0, state = "idle", justArmed = false }
		end

		local hit, depth = bandAt(input.pointerPos, input.hostRect)
		local justArmed = false

		if hit == nil then
			if state == "active" then
				beginCoast(now)
				state = "exiting"
			elseif state == "dwelling" then
				-- a flick THROUGH the band never arms (rule 2). Any coast already
				-- in flight keeps decaying — leaving does not re-cut it.
				state = if exitVelocity ~= 0 then "exiting" else "idle"
			end
			band = nil
			penetration = 0
		else
			penetration = depth
			if hit ~= band then
				-- crossing bands is a fresh intent: the dwell restarts, even from
				-- "active" in the opposite band — and the speed it was carrying
				-- COASTS out over the same 80 ms rather than flipping to zero
				-- (rule 4, D-11)
				if state == "active" then
					beginCoast(now)
				end
				band = hit
				dwellStart = now
				state = "dwelling"
			elseif state == "idle" or state == "exiting" then
				-- re-entering the band it just left re-pays the dwell (rule 2 has
				-- no memory: leaving IS the reset)
				dwellStart = now
				state = "dwelling"
			end
			if state == "dwelling" and now - dwellStart >= dwellS then
				state = "active"
				armedAt = now
				justArmed = true
			end
		end

		local delta = 0
		if state == "active" then
			-- arming supersedes the coast: the ramp starts from zero, so adding a
			-- decaying old velocity on top would double-count the first frames
			exitVelocity = 0
			delta = activeVelocity(now) * dt
		else
			local coast = coastVelocity(now)
			delta = coast * dt
			if state == "exiting" and coast == 0 then
				state = "idle"
			end
		end

		-- CANVAS-END CLAMP (rule 5): the delta is trimmed to what the host can
		-- actually take, and the state does NOT fall out of "active" — the player
		-- is still pushing, there is just nowhere left to go.
		if delta ~= 0 then
			local wanted = math.clamp(canvasPos + delta, 0, maxScroll)
			delta = wanted - canvasPos
		end

		return { delta = delta, state = state, justArmed = justArmed }
	end

	function model.state(_: any): string
		return state
	end

	function model.band(_: any): string?
		return band
	end

	function model.penetration(_: any): number
		return penetration
	end

	-- the tuning actually in force, for the gate's "within the ratified range?"
	-- check and for a fixture that wants to display it
	function model.options(_: any)
		return {
			bandH = bandH,
			dwellS = dwellS,
			rampS = rampS,
			exitEaseS = exitEaseS,
			vMin = vMin,
			vMax = vMax,
		}
	end

	return model
end

return autoscroll
