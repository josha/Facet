--!strict
-- CLIENT-ONLY. The one binding between a presenter's frame tick and the engine
-- render clock. Everything time-driven in the presentation layer — the motion
-- clock, structural transitions, toast scheduling, the 500 ms exit cap — advances
-- inside `presenter.tick(dt)`, and nothing advances without it: the headless
-- suite passes a scripted dt, and THIS module is the live analog. Bind once per
-- presenter; a second bind of the same presenter is a mistake the double-tick
-- would make visible, so it is rejected loudly instead.
--
-- PreRender, not Heartbeat: Heartbeat runs after render, which adds a frame of
-- latency to every visual the tick drives (the same reasoning as the adapter's
-- input paths; see APPLE_UI_MOTION_SKILL §11 for the platform rule).
--
-- TWO THINGS THE CALLER OWNS (measured on a real client):
--   1. THE UNBIND. Nothing here watches presenter lifetime — disposing a
--      presenter does not disconnect its binding, and `bound` keys presenters
--      strongly, so a discarded unbind keeps ticking (and retaining) a surface
--      nobody presents. Keep the returned function next to whatever owns the
--      presenter and call it there.
--   2. THE BUDGET. A PreRender handler BLOCKS the rendering pipeline until it
--      returns, so everything `presenter.tick` does — the clock's one
--      transaction, every motion write, transitions, the toast schedule — is
--      spent on the render thread. The frame budget those numbers are measured
--      against is therefore a render-thread budget, not spare time.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local motion_driver = {}

local bound: { [any]: RBXScriptConnection } = {}

--[[ THE ENGINE OWNS THE CURVE (ADR-0033; director ruling 2026-08-15, "use
	Roblox's animation system wherever possible"). `TweenService:GetValue` is the
	engine's easing evaluator and it is PURE — a number in, a number out, touching
	no Instance — which is the property that lets it drive a value Facet owns.
	`TweenService:Create` cannot: it targets an Instance, so driving a MotionValue
	through it would mean a proxy Instance per animated value (measured 6.1 us and
	one Instance each, against 0.031 us for the ramp Facet already runs), a dead
	Tween object per retarget, a completion that fires outside the clock's post
	phase, and a flight `clock:step(dt)` cannot advance — which would put the whole
	shipped path outside the headless suite.

	So the engine evaluates the curve and Facet's clock keeps the time — and the
	clock's time is the engine's too, since `PreRender` below is what advances it.
	Binding here rather than asking every game to wire it means native is the
	DEFAULT on Roblox, not an opt-in someone forgets; the pure twin in
	`src/motion/curves.luau` then serves only Lune, pinned to this very function by
	a differential oracle (33,033 samples, max |err| 4.73e-7).

	Cost, measured live 2026-08-15 (A/A control spread 3.8% over runs 2-4; the cold
	first run was 37% and is excluded as warm-up): 58.6 ns per call against 9.2 ns
	for the pure twin — 6.3x, and 3.5 us per frame at sixty concurrent tweens, or
	0.02% of a 16.7 ms budget. The engine is not cheaper here; it is CORRECT, which
	is the reason to take it. ]]
local function engineEasing(alpha: number, style: string, direction: string): number
	return TweenService:GetValue(
		alpha,
		(Enum.EasingStyle :: any)[string.upper(string.sub(style, 1, 1)) .. string.sub(style, 2)],
		(Enum.EasingDirection :: any)[if direction == "in" then "In" elseif direction == "out" then "Out" else "InOut"]
	)
end

motion_driver.engineEasing = engineEasing

-- bind(presenter) -> unbind. `presenter.tick(dt)` receives the PreRender dt so
-- clock time tracks render time exactly (tab-out stalls are clamped inside the
-- spring solver, not here).
function motion_driver.bind(presenter: any): () -> ()
	assert(type(presenter) == "table" and type(presenter.tick) == "function", "motion_driver.bind: not a presenter")
	assert(bound[presenter] == nil, "motion_driver.bind: this presenter is already bound (one clock, one driver)")
	-- hand the clock the engine's own easing evaluator (see `engineEasing` above).
	-- Guarded rather than assumed: a host may pass a presenter stub without a
	-- clock, and a missing evaluator degrades to the proven-equal pure twin rather
	-- than to a crash at bind time.
	local clock = presenter.motionClock
	if type(clock) == "table" and type(clock.setEasing) == "function" then
		clock:setEasing(engineEasing)
	end
	--[[ AND THE CLAIM THE OTHER DRIVER CAN SEE (R5 review §3b-3). `bound` above
		is private to this module, so its assert only ever caught a second
		`motion_driver.bind`; `client.host` connects its own PreRender and was
		invisible to it. `presenter.claimFrameDriver` is on the presenter, which
		is the one object both drivers hold, so the rule now catches the pair in
		either order. Guarded for a presenter stub older than the seam. ]]
	local releaseClaim = if type(presenter.claimFrameDriver) == "function"
		then presenter.claimFrameDriver("motion_driver.bind")
		else function() end
	local connection = RunService.PreRender:Connect(function(dt: number)
		presenter.tick(dt)
	end)
	bound[presenter] = connection
	return function()
		if bound[presenter] ~= nil then
			bound[presenter]:Disconnect()
			bound[presenter] = nil
			releaseClaim()
		end
	end
end

return motion_driver
