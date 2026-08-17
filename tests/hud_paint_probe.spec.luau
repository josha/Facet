--!strict
-- NM-H4a — THE DIRECTOR'S SEQUENCE, AND THE INSTRUMENT THAT SURVIVES IT.
--
-- THE DEFECT. On a real phone, opening the `hud` demo in portrait, tapping the
-- ··· overflow sink and closing it, then rotating and toggling the URL bar
-- through two full cycles, leaves a contiguous document-order PREFIX of the HUD
-- not painting, and it does not come back (`h.jpeg`, 2026-08-16). The unpainted
-- run ends immediately before the fixture's first `Path` node.
--
-- WHY THAT SIGNATURE IS NOT THE LADDER, and this is the fact that pins the whole
-- investigation: `Rounds` has ONE form, declares no `mayDrop`, and is rank 1 —
-- the composition CANNOT stop showing it at any viewport. It is absent in the
-- photograph anyway. So whatever this is, it is below the resolution, and every
-- model-side instrument in this repository will agree with itself while the
-- screen is wrong.
--
-- WHAT THIS FILE IS FOR, in two halves:
--
--   1. THE SEQUENCE ITSELF, replayed with the open/close of the sink that every
--      previous attempt omitted, asserted against the PAINTED tree rather than
--      the resolution. It passes today. It is here so that the day this becomes
--      reproducible headlessly — a park/adopt order, a presentation shift left
--      behind, a dismissal that misses a teardown — the suite says so on the
--      commit that introduced it, instead of a photograph saying so a week later.
--
--   2. THE PROBE'S OWN LOGIC, proved by FORCING the disagreement it exists to
--      catch. The probe compares what the framework believes it is painting
--      against what the engine says it painted; the only way to test that
--      without the defect is to make the engine side lie, which is what the
--      `lie` argument to `geometryFor` below does. A test that only ever sees
--      agreement would
--      prove the instrument compiles, not that it can fire.
--
-- MEASURED, NOT ASSUMED: every watched path in `hud.luau`'s `PROBE_ROWS` was
-- read back out of a LIVE Roblox instance tree in Studio (852x393, 2026-08-16)
-- before being written down, which is why none of them is a stack — the real
-- adapter elides those and they have no Instance at all.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local fake_target = require("../tests/lib/fake_target")
local hud = require("../examples/gallery/scenarios/hud") :: any

-- the device in the report, in points: 1180x2556 physical at 3x
local PORTRAIT = {
	viewportRect = { x = 0, y = 0, w = 393, h = 852 },
	coreSafeInsets = { top = 58, right = 0, bottom = 0, left = 0 },
	deviceSafeInsets = { top = 59, right = 0, bottom = 34, left = 0 },
	topbarInset = { x = 164, y = 0, w = 229, h = 58 },
}
local LANDSCAPE = {
	viewportRect = { x = 0, y = 0, w = 852, h = 393 },
	coreSafeInsets = { top = 46, right = 0, bottom = 0, left = 0 },
	deviceSafeInsets = { top = 0, right = 59, bottom = 21, left = 59 },
	topbarInset = { x = 223, y = 0, w = 629, h = 46 },
}

local function world(view: any): any
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	for key, value in view do
		env:set(key, value)
	end
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local presenter = LuauUI.newPresenter(core, env, adapter, system)
	return { core = core, env = env, adapter = adapter, presenter = presenter, system = system }
end

--[[ THE ENGINE SEAM, HEADLESS. The runner and the shipped showcase host both
	answer `{ x, y, w, h, visible }` for named paths off the live Instance; the
	fake target answers the same shape off `visibleOf`, so the fixture takes the
	SAME branch here that it takes on a phone. Without this the probe would be
	exercised only on its degraded model-only path — the test rig proving the
	half that does not ship. ]]
local function geometryFor(w: any, lie: ((path: string) -> boolean?)?): (paths: { string }) -> any
	return function(paths: { string }): any
		local out: { [string]: any } = {}
		for _, path in paths do
			local node = w.adapter.node(path)
			if node ~= nil and node.rect ~= nil then
				local forced = if lie ~= nil then lie(path) else nil
				out[path] = {
					x = node.rect.x,
					y = node.rect.y,
					w = node.rect.w,
					h = node.rect.h,
					visible = if forced ~= nil then forced else w.adapter.visibleOf(path) ~= false,
				}
			end
		end
		return out
	end
end

local function ctxFor(w: any, lie: ((path: string) -> boolean?)?): any
	return {
		LuauUI = LuauUI,
		core = w.core,
		env = w.env,
		adapter = w.adapter,
		presenter = w.presenter,
		actionSystem = w.system,
		flags = {},
		geometry = geometryFor(w, lie),
	}
end

local function mount(w: any, ctx: any): any
	local built = hud.build(ctx)
	built.handle = w.presenter.present(built.screen, built.present)
	w.presenter.refresh()
	w.presenter.refresh()
	return built
end

local function rotate(w: any, view: any)
	-- ASYNC ARRIVAL, because that is what a real orientation change does: the
	-- viewport lands first and the insets follow. An atomic write models a
	-- resize, not a rotation.
	w.env:set("viewportRect", view.viewportRect)
	w.presenter.refresh()
	w.env:set("coreSafeInsets", view.coreSafeInsets)
	w.env:set("deviceSafeInsets", view.deviceSafeInsets)
	w.env:set("topbarInset", view.topbarInset)
	w.presenter.refresh()
	w.presenter.refresh()
end

--[[ THE ORACLE IS THE PAINTED TREE, not the resolution. The resolution was
	already proved innocent — 288 headless replays, 144 viewport pairs and 36
	live Studio combinations all diverged by zero on it — so a spec that asserts
	`dropped`/`elided` here would re-prove the half that is not broken. ]]
local function paintedTree(w: any): { [string]: string }
	local out: { [string]: string } = {}
	for _, path in w.adapter.paths() do
		if string.find(path, "^/HudScreen") ~= nil then
			local node = w.adapter.node(path)
			local rect = if node ~= nil then node.rect else nil
			out[path] = string.format(
				"%s %s",
				tostring(w.adapter.visibleOf(path) ~= false),
				if rect ~= nil
					then string.format(
						"%d,%d %dx%d",
						math.floor(rect.x + 0.5),
						math.floor(rect.y + 0.5),
						math.floor(rect.w + 0.5),
						math.floor(rect.h + 0.5)
					)
					else "no-rect"
			)
		end
	end
	return out
end

local function divergences(driven: { [string]: string }, fresh: { [string]: string }): { string }
	local seen: { [string]: boolean } = {}
	for path in driven do
		seen[path] = true
	end
	for path in fresh do
		seen[path] = true
	end
	local keys: { string } = {}
	for path in seen do
		table.insert(keys, path)
	end
	table.sort(keys)
	local out: { string } = {}
	for _, path in keys do
		if driven[path] ~= fresh[path] then
			table.insert(out, `{path}: driven={tostring(driven[path])} fresh={tostring(fresh[path])}`)
		end
	end
	return out
end

-- the director's own words: "Portrait. Tap the control. Close it. Landscape.
-- URL bar on then off again. Portrait. URL bar on and off then landscape."
local function driveTheSequence(w: any, built: any)
	built.steps.openOverflow(built)
	w.presenter.refresh()
	built.steps.closeOverflow(built)
	w.presenter.refresh()

	rotate(w, LANDSCAPE)
	built.steps.openUrlBar(built)
	w.presenter.refresh()
	built.steps.closeUrlBar(built)
	w.presenter.refresh()

	rotate(w, PORTRAIT)
	built.steps.openUrlBar(built)
	w.presenter.refresh()
	built.steps.closeUrlBar(built)
	w.presenter.refresh()

	rotate(w, LANDSCAPE)
end

describe("hud: the director's full sequence leaves the painted tree exact", function()
	it("the sink opened and closed, then TWO orientation cycles, paints a fresh mount's tree", function()
		local w = world(PORTRAIT)
		local built = mount(w, ctxFor(w))
		driveTheSequence(w, built)
		local driven = paintedTree(w)
		built.dispose()

		local fw = world(LANDSCAPE)
		local fresh = mount(fw, ctxFor(fw))
		local freshTree = paintedTree(fw)
		fresh.dispose()

		local d = divergences(driven, freshTree)
		expect(#d).toBe(0)
	end)

	it("the round strip is on screen at the end, because no ladder may ever remove it", function()
		-- `Rounds` is one form, rank 1, `recover = "none"`, no `mayDrop`. The
		-- photograph shows it absent, which is why this assertion is the one that
		-- separates "the ladder did it" from "the paint did it".
		local w = world(PORTRAIT)
		local built = mount(w, ctxFor(w))
		driveTheSequence(w, built)
		expect(w.adapter.visibleOf("/HudScreen/Hud/Rounds/RoundStrip/R1")).toBe(true)
		expect(w.adapter.visibleOf("/HudScreen/Hud/Rounds/RoundStrip/R3")).toBe(true)
		local report = built.report()
		expect(table.find(report.dropped, "/HudScreen/Hud/Rounds")).toBe(nil)
		built.dispose()
	end)

	it("the probe stays quiet through the whole sequence and never latches", function()
		local w = world(PORTRAIT)
		local built = mount(w, ctxFor(w))
		driveTheSequence(w, built)
		local probe = built.report().paintProbe
		expect(probe.latches).toBe(0)
		expect(probe.held).toBe(false)
		expect(probe.engine).toBe(true)
		expect(#probe.lost).toBe(0)
		-- ...and it is actually looking at something: a probe that watched zero
		-- rows would be quiet for the wrong reason
		expect(probe.expected > 8).toBe(true)
		built.dispose()
	end)
end)

describe("hud: the paint probe fires when the engine disagrees with the framework", function()
	it("names the unpainted rows, the first painted row after them, and the node they are under", function()
		local w = world(LANDSCAPE)
		-- THE FORCED DEFECT: one ancestor reports `Visible = false` while the
		-- framework's own model says the whole subtree paints — which is exactly
		-- the shape of a visibility walk that stopped, and exactly the shape no
		-- model-side instrument can see.
		local built = mount(
			w,
			ctxFor(w, function(path: string): boolean?
				if path == "/HudScreen/Hud/Tasks" or path == "/HudScreen/Hud/Health" then
					return false
				end
				return nil
			end)
		)
		built.steps.sampleProbe(built)
		local probe = built.report().paintProbe

		expect(probe.held).toBe(true)
		expect(probe.latches > 0).toBe(true)
		expect(table.concat(probe.lost, ",")).toBe("Tasks,Health")
		-- the run ends and the next row that DID paint is named, which is the
		-- answer the photograph could not give
		expect(probe.firstPainted).toBe("Feed")
		expect(probe.hiddenUnder).toBe("/HudScreen/Hud/Tasks")
		built.dispose()
	end)

	it("a latched probe stops sampling until it is re-armed", function()
		local lying = true
		local w = world(LANDSCAPE)
		local built = mount(
			w,
			ctxFor(w, function(path: string): boolean?
				if lying and path == "/HudScreen/Hud/Feed" then
					return false
				end
				return nil
			end)
		)
		built.steps.sampleProbe(built)
		expect(built.report().paintProbe.held).toBe(true)
		expect(table.concat(built.report().paintProbe.lost, ",")).toBe("Feed")

		-- the failure clears, but the capture is HELD: this is the whole reason
		-- the latch exists, because the tester's next tap would otherwise erase
		-- the only evidence
		lying = false
		w.presenter.refresh()
		built.steps.sampleProbe(built)
		expect(table.concat(built.report().paintProbe.lost, ",")).toBe("Feed")

		built.steps.armProbe(built)
		expect(built.report().paintProbe.held).toBe(false)
		expect(#built.report().paintProbe.lost).toBe(0)
		built.dispose()
	end)

	it("the ladder legitimately hiding a zone is NOT a loss", function()
		-- at 393x852 the fixture elides Tasks, Health and Clock by design. A probe
		-- that counted those would fire on every phone in portrait and be
		-- worthless — the row is only lost when the framework says a form should
		-- be painting and the engine says none of them is.
		local w = world(PORTRAIT)
		local built = mount(w, ctxFor(w))
		built.steps.sampleProbe(built)
		local probe = built.report().paintProbe
		expect(#probe.lost).toBe(0)
		expect(probe.held).toBe(false)
		built.dispose()
	end)

	it("degrades honestly when the host carries no engine read", function()
		local w = world(LANDSCAPE)
		local ctx = ctxFor(w)
		ctx.geometry = nil
		local built = mount(w, ctx)
		built.steps.sampleProbe(built)
		local probe = built.report().paintProbe
		expect(probe.engine).toBe(false)
		expect(probe.held).toBe(false)
		built.dispose()
	end)
end)

describe("hud: the probe's plate is on a surface the HUD's own walk cannot reach", function()
	it("mounts its own screen, above the HUD's band, and survives the HUD being hidden", function()
		local w = world(LANDSCAPE)
		local built = mount(w, ctxFor(w))

		local probePaths = 0
		for _, path in w.adapter.paths() do
			if string.find(path, "^/PaintProbe") ~= nil then
				probePaths += 1
			end
		end
		expect(probePaths > 0).toBe(true)
		expect(w.adapter.visibleOf("/PaintProbe")).toBe(true)

		--[[ THE PROOF THAT MATTERS: hide the HUD's own screen root the way a
			visibility walk over THAT tree would, and the probe is untouched. It is
			a different mount, a different controller and a different walk, which is
			why a readout drawn inside the HUD could not have reported the HUD
			going dark. ]]
		built.handle.controller.setRootVisible(false)
		w.presenter.refresh()
		expect(w.adapter.visibleOf("/PaintProbe")).toBe(true)

		-- ...and neither surface files a cross-surface overlap finding, because
		-- the probe declares its band rather than landing on the HUD by accident
		for _, finding in built.handle.controller.diagnostics() do
			expect(string.find(finding.issue, "independently mounted surfaces", 1, true)).toBe(nil)
		end
		built.dispose()
	end)

	--[[ THE MEASUREMENT THAT DECIDED WHERE THE SWITCH LIVES, and it is a FRAMEWORK
		GAP rather than a fixture choice. LuauUI has no cross-surface traversal: a
		second base surface's focusables are in NEITHER surface's ring, in either
		responder mode, so a control over there is reachable by pointer and touch
		and by nothing else. The fixture cannot supply that capability for itself,
		and the HUD's own Screen has under 8px of headroom at 320x640 +14 (proved by
		the always-on sweep, three times, with three different controls), so the
		switch cannot come back to the driver row either.

		THIS CASE IS THE PIN. The day cross-surface traversal ships, it goes red and
		whoever lands it moves the switch. ]]
	it("a second base surface's control is in NEITHER traversal ring (the reported gap)", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		for key, value in LANDSCAPE do
			env:set(key, value)
		end
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local presenter = LuauUI.newPresenter(core, env, adapter, system, { keyboardNavigation = true })
		local w = { core = core, env = env, adapter = adapter, presenter = presenter, system = system }
		local built = mount(w, ctxFor(w))

		local seen: { [string]: boolean } = {}
		for _ = 1, 12 do
			system.deviceKey("Tab", true)
			system.deviceKey("Tab", false)
			local focused = presenter.focus.focused:get()
			if focused ~= nil then
				seen[focused] = true
			end
		end
		-- the HUD's own controls ARE in the ring
		expect(seen["/HudScreen/Drivers/UrlBar"]).toBe(true)
		expect(seen["/HudScreen/Drivers/RideStrip"]).toBe(true)
		-- ...and the probe's switch, on its own surface, is not
		expect(seen["/PaintProbe/ProbeField/ProbeSlot/ProbePlate/ProbeBody/ProbeHold"]).toBe(nil)
		built.dispose()
	end)

	it("the probe's surface is retired with the fixture", function()
		local w = world(LANDSCAPE)
		local built = mount(w, ctxFor(w))
		built.dispose()
		w.presenter.refresh()
		local left = 0
		for _, path in w.adapter.paths() do
			if string.find(path, "^/PaintProbe") ~= nil then
				left += 1
			end
		end
		expect(left).toBe(0)
	end)
end)
