--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local FixtureNavigationTypes = require("../src/ui/navigation_types")

	local Facet = require("../src")
	local worlds = require("./lib/content_world")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose
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
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
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

	verifyHarness:suite("native lab audit: drag and drop", function()
		verifyHarness:case("matrix bounds intrinsic buttons without changing pure helper arguments", {
			id = "native_lab_audit_parity::native lab audit: drag and drop::matrix bounds intrinsic buttons without changing pure helper arguments",
			run = function()
				local available = Compose.cell(353)
				local w = worlds.new(function(UI, Host, engine)
					local props = require("../examples/facet-lab/src/matrix_width")(Compose, {
						Name = "LongMatrixButton",
						label = string.rep("Long label ", 12),
					}, available, true)
					local node = UI.Button(props)
					require("../examples/facet-lab/src/matrix_limit")(
						Compose,
						Host,
						node,
						available,
						engine.types.Vector2
					)
					return node
				end)
				local limit = w.find("MatrixLimit")
				Verify.expect(limit.MaxSize.X):toBe(353)
				available:set(280)
				Verify.expect(limit.MaxSize.X):toBe(280)
				w.stop()
			end,
		})

		verifyHarness:case("Lab successful render clears only its prior refusal", {
			id = "native_lab_audit_parity::native lab audit: drag and drop::Lab successful render clears only its prior refusal",
			run = function()
				local render = require("../examples/facet-lab/src/render_result")
				local errors = { Picker = { playground = "old refusal", S1 = "other refusal" } }
				Verify.expect(render(errors, "Picker", "playground", function()
					return "mounted"
				end)):toBe("mounted")
				Verify.expect(errors.Picker.playground):toBe(nil)
				Verify.expect(errors.Picker.S1):toBe("other refusal")
			end,
		})
		verifyHarness:case("Lab Reset remounts control local state", {
			id = "native_lab_audit_parity::native lab audit: drag and drop::Lab Reset remounts control local state",
			run = function()
				local items = Compose.cell({ { id = "Rating", revision = 0 } })
				local w = worlds.new(function(UI)
					return UI.VStack({
						Compose.keyed({
							from = items,
							key = require("../examples/facet-lab/src/page_key"),
							render = function()
								return UI.Text({ Name = "ResetValue", text = "Before" })
							end,
						}),
					})
				end)
				local old = w.find("ResetValue")
				old.Text = "After"
				items:set({ { id = "Rating", revision = 1 } })
				Verify.expect(w.find("ResetValue").Text):toBe("Before")
				Verify.expect(old.Parent):toBe(nil)
				w.stop()
			end,
		})

		verifyHarness:case("LevelPicker disables custom glyph state for bar segments", {
			id = "native_lab_audit_parity::native lab audit: drag and drop::LevelPicker disables custom glyph state for bar segments",
			run = function()
				local data = require("@lune/luau").load(
					require("@lune/fs").readFile("examples/facet-lab/src/catalog.luau"),
					{ environment = engineLib.new().types }
				)().PAGE_DATA.LevelPicker
				Verify.expect(data.valid({ segment = "bar", glyphs = { filled = "●", empty = "○" } })):toBe(false)
				Verify.expect(data.valid({ segment = "glyph", glyphs = { filled = "●", empty = "○" } })):toBe(true)
			end,
		})

		verifyHarness:case("Lab long label preview gives text a bounded native width", {
			id = "native_lab_audit_parity::native lab audit: drag and drop::Lab long label preview gives text a bounded native width",
			run = function()
				local available = Compose.cell(353)
				local w = worlds.new(function(UI, Host, engine)
					local props = require("../examples/facet-lab/src/matrix_width")(
						Compose,
						{ Name = "BoundedLongLabel", label = string.rep("Long label ", 12) },
						available,
						true,
						engine.types,
						true
					)
					return UI.Button(props)
				end)
				Verify.expect(w.find("BoundedLongLabel").TextTruncate):toBe(w.engine.types.Enum.TextTruncate.AtEnd)
				Verify.expect(w.find("BoundedLongLabel").Size.X.Offset):toBe(353)
				available:set(280)
				Verify.expect(w.find("BoundedLongLabel").Size.X.Offset):toBe(280)
				w.stop()
			end,
		})

		verifyHarness:case("Lab sweep restores options and detects reset and stale focus faults", {
			id = "native_lab_audit_parity::native lab audit: drag and drop::Lab sweep restores options and detects reset and stale focus faults",
			run = function()
				local sweep = require("../examples/facet-lab/src/lab_sweep")
				Verify.expect(sweep.options({
					axes = { { key = "style", values = { "first", "second" } } },
					states = { { name = "disabled" }, { name = "matrix", matrixOnly = true } },
				})):toEqual({ "style=first", "style=second", "style=first", "+disabled", "-disabled" })
				local engine: any = engineLib.new()
				local screen = engine.new("ScreenGui")
				local root = engine.new("Frame")
				root.Parent = screen
				local button = engine.new("TextButton")
				button.Parent = root
				button.Text = "Before"
				local before = sweep.snapshot(root)
				button.AbsolutePosition = engine.types.Vector2.new(200, 500)
				Verify.expect(sweep.same(before, sweep.snapshot(root))):toBe(true)
				button.Text = "After"
				Verify.expect(sweep.same(before, sweep.snapshot(root))):toBe(false)
				Verify.expect(sweep.detached(button, screen)):toBe(false)
				button.Parent = nil
				Verify.expect(sweep.detached(button, screen)):toBe(true)
				Verify.expect(sweep.same(before, sweep.snapshot(root))):toBe(false)
			end,
		})

		verifyHarness:case("Lab sweep records engine parent conflicts without treating every warning as a fault", {
			id = "native_lab_audit_parity::native lab audit: drag and drop::Lab sweep records engine parent conflicts without treating every warning as a fault",
			run = function()
				local sweep: any = require("../examples/facet-lab/src/lab_sweep")
				Verify.expect(
					sweep.engineFault(
						"Something unexpectedly tried to set the parent of Slide to Fade while trying to set the parent of Slide. Current parent is Picker.",
						"MessageWarning"
					)
				):toBe(true)
				Verify.expect(sweep.engineFault("Asset request was retried", "MessageWarning")):toBe(false)
				Verify.expect(sweep.engineFault("An input callback failed", "MessageError")):toBe(true)
			end,
		})

		verifyHarness:case("Lab sweep includes editing and helper sections outside the standard matrix", {
			id = "native_lab_audit_parity::native lab audit: drag and drop::Lab sweep includes editing and helper sections outside the standard matrix",
			run = function()
				local sweep: any = require("../examples/facet-lab/src/lab_sweep")
				local engine: any = engineLib.new()
				local page = engine.new("ScrollingFrame")
				for _, name in { "Header", "Controls", "Playground", "Editing", "Helper_Label", "States" } do
					local child = engine.new("Frame")
					child.Name = name
					child.Parent = page
				end
				Verify.expect(sweep.sections(page)):toEqual({ "Playground", "Editing", "Helper_Label", "States" })
			end,
		})

		verifyHarness:case("Lab sweep keeps a finite inventory when an interaction adds a new row", {
			id = "native_lab_audit_parity::native lab audit: drag and drop::Lab sweep keeps a finite inventory when an interaction adds a new row",
			run = function()
				local sweep: any = require("../examples/facet-lab/src/lab_sweep")
				local engine: any = engineLib.new()
				local page = engine.new("ScrollingFrame")
				local group = engine.new("Frame")
				group.Name = "States"
				group.Parent = page
				local button = engine.new("TextButton")
				button.Name = "Copy"
				button.Parent = group
				local inventory = sweep.inventory(group, page)
				local copy = engine.new("TextButton")
				copy.Name = "NewCopy"
				copy.Parent = group
				Verify.expect(inventory["States[1].Copy[1]"]):toBe(true)
				Verify.expect(inventory["States[1].NewCopy[1]"]):toBe(nil)
				Verify.expect(sweep.inventory(group, page)["States[1].NewCopy[1]"]):toBe(true)
			end,
		})

		verifyHarness:case("Lab sweep distinguishes controls with the same native name", {
			id = "native_lab_audit_parity::native lab audit: drag and drop::Lab sweep distinguishes controls with the same native name",
			run = function()
				local sweep: any = require("../examples/facet-lab/src/lab_sweep")
				local engine: any = engineLib.new()
				local page = engine.new("ScrollingFrame")
				local group = engine.new("Frame")
				group.Parent = page
				for _ = 1, 2 do
					local button = engine.new("TextButton")
					button.Name = "Action"
					button.Parent = group
				end
				local count = 0
				for _ in sweep.inventory(group, page) do
					count += 1
				end
				Verify.expect(count):toBe(2)
			end,
		})

		verifyHarness:case("Lab pinned AdaptiveStack keeps all four commands in a native scroll window", {
			id = "native_lab_audit_parity::native lab audit: drag and drop::Lab pinned AdaptiveStack keeps all four commands in a native scroll window",
			run = function()
				local w = worlds.new(function(UI, Host, engine)
					local data = require("@lune/luau").load(
						require("@lune/fs").readFile("examples/facet-lab/src/catalog.luau"),
						{ environment = engine.types }
					)().PAGE_DATA.AdaptiveStack
					local props = data.base({ UI = UI })
					props.axis = "x"
					props.width = 240
					return data.make(UI, props)
				end)
				local root = w.screen:FindFirstChildWhichIsA("ScrollingFrame", true)
				Verify.expect(root:IsA("ScrollingFrame")):toBe(true)
				Verify.expect(root.ScrollingDirection):toBe(w.engine.types.Enum.ScrollingDirection.X)
				Verify.expect(root.ClipsDescendants):toBe(true)
				local labels = {}
				for _, node in root:GetDescendants() do
					if node:IsA("TextButton") then
						table.insert(labels, node.Text)
					end
				end
				Verify.expect(labels):toEqual({ "Start race", "Garage", "Leaderboard", "Settings" })
				w.stop()
			end,
		})

		verifyHarness:case("pure adaptive matrix decisions keep numeric arguments", {
			id = "native_lab_audit_parity::native lab audit: drag and drop::pure adaptive matrix decisions keep numeric arguments",
			run = function()
				local bounded = (require("../examples/facet-lab/src/matrix_width") :: any)(
					Compose,
					{ width = 360 },
					Compose.cell(300),
					false
				)
				Verify.expect(bounded.width):toBe(360)
				Verify.expect(Facet.adaptive.sizeClass(bounded.width)):toBe("compact")
			end,
		})

		verifyHarness:case("fixed width matrix controls use the offered phone width", {
			id = "native_lab_audit_parity::native lab audit: drag and drop::fixed width matrix controls use the offered phone width",
			run = function()
				local available = Compose.cell(353)
				local w = worlds.new(function(UI)
					local props = require("../examples/facet-lab/src/matrix_width")(Compose, {
						Name = "FixedMatrixControl",
						width = 460,
						maxWidth = 280,
					}, available)
					return UI.AdaptiveStack(props)
				end)
				local node = w.find("FixedMatrixControl")
				Verify.expect(node.Size.X.Offset):toBe(353)
				available:set(807)
				Verify.expect(node.Size.X.Offset):toBe(460)
				Verify.expect(node:FindFirstChildWhichIsA("UISizeConstraint").MaxSize.X):toBe(280)
				w.stop()
			end,
		})

		verifyHarness:case("audit checks text only inside its visible clipping window", {
			id = "native_lab_audit_parity::native lab audit: drag and drop::audit checks text only inside its visible clipping window",
			run = function()
				local visible = require("../examples/facet-lab/src/audit_visible")
				local engine: any = engineLib.new()
				local screen = engine.new("ScreenGui")
				local clip = engine.new("ScrollingFrame")
				clip.Parent = screen
				clip.ClipsDescendants = true
				clip.AbsolutePosition = engine.types.Vector2.new(0, 0)
				clip.AbsoluteSize = engine.types.Vector2.new(300, 200)
				local label = engine.new("TextLabel")
				label.Parent = clip
				label.AbsoluteSize = engine.types.Vector2.new(100, 20)
				label.AbsolutePosition = engine.types.Vector2.new(20, 220)
				Verify.expect(visible(label)):toBe(false)
				label.AbsolutePosition = engine.types.Vector2.new(20, 190)
				Verify.expect(visible(label)):toBe(true)
				label.AbsoluteSize = engine.types.Vector2.new(0, 20)
				Verify.expect(visible(label)):toBe(true)
				screen.Enabled = false
				Verify.expect(visible(label)):toBe(false)
			end,
		})

		verifyHarness:case("AdaptiveStack matrix cells contain the fixed width variants", {
			id = "native_lab_audit_parity::native lab audit: drag and drop::AdaptiveStack matrix cells contain the fixed width variants",
			run = function()
				local engine: any = engineLib.new()
				local fs = require("@lune/fs")
				local luau = require("@lune/luau")
				local catalog = luau.load(fs.readFile("examples/facet-lab/src/catalog.luau"), {
					environment = engine.types,
				})()
				local data = catalog.PAGE_DATA.AdaptiveStack
				for _, axis in data.axes do
					if axis.key == "width" then
						for _, width in axis.values do
							if type(width) == "number" then
								Verify.expect(data.cellWidth >= width):toBe(true)
							end
						end
					end
				end
			end,
		})

		verifyHarness:case("matrix pages display with native Vector2 viewport facts", {
			id = "native_lab_audit_parity::native lab audit: drag and drop::matrix pages display with native Vector2 viewport facts",
			run = function()
				local available = Compose.cell(0)
				local w = worlds.new(function(UI, Host, engine)
					return require("../examples/facet-lab/src/matrix_row")(UI, Compose, {
						Name = "Cells",
						width = "fill",
						wrap = true,
						Host.TextLabel({ Text = "DefaultButton", Size = engine.types.UDim2.fromOffset(200, 44) }),
					}, available)
				end)
				local row = w.find("Cells")
				w.resize(row, 560, 200)
				Verify.expect(available:peek()):toBe(560)
				w.resize(row, 340, 400)
				Verify.expect(available:peek()):toBe(340)
				w.stop()
			end,
		})

		verifyHarness:case("Sheet lab keeps a Close command when interactive dismissal is disabled", {
			id = "native_lab_audit_parity::native lab audit: drag and drop::Sheet lab keeps a Close command when interactive dismissal is disabled",
			run = function()
				local engine: any = engineLib.new()
				local fs = require("@lune/fs")
				local luau = require("@lune/luau")
				local catalog = luau.load(fs.readFile("examples/facet-lab/src/catalog.luau"), {
					environment = engine.types,
				})()
				local data = catalog.PAGE_DATA.Sheet
				local spec = data.base({
					cell = function(_, value)
						return Compose.cell(value)
					end,
				})
				for _, state in data.states do
					if state.name == "no interactive dismiss" then
						for key, value in state.props do
							spec[key] = value
						end
					end
				end
				Verify.expect(spec.interactiveDismissDisabled):toBe(true)
				Verify.expect(spec.closeButton):toBe(true)
			end,
		})

		verifyHarness:case("loads the canvas without mesh APIs and supports touch apply undo and reset", {
			id = "native_lab_audit_parity::native lab audit: drag and drop::loads the canvas without mesh APIs and supports touch apply undo and reset",
			run = function()
				local engine: any = engineLib.new()
				local runtime = Facet.Roblox.createRuntime(engine)
				local Host = runtime.constructors
				local world = engine.new("Folder")
				local screen = engine.new("ScreenGui")
				local input = engine.new("UserInputService")
				input.TouchEnabled, input.KeyboardEnabled, input.GamepadEnabled = true, false, false
				input.PreferredInput = engine.types.Enum.PreferredInput.Touch
				input.GetFocusedTextBox = function()
					return nil
				end
				input.IsKeyDown = function()
					return false
				end
				local UI = Facet.controls(
					runtime,
					{
						types = engine.types,
						inputParent = screen,
						userInputService = input,
						services = { UserInputService = input },
						motionLevel = "none",
					} :: any
				)
				local stop, node: any = runtime.mount(function()
					return require("../examples/facet-lab/src/drag_drop_demo")({
						UI = UI,
						Host = Host,
						Compose = Compose,
						runtime = runtime,
						types = engine.types,
						worldTarget = world,
					})
				end, screen)
				local grid = node:FindFirstChild("AppearanceAssets", true)
				grid.AbsoluteWindowSize = engine.types.Vector2.new(480, 120)
				local canvas = world:FindFirstChild("ImageCanvas", true)
				Verify.expect(canvas:IsA("Part")):toBe(true)
				Verify.expect(canvas:FindFirstChildWhichIsA("Decal") ~= nil):toBe(true)
				local function apply(id)
					local tap = {
						UserInputType = engine.types.Enum.UserInputType.Touch,
						UserInputState = engine.types.Enum.UserInputState.Begin,
					}
					node:FindFirstChild(id, true):FindFirstChild("RowHit", true).Activated:Fire(tap, 1)
					local choice = node:FindFirstChild("ChooseCanvas", true)
					Verify.expect(choice.Visible):toBe(true)
					choice.InputBegan:Fire(tap)
				end
				apply("portrait")
				for _, decal in canvas:GetChildren() do
					if decal:IsA("Decal") then
						Verify.expect(decal.Texture):toBe("rbxassetid://75342910516929")
					end
				end
				node:FindFirstChild("UndoAppearance", true).Activated:Fire()
				Verify.expect(canvas:FindFirstChildWhichIsA("Decal").Texture):toBe("")
				engine.heartbeat:Fire(1)
				apply("Red")
				Verify.expect(canvas.Color):toBe(engine.types.Color3.fromRGB(245, 92, 97))
				node:FindFirstChild("ResetAppearance", true).Activated:Fire()
				Verify.expect(canvas.Color):toBe(engine.types.Color3.fromRGB(180, 180, 180))
				stop()
				Verify.expect(#world:GetChildren()):toBe(0)
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("native lab audit: menu submenu rows", function()
		verifyHarness:case("a submenu row shows its chevron beside a shortcut row, and the shortcut row shows none", {
			id = "native_lab_audit_parity::native lab audit: menu submenu rows::a submenu row shows its chevron beside a shortcut row, and the shortcut row shows none",
			run = function()
				local opened = Compose.cell(false)
				local w = worlds.new(function(UI: FacetControls)
					return UI.Menu({
						isPresented = opened,
						items = {
							{ id = "copy", label = "Copy", shortcutLabel = "Ctrl+C", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
							{
								id = "share",
								label = "Share",
								children = { { id = "mail", label = "Mail", onSelect = function() end } },
							} :: FixtureNavigationTypes.MenuItem<any>,
						},
					})
				end)
				opened:set(true)
				local share, copy = w.find("share"), w.find("copy")
				Verify.expect(share ~= nil and copy ~= nil):toBe(true)
				Verify.expect(w.find("TrailingIcon", share) ~= nil):toBe(true)
				Verify.expect((w.find("TrailingIcon", copy))):toBe(nil)
				Verify.expect(#w.findAll("TrailingIcon", w.screen)):toBe(1)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native lab audit: Slider rung thumb and track floor", function()
		local function cell(axis: "x" | "y", size: ("xsmall" | "compact" | "regular" | "large")?): (any, number)
			local w = worlds.new(function(UI: FacetControls, Host: RobloxHost, engine)
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
			Verify.expect(#thumbs >= 1):toBe(true)
			return w, thumbs[1].Size.X.Offset
		end
		for _, axis in { "x", "y" } do
			verifyHarness:case(`axis {axis}: the track keeps one target of travel in a hugging cell`, {
				id = "native_lab_audit_parity::"
					.. "native lab audit: Slider rung thumb and track floor"
					.. "::"
					.. `axis {axis}: the track keeps one target of travel in a hugging cell`,
				run = function()
					local w = cell(axis :: "x" | "y", nil)
					local floor = w.find("Track"):FindFirstChildWhichIsA("UISizeConstraint")
					Verify.expect(floor ~= nil):toBe(true)
					Verify.expect(if axis == "y" then floor.MinSize.Y else floor.MinSize.X):toBe(44)
					w.stop()
				end,
			})
		end
		verifyHarness:case("compact and large thumbs differ, and regular is the theme's thumb", {
			id = "native_lab_audit_parity::native lab audit: Slider rung thumb and track floor::compact and large thumbs differ, and regular is the theme's thumb",
			run = function()
				local sizes: { [string]: number } = {}
				for _, rung in { "compact", "regular", "large", "none" } :: { "compact" | "large" | "none" | "regular" } do
					local w, size =
						cell("y", if rung == "none" then nil else rung :: "xsmall" | "compact" | "regular" | "large")
					sizes[rung] = size
					w.stop()
				end
				Verify.expect(sizes.compact < sizes.regular and sizes.regular < sizes.large):toBe(true)
				Verify.expect(sizes.regular):toBe(sizes.none)
			end,
		})
	end)

	verifyHarness:suite("native lab audit: ProgressView rungs", function()
		verifyHarness:case(
			"a bar spends its rung on track thickness: small rungs thin, regular and large the theme track",
			{
				id = "native_lab_audit_parity::native lab audit: ProgressView rungs::a bar spends its rung on track thickness: small rungs thin, regular and large the theme track",
				run = function()
					for rung, px in
						{ xsmall = 4, compact = 4, regular = 6, large = 6, none = 6 } :: { [string]: number }
					do
						local w = worlds.new(function(UI: FacetControls)
							return UI.ProgressView("P")({
								value = 0.5,
								controlSize = if rung == "none"
									then nil
									else rung :: "xsmall" | "compact" | "regular" | "large",
							})
						end)
						Verify.expect(`{rung}={w.find("Track").Size.Y.Offset}`):toBe(`{rung}={px}`)
						w.stop()
					end
				end,
			}
		)
		verifyHarness:case("a large ring shows its value in the gauge", {
			id = "native_lab_audit_parity::native lab audit: ProgressView rungs::a large ring shows its value in the gauge",
			run = function()
				local w = worlds.new(function(UI: FacetControls)
					return UI.ProgressView("P")({
						value = 0.65,
						presentation = "circular" :: "circular",
						showValue = true,
						controlSize = "large" :: "large",
						format = function(value: number): string
							return tostring(value)
						end,
					})
				end)
				local value = w.find("Value", w.find("Gauge"))
				Verify.expect(value ~= nil):toBe(true)
				Verify.expect(value.Text):toBe("0.65")
				w.stop()
			end,
		})
		verifyHarness:case("refuses a bar rung with a thickness", {
			id = "native_lab_audit_parity::native lab audit: ProgressView rungs::refuses a bar rung with a thickness",
			run = function()
				local ok, err = pcall(function()
					worlds.new(function(UI: FacetControls)
						return UI.ProgressView("P")({ value = 0.5, controlSize = "compact" :: "compact", thickness = 8 })
					end)
				end)
				Verify.expect(ok):toBe(false)
				Verify.expect(string.find(tostring(err), "not both", 1, true) ~= nil):toBe(true)
				for _, spec in
					{
						{
							presentation = "circular" :: "circular",
							value = 0.5,
							diameter = 64,
							controlSize = "regular" :: "regular",
						},
						{ presentation = "spinner" :: "spinner", controlSize = "huge" :: "huge" },
						{ value = 0.5, endLabel = 7 },
						{ value = 0.5, endLabel = Compose.cell(7 :: any) },
					} :: { { [string]: any } }
				do
					Verify.expect(worlds.mountError(function(UI: FacetControls)
						return UI.ProgressView("P")(spec :: any)
					end) ~= nil):toBe(true)
				end
				Verify.expect((worlds.mountError(function(UI: FacetControls)
					return UI.ProgressView("P")({ value = 0.5, endLabel = "Done" })
				end))):toBeNil()
			end,
		})
	end)

	verifyHarness:suite("native lab audit: Vote and one rung plate height", function()
		verifyHarness:case("a readOnly vote keeps the interactive strip's rung height", {
			id = "native_lab_audit_parity::native lab audit: Vote and one rung plate height::a readOnly vote keeps the interactive strip's rung height",
			run = function()
				local heights: { [string]: number } = {}
				for _, readOnly in { false, true } do
					for _, rung in { "compact", "large" } :: { "compact" | "large" } do
						local w = worlds.new(function(UI: FacetControls)
							return UI.Vote("V")({
								value = "up" :: "up",
								readOnly = readOnly,
								controlSize = rung :: "xsmall" | "compact" | "regular" | "large",
								onChange = function() end,
							})
						end)
						heights[`{readOnly}/{rung}`] = tall(w.find("Opt1", w.find("V")))
						w.stop()
					end
				end
				Verify.expect(heights["true/compact"]):toBe(heights["false/compact"])
				Verify.expect(heights["true/large"]):toBe(heights["false/large"])
				Verify.expect(heights["true/compact"] < heights["true/large"]):toBe(true)
			end,
		})
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
			verifyHarness:case(`{name}: a Button, the segmented track and a checkbox land on one rung height`, {
				id = "native_lab_audit_parity::"
					.. "native lab audit: Vote and one rung plate height"
					.. "::"
					.. `{name}: a Button, the segmented track and a checkbox land on one rung height`,
				run = function()
					local boxes: { number } = {}
					for _, rung in
						{ "xsmall", "compact", "regular", "large" } :: { "compact" | "large" | "regular" | "xsmall" }
					do
						local options = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } }
						local w = worlds.new(function(UI: FacetControls, Host: RobloxHost)
							return Host.Frame({
								Name = "Row",
								UI.Button("B")({
									label = "Settings",
									controlSize = rung :: "xsmall" | "compact" | "regular" | "large",
								}) :: unknown,
								UI.Picker("PM")({
									label = "Theme:",
									style = "menu" :: "menu",
									controlSize = rung :: "xsmall" | "compact" | "regular" | "large",
									selected = Compose.cell("a"),
									options = options,
								}),
								UI.Picker("PS")({
									style = "segmented" :: "segmented",
									controlSize = rung :: "xsmall" | "compact" | "regular" | "large",
									selected = Compose.cell("a"),
									options = options,
								}),
								UI.TextInput("TI")({
									value = Compose.cell("x"),
									controlSize = rung :: "xsmall" | "compact" | "regular" | "large",
								}),
								UI.Toggle("TK")({
									label = "Motion",
									presentation = "checkbox" :: "checkbox",
									controlSize = rung :: "xsmall" | "compact" | "regular" | "large",
									value = Compose.cell(false),
								}),
								UI.Toggle("TC")({
									label = "Reduced Motion",
									presentation = "checkbox" :: "checkbox",
									appearance = "plain" :: "plain",
									controlSize = rung :: "xsmall" | "compact" | "regular" | "large",
									value = Compose.cell(false),
								}),
								UI.Toggle("TS")({
									label = "Music",
									controlSize = rung :: "xsmall" | "compact" | "regular" | "large",
									value = Compose.cell(false),
								}),
							})
						end, { theme = package(name) })
						local button = w.find("B").Size.Y.Offset
						Verify.expect(w.find("PS"):FindFirstChild("TargetFloor").MinSize.Y):toBe(button)
						Verify.expect(`{rung} {button > 0}`):toBe(`{rung} true`)
						local plated = {
							menu = w.find("Trigger", w.find("PM")),
							segmented = w.find("PS"),
							field = w.find("Input", w.find("TI")),
							checkbox = w.find("TK"),
						}
						for key, node in plated :: { [string]: GuiObject } do
							Verify.expect(`{rung} {key} {node.Size.Y.Offset}`):toBe(`{rung} {key} {button}`)
						end
						for _, key in { "TC", "TS" } do
							Verify.expect(`{rung} {key} {w.find(key).Size.Y.Offset <= button}`)
								:toBe(`{rung} {key} true`)
						end
						local box = w.find("Indicator", w.find("TC")).Size
						Verify.expect(`{rung} {box.X.Offset == box.Y.Offset and box.Y.Offset <= button}`)
							:toBe(`{rung} true`)
						table.insert(boxes, box.Y.Offset)
						w.stop()
					end
					Verify.expect(boxes[1] <= boxes[2] and boxes[2] <= boxes[3] and boxes[3] <= boxes[4]):toBe(true)
					Verify.expect(boxes[1] < boxes[4]):toBe(true)
				end,
			})
		end
	end)

	verifyHarness:suite("native lab audit: Badge status mark", function()
		verifyHarness:case("the status mark has no page-colour ring and reads against the badge plate", {
			id = "native_lab_audit_parity::native lab audit: Badge status mark::the status mark has no page-colour ring and reads against the badge plate",
			run = function()
				for _, name in { "neutral", "pixel_quest", "fantasy_ornate" } do
					for _, status in
						{ "warning", "error", "accent", "neutral" } :: { "accent" | "error" | "neutral" | "warning" }
					do
						local w = worlds.new(function(UI: FacetControls)
							return UI.Badge("B")({
								label = "Ready",
								appearance = "status" :: "status",
								status = status :: "accent" | "error" | "neutral" | "warning",
							})
						end, { theme = package(name) })
						Verify.expect(w.find("Status") ~= nil):toBe(true)
						Verify.expect((w.find("Cutout"))):toBe(nil)
						Verify.expect(#tagged(w.screen, "facet-cutout")):toBe(0)
						w.stop()
					end
					local sheet, stop = sheetFor(package(name))
					local plate = assert(rule(sheet, ".facet-badge-status")):GetProperties().BackgroundColor3
					for _, status in
						{ "warning", "error", "accent", "neutral" } :: { "accent" | "error" | "neutral" | "warning" }
					do
						local mark = assert(rule(sheet, ".facet-status-" .. status)):GetProperties().BackgroundColor3
						Verify.expect(`{name} {status} {mark == plate}`):toBe(`{name} {status} false`)
					end
					stop()
				end
			end,
		})
		verifyHarness:case("an unplated utility badge draws no status mark", {
			id = "native_lab_audit_parity::native lab audit: Badge status mark::an unplated utility badge draws no status mark",
			run = function()
				local w = worlds.new(function(UI: FacetControls)
					return UI.Badge("B")({
						label = "Ready",
						appearance = "utility" :: "utility",
						status = "success" :: "success",
					})
				end)
				Verify.expect((w.find("Status"))):toBe(nil)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native lab audit: ShortcutHint keycap outline", function()
		verifyHarness:case("the keycap stroke is a theme metric: Neutral the hairline, 0 draws none", {
			id = "native_lab_audit_parity::native lab audit: ShortcutHint keycap outline::the keycap stroke is a theme metric: Neutral the hairline, 0 draws none",
			run = function()
				local neutral = themes.neutralPackage()
				local sheet, stop = sheetFor(neutral)
				local stroke = assert(rule(sheet, ".facet-shortcut-hint::UIStroke")):GetProperties()
				Verify.expect(stroke.Thickness):toBe(neutral.metrics.strokes.hairline)
				stop()
				for thickness, expected in { [0] = false, [2] = true } :: { [number]: boolean } do
					local soft, report = themes.define({
						base = themes.neutralPackage(),
						identity = {
							id = "soft",
							displayName = "Soft",
							schemaVersion = themes.SCHEMA,
							version = "1.0.0",
						},
						metrics = { controls = { shortcutHint = { capStroke = thickness, capGap = 2 } } },
					} :: any)
					assert(soft ~= nil, tostring(report.errors[1] and report.errors[1].message))
					local other, done = sheetFor(soft)
					local found = rule(other, ".facet-shortcut-hint::UIStroke")
					Verify.expect(found ~= nil):toBe(expected)
					if found then
						Verify.expect(found:GetProperties().Thickness):toBe(thickness)
					end
					done()
				end
			end,
		})
	end)

	verifyHarness:suite("native lab audit: StepIndicator rung marker", function()
		verifyHarness:case("the rung sizes the step marker, and regular is the theme's medium icon", {
			id = "native_lab_audit_parity::native lab audit: StepIndicator rung marker::the rung sizes the step marker, and regular is the theme's medium icon",
			run = function()
				local sizes: { [string]: number } = {}
				for _, rung in { "compact", "regular", "large", "none" } :: { "compact" | "large" | "none" | "regular" } do
					local w = worlds.new(function(UI: FacetControls)
						return UI.StepIndicator("S")({
							steps = {
								{ id = "cart", label = "Cart" },
								{ id = "pay", label = "Pay" },
								{ id = "ship", label = "Ship" },
							},
							current = "ship",
							controlSize = if rung == "none"
								then nil
								else rung :: "xsmall" | "compact" | "regular" | "large",
						})
					end)
					sizes[rung] = w.find("Cue").Size.Y.Offset
					w.stop()
				end
				Verify.expect(sizes.compact <= sizes.regular and sizes.regular < sizes.large):toBe(true)
				Verify.expect(sizes.regular):toBe(sizes.none)
			end,
		})
	end)

	verifyHarness:suite("native lab audit: Notice plate carve", function()
		verifyHarness:case("an art theme's panel carve pads the standard plate; emphasis keeps the plain inset", {
			id = "native_lab_audit_parity::native lab audit: Notice plate carve::an art theme's panel carve pads the standard plate; emphasis keeps the plain inset",
			run = function()
				for _, name in { "neutral", "pixel_quest", "fantasy_ornate", "glossy_mobile" } do
					local theme = package(name)
					local carve = ((theme.chrome or {}).panel or {}).contentInsets or {}
					for _, appearance in { "standard", "emphasis" } :: { "emphasis" | "standard" } do
						local w = worlds.new(function(UI: FacetControls)
							return UI.Notice("Conn")({
								title = "Update available",
								message = "A new track pack is ready.",
								appearance = appearance :: "emphasis" | "standard",
								actions = { { id = "Install", label = "Install", onActivate = function() end } },
								onDismiss = function() end,
							})
						end, { theme = theme })
						local root = w.find("Conn")
						local padding = root:FindFirstChildWhichIsA("UIPadding")
						local want = if appearance == "emphasis" then 8 else math.max(8, carve.left or 0)
						Verify.expect(`{name} {appearance} {padding.PaddingLeft.Offset}`)
							:toBe(`{name} {appearance} {want}`)
						local top = if appearance == "emphasis" then 8 else math.max(8, carve.top or 0)
						Verify.expect(`{name} {appearance} {padding.PaddingTop.Offset}`)
							:toBe(`{name} {appearance} {top}`)
						local title = w.find("Title", root)
						Verify.expect(title.TextWrapped):toBe(true)
						w.stop()
					end
				end
			end,
		})
	end)
end
