--!strict
-- TabView spec (navigation-and-menus brief §2 D5) — the tab construct
-- `adaptive.navPlacement` has been waiting for since 2026-08-09.
--
-- FOUR CLAIMS CARRY THE DELIVERABLE, and each is written so that the obvious
-- wrong implementation fails it:
--
--   * THE STRIP IS A PICKER. Not "a picker was consulted" — the mounted nodes
--     ARE `newPicker`'s option row, the D4 indicator included, and the dump
--     nests the picker's own dump rather than paraphrasing it.
--   * NESTING IS LOAD-BEARING, AND ONE LEVEL PROVES NOTHING. `r2` is a top tab
--     bar inside a screen that is itself a tab of the app-level bottom bar, so
--     every nesting case below mounts TWO live TabViews and asserts about the
--     inner one: it must not claim the app-level placement, must not fight for
--     a focus scope, and must not touch the presenter's back() stack.
--   * EVICTION IS A REAL DISPOSAL, NOT A HIDE. A hide passes every visual test
--     and leaks every switch, so the proof is `core:counters()` returning to a
--     baseline after N switches — plus a caller-owned resource on the tab scope
--     actually being disposed.
--   * A `fill` STRIP CANNOT OVERFLOW. Five tabs at 320px are 64px each, so an
--     autoscroll case built on the default sizing tests nothing at all. Every
--     overflow case below hugs, checks that the strip really is wider than its
--     band, and then asserts the engine was told to scroll.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local serde = require("@lune/serde")

local Facet = require("../src") :: any
local tab_view = require("../src/controls/tab_view")
local fake_target = require("./lib/fake_target")
local focus_map = require("../src/present/focus_map")

local UI = Facet.UI

-- ===== the harness ========================================================
-- One mounted TabView on a real presenter. The viewport/input facts below are
-- the ONLY thing that decides a placement — there is no device name anywhere in
-- this file, because there is none in the policy.
local PHONE = { w = 320, h = 640 } -- compact width          -> bottomBar
local LANDSCAPE = { w = 800, h = 400 } -- short height       -> bottomBarCompact
local TABLET = { w = 900, h = 900 } -- touch + Medium display -> topBar
local DESKTOP = { w = 1200, h = 900 } -- pointer primary     -> sidebar

local function body(name: string)
	return function(_scope: any)
		return UI.Text({ id = name .. "Body", text = name })
	end
end

local function tabsOf(names: { string })
	local out = {}
	for _, name in names do
		table.insert(
			out,
			{ id = name, label = string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2), content = body(name) }
		)
	end
	return out
end

local function world(opts: any?)
	local options = opts or {}
	local view = options.viewport or PHONE
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	if options.capabilities ~= nil then
		env:set("capabilities", options.capabilities)
	end
	if options.preferredInput ~= nil then
		env:set("preferredInput", options.preferredInput)
	end
	if options.displaySize ~= nil then
		env:set("displaySize", options.displaySize)
	end
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local selection = core:signal(options.initial or "home")
	local built: any = {
		id = "Tabs",
		selection = selection,
		env = env,
		tabs = options.tabs or tabsOf({ "home", "feed", "me" }),
	}
	for _, key in
		{ "placement", "indicator", "sizing", "iconOnly", "enabled", "onChange", "transition", "textSize", "railWidth" }
	do
		if (options :: any)[key] ~= nil then
			built[key] = (options :: any)[key]
		end
	end
	local tv = Facet.Controls.TabView(core, built)
	local handle = pres.present(UI.Screen({ id = "S", children = { tv.blueprint } }), { sinkNavigation = true })
	pres.refresh()
	return {
		core = core,
		env = env,
		adapter = adapter,
		pres = pres,
		system = system,
		handle = handle,
		tv = tv,
		selection = selection,
	}
end

-- the strip's mounted path depends on which HOME is live, which is the whole
-- point of the placement policy — so it is resolved from the dump rather than
-- hard-coded, exactly as the picker spec resolves its own option paths
local HOME_OF: { [string]: string } = {
	sidebar = "RailHome/then/Rail",
	topBar = "TopHome/then/TopBandCenter/TopBand",
	bottomBar = "BottomHome/then/BottomBand",
	bottomBarCompact = "CompactHome/then/CompactBandCenter/CompactBand",
}
local function stripPath(w: any, root: string?): string
	local base = root or "/S/Tabs"
	return `{base}/{HOME_OF[w.tv.dump().placement]}/Strip`
end
local function tabPath(w: any, n: number, root: string?): string
	local d = w.tv.dump()
	local inner = if d.strip.indicator == "none" then "Options" else "Indicator/Options"
	-- a badged tab wears a cell around its Button (see newPicker's header)
	local badged = w.tv.dump().strip.badgeCount > 0
	local leaf = if badged then `Opt{n}Cell/Opt{n}` else `Opt{n}`
	return `{stripPath(w, root)}/{inner}/{leaf}`
end

--[[ ADAPT-4 — THE PLACEMENTS DOCUMENTED AS *CENTERED* WERE LEFT-ALIGNED.

	`adaptive.luau` states it twice ("the SAME bottom bar in its reduced, inline,
	CENTERED form"; "a CENTER-ALIGNED top tab bar that HUGS its content") and
	api.md repeats it in two places, and this file declared no main-axis alignment
	at all: measured on a television, a three-tab bar was a 193px cluster at x=90
	with 1547px of empty band beside it. Three of the six combos were affected.

	EVERY ASSERTION HERE IS A MEASURED GAP, never a property in a dump — the audit
	names that specifically, because the naive fix (`alignH` on the strip inside
	the stack) is ACCEPTED AND IGNORED, and a dump would have shown it faithfully. ]]
describe("ADAPT-4: the centered homes are centered, and the overflowing one still scrolls", function()
	--[[ THE GAP IS MEASURED FROM THE STRIP TO THE CONTROL'S OWN BOX, which is the
		one frame that means the same thing before and after this fix. At the anchor
		the scroller FILLED the band and the strip sat at its leading edge; the fix
		hugs the scroller and centres it, so a case pinned to either node's path
		would be measuring a structure rather than a placement. The strip is found
		by id wherever it is mounted, so this reddens with a REAL number (0 against
		1547 on a television) rather than with "no such path". ]]
	local function stripGaps(w: any): (number, number, number)
		local found: string? = nil
		for _, path in w.adapter.paths() do
			if string.match(path, "/Strip$") ~= nil then
				found = path
			end
		end
		expect(`the strip is mounted: {found ~= nil}`).toBe("the strip is mounted: true")
		local strip = w.adapter.node(found :: string).rect
		local root = w.adapter.node("/S/Tabs").rect
		return strip.x - root.x, (root.x + root.w) - (strip.x + strip.w), strip.w
	end

	it("the ten-foot top bar is centered in its band, not parked in the corner", function()
		local w = world({
			viewport = { w = 1920, h = 1080 },
			displaySize = "Large",
			capabilities = { touch = false, mouse = false, keyboard = false, gamepad = true },
			preferredInput = "Gamepad",
		})
		expect(w.tv.dump().placement).toBe("topBar")
		local left, right, width = stripGaps(w)
		expect(width < 1920 * 0.5).toBe(true) -- it HUGS, which is what makes the gap visible
		-- an odd leftover cannot split evenly, so the tolerance is ONE pixel and
		-- nothing more: 1547 against 0 is the defect this is watching for
		expect(math.abs(left - right) <= 1).toBe(true)
		expect(left > 0).toBe(true)
	end)

	it("the landscape phone's inline band is centered too", function()
		local w = world({
			viewport = { w = 844, h = 390 },
			capabilities = { touch = true, mouse = false, keyboard = false, gamepad = false },
			preferredInput = "Touch",
		})
		expect(w.tv.dump().placement).toBe("bottomBarCompact")
		local left, right = stripGaps(w)
		expect(math.abs(left - right) <= 1).toBe(true)
		expect(left > 0).toBe(true)
	end)

	--[[ THE HALF THAT MAKES THE FIX SAFE. Centring is `hug` — the content's width
		CAPPED AT THE OFFER — so a strip that does not fit takes the whole band and
		scrolls, exactly as it did before. `content` would have centred an
		overflowing strip out past both edges of the band, which is the trap the
		framework's own zstack diagnostic catches. ]]
	it("...and a strip that does NOT fit fills the band, scrolls, and overflows nothing", function()
		-- the D5 overflow fixture, at its own declared placement: five long tabs on
		-- a phone, which is the shape that made a scrolling strip necessary at all
		local w = world({
			viewport = PHONE,
			placement = "topBar",
			tabs = tabsOf({ "avatars", "body", "clothing", "accessories", "backgrounds" }),
		})
		expect(w.tv.dump().placement).toBe("topBar")
		local band = w.adapter.node("/S/Tabs/TopHome/then/TopBandCenter/TopBand").rect
		local root = w.adapter.node("/S/Tabs").rect
		expect(band.x).toBe(root.x) -- the scroller takes the whole band...
		expect(band.w).toBe(root.w)
		local _, _, stripWidth = stripGaps(w)
		expect(stripWidth > band.w).toBe(true) -- ...and there is something to scroll
		expect(#w.handle.controller.diagnostics()).toBe(0)
	end)
end)

describe("D5: the strip IS a segmented picker, not a second option row", function()
	it("mounts newPicker's own option row, with the D4 indicator on it", function()
		local w = world()
		expect(w.core:lastError()).toBeNil()
		expect(w.adapter.node(tabPath(w, 1)).class).toBe("Button")
		expect(w.adapter.node(tabPath(w, 1)).props.label).toBe("Home")
		expect(w.adapter.node(stripPath(w) .. "/Indicator/Layer/Bar") ~= nil).toBe(true)
		-- ...and the strip's whole state is the picker's OWN dump, nested rather
		-- than paraphrased, so there is one description of a segment row
		expect(w.tv.dump().strip.schema).toBe("facet-picker-dump/1")
		expect(w.tv.dump().strip.optionCount).toBe(3)
	end)

	it("`indicator` defaults to the UNDERLINE every reference tab strip draws", function()
		local w = world()
		expect(w.tv.dump().strip.indicator.skin).toBe("underline")
		-- ...and "a segmented control used as a tab bar" is this with a chip
		local pill = world({ indicator = "pill" })
		expect(pill.tv.dump().strip.indicator.skin).toBe("pill")
		local none = world({ indicator = "none" })
		expect(none.tv.dump().strip.indicator).toBe("none")
	end)

	it("a tab id IS a name when no label was given, because a segment always has one", function()
		local w = world({
			tabs = { { id = "home", content = body("home") }, { id = "feed", content = body("feed") } },
		})
		expect(w.adapter.node(tabPath(w, 1)).props.label).toBe("home")
		expect(w.tv.dump().selectedLabel).toBe("home")
	end)

	it("an icon-only tab STILL carries a semantic label for the dump", function()
		local w = world({
			iconOnly = true,
			tabs = {
				{ id = "home", label = "Home", icon = "app:home", content = body("home") },
				{ id = "feed", label = "Feed", icon = "app:feed", content = body("feed") },
			},
		})
		expect(w.tv.dump().strip.iconOnly).toBe(true)
		-- the DRAWN text is the glyph (`props.label` is what the renderer paints)…
		expect(w.adapter.node(tabPath(w, 1)).props.label ~= "Home").toBe(true)
		-- …and the NAME survived being undrawn, which is the whole claim
		expect(w.tv.dump().strip.selectedLabel).toBe("Home")
		expect(w.tv.dump().selectedLabel).toBe("Home")
		expect(w.tv.dump().semanticText).toBe("Tabs: Home (1 of 2) in the bottomBar")
	end)

	it("a badge rides an UNSELECTED tab and survives every switch — the strip is never evicted", function()
		local w = world({
			tabs = {
				{ id = "home", label = "Home", content = body("home") },
				{ id = "feed", label = "Feed", badge = "12", content = body("feed") },
			},
		})
		local badge = stripPath(w) .. "/Indicator/Options/Opt2Cell/Badge/Count"
		expect(w.adapter.node(badge).props.text).toBe("12")
		for _ = 1, 6 do
			w.selection:set("feed")
			w.pres.refresh()
			w.selection:set("home")
			w.pres.refresh()
		end
		expect(w.adapter.node(badge).props.text).toBe("12")
		expect(w.adapter.node(tabPath(w, 2)) ~= nil).toBe(true)
		expect(w.tv.dump().contentEvictions > 0).toBe(true)
	end)
end)

describe("D5: placement comes from the policy, and the strip is RE-HOMED not rebuilt", function()
	it("the four homes come from shape and input facts — no device name decides one", function()
		expect(world({ viewport = PHONE }).tv.dump().placement).toBe("bottomBar")
		expect(world({ viewport = LANDSCAPE }).tv.dump().placement).toBe("bottomBarCompact")
		expect(world({ viewport = TABLET, preferredInput = "Touch", displaySize = "Medium" }).tv.dump().placement).toBe(
			"topBar"
		)
		expect(world({ viewport = DESKTOP, preferredInput = "KeyboardAndMouse" }).tv.dump().placement).toBe("sidebar")
	end)

	it("the sidebar runs the strip DOWN the screen and every other home ACROSS it", function()
		local rail = world({ viewport = DESKTOP, preferredInput = "KeyboardAndMouse" })
		expect(rail.tv.dump().axis).toBe("y")
		expect(rail.tv.dump().strip.verticalPill).toBe(true)
		expect(world({ viewport = PHONE }).tv.dump().axis).toBe("x")
	end)

	it("a rotation RE-HOMES one strip: the picker object survives and the bar follows it", function()
		local w = world({ viewport = PHONE })
		expect(w.adapter.node(stripPath(w) .. "/Indicator/Layer/Bar") ~= nil).toBe(true)
		local beforeTransitions = w.tv.dump().strip.indicator.transitions
		w.env:set("viewportRect", { x = 0, y = 0, w = DESKTOP.w, h = DESKTOP.h })
		w.env:set("preferredInput", "KeyboardAndMouse")
		w.pres.refresh()
		expect(w.tv.dump().placement).toBe("sidebar")
		-- the OLD home is gone and the new one carries the same strip, still
		-- resolving every segment — the indicator learned its paths again
		expect(w.adapter.node("/S/Tabs/BottomHome/then/BottomBand/Strip")).toBeNil()
		expect(w.adapter.node(stripPath(w) .. "/Indicator/Layer/Bar") ~= nil).toBe(true)
		expect(w.tv.dump().strip.indicator.resolved).toBe(3)
		expect(#w.tv.dump().strip.indicator.unresolved).toBe(0)
		-- ...and it is the SAME seam, not a fresh one: its transition count only
		-- ever climbs
		expect(w.tv.dump().strip.indicator.transitions > beforeTransitions).toBe(true)
	end)

	it("a DECLARED placement never consults the policy at all", function()
		local w = world({ viewport = PHONE, placement = "topBar" })
		expect(w.tv.dump().placement).toBe("topBar")
		expect(w.tv.dump().placementSource).toBe("declared")
		expect(w.tv.dump().requestedPlacement).toBe("topBar")
		-- ...and a rotation that would have moved a policy answer moves nothing
		w.env:set("viewportRect", { x = 0, y = 0, w = DESKTOP.w, h = DESKTOP.h })
		w.env:set("preferredInput", "KeyboardAndMouse")
		w.pres.refresh()
		expect(w.tv.dump().placement).toBe("topBar")
	end)

	it("resolvePlacement is pure, so the rule is a test over strings", function()
		expect((tab_view.resolvePlacement("automatic", false, "sidebar"))).toBe("sidebar")
		expect(select(2, tab_view.resolvePlacement("automatic", false, "sidebar"))).toBe("policy")
		expect((tab_view.resolvePlacement("automatic", true, "sidebar"))).toBe("topBar")
		expect(select(2, tab_view.resolvePlacement("automatic", true, "sidebar"))).toBe("nested")
		expect((tab_view.resolvePlacement("bottomBar", true, "sidebar"))).toBe("bottomBar")
		expect(select(2, tab_view.resolvePlacement("bottomBar", true, "sidebar"))).toBe("declared")
	end)

	it("the thumb-zone band FILLS and every other home HUGS — that is what lets a strip scroll", function()
		expect(world({ viewport = PHONE }).tv.dump().sizing).toBe("fill")
		expect(world({ viewport = LANDSCAPE }).tv.dump().sizing).toBe("hug")
		expect(tab_view.resolveSizing("automatic", "topBar")).toBe("hug")
		expect(tab_view.resolveSizing("fill", "topBar")).toBe("fill")
	end)

	it("an automatic placement with nothing to ask is an authoring error, not a guess", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			Facet.Controls.TabView(core, {
				id = "X",
				selection = core:signal("a"),
				tabs = { { id = "a", content = body("a") } },
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "conditions", 1, true) ~= nil).toBe(true)
	end)
end)

-- ===== NESTING: two live levels, and the bug is entirely in the second =====
local function nestedWorld(opts: any?)
	local options = opts or {}
	local view = options.viewport or PHONE
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local outerSelection = core:signal("discover")
	local innerSelection = core:signal("foryou")
	local inner: any = nil
	local innerBuilds = 0
	local outer = Facet.Controls.TabView(core, {
		id = "App",
		selection = outerSelection,
		env = env,
		tabs = {
			{
				id = "discover",
				label = "Discover",
				-- `r2` EXACTLY: the page's own top tab bar, built INSIDE the app
				-- tab's content factory, which is also where laziness puts it
				content = function(tabScope: any)
					innerBuilds += 1
					inner = Facet.Controls.TabView(core, {
						id = "Page",
						selection = innerSelection,
						env = env,
						tabs = {
							{ id = "foryou", label = "For you", content = body("foryou") },
							{ id = "charts", label = "Charts", content = body("charts") },
						},
					})
					tabScope:own(inner)
					return inner.blueprint
				end,
			},
			{ id = "create", label = "Create", content = body("create") },
			{ id = "me", label = "Profile", content = body("me") },
		},
	})
	local handle = pres.present(UI.Screen({ id = "S", children = { outer.blueprint } }), { sinkNavigation = true })
	pres.refresh()
	return {
		core = core,
		env = env,
		adapter = adapter,
		pres = pres,
		system = system,
		handle = handle,
		outer = outer,
		outerSelection = outerSelection,
		innerSelection = innerSelection,
		innerOf = function()
			return inner
		end,
		innerBuilds = function()
			return innerBuilds
		end,
	}
end

describe("D5: NESTING — an inner TabView never claims the app-level placement", function()
	it("on one phone viewport the app takes the bottom bar and the page takes the top", function()
		local w = nestedWorld({ viewport = PHONE })
		expect(w.outer.dump().placement).toBe("bottomBar")
		expect(w.outer.dump().placementSource).toBe("policy")
		expect(w.outer.dump().nested).toBe(false)
		local inner = w.innerOf()
		expect(inner.dump().placement).toBe("topBar")
		expect(inner.dump().placementSource).toBe("nested")
		expect(inner.dump().nested).toBe(true)
		-- and they really are in different homes on screen
		expect(w.adapter.node("/S/App/BottomHome/then/BottomBand/Strip") ~= nil).toBe(true)
		expect(w.adapter.node("/S/App/Content/Tab-discover/then/Page/TopHome/then/TopBandCenter/TopBand/Strip") ~= nil).toBe(
			true
		)
	end)

	it("...and it stays the top bar when the POLICY would have said sidebar", function()
		-- the failure this catches is an inner TabView reading navPlacement: on a
		-- desktop both would answer `sidebar` and the page's tabs would be drawn as
		-- a second rail beside the app's
		local w = nestedWorld({ viewport = DESKTOP })
		w.env:set("preferredInput", "KeyboardAndMouse")
		w.pres.refresh()
		expect(w.outer.dump().placement).toBe("sidebar")
		expect(w.innerOf().dump().placement).toBe("topBar")
	end)

	it("neither level claims a focus scope, and the two strips read in document order", function()
		local w = nestedWorld({ viewport = PHONE })
		local paths: { string } = {}
		focus_map.collectFocusables(w.handle.root.node, paths)
		-- the outer strip is painted AFTER the content on a bottom bar, so it
		-- reads after it — the shipped "reads where it is painted" rule
		expect(#paths).toBe(5)
		expect(paths[1]).toBe(
			"/S/App/Content/Tab-discover/then/Page/TopHome/then/TopBandCenter/TopBand/Strip/Indicator/Options/Opt1"
		)
		expect(paths[2]).toBe(
			"/S/App/Content/Tab-discover/then/Page/TopHome/then/TopBandCenter/TopBand/Strip/Indicator/Options/Opt2"
		)
		expect(paths[3]).toBe("/S/App/BottomHome/then/BottomBand/Strip/Indicator/Options/Opt1")
		-- ONE flat order: neither TabView trapped focus inside itself, which is
		-- what a `transientScope` would have done
		expect(w.pres.focus.trapped == nil or w.pres.focus.trapped:get() == nil).toBe(true)
	end)

	it("neither level touches the presenter's back() stack", function()
		local w = nestedWorld({ viewport = PHONE })
		local before = w.pres.depth()
		w.innerSelection:set("charts")
		w.pres.refresh()
		w.outerSelection:set("create")
		w.pres.refresh()
		w.outerSelection:set("discover")
		w.pres.refresh()
		w.innerSelection:set("foryou")
		w.pres.refresh()
		expect(w.pres.depth()).toBe(before)
		expect(before).toBe(1)
	end)

	it("two selections are two Signals: moving one never moves the other", function()
		local w = nestedWorld({ viewport = PHONE })
		w.innerSelection:set("charts")
		w.pres.refresh()
		expect(w.outerSelection:get()).toBe("discover")
		expect(w.innerOf().dump().selectedId).toBe("charts")
		expect(w.adapter.node("/S/App/Content/Tab-discover/then/Page/Content/Tab-charts/then/chartsBody") ~= nil).toBe(
			true
		)
	end)

	it("the inner TabView is CONTENT, so it is evicted with its host tab and re-nests on return", function()
		local w = nestedWorld({ viewport = PHONE })
		expect(w.innerBuilds()).toBe(1)
		w.outerSelection:set("create")
		w.pres.refresh()
		expect(w.adapter.node("/S/App/Content/Tab-discover/then/Page")).toBeNil()
		w.outerSelection:set("discover")
		w.pres.refresh()
		expect(w.innerBuilds()).toBe(2)
		-- the rebuilt one is nested too: the depth is a stack, not a one-shot flag
		expect(w.innerOf().dump().nested).toBe(true)
		expect(w.innerOf().dump().placement).toBe("topBar")
	end)

	it("a content factory that THROWS still leaves the depth balanced", function()
		-- an unbalanced build stack would make every later TabView in the session
		-- think it was nested, which is a bug that only shows up two screens away
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = PHONE.w, h = PHONE.h })
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local boom = Facet.Controls.TabView(core, {
			id = "Boom",
			selection = core:signal("a"),
			env = env,
			tabs = { {
				id = "a",
				content = function()
					error("content exploded", 0)
				end,
			} },
		})
		local ok = pcall(function()
			pres.present(UI.Screen({ id = "S", children = { boom.blueprint } }))
			pres.refresh()
		end)
		expect(ok).toBe(false)
		-- a TabView built AFTER the explosion is not falsely nested
		local after = world({ viewport = PHONE })
		expect(after.tv.dump().nested).toBe(false)
		expect(after.tv.dump().placementSource).toBe("policy")
	end)
end)

describe("D5: LAZY content, EVICTED state — a real disposal, never a hide", function()
	it("only the selected tab's subtree exists at all", function()
		local w = world()
		expect(w.adapter.node("/S/Tabs/Content/Tab-home/then/homeBody") ~= nil).toBe(true)
		expect(w.adapter.node("/S/Tabs/Content/Tab-feed/then/feedBody")).toBeNil()
		expect(w.adapter.node("/S/Tabs/Content/Tab-me/then/meBody")).toBeNil()
		expect(w.tv.dump().mountedTabs).toEqual({ "home" })
		expect(w.tv.dump().contentMounts).toBe(1)
	end)

	it("switching TEARS THE PREVIOUS SUBTREE DOWN — the node is gone, not hidden", function()
		local w = world()
		w.selection:set("feed")
		w.pres.refresh()
		-- gone, not merely invisible: a hide would leave the node and answer a
		-- visibility query, which is exactly the implementation this case refuses
		expect(w.adapter.node("/S/Tabs/Content/Tab-home/then/homeBody")).toBeNil()
		expect(w.adapter.visibleOf("/S/Tabs/Content/Tab-home/then/homeBody")).toBeNil()
		expect(w.adapter.node("/S/Tabs/Content/Tab-feed/then/feedBody") ~= nil).toBe(true)
		expect(w.tv.dump().mountedTabs).toEqual({ "feed" })
		expect(w.tv.dump().contentEvictions).toBe(1)
	end)

	it("the content region STRETCHES its tab to the offer rather than letting it overflow", function()
		--[[ FOUND BY THE FIRST REFERENCE APP MIGRATED ONTO THIS CONTROL. The content
			region was a `ZStack`, which gives a child its NATURAL size; a real page
			measures wider than a phone, so the solver filed "this child overflows its
			zstack by 512x0px" at every one of the five matrix viewports. Exactly one
			branch is ever mounted, so the container's only job is to STRETCH it. ]]
		local w = world({
			viewport = PHONE,
			tabs = {
				{
					id = "home",
					label = "Home",
					content = function()
						-- a content-sized body, wider than the phone offer
						return UI.HStack({
							id = "homeBody",
							width = { type = "content" },
							children = {
								UI.Text({ id = "A", text = "a considerably wider body than a phone offers" }),
								UI.Text({ id = "B", text = "and a second one after it, for good measure" }),
							},
						})
					end,
				},
				{ id = "feed", label = "Feed", content = body("feed") },
			},
		})
		local region = w.adapter.node("/S/Tabs/Content").rect
		local page = w.adapter.node("/S/Tabs/Content/Tab-home/then/homeBody").rect
		expect(page.w).toBe(region.w)
		-- ...and the region files no "child overflows its zstack" of its own. (The
		-- BODY still reports its own row overflowing, which is the fixture being
		-- deliberately too wide — that finding is about the page, not the region.)
		local mine = 0
		for _, finding in w.handle.controller.diagnostics() do
			if finding.filedBy == "/S/Tabs/Content" then
				mine += 1
			end
		end
		expect(mine).toBe(0)
	end)

	it("MEMORY NEUTRALITY: twenty switches return every counter to its baseline", function()
		-- the likeliest defect in this deliverable is a tab that leaks on switch,
		-- and it is invisible to every geometry and paint assertion
		local w = world()
		-- ONE WARM-UP CYCLE BEFORE THE BASELINE, and the reason is worth stating:
		-- the D4 indicator builds its four springs LAZILY, on the first slide, and
		-- they are owned by the strip's scope for the control's whole life. A
		-- baseline taken before any switch would count that one-time allocation as
		-- a leak, and moving the baseline is the honest fix — the claim is that
		-- switching is neutral, not that the first switch allocates nothing.
		w.selection:set("feed")
		w.pres.refresh()
		w.selection:set("home")
		w.pres.refresh()
		local baseline = w.core:counters()
		for _ = 1, 10 do
			w.selection:set("feed")
			w.pres.refresh()
			w.selection:set("me")
			w.pres.refresh()
			w.selection:set("home")
			w.pres.refresh()
		end
		local after = w.core:counters()
		expect(after.signals).toBe(baseline.signals)
		expect(after.memos).toBe(baseline.memos)
		expect(after.observers).toBe(baseline.observers)
		expect(after.effects).toBe(baseline.effects)
		expect(after.scopes).toBe(baseline.scopes)
		expect(after.settles).toBe(baseline.settles)
		expect(w.tv.dump().contentMounts).toBe(33)
		expect(w.tv.dump().contentEvictions).toBe(32)
	end)

	it("eviction disposes what the CALLER owned on the tab scope", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = PHONE.w, h = PHONE.h })
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local selection = core:signal("home")
		local disposed = 0
		local baseline: any = nil
		local tv = Facet.Controls.TabView(core, {
			id = "Tabs",
			selection = selection,
			env = env,
			tabs = {
				{
					id = "home",
					label = "Home",
					content = function(tabScope: any)
						-- the tab's own reactive state, owned on the scope the tab
						-- hands out — this is the whole eviction contract
						for _ = 1, 5 do
							tabScope:own(core:memo(function()
								return 1
							end))
						end
						tabScope:own({
							dispose = function()
								disposed += 1
							end,
						})
						return UI.Text({ id = "homeBody", text = "home" })
					end,
				},
				{ id = "feed", label = "Feed", content = body("feed") },
			},
		})
		pres.present(UI.Screen({ id = "S", children = { tv.blueprint } }))
		pres.refresh()
		local withTab = core:counters()
		selection:set("feed")
		pres.refresh()
		local withoutTab = core:counters()
		expect(disposed).toBe(1)
		-- the five memos the tab owned really went away: the neutrality claim
		-- above is measuring something
		expect(withoutTab.memos < withTab.memos).toBe(true)
		expect(withTab.memos - withoutTab.memos >= 5).toBe(true)
		selection:set("home")
		pres.refresh()
		expect(core:counters().memos).toBe(withTab.memos)
		tv.dispose()
	end)

	it("returning to a tab REPLAYS its entry cost — the accepted cost, stated as a test", function()
		local entries = 0
		local w = world({
			tabs = {
				{
					id = "home",
					label = "Home",
					content = function()
						entries += 1
						return UI.Text({ id = "homeBody", text = "home" })
					end,
				},
				{ id = "feed", label = "Feed", content = body("feed") },
			},
		})
		expect(entries).toBe(1)
		w.selection:set("feed")
		w.pres.refresh()
		w.selection:set("home")
		w.pres.refresh()
		expect(entries).toBe(2)
	end)

	it("...and state held OUTSIDE the TabView survives it — the documented escape hatch", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = PHONE.w, h = PHONE.h })
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local selection = core:signal("home")
		-- the caller's Signal, OUTSIDE the TabView, exactly as `selection` is
		local draft = core:signal("half typed")
		local tv = Facet.Controls.TabView(core, {
			id = "Tabs",
			selection = selection,
			env = env,
			tabs = {
				{
					id = "home",
					label = "Home",
					content = function()
						return UI.Text({ id = "homeBody", text = draft })
					end,
				},
				{ id = "feed", label = "Feed", content = body("feed") },
			},
		})
		pres.present(UI.Screen({ id = "S", children = { tv.blueprint } }))
		pres.refresh()
		expect(adapter.node("/S/Tabs/Content/Tab-home/then/homeBody").props.text).toBe("half typed")
		selection:set("feed")
		pres.refresh()
		selection:set("home")
		pres.refresh()
		expect(adapter.node("/S/Tabs/Content/Tab-home/then/homeBody").props.text).toBe("half typed")
		tv.dispose()
	end)
end)

describe("D5: an OVERFLOWING strip scrolls the selection into view", function()
	local MANY = tabsOf({ "avatars", "body", "clothing", "accessories", "backgrounds" })

	local function overflowing()
		-- a hugging strip, because a `fill` one divides the offer and can never
		-- overflow — and `topBar` is declared so the placement is not what is
		-- under test here
		return world({ viewport = PHONE, tabs = MANY, placement = "topBar", initial = "avatars" })
	end

	it("the strip really is WIDER than its band — otherwise there is nothing to test", function()
		local w = overflowing()
		local band = w.adapter.node("/S/Tabs/TopHome/then/TopBandCenter/TopBand").rect
		local strip = w.adapter.node(stripPath(w)).rect
		expect(strip.w > band.w).toBe(true)
		expect(w.tv.dump().sizing).toBe("hug")
	end)

	it("selecting an off-screen tab scrolls it into view", function()
		local w = overflowing()
		expect(w.adapter.scrollPositionOf("/S/Tabs/TopHome/then/TopBandCenter/TopBand").x).toBe(0)
		w.selection:set("backgrounds")
		w.pres.refresh()
		expect(w.tv.dump().reveals).toBe(1)
		local offset = w.adapter.scrollPositionOf("/S/Tabs/TopHome/then/TopBandCenter/TopBand").x
		expect(offset > 0).toBe(true)
		-- ...and the selected tab is now inside the band
		local band = w.adapter.node("/S/Tabs/TopHome/then/TopBandCenter/TopBand").rect
		local tab = w.adapter.node(tabPath(w, 5)).rect
		expect(tab.x - band.x - offset >= -0.001).toBe(true)
		expect(tab.x + tab.w - band.x - offset <= band.w + 0.001).toBe(true)
	end)

	it("a selection that is ALREADY visible issues no scroll at all", function()
		local w = overflowing()
		w.selection:set("body")
		w.pres.refresh()
		expect(w.tv.dump().reveals).toBe(0)
		expect(w.adapter.scrollPositionOf("/S/Tabs/TopHome/then/TopBandCenter/TopBand").x).toBe(0)
	end)

	it("...and repeated refreshes on an unchanged selection issue no scroll either", function()
		local w = overflowing()
		w.selection:set("backgrounds")
		w.pres.refresh()
		expect(w.tv.dump().reveals).toBe(1)
		for _ = 1, 10 do
			w.pres.refresh()
		end
		expect(w.tv.dump().reveals).toBe(1)
	end)

	it("a FILLING thumb-zone band has nothing to scroll, and that is correct", function()
		local w = world({ viewport = PHONE, tabs = MANY })
		expect(w.tv.dump().placement).toBe("bottomBar")
		expect(w.tv.dump().sizing).toBe("fill")
		local band = w.adapter.node("/S/Tabs/BottomHome/then/BottomBand").rect
		expect(w.adapter.node(stripPath(w)).rect.w <= band.w + 0.001).toBe(true)
		w.selection:set("backgrounds")
		w.pres.refresh()
		expect(w.tv.dump().reveals).toBe(0)
	end)
end)

describe("D5: four inputs, one story", function()
	it("TabView pointer: a tap activates through the presenter (device-true)", function()
		local w = world()
		w.adapter.tap(tabPath(w, 2))
		w.pres.refresh()
		expect(w.selection:get()).toBe("feed")
		expect(w.adapter.node("/S/Tabs/Content/Tab-feed/then/feedBody") ~= nil).toBe(true)
	end)

	it("TabView touch: a touch tap/pan drives the control (device-true)", function()
		local w = world()
		w.adapter.touchTap(tabPath(w, 3))
		w.pres.refresh()
		expect(w.selection:get()).toBe("me")
	end)

	it("TabView keyboard: focus + Return drives the control", function()
		local w = world()
		expect(w.pres.focus.focused:get()).toBe(tabPath(w, 1))
		-- RIGHT, not Down: a bar is a HORIZONTAL group, which is the whole point of
		-- the focus_map fix D5 landed
		w.system.deviceKey("Right", true)
		w.system.deviceKey("Right", false)
		expect(w.pres.focus.focused:get()).toBe(tabPath(w, 2))
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		w.pres.refresh()
		expect(w.selection:get()).toBe("feed")
		expect(w.adapter.node("/S/Tabs/Content/Tab-feed/then/feedBody") ~= nil).toBe(true)
	end)

	it("TabView gamepad: focus + ButtonA drives the control", function()
		local w = world()
		w.system.deviceKey("DPadRight", true)
		w.system.deviceKey("DPadRight", false)
		w.system.deviceKey("DPadRight", true)
		w.system.deviceKey("DPadRight", false)
		expect(w.pres.focus.focused:get()).toBe(tabPath(w, 3))
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		w.pres.refresh()
		expect(w.selection:get()).toBe("me")
	end)

	it("TabView pointer affordance: the pointer structural idiom (hover/direct-drag/wheel)", function()
		-- a tab is a Button, so the pointer idiom is the primitive's: it advertises
		-- hover to the adapter and has no drag of its own. What is TabView-specific
		-- is that the strip's SCROLLER takes the wheel as its own channel, which is
		-- how a pointer reaches an overflowing strip with no gesture at all.
		local w = world({
			viewport = PHONE,
			-- long names on purpose: five one-letter tabs FIT at 320px, and a
			-- scroll case over a strip that does not overflow tests nothing
			tabs = tabsOf({ "avatars", "body", "clothing", "accessories", "backgrounds" }),
			placement = "topBar",
			preferredInput = "KeyboardAndMouse",
			capabilities = { keyboard = true, mouse = true, touch = false, gamepad = false },
		})
		expect(w.adapter.node(tabPath(w, 1)).hoverEnabled).toBe(true)
		-- ...and the strip declares a real scroll REGION wider than its window, so
		-- the wheel and the drag are the ENGINE's own channel on a native scrolling
		-- host rather than anything this control re-implements. `driveScroll` is
		-- the headless stand-in for the engine moving CanvasPosition, and the
		-- framework sees the result.
		local region = w.adapter.scrollRegionOf("/S/Tabs/TopHome/then/TopBandCenter/TopBand")
		expect(region.axis).toBe("x")
		expect(region.contentW > w.adapter.node("/S/Tabs/TopHome/then/TopBandCenter/TopBand").rect.w).toBe(true)
		w.adapter.driveScroll("/S/Tabs/TopHome/then/TopBandCenter/TopBand", { x = 40, y = 0 })
		w.pres.refresh()
		expect(w.adapter.scrollPositionOf("/S/Tabs/TopHome/then/TopBandCenter/TopBand").x).toBe(40)
	end)

	it("TabView touch affordance: the touch structural idiom (44px/naked-pan-scroll/edit-grip)", function()
		-- EVERY tab is a 44px target, on both axes and in every home — the floor is
		-- the picker's, which is the point of composing it
		for _, opts in
			{
				{ viewport = PHONE },
				{ viewport = LANDSCAPE },
				{ viewport = DESKTOP, preferredInput = "KeyboardAndMouse" },
			}
		do
			local w = world(opts)
			for n = 1, 3 do
				local rect = w.adapter.node(tabPath(w, n)).rect
				expect(rect.h >= 44).toBe(true)
				expect(rect.w >= 44).toBe(true)
			end
		end
		-- ...and a NAKED PAN over an overflowing strip scrolls it, rather than
		-- needing a grip: the strip is an ordinary ScrollView
		local over = world({
			viewport = PHONE,
			tabs = tabsOf({ "avatars", "body", "clothing", "accessories", "backgrounds" }),
			placement = "topBar",
		})
		expect(over.adapter.node("/S/Tabs/TopHome/then/TopBandCenter/TopBand").class).toBe("ScrollView")
	end)

	it("TabView keyboard affordance: the keyboard structural idiom (focus ring/Navigate/Activate/Adjust)", function()
		local w = world()
		-- DOCUMENT ORDER, the Tab-order rule (97e9d93): the strip's tabs are a flat
		-- run of Buttons in declaration order, and the bottom bar reads after the
		-- content because that is where it is painted
		local paths: { string } = {}
		focus_map.collectFocusables(w.handle.root.node, paths)
		expect(#paths).toBe(3)
		expect(paths[1]).toBe(tabPath(w, 1))
		expect(paths[3]).toBe(tabPath(w, 3))
		expect(w.pres.focus.focused:get()).toBe(tabPath(w, 1))
		expect(w.adapter.node(tabPath(w, 1)).focused).toBe(true)
		-- Adjust on a focused tab PAGES, and it clamps rather than wrapping
		w.system.deviceKey("Period", true)
		w.system.deviceKey("Period", false)
		w.pres.refresh()
		expect(w.selection:get()).toBe("feed")
		w.system.deviceKey("Comma", true)
		w.system.deviceKey("Comma", false)
		w.pres.refresh()
		expect(w.selection:get()).toBe("home")
		w.system.deviceKey("Comma", true)
		w.system.deviceKey("Comma", false)
		w.pres.refresh()
		expect(w.selection:get()).toBe("home")
	end)

	it("TabView gamepad affordance: the gamepad structural idiom (focus/grab/A-B/ten-foot)", function()
		local w = world()
		expect(w.pres.focus.focused:get()).toBe(tabPath(w, 1))
		-- THE SHOULDERS PAGE. They are bound DYNAMICALLY, only while focus is on a
		-- tab, so a screen carrying a TabView never shadows gameplay bumpers.
		w.system.deviceKey("ButtonR1", true)
		w.system.deviceKey("ButtonR1", false)
		w.pres.refresh()
		expect(w.selection:get()).toBe("feed")
		w.system.deviceKey("ButtonR1", true)
		w.system.deviceKey("ButtonR1", false)
		w.pres.refresh()
		expect(w.selection:get()).toBe("me")
		w.system.deviceKey("ButtonR1", true)
		w.system.deviceKey("ButtonR1", false)
		w.pres.refresh()
		expect(w.selection:get()).toBe("me") -- clamps at the last tab, never wraps
		w.system.deviceKey("ButtonL1", true)
		w.system.deviceKey("ButtonL1", false)
		w.pres.refresh()
		expect(w.selection:get()).toBe("feed")
		-- ...and a ten-foot screen still reaches every tab (the top bar, per policy).
		-- `distanceProfile` is DERIVED from the engine's display size, never set:
		-- a TV at 3m is a fact the platform reports, not one a screen declares.
		local tv = world({ viewport = DESKTOP, displaySize = "Large", preferredInput = "Gamepad" })
		expect(tv.tv.dump().placement).toBe("topBar")
		for n = 1, 3 do
			expect(tv.adapter.node(tabPath(tv, n)) ~= nil).toBe(true)
		end
	end)

	it("a bar strip is ONE horizontal group, so a pad crosses it instead of falling out", function()
		--[[ D5's own find, fixed in `focus_map`: the auto-group derivation matched
			`HStack` alone, and a tab strip is an `AdaptiveStack` (it has to be — a
			placement flip is a re-solve, not a remount). Every bar therefore answered
			Up/Down on a pad, and Right walked out of the band into the page. ]]
		local w = world()
		local groups = focus_map.autoGroups(w.handle.root.node)
		expect(#groups).toBe(1)
		expect(groups[1].axis).toBe("horizontal")
		expect(groups[1].order[1]).toBe(tabPath(w, 1))
		w.system.deviceKey("DPadRight", true)
		w.system.deviceKey("DPadRight", false)
		expect(w.pres.focus.focused:get()).toBe(tabPath(w, 2))
		-- ...and the SIDEBAR rail stays vertical, from the same live axis
		local rail = world({ viewport = DESKTOP, preferredInput = "KeyboardAndMouse" })
		expect(focus_map.autoGroups(rail.handle.root.node)[1].axis).toBe("vertical")
	end)

	it("the shoulders are UNBOUND while focus sits off the strip — the ADR-0013 hazard", function()
		local w = world({
			tabs = {
				{
					id = "home",
					label = "Home",
					content = function()
						return UI.Button({ id = "Inside", label = "Inside" })
					end,
				},
				{ id = "feed", label = "Feed", content = body("feed") },
			},
		})
		-- the content's Button is the FIRST focusable (the bar is painted after it)
		expect(w.pres.focus.focused:get()).toBe("/S/Tabs/Content/Tab-home/then/Inside")
		w.system.deviceKey("ButtonR1", true)
		w.system.deviceKey("ButtonR1", false)
		w.pres.refresh()
		expect(w.selection:get()).toBe("home")
	end)
end)

--[[ §6 THE CONTENT REGION'S ENTER TRANSITION. Both reference shells migrated onto
	this control in the accessory round declared `transition = { enter = "fade" }` on
	their own section hosts, and the construct had nowhere to say it — so adopting it
	would have silently swapped a fade for a hard cut in two shipped proofs. It is
	the framework's own `UI.When` transition, passed through to the content branches
	and to nothing else: the STRIP is never evicted, so it has nothing to animate. ]]
describe("§6: the content branches carry the caller's enter transition", function()
	-- the MOUNTED node, not the adapter's record of it: a transition is a fact
	-- `mount.luau` writes on the branch it built, and the adapter never sees it
	local function nodeAt(w: any, path: string): any
		local found: any = nil
		local function walk(node: any)
			if node == nil then
				return
			end
			if node.path == path then
				found = node
			end
			for _, child in node.children or {} do
				walk(child)
			end
		end
		walk(w.handle.root.node)
		return found
	end

	-- a fade needs a fade GROUP (the framework diagnoses a fade over a bare leaf),
	-- which is exactly the plate both migrated shells already wrap their sections in
	local function plate(name: string)
		return function(_scope: any)
			return UI.ZStack({
				id = name .. "Plate",
				canvasGroup = true,
				children = { UI.Text({ id = name .. "Body", text = name }) },
			})
		end
	end

	it("the declared transition reaches the content branch, and only it", function()
		local w = world({
			transition = { enter = "fade", class = "container" },
			tabs = {
				{ id = "home", label = "Home", content = plate("home") },
				{ id = "me", label = "Me", content = plate("me") },
			},
		})
		expect(#w.handle.controller.diagnostics()).toBe(0)
		expect(nodeAt(w, "/S/Tabs/Content/Tab-home/then/homePlate").transition.enter).toBe("fade")
		-- the strip's home is NOT a content branch: it re-homes on rotation and a
		-- fade there would cross-fade a bar the player did not move
		expect(nodeAt(w, "/S/Tabs/BottomHome/then/BottomBand").transition).toBeNil()
	end)

	it("declaring none leaves the branch with none — p4_foyer's path is unchanged", function()
		local w = world()
		expect(nodeAt(w, "/S/Tabs/Content/Tab-home/then/homeBody").transition).toBeNil()
	end)

	it("a transition must be a table, not the name of one", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			Facet.Controls.TabView(core, {
				id = "X",
				selection = core:signal("a"),
				placement = "topBar",
				transition = "fade",
				tabs = { { id = "a", content = body("a") } },
			})
		end)
		expect(ok).toBe(false)
		-- naming `table` is what separates THIS refusal from the closed spec's
		-- "unknown key", which fires for the same input before the guard exists
		expect(string.find(tostring(err), "transition", 1, true) ~= nil).toBe(true)
		expect(string.find(string.lower(tostring(err)), "table", 1, true) ~= nil).toBe(true)
	end)
end)

describe("D5: the closed spec, the dump, and disposal", function()
	it("an unknown key is an authoring error", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			Facet.Controls.TabView(core, {
				id = "X",
				selection = core:signal("a"),
				placement = "topBar",
				tabs = { { id = "a", content = body("a") } },
				retain = true,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "retain", 1, true) ~= nil).toBe(true)
	end)

	it("`content` must be a FACTORY, and the refusal says why", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			Facet.Controls.TabView(core, {
				id = "X",
				selection = core:signal("a"),
				placement = "topBar",
				tabs = { { id = "a", content = UI.Text({ id = "T", text = "t" }) } },
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "LAZY", 1, true) ~= nil).toBe(true)
	end)

	it("two tabs may not share an id, because a tab id IS the selection value", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			Facet.Controls.TabView(core, {
				id = "X",
				selection = core:signal("a"),
				placement = "topBar",
				tabs = { { id = "a", content = body("a") }, { id = "a", content = body("b") } },
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "share the id", 1, true) ~= nil).toBe(true)
	end)

	it("`selection` must be a settable Signal the caller owns", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			Facet.Controls.TabView(core, {
				id = "X",
				selection = "home",
				placement = "topBar",
				tabs = { { id = "home", content = body("home") } },
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "SETTABLE Signal", 1, true) ~= nil).toBe(true)
	end)

	it("the dump is deterministic and names every fact a bug report needs", function()
		local w = world()
		local d = w.tv.dump()
		expect(d.schema).toBe("facet-tab_view-dump/1")
		expect(d.id).toBe("Tabs")
		expect(d.tabCount).toBe(3)
		expect(d.selectedId).toBe("home")
		expect(d.selectedIndex).toBe(1)
		expect(d.semanticText).toBe("Tabs: Home (1 of 3) in the bottomBar")
		expect(serde.encode("json", w.tv.dump(), true)).toBe(serde.encode("json", w.tv.dump(), true))
	end)

	it("dispose is registry-neutral, strip and indicator and all", function()
		local core = Facet.newCore()
		-- the selection Signal is the CALLER's, so it is created BEFORE the
		-- baseline: a control that freed it would be freeing what it does not own
		local selection = core:signal("a")
		local baseline = core:counters()
		local tv = Facet.Controls.TabView(core, {
			id = "X",
			selection = selection,
			placement = "sidebar",
			tabs = {
				{ id = "a", label = "A", badge = "2", content = body("a") },
				{ id = "b", label = "B", content = body("b") },
			},
		})
		tv.dispose()
		local after = core:counters()
		expect(after.scopes).toBe(baseline.scopes)
		expect(after.memos).toBe(baseline.memos)
		expect(after.observers).toBe(baseline.observers)
		expect(after.signals).toBe(baseline.signals)
	end)

	it("hot-switch: nothing to carry or cancel — selection is atomic", function()
		-- UI-PARADIGM-002. TabView owns NO in-flight gesture state: there is no
		-- drag, no grab and no open edit, and a tab switch is a single Signal
		-- write. A live class flip mid-anything therefore has nothing to resolve,
		-- which is why the registry row declares hotSwitch = false — and this case
		-- is the evidence for that declaration rather than a stub beside it.
		local w = world()
		w.adapter.tap(tabPath(w, 2))
		w.env:set("preferredInput", "Gamepad")
		w.pres.refresh()
		expect(w.selection:get()).toBe("feed")
		expect(w.tv.dump().mountedTabs).toEqual({ "feed" })
		expect(w.core:lastError()).toBeNil()
	end)
end)

--[[ §6 THE STRIP'S TYPE ROLE, passed through to the segments. A thumb-zone tab bar
	is caption-sized in tighter chrome and a rail is not — `p1_glade`'s shipped
	comment says so, and it carried that treatment on its own copy of the row until
	it migrated onto this construct. The construct does NOT pick the ramp: which
	home takes which role is a design language, so the caller binds it against the
	placement this control already publishes. What the construct owes is that the
	binding REACHES the segments and follows a live re-home. ]]
describe("§6: the strip carries the caller's type role, and it follows the home", function()
	it("a bound textSize reaches the segments and re-reads when the placement moves", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = PHONE.w, h = PHONE.h })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local conditions = Facet.adaptive.conditions(core, env)
		local role = core:memo(function(use)
			local home = use(conditions.navPlacement)
			return if home == "bottomBar" or home == "bottomBarCompact" then "caption" else "body"
		end)
		local tv = Facet.Controls.TabView(core, {
			id = "Tabs",
			selection = core:signal("home"),
			env = env,
			textSize = role,
			tabs = tabsOf({ "home", "feed", "me" }),
		})
		pres.present(UI.Screen({ id = "S", children = { tv.blueprint } }), { sinkNavigation = true })
		pres.refresh()
		expect(tv.dump().placement).toBe("bottomBar")
		local band = adapter.node("/S/Tabs/BottomHome/then/BottomBand/Strip/Indicator/Options/Opt1").props.textSize
		expect(type(band)).toBe("number")

		env:set("viewportRect", { x = 0, y = 0, w = DESKTOP.w, h = DESKTOP.h })
		env:set("preferredInput", "KeyboardAndMouse")
		pres.refresh()
		expect(tv.dump().placement).toBe("sidebar")
		local rail = adapter.node("/S/Tabs/RailHome/then/Rail/Strip/Indicator/Options/Opt1").props.textSize
		expect(rail > band).toBe(true)
		tv.dispose()
	end)

	it("declaring none leaves the segments at the Button's own default", function()
		local w = world()
		local bare = w.adapter.node(tabPath(w, 1)).props.textSize
		local sized = world({ textSize = "caption" })
		expect(sized.adapter.node(tabPath(sized, 1)).props.textSize < bare).toBe(true)
	end)
end)

--[[ §6 A DECLARED `hug` IN THE THUMB ZONE. The bottom band is the one home that is
	deliberately NOT a scroller, and this file's own comment says why: a `fill`
	strip divides the offer and has nothing to overflow with. That premise belongs
	to the DEFAULT, not to the home — a caller that declares `sizing = "hug"` gets
	natural-width segments there too, and until §6 they were parked at the leading
	edge of a band that could not scroll, so a strip wider than a phone simply ran
	off it. `p1_glade` is that caller: its bottom bar has always been a centred
	natural-width cluster, because equal-width segments truncate four localized
	words on a 320px phone (measured: three of the four, at the +4 text offset). ]]
describe("§6: a declared `hug` bottom band centres and scrolls, like every other hugging home", function()
	local LONG = {
		{ id = "avatars", label = "Avatars", content = body("avatars") },
		{ id = "body", label = "Bodywork", content = body("body") },
		{ id = "clothing", label = "Clothing", content = body("clothing") },
		{ id = "backgrounds", label = "Backgrounds", content = body("backgrounds") },
	}

	it("the default is untouched: an automatic band still fills, in the shipped shape", function()
		local w = world({ viewport = PHONE })
		expect(w.tv.dump().sizing).toBe("fill")
		expect(w.adapter.node("/S/Tabs/BottomHome/then/BottomBand/Strip") ~= nil).toBe(true)
		expect(w.adapter.node("/S/Tabs/BottomHome/then/BottomBandCenter/BottomBand")).toBeNil()
	end)

	it("a declared hug band is CENTRED — measured, not named", function()
		local w = world({ viewport = PHONE, sizing = "hug" })
		expect(w.tv.dump().placement).toBe("bottomBar")
		expect(w.tv.dump().sizing).toBe("hug")
		local strip = w.adapter.node("/S/Tabs/BottomHome/then/BottomBandCenter/BottomBand/Strip").rect
		local root = w.adapter.node("/S/Tabs").rect
		local left, right = strip.x - root.x, (root.x + root.w) - (strip.x + strip.w)
		expect(strip.w < root.w).toBe(true) -- it HUGS, which is what makes a gap exist
		expect(math.abs(left - right) <= 1).toBe(true)
		expect(left > 0).toBe(true)
	end)

	it("...and a hug band that does NOT fit takes the whole band and SCROLLS", function()
		local w = world({ viewport = PHONE, sizing = "hug", tabs = LONG })
		local band = w.adapter.node("/S/Tabs/BottomHome/then/BottomBandCenter/BottomBand").rect
		local root = w.adapter.node("/S/Tabs").rect
		local strip = w.adapter.node("/S/Tabs/BottomHome/then/BottomBandCenter/BottomBand/Strip").rect
		expect(band.x).toBe(root.x)
		expect(band.w).toBe(root.w)
		expect(strip.w > band.w).toBe(true) -- there really is something to scroll
		expect(#w.handle.controller.diagnostics()).toBe(0)
	end)
end)

--[[ §6 THE RAIL'S BAND. A rail is content-sized by default, which is right until a
	1.4x locale at the largest text preference makes the longest tab name the whole
	rail: `p3_sipworks` measured its own hand-built rail growing past 400px and
	squeezing the content lane, and capped it — "a rail is a rail: it states its
	band and the labels adapt inside it". The rail is the construct's node now, so
	the band has to be sayable here or that finding is lost in the migration. ]]
describe("§6: the sidebar rail's width is the caller's to state", function()
	it("the default is content-sized, and a declared band is honoured", function()
		local bare = world({ viewport = DESKTOP, preferredInput = "KeyboardAndMouse" })
		local natural = bare.adapter.node("/S/Tabs/RailHome/then/Rail").rect.w
		expect(natural > 0).toBe(true)
		local capped = world({
			viewport = DESKTOP,
			preferredInput = "KeyboardAndMouse",
			railWidth = { type = "minMax", min = 240, ideal = 240, max = 260 },
		})
		local railed = capped.adapter.node("/S/Tabs/RailHome/then/Rail").rect.w
		expect(railed).toBe(240)
		expect(railed ~= natural).toBe(true)
		-- ...and the content really did get the rest of the row
		local content = capped.adapter.node("/S/Tabs/Content").rect
		expect(content.x >= railed - 1).toBe(true)
	end)

	it("a rail band declared for a placement that has no rail refuses", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			Facet.Controls.TabView(core, {
				id = "X",
				selection = core:signal("a"),
				placement = "bottomBar",
				railWidth = { type = "fixed", px = 200 },
				tabs = { { id = "a", content = body("a") } },
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(string.lower(tostring(err)), "railwidth", 1, true) ~= nil).toBe(true)
		expect(string.find(string.lower(tostring(err)), "sidebar", 1, true) ~= nil).toBe(true)
	end)
end)
