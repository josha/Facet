--!strict
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local storage = game:GetService("ReplicatedStorage")

local cases = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local function interactive(
	id: string,
	contracts: { string },
	setup: (any) -> any,
	steps: { [string]: (any, any) -> () },
	keepGallery: boolean?
)
	table.insert(cases, { id = id, contracts = contracts, setup = setup, steps = steps, keepGallery = keepGallery })
end

local PAD: { [string]: Enum.KeyCode } = {
	ButtonA = Enum.KeyCode.Nine,
	ButtonB = Enum.KeyCode.Zero,
	ButtonX = Enum.KeyCode.Eight,
	ButtonY = Enum.KeyCode.Seven,
	DPadDown = Enum.KeyCode.Three,
	DPadLeft = Enum.KeyCode.Two,
	DPadRight = Enum.KeyCode.Four,
	ButtonL1 = Enum.KeyCode.R,
	ButtonR1 = Enum.KeyCode.O,
	ButtonL2 = Enum.KeyCode.E,
	ButtonSelect = Enum.KeyCode.Q,
	StickUp = Enum.KeyCode.W,
	StickDown = Enum.KeyCode.S,
	StickLeft = Enum.KeyCode.A,
	StickRight = Enum.KeyCode.D,
	RightStickUp = Enum.KeyCode.I,
	RightStickDown = Enum.KeyCode.K,
	RightStickLeft = Enum.KeyCode.J,
	RightStickRight = Enum.KeyCode.L,
}

local function gamepadWatch(): () -> { string }
	local seen = {}
	local connection = UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Gamepad1 then
			table.insert(seen, input.KeyCode.Name)
		end
	end)
	return function()
		connection:Disconnect()
		return seen
	end
end

local function device(t: any): any
	local virtual = (UserInputService :: any):CreateVirtualInput()
	t.check("virtual input is available", virtual ~= nil)
	local inset = GuiService:GetGuiInset()
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		local shield = Instance.new("ScreenGui")
		shield.DisplayOrder = 10000
		shield.IgnoreGuiInset = true
		local pad = Instance.new("TextButton")
		pad.Size = UDim2.fromScale(1, 1)
		pad.BackgroundTransparency = 1
		pad.Text = ""
		pad.Parent = shield
		shield.Parent = Players.LocalPlayer.PlayerGui
		t.settle(2)
		local seen: Vector3? = nil
		local watch = UserInputService.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				seen = input.Position
			end
		end)
		local probe = workspace.CurrentCamera.ViewportSize / 2 + inset
		virtual:SendMousePosition(probe)
		virtual:SendMouseButton(probe, Enum.UserInputType.MouseButton1, true)
		t.settle(2)
		virtual:SendMouseButton(probe, Enum.UserInputType.MouseButton1, false)
		t.settle(2)
		watch:Disconnect()
		shield:Destroy()
		if seen then
			inset = probe - Vector2.new(seen.X, seen.Y)
		end
		t.note("touch calibration inset", inset)
	end
	local io = { virtual = virtual, inset = inset }
	function io.move(at: Vector2)
		virtual:SendMousePosition(at + inset)
		t.settle(1)
	end
	function io.down(at: Vector2)
		virtual:SendMousePosition(at + inset)
		virtual:SendMouseButton(at + inset, Enum.UserInputType.MouseButton1, true)
		t.settle(1)
	end
	function io.up(at: Vector2)
		virtual:SendMouseButton(at + inset, Enum.UserInputType.MouseButton1, false)
		t.settle(1)
	end
	function io.drag(from: Vector2, to: Vector2, steps: number?, hold: number?)
		local count = steps or 12
		virtual:SendMousePosition(from + inset)
		t.settle(2)
		virtual:SendMouseButton(from + inset, Enum.UserInputType.MouseButton1, true)
		t.settle(hold or 2)
		for index = 1, count do
			virtual:SendMousePosition(from:Lerp(to, index / count) + inset)
			t.settle(1)
		end
		virtual:SendMouseButton(to + inset, Enum.UserInputType.MouseButton1, false)
		t.settle(4)
	end
	function io.click(at: Vector2)
		virtual:SendMousePosition(at + inset)
		t.settle(2)
		virtual:SendMouseButton(at + inset, Enum.UserInputType.MouseButton1, true)
		t.settle(2)
		virtual:SendMouseButton(at + inset, Enum.UserInputType.MouseButton1, false)
		t.settle(4)
	end
	function io.press(key: Enum.KeyCode, down: boolean)
		virtual:SendKey(down, key, false)
		t.settle(1)
	end
	function io.key(key: Enum.KeyCode)
		virtual:SendKey(true, key, false)
		t.settle(2)
		virtual:SendKey(false, key, false)
		t.settle(4)
	end
	function io.pad(button: string)
		local key = PAD[button]
		assert(key, "no emulator key for " .. button)
		virtual:SendKey(true, key, false)
		t.settle(3)
		virtual:SendKey(false, key, false)
		t.settle(5)
	end
	function io.warm()
		virtual:SendKey(true, PAD.ButtonL2, false)
		t.settle(3)
		virtual:SendKey(false, PAD.ButtonL2, false)
		t.settle(8)
		local previous = GuiService.SelectedObject
		local shield = Instance.new("ScreenGui")
		shield.DisplayOrder = 10000
		local pad = Instance.new("TextButton")
		pad.Size = UDim2.fromOffset(40, 40)
		pad.BackgroundTransparency = 1
		pad.Text = ""
		pad.Parent = shield
		shield.Parent = Players.LocalPlayer.PlayerGui
		t.settle(2)
		GuiService.SelectedObject = pad
		t.settle(2)
		virtual:SendKey(true, PAD.ButtonA, false)
		t.settle(3)
		virtual:SendKey(false, PAD.ButtonA, false)
		t.settle(4)
		shield:Destroy()
		GuiService.SelectedObject = previous
		t.settle(2)
	end
	function io.padHold(button: string, down: boolean)
		virtual:SendKey(down, PAD[button], false)
		t.settle(1)
	end
	function io.text(value: string)
		virtual:SendTextInput(value)
		t.settle(2)
	end
	function io.wheel(at: Vector2, delta: number)
		virtual:SendMousePosition(at + inset)
		t.settle(1)
		virtual:SendPointerAction(at + inset, { Wheel = delta })
		t.settle(4)
	end
	function io.pan(at: Vector2, delta: Vector2)
		virtual:SendMousePosition(at + inset)
		t.settle(1)
		virtual:SendPointerAction(at + inset, { Pan = delta })
		t.settle(4)
	end
	function io.pinch(at: Vector2, delta: number)
		virtual:SendMousePosition(at + inset)
		t.settle(1)
		virtual:SendPointerAction(at + inset, { Pinch = delta })
		t.settle(4)
	end
	return io
end

local function centre(node: GuiObject): Vector2
	return node.AbsolutePosition + node.AbsoluteSize / 2
end

local function selectedName(): string
	local selected = GuiService.SelectedObject
	return if selected then selected.Name else "nil"
end

local function textBox(root: Instance?): TextBox?
	if root == nil then
		return nil
	end
	if root:IsA("TextBox") then
		return root
	end
	return root:FindFirstChildWhichIsA("TextBox", true)
end

local function visibleNamed(t: any, root: Instance, name: string): any
	for _, node in root:GetDescendants() do
		if node.Name == name and node:IsA("GuiObject") and t.visible(node) then
			return node
		end
	end
	return nil
end

local function hits(at: Vector2): { GuiObject }
	return (Players.LocalPlayer.PlayerGui :: any):GetGuiObjectsAtPosition(at.X, at.Y)
end

local function example(t: any, name: string, patch: ((any) -> ())?, size: Vector2?): (any, any)
	local built
	local stage = t.mount(function(UI, Host, Compose, env)
		local ctx = t.context(UI, Host, Compose, env)
		if patch then
			patch(ctx)
		end
		built = (require :: any)(storage:WaitForChild("FacetExamples"):WaitForChild(name)).build(ctx)
		return if type(built) == "function" then built() else built.screen()
	end, { frames = 20, size = size })
	return stage, built
end

local function scenario(t: any, name: string, patch: ((any) -> ())?, size: Vector2?): (any, any)
	local built
	local stage = t.mount(function(UI, Host, Compose, env)
		local ctx = t.context(UI, Host, Compose, env)
		if patch then
			patch(ctx)
		end
		built = t.scenario(name).build(ctx)
		return if type(built) == "function" then built() else built.screen()
	end, { frames = 20, size = size })
	return stage, built
end

local function touch(t: any)
	t.device({ device = "iphone_14", input = Enum.PreferredInput.Touch, restore = "xbox" })
	for _ = 1, 180 do
		if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
			break
		end
		t.settle(1)
	end
	t.settle(10)
end

local function fill(node: any): string
	return `{node:GetStyled("BackgroundColor3")}|{node:GetStyled("BackgroundTransparency")}`
end

local function descendantCount(): number
	return #Players.LocalPlayer.PlayerGui:GetDescendants()
end

local function churnWatch(root: Instance, properties: { string }): () -> { [string]: number }
	local counts: { [string]: number } = {}
	local connections = {}
	local function watch(node: Instance)
		if node:IsA("GuiObject") or node:IsA("UIScale") or node:IsA("UIStroke") then
			for _, property in properties do
				local ok, signal = pcall(function()
					return node:GetPropertyChangedSignal(property)
				end)
				if ok then
					table.insert(
						connections,
						signal:Connect(function()
							local key = node.Name .. "." .. property
							counts[key] = (counts[key] or 0) + 1
						end)
					)
				end
			end
		end
	end
	watch(root)
	for _, node in root:GetDescendants() do
		watch(node)
	end
	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		return counts
	end
end

local function total(counts: { [string]: number }): number
	local sum = 0
	for _, value in counts do
		sum += value
	end
	return sum
end

local function stackProbe(t: any): any
	local value: any = {}
	value.stage = t.mount(function(UI, _, Compose)
		value.path = Compose.cell({})
		return UI.NavigationStack "Journey" {
			path = value.path,
			backLabel = "Back",
			root = {
				title = "Plan",
				content = function()
					return UI.Button "Next" {
						label = "Next",
						onActivate = function()
							local nextPath = table.clone(value.path:peek())
							table.insert(nextPath, { id = "detail", value = "coast" })
							value.path:set(nextPath)
						end,
					}
				end,
			},
			destinations = {
				detail = {
					title = "Detail",
					content = function()
						return UI.Button "Inner" { label = "Inner" }
					end,
				},
			},
		}
	end, { size = Vector2.new(900, 600), frames = 20 })
	value.gui = value.stage:FindFirstAncestorWhichIsA("LayerCollector")
	return value
end

local function backButton(t: any, gui: Instance): any
	local back = visibleNamed(t, gui, "Back")
	if back and not back:IsA("GuiButton") then
		back = back:FindFirstChildWhichIsA("GuiButton", true)
	end
	return back
end

add("stack-keyboard-activate-and-back", { "navigation-3-20" }, function(t)
	local io = device(t)
	local value = stackProbe(t)
	local nextButton = visibleNamed(t, value.gui, "Next")
	t.check("the root shows Next", nextButton ~= nil)
	if not nextButton then
		return
	end
	GuiService.SelectedObject = nextButton
	t.settle(3)
	io.key(Enum.KeyCode.Return)
	t.settle(40)
	t.check("Return on Next pushes the destination", #value.path:peek() == 1, #value.path:peek())
	local back = backButton(t, value.gui)
	t.check("the destination shows the Back chrome", back ~= nil)
	if back then
		GuiService.SelectedObject = back
		t.settle(3)
		io.key(Enum.KeyCode.Return)
		t.settle(40)
		t.check("Return on Back pops the stack", #value.path:peek() == 0, #value.path:peek())
	end
	io.key(Enum.KeyCode.Return)
	t.settle(40)
	GuiService.SelectedObject = visibleNamed(t, value.gui, "Next")
	t.settle(3)
	io.key(Enum.KeyCode.Return)
	t.settle(40)
	t.check("Return pushes again", #value.path:peek() == 1, #value.path:peek())
	local inner = visibleNamed(t, value.gui, "Inner")
	t.check("the destination's content mounts", inner ~= nil)
	GuiService.SelectedObject = nil
end)

add("pad-stack-activate-and-back", { "navigation-3-20" }, function(t)
	local io = device(t)
	local value = stackProbe(t)
	local nextButton = visibleNamed(t, value.gui, "Next")
	if not nextButton then
		t.check("the root shows Next", false)
		return
	end
	io.warm()
	local stop = gamepadWatch()
	GuiService.SelectedObject = nextButton
	t.settle(3)
	io.pad("ButtonA")
	t.settle(40)
	t.check("gamepad A on Next pushes the destination", #value.path:peek() == 1, #value.path:peek())
	t.note("selection after push", selectedName())
	t.check(
		"the selection moves into the destination",
		GuiService.SelectedObject ~= nil and GuiService.SelectedObject ~= nextButton,
		selectedName()
	)
	io.pad("ButtonB")
	t.settle(40)
	t.check("gamepad B pops the stack", #value.path:peek() == 0, #value.path:peek())
	t.check("the selection returns to Next", selectedName() == "Next", selectedName())
	io.pad("ButtonB")
	t.settle(10)
	t.check("gamepad B at the root pops nothing", #value.path:peek() == 0, #value.path:peek())
	t.note("gamepad events", stop())
	GuiService.SelectedObject = nil
end)

local function pagesProbe(t: any): any
	local value: any = { played = {} }
	value.stage = t.mount(function(UI, Host, Compose)
		value.selection = Compose.cell("one")
		local pages = {}
		for _, id in { "one", "two", "three" } do
			table.insert(pages, {
				id = id,
				title = id,
				content = Host.Frame "Course" {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					UI.Button "Play" {
						label = "Play " .. id,
						onActivate = function()
							table.insert(value.played, id)
						end,
					},
				},
			})
		end
		return Host.Frame "Holder" {
			Position = UDim2.fromOffset(20, 200),
			Size = UDim2.fromOffset(340, 420),
			BackgroundTransparency = 1,
			UI.PageView "Courses" { pages = pages, selection = value.selection },
			UI.Button "Below" { label = "Below", Position = UDim2.fromOffset(0, 440) },
		}
	end, { frames = 20 })
	value.pages = t.find(value.stage, "Pages")
	value.layout = value.pages and value.pages:FindFirstChildWhichIsA("UIPageLayout")
	return value
end

local function playOf(value: any, id: string): any
	local page = value.pages and value.pages:FindFirstChild(id)
	return page and page:FindFirstChild("Play", true)
end

add("page-view-keyboard-pages-and-activates", { "navigation-3-41" }, function(t)
	local io = device(t)
	local value = pagesProbe(t)
	local one = playOf(value, "one")
	t.check("page one shows Play", one ~= nil)
	if not one then
		return
	end
	GuiService.SelectedObject = one
	t.settle(3)
	io.key(Enum.KeyCode.Right)
	t.settle(40)
	t.check("Right pages to two", value.selection:peek() == "two", value.selection:peek())
	t.check("the selection moves into page two", GuiService.SelectedObject == playOf(value, "two"), selectedName())
	io.key(Enum.KeyCode.Return)
	t.check("Return reaches the showing page", value.played[#value.played] == "two", value.played)
	for _, id in { "one", "two", "three" } do
		value.selection:set(id)
		t.settle(40)
		GuiService.SelectedObject = playOf(value, id)
		t.settle(3)
		io.key(Enum.KeyCode.Down)
		local selected = GuiService.SelectedObject
		t.note(`{id} Down lands`, selected and selected:GetFullName())
		t.check(
			`{id}: one Down leaves the pages`,
			selected ~= nil and not selected:IsDescendantOf(value.pages),
			selected and selected:GetFullName()
		)
	end
	GuiService.SelectedObject = nil
end)

add("pad-page-view-pages-and-activates", { "navigation-3-41" }, function(t)
	local io = device(t)
	local value = pagesProbe(t)
	io.warm()
	GuiService.SelectedObject = playOf(value, "one")
	t.settle(3)
	io.pad("DPadRight")
	t.settle(40)
	t.check("DPadRight pages to two", value.selection:peek() == "two", value.selection:peek())
	io.pad("ButtonA")
	t.check("gamepad A reaches the showing page", value.played[#value.played] == "two", value.played)
	io.pad("DPadRight")
	t.settle(40)
	t.check("a second DPadRight pages to three", value.selection:peek() == "three", value.selection:peek())
	io.pad("DPadRight")
	t.settle(40)
	t.check("DPadRight at the last page stays on three", value.selection:peek() == "three", value.selection:peek())
	io.pad("DPadDown")
	local selected = GuiService.SelectedObject
	t.check(
		"one DPadDown leaves the pages",
		selected ~= nil and not selected:IsDescendantOf(value.pages),
		selected and selected:GetFullName()
	)
	GuiService.SelectedObject = nil
end)

add("touch-page-view-swipes-one-page", { "navigation-3-38" }, function(t)
	touch(t)
	local io = device(t)
	local value = pagesProbe(t)
	if not (value.pages and value.layout) then
		t.check("the pages mount", false)
		return
	end
	local function swipe(fraction: number, hold: number?)
		local r = t.rect(value.pages)
		local y = r.y + r.h * 0.7
		local from = r.x + r.w * 0.5 + r.w * fraction / 2
		local to = r.x + r.w * 0.5 - r.w * fraction / 2
		io.drag(Vector2.new(from, y), Vector2.new(to, y), 12, hold)
		t.settle(90)
	end
	swipe(0.6)
	t.check("one swipe left advances one page", value.selection:peek() == "two", value.selection:peek())
	t.check(
		"the layout shows page two",
		value.layout.CurrentPage and value.layout.CurrentPage.Name == "two",
		value.layout.CurrentPage
	)
	swipe(0.6, 30)
	t.check(
		"a swipe held still before release advances one page",
		value.selection:peek() == "three",
		value.selection:peek()
	)
	swipe(-0.6)
	t.check("a swipe right goes back one page", value.selection:peek() == "two", value.selection:peek())
	swipe(0.03)
	t.check("incidental movement stays on the current page", value.selection:peek() == "two", value.selection:peek())
	value.selection:set("three")
	value.selection:set("two")
	t.settle(90)
	t.check(
		"an owner reversal is not swallowed",
		value.selection:peek() == "two" and value.layout.CurrentPage.Name == "two",
		value.layout.CurrentPage
	)
end)

add("page-view-affordances", { "navigation-3-43" }, function(t)
	local io = device(t)
	local value = pagesProbe(t)
	local indicators = t.find(value.stage, "Indicators")
	t.check("the dots mount", indicators ~= nil)
	if indicators then
		local dots = {}
		for _, node in indicators:GetDescendants() do
			if node:IsA("GuiButton") and t.visible(node) then
				table.insert(dots, node)
			end
		end
		t.check("three dot targets", #dots == 3, #dots)
		for _, dot in dots do
			t.check(
				`dot {dot.Name} meets the 44 px target floor`,
				dot.AbsoluteSize.X >= 43.5 and dot.AbsoluteSize.Y >= 43.5,
				dot.AbsoluteSize
			)
		end
		table.sort(dots, function(a, b)
			return a.AbsolutePosition.X < b.AbsolutePosition.X
		end)
		if #dots == 3 then
			io.click(centre(dots[3]))
			t.settle(60)
			t.check(
				"a click on the third dot shows page three",
				value.selection:peek() == "three",
				value.selection:peek()
			)
			GuiService.SelectedObject = dots[1]
			t.settle(3)
			t.check("a dot takes the engine selection", GuiService.SelectedObject == dots[1], selectedName())
			io.key(Enum.KeyCode.Return)
			t.settle(60)
			t.check("Return on the first dot shows page one", value.selection:peek() == "one", value.selection:peek())
			GuiService.SelectedObject = nil
		end
	end
	local nextButton = t.find(value.stage, "Next")
	if nextButton then
		io.move(Vector2.new(5, 5))
		t.settle(6)
		local rest = fill(nextButton)
		io.move(centre(nextButton))
		io.move(centre(nextButton) + Vector2.new(2, 0))
		t.settle(10)
		t.check("Next hovers under the mouse", nextButton.GuiState == Enum.GuiState.Hover, nextButton.GuiState)
		t.check("and paints its hover fill", fill(nextButton) ~= rest, { rest, fill(nextButton) })
		io.click(centre(nextButton))
		t.settle(60)
		t.check("a click on Next pages forward", value.selection:peek() == "two", value.selection:peek())
	else
		t.check("the Next control mounts", false)
	end
end)

add("touch-page-view-dots", { "navigation-3-43" }, function(t)
	touch(t)
	local io = device(t)
	local value = pagesProbe(t)
	local indicators = t.find(value.stage, "Indicators")
	local dots = {}
	for _, node in (indicators and indicators:GetDescendants() or {}) do
		if node:IsA("GuiButton") and t.visible(node) then
			table.insert(dots, node)
		end
	end
	table.sort(dots, function(a, b)
		return a.AbsolutePosition.X < b.AbsolutePosition.X
	end)
	t.check("three dots on the phone", #dots == 3, #dots)
	if #dots == 3 then
		for _, dot in dots do
			t.check(
				`dot {dot.Name} meets 44 px on touch`,
				dot.AbsoluteSize.X >= 43.5 and dot.AbsoluteSize.Y >= 43.5,
				dot.AbsoluteSize
			)
		end
		io.click(centre(dots[2]))
		t.settle(60)
		t.check("a touch tap on the second dot shows page two", value.selection:peek() == "two", value.selection:peek())
	end
end)

add("component-setup-error-and-throwing-cleanup", { "apps-123" }, function(t)
	local Facet = t.Facet
	local Compose = Facet.Compose
	local target = Players.LocalPlayer.PlayerGui
	local baseline = descendantCount()
	local runtime = Facet.Roblox.createRuntime()
	local Host = runtime.constructors
	local released = {}
	local ok, problem = pcall(function()
		return runtime.mount(function()
			Compose.cleanup(function()
				table.insert(released, "partial")
			end)
			local gui = Host.ScreenGui "Partial" {
				Host.Frame "Built" { Size = UDim2.fromOffset(10, 10) },
			}
			error("setup failed on purpose", 0)
			return gui
		end, target)
	end)
	t.settle(4)
	t.note("setup error", tostring(problem))
	t.check("the setup error surfaces to the caller", not ok, problem)
	t.check("the partial component's cleanup ran", table.find(released, "partial") ~= nil, released)
	t.check(
		"no partial instance stays in PlayerGui",
		target:FindFirstChild("Partial") == nil and target:FindFirstChild("Built", true) == nil
	)
	local order = {}
	local stop = runtime.mount(function()
		Compose.cleanup(function()
			table.insert(order, "first")
		end)
		Compose.cleanup(function()
			error("cleanup failed on purpose", 0)
		end)
		Compose.cleanup(function()
			table.insert(order, "third")
		end)
		return Host.ScreenGui "Owner" { Host.Frame "Child" { Size = UDim2.fromOffset(10, 10) } }
	end, target)
	t.settle(2)
	t.check("the component mounts", target:FindFirstChild("Owner") ~= nil)
	local stopped, why = pcall(stop)
	t.settle(2)
	t.note("stop with a throwing cleanup", { ok = stopped, error = tostring(why), order = order })
	t.check(
		"every other cleanup still runs",
		table.find(order, "first") ~= nil and table.find(order, "third") ~= nil,
		order
	)
	t.check("the owner's instances are released", target:FindFirstChild("Owner") == nil)
	runtime:dispose()
	t.settle(2)
	t.check(
		"nothing the components built remains",
		target:FindFirstChild("Owner") == nil
			and target:FindFirstChild("Child", true) == nil
			and target:FindFirstChild("Built", true) == nil
	)
	t.note("PlayerGui descendants before and after", { baseline, descendantCount() })
end)

add("compose-delivery-order", { "mech1-65" }, function(t)
	local Compose = t.Facet.Compose
	local owner = Compose.createOwner()
	local source = Compose.cell(0)
	local seen = {}
	Compose.withOwner(owner, function()
		local first = Compose.formula(function(use)
			return use(source)
		end)
		local second = Compose.formula(function(use)
			return use(source)
		end)
		local primed = { false, false }
		Compose.watch(function(use)
			use(second)
			if primed[2] then
				table.insert(seen, 2)
			end
			primed[2] = true
		end)
		Compose.watch(function(use)
			use(first)
			if primed[1] then
				table.insert(seen, 1)
			end
			primed[1] = true
		end)
	end)
	source:set(1)
	t.settle(2)
	source:set(2)
	t.settle(2)
	t.note("delivery", seen)
	t.check(
		"observers of separately created formulas are delivered in registration order, every change",
		table.concat(seen, ",") == "2,1,2,1",
		seen
	)
	owner.dispose()
end)

local IMAGE = "rbxassetid://92798715826227"

add("image-tile-slice-resample", { "mech2-47", "paint-78" }, function(t)
	local modes
	local stage = t.mount(function(UI, Host, Compose)
		modes = Compose.cell("fit")
		return UI.HStack "Row" {
			UI.Image "Tile" {
				image = IMAGE,
				scaleMode = "tile",
				tileSize = { width = 16, height = 16 },
				Size = UDim2.fromOffset(64, 64),
			},
			UI.Image "Slice" {
				image = IMAGE,
				scaleMode = "slice",
				sliceCenter = { x0 = 4, y0 = 4, x1 = 12, y1 = 12 },
				sliceScale = 2,
				Size = UDim2.fromOffset(64, 64),
			},
			UI.Image "Pixel" { image = IMAGE, resample = "pixelated", Size = UDim2.fromOffset(64, 64) },
			UI.Image "Bound" { image = IMAGE, scaleMode = modes, Size = UDim2.fromOffset(64, 64) },
		}
	end, { frames = 20 })
	local tile, slice, pixel, bound =
		t.find(stage, "Tile"), t.find(stage, "Slice"), t.find(stage, "Pixel"), t.find(stage, "Bound")
	t.check("four images mount", tile and slice and pixel and bound and true or false)
	if not (tile and slice and pixel and bound) then
		return
	end
	t.check("tile sets ScaleType Tile", tile:GetStyled("ScaleType") == Enum.ScaleType.Tile, tile:GetStyled("ScaleType"))
	t.check(
		"tileSize reaches TileSize",
		tile:GetStyled("TileSize") == UDim2.fromOffset(16, 16),
		tile:GetStyled("TileSize")
	)
	t.check(
		"slice sets ScaleType Slice",
		slice:GetStyled("ScaleType") == Enum.ScaleType.Slice,
		slice:GetStyled("ScaleType")
	)
	t.check(
		"sliceCenter reaches SliceCenter",
		slice:GetStyled("SliceCenter") == Rect.new(4, 4, 12, 12),
		slice:GetStyled("SliceCenter")
	)
	t.check("sliceScale reaches SliceScale", slice:GetStyled("SliceScale") == 2, slice:GetStyled("SliceScale"))
	t.check(
		"pixelated sets ResampleMode Pixelated",
		pixel:GetStyled("ResampleMode") == Enum.ResamplerMode.Pixelated,
		pixel:GetStyled("ResampleMode")
	)
	local expected = {
		fit = Enum.ScaleType.Fit,
		fill = Enum.ScaleType.Crop,
		crop = Enum.ScaleType.Crop,
		stretch = Enum.ScaleType.Stretch,
	}
	for _, mode in { "fit", "fill", "crop", "stretch", "fit" } do
		modes:set(mode)
		t.settle(3)
		t.check(
			`a bound scaleMode {mode} sets ScaleType {expected[mode].Name}`,
			bound:GetStyled("ScaleType") == expected[mode],
			bound:GetStyled("ScaleType")
		)
	end
	local Facet = t.Facet
	local refused = {}
	for name, spec in
		{
			tileWithoutSize = { image = IMAGE, scaleMode = "tile" },
			sizeWithoutTile = { image = IMAGE, tileSize = { width = 8, height = 8 } },
			sliceWithoutCenter = { image = IMAGE, scaleMode = "slice" },
			centerWithoutSlice = { image = IMAGE, sliceCenter = { x0 = 1, y0 = 1, x1 = 2, y1 = 2 } },
			fractionalTile = { image = IMAGE, scaleMode = "tile", tileSize = { width = 1.5, height = 8 } },
			circleSlice = {
				image = IMAGE,
				scaleMode = "slice",
				sliceCenter = { x0 = 1, y0 = 1, x1 = 2, y1 = 2 },
				shape = "circle",
			},
			unknownMode = { image = IMAGE, scaleMode = "zoom" },
		}
	do
		local ok = pcall(function()
			local runtime = Facet.Roblox.createRuntime()
			local stop = runtime.mount(function()
				local UI = Facet.controls(runtime, {})
				return runtime.constructors.ScreenGui "Refusal" { UI.Image(spec) }
			end, Players.LocalPlayer.PlayerGui)
			stop()
			runtime:dispose()
		end)
		refused[name] = not ok
		t.check(`{name} is refused`, not ok)
	end
	local leftover = Players.LocalPlayer.PlayerGui:FindFirstChild("Refusal")
	t.check("no refused image leaves a ScreenGui behind", leftover == nil)
	if leftover then
		leftover:Destroy()
	end
end)

add("image-scale-mode-renders", { "paint-78" }, function(t)
	local stage = t.mount(function(UI)
		return UI.HStack "Row" {
			UI.Image "Fit" { image = IMAGE, scaleMode = "fit", Size = UDim2.fromOffset(120, 40) },
			UI.Image "Crop" { image = IMAGE, scaleMode = "crop", Size = UDim2.fromOffset(120, 40) },
			UI.Image "Stretch" { image = IMAGE, scaleMode = "stretch", Size = UDim2.fromOffset(120, 40) },
		}
	end, { frames = 30 })
	for _, name in { "Fit", "Crop", "Stretch" } do
		local node = t.find(stage, name)
		t.check(
			`{name} mounts with its own box`,
			node ~= nil and node.AbsoluteSize == Vector2.new(120, 40),
			node and node.AbsoluteSize
		)
		if node then
			t.note(`{name} loaded`, { loaded = node.IsLoaded, scale = node:GetStyled("ScaleType") })
		end
	end
end)
add("icon-clamped-to-content-box", { "paint-51" }, function(t)
	for _, entry in t.themes do
		for _, case in
			{
				{ key = "icon-only", size = UDim2.fromOffset(20, 20) },
				{ key = "tight", size = UDim2.fromOffset(52, 44), label = "Go" },
				{ key = "room", size = UDim2.fromOffset(220, 60), label = "Continue" },
			}
		do
			local where = `{entry.name} {case.key}`
			local stage = t.mount(function(UI)
				return UI.Button "Back" {
					icon = "chevron.leading",
					label = case.label,
					Size = case.size,
					AutomaticSize = Enum.AutomaticSize.None,
				}
			end, { size = Vector2.new(400, 200), theme = entry.package, frames = 8 })
			local button = t.find(stage, "Back")
			local icon = button and t.find(button, "LeadingIcon")
			local content = button and t.find(button, "Content")
			t.check(`{where} the icon and content box mount`, icon ~= nil and content ~= nil)
			if icon and content then
				local ib = t.rect(icon)
				t.check(`{where} the picture is never zero`, ib.w >= 1 and ib.h >= 1, { ib.w, ib.h })
				if case.key == "icon-only" then
					t.inside(`{where} the picture stays inside the content box`, icon, content, 0.5)
				else
					local pad = button:FindFirstChildWhichIsA("UIPadding")
					local box = t.rect(button)
					local left = if pad then pad:GetStyled("PaddingLeft").Offset else 0
					local right = if pad then pad:GetStyled("PaddingRight").Offset else 0
					local top = if pad then pad:GetStyled("PaddingTop").Offset else 0
					local bottom = if pad then pad:GetStyled("PaddingBottom").Offset else 0
					t.inside(`{where} the picture stays inside the button's content box`, icon, {
						x = box.x + left,
						y = box.y + top,
						w = box.w - left - right,
						h = box.h - top - bottom,
						r = box.r - right,
						b = box.b - bottom,
					}, 0.5)
				end
				t.inside(`{where} the picture stays inside the button`, icon, button, 0.5)
				t.note(`{where} icon`, { ib.w, ib.h, t.rect(content).w, t.rect(content).h })
				if case.key == "room" then
					local metric = entry.package.metrics.controls
					local rung = metric and metric.regular and metric.regular.iconSize
					if rung then
						t.near(`{where} a button with room draws the rung untouched`, ib.w, rung, 0.5)
					end
				end
			end
			t.cleanup()
		end
	end
end)

local function sortable(t: any, count: number): any
	local value: any = { reorders = {}, activated = {} }
	value.stage = t.mount(function(UI, Host, Compose)
		local items = {}
		for index = 1, count do
			items[index] = { id = tostring(index) }
		end
		value.rows = Compose.cell(items)
		return Host.Frame "Holder" {
			Position = UDim2.fromOffset(20, 200),
			Size = UDim2.fromOffset(320, 264),
			BackgroundTransparency = 1,
			UI.VirtualList "Sortable" {
				from = value.rows,
				key = "id",
				itemSize = 44,
				reorderable = true,
				onReorder = function(keys, slot)
					table.insert(value.reorders, { keys = keys, slot = slot })
				end,
				Size = UDim2.fromScale(1, 1),
				render = function(current)
					return UI.Button({
						Name = "Row" .. current:peek().id,
						label = "Row " .. current:peek().id,
						Size = UDim2.fromScale(1, 1),
						onActivate = function()
							table.insert(value.activated, current:peek().id)
						end,
					})
				end,
			},
		}
	end, { frames = 16 })
	value.list = t.find(value.stage, "Sortable")
	value.body = value.list
		and (
			if value.list:IsA("ScrollingFrame")
				then value.list
				else value.list:FindFirstChildWhichIsA("ScrollingFrame", true)
		)
	return value
end

local function handleOf(value: any, id: string): any
	local row = value.stage:FindFirstChild("Row" .. id, true)
	local wrapper = row and row:FindFirstAncestor("Reorderable")
	return wrapper and wrapper:FindFirstChild("Move"), row
end

local function dragging(value: any): number
	local count = 0
	for _, node in value.stage:GetDescendants() do
		if node.Name == "Reorderable" and node:GetAttribute("FacetDragging") == true then
			count += 1
		end
	end
	return count
end

add("reorder-mouse-thresholds", { "inputs-83", "mech2-106" }, function(t)
	local io = device(t)
	local value = sortable(t, 12)
	local handle, row = handleOf(value, "2")
	t.check("row 2 has a move handle", handle ~= nil and row ~= nil)
	if not (handle and row) then
		return
	end
	local at = centre(handle)
	io.drag(at, at + Vector2.new(0, 2), 2)
	t.settle(10)
	t.note("after a small press", { dragging = dragging(value), reorders = #value.reorders })
	t.check("a press under the drag threshold never reorders", #value.reorders == 0, value.reorders)
	t.check("the tap is not eaten: it arms exactly one row for a move", dragging(value) == 1, dragging(value))
	io.click(at)
	t.settle(10)
	t.check("a second tap commits the armed move in place and ends it", dragging(value) == 0, dragging(value))
	t.note("reorders after the armed tap pair", value.reorders)
	table.clear(value.reorders)
	handle = handleOf(value, "2")
	io.drag(centre(handle), centre(handle) + Vector2.new(0, 44 * 2 + 4), 16)
	t.settle(20)
	t.note("drag reorder", value.reorders)
	t.check("a drag past the threshold reorders once", #value.reorders == 1, value.reorders)
	if value.reorders[1] then
		t.check("the dragged key is row 2", value.reorders[1].keys[1] == "2", value.reorders[1].keys)
		t.check("it lands two rows lower", value.reorders[1].slot == 3, value.reorders[1].slot)
	end
	t.check("the drag ends the move", dragging(value) == 0, dragging(value))
	io.click(centre(row))
	t.check(
		"a click on the row content activates it once",
		#value.activated == 1 and value.activated[1] == "2",
		value.activated
	)
end)

add("touch-reorder-arms-and-pans", { "inputs-83", "inputs-209" }, function(t)
	touch(t)
	local io = device(t)
	local value = sortable(t, 30)
	local handle, row = handleOf(value, "2")
	if not (handle and row and value.body) then
		t.check("the list, row and handle mount", false)
		return
	end
	local before = value.body.CanvasPosition.Y
	local from = centre(row)
	io.drag(from, from - Vector2.new(0, 150), 12)
	t.settle(30)
	t.note("pan on the row", { canvas = value.body.CanvasPosition.Y, reorders = value.reorders })
	t.check(
		"a finger that travels on the row content pans the list",
		value.body.CanvasPosition.Y > before + 20,
		{ before, value.body.CanvasPosition.Y }
	)
	t.check("and never reorders", #value.reorders == 0, value.reorders)
	t.check("and does not activate the row", #value.activated == 0, value.activated)
	t.settle(180)
	value.body.CanvasPosition = Vector2.new(0, 0)
	t.stable(value.body, 10)
	t.check(
		"the pan's momentum has ended before the next gesture",
		value.body.CanvasPosition.Y == 0,
		value.body.CanvasPosition
	)
	handle = handleOf(value, "2")
	local canvasDuring = {}
	local watch = value.body:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		table.insert(canvasDuring, value.body.CanvasPosition.Y)
	end)
	io.drag(centre(handle), centre(handle) + Vector2.new(0, 90), 14, 20)
	t.settle(30)
	watch:Disconnect()
	t.note("handle drag", { reorders = value.reorders, canvas = canvasDuring })
	t.check("a finger held on the handle then moved reorders", #value.reorders == 1, value.reorders)
	t.check("the list does not pan under the dragged row", #canvasDuring == 0, canvasDuring)
	t.check("the drag ends", dragging(value) == 0, dragging(value))
end)

add("wheel-scrolls-through-drag-zones", { "mech2-97" }, function(t)
	local io = device(t)
	local value = sortable(t, 30)
	local handle = handleOf(value, "2")
	if not (handle and value.body) then
		t.check("the handle mounts", false)
		return
	end
	local before = value.body.CanvasPosition.Y
	io.wheel(centre(handle), -3)
	t.settle(20)
	t.note("wheel over the handle", { before, value.body.CanvasPosition.Y })
	t.check(
		"the wheel over a drag handle scrolls the list",
		value.body.CanvasPosition.Y > before + 1,
		{ before, value.body.CanvasPosition.Y }
	)
	local mid = value.body.CanvasPosition.Y
	io.pan(centre(handle), Vector2.new(0, -60))
	t.settle(20)
	t.note("trackpad pan over the handle", { mid, value.body.CanvasPosition.Y })
	t.check("neither starts a reorder", #value.reorders == 0 and dragging(value) == 0, value.reorders)
end)

add("reorder-capture-released-on-teardown", { "inputs-144" }, function(t)
	local io = device(t)
	local LogService = game:GetService("LogService")
	local errors = {}
	local watch = LogService.MessageOut:Connect(function(message, kind)
		if kind == Enum.MessageType.MessageError then
			table.insert(errors, message)
		end
	end)
	local value = sortable(t, 12)
	local handle = handleOf(value, "3")
	if not handle then
		watch:Disconnect()
		t.check("the handle mounts", false)
		return
	end
	local at = centre(handle)
	io.down(at)
	t.settle(2)
	for step = 1, 6 do
		io.move(at + Vector2.new(0, step * 8))
	end
	t.check("a drag is in flight", dragging(value) == 1, dragging(value))
	t.cleanup()
	t.settle(4)
	io.move(at + Vector2.new(0, 80))
	io.up(at + Vector2.new(0, 80))
	t.settle(6)
	t.check("tearing the list down mid-drag raises no error", #errors == 0, errors)
	local fresh = sortable(t, 12)
	local second = handleOf(fresh, "2")
	io.drag(centre(second), centre(second) + Vector2.new(0, 48), 12)
	t.settle(20)
	watch:Disconnect()
	t.check("a fresh list's press is not blocked by the torn-down capture", #fresh.reorders == 1, fresh.reorders)
	t.check("still no error", #errors == 0, errors)
end)

add("match3-detector-tap-selects-once", { "mech2-106" }, function(t)
	local io = device(t)
	local stage, built = example(t, "07_match3", function(ctx)
		ctx.reducedMotion = ctx.Compose.cell(true)
	end)
	t.settle(30)
	local tile = stage:FindFirstChild("tile" .. tostring(built.tileIdAt(4, 4)), true)
	local hit = tile and tile:FindFirstChild("hit", true)
	t.check("a board tile mounts", hit ~= nil)
	if not hit then
		return
	end
	local stroke = hit:FindFirstChild("Selection")
	io.click(centre(hit))
	t.settle(10)
	t.check("one tap on a tile selects it once", stroke and stroke.Transparency == 0, stroke and stroke.Transparency)
	io.click(centre(hit))
	t.settle(10)
	t.check(
		"a second tap deselects: each tap counted exactly once",
		stroke and stroke.Transparency == 1,
		stroke and stroke.Transparency
	)
	t.check("no swap happened", built.moves() == 0, built.moves())
end)

add("touch-match3-detector-tap-selects-once", { "mech2-106" }, function(t)
	touch(t)
	local io = device(t)
	local stage, built = example(t, "07_match3", function(ctx)
		ctx.reducedMotion = ctx.Compose.cell(true)
	end)
	t.settle(30)
	local tile = stage:FindFirstChild("tile" .. tostring(built.tileIdAt(4, 4)), true)
	local hit = tile and tile:FindFirstChild("hit", true)
	if not hit then
		t.check("a board tile mounts", false)
		return
	end
	local stroke = hit:FindFirstChild("Selection")
	io.click(centre(hit))
	t.settle(10)
	t.check(
		"one touch tap on a tile selects it once",
		stroke and stroke.Transparency == 0,
		stroke and stroke.Transparency
	)
	io.click(centre(hit))
	t.settle(10)
	t.check("a second touch tap deselects", stroke and stroke.Transparency == 1, stroke and stroke.Transparency)
end)

local function geometryWatch(nodes: { Instance }): () -> number
	local count = 0
	local connections = {}
	for _, node in nodes do
		for _, property in { "AbsolutePosition", "AbsoluteSize" } do
			table.insert(
				connections,
				node:GetPropertyChangedSignal(property):Connect(function()
					count += 1
				end)
			)
		end
	end
	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		return count
	end
end

add("feedback-motion-is-paint-only", { "mech2-70" }, function(t)
	local io = device(t)
	local value: any = {}
	local stage = t.mount(function(UI, _, Compose)
		value.invalid = Compose.cell(false)
		value.expanded = Compose.cell(false)
		return UI.VStack "Column" {
			gap = "s",
			UI.Text "Above" { text = "Above" },
			UI.Button "Pop" { label = "Pop", pop = true, onActivate = function() end },
			UI.Text "Middle" { text = "Middle" },
			UI.TextInput "Field" { value = Compose.cell("abc"), onChange = function() end, invalid = value.invalid },
			UI.Text "Lower" { text = "Lower" },
			UI.DisclosureGroup "Group" {
				label = "Details",
				expanded = value.expanded,
				content = function()
					return UI.Text "Inside" { text = "Inside" }
				end,
			},
		}
	end, { frames = 20, reducedMotion = false })
	local above, pop, middle, field, lower, group =
		t.find(stage, "Above"),
		t.find(stage, "Pop"),
		t.find(stage, "Middle"),
		t.find(stage, "Field"),
		t.find(stage, "Lower"),
		t.find(stage, "Group")
	t.check("the column mounts", above and pop and middle and field and lower and group and true or false)
	if not (above and pop and middle and field and lower and group) then
		return
	end
	local stopNeighbours = geometryWatch({ above, middle, lower })
	local scale = pop:FindFirstChild("Pop")
	local scales = {}
	local scaleWatch = game:GetService("RunService").RenderStepped:Connect(function()
		if scale and scale.Scale ~= 1 then
			table.insert(scales, scale.Scale)
		end
	end)
	io.click(centre(pop))
	t.settle(40)
	scaleWatch:Disconnect()
	t.note("pop scale samples", #scales)
	t.check("the Button pop animates its UIScale", #scales > 0, #scales)
	t.check("the pop moves no neighbour", stopNeighbours() == 0)
	local fieldRest = t.rect(field)
	local moved = 0
	local shaking = {}
	for _, node in field:GetDescendants() do
		if node:IsA("GuiObject") then
			table.insert(shaking, node)
		end
	end
	table.insert(shaking, field)
	local stopShake = geometryWatch(shaking)
	stopNeighbours = geometryWatch({ above, middle, lower })
	value.invalid:set(true)
	t.settle(40)
	moved = stopShake()
	t.note("shake geometry events", moved)
	t.check("the invalid shake moves the field's paint", moved > 0, moved)
	t.check("the shake moves no neighbour", stopNeighbours() == 0)
	t.check(
		"the field returns to its slot",
		t.rect(field).x == fieldRest.x and t.rect(field).y == fieldRest.y,
		{ t.rect(field), fieldRest }
	)
	local header = group:FindFirstChild("Header", true) or group
	local caret = header:FindFirstChild("LeadingIcon", true) or header:FindFirstChild("TrailingIcon", true)
	local title = header:FindFirstChild("Title", true)
	t.check("the group has a caret and a title", caret ~= nil and title ~= nil)
	if caret and title then
		local turns = {}
		local turnWatch = caret:GetPropertyChangedSignal("Rotation"):Connect(function()
			table.insert(turns, caret.Rotation)
		end)
		local stopHeader = geometryWatch({ title, caret, above, middle })
		value.expanded:set(true)
		t.settle(40)
		turnWatch:Disconnect()
		t.note("caret turn", { samples = #turns, final = caret.Rotation })
		t.check("the caret turns", #turns > 1, #turns)
		t.check("the caret turn moves no header text and resizes nothing above", stopHeader() == 0)
	end
	t.settle(20)
	local stopIdle = churnWatch(stage, {
		"Position",
		"Size",
		"AbsolutePosition",
		"AbsoluteSize",
		"Rotation",
		"BackgroundTransparency",
		"BackgroundColor3",
		"TextTransparency",
		"TextColor3",
		"Visible",
		"Text",
		"Scale",
	})
	t.settle(60)
	local idle = stopIdle()
	t.note("idle writes", idle)
	t.check("a settled surface writes nothing across 60 idle frames", total(idle) == 0, idle)
end)

add("radial-lift-is-paint-only", { "mech2-70" }, function(t)
	local value: any = {}
	local stage = t.mount(function(UI, _, Compose)
		value.open = Compose.cell(true)
		local items = {}
		for _, id in { "N", "E", "S", "W" } do
			table.insert(items, { id = id, slot = id, label = id, completion = "stay", onSelect = function() end })
		end
		return UI.RadialMenu "Quick" { isPresented = value.open, items = items }
	end, { size = Vector2.new(800, 600), frames = 60, reducedMotion = false })
	local gui = stage:FindFirstAncestorWhichIsA("LayerCollector")
	local panel = visibleNamed(t, gui, "RadialPanel")
	t.check("the ring presents", panel ~= nil)
	if not panel then
		return
	end
	t.stable(panel, 6)
	local buttons = {}
	for _, id in { "N", "E", "S", "W" } do
		buttons[id] = panel:FindFirstChild(id, true)
	end
	local stopOthers = geometryWatch({ buttons.E, buttons.S, buttons.W, panel })
	local moves = 0
	local lift = {}
	for _, node in buttons.N:GetDescendants() do
		if node:IsA("GuiObject") then
			table.insert(lift, node)
		end
	end
	table.insert(lift, buttons.N)
	local sector = buttons.N.Parent
	if sector and sector:IsA("GuiObject") then
		table.insert(lift, sector)
	end
	local stopGeometry = geometryWatch(lift)
	GuiService.SelectedObject = buttons.N
	t.settle(30)
	local own = stopGeometry()
	moves = stopOthers()
	t.note("selection feedback geometry", { own = own, others = moves })
	t.check("selecting North moves nothing: its own box keeps its place and size", own == 0, own)
	t.check("and no other ring stop moves", moves == 0, moves)
	GuiService.SelectedObject = nil
end)

add("fade-group-uses-group-transparency", { "mech2-101" }, function(t)
	local io = device(t)
	local stage, built = scenario(t, "with_animation")
	t.settle(10)
	local animate = t.find(stage, "Animate")
	if not animate then
		t.check("the Animate button mounts", false)
		return
	end
	local samples, childFades = {}, {}
	local group
	local watcher = game:GetService("RunService").RenderStepped:Connect(function()
		group = group or stage:FindFirstChild("DetailArrival", true)
		if group then
			table.insert(samples, group.GroupTransparency)
			local label = group:FindFirstChild("DetailPanel", true)
			if label then
				table.insert(childFades, label.TextTransparency)
			end
		end
	end)
	io.click(centre(animate))
	t.settle(40)
	watcher:Disconnect()
	t.check("the details arrive as a CanvasGroup", group ~= nil and group:IsA("CanvasGroup"), group and group.ClassName)
	t.note("group transparency on enter", samples)
	t.check("the group enters from transparent", #samples > 2 and samples[1] > 0.3, samples[1])
	t.check("and rests at GroupTransparency 0", samples[#samples] == 0, samples[#samples])
	local steady = true
	for _, fade in childFades do
		if fade ~= 0 then
			steady = false
		end
	end
	t.check(
		"its label's own TextTransparency never changes: the group fades it",
		steady and #childFades > 0,
		childFades
	)
	local exits = {}
	local exitWatch = game:GetService("RunService").RenderStepped:Connect(function()
		if group and group.Parent then
			table.insert(exits, group.GroupTransparency)
		end
	end)
	io.click(centre(animate))
	t.settle(40)
	exitWatch:Disconnect()
	t.note("group transparency on exit", exits)
	local rising = #exits > 1 and exits[#exits] > exits[1]
	t.check("the exit fades the group out before removing it", rising, exits)
	t.check("the group leaves once it has faded", group.Parent == nil or not t.visible(group))
	t.note("runs", built.report().runs)
end)

add("ring-geometry-only-on-real-change", { "paint-88" }, function(t)
	local value: any = {}
	local stage = t.mount(function(UI, Host, Compose)
		value.progress = Compose.cell(0.25)
		value.width = Compose.cell(300)
		return Host.Frame "Holder" {
			Size = function(use)
				return UDim2.fromOffset(use(value.width), 200)
			end,
			BackgroundTransparency = 1,
			UI.ProgressView "Ring" { value = value.progress, presentation = "circular", diameter = 96 },
		}
	end, { frames = 20 })
	local fillPath = t.find(stage, "RingFill")
	t.check("the ring fill is a Path2D", fillPath ~= nil and fillPath:IsA("Path2D"))
	if not fillPath then
		return
	end
	local function points(): string
		local out = {}
		for _, point in fillPath:GetControlPoints() do
			table.insert(out, tostring(point.Position) .. tostring(point.LeftTangent) .. tostring(point.RightTangent))
		end
		return table.concat(out, ";")
	end
	local before = points()
	local host = fillPath.Parent
	local rects = {}
	for _, width in { 320, 480, 260, 600, 300 } do
		value.width:set(width)
		t.settle(4)
		table.insert(rects, host and host.AbsolutePosition)
		t.check(`a {width} px host re-uploads no geometry`, points() == before)
	end
	t.note("host positions while resizing", rects)
	value.progress:set(0.75)
	t.settle(6)
	t.check("a real progress change uploads new geometry", points() ~= before)
	local ring = fillPath:FindFirstAncestorWhichIsA("GuiObject")
	t.check("the ring keeps its diameter", ring and ring.AbsoluteSize.X > 0, ring and ring.AbsoluteSize)
end)

add("press-feedback-reaches-the-device", { "paint-57" }, function(t)
	local io = device(t)
	local effect
	local built
	local stage = t.mount(function(UI, Host, Compose, env)
		effect = Host.HapticEffect "PressClick" { Type = Enum.HapticEffectType.UIClick }
		local Haptic =
			t.Facet.controls(env.runtime, { viewport = env.viewport, theme = env.theme, pressHaptic = effect })
		built = t.scenario("sensory_feedback").build(t.context(UI, Host, Compose, env))
		return Host.Frame "Holder" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			effect,
			Haptic.VStack "Plain" {
				Position = UDim2.fromOffset(600, 40),
				Haptic.Button "Saves" { label = "Save", haptic = true },
				Haptic.Button "Quiet" { label = "Quiet" },
			},
			Host.Frame "Demo" { Size = UDim2.new(0, 560, 1, 0), BackgroundTransparency = 1, built.screen() },
		}
	end, { frames = 20 })
	local saves, quiet = t.find(stage, "Saves"), t.find(stage, "Quiet")
	t.check(
		"a haptic Button carries the application press effect",
		saves and saves.PressHapticEffect == effect,
		saves and saves.PressHapticEffect
	)
	t.check(
		"a Button without haptic carries none",
		quiet and quiet.PressHapticEffect == nil,
		quiet and quiet.PressHapticEffect
	)
	local press = t.find(stage, "Press")
	t.check(
		"the demo's press button carries its native PressHapticEffect",
		press and press.PressHapticEffect == built.effects.press
	)
	if press then
		io.click(centre(press))
		t.settle(6)
	end
	local history = built.steps.readHistory()
	t.note("history after a real press", history)
	t.check(
		"a real mouse press requests press feedback",
		#history > 0 and string.find(history[1], "press", 1, true) ~= nil,
		history
	)
	t.note("vibration support", {
		gamepad = pcall(function()
			return game:GetService("HapticService"):IsVibrationSupported(Enum.UserInputType.Gamepad1)
		end),
	})
end)

add("presence-retires-until-exit", { "apps-260" }, function(t)
	local io = device(t)
	local Compose = t.Facet.Compose
	local value: any = { built = 0, cleaned = 0 }
	local stage = t.mount(function(UI, Host)
		value.shown = Compose.cell(true)
		value.done = Compose.cell(false)
		return Host.Frame "Holder" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			UI.Button "Toggle" {
				label = "Toggle",
				onActivate = function()
					value.shown:set(not value.shown:peek())
				end,
			},
			Host.Frame "Region" {
				Position = UDim2.fromOffset(0, 80),
				Size = UDim2.fromOffset(200, 100),
				BackgroundTransparency = 1,
				Compose.presence(value.shown, function(phase)
					value.built += 1
					value.phase = phase
					Compose.cleanup(function()
						value.cleaned += 1
					end)
					return Host.Frame "Panel" { Size = UDim2.fromOffset(120, 40) }
				end, {
					exit = function()
						value.done:set(false)
						return { completed = value.done }
					end,
				}),
			},
		}
	end, { frames = 12 })
	local toggle = t.find(stage, "Toggle")
	local first = t.find(stage, "Panel")
	t.check("the region shows its panel once", first ~= nil and value.built == 1, value.built)
	io.click(centre(toggle))
	t.settle(6)
	t.check(
		"hiding retires the panel instead of disposing it",
		t.find(stage, "Panel") == first and value.cleaned == 0,
		value.cleaned
	)
	t.check("the retired panel knows it is exiting", value.phase.exiting:peek() == true)
	io.click(centre(toggle))
	t.settle(6)
	t.check("re-entry mid-exit reuses the same panel instance", t.find(stage, "Panel") == first, t.find(stage, "Panel"))
	t.check("and does not build it again", value.built == 1, value.built)
	t.check("the panel is no longer exiting", value.phase.exiting:peek() == false)
	io.click(centre(toggle))
	t.settle(4)
	value.done:set(true)
	t.settle(4)
	t.check(
		"the exit completing disposes it exactly once",
		value.cleaned == 1 and t.find(stage, "Panel") == nil,
		value.cleaned
	)
	value.done:set(false)
	value.done:set(true)
	t.settle(2)
	t.check("a late completion disposes nothing twice", value.cleaned == 1, value.cleaned)
	local baseline = #stage:GetDescendants()
	for _ = 1, 20 do
		io.click(centre(toggle))
		t.settle(2)
		io.click(centre(toggle))
		t.settle(2)
		value.done:set(true)
		t.settle(1)
	end
	t.settle(4)
	t.note(
		"churn",
		{ built = value.built, cleaned = value.cleaned, descendants = #stage:GetDescendants(), baseline = baseline }
	)
	t.check(
		"churn returns the region to its baseline",
		#stage:GetDescendants() == baseline + (if value.shown:peek() then 1 else 0),
		{ #stage:GetDescendants(), baseline }
	)
	t.check(
		"every built panel but the showing one was disposed once",
		value.cleaned == value.built - (if value.shown:peek() then 1 else 0),
		{ value.built, value.cleaned }
	)
end)

add("stack-pop-retires-until-motion-ends", { "apps-260" }, function(t)
	local io = device(t)
	local value: any = {}
	local stage = t.mount(function(UI, _, Compose)
		value.path = Compose.cell({})
		return UI.NavigationStack "Journey" {
			path = value.path,
			root = {
				title = "Plan",
				content = function()
					return UI.Button "Next" {
						label = "Next",
						onActivate = function()
							value.path:set({ { id = "detail", value = 1 } })
						end,
					}
				end,
			},
			destinations = {
				detail = {
					title = "Detail",
					content = function()
						return UI.Button "Inner" { label = "Inner" }
					end,
				},
			},
		}
	end, { size = Vector2.new(900, 600), frames = 20, reducedMotion = false })
	local gui = stage:FindFirstAncestorWhichIsA("LayerCollector")
	io.click(centre(visibleNamed(t, gui, "Next")))
	t.settle(60)
	local inner = visibleNamed(t, gui, "Inner")
	t.check("the destination is pushed", inner ~= nil and #value.path:peek() == 1)
	value.path:set({})
	t.settle(2)
	t.check("right after the pop the page is still present while it leaves", inner and inner.Parent ~= nil)
	t.check(
		"the leaving page cannot hold the selection",
		inner
			and (
				not inner.Interactable
				or not inner.Selectable
				or not t.visible(inner)
				or GuiService.SelectedObject ~= inner
			)
	)
	t.settle(90)
	t.check("the popped page is gone once its motion ends", inner == nil or inner.Parent == nil)
	local baseline = #gui:GetDescendants()
	for _ = 1, 10 do
		value.path:set({ { id = "detail", value = 1 } })
		t.settle(3)
		value.path:set({})
		t.settle(3)
	end
	t.settle(120)
	t.note("churn", { baseline = baseline, now = #gui:GetDescendants() })
	t.check(
		"ten rapid push-pop cycles return to the baseline tree",
		#gui:GetDescendants() == baseline,
		{ baseline, #gui:GetDescendants() }
	)
end)

local function hintProbe(t: any): any
	local value: any = {}
	value.stage = t.mount(function(UI, Host)
		value.action = Host.InputAction "Go" {
			Type = Enum.InputActionType.Bool,
			Host.InputBinding({ KeyCode = Enum.KeyCode.K, DisplayName = "K" }),
			Host.InputBinding({ KeyCode = Enum.KeyCode.ButtonX }),
		}
		value.shifted = Host.InputAction "Shifted" {
			Type = Enum.InputActionType.Bool,
			Host.InputBinding({ KeyCode = Enum.KeyCode.J, PrimaryModifier = Enum.KeyCode.LeftShift }),
			Host.InputBinding({ KeyCode = Enum.KeyCode.J, PrimaryModifier = Enum.KeyCode.RightShift }),
		}
		return Host.Frame "Holder" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Host.InputContext "Hints" { value.action, value.shifted },
			UI.VStack "Column" {
				UI.ShortcutHint "Hint" { action = value.action },
				UI.ShortcutHint "ShiftHint" { action = value.shifted },
			},
		}
	end, { frames = 16 })
	return value
end

local function hintText(root: Instance?): string
	local out = {}
	if root then
		for _, node in root:GetDescendants() do
			if node:IsA("TextLabel") and node.ContentText ~= "" then
				table.insert(out, node.ContentText)
			elseif node:IsA("ImageLabel") and node.Image ~= "" then
				table.insert(out, "image")
			end
		end
	end
	return table.concat(out, " ")
end

local function readHints(t: any, value: any, where: string, key: string)
	t.settle(10)
	local preferred = value.action.PreferredBinding
	t.note(`{where} preferred`, preferred and preferred.KeyCode)
	t.check(
		`{where}: the preferred binding is {key}`,
		preferred ~= nil and preferred.KeyCode.Name == key,
		preferred and preferred.KeyCode
	)
	local hint = t.find(value.stage, "Hint")
	t.note(`{where} hint`, hintText(hint))
	t.check(
		`{where}: the hint draws the preferred binding`,
		hint ~= nil and hint:FindFirstChild("PreferredBinding", true) ~= nil
	)
end

add("hint-follows-keyboard", { "inputs-98", "inputs-165" }, function(t)
	local io = device(t)
	local value = hintProbe(t)
	io.key(Enum.KeyCode.LeftShift)
	readHints(t, value, "keyboard and mouse", "K")
	local shifted = value.shifted.PreferredBinding
	t.check(
		"a shifted chord's preferred binding is one of its Shift siblings",
		shifted ~= nil
			and shifted.KeyCode == Enum.KeyCode.J
			and (
				shifted.PrimaryModifier == Enum.KeyCode.LeftShift
				or shifted.PrimaryModifier == Enum.KeyCode.RightShift
			),
		shifted and shifted.PrimaryModifier
	)
	local shiftHint = t.find(value.stage, "ShiftHint")
	t.note("shift hint", hintText(shiftHint))
	t.check(
		"the shifted hint names Shift",
		string.find(hintText(shiftHint), "Shift", 1, true) ~= nil,
		hintText(shiftHint)
	)
end)

add("pad-hint-follows-gamepad", { "inputs-98", "inputs-165" }, function(t)
	local io = device(t)
	local value = hintProbe(t)
	io.warm()
	readHints(t, value, "gamepad", "ButtonX")
end)

add("touch-hint-with-no-touch-binding", { "inputs-98" }, function(t)
	touch(t)
	local value = hintProbe(t)
	t.settle(10)
	local preferred = value.action.PreferredBinding
	t.note("touch preferred", preferred and preferred.KeyCode)
	local hint = t.find(value.stage, "Hint")
	t.check("the hint stays drawable on a phone", hint ~= nil)
	t.note("touch hint", hintText(hint))
end)

add("split-long-press-vs-tap", { "inputs-211" }, function(t)
	touch(t)
	local io = device(t)
	local value: any = { primary = 0, alternative = 0 }
	local stage = t.mount(function(UI, Host)
		return Host.Frame "Holder" {
			Position = UDim2.fromOffset(40, 240),
			Size = UDim2.fromOffset(200, 60),
			BackgroundTransparency = 1,
			UI.SplitButton "Run" {
				Size = UDim2.fromOffset(148, 44),
				AutomaticSize = Enum.AutomaticSize.None,
				label = "Run",
				onActivate = function()
					value.primary += 1
				end,
				items = {
					{
						id = "Alternate",
						label = "Alternate",
						onSelect = function()
							value.alternative += 1
						end,
					},
				},
			},
		}
	end, { frames = 16 })
	local primary = t.find(stage, "Primary")
	t.check("the split primary mounts", primary ~= nil)
	if not primary then
		return
	end
	io.click(centre(primary))
	t.settle(10)
	t.check("a touch tap runs the primary once", value.primary == 1, value.primary)
	local gui = stage:FindFirstAncestorWhichIsA("LayerCollector")
	local presses = {}
	local watch = primary.TouchLongPress:Connect(function(_, state)
		table.insert(presses, state.Name)
	end)
	io.down(centre(primary))
	t.settle(90)
	io.up(centre(primary))
	t.settle(30)
	watch:Disconnect()
	t.note("long press states", presses)
	t.check("the engine reports a touch long press", table.find(presses, "Begin") ~= nil, presses)
	t.check("the long press opens the alternatives", visibleNamed(t, gui, "Alternate") ~= nil)
	t.check("the long press does not run the primary", value.primary == 1, value.primary)
	local alternate = visibleNamed(t, gui, "Alternate")
	if alternate then
		io.click(centre(alternate))
		t.settle(20)
		t.check("tapping the alternative runs it once", value.alternative == 1, value.alternative)
	end
end)

add("pinch-is-not-a-pan", { "inputs-211" }, function(t)
	local io = device(t)
	local value = sortable(t, 30)
	if not value.body then
		t.check("the list mounts", false)
		return
	end
	local at = centre(value.body)
	local before = value.body.CanvasPosition.Y
	local ok = pcall(function()
		io.pinch(at, 0.5)
		io.pinch(at, -0.5)
	end)
	t.settle(20)
	t.check("a trackpad pinch can be sent", ok)
	t.note("canvas after a trackpad pinch", { before, value.body.CanvasPosition.Y })
	value.body.CanvasPosition = Vector2.new(0, 0)
	t.settle(6)
	before = 0
	t.check("nor reorder", #value.reorders == 0)
	io.wheel(at, -3)
	t.settle(10)
	t.check("the wheel still scrolls it afterwards", value.body.CanvasPosition.Y > before, value.body.CanvasPosition.Y)
end)

local function multiline(t: any, touchDevice: boolean?): any
	if touchDevice then
		touch(t)
	end
	local value: any = { commits = 0 }
	value.io = device(t)
	value.stage = t.mount(function(UI, Host, Compose)
		value.text = Compose.cell("")
		return Host.Frame "Holder" {
			Position = UDim2.fromOffset(20, 200),
			Size = UDim2.fromOffset(300, 200),
			BackgroundTransparency = 1,
			UI.VStack "Column" {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				UI.TextInput "Notes" {
					value = value.text,
					onChange = function(text)
						value.text:set(text)
					end,
					onCommit = function()
						value.commits += 1
					end,
					multiline = true,
					visibleLines = 4,
				},
				UI.Text "Below" { text = "Below" },
			},
		}
	end, { frames = 16 })
	value.field = textBox(t.find(value.stage, "Notes"))
	value.scroller = value.field and value.field:FindFirstAncestor("Viewport")
	value.root = t.find(value.stage, "Notes")
	return value
end

add("multiline-editing-scroll-and-reveal", { "inputs-122", "inputs-124" }, function(t)
	local value = multiline(t)
	local field, io = value.field, value.io
	t.check("the multiline TextBox mounts", field ~= nil and field.MultiLine)
	if not field then
		return
	end
	t.note(
		"structure",
		{ root = value.root and value.root.ClassName, scroller = value.scroller and value.scroller:GetFullName() }
	)
	t.check("the editor sits in a native scrolling viewport", value.scroller ~= nil)
	t.check(
		"the field frame stays outside the scrolling viewport",
		value.scroller ~= nil and not value.root:IsDescendantOf(value.scroller)
	)
	io.click(centre(field))
	t.check("a click starts editing", field:IsFocused())
	io.text("one")
	io.key(Enum.KeyCode.Return)
	io.text("two")
	t.settle(4)
	t.check(
		"Return inserts a newline and keeps editing",
		field:IsFocused() and value.text:peek() == "one\ntwo",
		value.text:peek()
	)
	t.check("Return does not commit a multiline field", value.commits == 0, value.commits)
	for index = 3, 14 do
		io.key(Enum.KeyCode.Return)
		io.text("line " .. index)
	end
	t.settle(10)
	local scroller = value.scroller
	if scroller then
		t.note("scroll", {
			window = scroller.AbsoluteWindowSize,
			canvas = scroller.AbsoluteCanvasSize,
			position = scroller.CanvasPosition,
		})
		t.check(
			"long text grows the canvas past the viewport",
			scroller.AbsoluteCanvasSize.Y > scroller.AbsoluteWindowSize.Y,
			{ scroller.AbsoluteCanvasSize, scroller.AbsoluteWindowSize }
		)
		t.check("typing at the end reveals the caret line", scroller.CanvasPosition.Y > 0, scroller.CanvasPosition)
		local bottom = field.AbsolutePosition.Y + field.AbsoluteSize.Y
		local windowBottom = scroller.AbsolutePosition.Y + scroller.AbsoluteWindowSize.Y
		t.check(
			"the last line is inside the viewport",
			bottom <= windowBottom + field.LineHeight * field.TextSize + 2,
			{ bottom, windowBottom }
		)
		field.CursorPosition = 1
		io.text("X")
		t.settle(10)
		t.check(
			"typing at the start scrolls back to reveal the first line",
			scroller.CanvasPosition.Y < 1,
			scroller.CanvasPosition
		)
	end
	t.check(
		"the frame keeps the Below label in place outside the editor",
		t.find(value.stage, "Below").AbsolutePosition.Y
			>= value.root.AbsolutePosition.Y + value.root.AbsoluteSize.Y - 0.5
	)
	field:ReleaseFocus()
	t.settle(4)
	t.check("focus loss commits once", value.commits == 1, value.commits)
	t.check("the newlines are kept", select(2, string.gsub(value.text:peek(), "\n", "")) >= 13, value.text:peek())
end)

add("multiline-grows-with-hard-breaks", { "inputs-122" }, function(t)
	local io = device(t)
	local value: any = { commits = 0 }
	local stage = t.mount(function(UI, Host, Compose)
		value.text = Compose.cell("")
		return Host.Frame "Holder" {
			Position = UDim2.fromOffset(20, 200),
			Size = UDim2.fromOffset(300, 400),
			BackgroundTransparency = 1,
			Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder }),
			UI.TextInput "Notes" {
				value = value.text,
				onChange = function(text)
					value.text:set(text)
				end,
				multiline = true,
				LayoutOrder = 1,
			},
			UI.Text "Below" { text = "Below", LayoutOrder = 2 },
		}
	end, { frames = 16 })
	local field = textBox(t.find(stage, "Notes"))
	if not field then
		t.check("the field mounts", false)
		return
	end
	local start = field.AbsoluteSize.Y
	io.click(centre(field))
	t.check("a click starts editing", field:IsFocused())
	for index = 1, 16 do
		io.text("row " .. index)
		io.key(Enum.KeyCode.Return)
	end
	t.settle(10)
	t.note("heights", { start = start, now = field.AbsoluteSize.Y, bounds = field.TextBounds })
	t.check("hard breaks grow the editor", field.AbsoluteSize.Y > start, { start, field.AbsoluteSize.Y })
	t.check(
		"the editor holds every line including the final empty one",
		field.AbsoluteSize.Y >= field.TextBounds.Y,
		{ field.AbsoluteSize.Y, field.TextBounds.Y }
	)
	local measure = field:FindFirstChild("Measure")
	t.check(
		"the unclamped measure is an invisible label",
		measure ~= nil and measure.Visible == false,
		measure and measure.Visible
	)
	local below = t.find(stage, "Below")
	t.check(
		"the label below moves down with the editor",
		below.AbsolutePosition.Y >= field.AbsolutePosition.Y + field.AbsoluteSize.Y - 0.5
	)
	field:ReleaseFocus()
end)

return cases
