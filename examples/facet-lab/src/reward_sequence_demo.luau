--!strict
type Use = typeof(require("@repo/tools/typecheck/aliases").Use)
type SequenceSpec = typeof(require("@repo/tools/typecheck/aliases").SequenceSpec)
type SequenceStep = typeof(require("@repo/tools/typecheck/aliases").SequenceStep)
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type Compose = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)

return function(UI: Controls, Host: Host, C: Compose, showPulse: boolean?): Frame
	local row = Host.Frame { Name = "RewardCells", Size = UDim2.fromOffset(240, 60), BackgroundTransparency = 1 }
	local tiles: { GuiObject } = {}
	local labels = { C.cell("A"), C.cell("B"), C.cell("C") }
	local score, status = C.cell(0), C.cell("Ready")
	local sweep, pulse = C.cell(0), C.cell(0)
	local total = UI.countUp(score)
	local charge = C.cell(0)
	local shownCharge = UI.follow(charge, "move")
	for index = 1, 3 do
		tiles[index] = UI.Text {
			Name = `RewardTile{index}`,
			text = labels[index],
			Position = UDim2.fromOffset((index - 1) * 80, 0),
			Size = UDim2.fromOffset(60, 60),
			BackgroundTransparency = 0,
			TextXAlignment = Enum.TextXAlignment.Center,
		}
		tiles[index].Parent = row
	end
	local lane = Host.Frame { Size = UDim2.fromOffset(320, 80), BackgroundTransparency = 1 }
	local source = Host.Frame {
		Name = "PointsSource",
		Size = UDim2.fromOffset(60, 30),
		BackgroundTransparency = 1,
		Parent = C.static(lane),
	}
	local finish = Host.Frame {
		Name = "PointsTotal",
		Size = UDim2.fromOffset(60, 30),
		Position = UDim2.fromOffset(240, 0),
		BackgroundTransparency = 1,
		Parent = C.static(lane),
	}
	local origin: GuiObject = source
	local destination = C.cell(origin)
	local travel = UI.Travel {
		destination = destination,
		path = "arc",
		content = function(): GuiObject
			return UI.Text { text = "+24" }
		end,
	}
	travel.Parent = lane
	local tracks: { SequenceStep } = {}
	tracks[1] = {
		duration = "sequence",
		onStart = function()
			status:set("Sweep and flash")
		end,
		sample = function(p: number)
			sweep:set(p)
		end,
	}
	tracks[2] = {
		duration = "travelFade",
		sample = function(p: number)
			pulse:set(p)
		end,
	}
	local sequenceSpec: SequenceSpec = {
		steps = {
			{
				onStart = function()
					labels[1]:set("LOCK")
					status:set("Lock")
					charge:set(0)
				end,
			},
			{
				delay = "travelStagger",
				onStart = function()
					labels[2]:set("LOCK")
				end,
			},
			{
				delay = "travelStagger",
				onStart = function()
					labels[3]:set("LOCK")
				end,
			},
			{ parallel = tracks },
			{
				duration = "travel",
				onStart = function()
					status:set("Travel")
					destination:set(finish)
				end,
			},
			{
				duration = "countUp",
				onStart = function()
					status:set("Count")
					score:set(score:peek() + 24)
				end,
			},
			{
				delay = "travelStagger",
				duration = "glide",
				sample = UI.toward(charge, 1),
				onEnd = function()
					for _, label in labels do
						label:set("NEW")
					end
					status:set("Refilled")
				end,
			},
		},
	}
	local sequence = UI.sequence(sequenceSpec)
	return UI.VStack "RewardSequence" {
		gap = "s",
		UI.HStack {
			UI.Button "RewardPlay" {
				label = "Play reward",
				onActivate = function()
					sequence.play()
				end,
			},
			UI.Button "RewardFinish" {
				label = "Finish",
				onActivate = function()
					sequence.finish()
				end,
			},
			UI.Button "RewardCancel" {
				label = "Cancel",
				onActivate = function()
					sequence.cancel()
					sweep:set(0)
					pulse:set(0)
					charge:set(0)
					status:set("Cancelled")
				end,
			},
		},
		row,
		lane,
		UI.Flash "RowSweep" { target = row, progress = sweep, mode = "sweep" },
		UI.Flash {
			target = tiles[2],
			progress = C.formula(function(use: Use): number
				return if showPulse == false then 0 else use(pulse)
			end),
		},
		UI.Text "RewardTotal" {
			text = C.formula(function(use: Use)
				return `Total: {math.floor(use(total) + 0.5)}`
			end),
		},
		UI.ProgressView "RewardCharge" { value = shownCharge, presentation = "bar" },
		UI.Text "RewardState" { text = status },
	}
end
