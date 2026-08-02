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
-- TWO THINGS THE CALLER OWNS (platform verifier PLAT-6):
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

local motion_driver = {}

local bound: { [any]: RBXScriptConnection } = {}

-- bind(presenter) -> unbind. `presenter.tick(dt)` receives the PreRender dt so
-- clock time tracks render time exactly (tab-out stalls are clamped inside the
-- spring solver, not here).
function motion_driver.bind(presenter: any): () -> ()
	assert(type(presenter) == "table" and type(presenter.tick) == "function", "motion_driver.bind: not a presenter")
	assert(bound[presenter] == nil, "motion_driver.bind: this presenter is already bound (one clock, one driver)")
	local connection = RunService.PreRender:Connect(function(dt: number)
		presenter.tick(dt)
	end)
	bound[presenter] = connection
	return function()
		if bound[presenter] ~= nil then
			bound[presenter]:Disconnect()
			bound[presenter] = nil
		end
	end
end

return motion_driver
