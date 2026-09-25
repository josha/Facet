--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local Roblox = require("@lune/roblox")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose
local expect = t.expect
local Color3 = Roblox.Color3
local V2 = Roblox.Vector2.new
local BrickShim = {
	palette = function(index: number): any
		return Roblox.BrickColor.palette(index + 1)
	end,
}
local colorValue = require("../src/ui/color_value")({ Color3 = Color3, BrickColor = BrickShim :: any })

local function hex(c: any): string
	return if c == nil then "nil" else colorValue.hex(c)
end

local function deep(root: any, name: string): any
	if root.Name == name then
		return root
	end
	for _, child in root:GetChildren() do
		local found = deep(child, name)
		if found then
			return found
		end
	end
	return nil
end

local function under(root: any, path: string): any
	local at = root
	for name in string.gmatch(path, "[^/]+") do
		if at == nil then
			return nil
		end
		at = deep(at, name)
	end
	return at
end

local function caller(initial: any, accept: boolean?): (any, { any }, (any) -> ())
	local cell = Compose.cell(initial)
	local seen: { any } = {}
	return cell,
		seen,
		function(next: any)
			table.insert(seen, next)
			if accept ~= false then
				cell:set(next)
			end
		end
end

local function world(spec: any, options: any?): any
	local o = options or {}
	local engine: any = engineLib.new()
	local E = engine.types.Enum
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	if o.tenFoot then
		gui.IsTenFootInterface = function()
			return true
		end
	end
	local input = engine.new("UserInputService")
	input.PreferredInput = o.preferred or E.PreferredInput.KeyboardAndMouse
	local proxy = setmetatable({
		IsKeyDown = function()
			return false
		end,
		IsGamepadButtonDown = function()
			return false
		end,
		GetFocusedTextBox = function()
			return nil
		end,
	}, {
		__index = function(_, key)
			local value = input[key]
			if type(value) == "function" then
				return function(_, ...)
					return value(input, ...)
				end
			end
			return value
		end,
	})
	local types = table.clone(engine.types)
	types.BrickColor = BrickShim
	local UI: any = Facet.controls(
		runtime,
		{ types = types, services = { GuiService = gui, UserInputService = proxy }, guiService = gui } :: any
	)
	local target = engine.new("Folder")
	local Host = runtime.constructors
	local stop, screen = runtime.mount(function()
		return Host.ScreenGui({
			Host.Frame "Col" {
				if o.build then o.build(UI, Host) else UI.ColorPicker("P")(spec),
				UI.Button("Other")({ label = "Other" }),
			},
		})
	end, target)
	local w: any = { engine = engine, runtime = runtime, gui = gui, input = input, screen = screen, E = E, UI = UI }
	w.root = deep(screen, "P")
	function w.find(name: string): any
		return under(screen, name)
	end
	function w.attr(name: string): any
		return w.root:GetAttribute(name)
	end
	function w.hsv(): string
		return `{math.floor(w.attr("hue") + 0.5)},{math.floor(w.attr("saturation") + 0.5)},{math.floor(
			w.attr("brightness") + 0.5
		)}`
	end
	function w.open()
		w.find("Well").Activated.fire()
	end
	function w.cells(name: string?): { any }
		local grid = w.find(name or "Swatches")
		local out = {}
		for _, child in grid:GetChildren() do
			if child:IsA("GuiObject") then
				table.insert(out, child)
			end
		end
		table.sort(out, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		return out
	end
	function w.action(name: string): any
		for _, context in screen:GetChildren() do
			if context:IsA("InputContext") and context.Enabled then
				local found = context:FindFirstChild(name)
				if found then
					return found
				end
			end
		end
		return nil
	end
	function w.press(name: string, count: number?): number
		local pressed = 0
		for _ = 1, count or 1 do
			local found = w.action(name)
			if found then
				found.Pressed.fire()
				found.Released.fire()
				pressed += 1
			end
		end
		return pressed
	end
	function w.size(node: any, width: number, height: number, x: number?, y: number?)
		node.AbsoluteSize = V2(width, height)
		node.AbsolutePosition = V2(x or 0, y or 0)
	end
	function w.typeInto(field: any, text: string)
		field:CaptureFocus()
		field.Text = text
		field:ReleaseFocus(true)
	end
	function w.stop()
		stop()
		runtime.dispose()
	end
	return w
end

t.describe("native ColorPicker colour values", function()
	t.it("parses #RGB, #RRGGBB and #RRGGBBAA (only with alpha) and formats engine bytes uppercase", function()
		local c, a, why = colorValue.parseHex("#abc", false)
		expect(hex(c)).toBe("#AABBCC")
		expect(a).toBeNil()
		c, a = colorValue.parseHex("ff000080", true)
		expect(hex(c)).toBe("#FF0000")
		expect(math.floor((a :: number) * 255 + 0.5)).toBe(128)
		c, _, why = colorValue.parseHex("#ff000080", false)
		expect(c).toBeNil()
		expect(why ~= nil).toBe(true)
		for _, bad in { "", "#12", "#GGGGGG", " #ABCDEF", "#abcdef " } do
			expect(`{bad}:{tostring(colorValue.parseHex(bad, true))}`).toBe(`{bad}:nil`)
		end
		expect(colorValue.hex(Color3.new(0.5, 0.5, 0.5))).toBe("#808080")
		expect(colorValue.hex(Color3.new(1, 0, 0), 0)).toBe("#FF000000")
	end)

	t.it("keeps a grey's hue (and a black's saturation) through the engine conversion", function()
		local h = colorValue.hsvOf(Color3.new(0.5, 0.5, 0.5), { h = 0.5, s = 0.7, v = 1 })
		expect(h.h).toBe(0.5)
		expect(h.s).toBe(0)
		local b = colorValue.hsvOf(Color3.new(0, 0, 0), { h = 0.25, s = 0.7, v = 1 })
		expect(`{b.h},{b.s},{b.v}`).toBe("0.25,0.7,0")
		expect(#colorValue.standard()).toBe(48)
		expect(#colorValue.brick()).toBe(128)
	end)

	t.it("a saturation round trip through the Sliders tab returns to the hue the player set", function()
		local set = Color3.fromHSV(200 / 360, 1, 1)
		local cell, _, change = caller(set)
		local w = world({ value = cell, onChange = change, style = "inline", modes = { "sliders" } })
		w.gui.SelectedObject = w.find("Saturation/Track")
		expect(w.press("DecreaseArrow", 100)).toBe(100)
		expect(hex(cell:peek())).toBe("#FFFFFF")
		expect(math.floor(w.attr("hue") + 0.5)).toBe(200)
		w.press("IncreaseArrow", 100)
		expect(math.floor(w.attr("hue") + 0.5)).toBe(200)
		expect(hex(cell:peek())).toBe(hex(set))
		w.gui.SelectedObject = w.find("Brightness/Track")
		w.press("DecreaseArrow", 100)
		expect(hex(cell:peek())).toBe("#000000")
		w.press("IncreaseArrow", 100)
		expect(hex(cell:peek())).toBe(hex(set))
		w.stop()
	end)

	t.it("the readout format segments fill a fixed row height, so the row cannot grow with its own segments", function()
		local cell, _, change = caller(Color3.new(1, 0, 0))
		local w = world({ value = cell, onChange = change, style = "inline", modes = { "sliders" } })
		local format = w.find("Format")
		expect(format.AutomaticSize.Name).toBe("X")
		expect(format.Size.Y.Scale).toBe(0)
		expect(format.Size.Y.Offset >= 44).toBe(true)
		local segment = w.find("Format/hex")
		expect(segment.Size.Y.Scale).toBe(1)
		w.stop()
	end)

	t.it("switching the readout twenty times never moves canonical, and a hex commit is the only write", function()
		local start = Color3.fromHSV(0.61, 0.37, 0.83)
		local cell, seen, change = caller(start)
		local w = world({ value = cell, onChange = change, style = "inline", modes = { "sliders" } })
		local before = `{w.attr("hue")},{w.attr("saturation")},{w.attr("brightness")}`
		for _ = 1, 20 do
			for _, word in { "hsv", "hex", "rgb" } do
				w.find("Format/" .. word).Activated.fire()
			end
		end
		expect(`{w.attr("hue")},{w.attr("saturation")},{w.attr("brightness")}`).toBe(before)
		expect(#seen).toBe(0)
		w.find("Format/hex").Activated.fire()
		expect(w.attr("format")).toBe("hex")
		local field = w.find("FieldHex/Field")
		w.typeInto(field, "#zz0")
		expect(#seen).toBe(0)
		expect(w.attr("hexError") ~= "").toBe(true)
		expect(field.Text).toBe("#zz0")
		expect(w.find("FieldHex/Validation").Text).toBe(w.attr("hexError"))
		w.typeInto(field, "#0f0")
		expect(hex(cell:peek())).toBe("#00FF00")
		expect(w.attr("hexError")).toBe("")
		expect(field.Text).toBe("#00FF00")
		w.stop()
	end)
end)

t.describe("native ColorPicker well and panel", function()
	t.it("a bare well is its swatch, named by its value; a labelled one is a form row", function()
		local cell, _, change = caller(Color3.fromRGB(255, 0, 0))
		local w = world({ value = cell, onChange = change })
		local well = w.find("Well")
		expect(well:GetAttribute("label")).toBe("#FF0000")
		expect(w.find("Well/Chevron")).toBeNil()
		expect(hex(w.find("Well/Swatch/Plate").BackgroundColor3)).toBe("#FF0000")
		expect(`{well.Size.X.Offset}x{well.Size.Y.Offset}`).toBe("44x44")
		expect(well:HasTag("facet-appearance-utility")).toBe(true)
		expect(w.root:HasTag("facet-color-picker")).toBe(true)
		expect(w.find("Well/Swatch"):HasTag("facet-color-swatch")).toBe(true)
		w.stop()
		local w2 = world({ value = cell, onChange = change, label = "Kart body", hint = "On the track" })
		expect(w2.find("Well"):GetAttribute("label")).toBe("Kart body, #FF0000")
		expect(w2.find("Well/Chevron") ~= nil).toBe(true)
		expect(w2.find("Well/Title").Text).toBe("Kart body")
		expect(w2.find("Well/Value").Text).toBe("#FF0000")
		expect(w2.find("Well"):HasTag("facet-field")).toBe(true)
		expect(w2.find("P/Message/Validation").Text).toBe("On the track")
		expect(w2.find("Well").Size.X.Scale).toBe(1)
		w2.stop()
	end)

	t.it("the well opens an anchored panel on a roomy pointer screen; a refused swatch never paints", function()
		local cell, seen, change = caller(Color3.fromRGB(255, 0, 0), false)
		local w = world({ value = cell, onChange = change })
		w.size(w.screen, 900, 900)
		w.size(w.find("Well"), 44, 44)
		w.open()
		expect(w.attr("presented")).toBe(true)
		expect(w.attr("placement")).toBe("bottom")
		local panel = w.find("Panel")
		expect(panel:HasTag("facet-panel")).toBe(true)
		expect(panel.Position.Y.Offset).toBe(48)
		local cells = w.cells()
		expect(#cells).toBe(48)
		local held = w.hsv()
		cells[20].Activated.fire()
		expect(#seen).toBe(1)
		expect(w.hsv()).toBe(held)
		expect(hex(cell:peek())).toBe("#FF0000")
		expect(hex(w.find("Well/Swatch/Plate").BackgroundColor3)).toBe("#FF0000")
		expect(hex(w.find("Readout/Preview/Plate").BackgroundColor3)).toBe("#FF0000")
		expect(cells[20]:GetAttribute("selected")).toBe(false)
		w.stop()
	end)

	t.it("the panel never covers its well: below, else above, else beside, else shrunk", function()
		local function place(label: string?, screenHeight: number, wellY: number, wellWidth: number): any
			local cell, _, change = caller(Color3.fromRGB(46, 125, 255))
			local w = world({ value = cell, onChange = change, label = label, modes = { "swatches", "brick" } })
			w.size(w.screen, 1542, screenHeight)
			w.size(w.find("Well"), wellWidth, 44, 0, wellY)
			w.open()
			w.size(w.find("Modes"), 404, 44)
			w.size(w.find("Readout"), 404, 140)
			w.size(w.find("ShowSwatches"), 380, 290)
			w.size(w.find("ShowBricks"), 380, 800)
			local panel = w.find("Panel")
			local x, y = panel.Position.X.Offset, panel.Position.Y.Offset
			local pw, ph = panel.Size.X.Offset, panel.Size.Y.Offset
			local covers = x < wellWidth and x + pw > 0 and y < wellY + 44 and y + ph > wellY
			local inside = y >= 0 and y + ph <= screenHeight
			local body = w.find("Body").Size.Y.Offset
			local out =
				{ text = `covers={covers} inside={inside} edge={w.attr("placement")}`, height = ph, body = body }
			w.stop()
			return out
		end
		local natural = 44 + 140 + 800 + 2 * 8 + 2 * 12
		expect(place("Kart body", 1300, 0, 1542).text).toBe("covers=false inside=true edge=bottom")
		expect(place("Kart body", 1300, 1200, 1542).text).toBe("covers=false inside=true edge=top")
		local beside = place(nil, 560, 120, 44)
		expect(beside.text).toBe("covers=false inside=true edge=right")
		local shrunk = place("Kart body", 560, 120, 1542)
		expect(shrunk.text).toBe("covers=false inside=true edge=bottom")
		expect(`beside taller {beside.height > shrunk.height}`).toBe("beside taller true")
		expect(shrunk.height < natural).toBe(true)
		expect(shrunk.body).toBe(shrunk.height - (natural - 800))
	end)

	t.it("the panel keeps one height across every technique, on a pointer panel and a phone sheet", function()
		for _, case in
			{
				{ touch = false, w = 900, h = 900, modes = { "swatches", "spectrum", "sliders", "brick" } },
				{ touch = true, w = 390, h = 844, modes = { "swatches", "spectrum", "sliders" } },
			}
		do
			local cell, _, change = caller(Color3.fromRGB(46, 125, 255))
			local probe = world({ value = cell, onChange = change, modes = case.modes })
			local E = probe.E
			probe.stop()
			local w = world(
				{ value = cell, onChange = change, modes = case.modes },
				{ preferred = if case.touch then E.PreferredInput.Touch else nil }
			)
			w.size(w.screen, case.w, case.h)
			w.size(w.find("Well"), 44, 44)
			w.open()
			expect(w.attr("placement")).toBe(if case.touch then "sheet" else "bottom")
			local heights = { 180, 300, 240, 500 }
			for index, mode in case.modes do
				local label = ({ swatches = "Swatches", spectrum = "Spectrum", sliders = "Sliders", brick = "Bricks" })[mode]
				w.size(w.find("Show" .. label), 300, heights[index])
			end
			local tallest = 0
			for index = 1, #case.modes do
				tallest = math.max(tallest, heights[index])
			end
			local seen: { string } = {}
			for _, mode in case.modes do
				w.find("Modes/" .. mode).Activated.fire()
				expect(w.attr("mode")).toBe(mode)
				table.insert(seen, `{w.find("Technique").Size.Y.Offset}/{w.find("Body").Size.Y.Offset}`)
			end
			for index = 2, #seen do
				expect(`{case.w} {seen[index]}`).toBe(`{case.w} {seen[1]}`)
			end
			expect(w.find("Technique").Size.Y.Offset).toBe(tallest)
			w.stop()
		end
	end)

	t.it("the panel's height follows its room, never a height it once measured", function()
		local cell, _, change = caller(Color3.fromRGB(46, 125, 255))
		local modes = { "swatches", "spectrum", "sliders", "brick" }
		local w = world({ value = cell, onChange = change, modes = modes })
		w.size(w.screen, 900, 900)
		w.size(w.find("Well"), 44, 44)
		w.open()
		w.size(w.find("Modes"), 404, 44)
		w.size(w.find("Readout"), 404, 140)
		w.size(w.find("ShowSwatches"), 380, 290)
		w.size(w.find("ShowBricks"), 380, 600)
		local function height(): number
			return w.find("Body").Size.Y.Offset
		end
		local before = height()
		expect(before).toBe(600)
		w.size(w.screen, 900, 420)
		expect(height() < before).toBe(true)
		w.size(w.screen, 900, 900)
		for _, mode in modes do
			w.find("Modes/" .. mode).Activated.fire()
			expect(`{mode} {height()}`).toBe(`{mode} {before}`)
		end
		w.stop()
	end)

	t.it("an accepted swatch commits once, marks the cell, and the swatch grid lays out rows of eight", function()
		local cell, _, change = caller(Color3.fromRGB(255, 0, 0))
		local commits = {}
		local w = world({
			value = cell,
			onChange = change,
			onCommit = function(c: any)
				table.insert(commits, hex(c))
			end,
		})
		w.open()
		local cells = w.cells()
		expect(w.attr("columns")).toBe(8)
		cells[3].Activated.fire()
		local chosen = hex(cell:peek())
		expect(table.concat(commits, ",")).toBe(chosen)
		expect(cells[3]:FindFirstChild("Check").Visible).toBe(true)
		expect(cells[3]:GetAttribute("selected")).toBe(true)
		expect(cells[4]:FindFirstChild("Check").Visible).toBe(false)
		local grid = w.find("Swatches")
		expect(grid.Size.X.Offset).toBe(8 * 44 + 7 * 4)
		local layout = grid:FindFirstChildWhichIsA("UIListLayout")
		expect(`{layout.Wraps} {layout.FillDirection.Name} {layout.Padding.Offset}`).toBe("true Horizontal 4")
		for index, node in cells do
			expect(node.LayoutOrder).toBe(index)
			expect(node.Selectable).toBe(true)
		end
		w.size(w.find("Technique"), 300, 0)
		expect(w.attr("columns")).toBe(6)
		expect(#w.cells()).toBe(36)
		w.stop()
	end)

	t.it(
		"saved colours: + proposes the current colour once; Edit removes by activate or Delete and hands the ring on",
		function()
			local cell, _, change = caller(Color3.fromRGB(10, 200, 30))
			local list = Compose.cell({ Color3.fromRGB(255, 0, 0), Color3.fromRGB(0, 0, 255) } :: { any })
			local saved, removed = {}, {}
			local w = world({
				value = cell,
				onChange = change,
				swatches = list,
				onSaveSwatch = function(c: any)
					table.insert(saved, hex(c))
					local nextList = table.clone(list:peek())
					table.insert(nextList, c)
					list:set(nextList)
				end,
				onRemoveSwatch = function(item: any)
					table.insert(removed, item.key)
					local nextList = {}
					for _, c in list:peek() do
						if hex(c) ~= item.key then
							table.insert(nextList, c)
						end
					end
					list:set(nextList)
				end,
			})
			w.open()
			local cells = w.cells()
			local plus = cells[#cells]
			expect(plus.Name).toBe("Save")
			expect(plus:GetAttribute("label")).toBe("Save colour")
			expect(plus:FindFirstChild("Plus") ~= nil).toBe(true)
			plus.Activated.fire()
			w.cells()[4].Activated.fire()
			expect(table.concat(saved, ",")).toBe("#0AC81E")
			expect(#w.cells()).toBe(4)
			expect(w.cells()[4].Interactable).toBe(false)
			w.find("Saved/Edit").Activated.fire()
			expect(w.find("Saved/Edit").Text).toBe("Done")
			local first = w.cells()[1]
			expect(first:FindFirstChild("Remove").Visible).toBe(true)
			expect(first:GetAttribute("label")).toBe("Remove #FF0000")
			first.Activated.fire()
			expect(table.concat(removed, ",")).toBe("#FF0000")
			expect(hex(cell:peek())).toBe("#0AC81E")
			w.gui.SelectedObject = w.cells()[1]
			expect(w.press("ColorSwatchRemove")).toBe(1)
			expect(table.concat(removed, ",")).toBe("#FF0000,#0000FF")
			expect(w.gui.SelectedObject).toBe(w.cells()[1])
			local keys = {}
			for _, binding in w.action("ColorSwatchRemove"):GetChildren() do
				table.insert(keys, binding.KeyCode.Name)
			end
			table.sort(keys)
			expect(table.concat(keys, " ")).toBe("Backspace ButtonX Delete")
			w.find("Saved/Edit").Activated.fire()
			expect(w.action("ColorSwatchRemove")).toBeNil()
			w.cells()[1].Activated.fire()
			expect(#removed).toBe(2)
			w.stop()
		end
	)

	t.it("refuses a saved-colour callback that is not a function", function()
		local cell, _, change = caller(Color3.fromRGB(0, 0, 0))
		local ok, why = pcall(function()
			world({ value = cell, onChange = change, onSaveSwatch = true })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(why), "onSaveSwatch", 1, true) ~= nil).toBe(true)
	end)

	t.it("a short swatch list keeps square target cells, and the default grid stays a hue per column", function()
		local cell, _, change = caller(Color3.fromRGB(255, 196, 0))
		local w = world({
			value = cell,
			onChange = change,
			swatches = { { color = Color3.fromRGB(255, 196, 0) }, { color = Color3.fromRGB(20, 20, 24) } },
		})
		w.open()
		local cells = w.cells()
		expect(#cells).toBe(2)
		for _, node in cells do
			expect(`{node.Size.X.Offset}x{node.Size.Y.Offset} {node.AutomaticSize.Name}`).toBe("44x44 None")
		end
		expect(w.find("Swatches").Size.X.Offset).toBe(2 * 44 + 4)
		w.stop()
		local seven = colorValue.standard(7)
		expect(#seven).toBe(42)
		for column = 1, 7 do
			local hues = {}
			for row = 0, 4 do
				local h = colorValue.hsvOf(seven[row * 7 + column].color).h
				hues[math.floor(h * 360 + 0.5)] = true
			end
			local distinct = 0
			for _ in hues do
				distinct += 1
			end
			expect(distinct).toBe(1)
		end
	end)

	t.it("without draft every change commits live and B or an outside tap only closes, keeping it", function()
		local startColor = Color3.fromRGB(10, 20, 30)
		local cell, _, change = caller(startColor)
		local reasons, commits = {}, {}
		local w = world({
			value = cell,
			onChange = change,
			onCommit = function(c: any)
				table.insert(commits, hex(c))
			end,
			onDismiss = function(r: string)
				table.insert(reasons, r)
			end,
		})
		w.open()
		w.cells()[5].Activated.fire()
		local picked = hex(cell:peek())
		expect(picked ~= hex(startColor)).toBe(true)
		expect(w.press("ModalBack")).toBe(1)
		expect(w.attr("presented")).toBe(false)
		expect(w.find("Panel")).toBeNil()
		expect(hex(cell:peek())).toBe(picked)
		expect(table.concat(commits, ",")).toBe(picked)
		w.open()
		w.cells()[6].Activated.fire()
		local kept = hex(cell:peek())
		w.find("DismissOutside").Activated.fire()
		expect(w.attr("presented")).toBe(false)
		expect(hex(cell:peek())).toBe(kept)
		expect(table.concat(reasons, ",")).toBe("cancel,outside")
		w.stop()
	end)

	t.it("draft: B and an outside tap discard, restoring the open-time colour; a caller write re-bases it", function()
		local startColor = Color3.fromRGB(10, 20, 30)
		local cell, seen, change = caller(startColor)
		local w = world({ value = cell, onChange = change, draft = true })
		w.open()
		w.cells()[5].Activated.fire()
		expect(hex(cell:peek()) ~= hex(startColor)).toBe(true)
		w.press("ModalBack")
		expect(hex(cell:peek())).toBe(hex(startColor))
		expect(hex(seen[#seen])).toBe(hex(startColor))
		w.open()
		w.cells()[6].Activated.fire()
		w.find("DismissOutside").Activated.fire()
		expect(hex(cell:peek())).toBe(hex(startColor))
		w.open()
		local server = Color3.fromRGB(200, 100, 50)
		cell:set(server)
		w.cells()[7].Activated.fire()
		expect(hex(cell:peek()) ~= hex(server)).toBe(true)
		w.press("ModalBack")
		expect(hex(cell:peek())).toBe(hex(server))
		w.stop()
	end)

	t.it("draft: gestures propose live but commit nothing; Apply commits once and Cancel restores", function()
		local startColor = Color3.fromRGB(10, 20, 30)
		local cell, _, change = caller(startColor)
		local commits, reasons = {}, {}
		local w = world({
			value = cell,
			onChange = change,
			draft = true,
			onCommit = function(c: any)
				table.insert(commits, hex(c))
			end,
			onDismiss = function(r: string)
				table.insert(reasons, r)
			end,
		})
		w.open()
		expect(w.find("Actions/Apply"):HasTag("facet-accent")).toBe(true)
		expect(w.find("Actions/Cancel"):HasTag("facet-accent")).toBe(false)
		expect(w.find("Actions").Visible).toBe(true)
		w.cells()[9].Activated.fire()
		expect(#commits).toBe(0)
		w.find("Actions/Cancel").Activated.fire()
		expect(hex(cell:peek())).toBe(hex(startColor))
		expect(#commits).toBe(0)
		w.open()
		w.cells()[9].Activated.fire()
		w.find("Actions/Apply").Activated.fire()
		expect(table.concat(commits, ",")).toBe(hex(cell:peek()))
		expect(w.attr("presented")).toBe(false)
		expect(table.concat(reasons, ",")).toBe("cancel,apply")
		w.stop()
	end)

	t.it(
		"opens as a sheet with Done on a compact touch screen, and a centred sheet at ten feet with the plane",
		function()
			local cell, _, change = caller(Color3.fromRGB(255, 0, 0))
			local probe = world({ value = cell, onChange = change })
			local Touch = probe.E.PreferredInput.Touch
			probe.stop()
			local w = world({ value = cell, onChange = change }, { preferred = Touch })
			w.size(w.screen, 390, 844)
			w.size(w.find("Well"), 44, 44)
			w.open()
			expect(w.attr("placement")).toBe("sheet")
			expect(w.find("Actions/Done") ~= nil).toBe(true)
			expect(w.find("Actions").Visible).toBe(true)
			expect(w.find("Close")).toBeNil()
			expect(w.find("DismissOutside").BackgroundTransparency < 1).toBe(true)
			local panel = w.find("Panel")
			expect(panel.Size.X.Offset).toBe(390 - 24)
			w.find("Modes/spectrum").Activated.fire()
			local surface = w.find("Plane/Surface")
			w.size(surface, 300, 176, 30, 200)
			local top = panel.Position.Y.Offset
			local v0 = w.attr("brightness")
			local drag = surface:FindFirstChildWhichIsA("UIDragDetector")
			drag.DragStart.fire(V2(180, 200 + 176 * 0.2))
			for step = 1, 10 do
				drag.DragContinue.fire(V2(180, 200 + 176 * (0.2 + step * 0.05)))
			end
			drag.DragEnd.fire()
			expect(w.attr("brightness") < v0 - 20).toBe(true)
			expect(panel.Position.Y.Offset).toBe(top)
			w.find("Actions/Done").Activated.fire()
			expect(w.attr("presented")).toBe(false)
			w.stop()
			local four = world(
				{ value = cell, onChange = change, modes = { "swatches", "spectrum", "sliders", "brick" } },
				{ preferred = Touch }
			)
			four.open()
			expect(four.find("Modes/brick") ~= nil).toBe(true)
			four.size(four.find("Modes"), 300, 44)
			expect(four.find("Modes") ~= nil).toBe(true)
			expect(four.find("Modes/brick")).toBeNil()
			four.stop()
			local tv = world(
				{ value = cell, onChange = change, modes = { "spectrum", "swatches" } },
				{ preferred = Touch, tenFoot = true }
			)
			tv.size(tv.screen, 1920, 1080)
			tv.open()
			expect(tv.attr("placement")).toBe("center")
			expect(tv.find("Plane/Surface") ~= nil).toBe(true)
			expect(tv.find("Actions").Visible).toBe(true)
			local tvPanel = tv.find("Panel")
			expect(tvPanel.Position.X.Offset * 2 + tvPanel.Size.X.Offset).toBe(1920)
			tv.stop()
		end
	)
end)

t.describe("native ColorPicker spectrum plane", function()
	local function spectrum(options: any?): (any, any, { string })
		local cell, _, change = caller(Color3.fromHSV(0.5, 0.5, 0.5))
		local commits = {}
		local w = world({
			value = cell,
			onChange = change,
			style = "inline",
			modes = { "spectrum" },
			onCommit = function(c: any)
				table.insert(commits, hex(c))
			end,
		}, options)
		w.size(w.find("Plane"), 200, 176, 0, 0)
		w.size(w.find("Plane/Surface"), 200, 176, 0, 0)
		return w, cell, commits
	end

	t.it("a drag tracks 1:1 in saturation and value, keeps the hue, and commits once at release", function()
		local w, cell, commits = spectrum()
		local drag = w.find("Plane/Surface"):FindFirstChildWhichIsA("UIDragDetector")
		expect(drag.ResponseStyle.Name).toBe("CustomOffset")
		drag.DragStart.fire(V2(50, 88))
		drag.DragContinue.fire(V2(150, 44))
		expect(w.hsv()).toBe("180,75,75")
		expect(#commits).toBe(0)
		drag.DragEnd.fire()
		expect(#commits).toBe(1)
		expect(commits[1]).toBe(hex(cell:peek()))
		local mark = w.find("Plane/Ring")
		expect(`{mark.Position.X.Offset},{mark.Position.Y.Offset}`).toBe("150,44")
		drag.DragStart.fire(V2(200, 0))
		drag.DragEnd.fire()
		expect(`{mark.Position.X.Offset},{mark.Position.Y.Offset}`).toBe("190,10")
		expect(`{mark.AnchorPoint.X},{mark.Size.X.Offset}`).toBe("0.5,20")
		w.stop()
	end)

	t.it("the native drag detector follows the plane through a tab round trip", function()
		local cell, _, change = caller(Color3.fromHSV(0.5, 0.5, 0.5))
		local w = world({ value = cell, onChange = change, style = "inline", modes = { "spectrum", "sliders" } })
		local surface = w.find("Plane/Surface")
		w.size(surface, 200, 176)
		local function driveTo(fx: number)
			local drag = w.find("Plane/Surface"):FindFirstChildWhichIsA("UIDragDetector")
			drag.DragStart.fire(V2(200 * fx, 88))
			drag.DragEnd.fire()
		end
		driveTo(0.2)
		expect(math.floor(w.attr("saturation") + 0.5)).toBe(20)
		w.find("Modes/sliders").Activated.fire()
		expect(w.find("ShowSpectrum").Visible).toBe(false)
		expect(w.find("ShowSliders").Visible).toBe(true)
		w.find("Modes/spectrum").Activated.fire()
		expect(w.find("Plane/Surface")).toBe(surface)
		driveTo(0.8)
		expect(math.floor(w.attr("saturation") + 0.5)).toBe(80)
		w.stop()
	end)

	t.it("losing the pointer class mid-drag restores where the drag began", function()
		local w, cell, commits = spectrum()
		local before = hex(cell:peek())
		local drag = w.find("Plane/Surface"):FindFirstChildWhichIsA("UIDragDetector")
		drag.DragStart.fire(V2(5, 5))
		expect(hex(cell:peek()) ~= before).toBe(true)
		w.input.PreferredInput = w.E.PreferredInput.Gamepad
		expect(hex(cell:peek())).toBe(before)
		drag.DragContinue.fire(V2(100, 100))
		drag.DragEnd.fire()
		expect(hex(cell:peek())).toBe(before)
		expect(#commits).toBe(0)
		w.stop()
	end)

	t.it("phone portrait and landscape: every target keeps the floor and Apply stays in the panel", function()
		local probe = world({ value = Compose.cell(Color3.new(1, 0, 0)), onChange = function() end })
		local Touch = probe.E.PreferredInput.Touch
		probe.stop()
		for _, view in { { w = 390, h = 844 }, { w = 844, h = 390 } } do
			for _, mode in { "swatches", "spectrum", "sliders", "brick" } do
				local cell, _, change = caller(Color3.fromRGB(46, 125, 255))
				local w = world(
					{ value = cell, onChange = change, draft = true, modes = { mode } },
					{ preferred = Touch }
				)
				w.size(w.screen, view.w, view.h)
				w.size(w.find("Well"), 44, 44)
				w.open()
				local where = `{view.w}x{view.h} {mode}`
				expect(`{where} {w.attr("placement")}`).toBe(`{where} {if view.h > view.w then "sheet" else "bottom"}`)
				expect(`{where} {w.find("Close")}`).toBe(`{where} nil`)
				local grid = if mode == "brick" then "BrickGrid" elseif mode == "swatches" then "Swatches" else nil
				if grid then
					for _, node in w.cells(grid) do
						expect(`{where} {node.Size.X.Offset >= 44 and node.Size.Y.Offset >= 44}`).toBe(`{where} true`)
					end
				end
				local apply = w.find("Actions/Apply")
				expect(`{where} {apply ~= nil} {apply:IsDescendantOf(w.find("Panel"))}`).toBe(`{where} true true`)
				expect(`{where} {w.find("Actions"):IsDescendantOf(w.find("Body"))}`).toBe(`{where} false`)
				w.stop()
			end
		end
	end)

	t.it("on touch the preview leads the panel, and a drag shows the colour in a bubble above the finger", function()
		local probe = world({ value = Compose.cell(Color3.new(1, 0, 0)), onChange = function() end })
		local E = probe.E
		probe.stop()
		local w, cell = spectrum({ preferred = E.PreferredInput.Touch })
		expect(w.find("Readout").LayoutOrder < w.find("Technique").LayoutOrder).toBe(true)
		local bubble = w.find("Plane/Bubble")
		expect(bubble.Visible).toBe(false)
		local drag = w.find("Plane/Surface"):FindFirstChildWhichIsA("UIDragDetector")
		drag.DragStart.fire(V2(100, 88))
		drag.DragContinue.fire(V2(120, 106))
		expect(bubble.Visible).toBe(true)
		expect(bubble.AnchorPoint.Y).toBe(1)
		expect(bubble.Position.Y.Offset < 106).toBe(true)
		expect(`{bubble.Position.X.Offset},{bubble.Position.Y.Offset}`).toBe("120,88")
		expect(hex(bubble.BackgroundColor3)).toBe(hex(cell:peek()))
		drag.DragContinue.fire(V2(100, 20))
		expect(bubble.Position.Y.Offset - 44 >= 0).toBe(true)
		expect(bubble.Position.X.Offset - 22 > 100 or bubble.Position.X.Offset + 22 < 100).toBe(true)
		drag.DragEnd.fire()
		expect(bubble.Visible).toBe(false)
		drag.DragStart.fire(V2(5, 170))
		expect(bubble.Visible).toBe(true)
		drag.DragEnd.fire()
		for _, point in { V2(0, 0), V2(40, 12), V2(100, 30), V2(160, 20), V2(200, 0), V2(200, 176), V2(0, 176) } do
			drag.DragStart.fire(point)
			local left = bubble.Position.X.Offset - 22
			local top = bubble.Position.Y.Offset - 44
			local inside = left >= 0 and top >= 0 and left + 44 <= 200 and top + 44 <= 176
			local ring = w.find("Plane/Ring")
			local rx, ry = ring.Position.X.Offset, ring.Position.Y.Offset
			local covers = rx > left - 10 and rx < left + 54 and ry > top - 10 and ry < top + 54
			expect(`{point} {inside} {covers}`).toBe(`{point} true false`)
			drag.DragEnd.fire()
		end
		drag.DragStart.fire(V2(5, 170))
		w.input.PreferredInput = E.PreferredInput.Gamepad
		expect(bubble.Visible).toBe(false)
		w.stop()
		local h = spectrum({ preferred = E.PreferredInput.Touch })
		local hueSlider = h.find("Spectrum"):FindFirstChild("Hue")
		local track = under(hueSlider, "Track")
		h.size(track, 200, 44)
		local hueBubble = under(hueSlider, "Mark/Bubble")
		expect(hueBubble.Visible).toBe(false)
		local hueDrag = track:FindFirstChildWhichIsA("UIDragDetector")
		hueDrag.DragStart.fire(V2(60, 22))
		hueDrag.DragContinue.fire(V2(80, 22))
		expect(hueBubble.Visible).toBe(true)
		expect(`{hueBubble.AnchorPoint.Y} {hueBubble.Position.Y.Offset}`).toBe("1 -8")
		expect(math.floor(h.attr("hue") + 0.5)).toBe(144)
		hueDrag.DragEnd.fire()
		expect(hueBubble.Visible).toBe(false)
		h.stop()
		local p = spectrum()
		local pointerDrag = p.find("Plane/Surface"):FindFirstChildWhichIsA("UIDragDetector")
		pointerDrag.DragStart.fire(V2(10, 10))
		expect(p.find("Plane/Bubble").Visible).toBe(false)
		expect(p.find("Readout").LayoutOrder > p.find("Technique").LayoutOrder).toBe(true)
		pointerDrag.DragEnd.fire()
		p.stop()
	end)

	t.it("the right stick steers the plane only while it holds focus, and a live hint says so", function()
		local probe = world({ value = Compose.cell(Color3.new(1, 0, 0)), onChange = function() end })
		local E = probe.E
		probe.stop()
		local w, cell, commits = spectrum({ preferred = E.PreferredInput.Gamepad })
		local surface = w.find("Plane/Surface")
		expect(surface.Selectable).toBe(true)
		expect(surface:GetAttribute("AccessibleLabel")).toBe("Saturation and brightness")
		local before = w.hsv()
		w.gui.SelectedObject = w.find("Other")
		expect(w.action("ColorPlaneSteer")).toBeNil()
		expect(w.find("StickHint").Visible).toBe(false)
		w.engine.heartbeat.fire(1)
		expect(w.hsv()).toBe(before)
		w.gui.SelectedObject = surface
		expect(w.find("StickHint").Visible).toBe(true)
		local steer = w.action("ColorPlaneSteer")
		expect(steer.Type.Name).toBe("Direction2D")
		expect(steer.Parent.Sink).toBe(true)
		expect(steer:FindFirstChildWhichIsA("InputBinding").KeyCode.Name).toBe("Thumbstick2")
		local s0 = w.attr("saturation")
		local v0 = w.attr("brightness")
		local listeners = w.engine.heartbeat.count()
		steer.StateChanged.fire(V2(1, 0))
		w.engine.heartbeat.fire(0.5)
		steer.StateChanged.fire(V2(0, 0))
		expect(w.attr("saturation") > s0 + 10).toBe(true)
		expect(math.floor(w.attr("brightness") + 0.5)).toBe(math.floor(v0 + 0.5))
		expect(#commits).toBe(1)
		for _ = 1, 5 do
			steer.StateChanged.fire(V2(0, 1))
			w.engine.heartbeat.fire(0.1)
			steer.StateChanged.fire(V2(0, 0))
		end
		expect(w.engine.heartbeat.count()).toBe(listeners)
		expect(#commits).toBe(6)
		steer.StateChanged.fire(V2(-1, 0))
		w.engine.heartbeat.fire(0.1)
		w.gui.SelectedObject = w.find("Other")
		expect(#commits).toBe(7)
		expect(commits[7]).toBe(hex(cell:peek()))
		expect(w.engine.heartbeat.count()).toBe(listeners)
		w.stop()
	end)
end)

t.describe("native ColorPicker composed in a screen", function()
	t.it("a committed line follows a commit, and a refusal changes nothing", function()
		local trim = Compose.cell(Color3.fromRGB(230, 57, 70))
		local committed = Compose.cell("nothing yet")
		local refuse = Compose.cell(false)
		local team = Compose.cell({
			{ color = Color3.fromRGB(230, 57, 70), label = "Red" },
			{ color = Color3.fromRGB(255, 196, 0), label = "Gold" },
			{ color = Color3.fromRGB(46, 125, 255), label = "Blue" },
			{ color = Color3.fromRGB(0, 170, 140), label = "Teal" },
		} :: { any })
		local w = world({}, {
			build = function(UI, Host)
				return Host.Frame "Pickers" {
					UI.ColorPicker("P")({
						label = "Trim",
						value = trim,
						swatches = team,
						onChange = function(c: any)
							if not refuse:peek() then
								trim:set(c)
							end
						end,
						onCommit = function(c: any)
							committed:set(hex(c))
						end,
						onSaveSwatch = function(c: any)
							local nextList = table.clone(team:peek())
							table.insert(nextList, c)
							team:set(nextList)
						end,
					}),
					Host.TextLabel "Committed" {
						Text = function(use)
							return "Committed: " .. use(committed)
						end,
					},
				}
			end,
		})
		local line = w.find("Committed")
		expect(line.Text).toBe("Committed: nothing yet")
		w.open()
		local cells = w.cells()
		expect(#cells).toBe(5)
		cells[4].Activated.fire()
		expect(line.Text).toBe("Committed: #00AA8C")
		expect(hex(w.find("Well/Swatch/Plate").BackgroundColor3)).toBe("#00AA8C")
		w.find("DismissOutside").Activated.fire()
		refuse:set(true)
		w.open()
		w.cells()[2].Activated.fire()
		expect(hex(w.find("Well/Swatch/Plate").BackgroundColor3)).toBe("#00AA8C")
		expect(line.Text).toBe("Committed: #00AA8C")
		w.stop()
	end)
end)

t.describe("native ColorPicker alpha, empty, disabled and refusals", function()
	t.it("alpha mounts opacity, writes #RRGGBBAA, and shows the checker under a translucent colour", function()
		local cell, _, change = caller(Color3.fromRGB(255, 0, 0))
		local a = Compose.cell(0.5)
		local w = world({
			value = cell,
			onChange = change,
			alpha = a,
			onAlphaChange = function(n: number)
				a:set(n)
			end,
			label = "Tint",
		})
		expect(w.find("Well/Value").Text).toBe("#FF000080")
		expect(w.find("Well/Swatch/Checker").Visible).toBe(true)
		expect(w.find("Well/Swatch/Plate").BackgroundTransparency).toBeCloseTo(0.5)
		w.open()
		local track = w.find("Opacity/Track")
		expect(track:GetAttribute("AccessibleLabel")).toBe("Opacity")
		w.gui.SelectedObject = track
		w.press("IncreaseArrow", 60)
		expect(a:peek()).toBe(1)
		expect(w.find("Well/Swatch/Checker").Visible).toBe(false)
		expect(w.find("Well/Value").Text).toBe("#FF0000")
		w.find("Format/hex").Activated.fire()
		expect(w.find("FieldHex/Field").Text).toBe("#FF0000FF")
		w.typeInto(w.find("FieldHex/Field"), "zz")
		expect(string.find(w.attr("hexError"), "#RRGGBBAA", 1, true) ~= nil).toBe(true)
		w.typeInto(w.find("FieldHex/Field"), "#00FF0040")
		expect(hex(cell:peek())).toBe("#00FF00")
		expect(math.floor(a:peek() * 255 + 0.5)).toBe(64)
		w.stop()
		local plain = world({ value = cell, onChange = change })
		plain.open()
		expect(plain.find("Opacity")).toBeNil()
		plain.stop()
	end)

	t.it("the Bricks tab names the chosen brick in a field above its grid", function()
		local cell, _, change = caller(Color3.fromRGB(255, 0, 0))
		local w = world({ value = cell, onChange = change, style = "inline", modes = { "brick" } })
		local cells = w.cells("BrickGrid")
		expect(#cells).toBe(128)
		cells[1].Activated.fire()
		local name = w.find("Brick/NameField/BrickName")
		expect(name.Text).toBe(cells[1].Name)
		expect(w.find("Brick/NameField").LayoutOrder < w.find("Brick/BrickGrid").LayoutOrder).toBe(true)
		expect(w.root:GetAttribute("text")).toBe(hex(cell:peek()))
		w.stop()
	end)

	t.it(
		"the plane is two exact layers, the strips show what they select, and the thumbs are two-tone rings",
		function()
			local cell, _, change = caller(Color3.fromRGB(46, 125, 255))
			local a = Compose.cell(1)
			local w = world({
				value = cell,
				onChange = change,
				style = "inline",
				modes = { "spectrum" },
				alpha = a,
				onAlphaChange = function(n: number)
					a:set(n)
				end,
			})
			local hue = w.find("Plane/Field/Hue/Gradient")
			local stops = hue.Color.Keypoints
			expect(`{hue.Rotation} {#stops} {hex(stops[1].Value)} {hex(stops[2].Value)}`).toBe(
				`0 2 #FFFFFF {hex(Color3.fromHSV(w.attr("hue") / 360, 1, 1))}`
			)
			local fade = w.find("Plane/Field/Value/Gradient")
			local points = fade.Transparency.Keypoints
			expect(`{fade.Rotation} {points[1].Value} -> {points[#points].Value}`).toBe("90 1 -> 0")
			expect(hex(w.find("Plane/Field/Value").BackgroundColor3)).toBe("#000000")
			expect(w.find("Plane/Field/Band1")).toBeNil()
			local hueSlider = w.find("Spectrum"):FindFirstChild("Hue")
			local rainbow = under(hueSlider, "HueStrip/Rainbow")
			expect(#rainbow.Color.Keypoints).toBe(7)
			expect(hex(rainbow.Color.Keypoints[3].Value)).toBe("#00FF00")
			expect(under(hueSlider, "Track") ~= nil).toBe(true)
			expect(under(hueSlider, "Fill")).toBeNil()
			expect(under(w.find("Opacity"), "Fill")).toBeNil()
			expect(hex(w.find("Opacity/AlphaStrip/Ramp").BackgroundColor3)).toBe("#2E7DFF")
			expect(w.find("Opacity/AlphaStrip/Checker/Top/C24") ~= nil).toBe(true)
			local ramp = w.find("Opacity/AlphaStrip/Ramp"):FindFirstChildWhichIsA("UIGradient")
			expect(`{ramp.Transparency.Keypoints[1].Value} {ramp.Transparency.Keypoints[2].Value}`).toBe("1 0")
			local ringStroke = w.find("Plane/Ring"):FindFirstChildWhichIsA("UIStroke")
			local bandStroke = w.find("Plane/Ring/Band"):FindFirstChildWhichIsA("UIStroke")
			local function level(c: any): number
				return c.R + c.G + c.B
			end
			expect(`{level(ringStroke.Color)} {level(bandStroke.Color)}`).toBe("0 3")
			expect(`{ringStroke.Transparency} {bandStroke.Transparency}`).toBe("0 0")
			expect(under(hueSlider, "Mark/Ring/Band") ~= nil).toBe(true)
			expect(w.find("Opacity/Mark/Ring/Band") ~= nil).toBe(true)
			cell:set(Color3.fromRGB(255, 0, 0))
			expect(hex(w.find("Opacity/AlphaStrip/Ramp").BackgroundColor3)).toBe("#FF0000")
			w.stop()
		end
	)

	t.it("empty shows the placeholder and the crossed plate; disabled keeps its colour and does not open", function()
		local cell, _, change = caller(nil)
		local w = world({ value = cell, onChange = change, allowEmpty = true, label = "Trim", placeholder = "None" })
		expect(w.find("Well/Value").Text).toBe("None")
		expect(w.find("Well/Swatch/Empty").Visible).toBe(true)
		expect(w.find("Well/Swatch/Plate").BackgroundTransparency).toBe(1)
		w.stop()
		local red, _, change2 = caller(Color3.fromRGB(255, 0, 0))
		local off = world({ value = red, onChange = change2, enabled = false })
		expect(hex(off.find("Well/Swatch/Plate").BackgroundColor3)).toBe("#FF0000")
		expect(off.find("Well").Interactable).toBe(false)
		off.open()
		expect(off.attr("presented")).toBe(false)
		expect(off.find("Panel")).toBeNil()
		off.stop()
	end)

	t.it("refuses a malformed contract at construction and quarantines a late bad value", function()
		local red = Color3.fromRGB(255, 0, 0)
		local noop = function() end
		local function build(spec: any): string
			local ok, err = pcall(function()
				world(spec).stop()
			end)
			return if ok then "ok" else tostring(err)
		end
		expect(string.find(build({ value = "red", onChange = noop }), "Color3", 1, true) ~= nil).toBe(true)
		expect(string.find(build({ value = red }), "onChange", 1, true) ~= nil).toBe(true)
		expect(string.find(build({ value = red, onChange = noop, alpha = 0.5 }), "onAlphaChange", 1, true) ~= nil).toBe(
			true
		)
		expect(string.find(build({ value = red, onChange = noop, modes = { "wheel" } }), "modes", 1, true) ~= nil).toBe(
			true
		)
		expect(string.find(build({ value = red, onChange = noop, swatches = { red, red } }), "repeats", 1, true) ~= nil).toBe(
			true
		)
		expect(
			string.find(
				build({ value = red, onChange = noop, swatches = { { color = red, lable = "Red" } } }),
				"lable",
				1,
				true
			) ~= nil
		).toBe(true)
		expect(
			string.find(
				build({ value = red, onChange = noop, style = "inline", isPresented = true }),
				"inline",
				1,
				true
			) ~= nil
		).toBe(true)
		expect(
			string.find(build({ value = red, onChange = noop, shape = "circle" }), "unknown option 'shape'", 1, true)
				~= nil
		).toBe(true)
		expect(build({ value = Compose.cell(red) })).toBe("ok")
		local source = Compose.cell(red :: any)
		local m = world({
			value = function(use)
				return use(source)
			end,
			onChange = noop,
		})
		source:set("blue")
		expect(hex(m.find("Well/Swatch/Plate").BackgroundColor3)).toBe("#FF0000")
		expect(m.attr("value")).toBe("#FF0000")
		local lines = string.split(m.attr("diagnostics"), "\n")
		expect(#lines).toBe(1)
		expect(string.find(lines[1], "value", 1, true) ~= nil).toBe(true)
		m.stop()
	end)

	t.it("the caller can own the open state and hears why the panel closed", function()
		local cell, _, change = caller(Color3.fromRGB(255, 0, 0))
		local open = Compose.cell(false)
		local proposals, reasons = {}, {}
		local w = world({
			value = cell,
			onChange = change,
			isPresented = open,
			onPresentedChange = function(next: boolean)
				table.insert(proposals, tostring(next))
				open:set(next)
			end,
			onDismiss = function(r: string)
				table.insert(reasons, r)
			end,
			ref = function() end,
		})
		w.open()
		expect(open:peek()).toBe(true)
		expect(w.find("Panel") ~= nil).toBe(true)
		w.find("Well").Visible = false
		expect(open:peek()).toBe(false)
		expect(table.concat(proposals, ",")).toBe("true,false")
		expect(table.concat(reasons, ",")).toBe("anchorLost")
		w.stop()
	end)

	t.it("stays open when it is built already presented and closes only after its anchor was shown", function()
		local cell, _, change = caller(Color3.fromRGB(255, 0, 0))
		local open = Compose.cell(true)
		local reasons = {}
		local w = world({
			value = cell,
			onChange = change,
			isPresented = open,
			onPresentedChange = function(next: boolean)
				open:set(next)
			end,
			onDismiss = function(r: string)
				table.insert(reasons, r)
			end,
		})
		expect(open:peek()).toBe(true)
		expect(#reasons).toBe(0)
		expect(w.find("Panel") ~= nil).toBe(true)
		w.find("Well").Visible = false
		expect(open:peek()).toBe(false)
		expect(table.concat(reasons, ",")).toBe("anchorLost")
		w.stop()
	end)
end)

t.describe("native ColorPicker phone sheet", function()
	local function sheet(): (any, any, { any })
		local probe = world({ value = Compose.cell(Color3.new(1, 0, 0)), onChange = function() end })
		local Touch = probe.E.PreferredInput.Touch
		probe.stop()
		local cell, seen, change = caller(Color3.fromRGB(218, 195, 145))
		local w = world({
			label = "Hat colour",
			value = cell,
			onChange = change,
			modes = { "swatches", "spectrum" },
			swatches = {
				{ color = Color3.fromRGB(218, 195, 145), label = "Straw" },
				{ color = Color3.fromRGB(176, 58, 46), label = "Brick" },
			},
		}, { preferred = Touch })
		w.size(w.screen, 390, 844)
		w.size(w.find("Well"), 44, 44)
		w.open()
		return w, cell, seen
	end

	t.it("the mode strip keeps its rung height inside a sheet and never takes the panel height", function()
		local w = sheet()
		expect(w.attr("placement")).toBe("sheet")
		local strip = w.find("Modes/Presentation")
		expect(strip ~= nil).toBe(true)
		expect(strip:HasTag("facet-segmented")).toBe(true)
		local E = w.E
		expect(`{strip.Size.Y.Scale} {strip.Size.Y.Offset}`).toBe("0 44")
		expect(strip.AutomaticSize == E.AutomaticSize.Y or strip.AutomaticSize == E.AutomaticSize.XY).toBe(false)
		local format = w.find("Readout/Format")
		expect(format:HasTag("facet-segmented")).toBe(true)
		local formatGrows = format.AutomaticSize == E.AutomaticSize.Y or format.AutomaticSize == E.AutomaticSize.XY
		expect(`format {format.Size.Y.Scale} {format.Size.Y.Offset} {formatGrows}`).toBe("format 0 44 false")
		for _, mode in { "swatches", "spectrum" } do
			local segment = w.find("Modes/" .. mode)
			local grows = segment.AutomaticSize == E.AutomaticSize.Y or segment.AutomaticSize == E.AutomaticSize.XY
			expect(`{mode} {grows}`).toBe(`{mode} false`)
		end
		w.stop()
	end)

	t.it("a tapped swatch in the sheet calls onChange, and Done closes with the colour kept", function()
		local w, cell, seen = sheet()
		local cells = w.cells("Swatches")
		cells[#cells].Activated.fire()
		expect(#seen).toBe(1)
		expect(hex(cell:peek())).toBe("#B03A2E")
		local done = w.find("Actions/Done")
		expect(done ~= nil).toBe(true)
		done.Activated.fire()
		expect(w.attr("placement")).toBe("closed")
		expect(hex(cell:peek())).toBe("#B03A2E")
		w.stop()
	end)
end)

return nil
