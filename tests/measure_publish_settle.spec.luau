--!strict
--[[
	A MEASURE→PUBLISH CYCLE SETTLES INSIDE ONE FLUSH (optimization-log L-31;
	L-29 residual 1, priced tier 3 in
	artifacts/performance-stress-places/device-capture-2026-08-14.md).

	THE SHAPE. A surface measures its own geometry and publishes a number derived
	from it back into the environment, which invalidates the measurement. A dock
	reserving space under a HUD, a keyboard-avoidance inset, a sticky header, a
	safe-area publisher — all the same shape, and the performance lab's own
	overlay is the shipped example. Before this entry every such consumer paid:

	  * TWO reactive flushes per geometry change instead of one, because
	    `feedGeometry` ran from `presenter.refresh()` on the host's frame
	    connection, so the consumer's write could never join the flush that
	    caused it;
	  * TWO solves per surface instead of one, because a surface committed to a
	    layout in the MIDDLE of propagation — `geometryFacts`'s observer called
	    `solveAndApply()` inline — and was then invalidated by a write made later
	    in the same frame;
	  * and one PAINTED FRAME carrying the wrong number. Measured here before the
	    fix, on the 500x800 step: the content surface's root rect read 655 when
	    `env:batch` returned and 551 after the next refresh — the dock's whole
	    reservation, a frame late. That is the frame the performance lab's overlay
	    wrote `forgetReservation` to survive.

	MEASURED, headless (tools/lune/_probe_settle, 2026-08-14), two arms of the
	same scene — identical surfaces, the only difference being whether the dock
	publishes its measured height:

	  | arm             | react/step before | after | arrange/step before | after |
	  |-----------------|------------------:|------:|--------------------:|------:|
	  | no round trip   |                 1 |     1 |                   2 |     2 |
	  | measure→publish |                 2 |     1 |                   4 |     3 |

	The round trip DOUBLED both. On the real lab the same shape reproduced the
	device capture to three significant figures — 3 react, 7 arrange, 2 mount per
	`resizeStorm` step against the device's 3.03 / 7.12 / 2.00 — and now runs
	2 react, 6 arrange, 1 mount.

	WHAT THE FIX IS. `core:settle` (src/core/contract.luau) — terminal work runs
	after propagation quiesces, and a settle callback's writes re-enter the SAME
	flush and are drained before the next callback runs. The renderer's geometry
	re-solve and the presenter's geometry feed both became settle work, so the
	whole cycle converges inside one flush, before anything is committed.

	EVERY CASE HERE CARRIES ITS OWN CONTROL. The no-round-trip arm is measured in
	the same process, in the same case, and asserted EQUAL — so a future change
	that makes both arms slow passes nothing.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src")
local profile = require("../src/core/profile")
local fake_target = require("./lib/fake_target")

-- Scopes ship OFF, so a counter has to turn them on and put them back, or one
-- case leaks instrumentation into every spec that runs after it
-- (tests/profile_scopes.spec.luau established this shape).
local function withSpanCounts<T>(fn: (counts: { [string]: number }) -> T): T
	local counts: { [string]: number } = {}
	profile.resetCounters()
	profile.setEnabled(true)
	profile.setHooks(function(label: string)
		counts[label] = (counts[label] or 0) + 1
	end, function() end)
	local ok, result = pcall(fn, counts)
	profile.setHooks(nil, nil)
	profile.setEnabled(false)
	profile.resetCounters()
	if not ok then
		error(result, 0)
	end
	return result :: T
end

local SHAPES = {
	{ w = 360, h = 691 },
	{ w = 500, h = 800 },
	{ w = 390, h = 844 },
	{ w = 700, h = 600 },
}

type Scene = {
	core: any,
	env: any,
	pres: any,
	content: any,
	dock: any,
	reserved: () -> number,
	solves: () -> number,
}

--[[ The general shape, built from nothing but the public API: a CONTENT surface
	laid out inside the safe area, and a DOCK surface that measures its own panel
	and publishes that height as `coreSafeInsets.bottom`. `roundTrip=false` builds
	the identical pair with the publication removed — the control. ]]
local function scene(roundTrip: boolean): Scene
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 900, h = 700 })
	local system = LuauUI.newActionSystem(core)
	local pres = LuauUI.newPresenter(core, env, fake_target.new(), system)

	local rows = {}
	for i = 1, 24 do
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
	local content =
		pres.present(LuauUI.UI.Screen({ id = "W", children = { LuauUI.UI.VStack({ id = "List", children = rows }) } }))

	--[[ The equality guard reads the LIVE fact, never a remembered one — the
		platform adapter is the author of `coreSafeInsets` and rewrites all four
		edges on every resize, so a local cache says "already reserved" about a
		number nothing published any more. (The performance lab's overlay carried
		exactly that cache; it is gone, and its `forgetReservation` observer no
		longer has to punch a hole in one.) ]]
	local reservedBottom = 0
	local function reserveBottom(px: number)
		local want = math.max(0, math.floor(px))
		reservedBottom = want
		local live = env:get("coreSafeInsets"):get()
		local other = if type(live) == "table" then live else {}
		if (other.bottom or 0) == want then
			return
		end
		env:set("coreSafeInsets", {
			top = other.top or 0,
			bottom = want,
			left = other.left or 0,
			right = other.right or 0,
		})
	end

	local dock = pres.present(
		LuauUI.UI.Screen({
			id = "D",
			children = {
				LuauUI.UI.VStack({
					id = "Dock",
					children = {
						LuauUI.UI.Spacer({ id = "Push" }),
						LuauUI.UI.VStack({
							id = "Panel",
							-- the dock's height DEPENDS ON THE VIEWPORT, exactly as the
							-- performance lab's own panel does. This is what makes the
							-- round trip irreducible rather than a lab accident: every
							-- resize genuinely moves the number being published, so the
							-- cycle has to run and the only question is how much it costs
							height = { type = "percent", fraction = 0.34, min = 96, max = 260 },
							children = {
								LuauUI.UI.Text({ id = "T1", text = "dock line one" }),
								LuauUI.UI.Text({ id = "T2", text = "dock line two" }),
							},
						}),
					},
				}),
			},
		}),
		{
			responder = "passive",
			-- the dock owns the strip it draws in, so it is not inset by it
			rootPolicy = "edgeToEdge",
			onGeometry = if roundTrip
				then function(rectOf: (string) -> any)
					local r = rectOf("/D/Dock/Panel")
					if type(r) == "table" and type(r.h) == "number" then
						reserveBottom(r.h + 8)
					end
				end
				else nil,
		}
	)
	pres.refresh()

	return {
		core = core,
		env = env,
		pres = pres,
		content = content,
		dock = dock,
		reserved = function()
			return reservedBottom
		end,
		solves = function()
			return ((content.controller.stats() :: any).solves :: number)
				+ (dock.controller.stats() :: any).solves :: number
		end,
	}
end

-- exactly what src/client/roblox_env.luau pushViewport() writes on one real
-- resize, batched exactly as the adapter batches it
local function resize(s: Scene, shape: { w: number, h: number })
	s.env:batch(function()
		s.env:set("viewportRect", { x = 0, y = 0, w = shape.w, h = shape.h })
		s.env:set("coreSafeInsets", { top = 36, bottom = 0, left = 0, right = 0 })
		s.env:set("deviceSafeInsets", { top = 44, bottom = 34, left = 0, right = 0 })
		s.env:set("topbarSafeInsets", { top = 36, bottom = 0, left = 0, right = 0 })
		s.env:set("topbarInset", { x = 0, y = 0, w = shape.w, h = 36 })
		s.env:set("displaySize", "Medium")
	end)
end

describe("a measure→publish cycle settles inside one flush", function()
	it("the round trip costs NO extra reactive flush — the control is in the case", function()
		withSpanCounts(function(counts)
			local plain = scene(false)
			local before = counts["LuauUI/react"] or 0
			for _, shape in SHAPES do
				resize(plain, shape)
				plain.pres.refresh()
			end
			local plainReact = (counts["LuauUI/react"] or 0) - before

			local loop = scene(true)
			before = counts["LuauUI/react"] or 0
			for _, shape in SHAPES do
				resize(loop, shape)
				loop.pres.refresh()
			end
			local loopReact = (counts["LuauUI/react"] or 0) - before

			-- the control first, so a scene that stopped flushing at all cannot
			-- pass by making both numbers zero
			expect(plainReact).toBe(#SHAPES)
			-- measured 2x this before the settle phase (8 against 4)
			expect(loopReact).toBe(plainReact)
		end)
	end)

	it("the round trip costs ONE extra solve, not one per surface per round trip", function()
		--[[ THE BOUND, stated as what the data dependency actually costs.

			The dock's height depends on the viewport, so a resize genuinely moves
			the number it publishes and the cycle cannot be coalesced away: the
			CONSUMER must solve once against the pre-publication environment and
			once against the settled one. That is 3 solves for two surfaces —

			  1. content solves (the resize)
			  2. dock solves, measures itself, publishes
			  3. content re-solves against the published value

			— and the dock does NOT re-solve for its own publication, because an
			`edgeToEdge` surface is defined not to consume a safe-area inset and
			its geometry memo no longer claims to.

			Before the settle phase this was FOUR, in TWO flushes: the pre-fix
			dock re-solved for the inset it ignores, and the whole second
			generation happened a frame later.

			The ceiling matters more than the number. What must never come back is
			the shape where every round trip re-solves EVERY mounted surface, which
			is 2 x surfaces x generations and scales with how many surfaces are
			presented. ]]
		withSpanCounts(function(counts)
			local plain = scene(false)
			local p0, pa0 = plain.solves(), counts["LuauUI/arrange"] or 0
			for _, shape in SHAPES do
				resize(plain, shape)
				plain.pres.refresh()
			end
			local plainSolves = plain.solves() - p0
			local plainArrange = (counts["LuauUI/arrange"] or 0) - pa0

			local loop = scene(true)
			local l0, la0 = loop.solves(), counts["LuauUI/arrange"] or 0
			for _, shape in SHAPES do
				resize(loop, shape)
				loop.pres.refresh()
			end
			local loopSolves = loop.solves() - l0
			local loopArrange = (counts["LuauUI/arrange"] or 0) - la0

			-- the control: two surfaces, one solve each per geometry change
			expect(plainSolves).toBe(#SHAPES * 2)
			expect(plainArrange).toBe(plainSolves)
			-- ...and the round trip adds exactly ONE, measured 2x before (16 vs 12)
			expect(loopSolves).toBe(#SHAPES * 3)
			expect(loopArrange).toBe(loopSolves)
		end)
	end)

	it("a surface is FINAL when the geometry change returns — no correction a frame later", function()
		--[[ THE CORRECTNESS CASE, and the one that matters more than either
			counter. Before the settle phase the content surface solved against a
			reservation the dock had not republished yet, so `env:batch` returned
			with a rect that the NEXT refresh moved by the dock's height — a
			painted frame carrying a number nothing had settled. Measured then:
			655 → 607, 764 → 716, 808 → 760, 564 → 516, i.e. every step wrong by
			the 48px reservation. ]]
		local loop = scene(true)
		for _, shape in SHAPES do
			resize(loop, shape)
			local onReturn = loop.content.controller.rectOf("/W")
			loop.pres.refresh()
			local nextFrame = loop.content.controller.rectOf("/W")
			expect(type(onReturn)).toBe("table")
			expect((onReturn :: any).h).toBe((nextFrame :: any).h)
		end
		expect(loop.core:lastError()).toBeNil()
	end)

	it("...and the published reservation is REALLY applied — the fix is not 'never publish'", function()
		--[[ The negative control for the case above: making `onGeometry` a no-op
			would satisfy "no correction a frame later" perfectly and silently
			delete the feature. The reservation must be non-zero AND the content
			surface must be shorter than the dock surface by exactly it. ]]
		local loop = scene(true)
		resize(loop, { w = 500, h = 800 })
		loop.pres.refresh()
		expect(loop.reserved() > 0).toBe(true)
		local content = loop.content.controller.rectOf("/W") :: any
		local dockRect = loop.dock.controller.rectOf("/D") :: any
		-- the dock is edgeToEdge (full viewport); the content is inset by the
		-- topbar above and the published reservation below
		expect(dockRect.h - content.h).toBe(36 + loop.reserved())
	end)

	it("a geometry fact written by a LATE observer costs ONE solve, not two", function()
		--[[ THE RENDERER'S HALF OF L-31, and the case that discriminates it.

			Moving the re-solve out of the geometry OBSERVER and into the settle
			phase says one thing: every observer in the flush is heard before any
			surface commits to a layout. Nothing above could see that, because the
			shipped consumers all happen to sit on nodes created EARLY — `viewportRect`
			is one of the first signals an environment makes, so an observer on it
			is notified before any surface's geometry memo and its write is absorbed
			for free. Restoring the inline solve passed every other case here.

			An observer registered LATER is the unlucky half of the same coin, and
			it is not exotic: it is any app that reacts to an environment change by
			publishing a derived environment fact from a signal it created after its
			screens were presented — a theme tick, a layout mode, an accessibility
			preference fanning out to a safe-area inset. Notified AFTER the geometry
			memos, its write used to arrive one round too late and cost the consuming
			surface a second full solve.

			Measured on this scene: 3 solves inline (content twice, dock once), 2
			with the settle phase. ]]
		local s = scene(false)
		-- created after both surfaces are presented, so its observer is notified
		-- after their geometry memos (observers fire in node CREATION order)
		local late = s.core:signal(0)
		s.core:observe(late, function(v: number)
			s.env:set("coreSafeInsets", { top = 0, bottom = v, left = 0, right = 0 })
		end)

		local before = s.solves()
		s.env:batch(function()
			s.env:set("viewportRect", { x = 0, y = 0, w = 500, h = 800 })
			late:set(24)
		end)
		s.pres.refresh()

		-- content solves once (against the settled inset), dock once. Inline this
		-- was 3: the content surface solved before the late observer was heard and
		-- again afterwards.
		expect(s.solves() - before).toBe(2)
		-- ...and the inset really landed, so "never write" cannot pass this either
		expect((s.env:get("coreSafeInsets"):get() :: any).bottom).toBe(24)
		expect(s.core:lastError()).toBeNil()
	end)

	it("a round trip that will not converge is a LOUD error, not a hang or a silent frame", function()
		--[[ The property FEEDBACK_ROUND_CAP already gave the flush must survive
			the settle phase. A settle callback that publishes a NEW value every
			pass is a non-convergent measure→publish cycle — the runaway shape a
			real consumer reaches by publishing a value derived from a rect that
			its own publication moves. It must terminate, and it must say so. ]]
		local core = LuauUI.newCore()
		local sig = core:signal(0)
		local passes = 0
		core:settle(function()
			passes += 1
			sig:set(passes)
		end)
		sig:set(-1)
		expect(passes > 1).toBe(true)
		-- bounded: nowhere near unbounded, and the flush RETURNED
		expect(passes < 200).toBe(true)
		local err = core:lastError()
		expect(type(err)).toBe("string")
		expect(string.find(tostring(err), "iteration cap") ~= nil).toBe(true)
	end)
end)
