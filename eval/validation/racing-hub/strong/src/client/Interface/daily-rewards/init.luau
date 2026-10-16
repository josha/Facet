--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyRewards = require(ReplicatedStorage.Shared.Hub.DailyRewards)
local Kit = require(script.Parent.Kit)

export type Context = {
	player: Player,
	playerGui: PlayerGui,
	rewards: DailyRewards.Client,
}

type Card = { frame: Frame, state: TextLabel, claim: TextButton }

local function describe(reward: DailyRewards.Reward): string
	return ("%s %s"):format(Kit.number(reward.amount), reward.name)
end

local function mount(context: Context)
	local api = context.rewards
	local state = api.getState()
	local pending = false
	local lastReward: DailyRewards.Reward? = nil

	local screen = Kit.screen(context.playerGui, "RewardsInterface")
	local scale = Kit.scale(screen)
	local hud = Kit.hud(screen)
	local openButton = Kit.button("Rewards")
	openButton.Name = "OpenRewards"
	openButton.Parent = hud
	local badge = Kit.badge(openButton, "Ready")
	badge.Name = "Ready"

	local modal = Kit.modal(screen, "RewardsPanel", "Daily Rewards", Vector2.new(1180, 640))
	modal.hides(openButton)
	local scroller = Kit.scroller()
	scroller.Parent = modal.body
	Kit.list(Enum.FillDirection.Vertical, Kit.space.medium).Parent = scroller

	local balances = Kit.label("", Kit.size.body, Kit.colors.muted, true)
	balances.LayoutOrder = 1
	balances.Parent = scroller
	local banner, showBanner = Kit.message(scroller)
	banner.LayoutOrder = 2

	local track = Kit.create("ScrollingFrame", {
		Name = "Track",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, 200),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 6,
		Selectable = false,
		Parent = scroller,
	}) :: ScrollingFrame
	local trackLayout = Kit.list(Enum.FillDirection.Horizontal, Kit.space.small) :: UIListLayout
	trackLayout.Parent = track

	local status = Kit.label("", Kit.size.heading, Kit.colors.text, true)
	status.Name = "Status"
	status.LayoutOrder = 3
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.Parent = scroller
	local countdown = Kit.label("", Kit.size.body, Kit.colors.muted, true)
	countdown.Name = "Countdown"
	countdown.LayoutOrder = 4
	countdown.TextXAlignment = Enum.TextXAlignment.Center
	countdown.Parent = scroller

	local cards: { [number]: Card } = {}
	local narrow = false
	local render: () -> ()

	local function claim()
		if pending or state.claimedToday then
			return
		end
		pending = true
		task.spawn(function()
			local ok, result = pcall(api.claim)
			pending = false
			if ok then
				state = result.state
				if result.ok then
					lastReward = result.reward
				end
			end
			render()
			if ok and result.ok then
				Kit.focus(modal.close)
			end
		end)
	end

	local function build()
		for _, card in cards do
			card.frame:Destroy()
		end
		table.clear(cards)
		for _, entry in state.track do
			local big = entry.day == #state.track
			local frame = Kit.create("Frame", {
				Name = "Day" .. entry.day,
				LayoutOrder = entry.day,
				BackgroundColor3 = if big then Kit.colors.cardRaised else Kit.colors.card,
				Size = if narrow then UDim2.new(1, 0, 0, 0) else UDim2.fromOffset(if big then 180 else 140, 188),
				AutomaticSize = if narrow then Enum.AutomaticSize.Y else Enum.AutomaticSize.None,
				Parent = track,
			}, {
				Kit.corner(12),
				Kit.padding(Kit.space.small),
				Kit.create("UIStroke", {
					Color = if big then Kit.colors.primary else Kit.colors.cardRaised,
					Thickness = if big then 2 else 1,
				}),
			}) :: Frame
			if narrow then
				Kit.list(Enum.FillDirection.Vertical, 4).Parent = frame
			end
			local title = Kit.label("Day " .. entry.day, Kit.size.body, Kit.colors.text, true)
			title.AutomaticSize = Enum.AutomaticSize.None
			title.Size = UDim2.new(1, 0, 0, 24)
			title.LayoutOrder = 1
			title.Parent = frame
			local reward = Kit.label(describe(entry.reward), Kit.size.body, Kit.colors.primary, true)
			reward.AutomaticSize = Enum.AutomaticSize.None
			reward.Size = UDim2.new(1, 0, 0, 48)
			reward.LayoutOrder = 2
			reward.Position = UDim2.fromOffset(0, 28)
			reward.Parent = frame
			local label = Kit.label("", Kit.size.small, Kit.colors.muted, true)
			label.Name = "State"
			label.AutomaticSize = Enum.AutomaticSize.None
			label.Size = UDim2.new(1, 0, 0, 24)
			label.LayoutOrder = 3
			label.Position = UDim2.fromOffset(0, 80)
			label.Parent = frame
			local button = Kit.button("Claim", "primary")
			button.Name = "Claim"
			button.AnchorPoint = if narrow then Vector2.zero else Vector2.new(0, 1)
			button.Position = if narrow then UDim2.new() else UDim2.fromScale(0, 1)
			button.Size = UDim2.new(1, 0, 0, 48)
			button.LayoutOrder = 4
			button.Visible = false
			button.Parent = frame
			button.Activated:Connect(claim)
			cards[entry.day] = { frame = frame, state = label, claim = button }
		end
	end

	render = function()
		balances.Text = ("%s Coins   %s Gems"):format(Kit.number(state.wallet.Coins), Kit.number(state.wallet.Gems))
		badge.Visible = not state.claimedToday
		for day, card in cards do
			local word = if day < state.day or (day == state.day and state.claimedToday)
				then "Claimed"
				elseif day == state.day then "Today"
				else "Locked"
			card.state.Text = word
			card.state.TextColor3 = if word == "Today" then Kit.colors.primary else Kit.colors.muted
			card.claim.Visible = word == "Today"
			card.claim.Text = if pending then "Claiming" else "Claim"
			card.claim.Interactable = not pending
		end
		if state.restarted then
			showBanner("You missed a day. Your streak starts again at Day 1.")
		else
			showBanner(nil)
		end
		status.Text = if lastReward ~= nil and state.claimedToday
			then "You got " .. describe(lastReward :: DailyRewards.Reward)
			else ""
		status.Visible = status.Text ~= ""
	end

	local function layout()
		local wasNarrow = narrow
		local window = scroller.AbsoluteWindowSize / scale.Scale
		narrow = window.X < 760 and window.Y >= 480
		if narrow then
			track.ScrollingDirection = Enum.ScrollingDirection.Y
			track.AutomaticCanvasSize = Enum.AutomaticSize.Y
			trackLayout.FillDirection = Enum.FillDirection.Vertical
			track.Size = UDim2.new(1, 0, 0, 7 * 80)
		else
			track.ScrollingDirection = Enum.ScrollingDirection.X
			track.AutomaticCanvasSize = Enum.AutomaticSize.X
			trackLayout.FillDirection = Enum.FillDirection.Horizontal
			track.Size = UDim2.new(1, 0, 0, 200)
		end
		if wasNarrow ~= narrow or next(cards) == nil then
			build()
			render()
		end
	end
	scroller:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(layout)

	local function revealToday()
		local card = cards[state.day]
		if card == nil or narrow then
			return
		end
		task.delay(0.1, function()
			local frame = card.frame
			local offset = (frame.AbsolutePosition.X - track.AbsolutePosition.X) / scale.Scale + track.CanvasPosition.X
			local window = track.AbsoluteWindowSize.X / scale.Scale
			local target = offset - (window - frame.AbsoluteSize.X / scale.Scale) / 2
			local limit = math.max(0, track.AbsoluteCanvasSize.X / scale.Scale - window)
			track.CanvasPosition = Vector2.new(math.clamp(target, 0, limit), 0)
		end)
	end

	task.spawn(function()
		while screen.Parent ~= nil do
			if state.claimedToday and state.nextClaimAt > 0 then
				local left = math.floor(math.max(0, state.nextClaimAt - api.serverNow()))
				countdown.Text = ("Next reward in %d:%02d:%02d"):format(left // 3600, (left % 3600) // 60, left % 60)
			else
				countdown.Text = ""
			end
			countdown.Visible = countdown.Text ~= ""
			task.wait(0.25)
		end
	end)

	openButton.Activated:Connect(function()
		state = api.getState()
		layout()
		render()
		local today = cards[state.day]
		modal.setOpen(true, if today ~= nil and not state.claimedToday then today.claim else nil)
		revealToday()
	end)
	api.onStateChanged(function(next: DailyRewards.State)
		state = next
		if not state.claimedToday then
			lastReward = nil
			revealToday()
		end
		render()
	end)
	layout()
	render()
end

return {
	mount = mount,
}
