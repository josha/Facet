--!strict
--[[ THE SHOWCASE SURFACE FOR ADR-0032's TWO CAPABILITIES —
	`examples/gallery/scenarios/nested_compositing.luau`.

	The nested-instance-tree round's brief (item 7) requires a showcase demo for
	the compositing capability, "registered in `examples/gallery/scenarios/init.luau`
	`ORDER` and `demo_picker.DEMOS`, and swept" — the same standing rule 4
	`tests/row_capabilities_scenario.spec.luau` and `tests/theme_authoring_scenario.spec.luau`
	already hold their own fixtures to, so this file asks the same three questions of
	this one: registered in the scenario registry's ORDER, offered in the demo
	picker's DEMOS, and named by the always-on overflow sweep's own SCENARIOS list
	(the third half neither of the other two files' own registration case can see —
	see `tests/gallery_demo_picker.spec.luau`'s "standing rule 4" header for why the
	direction matters).

	THEN THE TWO CAPABILITIES THEMSELVES, through the seams the rest of this round's
	suite already trusts:

	  * GROUP OPACITY — `tests/gallery_demo_picker.spec.luau`'s `canvas_group`
	    section reads `node.canvasGroupInstance.groupTransparency` off the fake
	    target rather than re-deriving it; the same instrument, on this fixture's
	    smaller two-plate pair.
	  * A CONTAINER THAT CARRIES ITS CONTENTS — `tests/instance_hosts.spec.luau`
	    drives `adapter.isHost(path)` / `adapter.hostOf(path)` directly; this file
	    asks the same registry the same question, through the real scenario/demo-
	    picker mount path (`hostMountFixture`'s shape in
	    `tests/gallery_demo_picker.spec.luau`) rather than a hand-built tree.

	WHAT THIS FILE DOES NOT CLAIM. Headless only. `adapter.isHost`/`hostOf` and
	`canvasGroupInstance` are FAKE-TARGET facts about the framework's own model —
	proven live already in `artifacts/nested-instance-tree/live-probes.md` §1/§3 for
	the mechanism this fixture exercises, but this file makes no claim about the
	real engine composing anything. A Studio capture of THIS surface (mounted from
	the picker, not the probe) is still owed before the round's device pass closes.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local fake_target = require("./lib/fake_target")
local l10n = require("./fixtures/a11y_l10n_fixtures")
local fs = require("@lune/fs")
local demo_picker = require("../examples/gallery/client/demo_picker") :: any
local module = require("../examples/gallery/scenarios/nested_compositing") :: any

local ROOT = "/NestedCompositing/Page"
local ONE_GROUP = ROOT .. "/Opacity/Panels/One/OneGroup"
local TWO_GROUPS = ROOT .. "/Opacity/Panels/Two/TwoGroups"
local CARRIED = ROOT .. "/Carry/Panels/Carries/Stage/Carried"
local STATIC = ROOT .. "/Carry/Panels/Alone/Stage/Static"

-- the showcase's own chrome reservation (init.client.luau's fixture branch
-- lays every demo out BELOW the picker's chip strip) — same constant and the
-- same call `tests/examples_gallery.spec.luau` and `tests/overflow_sweep.spec.luau`
-- use, so this file cannot silently measure a screen 62px taller than the real one
local SHOWCASE_CORE_TOP = 58
local SHOWCASE_TOP = demo_picker.barReservation(SHOWCASE_CORE_TOP, nil, 8)

local NARROW_PORTRAIT = { w = 320, h = 640 }
local NARROW_LANDSCAPE = { w = 640, h = 320 }
local DESKTOP = { w = 1232, h = 1067 }

local function fixtureWorld(view: any): any
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	env:set("coreSafeInsets", { top = SHOWCASE_TOP, bottom = 0, left = 0, right = 0 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local presenter = LuauUI.newPresenter(core, env, adapter, system)
	return { core = core, env = env, adapter = adapter, presenter = presenter, system = system }
end

-- exactly the call `examples/gallery/client/init.client.luau`'s `mountDemo`
-- makes for `kind == "fixture"` (see `tests/examples_gallery.spec.luau`'s
-- `mountFixture`, the same idiom this file follows)
local function mountFixture(w: any): any
	local built = module.build({
		LuauUI = LuauUI,
		core = w.core,
		env = w.env,
		actionSystem = w.system,
		presenter = w.presenter,
	})
	built.handle = w.presenter.present(built.screen, built.present)
	for _ = 1, 3 do
		w.presenter.refresh()
	end
	return built
end

local function expectNoDiagnostics(label: string, w: any, built: any)
	local findings = built.handle.controller.diagnostics()
	if #findings > 0 then
		local lines = {}
		for _, finding in findings do
			local node = w.adapter.node(finding.node)
			local rect = if node ~= nil and node.rect ~= nil
				then string.format(" [box %dx%d at %d,%d]", node.rect.w, node.rect.h, node.rect.x, node.rect.y)
				else ""
			table.insert(lines, `  {finding.node}{rect}\n      {finding.issue}`)
		end
		error(`{label}: the solver reports {#findings} diagnostic(s):\n{table.concat(lines, "\n")}`, 0)
	end
	expect(#findings).toBe(0)
end

-- path -> groupTransparency for every engine CanvasGroup the fake target was
-- asked to create — the same instrument `tests/gallery_demo_picker.spec.luau`'s
-- `canvas_group` section uses (`groupsOf`), read here rather than re-derived
local function groupsOf(w: any): { [string]: number }
	local out: { [string]: number } = {}
	for _, path in w.adapter.paths() do
		local node = w.adapter.node(path)
		if node ~= nil and node.canvasGroupInstance ~= nil then
			out[path] = node.canvasGroupInstance.groupTransparency
		end
	end
	return out
end

-- ===========================================================================
-- STANDING RULE 4: registered in scenarios/init.luau ORDER, demo_picker.DEMOS,
-- AND the always-on overflow sweep's own SCENARIOS list (the third half
-- neither of the first two registration checks can see — see
-- tests/gallery_demo_picker.spec.luau's own "standing rule 4" header).
-- ===========================================================================
describe("nested_compositing showcase: registered everywhere a player or a sweep would look", function()
	it("is in scenarios/init.luau ORDER, in demo_picker.DEMOS, and in the overflow sweep's SCENARIOS", function()
		local orderSource = fs.readFile("examples/gallery/scenarios/init.luau")
		local orderBlock = string.match(orderSource, "local ORDER = (%b{})")
		assert(orderBlock ~= nil, "scenarios/init.luau no longer has a `local ORDER = { ... }` block to read")
		local registered: { [string]: boolean } = {}
		local count = 0
		for name in string.gmatch(orderBlock :: string, '"([%w_]+)"') do
			registered[name] = true
			count += 1
		end
		assert(count > 20, `the ORDER parse found only {count} entries — the block shape changed`)

		local sweepSource = fs.readFile("tests/overflow_sweep.spec.luau")
		local sweepBlock = string.match(sweepSource, "local SCENARIOS = (%b{})")
		assert(sweepBlock ~= nil, "overflow_sweep.spec.luau no longer has a `local SCENARIOS = { ... }` block")

		local demo = demo_picker.find("nested-tree")

		local missing: { string } = {}
		if registered["nested_compositing"] ~= true then
			table.insert(missing, "scenarios/init.luau ORDER is missing 'nested_compositing'")
		end
		if demo == nil then
			table.insert(missing, "demo_picker.DEMOS is missing 'nested-tree'")
		elseif (demo :: any).module ~= "nested_compositing" then
			table.insert(missing, `demo 'nested-tree' names module '{(demo :: any).module}', not 'nested_compositing'`)
		end
		if string.find(sweepBlock :: string, '"nested_compositing"', 1, true) == nil then
			table.insert(missing, "overflow_sweep.spec.luau's SCENARIOS does not name 'nested_compositing'")
		end
		expect(table.concat(missing, "; ")).toBe("")
	end)

	it("names a module that actually exists on disk", function()
		expect(fs.isFile("examples/gallery/scenarios/nested_compositing.luau")).toBe(true)
	end)
end)

-- ===========================================================================
-- THE SURFACE BUILDS AND PAINTS AT THE SWEPT VIEWPORTS, at rest and mid-drive
-- (a fixture that only proves itself before anyone touches it is a screenshot,
-- not a control) — the same non-negotiable `tests/examples_gallery.spec.luau`
-- holds `card_rail`/`with_animation` to (docs/lessons/the-solver-already-told-you.md §13).
-- ===========================================================================
describe("nested_compositing showcase: builds and paints with ZERO solver diagnostics", function()
	it("at the narrow/wide swept viewports, at rest", function()
		for _, view in { NARROW_PORTRAIT, NARROW_LANDSCAPE, DESKTOP } do
			local w = fixtureWorld(view)
			local built = mountFixture(w)
			expectNoDiagnostics(`nested_compositing at {view.w}x{view.h}`, w, built)
			expect(w.core:lastError()).toBeNil()
			built.dispose()
		end
	end)

	it("...and still zero after the fade is driven and the carry pair is turned", function()
		for _, view in { NARROW_PORTRAIT, NARROW_LANDSCAPE, DESKTOP } do
			local w = fixtureWorld(view)
			local built = mountFixture(w)
			built.fade:set(15)
			built.turned:set(true)
			w.presenter.refresh()
			expectNoDiagnostics(`nested_compositing driven at {view.w}x{view.h}`, w, built)
			expect(w.core:lastError()).toBeNil()
			built.dispose()
		end
	end)

	it("its chrome copy survives a ~1.4x pseudo-localization without clipping", function()
		local original: { [string]: string } = {}
		for key, value in module.copy do
			original[key] = value
			module.copy[key] = l10n.pseudoLocalize(value)
		end
		local ok, err = pcall(function()
			for _, view in { NARROW_PORTRAIT, NARROW_LANDSCAPE } do
				local w = fixtureWorld(view)
				local built = mountFixture(w)
				expectNoDiagnostics(`nested_compositing pseudo-localized at {view.w}x{view.h}`, w, built)
				built.dispose()
			end
		end)
		for key, value in original do
			module.copy[key] = value
		end
		if not ok then
			error(err, 0)
		end
		-- the strings really did come back, or every other case in this file is a lie
		expect(string.find(module.copy.title, "a real parent", 1, true) ~= nil).toBe(true)
	end)
end)

-- ===========================================================================
-- (a) GROUP OPACITY: one panel composites its two plates ONCE, the other
-- composites them TWICE — the same instrument
-- tests/gallery_demo_picker.spec.luau's `canvas_group` section uses.
-- ===========================================================================
describe("nested_compositing showcase: group opacity composites once, or twice", function()
	it("the left panel is ONE engine CanvasGroup and the right panel is two", function()
		local w = fixtureWorld(DESKTOP)
		local built = mountFixture(w)
		local groups = groupsOf(w)
		-- the fade is on the STACK on the left: one buffer over both plates
		expect(groups[ONE_GROUP]).never().toBeNil()
		-- ...and on each PLATE on the right: the stack itself is not a group...
		expect(groups[TWO_GROUPS]).toBeNil()
		-- ...while each of its two plates is
		expect(groups[TWO_GROUPS .. "/Back"]).never().toBeNil()
		expect(groups[TWO_GROUPS .. "/Front"]).never().toBeNil()
		expect(w.core:lastError()).toBeNil()
		built.dispose()
	end)

	it("every one of them carries the fade the slider's own signal drives, live", function()
		local w = fixtureWorld(DESKTOP)
		local built = mountFixture(w)
		-- the fixture opens at FADE_DEFAULT = 40, so transparency is 0.6
		expect(groupsOf(w)[ONE_GROUP]).toBe(0.6)
		built.fade:set(100)
		w.presenter.refresh()
		local opaque = groupsOf(w)
		for path, transparency in opaque do
			expect(`{path} at fade 100 -> {transparency}`).toBe(`{path} at fade 100 -> 0`)
		end
		built.fade:set(15)
		w.presenter.refresh()
		local faded = groupsOf(w)[TWO_GROUPS .. "/Front"]
		expect(math.abs((faded :: number) - 0.85) < 0.0001).toBe(true)
		expect(w.core:lastError()).toBeNil()
		built.dispose()
	end)
end)

-- ===========================================================================
-- (b) A CONTAINER THAT CARRIES ITS CONTENTS: the carrying panel's container is
-- a real instance host and its marker parents INSIDE it; the alone panel's
-- container is not, and its marker's nearest host is the page's own
-- ScrollView (a clip host by construction, ADR-0032 Decision 1) rather than
-- itself. The same registry `tests/instance_hosts.spec.luau` drives directly,
-- asked here through the real scenario/demo-picker mount path.
--
-- THIS IS THE NAMED CASE THIS ROUND'S MUTATION PROOF TARGETS — see the report:
-- removing `rotation`/`scale` from the "Carried" container in
-- `examples/gallery/scenarios/nested_compositing.luau` reddens the first
-- assertion below by name.
-- ===========================================================================
describe("nested_compositing showcase: a real parent, or not", function()
	it("the carrying panel's container is registered as a real instance host, and the alone panel's is not", function()
		local w = fixtureWorld(DESKTOP)
		local built = mountFixture(w)
		expect(w.adapter.isHost(CARRIED)).toBe(true)
		expect(w.adapter.isHost(STATIC)).toBe(false)
		expect(w.core:lastError()).toBeNil()
		built.dispose()
	end)

	it(
		"the carried marker parents INSIDE its container; the alone marker's nearest host is the page scroller",
		function()
			local w = fixtureWorld(DESKTOP)
			local built = mountFixture(w)
			local carriedHost = w.adapter.hostOf(CARRIED .. "/Marker")
			expect(carriedHost).never().toBeNil()
			expect((carriedHost :: any).path).toBe(CARRIED)
			-- a plain move-boundary host, not a group: no offscreen buffer was spent
			-- to compose the carry pair's rotation and scale (ADR-0032 D2/D4)
			expect((carriedHost :: any).crops).toBe(false)

			local aloneHost = w.adapter.hostOf(STATIC .. "/Marker")
			expect(aloneHost).never().toBeNil()
			-- NOT the "Static" container itself — it never registered — but the
			-- page's own ScrollView, the nearest ancestor that did
			expect((aloneHost :: any).path).toBe(ROOT)
			expect((aloneHost :: any).path).never().toBe(STATIC)
			expect(w.core:lastError()).toBeNil()
			built.dispose()
		end
	)

	it("turning the pair moves the SAME two driver signals both panels read", function()
		local w = fixtureWorld(DESKTOP)
		local built = mountFixture(w)
		expect(built.turned:get()).toBe(false)
		expect(built.carryRotation:get()).toBe(0)
		expect(built.carryScale:get()).toBe(1)
		built.steps.toggleTurn()
		w.presenter.refresh()
		expect(built.turned:get()).toBe(true)
		expect(built.carryRotation:get()).toBe(30)
		expect(built.carryScale:get()).toBe(1.5)
		-- registration itself does not depend on the driven VALUE — the prop KEY
		-- being authored is what registers the host (ADR-0032 D2/D4), so turning
		-- the pair back to rest must not un-register the carrying container
		built.steps.toggleTurn()
		w.presenter.refresh()
		expect(w.adapter.isHost(CARRIED)).toBe(true)
		expect(w.core:lastError()).toBeNil()
		built.dispose()
	end)
end)
