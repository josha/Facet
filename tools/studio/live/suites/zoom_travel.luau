--!strict
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type DestinationCell = typeof(require("@repo/tools/typecheck/aliases").ZoomDestinationCell)
type Live = {
	mount: ((Controls, Host, ComposeModule) -> Instance, { frames: number }?) -> GuiObject,
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
}
type TravelState = {
	source: Frame,
	target: Frame,
	content: TextButton,
	destination: DestinationCell,
	samples: { Vector2 },
	additions: number,
	removals: number,
}
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local function zoomSetup(t: Live): ZoomState
	local state: ZoomState
	local stage = t.mount(function(UI: Controls, Host: Host, C: ComposeModule): Instance
		local zoom = C.cell(1)
		local tile: TextButton
		local view = UI.ZoomView {
			Name = "LiveZoom",
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
				UI.draggable(tile, { payload = "A", touchPickup = "immediate" :: "immediate", statusLabels = false })
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
	end, { frames = 12 })
	state.view = assert(t.find(stage, "LiveZoom")) :: ScrollingFrame
	state.additions, state.removals = 0, 0
	state.scale, state.pan = state.view:GetAttribute("FacetZoom") :: number, state.view.CanvasPosition
	GuiService.SelectedObject = state.view
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
		}
		local target = Host.Frame {
			Name = "TravelTarget",
			Size = UDim2.fromOffset(60, 60),
			Position = UDim2.fromOffset(300, 260),
			ClipsDescendants = true,
		}
		local destination = C.cell(source :: GuiObject)
		local content: TextButton
		local travel = UI.Travel {
			destination = destination,
			path = "arc" :: "arc",
			content = function(): GuiObject
				content = UI.Button {
					Name = "LiveTravellingTile",
					label = "A",
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
	end, { frames = 12 })
	table.clear(state.samples)
	return state
end

local function afterLanding(t: Live, state: TravelState)
	local carrier = state.content :: GuiObject
	t.check("carrier lands in destination", carrier.Parent == state.destination:peek())
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
local cases: { ZoomCase | TravelCase } = {
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
