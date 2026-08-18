--!strict
--[[ ELISION MUST DISCLOSE, NOT DELETE (navigation-and-menus D7).

	ADAPTATION MAY CHANGE HOW MUCH OF SOMETHING IS SHOWN, AND WHAT IT COSTS TO
	REACH IT. IT MAY NOT CHANGE WHETHER IT CAN BE REACHED AT ALL.

	The rank ladder (ADR-0025) was never missing and never broken: it steps a region
	down to a poorer form and then drops it, in descending rank, exactly as
	declared. What it had no vocabulary for was WHERE the content the poorer form
	stopped showing went — so from the player's side "step down" and "delete" were
	the same operation. Frozen live before this file existed
	(artifacts/navigation-and-menus/d7-hud-baseline.md, Studio 0.734, 749x380): with
	a browser URL bar open, all three Beginner tasks and their rewards, the
	`Tasks 1/3` chip, the health figure, the kill feed and the whole weapon rail
	were `Visible = false` with no recovery route of any kind — and so was the `...`
	button that might have hosted one.

	The four things this file pins, in order:

	  1. THE CONTRACT. `recover` is a closed spec on `UI.Region`, REQUIRED on a
	     region with more than one form and REFUSED on a region with one. "none"
	     has to be written; silence is not consent.
	  2. THE SEAM. `RegionResolution.elided` beside `dropped`, and
	     `Resolution.unshown` — the list an overflow surface is populated from, so
	     no consumer re-derives elision by hand.
	  3. THE TERMINAL FORM. A `recover = "self"` route whose reduced form contains
	     nothing focusable is an authoring error at construction. A route nobody can
	     reach is the defect wearing the fix's clothes.
	  4. THE SWEEP (D7.6). At every swept viewport, in both URL-bar states, every
	     region the HUD has stopped showing has a LIVE route: the sink is mounted
	     and visible, or the region is standing with something focusable in it.
	     Mechanical, cheap, and the only one of these that keeps the defect out.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local composition = require("../src/layout/composition")
local UI = require("../src/blueprint")
local Facet = require("../src") :: any
local fake_target = require("./lib/fake_target")
local deviceViews = require("./lib/device_views")
local hudScenario = require("../examples/gallery/scenarios/hud")

-- ===== 1. the contract =====================================================

local function decl(regions: { any }): any
	return {
		groups = { { id = "body", lane = "main" } },
		arrangements = { { name = "one", lanes = { { "main" } } } },
		regions = regions,
	}
end

local function normalizeErr(regions: { any }): string
	local ok, err = pcall(composition.normalize, decl(regions))
	expect(ok).toBe(false)
	return tostring(err)
end

describe("D7.1 — a region states where the content a reduced form stops showing went", function()
	it("REQUIRES `recover` on a region with more than one form, and names it", function()
		local err = normalizeErr({ { id = "Panel", group = "body", rank = 1, forms = 2 } })
		expect(string.find(err, "region 'Panel' declares 2 forms but no 'recover'", 1, true) ~= nil).toBe(true)
		-- the message states the whole principle, because the author reading it is
		-- the person deciding which of the three answers is true
		expect(string.find(err, "it may not change whether it can be reached at all", 1, true) ~= nil).toBe(true)
	end)

	it("...and a THREE-form region is refused the same way — it is not a two-form rule", function()
		local err = normalizeErr({ { id = "Ladder", group = "body", rank = 1, forms = 3 } })
		expect(string.find(err, "region 'Ladder' declares 3 forms but no 'recover'", 1, true) ~= nil).toBe(true)
	end)

	--[[ THE MIRROR RULE LIVES AT THE BLUEPRINT BOUNDARY, and that placement is a
		measurement rather than a preference. `forms` reaching the solver is the count
		of MOUNTED forms, and a form behind a `UI.When` is absent while its condition
		reads false — the composition showcase declares two `When` forms per region
		and solves with one of them for most of its states. Refusing `recover` inside
		the pure normalizer therefore rejected a good declaration on the frame a
		condition flipped (measured: three regions of `scenarios/composition`). Here
		the count is the DECLARED one, which is what the rule is about. ]]
	it("REFUSES `recover` on a one-form region: there is nothing there to choose", function()
		local ok, err = pcall(UI.Region, {
			id = "Solo",
			group = "body",
			rank = 1,
			recover = "overflow",
			children = { UI.Text({ id = "T", text = "one form" }) },
		})
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "UI.Region 'Solo' declares one form", 1, true) ~= nil).toBe(true)
		-- ...and the reason, so the author does not read it as an arbitrary rule: a
		-- one-form region can only lose content by being DROPPED, and a dropped
		-- region has no form left to be its own route
		expect(string.find(tostring(err), "has no form left to be its own route", 1, true) ~= nil).toBe(true)
	end)

	it("...and the pure normalizer does NOT, because a `When`-gated form comes and goes", function()
		-- one MOUNTED form on this solve, `recover` declared: legal, because the
		-- declaration said two and only one of them is currently conditioned in
		local ok = pcall(
			composition.normalize,
			decl({
				{ id = "Gated", group = "body", rank = 1, forms = 1, recover = "overflow" },
			})
		)
		expect(ok).toBe(true)
	end)

	it("refuses an unknown route — a closed spec, never a silent no-op", function()
		local err = normalizeErr({ { id = "Panel", group = "body", rank = 1, forms = 2, recover = "later" } })
		expect(string.find(err, `recover must be "none" | "self" | "overflow", got 'later'`, 1, true) ~= nil).toBe(true)
	end)

	it('refuses "none" together with mayDrop — dropping shows NOTHING', function()
		local err = normalizeErr({
			{ id = "Panel", group = "body", rank = 1, forms = 2, recover = "none", mayDrop = true },
		})
		expect(string.find(err, "dropping shows NOTHING", 1, true) ~= nil).toBe(true)
	end)

	it("accepts all three routes, and carries the declared one through normalize", function()
		local d = composition.normalize(decl({
			{ id = "A", group = "body", rank = 1, forms = 2, recover = "none" },
			{ id = "B", group = "body", rank = 2, forms = 2, recover = "self" },
			{ id = "C", group = "body", rank = 3, forms = 2, recover = "overflow", mayDrop = true },
			{ id = "D", group = "body", rank = 4, forms = 1 },
		}))
		local got = {}
		for _, r in d.regions do
			table.insert(got, `{r.id}={tostring((r :: any).recover)}`)
		end
		expect(table.concat(got, " ")).toBe("A=none B=self C=overflow D=nil")
	end)
end)

-- ===== 2. the seam =========================================================

local SIZES: { [string]: { { w: number, h: number } } } = {
	A = { { w = 100, h = 120 }, { w = 100, h = 40 } },
	B = { { w = 100, h = 120 }, { w = 100, h = 40 } },
	C = { { w = 100, h = 120 }, { w = 100, h = 40 } },
	D = { { w = 100, h = 60 } },
}

local function measureFn(id: string, form: number, _w: number, _h: number): (number, number)
	local list = SIZES[id]
	local s = list[math.min(form, #list)]
	return s.w, s.h
end

local SEAM = decl({
	{ id = "A", group = "body", rank = 5, forms = 2, recover = "none" },
	{ id = "B", group = "body", rank = 6, forms = 2, recover = "self" },
	{ id = "C", group = "body", rank = 7, forms = 2, recover = "overflow", mayDrop = true },
	{ id = "D", group = "body", rank = 8, forms = 1, mayDrop = true },
})

local function solve(h: number): any
	return composition.resolve(SEAM, { w = 200, h = h }, { measure = measureFn })
end

local function ids(list: { any }): string
	local out = {}
	for _, u in list do
		table.insert(out, `{u.id}:{u.reason}->{u.route}`)
	end
	return table.concat(out, ", ")
end

describe("D7.1 — `elided` beside `dropped`, and the list an overflow surface reads", function()
	it("with room, nothing is elided and the list is EMPTY — that is what makes it additive", function()
		local r = solve(500)
		expect(#r.unshown).toBe(0)
		for _, res in r.regions do
			expect(`{res.id} elided={tostring(res.elided)} dropped={tostring(res.dropped)}`).toBe(
				`{res.id} elided=false dropped=false`
			)
		end
	end)

	it("a stepped-down region reports `elided`, and `dropped` stays false", function()
		-- 420 of need against 340: the two lowest-ranked step down
		local r = solve(340)
		local d = r.regionById
		expect(`C elided={tostring(d.C.elided)} form={d.C.form}`).toBe("C elided=true form=2")
		expect(d.C.dropped).toBe(false)
	end)

	--[[ 100, AND THE HEIGHT IS THE POINT. At 150 the only dropped region is `D`,
		which has ONE form — so `elided = false` there is arithmetic rather than a
		decision, and a mutation that set `elided = form > 1` on a dropped region
		passed (measured, mutation ledger M6). At 100 the ladder has stepped `C` DOWN
		and then dropped it, so it is a dropped region whose form index really is 2:
		the only state in which the two flags can disagree. ]]
	it("a DROPPED region is `elided = false`: it is showing nothing, not showing less", function()
		local r = solve(100)
		expect(`C stepped before it was dropped: form {r.regionById.C.form}`).toBe(
			"C stepped before it was dropped: form 2"
		)
		local dropped = {}
		for _, res in r.regions do
			if res.dropped then
				table.insert(dropped, res.id)
				expect(`{res.id} elided while dropped: {tostring(res.elided)}`).toBe(
					`{res.id} elided while dropped: false`
				)
			end
		end
		expect(#dropped > 0).toBe(true)
	end)

	--[[ 200, AND THE HEIGHT IS THE POINT. At 300 the ladder has only reached B and
		C, so `A` is not elided at all and "A is absent from the list" is true for the
		wrong reason — a mutation that listed every elided region regardless of its
		route passed (measured, mutation ledger M8). At 200 all THREE have stepped
		down, so A's absence is the `recover = "none"` rule doing work. ]]
	it('the unshown list OMITS a `recover = "none"` region and KEEPS the other two', function()
		local r = solve(200)
		expect(`A really did step down: elided={tostring(r.regionById.A.elided)}`).toBe(
			"A really did step down: elided=true"
		)
		-- ...and it is still absent: its poorer form shows everything, so nothing is
		-- missing and there is nothing for an overflow surface to disclose
		for _, u in r.unshown do
			expect(u.id ~= "A").toBe(true)
		end
		expect(ids(r.unshown)).toBe("B:elided->self, C:elided->overflow")
	end)

	it("a dropped region's route is ALWAYS overflow, whatever its `recover` said", function()
		local r = solve(100)
		for _, u in r.unshown do
			if u.reason == "dropped" then
				expect(`{u.id} route={u.route}`).toBe(`{u.id} route=overflow`)
			end
		end
		-- D declares no `recover` at all (one form) and is still listed when dropped:
		-- `mayDrop` has always implied "moves to the sink" and now states it
		local sawD = false
		for _, u in r.unshown do
			sawD = sawD or u.id == "D"
		end
		expect(sawD).toBe(true)
	end)

	it("the list is in DECLARATION order, so it reads with `regions` and never hash order", function()
		local r = solve(100)
		local order = {}
		for _, u in r.unshown do
			table.insert(order, u.id)
		end
		local declOrder = {}
		for _, res in r.regions do
			for _, u in r.unshown do
				if u.id == res.id then
					table.insert(declOrder, res.id)
				end
			end
		end
		expect(table.concat(order, ",")).toBe(table.concat(declOrder, ","))
	end)

	it("the dump carries both, and two calls are equal", function()
		local r = solve(300)
		local a, b = composition.dump(r), composition.dump(r)
		expect(#a.unshown).toBe(#b.unshown)
		for i, u in a.unshown do
			expect(`{u.id}:{u.reason}:{u.route}`).toBe(`{b.unshown[i].id}:{b.unshown[i].reason}:{b.unshown[i].route}`)
		end
		local byId: { [string]: any } = {}
		for _, entry in a.regions do
			byId[entry.id] = entry
		end
		expect(byId.C.elided).toBe(true)
		-- A never stepped: `elided` is the SOLVE's answer, not the declaration's
		expect(byId.A.elided).toBe(false)
		-- ADDITIVE: a reader that never heard of elision still reads `false`, never nil
		expect(byId.D.elided).toBe(false)
	end)
end)

-- ===== 3. a terminal form must be actionable ===============================

local function regionErr(spec: any): string
	local ok, err = pcall(UI.Region, spec)
	expect(ok).toBe(false)
	return tostring(err)
end

--[[ WAVE REVEAL MOVED THE POLARITY OF THIS RULE, and the two describes below are
	the same set of declarations read the other way round. D7.2 made a focusable in
	every reduced form MANDATORY under `recover = "self"`, because "the reduced form
	IS the route" was a promise only the author could keep. The framework now keeps
	it: `UI.Region` synthesizes one expand affordance for a collapsing region, it is
	a Button, and it stands exactly while a reduced form stands. So the refusal is
	now scoped to the ONE declaration that leaves nobody supplying a route —
	`expand = "none"` — and the same trees that used to be refused are accepted, by
	the framework doing the work instead. ]]
describe("D7.2 — a `self` route with no route left in it is still an authoring error", function()
	it('refuses a LAST form with nothing focusable in it — under expand = "none"', function()
		local err = regionErr({
			id = "Tasks",
			group = "body",
			rank = 8,
			recover = "self",
			expand = "none",
			children = {
				UI.VStack({ id = "Full", children = { UI.Text({ id = "T1", text = "everything" }) } }),
				UI.HStack({ id = "Chip", children = { UI.Text({ id = "T2", text = "Tasks 1/3" }) } }),
			},
		})
		expect(string.find(err, "UI.Region 'Tasks' declares recover = \"self\"", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "form 2 of 2", 1, true) ~= nil).toBe(true)
	end)

	it("...and a MIDDLE form too — the ladder can stop at any rung", function()
		local err = regionErr({
			id = "Tasks",
			group = "body",
			rank = 8,
			recover = "self",
			expand = "none",
			children = {
				UI.VStack({ id = "Full", children = { UI.Text({ id = "T1", text = "everything" }) } }),
				UI.VStack({ id = "One", children = { UI.Text({ id = "T2", text = "one task" }) } }),
				UI.HStack({ id = "Chip", children = { UI.Button({ id = "B", label = "Tasks 1/3" }) } }),
			},
		})
		expect(string.find(err, "form 2 of 3", 1, true) ~= nil).toBe(true)
	end)

	it("...and accepts every one of them once the framework is supplying the route", function()
		-- the SAME declaration as the two above, with the default expand: what used
		-- to be an authoring error is now a region with an affordance in it
		local ok = pcall(UI.Region, {
			id = "Tasks",
			group = "body",
			rank = 8,
			recover = "self",
			children = {
				UI.VStack({ id = "Full", children = { UI.Text({ id = "T1", text = "everything" }) } }),
				UI.HStack({ id = "Chip", children = { UI.Text({ id = "T2", text = "Tasks 1/3" }) } }),
			},
		})
		expect(ok).toBe(true)
	end)

	it("accepts a form whose focusable is NESTED — the walk is the whole subtree", function()
		local ok = pcall(UI.Region, {
			id = "Tasks",
			group = "body",
			rank = 8,
			recover = "self",
			expand = "none",
			children = {
				UI.VStack({ id = "Full", children = { UI.Text({ id = "T1", text = "everything" }) } }),
				UI.VStack({
					id = "Chip",
					children = { UI.HStack({ id = "Row", children = { UI.Button({ id = "B", label = "open" }) } }) },
				}),
			},
		})
		expect(ok).toBe(true)
	end)

	it('asks NOTHING of an "overflow" or "none" route — the sink is what carries those', function()
		for _, route in { "overflow", "none" } do
			local ok = pcall(UI.Region, {
				id = "Zone",
				group = "body",
				rank = 4,
				recover = route,
				children = {
					UI.VStack({ id = "Full", children = { UI.Text({ id = "T1", text = "everything" }) } }),
					UI.VStack({ id = "Less", children = { UI.Text({ id = "T2", text = "less" }) } }),
				},
			})
			expect(`{route} accepted: {ok}`).toBe(`{route} accepted: true`)
		end
	end)

	it("...and the RICHEST form is exempt: it is not showing less than anything", function()
		local ok = pcall(UI.Region, {
			id = "Zone",
			group = "body",
			rank = 4,
			recover = "self",
			children = {
				-- form 1 holds no focusable at all and that is fine
				UI.VStack({ id = "Full", children = { UI.Text({ id = "T1", text = "everything" }) } }),
				UI.VStack({ id = "Chip", children = { UI.Button({ id = "B", label = "open" }) } }),
			},
		})
		expect(ok).toBe(true)
	end)
end)

-- ===== 4. the sweep (D7.6) =================================================

local CORE_TOP = deviceViews.CORE_TOP
-- the showcase's own chip strip, the same reservation the always-on sweeps make:
-- every one of these surfaces is reached through the demo picker, and a sweep
-- against the bare viewport measures a screen no player ever sees
local PICKER_STRIP = 62
local SINK_PATH = "/HudScreen/Hud/Rounds/RoundStrip/R3"

local function drive(view: any): any
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	env:set("coreSafeInsets", { top = CORE_TOP + PICKER_STRIP, bottom = 0, left = 0, right = 0 })
	env:set("deviceSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	env:set("topbarSafeInsets", { top = 0, bottom = math.max(0, view.h - CORE_TOP), left = 164, right = 0 })
	env:set("topbarInset", { x = 164, y = 0, w = math.max(0, view.w - 164), h = CORE_TOP })
	env:set(
		"appChromeRects",
		{ { x = 8, y = CORE_TOP, w = math.max(1, math.min(259, view.w - 16)), h = PICKER_STRIP } }
	)
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local presenter = Facet.newPresenter(core, env, adapter, system)
	local handle: any = nil
	local built = hudScenario.build({
		Facet = Facet,
		core = core,
		env = env,
		adapter = adapter,
		presenter = presenter,
		actionSystem = system,
		record = function() end,
		-- the runner's own accessor, so the fixture reads the SAME dump Studio does
		composition = function(path: string?): any
			return if handle == nil then nil else handle.controller.compositionAt(path)
		end,
	})
	handle = presenter.present(built.screen, built.present)
	presenter.refresh()
	return {
		env = env,
		adapter = adapter,
		built = built,
		handle = handle,
		refresh = function()
			presenter.refresh()
		end,
		dispose = function()
			built.dispose()
			presenter.dismiss(handle)
		end,
	}
end

--[[ WHAT COUNTS AS A LIVE ROUTE. Two answers, one per route, and neither of them
	is "the declaration says so":
	  * "overflow" — the sink node is MOUNTED AND VISIBLE at this viewport. Not
	    declared, not present-in-the-tree: `visibleOf`, because a dropped region
	    keeps its mount and the adapter writes `Visible = false` down the subtree,
	    so "the node exists" is exactly the check that would have passed on the
	    broken fixture (its `...` was a real node at 36x36, invisible).
	  * "self" — the region is standing and something focusable is inside it. ]]
local function assertRouted(w: any, where: string): number
	local dump = w.handle.controller.compositionAt("/HudScreen/Hud")
	if dump == nil then
		error(`{where}: the HUD published NO composition dump — this check would prove nothing`, 0)
	end
	local sinkVisible = w.adapter.visibleOf(SINK_PATH) == true
	for _, u in dump.unshown do
		if u.route == "overflow" then
			if not sinkVisible then
				error(
					`{where}: '{u.id}' is {u.reason} and its route is the overflow sink, but the sink `
						.. `('{SINK_PATH}') is not visible — the content is unreachable here`,
					0
				)
			end
		else
			local res = dump.regionById and dump.regionById[u.id]
			local mounted = false
			for _, r in dump.regions do
				if r.id == u.id then
					mounted = r.mounted and not r.dropped
				end
			end
			if not mounted then
				error(`{where}: '{u.id}' claims a "self" route but is not standing ({tostring(res)})`, 0)
			end
			local focusable = false
			for _, path in w.adapter.paths() do
				if string.sub(path, 1, #u.id + 1) ~= u.id .. "/" then
					continue
				end
				local node = w.adapter.node(path)
				if
					node ~= nil
					and (node.class == "Button" or node.class == "Toggle" or node.class == "TextField")
					and w.adapter.visibleOf(path) == true
				then
					focusable = true
					break
				end
			end
			if not focusable then
				error(
					`{where}: '{u.id}' claims a "self" route, so the form it is standing in is the route — `
						.. "but nothing focusable in it is VISIBLE",
					0
				)
			end
		end
	end
	return #dump.unshown
end

describe("D7.6 — every elided or dropped region has a live recovery route, at every viewport", function()
	it("sweeps the device matrix in both URL-bar states", function()
		local total = 0
		local sawDrop, sawElide = false, false
		for _, view in deviceViews.VIEWS do
			local w = drive(view)
			for _, state in { "closed", "open" } do
				if state == "open" then
					w.built.steps.openUrlBar()
					w.refresh()
				end
				local n = assertRouted(w, `{view.id} {view.w}x{view.h} (url {state})`)
				total += n
				local dump = w.handle.controller.compositionAt("/HudScreen/Hud")
				for _, u in dump.unshown do
					sawDrop = sawDrop or u.reason == "dropped"
					sawElide = sawElide or u.reason == "elided"
				end
				-- ...and adaptation never fell back or collided while doing it
				expect(`{view.id} {state} fallback={tostring(dump.fallback)}`).toBe(`{view.id} {state} fallback=false`)
				expect(`{view.id} {state} collisions={#dump.collisions}`).toBe(`{view.id} {state} collisions=0`)
			end
			w.dispose()
		end
		--[[ THE FLOOR, so a check that proves nothing can never pass. Measured
			immediately before the repair (the same sweep over the same nine viewports
			and two states): 39 elided-or-dropped occurrences, every one of them a dead
			end. If this number collapses toward zero the HUD has stopped adapting, and
			a sweep that finds nothing to route is not evidence that routing works. ]]
		expect(`elided-or-dropped occurrences swept: {total >= 20}`).toBe("elided-or-dropped occurrences swept: true")
		expect(`saw a DROP: {sawDrop}`).toBe("saw a DROP: true")
		expect(`saw an ELISION: {sawElide}`).toBe("saw an ELISION: true")
	end)

	--[[ FINDING 1 FROM THE BASELINE, CLOSED. The `...` used to live in
		`RoundColumn` — a FORM of a two-form region — and that form was never chosen
		at any swept viewport, so the one affordance that recovers everything else was
		`Visible = false` everywhere. The host is now structurally undroppable, and
		this is the structure rather than the symptom. ]]
	it("the sink's host cannot elide and cannot drop, by construction", function()
		local w = drive({ id = "probe", w = 749, h = 380 })
		local dump = w.handle.controller.compositionAt("/HudScreen/Hud")
		local rounds: any = nil
		for _, r in dump.regions do
			if string.match(r.id, "([^/]+)$") == "Rounds" then
				rounds = r
			end
		end
		expect(rounds ~= nil).toBe(true)
		-- ONE form: `recover` is refused on it, so it has no ladder to lose a rung on
		expect(`Rounds form={rounds.form} elided={tostring(rounds.elided)}`).toBe("Rounds form=1 elided=false")
		expect(rounds.dropped).toBe(false)
		expect(rounds.rank).toBe(1)
		w.dispose()
	end)

	it("...and declaring a second form on it is refused, because `recover` would then be required", function()
		local ok, err = pcall(UI.Region, {
			id = "Rounds",
			group = "topLeft",
			rank = 1,
			children = {
				UI.HStack({ id = "Strip", children = { UI.Button({ id = "R1", label = "menu" }) } }),
				UI.HStack({ id = "Column", children = { UI.Button({ id = "R1c", label = "menu" }) } }),
			},
		})
		-- the Region itself builds; the refusal is the composition's, where the
		-- form count is known to the normalizer
		expect(ok).toBe(true)
		local built = err :: any
		local ok2, err2 = pcall(UI.Composition, {
			id = "Hud",
			groups = Facet.composition.HUD_GROUPS,
			arrangements = { Facet.composition.HUD },
			children = { built },
		})
		expect(ok2).toBe(false)
		expect(string.find(tostring(err2), "declares 2 forms but no 'recover'", 1, true) ~= nil).toBe(true)
	end)
end)

-- ===== 5. the fixture's own repairs ========================================

describe("D7 — the HUD showcase discloses what it stops showing", function()
	it("the sink OPENS and lists the content the screen is not showing", function()
		-- 640x320 with the bar open: the state the baseline caught, where Tasks and
		-- the feed are gone entirely
		local w = drive({ id = "narrow-landscape", w = 640, h = 320 })
		w.built.steps.openUrlBar()
		w.refresh()
		local opened = w.built.steps.openOverflow()
		w.refresh()
		expect(opened.open).toBe(true)
		expect(#opened.hidden > 0).toBe(true)
		-- the panel really mounted, and the strings the HUD stopped showing are ON it
		local seen: { [string]: boolean } = {}
		for _, path in w.adapter.paths() do
			local node = w.adapter.node(path)
			if node ~= nil and node.class == "Text" and node.props ~= nil and type(node.props.text) == "string" then
				seen[node.props.text] = true
			end
		end
		expect(`the panel names the task list: {seen[hudScenario.copy.tasksTitle] == true}`).toBe(
			"the panel names the task list: true"
		)
		expect(`the panel carries the kill feed: {seen[hudScenario.copy.feed] == true}`).toBe(
			"the panel carries the kill feed: true"
		)
		-- ...and closing it puts the screen back
		local closed = w.built.steps.closeOverflow()
		w.refresh()
		expect(closed.open).toBe(false)
		w.dispose()
	end)

	it("the sink's own copy survives a 1.4x pseudo-localization with zero findings", function()
		local l10n = require("./fixtures/a11y_l10n_fixtures")
		local original: { [string]: string } = {}
		for key, value in hudScenario.copy do
			original[key] = value
			hudScenario.copy[key] = l10n.pseudoLocalize(value)
		end
		local ok, err = pcall(function()
			for _, view in
				{ { id = "narrow-portrait", w = 320, h = 640 }, { id = "narrow-landscape", w = 640, h = 320 } }
			do
				local w = drive(view)
				w.built.steps.openUrlBar()
				w.refresh()
				w.built.steps.openOverflow()
				w.refresh()
				local findings = w.handle.controller.diagnostics()
				if #findings > 0 then
					local lines: { string } = {}
					for _, f in findings do
						table.insert(lines, `  {f.node}: {f.issue}`)
					end
					error(
						`{view.id}, sink open, pseudo-localized: {#findings} finding(s)\n` .. table.concat(lines, "\n"),
						0
					)
				end
				w.dispose()
			end
		end)
		for key, value in original do
			hudScenario.copy[key] = value
		end
		if not ok then
			error(err, 0)
		end
		expect(`restored: {hudScenario.copy.tasksChip}`).toBe("restored: Tasks 1/3")
	end)

	--[[ D7.5 — THE URL BAR IS TWO FACTS AND USED TO BE ONE NUMBER.
		`URL_BAR_PX = 200` was "a fact about the SCREENSHOT" and did both jobs: the
		height the chrome steals and the height the pseudo bar is drawn at. Measured
		against a real browser instead (Chrome 151 on macOS, a local page reporting
		`outerHeight - innerHeight`): 143px for a normal window, 67px for a popup with
		a location bar and no tab strip. The fixture models the 67 — a tab strip does
		not APPEAR, and what appears and disappears is the whole event this toggle is
		for. ]]
	it("the drawn bar is the height it steals, and its field is the theme's, not a slab", function()
		local w = drive({ id = "probe", w = 749, h = 380 })
		local before = (w.adapter.node("/HudScreen/Hud") :: any).rect.h
		local step = w.built.steps.openUrlBar()
		w.refresh()
		local after = (w.adapter.node("/HudScreen/Hud") :: any).rect.h
		local bar = w.adapter.node("/HudScreen/UrlBarWhen/then/UrlBarChrome") :: any
		expect(bar ~= nil).toBe(true)
		-- ONE number: the drawn band and the room the HUD lost cannot drift
		expect(`drawn {bar.rect.h} == stolen {step.lostPx}`).toBe(`drawn {step.lostPx} == stolen {step.lostPx}`)
		--[[ THE HUD SHRANK, BUT NOT BY THE WHOLE BAR, and that is the fixture's own
			rule rather than a discrepancy: at 749x380 the ladder caption is above
			`CAPTION_FLOOR` closed and below it open, so the instrument yields its own
			row first and hands part of it back to the thing it explains. Asserting an
			exact equality here would pin the caption's height, which is copy. ]]
		expect(`the HUD gave up room: {before > after}`).toBe("the HUD gave up room: true")
		expect(`...and no more than the bar took: {before - after <= step.lostPx}`).toBe(
			"...and no more than the bar took: true"
		)
		-- ...and it is no longer a near-half-viewport slab: 158px of 380 before
		expect(`bar is {math.floor(bar.rect.h / 380 * 100)}% of the viewport, under 25: {bar.rect.h / 380 < 0.25}`).toBe(
			`bar is {math.floor(bar.rect.h / 380 * 100)}% of the viewport, under 25: true`
		)
		-- the FIELD inside it is the control ladder's own box, so no band height can
		-- ever paint an empty plate again
		local field = w.adapter.node("/HudScreen/UrlBarWhen/then/UrlBarChrome/UrlBarBody/UrlBarFieldPlate") :: any
		expect(field ~= nil).toBe(true)
		expect(`field {field.rect.h} < band {bar.rect.h}: {field.rect.h < bar.rect.h}`).toBe(
			`field {field.rect.h} < band {bar.rect.h}: true`
		)
		w.dispose()
	end)

	--[[ D7.4 — THE LADDER MOVED, and the half of it a ladder cannot fix.
		A team score outranks an FPS readout. The readout is a whole region and the
		scores are the Clock's own second form, so the re-rank fixes the readout and
		the DISCLOSURE ROUTE fixes the scores: the Clock is in the centre lane and the
		readout in the right one, and rule 3 only ever spends the currency of the lane
		that does not fit. ]]
	it("the fps readout is now the first thing to give way, and the scores have a route", function()
		local w = drive({ id = "probe", w = 749, h = 380 })
		local dump = w.handle.controller.compositionAt("/HudScreen/Hud")
		local rank: { [string]: number } = {}
		for _, r in dump.regions do
			rank[string.match(r.id, "([^/]+)$") or r.id] = r.rank
		end
		expect(`readout {rank.Readout} > feed {rank.Feed} > tasks {rank.Tasks}`).toBe("readout 9 > feed 8 > tasks 7")
		-- ...and the scoreboard's own zone names a route rather than relying on rank
		local w2 = drive({ id = "narrow", w = 320, h = 640 })
		local d2 = w2.handle.controller.compositionAt("/HudScreen/Hud")
		local clockRoute = "none"
		for _, u in d2.unshown do
			if string.match(u.id, "([^/]+)$") == "Clock" then
				clockRoute = u.route
			end
		end
		expect(`the elided scoreboard routes to: {clockRoute}`).toBe("the elided scoreboard routes to: overflow")
		w.dispose()
		w2.dispose()
	end)

	--[[ THE BASELINE'S "FOURTH FAILURE CLASS", REFUTED WITH ARITHMETIC.
		`Round 3 · Capture @(416,-37) 81x15` was read as a node painted entirely above
		the top of the viewport. It is not: a Facet ScreenGui renders
		`IgnoreGuiInset = true`, and `AbsolutePosition` on such a tree is reported in
		the INSET-SUBTRACTED space, so window-space y 21 reads back as 21 - 58 = -37
		against the session's measured 58px inset. The baseline proves its own offset:
		three hidden nodes parked at the composition's origin (window y 0) reported
		y = -58 in the same capture.

		The invariant that matters is asserted directly, at the baseline's own
		viewport — the existing ADR-0027 case covers 735x413 and this one does not
		duplicate it, it pins the size the report was taken at. ]]
	it("the objective chip is inside the platform's band at 749x380, not above the screen", function()
		local w = drive({ id = "baseline", w = 749, h = 380 })
		local band = (w.env:get("platformChrome"):get() :: any).band
		expect(band ~= nil).toBe(true)
		local chip = w.adapter.node("/HudScreen/Hud/Strip/StripRow/StripFree/StripChip/then/StripFit/Objective") :: any
		expect(chip ~= nil).toBe(true)
		expect(`chip y {chip.rect.y} >= band y {band.y}: {chip.rect.y >= band.y}`).toBe(
			`chip y {chip.rect.y} >= band y {band.y}: true`
		)
		expect(`chip bottom {chip.rect.y + chip.rect.h} <= band bottom {band.y + band.h}`).toBe(
			`chip bottom {chip.rect.y + chip.rect.h} <= band bottom {band.y + band.h}`
		)
		expect(chip.rect.y + chip.rect.h <= band.y + band.h).toBe(true)
		-- and centred in the FREE band, which is what the baseline's own x agrees with
		expect(math.abs((chip.rect.x + chip.rect.w / 2) - (band.x + band.w / 2)) <= 1).toBe(true)
		w.dispose()
	end)
end)
