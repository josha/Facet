--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Codes = require(ReplicatedStorage.Shared.Hub.Codes)
local Kit = require(script.Parent.Kit)

export type Context = {
	player: Player,
	playerGui: PlayerGui,
	codes: Codes.Client,
}

local MESSAGES: { [string]: string } = {
	empty = "Type a code first",
	invalid = "That code does not exist",
	expired = "That code has expired",
	already_redeemed = "You already used that code",
	busy = "Please wait",
}

local function mount(context: Context)
	local api = context.codes
	local state = api.getState()
	local pending = false

	local screen = Kit.screen(context.playerGui, "CodesInterface")
	Kit.scale(screen)
	local hud = Kit.hud(screen)
	local openButton = Kit.button("Codes", "primary")
	openButton.Name = "OpenCodes"
	openButton.Parent = hud

	local modal = Kit.modal(screen, "CodesPanel", "Codes", Vector2.new(620, 640))
	modal.hides(openButton)
	local scroller = Kit.scroller()
	scroller.Parent = modal.body
	Kit.list(Enum.FillDirection.Vertical, Kit.space.medium).Parent = scroller

	local balances = Kit.create("Frame", {
		Name = "Balances",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = 1,
		Parent = scroller,
	}, { Kit.list(Enum.FillDirection.Horizontal, Kit.space.small) }) :: Frame
	local function pill(name: string): TextLabel
		local item = Kit.label("", Kit.size.body, Kit.colors.text, true)
		item.Name = name
		item.AutomaticSize = Enum.AutomaticSize.X
		item.Size = UDim2.fromOffset(0, 40)
		item.BackgroundTransparency = 0
		item.BackgroundColor3 = Kit.colors.card
		item.TextWrapped = false
		Kit.corner(20).Parent = item
		Kit.create("UIPadding", {
			PaddingLeft = UDim.new(0, 14),
			PaddingRight = UDim.new(0, 14),
			Parent = item,
		})
		item.Parent = balances
		return item
	end
	local coins = pill("Coins")
	local gems = pill("Gems")

	local hint = Kit.label("Type a code from our social pages to get free rewards.", Kit.size.small, Kit.colors.muted)
	hint.LayoutOrder = 2
	hint.Parent = scroller

	local field = Kit.input("Enter code")
	field.Name = "CodeField"
	field.LayoutOrder = 3
	field.Parent = scroller

	local redeem = Kit.button("Redeem", "primary")
	redeem.Name = "Redeem"
	redeem.LayoutOrder = 4
	redeem.Parent = scroller

	local note, show = Kit.message(scroller)
	note.LayoutOrder = 5

	local redeemedTitle = Kit.label("Redeemed", Kit.size.heading, Kit.colors.text, true)
	redeemedTitle.LayoutOrder = 6
	redeemedTitle.Parent = scroller
	local redeemedList = Kit.label("", Kit.size.body, Kit.colors.muted)
	redeemedList.Name = "RedeemedList"
	redeemedList.LayoutOrder = 7
	redeemedList.Parent = scroller

	local reveal = Kit.create("Frame", {
		Name = "Rewards",
		BackgroundColor3 = Kit.colors.panel,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 12,
		Parent = modal.body,
	}, { Kit.list(Enum.FillDirection.Vertical, Kit.space.medium, Enum.HorizontalAlignment.Center) }) :: Frame
	local revealTitle = Kit.label("You got", Kit.size.title, Kit.colors.primary, true)
	revealTitle.TextXAlignment = Enum.TextXAlignment.Center
	revealTitle.LayoutOrder = 1
	revealTitle.Parent = reveal
	local rewardLines = Kit.create("Frame", {
		Name = "Lines",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = reveal,
	}, { Kit.list(Enum.FillDirection.Vertical, Kit.space.small, Enum.HorizontalAlignment.Center) }) :: Frame
	local continue = Kit.button("Continue", "primary")
	continue.Name = "Continue"
	continue.Size = UDim2.new(1, 0, 0, 52)
	continue.LayoutOrder = 3
	continue.Parent = reveal

	local function render()
		coins.Text = Kit.number(state.wallet.Coins) .. " Coins"
		gems.Text = Kit.number(state.wallet.Gems) .. " Gems"
		redeemedList.Text = if #state.redeemed == 0 then "No codes yet" else table.concat(state.redeemed, ", ")
		redeem.Text = if pending then "Redeeming" else "Redeem"
		redeem.Interactable = not pending
		redeem.AutoButtonColor = not pending
		redeem.BackgroundColor3 = if pending then Kit.colors.secondary else Kit.colors.primary
		redeem.TextColor3 = if pending then Kit.colors.secondaryText else Kit.colors.primaryText
	end

	local function showRewards(rewards: { Codes.Reward })
		for _, child in rewardLines:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		for index, reward in rewards do
			local line = Kit.label(("%s %s"):format(Kit.number(reward.amount), reward.name), Kit.size.heading)
			line.TextXAlignment = Enum.TextXAlignment.Center
			line.FontFace = Kit.bold
			line.LayoutOrder = index
			line.BackgroundTransparency = 0
			line.BackgroundColor3 = Kit.colors.card
			Kit.corner(10).Parent = line
			Kit.padding(Kit.space.medium).Parent = line
			line.Parent = rewardLines
		end
		reveal.Visible = true
		scroller.Visible = false
		Kit.focus(continue)
	end

	local function submit()
		if pending then
			return
		end
		pending = true
		show(nil)
		render()
		local text = field.Text
		task.spawn(function()
			local ok, result = pcall(api.redeem, text)
			pending = false
			if not ok then
				show("Please try again")
			elseif result.ok then
				state = result.state
				field.Text = ""
				showRewards(result.rewards)
			else
				local reason = result.reason or "invalid"
				if reason == "rate_limited" then
					show(("Too many tries. Try again in %d seconds"):format(result.retryIn or 30))
				else
					show(MESSAGES[reason] or "That code does not work")
				end
				state = result.state
			end
			render()
		end)
	end

	redeem.Activated:Connect(submit)
	field.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			submit()
		end
	end)
	continue.Activated:Connect(function()
		reveal.Visible = false
		scroller.Visible = true
		Kit.focus(field)
	end)
	openButton.Activated:Connect(function()
		state = api.getState()
		show(nil)
		render()
		modal.setOpen(true, field)
	end)
	modal.onClosed(function()
		reveal.Visible = false
		scroller.Visible = true
	end)
	api.onStateChanged(function(next: Codes.State)
		state = next
		render()
	end)
	render()
end

return {
	mount = mount,
}
