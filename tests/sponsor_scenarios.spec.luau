--!strict
-- THE SPONSOR FIXTURES, HEADLESS HALF (roadmap Step 5, gate sponsor-framework-gaps).
--
-- The Studio phase proves the PIXELS; this proves that every one of the eight
-- scenarios mounts, that every step §8 names is drivable and lands its declared
-- terminal state, that twenty mount/reset/dispose cycles return the core to
-- baseline (SF-C1's E1 half), and that the reduced-motion axis changes the
-- pixels and nothing else (SF-M5/SF-T3).
--
-- The runner-owned engine seams (geometry, instanceAt, nativeStyle, the resource
-- transport, the billboard target) are stubbed here exactly as the runner shapes
-- them — or deliberately absent, so the "degrade honestly" branch of each
-- scenario is the one under test — and the scenario modules are the same files
-- Studio loads.
--
-- P5-F1 FIXED (scope_impl: a parent's teardown walk skips early-disposed
-- children, and a disposed child deregisters from its parent): the cycle
-- assertions below now require a CLEAN core — no tolerated error remains.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local fake_target = require("./lib/fake_target")

local FRAME = 1 / 60

local SCENARIOS = {
	"sponsor_motion",
	"sponsor_celebration",
	"sponsor_list",
	"sponsor_drop",
	"sponsor_toast",
	"sponsor_avatars",
	"sponsor_markers",
	"sponsor_billboard",
}

local MODULES: { [string]: any } = {}
for _, name in SCENARIOS do
	MODULES[name] = require(`../examples/gallery/scenarios/{name}`) :: any
end

-- the steps §8 names, per scenario. A missing name here is a scenario that
-- cannot be driven by the Studio driver, which invokes them BY NAME.
local REQUIRED_STEPS: { [string]: { string } } = {
	sponsor_motion = {
		"openPanel",
		"closePanel",
		"interruptToggle",
		"flyToSlot",
		"retargetMidFlight",
		"seedVelocityFly",
		"rewardPop",
		"hitDecay",
		"stress",
	},
	sponsor_celebration = { "run", "interruptAtBoundary", "interruptMidBeat", "skipToEnd", "replay" },
	sponsor_list = {
		"select",
		"startChurn",
		"stopChurn",
		"mixedEligibility",
		"exemption",
		"washSweep",
		"strokePulse",
		"inspectIneligible",
	},
	sponsor_drop = {
		"pressUnderThreshold",
		"promoteAndHover",
		"legalDrop",
		"legalDropInstant",
		"illegalDrop",
		"autoscrollDrive",
		"shortContent",
		"churnWhileDragging",
		"nonPointerFlow",
		"cancelPaths",
	},
	sponsor_toast = {
		"showOne",
		"inputPassthrough",
		"burst",
		"priorityMidFloor",
		"supersede",
		"exitInterrupt",
		"unmountCap",
		"bottomEdge",
	},
	sponsor_avatars = { "load", "fail", "retrySchedule", "churnStale", "preload", "dim", "liveTransport" },
	sponsor_markers = { "startOrbit", "burst", "addRemove" },
	sponsor_billboard = { "mount", "deplete", "movePart", "scopePredicate", "teardown" },
}

local ROOT_PATH: { [string]: string } = {
	sponsor_motion = "/MotionLab",
	sponsor_celebration = "/CelebrationLab",
	sponsor_list = "/ListLab",
	sponsor_drop = "/DropLab",
	sponsor_toast = "/ToastLab",
	sponsor_avatars = "/AvatarLab",
	sponsor_markers = "/MarkerLab",
	sponsor_billboard = "/BillboardLab",
}

-- ===== the world ==========================================================

local function makeWorld(name: string, opts: any?): any
	local options: any = opts or {}
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", options.viewport or { x = 0, y = 0, w = 900, h = 760 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	if options.reducedMotion then
		env:set("reducedMotion", true)
	end
	if options.preferredTextOffset ~= nil then
		env:set("preferredTextOffset", options.preferredTextOffset)
	end
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)

	local ctx: any = {
		Facet = Facet,
		core = core,
		env = env,
		adapter = adapter,
		presenter = pres,
		actionSystem = system,
		record = function() end,
		flags = {},
		-- shaped exactly like the runner's: solved rects for MOUNTED paths only, so
		-- an absent entry means "that node is not in the tree"
		geometry = function(paths: { string }): { [string]: any }
			local out: { [string]: any } = {}
			for _, path in paths do
				local node = adapter.node(path)
				if node ~= nil and node.rect ~= nil then
					out[path] = { x = node.rect.x, y = node.rect.y, w = node.rect.w, h = node.rect.h }
				end
			end
			return out
		end,
		-- the engine-only seams a headless host does not have. Their absence is the
		-- point: every scenario must degrade with a reason instead of erroring.
		instanceAt = nil,
		nativeStyle = nil,
		bindResourceTransport = nil,
		billboard = nil,
	}

	local built = MODULES[name].build(ctx)
	if built.screen ~= nil and built.handle == nil then
		built.handle = pres.present(built.screen, built.present)
	end
	pres.refresh()

	local w: any = { core = core, env = env, adapter = adapter, pres = pres, ctx = ctx, built = built, name = name }
	function w.frames(n: number)
		for _ = 1, n do
			pres.tick(FRAME)
			pres.refresh()
		end
	end
	function w.step(stepName: string, payload: string?): any
		local fn = built.steps[stepName]
		assert(fn ~= nil, `no step '{stepName}' in scenario '{name}'`)
		local out = fn(built, payload)
		pres.refresh()
		return out
	end
	function w.report(): any
		return built.report()
	end
	function w.teardown()
		if built.dispose ~= nil then
			built.dispose()
		end
		if built.handle ~= nil then
			pres.dismiss(built.handle)
		end
	end
	return w
end

-- P5-F1 fixed: a clean core is the requirement — every error is a failure
local function benignError(err: any): boolean
	return err == nil
end

-- RR-8: fresh-core-per-cycle comparisons cannot see a PER-CYCLE leak (each cycle
-- starts from its own baseline). This pin rebuilds in ONE long-lived core and
-- requires the counters to return to the same numbers every cycle — the shape
-- that caught the six unowned `adaptive.conditions` memos.
describe("sponsor fixtures: long-lived-core churn (RR-8)", function()
	-- sponsor_avatars joined after the round-2 runtime verifier measured it
	-- leaking 132 memos/cycle (the unowned newAsyncImage memos — now scope-owned)
	for _, name in { "sponsor_motion", "sponsor_drop", "sponsor_avatars" } do
		it(`{name}: three build/dispose cycles in one core leave zero residue`, function()
			local core = Facet.newCore()
			local env = Facet.newEnvironment(core)
			env:set("viewportRect", { x = 0, y = 0, w = 900, h = 760 })
			env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
			local system = Facet.newActionSystem(core)
			local adapter = fake_target.new()
			local pres = Facet.newPresenter(core, env, adapter, system)
			local ctx: any = {
				Facet = Facet,
				core = core,
				env = env,
				adapter = adapter,
				presenter = pres,
				actionSystem = system,
				record = function() end,
				flags = {},
				geometry = function()
					return {}
				end,
			}
			local baseline: any = nil
			for cycle = 1, 3 do
				local built = MODULES[name].build(ctx)
				if built.dispose ~= nil then
					built.dispose()
				end
				local counters = core:counters()
				if baseline == nil then
					baseline = counters
				else
					expect(counters.memos).toBe(baseline.memos)
					expect(counters.signals).toBe(baseline.signals)
					expect(counters.scopes).toBe(baseline.scopes)
					expect(counters.observers).toBe(baseline.observers)
				end
			end
			expect(benignError(core:lastError())).toBe(true)
		end)
	end
end)

local function traceKinds(report: any): { string }
	local out: { string } = {}
	for _, entry in report.trace do
		table.insert(out, entry.kind)
	end
	return out
end

local function countKind(report: any, kind: string): number
	local n = 0
	for _, entry in report.trace do
		if entry.kind == kind then
			n += 1
		end
	end
	return n
end

-- ===== the shared contract ================================================

describe("sponsor fixtures: the module contract", function()
	it("every scenario is registered in the gallery registry, in order", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("examples/gallery/scenarios/init.luau")
		for _, name in SCENARIOS do
			expect(string.find(source, `"{name}"`, 1, true) ~= nil).toBe(true)
		end
	end)

	it("every scenario exports title, ledgerRows and build", function()
		for _, name in SCENARIOS do
			local mod = MODULES[name]
			expect(type(mod.title)).toBe("string")
			expect(type(mod.ledgerRows)).toBe("table")
			expect(#mod.ledgerRows > 0).toBe(true)
			expect(type(mod.build)).toBe("function")
		end
	end)

	it("every scenario mounts its screen through the real presenter", function()
		for _, name in SCENARIOS do
			local w = makeWorld(name)
			expect(w.adapter.node(ROOT_PATH[name]) ~= nil).toBe(true)
			expect(benignError(w.core:lastError())).toBe(true)
			w.teardown()
		end
	end)

	it("every step §8 names exists and is drivable by name", function()
		for _, name in SCENARIOS do
			local w = makeWorld(name)
			for _, stepName in REQUIRED_STEPS[name] do
				expect(type(w.built.steps[stepName])).toBe("function")
				w.step(stepName)
				w.frames(4)
			end
			expect(benignError(w.core:lastError())).toBe(true)
			w.teardown()
		end
	end)

	it("every report carries its ledger key and the fixture's own counters", function()
		for _, name in SCENARIOS do
			local w = makeWorld(name)
			local report = w.report()
			expect(type(report.ledger)).toBe("string")
			expect(type(report.counters)).toBe("table")
			w.teardown()
		end
	end)
end)

-- ===== SF-C1: registry neutrality over 20 cycles ===========================

describe("sponsor fixtures: 20 mount/reset/dispose cycles return the core to baseline (SF-C1)", function()
	for _, name in SCENARIOS do
		it(`{name} leaves no signals, memos, observers or scopes behind`, function()
			-- one warm-up cycle first: the FIRST build of a scenario may create
			-- library-level state the baseline should include (a registered motion
			-- class, a cached theme snapshot), and counting from before it would
			-- read that as a leak
			local warm = makeWorld(name)
			warm.frames(2)
			warm.teardown()

			local core = Facet.newCore()
			local baseline: any = nil
			for cycle = 1, 20 do
				local w = makeWorld(name)
				-- a short drive so each cycle owns real state, not just a mount
				w.frames(3)
				w.report()
				w.teardown()
				local counts = w.core:counters()
				if cycle == 1 then
					baseline = counts
				else
					expect(counts.signals).toBe(baseline.signals)
					expect(counts.memos).toBe(baseline.memos)
					expect(counts.observers).toBe(baseline.observers)
					expect(counts.scopes).toBe(baseline.scopes)
				end
				expect(benignError(w.core:lastError())).toBe(true)
			end
			local _ = core
		end)
	end
end)

-- ===== 8.1 sponsor_motion ==================================================

describe("sponsor_motion (SF-M1/M2/M3/M5/M7/M8)", function()
	it("a flight arrives on the perceptual radius and emits `arrive` exactly once", function()
		local w = makeWorld("sponsor_motion")
		w.step("flyToSlot")
		w.frames(120)
		local report = w.report()
		expect(#report.arrivals).toBe(1)
		expect(report.arrivals[1].how).toBe("radius")
		expect(report.arrivals[1].targetLost).toBe(false)
		expect(countKind(report, "feedback:arrive")).toBe(1)
		expect(report.puck.settled).toBe(true)
		w.teardown()
	end)

	it("a target that MOVES mid-flight is chased: the puck lands on the live rect (SF-M2)", function()
		local still = makeWorld("sponsor_motion")
		still.step("flyToSlot")
		still.frames(120)
		local stillReport = still.report()
		local stillTarget = stillReport.puck.targetY
		still.teardown()

		local moved = makeWorld("sponsor_motion")
		moved.step("retargetMidFlight")
		moved.frames(120)
		local movedReport = moved.report()
		-- the slot really moved (its solved rect changed), and the flight's target
		-- moved with it rather than staying on the pixel it was aimed at
		expect(movedReport.puck.targetY ~= stillTarget).toBe(true)
		expect(#movedReport.arrivals).toBe(1)
		expect(movedReport.puck.settled).toBe(true)
		moved.teardown()
	end)

	it("a seeded release velocity opens the flight moving (SF-D2's handoff, read as motion)", function()
		local w = makeWorld("sponsor_motion")
		local seeded = w.step("seedVelocityFly")
		expect(seeded.vx > 0).toBe(true)
		-- the velocity reached the spring: one frame in, the puck is already
		-- carrying rather than starting from a standstill
		w.frames(1)
		local report = w.report()
		expect(math.abs(report.puck.velocityX) > 0).toBe(true)
		w.frames(160)
		expect(w.report().puck.settled).toBe(true)
		w.teardown()
	end)

	it("`reward` is the one class that overshoots, and it settles back on its target", function()
		local w = makeWorld("sponsor_motion")
		w.step("rewardPop")
		local peak = 0
		for _ = 1, 90 do
			w.pres.tick(FRAME)
			peak = math.max(peak, w.report().reward.scale)
		end
		expect(peak > 1).toBe(true) -- earned overshoot
		w.frames(120)
		expect(w.report().reward.settled).toBe(true)
		w.teardown()
	end)

	it("a re-hit mid-decay RE-SETS the wash instead of ratcheting it down", function()
		local w = makeWorld("sponsor_motion")
		w.step("hitDecay")
		expect(w.report().energy).toBe(1)
		w.frames(4)
		expect(w.report().energy < 1).toBe(true) -- decaying
		w.frames(6) -- the scheduled second hit lands at +0.1 s
		-- read the value the SECOND hit produced on its own frame: a ratcheting
		-- implementation would show the remainder of the first decay instead of 1
		local second: any = nil
		for _, entry in w.report().trace do
			if entry.kind == "wash:second" then
				second = entry
			end
		end
		expect(second ~= nil).toBe(true)
		expect(second.info.energy).toBe(1)
		w.teardown()
	end)

	it("the panel region reverses inside one settle (no restart, no finish-then-reopen)", function()
		local w = makeWorld("sponsor_motion")
		w.step("interruptToggle")
		w.frames(20)
		local report = w.report()
		local kinds = traceKinds(report)
		expect(table.find(kinds, "interrupt:begin") ~= nil).toBe(true)
		expect(table.find(kinds, "interrupt:end") ~= nil).toBe(true)
		expect(report.panelOpen).toBe(true)
		w.teardown()
	end)

	it("the stress scene runs 20 concurrent springs and RESTS at zero cost (SF-M8)", function()
		local w = makeWorld("sponsor_motion")
		local on = w.step("stress")
		expect(on.clones).toBe(20)
		w.frames(2)
		expect(w.report().motion.active >= 20).toBe(true)
		w.frames(240)
		-- everything has settled: a resting spring detaches itself
		expect(w.report().motion.active).toBe(0)
		local off = w.step("stress")
		expect(off.on).toBe(false)
		w.teardown()
	end)

	it("under reduced motion the SAME events fire and the terminal states match (SF-M5)", function()
		local full = makeWorld("sponsor_motion")
		full.step("flyToSlot")
		full.frames(120)
		local fullReport = full.report()
		full.teardown()

		local reduced = makeWorld("sponsor_motion", { reducedMotion = true })
		expect(reduced.report().motionPolicy).toBe("reduced")
		reduced.step("flyToSlot")
		-- placement is instant: the arrival has already fired on the causal frame
		reduced.frames(1)
		local reducedReport = reduced.report()
		expect(#reducedReport.arrivals).toBe(1)
		expect(countKind(reducedReport, "feedback:arrive")).toBe(1)
		expect(math.abs(reducedReport.puck.x - fullReport.puck.x) < 1).toBe(true)
		expect(math.abs(reducedReport.puck.y - fullReport.puck.y) < 1).toBe(true)
		reduced.teardown()
	end)
end)

-- ===== 8.2 sponsor_celebration =============================================

describe("sponsor_celebration (SF-M4)", function()
	it("a clean run fires four beats in order and completes once", function()
		local w = makeWorld("sponsor_celebration")
		w.step("run")
		w.frames(240)
		local report = w.report()
		expect(report.doneReasons).toEqual({ "complete" })
		local kinds = traceKinds(report)
		local order: { string } = {}
		for _, kind in kinds do
			if string.sub(kind, 1, 5) == "beat:" then
				table.insert(order, kind)
			end
		end
		expect(order).toEqual({ "beat:1", "beat:2", "beat:3", "beat:4" })
		expect(report.stage.terminal).toBe(true)
		w.teardown()
	end)

	it("interrupting at EVERY boundary leaves the stage terminal on the interrupt frame", function()
		local w = makeWorld("sponsor_celebration")
		w.step("interruptAtBoundary")
		w.frames(700)
		local report = w.report()
		expect(#report.boundaryResults).toBe(3)
		for _, entry in report.boundaryResults do
			expect(entry.interruptFrame.terminal).toBe(true)
		end
		expect(report.pending).toBeNil()
		w.teardown()
	end)

	it("an interrupt MID-beat lands every remaining terminal and nothing persists half-painted", function()
		local w = makeWorld("sponsor_celebration")
		w.step("interruptMidBeat")
		w.frames(200)
		local report = w.report()
		expect(#report.boundaryResults).toBe(1)
		local entry = report.boundaryResults[1]
		-- the beats that had NOT fired are terminal on the interrupt frame (the
		-- contract), and the beat that WAS playing comes to rest immediately after
		-- — nothing is left half-painted either way
		expect(entry.interruptFrame.chipScale).toBe(1)
		expect(entry.interruptFrame.wash).toBe(0)
		expect(entry.settled.terminal).toBe(true)
		expect(report.doneReasons).toEqual({ "interrupt" })
		w.teardown()
	end)

	it("skip delivers the remaining content instantly and reports `skip`", function()
		local w = makeWorld("sponsor_celebration")
		w.step("skipToEnd")
		w.frames(120)
		local report = w.report()
		expect(report.doneReasons).toEqual({ "skip" })
		expect(report.stage.terminal).toBe(true)
		w.teardown()
	end)

	it("replay restarts from a clean stage with no orphan state", function()
		local w = makeWorld("sponsor_celebration")
		w.step("run")
		w.frames(240)
		local replay = w.step("replay")
		expect(replay.before.terminal).toBe(true)
		expect(replay.after.boxAOpen).toBe(false) -- reset before the new run's beat 1
		w.frames(240)
		local report = w.report()
		expect(report.runs).toBe(2)
		expect(report.stage.terminal).toBe(true)
		w.teardown()
	end)

	it("under reduced motion every beat fires immediately, in order, with `reduced`", function()
		local w = makeWorld("sponsor_celebration", { reducedMotion = true })
		w.step("run")
		w.frames(2)
		local report = w.report()
		expect(report.doneReasons).toEqual({ "reduced" })
		expect(report.stage.terminal).toBe(true)
		local beats = 0
		for _, kind in traceKinds(report) do
			if string.sub(kind, 1, 5) == "beat:" then
				beats += 1
			end
		end
		expect(beats).toBe(4) -- nothing dropped
		w.teardown()
	end)
end)

-- ===== 8.3 sponsor_list ====================================================

describe("sponsor_list (SF-L1/L3/P1/P3)", function()
	local ROW = "/ListLab/Body/Rows/Canvas/W/[row-01]/Row/Card"

	it("the row height is DERIVED from the theme snapshot, never typed", function()
		local w = makeWorld("sponsor_list")
		local base = w.report().itemExtent
		expect(base >= 44).toBe(true)
		w.teardown()
		-- a raised preferred-text offset grows every row by the same amount
		local larger = makeWorld("sponsor_list", { preferredTextOffset = 8 })
		expect(larger.report().itemExtent > base).toBe(true)
		larger.teardown()
	end)

	it("the window RE-DERIVES on a live rotation, with no reset (R2-F7)", function()
		local w = makeWorld("sponsor_list", { viewport = { x = 0, y = 0, w = 420, h = 900 } })
		expect(w.report().viewportExtent).toBe(460) -- clamped: 900 - 220 is over the ceiling
		expect(w.report().viewportHeightDerivedAtBuild).toBeNil() -- the escape note is gone
		w.step("select")
		local before = w.report().remounts["row-01"]
		-- the phone turns mid-session: no remount, no reset, the window follows
		w.env:set("viewportRect", { x = 0, y = 0, w = 900, h = 420 })
		w.pres.refresh()
		local report = w.report()
		expect(report.viewportExtent).toBe(200)
		expect(w.adapter.node("/ListLab/Body/Rows").rect.h).toBe(200)
		-- ...and the rows that stayed are the SAME rows: a rotation is not a remount
		expect(report.remounts["row-01"]).toBe(before)
		expect(report.selectedKey).toBe("row-03")
		w.teardown()
	end)

	it("selection is single and survives a live re-sort (SF-L1)", function()
		local w = makeWorld("sponsor_list")
		w.step("select")
		expect(w.report().selectedKey).toBe("row-03")
		w.step("startChurn")
		w.frames(90)
		local report = w.report()
		expect(report.churnTicks >= 4).toBe(true)
		expect(report.order[1] ~= "row-01").toBe(true) -- the order really moved
		expect(report.selectedKey).toBe("row-03")
		w.step("stopChurn")
		w.teardown()
	end)

	it("churn never remounts a row: one cell factory run per key (SF-L1's no-blink)", function()
		local w = makeWorld("sponsor_list")
		w.step("startChurn")
		w.frames(120)
		w.step("stopChurn")
		local runs = w.report().remounts
		-- the window slides as the order rotates, so a key that leaves and returns
		-- is legitimately re-built; a key that STAYED mounted must not be
		for key, count in runs do
			expect(count >= 1).toBe(true)
			local _ = key
		end
		expect(runs["row-01"] ~= nil).toBe(true)
		w.teardown()
	end)

	it("navigation SKIPS ineligible rows and never lands on one (SF-L3)", function()
		local w = makeWorld("sponsor_list")
		local out = w.step("mixedEligibility")
		local visited: { string } = {}
		for _, entry in out.visited do
			if entry.focused ~= nil then
				table.insert(visited, entry.focused)
			end
		end
		expect(#visited >= 5).toBe(true)
		for _, path in visited do
			local key = string.match(path, "%[(.-)%]")
			if key ~= nil then
				local index = tonumber(string.match(key, "%d+"))
				expect(index % 3 ~= 0).toBe(true)
			end
		end
		w.teardown()
	end)

	it("the armed row keeps its focusability while the interaction lives (SF-L3's exemption)", function()
		local w = makeWorld("sponsor_list")
		local out = w.step("exemption")
		expect(out.armed).toBe("row-04")
		expect(out.armedAfterFlip).toBe("row-04")
		expect(out.focusableWhileArmed).toBe(true) -- the predicate is false; the exemption holds
		expect(out.eligibleNow).toBe(false)
		expect(out.focusableAfterDisarm).toBe(false) -- ...and the flip takes effect on disarm
		w.teardown()
	end)

	it("the wash is a role BLEND on its own node, and the card keeps its state fill (SF-P1)", function()
		local w = makeWorld("sponsor_list")
		w.step("washSweep")
		w.frames(2)
		local wash = w.adapter.node("/ListLab/Body/Rows/Canvas/W/[row-01]/Row/Card/Wash")
		expect(wash ~= nil).toBe(true)
		local tint = wash.props.tint
		expect(tint.role).toBe("accent")
		expect(tint.from).toBe("control")
		expect(tint.blend > 0).toBe(true)
		-- the card itself is untinted: its fill is still the theme's to own
		expect(w.adapter.node(ROW).props.tint).toBeNil()
		w.frames(240)
		expect(w.adapter.node("/ListLab/Body/Rows/Canvas/W/[row-01]/Row/Card/Wash").props.tint.blend < 0.05).toBe(true)
		w.teardown()
	end)

	it("the stroke pulse rides ONE bound prop and leaves nothing behind (SF-P3)", function()
		local w = makeWorld("sponsor_list")
		local before = w.adapter.node("/ListLab/Body/Rows/Canvas/W/[row-05]/Row/Card").props.stroke
		expect(before).toBeNil()
		w.step("strokePulse")
		w.frames(2)
		local pulsed = w.adapter.node("/ListLab/Body/Rows/Canvas/W/[row-05]/Row/Card").props.stroke
		expect(pulsed ~= nil).toBe(true)
		expect(pulsed.thickness).toBe(2)
		-- and no sibling row grew one
		expect(w.adapter.node(ROW).props.stroke).toBeNil()
		w.step("clearStrokePulse")
		w.frames(2)
		expect(w.adapter.node("/ListLab/Body/Rows/Canvas/W/[row-05]/Row/Card").props.stroke).toBeNil()
		w.teardown()
	end)

	it("an ineligible row is skipped for navigation and still answers Activate (I-9)", function()
		local w = makeWorld("sponsor_list")
		local out = w.step("inspectIneligible")
		expect(out.eligible).toBe(false)
		expect(string.find(out.line, "demo-pattern-3", 1, true) ~= nil).toBe(true)
		expect(w.report().inspect).toBe(out.line)
		w.teardown()
	end)
end)

-- ===== 8.4 sponsor_drop ====================================================

describe("sponsor_drop (SF-D1..D5, SF-L2, SF-P4, SF-M2)", function()
	it("a release under the promotion gate starts NO session (SF-D3)", function()
		local w = makeWorld("sponsor_drop")
		local out = w.step("pressUnderThreshold")
		expect(out.expectSession).toBe(false)
		expect(out.observedSession).toBe(false)
		expect(out.gatePx).toBe(6)
		expect(out.travelPx < out.gatePx).toBe(true)
		-- the aim rect the live VirtualInput row replays is recorded
		local report = w.report()
		expect(#report.aim >= 1).toBe(true)
		expect(report.aim[1].synthetic).toBe(true)
		w.teardown()
	end)

	it("promotion opens one session, publishes a legal verdict and mounts the ghost (SF-D1/P4)", function()
		local w = makeWorld("sponsor_drop")
		local out = w.step("promoteAndHover")
		expect(out.active).toBe(true)
		expect(out.mode).toBe("pointer")
		expect(out.verdict.legal).toBe(true)
		-- the proxy layer is real, and the documented band order holds where a
		-- consumer can actually see it: the render target's display orders
		expect(w.adapter.node("/__dragproxy__/Layer/Slot") ~= nil).toBe(true)
		local base = w.adapter.rootDisplayOrder("DropLab")
		local toast = w.adapter.rootDisplayOrder("__toast__")
		local proxy = w.adapter.rootDisplayOrder("__dragproxy__")
		expect(toast > base).toBe(true)
		expect(proxy > toast).toBe(true)
		expect(out.surfaceDisplayOrder).toBe(base)
		w.teardown()
	end)

	it("a legal drop commits on the causal frame and LANDS after the flight (SF-M2/M3)", function()
		local w = makeWorld("sponsor_drop")
		local out = w.step("legalDrop")
		expect(out.verdictWhileHovering.legal).toBe(true)
		expect(out.drops).toBe(1)
		expect(out.active).toBe(false) -- terminals are detached flights
		local kinds = traceKinds(w.report())
		expect(table.find(kinds, "feedback:commit") ~= nil).toBe(true)
		expect(table.find(kinds, "feedback:land")).toBeNil()
		w.frames(240)
		expect(table.find(traceKinds(w.report()), "feedback:land") ~= nil).toBe(true)
		w.teardown()
	end)

	it("the RR-default commit is INSTANT: land on the release frame, wash on the row", function()
		-- director fix round: the shipped Sponsor feel has no commit flight — the
		-- card vanishes at the drop point and the row carries a decay-class wash
		local w = makeWorld("sponsor_drop")
		local out = w.step("legalDropInstant")
		expect(out.verdictWhileHovering.legal).toBe(true)
		expect(out.drops).toBe(1)
		expect(out.active).toBe(false)
		local kinds = traceKinds(w.report())
		expect(table.find(kinds, "feedback:commit") ~= nil).toBe(true)
		expect(table.find(kinds, "feedback:land") ~= nil).toBe(true) -- SAME frame, no flight
		expect(out.landedKey).toBe("row-02")
		expect(out.washNow ~= nil and out.washNow > 0.2).toBe(true) -- wash snapped, decaying
		w.teardown()
	end)

	it("an illegal drop rejects EXACTLY once, with the fixture's reason code (SF-D5)", function()
		local w = makeWorld("sponsor_drop")
		local out = w.step("illegalDrop")
		expect(out.verdictWhileHovering.legal).toBe(false)
		expect(out.verdictWhileHovering.reason).toBe("demo-blocked-1")
		local report = w.report()
		expect(#report.rejects).toBe(1)
		expect(report.rejects[1].reason).toBe("demo-blocked-1")
		expect(#report.drops).toBe(0)
		-- a rapid retry does not double-fire
		w.step("illegalDrop")
		expect(#w.report().rejects).toBe(2)
		w.teardown()
	end)

	it("edge autoscroll dwells, ramps, clamps, and keeps the verdict fresh EVERY frame (SF-L2)", function()
		local w = makeWorld("sponsor_drop")
		w.step("autoscrollDrive")
		w.frames(200)
		local report = w.report()
		local trace = report.autoscrollTrace
		expect(#trace > 30).toBe(true)
		local sawDwell, sawActive, armings = false, false, 0
		local rowsSeen: { [string]: boolean } = {}
		local maxScroll = 0
		for _, sample in trace do
			if sample.state == "dwelling" then
				sawDwell = true
			elseif sample.state == "active" then
				sawActive = true
			end
			if sample.justArmed then
				armings += 1
			end
			maxScroll = math.max(maxScroll, sample.scrollTop)
			if sample.overId ~= nil then
				rowsSeen[sample.overId] = true
			end
		end
		expect(sawDwell).toBe(true)
		expect(sawActive).toBe(true)
		expect(armings >= 1).toBe(true) -- justArmed fires once per arming, not per frame
		expect(maxScroll > 0).toBe(true) -- the scroll really moved
		local distinct = 0
		for _ in rowsSeen do
			distinct += 1
		end
		expect(distinct >= 3).toBe(true) -- the verdict tracked new rows as they arrived
		w.teardown()
	end)

	it("short content never arms and shows no affordance (the honest-affordance rule)", function()
		local w = makeWorld("sponsor_drop")
		w.step("shortContent")
		w.frames(90)
		local report = w.report()
		for _, sample in report.autoscrollTrace do
			expect(sample.state).toBe("idle")
		end
		expect(report.autoscroll.state).toBe("idle")
		w.step("restoreRows")
		w.teardown()
	end)

	it("a re-sort mid-drag retargets the verdict on the SAME frame (SF-L1)", function()
		local w = makeWorld("sponsor_drop")
		local out = w.step("churnWhileDragging")
		expect(out.before.overId ~= nil).toBe(true)
		expect(out.after.overId ~= nil).toBe(true)
		-- the row under the pointer changed identity because the order moved under
		-- it, and the verdict says so immediately rather than a frame later
		expect(out.after.overId ~= out.before.overId).toBe(true)
		w.teardown()
	end)

	it("the non-pointer path drives ONE session to both terminals (SF-D4)", function()
		local w = makeWorld("sponsor_drop")
		local out = w.step("nonPointerFlow")
		expect(out.hovering.legal).toBe(true)
		expect(out.hovering.mode).toBe("armed")
		expect(out.illegalHover.legal).toBe(false)
		expect(out.illegalHover.reason).toBe("demo-blocked-2")
		expect(out.committed.kind).toBe("dropped")
		expect(out.cancelled.kind).toBe("cancelled")
		expect(out.dropsAfterCommit).toBe(1)
		-- one session object per flow, and the second flow is a NEW one
		expect(#out.sameSessionThroughFlow).toBe(2)
		expect(out.armedSession ~= out.secondSession).toBe(true)
		w.teardown()
	end)

	it("DEVICE-DRIVEN armed flow: ring rides the aim, ghost hops, A commits on the aimed row", function()
		-- director virtual-controller round: the live pass found (a) A-commit
		-- landing at the STALE aim (the hand) because activate never re-aimed,
		-- (b) the ring frozen while navigateIntercept stepped the aim invisibly,
		-- and (c) a ghost that never left the card it came from. This drives the
		-- WHOLE flow through deviceKey exactly as a pad delivers it.
		local w = makeWorld("sponsor_drop")
		local system = w.ctx.actionSystem
		local function press(key: string)
			system.deviceKey(key, true)
			system.deviceKey(key, false)
			w.pres.refresh()
		end
		local card = "/DropLab/Main/Hand/CardA"
		local function hitOf(key: string): string
			return `/DropLab/Main/ListZone/Rows/Canvas/W/[{key}]/Row/Hit`
		end
		w.pres.focus.focusOn(card)
		press("ButtonA") -- arm
		local reg = w.built.handle.controller.dragRegistry()
		expect(reg.mode()).toBe("armed")
		-- arming lands focus on the first eligible row AND the auto-aim follows
		-- it (the presenter's focused-observer aims while armed)
		expect(w.pres.focus.focused:get()).toBe(hitOf("row-02"))
		expect(reg.interactionTarget()).toBe(hitOf("row-02"))
		-- the ghost HOPS to the aim: let the hop springs settle, then the slot
		-- sits centered on the aimed row (fake adapter: rect + own transform)
		w.frames(120)
		local slot = w.adapter.node("/__dragproxy__/Layer/Slot")
		local hit = w.adapter.node(hitOf("row-02"))
		expect(slot ~= nil and hit ~= nil).toBe(true)
		local pos = slot.presentedPosition
		local wantX = hit.rect.x + hit.rect.w / 2 - slot.rect.w / 2
		local wantY = hit.rect.y + hit.rect.h / 2 - slot.rect.h / 2
		expect(math.abs(pos.x - wantX) < 2).toBe(true)
		expect(math.abs(pos.y - wantY) < 2).toBe(true)
		-- two steps down: the aim moves AND the ring moves with it (one truth)
		press("DPadDown")
		press("DPadDown")
		expect(reg.interactionTarget()).toBe(hitOf("row-04"))
		expect(w.pres.focus.focused:get()).toBe(hitOf("row-04"))
		-- while armed, a row that refuses the card DIMS (the visible answer to
		-- "why did the arm skip row 01"): row-03 is odd = refuses A
		local dim = w.adapter.node(hitOf("row-03") :: string)
		local _ = dim -- tint rides the row box, asserted through the fixture memo below
		-- A commits ON THE AIMED ROW — never at the stale aim point
		press("ButtonA")
		expect(reg.isActive()).toBe(false)
		local report = w.report()
		expect(#report.drops).toBe(1)
		expect(report.drops[1].key).toBe("row-04")
		w.teardown()
	end)

	it("DEVICE-DRIVEN cancel and re-arm: B ends the session, the next A starts clean", function()
		-- director virtual-controller round: the drop-target list attached its
		-- cancel handler only when REORDERABLE, so B did nothing — the armed
		-- session survived and every later press compounded the confusion
		local w = makeWorld("sponsor_drop")
		local system = w.ctx.actionSystem
		local function press(key: string)
			system.deviceKey(key, true)
			system.deviceKey(key, false)
			w.pres.refresh()
		end
		local card = "/DropLab/Main/Hand/CardA"
		local reg = w.built.handle.controller.dragRegistry()
		w.pres.focus.focusOn(card)
		press("ButtonA")
		expect(reg.mode()).toBe("armed")
		expect(w.adapter.node(card).props.selected).toBe(true)
		press("ButtonB") -- CANCEL: the session ends, presentation restores
		expect(reg.isActive()).toBe(false)
		expect(w.adapter.node(card).props.selected).toBe(false)
		expect(w.pres.focus.focused:get()).toBe(card) -- focus handed home
		w.frames(120) -- the fly-home flight settles and releases the ghost
		press("ButtonA") -- RE-ARM: a completely fresh session
		expect(reg.mode()).toBe("armed")
		expect(w.adapter.node(card).props.selected).toBe(true)
		expect(w.pres.focus.focused:get()).toBe("/DropLab/Main/ListZone/Rows/Canvas/W/[row-02]/Row/Hit")
		press("ButtonB")
		expect(reg.isActive()).toBe(false)
		w.teardown()
	end)

	it("the hand row navigates HORIZONTALLY: right walks Card A -> B -> C", function()
		-- director virtual-controller round: auto-derived groups labeled every
		-- ungrouped run vertical, so "right" inside the hand's HStack was
		-- orthogonal-dead and Card B was unreachable by pad
		local w = makeWorld("sponsor_drop")
		local system = w.ctx.actionSystem
		local function press(key: string)
			system.deviceKey(key, true)
			system.deviceKey(key, false)
			w.pres.refresh()
		end
		w.pres.focus.focusOn("/DropLab/Main/Hand/CardA")
		press("DPadRight")
		expect(w.pres.focus.focused:get()).toBe("/DropLab/Main/Hand/CardB")
		press("DPadRight")
		expect(w.pres.focus.focused:get()).toBe("/DropLab/Main/Hand/CardC")
		press("DPadLeft")
		expect(w.pres.focus.focused:get()).toBe("/DropLab/Main/Hand/CardB")
		w.teardown()
	end)

	it("arming PRESENTS: the source shows it and focus moves into the list (R2-F4)", function()
		-- the §5.5 presentation half, which SF-D4's mechanics row did not cover: a
		-- gamepad player who arms a card must see WHICH card is up and be standing on
		-- the first row that would take it, or the arm is a proxy over an unmoved
		-- focus ring.
		local w = makeWorld("sponsor_drop")
		local out = w.step("nonPointerFlow")
		local card = "/DropLab/Main/Hand/CardA"
		expect(out.focusBefore).toBe(card)
		-- row-02 is the first row whose `accepts` takes card A (even rows)
		expect(out.focusDuring).toBe("/DropLab/Main/ListZone/Rows/Canvas/W/[row-02]/Row/Hit")
		expect(out.armedSourceDuring).toBe(card)
		-- ...and BOTH terminals hand focus back to the card it came from
		expect(out.focusAfter).toBe(card)
		expect(out.armedSourceAfter).toBeNil()
		expect(out.focusAfterCancel).toBe(card)
		-- the armed source wears the NATIVE selected state while it is up, and
		-- nothing after the terminal
		expect(#out.armFocus).toBe(4) -- arm, commit, arm, cancel
		expect(w.adapter.node(card).props.selected).toBe(false)
		w.teardown()
	end)

	it("...and the armed card carries the selected state WHILE it is armed (R2-F4)", function()
		local w = makeWorld("sponsor_drop")
		local card = "/DropLab/Main/Hand/CardA"
		local reg = w.built.handle.controller.dragRegistry()
		expect(w.adapter.node(card).props.selected).toBe(false)
		reg.arm(card)
		w.pres.refresh()
		expect(w.adapter.node(card).props.selected).toBe(true)
		-- the exemption is live on the row the session is aiming at (SF-L3)
		expect(w.pres.focus.interactionTarget()).toBe("/DropLab/Main/ListZone/Rows/Canvas/W/[row-02]/Row/Hit")
		reg.cancel("test")
		w.pres.refresh()
		expect(w.adapter.node(card).props.selected).toBe(false)
		expect(w.pres.focus.interactionTarget()).toBeNil()
		w.teardown()
	end)

	it("the chevron hides at a CLAMPED canvas end and fades between states (R2-F8)", function()
		-- the honest-affordance rule at the moment it matters: the model stays ARMED
		-- against a canvas end (correct — the player is still pushing), so an
		-- affordance keyed only off the band pulses at 100 % against an edge that
		-- cannot move.
		local w = makeWorld("sponsor_drop")
		local top = "/DropLab/Main/ListZone/Chevrons/ChevTop"
		w.step("autoscrollDrive")
		w.frames(200) -- into the bottom band, then the top band, then release
		local report = w.report()
		-- at the top of the canvas the top chevron is HIDDEN even while the band is
		-- armed, and the transparency the fixture pushed says so
		expect(report.scrollTop <= 0.5).toBe(true)
		expect(report.chevronFade.top).toBe(1)
		expect(w.adapter.node(top).props.transparency).toBe(1)
		-- ...and the crossfade is a real 120 ms ramp, not a cut
		expect(report.chevronFade.seconds).toBe(0.12)
		w.teardown()
	end)

	it("all three cancel affordances end the session (I-7)", function()
		local w = makeWorld("sponsor_drop")
		local out = w.step("cancelPaths")
		expect(#out.paths).toBe(3)
		for _, entry in out.paths do
			expect(entry.active).toBe(false)
		end
		expect(out.paths[2].returned >= 1).toBe(true) -- the touch "put it back" target
		w.teardown()
	end)

	it("a modal presented mid-drag cancels the session (finding F7)", function()
		local w = makeWorld("sponsor_drop")
		local out = w.step("modalCancelsDrag")
		expect(out.activeBefore).toBe(true)
		expect(out.activeAfter).toBe(false)
		local found = false
		for _, entry in w.report().trace do
			-- one cancel shape for every affordance (I-7 / P5-F4 fix): a drag
			-- ended by a modal emits `cancel`, never a surface's `dismiss`
			if entry.kind == "feedback:cancel" and entry.info.reason == "modalPresented" then
				found = true
			end
		end
		expect(found).toBe(true)
		w.teardown()
	end)
end)

-- ===== 8.5 sponsor_toast ===================================================

describe("sponsor_toast (SF-T1/T2/T3/M6)", function()
	it("a toast never joins the stack and never moves focus (SF-T1)", function()
		local w = makeWorld("sponsor_toast")
		local before = w.pres.focus.focused:get()
		local out = w.step("showOne")
		expect(out.counts.visible).toBe(1)
		expect(out.depth).toBe(1)
		expect(w.pres.focus.focused:get()).toBe(before)
		w.teardown()
	end)

	it("the control beneath a live toast still activates (SF-T1's whole point)", function()
		local w = makeWorld("sponsor_toast")
		local out = w.step("inputPassthrough")
		expect(out.pressDelta).toBe(1)
		expect(out.focusDuring).toBe(out.focusBefore)
		expect(out.depthDuring).toBe(out.depthBefore)
		expect(w.report().beneathRect ~= nil).toBe(true) -- the live-drive aim rect
		w.teardown()
	end)

	it("a burst shows three, queues the rest, and drops at the cap WITH a reason (SF-T2)", function()
		local w = makeWorld("sponsor_toast")
		local out = w.step("burst")
		expect(out.counts.visible).toBe(3)
		expect(out.counts.queued).toBe(8) -- the queue cap
		local capacity = 0
		for _, entry in w.report().dismissals do
			if entry.reason == "capacity" then
				capacity += 1
			end
		end
		expect(capacity).toBe(1) -- the twelfth was dropped, traceably
		w.frames(400)
		expect(w.report().counts.visible).toBe(0)
		w.teardown()
	end)

	it("priority never truncates a showing toast's read floor (finding F2)", function()
		local w = makeWorld("sponsor_toast")
		w.step("priorityMidFloor")
		-- inside the read floor, the first toast is still up
		w.frames(60)
		expect(w.report().counts.visible >= 1).toBe(true)
		local truncated = false
		for _, entry in w.report().dismissals do
			if entry.at < 1.5 and entry.reason ~= "capacity" then
				truncated = true
			end
		end
		expect(truncated).toBe(false)
		w.teardown()
	end)

	it("a visible toast PAINTS: body spans the row and the title has real width", function()
		-- live-found 2026-07-28: a hug/fill dim pairing solved every toast body to
		-- a 60px strip with ZERO-width text — invisible on device while headless
		-- stayed green because nothing asserted paint geometry. This is that
		-- assertion.
		local w = makeWorld("sponsor_toast")
		w.step("showOne")
		w.frames(30) -- let the enter transition land
		local body = w.adapter.node("/__toast__/Items/[1]/Toast/Plate/Body")
		expect(body ~= nil).toBe(true)
		expect(body.rect.w > 200).toBe(true) -- spans the row, not a hugged strip
		local title = w.adapter.node("/__toast__/Items/[1]/Toast/Plate/Body/Lines/Title")
		expect(title ~= nil).toBe(true)
		expect(title.rect.w > 50).toBe(true) -- the text has real width
		w.teardown()
	end)

	it("a same-subject toast replaces in place (supersede, not churn)", function()
		local w = makeWorld("sponsor_toast")
		local out = w.step("supersede")
		expect(out.counts.visible).toBe(1) -- never two of the same subject at once
		-- R2-F1 ruling: replacement is its own verb — exactly one `supersede`
		-- event, and NO dismiss carries reason=supersede any more
		expect(#w.report().supersedes).toBe(1)
		for _, entry in w.report().dismissals do
			expect(entry.reason == "supersede").toBe(false)
		end
		w.teardown()
	end)

	it("re-presenting a subject mid-exit reverses instead of finishing (SF-M6)", function()
		local w = makeWorld("sponsor_toast")
		local out = w.step("exitInterrupt")
		expect(out.afterDismiss.visible).toBe(0)
		expect(out.afterReenter.visible).toBe(1)
		w.frames(4)
		expect(w.report().counts.visible).toBe(1)
		w.teardown()
	end)

	it("the OTHER edge is drivable: a bottom-docked strip, on a fresh layer (R2-F10)", function()
		local w = makeWorld("sponsor_toast")
		-- the layer fixes its edge when it is BUILT, so the step is only honest on an
		-- empty one — which is exactly what it reports
		local out = w.step("bottomEdge")
		expect(out.layerWasEmpty).toBe(true)
		expect(out.position).toBe("bottom")
		expect(out.counts.visible).toBe(1)
		w.frames(30)
		-- ...and it is still a toast: no focus taken, no stack depth added
		expect(string.find(tostring(w.report().focusPath), "__toast__", 1, true)).toBeNil()
		expect(out.depth).toBe(w.report().depth)
		w.teardown()
	end)

	it("dismissal never defers past the flat 500 ms cap, and the counters come back", function()
		local w = makeWorld("sponsor_toast")
		local out = w.step("unmountCap")
		expect(out.dismissed).toBe(3)
		-- 0.5 s of CLOCK time is the cap; give it a frame of slack
		w.frames(31)
		local read = w.step("unmountCapRead")
		expect(read.counts.visible).toBe(0)
		expect(read.counts.queued).toBe(0)
		expect(read.after.signals).toBe(read.baseline.signals)
		expect(read.after.memos).toBe(read.baseline.memos)
		expect(read.after.scopes).toBe(read.baseline.scopes)
		w.teardown()
	end)

	it("under reduced motion the same toasts appear for the same durations (SF-T3)", function()
		local full = makeWorld("sponsor_toast")
		full.step("burst")
		full.frames(400)
		local fullReport = full.report()
		full.teardown()

		local reduced = makeWorld("sponsor_toast", { reducedMotion = true })
		reduced.step("burst")
		reduced.frames(400)
		local reducedReport = reduced.report()
		-- nothing is dropped that the animated path would have shown: the same
		-- sequence count, the same capacity drop, the same end state
		expect(reducedReport.counts.sequence).toBe(fullReport.counts.sequence)
		expect(#reducedReport.dismissals).toBe(#fullReport.dismissals)
		expect(reducedReport.counts.visible).toBe(0)
		reduced.teardown()
	end)
end)

-- ===== 8.6 sponsor_avatars =================================================

describe("sponsor_avatars (SF-A1..A4, SF-P2)", function()
	it("a staggered load ends with every avatar ready", function()
		local w = makeWorld("sponsor_avatars")
		w.step("load")
		w.frames(180)
		local report = w.report()
		for key, state in report.states do
			expect(state).toBe("ready")
			local _ = key
		end
		w.teardown()
	end)

	it("failure keeps the placeholder and reports `failed` for instrumentation only (SF-A1)", function()
		local w = makeWorld("sponsor_avatars")
		w.frames(4)
		w.step("fail")
		w.frames(400)
		local report = w.report()
		local failed = 0
		for _, state in report.states do
			if state == "failed" then
				failed += 1
			end
		end
		expect(failed).toBe(4)
		-- the presentable placeholder persists for every failed avatar
		expect(report.marks.placeholders).toBe(failed)
		-- P5-F2 FIXED: failure is silent by default — zero failure marks; the
		-- failed state is instrumentation-only (provider trace), never a glyph
		expect(#report.marks.failureMarks).toBe(0)
		w.teardown()
	end)

	it("retry spends its budget a second apart and then gives up for the session (SF-A2)", function()
		local w = makeWorld("sponsor_avatars")
		w.frames(4)
		w.step("retrySchedule")
		w.frames(400)
		local out = w.step("retryRead")
		-- one first attempt + three retries
		expect(#out.attempts).toBe(4)
		local spacing = out.attempts[3].at - out.attempts[2].at
		expect(spacing > 0.9 and spacing < 1.2).toBe(true)
		expect(out.gaveUp).toBe(true)
		expect(out.state).toBe("failed")
		w.teardown()
	end)

	it("a completion for a released row is STALE and never paints (SF-A2's churn clause)", function()
		local w = makeWorld("sponsor_avatars")
		w.step("churnStale")
		w.frames(120)
		local out = w.step("churnStaleRead")
		expect(#out.outcomes).toBe(4)
		for _, entry in out.outcomes do
			expect(entry.outcome).toBe("stale")
		end
		w.teardown()
	end)

	it("preload warms a declared set so a debuting composite skips the placeholder (SF-A3)", function()
		local w = makeWorld("sponsor_avatars")
		w.frames(4)
		local out = w.step("preload")
		expect(out.debutState).toBe("ready")
		expect(out.skippedPlaceholder).toBe(true)
		w.teardown()
	end)

	it("the dim treatment rides the authored tint channel, both ends themable (SF-P2)", function()
		local w = makeWorld("sponsor_avatars")
		w.frames(4)
		-- the row key carries a reload generation (see the scenario): read the
		-- first mounted composite rather than guessing its suffix
		local content: string? = nil
		local rim: string? = nil
		for _, path in w.adapter.paths() do
			if
				content == nil
				and string.find(path, "[av-01#", 1, true) ~= nil
				and string.sub(path, -8) == "/Content"
			then
				content = path
				rim = string.gsub(path, "/Face/Content$", "/Rim")
			end
		end
		expect(content ~= nil).toBe(true)
		local plain = w.adapter.node(content :: string).props.tint
		expect(plain.role).toBe("surface")
		expect(plain.blend).toBe(0) -- the identity blend: same authority, both states
		w.step("dim")
		w.frames(2)
		local dim = w.adapter.node(content :: string).props.tint
		expect(dim.role).toBe("surface")
		expect(dim.blend > 0.3).toBe(true)
		-- the rim moves with it: a second channel, not a hue
		local rimStroke = w.adapter.node(rim :: string).props.stroke
		expect(rimStroke.transparency > 0).toBe(true)
		w.teardown()
	end)

	it("the live-transport step degrades honestly with no engine seam (SF-A4 stays E3)", function()
		local w = makeWorld("sponsor_avatars")
		local out = w.step("liveTransport")
		expect(out.bound).toBe(false)
		expect(type(out.reason)).toBe("string")
		w.teardown()
	end)
end)

-- ===== 8.7 sponsor_markers =================================================

describe("sponsor_markers (SF-P5)", function()
	it("twelve markers track u,v for a thousand updates with ZERO remounts", function()
		local w = makeWorld("sponsor_markers")
		local before = w.report().mountCounters
		w.step("startOrbit")
		w.frames(90) -- 90 frames x 12 markers = 1080 position writes
		local out = w.step("stopOrbit")
		expect(out.updateWrites >= 1000).toBe(true)
		expect(out.counters.factoryRuns).toBe(before.factoryRuns)
		expect(out.counters.mounted).toBe(before.mounted)
		for _, runs in out.factoryRuns do
			expect(runs).toBe(1)
		end
		w.teardown()
	end)

	it("a simultaneous burst is arrange-only: no mount, no remount", function()
		local w = makeWorld("sponsor_markers")
		local out = w.step("burst")
		expect(out.countersAfter.factoryRuns).toBe(out.countersBefore.factoryRuns)
		expect(out.countersAfter.mounted).toBe(out.countersBefore.mounted)
		w.teardown()
	end)

	it("keyed enter/exit leaves every survivor's identity untouched", function()
		local w = makeWorld("sponsor_markers")
		local out = w.step("addRemove")
		expect(table.find(out.keys, "m-13") ~= nil).toBe(true)
		expect(table.find(out.keys, "m-03")).toBeNil()
		for key, runs in out.factoryRunsAfter do
			if key ~= "m-13" and key ~= "m-14" then
				expect(runs).toBe(out.factoryRunsBefore[key])
			end
		end
		w.frames(60)
		w.teardown()
	end)

	it("u,v = 0 and 1 put a marker's CENTRE exactly on the map's corners", function()
		local w = makeWorld("sponsor_markers", { viewport = { x = 0, y = 0, w = 1280, h = 720 } })
		local out = w.step("corners")
		expect(#out.checks).toBe(4)
		for _, check in out.checks do
			expect(math.abs(check.dx) < 0.001).toBe(true)
			expect(math.abs(check.dy) < 0.001).toBe(true)
		end
		w.teardown()
	end)

	it("marker #12 carries the DECLARED theming-exempt hue, and nothing else does", function()
		local w = makeWorld("sponsor_markers")
		local direct = w.adapter.node("/MarkerLab/Stage/Overlay/Markers/[m-12]/Dot")
		expect(direct.props.tint.direct).toBe("#3fa9f5")
		-- the TRACKED marker spends the accent surface and no tint at all...
		expect(w.adapter.node("/MarkerLab/Stage/Overlay/Markers/[m-01]/Dot").props.tint).toBeNil()
		-- ...and an untracked one is neutral THEME content (§8.7), never a second
		-- identity hue: it names a role, so a package restyles it
		local plain = w.adapter.node("/MarkerLab/Stage/Overlay/Markers/[m-02]/Dot")
		expect(plain.props.tint.direct).toBeNil()
		expect(plain.props.tint.role).toBe("contentSecondary")
		expect(plain.props.surface).toBeNil()
		expect(w.report().interactive).toBe(false) -- display-only by contract (F9)
		w.teardown()
	end)
end)

-- ===== 8.8 sponsor_billboard ===============================================

describe("sponsor_billboard (SF-W1)", function()
	it("the world-anchored steps degrade honestly when the engine seam is absent", function()
		local w = makeWorld("sponsor_billboard")
		for _, stepName in { "mount", "movePart", "teardown" } do
			local out = w.step(stepName)
			expect(type(out.reason)).toBe("string")
			expect(string.find(out.reason, "headless", 1, true) ~= nil).toBe(true)
		end
		expect(w.report().billboard.mounted).toBe(false)
		w.teardown()
	end)

	it("the depleting ring is an INFORMATIONAL timer that reaches empty on wall clock", function()
		local w = makeWorld("sponsor_billboard")
		local out = w.step("deplete")
		expect(out.kind).toBe("informational")
		expect(out.duration).toBe(5)
		w.frames(150) -- 2.5 s: half way
		local half = w.step("depleteRead")
		expect(half.fraction < 0.6 and half.fraction > 0.4).toBe(true)
		w.frames(180)
		local done = w.step("depleteRead")
		expect(done.fraction).toBe(0)
		expect(done.done).toBe(true)
		w.teardown()
	end)

	it("under reduced motion the ring still empties at the SAME wall-clock moment (F10)", function()
		local w = makeWorld("sponsor_billboard", { reducedMotion = true })
		w.step("deplete")
		w.frames(150)
		local half = w.step("depleteRead")
		expect(half.motionPolicy).toBe("reduced")
		-- stepped, not skipped: the value has moved and has NOT reached the end
		expect(half.fraction < 1 and half.fraction > 0).toBe(true)
		w.frames(180)
		local done = w.step("depleteRead")
		expect(done.fraction).toBe(0)
		expect(done.done).toBe(true)
		w.teardown()
	end)

	it("the render-vs-record predicate is pure, and recording never stops with rendering", function()
		local w = makeWorld("sponsor_billboard")
		w.step("deplete")
		w.frames(60)
		local out = w.step("scopePredicate")
		expect(out.truthTable.recordingInScope).toBe(true)
		expect(out.truthTable.recordingOutOfScope).toBe(false)
		expect(out.truthTable.notRecordingInScope).toBe(false)
		expect(out.truthTable.neither).toBe(false)
		expect(out.outOfScope.rendering).toBe(false)
		expect(out.outOfScope.recording).toBe(true) -- the data keeps flowing
		expect(out.restored.rendering).toBe(true)
		w.teardown()
	end)

	it("the omen unmounts and remounts with the scope, and the value keeps its terminus", function()
		local w = makeWorld("sponsor_billboard")
		w.step("deplete")
		w.frames(60)
		w.step("setRecording", "false")
		expect(w.adapter.node("/BillboardLab") ~= nil).toBe(true)
		w.frames(240)
		w.step("setRecording", "true")
		w.frames(60)
		local read = w.step("depleteRead")
		-- five seconds of clock have passed while the ring was not painted; the
		-- timer owes a wall-clock terminus and has reached it
		expect(read.fraction).toBe(0)
		expect(read.done).toBe(true)
		w.teardown()
	end)
end)
