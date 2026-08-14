--!strict
--[[
	ONE VIEWPORT CHANGE IS ONE SOLVE (docs/plans/swiftui-parity-round3.md, item E
	-- the measurement story).

	L-27 recorded "one viewport change costs 5 solves and 2 structural syncs,
	reproducibly" and left the conclusion "the lever for a resize is the solve
	COUNT, not the solve". The 2026-08-13 device capture (rr.html) put a number
	on it: arrange 8.270 ms/occurrence, measure 3.057 ms/occurrence, 9.67
	arranges per step, arrange+measure = 58.5% of wall. Five solves where one
	would do is ~45 ms of a ~200 ms frame.

	The cause is two multipliers that compound, and BOTH have to go:

	  1. `src/client/roblox_env.luau` `pushViewport()` writes SIX facts on one
	     real resize (viewportRect, coreSafeInsets, deviceSafeInsets,
	     topbarSafeInsets, topbarInset, displaySize). Unbatched, each write is
	     its own flush.
	  2. `src/render/renderer.luau` observed EIGHT geometry keys INDEPENDENTLY,
	     each callback running a full `solveAndApply()`.

	Measured on 2026-08-13 with tools/lune/_probe_solves against a 40-row tree:
	six unbatched writes + eight observers = 5 solves (L-27's number exactly).
	Batching alone = 5. One coalescing memo alone = 4. Both = 1.

	WHAT EACH BLOCK WOULD CATCH:

	  · "a batched geometry change is ONE solve" -> the regression this whole
	    entry exists to prevent: someone re-splitting the coalescing memo back
	    into per-key observers, or dropping the adapter's batch. This is the
	    only check here that fails on today's shipped code.
	  · "every geometry key still re-solves" -> the way a coalescing memo goes
	    wrong is by reading FEWER keys than it replaced, which is silent: the
	    surface simply stops responding to (say) preferredTextOffset. Each key
	    is driven individually and must still cost exactly one solve, so a
	    dropped dependency reddens as 0.
	  · "a non-geometry write does not solve" -> the opposite failure: a memo
	    that returns a fresh identity on every flush would re-solve the whole
	    surface on any unrelated environment write.
	  · "env:batch is the general mechanism" -> that the adapter's batching is
	    the core's existing transaction, not a second bespoke one.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src")
local fake_target = require("./lib/fake_target")

-- the eight facts the renderer re-solves for, and a distinct value for each
local GEOMETRY: { { key: string, a: any, b: any } } = {
	{ key = "viewportRect", a = { x = 0, y = 0, w = 900, h = 700 }, b = { x = 0, y = 0, w = 600, h = 700 } },
	{ key = "coreSafeInsets", a = { top = 0, bottom = 0, left = 0, right = 0 }, b = { top = 36, bottom = 0, left = 0, right = 0 } },
	{ key = "deviceSafeInsets", a = { top = 0, bottom = 0, left = 0, right = 0 }, b = { top = 44, bottom = 34, left = 0, right = 0 } },
	{ key = "overscanInsets", a = { top = 0, bottom = 0, left = 0, right = 0 }, b = { top = 8, bottom = 8, left = 8, right = 8 } },
	{ key = "displaySize", a = "Large", b = "Compact" },
	{ key = "preferredTextOffset", a = 0, b = 10 },
	{ key = "themeMetrics", a = nil, b = { density = 2 } },
}

local function harness(rowCount: number?)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 900, h = 700 })
	local system = LuauUI.newActionSystem(core)
	local pres = LuauUI.newPresenter(core, env, fake_target.new(), system)

	local rows = {}
	for i = 1, rowCount or 40 do
		table.insert(
			rows,
			LuauUI.UI.HStack({
				id = "R" .. i,
				width = { type = "fill", weight = 1 },
				children = {
					LuauUI.UI.Text({ id = "A", text = "Row " .. i }),
					LuauUI.UI.Spacer({ id = "S" }),
					LuauUI.UI.Text({ id = "B", text = "value " .. i }),
				},
			})
		)
	end
	local handle = pres.present(
		LuauUI.UI.Screen({ id = "S", children = { LuauUI.UI.VStack({ id = "List", children = rows }) } })
	)
	pres.refresh()

	local function solves(): number
		return ((handle.controller.stats() :: any).solves :: number) or 0
	end

	return core, env, pres, solves
end

describe("one geometry change is one solve", function()
	it("a batched geometry change is ONE solve", function()
		local _core, env, pres, solves = harness()

		-- exactly the shape of roblox_env.pushViewport(): several facts, one
		-- real resize. Unbatched + per-key observers, this measured 5.
		local before = solves()
		env:batch(function()
			env:set("viewportRect", { x = 0, y = 0, w = 360, h = 691 })
			env:set("coreSafeInsets", { top = 36, bottom = 0, left = 0, right = 0 })
			env:set("deviceSafeInsets", { top = 44, bottom = 34, left = 0, right = 0 })
			env:set("topbarSafeInsets", { top = 36, bottom = 0, left = 0, right = 0 })
			env:set("topbarInset", { x = 0, y = 0, w = 360, h = 36 })
			env:set("displaySize", "Compact")
		end)
		pres.refresh()

		expect(solves() - before).toBe(1)
	end)

	it("every geometry key still re-solves", function()
		for _, fact in GEOMETRY do
			local _core, env, pres, solves = harness(8)
			env:set(fact.key, fact.a)
			pres.refresh()

			local before = solves()
			env:set(fact.key, fact.b)
			pres.refresh()

			-- exactly one: 0 means the coalescing memo stopped reading this key
			-- and the surface is now deaf to it; >1 means it is still fanned out.
			expect(solves() - before).toBe(1)
		end
	end)

	it("a non-geometry write does not solve", function()
		local _core, env, pres, solves = harness(8)
		local before = solves()
		env:set("reducedMotion", true)
		env:set("preferredTransparency", 0.5)
		pres.refresh()
		expect(solves() - before).toBe(0)
	end)

	it("env:batch is the general mechanism", function()
		local _core, env, pres, solves = harness(8)

		-- nested batches collapse to the outermost, and the batch is the core's
		-- own transaction: a write inside is not visible to an observer until
		-- the outer one closes, so the whole group costs one solve.
		local before = solves()
		env:batch(function()
			env:set("viewportRect", { x = 0, y = 0, w = 500, h = 700 })
			env:batch(function()
				env:set("displaySize", "Compact")
			end)
			env:set("preferredTextOffset", 4)
		end)
		pres.refresh()
		expect(solves() - before).toBe(1)
	end)
end)
