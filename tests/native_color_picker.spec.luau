--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Facet = require("../src")
	local Roblox = require("@lune/roblox")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose
	local expect = Verify.expect
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
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
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
			{
				types = types,
				services = { GuiService = gui, UserInputService = proxy },
				guiService = gui,
				theme = o.theme,
			} :: any
		)
		local target = engine.new("Folder")
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local stop, screen: any = runtime.mount(function()
			return Host.ScreenGui({
				Host.Frame "Col" {
					if o.build then o.build(UI, Host) else UI.ColorPicker("P")(spec) :: unknown,
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
			w.find("Well").Activated:Fire()
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
					found.Pressed:Fire()
					found.Released:Fire()
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
			runtime:dispose()
		end
		return w
	end

	verifyHarness:suite("native ColorPicker colour values", function()
		verifyHarness:case("a saturation round trip through the Sliders tab returns to the hue the player set", {
			id = "native_color_picker::native ColorPicker colour values::a saturation round trip through the Sliders tab returns to the hue the player set",
			run = function()
				local set = Color3.fromHSV(200 / 360, 1, 1)
				local cell, _, change = caller(set)
				local w =
					world({ value = cell, onChange = change, style = "inline" :: "inline", modes = { "sliders" } })
				w.gui.SelectedObject = w.find("Saturation")
				expect((w.press("DecreaseArrow", 100))):toBe(100)
				expect((hex(cell:peek()))):toBe("#FFFFFF")
				expect((math.floor(w.attr("hue") + 0.5))):toBe(200)
				w.press("IncreaseArrow", 100)
				expect((math.floor(w.attr("hue") + 0.5))):toBe(200)
				expect((hex(cell:peek()))):toBe(hex(set))
				w.gui.SelectedObject = w.find("Brightness")
				w.press("DecreaseArrow", 100)
				expect((hex(cell:peek()))):toBe("#000000")
				w.press("IncreaseArrow", 100)
				expect((hex(cell:peek()))):toBe(hex(set))
				w.stop()
			end,
		})

		verifyHarness:case(
			"the readout format segments fill a fixed row height, so the row cannot grow with its own segments",
			{
				id = "native_color_picker::native ColorPicker colour values::the readout format segments fill a fixed row height, so the row cannot grow with its own segments",
				run = function()
					local cell, _, change = caller(Color3.new(1, 0, 0))
					local w =
						world({ value = cell, onChange = change, style = "inline" :: "inline", modes = { "sliders" } })
					local format = w.find("Format")
					expect(format.AutomaticSize.Name):toBe("X")
					expect(format.Size.Y.Scale):toBe(0)
					expect(format.Size.Y.Offset >= 44):toBe(true)
					local segment = w.find("Format/hex")
					expect(segment.Size.Y.Scale):toBe(0)
					expect(segment.Size.Y.Offset):toBe(format.Size.Y.Offset - 6)
					w.stop()
				end,
			}
		)

		verifyHarness:case(
			"switching the readout twenty times never moves canonical, and a hex commit is the only write",
			{
				id = "native_color_picker::native ColorPicker colour values::switching the readout twenty times never moves canonical, and a hex commit is the only write",
				run = function()
					local start = Color3.fromHSV(0.61, 0.37, 0.83)
					local cell, seen, change = caller(start)
					local w =
						world({ value = cell, onChange = change, style = "inline" :: "inline", modes = { "sliders" } })
					local before = `{w.attr("hue")},{w.attr("saturation")},{w.attr("brightness")}`
					for _ = 1, 20 do
						for _, word in { "hsv", "hex", "rgb" } do
							w.find("Format/" .. word).Activated:Fire()
						end
					end
					expect(`{w.attr("hue")},{w.attr("saturation")},{w.attr("brightness")}`):toBe(before)
					expect(#seen):toBe(0)
					w.find("Format/hex").Activated:Fire()
					expect((w.attr("format"))):toBe("hex")
					local field = w.find("FieldHex/Field")
					w.typeInto(field, "#zz0")
					expect(#seen):toBe(0)
					expect(w.attr("hexError") ~= ""):toBe(true)
					expect(field.Text):toBe("#zz0")
					expect(w.find("FieldHex/Validation").Text):toBe(w.attr("hexError"))
					w.typeInto(field, "#0f0")
					expect((hex(cell:peek()))):toBe("#00FF00")
					expect((w.attr("hexError"))):toBe("")
					expect(field.Text):toBe("#00FF00")
					w.stop()
				end,
			}
		)
	end)

	verifyHarness:suite("native ColorPicker well and panel", function()
		verifyHarness:case(
			"the well opens an anchored panel on a roomy pointer screen; a refused swatch never paints",
			{
				id = "native_color_picker::native ColorPicker well and panel::the well opens an anchored panel on a roomy pointer screen; a refused swatch never paints",
				run = function()
					local cell, seen, change = caller(Color3.fromRGB(255, 0, 0), false)
					local w = world({ value = cell, onChange = change })
					w.size(w.screen, 900, 900)
					w.size(w.find("Well"), 44, 44)
					w.open()
					expect((w.attr("presented"))):toBe(true)
					expect((w.attr("placement"))):toBe("bottom")
					local panel = w.find("Panel")
					expect((panel:HasTag("facet-panel"))):toBe(true)
					expect(panel.Position.Y.Offset):toBe(48)
					local cells = w.cells()
					expect(#cells):toBe(48)
					local held = w.hsv()
					cells[20].Activated:Fire()
					expect(#seen):toBe(1)
					expect((w.hsv())):toBe(held)
					expect((hex(cell:peek()))):toBe("#FF0000")
					expect((hex(w.find("Well/Swatch/Plate").BackgroundColor3))):toBe("#FF0000")
					expect((hex(w.find("Readout/Preview/Plate").BackgroundColor3))):toBe("#FF0000")
					expect((cells[20]:GetAttribute("selected"))):toBe(false)
					w.stop()
				end,
			}
		)

		verifyHarness:case(
			"every technique shares the tallest picker's height and a long brick list scrolls inside it, on a pointer panel and a phone sheet",
			{
				id = "native_color_picker::native ColorPicker well and panel::every technique shares the tallest picker's height and a long brick list scrolls inside it, on a pointer panel and a phone sheet",
				run = function()
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
						expect((w.attr("placement"))):toBe(if case.touch then "sheet" else "bottom")
						local heights = { 180, 300, 240, 500 }
						for index, mode in case.modes do
							local label = ({
								swatches = "Swatches",
								spectrum = "Spectrum",
								sliders = "Sliders",
								brick = "Bricks",
							})[mode]
							w.size(w.find("Show" .. label), 300, heights[index])
						end
						local tallest = 0
						for index, mode in case.modes do
							if mode ~= "brick" then
								tallest = math.max(tallest, heights[index])
							end
						end
						for index, mode in case.modes do
							w.find("Modes/" .. mode).Activated:Fire()
							expect((w.attr("mode"))):toBe(mode)
							expect(`{case.w} {mode} {w.find("Body").Size.Y.Offset}`):toBe(`{case.w} {mode} {tallest}`)
							expect(w.find("Technique").Size.Y.Offset):toBe(heights[index])
						end
						w.stop()
					end
				end,
			}
		)

		verifyHarness:case("the panel's height follows its room, never a height it once measured", {
			id = "native_color_picker::native ColorPicker well and panel::the panel's height follows its room, never a height it once measured",
			run = function()
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
				expect(before):toBe(290)
				w.size(w.screen, 900, 420)
				expect(height() < before):toBe(true)
				w.size(w.screen, 900, 900)
				for _, mode in modes do
					w.find("Modes/" .. mode).Activated:Fire()
					expect(`{mode} {height()}`):toBe(`{mode} {before}`)
				end
				w.stop()
			end,
		})

		verifyHarness:case(
			"an accepted swatch commits once, marks the cell, and the swatch grid lays out rows of eight",
			{
				id = "native_color_picker::native ColorPicker well and panel::an accepted swatch commits once, marks the cell, and the swatch grid lays out rows of eight",
				run = function()
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
					expect((w.attr("columns"))):toBe(8)
					cells[3].Activated:Fire()
					local chosen = hex(cell:peek())
					expect((table.concat(commits, ","))):toBe(chosen)
					expect(cells[3]:FindFirstChild("Check").Visible):toBe(true)
					expect((cells[3]:GetAttribute("selected"))):toBe(true)
					expect(cells[4]:FindFirstChild("Check").Visible):toBe(false)
					local grid = w.find("Swatches")
					expect(grid.Size.X.Offset):toBe(8 * 44 + 7 * 4)
					local layout = grid:FindFirstChildWhichIsA("UIListLayout")
					expect(`{layout.Wraps} {layout.FillDirection.Name} {layout.Padding.Offset}`):toBe(
						"true Horizontal 4"
					)
					for index, node in cells do
						expect(node.LayoutOrder):toBe(index)
						expect(node.Selectable):toBe(true)
					end
					w.size(w.find("Technique"), 300, 0)
					expect((w.attr("columns"))):toBe(6)
					expect(#w.cells()):toBe(36)
					w.stop()
				end,
			}
		)

		verifyHarness:case(
			"saved colours: + proposes the current colour once; Edit removes by activate or Delete and hands the ring on",
			{
				id = "native_color_picker::native ColorPicker well and panel::saved colours: + proposes the current colour once; Edit removes by activate or Delete and hands the ring on",
				run = function()
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
					expect(plus.Name):toBe("Save")
					expect((plus:GetAttribute("label"))):toBe("Save colour")
					expect(plus:FindFirstChild("Plus") ~= nil):toBe(true)
					plus.Activated:Fire()
					w.cells()[4].Activated:Fire()
					expect((table.concat(saved, ","))):toBe("#0AC81E")
					expect(#w.cells()):toBe(4)
					expect(w.cells()[4].Interactable):toBe(false)
					w.find("Saved/Edit").Activated:Fire()
					expect(w.find("Saved/Edit").Text):toBe("Done")
					local first = w.cells()[1]
					expect(first:FindFirstChild("Remove").Visible):toBe(true)
					expect((first:GetAttribute("label"))):toBe("Remove #FF0000")
					first.Activated:Fire()
					expect((table.concat(removed, ","))):toBe("#FF0000")
					expect((hex(cell:peek()))):toBe("#0AC81E")
					w.gui.SelectedObject = w.cells()[1]
					expect((w.press("ColorSwatchRemove"))):toBe(1)
					expect((table.concat(removed, ","))):toBe("#FF0000,#0000FF")
					expect(w.gui.SelectedObject):toBe(w.cells()[1])
					local keys = {}
					for _, binding in w.action("ColorSwatchRemove"):GetChildren() do
						table.insert(keys, binding.KeyCode.Name)
					end
					table.sort(keys)
					expect((table.concat(keys, " "))):toBe("Backspace ButtonX Delete")
					w.find("Saved/Edit").Activated:Fire()
					expect((w.action("ColorSwatchRemove"))):toBeNil()
					w.cells()[1].Activated:Fire()
					expect(#removed):toBe(2)
					w.stop()
				end,
			}
		)

		verifyHarness:case("without draft every change commits live and B or an outside tap only closes, keeping it", {
			id = "native_color_picker::native ColorPicker well and panel::without draft every change commits live and B or an outside tap only closes, keeping it",
			run = function()
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
				w.cells()[5].Activated:Fire()
				local picked = hex(cell:peek())
				expect(picked ~= hex(startColor)):toBe(true)
				expect((w.press("ModalBack"))):toBe(1)
				expect((w.attr("presented"))):toBe(false)
				expect((w.find("Panel"))):toBeNil()
				expect((hex(cell:peek()))):toBe(picked)
				expect((table.concat(commits, ","))):toBe(picked)
				w.open()
				w.cells()[6].Activated:Fire()
				local kept = hex(cell:peek())
				w.find("DismissOutside").Activated:Fire()
				expect((w.attr("presented"))):toBe(false)
				expect((hex(cell:peek()))):toBe(kept)
				expect((table.concat(reasons, ","))):toBe("cancel,outside")
				w.stop()
			end,
		})

		verifyHarness:case(
			"draft: B and an outside tap discard, restoring the open-time colour; a caller write re-bases it",
			{
				id = "native_color_picker::native ColorPicker well and panel::draft: B and an outside tap discard, restoring the open-time colour; a caller write re-bases it",
				run = function()
					local startColor = Color3.fromRGB(10, 20, 30)
					local cell, seen, change = caller(startColor)
					local w = world({ value = cell, onChange = change, draft = true })
					w.open()
					w.cells()[5].Activated:Fire()
					expect(hex(cell:peek()) ~= hex(startColor)):toBe(true)
					w.press("ModalBack")
					expect((hex(cell:peek()))):toBe(hex(startColor))
					expect((hex(seen[#seen]))):toBe(hex(startColor))
					w.open()
					w.cells()[6].Activated:Fire()
					w.find("DismissOutside").Activated:Fire()
					expect((hex(cell:peek()))):toBe(hex(startColor))
					w.open()
					local server = Color3.fromRGB(200, 100, 50)
					cell:set(server)
					w.cells()[7].Activated:Fire()
					expect(hex(cell:peek()) ~= hex(server)):toBe(true)
					w.press("ModalBack")
					expect((hex(cell:peek()))):toBe(hex(server))
					w.stop()
				end,
			}
		)

		verifyHarness:case("draft: gestures propose live but commit nothing; Apply commits once and Cancel restores", {
			id = "native_color_picker::native ColorPicker well and panel::draft: gestures propose live but commit nothing; Apply commits once and Cancel restores",
			run = function()
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
				expect((w.find("Actions/Apply"):HasTag("facet-accent"))):toBe(true)
				expect((w.find("Actions/Cancel"):HasTag("facet-accent"))):toBe(false)
				expect(w.find("Actions").Visible):toBe(true)
				w.cells()[9].Activated:Fire()
				expect(#commits):toBe(0)
				w.find("Actions/Cancel").Activated:Fire()
				expect((hex(cell:peek()))):toBe(hex(startColor))
				expect(#commits):toBe(0)
				w.open()
				w.cells()[9].Activated:Fire()
				w.find("Actions/Apply").Activated:Fire()
				expect((table.concat(commits, ","))):toBe(hex(cell:peek()))
				expect((w.attr("presented"))):toBe(false)
				expect((table.concat(reasons, ","))):toBe("cancel,apply")
				w.stop()
			end,
		})

		verifyHarness:case(
			"opens as a sheet with Done on a compact touch screen, and a centred sheet at ten feet with the plane",
			{
				id = "native_color_picker::native ColorPicker well and panel::opens as a sheet with Done on a compact touch screen, and a centred sheet at ten feet with the plane",
				run = function()
					local cell, _, change = caller(Color3.fromRGB(255, 0, 0))
					local probe = world({ value = cell, onChange = change })
					local Touch = probe.E.PreferredInput.Touch
					probe.stop()
					local w = world({ value = cell, onChange = change }, { preferred = Touch })
					w.size(w.screen, 390, 844)
					w.size(w.find("Well"), 44, 44)
					w.open()
					expect((w.attr("placement"))):toBe("sheet")
					expect(w.find("Actions/Done") ~= nil):toBe(true)
					expect(w.find("Actions").Visible):toBe(true)
					expect((w.find("Close"))):toBeNil()
					expect(w.find("DismissOutside").BackgroundTransparency < 1):toBe(true)
					local panel = w.find("Panel")
					expect(panel.Size.X.Offset):toBe(390 - 24)
					w.find("Modes/spectrum").Activated:Fire()
					local surface = w.find("Plane/Surface")
					w.size(surface, 300, 176, 30, 200)
					local top = panel.Position.Y.Offset
					local v0 = w.attr("brightness")
					local drag = surface:FindFirstChildWhichIsA("UIDragDetector")
					drag.DragStart:Fire(V2(180, 200 + 176 * 0.2))
					for step = 1, 10 do
						drag.DragContinue:Fire(V2(180, 200 + 176 * (0.2 + step * 0.05)))
					end
					drag.DragEnd:Fire()
					expect(w.attr("brightness") < v0 - 20):toBe(true)
					expect(panel.Position.Y.Offset):toBe(top)
					w.find("Actions/Done").Activated:Fire()
					expect((w.attr("presented"))):toBe(false)
					w.stop()
					local four = world(
						{ value = cell, onChange = change, modes = { "swatches", "spectrum", "sliders", "brick" } },
						{ preferred = Touch }
					)
					four.open()
					expect(four.find("Modes/brick") ~= nil):toBe(true)
					four.size(four.find("Modes"), 300, 44)
					expect(four.find("Modes") ~= nil):toBe(true)
					expect(four.find("Modes/brick") ~= nil):toBe(true)
					four.find("Modes/LabelMeasure").TextBounds = V2(220, 18)
					expect((four.find("Modes/brick"))):toBeNil()
					four.stop()
					local tv = world(
						{ value = cell, onChange = change, modes = { "spectrum", "swatches" } },
						{ preferred = Touch, tenFoot = true }
					)
					tv.size(tv.screen, 1920, 1080)
					tv.open()
					expect((tv.attr("placement"))):toBe("center")
					expect(tv.find("Plane/Surface") ~= nil):toBe(true)
					expect(tv.find("Actions").Visible):toBe(true)
					local tvPanel = tv.find("Panel")
					expect(tvPanel.Position.X.Offset * 2 + tvPanel.Size.X.Offset):toBe(1920)
					tv.stop()
				end,
			}
		)
	end)

	verifyHarness:suite("native ColorPicker spectrum plane", function()
		local function spectrum(options: any?): (any, any, { string })
			local cell, _, change = caller(Color3.fromHSV(0.5, 0.5, 0.5))
			local commits = {}
			local w = world({
				value = cell,
				onChange = change,
				style = "inline" :: "inline",
				modes = { "spectrum" },
				onCommit = function(c: any)
					table.insert(commits, hex(c))
				end,
			}, options)
			w.size(w.find("Plane"), 200, 176, 0, 0)
			w.size(w.find("Plane/Surface"), 200, 176, 0, 0)
			return w, cell, commits
		end

		verifyHarness:case("a drag tracks 1:1 in saturation and value, keeps the hue, and commits once at release", {
			id = "native_color_picker::native ColorPicker spectrum plane::a drag tracks 1:1 in saturation and value, keeps the hue, and commits once at release",
			run = function()
				local w, cell, commits = spectrum()
				local drag = w.find("Plane/Surface"):FindFirstChildWhichIsA("UIDragDetector")
				expect(drag.ResponseStyle.Name):toBe("CustomOffset")
				drag.DragStart:Fire(V2(50, 88))
				drag.DragContinue:Fire(V2(150, 44))
				expect((w.hsv())):toBe("180,75,75")
				expect(#commits):toBe(0)
				drag.DragEnd:Fire()
				expect(#commits):toBe(1)
				expect(commits[1]):toBe(hex(cell:peek()))
				local mark = w.find("Plane/Ring")
				expect(`{mark.Position.X.Offset},{mark.Position.Y.Offset}`):toBe("150,44")
				drag.DragStart:Fire(V2(200, 0))
				drag.DragEnd:Fire()
				expect(`{mark.Position.X.Offset},{mark.Position.Y.Offset}`):toBe("190,10")
				expect(`{mark.AnchorPoint.X},{mark.Size.X.Offset}`):toBe("0.5,20")
				w.stop()
			end,
		})

		verifyHarness:case("a gamepad A on the selected plane is not a drag: the colour stays until the stick steers", {
			id = "native_color_picker::native ColorPicker spectrum plane::a gamepad A on the selected plane is not a drag: the colour stays until the stick steers",
			run = function()
				local w, _, commits =
					spectrum({ preferred = (require("@lune/roblox") :: any).Enum.PreferredInput.Gamepad })
				local before = w.hsv()
				local surface = w.find("Plane/Surface")
				w.gui.SelectedObject = surface
				local drag = surface:FindFirstChildWhichIsA("UIDragDetector")
				drag.DragStart:Fire(V2(100, 88))
				drag.DragEnd:Fire()
				expect((w.hsv())):toBe(before)
				expect(#commits):toBe(0)
				w.stop()
			end,
		})

		verifyHarness:case("the native drag detector follows the plane through a tab round trip", {
			id = "native_color_picker::native ColorPicker spectrum plane::the native drag detector follows the plane through a tab round trip",
			run = function()
				local cell, _, change = caller(Color3.fromHSV(0.5, 0.5, 0.5))
				local w = world({
					value = cell,
					onChange = change,
					style = "inline" :: "inline",
					modes = { "spectrum", "sliders" },
				})
				local surface = w.find("Plane/Surface")
				w.size(surface, 200, 176)
				local function driveTo(fx: number)
					local drag = w.find("Plane/Surface"):FindFirstChildWhichIsA("UIDragDetector")
					drag.DragStart:Fire(V2(200 * fx, 88))
					drag.DragEnd:Fire()
				end
				driveTo(0.2)
				expect((math.floor(w.attr("saturation") + 0.5))):toBe(20)
				w.find("Modes/sliders").Activated:Fire()
				expect(w.find("ShowSpectrum").Visible):toBe(false)
				expect(w.find("ShowSliders").Visible):toBe(true)
				w.find("Modes/spectrum").Activated:Fire()
				expect((w.find("Plane/Surface"))):toBe(surface)
				driveTo(0.8)
				expect((math.floor(w.attr("saturation") + 0.5))):toBe(80)
				w.stop()
			end,
		})

		verifyHarness:case("losing the pointer class mid-drag restores where the drag began", {
			id = "native_color_picker::native ColorPicker spectrum plane::losing the pointer class mid-drag restores where the drag began",
			run = function()
				local w, cell, commits = spectrum()
				local before = hex(cell:peek())
				local drag = w.find("Plane/Surface"):FindFirstChildWhichIsA("UIDragDetector")
				drag.DragStart:Fire(V2(5, 5))
				expect(hex(cell:peek()) ~= before):toBe(true)
				w.input.PreferredInput = w.E.PreferredInput.Gamepad
				expect((hex(cell:peek()))):toBe(before)
				drag.DragContinue:Fire(V2(100, 100))
				drag.DragEnd:Fire()
				expect((hex(cell:peek()))):toBe(before)
				expect(#commits):toBe(0)
				w.stop()
			end,
		})

		verifyHarness:case(
			"on touch the preview leads the panel, and a drag shows the colour in a bubble above the finger",
			{
				id = "native_color_picker::native ColorPicker spectrum plane::on touch the preview leads the panel, and a drag shows the colour in a bubble above the finger",
				run = function()
					local probe = world({ value = Compose.cell(Color3.new(1, 0, 0)), onChange = function() end })
					local E = probe.E
					probe.stop()
					local w, cell = spectrum({ preferred = E.PreferredInput.Touch })
					expect(w.find("Readout").LayoutOrder < w.find("Body").LayoutOrder):toBe(true)
					expect(w.find("Body"):IsA("ScrollingFrame") and w.find("Body").Size.X.Scale == 1):toBe(true)
					expect((w.screen:FindFirstChild("Bubble"))):toBe(nil)
					local drag = w.find("Plane/Surface"):FindFirstChildWhichIsA("UIDragDetector")
					drag.DragStart:Fire(V2(100, 88))
					drag.DragContinue:Fire(V2(120, 106))
					local bubble = w.screen:FindFirstChild("Bubble")
					expect(bubble.Visible):toBe(true)
					expect(bubble.Parent):toBe(w.screen)
					expect(bubble.ZIndex > w.find("Plane/Surface").ZIndex):toBe(true)
					expect(bubble.AnchorPoint.Y):toBe(1)
					expect(bubble.Position.Y.Offset < 106):toBe(true)
					expect(`{bubble.Position.X.Offset},{bubble.Position.Y.Offset}`):toBe("120,88")
					expect((hex(bubble.BackgroundColor3))):toBe(hex(cell:peek()))
					drag.DragContinue:Fire(V2(100, 20))
					expect(`{bubble.Position.X.Offset},{bubble.Position.Y.Offset}`):toBe("100,2")
					expect(bubble.Position.Y.Offset - 44 < 0):toBe(true)
					drag.DragEnd:Fire()
					expect((w.screen:FindFirstChild("Bubble"))):toBe(nil)
					drag.DragStart:Fire(V2(5, 170))
					expect(w.screen:FindFirstChild("Bubble").Visible):toBe(true)
					drag.DragEnd:Fire()
					for _, point in
						{ V2(0, 0), V2(40, 12), V2(100, 30), V2(160, 20), V2(200, 0), V2(200, 176), V2(0, 176) }
					do
						drag.DragStart:Fire(point)
						bubble = w.screen:FindFirstChild("Bubble")
						local left = bubble.Position.X.Offset - 22
						local top = bubble.Position.Y.Offset - 44
						local inside = left >= 0 and left + 44 <= 200
						local ring = w.find("Plane/Ring")
						local rx, ry = ring.Position.X.Offset, ring.Position.Y.Offset
						local covers = rx > left - 10 and rx < left + 54 and ry > top - 10 and ry < top + 54
						expect(`{point} {inside} {covers}`):toBe(`{point} true false`)
						expect(bubble.Position.Y.Offset + 8 <= ry - 10 + 1):toBe(true)
						drag.DragEnd:Fire()
					end
					drag.DragStart:Fire(V2(5, 170))
					w.input.PreferredInput = E.PreferredInput.Gamepad
					expect((w.screen:FindFirstChild("Bubble"))):toBe(nil)
					w.stop()
					local h = spectrum({ preferred = E.PreferredInput.Touch })
					local hueSlider = h.find("Spectrum"):FindFirstChild("Hue")
					local track = under(hueSlider, "Track")
					h.size(track, 200, 44)
					local hueBubble = under(hueSlider, "Mark/Bubble")
					expect(hueBubble.Visible):toBe(false)
					local hueDrag = track:FindFirstChildWhichIsA("UIDragDetector")
					hueDrag.DragStart:Fire(V2(60, 22))
					hueDrag.DragContinue:Fire(V2(82.4, 22))
					expect(hueBubble.Visible):toBe(true)
					expect(`{hueBubble.AnchorPoint.Y} {hueBubble.Position.Y.Offset}`):toBe("1 -8")
					expect((math.floor(h.attr("hue") + 0.5))):toBe(144)
					hueDrag.DragEnd:Fire()
					expect(hueBubble.Visible):toBe(false)
					h.stop()
					local p = spectrum()
					local pointerDrag = p.find("Plane/Surface"):FindFirstChildWhichIsA("UIDragDetector")
					pointerDrag.DragStart:Fire(V2(10, 10))
					expect((p.screen:FindFirstChild("Bubble"))):toBe(nil)
					expect(p.find("Readout").LayoutOrder > p.find("Technique").LayoutOrder):toBe(true)
					pointerDrag.DragEnd:Fire()
					p.stop()
				end,
			}
		)

		verifyHarness:case(
			"the touch bubble follows screen geometry and scaling outside clipped ancestors, and leaves with its owner",
			{
				id = "native_color_picker::native ColorPicker spectrum plane::the touch bubble follows screen geometry and scaling outside clipped ancestors, and leaves with its owner",
				run = function()
					local E = Roblox.Enum
					local w = spectrum({ preferred = E.PreferredInput.Touch })
					local plane = w.find("Plane")
					w.find("Body").ClipsDescendants = true
					w.find("Panel").ClipsDescendants = true
					w.size(w.screen, 600, 600, 10, 20)
					w.size(plane, 400, 352, 60, 120)
					w.size(w.find("Plane/Surface"), 400, 352, 60, 120)
					local drag = w.find("Plane/Surface"):FindFirstChildWhichIsA("UIDragDetector")
					drag.DragStart:Fire(V2(260, 180))
					local bubble = w.screen:FindFirstChild("Bubble")
					w.size(plane:FindFirstChild("LayoutUnit"), 200, 2)
					w.size(w.screen:FindFirstChild("LayoutUnit"), 100, 1)
					expect(bubble.Parent):toBe(w.screen)
					expect(bubble:FindFirstChildWhichIsA("UIScale").Scale):toBe(2)
					expect(`{bubble.Position.X.Offset},{bubble.Position.Y.Offset}`):toBe("250,124")
					w.size(plane, 400, 352, 80, 90)
					expect(`{bubble.Position.X.Offset},{bubble.Position.Y.Offset}`):toBe("270,94")
					w.size(w.screen:FindFirstChild("LayoutUnit"), 50, 1)
					expect(bubble:FindFirstChildWhichIsA("UIScale").Scale):toBe(4)
					expect(`{bubble.Position.X.Offset},{bubble.Position.Y.Offset}`):toBe("540,188")
					w.stop()
					expect(bubble.Parent):toBe(nil)
				end,
			}
		)

		verifyHarness:case(
			"the touch bubble goes beside the finger only when the screen has no room above, and stays within its edges",
			{
				id = "native_color_picker::native ColorPicker spectrum plane::the touch bubble goes beside the finger only when the screen has no room above, and stays within its edges",
				run = function()
					local w = spectrum({ preferred = Roblox.Enum.PreferredInput.Touch })
					w.size(w.screen, 200, 300)
					local plane = w.find("Plane")
					local surface = w.find("Plane/Surface")
					w.size(plane, 200, 176, 0, 100)
					w.size(surface, 200, 176, 0, 100)
					local drag = surface:FindFirstChildWhichIsA("UIDragDetector")
					drag.DragStart:Fire(V2(100, 100))
					local bubble = w.screen:FindFirstChild("Bubble")
					expect(`{bubble.Position.X.Offset},{bubble.Position.Y.Offset}`):toBe("100,92")
					w.size(plane, 200, 176)
					w.size(surface, 200, 176)
					for _, point in { V2(0, 0), V2(100, 0), V2(200, 0) } do
						drag.DragContinue:Fire(point)
						local left, top = bubble.Position.X.Offset - 22, bubble.Position.Y.Offset - 44
						expect(left >= 0 and top >= 0 and left + 44 <= 200):toBe(true)
						local ring = w.find("Plane/Ring")
						expect(math.abs(bubble.Position.X.Offset - ring.Position.X.Offset) >= 40):toBe(true)
					end
					drag.DragEnd:Fire()
					expect((w.screen:FindFirstChild("Bubble"))):toBe(nil)
					w.stop()
				end,
			}
		)

		verifyHarness:case("the right stick steers the plane only while it holds focus, and a live hint says so", {
			id = "native_color_picker::native ColorPicker spectrum plane::the right stick steers the plane only while it holds focus, and a live hint says so",
			run = function()
				local probe = world({ value = Compose.cell(Color3.new(1, 0, 0)), onChange = function() end })
				local E = probe.E
				probe.stop()
				local w, cell, commits = spectrum({ preferred = E.PreferredInput.Gamepad })
				local surface = w.find("Plane/Surface")
				expect(surface.Selectable):toBe(true)
				expect((surface:GetAttribute("AccessibleLabel"))):toBe("Saturation and brightness")
				local before = w.hsv()
				w.gui.SelectedObject = w.find("Other")
				expect((w.action("ColorPlaneSteer"))):toBeNil()
				expect(w.find("StickHint").Visible):toBe(false)
				w.engine.heartbeat:Fire(1)
				expect((w.hsv())):toBe(before)
				w.gui.SelectedObject = surface
				expect(w.find("StickHint").Visible):toBe(true)
				local steer = w.action("ColorPlaneSteer")
				expect(steer.Type.Name):toBe("Direction2D")
				expect(steer.Parent.Sink):toBe(true)
				expect(steer:FindFirstChildWhichIsA("InputBinding").KeyCode.Name):toBe("Thumbstick2")
				local s0 = w.attr("saturation")
				local v0 = w.attr("brightness")
				local listeners = engineLib.connections(w.engine.heartbeat)
				steer.StateChanged:Fire(V2(1, 0))
				w.engine.heartbeat:Fire(0.5)
				steer.StateChanged:Fire(V2(0, 0))
				expect(w.attr("saturation") > s0 + 10):toBe(true)
				expect((math.floor(w.attr("brightness") + 0.5))):toBe(math.floor(v0 + 0.5))
				expect(#commits):toBe(1)
				for _ = 1, 5 do
					steer.StateChanged:Fire(V2(0, 1))
					w.engine.heartbeat:Fire(0.1)
					steer.StateChanged:Fire(V2(0, 0))
				end
				expect((engineLib.connections(w.engine.heartbeat))):toBe(listeners)
				expect(#commits):toBe(6)
				steer.StateChanged:Fire(V2(-1, 0))
				w.engine.heartbeat:Fire(0.1)
				w.gui.SelectedObject = w.find("Other")
				expect(#commits):toBe(7)
				expect(commits[7]):toBe(hex(cell:peek()))
				expect((engineLib.connections(w.engine.heartbeat))):toBe(listeners)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native ColorPicker composed in a screen", function()
		verifyHarness:case("a committed line follows a commit, and a refusal changes nothing", {
			id = "native_color_picker::native ColorPicker composed in a screen::a committed line follows a commit, and a refusal changes nothing",
			run = function()
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
					build = function(UI: FacetControls, Host: RobloxHost)
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
							}) :: unknown,
							Host.TextLabel "Committed" {
								Text = function(use: Use)
									return "Committed: " .. use(committed)
								end,
							},
						}
					end,
				})
				local line = w.find("Committed")
				expect(line.Text):toBe("Committed: nothing yet")
				w.open()
				local cells = w.cells()
				expect(#cells):toBe(5)
				cells[4].Activated:Fire()
				expect(line.Text):toBe("Committed: #00AA8C")
				expect((hex(w.find("Well/Swatch/Plate").BackgroundColor3))):toBe("#00AA8C")
				w.find("DismissOutside").Activated:Fire()
				refuse:set(true)
				w.open()
				w.cells()[2].Activated:Fire()
				expect((hex(w.find("Well/Swatch/Plate").BackgroundColor3))):toBe("#00AA8C")
				expect(line.Text):toBe("Committed: #00AA8C")
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native ColorPicker alpha, empty, disabled and refusals", function()
		verifyHarness:case("alpha mounts opacity, writes #RRGGBBAA, and shows the checker under a translucent colour", {
			id = "native_color_picker::native ColorPicker alpha, empty, disabled and refusals::alpha mounts opacity, writes #RRGGBBAA, and shows the checker under a translucent colour",
			run = function()
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
				expect(w.find("Well/Value").Text):toBe("#FF000080")
				expect(w.find("Well/Swatch/Checker").Visible):toBe(true)
				expect(w.find("Well/Swatch/Plate").BackgroundTransparency):toBeCloseTo(0.5, 1e-4)
				w.open()
				for _, swatch in { w.find("Well/Swatch"), w.find("Readout/Head/Preview") } do
					local paint = swatch:FindFirstChild("Paint")
					expect((paint:IsA("CanvasGroup"))):toBe(true)
					expect(paint:FindFirstChildWhichIsA("UICorner") ~= nil):toBe(true)
					expect(paint:FindFirstChild("Checker") ~= nil):toBe(true)
					expect(paint:FindFirstChild("Plate") ~= nil):toBe(true)
				end
				local track = w.find("Opacity/Track")
				expect((track:GetAttribute("AccessibleLabel"))):toBe("Opacity")
				w.gui.SelectedObject = w.find("Opacity")
				w.press("IncreaseArrow", 60)
				expect((a:peek())):toBe(1)
				expect((w.find("Well/Swatch/Paint"):IsA("Frame"))):toBe(true)
				expect((w.find("Well/Swatch/Paint"):IsA("CanvasGroup"))):toBe(false)
				expect(w.find("Well/Swatch/Checker").Visible):toBe(false)
				a:set(0.5)
				expect((w.find("Well/Swatch/Paint"):IsA("CanvasGroup"))):toBe(true)
				expect(#w.find("Well/Swatch/Checker"):GetChildren()):toBe(4)
				a:set(1)
				expect(w.find("Well/Value").Text):toBe("#FF0000")
				w.find("Format/hex").Activated:Fire()
				expect(w.find("FieldHex/Field").Text):toBe("#FF0000FF")
				w.typeInto(w.find("FieldHex/Field"), "zz")
				expect(string.find(w.attr("hexError"), "#RRGGBBAA", 1, true) ~= nil):toBe(true)
				w.typeInto(w.find("FieldHex/Field"), "#00FF0040")
				expect((hex(cell:peek()))):toBe("#00FF00")
				expect((math.floor(a:peek() * 255 + 0.5))):toBe(64)
				w.stop()
				local plain = world({ value = cell, onChange = change })
				plain.open()
				expect((plain.find("Opacity"))):toBeNil()
				plain.stop()
			end,
		})

		verifyHarness:case("the Bricks tab names the chosen brick in a field above its grid", {
			id = "native_color_picker::native ColorPicker alpha, empty, disabled and refusals::the Bricks tab names the chosen brick in a field above its grid",
			run = function()
				local cell, _, change = caller(Color3.fromRGB(255, 0, 0))
				local w = world({ value = cell, onChange = change, style = "inline" :: "inline", modes = { "brick" } })
				local cells = w.cells("BrickGrid")
				expect(#cells):toBe(128)
				cells[1].Activated:Fire()
				local name = w.find("Brick/NameField/BrickName")
				expect(name.Text):toBe(cells[1].Name)
				expect(w.find("Brick/NameField").LayoutOrder < w.find("Brick/BrickGrid").LayoutOrder):toBe(true)
				expect((w.root:GetAttribute("text"))):toBe(hex(cell:peek()))
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native ColorPicker phone sheet", function()
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

		verifyHarness:case("a tapped swatch in the sheet calls onChange, and Done closes with the colour kept", {
			id = "native_color_picker::native ColorPicker phone sheet::a tapped swatch in the sheet calls onChange, and Done closes with the colour kept",
			run = function()
				local w, cell, seen = sheet()
				local cells = w.cells("Swatches")
				cells[#cells].Activated:Fire()
				expect(#seen):toBe(1)
				expect((hex(cell:peek()))):toBe("#B03A2E")
				local done = w.find("Actions/Done")
				expect(done ~= nil):toBe(true)
				done.Activated:Fire()
				expect((w.attr("placement"))):toBe("closed")
				expect((hex(cell:peek()))):toBe("#B03A2E")
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native ColorPicker cells, tabs and readout", function()
		verifyHarness:case("the readout leads with a wide preview and lays its fields out in equal columns", {
			id = "native_color_picker::native ColorPicker cells, tabs and readout::the readout leads with a wide preview and lays its fields out in equal columns",
			run = function()
				local cell, _, change = caller(Color3.fromRGB(255, 0, 0))
				local w = world({
					value = cell,
					onChange = change,
					style = "inline" :: "inline",
					modes = { "swatches", "brick" },
				})
				local E = w.E
				local preview = w.find("Readout/Head/Preview")
				expect(preview.Size.X.Offset > preview.Size.Y.Offset):toBe(true)
				expect(preview.Size.Y.Offset):toBe(44)
				local format = w.find("Readout/Head/Format")
				expect(format:FindFirstChildWhichIsA("UIFlexItem").FlexMode):toBe(E.UIFlexMode.Fill)
				local fields = w.find("Readout/Values/Fields")
				expect(fields:FindFirstChildWhichIsA("UIListLayout").HorizontalFlex):toBe(E.UIFlexAlignment.Fill)
				for _, name in { "FieldR", "FieldG", "FieldB" } do
					local size = fields:FindFirstChild(name).Size
					expect(`{name} {size.X.Scale} {size.X.Offset}`):toBe(`{name} 0 0`)
				end
				w.find("Readout/Head/Format/hex").Activated:Fire()
				expect(w.find("Readout/Values/Fields/FieldHex").Size.X.Scale):toBe(1)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native ColorPicker panel fit", function()
		verifyHarness:case("the technique fits the scroll window, never the width under the scrollbar", {
			id = "native_color_picker::native ColorPicker panel fit::the technique fits the scroll window, never the width under the scrollbar",
			run = function()
				local cell, _, change = caller(Color3.fromRGB(255, 0, 0))
				local w = world({ value = cell, onChange = change, modes = { "swatches", "brick" } })
				w.size(w.screen, 1200, 900)
				w.size(w.find("Well"), 44, 44)
				w.open()
				local body = w.find("Body")
				expect(body.VerticalScrollBarInset):toBe(w.E.ScrollBarInset.ScrollBar)
				body.AbsoluteWindowSize = V2(376, 300)
				local size = w.find("Technique").Size
				expect(`{size.X.Scale} {size.X.Offset}`):toBe("0 376")
				local probe = assert(w.find("Technique"):FindFirstChild("LayoutUnit"))
				probe.AbsoluteSize = V2(50, 0.5)
				size = w.find("Technique").Size
				expect(`under a 0.5 UIScale {size.X.Offset}`):toBe("under a 0.5 UIScale 752")
				w.stop()
			end,
		})

		verifyHarness:case("the Sliders tracks start at one x: the labels share the widest label's column", {
			id = "native_color_picker::native ColorPicker panel fit::the Sliders tracks start at one x: the labels share the widest label's column",
			run = function()
				local cell, _, change = caller(Color3.fromRGB(255, 0, 0))
				local w =
					world({ value = cell, onChange = change, style = "inline" :: "inline", modes = { "sliders" } })
				local widths: { [string]: number } = { Hue = 24, Saturation = 70, Brightness = 76 }
				for name, width in widths do
					w.find(`Sliders/{name}/Label`).TextBounds = V2(width, 18)
				end
				for name in widths do
					local label = w.find(`Sliders/{name}/Label`)
					local pad = label:FindFirstChildWhichIsA("UIPadding")
					local inset = pad.PaddingLeft.Offset + pad.PaddingRight.Offset
					expect(`{name} {label.Size.X.Offset}`):toBe(`{name} {76 + inset}`)
				end
				w.stop()
			end,
		})

		verifyHarness:case("an inactive technique reserves at most the body's room, so a short one never scrolls", {
			id = "native_color_picker::native ColorPicker panel fit::an inactive technique reserves at most the body's room, so a short one never scrolls",
			run = function()
				local cell, _, change = caller(Color3.fromRGB(255, 0, 0))
				local w = world({ value = cell, onChange = change, modes = { "swatches", "brick" } })
				w.size(w.screen, 1200, 700)
				w.size(w.find("Well"), 44, 44, 0, 0)
				w.open()
				w.size(w.find("Modes"), 380, 44)
				w.size(w.find("Readout"), 380, 140)
				w.size(w.find("ShowSwatches"), 380, 290)
				w.size(w.find("ShowBricks"), 380, 800)
				local body = w.find("Body").Size.Y.Offset
				expect(body < 800):toBe(true)
				expect(w.find("Technique").Size.Y.Offset):toBe(body)
				w.find("Modes/brick").Activated:Fire()
				expect(w.find("Technique").Size.Y.Offset):toBe(800)
				expect(w.find("Body").Size.Y.Offset):toBe(body)
				w.stop()
			end,
		})
	end)

	return nil
end
