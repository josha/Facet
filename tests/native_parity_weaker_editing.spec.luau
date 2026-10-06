--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	local FixtureComposeTypes = require("../src/vendor/compose/core")
	local FixtureCollectionTypes = require("../src/ui/collection_types")
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local perfRunner = require("../bench/perf_runner")
	local perfProfiles = require("../bench/perf_profiles")
	local Compose: ComposeModule = Facet.Compose
	local themes = Facet.themes

	type World = {
		engine: any,
		runtime: any,
		UI: any,
		Host: any,
		gui: any,
		input: any,
		root: any,
		node: any,
		stop: () -> (),
	}

	local function setup(build: (any, any, any, any) -> any, prepare: ((any, any) -> ())?): World
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.KeyboardEnabled = true
		input.GetFocusedTextBox = function()
			return nil
		end
		input.IsKeyDown = function()
			return false
		end
		if prepare then
			prepare(engine, input)
		end
		local root = engine.new("ScreenGui")
		local UI = Facet.controls(
			runtime,
			{
				types = engine.types,
				guiService = gui,
				userInputService = input,
				services = { GuiService = gui, UserInputService = input },
				inputParent = root,
				motionLevel = "none",
			} :: any
		)
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local stop, node: any = runtime.mount(function()
			return build(UI, Host, engine, runtime)
		end, root)
		return {
			engine = engine,
			runtime = runtime,
			UI = UI,
			Host = Host,
			gui = gui,
			input = input,
			root = root,
			node = node,
			stop = function()
				stop()
				runtime:dispose()
			end,
		}
	end

	local function find(root: any, name: string): any
		if root.Name == name then
			return root
		end
		for _, child in root:GetChildren() do
			local found = find(child, name)
			if found then
				return found
			end
		end
		return nil
	end

	local function action(root: any, name: string): any
		for _, child in root:GetDescendants() do
			if child:IsA("InputContext") and child.Name == "Facet" .. name and child.Enabled then
				return child:FindFirstChild(name)
			end
		end
		return nil
	end

	local function deliver(root: any, key: any): { string }
		local contexts = {}
		for _, child in root:GetDescendants() do
			if child:IsA("InputContext") and child.Enabled then
				table.insert(contexts, child)
			end
		end
		table.sort(contexts, function(a, b)
			return a.Priority > b.Priority
		end)
		local received = {}
		for _, context in contexts do
			local matched = false
			for _, inputAction in context:GetChildren() do
				if inputAction:IsA("InputAction") then
					for _, binding in inputAction:GetChildren() do
						if binding:IsA("InputBinding") and binding.KeyCode == key then
							matched = true
							table.insert(received, context.Name)
							inputAction.Pressed:Fire()
							break
						end
					end
				end
			end
			if matched and context.Sink then
				break
			end
		end
		return received
	end

	local function probe(Host: any, engine: any, onPressed: () -> ()): any
		return Host.InputContext "Probe" {
			Priority = 3000,
			Sink = false,
			Enabled = true,
			Host.InputAction "ProbeNavigate" {
				Pressed = onPressed,
				Host.InputBinding({ KeyCode = engine.types.Enum.KeyCode.DPadDown }) :: unknown,
				Host.InputBinding({ KeyCode = engine.types.Enum.KeyCode.Down }),
			},
		}
	end

	local function focusedBox(world: World, field: any)
		world.input.GetFocusedTextBox = function()
			return if field:IsFocused() then field else nil
		end
	end

	local function V2(world: World, x: number, y: number): any
		return world.engine.types.Vector2.new(x, y)
	end

	verifyHarness:suite("native parity weaker editing", function()
		verifyHarness:case(
			"apps-169 keeps the arrows with an editing field and commits it through Tab before advancing",
			{
				id = "native_parity_weaker_editing::native parity weaker editing::apps-169 keeps the arrows with an editing field and commits it through Tab before advancing",
				run = function()
					local commits, value = {}, Compose.cell("hi")
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.TextInput "Name" {
								value = value,
								onCommit = function(text: string, reason: "submit" | "focusLost")
									table.insert(commits, { text, reason })
								end,
							} :: unknown,
							UI.Button "Next" { label = "Next" },
						})
					end)
					local E = world.engine.types.Enum
					local field = find(world.node, "Name")
					focusedBox(world, field)
					world.gui.SelectedObject = field
					field:CaptureFocus()
					Verify.expect(find(world.root, "FacetTextEditing").Enabled):toBe(true)
					for _, key in { E.KeyCode.Down, E.KeyCode.Up, E.KeyCode.Left, E.KeyCode.Right } do
						Verify.expect(deliver(world.root, key)[1]):toBe("FacetTextEditing")
						Verify.expect(world.gui.SelectedObject):toBe(field)
						Verify.expect((field:IsFocused())):toBe(true)
					end
					field.Text = "hi there"
					Verify.expect(#commits):toBe(0)
					local received = deliver(world.root, E.KeyCode.Tab)
					Verify.expect(received):toEqual({ "FacetTraversal" })
					Verify.expect((field:IsFocused())):toBe(false)
					Verify.expect(#commits):toBe(1)
					Verify.expect(commits[1][1]):toBe("hi there")
					Verify.expect(commits[1][2]):toBe("focusLost")
					Verify.expect((value:peek())):toBe("hi there")
					Verify.expect(world.gui.SelectedObject):toBe(find(world.node, "Next"))
					Verify.expect(find(world.root, "FacetTextEditing").Enabled):toBe(false)
					deliver(world.root, E.KeyCode.Tab)
					Verify.expect(world.gui.SelectedObject):toBe(field)
					Verify.expect(#commits):toBe(1)
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"walks a table's idle editable rows with Tab in row order after the rows scroll and recycle",
			{
				id = "native_parity_weaker_editing::native parity weaker editing::walks a table's idle editable rows with Tab in row order after the rows scroll and recycle",
				run = function()
					local rows = {}
					for index = 1, 30 do
						rows[index] = { id = index, name = `Row {index}` }
					end
					local world = setup(function(UI: FacetControls)
						return UI.Table({
							from = rows,
							key = "id",
							itemSize = 20,
							onCellChange = function() end,
							columns = {
								{ id = "name", label = "Name", editor = "text" } :: FixtureCollectionTypes.TableColumn<any, any>,
							},
						})
					end)
					local E = world.engine.types.Enum
					local body = find(world.node, "Body")
					body.AbsoluteWindowSize = V2(world, 300, 100)
					for _, offset in { 200, 400, 120, 0, 60 } do
						body.CanvasPosition = V2(world, 0, offset)
					end
					local function rowOf(node: any): number?
						local at = node
						while at and at ~= body do
							if at.Parent and at.Parent.Name == "Items" then
								return tonumber(at.Name)
							end
							at = at.Parent
						end
						return nil
					end
					local editors = {}
					for _, node in body:GetDescendants() do
						if node.Name == "RowHit" and rowOf(node) then
							table.insert(editors, node)
						end
					end
					table.sort(editors, function(a, b)
						return (rowOf(a) :: number) < (rowOf(b) :: number)
					end)
					Verify.expect(#editors >= 3):toBe(true)
					world.gui.SelectedObject = editors[1]
					local walked = { rowOf(editors[1]) }
					for _ = 1, 40 do
						deliver(world.root, E.KeyCode.Tab)
						local current = world.gui.SelectedObject
						if current and current.Name == "RowHit" and rowOf(current) then
							if current == editors[1] then
								break
							end
							table.insert(walked, rowOf(current))
						end
					end
					local expected = {}
					for index, editor in editors do
						expected[index] = rowOf(editor)
					end
					Verify.expect((table.concat(walked, ","))):toBe(table.concat(expected, ","))
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"inputs-181 enters editing on native focus once and keeps the edit and its snapshot on a repeat",
			{
				id = "native_parity_weaker_editing::native parity weaker editing::inputs-181 enters editing on native focus once and keeps the edit and its snapshot on a repeat",
				run = function()
					local value, changes, commits, cancels = Compose.cell("seed"), {}, {}, 0
					local probed = 0
					local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
						return Host.Frame({
							probe(Host, engine, function()
								probed += 1
							end) :: unknown,
							UI.TextInput "Name" {
								value = value,
								onChange = function(text)
									value:set(text)
									table.insert(changes, text)
								end,
								onCommit = function(text: string, reason: "submit" | "focusLost")
									table.insert(commits, { text, reason })
								end,
								onCancel = function()
									cancels += 1
								end,
							},
						})
					end)
					local E = world.engine.types.Enum
					local field = find(world.node, "Name")
					world.gui.SelectedObject = field
					Verify.expect((action(world.root, "TextEditing"))):toBe(nil)
					field:CaptureFocus()
					Verify.expect(action(world.root, "TextEditing") ~= nil):toBe(true)
					field.Text = "seedX"
					Verify.expect((value:peek())):toBe("seedX")
					field.Focused:Fire()
					Verify.expect((field:IsFocused())):toBe(true)
					Verify.expect(action(world.root, "TextEditing") ~= nil):toBe(true)
					Verify.expect(#commits):toBe(0)
					Verify.expect(changes):toEqual({ "seedX" })
					deliver(world.root, E.KeyCode.DPadDown)
					Verify.expect(probed):toBe(0)
					action(world.root, "Cancel").Pressed:Fire()
					Verify.expect((value:peek())):toBe("seed")
					Verify.expect(field.Text):toBe("seed")
					Verify.expect(cancels):toBe(1)
					Verify.expect(#commits):toBe(0)
					Verify.expect((field:IsFocused())):toBe(false)
					Verify.expect(world.gui.SelectedObject):toBe(field)
					deliver(world.root, E.KeyCode.DPadDown)
					Verify.expect(probed):toBe(1)
					field:CaptureFocus()
					Verify.expect(action(world.root, "TextEditing") ~= nil):toBe(true)
					field:ReleaseFocus(true)
					Verify.expect(#commits):toBe(1)
					Verify.expect(commits[1][1]):toBe("seed")
					Verify.expect(commits[1][2]):toBe("submit")
					Verify.expect((action(world.root, "TextEditing"))):toBe(nil)
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"inputs-137 carries an edit across device arrivals and commits it once when the editing surface leaves",
			{
				id = "native_parity_weaker_editing::native parity weaker editing::inputs-137 carries an edit across device arrivals and commits it once when the editing surface leaves",
				run = function()
					local value, commits, probed = Compose.cell(""), {}, 0
					local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
						return Host.Frame({
							probe(Host, engine, function()
								probed += 1
							end) :: unknown,
							UI.TextInput "Name" {
								value = value,
								onCommit = function(text: string, reason: "submit" | "focusLost")
									table.insert(commits, { text, reason })
								end,
							},
						})
					end, function(_, input)
						input.TouchEnabled = true
						input.KeyboardEnabled = false
						input.GamepadEnabled = false
					end)
					local E = world.engine.types.Enum
					local field = find(world.node, "Name")
					field:CaptureFocus()
					field.Text = "hi"
					deliver(world.root, E.KeyCode.DPadDown)
					Verify.expect(probed):toBe(0)
					world.input.GamepadEnabled = true
					Verify.expect((field:IsFocused())):toBe(true)
					Verify.expect((value:peek())):toBe("hi")
					Verify.expect(#commits):toBe(0)
					world.input.KeyboardEnabled = true
					world.input.TouchEnabled = false
					Verify.expect((field:IsFocused())):toBe(true)
					Verify.expect(find(world.root, "FacetTextEditing").Enabled):toBe(true)
					Verify.expect(#commits):toBe(0)
					world.input.TouchEnabled = true
					world.input.KeyboardEnabled = false
					Verify.expect((field:IsFocused())):toBe(true)
					world.input.TouchEnabled = false
					Verify.expect((field:IsFocused())):toBe(false)
					Verify.expect(#commits):toBe(1)
					Verify.expect(commits[1][1]):toBe("hi")
					Verify.expect(commits[1][2]):toBe("focusLost")
					Verify.expect((value:peek())):toBe("hi")
					Verify.expect(find(world.root, "FacetTextEditing").Enabled):toBe(false)
					deliver(world.root, E.KeyCode.DPadDown)
					Verify.expect(probed):toBe(1)
					world.stop()
				end,
			}
		)

		verifyHarness:case("inputs-141 follows the engine preferred input and ignores raw pointer and stick noise", {
			id = "native_parity_weaker_editing::native parity weaker editing::inputs-141 follows the engine preferred input and ignores raw pointer and stick noise",
			run = function()
				local env: any, published = nil, 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					env = UI.environment(engine.new("ScreenGui"))
					Compose.watch(function(use: Use)
						use(env.effectiveInput)
						published += 1
					end)
					return Host.Frame({})
				end, function(engine, input)
					input.MouseEnabled = true
					input.KeyboardEnabled = true
					input.GamepadEnabled = true
					input.TouchEnabled = false
					input.PreferredInput = engine.types.Enum.PreferredInput.Gamepad
				end)
				local E = world.engine.types.Enum
				local classes = env.interactionClasses:peek()
				Verify.expect(classes.primary):toBe("gamepad")
				Verify.expect(classes.pointer):toBe(true)
				Verify.expect(classes.gamepad):toBe(true)
				Verify.expect((env.effectiveInput:peek())):toBe("Gamepad")
				local before = published
				for _ = 1, 20 do
					world.input.InputChanged:Fire({
						UserInputType = E.UserInputType.Gamepad1,
						KeyCode = E.KeyCode.Thumbstick1,
						Position = world.engine.types.Vector3.new(0.1, 0, 0),
					})
					world.input.InputChanged:Fire({
						UserInputType = E.UserInputType.MouseMovement,
						KeyCode = E.KeyCode:FromValue(0),
						Position = world.engine.types.Vector3.new(10, 10, 0),
					})
				end
				world.input.InputBegan:Fire({
					UserInputType = E.UserInputType.MouseButton1,
					KeyCode = E.KeyCode:FromValue(0),
				})
				Verify.expect(published):toBe(before)
				Verify.expect((env.effectiveInput:peek())):toBe("Gamepad")
				world.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
				Verify.expect(published):toBe(before + 1)
				classes = env.interactionClasses:peek()
				Verify.expect(classes.primary):toBe("pointer")
				Verify.expect(classes.gamepad):toBe(true)
				Verify.expect((env.effectiveInput:peek())):toBe("KeyboardAndMouse")
				for _ = 1, 10 do
					world.input.InputChanged:Fire({
						UserInputType = E.UserInputType.MouseMovement,
						KeyCode = E.KeyCode:FromValue(0),
						Position = world.engine.types.Vector3.new(20, 20, 0),
					})
				end
				Verify.expect(published):toBe(before + 1)
				world.input.PreferredInput = E.PreferredInput.Gamepad
				Verify.expect(env.interactionClasses:peek().primary):toBe("gamepad")
				Verify.expect(published):toBe(before + 2)
				world.input.TouchEnabled = true
				world.input.PreferredInput = E.PreferredInput.Touch
				Verify.expect(env.interactionClasses:peek().primary):toBe("touch")
				Verify.expect((env.effectiveInput:peek())):toBe("Touch")
				world.input.TouchEnabled = false
				world.input.MouseEnabled = false
				world.input.KeyboardEnabled = false
				world.input.PreferredInput = E.PreferredInput.Gamepad
				world.input.InputBegan:Fire({ UserInputType = E.UserInputType.Touch, KeyCode = E.KeyCode:FromValue(0) })
				classes = env.interactionClasses:peek()
				Verify.expect(classes.primary):toBe("gamepad")
				Verify.expect(classes.pointer):toBe(false)
				world.stop()
				world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					env = UI.environment(engine.new("ScreenGui"))
					return Host.Frame({})
				end, function(engine, input)
					input.MouseEnabled = true
					input.KeyboardEnabled = true
					input.GamepadEnabled = false
					input.TouchEnabled = false
					input.PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
				end)
				classes = env.interactionClasses:peek()
				Verify.expect(classes.primary):toBe("pointer")
				Verify.expect(classes.gamepad):toBe(false)
				Verify.expect((env.effectiveInput:peek())):toBe("KeyboardAndMouse")
				world.stop()
			end,
		})

		verifyHarness:case(
			"inputs-122 keeps the field frame outside a native viewport and keeps newlines until focus loss",
			{
				id = "native_parity_weaker_editing::native parity weaker editing::inputs-122 keeps the field frame outside a native viewport and keeps newlines until focus loss",
				run = function()
					local value, commits = Compose.cell("Notes"), {}
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.TextInput "Editor" {
								value = value,
								multiline = true,
								visibleLines = 4,
								onCommit = function(text: string, reason: "submit" | "focusLost")
									table.insert(commits, { text, reason })
								end,
							},
						})
					end)
					local root = find(world.node, "Editor")
					Verify.expect(root.ClassName):toBe("Frame")
					local viewport = find(root, "Viewport")
					Verify.expect(viewport.ClassName):toBe("ScrollingFrame")
					local field = find(viewport, "Field")
					Verify.expect(field.ClassName):toBe("TextBox")
					Verify.expect(field.MultiLine):toBe(true)
					Verify.expect((field:IsDescendantOf(viewport))):toBe(true)
					local plate = find(root, "Input")
					Verify.expect((plate:HasTag("facet-field"))):toBe(true)
					Verify.expect(plate:FindFirstChildWhichIsA("UIPadding") ~= nil):toBe(true)
					Verify.expect((viewport:IsDescendantOf(plate))):toBe(true)
					local viewportSize = viewport.Size
					field:CaptureFocus()
					field.Text = "first\nsecond"
					Verify.expect((value:peek())):toBe("first\nsecond")
					Verify.expect((field:IsFocused())):toBe(true)
					Verify.expect(#commits):toBe(0)
					local long = string.rep("A line of notes.\n", 14)
					field.Text = long
					local flow = find(viewport, "Flow")
					flow.AbsoluteSize = V2(world, 300, 14 * 21)
					Verify.expect(viewport.CanvasSize.Y.Offset):toBe(14 * 21)
					Verify.expect(viewport.Size):toBe(viewportSize)
					Verify.expect((find(world.node, "Editor"))):toBe(root)
					Verify.expect((find(viewport, "Field"))):toBe(field)
					field:ReleaseFocus(false)
					Verify.expect(#commits):toBe(1)
					Verify.expect(commits[1][1]):toBe(long)
					Verify.expect(commits[1][2]):toBe("focusLost")
					Verify.expect((value:peek())):toBe(long)
					world.stop()
					local grown = Compose.cell("Lap")
					world = setup(function(UI: FacetControls)
						return UI.TextInput "Plain" { value = grown, multiline = true }
					end)
					local plain = world.node
					Verify.expect(plain.ClassName):toBe("TextBox")
					local measure = plain:FindFirstChild("Measure")
					Verify.expect(measure.ClassName):toBe("TextLabel")
					Verify.expect(plain.Size.Y.Offset):toBe(96)
					plain:CaptureFocus()
					plain.Text = "Lap" .. string.rep("\nLap", 15) .. "\n"
					Verify.expect(measure.Text):toBe(plain.Text .. " ")
					measure.TextBounds = V2(world, 200, 17 * 16)
					Verify.expect(plain.Size.Y.Offset):toBe(17 * 16 + 16)
					Verify.expect((plain:IsFocused())):toBe(true)
					world.stop()
					local ornate = (require :: any)("../examples/themes/fantasy_ornate").build(themes)
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local stop, sheet: any = runtime.mount(function()
						return themes.createStyleSheet(runtime, ornate, { types = engine.types } :: any)
					end, engine.new("Folder"))
					local inset = ((ornate.chrome or {}).field or {}).contentInsets or {}
					local rule
					for _, node in sheet:GetChildren() do
						if node.Selector == ".facet-field::UIPadding" then
							rule = node
						end
					end
					Verify.expect(rule ~= nil):toBe(true)
					local padding = rule:GetProperties()
					Verify.expect(padding.PaddingLeft.Offset):toBe(math.max(0, inset.left or 0))
					Verify.expect(padding.PaddingRight.Offset):toBe(math.max(0, inset.right or 0))
					Verify.expect(padding.PaddingTop.Offset):toBe(math.max(0, inset.top or 0))
					Verify.expect(padding.PaddingBottom.Offset):toBe(math.max(0, inset.bottom or 0))
					Verify.expect((inset.left or 0) > 0):toBe(true)
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("collections-53 re-derives an open tray button width when the preferred text size changes", {
			id = "native_parity_weaker_editing::native parity weaker editing::collections-53 re-derives an open tray button width when the preferred text size changes",
			run = function()
				local open: FixtureComposeTypes.Cell<("leading" | "trailing")?> =
					Compose.cell("trailing" :: ("leading" | "trailing")?)
				local world = setup(function(UI: FacetControls)
					return UI.RowActions({
						open = open,
						content = UI.Button("Action")({ label = "Row" }) :: GuiObject,
						trailing = {
							{ id = "Delete", label = "Delete", role = "destructive" :: "destructive" } :: FixtureCollectionTypes.RowAction,
						},
					})
				end)
				local row = world.node
				row.AbsoluteSize = V2(world, 400, 44)
				local tray = find(row, "trailing")
				local button = find(tray, "Delete")
				local content = find(row, "Content")
				Verify.expect(tray.Visible):toBe(true)
				button.TextBounds = V2(world, 44, 20)
				Verify.expect(tray.Size.X.Offset):toBe(88)
				Verify.expect(content.Position.X.Offset):toBe(-88)
				world.gui.PreferredTextSize = world.engine.types.Enum.PreferredTextSize.Largest
				button.TextBounds = V2(world, 96, 30)
				Verify.expect((open:peek())):toBe("trailing")
				Verify.expect((find(tray, "Delete"))):toBe(button)
				Verify.expect(tray.Size.X.Offset):toBe(128)
				Verify.expect(content.Position.X.Offset):toBe(-128)
				world.gui.PreferredTextSize = world.engine.types.Enum.PreferredTextSize.Medium
				button.TextBounds = V2(world, 44, 20)
				Verify.expect(tray.Size.X.Offset):toBe(88)
				Verify.expect(content.Position.X.Offset):toBe(-88)
				open:set(nil)
				button.TextBounds = V2(world, 110, 30)
				open:set("trailing")
				Verify.expect(tray.Size.X.Offset):toBe(142)
				world.stop()
			end,
		})

		verifyHarness:case("apps-260 retires a presence region until its exit completes and reuses it on re-entry", {
			id = "native_parity_weaker_editing::native parity weaker editing::apps-260 retires a presence region until its exit completes and reuses it on re-entry",
			run = function()
				local shown, done = Compose.cell(true), Compose.cell(false)
				local built, cleaned, phase = 0, 0, nil :: any
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame "Holder" {
						UI.Button "Toggle" {
							label = "Toggle",
							onActivate = function()
								shown:set(not shown:peek())
							end,
						} :: unknown,
						Host.Frame "Region" {
							Compose.presence(shown, function(current)
								built += 1
								phase = current
								Compose.cleanup(function()
									cleaned += 1
								end)
								return Host.Frame "Panel" {}
							end, {
								exit = function()
									done:set(false)
									return { completed = done }
								end,
							}),
						},
					}
				end)
				local toggle = find(world.node, "Toggle")
				local region = find(world.node, "Region")
				local first = find(region, "Panel")
				Verify.expect(first ~= nil):toBe(true)
				Verify.expect(built):toBe(1)
				toggle.Activated:Fire()
				Verify.expect((find(region, "Panel"))):toBe(first)
				Verify.expect(cleaned):toBe(0)
				Verify.expect((phase.exiting:peek())):toBe(true)
				toggle.Activated:Fire()
				Verify.expect((find(region, "Panel"))):toBe(first)
				Verify.expect(built):toBe(1)
				Verify.expect((phase.exiting:peek())):toBe(false)
				toggle.Activated:Fire()
				done:set(true)
				Verify.expect(cleaned):toBe(1)
				Verify.expect((find(region, "Panel"))):toBeNil()
				done:set(false)
				done:set(true)
				Verify.expect(cleaned):toBe(1)
				local baseline = #region:GetDescendants()
				for _ = 1, 20 do
					toggle.Activated:Fire()
					toggle.Activated:Fire()
					done:set(true)
				end
				Verify.expect(built):toBe(21)
				Verify.expect(cleaned):toBe(21)
				Verify.expect(#region:GetDescendants()):toBe(baseline)
				Verify.expect((find(region, "Panel"))):toBeNil()
				world.stop()
			end,
		})

		verifyHarness:case("apps2-161 counts the registrations that the application owner of a scene holds", {
			id = "native_parity_weaker_editing::native parity weaker editing::apps2-161 counts the registrations that the application owner of a scene holds",
			run = function()
				local function scene(watchers: number)
					return {
						name = `registrations-{watchers}`,
						requirement = "UI-PERF-001",
						dataset = `{watchers} watchers`,
						setup = function()
							local core = Compose.createRootOwner(function() end)
							local source = Compose.cell(0)
							for _ = 1, watchers do
								core.owner.watch(function(use: Use)
									use(source)
								end)
							end
							return { core = core, source = source, n = 0 }
						end,
						run = function(state: any)
							state.n += 1
							state.source:set(state.n)
							return nil
						end,
						teardown = function(state: any)
							state.core.dispose()
						end,
					}
				end
				local profile = perfProfiles.get(perfProfiles.REFERENCE)
				local one = perfRunner.runScene(scene(1), profile, { warmup = 1, samples = 3 })
				local five = perfRunner.runScene(scene(5), profile, { warmup = 1, samples = 3 })
				Verify.expect((type(one.liveRegistry.registrations))):toBe("number")
				Verify.expect(one.liveRegistry.registrations >= 1):toBe(true)
				Verify.expect(five.liveRegistry.registrations - one.liveRegistry.registrations):toBe(4)
				Verify.expect(five.metrics.connections.reactiveRegistrations):toBe(five.liveRegistry.registrations)
				local blind = perfRunner.runScene({
					name = "no-owner",
					requirement = "UI-PERF-001",
					dataset = "none",
					setup = function()
						return {}
					end,
					run = function()
						return nil
					end,
				}, profile, { warmup = 1, samples = 2 })
				Verify.expect(blind.liveRegistry.registrations.measured):toBe(false)
			end,
		})

		verifyHarness:case(
			"mech1-115 rethrows a failure outside every boundary to the writer and contains one inside",
			{
				id = "native_parity_weaker_editing::native parity weaker editing::mech1-115 rethrows a failure outside every boundary to the writer and contains one inside",
				run = function()
					local outside, inside = Compose.cell(false), Compose.cell(false)
					local reported = {}
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							Compose.show(outside, function()
								error("outside failure", 0)
							end) :: unknown,
							UI.ErrorBoundary "Guard" {
								view = function()
									return Host.Frame({
										Compose.show(inside, function()
											error("inside failure", 0)
										end),
									})
								end,
								fallback = function()
									return Host.TextLabel "Fallback" { Text = "broken" }
								end,
								onError = function(failure)
									table.insert(reported, tostring(failure))
								end,
							},
							Host.TextLabel "Sibling" { Text = "ok" },
						})
					end)
					local ok = pcall(function()
						inside:set(true)
					end)
					Verify.expect(ok):toBe(true)
					Verify.expect(#reported):toBe(1)
					Verify.expect(string.find(reported[1], "inside failure", 1, true) ~= nil):toBe(true)
					Verify.expect(find(world.node, "Fallback") ~= nil):toBe(true)
					Verify.expect(find(world.node, "Sibling") ~= nil):toBe(true)
					local failed, message = pcall(function()
						outside:set(true)
					end)
					Verify.expect(failed):toBe(false)
					Verify.expect(string.find(tostring(message), "outside failure", 1, true) ~= nil):toBe(true)
					Verify.expect(#reported):toBe(1)
					world.stop()
				end,
			}
		)
	end)
end
