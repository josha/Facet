--!strict
--[[ THE SHOWCASE SURFACE FOR `newTabView` — `examples/gallery/scenarios/tab_view.luau`.

	`tests/tab_view.spec.luau` proves the CONSTRUCT against hand-built worlds.
	This file proves the thing a person holding a phone actually opens, which D5
	shipped without: `r2`'s two live levels on one screen, both printing the
	placement they resolved; an eviction that is a COUNT rather than a claim; a
	strip that is meant to overflow; and a badge that keeps climbing on a tab
	whose content no longer exists.

	THE THREE CASES THAT CARRY IT, because each is invisible in a screenshot and
	each is a defect the construct could ship with while looking perfect:

	  · THE INNER LEVEL MUST NOT CLAIM THE APP-LEVEL PLACEMENT. Both bars would
	    still be on screen if it did — they would just be in the same home, the
	    inner one winning because it is painted later. The desktop case is the
	    sharp one: the outer becomes a rail and the inner is STILL a top band.
	  · EVICTION IS A REAL DISPOSAL, NOT A HIDE, and a hide paints identically.
	    The fixture counts factory invocations, so leaving and returning to a tab
	    moves a number on the screen; the framework's own `contentEvictions` has
	    to move with it or one of the two is lying.
	  · A `fill` STRIP CANNOT OVERFLOW. The page bar hugs on purpose, so this is
	    the one surface in the gallery where the strip really does measure wider
	    than its band — which is the only state in which "scroll the selection
	    into view" means anything at all.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local fake_target = require("./lib/fake_target")
local focus_map = require("../src/present/focus_map")
local demo_picker = require("../examples/gallery/client/demo_picker") :: any
local module = require("../examples/gallery/scenarios/tab_view") :: any

local PHONE = { w = 320, h = 640 }
local LANDSCAPE = { w = 640, h = 320 }
local DESKTOP = { w = 1200, h = 900 }

local APP = "/TabViewDemo/Root/App"
local BOTTOM = `{APP}/BottomHome/then/BottomBand/Strip/Indicator/Options`
-- the app tab's whole body IS the page-level TabView, so there is no wrapper
-- between the two levels; everything the fixture says about the pair lives one
-- level further down, inside the selected PAGE's own scroller
local PAGE = `{APP}/Content/Tab-pages/then/Page`
local PAGE_BAND = `{PAGE}/TopHome/then/TopBandCenter/TopBand`
local PAGE_OPTS = `{PAGE_BAND}/Strip/Indicator/Options`
local function pageBody(tab: string): string
	return `{PAGE}/Content/Tab-{tab}/then/PageBody`
end

local function world(view: { w: number, h: number }, opts: any?)
	local options = opts or {}
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	if options.preferredInput ~= nil then
		env:set("preferredInput", options.preferredInput)
	end
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local built = module.build({
		Facet = Facet,
		core = core,
		env = env,
		adapter = adapter,
		presenter = pres,
		actionSystem = system,
	})
	built.handle = pres.present(built.screen, built.present)
	local w: any = { core = core, env = env, adapter = adapter, pres = pres, system = system, built = built }
	function w.settle(frames: number?)
		for _ = 1, frames or 6 do
			pres.tick(1 / 60)
			pres.refresh()
		end
	end
	function w.text(path: string): string?
		local facts = built.handle.controller.textAt()[path]
		return if facts ~= nil then facts.text else nil
	end
	w.settle()
	return w
end

describe("scenario 'tab_view': the surface D5 shipped without", function()
	it("is registered in BOTH places a player reaches it through, and names a root screen", function()
		local listed: any = nil
		for _, demo in demo_picker.list() do
			if demo.id == "tab-view" then
				listed = demo
			end
		end
		expect(listed ~= nil).toBe(true)
		expect(listed.kind).toBe("fixture")
		expect(listed.module).toBe("tab_view")
		local w = world(PHONE)
		expect(w.adapter.node("/TabViewDemo") ~= nil).toBe(true)
		expect(w.core:lastError()).toBeNil()
	end)

	it("mounts BOTH skins of the sliding indicator — underline above, pill inside", function()
		local w = world(PHONE)
		local r = w.built.report()
		expect(r.app.strip.indicator.skin).toBe("underline")
		expect(r.page.strip.indicator.skin).toBe("pill")
		-- and both are real mounted layers, not two names for one default
		expect(w.adapter.node(`{APP}/BottomHome/then/BottomBand/Strip/Indicator/Layer/Bar`) ~= nil).toBe(true)
		expect(w.adapter.node(`{PAGE_BAND}/Strip/Indicator/Layer/Bar`) ~= nil).toBe(true)
	end)
end)

describe("scenario 'tab_view': two levels, and each one SAYS where it landed", function()
	it("on a phone the app takes the thumb zone and the page takes the top — both printed", function()
		local w = world(PHONE)
		local r = w.built.report()
		expect(r.app.placement).toBe("bottomBar")
		expect(r.app.placementSource).toBe("policy")
		expect(r.app.nested).toBe(false)
		expect(r.page.placement).toBe("topBar")
		expect(r.page.placementSource).toBe("nested")
		expect(r.page.nested).toBe(true)
		-- the readouts, which are the only reason a device tester could ever know.
		-- They live INSIDE the tab rather than in a band above the construct — see
		-- `statusPanel` in the fixture for the 114 findings that decided that.
		expect(w.text(`{pageBody("avatars")}/Placements/Inner`)).toBe("Page bar: topBar (nested)")
		expect(w.text(`{pageBody("avatars")}/Placements/Outer`)).toBe("App bar: bottomBar (policy)")
		-- ...and the two bars really are in different homes
		expect(w.adapter.node(`{BOTTOM}/Opt1`) ~= nil).toBe(true)
		expect(w.adapter.node(`{PAGE_OPTS}/Opt1`) ~= nil).toBe(true)
	end)

	--[[ THE CASE THAT CATCHES AN INNER TabView READING THE POLICY. On a pointer
		desktop the policy answers `sidebar`; if the inner one asked, it would answer
		`sidebar` too and the page's tabs would become a second rail. It must stay a
		top band, and the readout must say so. ]]
	it("on a pointer desktop the app becomes a rail and the page is STILL a top band", function()
		local w = world(DESKTOP, { preferredInput = "KeyboardAndMouse" })
		local r = w.built.report()
		expect(r.app.placement).toBe("sidebar")
		expect(r.page.placement).toBe("topBar")
		expect(r.page.placementSource).toBe("nested")
		expect(w.text(`{pageBody("avatars")}/Placements/Outer`)).toBe("App bar: sidebar (policy)")
		expect(w.text(`{pageBody("avatars")}/Placements/Inner`)).toBe("Page bar: topBar (nested)")
		-- ...and a tab that is not the nested one carries the same answer, from the
		-- status panel every tab mounts
		w.built.steps.select(w.built, "notes")
		w.settle()
		expect(w.text(`{APP}/Content/Tab-notes/then/NotesBody/Status/AppPlacement`)).toBe("App bar: sidebar (policy)")
	end)

	it("no focus scope is claimed by either level, and the back() stack is untouched", function()
		local w = world(PHONE)
		expect(w.pres.depth()).toBe(1)
		expect(w.pres.focus.trapped == nil or w.pres.focus.trapped:get() == nil).toBe(true)
		w.built.steps.select(w.built, "notes")
		w.built.steps.select(w.built, "pages")
		w.built.steps.selectPage(w.built, "emotes")
		w.settle()
		expect(w.pres.depth()).toBe(1)
	end)
end)

describe("scenario 'tab_view': the eviction, as a number a tester can watch move", function()
	it("leaving and returning to a tab REBUILDS it, and the screen says so", function()
		local w = world(PHONE)
		expect(w.built.report().builds.notes).toBeNil()
		w.built.steps.select(w.built, "notes")
		w.settle()
		expect(w.built.report().builds.notes).toBe(1)
		expect(string.find(w.text(`{APP}/Content/Tab-notes/then/NotesBody/Status/Builds`) :: string, "Notes 1") ~= nil).toBe(
			true
		)
		w.built.steps.select(w.built, "me")
		w.built.steps.select(w.built, "notes")
		w.settle()
		expect(w.built.report().builds.notes).toBe(2)
		expect(string.find(w.text(`{APP}/Content/Tab-notes/then/NotesBody/Status/Builds`) :: string, "Notes 2") ~= nil).toBe(
			true
		)
		--[[ AND THE FRAMEWORK'S OWN COUNT MOVES WITH IT, which is what makes the
			fixture's number evidence rather than a second opinion: a HIDE would leave
			`contentEvictions` flat while this fixture's counter kept climbing, and a
			leak would leave mounts climbing with evictions flat. ]]
		local d = w.built.report().app
		expect(d.contentMounts).toBe(4)
		expect(d.contentEvictions).toBe(3)
		expect(#d.mountedTabs).toBe(1)
		expect(d.mountedTabs[1]).toBe("notes")
	end)

	--[[ THE ESCAPE HATCH IS OWNERSHIP AND NOT A FLAG, and this is that sentence
		with two numbers on it. Both counters are written by ONE press; the only
		difference between them is the scope that owns them. ]]
	it("state owned by the screen survives a switch; state owned by the tab does not", function()
		local w = world(PHONE)
		w.built.steps.select(w.built, "notes")
		w.settle()
		w.built.steps.bump(w.built)
		w.built.steps.bump(w.built)
		w.settle()
		expect(w.text(`{APP}/Content/Tab-notes/then/NotesBody/Kept`)).toBe("Kept outside the TabView: 2")
		expect(w.text(`{APP}/Content/Tab-notes/then/NotesBody/Owned`)).toBe("Owned by this tab's scope: 2")
		w.built.steps.select(w.built, "me")
		w.built.steps.select(w.built, "notes")
		w.settle()
		expect(w.text(`{APP}/Content/Tab-notes/then/NotesBody/Kept`)).toBe("Kept outside the TabView: 2")
		expect(w.text(`{APP}/Content/Tab-notes/then/NotesBody/Owned`)).toBe("Owned by this tab's scope: 0")
	end)

	--[[ THE STRIP IS NEVER EVICTED, which is the entire reason a badge is worth
		having: the count belongs to a tab whose content does not exist. ]]
	it("a badge climbs on an UNSELECTED tab while that tab's content is gone", function()
		local w = world(PHONE)
		expect(w.text(`{BOTTOM}/Opt2Cell/Badge/Count`)).toBe("3")
		expect(w.built.report().app.mountedTabs[1]).toBe("pages")
		w.built.steps.select(w.built, "me")
		w.built.steps.bumpUnread(w.built)
		w.built.steps.bumpUnread(w.built)
		w.settle()
		-- inbox has never been mounted at all, and its seal has still moved twice
		expect(w.built.report().builds.inbox).toBeNil()
		expect(w.text(`{BOTTOM}/Opt2Cell/Badge/Count`)).toBe("5")
		expect(w.adapter.node(`{BOTTOM}/Opt2Cell/Opt2`) ~= nil).toBe(true)
		-- ...and the badge empties rather than painting a zero, from the tab itself
		w.built.steps.select(w.built, "inbox")
		w.settle()
		expect(w.built.report().builds.inbox).toBe(1)
	end)
end)

describe("scenario 'tab_view': the page bar overflows, on purpose", function()
	it("a hugging strip measures wider than its band at a phone width", function()
		local w = world(PHONE)
		expect(w.built.report().page.sizing).toBe("hug")
		local band = w.adapter.node(PAGE_BAND)
		local strip = w.adapter.node(`{PAGE_BAND}/Strip`)
		expect(band.class).toBe("ScrollView")
		expect(`strip {strip.rect.w} > band {band.rect.w}? {strip.rect.w > band.rect.w}`).toBe(
			`strip {strip.rect.w} > band {band.rect.w}? true`
		)
		-- ...and the app's own band FILLS, so it has nothing to scroll — which is
		-- correct rather than a failure, and is why the overflow lives on the inner
		expect(w.built.report().app.sizing).toBe("fill")
		expect(w.built.report().app.reveals).toBe(0)
	end)

	it("a selection change that moved no focus still brings the tab into view, once", function()
		local w = world(PHONE)
		expect(w.built.report().page.reveals).toBe(0)
		w.built.steps.selectPage(w.built, "favorites")
		w.settle()
		expect(w.built.report().page.selectedId).toBe("favorites")
		expect(w.built.report().page.reveals).toBe(1)
		-- an already-visible selection issues NO scroll, and idling issues none
		w.built.steps.selectPage(w.built, "favorites")
		w.settle(20)
		expect(w.built.report().page.reveals).toBe(1)
	end)
end)

describe("scenario 'tab_view': everything on it is reachable, everywhere", function()
	it("every tab at BOTH levels is a Button at the 44px floor, read where it is painted", function()
		local w = world(PHONE)
		local paths: { string } = {}
		focus_map.collectFocusables(w.built.handle.root.node, paths)
		-- 8 page tabs + 2 jump chips + 4 app tabs. The app's bottom band reads LAST
		-- because that is where it is painted, and the page's top band reads before
		-- the page's own content for the same reason — so the ring walks the inner
		-- level first and lands on the app bar at the end.
		expect(#paths).toBe(14)
		expect(paths[11]).toBe(`{BOTTOM}/Opt1`)
		for _, path in paths do
			local node = w.adapter.node(path)
			expect(`{path}: {node.class}`).toBe(`{path}: Button`)
			expect(`{path} is {node.rect.h}px tall, under 44? {node.rect.h < 44}`).toBe(
				`{path} is {node.rect.h}px tall, under 44? false`
			)
		end
	end)

	it("a keyboard and a pad both move the page bar, and the shoulders page it", function()
		local w = world(PHONE)
		-- the ring starts on the page bar's first tab, because that band is painted
		-- before the page's own content and read where it is painted
		local first = `{PAGE_OPTS}/Opt1`
		expect(w.pres.focus.focused:get()).toBe(first)
		w.system.deviceKey("Right", true)
		w.system.deviceKey("Right", false)
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		w.settle()
		expect(w.built.report().page.selectedId).toBe("body")
		-- the gamepad shoulders page, and they clamp rather than wrapping
		w.system.deviceKey("ButtonR1", true)
		w.system.deviceKey("ButtonR1", false)
		w.settle()
		expect(w.built.report().page.selectedId).toBe("clothing")
		w.system.deviceKey("ButtonL1", true)
		w.system.deviceKey("ButtonL1", false)
		w.settle()
		expect(w.built.report().page.selectedId).toBe("body")
	end)

	it("the solver reports NOTHING at any swept viewport, on any tab", function()
		for _, view in { PHONE, LANDSCAPE, DESKTOP } do
			local w = world(view)
			for _, tab in { "pages", "inbox", "notes", "me" } do
				w.built.steps.select(w.built, tab)
				w.settle()
				local findings = w.built.handle.controller.diagnostics()
				expect(`{view.w}x{view.h} on {tab}: {#findings} finding(s)`).toBe(
					`{view.w}x{view.h} on {tab}: 0 finding(s)`
				)
			end
			w.built.dispose()
		end
	end)

	it("every player-visible string is reachable through the exported `copy`", function()
		local w = world(DESKTOP)
		local strings: { [string]: boolean } = {}
		for _, value in module.copy do
			if type(value) == "string" then
				strings[value] = true
			end
		end
		local painted = 0
		for path, facts in w.built.handle.controller.textAt() do
			-- a readout is COMPOSED (labels, numbers and the framework's own placement
			-- words), so the rule that covers both shapes is that every painted string
			-- either IS a copy value or CONTAINS one — which a hard-coded literal on
			-- this page would fail. The badge is a bare count and has no words in it.
			local isBadge = string.find(path, "/Badge/Count$") ~= nil
			if
				string.find(path, "^/TabViewDemo/") ~= nil
				and not isBadge
				and type(facts.text) == "string"
				and facts.text ~= ""
			then
				painted += 1
				local reached = strings[facts.text] == true
				if not reached then
					for value in strings do
						if #value > 3 and string.find(facts.text, value, 1, true) ~= nil then
							reached = true
							break
						end
					end
				end
				expect(`{path}: "{facts.text}" is reachable by the localization sweep? {reached}`).toBe(
					`{path}: "{facts.text}" is reachable by the localization sweep? true`
				)
			end
		end
		expect(painted > 15).toBe(true)
	end)
end)
