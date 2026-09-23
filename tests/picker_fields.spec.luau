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

describe("Picker message line: ownership", function()
	it("the hint line's owner is the picker's: dispose releases it", function()
		for _, style in { "menu", "segmented", "cards" } do
			-- built inside a caller's owner, which must get back exactly what it had
			local core = world.new(FACTS.desktop).core
			local caller = core.owner.createChild()
			local before = caller.size()
			local _, _, library = harness.libraryOf(core)
			local built = Compose.withOwner(caller, function()
				return require("../src/controls/picker").build(library, core, {
					id = "P",
					style = style,
					selected = Compose.cell("normal"),
					options = THREE,
					hint = "Change it any time",
				})
			end)
			built.dispose()
			expect(`{style} {caller.size() - before}`).toBe(`{style} 0`)
		end
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
		-- a cap below the panel's own chrome still leaves one visible row to walk
		local tiny, tinyPicker = mount("desktop", { style = "menu", options = LONG, maxHeight = 10 })
		tinyPicker.api.open()
		tiny.pres.refresh()
		tiny.pres.refresh()
		expect(node(tiny, "/List").rect.h >= FLOOR).toBe(true)
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

	it("the open popover declares no placement its parent ignores", function()
		local warnings = require("../src/layout/placement_warnings")
		local said: { string } = {}
		local realReport = warnings.report
		warnings.reset()
		warnings.setEnabled(true)
		warnings.report = function(message: string)
			table.insert(said, message)
		end
		local w, picker = mount("desktop", { style = "menu", label = "Driver" })
		picker.api.open()
		w.pres.refresh()
		w.pres.refresh()
		warnings.report = realReport
		warnings.reset()
		expect(table.concat(said, "\n")).toBe("")
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

	it("the popover is as wide as its widest row, avatar, icon, meta and badge counted", function()
		local w, picker = mount("desktop", {
			style = "menu",
			label = "Driver",
			selected = Compose.cell("a"),
			options = {
				{ value = "a", label = "Ada", avatar = { name = "Ada" }, badge = 3, icon = "settings" },
				{ value = "b", label = "Bo", avatar = { name = "Bo" }, meta = "Crew", icon = "settings" },
				{ value = "c", label = "Cy", avatar = { name = "Cy" }, icon = "settings" },
			},
		})
		picker.api.open()
		w.pres.refresh()
		w.pres.refresh()
		local panel = node(w, "/Popup").rect
		for _, path in w.adapter.paths() do
			local rect = w.adapter.node(path).rect
			if string.find(path, "/Opt-", 1, true) and rect ~= nil and rect.w > 0 then
				local inside = rect.x >= panel.x - 0.5 and rect.x + rect.w <= panel.x + panel.w + 0.5
				expect(`{path} inside {inside}`).toBe(`{path} inside true`)
			end
		end
		local labels = 0
		for _, path in w.adapter.paths() do
			if string.find(path, "/Opt-", 1, true) and string.sub(path, -6) == "/Label" then
				labels += 1
				expect(`{path} {w.adapter.node(path).rect.w > 0}`).toBe(`{path} true`)
			end
		end
		expect(labels).toBe(3)
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

describe("Picker segmented vocabulary and the radio mark", function()
	it("appearance paints the track filled, stroked or not at all, live, and refuses a menu word", function()
		local word = Compose.cell("filled")
		local w = mount("desktop", { style = "segmented", appearance = word })
		local track = suffixPath(w, "/Track") :: string
		expect(w.adapter.node(track).props.surface).toBe("control")
		word:set("stroke")
		w.pres.refresh()
		expect(w.adapter.node(track).props.surface).toBe("plain")
		expect(w.adapter.node(track).props.stroke ~= nil).toBe(true)
		word:set("utility")
		w.pres.refresh()
		expect(w.adapter.visibleOf(track)).toBe(false)
		pcall(function()
			word:set("contrast")
			w.pres.refresh()
		end)
		expect(w.adapter.visibleOf(track)).toBe(false)
		expect(pcall(function()
			mount("desktop", { style = "segmented", appearance = "contrast" })
		end)).toBe(false)
	end)

	it("an automatic picker keeps its appearance intent across a live family switch", function()
		local w, picker = mount("desktop", { appearance = "contrast" })
		expect(picker.dump().style).toBe("menu")
		expect(node(w, "/Trigger").props.appearance).toBe("emphasis")
		w.env:set("displaySize", "Large")
		w.env:set("capabilities", { gamepad = true })
		w.env:set("preferredInput", "Gamepad")
		w.pres.refresh()
		w.pres.refresh()
		expect(picker.dump().style).toBe("segmented")
		expect(node(w, "/Track").props.surface).toBe("plain")
		w.env:set("displaySize", "Medium")
		w.env:set("capabilities", { mouse = true, keyboard = true })
		w.env:set("preferredInput", "KeyboardAndMouse")
		w.pres.refresh()
		w.pres.refresh()
		expect(picker.dump().style).toBe("menu")
		expect(node(w, "/Trigger").props.appearance).toBe("emphasis")
	end)

	it("corners reach the track, its ends and the fill; a rung shrinks segments inside one reserved target", function()
		local pill = mount("desktop", { style = "segmented", corners = "pill" })
		expect(node(pill, "/Track").props.corners.tokens.radius).toBe("pill")
		local square = mount("desktop", { style = "segmented", corners = "square" })
		expect(node(square, "/Track").props.corners.radius).toBe(0)
		local w = mount("desktop", { style = "segmented", controlSize = "compact" })
		local segs: { any } = {}
		for _, key in { "Opt1", "Opt2", "Opt3" } do
			table.insert(segs, node(w, "/" .. key).rect)
		end
		expect(segs[1].h < FLOOR).toBe(true)
		expect(node(w, "/P+target").rect.h >= FLOOR).toBe(true)
		for i = 1, 2 do
			local a = w.adapter.hitRectOf(suffixPath(w, `/Opt{i}`) :: string) or segs[i]
			local b = w.adapter.hitRectOf(suffixPath(w, `/Opt{i + 1}`) :: string) or segs[i + 1]
			expect(a.x + a.w <= b.x + 0.5).toBe(true)
		end
	end)

	it("indicatorPosition moves the radio mark to either edge, and belongs to the radio group only", function()
		for _, edge in { "leading", "trailing" } do
			local w = mount("desktop", { style = "radioGroup", indicatorPosition = edge })
			local mark = node(w, "/Opt2/HStack#1/Indicator") or node(w, "/Opt2/Indicator")
			local markRect: any = nil
			local labelRect: any = nil
			for _, path in w.adapter.paths() do
				if string.find(path, "/Opt2/", 1, true) then
					if string.sub(path, -#"/Indicator") == "/Indicator" then
						markRect = w.adapter.node(path).rect
					elseif string.sub(path, -#"/Label") == "/Label" then
						labelRect = w.adapter.node(path).rect
					end
				end
			end
			local _ = mark
			local trailing = markRect.x > labelRect.x
			expect(`{edge}: {trailing}`).toBe(`{edge}: {edge == "trailing"}`)
		end
		expect(pcall(function()
			mount("desktop", { style = "segmented", indicatorPosition = "trailing" })
		end)).toBe(false)
	end)
end)

describe("Picker cards", function()
	local CARDS = {
		{ value = "sprint", label = "Sprint", description = "Three short laps", meta = "3 laps", icon = "flag" },
		{
			value = "endurance",
			label = "Endurance",
			description = "A long race for the patient",
			meta = "20 laps",
			icon = "flag",
		},
		{
			value = "locked",
			label = "Night",
			description = "Unlocks at level 10",
			meta = "Soon",
			icon = "flag",
			enabled = false,
		},
	}

	it("each option is a bordered card with its meta, the chosen one plated, on every input", function()
		for _, input in { "pointer", "touch", "keyboard", "gamepad" } do
			local selected = Compose.cell("sprint")
			local w = mount("desktop", { style = "cards", options = CARDS, selected = selected })
			local card = suffixPath(w, "/Card-endurance") :: string
			expect(w.adapter.node(card).props.stroke ~= nil).toBe(true)
			expect(node(w, "/Card-sprint").props.surface).toBe("accent")
			expect(node(w, "/Card-endurance").props.surface).toBe("plain")
			local metas = 0
			for _, path in w.adapter.paths() do
				if string.find(path, "/Card-endurance/", 1, true) and w.adapter.node(path).props.text == "20 laps" then
					metas += 1
				end
			end
			expect(metas).toBe(1)
			if input == "pointer" then
				w.adapter.tap(card)
			elseif input == "touch" then
				w.adapter.tap(card, { inputType = "Touch" })
			else
				w.pres.focus.focusOn(card)
				w.pres.refresh()
				w.press(if input == "keyboard" then "Return" else "ButtonA")
			end
			w.pres.refresh()
			expect(`{input}: {selected:peek()}`).toBe(`{input}: endurance`)
			expect(node(w, "/Card-endurance").props.surface).toBe("accent")
			-- a disabled card is unreachable
			w.adapter.tap(suffixPath(w, "/Card-locked") :: string)
			w.pres.refresh()
			expect(selected:peek()).toBe("endurance")
		end
	end)

	it("choosing the chosen card again clears it only when the selection is not required", function()
		for _, input in { "pointer", "touch", "keyboard", "gamepad" } do
			local optional = Compose.cell("sprint")
			local w = mount("desktop", { style = "cards", options = CARDS, selected = optional, required = false })
			local card = suffixPath(w, "/Card-sprint") :: string
			if input == "pointer" then
				w.adapter.tap(card)
			elseif input == "touch" then
				w.adapter.tap(card, { inputType = "Touch" })
			else
				w.pres.focus.focusOn(card)
				w.pres.refresh()
				w.press(if input == "keyboard" then "Return" else "ButtonA")
			end
			w.pres.refresh()
			expect(`{input}: {optional:peek()}`).toBe(`{input}: nil`)
			-- the disabled card is no stop for a keyboard or a pad either
			for _, entry in w.handle.focusOrder().traversal do
				expect(string.find(tostring(entry.path), "Card-locked", 1, true)).toBeNil()
			end
		end
		local kept = Compose.cell("sprint")
		local w2 = mount("desktop", { style = "cards", options = CARDS, selected = kept })
		w2.adapter.tap(suffixPath(w2, "/Card-sprint") :: string)
		w2.pres.refresh()
		expect(kept:peek()).toBe("sprint")
	end)

	it("a row of cards wraps on a narrow phone and long copy wraps inside its card", function()
		local w = mount("phone", { style = "cards", options = CARDS, axis = "x" })
		local ys: { [number]: boolean } = {}
		local rows = 0
		for _, key in { "sprint", "endurance", "locked" } do
			local r = node(w, "/Card-" .. key).rect
			expect(`{key} inside {r.x >= 0 and r.x + r.w <= 390}`).toBe(`{key} inside true`)
			if not ys[r.y] then
				ys[r.y] = true
				rows += 1
			end
		end
		expect(rows > 1).toBe(true)
		local long = mount("phone", {
			style = "cards",
			selected = Compose.cell("a"),
			options = {
				{
					value = "a",
					label = "Championship",
					description = "Every track in the season, back to back, with the standings carried between races",
				},
			},
		})
		local card = node(long, "/Card-a").rect
		local description = node(long, "/Description").rect
		expect(card.x + card.w <= 390).toBe(true)
		expect(description.h > 20).toBe(true)
		expect(pcall(function()
			mount("desktop", { style = "cards", options = CARDS, appearance = "utility" })
		end)).toBe(false)
	end)
end)

describe("Picker option indicator", function()
	it("follows the caller's live option record: status changes and a removed mark goes", function()
		local function options(indicator: any?)
			return {
				{ value = "easy", label = "Easy" },
				{ value = "normal", label = "Normal", indicator = indicator },
				{ value = "hard", label = "Hard" },
			}
		end
		local list = Compose.cell(options({ status = "warning" }))
		local w = mount("desktop", { style = "radioGroup", options = list })
		local function roles(): string
			local out: { string } = {}
			for _, path in w.adapter.paths() do
				local tint = w.adapter.node(path).props.tint
				-- the plate's status role (the cutout ring paints `surface`)
				if string.find(path, "/Status/", 1, true) and type(tint) == "table" and tint.role ~= "surface" then
					if not table.find(out, tint.role) then
						table.insert(out, tint.role)
					end
				end
			end
			table.sort(out)
			return table.concat(out, ",")
		end
		expect(roles()).toBe("warning")
		list:set(options({ status = "error" }))
		w.pres.refresh()
		expect(roles()).toBe("danger")
		list:set(options(nil))
		w.pres.refresh()
		expect(roles()).toBe("")
	end)
end)
