--!strict
-- Perceptual arrival (ui-designer spec §1.4): a 2-D flight
-- is TWO scalar springs, and it ARRIVES when it enters a radius around the LIVE
-- target — not when the solver's settle epsilon trips.
--
-- WHY A RADIUS: settle is |x - target| <= 1e-3 AND |v| <= 1e-3, which in the
-- position domain trails the moment a player sees the thing land by ~0.7 s
-- (measured in the shipped implementation this ports). A game beat fired on
-- settle therefore desyncs from what the eye saw. The radius (4 px default,
-- [2–8]) fires on the causal frame; settle stays as the FALLBACK for the two
-- cases the radius cannot answer: the target vanished (its row unmounted), or
-- the chase never catches a fast mover and the springs stop short.
--
-- The target is re-read ONCE PER FRAME, in the retarget phase, and arrival is
-- judged against that same read — so "arrived" always means "arrived at where
-- the target was on the frame we said so", never at a pixel captured at launch.
--
-- Engine-free: the chase is a clock participant like any other motion.

local num = require("../num")

local chase = {}

-- perceptual arrival radius in px (ui-designer spec §1.4 default, range [2–8])
local DEFAULT_ARRIVE_RADIUS = 4

export type Arrival = {
	how: string, -- "radius" (perceptual) | "settle" (fallback)
	targetLost: boolean,
}

export type Opts = {
	x: any, -- MotionValue for the X axis
	y: any, -- MotionValue for the Y axis
	-- the live target: re-read every frame. Return nil (either component) when
	-- the target no longer exists — the flight then resolves by settle and the
	-- arrival reports targetLost, so the consumer can present the honest outcome.
	target: () -> (number?, number?),
	arriveRadius: number?,
	onArrive: ((info: Arrival) -> ())?,
}

export type Chase = {
	cancel: (self: Chase) -> (),
	isDone: (self: Chase) -> boolean,
}

local isFinite = num.isFinite

function chase.new(internals: any, opts: Opts): Chase
	if type(opts) ~= "table" or opts.x == nil or opts.y == nil or type(opts.target) ~= "function" then
		error(
			"Facet motion: clock:chase needs { x = MotionValue, y = MotionValue, target = function() -> (x, y) } "
				.. "(2-D motion is two scalar springs, never one spring on a 2-D distance)",
			0
		)
	end
	local x, y = opts.x, opts.y
	local radius = if isFinite(opts.arriveRadius) and (opts.arriveRadius :: number) >= 0
		then opts.arriveRadius :: number
		else DEFAULT_ARRIVE_RADIUS
	local readTarget = opts.target
	local onArrive = opts.onArrive

	local done = false
	local lost = false
	local haveRead = false
	local tx, ty = 0, 0
	local detach: (() -> ())? = nil

	local handle = {}

	local function finish(how: string)
		if done then
			return
		end
		done = true
		if detach ~= nil then
			detach()
			detach = nil
		end
		if onArrive ~= nil then
			onArrive({ how = how, targetLost = lost })
		end
	end

	-- retarget phase: one live read per frame, then aim both axes at it
	local function retarget()
		if done then
			return
		end
		local rx, ry = readTarget()
		if not isFinite(rx) or not isFinite(ry) then
			lost = true -- vanished: keep the last aim and resolve by settle (§1.3)
			return
		end
		lost = false
		haveRead = true
		tx, ty = rx :: number, ry :: number
		x:setTarget(tx)
		y:setTarget(ty)
	end

	-- post-commit phase: judge arrival against THIS frame's read
	local function judge()
		if done then
			return
		end
		if lost or not haveRead then
			if x:isSettled() and y:isSettled() then
				finish("settle")
			end
			return
		end
		if math.abs(x:get() - tx) <= radius and math.abs(y:get() - ty) <= radius then
			finish("radius")
			return
		end
		if x:isSettled() and y:isSettled() then
			-- the springs came to rest without ever entering the radius (a target
			-- that ran away and stopped, or a radius tighter than the last read)
			finish("settle")
		end
	end

	function handle.cancel(_: any)
		-- abandons the chase WITHOUT an arrival event; the springs keep whatever
		-- aim they had (the caller decides whether to stop or re-aim them)
		if done then
			return
		end
		done = true
		if detach ~= nil then
			detach()
			detach = nil
		end
	end

	function handle.isDone(_: any): boolean
		return done
	end

	-- aim from the first frame rather than waiting for the first step
	retarget()

	if internals.isReduced() then
		-- reduced motion: the retarget above already SNAPPED decorative values to
		-- the target, so the flight is over and the SAME arrival event fires on
		-- the same frame (I-4 information parity). Informational values keep
		-- stepping even under RM, so those fall through and run normally.
		if lost then
			finish("settle")
			return handle :: any
		end
		if x:isSettled() and y:isSettled() then
			finish("radius")
			return handle :: any
		end
	end

	detach = internals.attach({ pre = retarget, post = judge })

	return handle :: any
end

return chase
