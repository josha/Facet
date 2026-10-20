--!strict
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type Compose = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Runtime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type Placement = typeof(require("@repo/tools/typecheck/aliases").SpatialPlacement)
type DropInfo = typeof(require("@repo/tools/typecheck/aliases").DropInfo)
type Phase = typeof(require("@repo/tools/typecheck/aliases").TransitionContext)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type Live = {
	mount: (
		(Controls, Host, Compose, { runtime: Runtime }) -> Instance,
		{ size: Vector2, motionLevel: string, frames: number }
	) -> GuiObject,
	check: (string, boolean, unknown?) -> (),
	note: (string, unknown) -> (),
	settle: (number) -> (),
	find: (Instance, string) -> GuiObject,
}
type Virtual = {
	SendKey: (Virtual, boolean, Enum.KeyCode, boolean?) -> (),
	SendMousePosition: (Virtual, Vector2) -> (),
	SendMouseButton: (Virtual, Vector2, Enum.UserInputType, boolean) -> (),
}
local Input = game:GetService("UserInputService")
local Gui = game:GetService("GuiService")
local virtual = ((Input :: unknown) :: { CreateVirtualInput: (unknown) -> Virtual }):CreateVirtualInput()
local function key(t: Live, code: Enum.KeyCode)
	virtual:SendKey(true, code, false)
	t.settle(3)
	virtual:SendKey(false, code, false)
	t.settle(8)
end

local function inventory(t: Live, width: number)
	local commits = 0
	local stage = t.mount(function(UI: Controls, _Host: Host, C: Compose): Instance
		local item = C.cell({ column = 1, row = 1, width = 2, height = 2 } :: Placement)
		return UI.SpatialGrid "Board" {
			columns = 5,
			rows = 4,
			cellSize = 48,
			gap = 4,
			from = function(use: Use): { Placement }
				return { use(item) }
			end,
			key = function(): string
				return "Pack"
			end,
			placement = function(value: Placement): Placement
				return value
			end,
			footprint = function(): Vector2
				return Vector2.new(2, 2)
			end,
			drag = function()
				return { payload = "Pack", returnTravel = false }
			end,
			drop = {
				travel = false,
				onDrop = function(_payload: unknown, info: DropInfo): boolean
					item:set(assert(info.placement))
					commits += 1
					return true
				end,
			},
			render = function(): GuiObject
				return UI.Button "Pack" { label = "Pack" }
			end,
		}
	end, { size = Vector2.new(width, 360), motionLevel = "normal", frames = 12 })
	local item, origin, destination = t.find(stage, "Pack"), t.find(stage, "Cell1_1"), t.find(stage, "Cell2_2")
	t.check(
		"native grid places a two-cell item at its origin",
		(item.AbsolutePosition - origin.AbsolutePosition).Magnitude < 1
	)
	t.check(
		"native item spans two cells plus their gap",
		math.abs(item.AbsoluteSize.X - (origin.AbsoluteSize.X * 2 + 4)) < 1,
		item.AbsoluteSize
	)
	t.check(
		"cells remain usable",
		destination.AbsoluteSize.X >= 44 and destination.AbsoluteSize.Y >= 44,
		destination.AbsoluteSize
	)
	local touch = Input.TouchEnabled and not Input.MouseEnabled
	local touches = 0
	local delivered: Vector3? = nil
	local watch = Input.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			touches += 1
			delivered = input.Position
		end
	end)
	local inset = Gui:GetGuiInset()
	local function tap(node: GuiObject)
		local at = node.AbsolutePosition + node.AbsoluteSize / 2 + inset
		virtual:SendMousePosition(at)
		virtual:SendMouseButton(at, Enum.UserInputType.MouseButton1, true)
		t.settle(2)
		virtual:SendMouseButton(at, Enum.UserInputType.MouseButton1, false)
		t.settle(8)
	end
	if touch then
		tap(item)
		local at = assert(delivered)
		inset += item.AbsolutePosition + item.AbsoluteSize / 2 - Vector2.new(at.X, at.Y)
		t.note("touch calibration inset", inset)
	else
		if Input.PreferredInput == Enum.PreferredInput.Gamepad then
			key(t, Enum.KeyCode.LeftShift)
		end
		Gui.SelectedObject = item
		t.settle(4)
		key(t, Enum.KeyCode.Return)
	end
	t.check("activation arms without committing", commits == 0 and destination.Selectable, commits)
	if not touch then
		t.check("pickup hands native selection to the source cell", Gui.SelectedObject == origin)
	end
	if touch then
		tap(destination)
	else
		Gui.SelectedObject = destination
		t.settle(4)
		key(t, Enum.KeyCode.Return)
	end
	watch:Disconnect()
	if touch then
		t.check("the engine delivered native touch input", touches >= 2, touches)
	end
	t.check(
		"activation commits the chosen cell",
		commits == 1 and (item.AbsolutePosition - destination.AbsolutePosition).Magnitude < 1,
		{ commits :: unknown, item.AbsolutePosition, destination.AbsolutePosition }
	)
	t.check("commit restores normal targets", item.Selectable and not destination.Selectable)
	if not touch then
		t.check("commit returns native selection to the placed item", Gui.SelectedObject == item)
	end
	if touch then
		return
	end
	Gui.SelectedObject = nil
	local start = item.AbsolutePosition + item.AbsoluteSize / 2
	local finish = origin.AbsolutePosition + item.AbsoluteSize / 2
	virtual:SendMousePosition(start + inset)
	virtual:SendMouseButton(start + inset, Enum.UserInputType.MouseButton1, true)
	t.settle(3)
	for index = 1, 12 do
		virtual:SendMousePosition(start:Lerp(finish, index / 12) + inset)
		t.settle(2)
	end
	virtual:SendMouseButton(finish + inset, Enum.UserInputType.MouseButton1, false)
	t.settle(12)
	t.check(
		"pointer drag preserves the pickup point",
		commits == 2 and (item.AbsolutePosition - origin.AbsolutePosition).Magnitude < 1,
		{ commits :: unknown, item.AbsolutePosition, origin.AbsolutePosition }
	)
end

local function transitions(t: Live, motion: string)
	local select: (string) -> ()
	local calls = 0
	local stage = t.mount(function(UI: Controls, _Host: Host, C: Compose, env): Instance
		local selection = C.cell("a")
		select = function(value: string)
			selection:set(value)
		end
		return UI.TabView {
			selection = selection,
			placement = "topBar",
			transition = {
				seconds = 0.35,
				apply = function(node: GuiObject, phase: Phase)
					calls += 1
					env.runtime.decorate(node, {
						Rotation = function(use: Use): number
							return -8 * (1 - use(phase.progress))
						end,
					})
				end,
			},
			tabs = {
				{
					id = "a",
					content = function(): Instance
						return UI.Button "First" { label = "First" }
					end,
				},
				{
					id = "b",
					content = function(): Instance
						return UI.Button "Second" { label = "Second" }
					end,
				},
			},
		}
	end, { size = Vector2.new(390, 360), motionLevel = motion, frames = 12 })
	local first = t.find(stage, "First")
	select("b")
	t.settle(4)
	local second = t.find(stage, "Second")
	local content = second:FindFirstAncestor("TransitionContent") :: GuiObject
	t.check(
		"custom transform follows the motion policy",
		if motion == "normal" then content.Rotation < 0 else content.Rotation == 0,
		content.Rotation
	)
	select("a")
	t.settle(30)
	t.check("reentry preserves the first page", t.find(stage, "First") == first and calls == 2)
	t.check("the resting page accepts input", (first:FindFirstAncestor("a") :: GuiObject).Interactable)
	t.note("motion", motion)
end

return {
	{
		id = "sheet-custom-open-close",
		run = function(t: Live)
			local stage = t.mount(function(UI: Controls, Host: Host, C: Compose, env): Instance
				local shown = C.cell(false)
				return Host.Frame "JournalDemo" {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					UI.Button "OpenJournal" {
						label = "Open journal",
						onActivate = function()
							shown:set(true)
						end,
					},
					UI.Sheet {
						title = "Field journal",
						isPresented = shown,
						placement = "center",
						transition = {
							motion = "pageTurn",
							apply = function(content: GuiObject, phase: Phase)
								env.runtime.decorate(content, {
									AnchorPoint = Vector2.new(0, 0.5),
									Position = UDim2.fromScale(0, 0.5),
									Size = function(use: Use): UDim2
										return UDim2.fromScale(0.12 + 0.88 * use(phase.progress), 1)
									end,
								})
							end,
						},
						content = function(): Instance
							return UI.Button "CloseJournal" {
								label = "Close journal",
								onActivate = function()
									shown:set(false)
								end,
							}
						end,
					},
				}
			end, { size = Vector2.new(800, 600), motionLevel = "normal", frames = 12 })
			local open = t.find(stage, "OpenJournal")
			local at = open.AbsolutePosition + open.AbsoluteSize / 2 + Gui:GetGuiInset()
			virtual:SendMousePosition(at)
			virtual:SendMouseButton(at, Enum.UserInputType.MouseButton1, true)
			t.settle(2)
			virtual:SendMouseButton(at, Enum.UserInputType.MouseButton1, false)
			t.settle(90)
			local close = stage:FindFirstChild("CloseJournal", true) :: GuiObject?
			local panel = stage:FindFirstChild("SheetTransition", true) :: GuiObject?
			t.check(
				"the custom Sheet opens and accepts input",
				close ~= nil and panel ~= nil and panel.Interactable,
				(stage:FindFirstChild("Sheet", true) :: Instance):GetAttribute("FacetError")
			)
			Gui.SelectedObject = close
			key(t, Enum.KeyCode.Return)
			t.settle(45)
			t.check("the custom Sheet leaves after Close", stage:FindFirstChild("CloseJournal", true) == nil)
		end,
	},
	{
		id = "inventory-desktop",
		run = function(t: Live)
			inventory(t, 800)
		end,
	},
	{
		id = "inventory-phone",
		run = function(t: Live)
			inventory(t, 390)
		end,
	},
	{
		id = "transition-normal",
		run = function(t: Live)
			transitions(t, "normal")
		end,
	},
	{
		id = "transition-limited",
		run = function(t: Live)
			transitions(t, "limited")
		end,
	},
	{
		id = "transition-none",
		run = function(t: Live)
			transitions(t, "none")
		end,
	},
}
