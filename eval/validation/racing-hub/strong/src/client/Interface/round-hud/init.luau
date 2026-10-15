--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hub = require(ReplicatedStorage.Shared.Hub)
local Round = require(ReplicatedStorage.Shared.Hub.Round)
local Kit = require(script.Parent.Kit)

export type Context = {
	player: Player,
	playerGui: PlayerGui,
	round: Round.Client,
	hub: Hub.Client,
}

local FEED_LINES = 4
local TEAM_COLORS: { [string]: Color3 } = {
	Red = Color3.fromRGB(230, 90, 90),
	Blue = Color3.fromRGB(100, 160, 240),
}

local function mount(context: Context)
	local api = context.round
	local state = api.getState()
	local lines: { string } = {}
	local lastRound = state.round
	local lastPhase = state.phase

	local screen = Kit.screen(context.playerGui, "RoundInterface")
	Kit.scale(screen)

	local timer = Kit.label("", Kit.size.heading, Kit.colors.text, true)
	timer.Name = "Timer"
	timer.AutomaticSize = Enum.AutomaticSize.XY
	timer.Size = UDim2.new()
	timer.AnchorPoint = Vector2.new(0.5, 0)
	timer.Position = UDim2.new(0.5, 0, 0, Kit.space.small)
	timer.TextWrapped = false
	timer.BackgroundTransparency = 0.1
	timer.BackgroundColor3 = Kit.colors.panel
	Kit.corner(18).Parent = timer
	Kit.create("UIPadding", {
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		Parent = timer,
	})
	timer.Parent = screen

	local out = Kit.label("You are out", Kit.size.heading, Kit.colors.dangerText, true)
	out.Name = "Out"
	out.AutomaticSize = Enum.AutomaticSize.XY
	out.Size = UDim2.new()
	out.AnchorPoint = Vector2.new(0.5, 0)
	out.Position = UDim2.new(0.5, 0, 0, 64)
	out.TextWrapped = false
	out.BackgroundTransparency = 0
	out.BackgroundColor3 = Kit.colors.danger
	out.Visible = false
	Kit.corner(12).Parent = out
	Kit.padding(Kit.space.small).Parent = out
	out.Parent = screen

	local function teamPanel(team: Round.Team, right: boolean): (ScrollingFrame, TextLabel, Frame)
		local panel = Kit.create("ScrollingFrame", {
			Name = team .. "Team",
			AnchorPoint = Vector2.new(if right then 1 else 0, 0),
			Position = if right
				then UDim2.new(1, -Kit.space.small, 0, Kit.space.small)
				else UDim2.new(0, Kit.space.small, 0, Kit.space.small),
			Size = UDim2.new(0.22, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 4,
			VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
			ClipsDescendants = true,
			BorderSizePixel = 0,
			BackgroundColor3 = Kit.colors.panel,
			BackgroundTransparency = 0.1,
			Parent = screen,
		}, {
			Kit.corner(12),
			Kit.padding(Kit.space.small),
			Kit.create("UISizeConstraint", { MinSize = Vector2.new(120, 0), MaxSize = Vector2.new(240, math.huge) }),
			Kit.list(Enum.FillDirection.Vertical, 2),
		}) :: ScrollingFrame
		local header = Kit.label(team, Kit.size.body, TEAM_COLORS[team], true)
		header.Name = "Header"
		header.LayoutOrder = 0
		header.Parent = panel
		local roster = Kit.create("Frame", {
			Name = "Roster",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			Parent = panel,
		}, { Kit.list(Enum.FillDirection.Vertical, 2) }) :: Frame
		return panel, header, roster
	end

	local redPanel, redHeader, redRoster = teamPanel("Red", false)
	local bluePanel, blueHeader, blueRoster = teamPanel("Blue", true)
	local hubScreen = Kit.screen(context.playerGui, "Hub")
	local stats = hubScreen:WaitForChild("PlayerStats") :: Frame
	local commands = hubScreen:WaitForChild("HubCommands") :: Frame
	local redLimit = redPanel:FindFirstChildOfClass("UISizeConstraint") :: UISizeConstraint
	local blueLimit = bluePanel:FindFirstChildOfClass("UISizeConstraint") :: UISizeConstraint
	stats.Size = UDim2.new(1, 0, 0, 0)
	stats.LayoutOrder = 2
	stats.Parent = redPanel
	local function layout()
		local compact = screen.AbsoluteSize.X < 600
		redPanel.Position = UDim2.new(0, 8, 0, if compact then 48 else 8)
		bluePanel.Position = UDim2.new(1, -8, 0, if compact then 48 else 8)
		redPanel.Size = UDim2.new(if compact then 0.46 else 0.22, 0, 0, 0)
		bluePanel.Size = redPanel.Size
		local height = math.max(0, screen.AbsoluteSize.Y - redPanel.Position.Y.Offset - Kit.space.small)
		redLimit.MaxSize = Vector2.new(240, height)
		blueLimit.MaxSize = redLimit.MaxSize
	end
	local function layoutCommands()
		local top = bluePanel.AbsolutePosition.Y
			+ bluePanel.AbsoluteSize.Y
			- hubScreen.AbsolutePosition.Y
			+ Kit.space.small
		commands.Position = UDim2.new(1, -16, 0, top)
		commands.Size = UDim2.new(0, 156, 1, -(top + 16))
	end
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	bluePanel:GetPropertyChangedSignal("AbsolutePosition"):Connect(layoutCommands)
	bluePanel:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutCommands)
	layout()
	layoutCommands()

	local feed = Kit.create("Frame", {
		Name = "Feed",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, Kit.space.small, 0.55, 0),
		Size = UDim2.new(0.3, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = screen,
	}, {
		Kit.create("UISizeConstraint", { MinSize = Vector2.new(160, 0), MaxSize = Vector2.new(320, math.huge) }),
		Kit.list(Enum.FillDirection.Vertical, 4),
	}) :: Frame
	local function feedLayout()
		local compact = screen.AbsoluteSize.X < 600
		feed.AnchorPoint = Vector2.new(0, if compact then 1 else 0.5)
		feed.Position = if compact then UDim2.new(0, 8, 1, -8) else UDim2.new(0, 8, 0.55, 0)
	end
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(feedLayout)
	feedLayout()

	local results = Kit.create("Frame", {
		Name = "Results",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.new(0.6, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Kit.colors.panel,
		Visible = false,
		Parent = screen,
	}, {
		Kit.corner(16),
		Kit.padding(Kit.space.large),
		Kit.create("UISizeConstraint", { MinSize = Vector2.new(220, 0), MaxSize = Vector2.new(420, math.huge) }),
		Kit.list(Enum.FillDirection.Vertical, Kit.space.small, Enum.HorizontalAlignment.Center),
	}) :: Frame
	local winner = Kit.label("", Kit.size.title, Kit.colors.primary, true)
	winner.TextXAlignment = Enum.TextXAlignment.Center
	winner.LayoutOrder = 1
	winner.Parent = results
	local earned = Kit.label("", Kit.size.heading, Kit.colors.text, true)
	earned.TextXAlignment = Enum.TextXAlignment.Center
	earned.LayoutOrder = 2
	earned.Parent = results

	local back = Kit.button("Back to hub", "primary")
	back.Parent = results
	back.LayoutOrder = 3
	back.Activated:Connect(function()
		context.hub.returnToHub()
	end)
	local function me(): Round.Fighter?
		for _, fighter in state.fighters do
			if fighter.name == api.localName then
				return fighter
			end
		end
		return nil
	end

	local function renderRoster(team: Round.Team, header: TextLabel, roster: Frame)
		for _, child in roster:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local alive = 0
		local order = 0
		for _, fighter in state.fighters do
			if fighter.team == team then
				order += 1
				if not fighter.eliminated then
					alive += 1
				end
				local row = Kit.create("Frame", {
					Name = fighter.name,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 24),
					AutomaticSize = Enum.AutomaticSize.Y,
					LayoutOrder = order,
					Parent = roster,
				}) :: Frame
				local you = fighter.name == api.localName
				local name = Kit.label(if you then fighter.name .. " (You)" else fighter.name, Kit.size.small)
				name.Size = UDim2.new(1, -44, 0, 0)
				name.TextYAlignment = Enum.TextYAlignment.Top
				name.TextColor3 = if fighter.eliminated then Kit.colors.muted else Kit.colors.text
				name.FontFace = if you then Kit.bold else Kit.font
				name.Parent = row
				if fighter.eliminated then
					local tag = Kit.label("OUT", Kit.size.small, Kit.colors.dangerText, true)
					tag.AutomaticSize = Enum.AutomaticSize.None
					tag.AnchorPoint = Vector2.new(1, 0)
					tag.Position = UDim2.fromScale(1, 0)
					tag.Size = UDim2.fromOffset(40, 22)
					tag.TextXAlignment = Enum.TextXAlignment.Center
					tag.BackgroundTransparency = 0
					tag.BackgroundColor3 = Kit.colors.danger
					Kit.corner(6).Parent = tag
					tag.Parent = row
				end
			end
		end
		header.Text = ("%s  %d alive"):format(team, alive)
	end

	local function renderFeed()
		for _, child in feed:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		for index, text in lines do
			local line = Kit.label(text, Kit.size.small, Kit.colors.text, true)
			line.LayoutOrder = index
			line.BackgroundTransparency = 0.2
			line.BackgroundColor3 = Kit.colors.panel
			Kit.corner(8).Parent = line
			Kit.padding(6).Parent = line
			line.Parent = feed
		end
	end

	local function renderTimer()
		local left = math.max(0, math.ceil(state.endsAt - api.serverNow()))
		timer.Text = ("%s %d:%02d"):format(state.phase, left // 60, left % 60)
	end

	local function render()
		if state.round ~= lastRound or (state.phase == "Round" and lastPhase ~= "Round") then
			table.clear(lines)
			renderFeed()
		end
		lastRound = state.round
		lastPhase = state.phase
		renderTimer()
		renderRoster("Red", redHeader, redRoster)
		renderRoster("Blue", blueHeader, blueRoster)
		local self = me()
		out.Visible = state.phase == "Round" and self ~= nil and self.eliminated
		results.Visible = state.phase == "Results"
		if state.phase == "Results" then
			local won = state.winner
			winner.Text = if won == "Draw" or won == nil then "Draw" else won .. " wins"
			local team = if self ~= nil then self.team else "Red"
			local rewards = state.rewards
			local amount = if rewards == nil then 0 elseif team == "Red" then rewards.Red else rewards.Blue
			earned.Text = ("You earned %d Coins • 5 Gems • 120 XP"):format(amount)
		end
	end

	api.onStateChanged(function(next: Round.State)
		state = next
		render()
	end)
	api.onEvent(function(event: Round.Event)
		table.insert(lines, ("%s knocked out: last on %s"):format(event.victim, event.by))
		while #lines > FEED_LINES do
			table.remove(lines, 1)
		end
		renderFeed()
	end)
	task.spawn(function()
		while screen.Parent ~= nil do
			renderTimer()
			task.wait(0.2)
		end
	end)
	render()
end

return {
	mount = mount,
}
