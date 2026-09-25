--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose
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
	local runtime = Facet.Roblox.createRuntime(engine)
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
		reducedMotion = true,
	}
	for field, value in (options or {}) :: { [string]: any } do
		config[field] = value
	end
	local UI = Facet.controls(runtime, config :: any)
	local Host = runtime.constructors
	local stop, node = runtime.mount(function()
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
		world.engine.heartbeat.fire(1 / 60)
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
		KeyCode = if keyCode then (enum.KeyCode :: any)[keyCode] else enum.KeyCode.Unknown,
		UserInputState = enum.UserInputState.Begin,
		Position = world.engine.types.Vector3.new(0, 0, 0),
	}
end

local function select(world: World, node: any)
	local previous = world.gui.SelectedObject
	world.gui.SelectedObject = node
	if previous and previous ~= node then
		previous.SelectionLost.fire()
	end
	if node and previous ~= node then
		node.SelectionGained.fire()
	end
end

local function sheetFor(world: World, package: any): any
	local _, sheet = world.runtime.mount(function()
		return themes.createStyleSheet(
			world.runtime,
			package,
			{ types = world.engine.types, preferredTransparency = 1, reducedMotion = false } :: any
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
	local world = setup(function(UI)
		local base: { [string]: any } = {
			from = rows(20),
			key = "id",
			columns = {
				{ id = "name", label = "Name" },
				{ id = "laps", label = "Laps", width = 80 },
			},
		}
		for field, value in spec do
			base[field] = value
		end
		return UI.Table(base)
	end, options)
	local body = find(world.node, "Body")
	body.AbsoluteWindowSize = V2(world, 400, 200)
	body.AbsoluteSize = V2(world, 400, 200)
	return world, body
end

local function rowFrame(body: any, key: string): any
	local items = find(body, "Items")
	return if items then items:FindFirstChild(key, true) else nil
end

t.describe("native parity classb collections", function()
	t.it("collections-29 the cross axis of each row fills the collection window by default", function()
		for _, direction in { "vertical", "horizontal" } do
			local world = setup(function(UI)
				return UI.VirtualList({
					from = rows(30),
					key = "id",
					itemSize = 60,
					direction = direction,
					render = function(current)
						return UI.Label({ text = current:peek().name })
					end,
				})
			end)
			local list = world.node
			local horizontal = direction == "horizontal"
			list.AbsoluteWindowSize = if horizontal then V2(world, 480, 200) else V2(world, 320, 240)
			list.AbsoluteSize = list.AbsoluteWindowSize
			local row = rowFrame(list, "r1")
			t.expect(row ~= nil).toBe(true)
			if horizontal then
				t.expect(row.Size.X.Offset).toBe(60)
				t.expect(row.Size.Y.Offset).toBe(200)
				t.expect(row.Size.Y.Scale).toBe(0)
			else
				t.expect(row.Size.Y.Offset).toBe(60)
				t.expect(row.Size.X.Offset).toBe(320)
				t.expect(row.Size.X.Scale).toBe(0)
			end
			list.AbsoluteWindowSize = if horizontal then V2(world, 480, 150) else V2(world, 250, 240)
			if horizontal then
				t.expect(row.Size.Y.Offset).toBe(150)
			else
				t.expect(row.Size.X.Offset).toBe(250)
			end
			world.stop()
		end
		local grid = setup(function(UI)
			return UI.VirtualGrid({
				from = rows(30),
				key = "id",
				columns = 4,
				itemSize = 60,
				render = function(current)
					return UI.Label({ text = current:peek().name })
				end,
			})
		end)
		grid.node.AbsoluteWindowSize = V2(grid, 400, 300)
		local cell = rowFrame(grid.node, "r2")
		t.expect(cell.Size.X.Offset).toBe(100)
		t.expect(cell.Position.X.Offset).toBe(100)
		grid.stop()
	end)

	t.it("collections-42 a table keeps its engine scroll position when the input class flips", function()
		local world, body = tableWorld({ reorderable = true, onReorder = function() end, selectionMode = "multi" })
		local enum = E(world)
		world.input.PreferredInput = enum.PreferredInput.Touch
		world.input.TouchEnabled = true
		world.input.KeyboardEnabled = false
		world.input.GamepadEnabled = false
		world.input.MouseEnabled = false
		frames(world, 2)
		body.CanvasPosition = V2(world, 0, 120)
		frames(world, 2)
		t.expect(body.CanvasPosition.Y).toBe(120)
		local writes = 0
		body:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			writes += 1
		end)
		world.input.KeyboardEnabled = true
		world.input.GamepadEnabled = true
		world.input.PreferredInput = enum.PreferredInput.Gamepad
		frames(world, 4)
		t.expect(body.CanvasPosition.Y).toBe(120)
		t.expect(writes).toBe(0)
		world.input.PreferredInput = enum.PreferredInput.KeyboardAndMouse
		world.input.TouchEnabled = false
		world.input.MouseEnabled = true
		frames(world, 4)
		t.expect(rowFrame(body, "r4") ~= nil).toBe(true)
		t.expect(body.CanvasPosition.Y).toBe(120)
		world.stop()
	end)
	t.it("collections-54 a destructive tray action and a default tray action resolve different paint", function()
		local open = Compose.cell("trailing" :: string?)
		local world = setup(function(UI)
			return UI.RowActions({
				open = open,
				content = UI.Label({ text = "Row" }),
				trailing = {
					{ id = "delete", label = "Delete", role = "destructive" },
					{ id = "flag", label = "Flag" },
				},
			})
		end)
		world.node.AbsoluteSize = V2(world, 300, 44)
		local sheet = sheetFor(world, themes.neutralPackage())
		local tray = find(world.node, "trailing")
		local delete, flag = find(tray, "delete"), find(tray, "flag")
		t.expect(delete:HasTag("facet-role-destructive")).toBe(true)
		t.expect(delete:HasTag("facet-role-default")).toBe(false)
		t.expect(flag:HasTag("facet-role-default")).toBe(true)
		t.expect(flag:HasTag("facet-role-destructive")).toBe(false)
		local danger = resolve(sheet, delete, "BackgroundColor3")
		local plain = resolve(sheet, flag, "BackgroundColor3")
		t.expect(danger ~= nil and plain ~= nil).toBe(true)
		t.expect(danger ~= plain).toBe(true)
		local rule
		for _, node in sheet:GetChildren() do
			if node.Selector == ".facet-role-destructive" then
				rule = node
			end
		end
		t.expect(danger).toBe(rule:GetProperties().BackgroundColor3)
		t.expect(resolve(sheet, delete, "TextColor3") ~= resolve(sheet, flag, "TextColor3")).toBe(true)
		world.stop()
	end)

	t.it(
		"collections-60 a revealed tray action keeps the button idioms of pointer, touch, keyboard and gamepad",
		function()
			local open = Compose.cell(nil :: string?)
			local fired = {}
			local world = setup(function(UI)
				return UI.RowActions({
					open = open,
					content = UI.Button({ Name = "Body", label = "Row" }),
					trailing = {
						{
							id = "flag",
							label = "Flag",
							onActivate = function()
								table.insert(fired, "flag")
							end,
						},
						{
							id = "delete",
							label = "Delete",
							onActivate = function()
								table.insert(fired, "delete")
							end,
						},
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
			t.expect(world.gui.SelectedObject).toBe(flag)
			t.expect(flag.Selectable and delete.Selectable).toBe(true)
			t.expect(flag:IsA("GuiButton")).toBe(true)
			local idle = resolve(sheet, flag, "BackgroundColor3")
			flag.GuiState = E(world).GuiState.Hover
			local hovered = resolve(sheet, flag, "BackgroundColor3")
			t.expect(hovered ~= nil and hovered ~= idle).toBe(true)
			flag.GuiState = E(world).GuiState.Idle
			t.expect(row.Size.Y.Offset).toBe(44)
			t.expect(tray.Size.Y.Scale).toBe(1)
			t.expect(flag.Size.Y.Scale).toBe(1)
			t.expect(delete.Size.Y.Scale).toBe(1)
			t.expect(flag.Size.Y.Offset).toBe(0)
			select(world, delete)
			delete.Activated.fire(inputOf(world, "Keyboard", "Return"), 1)
			t.expect(fired).toEqual({ "delete" })
			t.expect(open:peek()).toBeNil()
			open:set("trailing")
			select(world, find(find(row, "trailing"), "delete"))
			find(find(row, "trailing"), "delete").Activated.fire(inputOf(world, "Gamepad1", "ButtonA"), 1)
			t.expect(fired).toEqual({ "delete", "delete" })
			open:set("trailing")
			find(find(row, "trailing"), "flag").Activated.fire(inputOf(world, "Touch"), 1)
			t.expect(fired).toEqual({ "delete", "delete", "flag" })
			world.stop()
		end
	)

	t.it("collections-73 a re-grab mid snap-open flight starts from the painted offset and never drifts", function()
		local open = Compose.cell(nil :: string?)
		local world = setup(function(UI)
			return UI.RowActions({
				open = open,
				content = UI.Label({ text = "Row" }),
				trailing = { { id = "flag", label = "Flag" } },
			})
		end, { reducedMotion = false })
		local row = world.node
		row.AbsoluteSize = V2(world, 600, 44)
		frames(world, 1)
		local detector = row:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
		local content = find(row, "Content")
		detector.DragStart.fire(V2(world, 100, 20))
		frames(world, 1)
		detector.DragContinue.fire(V2(world, 0, 20))
		frames(world, 60)
		t.expect(content.Position.X.Offset).toBe(-100)
		detector.DragEnd.fire()
		t.expect(open:peek()).toBe("trailing")
		frames(world, 3)
		local target = find(row, "trailing").Size.X.Offset
		local mid = content.Position.X.Offset
		t.expect(mid < 0).toBe(true)
		t.expect(math.abs(mid - -88) > 1).toBe(true)
		t.expect(mid > -100 and mid < -88).toBe(true)
		detector.DragStart.fire(V2(world, 500, 20))
		frames(world, 1)
		detector.DragContinue.fire(V2(world, 485, 20))
		local crossed = content.Position.X.Offset
		t.expect(crossed).toBe(mid - 15)
		frames(world, 15)
		t.expect(content.Position.X.Offset).toBe(crossed)
		detector.DragContinue.fire(V2(world, 440, 20))
		t.expect(content.Position.X.Offset).toBe(mid - 60)
		detector.DragEnd.fire()
		t.expect(target <= 88).toBe(true)
		world.stop()
	end)
	t.it(
		"collections-98 a destructive departure leaves the clipped row box before the row starts to collapse",
		function()
			for _, edge in { "leading", "trailing" } do
				local fired = 0
				local destructive = {
					id = "delete",
					label = "Delete",
					role = "destructive",
					onActivate = function()
						fired += 1
					end,
				}
				local world = setup(function(UI)
					return UI.RowActions({
						content = UI.Label({ Name = "Body", text = "Row" }),
						leading = if edge == "leading" then { destructive } else nil,
						trailing = if edge == "trailing" then { destructive } else nil,
					})
				end, { reducedMotion = false })
				local row = world.node
				row.AbsoluteSize = V2(world, 300, 44)
				frames(world, 1)
				t.expect(row.ClipsDescendants).toBe(true)
				t.expect(find(row, "leading").ClipsDescendants).toBe(true)
				t.expect(find(row, "trailing").ClipsDescendants).toBe(true)
				local content = find(row, "Content")
				local detector = row:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				local sign = if edge == "leading" then 1 else -1
				detector.DragStart.fire(V2(world, 150, 20))
				detector.DragContinue.fire(V2(world, 150 + sign * 20, 20))
				detector.DragContinue.fire(V2(world, 150 + sign * 250, 20))
				detector.DragEnd.fire()
				local collapsing, samples = 0, 0
				for _ = 1, 40 do
					frames(world, 1)
					if fired > 0 then
						break
					end
					samples += 1
					t.expect(find(row, edge).Visible).toBe(false)
					if row.Size.Y.Offset < 44 then
						collapsing += 1
						t.expect(math.abs(content.Position.X.Offset) >= 300).toBe(true)
						t.expect(content.Position.X.Offset * sign > 0).toBe(true)
					end
				end
				t.expect(samples > 4).toBe(true)
				t.expect(collapsing > 0).toBe(true)
				t.expect(fired).toBe(1)
				world.stop()
			end
		end
	)
	t.it("collections-140 fill columns keep a native floor and row hits stay beneath cell content", function()
		local widths = Compose.cell({} :: { [string]: number })
		local world, body = tableWorld({
			widths = widths,
			selectionMode = "single",
			columns = {
				{ id = "name", label = "Name", minWidth = 120, priority = "always" },
				{ id = "artist", label = "Artist", minWidth = 100, priority = "always" },
				{ id = "laps", label = "Laps", width = 96, priority = "always" },
			},
		})
		local enum = E(world)
		local header = find(world.node, "Header")
		local row = rowFrame(body, "r2")
		for _, scope in { header, row } do
			local name, artist, laps = find(scope, "name"), find(scope, "artist"), find(scope, "laps")
			t.expect(name:FindFirstChildWhichIsA("UISizeConstraint").MinSize.X).toBe(120)
			t.expect(artist:FindFirstChildWhichIsA("UISizeConstraint").MinSize.X).toBe(100)
			t.expect(laps:FindFirstChildWhichIsA("UISizeConstraint").MinSize.X).toBe(48)
			t.expect(name:FindFirstChildWhichIsA("UIFlexItem").FlexMode).toBe(enum.UIFlexMode.Fill)
			t.expect(artist:FindFirstChildWhichIsA("UIFlexItem").FlexMode).toBe(enum.UIFlexMode.Fill)
			t.expect(laps:FindFirstChildWhichIsA("UIFlexItem").FlexMode).toBe(enum.UIFlexMode.None)
			t.expect(laps.Size.X.Offset).toBe(96)
			t.expect(name.Visible and artist.Visible and laps.Visible).toBe(true)
		end
		body.AbsoluteWindowSize = V2(world, 300, 200)
		t.expect(find(row, "artist").Visible).toBe(true)
		t.expect(find(row, "laps").Visible).toBe(true)
		widths:set({ name = 200 })
		t.expect(find(row, "name"):FindFirstChildWhichIsA("UIFlexItem").FlexMode).toBe(enum.UIFlexMode.None)
		t.expect(find(row, "name").Size.X.Offset).toBe(200)
		for _, key in { "r1", "r2", "r3" } do
			local content = rowFrame(body, key):FindFirstChild("Content")
			local children = content:GetChildren()
			local hit = content:FindFirstChild("RowHit")
			t.expect(children[1]).toBe(hit)
			t.expect(#children).toBe(2)
			t.expect(children[2].ZIndex >= hit.ZIndex).toBe(true)
			t.expect(find(children[2], "Value") ~= nil).toBe(true)
		end
		world.stop()
	end)

	t.it("collections-154 a second pointer on another row cannot take over a live row drag", function()
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
		t.expect(height >= 40).toBe(true)
		local first = inputOf(world, "MouseButton1")
		handle.InputBegan.fire(first)
		handle:FindFirstChildWhichIsA("UIDragDetector").DragStart.fire(V2(world, 20, 10))
		local moved = inputOf(world, "MouseMovement")
		moved.Position = world.engine.types.Vector3.new(20, height * 3.6, 0)
		world.input.InputChanged.fire(moved)
		local second = inputOf(world, "Touch")
		other.InputBegan.fire(second)
		other:FindFirstChildWhichIsA("UIDragDetector").DragStart.fire(V2(world, 20, height * 1.5))
		local label = find(world.node, "DragLabel")
		t.expect(label ~= nil and label.Text == "r1").toBe(true)
		local ended = inputOf(world, "MouseButton1")
		ended.UserInputState = E(world).UserInputState.End
		world.input.InputEnded.fire(ended)
		t.expect(#reorders).toBe(1)
		t.expect(reorders[1].keys).toEqual({ "r1" })
		t.expect(reorders[1].slot).toBe(3)
		t.expect(find(world.node, "DragLabel")).toBeNil()
		world.stop()
	end)

	t.it("collections-156 the row body of a reorderable table leaves touch pans to the native scroll", function()
		local editing = Compose.cell(false)
		local reorders, activations = 0, 0
		local world, body = tableWorld({
			reorderable = true,
			editing = editing,
			selectionMode = "none",
			onActivate = function()
				activations += 1
			end,
			onReorder = function()
				reorders += 1
			end,
		})
		for _, on in { false, true } do
			editing:set(on)
			t.expect(body:IsA("ScrollingFrame")).toBe(true)
			t.expect(body.ScrollingEnabled).toBe(true)
			t.expect(body.ClipsDescendants).toBe(true)
			local height = rowFrame(body, "r1").Size.Y.Offset
			t.expect(body.CanvasSize.Y.Offset).toBe(20 * height)
			for _, detector in world.node:GetDescendants() do
				if detector:IsA("UIDragDetector") then
					local owner = detector.Parent
					t.expect(owner.Name == "Move" or owner.Name == "Resize").toBe(true)
				end
			end
			local row = rowFrame(body, "r2")
			local hit = find(row, "RowHit")
			t.expect(hit:FindFirstChildWhichIsA("UIDragDetector")).toBeNil()
			t.expect(find(row, "Cells"):FindFirstChildWhichIsA("UIDragDetector", true)).toBeNil()
			local touch = inputOf(world, "Touch")
			hit.InputBegan.fire(touch)
			local moved = inputOf(world, "Touch")
			moved.Position = world.engine.types.Vector3.new(100, 10, 0)
			world.input.InputChanged.fire(moved)
			body.CanvasPosition = V2(world, 0, 60)
			touch.UserInputState = E(world).UserInputState.End
			world.input.InputEnded.fire(touch)
			t.expect(reorders).toBe(0)
			t.expect(activations).toBe(0)
			t.expect(find(world.node, "DragLabel")).toBeNil()
			body.CanvasPosition = V2(world, 0, 0)
		end
		world.stop()
	end)

	t.it("collections-182 a drop after a page scroll reads the body's current screen position", function()
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
			local handle = find(rowFrame(body, "r1"), "Move")
			local pressed = inputOf(world, "Touch")
			handle.InputBegan.fire(pressed)
			handle:FindFirstChildWhichIsA("UIDragDetector").DragStart.fire(V2(world, 20, 300 - scrolled + 10))
			local moved = inputOf(world, "Touch")
			moved.Position = world.engine.types.Vector3.new(20, 300 - scrolled + height * 2.2, 0)
			pressed.Position = moved.Position
			world.input.InputChanged.fire(pressed)
			pressed.UserInputState = E(world).UserInputState.End
			world.input.InputEnded.fire(pressed)
			world.stop()
			return slot
		end
		local unscrolled = run(0)
		t.expect(unscrolled).toBe(1)
		t.expect(run(120)).toBe(unscrolled)
		t.expect(run(250)).toBe(unscrolled)
	end)

	t.it("collections-174 header sort buttons are native selection stops and Return cycles the sort", function()
		local sort = Compose.cell(nil :: any)
		local world = tableWorld({ sort = sort })
		local header = find(world.node, "Header")
		local nameSort = find(find(header, "name"), "Sort")
		local lapsSort = find(find(header, "laps"), "Sort")
		t.expect(nameSort:IsA("GuiButton") and nameSort.Selectable and nameSort.Visible).toBe(true)
		t.expect(lapsSort:IsA("GuiButton") and lapsSort.Selectable and lapsSort.Visible).toBe(true)
		t.expect(nameSort.Interactable and lapsSort.Interactable).toBe(true)
		select(world, nameSort)
		nameSort.Activated.fire(inputOf(world, "Keyboard", "Return"), 1)
		t.expect(sort:peek()).toEqual({ column = "name", direction = "ascending" })
		nameSort.Activated.fire(inputOf(world, "Keyboard", "Return"), 1)
		t.expect(sort:peek()).toEqual({ column = "name", direction = "descending" })
		select(world, lapsSort)
		lapsSort.Activated.fire(inputOf(world, "Gamepad1", "ButtonA"), 1)
		t.expect(sort:peek()).toEqual({ column = "laps", direction = "ascending" })
		t.expect(string.find(lapsSort.Text .. (find(lapsSort, "Caption") or lapsSort).Text, "↑", 1, true) ~= nil)
			.toBe(true)
		world.stop()
	end)

	t.it(
		"collections-192 a collapsed column is invisible to native selection and the More button opens the plate",
		function()
			local world, body = tableWorld({
				columns = {
					{ id = "name", label = "Name", minWidth = 200 },
					{ id = "laps", label = "Laps", width = 120, minWidth = 120 },
				},
			})
			local header = find(world.node, "Header")
			t.expect(find(header, "laps").Visible).toBe(true)
			t.expect(find(find(header, "laps"), "Resize").Selectable).toBe(true)
			body.AbsoluteWindowSize = V2(world, 280, 200)
			t.expect(find(header, "laps").Visible).toBe(false)
			t.expect(find(rowFrame(body, "r1"), "laps").Visible).toBe(false)
			t.expect(find(header, "name").Visible).toBe(true)
			local details = find(rowFrame(body, "r1"), "Details")
			t.expect(details ~= nil and details:IsA("GuiButton") and details.Selectable).toBe(true)
			local function plate(): any
				for _, node in world.engine.made do
					local at = node.Parent
					while node.Name == "FullValue" and at ~= nil do
						if at.Name == "Modal" then
							return node
						end
						at = at.Parent
					end
				end
				return nil
			end
			t.expect(plate()).toBeNil()
			select(world, details)
			details.Activated.fire(inputOf(world, "Keyboard", "Return"), 1)
			local expanded = plate()
			t.expect(expanded ~= nil and expanded.Text == "1").toBe(true)
			body.AbsoluteWindowSize = V2(world, 400, 200)
			t.expect(find(header, "laps").Visible).toBe(true)
			world.stop()
		end
	)

	t.it("collections-197 Return on a focused row toggles it in a multi-selection table, also while editing", function()
		for _, editing in { false, true } do
			local selection = Compose.cell({} :: { [string]: boolean })
			local world, body = tableWorld({
				selection = selection,
				selectionMode = "multi",
				editing = Compose.cell(editing),
			})
			local function press(key: string)
				local hit = find(rowFrame(body, key), "RowHit")
				select(world, hit)
				hit.Activated.fire(inputOf(world, "Keyboard", "Return"), 1)
			end
			press("r1")
			t.expect(selection:peek()).toEqual({ r1 = true })
			press("r2")
			t.expect(selection:peek()).toEqual({ r1 = true, r2 = true })
			press("r1")
			t.expect(selection:peek()).toEqual({ r2 = true })
			t.expect(find(rowFrame(body, "r2"), "RowHit"):GetAttribute("FacetSelected")).toBe(true)
			world.stop()
		end
	end)
	t.it(
		"collections-233 a virtual grid clips partial lines, slides on engine scroll without activating and clamps a negative offset",
		function()
			local activations = {}
			local world = setup(function(UI)
				return UI.VirtualGrid({
					from = rows(200),
					key = "id",
					columns = 4,
					itemSize = 100,
					overscan = 0,
					onActivate = function(item)
						table.insert(activations, item.id)
					end,
					render = function(current)
						return UI.Label({ text = current:peek().name })
					end,
				})
			end)
			local grid = world.node
			grid.AbsoluteWindowSize = V2(world, 400, 250)
			t.expect(grid:IsA("ScrollingFrame")).toBe(true)
			t.expect(grid.ClipsDescendants).toBe(true)
			t.expect(grid.CanvasSize.Y.Offset).toBe(50 * 100)
			t.expect(rowFrame(grid, "r1") ~= nil).toBe(true)
			t.expect(rowFrame(grid, "r9") ~= nil).toBe(true)
			t.expect(rowFrame(grid, "r13")).toBeNil()
			grid.CanvasPosition = V2(world, 0, 1000)
			t.expect(rowFrame(grid, "r1")).toBeNil()
			t.expect(rowFrame(grid, "r41") ~= nil).toBe(true)
			t.expect(rowFrame(grid, "r41").Position.Y.Offset).toBe(1000)
			t.expect(#activations).toBe(0)
			grid.CanvasPosition = V2(world, 0, -300)
			t.expect(rowFrame(grid, "r1") ~= nil).toBe(true)
			t.expect(rowFrame(grid, "r41")).toBeNil()
			t.expect(#activations).toBe(0)
			local hit = find(rowFrame(grid, "r3"), "RowHit")
			hit.Activated.fire(inputOf(world, "Touch"), 1)
			t.expect(activations).toEqual({ "r3" })
			world.stop()
		end
	)

	t.it("collections-243 a horizontal virtual grid clamps a negative engine offset to its leading line", function()
		local world = setup(function(UI)
			return UI.VirtualGrid({
				from = rows(200),
				key = "id",
				columns = 4,
				itemSize = 100,
				overscan = 0,
				direction = "horizontal",
				render = function(current)
					return UI.Label({ text = current:peek().name })
				end,
			})
		end)
		local grid = world.node
		grid.AbsoluteWindowSize = V2(world, 450, 400)
		t.expect(grid.ScrollingDirection).toBe(E(world).ScrollingDirection.X)
		t.expect(grid.CanvasSize.X.Offset).toBe(50 * 100)
		grid.CanvasPosition = V2(world, 1000, 0)
		t.expect(rowFrame(grid, "r1")).toBeNil()
		t.expect(rowFrame(grid, "r41").Position.X.Offset).toBe(1000)
		grid.CanvasPosition = V2(world, -300, 0)
		t.expect(rowFrame(grid, "r1") ~= nil).toBe(true)
		t.expect(rowFrame(grid, "r1").Position.X.Offset).toBe(0)
		t.expect(rowFrame(grid, "r41")).toBeNil()
		world.stop()
	end)

	t.it(
		"collections-254 a horizontal list slides on a sideways engine scroll without activating, and Return or ButtonA activate",
		function()
			local activations = {}
			local world = setup(function(UI)
				return UI.VirtualList({
					from = rows(100),
					key = "id",
					itemSize = 120,
					overscan = 0,
					direction = "horizontal",
					onActivate = function(item, _, input)
						table.insert(activations, { id = item.id, key = input and input.KeyCode.Name })
					end,
					render = function(current)
						return UI.Label({ text = current:peek().name })
					end,
				})
			end)
			local list = world.node
			list.AbsoluteWindowSize = V2(world, 480, 80)
			t.expect(list.ScrollingDirection).toBe(E(world).ScrollingDirection.X)
			list.CanvasPosition = V2(world, 240, 0)
			t.expect(rowFrame(list, "r2")).toBeNil()
			t.expect(rowFrame(list, "r6") ~= nil).toBe(true)
			t.expect(rowFrame(list, "r6").Position.X.Offset).toBe(600)
			t.expect(rowFrame(list, "r6").Size.Y.Offset).toBe(80)
			t.expect(#activations).toBe(0)
			list.CanvasPosition = V2(world, -900, 0)
			t.expect(rowFrame(list, "r1") ~= nil).toBe(true)
			t.expect(#activations).toBe(0)
			local second = find(rowFrame(list, "r2"), "RowHit")
			select(world, second)
			second.Activated.fire(inputOf(world, "Keyboard", "Return"), 1)
			second.Activated.fire(inputOf(world, "Gamepad1", "ButtonA"), 1)
			t.expect(activations).toEqual({ { id = "r2", key = "Return" }, { id = "r2", key = "ButtonA" } })
			world.stop()
		end
	)

	t.it(
		"collections-264 a vertical list clips partial rows, slides on engine scroll and clamps a negative offset",
		function()
			local activations = {}
			local world = setup(function(UI)
				return UI.VirtualList({
					from = rows(100),
					key = "id",
					itemSize = 40,
					overscan = 0,
					onActivate = function(item)
						table.insert(activations, item.id)
					end,
					render = function(current)
						return UI.Label({ text = current:peek().name })
					end,
				})
			end)
			local list = world.node
			list.AbsoluteWindowSize = V2(world, 300, 190)
			t.expect(list.ClipsDescendants).toBe(true)
			t.expect(list.CanvasSize.Y.Offset).toBe(4000)
			t.expect(rowFrame(list, "r5") ~= nil).toBe(true)
			t.expect(rowFrame(list, "r6")).toBeNil()
			list.CanvasPosition = V2(world, 0, 80)
			t.expect(rowFrame(list, "r1")).toBeNil()
			t.expect(rowFrame(list, "r7") ~= nil).toBe(true)
			t.expect(rowFrame(list, "r7").Position.Y.Offset).toBe(240)
			t.expect(#activations).toBe(0)
			list.CanvasPosition = V2(world, 0, -200)
			t.expect(rowFrame(list, "r1") ~= nil).toBe(true)
			t.expect(rowFrame(list, "r7")).toBeNil()
			find(rowFrame(list, "r2"), "RowHit").Activated.fire(inputOf(world, "Touch"), 1)
			t.expect(activations).toEqual({ "r2" })
			world.stop()
		end
	)

	t.it(
		"collections-291 a vertical drag on a row with swipe actions opens nothing and does not activate the row",
		function()
			local activations, fired = {}, {}
			local world = setup(function(UI)
				return UI.VirtualList({
					from = rows(40),
					key = "id",
					itemSize = 44,
					overscan = 0,
					onActivate = function(item)
						table.insert(activations, item.id)
					end,
					render = function(current)
						return UI.RowActions({
							content = UI.Label({ text = current:peek().name }),
							leading = {
								{
									id = "pin",
									label = "Pin",
									onActivate = function()
										table.insert(fired, "pin")
									end,
								},
							},
							trailing = {
								{
									id = "delete",
									label = "Delete",
									onActivate = function()
										table.insert(fired, "delete")
									end,
								},
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
			t.expect(detector.DragAxis).toBe(V2(world, 1, 0))
			t.expect(detector.DragStyle).toBe(E(world).UIDragDetectorDragStyle.TranslateLine)
			for _, dy in { 60, 90, -70 } do
				detector.DragStart.fire(V2(world, 150, 20))
				detector.DragContinue.fire(V2(world, 152, 20 + dy / 2))
				detector.DragContinue.fire(V2(world, 153, 20 + dy))
				t.expect(find(row, "Content").Position.X.Offset).toBe(0)
				list.CanvasPosition = V2(world, 0, math.max(0, -dy))
				detector.DragEnd.fire()
				list.CanvasPosition = V2(world, 0, 0)
			end
			t.expect(find(row, "leading").Visible).toBe(false)
			t.expect(find(row, "trailing").Visible).toBe(false)
			t.expect(activations).toEqual({})
			t.expect(fired).toEqual({})
			local hit = find(rowFrame(list, "r2"), "RowHit")
			hit.Activated.fire(inputOf(world, "Gamepad1", "ButtonA"), 1)
			hit.Activated.fire(inputOf(world, "Touch"), 1)
			t.expect(activations).toEqual({ "r2", "r2" })
			world.stop()
		end
	)
	t.it(
		"collections-189 each editing row carries its own minus at its leading edge and it deletes that row",
		function()
			local fired = {}
			local editing = Compose.cell(true)
			local world, body = tableWorld({
				editing = editing,
				selectionMode = "single",
				rowActions = function(_, key)
					return {
						trailing = {
							{
								id = "delete",
								label = "Delete",
								role = "destructive",
								onActivate = function()
									table.insert(fired, "delete:" .. key)
								end,
							},
						},
					}
				end,
			})
			for _, key in { "r1", "r2", "r3" } do
				local row = rowFrame(body, key)
				local wrapper
				for _, node in row:GetDescendants() do
					if node:HasTag("facet-rowactions") then
						wrapper = node
					end
				end
				wrapper.AbsoluteSize = V2(world, 400, 44)
				local minus = wrapper:FindFirstChild("Delete")
				t.expect(minus ~= nil and minus:IsA("GuiButton") and minus.Selectable).toBe(true)
				t.expect(minus.Position.X.Offset).toBe(0)
				t.expect(minus.Position.X.Scale).toBe(0)
				local content = wrapper:FindFirstChild("Content")
				t.expect(minus.Size.X.Offset >= 72).toBe(true)
				t.expect(content.Position.X.Offset).toBe(minus.Size.X.Offset)
				t.expect(minus.Size.Y.Scale).toBe(1)
			end
			local minus = find(rowFrame(body, "r2"), "Delete")
			select(world, minus)
			minus.Activated.fire(inputOf(world, "Gamepad1", "ButtonA"), 1)
			t.expect(fired).toEqual({ "delete:r2" })
			editing:set(false)
			t.expect(find(rowFrame(body, "r2"), "Delete")).toBeNil()
			world.stop()
		end
	)
	t.it("collections-153 table cell text is inset like the header title and both use the content color", function()
		local world, body = tableWorld({})
		for _, package in { themes.neutralPackage() } do
			local sheet = sheetFor(world, package)
			local cell = find(rowFrame(body, "r1"), "name")
			local value = cell:FindFirstChild("Value")
			local sort = find(find(world.node, "Header"), "name"):FindFirstChild("Sort")
			t.expect(cell:HasTag("facet-tablecell")).toBe(true)
			t.expect(value:HasTag("facet-text") and value:HasTag("facet-tablevalue")).toBe(true)
			local cellLeft = resolve(sheet, value, "PaddingLeft", "UIPadding")
			local titleLeft = resolve(sheet, sort, "PaddingLeft", "UIPadding")
			t.expect(cellLeft ~= nil and titleLeft ~= nil).toBe(true)
			t.expect(cellLeft.Offset >= 8).toBe(true)
			t.expect(cellLeft).toBe(titleLeft)
			t.expect(resolve(sheet, value, "PaddingRight", "UIPadding"))
				.toBe(resolve(sheet, sort, "PaddingRight", "UIPadding"))
			t.expect(value.TextYAlignment).toBe(E(world).TextYAlignment.Center)
			t.expect(value.Size.Y.Scale).toBe(1)
			t.expect(resolve(sheet, value, "TextColor3")).toBe(resolve(sheet, sort, "TextColor3"))
			t.expect(sort:HasTag("facet-secondary")).toBe(false)
		end
		world.stop()
	end)
end)
