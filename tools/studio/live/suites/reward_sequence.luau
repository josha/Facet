--!strict
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type Compose = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Live = {
	mount: ((Controls, Host, Compose) -> Instance, { frames: number, motionLevel: "normal"? }?) -> GuiObject,
	check: (string, boolean, unknown?) -> (),
	note: (string, unknown) -> (),
}
type State = { events: { string }, samples: { number }, display: TextLabel, target: Frame }
local RunService = game:GetService("RunService")
local function setup(t: Live): State
	local state: State
	t.mount(function(UI: Controls, Host: Host, C: Compose): Instance
		local score, flash = C.cell(0), C.cell(0)
		local number = UI.countUp(score)
		local target = Host.Frame { Size = UDim2.fromOffset(240, 60), Position = UDim2.fromOffset(20, 80) }
		local display = UI.Text {
			Name = "LiveTotal",
			text = C.formula(function(use)
				return tostring(math.floor(use(number) + 0.5))
			end),
		}
		state = { events = {}, samples = {}, display = display :: TextLabel, target = target }
		local reward = UI.sequence {
			steps = {
				{
					onStart = function()
						table.insert(state.events, "lock1")
					end,
				},
				{
					delay = "travelStagger",
					onStart = function()
						table.insert(state.events, "lock2")
					end,
				},
				{
					duration = "sequence",
					sample = function(p)
						flash:set(p)
					end,
				},
				{
					duration = "countUp",
					onStart = function()
						score:set(score:peek() + 24)
						table.insert(state.events, "count")
					end,
				},
				{
					delay = "travelStagger",
					onEnd = function()
						table.insert(state.events, "refill")
					end,
				},
			},
		}
		local sample = RunService.PreRender:Connect(function()
			table.insert(state.samples, number:peek())
		end)
		C.cleanup(function()
			sample:Disconnect()
		end)
		return Host.Frame {
			Size = UDim2.fromScale(1, 1),
			target :: unknown,
			display :: unknown,
			UI.Flash { target = target :: GuiObject, progress = flash } :: unknown,
			UI.Button {
				Name = "Play",
				label = "Play reward",
				Position = UDim2.fromOffset(20, 160),
				onActivate = reward.play,
			} :: unknown,
			UI.Button {
				Name = "Finish",
				label = "Finish",
				Position = UDim2.fromOffset(160, 160),
				onActivate = reward.finish,
			} :: unknown,
			UI.Button {
				Name = "Cancel",
				label = "Cancel",
				Position = UDim2.fromOffset(260, 160),
				onActivate = function()
					reward.cancel()
					flash:set(0)
				end,
			} :: unknown,
		}
	end, { frames = 12, motionLevel = "normal" })
	return state
end
local function afterReward(t: Live, state: State)
	t.check("sequence reaches refill", state.events[#state.events] == "refill", state.events)
	t.check("native count-up has intermediate frames", #state.samples > 12, #state.samples)
	local intermediate = false
	for _, number in state.samples do
		intermediate = intermediate or number > 0 and number < 24
	end
	t.check("number interpolation is visible", intermediate)
	t.check(
		"native label reaches total",
		tonumber(state.display.Text) ~= nil and assert(tonumber(state.display.Text)) >= 24,
		state.display.Text
	)
	t.note("native count samples", state.samples)
end
type Case = { id: string, contracts: { string }, setup: (Live) -> State, steps: { [string]: (Live, State) -> () } }
local cases: { Case } = {
	{
		id = "reward-pointer",
		contracts = { "UI.sequence", "UI.countUp", "UI.Flash" },
		setup = setup,
		steps = { afterReward = afterReward, afterFinish = afterReward },
	},
	{
		id = "reward-gamepad",
		contracts = { "UI.sequence", "UI.countUp", "UI.Flash" },
		setup = setup,
		steps = { afterReward = afterReward, afterFinish = afterReward },
	},
}
return cases
