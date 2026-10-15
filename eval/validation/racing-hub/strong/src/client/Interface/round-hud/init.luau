--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Hub = require(ReplicatedStorage.Shared.Hub)
local Round = require(ReplicatedStorage.Shared.Hub.Round)
local Kit = require(script.Parent.Kit)

export type Context = { player: Player, playerGui: PlayerGui, round: Round.Client, hub: Hub.Client }

local function mount(context: Context)
	local api = context.round
	local state = api.getState()
	local screen = Kit.screen(context.playerGui, "RoundInterface")
	Kit.scale(screen)
	local timer = Kit.label("", Kit.size.heading, Kit.colors.primary, true)
	timer.Size = UDim2.new(1, -16, 0, 0)
	timer.Position = UDim2.fromOffset(8, 8)
	timer.TextXAlignment = Enum.TextXAlignment.Center
	timer.BackgroundColor3 = Kit.colors.panel
	timer.BackgroundTransparency = 0
	timer.Parent = screen
	local standings = Kit.create("ScrollingFrame", {
		Position = UDim2.fromOffset(8, 52),
		Size = UDim2.new(0.46, -8, 0.2, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		BorderSizePixel = 0,
		BackgroundColor3 = Kit.colors.panel,
		ClipsDescendants = true,
		Parent = screen,
	}, {
		Kit.padding(8),
		Kit.corner(12),
		Kit.list(Enum.FillDirection.Vertical, 4),
		Kit.create("UISizeConstraint", { MaxSize = Vector2.new(260, 250) }),
	}) :: ScrollingFrame
	local feed = Kit.label("", Kit.size.small, Kit.colors.text)
	feed.BackgroundColor3 = Kit.colors.panel
	feed.BackgroundTransparency = 0
	feed.Parent = standings
	feed.LayoutOrder = 100
	feed.Position = UDim2.new()
	feed.Size = UDim2.new(1, 0, 0, 0)
	local function layout()
		standings.Size = UDim2.new(if screen.AbsoluteSize.X < 600 then 0.46 else 0.28, -8, 0.2, 0)
	end
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()
	local lines: { string } = {}
	local lastRound = state.round
	local results = Kit.modal(screen, "RaceResults", "Results")
	local resultList = Kit.scroller()
	resultList.Parent = results.body
	Kit.list(Enum.FillDirection.Vertical, 8).Parent = resultList
	local order = Kit.label("", Kit.size.body)
	order.Parent = resultList
	order.LayoutOrder = 1
	local earned = Kit.label("", Kit.size.body, Kit.colors.primary, true)
	earned.Parent = resultList
	earned.LayoutOrder = 2
	local back = Kit.button("Back to hub", "primary")
	back.Parent = resultList
	back.LayoutOrder = 3
	results.onClosed(function()
		if state.phase == "Results" then
			context.hub.returnToHub()
		end
	end)
	back.Activated:Connect(function()
		context.hub.returnToHub()
	end)
	local function renderTimer()
		local left = math.max(0, math.ceil(state.endsAt - api.serverNow()))
		local me: Round.Racer? = nil
		for _, racer in state.racers do
			if racer.name == api.localName then
				me = racer
			end
		end
		timer.Text = ("%s %d:%02d%s"):format(
			state.phase,
			left // 60,
			left % 60,
			if me and state.phase == "Round"
				then (" | Position %d / %d | Lap %d/%d%s"):format(
					me.position,
					#state.racers,
					me.lap,
					me.lapCount,
					if me.eliminated then " | You are out" elseif me.finished then " | Finished" else ""
				)
				else ""
		)
	end
	local function render()
		if state.round ~= lastRound or (state.phase == "Round" and lastRound < 0) then
			table.clear(lines)
		end
		lastRound = if state.phase == "Results" then -1 else state.round
		feed.Text = table.concat(lines, "\n")
		feed.Visible = state.phase == "Round" and #lines > 0
		standings.Visible = state.phase == "Round"
		for _, child in standings:GetChildren() do
			if child:IsA("TextLabel") and child ~= feed then
				child:Destroy()
			end
		end
		local finish: { string } = {}
		for _, racer in state.racers do
			local text = ("%d. %s%s%s"):format(
				racer.position,
				racer.name,
				if racer.name == api.localName then " (You)" else "",
				if racer.eliminated then " OUT" elseif racer.finished then " Finished" else ""
			)
			local row = Kit.label(
				text,
				Kit.size.small,
				if racer.name == api.localName then Kit.colors.primary else Kit.colors.text
			)
			row.LayoutOrder = racer.position
			row.Parent = standings
			table.insert(
				finish,
				("%d. %s%s%s"):format(
					racer.position,
					racer.name,
					if racer.name == api.localName then " (You)" else "",
					if racer.finished then " Finished" elseif racer.eliminated then " OUT" else " DNF"
				)
			)
		end
		order.Text = "Finish order\n" .. table.concat(finish, "\n")
		local rewards = state.rewards
		earned.Text = ("You earned %d Coins / 5 Gems / 120 XP"):format(
			if rewards then rewards[api.localName] or 0 else 0
		)
		results.setOpen(state.phase == "Results", back)
		renderTimer()
	end
	api.onStateChanged(function(next: Round.State)
		state = next
		render()
	end)
	api.onEvent(function(event: Round.Event)
		table.insert(lines, ("%s knocked out: last on %s"):format(event.victim, event.by))
		while #lines > 4 do
			table.remove(lines, 1)
		end
		feed.Text = table.concat(lines, "\n")
		feed.Visible = true
	end)
	task.spawn(function()
		while screen.Parent do
			renderTimer()
			task.wait(0.2)
		end
	end)
	render()
end

return { mount = mount }
