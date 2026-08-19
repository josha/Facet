--!strict
--[[ ADAPT-1 — ADAPTATION ARRIVES BY ITSELF, OR THE CONTROL SAYS SO.

	The audit's spine finding (`artifacts/release-candidate-review/adapt-audit/
	matrix.md`, critical): every adaptive rung ran on facts the AUTHOR had to hand
	to the control, and a missing fact was SILENT — `picker.resolvePresentation(4,
	nil, 14)` answers "segmented", four long labels crammed onto a phone, where the
	same call with a size class answers "inline". The census made the consequence
	concrete: of seventeen `Picker` call sites in `examples/`, eight wired the
	fact, ten disabled the ladder outright, and ZERO relied on the adaptive
	default, so the touch->sheet rung had never fired in any shipped app.

	The fix is one channel and one rule. An environment publishes itself against
	the CORE it was built on (`src/env/surface_env.luau`), which is the same core
	every control on that surface is built with — so a control asks instead of
	being told. When there is nothing to ask, it refuses to construct, naming the
	host, in the shape `tab_view` has used since 2026-08-16.

	THE FILE IS THE STANDING GUARD for that contract: every case here fails if the
	channel is removed, and the refusal cases fail if the refusal is softened into
	a default. It also pins the two rules that keep the channel honest — a second
	environment on one core is refused rather than guessed at, and re-publishing
	the SAME environment is not ambiguity. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local host = require("../src/client/host")
local actionsLib = require("../src/input/actions")
local surfaceEnv = require("../src/env/surface_env")
local fake_target = require("./lib/fake_target")
local UI = Facet.UI

local TOUCH = { touch = true, mouse = false, keyboard = false, gamepad = false }

-- a surface: core, environment, presenter — in the order the world builds them,
-- and NOTHING is passed to any control below
local function surface(w: number, h: number, classes: any?, preferred: string?)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
	if classes ~= nil then
		env:set("capabilities", classes)
	end
	if preferred ~= nil then
		env:set("preferredInput", preferred)
	end
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	return { core = core, env = env, adapter = adapter, system = system, pres = pres }
end

local LONG_OPTIONS = {
	{ value = "a", label = "Alphabetical order" },
	{ value = "b", label = "Beta distribution" },
	{ value = "c", label = "Chronological" },
	{ value = "d", label = "Descending value" },
}

describe("ADAPT-1: the environment is discoverable from the core it was built on", function()
	it("publishes itself, and a control on that core finds it", function()
		local s = surface(390, 844)
		expect(surfaceEnv.find(s.core)).toBe(s.env)
	end)

	it("an unrelated core has nothing to find, and says which of the two reasons", function()
		local bare = Facet.newCore()
		local found, reason = surfaceEnv.find(bare)
		expect(found).toBeNil()
		expect(reason).toBe("none")
	end)

	it("TWO environments on one core are refused, never resolved by coin flip", function()
		local core = Facet.newCore()
		Facet.newEnvironment(core)
		Facet.newEnvironment(core)
		local found, reason = surfaceEnv.find(core)
		expect(found).toBeNil()
		expect(reason).toBe("ambiguous")
		-- and a control on that core says so, naming the way out
		local ok, err = pcall(function()
			return Facet.Controls.Picker(core, {
				id = "P",
				options = LONG_OPTIONS,
				selected = core:signal("a"),
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "MORE THAN ONE environment", 1, true) ~= nil).toBe(true)
	end)

	it("re-publishing the SAME environment is not ambiguity", function()
		local s = surface(390, 844)
		surfaceEnv.publish(s.core, s.env)
		expect(surfaceEnv.find(s.core)).toBe(s.env)
	end)
end)

describe("ADAPT-1: the six adaptive controls take their facts from the surface", function()
	it("Picker: a compact surface collapses four long labels to the row list, unwired", function()
		local phone = surface(390, 844)
		local wide = surface(1400, 900)
		local onPhone = Facet.Controls.Picker(phone.core, {
			id = "P",
			options = LONG_OPTIONS,
			selected = phone.core:signal("a"),
		})
		local onDesktop = Facet.Controls.Picker(wide.core, {
			id = "P",
			options = LONG_OPTIONS,
			selected = wide.core:signal("a"),
		})
		-- FOUR options is the count the ladder still calls segmented; the WIDTH
		-- axis is the one that was dead, and it is the one this asserts
		expect(onPhone.dump().presentation).toBe("inline")
		expect(onPhone.dump().sizeClassFrom).toBe("core")
		expect(onDesktop.dump().presentation).toBe("segmented")
		onPhone.dispose()
		onDesktop.dispose()
	end)

	it("Picker: an authored size class still wins over the surface's", function()
		local wide = surface(1400, 900)
		local pinned = Facet.Controls.Picker(wide.core, {
			id = "P",
			options = LONG_OPTIONS,
			selected = wide.core:signal("a"),
			sizeClass = "compact",
		})
		expect(pinned.dump().presentation).toBe("inline")
		expect(pinned.dump().sizeClassFrom).toBe("spec")
		pinned.dispose()
	end)

	it("PopupButton: touch resolves the SHEET with nothing wired at all", function()
		local phone = surface(390, 844, TOUCH, "Touch")
		local popup = Facet.Controls.PopupButton(phone.core, {
			id = "Choice",
			value = phone.core:signal("one"),
			options = {
				{ id = "one", label = "One" },
				{ id = "two", label = "Two" },
				{ id = "three", label = "Three" },
				{ id = "four", label = "Four" },
			},
		})
		expect(popup.presentation()).toBe("sheet")
		expect(popup.dump().factsFrom).toBe("core")
		popup.dispose()

		local desktop = surface(1400, 900)
		local pointer = Facet.Controls.PopupButton(desktop.core, {
			id = "Choice",
			value = desktop.core:signal("one"),
			options = {
				{ id = "one", label = "One" },
				{ id = "two", label = "Two" },
				{ id = "three", label = "Three" },
				{ id = "four", label = "Four" },
			},
		})
		expect(pointer.presentation()).toBe("menu")
		pointer.dispose()
	end)

	it("Menu: the same rung, through the same recipe, unwired", function()
		local phone = surface(390, 844, TOUCH, "Touch")
		local menu = Facet.Controls.Menu(phone.core, {
			id = "M",
			trigger = UI.Button({ id = "T", label = "More" }),
			items = {
				{ id = "a", label = "Rename", onSelect = function() end },
				{ id = "b", label = "Duplicate", onSelect = function() end },
			},
		})
		expect(menu.presentation()).toBe("sheet")
		expect(menu.dump().factsFrom).toBe("core")
		menu.dispose()
	end)

	--[[ MEASURED, NOT DUMPED. The mark gap is a theme METRIC NAME inside the
		control, so the honest instrument is the solved geometry: mount the same
		five-mark run on two surfaces and read the space BETWEEN two marks. (The
		pitch is identical on both — the marks divide the offer — so a pitch
		comparison would have passed with the fix removed. The gap is the fact.) ]]
	it("LevelPicker: the touch run is wider than the pointer run, with no `env` key", function()
		local function markGap(s: any): number
			local picker = Facet.Controls.LevelPicker(s.core, { id = "L", value = s.core:signal(3), count = 5 })
			s.pres.present(UI.Screen({ id = "S", children = { picker.blueprint } }))
			s.pres.refresh()
			local first = s.adapter.node("/S/L/Levels/Level1")
			local second = s.adapter.node("/S/L/Levels/Level2")
			expect(`first mark solved: {first ~= nil}`).toBe("first mark solved: true")
			expect(`second mark solved: {second ~= nil}`).toBe("second mark solved: true")
			return second.rect.x - (first.rect.x + first.rect.w)
		end
		local touchGap = markGap(surface(390, 844, TOUCH, "Touch"))
		local pointerGap = markGap(surface(390, 844))
		expect(touchGap > pointerGap).toBe(true)
	end)

	it("Table: a row on a touch surface clears the target floor with no `env` key (ADAPT-11)", function()
		--[[ THE AUDIT'S MEASUREMENT (matrix ADAPT-11, high): "Table row height
			defaults to 36px on every combo, including compact touch portrait, because
			`table.luau` returns `rowBoxFor(nil, ...)` when `spec.env` is absent, which
			makes `classes` nil and the paradigm `pointer`. The engine hit rect is still
			expanded to 44, so the tap survives — but adjacent 44px expanders then
			OVERLAP on a 38px pitch, the same class of defect measured in the menu
			plate." Wired, it was already correct: 44 on touch, 36 on pointer. The
			ladder was right and nobody was climbing it. ]]
		local function rowHeight(s: any): number
			local tbl = Facet.Controls.Table(s.core, {
				id = "T",
				rows = s.core:signal({ { id = "a", name = "Aria" }, { id = "b", name = "Bo" } }),
				key = function(item: any)
					return item.id
				end,
				columns = {
					{
						id = "name",
						title = "Name",
						width = { type = "fill", weight = 1 },
						value = function(item: any)
							return item.name
						end,
					},
				},
				selection = "single",
			})
			s.pres.present(UI.Screen({ id = "S", children = { tbl.blueprint } }))
			s.pres.refresh()
			local row = s.adapter.node("/S/T/Main/Body/Rows/[a@0]/Row")
			expect(`row solved: {row ~= nil}`).toBe("row solved: true")
			return row.rect.h
		end
		local touch = rowHeight(surface(390, 844, TOUCH, "Touch"))
		local pointer = rowHeight(surface(390, 844))
		-- the theme's own touch floor is `targetSizes.minimum`, which is 44 and is
		-- the number a fingertip is owed
		expect(touch >= 44).toBe(true)
		expect(touch > pointer).toBe(true)
	end)

	it("Table: an authored `env` still wins over the surface's, and a pinned height still wins over both", function()
		-- the two escapes, because a channel that cannot be overridden is a channel
		-- an author cannot reason about
		local phone = surface(390, 844, TOUCH, "Touch")
		local pinned = Facet.Controls.Table(phone.core, {
			id = "P",
			rows = phone.core:signal({ { id = "a", name = "Aria" } }),
			key = function(item: any)
				return item.id
			end,
			columns = {
				{
					id = "name",
					width = { type = "fill", weight = 1 },
					value = function(item: any)
						return item.name
					end,
				},
			},
			rowHeight = 52,
			selection = "single",
		})
		phone.pres.present(UI.Screen({ id = "S", children = { pinned.blueprint } }))
		phone.pres.refresh()
		expect(phone.adapter.node("/S/P/Main/Body/Rows/[a@0]/Row").rect.h).toBe(52)
	end)

	it("TextInput: the field lifts itself off the keyboard with no `env` key", function()
		local phone = surface(390, 844, TOUCH, "Touch")
		local field = Facet.Controls.TextInput(phone.core, {
			id = "Name",
			value = phone.core:signal("hello"),
			actionSystem = phone.system,
		})
		phone.pres.present(UI.Screen({ id = "S", children = { field.blueprint } }), {
			sinkNavigation = true,
			onActivate = function(path, meta)
				field.api.handleActivate(path, meta)
			end,
			onGeometry = function(rectOf)
				field.api.syncGeometry(rectOf)
			end,
			keepVisibleOffset = field.api.keepVisibleOffset,
		})
		phone.pres.refresh()
		expect(field.dump().occlusionOffset).toBe(0)
		phone.adapter.tap("/S/Name/Field")
		phone.pres.refresh()
		expect(field.dump().editing).toBe(true)
		-- the on-screen keyboard arrives as an environment fact, over the field
		phone.env:set("keyboardOcclusionRect", { x = 0, y = 40, w = 390, h = 804 })
		phone.pres.refresh()
		expect(field.dump().occlusionOffset > 0).toBe(true)
		field.dispose()
	end)

	it("TabView: an automatic placement no longer needs the author to hand it anything", function()
		local phone = surface(390, 844, TOUCH, "Touch")
		local tabs = Facet.Controls.TabView(phone.core, {
			id = "TV",
			selection = phone.core:signal("a"),
			tabs = {
				{
					id = "a",
					label = "Alpha",
					content = function()
						return UI.Text({ id = "A", text = "a" })
					end,
				},
				{
					id = "b",
					label = "Beta",
					content = function()
						return UI.Text({ id = "B", text = "b" })
					end,
				},
			},
		})
		expect(tabs.dump().placement).toBe("bottomBar")
		expect(tabs.dump().placementSource).toBe("policy")
		tabs.dispose()
	end)
end)

describe("ADAPT-1: a control that cannot get its facts refuses, naming the host", function()
	local function refusal(build: (core: any) -> ()): string
		local core = Facet.newCore()
		local ok, err = pcall(function()
			build(core)
		end)
		expect(ok).toBe(false)
		return tostring(err)
	end

	it("Picker, PopupButton, Menu and TextInput each name the fix, not the symptom", function()
		local messages = {
			refusal(function(core)
				Facet.Controls.Picker(core, { id = "P", options = LONG_OPTIONS, selected = core:signal("a") })
			end),
			refusal(function(core)
				Facet.Controls.PopupButton(core, {
					id = "C",
					value = core:signal("one"),
					options = { { id = "one", label = "One" }, { id = "two", label = "Two" } },
				})
			end),
			refusal(function(core)
				Facet.Controls.Menu(core, {
					id = "M",
					trigger = UI.Button({ id = "T", label = "More" }),
					items = { { id = "a", label = "Rename", onSelect = function() end } },
				})
			end),
			refusal(function(core)
				Facet.Controls.TextInput(core, { id = "F", value = core:signal("") })
			end),
		}
		for _, message in messages do
			-- the refusal names the HOST (the thing that would have supplied the
			-- fact) and the explicit key (the thing the caller can do right now)
			expect(string.find(message, "Facet.client.host.new", 1, true) ~= nil).toBe(true)
			expect(string.find(message, "env", 1, true) ~= nil).toBe(true)
		end
	end)

	it("...and a DECLARED presentation consults no ladder, so it never refuses", function()
		local core = Facet.newCore()
		local declared = Facet.Controls.Picker(core, {
			id = "P",
			options = LONG_OPTIONS,
			selected = core:signal("a"),
			presentation = "segmented",
		})
		expect(declared.dump().presentation).toBe("segmented")
		expect(declared.dump().sizeClassFrom).toBe("none")
		declared.dispose()
	end)
end)

describe("ADAPT-1: the client host is what makes this free on a real surface", function()
	it("a hosted screen's controls adapt with zero authoring", function()
		local adapter = fake_target.new()
		local frames: { (dt: number) -> () } = {}
		local h = host.new({
			newAdapter = function()
				return adapter
			end,
			newInputSystem = function(core: any)
				return actionsLib.newSystem(core)
			end,
			bindEnv = function(env: any)
				-- the engine's own facts, as the real binder would deliver them
				env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
				env:set("capabilities", TOUCH)
				env:set("preferredInput", "Touch")
				return function() end
			end,
			connectFrame = function(fn)
				table.insert(frames, fn)
				return function() end
			end,
		})

		-- the author writes this and nothing else
		local picker = Facet.Controls.Picker(h.core, {
			id = "P",
			options = LONG_OPTIONS,
			selected = h.core:signal("a"),
		})
		local popup = Facet.Controls.PopupButton(h.core, {
			id = "C",
			value = h.core:signal("one"),
			options = {
				{ id = "one", label = "One" },
				{ id = "two", label = "Two" },
				{ id = "three", label = "Three" },
				{ id = "four", label = "Four" },
			},
		})
		h.presenter.present(UI.Screen({ id = "S", children = { picker.blueprint, popup.blueprint } }))
		for _, fn in frames do
			fn(1 / 60)
		end
		expect(picker.dump().presentation).toBe("inline")
		expect(picker.dump().sizeClassFrom).toBe("core")
		expect(popup.presentation()).toBe("sheet")
		picker.dispose()
		popup.dispose()
		h.dispose()
	end)
end)
