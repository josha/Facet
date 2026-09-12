--!strict
-- Picker `style` — the reference-platform-shaped selection control (2026-09-11).
--
-- ONE control, six styles, and an `automatic` that resolves from PUBLISHED
-- FACTS (size class, distance profile, primary interaction class), never a
-- device name. The old popup button, its split trigger and the radio spelling
-- fold into this surface; the claims below are what "folded" means:
--
--   * `automatic` on a nearby touch or pointer surface is the MENU style: one
--     integrated trigger (value + up/down chevron INSIDE one button), never a
--     separate chevron cell.
--   * `automatic` on a ten-foot surface is a focus-navigable strip (segmented
--     for a few short options, inline rows otherwise); a nearby gamepad keeps
--     a short strip and falls back to the menu when the strip cannot fit.
--   * the menu presents ANCHORED to the trigger with a materialize transition,
--     marks the selected row with a check and has no Cancel row on a pointer
--     surface (outside tap / Escape / ButtonB dismiss).
--   * `presentation` keeps working as a deprecated alias of `style`.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local world = require("./lib/world")
local pickerLib = require("../src/controls/picker")

local UI = Facet.UI

local THREE = {
	{ value = "easy", label = "Easy" },
	{ value = "normal", label = "Normal" },
	{ value = "hard", label = "Hard" },
}
local SEVEN = {}
for i = 1, 7 do
	table.insert(SEVEN, { value = `v{i}`, label = `Option {i}` })
end

local function suffixNode(w, suffix: string): any
	for _, path in w.adapter.paths() do
		if string.sub(path, -#suffix) == suffix then
			return w.adapter.node(path)
		end
	end
	return nil
end
local function suffixPath(w, suffix: string): string?
	for _, path in w.adapter.paths() do
		if string.sub(path, -#suffix) == suffix then
			return path
		end
	end
	return nil
end

-- PHONE: touch primary, compact. DESKTOP: pointer, wide. TV: Large display,
-- gamepad. HANDHELD: compact width with a gamepad primary.
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
	handheld = {
		viewport = { x = 0, y = 0, w = 560, h = 320 },
		capabilities = { gamepad = true, touch = true },
		preferredInput = "Gamepad",
	},
}

local function mount(device: string, spec: any)
	local w = world.new(FACTS[device])
	local built = table.clone(spec)
	built.id = built.id or "P"
	built.selected = built.selected or w.core:signal("normal")
	built.options = built.options or THREE
	local picker = Facet.Controls.Picker(w.core, built)
	w.present(UI.Screen({ id = "S", children = { picker.blueprint } }))
	w.pres.refresh()
	return w, picker
end

describe("Picker style: the automatic ladder is a pure function of facts", function()
	local function facts(over: any)
		local base = {
			optionCount = 3,
			longestLabel = 6,
			sizeClass = "compact",
			distanceProfile = "near",
			primaryInput = "touch",
		}
		for k, v in over do
			base[k] = v
		end
		return base
	end
	it("nearby touch and pointer resolve MENU whatever the count", function()
		expect(pickerLib.resolveStyle(facts({}))).toBe("menu")
		expect(pickerLib.resolveStyle(facts({ optionCount = 2, sizeClass = "wide", primaryInput = "pointer" }))).toBe(
			"menu"
		)
		expect(pickerLib.resolveStyle(facts({ optionCount = 12, primaryInput = "pointer" }))).toBe("menu")
	end)
	it("ten-foot resolves a focus-navigable strip: segmented for a few short options, inline up to six", function()
		expect(pickerLib.resolveStyle(facts({ distanceProfile = "ten-foot", sizeClass = "regular" }))).toBe("segmented")
		expect(pickerLib.resolveStyle(facts({ distanceProfile = "ten-foot", sizeClass = "regular", optionCount = 6 }))).toBe(
			"inline"
		)
		-- past the popover limit the rows would be a page of their own: a menu
		-- (one focus-navigable panel under a gamepad) holds them instead
		expect(pickerLib.resolveStyle(facts({ distanceProfile = "ten-foot", sizeClass = "regular", optionCount = 7 }))).toBe(
			"menu"
		)
		expect(
			pickerLib.resolveStyle(
				facts({ distanceProfile = "ten-foot", sizeClass = "regular", primaryInput = "pointer" })
			)
		).toBe("segmented")
	end)
	it("a nearby gamepad keeps a short strip, and falls back to the menu on a compact screen", function()
		expect(pickerLib.resolveStyle(facts({ primaryInput = "gamepad", sizeClass = "compact" }))).toBe("segmented")
		expect(pickerLib.resolveStyle(facts({ primaryInput = "gamepad", sizeClass = "compact", optionCount = 7 }))).toBe(
			"menu"
		)
		expect(pickerLib.resolveStyle(facts({ primaryInput = "gamepad", sizeClass = "regular", optionCount = 6 }))).toBe(
			"inline"
		)
		expect(pickerLib.resolveStyle(facts({ primaryInput = "gamepad", sizeClass = "regular", optionCount = 7 }))).toBe(
			"menu"
		)
	end)
	it("a searchable picker is always the navigation link", function()
		expect(pickerLib.resolveStyle(facts({ searchable = true, primaryInput = "pointer", sizeClass = "wide" }))).toBe(
			"navigationLink"
		)
	end)
end)

describe("Picker style: the menu trigger is ONE integrated control", function()
	it("on a phone the automatic picker is a menu whose trigger carries the value AND the chevron", function()
		local w, picker = mount("phone", { label = "Difficulty" })
		expect(picker.dump().style).toBe("menu")
		expect(picker.dump().requestedStyle).toBe("automatic")
		local trigger = suffixNode(w, "/Trigger")
		expect(trigger ~= nil).toBe(true)
		-- a CONTENT button: the rendered label is its `Value` child, never a
		-- second painted word
		expect(suffixNode(w, "/Value").props.text).toBe("Normal")
		local chevron = suffixNode(w, "/Chevron")
		expect(chevron ~= nil).toBe(true)
		-- the label sits BESIDE the trigger in one row, the reference platform's form-row shape
		expect(suffixNode(w, "/Label").props.text).toBe("Difficulty")
		-- the closed control is a single focusable: the trigger, never a chevron cell
		expect(w.pres.focus.focused:get()).toBe(suffixPath(w, "/Trigger"))
		w.overflowGuard()
	end)
	it("on a desktop the trigger hugs its content like a pop-up button and opens ANCHORED", function()
		local w, picker = mount("desktop", {})
		expect(picker.dump().style).toBe("menu")
		local root = w.controller.rectOf("/S/P")
		local trigger = w.controller.rectOf(suffixPath(w, "/Trigger") :: string)
		expect(trigger.w < 1280 / 2).toBe(true)
		expect(root.w >= trigger.w).toBe(true)
		w.adapter.tap(suffixPath(w, "/Trigger") :: string)
		w.pres.refresh()
		expect(picker.dump().open).toBe(true)
		expect(picker.dump().presentation).toBe("menu")
		expect(w.pres.anchoredSurfaces().count).toBe(1)
		-- every option is a row; the selected one wears the check; no Cancel row
		expect(suffixNode(w, "/Opt-normal") ~= nil).toBe(true)
		-- (`visibleOf` is nil for a node never hidden, false once `hidden` wrote it)
		local function markVisible(key: string): boolean
			for _, path in w.adapter.paths() do
				if string.find(path, `/Opt-{key}/`, 1, true) ~= nil and string.sub(path, -5) == "/Mark" then
					return w.adapter.visibleOf(path) ~= false
				end
			end
			error(`no mark under Opt-{key}`)
		end
		expect(markVisible("normal")).toBe(true)
		expect(markVisible("hard")).toBe(false)
		expect(suffixPath(w, "/Cancel")).toBe(nil)
		-- ...and the menu opens with the CURRENT value focused, the pop-up rule
		expect(w.pres.focus.focused:get()).toBe(suffixPath(w, "/Opt-normal"))
		-- the panel is at least as wide as the trigger (the pop-up button rule)
		local panel = w.adapter.node(suffixPath(w, "/Popup") :: string).rect
		expect(panel.w + 0.5 >= trigger.w).toBe(true)
		-- picking a row writes the caller's signal, closes, relabels the trigger
		w.adapter.tap(suffixPath(w, "/Opt-hard") :: string)
		w.pres.refresh()
		expect(picker.dump().open).toBe(false)
		expect(picker.dump().selected).toBe("hard")
		expect(suffixNode(w, "/Value").props.text).toBe("Hard")
		w.overflowGuard()
	end)
	it("re-activating the trigger and gamepad B close an open menu without changing the selection", function()
		-- (Escape is the engine's own key — bound to the Roblox menu, never
		-- deliverable to a surface — so the keyboard's ways out are the trigger,
		-- an outside click and ButtonB; docs/guide/07-input.md)
		local w, picker = mount("desktop", {})
		w.adapter.tap(suffixPath(w, "/Trigger") :: string)
		w.pres.refresh()
		expect(picker.dump().open).toBe(true)
		w.adapter.tap(suffixPath(w, "/Trigger") :: string)
		w.pres.refresh()
		expect(picker.dump().open).toBe(false)
		expect(picker.dump().selected).toBe("normal")
		w.adapter.tap(suffixPath(w, "/Trigger") :: string)
		w.pres.refresh()
		w.system.deviceKey("ButtonB", true)
		w.system.deviceKey("ButtonB", false)
		w.pres.refresh()
		expect(picker.dump().open).toBe(false)
		expect(picker.dump().selected).toBe("normal")
	end)
	it("on a phone a touch tap opens the menu anchored to the row, and a long list becomes a sheet", function()
		local w, picker = mount("phone", { label = "Difficulty" })
		w.adapter.tap(suffixPath(w, "/Trigger") :: string, { inputType = "Touch" })
		w.pres.refresh()
		expect(picker.dump().open).toBe(true)
		expect(picker.dump().presentation).toBe("menu")
		expect(w.pres.anchoredSurfaces().count).toBe(1)
		picker.api.close()
		w.pres.refresh()
		local w2, long = mount("phone", { options = SEVEN, selected = w.core:signal("v1") })
		w2.adapter.tap(suffixPath(w2, "/Trigger") :: string, { inputType = "Touch" })
		w2.pres.refresh()
		expect(long.dump().presentation).toBe("sheet")
		expect(suffixPath(w2, "/Popup/Cancel") ~= nil).toBe(true)
	end)
end)

describe("Picker style: a described popover never paints past the phone", function()
	it("caps the themed panel width at the viewport less a gutter each side", function()
		local w = world.new(FACTS.phone)
		local picker = Facet.Controls.Picker(w.core, {
			id = "P",
			label = "Race group",
			selected = w.core:signal("open"),
			options = {
				{ value = "open", label = "Open races" },
				{ value = "club", label = "Club races", description = "Join a club to unlock." },
			},
		})
		w.present(UI.Screen({ id = "S", children = { picker.blueprint } }))
		w.pres.refresh()
		picker.api.open()
		w.pres.refresh()
		local panel = w.adapter.node(suffixPath(w, "/Popup") :: string).rect
		expect(panel.x >= 0).toBe(true)
		expect(panel.x + panel.w <= 390).toBe(true)
		expect(panel.w <= 390 - 16).toBe(true)
		-- ...and a phone narrower than the themed panel gets the capped width
		local n = world.new({
			viewport = { x = 0, y = 0, w = 320, h = 640 },
			capabilities = { touch = true },
			preferredInput = "Touch",
		})
		local narrow = Facet.Controls.Picker(n.core, {
			id = "P",
			label = "Race group",
			selected = n.core:signal("open"),
			options = {
				{ value = "open", label = "Open races" },
				{
					value = "club",
					label = "Club races",
					-- long enough that the row it wants is wider than the screen can give
					description = "Join a club to unlock these races and the club-only weekend events.",
				},
			},
		})
		n.present(UI.Screen({ id = "S", children = { narrow.blueprint } }))
		n.pres.refresh()
		narrow.api.open()
		n.pres.refresh()
		-- the popover HUGS its widest row (the described one wants more than the
		-- row can have) and stops at the screen's content inset on both sides
		local capped = n.adapter.node(suffixPath(n, "/Popup") :: string).rect
		expect(capped.w).toBe(320 - 2 * 16)
		expect(capped.x >= 16 and capped.x + capped.w <= 320 - 16).toBe(true)
	end)
end)

describe("Picker style: the strip styles and the deprecated spellings", function()
	it("on a TV the automatic picker is a segmented strip, inline past four options, a menu past six", function()
		local _, picker = mount("tv", {})
		expect(picker.dump().style).toBe("segmented")
		expect(picker.dump().presentation).toBe("segmented")
		local six = table.clone(SEVEN)
		table.remove(six)
		local _, rows = mount("tv", { options = six, selected = Facet.newCore():signal("v1") })
		expect(rows.dump().style).toBe("inline")
		local w, long = mount("tv", { options = SEVEN, selected = Facet.newCore():signal("v1") })
		expect(long.dump().style).toBe("menu")
		-- ...and under a gamepad that menu is ONE panel, focus-navigable
		long.api.open()
		w.pres.refresh()
		expect(long.dump().presentation).toBe("sheet")
	end)
	it("a handheld (compact + gamepad) keeps three short options segmented and sends seven to the menu", function()
		local _, picker = mount("handheld", {})
		expect(picker.dump().style).toBe("segmented")
		local _, long = mount("handheld", { options = SEVEN, selected = Facet.newCore():signal("v1") })
		expect(long.dump().style).toBe("menu")
	end)
	it('`presentation = "radio"` still builds, as the radioGroup style, and is declared deprecated', function()
		local _, picker = mount("phone", { presentation = "radio" })
		expect(picker.dump().style).toBe("radioGroup")
		expect(picker.dump().requestedStyle).toBe("radioGroup")
		local found = false
		for _, entry in Facet.DEPRECATIONS do
			if entry.surface == "Picker.presentation" then
				found = true
			end
		end
		expect(found).toBe(true)
	end)
	it("a declared style never consults the ladder, and an unknown one is refused by name", function()
		local _, picker = mount("phone", { style = "segmented" })
		expect(picker.dump().style).toBe("segmented")
		local ok, err = pcall(function()
			return mount("phone", { style = "wheel" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "wheel", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "navigationLink", 1, true) ~= nil).toBe(true)
	end)
	it("the navigation link presents a full sheet with its search field", function()
		local w = world.new(FACTS.phone)
		local query = w.core:signal("")
		local picker = Facet.Controls.Picker(w.core, {
			id = "P",
			label = "Track",
			selected = w.core:signal("v1"),
			options = SEVEN,
			query = query,
		})
		w.present(UI.Screen({ id = "S", children = { picker.blueprint } }))
		w.pres.refresh()
		expect(picker.dump().style).toBe("navigationLink")
		-- the title lives INSIDE the one row button, which fills its row
		expect(suffixNode(w, "/Trigger/Row/Label").props.text).toBe("Track")
		w.overflowGuard()
		w.adapter.tap(suffixPath(w, "/Trigger") :: string, { inputType = "Touch" })
		w.pres.refresh()
		expect(picker.dump().presentation).toBe("sheet")
		expect(suffixNode(w, "/Popup/Search") ~= nil).toBe(true)
		-- ...and on a desktop the row still fills (a hugging row would give its
		-- fill title nothing)
		local d = world.new(FACTS.desktop)
		local desk = Facet.Controls.Picker(d.core, {
			id = "P",
			label = "Track",
			selected = d.core:signal("v1"),
			options = SEVEN,
			query = d.core:signal(""),
		})
		d.present(UI.Screen({ id = "S", children = { desk.blueprint } }))
		d.pres.refresh()
		expect(d.controller.rectOf(suffixPath(d, "/Trigger") :: string).w).toBe(1280)
		d.overflowGuard()
	end)
end)

--[[ THE CHOSEN ROW CAN BE READ (user feedback item 7, the popover half:
	measured 2.37:1 on Glossy Touch and 2.46:1 on Pixel Quest against a 4.5:1
	floor).

	WHAT THE DEFECT WAS, because no palette was wrong. The picker's card marks its
	current value with a `controlSelected` wash — a `Fill` Box behind a row that is
	`surface = "plain"` by design. `plain` paints nothing, states included, so the
	sheet's `Selected row` rule never fires; and a row with a check draws its label
	into a CHILD `UI.Text`, which no `TextButton`-scoped colour rule can reach even
	when it does. So the label kept `$Content` — the colour chosen to read on the
	PAGE — and sat on the selection blue.

	THE MEASUREMENT IS OF THE SHIPPED ROW, not of the constants. Both colours are
	read off the nodes the picker actually mounted: the `Fill` Box's own `tint`
	role, and the chosen row's `Label` tint role, each resolved through the theme
	the package publishes. `onSelected` is resolved by
	`sheet_model.selectedContentColor`, which is the framework's own decision for
	that exact fill, so this asks the PAINT rather than restating a table.

	Every theme of every shipped package, because a package may publish several. ]]
local tokens = require("../src/tokens/tokens")
local sheet_model = require("../src/tokens/sheet_model")
local snapshot = require("../src/themes/snapshot")

local CONTRAST_FLOOR = 4.5
local SHIPPED = {
	"classic_desktop",
	"compact_pointer",
	"fantasy_ornate",
	"fantasy_parchment",
	"glossy_mobile",
	"glossy_touch",
	"pixel_quest",
	"scifi_hud",
}

local function readFact(value: any): any
	if type(value) == "table" and (value.kind == "signal" or value.kind == "memo") then
		return value:get()
	end
	return value
end

-- the palette colour a tint role names, for exactly the two roles this row
-- paints with. An unknown role is an error rather than a default: a silent
-- fallback here would measure the wrong pair and pass.
local function roleColor(theme: any, role: string): any
	if role == "controlSelected" then
		return sheet_model.selectedSurfaceOf(theme)
	elseif role == "onSelected" then
		return sheet_model.selectedContentColor(theme)
	elseif role == "content" then
		return theme.colors.content
	end
	error(`picker_style: no palette colour for tint role '{tostring(role)}'`, 0)
end

describe("Picker menu: the chosen row is readable on its own selection fill", function()
	it("every shipped theme clears 4.5:1 between the chosen row's label and its fill", function()
		local measured = 0
		for _, name in SHIPPED do
			local pkg = (require)(`../examples/themes/{name}`).build(Facet.themes)
			for _, theme in pkg.style.themes do
				local w = world.new({
					viewport = FACTS.phone.viewport,
					capabilities = FACTS.phone.capabilities,
					preferredInput = FACTS.phone.preferredInput,
					themeMetrics = snapshot.resolve(pkg, theme.name, {}),
				})
				local picker = Facet.Controls.Picker(w.core, {
					id = "P",
					label = "Quality",
					style = "menu",
					selected = w.core:signal("normal"),
					options = THREE,
				})
				w.present(UI.Screen({ id = "S", children = { picker.blueprint } }))
				w.pres.refresh()
				picker.api.open()
				w.pres.refresh()
				w.pres.refresh()
				local fillNode, labelNode
				for _, path in w.adapter.paths() do
					if string.find(path, "Opt%-normal", 1) == nil then
						continue
					end
					if string.sub(path, -5) == "/Fill" then
						fillNode = w.adapter.node(path)
					elseif string.sub(path, -6) == "/Label" then
						labelNode = w.adapter.node(path)
					end
				end
				local row = `[{name}/{theme.name}]`
				expect(`{row} the chosen row has a fill and a label: {fillNode ~= nil and labelNode ~= nil}`).toBe(
					`{row} the chosen row has a fill and a label: true`
				)
				local fillTint = readFact((fillNode :: any).props.tint)
				local labelTint = readFact((labelNode :: any).props.tint)
				expect(`{row} the fill is the selection wash: {type(fillTint) == "table" and fillTint.role}`).toBe(
					`{row} the fill is the selection wash: controlSelected`
				)
				local labelRole = if type(labelTint) == "table" and labelTint.role ~= nil
					then labelTint.role
					else "content"
				local ratio = tokens.contrastRatio(roleColor(theme, labelRole), roleColor(theme, fillTint.role))
				local reported = math.floor(ratio * 100 + 0.5) / 100
				expect(`{row} label '{labelRole}' on the fill: {ratio >= CONTRAST_FLOOR} ({reported}:1)`).toBe(
					`{row} label '{labelRole}' on the fill: true ({reported}:1)`
				)
				measured += 1
				picker.dispose()
				w.pres.dismiss(w.handle)
			end
		end
		expect(`themes measured: {measured >= #SHIPPED}`).toBe("themes measured: true")
	end)
end)
