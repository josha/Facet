--!strict
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type Compose = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Live = {
	mount: ((Controls, Host, Compose) -> GuiObject, { size: Vector2, frames: number }) -> Instance,
	find: (Instance, string) -> GuiObject,
	check: (string, boolean, unknown?) -> (),
	note: (string, unknown) -> (),
	settle: (number) -> (),
}
type State = {
	stage: Instance,
	source: GuiObject,
	target: GuiObject,
	scroll: ScrollingFrame,
	commits: number,
	presses: number,
	frames: number,
	maxError: number,
	canvas: Vector2,
}
type Case = {
	id: string,
	contracts: { string },
	setup: (Live) -> State,
	steps: { [string]: (Live, State) -> () },
}
local GuiService = game:GetService("GuiService")
local Input = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local function setup(t: Live): State
	local source: GuiObject?, target: GuiObject?, scroll: ScrollingFrame?
	local value: State
	local at: Vector2?
	local commits, presses = 0, 0
	local stage = t.mount(function(UI: Controls, Host: Host, C: Compose): GuiObject
		local button = UI.Button "Source" {
			label = "Carry A",
			Position = UDim2.fromOffset(20, 20),
			Size = UDim2.fromOffset(80, 64),
			AutomaticSize = Enum.AutomaticSize.None,
			onActivate = function()
				presses += 1
			end,
		}
		local destination = UI.Button "Target" {
			label = "Place here",
			Position = UDim2.fromOffset(240, 180),
			Size = UDim2.fromOffset(80, 64),
			AutomaticSize = Enum.AutomaticSize.None,
		}
		source, target = button, destination
		UI.draggable(button, { payload = "A", returnTravel = true, touchPickup = "immediate", hitArea = button })
		UI.dropTarget(destination, {
			label = "Board slot",
			travel = true,
			onDrop = function()
				commits += 1
				return true
			end,
		})
		C.cleanup(button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				at = Vector2.new(input.Position.X, input.Position.Y)
			end
		end))
		C.cleanup(Input.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				at = Vector2.new(input.Position.X, input.Position.Y)
			elseif input.UserInputType == Enum.UserInputType.MouseMovement then
				at = Vector2.new(input.Position.X, input.Position.Y)
			end
		end))
		C.cleanup(RunService.RenderStepped:Connect(function()
			if not value then
				return
			end
			value.commits, value.presses = commits, presses
			local ghost = value.stage:FindFirstChild("DragGhost", true)
			if ghost and ghost:IsA("GuiObject") and at and value.source:GetAttribute("FacetDragHeld") then
				local contact = ghost.AbsolutePosition + ghost.AnchorPoint * ghost.AbsoluteSize
				value.maxError = math.max(value.maxError, (contact - at).Magnitude)
				value.frames += 1
			end
		end))
		local body = UI.ScrollView "ScrolledParent" {
			Size = UDim2.fromOffset(420, 340),
			CanvasSize = UDim2.fromOffset(420, 720),
			AutomaticCanvasSize = Enum.AutomaticSize.None,
			Host.Frame {
				Size = UDim2.fromOffset(420, 720),
				BackgroundTransparency = 1,
				Host.UIScale { Scale = 0.8 } :: unknown,
				button :: unknown,
				destination :: unknown,
			} :: unknown,
		}
		scroll = body
		return body
	end, { size = Vector2.new(480, 400), frames = 20 })
	value = {
		stage = stage,
		source = assert(source),
		target = assert(target),
		scroll = assert(scroll),
		commits = commits,
		presses = presses,
		frames = 0,
		maxError = 0,
		canvas = assert(scroll).CanvasPosition,
	}
	GuiService.SelectedObject = value.source
	t.note("source contact", value.source.AbsolutePosition + value.source.AbsoluteSize / 2)
	t.note("target contact", value.target.AbsolutePosition + value.target.AbsoluteSize / 2)
	return value
end

local cases: { Case } = {
	{
		id = "pointer-contact-scroll-and-travel",
		contracts = { "UI.draggable", "UI.dropTarget", "UI.ScrollView" },
		setup = setup,
		steps = {
			afterTap = function(t, value)
				t.settle(2)
				t.check("a tap delivers one press", value.presses == 1, value.presses)
			end,
			whileDragging = function(t, value)
				t.check("a preview was sampled on real frames", value.frames >= 10, value.frames)
				t.check("preview contact stays within one pixel", value.maxError <= 1, value.maxError)
				t.check("the parent does not pan under a drag", value.scroll.CanvasPosition == value.canvas)
				t.check("the source stays captured", value.source:GetAttribute("FacetDragHeld") == true)
			end,
			afterDrop = function(t, value)
				t.settle(60)
				t.check("one drop commits after travel", value.commits == 1, value.commits)
				t.check("the source capture ends", value.source:GetAttribute("FacetDragHeld") == nil)
				t.check("travel removes its preview", value.stage:FindFirstChild("DragGhost", true) == nil)
			end,
		},
	},
	{
		id = "keyboard-gamepad-place-and-cancel",
		contracts = { "UI.draggable", "UI.dropTarget" },
		setup = setup,
		steps = {
			afterPickUp = function(t, value)
				t.check("A or Return captures the selected item", value.source:GetAttribute("FacetDragHeld") == true)
				t.check("the source has visible native selection", GuiService.SelectedObject == value.source)
			end,
			afterTarget = function(t, value)
				t.check("native navigation selects the destination", GuiService.SelectedObject == value.target)
			end,
			afterPlace = function(t, value)
				t.settle(60)
				t.check("A or Return places once", value.commits == 1, value.commits)
				GuiService.SelectedObject = value.source
			end,
			afterCancel = function(t, value)
				t.settle(60)
				t.check("B or Escape cancels without a second commit", value.commits == 1, value.commits)
				t.check("cancel clears capture", value.source:GetAttribute("FacetDragHeld") == nil)
			end,
		},
	},
}
return cases
