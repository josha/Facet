--!strict
-- Milestone B — display and selection controls (docs/plans/swiftui-parity-next.md
-- investment 7; acceptance rows B-DSP1 and B-DSP2).
--
-- These four share the rules the earlier rows established: paint is style-owned
-- (no bespoke fills), interactive rows meet the enforced 44px floor, every input
-- class reaches the same mutation site through a real path, and presentation
-- adapts from SPACE, never from a device name.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local serde = require("@lune/serde")

local customFactory = require("../src/core/custom")
local LuauUI = require("../src") :: any
local UI = require("../src/blueprint")
local environment = require("../src/env/environment")
local presenterLib = require("../src/present/presenter")
local actionsLib = require("../src/input/actions")
local picker = require("../src/controls/picker")
local fake_target = require("../tests/lib/fake_target")

local function harness()
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local adapter = fake_target.new()
	local system = actionsLib.newSystem(core)
	local pres = presenterLib.new(core, env, adapter, system)
	return core, env, adapter, system, pres
end

describe("B-DSP1: ProgressView is determinate and style-owned", function()
	it("maps the value onto a percent fill", function()
		local core, _, adapter, _, pres = harness()
		local p = LuauUI.newProgressView(LuauUI, core, { id = "Load", value = 0.25, showValue = true })
		pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		expect(p.dump().fraction).toBe(0.25)
		local bar = adapter.node("/S/Load/Bar").rect
		local fill = adapter.node("/S/Load/Bar/Fill").rect
		expect(fill.w).toBe(math.floor(bar.w * 0.25 + 0.5))
	end)

	it("a reactive value re-renders the fill with no rebuild", function()
		local core, _, adapter, _, pres = harness()
		local v = core:signal(0)
		local p = LuauUI.newProgressView(LuauUI, core, { id = "Load", value = v })
		pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		expect(adapter.node("/S/Load/Bar/Fill").rect.w).toBe(0)
		v:set(1)
		pres.refresh()
		local bar = adapter.node("/S/Load/Bar").rect
		expect(adapter.node("/S/Load/Bar/Fill").rect.w).toBe(bar.w)
	end)

	it("clamps out-of-range values instead of overflowing the bar", function()
		local core, _, adapter, _, pres = harness()
		local p = LuauUI.newProgressView(LuauUI, core, { id = "Load", value = 5 })
		pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		expect(p.dump().fraction).toBe(1)
		expect(adapter.node("/S/Load/Bar/Fill").rect.w).toBe(adapter.node("/S/Load/Bar").rect.w)
	end)

	it("paint is style-owned through the BAR FAMILY, never a borrowed surface", function()
		-- ADR-0020 R3: the track used to declare `surface = "control"` and the fill
		-- `surface = "accent"`, which subscribed both to treatments meant for
		-- buttons and panels — an ornate package stretched a BUTTON plate over the
		-- track, and a panel gradient's alpha made the fill see-through. They now
		-- declare their own slots on the internal meta channel, exactly as the
		-- Slider's rail and thumb do, so nothing generic can mistake them.
		local sheet_model = require("../src/tokens/sheet_model")
		local core, _, adapter, _, pres = harness()
		local p = LuauUI.newProgressView(LuauUI, core, { id = "Load", value = 0.5 })
		pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		for path, slot in { ["/S/Load/Bar"] = "barTrack", ["/S/Load/Bar/Fill"] = "barFill" } do
			local node = adapter.node(path)
			expect(node.props.surface).toBeNil()
			expect(node.decorationHint.slot).toBe(slot)
			-- and the hint yields exactly the tag the `Slot — <slot>` rules select
			-- on, and nothing else: no surface treatment leaks in
			local desired =
				sheet_model.classifyTags({ surface = node.props.surface, slotHint = node.decorationHint.slot })
			expect(desired["luau-slot-" .. slot]).toBe(true)
			local count = 0
			for _ in desired do
				count += 1
			end
			expect(count).toBe(1)
		end
	end)

	it("carries semantic value-in-range text and a deterministic dump", function()
		local core = customFactory.new()
		local p = LuauUI.newProgressView(LuauUI, core, { id = "L", value = 0.5, min = 0, max = 1 })
		expect(p.dump().semanticText).toBe("0.5 of 0 to 1")
		expect(serde.encode("json", p.dump(), true)).toBe(serde.encode("json", p.dump(), true))
	end)

	it("is registry-neutral after dispose", function()
		local core = customFactory.new()
		local baseline = core:counters()
		local p = LuauUI.newProgressView(LuauUI, core, { id = "L", value = 0.5 })
		p.dispose()
		expect(core:counters().scopes).toBe(baseline.scopes)
		expect(core:counters().observers).toBe(baseline.observers)
	end)
end)

describe("B-DSP1: Label keeps a semantic text fallback", function()
	it("renders icon and title together", function()
		local core, _, adapter, _, pres = harness()
		local l = LuauUI.newLabel(LuauUI, core, { id = "Save", title = "Save", icon = "rbxassetid://1" })
		pres.present(UI.Screen({ id = "S", children = { l.blueprint } }))
		pres.refresh()
		expect(adapter.node("/S/Save/Icon") ~= nil).toBe(true)
		expect(adapter.node("/S/Save/Title") ~= nil).toBe(true)
	end)

	it("an icon-only presentation still reports the title as its semantic text", function()
		local core = customFactory.new()
		local l = LuauUI.newLabel(LuauUI, core, {
			id = "Save",
			title = "Save",
			icon = "rbxassetid://1",
			presentation = "iconOnly",
		})
		expect(l.semanticText:get()).toBe("Save")
		expect(l.dump().effectivePresentation).toBe("iconOnly")
	end)

	-- CTRL-06 (api-architecture-consistency F-23). `semanticText` is a Readable
	-- on ProgressView, Stepper, Slider and Rating; it was a bare string here, so
	-- an accessibility/readout layer written once for the family errored on the
	-- one control whose whole reason to exist is the semantic fallback.
	it("semanticText is a Readable, like every sibling that publishes one", function()
		local core = customFactory.new()
		local l = LuauUI.newLabel(LuauUI, core, { id = "Save", title = "Save changes" })
		expect(UI.isReadable(l.semanticText)).toBe(true)
		expect(l.semanticText:get()).toBe("Save changes")
		-- dump() still carries the STRING value (a dump is data, not a graph node)
		expect(l.dump().semanticText).toBe("Save changes")
	end)

	-- CTRL-08d: the dump/dispose pair Picker and DisclosureGroup already pin
	it("dump is deterministic and dispose is registry-neutral", function()
		local core = customFactory.new()
		local baseline = core:counters()
		local l = LuauUI.newLabel(LuauUI, core, { id = "Save", title = "Save", icon = "rbxassetid://1" })
		expect(serde.encode("json", l.dump(), true)).toBe(serde.encode("json", l.dump(), true))
		l.dispose()
		expect(core:counters().scopes).toBe(baseline.scopes)
		expect(core:counters().observers).toBe(baseline.observers)
		expect(core:counters().memos).toBe(baseline.memos)
	end)

	it("iconOnly DEGRADES to the title when there is no icon (an empty square is worse than a word)", function()
		local core, _, adapter, _, pres = harness()
		local l = LuauUI.newLabel(LuauUI, core, { id = "Save", title = "Save", presentation = "iconOnly" })
		pres.present(UI.Screen({ id = "S", children = { l.blueprint } }))
		pres.refresh()
		expect(l.dump().degradedToTitle).toBe(true)
		expect(adapter.node("/S/Save/Title") ~= nil).toBe(true)
		expect(adapter.node("/S/Save/Icon")).toBe(nil)
	end)

	it("titleOnly renders no empty icon slot", function()
		local core, _, adapter, _, pres = harness()
		local l = LuauUI.newLabel(LuauUI, core, {
			id = "Save",
			title = "Save",
			icon = "rbxassetid://1",
			presentation = "titleOnly",
		})
		pres.present(UI.Screen({ id = "S", children = { l.blueprint } }))
		pres.refresh()
		expect(adapter.node("/S/Save/Icon")).toBe(nil)
	end)

	it("requires a title, because an icon-only label without one has no accessible name", function()
		local core = customFactory.new()
		expect(pcall(function()
			return LuauUI.newLabel(LuauUI, core, { id = "X", icon = "rbxassetid://1" })
		end)).toBe(false)
		expect(pcall(function()
			return LuauUI.newLabel(LuauUI, core, { id = "X", title = "" })
		end)).toBe(false)
	end)

	it("rejects an unknown presentation", function()
		local core = customFactory.new()
		local ok, err = pcall(function()
			return LuauUI.newLabel(LuauUI, core, { id = "X", title = "T", presentation = "sideways" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "iconOnly | titleAndIcon | titleOnly", 1, true) ~= nil).toBe(true)
	end)
end)

describe("B-DSP2: Picker presentation adapts from space, not device names", function()
	it("the adaptive rule stacks when options cannot sit side by side", function()
		expect(picker.resolvePresentation(2, "wide", 6)).toBe("segmented")
		expect(picker.resolvePresentation(5, "wide", 6)).toBe("inline")
		expect(picker.resolvePresentation(4, "compact", 6)).toBe("inline")
		expect(picker.resolvePresentation(2, "compact", 20)).toBe("inline")
		expect(picker.resolvePresentation(2, "compact", 6)).toBe("segmented")
	end)

	local function mountPicker(overrides: any?)
		local core, env, adapter, system, pres = harness()
		local selected = core:signal("b")
		local spec: any = {
			id = "Mode",
			label = "Mode",
			options = { { value = "a", label = "A" }, { value = "b", label = "B" }, { value = "c", label = "C" } },
			selected = selected,
		}
		for k, v in (overrides or {}) :: any do
			spec[k] = v
		end
		local control = LuauUI.newPicker(LuauUI, core, spec)
		pres.present(UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		return core, env, adapter, system, pres, selected, control
	end

	it("segmented lays options along x; inline stacks them along y", function()
		local _, _, segAdapter = mountPicker({ presentation = "segmented" })
		expect(segAdapter.node("/S/Mode/Options/Opt1").rect.y).toBe(segAdapter.node("/S/Mode/Options/Opt2").rect.y)
		local _, _, inlineAdapter = mountPicker({ presentation = "inline" })
		expect(inlineAdapter.node("/S/Mode/Options/Opt1").rect.x).toBe(
			inlineAdapter.node("/S/Mode/Options/Opt2").rect.x
		)
	end)

	it("a live size-class change flips the presentation WITHOUT remounting the options", function()
		local core, _, adapter, _, pres = harness()
		local selected = core:signal("a")
		local sizeClass = core:signal("wide")
		local control = LuauUI.newPicker(LuauUI, core, {
			id = "Mode",
			-- long labels: in a COMPACT space these cannot sit side by side legibly,
			-- which is the space-based condition the rule keys on
			options = {
				{ value = "a", label = "Alphabetical order" },
				{ value = "b", label = "Beta distribution" },
				{ value = "c", label = "Gamma correction" },
			},
			selected = selected,
			sizeClass = sizeClass,
		})
		pres.present(UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		expect(control.dump().presentation).toBe("segmented")
		local liveBefore = adapter.liveCount()
		sizeClass:set("compact")
		pres.refresh()
		expect(control.dump().presentation).toBe("inline")
		-- the option buttons kept their identity: a presentation flip is a re-solve
		expect(adapter.liveCount()).toBe(liveBefore)
	end)

	it("pointer: tapping an option selects it and reports through onChange", function()
		local changed: any = nil
		local _, _, adapter, _, pres, selected = mountPicker({
			onChange = function(v: any)
				changed = v
			end,
		})
		adapter.tap("/S/Mode/Options/Opt3")
		pres.refresh()
		expect(selected:get()).toBe("c")
		expect(changed).toBe("c")
	end)

	it("keyboard and gamepad select through the same path", function()
		local _, _, _, system, pres, selected = mountPicker()
		-- focus starts on the first focusable option
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		pres.refresh()
		expect(selected:get()).toBe("a")
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		pres.refresh()
		system.deviceKey("ButtonA", true)
		system.deviceKey("ButtonA", false)
		pres.refresh()
		expect(selected:get()).toBe("b")
	end)

	it("touch: a finger tap selects identically, and every row meets the floor", function()
		local _, _, adapter, _, pres, selected = mountPicker()
		adapter.tap("/S/Mode/Options/Opt1", { pointer = "touch" })
		pres.refresh()
		expect(selected:get()).toBe("a")
		for i = 1, 3 do
			expect(adapter.node(`/S/Mode/Options/Opt{i}`).rect.h >= 44).toBe(true)
		end
	end)

	it("selection rides the `selected` style binding, never a bespoke fill", function()
		local _, _, adapter, _, pres = mountPicker()
		expect(adapter.node("/S/Mode/Options/Opt2").props.selected).toBe(true)
		expect(adapter.node("/S/Mode/Options/Opt1").props.selected).toBe(false)
	end)

	it("a disabled Picker refuses selection", function()
		local _, _, adapter, _, pres, selected = mountPicker({ enabled = false })
		adapter.tap("/S/Mode/Options/Opt3")
		pres.refresh()
		expect(selected:get()).toBe("b")
	end)

	it("rejects an empty option set, a non-settable selection, and an unknown presentation", function()
		local core = customFactory.new()
		expect(pcall(function()
			return LuauUI.newPicker(LuauUI, core, { id = "X", options = {}, selected = core:signal(1) })
		end)).toBe(false)
		expect(pcall(function()
			return LuauUI.newPicker(LuauUI, core, {
				id = "X",
				options = { { value = 1, label = "one" } },
				selected = core:memo(function()
					return 1
				end),
			})
		end)).toBe(false)
		expect(pcall(function()
			return LuauUI.newPicker(LuauUI, core, {
				id = "X",
				options = { { value = 1, label = "one" } },
				selected = core:signal(1),
				presentation = "carousel",
			})
		end)).toBe(false)
	end)

	it("dump is deterministic and dispose is registry-neutral", function()
		local core = customFactory.new()
		local baseline = core:counters()
		local control = LuauUI.newPicker(LuauUI, core, {
			id = "X",
			options = { { value = 1, label = "one" }, { value = 2, label = "two" } },
			selected = core:signal(1),
		})
		expect(serde.encode("json", control.dump(), true)).toBe(serde.encode("json", control.dump(), true))
		control.dispose()
		expect(core:counters().scopes).toBe(baseline.scopes)
		expect(core:counters().observers).toBe(baseline.observers)
	end)
end)

describe("B-DSP2: DisclosureGroup updates focus correctly", function()
	local function mountDisclosure(startExpanded: boolean)
		local core, env, adapter, system, pres = harness()
		local expanded = core:signal(startExpanded)
		local control = LuauUI.newDisclosureGroup(LuauUI, core, {
			id = "Advanced",
			label = "Advanced",
			expanded = expanded,
			content = function()
				return UI.VStack({
					id = "Body",
					children = {
						UI.Button({ id = "Inner", label = "inner", height = { type = "minMax", min = 44 } }),
					},
				})
			end,
		})
		pres.present(UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		return core, adapter, system, pres, expanded, control
	end

	it("expanding mounts the content; collapsing unmounts it", function()
		local _, adapter, _, pres, expanded = mountDisclosure(false)
		expect(adapter.node("/S/Advanced/Content/then/Body/Inner")).toBe(nil)
		adapter.tap("/S/Advanced/Header")
		pres.refresh()
		expect(expanded:get()).toBe(true)
		expect(adapter.node("/S/Advanced/Content/then/Body/Inner") ~= nil).toBe(true)
		adapter.tap("/S/Advanced/Header")
		pres.refresh()
		expect(expanded:get()).toBe(false)
		expect(adapter.node("/S/Advanced/Content/then/Body/Inner")).toBe(nil)
	end)

	it("collapsing with focus INSIDE the content moves focus back to the header first", function()
		local _, adapter, system, pres, _, control = mountDisclosure(true)
		control.bindFocus(pres.focus)
		-- walk focus into the content
		local guard = 0
		while guard < 6 do
			system.deviceKey("DPadDown", true)
			system.deviceKey("DPadDown", false)
			pres.refresh()
			local f = pres.focus.focused:get()
			if f ~= nil and string.find(f, "Inner", 1, true) then
				break
			end
			guard += 1
		end
		expect(string.find(tostring(pres.focus.focused:get()), "Inner", 1, true) ~= nil).toBe(true)
		adapter.tap("/S/Advanced/Header")
		pres.refresh()
		-- focus must NOT be left pointing at the unmounted content
		local after = tostring(pres.focus.focused:get())
		expect(string.find(after, "Inner", 1, true)).toBe(nil)
		expect(string.find(after, "Header", 1, true) ~= nil).toBe(true)
	end)

	it("expanding leaves focus on the header (the player asked to SEE the content)", function()
		local _, adapter, system, pres, _, control = mountDisclosure(false)
		control.bindFocus(pres.focus)
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		pres.refresh()
		adapter.tap("/S/Advanced/Header")
		pres.refresh()
		expect(string.find(tostring(pres.focus.focused:get()), "Header", 1, true) ~= nil).toBe(true)
	end)

	it("keyboard and gamepad toggle it through the same path", function()
		local _, _, system, pres, expanded = mountDisclosure(false)
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		pres.refresh()
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		pres.refresh()
		expect(expanded:get()).toBe(true)
		system.deviceKey("ButtonA", true)
		system.deviceKey("ButtonA", false)
		pres.refresh()
		expect(expanded:get()).toBe(false)
	end)

	it("touch: a finger tap toggles it, and the header meets the floor", function()
		local _, adapter, _, pres, expanded = mountDisclosure(false)
		adapter.tap("/S/Advanced/Header", { pointer = "touch" })
		pres.refresh()
		expect(expanded:get()).toBe(true)
		expect(adapter.node("/S/Advanced/Header").rect.h >= 44).toBe(true)
	end)

	it("a disabled group does not toggle", function()
		local core, _, adapter, _, pres = harness()
		local expanded = core:signal(false)
		local control = LuauUI.newDisclosureGroup(LuauUI, core, {
			id = "Advanced",
			label = "Advanced",
			expanded = expanded,
			enabled = false,
			content = function()
				return UI.Box({ id = "Body" })
			end,
		})
		pres.present(UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		adapter.tap("/S/Advanced/Header")
		pres.refresh()
		expect(expanded:get()).toBe(false)
	end)

	it("requires a label, a settable expanded signal, and a content function", function()
		local core = customFactory.new()
		local content = function()
			return UI.Box({ id = "B" })
		end
		expect(pcall(function()
			return LuauUI.newDisclosureGroup(
				LuauUI,
				core,
				{ id = "X", expanded = core:signal(false), content = content }
			)
		end)).toBe(false)
		expect(pcall(function()
			return LuauUI.newDisclosureGroup(LuauUI, core, {
				id = "X",
				label = "L",
				expanded = core:memo(function()
					return false
				end),
				content = content,
			})
		end)).toBe(false)
		expect(pcall(function()
			return LuauUI.newDisclosureGroup(LuauUI, core, { id = "X", label = "L", expanded = core:signal(false) })
		end)).toBe(false)
	end)

	it("dump is deterministic and dispose is registry-neutral", function()
		local core = customFactory.new()
		local baseline = core:counters()
		local control = LuauUI.newDisclosureGroup(LuauUI, core, {
			id = "X",
			label = "L",
			expanded = core:signal(false),
			content = function()
				return UI.Box({ id = "B" })
			end,
		})
		expect(serde.encode("json", control.dump(), true)).toBe(serde.encode("json", control.dump(), true))
		control.dispose()
		expect(core:counters().scopes).toBe(baseline.scopes)
		expect(core:counters().observers).toBe(baseline.observers)
	end)
end)

-- ===== B-DSP3: PopupButton rows meet the enforced target floor ==============
-- The plan asks for PopupButton rows to be raised to the enforced floor. B-BTN3
-- made that floor a renderer-enforced property of every control that DECLARES one
-- (`contract.minHitSize`), so this asserts the outcome on the shipped control
-- rather than re-implementing the rule inside it.

describe("B-DSP3: PopupButton rows meet the enforced target floor", function()
	it("the trigger and every open row report a hit rect at or above the floor", function()
		local core, _, adapter, _, pres = harness()
		local selected = core:signal("one")
		local control = LuauUI.newPopupButton(LuauUI, core, {
			id = "Choice",
			value = selected,
			options = {
				{ id = "one", label = "One" },
				{ id = "two", label = "Two" },
			},
		})
		pres.present(UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()

		local function effectiveHeight(path: string): number
			local node = adapter.node(path)
			if node == nil then
				return 0
			end
			local hit = adapter.hitRectOf(path)
			return math.max(node.rect.h, if hit ~= nil then (hit :: any).h else 0)
		end

		-- open it through a real tap, then measure every rendered Button
		adapter.tap("/S/Choice/Trigger")
		pres.refresh()
		local measured = 0
		for _, path in adapter.paths() do
			local node = adapter.node(path)
			if node ~= nil and node.class == "Button" then
				measured += 1
				if effectiveHeight(path) < 44 then
					error(`popup control node {path} has an effective target of {effectiveHeight(path)}px`)
				end
			end
		end
		expect(measured > 1).toBe(true) -- the trigger plus at least one open row
	end)
end)

-- ===== B-DSP3 second half: PopupButton's adaptive presentation ==============
-- The idiom follows the option count, the available SPACE class, and whether touch
-- is a LIVE interaction class — never a device name. The transient-surface
-- machinery (outsideDismiss, transientScope, handleCancel) keys on `open`, not on
-- the presentation, so it is unchanged by the choice.

describe("B-DSP3: PopupButton adapts its presentation", function()
	local popupButton = require("../src/controls/popup_button")

	it("the pure rule prefers a sheet on touch, inline when short, menu otherwise", function()
		-- touch is the strongest signal: a finger wants the bigger surface
		expect(popupButton.resolvePresentation(3, "wide", true)).toBe("sheet")
		-- a compact space cannot hold a long menu
		expect(popupButton.resolvePresentation(8, "compact", false)).toBe("sheet")
		-- few options with room: show them in place
		expect(popupButton.resolvePresentation(3, "wide", false)).toBe("inline")
		-- more options with room: the pointer menu idiom
		expect(popupButton.resolvePresentation(6, "wide", false)).toBe("menu")
		-- compact but short: still a menu, not a sheet
		expect(popupButton.resolvePresentation(3, "compact", false)).toBe("menu")
	end)

	local function mountPopup(overrides: any?)
		local core, _, adapter, system, pres = harness()
		local value = core:signal("one")
		local spec: any = {
			id = "Choice",
			value = value,
			options = {
				{ id = "one", label = "One" },
				{ id = "two", label = "Two" },
				{ id = "three", label = "Three" },
				{ id = "four", label = "Four" },
				{ id = "five", label = "Five" },
				{ id = "six", label = "Six" },
			},
		}
		for k, v in (overrides or {}) :: any do
			spec[k] = v
		end
		local control = LuauUI.newPopupButton(LuauUI, core, spec)
		pres.present(UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		return core, adapter, system, pres, value, control
	end

	it("a sheet anchors to the bottom edge with visually larger rows", function()
		local _, adapter, _, pres, _, control = mountPopup({ presentation = "sheet" })
		adapter.tap("/S/Choice/Trigger")
		pres.refresh()
		expect(control.presentation()).toBe("sheet")
		local row = adapter.node("/S/Choice/PopupWhen/then/Popup/Opt-one")
		expect(row.rect.h).toBe(56)
		-- bottom-anchored: the panel's bottom edge meets the container's
		local panel = adapter.node("/S/Choice/PopupWhen/then/Popup").rect
		local host = adapter.node("/S/Choice").rect
		expect(panel.y + panel.h).toBe(host.y + host.h)
	end)

	it("a menu sits just below the trigger with compact rows", function()
		local _, adapter, _, pres, _, control = mountPopup({ presentation = "menu" })
		adapter.tap("/S/Choice/Trigger")
		pres.refresh()
		expect(control.presentation()).toBe("menu")
		local panel = adapter.node("/S/Choice/PopupWhen/then/Popup").rect
		local trigger = adapter.node("/S/Choice/Trigger").rect
		expect(panel.y).toBe(trigger.y + trigger.h)
		expect(adapter.node("/S/Choice/PopupWhen/then/Popup/Opt-one").rect.h).toBe(36)
	end)

	it("an inline list takes the CONTROL surface, not a floating-panel one", function()
		local _, adapter, _, pres = mountPopup({
			presentation = "inline",
			options = { { id = "a", label = "A" }, { id = "b", label = "B" } },
		})
		adapter.tap("/S/Choice/Trigger")
		pres.refresh()
		expect(adapter.node("/S/Choice/PopupWhen/then/Popup").props.surface).toBe("control")
		expect(adapter.node("/S/Choice/PopupWhen/then/Popup/Opt-a").rect.h).toBe(44)
	end)

	it("automatic resolves from LIVE facts, and re-resolves when they change", function()
		local core, adapter, _, pres, _, control = mountPopup({ sizeClass = nil })
		-- six options, no facts supplied: the pointer menu idiom
		expect(control.presentation()).toBe("menu")
		-- six options in a compact space is still a menu by the rule (the sheet
		-- threshold is >6); seven crosses it
		local _, _, _, _, _, six = mountPopup({ sizeClass = "compact" })
		expect(six.presentation()).toBe("menu")
		local core2, adapter2, _, pres2, _, control2 = mountPopup({
			sizeClass = "compact",
			options = {
				{ id = "one", label = "One" },
				{ id = "two", label = "Two" },
				{ id = "three", label = "Three" },
				{ id = "four", label = "Four" },
				{ id = "five", label = "Five" },
				{ id = "six", label = "Six" },
				{ id = "seven", label = "Seven" },
			},
		})
		expect(control2.presentation()).toBe("sheet")
		adapter2.tap("/S/Choice/Trigger")
		pres2.refresh()
		expect(adapter2.node("/S/Choice/PopupWhen/then/Popup/Opt-one").rect.h).toBe(56)
	end)

	it("a LIVE touch class flips it to a sheet with no rebuild of the trigger", function()
		local core, adapter, _, pres, _, control = mountPopup({
			interactionClasses = nil,
		})
		expect(control.presentation()).toBe("menu")
		-- the same control, told touch is live through a Readable
		local core2 = customFactory.new()
		local env2 = environment.new(core2)
		env2:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env2:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter3 = fake_target.new()
		local pres3 = presenterLib.new(core2, env2, adapter3, actionsLib.newSystem(core2))
		local classes = core2:signal({ touch = false, pointer = true })
		local c3 = LuauUI.newPopupButton(LuauUI, core2, {
			id = "Choice",
			value = core2:signal("one"),
			options = {
				{ id = "one", label = "One" },
				{ id = "two", label = "Two" },
				{ id = "three", label = "T" },
				{ id = "four", label = "F" },
				{ id = "five", label = "V" },
				{ id = "six", label = "S" },
			},
			interactionClasses = classes,
		})
		pres3.present(UI.Screen({ id = "S", children = { c3.blueprint } }))
		pres3.refresh()
		expect(c3.presentation()).toBe("menu")
		local triggerBefore = adapter3.node("/S/Choice/Trigger")
		classes:set({ touch = true, pointer = true })
		pres3.refresh()
		expect(c3.presentation()).toBe("sheet")
		-- the TRIGGER was not rebuilt: only the panel's presentation is adaptive
		expect(adapter3.node("/S/Choice/Trigger")).toBe(triggerBefore)
	end)

	it("every presentation keeps selection, Cancel, and the tap-away machinery", function()
		for _, presentation in { "menu", "inline", "sheet" } do
			local _, adapter, _, pres, value = mountPopup({ presentation = presentation })
			adapter.tap("/S/Choice/Trigger")
			pres.refresh()
			-- Cancel exists in every idiom
			expect(adapter.node("/S/Choice/PopupWhen/then/Popup/Cancel") ~= nil).toBe(true)
			-- selecting still works and closes
			adapter.tap("/S/Choice/PopupWhen/then/Popup/Opt-two")
			pres.refresh()
			expect(value:get()).toBe("two")
			expect(adapter.node("/S/Choice/PopupWhen/then/Popup")).toBe(nil)
		end
	end)

	it("rejects an unknown presentation at build", function()
		local core = customFactory.new()
		expect(pcall(function()
			return LuauUI.newPopupButton(LuauUI, core, {
				id = "X",
				value = core:signal("a"),
				options = { { id = "a", label = "A" } },
				presentation = "carousel",
			})
		end)).toBe(false)
	end)
end)

describe("progress: exact vertical centring (director review 2026-07-24)", function()
	it("the track centres on the row's midline with no half-pixel bias", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local progress = LuauUI.newProgressView(LuauUI, core, {
			id = "Down",
			label = "Download",
			value = core:signal(0.35),
			showValue = true,
		})
		local root = require("../src/mount").mount(core, UI.Screen({ id = "S", children = { progress.blueprint } }))
		local adapter = fake_target.new()
		local controller =
			require("../src/render/renderer").attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local row = adapter.node("/S/Down").rect
		local bar = adapter.node("/S/Down/Bar").rect
		-- an even track in an odd row cannot be centred on an integer grid, so the
		-- row's height is kept even; this asserts the parity, not just the result
		expect(row.h % 2).toBe(0)
		expect(bar.h % 2).toBe(0)
		expect(bar.y + bar.h / 2).toBe(row.y + row.h / 2)
		progress.dispose()
		controller.dispose()
		root.dispose()
	end)
end)

describe("label: the title reads centred in its own box (director review 2026-07-24)", function()
	it("centres its text so the measurer's width over-reserve does not pile up on one side", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local label = LuauUI.newLabel(LuauUI, core, { id = "Cap", title = "Save changes" })
		local root = require("../src/mount").mount(core, UI.Screen({ id = "S", children = { label.blueprint } }))
		local adapter = fake_target.new()
		local controller =
			require("../src/render/renderer").attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect(adapter.node("/S/Cap/Title").props.textAlign).toBe("center")
		label.dispose()
		controller.dispose()
		root.dispose()
	end)
end)

-- =============================================================================
-- INDETERMINATE PROGRESS AND THE SPINNER (swiftui-parity-round2.md §3.1)
--
-- Two things are proved here that nothing else can prove:
--   1. the DETERMINATE path is untouched — same node tree, same geometry, same
--      dump values — because one live RascalRally caller depends on it
--      (LuauUISponsor/ResultsScreen.luau:1471);
--   2. BOTH reduced-motion policies. A loading indicator is the one piece of
--      motion in this framework that CARRIES information, so it is
--      `kind = "informational"`: under reduced motion it must still visibly
--      PROGRESS (quantized onto the authority's 250 ms tick), never freeze and
--      never vanish. A test that only proved "it does not animate" would be
--      asserting the bug.
-- =============================================================================
local motionClockLib = require("../src/motion/clock")

describe("ProgressView: indeterminate is selected by value = nil (§3.1)", function()
	local function clockWorld(policy: string?)
		local core, _, adapter, _, pres = harness()
		local t = { now = 0 }
		local clock = motionClockLib.new(core, {
			now = function()
				return t.now
			end,
			motionPolicy = core:signal(policy or "full"),
		})
		return core, adapter, pres, clock, t
	end

	it("the DETERMINATE tree and dump are exactly what they were before indeterminate existed", function()
		local core, _, adapter, _, pres = harness()
		local p = LuauUI.newProgressView(LuauUI, core, { id = "Load", value = 0.25, showValue = true })
		local handle = pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		expect(#handle.controller.diagnostics()).toBe(0)
		-- the fill is the track's DIRECT child: no sweep wrapper, no lead spacer
		expect(adapter.node("/S/Load/Bar/Fill") ~= nil).toBe(true)
		expect(adapter.node("/S/Load/Bar/Sweep")).toBeNil()
		expect(adapter.node("/S/Load/Bar/Sweep/Lead")).toBeNil()
		local bar = adapter.node("/S/Load/Bar").rect
		local fill = adapter.node("/S/Load/Bar/Fill").rect
		expect(fill.x).toBe(bar.x)
		expect(fill.w).toBe(math.floor(bar.w * 0.25 + 0.5))
		local d = p.dump()
		expect(d.schema).toBe("luauui-progress-dump/1")
		expect(d.value).toBe(0.25)
		expect(d.fraction).toBe(0.25)
		expect(d.formatted).toBe("0.25")
		expect(d.min).toBe(0)
		expect(d.max).toBe(1)
		expect(d.showValue).toBe(true)
		expect(d.semanticText).toBe("0.25 of 0 to 1")
		-- ...and the two additive keys that name the mode
		expect(d.indeterminate).toBe(false)
		expect(d.presentation).toBe("bar")
		p.dispose()
	end)

	it("value = nil builds the sweeping segment instead of a value-tracking fill", function()
		local core, adapter, pres, clock = clockWorld()
		local p = LuauUI.newProgressView(LuauUI, core, { id = "Load", motionClock = clock })
		local handle = pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		expect(#handle.controller.diagnostics()).toBe(0)
		expect(p.dump().indeterminate).toBe(true)
		expect(p.dump().animating).toBe(true)
		expect(p.dump().semanticText).toBe("Loading")
		local bar = adapter.node("/S/Load/Bar").rect
		local fill = adapter.node("/S/Load/Bar/Sweep/Fill").rect
		-- the segment is a FIXED share of the track and starts at its leading edge
		expect(fill.w).toBe(math.floor(bar.w * 0.3 + 0.5))
		expect(fill.x).toBe(bar.x)
		p.dispose()
		clock:dispose()
	end)

	it("the segment PEAKS AT MID-CYCLE and folds back, and never leaves the track", function()
		-- THE FOLD IS THE POINT, AND IT HAS TO BE MEASURED AT THE PEAK. An earlier
		-- version of this case only compared the LAST sample against the largest
		-- one, which a pure sawtooth also satisfies (its restart drops the segment
		-- back to the left edge). Mutating `triangle` to the identity left it green
		-- — so the peak's POSITION in the cycle is asserted instead, plus the
		-- symmetry of the quarter points, and both bite.
		local core, adapter, pres, clock, t = clockWorld()
		local p = LuauUI.newProgressView(LuauUI, core, { id = "Load", motionClock = clock })
		pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		local bar = adapter.node("/S/Load/Bar").rect
		local function sweep(): number
			return adapter.node("/S/Load/Bar/Sweep/Fill").rect.x - bar.x
		end
		local seen: { number } = {}
		for _ = 1, 20 do -- 20 x 50 ms = one full 1 s cycle
			t.now += 0.05
			clock:step()
			pres.refresh()
			table.insert(seen, sweep())
			-- the segment is INSIDE the track on every single frame
			local fill = adapter.node("/S/Load/Bar/Sweep/Fill").rect
			expect(fill.x >= bar.x).toBe(true)
			expect(fill.x + fill.w <= bar.x + bar.w + 1).toBe(true)
		end
		local widest, peakAt = -1, 0
		for index, x in seen do
			if x > widest then
				widest, peakAt = x, index
			end
		end
		-- it travelled most of the free space...
		expect(widest > math.floor(bar.w * 0.6)).toBe(true)
		-- ...at the MIDDLE of the cycle, not at its end
		expect(peakAt >= 8).toBe(true)
		expect(peakAt <= 13).toBe(true)
		-- ...and the outbound and return legs mirror each other
		expect(math.abs(seen[5] - seen[15]) <= 2).toBe(true)
		expect(seen[20] < widest).toBe(true)
		p.dispose()
		clock:dispose()
	end)

	it("the cycle REPEATS: the indicator is still travelling in its third second", function()
		-- A LOADER THAT RUNS ONCE IS A LOADER THAT LIES. Deleting the restart from
		-- the settle handler left every other case green, because none of them ran
		-- past the first cycle's terminus — so this one does, deliberately.
		local core, adapter, pres, clock, t = clockWorld()
		local p = LuauUI.newProgressView(LuauUI, core, { id = "Load", motionClock = clock })
		pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		local function sweep(): number
			return adapter.node("/S/Load/Bar/Sweep/Fill").rect.x
		end
		for _ = 1, 40 do -- two full cycles, terminus crossed twice
			t.now += 0.05
			clock:step()
		end
		pres.refresh()
		local resting = sweep()
		local seen: { [number]: boolean } = {}
		local distinct = 0
		for _ = 1, 10 do
			t.now += 0.05
			clock:step()
			pres.refresh()
			local x = sweep()
			if seen[x] == nil then
				seen[x] = true
				distinct += 1
			end
		end
		expect(distinct > 1).toBe(true) -- it MOVED in the third second
		expect(seen[resting] == nil or distinct > 2).toBe(true)
		p.dispose()
		clock:dispose()
	end)

	it("REDUCED MOTION keeps the indicator advancing — quantized, never frozen (§3.1)", function()
		local core, adapter, pres, clock, t = clockWorld("reduced")
		expect(clock:isReduced()).toBe(true)
		local p = LuauUI.newProgressView(LuauUI, core, { id = "Load", motionClock = clock })
		pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		-- the motion is INFORMATIONAL, which is the whole decision: a decorative
		-- value would have been placed at its terminus and stopped
		expect(p.phase:motionKind()).toBe("informational")
		local start = p.dump().phase
		-- a sub-quantum step writes NOTHING: that is the stepped policy, not a stall
		t.now += 0.05
		clock:step()
		expect(p.dump().phase).toBe(start)
		-- ...and the very next tick past 250 ms DOES advance it. This is the
		-- assertion the whole decision rests on: reduced motion must not delete the
		-- only thing on screen saying "work is still happening".
		t.now += 0.25
		clock:step()
		expect(p.dump().phase > start).toBe(true)
		-- over a full cycle it still traverses the track, in visible steps
		local positions: { [number]: boolean } = {}
		local count = 0
		for _ = 1, 20 do
			t.now += 0.05
			clock:step()
			pres.refresh()
			local x = adapter.node("/S/Load/Bar/Sweep/Fill").rect.x
			if positions[x] == nil then
				positions[x] = true
				count += 1
			end
		end
		-- roughly one distinct position per 250 ms tick over a 1 s cycle — several,
		-- and nothing like the sixty a full-motion second would produce
		expect(count >= 3).toBe(true)
		expect(count <= 8).toBe(true)
		p.dispose()
		clock:dispose()
	end)

	it("FULL motion writes far more often than reduced motion over the same wall clock", function()
		-- the differential the two policies are ABOUT, measured rather than asserted
		local function distinctPositions(policy: string): number
			local core, adapter, pres, clock, t = clockWorld(policy)
			local p = LuauUI.newProgressView(LuauUI, core, { id = "Load", motionClock = clock })
			pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
			pres.refresh()
			local seen: { [number]: boolean } = {}
			local n = 0
			for _ = 1, 20 do
				t.now += 0.02
				clock:step()
				pres.refresh()
				local x = adapter.node("/S/Load/Bar/Sweep/Fill").rect.x
				if seen[x] == nil then
					seen[x] = true
					n += 1
				end
			end
			p.dispose()
			clock:dispose()
			return n
		end
		local full = distinctPositions("full")
		local reduced = distinctPositions("reduced")
		expect(full > reduced).toBe(true)
		expect(reduced >= 2).toBe(true) -- still moving: not a freeze
	end)

	it("with NO clock the indeterminate view holds its rest pose and says so", function()
		local core, _, adapter, _, pres = harness()
		local p = LuauUI.newProgressView(LuauUI, core, { id = "Load" })
		local handle = pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		expect(#handle.controller.diagnostics()).toBe(0)
		expect(p.dump().animating).toBe(false)
		expect(p.dump().phase).toBe(0)
		expect(adapter.node("/S/Load/Bar/Sweep/Fill") ~= nil).toBe(true)
		p.dispose()
	end)

	it("is registry-neutral after dispose, clock and all", function()
		local core, _, _, _, _ = harness()
		local baseline = core:counters()
		local clock = motionClockLib.new(core, {
			now = function()
				return 0
			end,
		})
		local p = LuauUI.newProgressView(LuauUI, core, { id = "L", motionClock = clock })
		p.dispose()
		clock:dispose()
		expect(core:counters().scopes).toBe(baseline.scopes)
		expect(core:counters().observers).toBe(baseline.observers)
		expect(core:counters().signals).toBe(baseline.signals)
	end)
end)

describe("ProgressView: the spinner presentation (§3.1)", function()
	local function spinnerWorld(policy: string?)
		local core, _, adapter, _, pres = harness()
		local t = { now = 0 }
		local clock = motionClockLib.new(core, {
			now = function()
				return t.now
			end,
			motionPolicy = core:signal(policy or "full"),
		})
		local p = LuauUI.newProgressView(LuauUI, core, {
			id = "Load",
			presentation = "spinner",
			motionClock = clock,
		})
		local handle = pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		expect(#handle.controller.diagnostics()).toBe(0)
		return core, adapter, pres, clock, t, p
	end

	it("is five dots on the one new theme slot, and no bar at all", function()
		local _, adapter, _, clock, _, p = spinnerWorld()
		expect(adapter.node("/S/Load/Bar")).toBeNil()
		for index = 1, 5 do
			local node = adapter.node(`/S/Load/Spinner/Dot{index}`)
			expect(node ~= nil).toBe(true)
			-- the paint identity is the slot, never a borrowed public surface
			expect(node.props.surface).toBeNil()
			expect(node.decorationHint.slot).toBe("spinner")
		end
		expect(adapter.node("/S/Load/Spinner/Dot6")).toBeNil()
		expect(p.dump().presentation).toBe("spinner")
		expect(p.dump().indeterminate).toBe(true)
		p.dispose()
		clock:dispose()
	end)

	it("THE PULSE IS PAINT, NOT GEOMETRY: every dot keeps a fixed square box", function()
		-- The first shape here sized each dot as a PERCENT of the row, and the
		-- solver's own diagnostic killed it: a loading indicator lives inside a
		-- vertical ScrollView, and a fraction of an unbounded axis is not a size.
		-- This case pins the replacement — geometry is constant, the tint moves —
		-- INSIDE a scroller, which is the container the defect needed.
		local core, _, _, _ = harness()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 320, h = 200 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local pres = presenterLib.new(core, env, adapter, actionsLib.newSystem(core))
		local clock = motionClockLib.new(core, {
			now = function()
				return 0
			end,
		})
		local p = LuauUI.newProgressView(LuauUI, core, {
			id = "Load",
			presentation = "spinner",
			motionClock = clock,
		})
		local handle = pres.present(UI.Screen({
			id = "S",
			children = {
				UI.ScrollView({
					id = "SV",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.VStack({
							id = "Col",
							gap = 8,
							width = { type = "fill", weight = 1 },
							children = {
								-- taller than the viewport: the scroll axis is live
								UI.Box({
									id = "Tall",
									width = { type = "fill", weight = 1 },
									height = { type = "fixed", px = 400 },
								}),
								p.blueprint,
							},
						}),
					},
				}),
			},
		}))
		pres.refresh()
		expect(#handle.controller.diagnostics()).toBe(0)
		for index = 1, 5 do
			local rect = adapter.node(`/S/SV/Col/Load/Spinner/Dot{index}`).rect
			expect(rect.w).toBe(rect.h)
			expect(rect.w > 0).toBe(true)
		end
		p.dispose()
		clock:dispose()
	end)

	it("the pulse TRAVELS: the brightest dot moves along the ring as the phase sweeps", function()
		local _, adapter, pres, clock, t, p = spinnerWorld()
		local function brightest(): number
			local best, bestIndex = -1, 0
			for index = 1, 5 do
				local blend = adapter.node(`/S/Load/Spinner/Dot{index}`).props.tint.blend
				if blend > best then
					best, bestIndex = blend, index
				end
			end
			return bestIndex
		end
		local first = brightest()
		local moved = false
		for _ = 1, 10 do
			t.now += 0.05
			clock:step()
			pres.refresh()
			if brightest() ~= first then
				moved = true
			end
		end
		expect(moved).toBe(true)
		-- and every dot is still a DOT: the resting blend is visible, never zero,
		-- so the ring never looks like it lost a member
		for index = 1, 5 do
			local node = adapter.node(`/S/Load/Spinner/Dot{index}`)
			expect(node.props.tint.blend > 0).toBe(true)
			-- ...and the blend really reached the paint, not just the prop bag
			expect(node.tintColor ~= nil).toBe(true)
		end
		p.dispose()
		clock:dispose()
	end)

	it("under REDUCED motion the pulse still travels, on the quantized tick", function()
		local _, adapter, pres, clock, t, p = spinnerWorld("reduced")
		local function blends(): string
			local parts: { string } = {}
			for index = 1, 5 do
				table.insert(parts, string.format("%.4f", adapter.node(`/S/Load/Spinner/Dot{index}`).props.tint.blend))
			end
			return table.concat(parts, ",")
		end
		local start = blends()
		t.now += 0.05
		clock:step()
		pres.refresh()
		expect(blends()).toBe(start) -- quantized: no write inside the tick
		t.now += 0.3
		clock:step()
		pres.refresh()
		expect(blends() ~= start).toBe(true) -- ...and it MOVED, rather than froze
		p.dispose()
		clock:dispose()
	end)
end)

describe("ProgressView: the refusals that keep the two modes from contradicting", function()
	it("refuses a spinner with a value — a determinate spinner is an arc nothing can draw", function()
		local core = customFactory.new()
		local ok, err = pcall(function()
			LuauUI.newProgressView(LuauUI, core, { id = "L", value = 0.5, presentation = "spinner" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "indeterminate only", 1, true) ~= nil).toBe(true)
	end)

	it("refuses an unknown presentation, listing the two that exist", function()
		local core = customFactory.new()
		local ok, err = pcall(function()
			LuauUI.newProgressView(LuauUI, core, { id = "L", value = 0.5, presentation = "circular" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "spinner", 1, true) ~= nil).toBe(true)
	end)

	it("refuses min/max/format/showValue on a view with no value, rather than dropping them", function()
		local core = customFactory.new()
		for _, key in { "min", "max", "showValue" } do
			local spec: any = { id = "L" }
			spec[key] = if key == "showValue" then true else 3
			local ok, err = pcall(function()
				LuauUI.newProgressView(LuauUI, core, spec)
			end)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), key, 1, true) ~= nil).toBe(true)
		end
		local ok = pcall(function()
			LuauUI.newProgressView(LuauUI, core, {
				id = "L",
				format = function()
					return ""
				end,
			})
		end)
		expect(ok).toBe(false)
	end)
end)
