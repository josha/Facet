--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local nativeDrag = require("./lib/native_drag")

	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	local FixtureComposeTypes = require("../src/vendor/compose/core")
	local FixtureCollectionTypes = require("../src/ui/collection_types")

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
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

	local function setup(build: (any, any, any) -> any, options: { [string]: any }?): World
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		input.IsKeyDown = function()
			return false
		end
		local root = engine.new("ScreenGui")
		local config: { [string]: any } = {
			types = engine.types,
			guiService = gui,
			services = { GuiService = gui, UserInputService = input },
			userInputService = input,
			inputParent = root,
			motionLevel = "none",
		}
		for field, value in (options or {}) :: { [string]: any } do
			config[field] = value
		end
		local UI = Facet.controls(runtime, config :: any)
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local stop, node: any = runtime.mount(function()
			return build(UI, Host, engine)
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
		if root == nil then
			return nil
		end
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

	local function V2(world: World, x: number, y: number): any
		return world.engine.types.Vector2.new(x, y)
	end

	local function E(world: World): any
		return world.engine.types.Enum
	end

	local function frames(world: World, count: number)
		for _ = 1, count do
			world.engine.heartbeat:Fire(1 / 60)
		end
	end

	local function rows(count: number): { any }
		local out = {}
		for index = 1, count do
			out[index] = { id = "r" .. index, name = "Row " .. index, laps = index }
		end
		return out
	end

	local function inputOf(world: World, kind: string, keyCode: string?): any
		local enum = E(world)
		return {
			UserInputType = (enum.UserInputType :: any)[kind],
			KeyCode = if keyCode then (enum.KeyCode :: any)[keyCode] else enum.KeyCode:FromValue(0),
			UserInputState = enum.UserInputState.Begin,
			Position = world.engine.types.Vector3.new(0, 0, 0),
		}
	end

	local function select(world: World, node: any)
		local previous = world.gui.SelectedObject
		world.gui.SelectedObject = node
		if previous and previous ~= node then
			previous.SelectionLost:Fire()
		end
		if node and previous ~= node then
			node.SelectionGained:Fire()
		end
	end

	local function sheetFor(world: World, package: any): any
		local _, sheet = world.runtime.mount(function()
			return themes.createStyleSheet(
				world.runtime,
				package,
				{ types = world.engine.types, preferredTransparency = 1, motionLevel = "normal" } :: any
			)
		end, world.engine.new("Folder"))
		return sheet
	end

	local function compound(text: string): any
		local tags = {}
		for tag in string.gmatch(text, "%.([%w%-]+)") do
			table.insert(tags, tag)
		end
		return { class = string.match(text, "^(%a%w*)"), tags = tags, state = string.match(text, ":(%a+)$") }
	end

	local function parse(selector: string): any
		local pseudo = string.match(selector, "::(%a+)$")
		local rest = if pseudo then string.sub(selector, 1, -(#pseudo + 3)) else selector
		local parts, combinators = {}, {}
		while true do
			local first, last, combinator = string.find(rest, " (>>?) ")
			if not first then
				table.insert(parts, compound(rest))
				break
			end
			table.insert(parts, compound(string.sub(rest, 1, first - 1)))
			table.insert(combinators, combinator)
			rest = string.sub(rest, (last :: number) + 1)
		end
		return { parts = parts, combinators = combinators, pseudo = pseudo }
	end

	local function matchesPart(part: any, node: any): boolean
		if part.class and not node:IsA(part.class) then
			return false
		end
		for _, tag in part.tags do
			if not node:HasTag(tag) then
				return false
			end
		end
		if part.state then
			local ok, state = pcall(function()
				return node.GuiState
			end)
			if not ok or state == nil or state.Name ~= part.state then
				return false
			end
		end
		return true
	end

	local function matchesAt(selector: any, index: number, node: any): boolean
		if not matchesPart(selector.parts[index], node) then
			return false
		end
		if index == 1 then
			return true
		end
		local parent = node.Parent
		if selector.combinators[index - 1] == ">" then
			return parent ~= nil and matchesAt(selector, index - 1, parent)
		end
		while parent do
			if matchesAt(selector, index - 1, parent) then
				return true
			end
			parent = parent.Parent
		end
		return false
	end

	local function resolve(sheet: any, node: any, property: string, pseudo: string?): any
		local best, value = -math.huge, nil
		for _, rule in sheet:GetChildren() do
			local selector = parse(rule.Selector)
			if selector.pseudo == pseudo and matchesAt(selector, #selector.parts, node) then
				local candidate = rule:GetProperties()[property]
				if candidate ~= nil and rule.Priority >= best then
					best, value = rule.Priority, candidate
				end
			end
		end
		return value
	end

	local function tableWorld(spec: { [string]: any }, options: { [string]: any }?): (World, any)
		local world = setup(function(UI: FacetControls)
			local base: { [any]: any } = {
				from = rows(20),
				key = "id",
				columns = {
					{ id = "name", label = "Name" } :: FixtureCollectionTypes.TableColumn<any, any>,
					{ id = "laps", label = "Laps", width = 80 } :: FixtureCollectionTypes.TableColumn<any, any>,
				},
			}
			for field, value in spec do
				base[field] = value
			end
			return UI.Table(base)
		end, options)
		local body = find(world.node, "Body")
		body.AbsoluteWindowSize = V2(world, 400, 200)
		nativeDrag.measure(body)
		body.AbsoluteSize = V2(world, 400, 200)
		return world, body
	end

	local function rowFrame(body: any, key: string): any
		local items = find(body, "Items")
		return if items then items:FindFirstChild(key, true) else nil
	end

	verifyHarness:suite("native parity classb collections", function()
		verifyHarness:case("collections-29 the cross axis of each row fills the collection window by default", {
			id = "native_parity_classb_collections::native parity classb collections::collections-29 the cross axis of each row fills the collection window by default",
			run = function()
				for _, direction in { "vertical", "horizontal" } :: { "horizontal" | "vertical" } do
					local world = setup(function(UI: FacetControls)
						return UI.VirtualList({
							from = rows(30),
							key = "id",
							itemSize = 60,
							direction = direction :: "horizontal" | "vertical",
							render = function(current): GuiObject
								return UI.Text({ text = current:peek().name })
							end,
						})
					end)
					local list = world.node
					local horizontal = direction == "horizontal"
					list.AbsoluteWindowSize = if horizontal then V2(world, 480, 200) else V2(world, 320, 240)
					list.AbsoluteSize = list.AbsoluteWindowSize
					local row = rowFrame(list, "r1")
					Verify.expect(row ~= nil):toBe(true)
					if horizontal then
						Verify.expect(row.Size.X.Offset):toBe(60)
						Verify.expect(row.Size.Y.Offset):toBe(200)
						Verify.expect(row.Size.Y.Scale):toBe(0)
					else
						Verify.expect(row.Size.Y.Offset):toBe(60)
						Verify.expect(row.Size.X.Offset):toBe(320)
						Verify.expect(row.Size.X.Scale):toBe(0)
					end
					list.AbsoluteWindowSize = if horizontal then V2(world, 480, 150) else V2(world, 250, 240)
					if horizontal then
						Verify.expect(row.Size.Y.Offset):toBe(150)
					else
						Verify.expect(row.Size.X.Offset):toBe(250)
					end
					world.stop()
				end
				local grid = setup(function(UI: FacetControls)
					return UI.VirtualGrid({
						from = rows(30),
						key = "id",
						columns = 4,
						itemSize = 60,
						render = function(current): GuiObject
							return UI.Text({ text = current:peek().name })
						end,
					})
				end)
				grid.node.AbsoluteWindowSize = V2(grid, 400, 300)
				local cell = rowFrame(grid.node, "r2")
				Verify.expect(cell.Size.X.Offset):toBe(100)
				Verify.expect(cell.Position.X.Offset):toBe(100)
				grid.stop()
			end,
		})

		verifyHarness:case("collections-42 a table keeps its engine scroll position when the input class flips", {
			id = "native_parity_classb_collections::native parity classb collections::collections-42 a table keeps its engine scroll position when the input class flips",
			run = function()
				local world, body = tableWorld({
					reorderable = true,
					onReorder = function() end,
					selectionMode = "multiple" :: "multiple",
				})
				local enum = E(world)
				world.input.PreferredInput = enum.PreferredInput.Touch
				world.input.TouchEnabled = true
				world.input.KeyboardEnabled = false
				world.input.GamepadEnabled = false
				world.input.MouseEnabled = false
				frames(world, 2)
				body.CanvasPosition = V2(world, 0, 120)
				frames(world, 2)
				Verify.expect(body.CanvasPosition.Y):toBe(120)
				local writes = 0
				body:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
					writes += 1
				end)
				world.input.KeyboardEnabled = true
				world.input.GamepadEnabled = true
				world.input.PreferredInput = enum.PreferredInput.Gamepad
				frames(world, 4)

				Verify.expect(body.CanvasPosition.Y):toBe(2 * 44 + 8)
				writes = 0
				world.input.PreferredInput = enum.PreferredInput.KeyboardAndMouse
				world.input.TouchEnabled = false
				world.input.MouseEnabled = true
				frames(world, 4)
				Verify.expect(rowFrame(body, "r4") ~= nil):toBe(true)
				Verify.expect(body.CanvasPosition.Y):toBe(2 * 44 + 8)
				Verify.expect(writes):toBe(0)
				world.stop()
			end,
		})
		verifyHarness:case(
			"collections-54 a destructive tray action and a default tray action resolve different paint",
			{
				id = "native_parity_classb_collections::native parity classb collections::collections-54 a destructive tray action and a default tray action resolve different paint",
				run = function()
					local open: FixtureComposeTypes.Cell<("leading" | "trailing")?> =
						Compose.cell("trailing" :: ("leading" | "trailing")?)
					local world = setup(function(UI: FacetControls)
						return UI.RowActions({
							open = open,
							content = UI.Text({ text = "Row" }),
							trailing = {
								{ id = "delete", label = "Delete", role = "destructive" :: "destructive" } :: FixtureCollectionTypes.RowAction,
								{ id = "flag", label = "Flag" } :: FixtureCollectionTypes.RowAction,
							},
						})
					end)
					world.node.AbsoluteSize = V2(world, 300, 44)
					local sheet = sheetFor(world, themes.neutralPackage())
					local tray = find(world.node, "trailing")
					local delete, flag = find(tray, "delete"), find(tray, "flag")
					Verify.expect((delete:HasTag("facet-role-destructive"))):toBe(true)
					Verify.expect((delete:HasTag("facet-role-default"))):toBe(false)
					Verify.expect((flag:HasTag("facet-role-default"))):toBe(true)
					Verify.expect((flag:HasTag("facet-role-destructive"))):toBe(false)
					local danger = resolve(sheet, delete, "BackgroundColor3")
					local plain = resolve(sheet, flag, "BackgroundColor3")
					Verify.expect(danger ~= nil and plain ~= nil):toBe(true)
					Verify.expect(danger ~= plain):toBe(true)
					local rule
					for _, node in sheet:GetChildren() do
						if node.Selector == ".facet-role-destructive" then
							rule = node
						end
					end
					Verify.expect(danger):toBe(rule:GetProperties().BackgroundColor3)
					Verify.expect(resolve(sheet, delete, "TextColor3") ~= resolve(sheet, flag, "TextColor3")):toBe(true)
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"collections-60 a revealed tray action keeps the button idioms of pointer, touch, keyboard and gamepad",
			{
				id = "native_parity_classb_collections::native parity classb collections::collections-60 a revealed tray action keeps the button idioms of pointer, touch, keyboard and gamepad",
				run = function()
					local open: FixtureComposeTypes.Cell<("leading" | "trailing")?> =
						Compose.cell(nil :: ("leading" | "trailing")?)
					local fired = {}
					local world = setup(function(UI: FacetControls)
						return UI.RowActions({
							open = open,
							content = UI.Button({ Name = "Body", label = "Row" }) :: GuiObject,
							trailing = {
								{
									id = "flag",
									label = "Flag",
									onActivate = function()
										table.insert(fired, "flag")
									end,
								} :: FixtureCollectionTypes.RowAction,
								{
									id = "delete",
									label = "Delete",
									onActivate = function()
										table.insert(fired, "delete")
									end,
								} :: FixtureCollectionTypes.RowAction,
							},
						})
					end)
					local row = world.node
					row.AbsoluteSize = V2(world, 300, 44)
					local sheet = sheetFor(world, themes.neutralPackage())
					local body = find(row, "Body")
					select(world, body)
					open:set("trailing")
					local tray = find(row, "trailing")
					local flag, delete = find(tray, "flag"), find(tray, "delete")
					Verify.expect(world.gui.SelectedObject):toBe(flag)
					Verify.expect(flag.Selectable and delete.Selectable):toBe(true)
					Verify.expect((flag:IsA("GuiButton"))):toBe(true)
					local idle = resolve(sheet, flag, "BackgroundColor3")
					flag.GuiState = E(world).GuiState.Hover
					local hovered = resolve(sheet, flag, "BackgroundColor3")
					Verify.expect(hovered ~= nil and hovered ~= idle):toBe(true)
					flag.GuiState = E(world).GuiState.Idle
					Verify.expect(row.Size.Y.Offset):toBe(44)
					Verify.expect(tray.Size.Y.Scale):toBe(1)
					Verify.expect(flag.Size.Y.Scale):toBe(1)
					Verify.expect(delete.Size.Y.Scale):toBe(1)
					Verify.expect(flag.Size.Y.Offset):toBe(0)
					select(world, delete)
					delete.Activated:Fire(inputOf(world, "Keyboard", "Return"), 1)
					Verify.expect(fired):toEqual({ "delete" })
					Verify.expect((open:peek())):toBeNil()
					open:set("trailing")
					select(world, find(find(row, "trailing"), "delete"))
					find(find(row, "trailing"), "delete").Activated:Fire(inputOf(world, "Gamepad1", "ButtonA"), 1)
					Verify.expect(fired):toEqual({ "delete", "delete" })
					open:set("trailing")
					find(find(row, "trailing"), "flag").Activated:Fire(inputOf(world, "Touch"), 1)
					Verify.expect(fired):toEqual({ "delete", "delete", "flag" })
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"collections-73 a re-grab mid snap-open flight starts from the painted offset and never drifts",
			{
				id = "native_parity_classb_collections::native parity classb collections::collections-73 a re-grab mid snap-open flight starts from the painted offset and never drifts",
				run = function()
					local open: FixtureComposeTypes.Cell<("leading" | "trailing")?> =
						Compose.cell(nil :: ("leading" | "trailing")?)
					local world = setup(function(UI: FacetControls)
						return UI.RowActions({
							open = open,
							content = UI.Text({ text = "Row" }),
							trailing = { { id = "flag", label = "Flag" } :: FixtureCollectionTypes.RowAction },
						})
					end, { motionLevel = "normal" })
					local row = world.node
					row.AbsoluteSize = V2(world, 600, 44)
					frames(world, 1)
					local detector = row:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
					local content = find(row, "Content")
					detector.DragStart:Fire(V2(world, 100, 20))
					frames(world, 1)
					detector.DragContinue:Fire(V2(world, 0, 20))
					frames(world, 60)
					Verify.expect(content.Position.X.Offset):toBe(-100)
					detector.DragEnd:Fire()
					Verify.expect((open:peek())):toBe("trailing")
					frames(world, 3)
					local target = find(row, "trailing").Size.X.Offset
					local mid = content.Position.X.Offset
					Verify.expect(mid < 0):toBe(true)
					Verify.expect(math.abs(mid - -88) > 1):toBe(true)
					Verify.expect(mid > -100 and mid < -88):toBe(true)
					detector.DragStart:Fire(V2(world, 500, 20))
					frames(world, 1)
					detector.DragContinue:Fire(V2(world, 485, 20))
					local crossed = content.Position.X.Offset
					Verify.expect(crossed):toBe(mid - 15)
					frames(world, 15)
					Verify.expect(content.Position.X.Offset):toBe(crossed)
					detector.DragContinue:Fire(V2(world, 440, 20))
					Verify.expect(content.Position.X.Offset):toBe(mid - 60)
					detector.DragEnd:Fire()
					Verify.expect(target <= 88):toBe(true)
					world.stop()
				end,
			}
		)
		verifyHarness:case(
			"collections-98 a destructive departure shows its action across the tray and leaves the row box before it collapses",
			{
				id = "native_parity_classb_collections::native parity classb collections::collections-98 a destructive departure shows its action across the tray and leaves the row box before it collapses",
				run = function()
					for _, edge in { "leading", "trailing" } :: { "leading" | "trailing" } do
						local fired = 0
						local destructive = {
							id = "delete",
							label = "Delete",
							role = "destructive" :: "destructive",
							onActivate = function()
								fired += 1
							end,
						}
						local world = setup(function(UI: FacetControls)
							return UI.RowActions({
								content = UI.Text({ Name = "Body", text = "Row" }),
								leading = if edge == "leading" then { destructive } else nil,
								trailing = if edge == "trailing" then { destructive } else nil,
							})
						end, { motionLevel = "normal" })
						local row = world.node
						row.AbsoluteSize = V2(world, 300, 44)
						frames(world, 1)
						Verify.expect(row.ClipsDescendants):toBe(true)
						Verify.expect(find(row, "leading").ClipsDescendants):toBe(true)
						Verify.expect(find(row, "trailing").ClipsDescendants):toBe(true)
						local content = find(row, "Content")
						local detector = row:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
						local sign = if edge == "leading" then 1 else -1
						detector.DragStart:Fire(V2(world, 150, 20))
						detector.DragContinue:Fire(V2(world, 150 + sign * 20, 20))
						detector.DragContinue:Fire(V2(world, 150 + sign * 250, 20))
						detector.DragEnd:Fire()
						local collapsing, samples = 0, 0
						for _ = 1, 40 do
							frames(world, 1)
							if fired > 0 then
								break
							end
							samples += 1
							Verify.expect(find(row, edge).Visible):toBe(true)
							Verify.expect(find(find(row, edge), "delete").Size)
								:toEqual(world.engine.types.UDim2.fromScale(1, 1))
							if row.Size.Y.Offset < 44 then
								collapsing += 1
								Verify.expect(math.abs(content.Position.X.Offset) >= 300):toBe(true)
								Verify.expect(content.Position.X.Offset * sign > 0):toBe(true)
							end
						end
						Verify.expect(samples > 4):toBe(true)
						Verify.expect(collapsing > 0):toBe(true)
						Verify.expect(fired):toBe(1)
						world.stop()
					end
				end,
			}
		)
		verifyHarness:case("collections-140 fill columns keep a native floor and row hits stay beneath cell content", {
			id = "native_parity_classb_collections::native parity classb collections::collections-140 fill columns keep a native floor and row hits stay beneath cell content",
			run = function()
				local widths = Compose.cell({} :: { [string]: number })
				local world, body = tableWorld({
					widths = widths,
					selectionMode = "single" :: "single",
					columns = {
						{ id = "name", label = "Name", minWidth = 120, priority = "always" } :: FixtureCollectionTypes.TableColumn<any, any>,
						{ id = "artist", label = "Artist", minWidth = 100, priority = "always" } :: FixtureCollectionTypes.TableColumn<any, any>,
						{ id = "laps", label = "Laps", width = 96, priority = "always" } :: FixtureCollectionTypes.TableColumn<any, any>,
					},
				})
				local enum = E(world)
				local header = find(world.node, "Header")
				local row = rowFrame(body, "r2")
				for _, scope in { header, row } do
					local name, artist, laps = find(scope, "name"), find(scope, "artist"), find(scope, "laps")
					Verify.expect(name:FindFirstChildWhichIsA("UISizeConstraint").MinSize.X):toBe(120)
					Verify.expect(artist:FindFirstChildWhichIsA("UISizeConstraint").MinSize.X):toBe(100)
					Verify.expect(laps:FindFirstChildWhichIsA("UISizeConstraint").MinSize.X):toBe(48)
					Verify.expect(name:FindFirstChildWhichIsA("UIFlexItem").FlexMode):toBe(enum.UIFlexMode.Fill)
					Verify.expect(artist:FindFirstChildWhichIsA("UIFlexItem").FlexMode):toBe(enum.UIFlexMode.Fill)
					Verify.expect(laps:FindFirstChildWhichIsA("UIFlexItem").FlexMode):toBe(enum.UIFlexMode.None)
					Verify.expect(laps.Size.X.Offset):toBe(96)
					Verify.expect(name.Visible and artist.Visible and laps.Visible):toBe(true)
				end
				body.AbsoluteWindowSize = V2(world, 300, 200)
				nativeDrag.measure(body)
				Verify.expect(find(row, "artist").Visible):toBe(true)
				Verify.expect(find(row, "laps").Visible):toBe(true)
				widths:set({ name = 200 })
				Verify.expect(find(row, "name"):FindFirstChildWhichIsA("UIFlexItem").FlexMode)
					:toBe(enum.UIFlexMode.None)
				Verify.expect(find(row, "name").Size.X.Offset):toBe(200)
				for _, key in { "r1", "r2", "r3" } do
					local content = rowFrame(body, key):FindFirstChild("Content")
					local children = content:GetChildren()
					local hit = content:FindFirstChild("RowHit")
					Verify.expect(children[1]):toBe(hit)
					Verify.expect(#children):toBe(2)
					Verify.expect(children[2].ZIndex >= hit.ZIndex):toBe(true)
					Verify.expect(find(children[2], "Value") ~= nil):toBe(true)
				end
				world.stop()
			end,
		})

		verifyHarness:case("collections-154 a second pointer on another row cannot take over a live row drag", {
			id = "native_parity_classb_collections::native parity classb collections::collections-154 a second pointer on another row cannot take over a live row drag",
			run = function()
				local reorders = {}
				local world, body = tableWorld({
					reorderable = true,
					onReorder = function(keys, slot)
						table.insert(reorders, { keys = keys, slot = slot })
					end,
				})
				local handle = find(rowFrame(body, "r1"), "Move")
				local other = find(rowFrame(body, "r2"), "Move")
				local height = rowFrame(body, "r1").Size.Y.Offset
				Verify.expect(height >= 40):toBe(true)
				local first = inputOf(world, "MouseButton1")
				handle.InputBegan:Fire(first)
				handle:FindFirstChildWhichIsA("UIDragDetector").DragStart:Fire(V2(world, 20, 10))
				local moved = inputOf(world, "MouseMovement")
				moved.Position = world.engine.types.Vector3.new(20, height * 3.6, 0)
				handle:FindFirstChildWhichIsA("UIDragDetector").DragContinue:Fire(V2(world, 20, height * 3.6))
				local second = inputOf(world, "Touch")
				other.InputBegan:Fire(second)
				other:FindFirstChildWhichIsA("UIDragDetector").DragStart:Fire(V2(world, 20, height * 1.5))
				local label = find(world.node, "DragLabel")
				Verify.expect(label ~= nil and label.Text == "r1"):toBe(true)
				local ended = inputOf(world, "MouseButton1")
				ended.UserInputState = E(world).UserInputState.End
				world.input.InputEnded:Fire(ended)
				Verify.expect(#reorders):toBe(1)
				Verify.expect(reorders[1].keys):toEqual({ "r1" })
				Verify.expect(reorders[1].slot):toBe(3)
				Verify.expect((find(world.node, "DragLabel"))):toBeNil()
				world.stop()
			end,
		})

		verifyHarness:case(
			"collections-156 the row body of a reorderable table leaves touch pans to the native scroll",
			{
				id = "native_parity_classb_collections::native parity classb collections::collections-156 the row body of a reorderable table leaves touch pans to the native scroll",
				run = function()
					local editing = Compose.cell(false)
					local reorders, activations = 0, 0
					local world, body = tableWorld({
						reorderable = true,
						editing = editing,
						selectionMode = "none" :: "none",
						onActivate = function()
							activations += 1
						end,
						onReorder = function()
							reorders += 1
						end,
					})
					world.input.PreferredInput = E(world).PreferredInput.Touch
					for _, on in { false, true } do
						editing:set(on)
						Verify.expect((body:IsA("ScrollingFrame"))):toBe(true)
						Verify.expect(body.ScrollingEnabled):toBe(true)
						Verify.expect(body.ClipsDescendants):toBe(true)
						local height = rowFrame(body, "r1").Size.Y.Offset
						Verify.expect(body.CanvasSize.Y.Offset):toBe(20 * height)
						for _, detector in world.node:GetDescendants() do
							if detector:IsA("UIDragDetector") then
								local owner = detector.Parent
								Verify.expect(owner.Name == "Move" or owner.Name == "Resize" or not detector.Enabled)
									:toBe(true)
							end
						end
						local row = rowFrame(body, "r2")
						local hit = find(row, "RowHit")
						Verify.expect((hit:FindFirstChildWhichIsA("UIDragDetector"))):toBeNil()
						Verify.expect(find(row, "Cells"):FindFirstChildWhichIsA("UIDragDetector", true).Enabled)
							:toBe(false)
						local touch = inputOf(world, "Touch")
						hit.InputBegan:Fire(touch)
						local moved = inputOf(world, "Touch")
						moved.Position = world.engine.types.Vector3.new(100, 10, 0)
						world.input.InputChanged:Fire(moved)
						body.CanvasPosition = V2(world, 0, 60)
						touch.UserInputState = E(world).UserInputState.End
						world.input.InputEnded:Fire(touch)
						Verify.expect(reorders):toBe(0)
						Verify.expect(activations):toBe(0)
						Verify.expect((find(world.node, "DragLabel"))):toBeNil()
						body.CanvasPosition = V2(world, 0, 0)
					end
					world.stop()
				end,
			}
		)

		verifyHarness:case("collections-182 a drop after a page scroll reads the body's current screen position", {
			id = "native_parity_classb_collections::native parity classb collections::collections-182 a drop after a page scroll reads the body's current screen position",
			run = function()
				local function run(scrolled: number): number?
					local slot: number? = nil
					local world, body = tableWorld({
						reorderable = true,
						onReorder = function(_, index)
							slot = index
						end,
					})
					local height = rowFrame(body, "r1").Size.Y.Offset
					body.AbsolutePosition = V2(world, 0, 300 - scrolled)
					nativeDrag.measure(body)
					local handle = find(rowFrame(body, "r1"), "Move")
					local pressed = inputOf(world, "Touch")
					handle.InputBegan:Fire(pressed)
					handle:FindFirstChildWhichIsA("UIDragDetector").DragStart:Fire(V2(world, 20, 300 - scrolled + 10))
					local moved = inputOf(world, "Touch")
					moved.Position = world.engine.types.Vector3.new(20, 300 - scrolled + height * 2.2, 0)
					pressed.Position = moved.Position
					world.input.InputChanged:Fire(pressed)
					pressed.UserInputState = E(world).UserInputState.End
					world.input.InputEnded:Fire(pressed)
					world.stop()
					return slot
				end
				local unscrolled = run(0)
				Verify.expect(unscrolled):toBe(1)
				Verify.expect((run(120))):toBe(unscrolled)
				Verify.expect((run(250))):toBe(unscrolled)
			end,
		})

		verifyHarness:case(
			"collections-174 header sort buttons are native selection stops and Return cycles the sort",
			{
				id = "native_parity_classb_collections::native parity classb collections::collections-174 header sort buttons are native selection stops and Return cycles the sort",
				run = function()
					local sort = Compose.cell(nil :: any)
					local world = tableWorld({ sort = sort })
					local header = find(world.node, "Header")
					local nameSort = find(find(header, "name"), "Sort")
					local lapsSort = find(find(header, "laps"), "Sort")
					Verify.expect(nameSort:IsA("GuiButton") and nameSort.Selectable and nameSort.Visible):toBe(true)
					Verify.expect(lapsSort:IsA("GuiButton") and lapsSort.Selectable and lapsSort.Visible):toBe(true)
					Verify.expect(nameSort.Interactable and lapsSort.Interactable):toBe(true)
					select(world, nameSort)
					nameSort.Activated:Fire(inputOf(world, "Keyboard", "Return"), 1)
					Verify.expect((sort:peek())):toEqual({ column = "name", direction = "ascending" :: "ascending" })
					nameSort.Activated:Fire(inputOf(world, "Keyboard", "Return"), 1)
					Verify.expect((sort:peek())):toEqual({ column = "name", direction = "descending" :: "descending" })
					select(world, lapsSort)
					lapsSort.Activated:Fire(inputOf(world, "Gamepad1", "ButtonA"), 1)
					Verify.expect((sort:peek())):toEqual({ column = "laps", direction = "ascending" :: "ascending" })
					Verify.expect(
						string.find(lapsSort.Text .. (find(lapsSort, "Caption") or lapsSort).Text, "↑", 1, true)
							~= nil
					)
						:toBe(true)
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"collections-192 a collapsed column is invisible to native selection and the More button opens the plate",
			{
				id = "native_parity_classb_collections::native parity classb collections::collections-192 a collapsed column is invisible to native selection and the More button opens the plate",
				run = function()
					local world, body = tableWorld({
						columns = {
							{ id = "name", label = "Name", minWidth = 200 } :: FixtureCollectionTypes.TableColumn<any, any>,
							{ id = "laps", label = "Laps", width = 120, minWidth = 120, priority = 2 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					})
					local header = find(world.node, "Header")
					Verify.expect(find(header, "laps").Visible):toBe(true)
					Verify.expect(find(find(header, "laps"), "Resize").Selectable):toBe(true)
					body.AbsoluteWindowSize = V2(world, 280, 200)
					nativeDrag.measure(body)
					Verify.expect(find(header, "laps").Visible):toBe(false)
					Verify.expect(find(rowFrame(body, "r1"), "laps").Visible):toBe(false)
					Verify.expect(find(header, "name").Visible):toBe(true)
					local details = find(rowFrame(body, "r1"), "Details")
					Verify.expect(details ~= nil and details:IsA("GuiButton") and details.Selectable):toBe(true)
					local function plate(): any
						for _, node in world.engine.made do
							local at = node.Parent
							while node.Name == "FullValue" and at ~= nil do
								if at.Name == "PopoverModal" then
									return node
								end
								at = at.Parent
							end
						end
						return nil
					end
					Verify.expect((plate())):toBeNil()
					select(world, details)
					details.Activated:Fire(inputOf(world, "Keyboard", "Return"), 1)
					local expanded = plate()
					Verify.expect(expanded ~= nil and expanded.Text == "1"):toBe(true)
					body.AbsoluteWindowSize = V2(world, 400, 200)
					nativeDrag.measure(body)
					Verify.expect(find(header, "laps").Visible):toBe(true)
					world.stop()
				end,
			}
		)

		verifyHarness:case("collections-197 Return replaces selection normally and toggles it while editing", {
			id = "native_parity_classb_collections::native parity classb collections::collections-197 Return replaces selection normally and toggles it while editing",
			run = function()
				for _, editing in { false, true } do
					local selection = Compose.cell({} :: { [string]: boolean })
					local world, body = tableWorld({
						selection = selection,
						selectionMode = "multiple" :: "multiple",
						editing = Compose.cell(editing),
					})
					local function press(key: string)
						local hit = find(rowFrame(body, key), "RowHit")
						select(world, hit)
						hit.Activated:Fire(inputOf(world, "Keyboard", "Return"), 1)
					end
					press("r1")
					Verify.expect((selection:peek())):toEqual({ r1 = true })
					press("r2")
					Verify.expect((selection:peek()))
						:toEqual(if editing then { r1 = true, r2 = true } else { r2 = true })
					press("r1")
					Verify.expect((selection:peek())):toEqual(if editing then { r2 = true } else { r1 = true })
					Verify.expect((find(rowFrame(body, "r2"), "RowHit"):GetAttribute("FacetSelected"))):toBe(editing)
					world.stop()
				end
			end,
		})
		verifyHarness:case(
			"collections-233 a virtual grid clips partial lines, slides on engine scroll without activating and clamps a negative offset",
			{
				id = "native_parity_classb_collections::native parity classb collections::collections-233 a virtual grid clips partial lines, slides on engine scroll without activating and clamps a negative offset",
				run = function()
					local activations = {}
					local world = setup(function(UI: FacetControls)
						return UI.VirtualGrid({
							from = rows(200),
							key = "id",
							columns = 4,
							itemSize = 100,
							overscan = 0,
							onActivate = function(item)
								table.insert(activations, item.id)
							end,
							render = function(current): GuiObject
								return UI.Text({ text = current:peek().name })
							end,
						})
					end)
					local grid = world.node
					grid.AbsoluteWindowSize = V2(world, 400, 250)
					Verify.expect((grid:IsA("ScrollingFrame"))):toBe(true)
					Verify.expect(grid.ClipsDescendants):toBe(true)
					Verify.expect(grid.CanvasSize.Y.Offset):toBe(50 * 100)
					Verify.expect(rowFrame(grid, "r1") ~= nil):toBe(true)
					Verify.expect(rowFrame(grid, "r9") ~= nil):toBe(true)
					Verify.expect((rowFrame(grid, "r13"))):toBeNil()
					grid.CanvasPosition = V2(world, 0, 1000)
					Verify.expect((rowFrame(grid, "r1"))):toBeNil()
					Verify.expect(rowFrame(grid, "r41") ~= nil):toBe(true)
					Verify.expect(rowFrame(grid, "r41").Position.Y.Offset):toBe(1000)
					Verify.expect(#activations):toBe(0)
					grid.CanvasPosition = V2(world, 0, -300)
					Verify.expect(rowFrame(grid, "r1") ~= nil):toBe(true)
					Verify.expect((rowFrame(grid, "r41"))):toBeNil()
					Verify.expect(#activations):toBe(0)
					local hit = find(rowFrame(grid, "r3"), "RowHit")
					hit.Activated:Fire(inputOf(world, "Touch"), 1)
					Verify.expect(activations):toEqual({ "r3" })
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"collections-243 a horizontal virtual grid clamps a negative engine offset to its leading line",
			{
				id = "native_parity_classb_collections::native parity classb collections::collections-243 a horizontal virtual grid clamps a negative engine offset to its leading line",
				run = function()
					local world = setup(function(UI: FacetControls)
						return UI.VirtualGrid({
							from = rows(200),
							key = "id",
							columns = 4,
							itemSize = 100,
							overscan = 0,
							direction = "horizontal" :: "horizontal",
							render = function(current): GuiObject
								return UI.Text({ text = current:peek().name })
							end,
						})
					end)
					local grid = world.node
					grid.AbsoluteWindowSize = V2(world, 450, 400)
					Verify.expect(grid.ScrollingDirection):toBe(E(world).ScrollingDirection.X)
					Verify.expect(grid.CanvasSize.X.Offset):toBe(50 * 100)
					grid.CanvasPosition = V2(world, 1000, 0)
					Verify.expect((rowFrame(grid, "r1"))):toBeNil()
					Verify.expect(rowFrame(grid, "r41").Position.X.Offset):toBe(1000)
					grid.CanvasPosition = V2(world, -300, 0)
					Verify.expect(rowFrame(grid, "r1") ~= nil):toBe(true)
					Verify.expect(rowFrame(grid, "r1").Position.X.Offset):toBe(0)
					Verify.expect((rowFrame(grid, "r41"))):toBeNil()
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"collections-254 a horizontal list slides on a sideways engine scroll without activating, and Return or ButtonA activate",
			{
				id = "native_parity_classb_collections::native parity classb collections::collections-254 a horizontal list slides on a sideways engine scroll without activating, and Return or ButtonA activate",
				run = function()
					local activations = {}
					local world = setup(function(UI: FacetControls)
						return UI.VirtualList({
							from = rows(100),
							key = "id",
							itemSize = 120,
							overscan = 0,
							direction = "horizontal" :: "horizontal",
							onActivate = function(item: any, _, input: InputObject?)
								table.insert(activations, { id = item.id, key = input and input.KeyCode.Name })
							end,
							render = function(current): GuiObject
								return UI.Text({ text = current:peek().name })
							end,
						})
					end)
					local list = world.node
					list.AbsoluteWindowSize = V2(world, 480, 80)
					Verify.expect(list.ScrollingDirection):toBe(E(world).ScrollingDirection.X)
					list.CanvasPosition = V2(world, 240, 0)
					Verify.expect((rowFrame(list, "r2"))):toBeNil()
					Verify.expect(rowFrame(list, "r6") ~= nil):toBe(true)
					Verify.expect(rowFrame(list, "r6").Position.X.Offset):toBe(600)
					Verify.expect(rowFrame(list, "r6").Size.Y.Offset):toBe(80)
					Verify.expect(#activations):toBe(0)
					list.CanvasPosition = V2(world, -900, 0)
					Verify.expect(rowFrame(list, "r1") ~= nil):toBe(true)
					Verify.expect(#activations):toBe(0)
					local second = find(rowFrame(list, "r2"), "RowHit")
					select(world, second)
					second.Activated:Fire(inputOf(world, "Keyboard", "Return"), 1)
					second.Activated:Fire(inputOf(world, "Gamepad1", "ButtonA"), 1)
					Verify.expect(activations)
						:toEqual({ { id = "r2", key = "Return" }, { id = "r2", key = "ButtonA" } })
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"collections-264 a vertical list clips partial rows, slides on engine scroll and clamps a negative offset",
			{
				id = "native_parity_classb_collections::native parity classb collections::collections-264 a vertical list clips partial rows, slides on engine scroll and clamps a negative offset",
				run = function()
					local activations = {}
					local world = setup(function(UI: FacetControls)
						return UI.VirtualList({
							from = rows(100),
							key = "id",
							itemSize = 40,
							overscan = 0,
							onActivate = function(item)
								table.insert(activations, item.id)
							end,
							render = function(current): GuiObject
								return UI.Text({ text = current:peek().name })
							end,
						})
					end)
					local list = world.node
					list.AbsoluteWindowSize = V2(world, 300, 190)
					Verify.expect(list.ClipsDescendants):toBe(true)
					Verify.expect(list.CanvasSize.Y.Offset):toBe(4000)
					Verify.expect(rowFrame(list, "r5") ~= nil):toBe(true)
					Verify.expect((rowFrame(list, "r6"))):toBeNil()
					list.CanvasPosition = V2(world, 0, 80)
					Verify.expect((rowFrame(list, "r1"))):toBeNil()
					Verify.expect(rowFrame(list, "r7") ~= nil):toBe(true)
					Verify.expect(rowFrame(list, "r7").Position.Y.Offset):toBe(240)
					Verify.expect(#activations):toBe(0)
					list.CanvasPosition = V2(world, 0, -200)
					Verify.expect(rowFrame(list, "r1") ~= nil):toBe(true)
					Verify.expect((rowFrame(list, "r7"))):toBeNil()
					find(rowFrame(list, "r2"), "RowHit").Activated:Fire(inputOf(world, "Touch"), 1)
					Verify.expect(activations):toEqual({ "r2" })
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"collections-291 a vertical drag on a row with swipe actions opens nothing and does not activate the row",
			{
				id = "native_parity_classb_collections::native parity classb collections::collections-291 a vertical drag on a row with swipe actions opens nothing and does not activate the row",
				run = function()
					local activations, fired = {}, {}
					local world = setup(function(UI: FacetControls)
						return UI.VirtualList({
							from = rows(40),
							key = "id",
							itemSize = 44,
							overscan = 0,
							onActivate = function(item)
								table.insert(activations, item.id)
							end,
							render = function(current): GuiObject
								return UI.RowActions({
									content = UI.Text({ text = current:peek().name }),
									leading = {
										{
											id = "pin",
											label = "Pin",
											onActivate = function()
												table.insert(fired, "pin")
											end,
										} :: FixtureCollectionTypes.RowAction,
									},
									trailing = {
										{
											id = "delete",
											label = "Delete",
											onActivate = function()
												table.insert(fired, "delete")
											end,
										} :: FixtureCollectionTypes.RowAction,
									},
								})
							end,
						})
					end)
					local list = world.node
					list.AbsoluteWindowSize = V2(world, 300, 220)
					local row = find(rowFrame(list, "r2"), "Content"):FindFirstChildWhichIsA("Frame")
					row.AbsoluteSize = V2(world, 300, 44)
					local detector = row:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
					Verify.expect(detector.DragAxis):toBe(V2(world, 1, 0))
					Verify.expect(detector.DragStyle):toBe(E(world).UIDragDetectorDragStyle.TranslateLine)
					for _, dy in { 60, 90, -70 } do
						detector.DragStart:Fire(V2(world, 150, 20))
						detector.DragContinue:Fire(V2(world, 152, 20 + dy / 2))
						detector.DragContinue:Fire(V2(world, 153, 20 + dy))
						Verify.expect(find(row, "Content").Position.X.Offset):toBe(0)
						list.CanvasPosition = V2(world, 0, math.max(0, -dy))
						detector.DragEnd:Fire()
						list.CanvasPosition = V2(world, 0, 0)
					end
					Verify.expect(find(row, "leading").Visible):toBe(false)
					Verify.expect(find(row, "trailing").Visible):toBe(false)
					Verify.expect(activations):toEqual({})
					Verify.expect(fired):toEqual({})
					local hit = find(rowFrame(list, "r2"), "RowHit")
					hit.Activated:Fire(inputOf(world, "Gamepad1", "ButtonA"), 1)
					hit.Activated:Fire(inputOf(world, "Touch"), 1)
					Verify.expect(activations):toEqual({ "r2", "r2" })
					world.stop()
				end,
			}
		)
		verifyHarness:case(
			"collections-189 a deletable table in edit mode gives each row a leading minus that reveals its Delete",
			{
				id = "native_parity_classb_collections::native parity classb collections::collections-189 a deletable table in edit mode gives each row a leading minus that reveals its Delete",
				run = function()
					local deleted = {}
					local editing = Compose.cell(true)
					local world, body = tableWorld({
						editing = editing,
						selectionMode = "single" :: "single",
						deletable = true,
						onDelete = function(keys)
							table.insert(deleted, table.concat(keys, ","))
						end,
					})
					world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Gamepad
					for _, key in { "r1", "r2", "r3" } do
						local minus = find(rowFrame(body, key), "Minus")
						Verify.expect(minus ~= nil and minus:IsA("GuiButton") and minus.Visible):toBe(true)
						Verify.expect(minus.Position.X.Scale):toBe(0)
						Verify.expect(find(rowFrame(body, key), "Cells").Position.X.Offset):toBe(44)
					end
					local minus = find(rowFrame(body, "r2"), "Minus")
					select(world, minus)
					minus.Activated:Fire(inputOf(world, "Gamepad1", "ButtonA"), 1)
					Verify.expect(deleted):toEqual({})
					local confirm = find(rowFrame(body, "r2"), "Delete")
					Verify.expect(confirm.Visible):toBe(true)
					confirm.Activated:Fire(inputOf(world, "Gamepad1", "ButtonA"), 1)
					Verify.expect(deleted):toEqual({ "r2" })
					editing:set(false)
					Verify.expect(find(rowFrame(body, "r2"), "Minus").Visible):toBe(false)
					Verify.expect(find(rowFrame(body, "r2"), "Cells").Position.X.Offset):toBe(0)
					world.stop()
				end,
			}
		)
		verifyHarness:case(
			"collections-153 table cell text is inset like the header title and both use the content color",
			{
				id = "native_parity_classb_collections::native parity classb collections::collections-153 table cell text is inset like the header title and both use the content color",
				run = function()
					local world, body = tableWorld({})
					for _, package in { themes.neutralPackage() } do
						local sheet = sheetFor(world, package)
						local cell = find(rowFrame(body, "r1"), "name")
						local value = cell:FindFirstChild("Value")
						local sort = find(find(world.node, "Header"), "name"):FindFirstChild("Sort")
						Verify.expect((cell:HasTag("facet-tablecell"))):toBe(true)
						Verify.expect(value:HasTag("facet-text") and value:HasTag("facet-tablevalue")):toBe(true)
						local cellLeft = resolve(sheet, value, "PaddingLeft", "UIPadding")
						local titleLeft = resolve(sheet, sort, "PaddingLeft", "UIPadding")
						Verify.expect(cellLeft ~= nil and titleLeft ~= nil):toBe(true)
						Verify.expect(cellLeft.Offset >= 8):toBe(true)
						Verify.expect(cellLeft):toBe(titleLeft)
						Verify.expect((resolve(sheet, value, "PaddingRight", "UIPadding")))
							:toBe(resolve(sheet, sort, "PaddingRight", "UIPadding"))
						Verify.expect(value.TextYAlignment):toBe(E(world).TextYAlignment.Center)
						Verify.expect(value.Size.Y.Scale):toBe(1)
						Verify.expect((resolve(sheet, value, "TextColor3"))):toBe(resolve(sheet, sort, "TextColor3"))
						Verify.expect((sort:HasTag("facet-secondary"))):toBe(false)
					end
					world.stop()
				end,
			}
		)
	end)
end
