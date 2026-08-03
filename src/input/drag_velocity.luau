--!strict
-- Release-velocity tracker (ADR-0022 Decision 5, row SF-D2). A rolling,
-- TIME-WINDOWED sample buffer whose estimate is first-vs-last across the
-- retained window.
--
-- WHY NOT THE LAST FRAME'S DELTA: one frame of pointer movement is mostly
-- noise — a 16 ms sample of a finger that is decelerating reports whatever the
-- last jitter did, so a flick and a stop can hand back the same number. A
-- 100 ms window averages the gesture's actual intent, which is what the settle
-- motion needs to continue without a visible seam.
--
-- WHY FIRST-VS-LAST AND NOT A FIT: the pair estimate is the derivative of the
-- gesture over the window and costs two subtractions; a least-squares fit over
-- the same samples answers a slightly smoother number that no player can tell
-- apart, at a cost paid every pointer move.
--
-- TIME IS INJECTED. `push` takes the timestamp; this module never reads
-- `os.clock`, so a scripted clock replays a flick exactly (the whole reason the
-- release feel is assertable headlessly).
--
-- THE READ ORDER IS PART OF THE CONTRACT: read `velocity()` at release BEFORE
-- any state reset, or the buffer that describes the gesture is already gone. A
-- non-gestural cancel (keyboard, gamepad, a modal stealing the drag) seeds ZERO
-- through this same consumer path rather than skipping it — one code path means
-- the two cancels cannot drift in feel.

local specGuard = require("../spec_guard")

local drag_velocity = {}

-- the ratified window (Sponsor motion spec): 0.1 s
local WINDOW_S = 0.1

export type Sample = { t: number, x: number, y: number }

export type Opts = {
	windowS: number?,
}

local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- CLOSED OPTS (constitution §4; ARCH-1): one tuning field, and therefore the
-- easiest of all to misspell into the default.
local DRAG_VELOCITY_OPTS_KEYS = specGuard.keySet({ "windowS" })

function drag_velocity.new(opts: Opts?)
	specGuard.assertKnownKeys("newDragVelocity", opts, DRAG_VELOCITY_OPTS_KEYS, "opts")
	local options: Opts = opts or {}
	local windowS = if isFinite(options.windowS) and (options.windowS :: number) > 0
		then options.windowS :: number
		else WINDOW_S

	local samples: { Sample } = {}

	local tracker = {}

	-- record a position at time `t`. Samples older than the window are dropped,
	-- but the buffer NEVER falls below two: a gesture that paused before release
	-- must still answer a velocity (zero, from two stale samples that did not
	-- move) instead of falling back to "no samples" and letting the caller
	-- invent one.
	function tracker.push(_: any, x: number, y: number, t: number)
		if not isFinite(x) or not isFinite(y) or not isFinite(t) then
			return
		end
		table.insert(samples, { t = t, x = x, y = y })
		local last = samples[#samples]
		while #samples > 2 and (last.t - samples[1].t) > windowS do
			table.remove(samples, 1)
		end
	end

	-- px/s over the retained window. Zero for fewer than two samples or a
	-- non-advancing clock — never a division by zero and never an infinity
	-- handed to a spring.
	function tracker.velocity(_: any): (number, number)
		if #samples < 2 then
			return 0, 0
		end
		local first = samples[1]
		local last = samples[#samples]
		local dt = last.t - first.t
		if dt <= 0 then
			return 0, 0
		end
		return (last.x - first.x) / dt, (last.y - first.y) / dt
	end

	function tracker.reset(_: any)
		table.clear(samples)
	end

	function tracker.sampleCount(_: any): number
		return #samples
	end

	-- the most recent recorded point (nil before the first push): the caller's
	-- release position when the terminal event carries none of its own
	function tracker.last(_: any): Sample?
		return samples[#samples]
	end

	function tracker.windowSeconds(_: any): number
		return windowS
	end

	return tracker
end

drag_velocity.WINDOW_S = WINDOW_S

return drag_velocity
