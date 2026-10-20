--!strict
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type Compose = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Runtime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type Types = typeof(require("@repo/tools/typecheck/aliases").RobloxTypes)
type Placement = typeof(require("@repo/tools/typecheck/aliases").SpatialPlacement)
type DropInfo = typeof(require("@repo/tools/typecheck/aliases").DropInfo)
type Phase = typeof(require("@repo/tools/typecheck/aliases").TransitionContext)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type Live = {
	mount: (
		(Controls, Host, Compose, { runtime: Runtime, types: Types }) -> Instance,
		{ size: Vector2, motionLevel: string, frames: number }
	) -> GuiObject,
	check: (string, boolean, unknown?) -> (),
	note: (string, unknown) -> (),
	settle: (number) -> (),
	find: (Instance, string) -> GuiObject,
	device: ({ device: string, orientation: Enum.ScreenOrientation }) -> Vector2,
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
				fade = false,
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

local function journal(t: Live, motion: string)
	t.settle(30)
	if Input.TouchEnabled and not Input.MouseEnabled then
		t.device({ device = "iphone_14", orientation = Enum.ScreenOrientation.Portrait })
	end
	local chosen: () -> string
	local presented: () -> boolean
	local open: () -> ()
	local width = math.min(640, workspace.CurrentCamera.ViewportSize.X - 48)
	local stage = t.mount(function(UI: Controls, _Host: Host, C: Compose, env): Instance
		local selected = C.cell("crossing")
		local shown = C.cell(false)
		presented = function(): boolean
			return shown:peek()
		end
		open = function()
			shown:set(true)
		end
		chosen = function(): string
			return selected:peek()
		end
		local build = (require :: (Instance) -> typeof(require("../../../../examples/facet-lab/src/journal_demo")))(
			game:GetService("ReplicatedStorage"):WaitForChild("Lab"):WaitForChild("journal_demo")
		)
		return UI.Sheet {
			title = "Field journal",
			closeButton = false,
			isPresented = shown,
			placement = "bottom",
			width = "wide",
			detents = { "hug" :: "hug" },
			content = function(): Instance
				return build(UI, env.runtime, C, env.types, selected)
			end,
		}
	end, { size = Vector2.new(width, 520), motionLevel = motion, frames = 30 })
	open()
	t.settle(60)
	local nextPage, previous = t.find(stage, "NextPage"), t.find(stage, "PreviousPage")
	local pad = Input.PreferredInput == Enum.PreferredInput.Gamepad
	local touch = Input.TouchEnabled and not Input.MouseEnabled
	local delivered = {}
	local touchPosition: Vector3? = nil
	local watch = Input.InputBegan:Connect(function(input: InputObject)
		table.insert(delivered, tostring(input.UserInputType.Name) .. ":" .. tostring(input.KeyCode.Name))
		if input.UserInputType == Enum.UserInputType.Touch then
			touchPosition = input.Position
		end
	end)
	local inset = Gui:GetGuiInset()
	if touch then
		local probe = previous.AbsolutePosition + previous.AbsoluteSize / 2 + inset
		virtual:SendMousePosition(probe)
		virtual:SendMouseButton(probe, Enum.UserInputType.MouseButton1, true)
		t.settle(2)
		virtual:SendMouseButton(probe, Enum.UserInputType.MouseButton1, false)
		t.settle(30)
		local seen = assert(touchPosition, "touch calibration did not receive input")
		inset = probe - Vector2.new(seen.X, seen.Y)
	end
	local function activate(button: GuiObject)
		if touch then
			local at = button.AbsolutePosition + button.AbsoluteSize / 2 + inset
			virtual:SendMousePosition(at)
			virtual:SendMouseButton(at, Enum.UserInputType.MouseButton1, true)
			t.settle(2)
			virtual:SendMouseButton(at, Enum.UserInputType.MouseButton1, false)
			t.settle(2)
		else
			Gui.SelectedObject = button
			t.settle(2)
			key(t, if pad then Enum.KeyCode.Nine else Enum.KeyCode.Return)
		end
	end
	local samples = 0
	local narrowed, front, back = false, false, false
	local backPrint = false
	local handoffDelta = 0
	local function boardFor(name: string): GuiObject?
		for _, node in stage:GetDescendants() do
			if node:IsA("GuiObject") and node.Name == "BookSpread" and node:GetAttribute("Spread") == name then
				return node
			end
		end
		return nil
	end
	local monitor = game:GetService("RunService").RenderStepped:Connect(function()
		local board = boardFor("ridge")
		if board then
			local leaf = board:FindFirstChild("TurningLeaf") :: GuiObject?
			if leaf and board.AbsoluteSize.X > 0 then
				samples += 1
				local ratio = leaf.AbsoluteSize.X / board.AbsoluteSize.X
				narrowed = narrowed or (ratio > 0.03 and ratio < 0.45)
				front = front or (leaf:FindFirstChild("LeafFront") :: GuiObject).Visible
				local reverse = leaf:FindFirstChild("LeafBack") :: GuiObject
				back = back or reverse.Visible
				if reverse.Visible and ratio > 0.05 and ratio < 0.35 then
					for _, node in reverse:GetDescendants() do
						if node:IsA("TextLabel") and node.Text == "Trail notes" then
							backPrint = backPrint
								or (
									node.AbsolutePosition.X >= leaf.AbsolutePosition.X
									and node.AbsolutePosition.X < leaf.AbsolutePosition.X + leaf.AbsoluteSize.X - 10
								)
						end
					end
				end
				local other = boardFor("crossing")
				local panel = board:FindFirstAncestor("ridge") :: GuiObject
				if other and panel:GetAttribute("FacetPreparing") ~= true then
					local oldPanel = other:FindFirstAncestor("crossing") :: GuiObject
					if panel.Visible and oldPanel.Visible and motion == "normal" then
						local oldLeaf = t.find(other, "TurningLeaf")
						handoffDelta = math.max(handoffDelta, math.abs(leaf.Size.X.Scale - oldLeaf.Size.X.Scale))
					end
				end
			end
		end
	end)
	activate(nextPage)
	t.settle(60)
	t.check("Next turns to the second spread", chosen() == "ridge", delivered)
	if motion == "normal" then
		t.check("a leaf narrows and changes from front to back", narrowed and front and back, samples)
		t.check("the reverse face shows its print before lying flat", backPrint)
		t.check("retained leaves stay synchronized through the handoff", handoffDelta < 0.02, handoffDelta)
	else
		t.check("reduced motion keeps the leaf at rest", not narrowed, samples)
	end
	local ridge = assert(boardFor("ridge"), "ridge book spread is absent")
	local turned = t.find(ridge, "TurningLeaf")
	t.check("the turned leaf rests left of the spine", turned.AnchorPoint.X == 1 and turned.Size.X.Scale == 0.5)
	activate(previous)
	t.settle(60)
	t.check("Previous returns to the first spread", chosen() == "crossing")
	local crossing = assert(boardFor("crossing"), "crossing book spread is absent")
	local returned = t.find(crossing, "TurningLeaf")
	t.check("the returned leaf rests right of the spine", returned.AnchorPoint.X == 0 and returned.Size.X.Scale == 0.5)
	if not pad then
		local gesture = t.find(stage, "JournalGesture")
		local bookWidth = crossing.AbsoluteSize.X
		local function begin(reverse: boolean): Vector2
			local point = gesture.AbsolutePosition
				+ Vector2.new(gesture.AbsoluteSize.X * (if reverse then 0.25 else 0.75), gesture.AbsoluteSize.Y / 2)
				+ inset
			virtual:SendMousePosition(point)
			virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, true)
			t.settle(4)
			return point
		end
		local function move(from: Vector2, fraction: number): Vector2
			local point = from + Vector2.new(bookWidth * fraction, 0)
			virtual:SendMousePosition(point)
			t.settle(6)
			return point
		end
		local function release(point: Vector2)
			virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, false)
			t.settle(60)
		end
		local start = begin(false)
		local point = move(start, -0.2)
		t.settle(60)
		if motion == "normal" then
			local heldBook = assert(boardFor("ridge"))
			local heldLeaf = t.find(heldBook, "TurningLeaf")
			local ratio = heldLeaf.Size.X.Scale
			t.check("a slow drag moves the leaf before release", ratio > 0.1 and ratio < 0.4, ratio)
			local paper = heldLeaf:FindFirstChild("Crossing", true) :: GuiObject
			local restingGradient = paper:FindFirstChildWhichIsA("UIGradient") :: UIGradient
			local strip = t.find(heldBook, "PaperStrip1")
			local movingGradient = strip:FindFirstChildWhichIsA("UIGradient") :: UIGradient?
			t.check(
				"the moving paper keeps the resting page gradient",
				movingGradient ~= nil
					and movingGradient.Color.Keypoints[1].Value == restingGradient.Color.Keypoints[1].Value
			)
			local fold = t.find(heldBook, "Fold")
			t.check(
				"the opaque moving paper covers the stationary pages and spine",
				strip.BackgroundTransparency == 0
					and fold.ZIndex > t.find(heldBook, "LeftPage").ZIndex
					and fold.ZIndex > t.find(heldBook, "RightPage").ZIndex
					and fold.ZIndex > t.find(heldBook, "Spine").ZIndex
			)
			t.settle(20)
			t.check("a held finger stops the leaf", math.abs(heldLeaf.Size.X.Scale - ratio) < 0.001)
		else
			t.check("reduced motion defers navigation until release", chosen() == "crossing")
		end
		release(point)
		t.check("a short held drag cancels to the original spread", chosen() == "crossing")
		start = begin(false)
		for step = 1, 8 do
			point = move(start, -0.075 * step)
		end
		release(point)
		t.check("a swipe commits the next spread", chosen() == "ridge")
		start = begin(true)
		for step = 1, 8 do
			point = move(start, 0.125 * step)
		end
		release(point)
		t.check("a reverse swipe released outside commits the previous spread", chosen() == "crossing")
		local flickSamples: { { x: number, time: number } } = {}
		local detector = gesture:FindFirstChild("PageSwipe") :: UIDragDetector
		local sampling = detector.DragContinue:Connect(function(position: Vector2)
			table.insert(flickSamples, { x = position.X, time = os.clock() })
		end)
		start = begin(false)
		virtual:SendMousePosition(start - Vector2.new(bookWidth * 0.03, 0))
		t.settle(1)
		point = start - Vector2.new(bookWidth * 0.12, 0)
		virtual:SendMousePosition(point)
		t.settle(1)
		release(point)
		sampling:Disconnect()
		t.check("a short fast flick commits the next spread", chosen() == "ridge", flickSamples)
	end
	if touch then
		t.check("the device emulator delivered Touch", touchPosition ~= nil, delivered)
	elseif pad then
		t.check("the controller emulator delivered A", table.find(delivered, "Gamepad1:ButtonA") ~= nil, delivered)
	else
		t.check("keyboard activation reached the journal", table.find(delivered, "Keyboard:Return") ~= nil, delivered)
	end
	monitor:Disconnect()
	watch:Disconnect()
	t.check("the journal has no duplicate header Close", stage:FindFirstChild("Close", true) == nil)
	activate(t.find(stage, "Grabber"))
	t.settle(60)
	t.check("the one-detent grabber closes the journal", not presented())
end

return {
	{
		id = "pad-journal-page-turn",
		run = function(t: Live)
			journal(t, "normal")
		end,
	},
	{
		id = "journal-page-turn",
		run = function(t: Live)
			journal(t, "normal")
		end,
	},
	{
		id = "journal-limited-motion",
		run = function(t: Live)
			journal(t, "limited")
		end,
	},
	{
		id = "journal-no-motion",
		run = function(t: Live)
			journal(t, "none")
		end,
	},
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
