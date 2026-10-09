--!strict
type DraggableSpec = typeof(require("@repo/tools/typecheck/aliases").DraggableSpec)
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type Compose = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Live = {
	mount: (
		(Controls, Host, Compose) -> GuiObject,
		{ size: Vector2, frames: number, motionLevel: "normal" }
	) -> Instance,
	find: (Instance, string) -> GuiObject,
	check: (string, boolean, unknown?) -> (),
	note: (string, unknown) -> (),
	settle: (number) -> (),
}
type Readable<T> = { peek: (Readable<T>) -> T }
type Item = { id: string }
type PreviewSample = { pointer: Vector2, contact: Vector2, rect: { number }, error: number }
type State = {
	stage: Instance,
	source: GuiObject,
	target: GuiObject,
	scroll: ScrollingFrame,
	commits: number,
	presses: number,
	frames: number,
	maxError: number,
	previewSamples: { PreviewSample }?,
	canvas: Vector2,
	secondPosition: Vector2?,
	reflowSamples: { number }?,
	releaseSlots: (() -> ())?,
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

local function preview(stage: Instance): GuiObject?
	local layer = stage:FindFirstAncestorWhichIsA("LayerCollector")
	local ghost = if layer then layer:FindFirstChild("DragGhost", true) else nil
	return if ghost and ghost:IsA("GuiObject") then ghost else nil
end

local function setup(t: Live, collection: boolean?, reserved: boolean?): State
	local source: GuiObject?, target: GuiObject?, scroll: ScrollingFrame?
	local value: State
	local at: Vector2?
	local commits, presses = 0, 0
	local releaseSlots: (() -> ())?
	local removeSource: (() -> ())?
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
		local pickup: GuiObject = button
		if collection then
			local rows = C.cell({ { id = "A" }, { id = "B" } })
			local slots = C.cell({ "A", "B" })
			removeSource = function()
				rows:set({ { id = "B" } })
			end
			releaseSlots = function()
				slots:set({ "B" })
			end
			UI.draggable(destination, { payload = { keys = { "A" } }, touchPickup = "immediate", returnTravel = true })
			pickup = UI.VirtualGrid "SourceRack" {
				from = rows,
				slots = if reserved then slots else nil,
				key = "id",
				mode = "all" :: "all",
				columns = 2,
				itemSize = 64,
				Position = UDim2.fromOffset(20, 20),
				Size = UDim2.fromOffset(160, 88),
				reorderable = true,
				onReorder = function() end,
				drag = function(items: { { id: string } }, _keys: { string }): DraggableSpec
					return { payload = items[1].id, touchPickup = "immediate" :: "immediate", returnTravel = true }
				end,
				drop = if reserved
					then {
						travel = true,
						onDrop = function()
							rows:set({ { id = "A" }, { id = "B" } })
							return true
						end,
					}
					else nil,
				render = function(): GuiObject
					return UI.Button "RackTile" { label = "Carry tile" }
				end,
			}
		else
			UI.draggable(button, { payload = "A", returnTravel = true, touchPickup = "immediate", hitArea = button })
		end
		UI.dropTarget(destination, {
			label = "Board slot",
			travel = true,
			onDrop = function()
				commits += 1
				if reserved and removeSource then
					removeSource()
				end
				return true
			end,
		})
		local sourceInput = button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				at = Vector2.new(input.Position.X, input.Position.Y)
			end
		end)
		local pointerInput = Input.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				at = Vector2.new(input.Position.X, input.Position.Y)
			elseif input.UserInputType == Enum.UserInputType.MouseMovement then
				at = Vector2.new(input.Position.X, input.Position.Y)
			end
		end)
		local pointerEnded = Input.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				at = nil
			end
		end)
		local frames = RunService.RenderStepped:Connect(function()
			if not value then
				return
			end
			value.commits, value.presses = commits, presses
			local ghost = preview(value.stage)
			if
				ghost
				and ghost:IsA("GuiObject")
				and at
				and (value.source:GetAttribute("FacetDragHeld") or value.source:GetAttribute("FacetDragging"))
			then
				local contact = ghost.AbsolutePosition + ghost.AnchorPoint * ghost.AbsoluteSize
				value.maxError = math.max(value.maxError, math.abs(contact.X - at.X), math.abs(contact.Y - at.Y))
				value.frames += 1
				table.insert(assert(value.previewSamples), {
					pointer = at,
					contact = contact,
					rect = {
						ghost.AbsolutePosition.X,
						ghost.AbsolutePosition.Y,
						ghost.AbsoluteSize.X,
						ghost.AbsoluteSize.Y,
					},
					error = math.max(math.abs(contact.X - at.X), math.abs(contact.Y - at.Y)),
				})
			end
		end)
		C.cleanup(function()
			sourceInput:Disconnect()
			pointerInput:Disconnect()
			pointerEnded:Disconnect()
			frames:Disconnect()
		end)
		local body = UI.ScrollView "ScrolledParent" {
			Size = UDim2.fromOffset(420, 340),
			CanvasSize = UDim2.fromOffset(420, 720),
			AutomaticCanvasSize = Enum.AutomaticSize.None,
			Host.Frame {
				Size = UDim2.fromOffset(420, 720),
				BackgroundTransparency = 1,
				Host.UIScale { Scale = 0.8 } :: unknown,
				pickup :: unknown,
				destination :: unknown,
			} :: unknown,
		}
		scroll = body
		return body
	end, { size = Vector2.new(480, 400), frames = 20, motionLevel = "normal" })
	if collection then
		source = assert(stage:FindFirstChild("Reorderable", true)) :: GuiObject
	end
	value = {
		stage = stage,
		source = assert(source),
		target = assert(target),
		scroll = assert(scroll),
		commits = commits,
		presses = presses,
		frames = 0,
		maxError = 0,
		previewSamples = {},
		canvas = assert(scroll).CanvasPosition,
		releaseSlots = releaseSlots,
		secondPosition = if reserved then (t.find(stage, "B")).AbsolutePosition else nil,
	}
	GuiService.SelectedObject = value.source
	t.note("source contact", value.source.AbsolutePosition + value.source.AbsoluteSize / 2)
	t.note("target contact", value.target.AbsolutePosition + value.target.AbsoluteSize / 2)
	return value
end

local cases: { Case } = {
	{
		id = "hover-slot-reflow",
		contracts = { "UI.draggable", "UI.VirtualGrid", "UI.dropTarget" },
		setup = function(t)
			local source: GuiObject?, target: GuiObject?, neighbour: GuiObject?
			local value: State?
			local stage = t.mount(function(UI, Host, C)
				local button = UI.Button "Source" {
					label = "A",
					Position = UDim2.fromOffset(20, 20),
					Size = UDim2.fromOffset(64, 64),
					AutomaticSize = Enum.AutomaticSize.None,
				}
				source = button
				UI.draggable(button, {
					payload = { collection = "source", keys = { "A" } },
					touchPickup = "immediate",
					returnTravel = true,
				})
				local items: { Item } = { { id = "B" }, { id = "C" } }
				local rack = UI.VirtualGrid "TargetRack" {
					from = items,
					key = "id",
					columns = 3,
					itemSize = 64,
					mode = "all" :: "all",
					Position = UDim2.fromOffset(160, 120),
					Size = UDim2.fromOffset(240, 88),
					drop = {
						onDrop = function()
							return true
						end,
					},
					render = function(current: Readable<Item>): GuiObject
						return UI.Button { label = current:peek().id }
					end,
				}
				target = rack
				local connection = RunService.RenderStepped:Connect(function()
					local state = value
					if state and neighbour and state.target:GetAttribute("FacetDropState") == "accepted" then
						table.insert(assert(state.reflowSamples), neighbour.AbsolutePosition.X)
					end
				end)
				C.cleanup(function()
					connection:Disconnect()
				end)
				return Host.Frame { Size = UDim2.fromOffset(440, 320), button :: unknown, rack :: unknown }
			end, { size = Vector2.new(480, 400), frames = 30, motionLevel = "normal" })
			neighbour = t.find(stage, "B")
			value = {
				stage = stage,
				source = assert(source),
				target = assert(target),
				scroll = assert(target) :: ScrollingFrame,
				commits = 0,
				presses = 0,
				frames = 0,
				maxError = 0,
				canvas = Vector2.zero,
				secondPosition = assert(neighbour).AbsolutePosition,
				reflowSamples = {},
			}
			return assert(value)
		end,
		steps = {
			whileHovering = function(t, value)
				t.settle(40)
				local samples = assert(value.reflowSamples)
				local initial = assert(value.secondPosition).X
				local final = t.find(value.stage, "B").AbsolutePosition.X
				local intermediate = false
				for _, x in samples do
					intermediate = intermediate or (x > initial + 1 and x < final - 1)
				end
				t.check("hover opens a slot before release", final > initial + 1)
				t.check("neighbours reflow on real intermediate frames", intermediate, samples)
				t.note("hover reflow frames", samples)
			end,
			afterLeave = function(t, value)
				t.settle(80)
				t.check(
					"leave restores the original slot",
					(t.find(value.stage, "B").AbsolutePosition - assert(value.secondPosition)).Magnitude <= 1
				)
			end,
		},
	},
	{
		id = "reserved-slots-pointer-and-gamepad-recall",
		contracts = { "UI.VirtualGrid", "UI.draggable", "UI.dropTarget" },
		setup = function(t)
			local value = setup(t, true, true)
			local handle = value.source:FindFirstChild("Move") :: GuiObject?
			if handle then
				GuiService.SelectedObject = handle
			end
			return value
		end,
		steps = {
			afterStage = function(t, value)
				t.settle(60)
				local empty = false
				for _, child in value.stage:GetDescendants() do
					if child:GetAttribute("FacetReservedKey") == "A" and child:IsA("GuiObject") then
						empty = child.Visible
					end
				end
				t.check("staging keeps an empty A slot", empty)
				t.check("B keeps its drawn slot", t.find(value.stage, "B").AbsolutePosition == value.secondPosition)
				GuiService.SelectedObject = value.target
			end,
			afterRecall = function(t, value)
				t.settle(60)
				t.check("Recall returns A to its key slot", value.stage:FindFirstChild("A", true) ~= nil)
				t.check(
					"B stays in its original slot",
					t.find(value.stage, "B").AbsolutePosition == value.secondPosition
				)
			end,
			afterRelease = function(t, value)
				assert(value.releaseSlots)()
				t.settle(120)
				t.check("release reflows the rack", t.find(value.stage, "B").AbsolutePosition ~= value.secondPosition)
			end,
		},
	},
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
				t.note("preview render samples", value.previewSamples)
				t.check("a preview was sampled on real frames", value.frames >= 10, value.frames)
				t.check("preview contact stays within one pixel", value.maxError <= 1, value.maxError)
				t.check("the parent does not pan under a drag", value.scroll.CanvasPosition == value.canvas)
				t.check("the source stays captured", value.source:GetAttribute("FacetDragHeld") == true)
			end,
			afterDrop = function(t, value)
				t.settle(60)
				t.check("one drop commits after travel", value.commits == 1, value.commits)
				t.check("the source capture ends", value.source:GetAttribute("FacetDragHeld") == nil)
				t.check("travel removes its preview", preview(value.stage) == nil)
			end,
		},
	},
	{
		id = "collection-immediate-touch-transfer",
		contracts = { "UI.VirtualGrid", "UI.draggable", "UI.dropTarget" },
		setup = function(t)
			return setup(t, true)
		end,
		steps = {
			afterEightPixels = function(t, value)
				t.check("eight pixels captures without long press", value.source:GetAttribute("FacetDragging") == true)
				local cells = value.source:FindFirstChild("Cells") :: GuiObject?
				t.check("the source shows a recess", cells ~= nil and not cells.Visible)
				t.check("the outer parent is locked", not value.scroll.ScrollingEnabled)
			end,
			whileDragging = function(t, value)
				t.check("the collection preview has render samples", value.frames >= 10, value.frames)
				t.check("the collection preview stays within one pixel", value.maxError <= 1, value.maxError)
				t.check("the outer scroll position stays fixed", value.scroll.CanvasPosition == value.canvas)
			end,
			afterDrop = function(t, value)
				t.settle(60)
				t.check("the collection transfer commits once", value.commits == 1, value.commits)
				t.check("the collection capture ends", value.source:GetAttribute("FacetDragging") == false)
				t.check("the outer scroller is restored", value.scroll.ScrollingEnabled)
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
