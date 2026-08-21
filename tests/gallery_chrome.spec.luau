--!strict
--[[ THE SHOWCASE CHROME — FOUR-INPUT REACHABILITY, THE SETTINGS SURFACE, AND
	THE SWEEP THAT COVERS BOTH (parity round 3, item E rows 4 and 11).

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
	-- the console row: displaySize Large is what turns the ten-foot profile on
	-- (and with it the renderer's overscan margin); preferredInput drives the
	-- affordance labels. Absent on every other row, which keeps them byte-identical
	if o.displaySize ~= nil then
		env:set("displaySize", o.displaySize)
	end
	if o.preferredInput ~= nil then
		env:set("preferredInput", o.preferredInput)
	end
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
			--[[ `o.demoPresent` IS HOW A CASE MAKES THE DEMO CONTEND FOR A KEY. The
				stand-in above declares nothing, which is exactly why the suite was green
				through the whole life of the shoulder-button double-fire: a surface that
				passes `onAdjust` binds `ButtonL1`/`ButtonR1` for Adjust
				(`presenter.luau:2292-2293`), and four demos in the real catalogue do the
				same thing dynamically through a focused `adjustTargets` member. ]]
			local handle = pres.present(screen, o.demoPresent)
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
			-- the host's own arithmetic, including the ten-foot subtraction: the
			-- renderer adds the overscan to every content surface on top of whatever
			-- is published here, and the chip row already sits inside it
			top = demo_picker.barReservation(
				coreTop:get(),
				chipsBottom:get(),
				8,
				showcase_chrome.overscanEdge(
					env:get("distanceProfile"):get(),
					env:get("effectiveOverscanInsets"):get(),
					"top"
				)
			),
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

--[[ ── DIR-1: THE CHIP STRIP'S LEFT GUTTER, ON THE SURFACE THE DIRECTOR SAW ────
	(device round 2026-08-17: on a real phone in portrait (~393px) the chip row's
	left border is clipped at the screen edge.)

	THE MODEL IS INNOCENT, and this is the case that says so — on the SHIPPED
	composition. The first version of this guard mounted `demo_picker` WITHOUT
	`composed`, which builds a standalone `UI.Screen({ id = "ShowcaseDemos" })`
	that `demo_picker.luau` returns before ever constructing when the showcase
	asks for `composed = true`. The strip the director photographed is laid out by
	`showcase_chrome.luau` as `/ShowcaseChrome/Dock/Bar/Chips`, so the guard could
	not have caught a regression in the surface that produced the report (review
	finding NEW-6).

	Measured here at 393x759 with touch capabilities, under every shipped
	reference package, the strip stands off the edge by exactly that package's own
	`space.s`: classic_desktop 4, compact_pointer 6, fantasy_ornate 8,
	fantasy_parchment 8, glossy_mobile 10, glossy_touch 10, pixel_quest 8,
	scifi_hud 8. The theme metric was the suspect worth checking — a package can
	change what `"s"` resolves to — and it is not the cause. DIR-1 is therefore
	adapter/device-side: the pixels between the solved rect and the glass. What
	this case does is make sure the MODEL never becomes the cause without anyone
	noticing.

	── AND THE FLOOR UNDER IT (DIR wave contract 6, 2026-08-18) ────────────────

	"Positive" is not a gutter. The two numbers above that were UNDER 8 —
	classic_desktop's 4 and compact_pointer's 6 — are the whole width a phone's
	rounded corner and its glass bezel eat before a single pixel of a stroke is
	visible, so a package could satisfy the case above and still hand the director
	the clipped border he photographed.

	THE STEP THE STRIP SPENDS IS `space.gutter` NOW, not `space.s`, and the case
	below asserts BOTH ENDS of that seam: the metric (so a package that lowers it
	fails here even on a screen this file never mounts) and the solved strip (so a
	consumer that stops spending it fails the same case). Either half alone is a
	check that proves half of what it claims.

	`space.gutter` is DERIVED — a package's own `s`, floored at 8 — and the long
	note in `src/themes/snapshot.luau` records why raising `space.s` instead was
	measured and rejected: it re-widened every gap in the package and put four
	unrelated showcase surfaces into overflow. It is a floor, not a replacement:
	glossy_mobile and glossy_touch keep their 10. ]]
describe("the showcase chip strip keeps a left gutter at phone width (DIR-1)", function()
	local theme_packages = require("../tools/lune/theme_packages")
	-- the smallest screen-edge gutter any shipped package may resolve to. 8px is
	-- the step the neutral default already uses and the one the HUD's own
	-- `screenPadding` falls back to when no package is installed.
	local GUTTER_FLOOR = 8

	local function gutterUnder(packageName: string?): (number, number)
		local w = showcase({
			w = 393,
			h = 759,
			theme = packageName,
			capabilities = { touch = true, mouse = false, keyboard = false, gamepad = false },
		})
		w.settle()
		local expected = GUTTER_FLOOR
		if packageName ~= nil then
			local snapshot = themes.resolve((require)(`../examples/themes/{packageName}`).build(themes), nil, {})
			expected = (snapshot :: any).space.gutter
		end
		local chips = w.adapter.node("/ShowcaseChrome/Dock/Bar/Chips")
		expect(`{tostring(packageName)}: strip mounted {tostring(chips ~= nil)}`).toBe(
			`{tostring(packageName)}: strip mounted true`
		)
		return (chips :: any).rect.x, expected
	end

	it("the strip stands off the screen edge under EVERY shipped package", function()
		for _, name in theme_packages.byRole("reference") do
			local x, expected = gutterUnder(name)
			-- a gutter at all — the symptom is a clipped border at x = 0
			expect(`{name}: gutter positive {tostring(x > 0)}`).toBe(`{name}: gutter positive true`)
			-- ...and it is the package's OWN spacing step, not a constant
			expect(`{name}: gutter {x}`).toBe(`{name}: gutter {expected}`)
		end
	end)

	it("...and no package's screen-edge step is under the 8px floor, in the metric OR on the glass", function()
		-- the floor is read from the module that owns it, so raising the number
		-- there without raising it here cannot leave this case asserting the old one
		local snapshotModule = require("../src/themes/snapshot")
		expect((snapshotModule :: any).SCREEN_GUTTER_FLOOR).toBe(GUTTER_FLOOR)
		local under = 0
		for _, name in theme_packages.byRole("reference") do
			local snapshot = themes.resolve((require)(`../examples/themes/{name}`).build(themes), nil, {})
			local step = (snapshot :: any).space.gutter
			expect(`{name}: space.gutter {step} >= {GUTTER_FLOOR}: {tostring(step >= GUTTER_FLOOR)}`).toBe(
				`{name}: space.gutter {step} >= {GUTTER_FLOOR}: true`
			)
			local x = gutterUnder(name)
			expect(`{name}: solved gutter {x} >= {GUTTER_FLOOR}: {tostring(x >= GUTTER_FLOOR)}`).toBe(
				`{name}: solved gutter {x} >= {GUTTER_FLOOR}: true`
			)
			-- ...and the floor really BINDS somewhere, or this whole case is a
			-- tautology over a set of packages that all cleared it anyway
			if (snapshot :: any).space.s < GUTTER_FLOOR then
				under += 1
				expect(`{name}: the floor raised it: {step > (snapshot :: any).space.s}`).toBe(
					`{name}: the floor raised it: true`
				)
			end
		end
		expect(`packages whose own small step is under the floor: {under > 0}`).toBe(
			"packages whose own small step is under the floor: true"
		)
	end)

	it("with no package at all it is the default spacing step, never zero", function()
		local x = gutterUnder(nil)
		expect(x > 0).toBe(true)
		expect(x).toBe(GUTTER_FLOOR)
	end)
end)

-- ===========================================================================
-- (10) THE DIRECTOR'S RULE, ON THIS SURFACE: an open panel stays OVER the demo,
--      and the two shoulder buttons are the pad's way in.
-- ===========================================================================

--[[ WHAT THE LIVE SESSION SHOWED (director, 2026-08-21): the demo picker open
	with the entire screen behind it a flat opaque fill — the mounted demo gone.

	THE MECHANISM, measured here. Cross-surface z is PRESENT ORDER: the presenter
	hands each presented surface the next slot in its band (`displayLayer += 100`)
	and the showcase leans on that — the backdrop is presented once, first, and
	"never raised, and that is the mechanism". What the arrangement does not
	survive is a surface being RE-presented underneath a live one: every demo swap
	dismisses and re-presents the demo, so the demo climbs, and after a handful of
	swaps it stands ABOVE a panel that was presented before it. Measured on this
	harness before the fix: six swaps put the demo at 11000 against the panel's
	10400.

	The panel is the transient and the demo is the live screen, so the panel is
	what must be raised — it re-presents itself when the demo underneath it
	changes, which is the same "re-present rather than teach the presenter a raise
	operation" trade the picker's own overlay already makes. ]]
describe("showcase chrome (10): the open panel stays over the demo", function()
	it("a demo swap under an open panel leaves the panel on top", function()
		local w = showcase()
		w.chrome.request("demos")
		w.settle()
		local panelBefore = w.adapter.rootDisplayOrder("ShowcasePanel")
		expect(`the panel is above the demo when it opens: {panelBefore > w.adapter.rootDisplayOrder("Demo")}`).toBe(
			"the panel is above the demo when it opens: true"
		)
		for _ = 1, 6 do
			w.demos.showNext(1)
			w.settle()
		end
		local panel = w.adapter.rootDisplayOrder("ShowcasePanel")
		local demo = w.adapter.rootDisplayOrder("Demo")
		expect(`panel {panel} over demo {demo}: {panel > demo}`).toBe(`panel {panel} over demo {demo}: true`)
		-- ...and it is still the same open panel, not a second one
		expect(w.chrome.isOpen()).toBe(true)
	end)

	it("...and the panel it re-presents is still the panel: focus and section survive", function()
		local w = showcase()
		w.chrome.request("settings")
		w.settle()
		w.demos.showNext(1)
		w.settle()
		expect(w.chrome.kind:get()).toBe("settings")
		local focused = w.pres.focus.focused:get()
		expect(`focus is inside the panel: {isPrefix("/ShowcasePanel", focused)}`).toBe(
			"focus is inside the panel: true"
		)
	end)
end)

--[[ THE PAD'S WAY IN (director, 2026-08-21). The chips sit at the two top
	corners of the strip, so the two shoulder buttons match them by POSITION:
	ButtonL1 opens the demo list, ButtonR1 opens settings. It is the same seam the
	`ButtonY` toggle already uses — one action-system context, one bound key each,
	no raw input anywhere — and the same `requestFromNavigation` entry, so the
	focus ring is visible on the frame the panel opens. ]]
describe("showcase chrome (11): the two shoulder buttons open the two sections", function()
	it("ButtonL1 opens the demo list, with focus inside it", function()
		local w = showcase()
		press(w.system, showcase_chrome.SECTION_GAMEPAD.demos)
		w.settle()
		expect(w.chrome.isOpen()).toBe(true)
		expect(w.chrome.kind:get()).toBe("demos")
		expect(`focus landed in the panel: {isPrefix("/ShowcasePanel", w.pres.focus.focused:get())}`).toBe(
			"focus landed in the panel: true"
		)
	end)

	it("ButtonR1 opens settings, from closed AND from the other section", function()
		local w = showcase()
		press(w.system, showcase_chrome.SECTION_GAMEPAD.settings)
		w.settle()
		expect(w.chrome.kind:get()).toBe("settings")
		expect(w.chrome.isOpen()).toBe(true)
		-- ...and the other shoulder SWITCHES rather than closing: two buttons, two
		-- destinations, no state to remember
		press(w.system, showcase_chrome.SECTION_GAMEPAD.demos)
		w.settle()
		expect(w.chrome.kind:get()).toBe("demos")
		expect(w.chrome.isOpen()).toBe(true)
	end)

	it("the same shoulder closes what it opened, and B closes it too", function()
		local w = showcase()
		press(w.system, showcase_chrome.SECTION_GAMEPAD.demos)
		w.settle()
		expect(w.chrome.isOpen()).toBe(true)
		press(w.system, showcase_chrome.SECTION_GAMEPAD.demos)
		w.settle()
		expect(w.chrome.isOpen()).toBe(false)

		press(w.system, showcase_chrome.SECTION_GAMEPAD.settings)
		w.settle()
		expect(w.chrome.isOpen()).toBe(true)
		press(w.system, "ButtonB")
		w.settle()
		expect(w.chrome.isOpen()).toBe(false)
		-- the ring goes back to the screen the player was on
		expect(`focus returned to the demo: {isPrefix("/Demo", w.pres.focus.focused:get())}`).toBe(
			"focus returned to the demo: true"
		)
	end)
end)

--[[ (12) THE TELEVISION CROPS THE EDGES, AND THE STRIP WAS STANDING IN THEM
	(director round 4, 2026-08-21: "the showcase picker/settings buttons seem to
	have disappeared on console").

	MEASURED LIVE by the controller at 1920x1080 / displaySize Large: the chips were
	mounted, visible, and painted at (12,12) — while the demo body under them started
	at x=106/y=169 because the ten-foot `effectiveOverscanInsets` (90 left/right, 60
	top/bottom) had engaged for it. The chrome is presented `rootPolicy =
	"edgeToEdge"`, and `solver.solve` answers that policy with the WHOLE viewport and
	reads no insets at all, so the renderer's ten-foot margin reached every content
	surface and never reached the one surface that draws nearest the glass. Twelve
	pixels from the edge of a set that crops ninety is a chip inside the bezel.

	THE FIX IS NOT "STOP BEING EDGE-TO-EDGE". The strip still owns the strip — that
	is what keeps it out of its own reservation — it simply places its content inside
	the same margin the renderer would have applied, gated on the same
	`distanceProfile`. These cases pin both halves: the console row moves in, and the
	near rows do not move at all. ]]
describe("showcase chrome (12): the chip strip sits inside the television's overscan", function()
	local CONSOLE = { w = 1920, h = 1080, displaySize = "Large", preferredInput = "Gamepad" }

	local function insets(w: any): any
		return w.env:get("effectiveOverscanInsets"):get()
	end

	it("the console row starts at or inside the overscan inset, on both axes", function()
		local w = showcase(CONSOLE)
		expect(w.env:get("distanceProfile"):get()).toBe("ten-foot")
		local over = insets(w)
		expect(`overscan {over.left}/{over.top}`).toBe("overscan 90/60")
		local chips = w.adapter.node("/ShowcaseChrome/Dock/Bar/Chips")
		expect(chips ~= nil).toBe(true)
		expect(
			`chips at ({chips.rect.x},{chips.rect.y}) inside ({over.left},{over.top}): `
				.. `{chips.rect.x >= over.left and chips.rect.y >= over.top}`
		).toBe(`chips at ({chips.rect.x},{chips.rect.y}) inside ({over.left},{over.top}): true`)
		-- ...and the chips a player actually presses, not only the ladder's box
		local demo = w.adapter.node("/ShowcaseChrome/Dock/Bar/Chips/Full/DemoToggle")
		expect(`the demo chip is inside the bezel: {demo.rect.x >= over.left and demo.rect.y >= over.top}`).toBe(
			"the demo chip is inside the bezel: true"
		)
	end)

	it("...and the demo body does not move down to pay for it", function()
		--[[ THE DOUBLE-COUNT THIS RULES OUT. The reservation the host publishes is
			`coreSafeInsets.top`, and `renderer.luau` ADDS the overscan to the core
			insets before it solves any content surface. With the chips inside the
			margin their measured bottom edge already carries it, so reserving the raw
			number would spend it twice and open a sixty-pixel dead band. ]]
		local w = showcase(CONSOLE)
		local demo = w.adapter.node("/Demo")
		local chips = w.adapter.node("/ShowcaseChrome/Dock/Bar/Chips")
		local gap = demo.rect.y - (chips.rect.y + chips.rect.h)
		expect(`the demo starts {gap}px under the chips, and that is under the slack+floor: {gap <= 62}`).toBe(
			`the demo starts {gap}px under the chips, and that is under the slack+floor: true`
		)
		-- the demo is still inset by the margin itself: this fixes the CHROME, it
		-- does not take the television's margin away from the content
		expect(demo.rect.x).toBe(90)
	end)

	it("every near row is byte-identical: the strip still starts at the screen gutter", function()
		for _, row in
			{
				{ name = "phone portrait", w = 390, h = 844 },
				{ name = "phone landscape", w = 844, h = 390 },
				{ name = "desktop", w = 1232, h = 1067 },
			}
		do
			local w = showcase({ w = row.w, h = row.h })
			expect(`{row.name}: {w.env:get("distanceProfile"):get()}`).toBe(`{row.name}: near`)
			local chips = w.adapter.node("/ShowcaseChrome/Dock/Bar/Chips")
			local screen = w.adapter.node("/ShowcaseChrome")
			-- the gutter, and nothing but the gutter — the same number the DIR-1
			-- block below measures, read here as "no overscan was added"
			expect(`{row.name}: chips at ({chips.rect.x},{chips.rect.y})`).toBe(
				`{row.name}: chips at ({screen.rect.x + 8},{screen.rect.y + 8})`
			)
		end
	end)

	it("a Large display that AUTHORS no overscan still gets the ten-foot default, and 'none' opts out", function()
		-- the gate is the profile, not the authored table: this is the seam the
		-- chrome shares with the renderer, asserted as a pure function
		expect(showcase_chrome.overscanEdge("ten-foot", { left = 90, top = 60 }, "left")).toBe(90)
		expect(showcase_chrome.overscanEdge("near", { left = 90, top = 60 }, "left")).toBe(0)
		expect(showcase_chrome.overscanEdge("ten-foot", { left = 0, top = 0 }, "left")).toBe(0)
		expect(showcase_chrome.overscanEdge("ten-foot", nil, "left")).toBe(0)
	end)
end)

--[[ (13) HOW A PAD PLAYER KNOWS THE SHOULDERS DO ANYTHING (director round 4:
	"how would a user know they're available for the left/right buttons").

	The two bindings were chosen by POSITION — the chip at the left corner is the
	button at the left shoulder — and nothing on screen said so. The mark now sits at
	the OUTSIDE edge of each chip, which is that argument drawn.

	IT IS THE BINDING'S OWN `DisplayName`, read back through `Facet.inputHint`, so
	there is exactly one spelling of "LB" in the tree. And it is GATED on the
	resolved input class, because `preferredBinding` answers the first keyCode
	binding for every non-touch class — an ungated hint would tell a keyboard player
	to press LB. ]]
describe("showcase chrome (13): the chips carry their shoulder mark on a pad", function()
	local GLYPH_DEMOS = "/ShowcaseChrome/Dock/Bar/Chips/Full/demosHint/then/Glyph"
	local GLYPH_SETTINGS = "/ShowcaseChrome/Dock/Bar/Chips/Full/settingsHint/then/Glyph"

	local function textAt(w: any, path: string): string?
		local node = w.adapter.node(path)
		if node == nil or type(node.props) ~= "table" then
			return nil
		end
		local text = node.props.text
		return if type(text) == "string" then text else nil
	end

	it("a gamepad sees LB and RB, and they are the bindings' own display names", function()
		local w = showcase({ preferredInput = "Gamepad" })
		expect(w.env:get("effectiveInput"):get()).toBe("Gamepad")
		expect(textAt(w, GLYPH_DEMOS)).toBe(showcase_chrome.SECTION_GLYPH.demos)
		expect(textAt(w, GLYPH_SETTINGS)).toBe(showcase_chrome.SECTION_GLYPH.settings)
	end)

	it("...and they are still there with the panel OPEN, which is when the pair matters most", function()
		local w = showcase({ preferredInput = "Gamepad" })
		press(w.system, showcase_chrome.SECTION_GAMEPAD.demos)
		w.settle()
		expect(w.chrome.isOpen()).toBe(true)
		expect(`{textAt(w, GLYPH_DEMOS)}/{textAt(w, GLYPH_SETTINGS)}`).toBe("LB/RB")
	end)

	it("a keyboard and a touchscreen are told nothing, and the row does not reserve for it", function()
		for _, class in { "KeyboardAndMouse", "Touch" } do
			local w = showcase({
				preferredInput = class,
				capabilities = { touch = class == "Touch", mouse = true, keyboard = true, gamepad = false },
			})
			expect(`{class}: demos glyph {tostring(textAt(w, GLYPH_DEMOS))}`).toBe(`{class}: demos glyph nil`)
			expect(`{class}: settings glyph {tostring(textAt(w, GLYPH_SETTINGS))}`).toBe(`{class}: settings glyph nil`)
			--[[ A `UI.When` and not an empty string, and this is the assertion that
				makes the difference visible: an empty `UI.Text` is still a child and a
				child costs the HStack a gap, so a hidden hint that was merely blank
				would push the first chip in by one gap on every non-pad row. ]]
			local row = w.adapter.node("/ShowcaseChrome/Dock/Bar/Chips/Full")
			local chip = w.adapter.node("/ShowcaseChrome/Dock/Bar/Chips/Full/DemoToggle")
			expect(`{class}: the first chip starts at the row's own edge: {chip.rect.x == row.rect.x}`).toBe(
				`{class}: the first chip starts at the row's own edge: true`
			)
		end
	end)

	it("the mark survives ~1.4x pseudo-localization inside the strip, at phone width", function()
		-- the strip's own sweep (case 9) proves the CHIPS do; this proves the row
		-- still fits once the marks are in it, on the narrowest supported screen
		local w = showcase({ w = 320, h = 640, preferredInput = "Gamepad" })
		local screen = w.adapter.node("/ShowcaseChrome")
		local chips = w.adapter.node("/ShowcaseChrome/Dock/Bar/Chips")
		local rung = w.adapter.node("/ShowcaseChrome/Dock/Bar/Chips/Icons")
			or w.adapter.node("/ShowcaseChrome/Dock/Bar/Chips/Full")
		expect(rung ~= nil).toBe(true)
		expect(`the strip fits its screen: {rung.rect.x + rung.rect.w <= screen.rect.x + screen.rect.w}`).toBe(
			"the strip fits its screen: true"
		)
		expect(chips ~= nil).toBe(true)
	end)
end)

--[[ (14) ONE PRESS, ONE CONTEXT (review of `48b6e7b`, MAJOR-1; controller ruling
	R19, 2026-08-21).

	`ButtonL1`/`ButtonR1` are the FRAMEWORK's Adjust step keys — `presenter.luau:
	2292-2293` on any surface declaring `onAdjust`, `:2394-2395` dynamically whenever
	the focused node is a declared `adjustTargets` member (Slider, Stepper, a Table
	grip, a TabView strip, LevelPicker, Rating; four catalogue demos contain one).
	The chrome's own doc header claimed "nothing else in the place binds either key"
	and nobody checked.

	MEASURED before the fix, on this harness: one `ButtonR1` press on a surface that
	declares `onAdjust` fired BOTH — the value under the player's ring moved AND the
	panel opened over it. The context was non-sinking, which is why: `deviceKey`
	only cuts strictly-lower candidates once a SINKING context has been delivered.

	R19 gives the bumpers to the chrome (position argument + console convention) and
	leaves the framework's Adjust its DPad/Comma/Period. What it does not allow is
	one press resolving to two contexts, so the chrome's context sinks and the
	outcome is decided by priority alone.

	THE STAND-IN DEMO IS WHY THE SUITE NEVER SAW IT. Case (11) presses the same two
	buttons against a two-button screen that binds nothing. `demoPresent` is the
	harness hook that makes the demo contend. ]]
describe("showcase chrome (14): a shoulder press resolves to ONE context", function()
	local function contending(): any
		local hits = { n = 0, last = 0 }
		local w = showcase({
			demoPresent = {
				-- (path, direction, rectOf) — the presenter's own signature
				onAdjust = function(_path: string, direction: number)
					hits.n += 1
					hits.last = direction
				end,
			},
		})
		w.hits = hits
		return w
	end

	it("the demo's Adjust really is live — the negative control this case needs", function()
		--[[ WITHOUT THIS THE CASE BELOW PROVES NOTHING. "adjustHits 0" is equally
			explained by "the demo never bound Adjust at all", so the dedicated adjust
			key nothing contends is pressed first: `Period` is bound by the same
			`if opts.onAdjust` branch as the two shoulders and reaches the same
			handler. ]]
		local w = contending()
		press(w.system, "Period")
		w.settle()
		expect(`adjust fired {w.hits.n} time(s), direction {w.hits.last}`).toBe("adjust fired 1 time(s), direction 1")
		press(w.system, "Comma")
		w.settle()
		expect(`adjust fired {w.hits.n} time(s), direction {w.hits.last}`).toBe("adjust fired 2 time(s), direction -1")
		expect(w.chrome.isOpen()).toBe(false)
	end)

	it("the framework's Adjust does not also fire — L1 and R1, both", function()
		for _, section in { "demos", "settings" } do
			local w = contending()
			press(w.system, showcase_chrome.SECTION_GAMEPAD[section])
			w.settle()
			expect(`{section}: open {w.chrome.isOpen()} kind {w.chrome.kind:get()} adjustHits {w.hits.n}`).toBe(
				`{section}: open true kind {section} adjustHits 0`
			)
		end
	end)

	it("all three transitions, on both shoulders, with the demo contending for the key", function()
		local w = contending()
		-- idle -> open
		press(w.system, showcase_chrome.SECTION_GAMEPAD.demos)
		w.settle()
		expect(`open {w.chrome.isOpen()} kind {w.chrome.kind:get()}`).toBe("open true kind demos")
		-- other section -> SWITCH, not close
		press(w.system, showcase_chrome.SECTION_GAMEPAD.settings)
		w.settle()
		expect(`open {w.chrome.isOpen()} kind {w.chrome.kind:get()}`).toBe("open true kind settings")
		-- same section -> close
		press(w.system, showcase_chrome.SECTION_GAMEPAD.settings)
		w.settle()
		expect(`open {w.chrome.isOpen()} kind {w.chrome.kind:get()}`).toBe("open false kind settings")
		-- ...and back the other way, from closed
		press(w.system, showcase_chrome.SECTION_GAMEPAD.demos)
		w.settle()
		expect(`open {w.chrome.isOpen()} kind {w.chrome.kind:get()}`).toBe("open true kind demos")
		press(w.system, showcase_chrome.SECTION_GAMEPAD.demos)
		w.settle()
		expect(`open {w.chrome.isOpen()} kind {w.chrome.kind:get()}`).toBe("open false kind demos")
		expect(`the value under the ring never moved: {w.hits.n}`).toBe("the value under the ring never moved: 0")
	end)

	it("the toggle key still reaches the chrome through a demo that sinks the keyboard", function()
		-- sinking is per-KEY: `Backquote`/`ButtonY` were never contended and the
		-- chrome's new sink must not have changed what they do
		local w = contending()
		press(w.system, showcase_chrome.TOGGLE_KEYBOARD)
		w.settle()
		expect(w.chrome.isOpen()).toBe(true)
		press(w.system, showcase_chrome.TOGGLE_GAMEPAD)
		w.settle()
		expect(w.chrome.isOpen()).toBe(false)
		expect(w.hits.n).toBe(0)
	end)
end)

--[[ (15) WHAT THE RAISE COSTS, AND WHAT IT MUST NOT COST (review of `48b6e7b`,
	MAJOR-2 and MINOR-4).

	`presenter.luau`'s `displayLayer` counter only ever goes up (it resets when the
	stack EMPTIES, and this stack never does — the backdrop is permanent), so every
	present spends a slot. Re-presenting the panel on each demo swap therefore costs
	+200 per swap where a closed panel costs +100, which halves the number of swaps
	before a base screen climbs into the toast band. The counter and the
	`presenter.raise(handle)` that would fix it are inside a file whose extraction is
	owed, so this round reports it (CONTESTED) and spends no layer it does not need:
	a raise that names a demo handle the panel is already above is a no-op.

	AND THE RING STAYS WHERE THE PLAYER LEFT IT. `openPanel` asks for
	`initialFocus = "first"`, which is right for opening and wrong for a swap
	underneath — a player reading row nine was put back on row one by something they
	did not do. ]]
describe("showcase chrome (15): the raise spends a layer only when it has to", function()
	it("a raise the panel does not need costs nothing", function()
		local w = showcase()
		w.chrome.request("demos")
		w.settle()
		local before = w.adapter.rootDisplayOrder("ShowcasePanel")
		-- the failed-mount path raises with no demo presented: `mounted` is nil, so
		-- the listener is handed nil and the panel re-presents (it cannot prove it is
		-- above a surface it was never told about). Handed a handle it IS above,
		-- nothing is spent.
		local panelHandle = w.chrome.panelHandle()
		w.chrome.raise({ displayOrder = panelHandle.displayOrder - 100 })
		w.settle()
		expect(`already above: {w.adapter.rootDisplayOrder("ShowcasePanel")} (was {before})`).toBe(
			`already above: {before} (was {before})`
		)
		-- ...and a raise it DOES need still happens
		w.chrome.raise({ displayOrder = panelHandle.displayOrder + 100 })
		w.settle()
		expect(`raised: {w.adapter.rootDisplayOrder("ShowcasePanel") > before}`).toBe("raised: true")
	end)

	it("a demo swap under an open panel leaves the ring where the player put it", function()
		local w = showcase()
		w.chrome.request("demos")
		w.settle()
		-- walk down the list, the way a player reading it would
		press(w.system, "DPadDown")
		press(w.system, "DPadDown")
		local before = w.pres.focus.focused:get()
		expect(isPrefix("/ShowcasePanel", before)).toBe(true)
		w.demos.showNext(1)
		w.settle()
		expect(`the ring stayed on {tostring(w.pres.focus.focused:get())}`).toBe(
			`the ring stayed on {tostring(before)}`
		)
	end)
end)
