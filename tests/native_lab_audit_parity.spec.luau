--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local worlds = require("./lib/content_world")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose
local themes = Facet.themes

local function package(name: string): any
	if name == "neutral" then
		return themes.neutralPackage()
	end
	local module: any = (require :: any)("../examples/themes/" .. name)
	return module.build(themes)
end

local function tall(node: any): number
	local floor = node:FindFirstChildWhichIsA("UISizeConstraint")
	return math.max(node.Size.Y.Offset, if floor then floor.MinSize.Y else 0)
end

local function tagged(root: any, tag: string): { any }
	local found = {}
	for _, node in root:GetDescendants() do
		if node:HasTag(tag) then
			table.insert(found, node)
		end
	end
	return found
end

local function sheetFor(theme: any): (any, () -> ())
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local sheet
	local stop = runtime.mount(function()
		sheet = themes.createStyleSheet(runtime, theme, { types = engine.types })
		return sheet
	end, engine.new("Folder"))
	return sheet, stop
end

local function rule(sheet: any, selector: string): any?
	for _, node in sheet:GetChildren() do
		if node.Selector == selector then
			return node
		end
	end
	return nil
end

t.describe("native lab audit: menu submenu rows", function()
	t.it("a submenu row shows its chevron beside a shortcut row, and the shortcut row shows none", function()
		local opened = Compose.cell(false)
		local w = worlds.new(function(UI)
			return UI.Menu({
				isPresented = opened,
				items = {
					{ id = "copy", label = "Copy", shortcutLabel = "Ctrl+C", onSelect = function() end },
					{
						id = "share",
						label = "Share",
						children = { { id = "mail", label = "Mail", onSelect = function() end } },
					},
				},
			})
		end)
		opened:set(true)
		local share, copy = w.find("share"), w.find("copy")
		t.expect(share ~= nil and copy ~= nil).toBe(true)
		t.expect(w.find("TrailingIcon", share) ~= nil).toBe(true)
		t.expect(w.find("TrailingIcon", copy)).toBe(nil)
		t.expect(#w.findAll("TrailingIcon", w.screen)).toBe(1)
		w.stop()
	end)
end)

t.describe("native lab audit: Slider rung thumb and track floor", function()
	local function cell(axis: string, size: string?): (any, number)
		local w = worlds.new(function(UI, Host, engine)
			return Host.Frame({
				Name = "Cell",
				AutomaticSize = engine.types.Enum.AutomaticSize.XY,
				UI.Slider("Vol")({
					label = "Vol",
					value = Compose.cell(50),
					min = 0,
					max = 100,
					axis = axis,
					controlSize = size,
					onChange = function() end,
				}),
			})
		end)
		local thumbs = tagged(w.screen, "facet-slider-thumb")
		t.expect(#thumbs >= 1).toBe(true)
		return w, thumbs[1].Size.X.Offset
	end
	for _, axis in { "x", "y" } do
		t.it(`axis {axis}: the track keeps one target of travel in a hugging cell`, function()
			local w = cell(axis, nil)
			local floor = w.find("Track"):FindFirstChildWhichIsA("UISizeConstraint")
			t.expect(floor ~= nil).toBe(true)
			t.expect(if axis == "y" then floor.MinSize.Y else floor.MinSize.X).toBe(44)
			w.stop()
		end)
	end
	t.it("compact and large thumbs differ, and regular is the theme's thumb", function()
		local sizes: { [string]: number } = {}
		for _, rung in { "compact", "regular", "large", "none" } do
			local w, size = cell("y", if rung == "none" then nil else rung)
			sizes[rung] = size
			w.stop()
		end
		t.expect(sizes.compact < sizes.regular and sizes.regular < sizes.large).toBe(true)
		t.expect(sizes.regular).toBe(sizes.none)
	end)
end)

t.describe("native lab audit: ProgressView rungs", function()
	t.it("a bar spends its rung on track thickness: small rungs thin, regular and large the theme track", function()
		for rung, px in { xsmall = 4, compact = 4, regular = 6, large = 6, none = 6 } :: { [string]: number } do
			local w = worlds.new(function(UI)
				return UI.ProgressView("P")({ value = 0.5, controlSize = if rung == "none" then nil else rung })
			end)
			t.expect(`{rung}={w.find("Track").Size.Y.Offset}`).toBe(`{rung}={px}`)
			w.stop()
		end
	end)
	t.it("a large ring shows its value in the gauge", function()
		local w = worlds.new(function(UI)
			return UI.ProgressView("P")({
				value = 0.65,
				presentation = "circular",
				showValue = true,
				controlSize = "large",
				format = function(value: number): string
					return tostring(value)
				end,
			})
		end)
		local value = w.find("Value", w.find("Gauge"))
		t.expect(value ~= nil).toBe(true)
		t.expect(value.Text).toBe("0.65")
		w.stop()
	end)
	t.it("refuses a bar rung with a thickness", function()
		local ok, err = pcall(function()
			worlds.new(function(UI)
				return UI.ProgressView("P")({ value = 0.5, controlSize = "compact", thickness = 8 })
			end)
		end)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "not both", 1, true) ~= nil).toBe(true)
		for _, spec in
			{
				{ presentation = "circular", value = 0.5, diameter = 64, controlSize = "regular" },
				{ presentation = "spinner", controlSize = "huge" },
				{ value = 0.5, endLabel = 7 },
				{ value = 0.5, endLabel = Compose.cell(7 :: any) },
			} :: { { [string]: any } }
		do
			t.expect(worlds.mountError(function(UI)
				return UI.ProgressView("P")(spec)
			end) ~= nil).toBe(true)
		end
		t.expect(worlds.mountError(function(UI)
			return UI.ProgressView("P")({ value = 0.5, endLabel = "Done" })
		end)).toBeNil()
	end)
end)

t.describe("native lab audit: Vote and one rung plate height", function()
	t.it("a readOnly vote keeps the interactive strip's rung height", function()
		local heights: { [string]: number } = {}
		for _, readOnly in { false, true } do
			for _, rung in { "compact", "large" } do
				local w = worlds.new(function(UI)
					return UI.Vote("V")({
						value = "up",
						readOnly = readOnly,
						controlSize = rung,
						onChange = function() end,
					})
				end)
				heights[`{readOnly}/{rung}`] = tall(w.find("Opt1", w.find("V")))
				w.stop()
			end
		end
		t.expect(heights["true/compact"]).toBe(heights["false/compact"])
		t.expect(heights["true/large"]).toBe(heights["false/large"])
		t.expect(heights["true/compact"] < heights["true/large"]).toBe(true)
	end)
	for _, name in
		{
			"neutral",
			"classic_desktop",
			"compact_pointer",
			"fantasy_ornate",
			"fantasy_parchment",
			"glossy_mobile",
			"glossy_touch",
			"pixel_quest",
			"scifi_hud",
		}
	do
		t.it(`{name}: a Button, the segmented track and a checkbox land on one rung height`, function()
			local boxes: { number } = {}
			for _, rung in { "xsmall", "compact", "regular", "large" } do
				local options = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } }
				local w = worlds.new(function(UI, Host)
					return Host.Frame({
						Name = "Row",
						UI.Button("B")({ label = "Settings", controlSize = rung }),
						UI.Picker("PM")({
							label = "Theme:",
							style = "menu",
							controlSize = rung,
							selected = Compose.cell("a"),
							options = options,
						}),
						UI.Picker("PS")({
							style = "segmented",
							controlSize = rung,
							selected = Compose.cell("a"),
							options = options,
						}),
						UI.TextInput("TI")({ value = Compose.cell("x"), controlSize = rung }),
						UI.Toggle("TK")({
							label = "Motion",
							presentation = "checkbox",
							controlSize = rung,
							value = Compose.cell(false),
						}),
						UI.Toggle("TC")({
							label = "Reduced Motion",
							presentation = "checkbox",
							appearance = "plain",
							controlSize = rung,
							value = Compose.cell(false),
						}),
						UI.Toggle("TS")({ label = "Music", controlSize = rung, value = Compose.cell(false) }),
					})
				end, { theme = package(name) })
				local button = w.find("B").Size.Y.Offset
				t.expect(`{rung} {button > 0}`).toBe(`{rung} true`)
				local plated = {
					menu = w.find("Trigger", w.find("PM")),
					segmented = w.find("PS"),
					field = w.find("Input", w.find("TI")),
					checkbox = w.find("TK"),
				}
				for key, node in plated do
					t.expect(`{rung} {key} {node.Size.Y.Offset}`).toBe(`{rung} {key} {button}`)
				end
				for _, key in { "TC", "TS" } do
					t.expect(`{rung} {key} {w.find(key).Size.Y.Offset <= button}`).toBe(`{rung} {key} true`)
				end
				local box = w.find("Indicator", w.find("TC")).Size
				t.expect(`{rung} {box.X.Offset == box.Y.Offset and box.Y.Offset <= button}`).toBe(`{rung} true`)
				table.insert(boxes, box.Y.Offset)
				w.stop()
			end
			t.expect(boxes[1] <= boxes[2] and boxes[2] <= boxes[3] and boxes[3] <= boxes[4]).toBe(true)
			t.expect(boxes[1] < boxes[4]).toBe(true)
		end)
	end
end)

t.describe("native lab audit: Badge status mark", function()
	t.it("the status mark has no page-colour ring and reads against the badge plate", function()
		for _, name in { "neutral", "pixel_quest", "fantasy_ornate" } do
			for _, status in { "warning", "error", "accent", "neutral" } do
				local w = worlds.new(function(UI)
					return UI.Badge("B")({ label = "Ready", appearance = "status", status = status })
				end, { theme = package(name) })
				t.expect(w.find("Status") ~= nil).toBe(true)
				t.expect(w.find("Cutout")).toBe(nil)
				t.expect(#tagged(w.screen, "facet-cutout")).toBe(0)
				w.stop()
			end
			local sheet, stop = sheetFor(package(name))
			local plate = assert(rule(sheet, ".facet-badge-status")):GetProperties().BackgroundColor3
			for _, status in { "warning", "error", "accent", "neutral" } do
				local mark = assert(rule(sheet, ".facet-status-" .. status)):GetProperties().BackgroundColor3
				t.expect(`{name} {status} {mark == plate}`).toBe(`{name} {status} false`)
			end
			stop()
		end
	end)
	t.it("an unplated utility badge draws no status mark", function()
		local w = worlds.new(function(UI)
			return UI.Badge("B")({ label = "Ready", appearance = "utility", status = "success" })
		end)
		t.expect(w.find("Status")).toBe(nil)
		w.stop()
	end)
end)

t.describe("native lab audit: ShortcutHint keycap outline", function()
	t.it("the keycap stroke is a theme metric: Neutral the hairline, 0 draws none", function()
		local neutral = themes.neutralPackage()
		local sheet, stop = sheetFor(neutral)
		local stroke = assert(rule(sheet, ".facet-shortcut-hint::UIStroke")):GetProperties()
		t.expect(stroke.Thickness).toBe(neutral.metrics.strokes.hairline)
		stop()
		for thickness, expected in { [0] = false, [2] = true } :: { [number]: boolean } do
			local soft, report = themes.define({
				base = themes.neutralPackage(),
				identity = { id = "soft", displayName = "Soft", schemaVersion = themes.SCHEMA, version = "1.0.0" },
				metrics = { controls = { shortcutHint = { capStroke = thickness, capGap = 2 } } },
			} :: any)
			assert(soft ~= nil, tostring(report.errors[1] and report.errors[1].message))
			local other, done = sheetFor(soft)
			local found = rule(other, ".facet-shortcut-hint::UIStroke")
			t.expect(found ~= nil).toBe(expected)
			if found then
				t.expect(found:GetProperties().Thickness).toBe(thickness)
			end
			done()
		end
	end)
end)

t.describe("native lab audit: StepIndicator rung marker", function()
	t.it("the rung sizes the step marker, and regular is the theme's medium icon", function()
		local sizes: { [string]: number } = {}
		for _, rung in { "compact", "regular", "large", "none" } do
			local w = worlds.new(function(UI)
				return UI.StepIndicator("S")({
					steps = {
						{ id = "cart", label = "Cart" },
						{ id = "pay", label = "Pay" },
						{ id = "ship", label = "Ship" },
					},
					current = "ship",
					controlSize = if rung == "none" then nil else rung,
				})
			end)
			sizes[rung] = w.find("Cue").Size.Y.Offset
			w.stop()
		end
		t.expect(sizes.compact <= sizes.regular and sizes.regular < sizes.large).toBe(true)
		t.expect(sizes.regular).toBe(sizes.none)
	end)
end)

t.describe("native lab audit: Notice plate carve", function()
	t.it("an art theme's panel carve pads the standard plate; emphasis keeps the plain inset", function()
		for _, name in { "neutral", "pixel_quest", "fantasy_ornate", "glossy_mobile" } do
			local theme = package(name)
			local carve = ((theme.chrome or {}).panel or {}).contentInsets or {}
			for _, appearance in { "standard", "emphasis" } do
				local w = worlds.new(function(UI)
					return UI.Notice("Conn")({
						title = "Update available",
						message = "A new track pack is ready.",
						appearance = appearance,
						actions = { { id = "Install", label = "Install", onActivate = function() end } },
						onDismiss = function() end,
					})
				end, { theme = theme })
				local root = w.find("Conn")
				local padding = root:FindFirstChildWhichIsA("UIPadding")
				local want = if appearance == "emphasis" then 8 else math.max(8, carve.left or 0)
				t.expect(`{name} {appearance} {padding.PaddingLeft.Offset}`).toBe(`{name} {appearance} {want}`)
				local top = if appearance == "emphasis" then 8 else math.max(8, carve.top or 0)
				t.expect(`{name} {appearance} {padding.PaddingTop.Offset}`).toBe(`{name} {appearance} {top}`)
				local title = w.find("Title", root)
				t.expect(title.TextWrapped).toBe(true)
				w.stop()
			end
		end
	end)
end)
