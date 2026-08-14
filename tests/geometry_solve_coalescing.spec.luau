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
	{
		key = "coreSafeInsets",
		a = { top = 0, bottom = 0, left = 0, right = 0 },
		b = { top = 36, bottom = 0, left = 0, right = 0 },
	},
	{
		key = "deviceSafeInsets",
		a = { top = 0, bottom = 0, left = 0, right = 0 },
		b = { top = 44, bottom = 34, left = 0, right = 0 },
	},
	{
		key = "overscanInsets",
		a = { top = 0, bottom = 0, left = 0, right = 0 },
		b = { top = 8, bottom = 8, left = 8, right = 8 },
	},
	-- Small|Medium|Large; `Large` is the TV class, so drive Medium->Small to
	-- exercise the key without flipping the surface into a ten-foot layout
	{ key = "displaySize", a = "Medium", b = "Small" },
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
	local handle =
		pres.present(LuauUI.UI.Screen({ id = "S", children = { LuauUI.UI.VStack({ id = "List", children = rows }) } }))
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
			-- displaySize is Small|Medium|Large, NOT the size class, and `Large`
			-- alone means TELEVISION (typographyScale 1.5, ten-foot, overscan).
			-- The adapter publishes it on every pushViewport; a rotation does not
			-- change it. Held constant so this measures batching, not a TV swap.
			env:set("displaySize", "Medium")
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

	it("a set-and-revert inside one batch costs NOTHING", function()
		--[[ RED-TEAM 2026-08-13. The first cut of the coalescing memo returned a
			fresh `{}` per recompute, so identity-inequality meant "recomputed",
			not "changed". That discarded both guarantees `src/core/custom.luau`
			states in its own header — "set-and-revert transactions and unchanged
			recomputes [are] fire-free" — and it discarded them in the exact
			dimension this whole entry exists to reduce. Measured then: 1 solve
			where there had been 0. ]]
		local _core, env, pres, solves = harness(8)
		local before = solves()
		env:batch(function()
			env:set("viewportRect", { x = 0, y = 0, w = 500, h = 700 })
			env:set("viewportRect", { x = 0, y = 0, w = 900, h = 700 }) -- back where it started
		end)
		pres.refresh()
		expect(solves() - before).toBe(0)
	end)

	it("a write that moves NO geometry value costs nothing", function()
		-- `typographyScale` is a memo over displaySize + preferredTextOffset and
		-- clamps: two different preferredTextSize values can produce the SAME
		-- scale. Recomputed-but-unchanged must not re-solve the surface.
		local _core, env, pres, solves = harness(8)
		env:set("preferredTextSize", 4)
		pres.refresh()
		local before = solves()
		env:set("preferredTextSize", 9)
		pres.refresh()
		expect(solves() - before).toBe(0)
	end)

	it("re-publishing the SAME numbers in a fresh table costs nothing", function()
		--[[ THE REAL-WORLD CASE, and the reason the memo compares by content.
			`roblox_env.pushViewport()` builds a BRAND NEW rect and inset tables
			every time it runs, and it runs on `TopbarInset` changes as well as on
			resizes. Under table-identity comparison, a topbar change alone
			re-solved the whole surface for a viewport that had not moved. ]]
		local _core, env, pres, solves = harness(8)
		local before = solves()
		for _ = 1, 3 do
			env:batch(function()
				env:set("viewportRect", { x = 0, y = 0, w = 900, h = 700 }) -- identical numbers
				env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
				env:set("deviceSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
			end)
			pres.refresh()
		end
		expect(solves() - before).toBe(0)
	end)

	it("consumers on SEPARATE memos are notified in creation order", function()
		--[[ RED-TEAM 2026-08-13. Coalescing moved each surface's solve observer off
			the shared env signal onto its OWN memo. `notify` sorts observers by seq
			WITHIN one node, which gave a total order only while every consumer
			observed the same signal; `flushBody` builds its queue by iterating
			tables keyed by node REFERENCES, and hash order is not an order. Measured
			solve order across six surfaces varying run to run within one process.

			A FIRST CUT OF THIS CASE PROVED NOTHING. It presented six surfaces and
			compared their `onGeometry` order across three runs — and passed with the
			sort REMOVED, because six small surfaces happened to hash stably. Twelve
			memos do not: without the sort this reads `4,10,6,9,8,12,11,7,3,2,5,1`,
			then `1,11,7,2,6,3,5,9,12,10,4,8`, then `4,11,1,9,7,3,2,12,6,8,5,10`.
			That is the shape a determinism check has to have — seen to fail. ]]
		local core = LuauUI.newCore()
		local sig = core:signal(0)
		local order: { number } = {}
		for i = 1, 12 do
			local m = core:memo(function(use)
				return use(sig) + i
			end)
			core:observe(m, function()
				table.insert(order, i)
			end)
		end
		sig:set(1)

		local expected = {}
		for i = 1, 12 do
			table.insert(expected, tostring(i))
		end
		expect(table.concat(order, ",")).toBe(table.concat(expected, ","))
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
				env:set("displaySize", "Small")
			end)
			env:set("preferredTextOffset", 4)
		end)
		pres.refresh()
		expect(solves() - before).toBe(1)
	end)
end)
