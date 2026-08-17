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
	answer `{ x, y, w, h, visible, enabled }` for named paths off the live
	Instance; the fake target answers the same shape off `visibleOf` and
	`rootVisibleOf`, so the fixture takes the SAME branch here that it takes on a
	phone. Without this the probe would be exercised only on its degraded
	model-only path — the test rig proving the half that does not ship.

	`lie` FORCES A DISAGREEMENT, and it is the only way to test a comparison
	whose two sides agree by construction headlessly. It may return a boolean
	(the node's own paint bit) or a rect-shaped table (the engine's own
	`AbsoluteSize`, which is the half the first cut of this probe collected and
	never read). ]]
local function geometryFor(w: any, lie: ((path: string) -> any)?): (paths: { string }) -> any
	return function(paths: { string }): any
		local out: { [string]: any } = {}
		for _, path in paths do
			local node = w.adapter.node(path)
			if node ~= nil and node.rect ~= nil then
				local forced = if lie ~= nil then lie(path) else nil
				local screenId = string.match(path, "^/([^/]+)")
				local rootOn = if screenId ~= nil then w.adapter.rootVisibleOf(screenId) ~= false else true
				out[path] = {
					x = node.rect.x,
					y = node.rect.y,
					w = if type(forced) == "table" then forced.w else node.rect.w,
					h = if type(forced) == "table" then forced.h else node.rect.h,
					visible = if type(forced) == "boolean" then forced else w.adapter.visibleOf(path) ~= false,
					enabled = rootOn,
				}
			end
		end
		return out
	end
end

local function ctxFor(w: any, lie: ((path: string) -> any)?): any
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

--[[ ══ THE INSTRUMENT'S OWN HONESTY (the 2026-08-16 director round) ═════════════

	THE PLATE SHIPPED A FALSE VERDICT. On the reported phone it read `13 of 13
	painting` on a screen visibly missing six things, and the director acted on
	it. Four separate defects in the readout produce that number, and each one is
	pinned below by a spec that FAILS against the shipped code:

	  1. THE FALLBACK CLAIMED SUCCESS. With no `ctx.geometry` the per-path engine
	     verdict returned `true` — "could not measure" published as "measured
	     yes", which is the exact collapse
	     docs/lessons/capability-probes-must-be-tri-state.md was written about.
	  2. A ROW WAS PAINTED IF *ANY* PATH PAINTED, so partial loss inside a row
	     was invisible. The HUD's rows are groups.
	  3. A ROW THE MODEL DID NOT WANT WAS DROPPED FROM THE DENOMINATOR ENTIRELY.
	     Measured across 28 viewport x URL-bar states before this change: one row
	     silently left the count at every landscape size and four did at every
	     portrait size — and `13 of 13` is precisely what the HEALTHY fixture
	     prints at the director's own 734x393. The plate on the phone was
	     indistinguishable from a plate with nothing wrong.
	  4. THE ENGINE'S RECT WAS COLLECTED AND NEVER READ. The seam answers
	     `AbsoluteSize`; the verdict looked only at `Visible`. A node the engine
	     is painting at zero pixels — a parked corpse, an unmaterialised node, a
	     collapsed box — reported as painting, and that is the whole class of
	     "the write never landed" the probe exists to catch.
	  5. ...AND A SURFACE ROOT IS `ScreenGui.Enabled`, NOT `Visible`. Every
	     watched path is a GuiObject, so a whole surface going dark left all
	     fourteen rows reporting `Visible = true` with nothing on screen. ]]
describe("hud: the paint probe never reports a verdict it did not measure", function()
	it("refuses to print a paint count when the host supplies no engine seam", function()
		local w = world(LANDSCAPE)
		local ctx = ctxFor(w)
		ctx.geometry = nil
		local built = mount(w, ctx)
		built.steps.sampleProbe(built)
		local probe = built.report().paintProbe

		-- the plate SAYS SO, in place of a count, and unmissably
		expect(string.find(probe.plate, "ENGINE SIDE UNAVAILABLE", 1, true) ~= nil).toBe(true)
		-- ...and there is no paint verdict anywhere on it
		expect(string.find(probe.plate, "painting", 1, true)).toBe(nil)
		expect(string.find(probe.plate, "NOT PAINTED", 1, true)).toBe(nil)
		expect(probe.painting).toBe(0)
		expect(#probe.lost).toBe(0)
		-- every row the model wants is UNMEASURED, which is a third state
		expect(#probe.unmeasured).toBe(probe.wanted)
		expect(probe.wanted > 8).toBe(true)
		expect(probe.engine).toBe(false)
		built.dispose()
	end)

	it("an engine seam that answers nothing at all is unavailable, not a healthy screen", function()
		-- the shipped host reads `adapter.getInstance`; an adapter without it, or
		-- a path map that has moved on, answers `{}` for every path. A seam that
		-- returned nothing for a query of forty paths has not measured a screen.
		local w = world(LANDSCAPE)
		local ctx = ctxFor(w)
		ctx.geometry = function(): any
			return {}
		end
		local built = mount(w, ctx)
		built.steps.sampleProbe(built)
		local probe = built.report().paintProbe
		expect(probe.engine).toBe(false)
		expect(string.find(probe.plate, "ENGINE SIDE UNAVAILABLE", 1, true) ~= nil).toBe(true)
		expect(#probe.unmeasured).toBe(probe.wanted)
		expect(probe.painting).toBe(0)
		built.dispose()
	end)

	it("names every row it skipped and shows the denominator it actually watched", function()
		--[[ `13 of 13 painting` was never a count of fourteen rows: rows the model
			did not want left the denominator with nothing said, and the reader had
			no way to tell a shrunken denominator from a full one. Measured in
			portrait: `ScoreHome`, `TimerRing` and `ScoreAway` all leave — and
			`TimerRing` is the fixture's first `Path` node, the exact boundary the
			reported prefix stops at, so the probe was silently dropping the one row
			it was built to resolve. A skipped row is UNPROVEN, and it is named. ]]
		local w = world(PORTRAIT)
		local built = mount(w, ctxFor(w))
		built.steps.sampleProbe(built)
		local probe = built.report().paintProbe

		expect(probe.declared).toBe(14)
		expect(probe.wanted + #probe.skipped).toBe(probe.declared)
		expect(#probe.skipped > 0).toBe(true)
		-- the plate carries BOTH halves rather than a denominator that quietly moved
		expect(string.find(probe.plate, `{probe.wanted} of 14 rows`, 1, true) ~= nil).toBe(true)
		expect(string.find(probe.plate, "skipped:", 1, true) ~= nil).toBe(true)
		for _, name in probe.skipped do
			expect(string.find(probe.plate, name, 1, true) ~= nil).toBe(true)
		end
		built.dispose()
	end)

	it("a row the engine paints at ZERO PIXELS is LOST, not painting", function()
		-- `Visible = true` is not "painting". The seam has always answered
		-- `AbsoluteSize`; the verdict never looked at it.
		local w = world(LANDSCAPE)
		local built = mount(
			w,
			ctxFor(w, function(path: string): any
				if path == "/HudScreen/Hud/Feed/FeedLine" then
					return { w = 0, h = 0 }
				end
				return nil
			end)
		)
		built.steps.sampleProbe(built)
		local probe = built.report().paintProbe
		expect(table.concat(probe.lost, ",")).toBe("Feed")
		expect(probe.hiddenUnder).toBe("/HudScreen/Hud/Feed/FeedLine")
		expect(string.find(probe.plate, "NOT PAINTED", 1, true) ~= nil).toBe(true)
		built.dispose()
	end)

	it("a row is painted only when EVERY path the model wants is painting", function()
		--[[ `Rounds` is the row that makes this testable and the row that needs it:
			one form, rank 1, `recover = "none"`, and THREE discs that are all on
			screen at once — R3 is the ··· sink, the recovery route for everything
			the ladder has taken away. Losing R3 while R1 and R2 paint is a partial
			loss of the one zone no ladder may touch, and the first cut of this
			probe called that row `painted`. ]]
		local w = world(LANDSCAPE)
		local built = mount(
			w,
			ctxFor(w, function(path: string): any
				if path == "/HudScreen/Hud/Rounds/RoundStrip/R3" then
					return false
				end
				return nil
			end)
		)
		built.steps.sampleProbe(built)
		local probe = built.report().paintProbe
		expect(table.concat(probe.lost, ",")).toBe("Rounds")
		expect(probe.hiddenUnder).toBe("/HudScreen/Hud/Rounds/RoundStrip/R3")
		-- ...and the other two discs really are painting, so this is a PARTIAL loss
		-- and not the whole row going dark
		expect(w.adapter.visibleOf("/HudScreen/Hud/Rounds/RoundStrip/R1")).toBe(true)
		expect(w.adapter.visibleOf("/HudScreen/Hud/Rounds/RoundStrip/R2")).toBe(true)
		built.dispose()
	end)

	it("a surface whose ROOT is disabled loses every row, with the root named", function()
		-- `ScreenGui.Enabled` is not `GuiObject.Visible`, and every watched path is
		-- a GuiObject: the whole HUD can go dark with all fourteen rows still
		-- reporting `Visible = true`. That is "the UI went away and the plate said
		-- everything was fine", exactly.
		local w = world(LANDSCAPE)
		local built = mount(w, ctxFor(w))
		built.handle.controller.setRootVisible(false)
		built.steps.sampleProbe(built)
		local probe = built.report().paintProbe
		expect(#probe.lost).toBe(probe.wanted)
		expect(probe.painting).toBe(0)
		expect(probe.firstPainted).toBe(nil)
		built.dispose()
	end)

	it("`13 of 13 painting` cannot be printed while anything is lost or unmeasured", function()
		-- the plate's whole contract in one case: a count is a claim, and a claim
		-- may not be made over rows that were not measured
		local w = world(LANDSCAPE)
		local built = mount(
			w,
			ctxFor(w, function(path: string): any
				if path == "/HudScreen/Hud/Feed/FeedLine" then
					return false
				end
				return nil
			end)
		)
		built.steps.sampleProbe(built)
		local probe = built.report().paintProbe
		expect(#probe.lost > 0).toBe(true)
		expect(string.find(probe.plate, "painting", 1, true)).toBe(nil)
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

--[[ NM-H4a — THE SEQUENCE ON A TARGET THAT HOSTS THE SURFACES THE PHONE HOSTS.

	The describe above drives the director's sequence against a world holding the
	HUD and its own probe plate. The phone holds more: the gallery presents its
	showcase screen ON TOP of the scenario's (`examples/gallery/client/
	init.client.luau:961` after `:444`), and the ··· sink opens a fourth surface
	over both.

	That is not decoration. `park`/`adopt` move an instance between identities and
	`adopt` is never told which ROOT it is adopting for, so `screen_target` used
	the root of the last `create` anywhere on the adapter. With one surface that
	is always right. With several it is right by luck, and when the luck runs out
	a HUD node is re-parented into another surface's ScreenGui — same rect, same
	ZIndex, `Visible = true`, drawn somewhere else or not at all.

	So this block re-drives the same sequence with a second live surface above the
	HUD and asserts the thing the first block could not see: every HUD node is
	parented under the HUD's own root, and the painted tree still matches a fresh
	mount. ]]
describe("hud: the director's sequence with the gallery's other surfaces present", function()
	local function screenAbove(core: any, count: any): any
		local items = core:memo(function(use: any)
			local out = {}
			for i = 1, use(count) do
				table.insert(out, { id = `c{i}` })
			end
			return out
		end)
		return LuauUI.UI.Screen({
			id = "Showcase",
			children = {
				LuauUI.UI.VStack({
					id = "ShowcaseCol",
					children = {
						LuauUI.UI.ForEach({
							id = "ShowcaseItems",
							items = items,
							key = function(item: any)
								return item.id
							end,
							row = function(item: any)
								return LuauUI.UI.Text({ id = "ShowcaseText", text = item.id, textSize = 15 })
							end,
						}),
					},
				}),
			},
		})
	end

	-- every node whose path says one surface and whose parent says another
	local function misparented(adapter: any): { string }
		local out: { string } = {}
		for _, path in adapter.paths() do
			local own = string.match(path, "^/([^/]+)")
			local under = adapter.rootIdOf(path)
			if under ~= nil and own ~= nil and under ~= own then
				table.insert(out, `{path} under '{under}'`)
			end
		end
		return out
	end

	it("no HUD node is left parented under another surface's root", function()
		local w = world(PORTRAIT)
		local built = mount(w, ctxFor(w))
		local count = w.core:signal(0)
		w.presenter.present(screenAbove(w.core, count), {})
		w.presenter.refresh()

		--[[ THE OTHER SURFACE CHANGES WHILE THE HUD DOES, which is what a rotation
			does to a real gallery: both surfaces re-solve in the same frame and the
			last create on the adapter belongs to whichever ran last. ]]
		built.steps.openOverflow(built)
		w.presenter.refresh()
		built.steps.closeOverflow(built)
		w.presenter.refresh()

		for cycle = 1, 2 do
			rotate(w, LANDSCAPE)
			count:set(cycle * 2)
			w.presenter.refresh()
			built.steps.openUrlBar(built)
			w.presenter.refresh()
			built.steps.closeUrlBar(built)
			w.presenter.refresh()

			rotate(w, PORTRAIT)
			count:set(cycle * 2 + 1)
			w.presenter.refresh()
			built.steps.openUrlBar(built)
			w.presenter.refresh()
			built.steps.closeUrlBar(built)
			w.presenter.refresh()
		end
		rotate(w, LANDSCAPE)

		-- the sequence has to actually recycle, or this proves nothing
		expect(built.handle.controller.stats().recycled > 0).toBe(true)
		expect(table.concat(misparented(w.adapter), " ; ")).toBe("")
		built.dispose()
	end)

	it("...and the painted tree still equals a fresh mount's", function()
		local w = world(PORTRAIT)
		local built = mount(w, ctxFor(w))
		local count = w.core:signal(0)
		w.presenter.present(screenAbove(w.core, count), {})
		w.presenter.refresh()
		built.steps.openOverflow(built)
		w.presenter.refresh()
		built.steps.closeOverflow(built)
		w.presenter.refresh()
		for cycle = 1, 2 do
			rotate(w, LANDSCAPE)
			count:set(cycle * 2)
			w.presenter.refresh()
			built.steps.openUrlBar(built)
			w.presenter.refresh()
			built.steps.closeUrlBar(built)
			w.presenter.refresh()
			rotate(w, PORTRAIT)
			count:set(cycle * 2 + 1)
			w.presenter.refresh()
			built.steps.openUrlBar(built)
			w.presenter.refresh()
			built.steps.closeUrlBar(built)
			w.presenter.refresh()
		end
		rotate(w, LANDSCAPE)
		local driven = paintedTree(w)
		built.dispose()

		local fw = world(LANDSCAPE)
		local fresh = mount(fw, ctxFor(fw))
		local freshTree = paintedTree(fw)
		fresh.dispose()

		expect(#divergences(driven, freshTree)).toBe(0)
	end)
end)

--[[ NM-H4a round 2 — THE PLATE MUST SAY WHY A ROW LEFT THE DENOMINATOR.

	The director, on the phone, 2026-08-17: the plate read `13 of 14 rows wanted /
	skipped: Objective` in landscape, and rotating away and back restored
	`14 of 14`. A 36 624-state sweep over every viewport, both URL states, seven
	topbar positions, four text sizes and both strip flags never produced that
	reading — because every one of those states MOUNTED FRESH with a platform band
	present.

	The reading is what the model prints when `platformChrome.band` is nil.
	`Objective` sits behind `UI.When{ condition = riding }` and

	    riding = ride AND platformChrome.band ~= nil
	    band   = nil whenever coreSafeInsets.top == 0, or the topbar rect is
	             missing/zero (src/env/environment.luau:305-343)

	so a band the engine has not yet published — or has withdrawn — silently takes
	that row out of the denominator, and the not-riding rung spends a different top
	inset for the whole HUD. On a photograph that is indistinguishable from a
	healthy screen at a smaller size, which is the whole reason the plate now
	carries the INPUT beside the verdict. ]]
describe("hud: a row skipped by a PLATFORM fact says so on the plate", function()
	local function bandless(view: any): any
		local v = {}
		for k, value in view do
			v[k] = value
		end
		v.coreSafeInsets = { top = 0, right = 0, bottom = 0, left = 0 }
		return v
	end

	it("no platform band takes Objective out of the denominator — the phone's exact reading", function()
		local w = world(PORTRAIT)
		local built = mount(w, ctxFor(w))
		-- the band goes away UNDER the mounted surface, which is what an engine that
		-- owns the inset can do at any moment
		w.env:set("viewportRect", LANDSCAPE.viewportRect)
		w.env:set("coreSafeInsets", { top = 0, right = 0, bottom = 0, left = 0 })
		w.env:set("deviceSafeInsets", LANDSCAPE.deviceSafeInsets)
		w.presenter.refresh()
		local probe = built.report().paintProbe
		expect(probe.riding).toBe(false)
		expect(probe.expected).toBe(13)
		expect(#probe.skipped).toBe(1)
		expect(probe.skipped[1]).toBe("Objective")
		-- ...and the plate NAMES the reason, so a photograph carries it
		expect(string.find(probe.plate, "NOT RIDING", 1, true) ~= nil).toBe(true)
		expect(string.find(probe.plate, "no platform band", 1, true) ~= nil).toBe(true)
		expect(string.find(probe.plate, "coreTop=0", 1, true) ~= nil).toBe(true)
		built.dispose()
	end)

	it("the band coming back restores the row, which is the director's own recovery", function()
		local w = world(PORTRAIT)
		local built = mount(w, ctxFor(w))
		w.env:set("viewportRect", LANDSCAPE.viewportRect)
		w.env:set("coreSafeInsets", { top = 0, right = 0, bottom = 0, left = 0 })
		w.presenter.refresh()
		expect(built.report().paintProbe.expected).toBe(13)
		w.env:set("coreSafeInsets", LANDSCAPE.coreSafeInsets)
		w.env:set("topbarInset", LANDSCAPE.topbarInset)
		w.presenter.refresh()
		w.presenter.refresh()
		local probe = built.report().paintProbe
		expect(probe.riding).toBe(true)
		expect(probe.expected).toBe(14)
		expect(#probe.skipped).toBe(0)
		expect(string.find(probe.plate, "NOT RIDING", 1, true)).toBe(nil)
		built.dispose()
	end)

	it("a healthy band never prints the reason line", function()
		-- the negative control: the line must not be a decoration that is always on
		local w = world(LANDSCAPE)
		local built = mount(w, ctxFor(w))
		local probe = built.report().paintProbe
		expect(probe.riding).toBe(true)
		expect(string.find(probe.plate, "NOT RIDING", 1, true)).toBe(nil)
		expect(bandless(LANDSCAPE).coreSafeInsets.top).toBe(0)
		built.dispose()
	end)
end)
