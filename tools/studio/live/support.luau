--!strict
type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Built = { read screen: () -> Instance } | (() -> Instance)
local storage = game:GetService("ReplicatedStorage")

local GuiService = game:GetService("GuiService")

local UserInputService = game:GetService("UserInputService")

type Rect = { x: number, y: number, r: number, b: number }

local function selectedName(): string
	local selected = GuiService.SelectedObject
	return if selected then selected.Name else "nil"
end

local function overlap(a: Rect, b: Rect): boolean
	local w = math.min(a.r, b.r) - math.max(a.x, b.x)
	local h = math.min(a.b, b.b) - math.max(a.y, b.y)
	return w > 0.5 and h > 0.5
end

local function gamepadWatch(): () -> { string }
	local seen: { string } = {}
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

local function centre(node: GuiObject): Vector2
	return node.AbsolutePosition + node.AbsoluteSize / 2
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

local Players = game:GetService("Players")

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

local function pointer(t: { settle: (number) -> (), check: (string, boolean) -> (), note: (string, unknown) -> () })
	local virtual = UserInputService:CreateVirtualInput()
	t.check("virtual input is available", virtual ~= nil)
	assert(virtual and virtual:IsA("VirtualInput"))
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
		shield.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
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
	return virtual, inset
end

local function device(t: { settle: (number) -> (), check: (string, boolean) -> (), note: (string, unknown) -> () })
	local virtual, inset = pointer(t)
	local io: { virtual: VirtualInput, inset: Vector2, [string]: unknown } = { virtual = virtual, inset = inset }
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
		shield.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
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
	return io
end

local function layerOf(stage: any): any
	return stage:FindFirstAncestorWhichIsA("LayerCollector")
end

local function grown(t: any, base: any, offset: number): any
	if offset == 0 then
		return base
	end
	local typography = {}
	for _, role in t.Facet.themes.TYPE_ROLES do
		local entry = base.metrics.typography[role]
		if entry then
			typography[role] = { size = entry.size + offset, font = entry.font, lineHeight = entry.lineHeight }
		end
	end
	local package, report = t.Facet.themes.define({
		base = base,
		identity = { id = `{base.identity.id}-plus-{offset}` },
		metrics = { typography = typography },
	})
	assert(package, report and report.errors and report.errors[1] and report.errors[1].message)
	return package
end

local function scenario(t: any, name: string, patch: ((any) -> ())?, size: Vector2?): (any, any)
	local built: Built
	local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule, env)
		local ctx = t.context(UI, Host, Compose, env)
		if patch then
			patch(ctx)
		end
		local current: Built = t.scenario(name).build(ctx)
		built = current
		return if type(current) == "function" then current() else current.screen()
	end, { frames = 20, size = size })
	return stage, built
end

local function example(t: any, name: string, patch: ((any) -> ())?, size: Vector2?): (any, any)
	local built: Built
	local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule, env)
		local ctx = t.context(UI, Host, Compose, env)
		if patch then
			patch(ctx)
		end
		local current: Built = (require :: any)(storage:WaitForChild("FacetExamples"):WaitForChild(name)).build(ctx)
		built = current
		return if type(current) == "function" then current() else current.screen()
	end, { frames = 20, size = size })
	return stage, built
end

local function partOf(root: any, name: string): any
	if root == nil then
		return nil
	end
	return root:FindFirstChild(name) or root:FindFirstChild(name, true)
end

local function found(t: any, label: string, names: { string }, nodes: { [string]: any }): boolean
	local missing = {}
	for _, key in names do
		if nodes[key] == nil then
			table.insert(missing, key)
		end
	end
	t.check(label, #missing == 0, missing)
	return #missing == 0
end

local function sameColor(a: unknown, b: unknown): boolean
	return typeof(a) == "Color3"
		and typeof(b) == "Color3"
		and math.abs(a.R - b.R) <= 2.5 / 255
		and math.abs(a.G - b.G) <= 2.5 / 255
		and math.abs(a.B - b.B) <= 2.5 / 255
end

local function styled(node: any, property: string): any
	local ok, value = pcall(function()
		return node:GetStyled(property)
	end)
	if ok and value ~= nil then
		return value
	end
	return node[property]
end

local function fill(node: any): string
	return `{node:GetStyled("BackgroundColor3")}|{node:GetStyled("BackgroundTransparency")}`
end
export type Case = {
	id: string,
	contracts: { string },
	run: ((any) -> ())?,
	setup: ((any) -> any)?,
	steps: { [string]: (any, any) -> () }?,
	keepGallery: boolean?,
}
local function new(): ({ Case }, (string, { string }, (any) -> ()) -> ())
	local cases: { Case } = {}
	local function add(id: string, contracts: { string }, run: (any) -> ())
		table.insert(cases, { id = id, contracts = contracts, run = run })
	end
	return cases, add
end

local function interactive(cases: { Case })
	local function interactive(
		id: string,
		contracts: { string },
		setup: (any) -> any,
		steps: { [string]: (any, any) -> () }
	)
		table.insert(cases, { id = id, contracts = contracts, setup = setup, steps = steps })
	end
	return interactive
end

local function planned(cases: { Case })
	local function interactive(
		id: string,
		contracts: { string },
		plan: string,
		setup: (any) -> any,
		steps: { [string]: (any, any) -> () }
	)
		table.insert(cases, { id = id, contracts = contracts, plan = plan, setup = setup, steps = steps })
	end
	return interactive
end

return {
	new = new,
	planned = planned,
	interactive = interactive,
	layerOf = layerOf,
	grown = grown,
	scenario = scenario,
	example = example,
	partOf = partOf,
	found = found,
	sameColor = sameColor,
	styled = styled,
	fill = fill,
	pointer = pointer,
	device = device,
	selectedName = selectedName,
	overlap = overlap,
	gamepadWatch = gamepadWatch,
	centre = centre,
	textBox = textBox,
}
