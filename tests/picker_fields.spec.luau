--!strict
--[[ PICKER AS A FIELD, CARDS, RADIO AND SEGMENTED VOCABULARY (P3c). Every
	claim reads the SCREEN: mounted paths, solved and painted rects, props the
	adapter was told, the focus the ring holds and the caller's own cells. ]]

local harness = require("./lib/harness")
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local world = require("./lib/harness_world")
local Compose = require("../src/vendor/compose/core")
local snapshot = require("../src/themes/snapshot")

local UI = harness.UI
local FLOOR = snapshot.neutral().targetSizes.minimum

local FACTS = {
	phone = { viewport = { x = 0, y = 0, w = 390, h = 844 }, capabilities = { touch = true }, preferredInput = "Touch" },
	desktop = {
		viewport = { x = 0, y = 0, w = 1280, h = 720 },
		capabilities = { mouse = true, keyboard = true },
		preferredInput = "KeyboardAndMouse",
	},
	tv = {
		viewport = { x = 0, y = 0, w = 1920, h = 1080 },
		capabilities = { gamepad = true },
		preferredInput = "Gamepad",
		displaySize = "Large",
	},
}
local THREE = {
	{ value = "easy", label = "Easy" },
	{ value = "normal", label = "Normal" },
	{ value = "hard", label = "Hard" },
}

local function mount(device: string, spec: any, facts: any?)
	local w = world.new(facts or FACTS[device])
	local built = table.clone(spec)
	built.id = built.id or "P"
	built.selected = built.selected or Compose.cell("normal")
	built.options = built.options or THREE
	local picker = harness.Controls.Picker(w.core, built)
	w.present(UI.Screen({ id = "S", children = { picker.blueprint } }), { keyboardNavigation = true })
	w.pres.refresh()
	return w, picker
end

local function suffixPath(w: any, suffix: string): string?
	for _, path in w.adapter.paths() do
		if string.sub(path, -#suffix) == suffix then
			return path
		end
	end
	return nil
end
local function node(w: any, suffix: string): any
	local path = suffixPath(w, suffix)
	return if path ~= nil then w.adapter.node(path) else nil
end
local function inside(outer: any, inner: any): boolean
	return inner.y >= outer.y - 0.5 and inner.y + inner.h <= outer.y + outer.h + 0.5
end

describe("Picker menu field: notation, message line and paint", function()
	it("the required mark rides the label and the error replaces the hint beside a danger trigger", function()
		local failure = Compose.cell("")
		local w = mount("desktop", {
			label = "Difficulty",
			requiredMark = "required",
			hint = "Change it any time",
			errorText = failure,
		})
		expect(node(w, "/Row/Label").props.text).toBe("Difficulty *")
		expect(node(w, "/Message/Validation").props.text).toBe("Change it any time")
		expect(node(w, "/Trigger").props.stroke).toBeNil()
		local before = node(w, "/Trigger").rect
		failure:set("Pick a difficulty to continue.")
		w.pres.refresh()
		expect(node(w, "/Message/Validation").props.text).toBe("Pick a difficulty to continue.")
		expect(node(w, "/Message/Validation").props.tint.role).toBe("danger")
		expect(suffixPath(w, "/MarkWhen/then/MessageMark") ~= nil).toBe(true)
		local stroke = node(w, "/Trigger").props.stroke
		expect(stroke ~= nil and stroke.color.r > stroke.color.g * 2).toBe(true) -- the danger red
		expect(node(w, "/Trigger").rect.y).toBe(before.y)
	end)

	it("appearance maps onto the trigger's paint live, and a word outside the family is refused", function()
		local word = Compose.cell("standard")
		local w = mount("desktop", { style = "menu", appearance = word })
		local path = suffixPath(w, "/Trigger") :: string
		expect(w.adapter.node(path).props.appearance).toBeNil()
		word:set("contrast")
		w.pres.refresh()
		expect(w.adapter.node(path).props.appearance).toBe("emphasis")
		word:set("utility")
		w.pres.refresh()
		expect(w.adapter.node(path).props.appearance).toBe("utility")
		expect(suffixPath(w, "/Trigger")).toBe(path)
		pcall(function()
			word:set("filled")
			w.pres.refresh()
		end)
		expect(w.adapter.node(path).props.appearance).toBe("utility")
		for _, bad in { { style = "menu", appearance = "stroke" }, { style = "inline", appearance = "utility" } } do
			local ok = pcall(function()
				mount("desktop", bad)
			end)
			expect(ok).toBe(false)
		end
	end)

	it("a named rung shrinks the trigger inside a whole reserved target, and corners reach it", function()
		local w = mount("desktop", { style = "menu", controlSize = "compact", corners = "pill" })
		local trigger = node(w, "/Trigger")
		expect(trigger.rect.h < FLOOR).toBe(true)
		expect(node(w, "/P+target").rect.h >= FLOOR).toBe(true)
		expect(trigger.props.corners.tokens.radius).toBe("pill")
		w.adapter.tap(suffixPath(w, "/Trigger") :: string)
		w.pres.refresh()
		expect(suffixPath(w, "/Opt-normal") ~= nil).toBe(true)
	end)
end)

describe("Picker menu panel: maxHeight and the selected row", function()
	local LONG = {}
	for i = 1, 30 do
		table.insert(LONG, { value = `v{i}`, label = `Option {i}` })
	end

	it("maxHeight bounds the whole panel, ordinary and searchable, and a bad cap is refused", function()
		for _, searchable in { false, true } do
			local spec: any = { style = if searchable then "navigationLink" else "menu", maxHeight = 96 }
			spec.options = LONG
			spec.selected = Compose.cell("v1")
			if searchable then
				spec.query = Compose.cell("")
			end
			local w, picker = mount("desktop", spec)
			picker.api.open()
			w.pres.refresh()
			w.pres.refresh()
			local list = node(w, if searchable then "/Results" else "/List")
			expect(`searchable={searchable} list {list.rect.h <= 96}`).toBe(`searchable={searchable} list true`)
			if searchable then
				-- a searchable list reveals the selected row through its own window
				local w2, picker2 = mount("desktop", {
					style = "navigationLink",
					options = LONG,
					query = Compose.cell(""),
					selected = Compose.cell("v25"),
				})
				picker2.api.open()
				w2.pres.refresh()
				w2.pres.refresh()
				local scrolled = false
				for _, path in w2.adapter.paths() do
					local pos = w2.adapter.scrollPositionOf(path)
					if string.find(path, "/Results", 1, true) and pos ~= nil and pos.y > 0 then
						scrolled = true
					end
				end
				expect(`searchable list revealed {scrolled}`).toBe("searchable list revealed true")
			end
		end
		for _, bad in { 0, math.huge, 0 / 0, "96" } do
			local ok = pcall(function()
				mount("desktop", { style = "menu", maxHeight = bad })
			end)
			expect(ok).toBe(false)
		end
		expect(pcall(function()
			mount("desktop", { style = "segmented", maxHeight = 96 })
		end)).toBe(false)
	end)

	it("opening lands on the selected row, visible inside the list, on every input", function()
		for _, input in { "pointer", "keyboard", "gamepad", "touch" } do
			local w, picker = mount(
				if input == "touch" then "phone" else "desktop",
				{ style = "menu", options = LONG, maxHeight = 200, selected = Compose.cell("v25") }
			)
			local trigger = suffixPath(w, "/Trigger") :: string
			if input == "pointer" then
				w.adapter.tap(trigger)
			elseif input == "touch" then
				w.adapter.tap(trigger, { inputType = "Touch" })
			else
				w.pres.focus.focusOn(trigger)
				w.pres.refresh()
				w.press(if input == "keyboard" then "Return" else "ButtonA")
			end
			w.pres.refresh()
			w.pres.refresh()
			expect(`{input} open {picker.dump().open}`).toBe(`{input} open true`)
			local list = suffixPath(w, "/List") :: string
			local scroll = w.adapter.scrollPositionOf(list) or { x = 0, y = 0 }
			local row = table.clone(node(w, "/Opt-v25").rect)
			row.y -= scroll.y
			local shown = inside(w.adapter.node(list).rect, row)
			expect(`{input} selected row visible {shown}`).toBe(`{input} selected row visible true`)
		end
	end)
end)

describe("Picker menu rows: avatar, disabled and long labels", function()
	it("an avatar leads its row without a second stop or press, and a disabled row is unreachable", function()
		local selected = Compose.cell("a")
		local w, picker = mount("desktop", {
			style = "menu",
			selected = selected,
			options = {
				{ value = "a", label = "Ada", avatar = { name = "Ada" } },
				{ value = "b", label = "Bo", avatar = { name = "Bo" }, badge = 2 },
				{ value = "c", label = "Cy", avatar = { name = "Cy" }, enabled = false },
			},
		})
		picker.api.open()
		w.pres.refresh()
		local avatar = suffixPath(w, "/Opt-b/HStack#1/Avatar") or suffixPath(w, "/Avatar")
		expect(avatar ~= nil).toBe(true)
		for _, entry in w.handle.focusOrder().traversal do
			expect(string.find(tostring(entry.path), "/Avatar", 1, true)).toBeNil()
		end
		w.adapter.tap(suffixPath(w, "/Opt-c") :: string)
		w.pres.refresh()
		expect(selected:peek()).toBe("a")
		w.adapter.tap(suffixPath(w, "/Opt-b") :: string)
		w.pres.refresh()
		expect(selected:peek()).toBe("b")
		expect(w.core.lastError()).toBeNil()
	end)

	it("a long option label stays inside its panel", function()
		local w, picker = mount("phone", {
			style = "menu",
			selected = Compose.cell("x"),
			options = {
				{ value = "x", label = "A very long option label that a narrow phone cannot hold on one line" },
				{ value = "y", label = "Short" },
			},
		})
		picker.api.open()
		w.pres.refresh()
		local panel = node(w, "/Popup").rect
		local row = node(w, "/Opt-x").rect
		expect(row.x >= panel.x - 0.5 and row.x + row.w <= panel.x + panel.w + 0.5).toBe(true)
	end)
end)
