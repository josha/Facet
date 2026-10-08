--!strict
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type DraggableSpec = typeof(require("@repo/tools/typecheck/aliases").DraggableSpec)
type DestinationCell = typeof(require("@repo/tools/typecheck/aliases").ZoomDestinationCell)
type Live = {
	mount: ((Controls, Host, ComposeModule) -> Instance, { frames: number, motionLevel: "normal"? }?) -> GuiObject,
	find: (Instance, string) -> GuiObject?,
	check: (string, boolean, unknown?) -> (),
	note: (string, unknown) -> (),
}
type Sample = { scale: number, pan: Vector2, held: boolean }
type ZoomState = {
	view: ScrollingFrame,
	tile: TextButton,
	samples: { Sample },
	additions: number,
	removals: number,
	scale: number,
	pan: Vector2,
	captured: boolean?,
	contactError: number?,
}
type TravelState = {
	source: Frame,
	target: Frame,
	content: GuiObject,
	destination: DestinationCell,
	samples: { Vector2 },
	additions: number,
	removals: number,
}
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local function zoomSetup(t: Live, captureCamera: boolean?): ZoomState
	local state: ZoomState
	local stage = t.mount(function(UI: Controls, Host: Host, C: ComposeModule): Instance
		local zoom = C.cell(1)
		local camera: {
			fit: (() -> boolean)?,
			zoomTo: (({ x: number, y: number, w: number, h: number }) -> boolean)?,
			zoomAt: ((number, Vector2?) -> boolean)?,
		} =
			{}
		local tile: TextButton
		local view = UI.ZoomView {
			Name = "LiveZoom",
			controls = camera,
			Size = UDim2.fromOffset(360, 320),
			contentSize = Vector2.new(900, 900),
			zoom = zoom,
			content = function(): GuiObject
				tile = UI.Button {
					Name = "CapturedTile",
					label = "A",
					Size = UDim2.fromOffset(60, 60),
					Position = UDim2.fromOffset(420, 420),
				}
				UI.draggable(tile, {
					payload = "A",
					touchPickup = "immediate" :: "immediate",
					statusLabels = false,
					onStart = function()
						if captureCamera then
							assert(camera.zoomAt)(2)
						end
					end,
					onEnd = function()
						if captureCamera then
							assert(camera.fit)()
						end
					end,
				})
				return Host.Frame {
					Name = "StableBoard",
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = Color3.fromRGB(45, 70, 90),
					tile :: unknown,
					UI.Text { text = "BOARD", Position = UDim2.fromOffset(20, 20), Size = UDim2.fromOffset(120, 60) } :: unknown,
				}
			end,
		}
		state = { view = view, tile = tile, samples = {}, additions = 0, removals = 0, scale = 1, pan = Vector2.zero }
		local added = view.DescendantAdded:Connect(function()
			state.additions += 1
		end)
		local removed = view.DescendantRemoving:Connect(function()
			state.removals += 1
		end)
		local sample = RunService.PreRender:Connect(function()
			table.insert(state.samples, {
				scale = view:GetAttribute("FacetZoom") :: number,
				pan = view.CanvasPosition,
				held = tile:GetAttribute("FacetDragHeld") == true,
			})
		end)
		C.cleanup(function()
			added:Disconnect()
			removed:Disconnect()
			sample:Disconnect()
		end)
		return view
	end, { frames = 12, motionLevel = "normal" })
	state.view = assert(t.find(stage, "LiveZoom")) :: ScrollingFrame
	state.additions, state.removals = 0, 0
	state.scale, state.pan = state.view:GetAttribute("FacetZoom") :: number, state.view.CanvasPosition
	GuiService.SelectedObject = state.view
	return state
end

local function collectionCameraSetup(t: Live): ZoomState
	local state: ZoomState
	t.mount(function(UI: Controls, Host: Host, C: ComposeModule): Instance
		local camera: {
			zoomTo: (({ x: number, y: number, w: number, h: number }) -> boolean)?,
			fit: (() -> boolean)?,
			zoomAt: ((number, Vector2?) -> boolean)?,
		} =
			{}
		local view = UI.ZoomView {
			Name = "CollectionCamera",
			Size = UDim2.fromOffset(360, 320),
			contentSize = Vector2.new(900, 900),
			controls = camera,
			content = function(): GuiObject
				return Host.Frame { BackgroundColor3 = Color3.fromRGB(45, 70, 90) }
			end,
		}
		local tile: TextButton
		local rack = UI.VirtualGrid {
			Name = "ExternalCameraRack",
			from = { 1 },
			key = function(id: number): number
				return id
			end,
			columns = 1,
			itemSize = 60,
			mode = "all" :: "all",
			Position = UDim2.fromOffset(0, 340),
			Size = UDim2.fromOffset(360, 80),
			drag = function(_items: { number }, _keys: { number }): DraggableSpec
				return {
					payload = "collection tile",
					touchPickup = "immediate",
					statusLabels = false,
					onStart = function()
						state.captured = true
						t.check(
							"external collection receives pickup camera",
							assert(camera.zoomAt)(2, view.AbsolutePosition + view.AbsoluteWindowSize / 2)
						)
						t.check("second capture request is rejected", not assert(camera.fit)())
					end,
					onEnd = function()
						state.captured = false
						t.check("release permits fit", assert(camera.fit)())
					end,
				}
			end,
			render = function(): GuiObject
				tile = UI.Button { Name = "CollectionTile", label = "A", Size = UDim2.fromScale(1, 1) }
				return tile
			end,
		}
		state = { view = view, tile = tile, samples = {}, additions = 0, removals = 0, scale = 1, pan = Vector2.zero }
		local sample = RunService.PreRender:Connect(function()
			local layer = view:FindFirstAncestorWhichIsA("ScreenGui")
			local ghost = if layer then layer:FindFirstChild("DragGhost", true) else nil
			if state.captured and ghost and ghost:IsA("GuiObject") then
				local pointer = game:GetService("UserInputService"):GetMouseLocation() - GuiService:GetGuiInset()
				local contact = ghost.AbsolutePosition + ghost.AbsoluteSize * ghost.AnchorPoint
				state.contactError = math.max(state.contactError or 0, (contact - pointer).Magnitude)
			end
			table.insert(state.samples, {
				scale = view:GetAttribute("FacetZoom") :: number,
				pan = view.CanvasPosition,
				held = state.captured == true,
			})
		end)
		C.cleanup(function()
			sample:Disconnect()
		end)
		return Host.Frame { Size = UDim2.fromScale(1, 1), view :: unknown, rack :: unknown }
	end, { frames = 12, motionLevel = "normal" })
	return state
end

local function afterZoom(t: Live, state: ZoomState)
	local next = state.view:GetAttribute("FacetZoom") :: number
	t.check("zoom changed", math.abs(next - state.scale) > 0.01, next)
	t.check(
		"zoom keeps content instances",
		state.additions == 0 and state.removals == 0,
		{ state.additions, state.removals }
	)
	state.scale, state.pan = next, state.view.CanvasPosition
	t.note("render samples", state.samples)
	table.clear(state.samples)
end

local function afterPan(t: Live, state: ZoomState)
	t.check("pan changed", (state.view.CanvasPosition - state.pan).Magnitude > 1, state.view.CanvasPosition)
	state.pan = state.view.CanvasPosition
end

local function afterCapture(t: Live, state: ZoomState)
	local held: Sample? = nil
	local count = 0
	for _, sample in state.samples do
		if sample.held then
			count += 1
			if held then
				t.check("captured scale stays fixed", sample.scale == held.scale, sample)
				t.check("captured pan stays fixed", (sample.pan - held.pan).Magnitude < 0.01, sample)
			end
			held = sample
		end
	end
	t.check("captured frames observed", count >= 3, count)
	t.note("captured render samples", state.samples)
	table.clear(state.samples)
end

local function travelSetup(t: Live): TravelState
	local state: TravelState
	t.mount(function(UI: Controls, Host: Host, C: ComposeModule): Instance
		local source = Host.Frame {
			Name = "TravelSource",
			Size = UDim2.fromOffset(60, 60),
			Position = UDim2.fromOffset(20, 80),
			ClipsDescendants = true,
			Host.UIPadding { PaddingLeft = UDim.new(0, 12), PaddingTop = UDim.new(0, 1) } :: unknown,
			Host.UIStroke { Thickness = 3 } :: unknown,
			UI.Button { Name = "SlotButton", label = "slot", Size = UDim2.fromScale(1, 1) } :: unknown,
		}
		local target = Host.Frame {
			Name = "TravelTarget",
			Size = UDim2.fromOffset(60, 60),
			Position = UDim2.fromOffset(300, 260),
			ClipsDescendants = true,
		}
		Host.Frame {
			Name = "LandingContentBox",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Parent = C.static(source),
		}
		Host.Frame {
			Name = "LandingContentBox",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Parent = C.static(target),
		}
		local destination = C.cell(source :: GuiObject)
		local content: GuiObject
		local travel = UI.Travel {
			destination = destination,
			path = "arc" :: "arc",
			content = function(): GuiObject
				content = UI.Text {
					Name = "LiveTravellingTile",
					text = "A",
					Size = UDim2.fromScale(1, 1),
					AutomaticSize = Enum.AutomaticSize.None,
				}
				return content
			end,
		}
		state = {
			source = source,
			target = target,
			content = content,
			destination = destination,
			samples = {},
			additions = 0,
			removals = 0,
		}
		local sample = RunService.PreRender:Connect(function()
			if content then
				state.content = content
				table.insert(state.samples, content.AbsolutePosition)
			end
		end)
		C.cleanup(function()
			sample:Disconnect()
		end)
		return Host.Frame {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			source :: unknown,
			target :: unknown,
			travel :: unknown,
			UI.Button {
				Name = "Send",
				label = "Send",
				onActivate = function()
					destination:set(target)
				end,
			} :: unknown,
			UI.Button {
				Name = "Return",
				label = "Return",
				Position = UDim2.fromOffset(100, 0),
				onActivate = function()
					destination:set(source)
				end,
			} :: unknown,
		}
	end, { frames = 12, motionLevel = "normal" })
	table.clear(state.samples)
	return state
end

local function afterLanding(t: Live, state: TravelState)
	local carrier = state.content :: GuiObject
	t.check("carrier lands in destination", carrier.Parent == state.destination:peek())
	t.check(
		"handoff keeps the slot screen rectangle",
		(
			carrier.AbsolutePosition
			- (state.destination:peek():FindFirstChild("LandingContentBox") :: GuiObject).AbsolutePosition
		).Magnitude <= 1
	)
	local paint = state.destination:peek():FindFirstChild("SlotButton") :: GuiObject?
	if paint then
		t.check(
			"landed letter stays above the cell button",
			(carrier:GetStyled("ZIndex") :: number) > (paint:GetStyled("ZIndex") :: number)
		)
	end
	t.check("content remains visible at hand-off", carrier.Visible and state.content.Visible)
	t.check("travel has rendered samples", #state.samples >= 3, #state.samples)
	local maximum = 0
	for index = 2, #state.samples do
		maximum = math.max(maximum, (state.samples[index] - state.samples[index - 1]).Magnitude)
	end
	t.check("no whole-route jump", maximum < 100, maximum)
	t.note("travel render samples", state.samples)
	table.clear(state.samples)
end

type RecycleState = {
	replace: () -> (),
	remove: () -> (),
	destination: DestinationCell,
	targets: { [number]: GuiObject },
	content: GuiObject,
}
local function recycleSetup(t: Live): RecycleState
	local state: RecycleState
	t.mount(function(UI: Controls, Host: Host, C: ComposeModule): Instance
		local rows = C.cell({ 1, 2 })
		local targets: { [number]: GuiObject } = {}
		local park = Host.Frame { Name = "Park", Size = UDim2.fromOffset(60, 60), ClipsDescendants = true }
		local destination = C.cell(park :: GuiObject)
		local grid = UI.VirtualGrid {
			from = rows,
			key = function(value: number): number
				return value
			end,
			columns = 2,
			itemSize = 64,
			mode = "all" :: "all",
			Size = UDim2.fromOffset(240, 100),
			Position = UDim2.fromOffset(160, 160),
			render = function(current): GuiObject
				local slot = UI.Button { Name = `Target{current:peek()}`, label = "Slot", ClipsDescendants = true }
				targets[current:peek()] = slot
				return slot
			end,
		}
		local content: GuiObject
		local travel = UI.Travel {
			destination = destination,
			content = function(): GuiObject
				content = UI.Text { Name = "Tile40", text = "A" }
				return content
			end,
		}
		state = {
			replace = function()
				rows:set({ 3, 4 })
				destination:set(assert(targets[3]))
			end,
			remove = function()
				rows:set({})
			end,
			destination = destination,
			targets = targets,
			content = content,
		}
		return Host.Frame { Size = UDim2.fromScale(1, 1), park :: unknown, grid :: unknown, travel :: unknown }
	end, { frames = 12, motionLevel = "normal" })
	return state
end
local function afterRecycle(t: Live, state: RecycleState)
	t.check("removed destination ends its carrier", state.content.Parent == nil)
	t.note("carrier parent after destination destruction", tostring(state.content.Parent))
end

type ShuffleState = {
	row: Frame,
	nodes: { TextButton },
	cells: { DestinationCell },
	starts: { number },
	frames: number,
	collisions: number,
	maxLift: number,
}
local function shuffleSetup(t: Live): ShuffleState
	local state: ShuffleState
	t.mount(function(UI: Controls, Host: Host, C: ComposeModule): Instance
		local row = Host.Frame {
			Size = UDim2.fromOffset(392, 140),
			Position = UDim2.fromOffset(20, 60),
			BackgroundTransparency = 1,
		}
		state = { row = row, nodes = {}, cells = {}, starts = {}, frames = 0, collisions = 0, maxLift = 1 }
		local slots: { Frame } = {}
		for index = 1, 7 do
			slots[index] = Host.Frame {
				Size = UDim2.fromOffset(44, 44),
				Position = UDim2.fromOffset((index - 1) * 56, 70),
				BackgroundTransparency = 1,
				Parent = C.static(row),
			}
		end
		for index = 1, 7 do
			state.cells[index] = C.cell(slots[index] :: GuiObject)
			local anchor = UI.Travel {
				destination = state.cells[index],
				path = "arc" :: "arc",
				lift = true,
				stagger = index - 1,
				onStarted = function()
					table.insert(state.starts, index)
				end,
				content = function(): GuiObject
					state.nodes[index] = UI.Button { label = tostring(index), AutomaticSize = Enum.AutomaticSize.None }
					return state.nodes[index]
				end,
			}
			anchor.Parent = row
		end
		local offset = 0
		local button = UI.Button {
			Name = "Shuffle",
			label = "Shuffle",
			onActivate = function()
				offset = (offset + 3) % 7
				for index, cell in state.cells do
					cell:set(slots[(index - 1 + offset) % 7 + 1])
				end
			end,
		}
		local sample = RunService.PreRender:Connect(function()
			state.frames += 1
			for index, node in state.nodes do
				local scale = node:FindFirstChild("TravelLift") :: UIScale
				state.maxLift = math.max(state.maxLift, scale.Scale)
				for other = index + 1, 7 do
					local neighbor = state.nodes[other]
					if
						math.abs(node.AbsolutePosition.X - neighbor.AbsolutePosition.X) < 44
						and math.abs(node.AbsolutePosition.Y - neighbor.AbsolutePosition.Y) < 44
						and node.ZIndex == neighbor.ZIndex
					then
						state.collisions += 1
					end
				end
			end
		end)
		C.cleanup(function()
			sample:Disconnect()
		end)
		return Host.Frame { Size = UDim2.fromScale(1, 1), row :: unknown, button :: unknown }
	end, { frames = 12, motionLevel = "normal" })
	return state
end
local function afterShuffle(t: Live, state: ShuffleState)
	t.check("shuffle has real frame samples", state.frames > 12, state.frames)
	t.check("overlapping carriers have different depths", state.collisions == 0, state.collisions)
	t.check("lift scales the native visual", state.maxLift > 1, state.maxLift)
	t.check("all items have started", #state.starts >= 7, state.starts)
	for index, node in state.nodes do
		local slot = state.cells[index]:peek()
		t.check("item lands in its drawn slot", (node.AbsolutePosition - slot.AbsolutePosition).Magnitude <= 1)
		t.check("item keeps its in-place parent", node.Parent == state.row)
		t.check("resting lift resets", (node:FindFirstChild("TravelLift") :: UIScale).Scale == 1)
	end
end

type ShuffleCase = {
	id: string,
	contracts: { string },
	setup: (Live) -> ShuffleState,
	steps: { [string]: (Live, ShuffleState) -> () },
}

type ZoomCase = {
	id: string,
	contracts: { string },
	setup: (Live) -> ZoomState,
	steps: { [string]: (Live, ZoomState) -> () },
}
type TravelCase = {
	id: string,
	contracts: { string },
	setup: (Live) -> TravelState,
	steps: { [string]: (Live, TravelState) -> () },
}
type RecycleCase = {
	id: string,
	contracts: { string },
	setup: (Live) -> RecycleState,
	steps: { [string]: (Live, RecycleState) -> () },
}
local cases: { ZoomCase | TravelCase | ShuffleCase | RecycleCase } = {
	{
		id = "travel-recycled-destination",
		contracts = { "UI.Travel", "UI.VirtualGrid" },
		setup = recycleSetup,
		steps = {
			afterReplace = function(t: Live, state: RecycleState)
				t.check(
					"recycled destination cancels or lands in the new slot",
					state.content.Parent == nil or state.content.Parent == state.targets[3]
				)
			end,
			afterRemove = afterRecycle,
		},
	},
	{
		id = "zoom-collection-capture-camera",
		contracts = { "UI.ZoomView", "UI.VirtualGrid" },
		setup = collectionCameraSetup,
		steps = {
			whileLifted = function(t: Live, state: ZoomState)
				t.check(
					"collection capture reaches zoom level",
					math.abs((state.view:GetAttribute("FacetZoom") :: number) - 2) < 0.001
				)
				t.check("collection stays captured", state.captured == true)
				t.check(
					"collection preview follows the pointer",
					state.contactError ~= nil and state.contactError <= 1,
					state.contactError
				)
				t.note("collection camera samples", state.samples)
			end,
			afterRelease = function(t: Live, state: ZoomState)
				t.check("collection release returns fit", (state.view:GetAttribute("FacetZoom") :: number) < 1)
				t.check("collection capture ends", state.captured == false)
			end,
		},
	},
	{
		id = "zoom-capture-camera",
		contracts = { "UI.ZoomView", "UI.draggable" },
		setup = function(t: Live): ZoomState
			return zoomSetup(t, true)
		end,
		steps = {
			whileLifted = function(t: Live, state: ZoomState)
				t.check(
					"capture camera reaches zoom level",
					math.abs(state.view:GetAttribute("FacetZoom") :: number - 2) < 0.001
				)
				t.check("source stays captured while camera moves", state.tile:GetAttribute("FacetDragHeld") == true)
				t.note("capture-camera render samples", state.samples)
			end,
			afterRelease = function(t: Live, state: ZoomState)
				t.check("release returns to fit", (state.view:GetAttribute("FacetZoom") :: number) < 1)
				t.check("capture ends", state.tile:GetAttribute("FacetDragHeld") ~= true)
			end,
		},
	},
	{
		id = "shuffle-pointer",
		contracts = { "UI.Travel" },
		setup = shuffleSetup,
		steps = { afterShuffle = afterShuffle, afterInterrupt = afterShuffle },
	},
	{
		id = "shuffle-gamepad",
		contracts = { "UI.Travel" },
		setup = shuffleSetup,
		steps = { afterShuffle = afterShuffle, afterInterrupt = afterShuffle },
	},
	{
		id = "zoom-pointer",
		contracts = {},
		setup = zoomSetup,
		steps = {
			afterPinch = afterZoom,
			afterDoubleTap = afterZoom,
			afterWheelZoom = afterZoom,
			afterWheelPan = afterPan,
			afterMousePan = afterPan,
			afterChildDrag = afterCapture,
		},
	},
	{
		id = "zoom-gamepad",
		contracts = {},
		setup = zoomSetup,
		steps = { afterTrigger = afterZoom, afterStick = afterPan, afterFit = afterZoom },
	},
	{
		id = "travel-pointer",
		contracts = {},
		setup = travelSetup,
		steps = { afterSend = afterLanding, afterReverse = afterLanding },
	},
	{
		id = "travel-gamepad",
		contracts = {},
		setup = travelSetup,
		steps = { afterSend = afterLanding, afterReturn = afterLanding },
	},
}

return cases
