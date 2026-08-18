--!strict
-- O-20 / L-29 residual 2 probe: does a PRESENTED MODAL still cost 2 solves per
-- batched geometry change, where a plain screen costs 1?
--
-- The recipe the optimization log recorded (L-29 residual 2, "next step when
-- picked up"): tag the `solveAndApply()` call sites in src/render/renderer.luau
-- and drive one rotation against a presented modal. This probe drives the
-- rotation and reads the solve counters; the call-site attribution comes from
-- the temporary tag patch described in the run log.
--
-- Usage: lune run tools/lune/_probe_modal_solves

local Facet = require("../../src") :: any
local fake_target = require("../../tests/lib/fake_target")

local function body()
	local rows = {}
	for i = 1, 12 do
		table.insert(
			rows,
			Facet.UI.HStack({
				id = "R" .. i,
				width = { type = "fill", weight = 1 },
				children = {
					Facet.UI.Text({ id = "A", text = "Row " .. i }),
					Facet.UI.Spacer({ id = "S" }),
					Facet.UI.Text({ id = "B", text = "value " .. i }),
				},
			})
		)
	end
	return Facet.UI.Screen({ id = "S", children = { Facet.UI.VStack({ id = "List", children = rows }) } })
end

local function arm(mode: string, opts: any?)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 1920, h = 1080 })
	local system = Facet.newActionSystem(core)
	local pres = Facet.newPresenter(core, env, fake_target.new(), system)
	local handle
	if mode == "modal" then
		handle = pres.presentModal(body(), opts)
	else
		handle = pres.present(body(), opts)
	end
	pres.refresh()
	return core, env, pres, handle
end

local function solvesOf(handle: any): number
	return ((handle.controller.stats() :: any).solves :: number) or 0
end

-- exactly roblox_env.pushViewport()'s fact group, batched
local function rotate(env: any, w: number, h: number)
	local compact = w < 600
	env:batch(function()
		env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
		env:set("coreSafeInsets", { top = if compact then 36 else 0, bottom = 0, left = 0, right = 0 })
		env:set("deviceSafeInsets", {
			top = if compact then 44 else 0,
			bottom = if compact then 34 else 0,
			left = 0,
			right = 0,
		})
		env:set("topbarSafeInsets", { top = if compact then 36 else 0, bottom = 0, left = 0, right = 0 })
		env:set("topbarInset", { x = 0, y = 0, w = w, h = if compact then 36 else 0 })
		env:set("displaySize", "Medium")
	end)
end

local ARMS = {
	{ name = "screen (plain)", mode = "screen", opts = nil },
	{ name = "screen edgeToEdge", mode = "screen", opts = { rootPolicy = "edgeToEdge" } },
	{ name = "modal (default policy)", mode = "modal", opts = nil },
	{ name = "modal edgeToEdge", mode = "modal", opts = { rootPolicy = "edgeToEdge" } },
}

-- ...and the shape that actually costs: a LAYOUT prop bound to a memo over the
-- viewport that returns a fresh table of the same numbers (the role-pick modal's
-- two CTA sub-labels). `stable` holds px constant, so nothing about the layout
-- moved and every solve past the first is pure overhead.
local function boundArm(stable: boolean)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 1920, h = 1080 })
	local width = core:memo(function(use)
		local vp = use(env:get("viewportRect")) :: any
		return { type = "fixed", px = if stable then 120 else math.min(120, vp.w // 8) }
	end)
	local system = Facet.newActionSystem(core)
	local pres = Facet.newPresenter(core, env, fake_target.new(), system)
	local handle = pres.present(Facet.UI.Screen({
		id = "S",
		children = {
			Facet.UI.VStack({ id = "Card", children = { Facet.UI.Text({ id = "Sub", text = "x", width = width }) } }),
		},
	}))
	pres.refresh()
	local function solves(): number
		return ((handle.controller.stats() :: any).solves :: number) or 0
	end
	local out = {}
	for i = 1, 4 do
		local before = solves()
		rotate(env, 1900 + i, 1000 + i)
		pres.refresh()
		table.insert(out, tostring(solves() - before))
	end
	print(
		string.format(
			"%-24s  per-rotation: %s",
			if stable then "bound prop (stable px)" else "bound prop (moving px)",
			table.concat(out, ", ")
		)
	)
end

print("== O-20 probe: solves per BATCHED rotation ==")
for _, a in ARMS do
	local _core, env, pres, handle = arm(a.mode, a.opts)
	-- A/A control: the same measurement twice with no change between arms
	local base = solvesOf(handle)
	pres.refresh()
	local aa = solvesOf(handle) - base

	local before = solvesOf(handle)
	rotate(env, 691, 360)
	pres.refresh()
	local crossing = solvesOf(handle) - before

	before = solvesOf(handle)
	rotate(env, 1900, 1000)
	pres.refresh()
	local nonCrossing = solvesOf(handle) - before

	before = solvesOf(handle)
	rotate(env, 1901, 1001)
	pres.refresh()
	local second = solvesOf(handle) - before

	print(
		string.format(
			"%-24s  A/A=%d  crossing=%d  non-crossing=%d  repeat=%d",
			a.name,
			aa,
			crossing,
			nonCrossing,
			second
		)
	)
end
boundArm(true)
boundArm(false)
