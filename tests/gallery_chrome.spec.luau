--!strict
--[[ THE SHOWCASE CHROME — FOUR-INPUT REACHABILITY, THE SETTINGS SURFACE, AND
	THE SWEEP THAT COVERS BOTH (SwiftUI-parity round 3, item E rows 4 and 11).

	WHY THIS FILE IS DIFFERENT FROM ITS TWO NEIGHBOURS. `gallery_demo_picker.spec`
	and `gallery_theme_picker.spec` assert the PURE halves of their modules plus
	some solved geometry; the one claim neither of them could make was the one
	that mattered — "a player holding only a keyboard, or only a gamepad, can
	change the demo and change the theme". The nearest thing in the tree was
	`gallery_theme_picker.spec.luau:194`, which asserts that a source file
	*contains* the string `responder = "passive"`: a check that pins a constraint
	and says nothing at all about a capability.

	So everything below drives the REAL device path — `system.deviceKey(keyCode,
	isDown)` through the real `InputBinding` table, and `adapter.tap(path)`
	through the real hit path — against the real chrome mounted on a real
	presenter. Nothing here reads source text.

	THE DEFECT IT CLOSES, as measured before the fix:
	  · Backquote and ButtonY were bound to nothing anywhere in the place;
	  · the chrome presented `responder = "passive"`, whose nav context is created
	    DISABLED, and the only `engage()` call in `src/` is inside the presenter's
	    TAP handler — so a keyboard and a pad could never make the chrome first
	    responder, and Tab/Space were never bound on it;
	  · and — unreported until this round — the chrome re-presented itself after
	    every demo mount, so ITS focus scope was permanently the top one: Tab
	    landed on a chrome chip that could not be activated (Activate dispatched
	    against the DEMO's handle with a chrome path) and no key could reach a
	    single control of the demo on screen. Case (0) below is that regression. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local UI = require("../src/blueprint")
local fake_target = require("./lib/fake_target")
local device_views = require("./lib/device_views")
local demo_picker = require("../examples/gallery/client/demo_picker")
local theme_picker = require("../examples/gallery/client/theme_picker")
local settings_panel = require("../examples/gallery/client/settings_panel")
local showcase_chrome = require("../examples/gallery/client/showcase_chrome")
local themes = Facet.themes

-- the reference packages the showcase actually replicates, minus the
-- deliberately-degenerate fixtures (`theme_picker.isPickable`'s population split)
local SHIPPED_THEMES = {
	"classic_desktop",
	"compact_pointer",
	"fantasy_ornate",
	"fantasy_parchment",
	"glossy_mobile",
	"glossy_touch",
	"pixel_quest",
	"scifi_hud",
}

local function stubThemeController(): any
	return {
		install = function()
			return {
				inspect = function()
					return { fallback = false }
				end,
				swap = function() end,
				swapPackage = function() end,
				uninstall = function() end,
			}
		end,
	}
end

--[[ THE WHOLE SHOWCASE, AS `init.client.luau` ASSEMBLES IT — backdrop, strip,
	demo, and the chrome module that owns the panel. The demo is a two-button
	stand-in rather than a catalogue fixture on purpose: what is under test is
	whether the chrome and the demo can each be reached, and a stand-in with two
	known focusable paths makes "focus is on the demo" a assertion rather than an
	inference about somebody else's tree. ]]
local function showcase(opts: any?): any
	local o: any = opts or {}
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = o.w or 1232, h = o.h or 1067 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	env:set("capabilities", o.capabilities or { touch = false, mouse = true, keyboard = true, gamepad = true })
	if o.theme ~= nil then
		env:set("themeMetrics", themes.resolve((require)(`../examples/themes/{o.theme}`).build(themes), nil, {}))
	end
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system, { keyboardNavigation = true })

	-- the backdrop, presented first and never raised (z-order is present order)
	pres.present(
		UI.Screen({
			id = "ShowcaseBackdrop",
			surface = "base",
			children = { UI.Spacer({ id = "Fill", width = { type = "fill", weight = 1 } }) },
		}),
		{ responder = "passive", rootPolicy = "edgeToEdge" }
	)

	local chipsBottom = core:signal(nil :: number?)
	local coreTop = core:signal(o.coreTop or 0)
	local demoHandles: { any } = {}
	local chrome: any = nil
	local settings: any = nil

	local demos = demo_picker.mount({
		Facet = Facet,
		core = core,
		env = env,
		presenter = pres,
		composed = true,
		mountDemo = function(demo: any)
			local screen = UI.Screen({
				id = "Demo",
				padding = 8,
				gap = 8,
				children = {
					UI.Text({ id = "Title", text = demo.title }),
					UI.Button({ id = "D1", label = "Demo one" }),
					UI.Button({ id = "D2", label = "Demo two" }),
				},
			})
			local handle = pres.present(screen)
			table.insert(demoHandles, handle)
			return { screen = screen, handle = handle }
		end,
		onChip = function()
			chrome.request("demos")
		end,
		onChose = function()
			chrome.close()
		end,
		onRaise = function()
			if settings ~= nil then
				settings.apply()
			end
		end,
		warn = function() end,
	})

	local picker = theme_picker.mount({
		Facet = Facet,
		core = core,
		env = env,
		adapter = adapter,
		presenter = pres,
		packages = {
			glossy_touch = (require)("../examples/themes/glossy_touch").build(themes),
			pixel_quest = (require)("../examples/themes/pixel_quest").build(themes),
		},
		themeController = stubThemeController(),
		composed = true,
		collapsible = true,
		warn = function() end,
	})

	settings = settings_panel.mount({
		Facet = Facet,
		core = core,
		env = env,
		themeSections = if picker ~= nil then picker.sections else nil,
		onChip = function()
			chrome.request("settings")
		end,
		copy = o.copy,
	})

	chrome = showcase_chrome.mount({
		Facet = Facet,
		core = core,
		env = env,
		presenter = pres,
		actionSystem = system,
		demos = demos,
		settings = settings,
		coreTop = coreTop,
		onChipsBottom = function(bottom: number)
			if chipsBottom:get() ~= bottom then
				chipsBottom:set(bottom)
			end
		end,
	})
	demos.show(demos.current())
	for _ = 1, 3 do
		-- the reservation the host re-asserts every heartbeat, so the demo is laid
		-- out below the strip exactly as it is in the place
		env:set("coreSafeInsets", {
			top = demo_picker.barReservation(coreTop:get(), chipsBottom:get(), 8),
			bottom = 0,
			left = 0,
			right = 0,
		})
		pres.refresh()
	end
	return {
		core = core,
		env = env,
		system = system,
		adapter = adapter,
		pres = pres,
		demos = demos,
		picker = picker,
		settings = settings,
		chrome = chrome,
		chipsBottom = chipsBottom,
		demoHandles = demoHandles,
		settle = function()
			for _ = 1, 3 do
				pres.refresh()
			end
		end,
	}
end

local function press(system: any, key: string)
	system.deviceKey(key, true)
	system.deviceKey(key, false)
end

local function isPrefix(prefix: string, path: string?): boolean
	return path ~= nil and (path == prefix or string.sub(path, 1, #prefix + 1) == prefix .. "/")
end

-- ===========================================================================
-- (0) THE REGRESSION THE RESTRUCTURE FIXES: with the chrome closed, keyboard
--     and gamepad belong to the DEMO.
-- ===========================================================================
describe("showcase chrome (0): a closed chrome leaves the demo's own input alone", function()
	it("Tab reaches the demo, not the chip strip", function()
		local w = showcase()
		press(w.system, "Tab")
		local focused = w.pres.focus.focused:get()
		expect(`Tab landed on {tostring(focused)}; inside the demo: {isPrefix("/Demo", focused)}`).toBe(
			`Tab landed on {tostring(focused)}; inside the demo: true`
		)
	end)

	it("the d-pad reaches the demo too, and the strip is not the active focus scope", function()
		local w = showcase()
		press(w.system, "DPadDown")
		expect(isPrefix("/Demo", w.pres.focus.focused:get())).toBe(true)
		expect(w.pres.focus.activeScopeName()).toBe("Demo")
	end)

	it("the strip is presented, visible, and never above the demo in scope order", function()
		local w = showcase()
		local chips = w.adapter.node("/ShowcaseChrome/Dock/Bar/Chips")
		expect(chips ~= nil).toBe(true)
		expect(chips.rect.h > 0).toBe(true)
		-- ...and it is passive, which is what keeps it out of the demo's way
		expect(w.chrome.barHandle().responder:get()).toBe("passive")
	end)
end)

-- ===========================================================================
-- (0b) THE DEVICE REVIEW'S OWN FINDING (2026-08-16): "the demo list and
--      settings button aren't reachable with the dpad".
--
--      The four-input block below this one proves every ROUTE INTO the chrome
--      that the chrome itself declares — a toggle key on the keyboard, ButtonY
--      on the pad — and every one of them starts by pressing that toggle. Not
--      one of them asks the question a player asks first, which is "what does
--      the d-pad do", and the answer was NOTHING: the strip is presented before
--      the demo so the demo owns the scope, `navigateDirection` reads the top
--      scope alone, and a flat scope's ring wraps — so a d-pad pressed against
--      a demo walked that demo's own controls forever (measured trail:
--      D2,D1,D2,D1,…). The chips were reachable by pointer and by a button
--      nothing on screen names.
--
--      These cases drive the d-pad ONLY, from where a player actually starts.
-- ===========================================================================
describe("showcase chrome (0b): the d-pad alone reaches both chips", function()
	-- every path the ACTIVE scope's focus map carries, which is what navigation
	-- walks — as opposed to what any surface's props say about itself
	local function activePaths(w: any): { string }
		local out: { string } = {}
		for _, entry in ((w.pres.focus.focusMap() or {}).traversal or {}) do
			table.insert(out, entry.path)
		end
		return out
	end

	local function contains(list: { string }, want: string): boolean
		for _, v in list do
			if v == want then
				return true
			end
		end
		return false
	end

	it("the demo's own focus map carries the chips — one map, not two", function()
		local w = showcase()
		-- the map still BELONGS to the demo: adoption is reachability, not a takeover
		expect(w.pres.focus.activeScopeName()).toBe("Demo")
		local paths = activePaths(w)
		expect(contains(paths, "/Demo/D1")).toBe(true)
		expect(contains(paths, "/ShowcaseChrome/Dock/Bar/Chips/Full/DemoToggle")).toBe(true)
		expect(contains(paths, "/ShowcaseChrome/Dock/Bar/Chips/Full/SettingsToggle")).toBe(true)
	end)

	it("up from the demo lands on the demo-list chip, and right walks to Settings", function()
		local w = showcase()
		expect(isPrefix("/Demo", w.pres.focus.focused:get())).toBe(true)
		press(w.system, "DPadUp")
		expect(w.pres.focus.focused:get()).toBe("/ShowcaseChrome/Dock/Bar/Chips/Full/DemoToggle")
		press(w.system, "DPadRight")
		expect(w.pres.focus.focused:get()).toBe("/ShowcaseChrome/Dock/Bar/Chips/Full/SettingsToggle")
	end)

	it("...and down goes back to the demo, so the strip is somewhere you can leave", function()
		local w = showcase()
		press(w.system, "DPadUp")
		press(w.system, "DPadDown")
		expect(isPrefix("/Demo", w.pres.focus.focused:get())).toBe(true)
	end)

	it("ButtonA on the reached demo chip OPENS THE DEMO LIST — a pad, and nothing else", function()
		local w = showcase()
		press(w.system, "DPadUp")
		press(w.system, "ButtonA")
		expect(`open:{w.chrome.isOpen()} section:{w.chrome.kind:get()}`).toBe("open:true section:demos")
		-- ...and the list is what the panel is showing, reachable from here on
		w.settle()
		expect(isPrefix("/ShowcasePanel", w.pres.focus.focused:get())).toBe(true)
	end)

	it("ButtonA on the reached settings chip OPENS SETTINGS", function()
		local w = showcase()
		press(w.system, "DPadUp")
		press(w.system, "DPadRight")
		press(w.system, "ButtonA")
		expect(`open:{w.chrome.isOpen()} section:{w.chrome.kind:get()}`).toBe("open:true section:settings")
	end)

	it("the ring PAINTS when the d-pad puts it on a chip (a pad must see where it is)", function()
		local w = showcase()
		press(w.system, "DPadUp")
		expect(w.pres.focus.focusVisible:get()).toBe(true)
	end)

	it("a tap still moves focus onto a chip, and still does not paint the ring", function()
		local w = showcase()
		w.adapter.tap("/ShowcaseChrome/Dock/Bar/Chips/Full/SettingsToggle")
		w.settle()
		expect(w.pres.focus.focusVisible:get()).toBe(false)
	end)
end)

-- ===========================================================================
-- (1) KEYBOARD
-- ===========================================================================
describe("showcase chrome (1): a keyboard alone can change demo and change theme", function()
	it("the toggle key opens the panel, engages it, and lands focus inside it with the ring showing", function()
		local w = showcase()
		expect(w.chrome.isOpen()).toBe(false)
		press(w.system, showcase_chrome.TOGGLE_KEYBOARD)
		w.settle()
		expect(w.chrome.isOpen()).toBe(true)
		expect(w.chrome.panelHandle().responder:get()).toBe("engaged")
		local focused = w.pres.focus.focused:get()
		expect(`focus after the toggle key: {tostring(focused)} (in the panel: {isPrefix("/ShowcasePanel", focused)})`).toBe(
			`focus after the toggle key: {tostring(focused)} (in the panel: true)`
		)
		-- the ring PAINTS: a chrome opened from a key has to show where the next
		-- press goes (api.md "Focus identity vs the focus RING")
		expect(w.pres.focus.focusVisible:get()).toBe(true)
	end)

	it("Tab walks the panel and Return changes the demo", function()
		local w = showcase()
		press(w.system, showcase_chrome.TOGGLE_KEYBOARD)
		w.settle()
		local before = w.demos.current()
		-- walk until a demo row is focused, then press Return. Bounded by the
		-- panel's own focusable count so a broken scope fails instead of hanging.
		local landed: string? = nil
		for _ = 1, 40 do
			local focused = w.pres.focus.focused:get()
			-- ...and NOT the row already showing: choosing the live demo is a
			-- documented no-op, so landing there would prove nothing
			if
				focused ~= nil
				and string.find(focused, `/Rows/`, 1, true) ~= nil
				and not string.find(focused, `/Rows/{before}`, 1, true)
			then
				landed = focused
				break
			end
			press(w.system, "Tab")
		end
		expect(`Tab reached a demo row other than the live one: {landed ~= nil}`).toBe(
			"Tab reached a demo row other than the live one: true"
		)
		press(w.system, "Return")
		w.settle()
		expect(`the demo changed: {w.demos.current() ~= before}`).toBe("the demo changed: true")
		-- ...and choosing took the panel down, exactly as a tap does
		expect(w.chrome.isOpen()).toBe(false)
	end)

	it("Space activates too (the desktop convention), and only while the panel is engaged", function()
		local w = showcase()
		press(w.system, showcase_chrome.TOGGLE_KEYBOARD)
		w.settle()
		-- onto the section switch's 'Settings' option and press Space
		local reached = false
		for _ = 1, 40 do
			local focused = w.pres.focus.focused:get()
			if
				focused ~= nil
				and w.chrome.kind:get() == "demos"
				-- one level deeper since D6: the section switch is segmented, so it
				-- carries the sliding indicator by default
				and string.find(focused, "/Section/Indicator/Options/Opt2", 1, true) ~= nil
			then
				reached = true
				break
			end
			press(w.system, "Tab")
		end
		expect(`Tab reached the section switch: {reached}`).toBe("Tab reached the section switch: true")
		press(w.system, "Space")
		w.settle()
		expect(w.chrome.kind:get()).toBe("settings")
	end)

	it("the theme rows are reachable from the keyboard, through settings", function()
		local w = showcase()
		w.chrome.request("settings")
		w.settle()
		expect(w.chrome.panelHandle().responder:get()).toBe("engaged")
		local before = w.picker.selection:get().packageId
		local landed: string? = nil
		for _ = 1, 60 do
			local focused = w.pres.focus.focused:get()
			if focused ~= nil and string.find(focused, "/Packages/P_", 1, true) ~= nil then
				local id = string.match(focused, "/P_([%w%-]+)$")
				if id ~= nil and id ~= before then
					landed = focused
					break
				end
			end
			press(w.system, "Tab")
		end
		expect(`Tab reached another package row: {landed ~= nil} ({tostring(landed)})`).toBe(
			`Tab reached another package row: true ({tostring(landed)})`
		)
		press(w.system, "Return")
		w.settle()
		expect(`the theme changed: {w.picker.selection:get().packageId ~= before}`).toBe("the theme changed: true")
	end)

	it("the toggle key closes again, and focus goes back to the demo", function()
		local w = showcase()
		press(w.system, showcase_chrome.TOGGLE_KEYBOARD)
		w.settle()
		press(w.system, showcase_chrome.TOGGLE_KEYBOARD)
		w.settle()
		expect(w.chrome.isOpen()).toBe(false)
		expect(isPrefix("/Demo", w.pres.focus.focused:get())).toBe(true)
	end)
end)

-- ===========================================================================
-- (2) GAMEPAD
-- ===========================================================================
describe("showcase chrome (2): a gamepad alone can change demo and change theme", function()
	local PAD = { touch = false, mouse = false, keyboard = false, gamepad = true }

	it("the pad's toggle button opens the panel and engages it — with no keyboard anywhere", function()
		local w = showcase({ capabilities = PAD })
		press(w.system, showcase_chrome.TOGGLE_GAMEPAD)
		w.settle()
		expect(w.chrome.isOpen()).toBe(true)
		expect(w.chrome.panelHandle().responder:get()).toBe("engaged")
		expect(isPrefix("/ShowcasePanel", w.pres.focus.focused:get())).toBe(true)
	end)

	it("the d-pad walks the panel and ButtonA changes the demo", function()
		local w = showcase({ capabilities = PAD })
		press(w.system, showcase_chrome.TOGGLE_GAMEPAD)
		w.settle()
		local before = w.demos.current()
		local landed = false
		for _ = 1, 40 do
			local focused = w.pres.focus.focused:get()
			if
				focused ~= nil
				and string.find(focused, `/Rows/`, 1, true) ~= nil
				and not string.find(focused, `/Rows/{before}`, 1, true)
			then
				landed = true
				break
			end
			press(w.system, "DPadDown")
		end
		expect(`the d-pad reached a demo row other than the live one: {landed}`).toBe(
			"the d-pad reached a demo row other than the live one: true"
		)
		press(w.system, "ButtonA")
		w.settle()
		expect(`the demo changed: {w.demos.current() ~= before}`).toBe("the demo changed: true")
	end)

	it("ButtonB (Cancel) resigns the panel, which takes it down and returns the demo", function()
		local w = showcase({ capabilities = PAD })
		press(w.system, showcase_chrome.TOGGLE_GAMEPAD)
		w.settle()
		expect(w.chrome.isOpen()).toBe(true)
		press(w.system, "ButtonB")
		w.settle()
		expect(w.chrome.isOpen()).toBe(false)
		expect(isPrefix("/Demo", w.pres.focus.focused:get())).toBe(true)
	end)

	it("the motion setting is reachable and changeable with a pad alone", function()
		local w = showcase({ capabilities = PAD })
		expect(w.env:get("reducedMotion"):get() == true).toBe(false)
		press(w.system, showcase_chrome.TOGGLE_GAMEPAD)
		w.settle()
		-- section switch -> Settings, then onto the motion picker's Reduced option.
		--
		-- THE WALK USES BOTH AXES, and it has to since navigation-and-menus D5:
		-- `focus_map` now derives a HORIZONTAL group from an `AdaptiveStack`
		-- running along x, which is what every segmented picker's option stack is,
		-- so a segment's neighbour is to its RIGHT rather than below it. Right
		-- first, falling back to Down when it does not move, is the honest "a pad
		-- alone can reach this" walk either way.
		local function step()
			local before = w.pres.focus.focused:get()
			press(w.system, "DPadRight")
			if w.pres.focus.focused:get() == before then
				press(w.system, "DPadDown")
			end
		end
		local ok = false
		for _ = 1, 60 do
			local focused = w.pres.focus.focused:get()
			if focused == nil then
				step()
				continue
			end
			-- the section switch first (its second option is Settings)...
			if
				w.chrome.kind:get() == "demos"
				and string.find(focused, "/Section/Indicator/Options/Opt2", 1, true) ~= nil
			then
				press(w.system, "ButtonA")
				w.settle()
				continue
			end
			-- ...then the motion picker's second option, which is Reduced
			if string.find(focused, "/MotionMode/Indicator/Options/Opt2", 1, true) ~= nil then
				press(w.system, "ButtonA")
				w.settle()
				ok = true
				break
			end
			step()
		end
		expect(`the pad reached and pressed Reduced: {ok}`).toBe("the pad reached and pressed Reduced: true")
		expect(w.env:get("reducedMotion"):get()).toBe(true)
		expect(w.settings.setting:get()).toBe("reduced")
	end)
end)

-- ===========================================================================
-- (3) POINTER AND TOUCH — unchanged, and asserted so the fix cannot trade one
--     input class for another.
-- ===========================================================================
describe("showcase chrome (3): mouse and touch still work exactly as before", function()
	it("a tap on the demo chip opens the panel; a tap on a row chooses and closes", function()
		local w = showcase()
		w.adapter.tap("/ShowcaseChrome/Dock/Bar/Chips/Full/DemoToggle")
		w.settle()
		expect(w.chrome.isOpen()).toBe(true)
		expect(w.chrome.kind:get()).toBe("demos")
		local before = w.demos.current()
		local other = demo_picker.next(before, 1)
		w.adapter.tap(`/ShowcasePanel/Dock/Column/Panel/DemosWhen/then/Rows/{other}`)
		w.settle()
		expect(w.demos.current()).toBe(other)
		expect(w.chrome.isOpen()).toBe(false)
	end)

	it("a tap on the settings chip opens settings", function()
		local w = showcase()
		w.adapter.tap("/ShowcaseChrome/Dock/Bar/Chips/Full/SettingsToggle")
		w.settle()
		expect(w.chrome.isOpen()).toBe(true)
		expect(w.chrome.kind:get()).toBe("settings")
	end)

	it("a tap outside the open panel takes it down (the engaged-surface dismissal path)", function()
		local w = showcase()
		w.chrome.request("demos")
		w.settle()
		w.adapter.tap("/Demo/D1")
		w.settle()
		expect(w.chrome.isOpen()).toBe(false)
	end)
end)

-- ===========================================================================
-- (4) THE RESPONDER INVARIANTS the fix has to keep
-- ===========================================================================
describe("showcase chrome (4): exactly one engaged surface, and no stolen keys", function()
	it("the strip never holds first responder while the panel is up", function()
		local w = showcase()
		-- a tap on a focusable inside a passive surface engages it
		-- (presenter.luau:2248), so this is the case that would give us two
		w.adapter.tap("/ShowcaseChrome/Dock/Bar/Chips/Full/DemoToggle")
		w.settle()
		expect(w.chrome.panelHandle().responder:get()).toBe("engaged")
		expect(w.chrome.barHandle().responder:get()).toBe("passive")
	end)

	it("one Tab press moves the ring one step, not two", function()
		local w = showcase()
		w.adapter.tap("/ShowcaseChrome/Dock/Bar/Chips/Full/DemoToggle")
		w.settle()
		local map = w.pres.focus.focusMap("ShowcasePanel")
		expect(map ~= nil).toBe(true)
		local order: { string } = {}
		for _, entry in map.traversal do
			if entry.eligible then
				table.insert(order, entry.path)
			end
		end
		expect(#order > 3).toBe(true)
		local from = w.pres.focus.focused:get()
		local index = table.find(order, from)
		expect(`focus is in the panel's traversal order: {index ~= nil}`).toBe(
			"focus is in the panel's traversal order: true"
		)
		press(w.system, "Tab")
		local to = w.pres.focus.focused:get()
		local moved = (table.find(order, to) or -99) - (index or 0)
		expect(`one Tab moved {moved} step(s)`).toBe("one Tab moved 1 step(s)")
	end)

	it("the toggle context binds exactly the two documented keys, and nothing a demo uses", function()
		local w = showcase()
		-- a stand-in for everything the framework and the demos bind: if the
		-- chrome's own context claimed any of these, this would fire
		local contended = {
			"Tab",
			"Space",
			"Return",
			"Up",
			"Down",
			"Left",
			"Right",
			"ButtonA",
			"ButtonB",
			"ButtonX",
			"DPadUp",
			"DPadDown",
		}
		for _, key in contended do
			local openBefore = w.chrome.isOpen()
			press(w.system, key)
			expect(`{key} toggled the chrome: {w.chrome.isOpen() ~= openBefore}`).toBe(
				`{key} toggled the chrome: false`
			)
		end
		-- ...and the two that DO
		press(w.system, showcase_chrome.TOGGLE_KEYBOARD)
		expect(w.chrome.isOpen()).toBe(true)
		press(w.system, showcase_chrome.TOGGLE_KEYBOARD)
		expect(w.chrome.isOpen()).toBe(false)
		press(w.system, showcase_chrome.TOGGLE_GAMEPAD)
		expect(w.chrome.isOpen()).toBe(true)
	end)

	it("the toggle still works while the panel it opened is engaged and sinking", function()
		-- the priority claim: the chrome context sits above the engaged band, and
		-- sinking is per-key anyway
		expect(showcase_chrome.TOGGLE_PRIORITY > 3000).toBe(true)
		local w = showcase()
		press(w.system, showcase_chrome.TOGGLE_KEYBOARD)
		w.settle()
		expect(w.chrome.panelHandle().responder:get()).toBe("engaged")
		press(w.system, showcase_chrome.TOGGLE_KEYBOARD)
		expect(w.chrome.isOpen()).toBe(false)
	end)
end)

-- ===========================================================================
-- (5) THE TWO-CHIP LADDER (`[SHOWCASE-CHROME]: CONCERNS 16`)
-- ===========================================================================
describe("showcase chrome (5): two targets forever, stepping down to icon-only", function()
	it("the strip carries exactly two chips", function()
		expect(#showcase_chrome.KINDS).toBe(2)
		local w = showcase()
		local full = w.adapter.node("/ShowcaseChrome/Dock/Bar/Chips/Full")
		expect(full ~= nil).toBe(true)
		expect(w.adapter.node("/ShowcaseChrome/Dock/Bar/Chips/Full/DemoToggle") ~= nil).toBe(true)
		expect(w.adapter.node("/ShowcaseChrome/Dock/Bar/Chips/Full/SettingsToggle") ~= nil).toBe(true)
	end)

	local function rung(w: any): string
		local full = w.adapter.node("/ShowcaseChrome/Dock/Bar/Chips/Full")
		local icons = w.adapter.node("/ShowcaseChrome/Dock/Bar/Chips/Icons")
		local fullW = if full ~= nil and full.rect ~= nil then full.rect.w else 0
		local iconW = if icons ~= nil and icons.rect ~= nil then icons.rect.w else 0
		if fullW > 0 and iconW == 0 then
			return "full"
		end
		if iconW > 0 and fullW == 0 then
			return "icons"
		end
		return `ambiguous (full {fullW}, icons {iconW})`
	end

	it("a desktop shows the labels", function()
		expect(rung(showcase({ w = 1232, h = 1067 }))).toBe("full")
	end)

	it("the 320px phone that killed the third chip steps down to icons rather than clipping", function()
		-- the case CONCERNS 16 did the arithmetic on. The demo chip's label is the
		-- current demo's title, so the widest catalogue entry is what has to fit.
		local w = showcase({ w = 320, h = 640 })
		--[[ SELECTED BY LENGTH, NOT BY INDEX. This used to be `showNext(6)` with a
			comment naming the demo it landed on — and a catalogue entry inserted
			anywhere before that one silently re-aimed it at a shorter title, which is
			how the case went red on a round that only ADDED a fixture. The thing
			under test is "the widest catalogue entry has to fit", so derive it. ]]
		local widest = demo_picker.list()[1]
		for _, demo in demo_picker.list() do
			if #demo.title > #widest.title then
				widest = demo
			end
		end
		for _ = 1, #demo_picker.list() do
			if w.demos.current() == widest.id then
				break
			end
			w.demos.showNext(1)
		end
		w.settle()
		expect(`landed on the widest title: {w.demos.current()}`).toBe(`landed on the widest title: {widest.id}`)
		expect(rung(w)).toBe("icons")
	end)

	it("the losing rung is out of the focus order at every width, on both rungs", function()
		for _, view in { { 320, 640 }, { 1232, 1067 } } do
			local w = showcase({ w = view[1], h = view[2] })
			w.chrome.request("demos")
			w.settle()
			local live = rung(w)
			local dead = if live == "full" then "Icons" else "Full"
			local map = w.pres.focus.focusMap("ShowcaseChrome")
			for _, entry in (map or { traversal = {} }).traversal do
				expect(`{view[1]}x{view[2]}: {entry.path} is in the ring while '{dead}' lost`).toBe(
					`{view[1]}x{view[2]}: {entry.path} is in the ring while '{dead}' lost`
				)
				if string.find(entry.path, `/{dead}/`, 1, true) ~= nil then
					expect(`{view[1]}x{view[2]}: losing rung {entry.path} eligible: {entry.eligible}`).toBe(
						`{view[1]}x{view[2]}: losing rung {entry.path} eligible: false`
					)
				end
			end
		end
	end)
end)

-- ===========================================================================
-- (6) THE SETTINGS MODEL — pure half
-- ===========================================================================
describe("settings model: Full | Reduced, never on/off", function()
	it("the vocabulary is the two words, in that order", function()
		expect(showcase_chrome.COPY.settings).toBe("Settings")
		expect(settings_panel.MODES[1]).toBe("full")
		expect(settings_panel.MODES[2]).toBe("reduced")
		expect(settings_panel.COPY.full).toBe("Full")
		expect(settings_panel.COPY.reduced).toBe("Reduced")
	end)

	it("no player-visible string in this surface says on, off, disable or enable", function()
		-- the claim the header makes: a control labelled "Motion: Off" teaches the
		-- opposite of the framework's reduced-motion policy
		for key, value in settings_panel.COPY do
			local lower = string.lower(tostring(value))
			for _, banned in { "^off$", "^on$", "%f[%a]off%f[%A]", "%f[%a]disabled?%f[%A]" } do
				expect(`{key} ('{value}') matches '{banned}': {string.find(lower, banned) ~= nil}`).toBe(
					`{key} ('{value}') matches '{banned}': false`
				)
			end
		end
	end)

	it("maps onto the one environment fact both ways, and refuses to reduce on a typo", function()
		expect(settings_panel.modeOf(true)).toBe("reduced")
		expect(settings_panel.modeOf(false)).toBe("full")
		expect(settings_panel.modeOf(nil)).toBe("full")
		expect(settings_panel.reducedOf("reduced")).toBe(true)
		expect(settings_panel.reducedOf("full")).toBe(false)
		-- an unknown word must never silently REDUCE: that is the direction the
		-- player did not ask for
		expect(settings_panel.reducedOf("Reduced")).toBe(false)
		expect(settings_panel.choose("full", "nonsense").action).toBe("none")
		expect(settings_panel.choose("full", "full").action).toBe("none")
		expect(settings_panel.choose("full", "reduced").action).toBe("apply")
	end)

	it("the toggle state machine is a pure function of open x section", function()
		expect(showcase_chrome.toggle(false, "demos", nil).action).toBe("open")
		expect(showcase_chrome.toggle(true, "demos", nil).action).toBe("close")
		-- a chip press on the section already showing closes it; on the other one
		-- it switches
		expect(showcase_chrome.toggle(true, "demos", "demos").action).toBe("close")
		local switch = showcase_chrome.toggle(true, "demos", "settings")
		expect(switch.action).toBe("open")
		expect(switch.kind).toBe("settings")
		expect(showcase_chrome.otherKind("demos")).toBe("settings")
		expect(showcase_chrome.otherKind("settings")).toBe("demos")
	end)
end)

-- ===========================================================================
-- (7) THE SETTING IS PERSISTENT AND PLACE-WIDE — the reason row 11 was owed
-- ===========================================================================
describe("settings surface: the motion setting survives a demo swap", function()
	it("flipping it writes the real environment fact", function()
		local w = showcase()
		expect(w.env:get("reducedMotion"):get() == true).toBe(false)
		expect(w.settings.setMode("reduced")).toBe(true)
		expect(w.env:get("reducedMotion"):get()).toBe(true)
		expect(w.settings.mode:get()).toBe("reduced")
		-- and the derived policy follows, which is what makes it a real setting
		expect(w.pres.motionClock:isReduced()).toBe(true)
	end)

	it("...and it is still set after switching demos, which is what 'place-wide' means", function()
		local w = showcase()
		w.settings.setMode("reduced")
		for _ = 1, 3 do
			w.demos.showNext(1)
			w.settle()
		end
		expect(w.env:get("reducedMotion"):get()).toBe(true)
		expect(w.settings.mode:get()).toBe("reduced")
	end)

	it("a demo that drives the fact itself is a LOCAL override the setting outlives", function()
		local w = showcase()
		w.settings.setMode("reduced")
		-- a demo teardown that restores what it found (with_animation's documented
		-- behaviour) must not silently revert the preference
		w.env:set("reducedMotion", false)
		expect(w.settings.mode:get()).toBe("full") -- the card follows the live fact...
		expect(w.settings.setting:get()).toBe("reduced") -- ...and the preference does not
		w.settings.apply()
		expect(w.env:get("reducedMotion"):get()).toBe(true)
	end)

	it("flipping it RE-SOLVES without rebuilding: mount identity and factory runs are untouched", function()
		local w = showcase()
		local handle = w.demoHandles[#w.demoHandles]
		local before = handle.root.counters().factoryRuns
		local nodesBefore = #w.adapter.paths()
		w.settings.setMode("reduced")
		w.settle()
		local nodesAfter = #w.adapter.paths()
		expect(`factoryRuns {before} -> {handle.root.counters().factoryRuns}`).toBe(`factoryRuns {before} -> {before}`)
		expect(`instances {nodesBefore} -> {nodesAfter}`).toBe(`instances {nodesBefore} -> {nodesBefore}`)
		expect(w.pres.motionClock:isReduced()).toBe(true)
	end)
end)

-- ===========================================================================
-- (8) COMPOSITION WITH `with_animation`'s OWN INLINE CONTROL
-- ===========================================================================
describe("settings surface x with_animation: one fact, two editors", function()
	local function withAnimationWorld(reduced: boolean): any
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		env:set("reducedMotion", reduced)
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local fixture = (require)("../examples/gallery/scenarios/with_animation") :: any
		local built = fixture.build({
			Facet = Facet,
			core = core,
			env = env,
			actionSystem = system,
			presenter = pres,
		})
		built.handle = pres.present(built.screen, built.present)
		pres.refresh()
		return { core = core, env = env, pres = pres, built = built }
	end

	it("the fixture still inherits whatever the place-wide setting left behind", function()
		expect(withAnimationWorld(true).built.motionMode:get()).toBe("reduced")
		expect(withAnimationWorld(false).built.motionMode:get()).toBe("full")
	end)

	it("a settings flip moves the demo's own segmented control in the same frame", function()
		local w = withAnimationWorld(false)
		expect(w.built.motionMode:get()).toBe("full")
		-- what the settings card's picker does, through the same one fact
		w.env:set("reducedMotion", true)
		expect(w.built.motionMode:get()).toBe("reduced")
	end)

	it("the demo's own flip still restores on dispose — the trap that rule exists for", function()
		local w = withAnimationWorld(false)
		w.built.steps.setMotion(w.built, "reduced")
		expect(w.env:get("reducedMotion"):get()).toBe(true)
		w.built.dispose()
		expect(w.env:get("reducedMotion"):get()).toBe(false)
	end)

	it("and the host's re-apply is what makes the SETTING win over that restore", function()
		-- the exact sequence the showcase runs: setting = reduced, mount the demo
		-- (which inherits it), the demo restores what it found on dispose, and the
		-- host re-applies the preference on the next mount
		local w = showcase()
		w.settings.setMode("reduced")
		local inherited = w.env:get("reducedMotion"):get()
		expect(inherited).toBe(true)
		w.env:set("reducedMotion", false) -- the demo's restore, in miniature
		w.demos.showNext(1) -- ...and the next mount, which calls settings.apply()
		w.settle()
		expect(w.env:get("reducedMotion"):get()).toBe(true)
	end)
end)

-- ===========================================================================
-- (9) THE SHOWCASE RULE IN FULL: swept at every viewport, under every shipped
--     theme, on BOTH axes, and never overlapping the demo below.
-- ===========================================================================
describe("showcase chrome (9): the sweep", function()
	local function overflowsOf(w: any): { string }
		local out: { string } = {}
		for _, handle in { w.chrome.barHandle(), w.chrome.panelHandle() } do
			if handle == nil then
				continue
			end
			for _, finding in handle.controller.diagnostics() do
				if
					string.find(finding.issue, "on the main axis", 1, true) ~= nil
					or string.find(finding.issue, "on the cross axis", 1, true) ~= nil
				then
					table.insert(out, `{finding.node}: {finding.issue}`)
				end
			end
		end
		return out
	end

	it("no overflow on either axis, at any swept viewport, under any shipped theme", function()
		local problems: { string } = {}
		for _, theme in SHIPPED_THEMES do
			for _, view in device_views.VIEWS do
				for _, section in showcase_chrome.KINDS do
					local w = showcase({
						w = view.w,
						h = view.h,
						theme = theme,
						coreTop = device_views.CORE_TOP,
						capabilities = device_views.CAPABILITIES[view.input],
					})
					w.chrome.request(section)
					w.settle()
					for _, problem in overflowsOf(w) do
						table.insert(problems, `  {theme} {view.id} ({view.w}x{view.h}) [{section}]: {problem}`)
					end
				end
			end
		end
		if #problems > 0 then
			error(`the showcase chrome overflows in {#problems} place(s):\n{table.concat(problems, "\n")}`, 0)
		end
	end)

	it("the panel never overlaps the chip strip, under any shipped theme at 320x640", function()
		-- the case CONCERNS 16 did its arithmetic on, and the one the strip's
		-- reservation exists for
		local problems: { string } = {}
		for _, theme in SHIPPED_THEMES do
			for _, section in showcase_chrome.KINDS do
				local w = showcase({ w = 320, h = 640, theme = theme, coreTop = device_views.CORE_TOP })
				w.chrome.request(section)
				w.settle()
				local chips = w.adapter.node("/ShowcaseChrome/Dock/Bar/Chips")
				local panel = w.adapter.node("/ShowcasePanel/Dock/Column/Panel")
				if chips == nil or panel == nil then
					table.insert(problems, `  {theme} [{section}]: a surface did not render`)
					continue
				end
				local chipsBottom = chips.rect.y + chips.rect.h
				if panel.rect.y < chipsBottom then
					table.insert(
						problems,
						`  {theme} [{section}]: the panel starts at y={panel.rect.y} but the chips end at {chipsBottom}`
					)
				end
				-- ...and the strip itself fits the phone
				if chips.rect.x + chips.rect.w > 320 then
					table.insert(
						problems,
						`  {theme} [{section}]: the chip strip ends at x={chips.rect.x + chips.rect.w}`
					)
				end
			end
		end
		if #problems > 0 then
			error(`the chrome overlaps or overhangs at 320x640:\n{table.concat(problems, "\n")}`, 0)
		end
	end)

	it("every player-visible string survives ~1.4x pseudo-localization", function()
		-- the localization-safe-UI-text rider: expanded copy must wrap, never clip,
		-- and never push a surface past its own box. `copy` is an override the
		-- surface itself accepts, so this expands the SHIPPED strings rather than a
		-- test-local copy of them.
		local expanded: { [string]: string } = {}
		for key, value in settings_panel.COPY do
			local text = tostring(value)
			expanded[key] = text .. string.rep("~", math.ceil(utf8.len(text) or #text) * 0.4 // 1)
		end
		local problems: { string } = {}
		for _, view in { { 320, 640 }, { 640, 320 }, { 359, 718 } } do
			local w = showcase({ w = view[1], h = view[2], copy = expanded })
			w.chrome.request("settings")
			w.settle()
			for _, problem in overflowsOf(w) do
				table.insert(problems, `  {view[1]}x{view[2]}: {problem}`)
			end
		end
		if #problems > 0 then
			error(`pseudo-localized settings copy overflows:\n{table.concat(problems, "\n")}`, 0)
		end
	end)
end)
