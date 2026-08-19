--!strict
--[[ D2 — THE `Menu` CONSTRUCT (navigation-and-menus brief §2 D2).

	A freestanding ACTION menu: items are VERBS, not values. It attaches to any
	blueprint, presents on D1's anchored seam, renders its rows from the ONE
	shared recipe, and opens on all five triggers — which together are what close
	`.contextMenu`, listed Missing until this stage.

	Six things here are the ones a lower-level test cannot see, so they get named
	cases rather than a smoke test:

	  * a submenu nests with NO structural cap and says so at depth >= 2. A hard
	    cap forbids what SwiftUI allows; no diagnostic permits twice what the HIG
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

local UI = Facet.UI

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
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = options.w or 800, h = options.h or 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
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
	return `/{surface}/Layer/Surface/Panel/Item:{itemId}`
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
		local core = Facet.newCore()
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
		local core = Facet.newCore()
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
		local core = Facet.newCore()
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

	it("HIG: icons for ALL items in a group, or none — a half-iconned group is refused", function()
		local core = Facet.newCore()
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
		local core = Facet.newCore()
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
		local core = Facet.newCore()
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
		local core = Facet.newCore()
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
		-- ...AND DIAGNOSED: SwiftUI caps nothing, the HIG advises one level
		local notes = table.concat(control.api.diagnostics(), " | ")
		expect(string.find(notes, "nests 2 levels deep", 1, true) ~= nil).toBe(true)
		expect(string.find(notes, "single level", 1, true) ~= nil).toBe(true)
	end)

	it("one level of submenu is silent — the diagnostic is advice, not noise", function()
		local core = Facet.newCore()
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

	it("HIG: a group of more than about five items is diagnosed as wanting its own menu", function()
		local core = Facet.newCore()
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

	it("HIG: a destructive item that is not last is diagnosed", function()
		local core = Facet.newCore()
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
		expect(w.control.api.isOpen:get()).toBe(true)
		local trigger = w.adapter.node(TRIGGER).rect
		local panel = w.adapter.node("/Menu-M/Layer/Surface/Panel").rect
		-- D1 placed it: below the source, not at a parent corner
		expect(panel.y >= trigger.y + trigger.h).toBe(true)
		expect(w.pres.anchoredSurfaces().count).toBe(1)
	end)

	it("a pointer SECONDARY click on the trigger opens the menu", function()
		local w = world()
		expect(w.adapter.driveSecondaryActivate(TRIGGER)).toBe(true)
		w.pres.refresh()
		expect(w.control.api.isOpen:get()).toBe(true)
		expect(w.adapter.node(rowPath(0, "body")) ~= nil).toBe(true)
	end)

	it("a touch LONG-PRESS on the trigger opens the menu, through the normalized gesture layer", function()
		local w = world()
		-- the value object the SHIPPED normalizer produces, not a bespoke event:
		-- `touch_gestures.normalize("longPress", { positions, state })`
		w.adapter.driveTouchGesture(TRIGGER, { kind = "longPress", state = "began", positions = {} })
		w.pres.refresh()
		expect(w.control.api.isOpen:get()).toBe(true)
		-- ...and the RELEASE does not re-toggle it shut under the finger
		w.adapter.driveTouchGesture(TRIGGER, { kind = "longPress", state = "ended", positions = {} })
		w.pres.refresh()
		expect(w.control.api.isOpen:get()).toBe(true)
	end)

	it("a tap gesture is NOT a long press: the menu stays shut", function()
		local w = world()
		w.adapter.driveTouchGesture(TRIGGER, { kind = "tap", state = "ended", positions = {} })
		w.pres.refresh()
		expect(w.control.api.isOpen:get()).toBe(false)
	end)

	it("the keyboard context chord opens the menu, and Return activates the focused item", function()
		local w = world()
		w.system.deviceKey("Menu", true)
		w.system.deviceKey("Menu", false)
		w.pres.refresh()
		expect(w.control.api.isOpen:get()).toBe(true)
		-- the open rows are ordinary focusables, so the ring is already on the first
		expect(w.pres.focus.focused:get()).toBe(rowPath(0, "accessory"))
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		w.pres.refresh()
		expect(w.control.api.isOpen:get()).toBe(false)
	end)

	it("the gamepad menu button opens it, and ButtonB closes ONE level", function()
		local w = world({ items = NESTED })
		w.system.deviceKey("ButtonY", true)
		w.system.deviceKey("ButtonY", false)
		w.pres.refresh()
		expect(w.control.api.isOpen:get()).toBe(true)
		w.control.api.select("adjust")
		w.pres.refresh()
		expect(#w.control.api.openPath:get()).toBe(1)
		-- ONE level, not all of them
		w.system.deviceKey("ButtonB", true)
		w.system.deviceKey("ButtonB", false)
		w.pres.refresh()
		expect(#w.control.api.openPath:get()).toBe(0)
		expect(w.control.api.isOpen:get()).toBe(true)
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
		expect(w.control.api.isOpen:get()).toBe(false)
		expect(w.pres.anchoredSurfaces().count).toBe(0)
	end)

	it("every trigger declared is honoured, and one that was not is inert", function()
		local w = world({ triggers = { "activate" } })
		expect(w.adapter.driveSecondaryActivate(TRIGGER)).toBe(false)
		w.adapter.driveTouchGesture(TRIGGER, { kind = "longPress", state = "began", positions = {} })
		w.pres.refresh()
		expect(w.control.api.isOpen:get()).toBe(false)
		w.adapter.tap(TRIGGER)
		w.pres.refresh()
		expect(w.control.api.isOpen:get()).toBe(true)
	end)
end)

-- ===== the state nobody fixtures ========================================

describe("D2 Menu: a menu whose every item is disabled still OPENS", function()
	it("a wholly unavailable menu opens rather than swallowing its trigger", function()
		--[[ Apple: "If all of a menu's items are unavailable, the menu itself needs
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
		expect(w.control.api.isOpen:get()).toBe(true)
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
		expect(w.control.api.isOpen:get()).toBe(true)
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
		expect(#w.control.api.openPath:get()).toBe(2)
		expect(w.pres.anchoredSurfaces().count).toBe(3)
		-- a tap on a node OUTSIDE the menu: the presenter's own outside-tap path
		w.adapter.tap(TRIGGER)
		w.pres.refresh()
		expect(w.control.api.isOpen:get()).toBe(false)
		expect(w.pres.anchoredSurfaces().count).toBe(0)
	end)

	it("Cancel unwinds the chain one level at a time, and only then closes", function()
		local w = world({ items = NESTED })
		w.control.api.open()
		w.pres.refresh()
		w.control.api.select("adjust")
		w.control.api.select("layer")
		w.pres.refresh()
		expect(#w.control.api.openPath:get()).toBe(2)
		w.control.api.closeLevel()
		w.pres.refresh()
		expect(#w.control.api.openPath:get()).toBe(1)
		expect(w.control.api.isOpen:get()).toBe(true)
		w.control.api.closeLevel()
		w.pres.refresh()
		expect(#w.control.api.openPath:get()).toBe(0)
		expect(w.control.api.isOpen:get()).toBe(true)
		w.control.api.closeLevel()
		w.pres.refresh()
		expect(w.control.api.isOpen:get()).toBe(false)
	end)

	it("Right enters the focused submenu and Left leaves it, in document order", function()
		local w = world({ items = NESTED })
		w.control.api.open()
		w.pres.refresh()
		expect(w.pres.focus.focused:get()).toBe(rowPath(0, "adjust"))
		w.system.deviceKey("Right", true)
		w.system.deviceKey("Right", false)
		w.pres.refresh()
		expect(w.control.api.openPath:get()[1]).toBe("adjust")
		w.system.deviceKey("Left", true)
		w.system.deviceKey("Left", false)
		w.pres.refresh()
		expect(#w.control.api.openPath:get()).toBe(0)
	end)

	it("Right on a plain ACTION row is not the menu's arrow, so the ring keeps it", function()
		local w = world()
		w.control.api.open()
		w.pres.refresh()
		w.system.deviceKey("Right", true)
		w.system.deviceKey("Right", false)
		w.pres.refresh()
		expect(#w.control.api.openPath:get()).toBe(0)
		expect(w.control.api.isOpen:get()).toBe(true)
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
		expect(#w.control.api.openPath:get()).toBe(0)
		expect(w.control.api.isOpen:get()).toBe(true)
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
		local core = Facet.newCore()
		local classes = core:signal({ pointer = true, primary = "pointer" })
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
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
		expect(control.api.openPath:get()[1]).toBe("adjust")
		expect(control.dump().surfaces).toBe(1)
		expect(adapter.node("/Menu-M/Layer/Panel/Item:head") ~= nil).toBe(true)
	end)
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
		expect(row.children).toBeNil()
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
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local value = core:signal("a")
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
		local core = Facet.newCore()
		local ok, err = pcall(function()
			popup_button.build(
				Facet,
				core,
				{
					id = "P",
					options = { { id = "a", label = "A", icon = "edit" }, { id = "b", label = "B" } },
					value = core:signal("a"),
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
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 320, h = 640 })
		-- a pure-touch world, declared the way every other spec does: the CLASSES
		-- are derived from these two facts, never set directly
		env:set("capabilities", { keyboard = false, mouse = false, touch = true, gamepad = false })
		env:set("preferredInput", "Touch")
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
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
		expect(core:lastError()).toBeNil()
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
		expect(control.api.isOpen:get()).toBe(true)
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
			"src/client/screen_target.luau src/controls/menu.luau src/input/contribution.luau "
				.. "src/input/touch_gestures.luau src/present/presenter.luau src/render/renderer.luau "
				.. "src/render/target_contract.luau"
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
		expect(control.api.isOpen:get()).toBe(false)
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
		expect(w.core:lastError()).toBeNil()
	end)
end)
