--!strict
-- THEME SCENARIO, HEADLESS HALF (stage theme-packages-and-skinning).
-- The Studio scenario proves the PAINT; this proves that every step is
-- drivable, that a swap re-solves a mounted screen without rebuilding it, and
-- that each failure fixture degrades the way its acceptance row claims — none
-- of which needs an engine, and all of which would otherwise only ever be
-- checked by a human looking at a screenshot.
--
-- The runner-owned engine seams (themePackages, themeChrome, themeController,
-- geometry, nativeStyle) are stubbed here exactly as the runner shapes them,
-- so the scenario module under test is the same file Studio loads.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local fake_target = require("./lib/fake_target")
local chrome_slots = require("../src/tokens/chrome_slots")

local scenario = require("../examples/gallery/scenarios/theme_authoring") :: any

local PACKAGES = {
	classic_desktop = require("../examples/themes/classic_desktop"),
	glossy_mobile = require("../examples/themes/glossy_mobile"),
	scifi_hud = require("../examples/themes/scifi_hud"),
	fantasy_parchment_stub = require("../examples/themes/fantasy_parchment_stub"),
	fantasy_parchment = require("../examples/themes/fantasy_parchment"),
	custom_control = require("../examples/themes/custom_control"),
	-- the rung-3 worked example (ADR-0020 R8): a CONTROL module, not a package
	ornate_gauge = require("../examples/themes/ornate_gauge"),
	-- P5's reference packages, so the steps that install them are driven
	-- headlessly and not only in a Studio session
	fantasy_ornate = require("../examples/themes/fantasy_ornate"),
	pixel_quest = require("../examples/themes/pixel_quest"),
	glossy_touch = require("../examples/themes/glossy_touch"),
	compact_pointer = require("../examples/themes/compact_pointer"),
}

local function makeWorld(flags: any?)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 900, h = 760 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local presenter = Facet.newPresenter(core, env, adapter, system)

	-- the adapter's decoration surface, stubbed over the SAME pure state
	-- machine screen_target drives, so the census here is the census there
	local chromeState = chrome_slots.newState(nil)
	local ctx: any
	ctx = {
		Facet = Facet,
		core = core,
		env = env,
		adapter = adapter,
		presenter = presenter,
		actionSystem = system,
		record = function() end,
		flags = flags or {},
		themePackages = PACKAGES,
		themeChrome = {
			setPackage = function(package: any?): boolean
				local changed = chromeState.setPackage(package)
				if changed then
					-- the adapter re-materializes; headlessly, re-derive the
					-- census from what the fixture actually rendered
					for _, path in adapter.paths() do
						local node = adapter.node(path)
						local slot = chrome_slots.classify({
							class = node.class,
							surface = node.props.surface,
							hasSelection = node.props.selected ~= nil,
						})
						if slot ~= nil and chromeState.planFor(slot) ~= nil then
							chromeState.noteCreated(slot)
						end
					end
				end
				return changed
			end,
			census = function()
				return chromeState.census()
			end,
			setAssetLoaded = function(name: string, ok: boolean): boolean
				return chromeState.setAssetLoaded(name, ok)
			end,
			assetsToPreload = function(policy: string)
				return chrome_slots.assetsToPreload(chromeState.package(), policy)
			end,
			-- the decode judgement is an INSTANCE reading (RS-A16-D5): the headless
			-- target owns no ImageLabels, so the seam reports `unsupported` exactly
			-- as the runner does for an adapter that lacks the method — and the step
			-- has to stay drivable through it
			artJudgement = function(): any
				return { unsupported = true }
			end,
		},
		themeController = function()
			return nil -- package-2 seam: absent, and every step must survive it
		end,
		geometry = function(paths: { string })
			local out: any = {}
			for _, path in paths do
				local node = adapter.node(path)
				if node ~= nil and node.rect ~= nil then
					out[path] = { x = node.rect.x, y = node.rect.y, w = node.rect.w, h = node.rect.h }
				end
			end
			return out
		end,
		nativeStyle = {
			styledOf = function()
				return nil
			end,
			-- the runner's Instance-subtree dump has no headless counterpart (there
			-- are no Instances); the fake node is what a headless caller can see, and
			-- reporting `missing` for a path that never mounted is the same answer
			-- the real one gives
			dumpNode = function(path: string): any
				local node = adapter.node(path)
				return if node == nil then { missing = path } else { path = path, class = node.class }
			end,
			mountIdentity = function()
				local ids: any = {}
				for _, path in adapter.paths() do
					ids[path] = tostring(adapter.node(path))
				end
				return ids
			end,
			info = function()
				return { active = false }
			end,
		},
	}
	local built = scenario.build(ctx)
	local handle = presenter.present(built.screen, built.present)
	presenter.refresh()
	return {
		ctx = ctx,
		built = built,
		adapter = adapter,
		presenter = presenter,
		core = core,
		handle = handle,
		env = env,
	}
end

local function teardown(world: any)
	world.presenter.dismiss(world.handle)
	if world.built.dispose ~= nil then
		world.built.dispose()
	end
end

local SAVE = "/AdaptiveScreen/Actions/ActionsRow/Save"

describe("theme_authoring scenario: it mounts the shared fixture and exposes every step", function()
	it("mounts the all-controls fixture through the real presenter", function()
		local world = makeWorld()
		expect(world.adapter.node("/AdaptiveScreen") ~= nil).toBe(true)
		expect(world.adapter.node(SAVE) ~= nil).toBe(true)
		expect(world.adapter.node("/AdaptiveScreen/BodyScroll/Body/Settings/Volume") ~= nil).toBe(true)
		expect(world.core:lastError()).toBeNil()
		teardown(world)
	end)

	it("registers the steps the acceptance rows drive, by name", function()
		local world = makeWorld()
		for _, name in
			{
				"installPackage",
				"swapTheme",
				"swapPackage",
				"editMetricLive",
				"exportDump",
				"failMissingAsset",
				"failMissingFont",
				"failIncompatible",
				"inspect",
				"customControl",
				-- rich-skinning-v2 image value displays (RS-A5, RS-A6)
				"presentValueFixture",
				"dismissValueFixture",
				"barSweep",
				"barProbe",
				"setToggle",
				"toggleProbe",
				"stepperProbe",
				-- the decode judgement beside the failure ledger (RS-A16-D5)
				"artJudgement",
				"failAsset",
				"recoverAsset",
				-- rich-skinning-v2 rung 3 (RS-A15)
				"presentGaugeFixture",
				"dismissGaugeFixture",
				"gaugeProbe",
				"gaugeCoverage",
				-- the circle Button (feature round 2026-07-26)
				"presentCircleFixture",
				"dismissCircleFixture",
				"circleProbe",
			}
		do
			expect(type(world.built.steps[name])).toBe("function")
		end
		teardown(world)
	end)

	it("the decode judgement step reports the ledger it explains, and survives a headless target", function()
		-- RS-A16-D5. The Studio row asserts the NUMBERS (undecodedJudgeable = 0 on a
		-- phone under fantasy-ornate); what a headless run can prove is that the step
		-- exists, pairs the judgement with the census that condemned the assets, and
		-- degrades instead of erroring where there are no Instances to judge.
		local world = makeWorld()
		world.built.steps.installPackage(nil, "fantasy_ornate")
		local read = world.built.steps.artJudgement()
		expect(read.judgement.unsupported).toBe(true)
		expect(#read.census.failedAssets).toBe(0)
		-- an asset the app's provider condemns shows up in the paired census, which
		-- is the half of the instrument that is not an instance reading
		world.built.steps.failAsset(nil, "ornate_panel_frame")
		local after = world.built.steps.artJudgement()
		expect(after.census.failedAssets[1]).toBe("ornate_panel_frame")
		expect(after.census.fallbackSlots[1]).toBe("panel")
		world.built.steps.recoverAsset(nil, "ornate_panel_frame")
		expect(#world.built.steps.artJudgement().census.failedAssets).toBe(0)
		teardown(world)
	end)

	it("the value fixture mounts the three value displays and sweeps a percent", function()
		-- headless half of RS-A5/RS-A6: the STEPS are drivable and the sweep moves
		-- the solved fill while the track stays put. The paint is Studio's to prove
		-- — this is the part a screenshot cannot show and a green suite must.
		local world = makeWorld()
		local presented = world.built.steps.presentValueFixture()
		expect(presented.presented).toBe(true)
		expect(presented.paths.window).toBe("/ValueProbe/Load/Bar/Fill/FacetBarWindow")
		local swept = world.built.steps.barSweep(nil, "0,0.5,1")
		expect(#swept.stops).toBe(3)
		local trackW = swept.stops[1].nodes.bar.geometry.w
		expect(trackW > 0).toBe(true)
		for index, want in { 0, 0.5, 1 } do
			local stop = swept.stops[index]
			expect(stop.fraction).toBe(want)
			-- THE TRACK NEVER MOVES; only the window (the solved fill rect) does.
			-- The fixture omits the readout for exactly this reason: with one, the
			-- text node's reserved width changes between "0", "0.5" and "1" and the
			-- fill-weight track absorbs the difference, so a percent sweep would be
			-- measuring text reflow instead of the clip.
			expect(stop.nodes.bar.geometry.w).toBe(trackW)
			expect(stop.nodes.fill.geometry.w).toBe(math.floor(trackW * want + 0.5))
		end
		local flipped = world.built.steps.setToggle(nil, "on")
		expect(flipped.on).toBe(true)
		expect(world.built.steps.setToggle(nil, "off").on).toBe(false)
		expect(world.built.steps.stepperProbe().dec.path).toBe("/ValueProbe/Qty/Dec")
		world.built.steps.dismissValueFixture()
		teardown(world)
	end)

	it("the rung-3 gauge mounts, checks both ways, and re-themes without a rebuild", function()
		-- headless half of RS-A15. The Studio session proves the PAINT; this
		-- proves the three things a capture cannot: that a control the framework
		-- knows nothing about mounts through the public primitives, that its
		-- conformance answer differs between a covering and an uncovering
		-- package, and that a package swap re-sizes it through a reactive prop
		-- with the SAME node object — a re-solve, never a remount.
		local world = makeWorld()
		world.built.steps.installPackage(nil, "fantasy_ornate")
		world.presenter.refresh()

		local presented = world.built.steps.presentGaugeFixture()
		expect(presented.presented).toBe(true)
		expect(presented.builtUnder).toBe("fantasy-ornate")
		local dialPath = "/GaugeProbe/Gauge/GaugeDial"
		local dial = world.adapter.node(dialPath)
		expect(dial ~= nil).toBe(true)
		-- the control's OWN art is on its own nodes; no theme supplied it
		local face = world.adapter.node(dialPath .. "/GaugeFace")
		expect(face.class).toBe("Image")
		expect(face.props.image).toBe(require("../examples/themes/ornate_gauge").ART.face)

		local first = world.built.steps.gaugeProbe()
		expect(first.package).toBe("fantasy-ornate")
		expect(first.resolved.usedFallback.size).toBe(false)
		local ornateHeight = first.geometry[dialPath].h
		expect(ornateHeight).toBe(first.resolved.height)

		-- SWAP THE PACKAGE. The gauge is not rebuilt: the step writes the new
		-- resolved height into the reactive signal it was built with.
		world.built.steps.installPackage(nil, "pixel_quest")
		world.presenter.refresh()
		local second = world.built.steps.gaugeProbe()
		expect(second.package).toBe("pixel-quest")
		expect(second.rebuilt).toBe(false)
		expect(second.geometry[dialPath].h).toBe(second.resolved.height)
		expect(second.resolved.height ~= first.resolved.height).toBe(true)
		-- the same node object survived the swap
		expect(world.adapter.node(dialPath)).toBe(dial)
		expect(world.core:lastError()).toBeNil()

		-- CONFORMANCE, BOTH DIRECTIONS, from the framework gate
		local coverage = world.built.steps.gaugeCoverage()
		expect(coverage.covered.ok).toBe(true)
		expect(#coverage.covered.covered).toBe(3)
		expect(coverage.uncovered.ok).toBe(false)
		expect(#coverage.uncovered.missing).toBe(3)
		expect(coverage.frameworkCovered.ok).toBe(coverage.covered.ok)
		expect(coverage.frameworkUncovered.ok).toBe(coverage.uncovered.ok)

		-- RUNG 2 on the same screen: the per-view gradient is materialized once,
		-- keeps the VIEW's values, and the package swap above neither clobbered
		-- nor duplicated it (charter cap 11; ADR-0020 R8 composition)
		local washPath = "/GaugeProbe/WashCard"
		local wash = world.adapter.node(washPath)
		expect(wash ~= nil).toBe(true)
		expect(wash.props.gradient ~= nil).toBe(true)
		expect(wash.gradientInstance ~= nil).toBe(true)
		expect(wash.gradientInstance.className).toBe("UIGradient")
		expect(wash.gradientInstance.creations).toBe(1)
		expect(wash.gradientInstance.rotation).toBe(90)
		-- the theme still owns this node's SURFACE; only the wash is the view's
		expect(wash.props.surface).toBe("raised")

		world.built.steps.dismissGaugeFixture()
		expect(world.adapter.node(dialPath)).toBeNil()
		expect(world.adapter.node(washPath)).toBeNil()
		teardown(world)
	end)

	it("the circle fixture mounts six discs, squares every one, and re-sizes on a metric swap", function()
		-- headless half of the circle-button live proof. What a capture CANNOT
		-- show is that each disc's box is exactly square, that the diameter came
		-- from the theme's own metric, and that an authored axis drove the other
		-- one; what a headless run cannot show is the pill and the rim, which is
		-- the Studio session's job (RS-CIRCLE_desktop_*.png).
		local world = makeWorld()
		world.built.steps.installPackage(nil, "classic_desktop")
		world.presenter.refresh()

		local presented = world.built.steps.presentCircleFixture()
		expect(presented.presented).toBe(true)
		expect(presented.paths.dots).toBe("/CircleProbe/Row/Dots")

		local flat = world.built.steps.circleProbe()
		expect(flat.package).toBe("classic-desktop")
		expect(flat.presented).toBe(true)
		for _, name in { "dots", "close", "menu", "wide", "accent" } do
			expect(flat.nodes[name].square).toBe(true)
		end
		-- FOUR of the five take the metric; the fifth authored its own axis and
		-- the solver owed it the matching height
		for _, name in { "dots", "close", "menu", "accent" } do
			expect(flat.nodes[name].box.w).toBe(flat.diameterMetric)
		end
		expect(flat.nodes.wide.box.w).toBe(72)
		expect(flat.nodes.wide.box.h).toBe(72)
		-- the rectangle beside them is NOT square: the A/B control
		expect(flat.nodes.rect.square).toBe(false)

		-- THE ICON PATH. `close` has art in Fantasy Ornate and `menu` has none in
		-- any reference package, so the same declaration resolves two ways — and
		-- the drawn text is the framework glyph either way, never the label.
		local dots = world.adapter.node("/CircleProbe/Row/Dots")
		expect(dots.props.label).toBe("...")
		expect(world.adapter.node("/CircleProbe/Row/Close").props.label).toBe("x")
		expect(world.adapter.node("/CircleProbe/Row/Menu").props.label).toBe("=")
		expect(world.adapter.node("/CircleProbe/Row/Close").props.icon).toBe("close")

		-- A PACKAGE SWAP re-solves every disc against the NEW snapshot with no
		-- rebuild — the same node object survives. Both reference packages happen
		-- to sit on the 44 px floor, so the number here is stable ON PURPOSE:
		-- what this proves is that the disc re-reads the metric and keeps its
		-- identity. That the metric MOVES the diameter is proven against an
		-- authored `controls.button.height` in tests/button_shape.spec.luau.
		world.built.steps.installPackage(nil, "glossy_mobile")
		world.presenter.refresh()
		local glossy = world.built.steps.circleProbe()
		expect(glossy.nodes.dots.square).toBe(true)
		expect(glossy.nodes.dots.box.w).toBe(glossy.diameterMetric)
		expect(world.adapter.node("/CircleProbe/Row/Dots")).toBe(dots)
		expect(world.core:lastError()).toBeNil()

		world.built.steps.dismissCircleFixture()
		expect(world.adapter.node("/CircleProbe/Row/Dots")).toBeNil()
		teardown(world)
	end)

	it("is registered in the scenario registry", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("examples/gallery/scenarios/init.luau")
		expect(string.find(source, '"theme_authoring"', 1, true) ~= nil).toBe(true)
		local project = fs.readFile("examples/gallery.project.json")
		expect(string.find(project, "FacetThemes", 1, true) ~= nil).toBe(true)
	end)
end)

describe("theme_authoring scenario: installing and swapping", function()
	it("installing a package re-solves the mounted screen instead of rebuilding it", function()
		local world = makeWorld()
		local before = world.adapter.node(SAVE)
		local beforeHeight = before.rect.h
		local result = world.built.steps.installPackage()
		expect(result.ok).toBe(true)
		expect(result.applied.package).toBe("fantasy-parchment-stub")
		world.presenter.refresh()
		-- SAME node object: a re-solve, never a remount
		expect(world.adapter.node(SAVE)).toBe(before)
		expect(world.adapter.node(SAVE).rect.h ~= beforeHeight).toBe(true)
		expect(world.core:lastError()).toBeNil()
		teardown(world)
	end)

	it("a palette-only theme swap moves paint and no geometry, and churns no decoration", function()
		local world = makeWorld()
		world.built.steps.installFlat()
		world.presenter.refresh()
		local before = world.ctx.geometry({ SAVE })[SAVE]
		local result = world.built.steps.swapTheme()
		world.presenter.refresh()
		expect(result.before.theme ~= result.after.theme).toBe(true)
		expect(result.after.controlHeight).toBe(result.before.controlHeight)
		expect(result.applied.chromeChanged).toBe(false)
		local after = world.ctx.geometry({ SAVE })[SAVE]
		expect(after.h).toBe(before.h)
		expect(after.w).toBe(before.w)
		teardown(world)
	end)

	it("swapping packages cycles through the corpus and reports the new identity every time", function()
		local world = makeWorld()
		local seen: { [string]: boolean } = {}
		for _ = 1, 4 do
			local result = world.built.steps.swapPackage()
			expect(result.ok).toBe(true)
			seen[result.applied.package] = true
		end
		expect(seen["classic-desktop"]).toBe(true)
		expect(seen["glossy-mobile"]).toBe(true)
		expect(seen["scifi-hud"]).toBe(true)
		teardown(world)
	end)

	it("an ornate package pays a census and a flat one pays nothing", function()
		local world = makeWorld()
		world.built.steps.installFlat()
		expect(world.built.steps.inspect().census.created).toBe(0)
		world.built.steps.installPackage()
		local census = world.built.steps.inspect().census
		expect(census.created).toBeGreaterThan(0)
		expect(census.perSlot.divider).toBeNil()
		teardown(world)
	end)

	it("the operator's chosen package opens the fixture before any step runs", function()
		local world = makeWorld({ themePackage = "scifi_hud" })
		expect(world.built.report().snapshot.packageId).toBe("scifi-hud")
		expect(world.built.report().snapshot.radii).toBeNil() -- the report carries what it says it carries
		teardown(world)
	end)
end)

describe("theme_authoring scenario: live authoring and export degrade without the controller", function()
	it("editMetricLive drives the same transaction and says which path it took", function()
		local world = makeWorld()
		local result = world.built.steps.editMetricLive()
		expect(result.via).toBe("override-fallback")
		expect(result.controller).toBe("absent")
		expect(result.spaceM).toBe(32)
		world.built.steps.restoreMetric()
		expect(world.env:get("themeMetrics"):get().space.m).toBe(Facet.themes.neutral().space.m)
		teardown(world)
	end)

	it("exportDump falls back to the committed package data and names the missing seam", function()
		local world = makeWorld()
		local dump = world.built.steps.exportDump()
		expect(dump.via).toBe("package-data")
		expect(dump.controller).toBe("absent")
		expect(dump.identity.id).toBe("studio-neutral")
		expect(dump.chrome.panel.kind).toBe("native")
		teardown(world)
	end)
end)

describe("theme_authoring scenario: the failure fixtures", function()
	it("a missing asset flips the fallback and leaves focus and hit geometry alone", function()
		local world = makeWorld()
		-- baseline under the WORKING package: the proposition is that losing the
		-- art changes nothing but paint, so the comparison has to be against the
		-- same package's geometry, not against the theme it replaced
		world.built.steps.installPackage()
		world.presenter.refresh()
		world.presenter.focus.focusOn(SAVE)
		local before = world.ctx.geometry({ SAVE })[SAVE]
		local result = world.built.steps.failMissingAsset()
		expect(result.installed.ok).toBe(true)
		expect(result.failureReported).toBe(true)
		expect(result.census.fallbackSlots[1]).toBe("panel")
		expect(result.focusPath).toBe(SAVE)
		expect(result.geometry[SAVE].w).toBe(before.w)
		expect(result.geometry[SAVE].h).toBe(before.h)
		-- and recovery unflips exactly once
		local recovered = world.built.steps.recoverMissingAsset()
		expect(recovered.recoveryReported).toBe(true)
		expect(#recovered.census.fallbackSlots).toBe(0)
		expect(world.built.steps.recoverMissingAsset().recoveryReported).toBe(false)
		teardown(world)
	end)

	it("a missing font degrades conservatively: boxes grow, nothing shrinks", function()
		local world = makeWorld()
		world.built.steps.installPackage() -- the same package with a KNOWN font
		world.presenter.refresh()
		local result = world.built.steps.failMissingFont()
		expect(result.installed.ok).toBe(true)
		expect(string.find(result.fontKey, "NotAShippedFamily", 1, true) ~= nil).toBe(true)
		for path, after in result.geometryAfter do
			local before = result.geometryBefore[path]
			if before ~= nil then
				-- a conservative measurement may reserve MORE room; it may never
				-- reserve less, because less is the shape of a clip
				expect(after.w).toBeGreaterThanOrEqual(before.w - 1)
			end
		end
		expect(world.core:lastError()).toBeNil()
		teardown(world)
	end)

	it("an incompatible package is refused and the screen stays mounted and usable", function()
		local world = makeWorld()
		world.built.steps.installFlat()
		local result = world.built.steps.failIncompatible()
		expect(result.result.ok).toBe(false)
		expect(result.result.rejected).toBe(true)
		expect(result.activeAfter).toBe(result.activeBefore) -- the good package still runs
		expect(result.stillFocusable).toBeTruthy()
		expect(result.geometry[SAVE] ~= nil).toBe(true)
		local named = false
		for _, entry in result.result.errors do
			named = named or entry.class == "schemaVersion"
		end
		expect(named).toBe(true)
		expect(world.core:lastError()).toBeNil()
		teardown(world)
	end)

	it("a package name that does not exist reports the names that do", function()
		local world = makeWorld({ themePackage = "not_a_package" })
		local inspect = world.built.steps.inspect()
		expect(string.find(inspect.lastError, "no theme package module", 1, true) ~= nil).toBe(true)
		expect(string.find(inspect.lastError, "classic_desktop", 1, true) ~= nil).toBe(true)
		expect(inspect.identity.packageId).toBe("studio-neutral") -- unchanged
		teardown(world)
	end)
end)

describe("theme_authoring scenario: the report pairs the evidence", function()
	it("carries geometry, snapshot identity, census, focus, mount identity and the chrome probe together", function()
		local world = makeWorld()
		world.built.steps.installPackage()
		world.presenter.focus.focusOn(SAVE)
		local report = world.built.report()
		expect(report.snapshot.packageId).toBe("fantasy-parchment-stub")
		expect(report.snapshot.stamp ~= nil).toBe(true)
		expect(report.geometry[SAVE] ~= nil).toBe(true)
		expect(report.census.created).toBeGreaterThan(0)
		expect(report.focusPath).toBe(SAVE)
		expect(next(report.mountIdentity) ~= nil).toBe(true)
		expect(type(report.chromeProbe)).toBe("table")
		expect(report.controller).toBe("absent")
		-- the fixture's own report rides along, so one call answers both
		expect(report.fixture ~= nil).toBe(true)
		expect(report.fixture.state ~= nil).toBe(true)
		teardown(world)
	end)

	it("survives a package whose recipes carry PER-STATE asset maps", function()
		-- LIVE-FOUND (P5, 2026-07-25): `chromeProbe` indexed `package.assets` with
		-- `recipe.asset`, which ADR-0020 R2 made legal as a TABLE. Under Fantasy
		-- Ornate — whose toggle, knob and stepper recipes all carry state maps —
		-- the lookup returned nil and `report()` threw, so the one step that pairs
		-- geometry with identity could not be called on the centerpiece package at
		-- all. The probe now reads the DEFAULT state of a map.
		local world = makeWorld()
		world.built.steps.installOrnate()
		local report = world.built.report()
		expect(report.snapshot.packageId).toBe("fantasy-ornate")
		local expected = report.chromeProbe.expectedBySlot
		-- a bare-string recipe still resolves its one asset...
		expect(expected.barTrack.Image).toBe("rbxassetid://92904178783883")
		-- ...and a per-state one resolves the DEFAULT picture, named
		expect(expected.toggleTrack.asset).toBe("ornate_toggle_track_off")
		expect(expected.toggleTrack.Image).toBe("rbxassetid://79434491980979")
		expect(expected.stepperPlate.asset).toBe("ornate_stepper_plate_default")
		teardown(world)
	end)

	it("the snapshot identity reports the chrome insets the solver actually used", function()
		local world = makeWorld()
		world.built.steps.installPackage()
		local report = world.built.report()
		expect(report.snapshot.chromeInsets.panel.top).toBe(18)
		world.built.steps.installFlat()
		-- flat: every slot answers, and every answer is zero (the table used to be
		-- absent entirely; see snapshot.resolve on why every slot now publishes one)
		expect(world.built.report().snapshot.chromeInsets.panel.top).toBe(0)
		expect(world.built.report().snapshot.chromeInsets.control.left).toBe(0)
		teardown(world)
	end)

	it("the custom-control step answers both directions and the active resolution", function()
		local world = makeWorld()
		world.built.steps.installGlossy()
		local result = world.built.steps.customControl()
		expect(result.covered.ok).toBe(true)
		expect(result.uncovered.ok).toBe(false)
		expect(result.resolvedUnderActive.usedFallback.size).toBe(false)
		expect(#result.needs).toBe(2)
		teardown(world)
	end)
end)
