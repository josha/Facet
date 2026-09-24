--!strict
local harness = require("./lib/harness")
--[[ D2 — THE `Menu` CONSTRUCT (navigation-and-menus brief §2 D2).

	A freestanding ACTION menu: items are VERBS, not values. It attaches to any
	blueprint, presents on D1's anchored seam, renders its rows from the ONE
	shared recipe, and opens on all five triggers — which together are what close
	the context-menu construct, listed Missing until this stage.

	Six things here are the ones a lower-level test cannot see, so they get named
	cases rather than a smoke test:

	  * a submenu nests with NO structural cap and says so at depth >= 2. A hard
	    cap forbids what the guidance allows; no diagnostic permits twice what the interface guidance
	    advises. Both halves have to be asserted, in one case.
	  * `children` AND `onSelect` on one item is a REFUSAL, not a precedence rule.
	  * a menu whose every item is disabled STILL OPENS.
	  * under `sheet` a submenu REPLACES the panel's contents. Stacked panels on
	    touch is the shape that made this a device-only defect last time, and
	    counting surfaces is the only way to tell the two apart.
	  * Cancel closes ONE level; tap-away closes ALL. Invisible until a submenu is
	    open, which no smoke test does.
	  * long-press ownership. The disclosure plate KEEPS the gesture — it is the
	    only touch route to a truncated label's full value — and a Menu trigger is
	    the carve-out. Both directions are asserted, because "removed the binding"
	    and "never had one" look identical from inside a menu fixture.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local menuLib = require("../src/controls/menu")
local menuRecipe = require("../src/controls/menu_recipe")
local popup_button = require("../src/controls/popup_button")
local fake_target = require("../tests/lib/fake_target")
local Compose = require("../src/vendor/compose/core")

local UI = harness.UI

local ITEMS = {
	{ id = "accessory", label = "Accessory Adjustment", icon = "edit", onSelect = function() end },
	{ id = "body", label = "Body Shape", icon = "edit", onSelect = function() end },
	{ id = "skin", label = "Skin Color", icon = "edit", onSelect = function() end },
}

--[[ headless world. The trigger is an ordinary Button the caller authored — the
	control attaches to it and adds no wrapper, so its mounted path is the one the
	caller's own tree gives it. Every interaction below goes through a REAL path
	(adapter.tap / adapter.driveTouchGesture / adapter.driveSecondaryActivate /
	system.deviceKey), never by calling a control callback directly. ]]
local function world(opts: any?)
	local options = opts or {}
	local core = harness.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = options.w or 800, h = options.h or 600 })
	local system = Facet.newActionSystem(core)
	-- ARMED (T12): the "no orphaned nodes once closed" case reads `.ops()`.
	local adapter = fake_target.new({ ops = true })
	local pres = harness.newPresenter(core, env, adapter, system)
	local ran: { string } = {}
	local control = menuLib.build(Facet, core, {
		id = "M",
		trigger = UI.Button({
			id = "Trigger",
			label = "More",
			width = { type = "fixed", px = 120 },
			height = { type = "fixed", px = 44 },
		}),
		items = options.items or ITEMS,
		triggers = options.triggers,
		presentation = options.presentation,
		sizeClass = options.sizeClass,
		interactionClasses = options.interactionClasses,
		backLabel = options.backLabel,
		edge = options.edge,
		align = options.align,
		width = options.width,
		maxHeight = options.maxHeight,
		onOpen = function()
			table.insert(ran, "open")
		end,
		onClose = function()
			table.insert(ran, "close")
		end,
	})
	local screen = UI.Screen({
		id = "S",
		children = {
			UI.Anchor({
				id = "Body",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = { control.blueprint },
			}),
		},
	})
	local handle = pres.present(screen, { sinkNavigation = true })
	pres.refresh()
	return {
		core = core,
		env = env,
		adapter = adapter,
		pres = pres,
		system = system,
		control = control,
		ran = ran,
		handle = handle,
	}
end

local TRIGGER = "/S/Body/Trigger"
local function rowPath(level: number, itemId: string): string
	local surface = if level == 0 then "Menu-M" else `Menu-M-L{level}`
	return `/{surface}/Layer/Surface/Popup/Panel/List/Rows/Item:{itemId}`
end
local function sheetRow(itemId: string): string
	return `/Menu-M/Layer/Panel/Item:{itemId}`
end

local NESTED = {
	{
		id = "adjust",
		label = "Adjust",
		children = {
			{ id = "head", label = "Head Adjustment", onSelect = function() end },
			{
				id = "layer",
				label = "Layering",
				children = {
					{ id = "clothing", label = "Clothing Layering", onSelect = function() end },
					{ id = "makeup", label = "Makeup Layering", onSelect = function() end },
				},
			},
		},
	},
	{ id = "skin", label = "Skin Color", onSelect = function() end },
}

-- ===== the spec, and what it refuses ====================================

describe("D2 Menu: the spec is closed, and an ambiguous item is a refusal", function()
	it("an unknown spec key is an authoring error, named with the whole legal set", function()
		local core = harness.newCore()
		local ok, err = pcall(function()
			menuLib.build(
				Facet,
				core,
				{
					id = "M",
					trigger = UI.Button({ id = "T", label = "x" }),
					items = ITEMS,
					onPick = function() end,
				} :: any
			)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "onPick", 1, true) ~= nil).toBe(true)
	end)

	it("declaring BOTH children and onSelect is a spec error, never a precedence rule", function()
		local core = harness.newCore()
		local ok, err = pcall(function()
			menuLib.build(
				Facet,
				core,
				{
					id = "M",
					trigger = UI.Button({ id = "T", label = "x" }),
					items = {
						{
							id = "both",
							label = "Both",
							onSelect = function() end,
							children = { { id = "a", label = "A", onSelect = function() end } },
						},
					},
				} :: any
			)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "spec error", 1, true) ~= nil).toBe(true)
	end)

	it("an item with neither an action nor children is refused rather than silently inert", function()
		local core = harness.newCore()
		local ok, err = pcall(function()
			menuLib.build(
				Facet,
				core,
				{
					id = "M",
					trigger = UI.Button({ id = "T", label = "x" }),
					items = { { id = "dead", label = "Dead" } },
				} :: any
			)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "silently do nothing", 1, true) ~= nil).toBe(true)
	end)

	it("Guidance: icons for ALL items in a group, or none — a half-iconned group is refused", function()
		local core = harness.newCore()
		local ok, err = pcall(function()
			menuLib.build(
				Facet,
				core,
				{
					id = "M",
					trigger = UI.Button({ id = "T", label = "x" }),
					items = {
						{ id = "a", label = "A", icon = "edit", onSelect = function() end },
						{ id = "b", label = "B", onSelect = function() end },
					},
				} :: any
			)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "or none of them", 1, true) ~= nil).toBe(true)
	end)

	it("...and a DIVIDER starts a new group, so the two sides may differ", function()
		local core = harness.newCore()
		-- the surface's environment, which an automatic presentation reads (ADAPT-1)
		Facet.newEnvironment(core)
		local control = menuLib.build(
			Facet,
			core,
			{
				id = "M",
				trigger = UI.Button({ id = "T", label = "x" }),
				items = {
					{ id = "a", label = "A", icon = "edit", onSelect = function() end },
					{ divider = true },
					{ id = "b", label = "B", onSelect = function() end },
				},
			} :: any
		)
		expect(control.dump().items[2].divider).toBe(true)
	end)

	it("a menu that drops `activate` without both key triggers is unreachable, and refused", function()
		local core = harness.newCore()
		local ok, err = pcall(function()
			menuLib.build(
				Facet,
				core,
				{
					id = "M",
					trigger = UI.Button({ id = "T", label = "x" }),
					items = ITEMS,
					triggers = { "secondary", "longPress" },
				} :: any
			)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "unreachable on a", 1, true) ~= nil).toBe(true)
	end)
end)

-- ===== submenus: unbounded, and diagnosed ===============================

describe("D2 Menu: submenus nest without a cap, and say so past one level", function()
	it("a three-level tree BUILDS, and depth >= 2 is diagnosed rather than refused", function()
		local core = harness.newCore()
		-- the surface's environment, which an automatic presentation reads (ADAPT-1)
		Facet.newEnvironment(core)
		local control = menuLib.build(
			Facet,
			core,
			{
				id = "M",
				trigger = UI.Button({ id = "T", label = "x" }),
				items = NESTED,
			} :: any
		)
		-- STRUCTURALLY UNBOUNDED: the tree exists, all three levels of it
		local items = control.dump().items
		expect(items[1].kind).toBe("submenu")
		expect(items[1].children[2].kind).toBe("submenu")
		expect(items[1].children[2].children[1].id).toBe("clothing")
		-- ...AND DIAGNOSED: nothing caps the depth, the interface guidance advises one level
		local notes = table.concat(control.api.diagnostics(), " | ")
		expect(string.find(notes, "nests 2 levels deep", 1, true) ~= nil).toBe(true)
		expect(string.find(notes, "single level", 1, true) ~= nil).toBe(true)
	end)

	it("one level of submenu is silent — the diagnostic is advice, not noise", function()
		local core = harness.newCore()
		-- the surface's environment, which an automatic presentation reads (ADAPT-1)
		Facet.newEnvironment(core)
		local control = menuLib.build(
			Facet,
			core,
			{
				id = "M",
				trigger = UI.Button({ id = "T", label = "x" }),
				items = {
					{
						id = "adjust",
						label = "Adjust",
						children = { { id = "head", label = "Head", onSelect = function() end } },
					},
				},
			} :: any
		)
		expect(#control.api.diagnostics()).toBe(0)
	end)

	it("Guidance: a group of more than about five items is diagnosed as wanting its own menu", function()
		local core = harness.newCore()
		Facet.newEnvironment(core)
		local many = {}
		for i = 1, 6 do
			table.insert(many, { id = `i{i}`, label = `Item {i}`, onSelect = function() end })
		end
		local control = menuLib.build(
			Facet,
			core,
			{
				id = "M",
				trigger = UI.Button({ id = "T", label = "x" }),
				items = many,
			} :: any
		)
		local notes = table.concat(control.api.diagnostics(), " | ")
		expect(string.find(notes, "consider creating a new menu", 1, true) ~= nil).toBe(true)
	end)

	it("Guidance: a destructive item that is not last is diagnosed", function()
		local core = harness.newCore()
		-- the surface's environment, which an automatic presentation reads (ADAPT-1)
		Facet.newEnvironment(core)
		local control = menuLib.build(
			Facet,
			core,
			{
				id = "M",
				trigger = UI.Button({ id = "T", label = "x" }),
				items = {
					{ id = "del", label = "Delete", role = "destructive", onSelect = function() end },
					{ id = "keep", label = "Keep", onSelect = function() end },
				},
			} :: any
		)
		local notes = table.concat(control.api.diagnostics(), " | ")
		expect(string.find(notes, "at the end of the menu", 1, true) ~= nil).toBe(true)
	end)
end)

-- ===== the four input classes ===========================================

describe("D2 Menu: every input class opens it, and the verbs are the same ones", function()
	it("a primary activate on the trigger opens the menu against the trigger's own rect", function()
		local w = world()
		w.adapter.tap(TRIGGER)
		w.pres.refresh()
		expect(w.control.api.isOpen:peek()).toBe(true)
		local trigger = w.adapter.node(TRIGGER).rect
		local panel = w.adapter.node("/Menu-M/Layer/Surface/Popup/Panel").rect
		-- D1 placed it: below the source, not at a parent corner
		expect(panel.y >= trigger.y + trigger.h).toBe(true)
		expect(w.pres.anchoredSurfaces().count).toBe(1)
	end)

	it("a pointer SECONDARY click on the trigger opens the menu", function()
		local w = world()
		expect(w.adapter.driveSecondaryActivate(TRIGGER)).toBe(true)
		w.pres.refresh()
		expect(w.control.api.isOpen:peek()).toBe(true)
		expect(w.adapter.node(rowPath(0, "body")) ~= nil).toBe(true)
	end)

	it("a touch LONG-PRESS on the trigger opens the menu, through the normalized gesture layer", function()
		local w = world()
		-- the value object the SHIPPED normalizer produces, not a bespoke event:
		-- `touch_gestures.normalize("longPress", { positions, state })`
		w.adapter.driveTouchGesture(TRIGGER, { kind = "longPress", state = "began", positions = {} })
		w.pres.refresh()
		expect(w.control.api.isOpen:peek()).toBe(true)
		-- ...and the RELEASE does not re-toggle it shut under the finger
		w.adapter.driveTouchGesture(TRIGGER, { kind = "longPress", state = "ended", positions = {} })
		w.pres.refresh()
		expect(w.control.api.isOpen:peek()).toBe(true)
	end)

	it("a tap gesture is NOT a long press: the menu stays shut", function()
		local w = world()
		w.adapter.driveTouchGesture(TRIGGER, { kind = "tap", state = "ended", positions = {} })
		w.pres.refresh()
		expect(w.control.api.isOpen:peek()).toBe(false)
	end)

	it("the keyboard context chord opens the menu, and Return activates the focused item", function()
		local w = world()
		w.system.deviceKey("Menu", true)
		w.system.deviceKey("Menu", false)
		w.pres.refresh()
		expect(w.control.api.isOpen:peek()).toBe(true)
		-- the open rows are ordinary focusables, so the ring is already on the first
		expect(w.pres.focus.focused:peek()).toBe(rowPath(0, "accessory"))
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		w.pres.refresh()
		expect(w.control.api.isOpen:peek()).toBe(false)
	end)

	it("the gamepad menu button opens it, and ButtonB closes ONE level", function()
		local w = world({ items = NESTED })
		w.system.deviceKey("ButtonY", true)
		w.system.deviceKey("ButtonY", false)
		w.pres.refresh()
		expect(w.control.api.isOpen:peek()).toBe(true)
		w.control.api.select("adjust")
		w.pres.refresh()
		expect(#w.control.api.openPath:peek()).toBe(1)
		-- ONE level, not all of them
		w.system.deviceKey("ButtonB", true)
		w.system.deviceKey("ButtonB", false)
		w.pres.refresh()
		expect(#w.control.api.openPath:peek()).toBe(0)
		expect(w.control.api.isOpen:peek()).toBe(true)
	end)

	it("ButtonA opens, ButtonB closes, and the next ButtonA opens again", function()
		local w = world()
		expect(w.pres.focus.focusOn(TRIGGER)).toBe(true)
		for _ = 1, 2 do
			-- the menu opens on the down edge; its Sink is born holding that press
			w.system.deviceKey("ButtonA", true)
			w.pres.refresh()
			w.system.deviceKey("ButtonA", false)
			w.pres.refresh()
			expect(w.control.api.isOpen:peek()).toBe(true)
			w.system.deviceKey("ButtonB", true)
			w.system.deviceKey("ButtonB", false)
			w.pres.refresh()
			expect(w.control.api.isOpen:peek()).toBe(false)
			expect(w.pres.focus.focused:peek()).toBe(TRIGGER)
		end
	end)

	it("activating an item runs its onSelect exactly once and closes the menu", function()
		local runs = 0
		local w = world({
			items = { {
				id = "go",
				label = "Go",
				onSelect = function()
					runs += 1
				end,
			} },
		})
		w.adapter.tap(TRIGGER)
		w.pres.refresh()
		w.adapter.tap(rowPath(0, "go"))
		w.pres.refresh()
		expect(runs).toBe(1)
		expect(w.control.api.isOpen:peek()).toBe(false)
		expect(w.pres.anchoredSurfaces().count).toBe(0)
	end)

	it("every trigger declared is honoured, and one that was not is inert", function()
		local w = world({ triggers = { "activate" } })
		expect(w.adapter.driveSecondaryActivate(TRIGGER)).toBe(false)
		w.adapter.driveTouchGesture(TRIGGER, { kind = "longPress", state = "began", positions = {} })
		w.pres.refresh()
		expect(w.control.api.isOpen:peek()).toBe(false)
		w.adapter.tap(TRIGGER)
		w.pres.refresh()
		expect(w.control.api.isOpen:peek()).toBe(true)
	end)
end)

-- ===== the state nobody fixtures ========================================

describe("D2 Menu: a menu whose every item is disabled still OPENS", function()
	it("a wholly unavailable menu opens rather than swallowing its trigger", function()
		--[[ The guidance: if all of a menu's items are unavailable, the menu itself needs
			to remain available so people can open it and learn about the commands it
			contains." A trigger that silently does nothing cannot be told apart from a
			dead button, which is why this is a case and not a comment. ]]
		local w = world({
			items = {
				{ id = "a", label = "Cut", enabled = false, onSelect = function() end },
				{ id = "b", label = "Copy", enabled = false, onSelect = function() end },
			},
		})
		w.adapter.tap(TRIGGER)
		w.pres.refresh()
		expect(w.control.api.isOpen:peek()).toBe(true)
		expect(w.adapter.node(rowPath(0, "a")) ~= nil).toBe(true)
		-- ...and the rows are visibly unavailable, not merely inert
		expect(w.adapter.node(rowPath(0, "a")).props.enabled).toBe(false)
		expect(w.control.dump().items[1].enabled).toBe(false)
	end)

	it("selecting a disabled item does nothing and leaves the menu standing", function()
		local ran = false
		local w = world({
			items = {
				{
					id = "a",
					label = "Cut",
					enabled = false,
					onSelect = function()
						ran = true
					end,
				},
			},
		})
		w.control.api.open()
		w.pres.refresh()
		w.control.api.select("a")
		expect(ran).toBe(false)
		expect(w.control.api.isOpen:peek()).toBe(true)
	end)
end)

-- ===== dismissal ========================================================

describe("D2 Menu: Cancel closes one level, tap-away closes all", function()
	it("tap-away closes EVERY level, not just the innermost", function()
		local w = world({ items = NESTED })
		w.control.api.open()
		w.pres.refresh()
		w.control.api.select("adjust")
		w.pres.refresh()
		w.control.api.select("layer")
		w.pres.refresh()
		expect(#w.control.api.openPath:peek()).toBe(2)
		expect(w.pres.anchoredSurfaces().count).toBe(3)
		-- a tap on a node OUTSIDE the menu: the presenter's own outside-tap path
		w.adapter.tap(TRIGGER)
		w.pres.refresh()
		expect(w.control.api.isOpen:peek()).toBe(false)
		expect(w.pres.anchoredSurfaces().count).toBe(0)
	end)

	it("Cancel unwinds the chain one level at a time, and only then closes", function()
		local w = world({ items = NESTED })
		w.control.api.open()
		w.pres.refresh()
		w.control.api.select("adjust")
		w.control.api.select("layer")
		w.pres.refresh()
		expect(#w.control.api.openPath:peek()).toBe(2)
		w.control.api.closeLevel()
		w.pres.refresh()
		expect(#w.control.api.openPath:peek()).toBe(1)
		expect(w.control.api.isOpen:peek()).toBe(true)
		w.control.api.closeLevel()
		w.pres.refresh()
		expect(#w.control.api.openPath:peek()).toBe(0)
		expect(w.control.api.isOpen:peek()).toBe(true)
		w.control.api.closeLevel()
		w.pres.refresh()
		expect(w.control.api.isOpen:peek()).toBe(false)
	end)

	it("Right enters the focused submenu and Left leaves it, in document order", function()
		local w = world({ items = NESTED })
		w.control.api.open()
		w.pres.refresh()
		expect(w.pres.focus.focused:peek()).toBe(rowPath(0, "adjust"))
		w.system.deviceKey("Right", true)
		w.system.deviceKey("Right", false)
		w.pres.refresh()
		expect(w.control.api.openPath:peek()[1]).toBe("adjust")
		w.system.deviceKey("Left", true)
		w.system.deviceKey("Left", false)
		w.pres.refresh()
		expect(#w.control.api.openPath:peek()).toBe(0)
	end)

	it("Right on a plain ACTION row is not the menu's arrow, so the ring keeps it", function()
		local w = world()
		w.control.api.open()
		w.pres.refresh()
		w.system.deviceKey("Right", true)
		w.system.deviceKey("Right", false)
		w.pres.refresh()
		expect(#w.control.api.openPath:peek()).toBe(0)
		expect(w.control.api.isOpen:peek()).toBe(true)
	end)
end)

-- ===== the two presentations ============================================

describe("D2 Menu: touch does not nest — the sheet replaces its contents", function()
	it("touch resolves to `sheet` through the ONE shared rule, never a device name", function()
		local w = world({ interactionClasses = { touch = true, primary = "touch" } })
		expect(w.control.presentation()).toBe("sheet")
		local pointer = world({ interactionClasses = { pointer = true, primary = "pointer" } })
		expect(pointer.control.presentation()).toBe("menu")
	end)

	--[[ ADAPT-9 — THE HYBRID THE OLD RULE GOT WRONG. The rung asked whether touch
		was AVAILABLE, so a touchscreen laptop being driven with a mouse resolved a
		bottom sheet — directly against the environment's own ruling ("A mouse still
		wins outright, which keeps every desktop and every hybrid (touchscreen
		laptop) exactly where it was"). The question is which class is PRIMARY, and
		the same device answers both ways as the player switches. ]]
	--[[ MEDIUM-2 (re-review) — THE TABLE THAT NEVER DECLARED A PRIMARY.

		`interactionClasses` is typed `table | Readable`, so a hand-authored one may
		carry `touch = true` and nothing else — every fixture in this file did until
		ADAPT-9 landed. Reading `primary` alone silently moved that shape from `sheet`
		to `menu`. The fallback is explicit and is the old meaning; the case below is
		the one that was red after ADAPT-9 and is the reason it exists. ]]
	it("MEDIUM-2: a class table with no `primary` keeps its pre-ADAPT-9 answer", function()
		local touchOnly = world({ interactionClasses = { touch = true } })
		expect(touchOnly.control.presentation()).toBe("sheet")
		local pointerOnly = world({ interactionClasses = { pointer = true } })
		expect(pointerOnly.control.presentation()).toBe("menu")
		-- ...and a DECLARED primary still outranks what the table merely has
		local declaredPointer = world({ interactionClasses = { touch = true, primary = "pointer" } })
		expect(declaredPointer.control.presentation()).toBe("menu")
	end)

	it("ADAPT-9: a hybrid follows its PRIMARY class, not merely what it has", function()
		local mouseDriven = world({
			interactionClasses = { touch = true, pointer = true, keyboard = true, primary = "pointer" },
		})
		expect(mouseDriven.control.presentation()).toBe("menu")
		local thumbDriven = world({
			interactionClasses = { touch = true, pointer = true, keyboard = true, primary = "touch" },
		})
		expect(thumbDriven.control.presentation()).toBe("sheet")
	end)

	it("under `sheet` a submenu REPLACES the sheet's contents and grows a Back row", function()
		local w = world({ items = NESTED, presentation = "sheet" })
		w.control.api.open()
		w.pres.refresh()
		expect(w.control.dump().surfaces).toBe(1)
		expect(w.adapter.node(sheetRow("adjust")) ~= nil).toBe(true)
		expect(w.adapter.node("/Menu-M/Layer/Panel/Back")).toBe(nil) -- no way back UP from the root
		w.control.api.select("adjust")
		w.pres.refresh()
		-- ONE surface still: the contents were replaced, not stacked
		expect(w.control.dump().surfaces).toBe(1)
		expect(w.adapter.node(sheetRow("head")) ~= nil).toBe(true)
		expect(w.adapter.node(sheetRow("adjust"))).toBe(nil) -- the parent level is GONE
		expect(w.adapter.node("/Menu-M/Layer/Panel/Back") ~= nil).toBe(true)
	end)

	it("...and the Back row walks the chain back up rather than closing the menu", function()
		local w = world({ items = NESTED, presentation = "sheet" })
		w.control.api.open()
		w.pres.refresh()
		w.control.api.select("adjust")
		w.pres.refresh()
		w.adapter.tap("/Menu-M/Layer/Panel/Back")
		w.pres.refresh()
		expect(#w.control.api.openPath:peek()).toBe(0)
		expect(w.control.api.isOpen:peek()).toBe(true)
		expect(w.adapter.node(sheetRow("adjust")) ~= nil).toBe(true)
	end)

	it("under `menu` a submenu STACKS beside its parent, anchored to the row it came from", function()
		local w = world({ items = NESTED, presentation = "menu" })
		w.control.api.open()
		w.pres.refresh()
		w.control.api.select("adjust")
		w.pres.refresh()
		expect(w.control.dump().surfaces).toBe(2)
		-- the parent panel is STILL up, which is what makes a Back row unnecessary
		expect(w.adapter.node(rowPath(0, "adjust")) ~= nil).toBe(true)
		expect(w.adapter.node(rowPath(1, "head")) ~= nil).toBe(true)
		local surfaces = w.pres.anchoredSurfaces()
		expect(surfaces.count).toBe(2)
		-- the SECOND one is anchored to its parent row, on the trailing edge
		expect(surfaces.surfaces[2].source).toBe(rowPath(0, "adjust"))
		expect(surfaces.surfaces[2].requestedEdge).toBe("trailing")
	end)

	it("a live class flip while a submenu is open CARRIES the open path into the new presentation", function()
		local core = harness.newCore()
		local classes = Compose.cell({ pointer = true, primary = "pointer" })
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = harness.newPresenter(core, env, adapter, system)
		local control = menuLib.build(
			Facet,
			core,
			{
				id = "M",
				trigger = UI.Button({ id = "Trigger", label = "More" }),
				items = NESTED,
				interactionClasses = classes,
			} :: any
		)
		pres.present(UI.Screen({ id = "S", children = { control.blueprint } }), { sinkNavigation = true })
		pres.refresh()
		control.api.open()
		pres.refresh()
		control.api.select("adjust")
		pres.refresh()
		expect(control.presentation()).toBe("menu")
		expect(control.dump().surfaces).toBe(2)
		-- the player put the mouse down and picked the screen up
		classes:set({ touch = true, primary = "touch" })
		pres.refresh()
		expect(control.presentation()).toBe("sheet")
		-- the CHAIN survived; only the idiom changed
		expect(control.api.openPath:peek()[1]).toBe("adjust")
		expect(control.dump().surfaces).toBe(1)
		expect(adapter.node("/Menu-M/Layer/Panel/Item:head") ~= nil).toBe(true)
	end)
end)

--[[ D2, director item 14 (framework-gaps-phase2-followups; shouldHaveSinglePanel.png;
	the compact boundary): the "Menus and their five triggers" showcase, driven on a phone
	viewport with NO touch signal (Roblox Studio's own compact preset — it cannot
	inject touch at all, so `interactionClasses.primary` reads "pointer"
	unconditionally), showed a submenu floating over its own still-open parent
	AND the page beneath it. `resolvePresentation`'s sheet branch answers "is
	touch primary", a different question from "does a floating panel fit" —
	COMPACT is the framework's own single-panel boundary
	(`layout/adaptive.luau`'s `sizeClass`, breakpoints 600/1000), asked here as
	the SAME string this file already reads as `sizeClassSource`, never a new
	breakpoint. ]]
describe("D2 Menu: item 14 — COMPACT forces the single-panel idiom, not touch", function()
	it("a compact width forces `sheet` even with a POINTER-primary class (the exact screenshot repro)", function()
		local w = world({ w = 390, interactionClasses = { pointer = true, primary = "pointer" } })
		expect(w.control.presentation()).toBe("sheet")
	end)

	it("...and the SAME pointer-primary class resolves `menu` once the width crosses into `regular`", function()
		local w = world({ w = 800, interactionClasses = { pointer = true, primary = "pointer" } })
		expect(w.control.presentation()).toBe("menu")
	end)

	it(
		"this only WIDENS which environments choose `sheet` — touch still forces it at any width (ADAPT-9 unaffected)",
		function()
			local w = world({ w = 1200, interactionClasses = { touch = true, primary = "touch" } })
			expect(w.control.presentation()).toBe("sheet")
		end
	)

	it(
		"an author-forced `presentation` is untouched — forcing stays the escape hatch even at a compact width",
		function()
			local w =
				world({ w = 390, presentation = "menu", interactionClasses = { pointer = true, primary = "pointer" } })
			expect(w.control.presentation()).toBe("menu")
		end
	)

	it(
		"AUTOMATICALLY, with no forced idiom: entering a submenu on a compact pointer-primary surface REPLACES the panel instead of stacking a second one over it",
		function()
			local w = world({ items = NESTED, w = 390, interactionClasses = { pointer = true, primary = "pointer" } })
			w.control.api.open()
			w.pres.refresh()
			expect(w.control.dump().surfaces).toBe(1)
			w.control.api.select("adjust")
			w.pres.refresh()
			-- ONE surface, not two overlapping ones — shouldHaveSinglePanel.png's own defect
			expect(w.control.dump().surfaces).toBe(1)
			expect(w.adapter.node(sheetRow("head")) ~= nil).toBe(true)
			expect(w.adapter.node(sheetRow("adjust"))).toBe(nil) -- the parent level is GONE, not overlapping
		end
	)

	it(
		"touch (the Back row) closes one level on the AUTOMATIC compact idiom, exactly as the forced `sheet` case does",
		function()
			local w = world({ items = NESTED, w = 390 }) -- default classes: pointer-primary, no forced presentation
			w.control.api.open()
			w.pres.refresh()
			w.control.api.select("adjust")
			w.pres.refresh()
			expect(w.adapter.node("/Menu-M/Layer/Panel/Back") ~= nil).toBe(true)
			w.adapter.tap("/Menu-M/Layer/Panel/Back")
			w.pres.refresh()
			expect(#w.control.api.openPath:peek()).toBe(0)
			expect(w.control.api.isOpen:peek()).toBe(true)
		end
	)

	it("keyboard (Left) and gamepad (ButtonB) each close one level on the AUTOMATIC compact idiom", function()
		local w = world({ items = NESTED, w = 390 })
		w.control.api.open()
		w.pres.refresh()
		w.system.deviceKey("Right", true)
		w.system.deviceKey("Right", false)
		w.pres.refresh()
		expect(#w.control.api.openPath:peek()).toBe(1)
		w.system.deviceKey("Left", true)
		w.system.deviceKey("Left", false)
		w.pres.refresh()
		expect(#w.control.api.openPath:peek()).toBe(0)
		expect(w.control.api.isOpen:peek()).toBe(true)
		w.control.api.select("adjust")
		w.pres.refresh()
		expect(#w.control.api.openPath:peek()).toBe(1)
		w.system.deviceKey("ButtonB", true)
		w.system.deviceKey("ButtonB", false)
		w.pres.refresh()
		expect(#w.control.api.openPath:peek()).toBe(0)
		expect(w.control.api.isOpen:peek()).toBe(true)
	end)

	it(
		"dismissal semantics are UNCHANGED at the root: an outside tap still closes every level on the automatic compact idiom",
		function()
			local w = world({ items = NESTED, w = 390 })
			w.control.api.open()
			w.pres.refresh()
			w.control.api.select("adjust")
			w.control.api.select("layer")
			w.pres.refresh()
			expect(#w.control.api.openPath:peek()).toBe(2)
			w.adapter.tap(TRIGGER)
			w.pres.refresh()
			expect(w.control.api.isOpen:peek()).toBe(false)
			expect(w.control.dump().surfaces).toBe(0)
		end
	)

	it(
		"BACK restores focus to the row that led into the level just left, not the level's first row (state preserved)",
		function()
			local w = world({ items = NESTED, presentation = "sheet" })
			w.control.api.open()
			w.pres.refresh()
			w.control.api.select("adjust")
			w.pres.refresh()
			-- "layer" is the SECOND row of "adjust"'s children ({ head, layer }) — a
			-- naive `entry = "first"` rebuild on the way back out would land on
			-- "head" instead, which is the defect this proves closed
			w.control.api.select("layer")
			w.pres.refresh()
			expect(#w.control.api.openPath:peek()).toBe(2)
			w.control.api.closeLevel()
			w.pres.refresh()
			expect(#w.control.api.openPath:peek()).toBe(1)
			expect(w.pres.focus.focused:peek()).toBe(sheetRow("layer"))
			w.control.api.closeLevel()
			w.pres.refresh()
			expect(#w.control.api.openPath:peek()).toBe(0)
			expect(w.pres.focus.focused:peek()).toBe(sheetRow("adjust"))
		end
	)

	it("repeated enter/back leaves no orphaned nodes once closed (no leaked scope)", function()
		local w = world({ items = NESTED, presentation = "sheet" })
		w.control.api.open()
		w.pres.refresh()
		for _ = 1, 5 do
			w.control.api.select("adjust")
			w.pres.refresh()
			w.control.api.select("layer")
			w.pres.refresh()
			w.control.api.closeLevel()
			w.pres.refresh()
			w.control.api.closeLevel()
			w.pres.refresh()
		end
		--[[ EVERY PATH EVER CREATED under this menu's surfaces, over the whole
				five-cycle run — collected BEFORE the close, so a path built and torn
				down MID-run (every level `sheet` replaces) is still counted. `ops()`'s
				own "create"/"remove" pairing is the WRONG instrument here and was the
				first draft's mistake: a `sheet` surface is a MODAL, torn down through
				`adapter.destroyRoot`, which clears every descendant's `nodes` entry in
				ONE opaque `"destroyRoot"` op with no per-path text at all — mirroring a
				real engine's `Instance:Destroy()` cascade, which never calls back once
				per descendant either. So "was a remove logged for this exact path" is
				unanswerable by construction and reddened on every row despite nothing
				being leaked. The instrument that actually answers "is it gone" is the
				live node table itself. ]]
		local everCreated: { [string]: boolean } = {}
		for _, op in w.adapter.ops() do
			local path = string.match(op, "^create (%S+)")
			if path ~= nil and string.match(path, "^/Menu%-M") ~= nil then
				everCreated[path] = true
			end
		end
		w.control.api.close()
		w.pres.refresh()
		for _ = 1, 60 do
			w.pres.tick(1 / 60)
		end
		local stillAlive: { string } = {}
		for path in everCreated do
			if w.adapter.node(path) ~= nil then
				table.insert(stillAlive, path)
			end
		end
		table.sort(stillAlive)
		expect(table.concat(stillAlive, ", ")).toBe("")
	end)

	--[[ REVIEW FINDING I1 (fix round 1): the Back row's WORD was a hardcoded,
		unlocalizable English literal with no caller override — a real,
		reachable defect once this round made `sheet` (and its Back row) the
		framework default for every compact `newMenu`. Fixed on the sibling
		doctrine `present/nav_bar.luau`'s `NavBarSpec.backLabel` already
		ships: an optional `spec.backLabel`, the current literal surviving only
		as the fallback when it is absent. ]]
	it("`backLabel` reaches the Back row's rendered label", function()
		local w = world({ items = NESTED, presentation = "sheet", backLabel = "Zurück" })
		w.control.api.open()
		w.pres.refresh()
		w.control.api.select("adjust")
		w.pres.refresh()
		local back = w.adapter.node("/Menu-M/Layer/Panel/Back")
		expect(back ~= nil).toBe(true)
		expect(string.find(back.props.label, "Zurück", 1, true) ~= nil).toBe(true)
		-- the glyph prefix stays — only the WORD is the caller's to replace
		expect(string.find(back.props.label, "Back", 1, true) ~= nil).toBe(false)
	end)

	it("the literal 'Back' stands as the fallback when `backLabel` is absent (no regression)", function()
		local w = world({ items = NESTED, presentation = "sheet" })
		w.control.api.open()
		w.pres.refresh()
		w.control.api.select("adjust")
		w.pres.refresh()
		local back = w.adapter.node("/Menu-M/Layer/Panel/Back")
		expect(string.find(back.props.label, "Back", 1, true) ~= nil).toBe(true)
	end)

	--[[ THE EXPANSION CASE (binding R9-family): a caller's localized word can
		run well past English under pseudo-localization (this codebase's own
		`xa`-pass convention measures ~1.4x); the Back row must degrade to its
		icon rather than clip. `compactLabel` (no `prefer`) is the SAME ladder
		`menu_recipe.row`'s own doctrine already gives every other row in this
		panel — proven the same way `menu_scenario.spec.luau` already proves
		"the solver reports nothing" for this construct: zero overflow
		findings from the live solver, not an inspected prop. ]]
	it("a Back label past ~1.4x an English source degrades to the icon alone rather than clipping", function()
		--[[ `diagnostics()` was tried first and found VACUOUS here (mutation
				check, fix round 1): it never fires for a label overflowing its OWN
				Button, only for a BOX escaping its container, so removing the
				`compactLabel` this fix adds does not redden it. The instrument that
				actually sees the claim is `commit_walks.textVerdicts`' own compact
				verdict, which the adapter mirrors as `props.icon` — set to the
				`compactLabel` icon the instant the full label's measured width does
				not fit the row, exactly the ladder `menu_recipe.row`'s doctrine
				already gives every other row (never a partial/cut-off word: the WHOLE
				label, or the WHOLE icon standing in for it). ]]
		local longLabel = "Zurück zur vorherigen Menüebene, danke für Ihre Geduld"
		local w = world({ items = NESTED, w = 320, presentation = "sheet", backLabel = longLabel })
		w.control.api.open()
		w.pres.refresh()
		w.control.api.select("adjust")
		w.pres.refresh()
		local back = w.adapter.node("/Menu-M/Layer/Panel/Back")
		expect(back ~= nil).toBe(true)
		-- the full word does not fit a compact row — the ladder went compact,
		-- never a mid-word clip
		expect(back.props.icon).toBe("chevron.leading")
		-- ...and the short, undegraded case proves this isn't just always true:
		-- a word that DOES fit keeps its text, icon-free
		local short = world({ items = NESTED, w = 320, presentation = "sheet", backLabel = "Zurück" })
		short.control.api.open()
		short.pres.refresh()
		short.control.api.select("adjust")
		short.pres.refresh()
		local shortBack = short.adapter.node("/Menu-M/Layer/Panel/Back")
		expect(shortBack.props.icon).toBeNil()
		expect(string.find(shortBack.props.label, "Zurück", 1, true) ~= nil).toBe(true)
	end)
end)

--[[ D2: `presentation` accepts a Readable (gap 20, framework-gaps-phase2).
	Was a static string, checked once at construction; the audit's own
	adjacent evidence (teaches-wrong #8) put `sizeClass`/`interactionClasses`
	on the same file already accepting a Readable — this is the third leg,
	riding the SAME `presentationMemo`/hot-switch machinery the class-flip
	test above proves, so a forced override reacts exactly like an automatic
	resolution already does. ]]
describe("D2: newMenu.presentation is a Readable<string> (gap 20)", function()
	it("a plain string still fails fast, at CONSTRUCTION — no regression", function()
		local ok, err = pcall(function()
			world({ presentation = "bogus" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "unknown presentation", 1, true) ~= nil).toBe(true)
	end)

	it("a Readable forcing 'sheet' opens sheeted even on a desktop-shaped surface", function()
		local core = harness.newCore()
		local forced = Compose.cell("sheet")
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = harness.newPresenter(core, env, adapter, system)
		local control = menuLib.build(
			Facet,
			core,
			{
				id = "M",
				trigger = UI.Button({ id = "Trigger", label = "More" }),
				items = ITEMS,
				presentation = forced,
				interactionClasses = { pointer = true, primary = "pointer" }, -- would resolve "menu" if honoured
			} :: any
		)
		pres.present(UI.Screen({ id = "S", children = { control.blueprint } }), { sinkNavigation = true })
		pres.refresh()
		expect(control.presentation()).toBe("sheet")
		control.api.open()
		pres.refresh()
		expect(adapter.node("/Menu-M/Layer/Panel/Item:accessory") ~= nil).toBe(true)
	end)

	it("flipping the Readable while OPEN re-presents through the same hot-switch the automatic case uses", function()
		local core = harness.newCore()
		local forced = Compose.cell("menu")
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = harness.newPresenter(core, env, adapter, system)
		local control = menuLib.build(
			Facet,
			core,
			{
				id = "M",
				trigger = UI.Button({ id = "Trigger", label = "More" }),
				items = ITEMS,
				presentation = forced,
			} :: any
		)
		pres.present(UI.Screen({ id = "S", children = { control.blueprint } }), { sinkNavigation = true })
		pres.refresh()
		control.api.open()
		pres.refresh()
		expect(control.dump().surfaces).toBe(1)
		expect(adapter.node(sheetRow("accessory"))).toBe(nil)
		forced:set("sheet")
		pres.refresh()
		expect(control.presentation()).toBe("sheet")
		expect(control.api.isOpen:peek()).toBe(true) -- the surface survived the switch
		expect(adapter.node(sheetRow("accessory")) ~= nil).toBe(true)
	end)

	it(
		"a Readable can flip INTO 'automatic', resolving the size/interaction facts as if authored from the start",
		function()
			local core = harness.newCore()
			local forced = Compose.cell("sheet")
			local classes = Compose.cell({ pointer = true, primary = "pointer" })
			local env = Facet.newEnvironment(core)
			env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
			local system = Facet.newActionSystem(core)
			local adapter = fake_target.new()
			local pres = harness.newPresenter(core, env, adapter, system)
			local control = menuLib.build(
				Facet,
				core,
				{
					id = "M",
					trigger = UI.Button({ id = "Trigger", label = "More" }),
					items = ITEMS,
					presentation = forced,
					interactionClasses = classes,
				} :: any
			)
			pres.present(UI.Screen({ id = "S", children = { control.blueprint } }), { sinkNavigation = true })
			pres.refresh()
			expect(control.presentation()).toBe("sheet")
			-- flip to "automatic": the env facts must already be resolved (the
			-- construction-time gate had to anticipate a Readable might do this)
			forced:set("automatic")
			pres.refresh()
			expect(control.presentation()).toBe("menu") -- pointer/primary resolves menu, not sheet
		end
	)

	--[[ THE DOMAIN CHECK LIVES INSIDE `presentationMemo` — a `Compose.formula`, not
		`readAuthoredPresentation`'s plain renderer-side call (the path
		`scale`/`rotation`/`opacity` use, which genuinely throws OUT of
		`pres.refresh()`, per `authored_presentation.spec.luau`'s equivalent
		case). The reactive core QUARANTINES a memo compute error by design
		(the core's containment: an equality callback error is reported, and it
		must never unwind a writer or wedge the flush loop") — one screen's
		malformed reactive value must not crash an unrelated surface mid-frame.
		So the refusal here is loud on `core.lastError()`, and the menu HOLDS
		its last valid presentation rather than adopting the bad one — never a
		silent, undiagnosed acceptance of "bogus" as if it were a real idiom. ]]
	it(
		"a reactive value out of domain is refused loudly on core.lastError(), and the menu HOLDS its last valid state",
		function()
			-- `warns` (device bug fix round, director 2026-08-23, task-fix2 item 6):
			-- a quarantine used to be recorded on `lastError()` and nowhere else — an
			-- author who never thinks to poll it never hears about a bad reactive
			-- `presentation` value. `core/services.luau`'s `report()` now calls this on
			-- every quarantine, real `warn()` by default; injected here so the
			-- assertion below is exact rather than a print the suite has to eyeball.
			local warns: { string } = {}
			local core = harness.newCore({
				warn = function(message: string)
					table.insert(warns, message)
				end,
			})
			local forced = Compose.cell("menu")
			local env = Facet.newEnvironment(core)
			env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
			local system = Facet.newActionSystem(core)
			local adapter = fake_target.new()
			local pres = harness.newPresenter(core, env, adapter, system)
			local control = menuLib.build(
				Facet,
				core,
				{
					id = "M",
					trigger = UI.Button({ id = "Trigger", label = "More" }),
					items = ITEMS,
					presentation = forced,
				} :: any
			)
			pres.present(UI.Screen({ id = "S", children = { control.blueprint } }), { sinkNavigation = true })
			pres.refresh()
			expect(control.presentation()).toBe("menu")
			expect(core.lastError()).toBeNil()
			-- the healthy path never warns: building and presenting a VALID menu
			-- must not print anything, or a warning becomes noise nobody trusts
			expect(#warns).toBe(0)
			forced:set("bogus")
			pres.refresh()
			expect(string.find(tostring(core.lastError()), "unknown presentation", 1, true) ~= nil).toBe(true)
			expect(string.find(tostring(core.lastError()), "bogus", 1, true) ~= nil).toBe(true)
			expect(control.presentation()).toBe("menu") -- HELD, not silently accepted
			-- ...and NOW it warns — once, naming the same failure `lastError` holds
			expect(#warns).toBe(1)
			expect(string.find(warns[1], "unknown presentation", 1, true) ~= nil).toBe(true)
			expect(string.find(warns[1], "bogus", 1, true) ~= nil).toBe(true)
			-- a repeated re-evaluation of the SAME bad value does not warn again
			pres.refresh()
			pres.refresh()
			expect(#warns).toBe(1)
		end
	)
end)

-- ===== the shared recipe ================================================

describe("D2: one menu row recipe, and one presentation rule", function()
	it("`resolvePresentation` lives in ONE place, and popup_button's name is an alias for it", function()
		expect(popup_button.resolvePresentation).toBe(menuRecipe.resolvePresentation)
		-- ...and it still answers exactly as it did before the move
		expect(menuRecipe.resolvePresentation(3, "regular", false)).toBe("inline")
		expect(menuRecipe.resolvePresentation(3, "regular", true)).toBe("sheet")
		expect(menuRecipe.resolvePresentation(8, "compact", false)).toBe("sheet")
		expect(menuRecipe.resolvePresentation(5, "regular", false)).toBe("menu")
	end)

	it("all three menus take their row height and gap from the same tokens", function()
		expect(menuRecipe.ROW_HEIGHT).toBe("controlSizes.compact.height")
		expect(menuRecipe.rowHeightFor("sheet")).toBe("controlSizes.large.height")
		expect(menuRecipe.rowHeightFor("inline")).toBe("controlSizes.regular.height")
		expect(menuRecipe.ROW_GAP).toBe("strokes.hairline")
	end)

	it("a leaf row is the SHIPPED shape: the label on the button, the icon on compactLabel", function()
		--[[ The device-round ruling (2026-08-12) this recipe exists to keep: a menu
			row keeps its LABEL, and there is deliberately no `prefer`. Icon-first is
			the TRAY's inversion — "a menu row is a list of names". ]]
		local row = menuRecipe.row(UI, { id = "Item:a", label = "Accessory", icon = "edit" })
		expect(row.props.label).toBe("Accessory")
		expect(row.props.compactLabel.icon).toBe("edit")
		expect(row.props.compactLabel.prefer).toBeNil()
		expect(#row.children).toBe(0)
	end)

	it("a SUBMENU row carries a trailing chevron, and keeps its label semantic", function()
		local row = menuRecipe.row(UI, { id = "Item:a", label = "Adjust", submenu = true })
		expect(row.props.label).toBe("Adjust")
		local ids = {}
		for _, child in row.children do
			table.insert(ids, child.id)
		end
		expect(table.concat(ids, ",")).toBe("Label,Chevron")
	end)

	it("`icon` and a divider joined popup_button.Option, and both render from the recipe", function()
		local core = harness.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = harness.newPresenter(core, env, adapter, system)
		local value = Compose.cell("a")
		local control = popup_button.build(
			Facet,
			core,
			{
				id = "P",
				options = {
					{ id = "a", label = "Trending", icon = "edit" },
					{ id = "b", label = "New", icon = "edit" },
					{ divider = true },
					{ id = "c", label = "Saved" },
				},
				value = value,
			} :: any
		)
		pres.present(UI.Screen({ id = "S", children = { control.blueprint } }), {
			sinkNavigation = true,
			onActivate = function(path, meta)
				control.api.handleActivate(path, meta)
			end,
		})
		control.api.open()
		pres.refresh()
		expect(adapter.node("/S/P/PopupWhen/then/Popup/Opt-a").props.compactLabel.icon).toBe("edit")
		expect(adapter.node("/S/P/PopupWhen/then/Popup/Div-3") ~= nil).toBe(true)
		expect(control.dump().options[3].divider).toBe(true)
	end)

	it("popup_button refuses a half-iconned group through the SAME lint the Menu uses", function()
		local core = harness.newCore()
		local ok, err = pcall(function()
			popup_button.build(
				Facet,
				core,
				{
					id = "P",
					options = { { id = "a", label = "A", icon = "edit" }, { id = "b", label = "B" } },
					value = Compose.cell("a"),
				} :: any
			)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "or none of them", 1, true) ~= nil).toBe(true)
	end)
end)

-- ===== the gesture that two constructs wanted ===========================

describe("D2: long-press ownership, settled in code", function()
	--[[ MEASURED BEFORE DECIDING (2026-08-16). Touch long-press is claimed today by
		the full-value disclosure plate, and it is the ONLY touch route to a truncated
		label's full value: `UI.Text{ reveal = "auto" }` is opt-in, `UI.Text`-only, at
		most one per presentation and disabled entirely under reduced motion, and a
		disclosing `Toggle` label or `Table` cell has no marquee even in principle.
		`text_audit` cannot see the difference either — it checks the DECLARATION,
		never the reachability. So the binding was NOT removed. The Menu takes the
		gesture inside its own trigger subtree and nowhere else.

		These two cases are the alarm in both directions. If `help` (D3a) ever binds
		long-press, the first one fails; if the carve-out is dropped, the second does. ]]
	local function discloseWorld()
		local core = harness.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 320, h = 640 })
		-- a pure-touch world, declared the way every other spec does: the CLASSES
		-- are derived from these two facts, never set directly
		env:set("capabilities", { keyboard = false, mouse = false, touch = true, gamepad = false })
		env:set("preferredInput", "Touch")
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = harness.newPresenter(core, env, adapter, system)
		return core, env, adapter, system, pres
	end

	it("the disclosure plate KEEPS long-press outside a menu trigger — the a11y route survives", function()
		local core, _, _, _, pres = discloseWorld()
		local long = "A racer name far too long for the sixty pixels this cell was given"
		pres.present(
			UI.Screen({
				id = "S",
				children = {
					UI.Text({
						id = "Name",
						text = long,
						disclose = true,
						lineLimit = 1,
						width = { type = "fixed", px = 60 },
					}),
				},
			}),
			{ initialFocus = "none" }
		)
		pres.refresh()
		pres._discloseLongPress("/S/Name")
		expect(pres.disclosure().present).toBe(true)
		expect(pres.disclosure().source).toBe("touch")
		expect(core.lastError()).toBeNil()
	end)

	it("...and inside a Menu trigger the MENU owns it: one gesture, one construct", function()
		local core, _, adapter, system, pres = discloseWorld()
		local long = "A racer name far too long for the sixty pixels this cell was given"
		local control = menuLib.build(
			Facet,
			core,
			{
				id = "M",
				trigger = UI.Button({
					id = "Trigger",
					label = long,
					width = { type = "fixed", px = 60 },
					height = { type = "fixed", px = 44 },
					children = {
						UI.Text({ id = "Name", text = long, disclose = true, lineLimit = 1 }),
					},
				}),
				items = ITEMS,
			} :: any
		)
		-- `initialFocus = "none"`: the FOCUS engagement is a third, separate route to
		-- the same plate and it is untouched by this carve-out (it is also the route
		-- a keyboard or pad player has). Leaving the ring on the trigger would put a
		-- plate on screen before the press ever happened and prove nothing about who
		-- owns the gesture.
		pres.present(
			UI.Screen({ id = "S", children = { control.blueprint } }),
			{ sinkNavigation = true, initialFocus = "none" }
		)
		pres.refresh()
		-- the same engagement the case above proves still fires, on a label that is
		-- still truncated — and it presents NOTHING, because the menu owns the press
		pres._discloseLongPress("/S/Trigger/Name")
		expect(pres.disclosure().present).toBe(false)
		-- and the gesture that DID arrive opens the menu
		adapter.driveTouchGesture("/S/Trigger", { kind = "longPress", state = "began", positions = {} })
		pres.refresh()
		expect(control.api.isOpen:peek()).toBe(true)
		expect(system ~= nil).toBe(true)
	end)

	it("exactly two constructs know the word long-press, and `help` is not going to be a third", function()
		--[[ THE DURABLE ALARM (brief §4: "help never binding long-press is a claim a
			spec should be able to fail on"). The two behavioural cases above prove who
			wins TODAY; this one fails the day a third construct starts competing at
			all, which is the failure that would otherwise arrive as a device-only
			report months later. It is deliberately a source sweep rather than a
			behaviour test, because the hazard is a NEW file nobody wrote a fixture
			for. Adding a legitimate consumer means adding it here, on purpose. ]]
		local fs = require("@lune/fs")
		local hits: { string } = {}
		local function walk(dir: string)
			for _, entry in fs.readDir(dir) do
				local path = `{dir}/{entry}`
				if fs.isDir(path) then
					walk(path)
				elseif
					string.sub(entry, -5) == ".luau"
					and (
						string.find(fs.readFile(path), "longPress", 1, true) ~= nil
						or string.find(fs.readFile(path), "LongPress", 1, true) ~= nil
					)
				then
					table.insert(hits, path)
				end
			end
		end
		walk("src")
		table.sort(hits)
		expect(table.concat(hits, " ")).toBe(
			-- the ENGINE side (the recognizer, the two adapter channels, the contract),
			-- the DISCLOSURE plate (which keeps the gesture), the MENU (which carves
			-- itself out of it), and the contribution field that states the carve-out.
			-- `split_button` is not a third construct: its touch form AUTHORS the
			-- Menu's own `triggers` list (a tap runs the action, the long press
			-- opens the menu), which is the one place a caller names the gesture.
			-- `render/env_wiring.luau` is not a fourth construct either: it is the
			-- renderer's own disclosure-engagement carry, which left `renderer.luau`
			-- on 2026-09-20 to put that file back under the engine's Source cap. The
			-- code is unchanged and the two files are one consumer. The same holds for
			-- `present/text_disclosure.luau`: the plate itself, which left the
			-- presenter for the same cap; the presenter keeps only the seam binding.
			"src/client/screen_target.luau src/controls/menu.luau src/controls/split_button.luau "
				.. "src/input/contribution.luau src/input/touch_gestures.luau src/present/presenter.luau "
				.. "src/present/text_disclosure.luau "
				.. "src/render/env_wiring.luau src/render/renderer.luau src/render/target_contract.luau"
		)
	end)

	it("a Menu declared WITHOUT a touch trigger takes nothing away from the plate", function()
		local core, _, _, _, pres = discloseWorld()
		local long = "A racer name far too long for the sixty pixels this cell was given"
		local control = menuLib.build(
			Facet,
			core,
			{
				id = "M",
				trigger = UI.Button({
					id = "Trigger",
					label = long,
					width = { type = "fixed", px = 60 },
					height = { type = "fixed", px = 44 },
					children = { UI.Text({ id = "Name", text = long, disclose = true, lineLimit = 1 }) },
				}),
				items = ITEMS,
				triggers = { "activate", "keyboard", "gamepad" },
			} :: any
		)
		pres.present(
			UI.Screen({ id = "S", children = { control.blueprint } }),
			{ sinkNavigation = true, initialFocus = "none" }
		)
		pres.refresh()
		pres._discloseLongPress("/S/Trigger/Name")
		expect(pres.disclosure().present).toBe(true)
		expect(control.api.isOpen:peek()).toBe(false)
	end)
end)

-- ===== the dump =========================================================

describe("D2 Menu: the dump says what is on screen", function()
	it("the dump carries the schema, the open chain and the whole item tree", function()
		local w = world({ items = NESTED })
		local shut = w.control.dump()
		expect(shut.schema).toBe("facet-menu-dump/1")
		expect(shut.open).toBe(false)
		expect(shut.surfaces).toBe(0)
		expect(string.find(shut.text, "closed", 1, true) ~= nil).toBe(true)
		w.control.api.open()
		w.control.api.select("adjust")
		w.pres.refresh()
		local open = w.control.dump()
		expect(open.open).toBe(true)
		expect(open.depth).toBe(1)
		expect(table.concat(open.openPath, ">")).toBe("adjust")
		expect(string.find(open.text, "depth 1", 1, true) ~= nil).toBe(true)
	end)

	it("dispose closes every live surface rather than stranding one", function()
		local w = world({ items = NESTED })
		w.control.api.open()
		w.control.api.select("adjust")
		w.pres.refresh()
		expect(w.pres.anchoredSurfaces().count).toBe(2)
		w.control.dispose()
		w.pres.refresh()
		expect(w.pres.anchoredSurfaces().count).toBe(0)
		expect(w.core.lastError()).toBeNil()
	end)
end)

-- ===== the card ==========================================================

--[[ ONE CARD, FLAT ROWS (user review of the desktop split button's menu,
	2026-09-12: *"the open menu still reads as stacked rounded rects"*).

	The anchored panel was a `raised` VStack of ordinary `control`-surfaced rows
	separated by a hairline of surface showing through the gap — so every row wore
	the theme's control radius and (under a skinned package) its whole button
	picture, and the plate behind them was invisible between them. What a player
	saw was a stack of buttons, not a menu.

	Five things have to hold together for the card to read as one plate, and each
	one fails in a way the other four hide:

	  * ONE hairline between two neighbouring rows — never two, never a gap AND a
	    rule (a 2px seam is what makes a highlight look under-filled at its edges);
	  * no row carrying the control radius, or the stack of rounded rects is back;
	  * the first and last rows carrying the CARD's radius on their OUTER corners,
	    or a square corner paints over the plate's arc (the engine does not clip a
	    child to its parent's `UICorner`);
	  * the selection fill being the row's own surface, which is the only way
	    "fits the row exactly" is true by construction rather than by two
	    rectangles agreeing;
	  * the selected row's LABEL pairing with that fill. A row with a check draws
	    its label into a child `UI.Text`, and no `TextButton` colour rule in the
	    sheet can reach a child — see `tests/selection_contrast.spec.luau` for the
	    measurement that makes `accent`/`onAccent` the pair this uses. ]]
describe("D2 Menu: the anchored panel is ONE card", function()
	local CHECKED = {
		{ id = "a", label = "Alpha", onSelect = function() end },
		{ id = "b", label = "Beta", checked = nil :: any },
		{ id = "c", label = "Gamma", onSelect = function() end },
	}
	local function cardWorld()
		local core = harness.newCore()
		local checked = Compose.cell(true)
		local items = table.clone(CHECKED)
		items[2] = { id = "b", label = "Beta", checked = checked }
		local w = world({ items = items, presentation = "menu" })
		w.control.api.open()
		w.pres.refresh()
		return w, checked
	end
	-- a floating panel's rows scroll one level deeper (always bounded)
	local PANEL = "/Menu-M/Layer/Surface/Popup/Panel/List/Rows"

	it("draws exactly one hairline between two rows — rows minus one, and no gap besides", function()
		local w = cardWorld()
		local rules = 0
		for _, path in w.adapter.paths() do
			-- plain find: the surface id carries a `-`, which is a Lua pattern
			-- quantifier, and a pattern that silently matches nothing counts zero
			-- rules and passes the day the card stops drawing them
			if string.find(path, `{PANEL}/Rule-`, 1, true) == 1 then
				rules += 1
			end
		end
		expect(rules).toBe(2) -- three rows
		-- ...and the rows TOUCH their rule: the panel's own gap is gone, so the
		-- separator is the hairline and nothing else
		local a = w.adapter.node(rowPath(0, "a")).rect
		local rule = w.adapter.node(`{PANEL}/Rule-2`).rect
		local b = w.adapter.node(rowPath(0, "b")).rect
		expect(rule.y).toBe(a.y + a.h)
		expect(b.y).toBe(rule.y + rule.h)
	end)

	it("no row carries a control radius, and the card's ends carry the PANEL's", function()
		local w = cardWorld()
		local function corners(id: string): any
			return w.adapter.node(rowPath(0, id)).props.corners
		end
		-- the middle row is square on all four
		local middle = corners("b")
		expect(middle.form).toBe("perCorner")
		expect(middle.topLeft).toBe(0)
		expect(middle.bottomRight).toBe(0)
		expect(middle.tokens).toBeNil()
		-- the ends take the card's own radius OUTWARD and 0 into the card, named
		-- by TOKEN so a theme that retunes `radii.panel` retunes the card with it
		local first, last = corners("a"), corners("c")
		expect(first.tokens.topLeft).toBe(menuRecipe.CARD_CORNER)
		expect(first.tokens.topRight).toBe(menuRecipe.CARD_CORNER)
		expect(first.bottomLeft).toBe(0)
		expect(last.tokens.bottomLeft).toBe(menuRecipe.CARD_CORNER)
		expect(last.tokens.bottomRight).toBe(menuRecipe.CARD_CORNER)
		expect(last.topRight).toBe(0)
		-- and the radius they take IS the panel's, read off the same node
		expect(first.topLeft).toBe(last.bottomRight)
	end)

	it("the selection fill IS the row — same rect, no second box, clipped by the card's ends", function()
		local w, checked = cardWorld()
		local row = w.adapter.node(rowPath(0, "b"))
		expect(row.props.surface).toBe(menuRecipe.SELECTED_SURFACE)
		-- the unselected neighbours paint nothing at all, so the card is the plate
		expect(w.adapter.node(rowPath(0, "a")).props.surface).toBe(menuRecipe.RESTING_SURFACE)
		-- there is no separate fill node to drift from the row's rect
		for _, path in w.adapter.paths() do
			expect(string.find(path, "Fill", 1, true) == nil).toBe(true)
		end
		-- the fill spans the row, which spans the card inside its inner hairline (F1)
		local panel = w.adapter.node((string.gsub(PANEL, "/List/Rows$", ""))).rect
		local hairline = require("../src/themes/snapshot").neutral().strokes.hairline
		expect(row.rect.w).toBe(panel.w - 2 * hairline)
		--[[ ...and it is a FILL, not a picture. `slot = "none"` is what keeps a
			skinned package from painting its whole control plate over the one row
			that is meant to read as a wash inside the card — the same declaration
			`selection_indicator` makes for its pill, and without it the paired
			label is sitting on art rather than on `$Accent`. ]]
		expect(row.decorationHint.slot).toBe("none")
		-- ...and it lets go when the item does
		checked:set(false)
		w.pres.refresh()
		expect(w.adapter.node(rowPath(0, "b")).props.surface).toBe(menuRecipe.RESTING_SURFACE)
	end)

	it("the selected row's LABEL is painted for the fill it now sits on", function()
		local w, checked = cardWorld()
		-- the row's content stacks are unnamed, so the label is found under the row
		local label
		for _, path in w.adapter.paths() do
			if
				string.sub(path, 1, #rowPath(0, "b") + 1) == rowPath(0, "b") .. "/"
				and string.sub(path, -6) == "/Label"
			then
				label = path
			end
		end
		local tint = w.adapter.node(label).props.tint
		expect(tint.role).toBe(menuRecipe.SELECTED_LABEL_ROLE)
		expect(tint.blend).toBe(1)
		-- ...and BOTH ends are named: a bound paint that resolves to nil releases
		-- its claim, and a release restores what the property held when the claim
		-- was taken — the previous occupant's colour on a recycled instance
		checked:set(false)
		w.pres.refresh()
		expect(w.adapter.node(label).props.tint.role).toBe(menuRecipe.RESTING_LABEL_ROLE)
	end)

	it("...and so does the row's ICON, which is the rule doing what it says", function()
		local checked = Compose.cell(true)
		local w = world({
			items = {
				{ id = "a", label = "Alpha", icon = "checkmark", description = "First", onSelect = function() end },
				{ id = "b", label = "Beta", icon = "close", checked = checked },
			},
			presentation = "menu",
		})
		w.control.api.open()
		w.pres.refresh()
		local function letters(id: string): string
			local iconPath
			for _, path in w.adapter.paths() do
				if
					string.sub(path, 1, #rowPath(0, id) + 1) == rowPath(0, id) .. "/"
					and string.sub(path, -5) == "/Icon"
				then
					iconPath = path
				end
			end
			local tags = w.adapter.tagsOf(assert(iconPath, "mounted menu icon"))
			for _, tag in tags do
				if string.find(tag, "facet-letters-", 1, true) == 1 then
					return tag
				end
			end
			return "none"
		end
		expect(`selected {letters("b")} · resting {letters("a")}`).toBe(
			`selected facet-letters-{menuRecipe.SELECTED_LABEL_ROLE} · resting none`
		)
		-- ...and it lets go with the selection, exactly as the label's tint does
		checked:set(false)
		w.pres.refresh()
		expect(`released {letters("b")}`).toBe("released none")
	end)

	it("the SHEET keeps the shape it had — the card is a presentation branch", function()
		local core = harness.newCore()
		local checked = Compose.cell(true)
		local w = world({
			items = {
				{ id = "a", label = "Alpha", onSelect = function() end },
				{ id = "b", label = "Beta", checked = checked },
			},
			presentation = "sheet",
		})
		w.control.api.open()
		w.pres.refresh()
		local row = w.adapter.node("/Menu-M/Layer/Panel/Item:b")
		expect(row ~= nil).toBe(true)
		expect(row.props.surface).toBeNil()
		expect(row.props.corners).toBeNil()
		expect(row.props.selected).toBe(true)
	end)
end)

describe("menu: the floating panel materializes", function()
	local FRAME = 1 / 60
	it("fades and grows in, then leaves faster", function()
		--[[ MEASURED ON THE PAINT (task 7 item 1), for the reason alert.spec's
			twin states at length: "frames until the node is gone" was decided by
			the flat 500 ms exit cap, not by the exit class, so the old
			comparison passed under `exitClass = "container"` exactly as it did
			under `dismiss` and proved nothing about the asymmetry the round
			introduced. The pin is now the frame the popup's fade crosses 95% in
			each direction, plus the fact that its own spring — not the cap —
			ends the exit. ]]
		local w = world({})
		w.adapter.tap(TRIGGER)
		w.pres.refresh()
		local popupPath = rowPath(0, "accessory"):gsub("/Popup/Panel/List/Rows/Item:accessory$", "/Popup")
		local popup = w.adapter.node(popupPath)
		expect(popup ~= nil and popup.canvasGroupInstance ~= nil).toBe(true)
		expect(popup.canvasGroupInstance.groupTransparency).toBe(1)
		local enterCross = -1
		for f = 1, 120 do
			w.pres.tick(FRAME)
			if enterCross < 0 and popup.canvasGroupInstance.groupTransparency <= 0.05 then
				enterCross = f
			end
		end
		expect(popup.canvasGroupInstance.groupTransparency).toBe(0)
		-- closing through the control's own verb (the file's other whole-menu
		-- teardown case, :860, uses the same one): the popup now dips out on a
		-- real exit transition rather than vanishing on this tick, so its node
		-- survives `close()` until the coordinator's retire completes
		w.control.api.close()
		w.pres.refresh()
		local exitCross, goneAt = -1, -1
		for f = 1, 120 do
			w.pres.tick(FRAME)
			local node = w.adapter.node(popupPath)
			if node == nil then
				if goneAt < 0 then
					goneAt = f
				end
			elseif exitCross < 0 and node.canvasGroupInstance.groupTransparency >= 0.95 then
				exitCross = f
			end
		end
		expect(w.adapter.node(popupPath)).toBeNil()
		-- the PACE, and then the LIFETIME
		expect(exitCross > 0 and exitCross < enterCross).toBe(true)
		expect(goneAt > 0 and goneAt < math.ceil(Facet.EXIT_CAP_SECONDS * 60)).toBe(true)
	end)
end)

describe("sheet submenu motion", function()
	for _, reduced in { false, true } do
		it("slides in opposite directions on enter and Back; reduced=" .. tostring(reduced), function()
			local w = world({ presentation = "sheet", items = NESTED })
			w.env:set("reducedMotion", reduced)
			w.adapter.tap(TRIGGER)
			for _ = 1, 60 do
				w.pres.tick(1 / 60)
			end
			w.adapter.tap(sheetRow("adjust"))
			w.pres.refresh()
			local panel = w.adapter.node("/Menu-M/Layer/Panel")
			local forward = panel.presentationOffset and panel.presentationOffset.x or 0
			expect(if reduced then forward == 0 else forward > 0).toBe(true)
			for _ = 1, 60 do
				w.pres.tick(1 / 60)
			end
			w.adapter.tap("/Menu-M/Layer/Panel/Back")
			w.pres.refresh()
			panel = w.adapter.node("/Menu-M/Layer/Panel")
			local backward = panel.presentationOffset and panel.presentationOffset.x or 0
			expect(if reduced then backward == 0 else backward < 0).toBe(true)
			for _ = 1, 60 do
				w.pres.tick(1 / 60)
			end
			expect(w.control.dump().depth).toBe(0)
			expect(w.control.dump().surfaces).toBe(1)
			w.control.dispose()
			w.pres.dismiss(w.handle)
		end)
	end
end)

describe("Menu: placement, width, a bounded list and the shared row vocabulary", function()
	local function open(w: any)
		w.adapter.tap(TRIGGER)
		w.pres.refresh()
	end
	local SURFACE0 = "/Menu-M/Layer/Surface"

	it("edge and align place the root panel; absent keeps bottom/start", function()
		local base = world({ w = 800, h = 600 })
		open(base)
		expect(base.pres.anchoredSurfaces().surfaces[1].edge).toBe("bottom")
		local w = world({ w = 800, h = 600, edge = "trailing", align = "center" })
		open(w)
		local dump = w.pres.anchoredSurfaces().surfaces[1]
		expect(dump.edge).toBe("right")
		local trigger, panel = w.adapter.node(TRIGGER).rect, w.adapter.node(SURFACE0).rect
		expect(panel.x >= trigger.x + trigger.w).toBe(true)
	end)

	it("width sets the panel's width dimension", function()
		local w = world({ width = { type = "fixed", px = 300 } })
		open(w)
		expect(w.adapter.node("/Menu-M/Layer/Surface/Popup/Panel").rect.w).toBe(300)
	end)

	it("rows with a badge, a shortcut or a section heading never collapse the panel", function()
		local items = {}
		for i = 1, 6 do
			table.insert(items, {
				id = `t{i}`,
				label = `Track {i}`,
				badge = "New",
				shortcutLabel = if i == 1 then "Ctrl+1" else nil,
				sectionTitle = if i == 4 then "Night" else nil,
				onSelect = function() end,
			})
		end
		local w = world({ items = items })
		open(w)
		local panel = w.adapter.node("/Menu-M/Layer/Surface/Popup/Panel").rect
		expect(panel.w >= 120).toBe(true)
		for i = 1, 6 do
			local label = w.adapter.node(rowPath(0, `t{i}`)).rect
			expect(`Track {i} w>40: {label.w > 40}`).toBe(`Track {i} w>40: true`)
		end
	end)

	it("plain rows lead like accessory rows, and every row reserves the target floor", function()
		local items = {
			{ id = "a", label = "All tracks", badge = 3, onSelect = function() end },
			{ id = "b", label = "Favourites", shortcutLabel = "Ctrl+F", onSelect = function() end },
		}
		for i = 1, 4 do
			table.insert(items, { id = `p{i}`, label = `Track {i}`, onSelect = function() end })
		end
		local w = world({ items = items })
		open(w)
		local floor = require("../src/themes/snapshot").neutral().targetSizes.minimum
		local lefts, previous = {}, nil
		for _, item in items do
			local row = rowPath(0, item.id)
			local rect = w.adapter.node(row).rect
			expect(`{item.id} h>={floor}: {rect.h >= floor}`).toBe(`{item.id} h>={floor}: true`)
			if previous ~= nil then
				expect(`{item.id} clear of the row above: {rect.y >= previous.y + previous.h}`).toBe(
					`{item.id} clear of the row above: true`
				)
			end
			previous = rect
			for _, path in w.adapter.paths() do
				if string.sub(path, 1, #row + 1) == row .. "/" and string.sub(path, -6) == "/Label" then
					lefts[item.id] = w.adapter.node(path).rect.x
				end
			end
			expect(`{item.id} has a leading label: {lefts[item.id] ~= nil}`).toBe(`{item.id} has a leading label: true`)
		end
		for _, item in items do
			expect(`{item.id} label x {lefts[item.id]}`).toBe(`{item.id} label x {lefts.a}`)
		end
	end)

	it("a floating panel never outgrows the screen: a long list scrolls (owner: the blurry year menu)", function()
		-- 201 rows ran 9,448 px off the screen, and its fade group outgrew the
		-- engine's canvas budget, blurring every CanvasGroup's text
		local items = {}
		for i = 1, 201 do
			table.insert(items, { id = `y{i}`, label = tostring(1925 + i), onSelect = function() end })
		end
		local w = world({ items = items })
		open(w)
		local panel = w.adapter.node("/Menu-M/Layer/Surface/Popup/Panel").rect
		expect(`panel {panel.h <= 600}`).toBe("panel true")
		expect(w.adapter.node("/Menu-M/Layer/Surface/Popup/Panel/List/Rows/Item:y201") ~= nil).toBe(true)
	end)

	it(
		"a menu opens on its selected row, centred in the scrolled list (owner: the year menu opened at 1926)",
		function()
			local year = Compose.cell(2026)
			local items = {}
			for y = 1926, 2126 do
				table.insert(items, { id = `y{y}`, label = tostring(y), selected = year, value = y })
			end
			local w = world({ items = items })
			open(w)
			local path = "/Menu-M/Layer/Surface/Popup/Panel/List/Rows/Item:y2026"
			expect(w.pres.focus.focused:peek()).toBe(path)
			local list = w.adapter.node("/Menu-M/Layer/Surface/Popup/Panel/List")
			local row = w.adapter.node(path).rect
			local scrolled = (list.scrollPosition or { y = 0 }).y
			local off = (row.y - scrolled + row.h / 2) - (list.rect.y + list.rect.h / 2)
			expect(`centred={math.abs(off) <= 1}`).toBe("centred=true")
		end
	)

	it("maxHeight bounds the whole panel and the rows scroll, with ids and activation intact", function()
		local items = {}
		local picked: { string } = {}
		for i = 1, 20 do
			table.insert(items, {
				id = `row{i}`,
				label = `Row {i}`,
				onSelect = function()
					table.insert(picked, `row{i}`)
				end,
			})
		end
		local w = world({ items = items, maxHeight = 200 })
		open(w)
		local panel = w.adapter.node("/Menu-M/Layer/Surface/Popup/Panel").rect
		expect(panel.h <= 200).toBe(true)
		local last = "/Menu-M/Layer/Surface/Popup/Panel/List/Rows/Item:row20"
		expect(w.adapter.node(last) ~= nil).toBe(true)
		-- keyboard walks to the last row and it is scrolled into view, then activates
		for _ = 1, 19 do
			w.system.deviceKey("Down", true)
			w.system.deviceKey("Down", false)
			w.pres.refresh()
		end
		expect(w.pres.focus.focused:peek()).toBe(last)
		local list = w.adapter.node("/Menu-M/Layer/Surface/Popup/Panel/List")
		local scrolled = (list.scrollPosition or { y = 0 }).y
		local row = w.adapter.node(last).rect
		expect(scrolled > 0).toBe(true)
		expect(`visible={row.y - scrolled + row.h <= list.rect.y + list.rect.h + 1}`).toBe("visible=true")
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(table.concat(picked, ",")).toBe("row20")
	end)

	it("a bounded list keeps submenus anchored to their parent row", function()
		local w = world({ items = NESTED, maxHeight = 300 })
		w.control.api.open()
		w.pres.refresh()
		expect(w.pres.focus.focused:peek()).toBe("/Menu-M/Layer/Surface/Popup/Panel/List/Rows/Item:adjust")
		w.system.deviceKey("Right", true)
		w.system.deviceKey("Right", false)
		w.pres.refresh()
		local surfaces = w.pres.anchoredSurfaces().surfaces
		expect(#surfaces).toBe(2)
		expect(surfaces[2].edge).toBe("right")
		expect(w.adapter.node("/Menu-M-L1/Layer/Surface/Popup/Panel/List/Rows/Item:head") ~= nil).toBe(true)
	end)

	it("badge, avatar, sectionTitle and a display-only shortcutLabel share the row recipe", function()
		local ran = 0
		local w = world({
			items = {
				{
					id = "a",
					label = "Alpha",
					badge = 3,
					sectionTitle = "Recent",
					onSelect = function()
						ran += 1
					end,
				},
				{
					id = "b",
					label = "Beta",
					avatar = { name = "Bea" },
					shortcutLabel = "Ctrl+B",
					onSelect = function() end,
				},
			},
		})
		open(w)
		local panel = "/Menu-M/Layer/Surface/Popup/Panel"
		expect(w.adapter.node(`{panel}/List/Rows/Section:a/SectionTitle`).props.text).toBe("Recent")
		local texts: { string } = {}
		local avatar = false
		for _, path in w.adapter.paths() do
			if string.find(path, "Item:b/", 1, true) ~= nil and string.find(path, "Avatar", 1, true) ~= nil then
				avatar = true
			end
			local node = w.adapter.node(path)
			if string.find(path, panel, 1, true) == 1 and node.class == "Text" then
				table.insert(texts, node.props.text)
			end
		end
		expect(avatar).toBe(true)
		expect(table.find(texts, "3") ~= nil).toBe(true)
		expect(table.find(texts, "Ctrl+B") ~= nil).toBe(true)
		-- the heading is not a stop: the first Down lands on the first ROW
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(string.find(w.pres.focus.focused:peek() or "", "Item:", 1, true) ~= nil).toBe(true)
		-- the shortcut label registers nothing: pressing B does not select
		w.system.deviceKey("B", true)
		w.system.deviceKey("B", false)
		expect(ran).toBe(0)
	end)

	it("malformed placement and bounds are refused by name", function()
		for _, bad in
			{
				{ edge = "middle" },
				{ align = "top" },
				{ maxHeight = 0 },
				{ maxHeight = math.huge },
				{ width = 200 },
			}
		do
			local ok, err = pcall(world, bad)
			expect(ok).toBe(false)
			local key = next(bad) :: string
			expect(string.find(tostring(err), key, 1, true) ~= nil).toBe(true)
		end
	end)
end)

-- DENSE POINTER ROWS (owner ruling 2026-09-24): a theme's `targetSizes.pointer`
-- is the floating menu's row pitch while the input is pointer-only
describe("Menu rows under a dense pointer theme", function()
	it("rows take the pointer floor, each hit is its row, and a gamepad grows them to 44 live", function()
		local snapshot = require("../src/themes/snapshot")
		local pkg = Facet.themes.define({
			base = snapshot.neutralPackage(),
			identity = { id = "dense", displayName = "Dense", schemaVersion = Facet.themes.SCHEMA, version = "1.0.0" },
			metrics = { targetSizes = { minimum = 44, pointer = 28 } },
		})
		local w = world({ presentation = "menu" })
		w.env:set("themeMetrics", snapshot.resolve(pkg))
		w.env:set("capabilities", { mouse = true, keyboard = true, touch = false, gamepad = false })
		w.control.api.open()
		w.pres.refresh()
		local function pitch(): (string, boolean)
			local out, previous, overlap = {}, nil, false
			for _, item in ITEMS do
				local path = rowPath(0, item.id)
				local hit = w.adapter.hitRectOf(path) or w.adapter.node(path).rect
				table.insert(out, tostring(math.round(hit.h)))
				if previous ~= nil and hit.y < previous.y + previous.h then
					overlap = true
				end
				previous = hit
			end
			return table.concat(out, ","), overlap
		end
		expect((pitch())).toBe("28,28,28")
		w.env:set("capabilities", { mouse = true, keyboard = true, touch = false, gamepad = true })
		w.pres.refresh()
		-- back to the shipped row: the 44 floor, grown by its content as in Neutral
		local tall, overlap = pitch()
		expect(tall).toBe("46,46,46")
		expect(overlap).toBe(false)
		w.env:set("capabilities", { mouse = true, keyboard = true, touch = false, gamepad = false })
		w.pres.refresh()
		local dense, denseOverlap = pitch()
		expect(dense).toBe("28,28,28")
		expect(denseOverlap).toBe(false)
	end)
end)
