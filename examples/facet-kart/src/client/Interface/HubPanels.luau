--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local Round = require(ReplicatedStorage.Shared.Hub.Round)
local Hub = require(ReplicatedStorage.Shared.Hub)
local Garage = require(ReplicatedStorage.Shared.Hub.Garage)
local Drivers = require(ReplicatedStorage.Shared.Hub.Drivers)
local Kit = require(script.Parent.Kit)

local function mount(context: Hub.Context)
	local screen = Kit.screen(context.playerGui, "Hub")
	local dock = Kit.hud(screen)
	local readouts =
		Kit.create("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = screen }) :: Frame
	local function coverReadouts()
		readouts.Visible = screen:GetAttribute("ModalOpen") ~= true
	end
	screen:GetAttributeChangedSignal("ModalOpen"):Connect(coverReadouts)
	coverReadouts()
	local status = Kit.create("Frame", {
		Name = "HubStatus",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(260, 0),
		Parent = readouts,
	}, { Kit.list(Enum.FillDirection.Vertical, 8) }) :: Frame
	status.LayoutOrder = 2
	local leftColumn = Kit.create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 48),
		Size = UDim2.fromOffset(186, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = readouts,
	}, { Kit.list(Enum.FillDirection.Vertical, 8) }) :: Frame
	local more = Kit.modal(screen, "More", "More", Vector2.new(360, 680))
	local moreButton = Kit.button("More")
	moreButton.LayoutOrder = 4
	moreButton.Parent = dock
	moreButton.Activated:Connect(function()
		more.setOpen(true)
	end)
	local menuScroll = Kit.scroller()
	menuScroll.Parent = more.body
	Kit.list(Enum.FillDirection.Vertical, 12).Parent = menuScroll
	local destinations: { [string]: Frame } = {}
	for index, group in
		{
			{ "Progress", "Quests", "Rewards", "Boosts", "Offer" },
			{ "Collection", "Drivers", "Crates", "Inventory" },
			{ "Account", "Codes", "Settings" },
		}
	do
		local section = Kit.create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = index,
			Parent = menuScroll,
		}, { Kit.list(Enum.FillDirection.Vertical, 8) }) :: Frame
		local heading = Kit.label(group[1], Kit.size.small, Kit.colors.muted, true)
		heading.Parent = section
		for order = 2, #group do
			destinations[group[order]] = section
		end
	end
	local notice = Kit.create("Frame", {
		Name = "Attention",
		BackgroundColor3 = Kit.colors.primary,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(8, 8),
		Parent = moreButton,
	}, { Kit.corner(4) }) :: Frame
	local function menuLayout()
		local panelScreen = more.panel.Parent :: ScreenGui
		local scale = if Kit.isTenFoot() then 1.25 else 1
		local size = panelScreen.AbsoluteSize / scale
		local phone = game:GetService("UserInputService").TouchEnabled and math.min(size.X, size.Y) < 600
		if phone then
			more.panel.AnchorPoint = Vector2.new(0.5, 0.5)
			more.panel.Position = UDim2.fromScale(0.5, 0.5)
			more.panel.Size = UDim2.fromOffset(math.min(480, size.X - 32), math.min(680, size.Y - 32))
		else
			more.panel.AnchorPoint = Vector2.zero
			more.panel.Position = UDim2.fromOffset(
				math.max(
					Kit.space.large,
					(moreButton.AbsolutePosition.X + moreButton.AbsoluteSize.X - panelScreen.AbsolutePosition.X) / scale
						- 360
				),
				Kit.size.body * 4
			)
			more.panel.Size = UDim2.fromOffset(360, math.min(680, size.Y - 112))
		end
	end
	moreButton:GetPropertyChangedSignal("AbsolutePosition"):Connect(menuLayout)
	local menuScreen = more.panel.Parent :: ScreenGui
	menuScreen:GetPropertyChangedSignal("AbsoluteSize"):Connect(menuLayout)
	menuLayout()
	local commands = dock.Parent :: Frame
	commands.Name = "HubCommands"
	local function button(parent: Instance, words: string, action: () -> ()): TextButton
		local control = Kit.button(words)
		control.Parent = parent
		control.Activated:Connect(function()
			action()
		end)
		return control
	end
	local function label(parent: Instance, words: string): TextLabel
		local control = Kit.label(words)
		control.Parent = parent
		return control
	end
	local function body(modal: Kit.Modal): ScrollingFrame
		local scroll = Kit.scroller()
		scroll.Parent = modal.body
		Kit.list(Enum.FillDirection.Vertical, 8).Parent = scroll
		return scroll
	end
	local function clear(parent: Instance)
		for _, child in parent:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end
	local hub = context.hub.getState()
	local economy = context.economy.getState()
	local counters = Kit.create("Frame", {
		Name = "PlayerStats",
		BackgroundTransparency = 0,
		BackgroundColor3 = Kit.colors.panel,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(16, 48),
		Size = UDim2.fromOffset(170, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = readouts,
	}, { Kit.list(Enum.FillDirection.Vertical, 8), Kit.padding(12), Kit.corner(12) }) :: Frame
	counters.LayoutOrder = 1
	local counterLayout = counters:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	local counterPadding = counters:FindFirstChildOfClass("UIPadding") :: UIPadding
	local function hudLayout()
		local size = screen.AbsoluteSize / (if Kit.isTenFoot() then 1.25 else 1)
		local touch = game:GetService("UserInputService").TouchEnabled
		local landscape = touch and size.X > size.Y and size.Y < 600
		local portrait = touch and size.X < 600
		leftColumn.Visible = portrait
		leftColumn.AnchorPoint = Vector2.new(1, 0)
		leftColumn.Position = UDim2.new(1, -Kit.space.large, 0, Kit.size.body * 9)
		counters.Parent = readouts
		status.Parent = if portrait then leftColumn else readouts
		counters.AnchorPoint = Vector2.new(1, 0)
		counters.Position = UDim2.new(1, -Kit.space.large, 0, Kit.size.body * 4)
		local width = math.min(484, size.X - Kit.space.large * 2)
		counters.Size = UDim2.fromOffset(width, 0)
		counterLayout.FillDirection = Enum.FillDirection.Horizontal
		counterPadding.PaddingTop = UDim.new(0, Kit.space.small)
		counterPadding.PaddingBottom = counterPadding.PaddingTop
		counterPadding.PaddingLeft = UDim.new(0, Kit.space.small)
		counterPadding.PaddingRight = counterPadding.PaddingLeft
		for _, child in counters:GetChildren() do
			if child:IsA("TextLabel") then
				child.Size = UDim2.fromOffset((width - Kit.space.small * 4) / 3, 0)
			end
		end
		status.AnchorPoint = if landscape or portrait then Vector2.zero else Vector2.new(0.5, 0)
		status.Position = if landscape
			then UDim2.fromOffset(370, 150)
			elseif touch and size.X < 600 then UDim2.new(0.5, 0, 0, 328)
			elseif touch then UDim2.fromScale(0.6, 0.72)
			else UDim2.fromScale(0.5, 0.72)
		status.Size = UDim2.fromOffset(if landscape then 180 elseif portrait then 186 else 260, 0)
	end
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(hudLayout)
	hudLayout()
	local wallet = label(counters, "")
	local progress = label(counters, "")
	local income = label(counters, "")
	local summary = Kit.create("ScrollingFrame", {
		BackgroundColor3 = Kit.colors.panel,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 52),
		Size = UDim2.new(0.46, -8, 0.18, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		AutomaticSize = Enum.AutomaticSize.None,
		Visible = false,
		Parent = screen,
	}, { Kit.padding(8), Kit.list(Enum.FillDirection.Vertical, 8) }) :: ScrollingFrame
	local function raceLayout()
		local size = screen.AbsoluteSize
		local landscape = game:GetService("UserInputService").TouchEnabled and size.X > size.Y and size.Y < 600
		summary.Position = UDim2.new(1, -8, 0, if landscape then 64 + size.Y * 0.18 else 52)
		summary.Size = UDim2.new(if size.X < 600 then 0.46 else 0.28, -8, 0.18, 0)
	end
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(raceLayout)
	raceLayout()
	Kit.create("UISizeConstraint", { MaxSize = Vector2.new(260, 250), Parent = summary })
	local loadout = label(summary, "")
	local raceWallet = label(summary, "")
	local boosts = Kit.modal(screen, "Boosts", "Boosts")
	local boostBody = body(boosts)
	label(boostBody, "2x Coins for 30 seconds")
	local boostTimer = label(boostBody, "")
	local boostIncome = label(boostBody, "")
	local boostBuy = button(boostBody, "Buy for 10 Gems", function()
		context.economy.buyBoost()
	end)
	local quests = Kit.modal(screen, "Quests", "Quests")
	local questBody = body(quests)
	local offer = Kit.modal(screen, "Offer", "Offer")
	local offerBody = body(offer)
	label(offerBody, "Starter Offer")
	label(offerBody, "5K Coins for 99 Gems")
	local offerTimer = label(offerBody, "")
	local offerBuy = button(offerBody, "Buy", function()
		context.economy.buyOffer()
	end)
	local offerButton = button(dock, "Offer", function()
		offer.setOpen(true)
	end)
	local offerBadge = Kit.badge(offerButton, "")
	button(dock, "Boosts", function()
		boosts.setOpen(true)
	end)
	button(dock, "Quests", function()
		quests.setOpen(true)
	end)
	local function renderEconomy()
		wallet.Text = Kit.short(economy.coins) .. " Coins\n" .. Kit.short(economy.gems) .. " Gems"
		progress.Text = ("Level %d\nXP %d / 100\nRaces %d"):format(hub.level, hub.xp % 100, hub.races)
		income.Text = ("+%d/s\nZone 2 %s / 5K"):format(economy.perSecond, Kit.short(economy.zoneProgress))
		boostIncome.Text = ("Income +%d/s"):format(economy.perSecond)
		local left = economy.offer.endsAt - context.hub.serverNow()
		local attention = not economy.offer.bought and left > 0 or not context.rewards.getState().claimedToday
		for _, quest in economy.quests do
			attention = attention or not quest.claimed and quest.progress >= quest.goal
		end
		notice.Visible = attention
		offerBadge.Text = Kit.clock(left)
		offerBadge.Visible = not economy.offer.bought and left > 0
		offerTimer.Text = "Ends in " .. Kit.clock(left)
		offerBuy.Text = if economy.offer.bought then "Bought" else "Buy"
		offerBuy.Interactable = not economy.offer.bought and left > 0
		local boostLeft = (economy.boostEndsAt or 0) - context.hub.serverNow()
		boostTimer.Text = if boostLeft > 0 then "2x Coins: " .. Kit.clock(boostLeft) .. " left" else "Ready"
		boostBuy.Interactable = boostLeft <= 0
	end
	local function renderQuests()
		clear(questBody)
		for _, quest in economy.quests do
			local card = Kit.card()
			card.Parent = questBody
			Kit.list(Enum.FillDirection.Vertical, 8).Parent = card
			label(card, quest.title)
			label(card, ("%d / %d • %d Gems"):format(quest.progress, quest.goal, quest.reward))
			local action = button(card, if quest.claimed then "Claimed" else "Claim", function()
				context.economy.claimQuest(quest.id)
			end)
			action.Interactable = not quest.claimed and quest.progress >= quest.goal
		end
	end
	context.economy.onStateChanged(function(next)
		economy = next
		renderEconomy()
		renderQuests()
	end)
	context.rewards.onStateChanged(function()
		renderEconomy()
	end)
	context.hub.onStateChanged(function(next)
		hub = next
		renderEconomy()
	end)
	local queue = context.lobby.getState()
	local modes = Kit.modal(screen, "Modes", "Play")
	modes.close.Text = "Back"
	local modeBody = body(modes)
	for _, mode in context.lobby.modes do
		button(modeBody, mode.name .. " • " .. tostring(mode.players) .. " players", function()
			context.lobby.join(mode.id)
			modes.setOpen(false)
		end)
	end
	local playButton = button(dock, "Play", function()
		modes.setOpen(true)
	end)
	playButton.LayoutOrder = 1
	playButton.BackgroundColor3 = Kit.colors.primary
	playButton.TextColor3 = Kit.colors.primaryText
	local previousPhase: Round.Phase? = nil
	local function phaseChanged(state: Round.State)
		counters.Visible = state.phase == "Intermission"
		status.Visible = state.phase == "Intermission"
		dock.Visible = state.phase == "Intermission"
		summary.Visible = state.phase == "Round"
		if previousPhase ~= state.phase then
			if state.phase == "Round" then
				GuiService.SelectedObject = nil
			elseif state.phase == "Intermission" then
				Kit.focus(playButton)
			end
		end
		previousPhase = state.phase
	end
	context.round.onStateChanged(phaseChanged)
	phaseChanged(context.round.getState())
	local queueLabel = label(status, "")
	queueLabel.LayoutOrder = 2
	queueLabel.TextXAlignment = Enum.TextXAlignment.Center
	queueLabel.BackgroundColor3 = Kit.colors.panel
	queueLabel.BackgroundTransparency = 0.05
	queueLabel.FontFace = Kit.bold
	Kit.corner(12).Parent = queueLabel
	Kit.padding(Kit.space.medium).Parent = queueLabel
	local leaveQueue = button(dock, "Leave Queue", function()
		context.lobby.leave()
	end)
	leaveQueue.LayoutOrder = 1
	leaveQueue.BackgroundColor3 = Kit.colors.primary
	leaveQueue.TextColor3 = Kit.colors.primaryText
	local function renderQueue()
		local racing = previousPhase == "Round"
		queueLabel.Parent = if racing then summary else status
		queueLabel.Size = UDim2.new(1, 0, 0, 0)
		queueLabel.Visible = queue.phase ~= "Lobby"
		playButton.Visible = queue.phase == "Lobby" and context.garage.getState().spawned == nil
		leaveQueue.Visible = (queue.phase == "Queue" or queue.phase == "Countdown")
			and context.garage.getState().spawned == nil
		if queue.phase == "Countdown" then
			queueLabel.Text = ("%d/%d\nMatch starts in %d"):format(
				queue.players,
				queue.needed,
				math.max(0, math.ceil((queue.countdownEndsAt or 0) - context.hub.serverNow()))
			)
		elseif queue.phase == "Queue" then
			local needed = queue.needed - queue.players
			queueLabel.Text = ("%d/%d\nNeed %d more %s"):format(
				queue.players,
				queue.needed,
				needed,
				if needed == 1 then "player" else "players"
			)
		elseif queue.phase == "Starting" then
			queueLabel.Text = "Starting match"
		else
			queueLabel.Text = ""
		end
	end
	context.lobby.onStateChanged(function(next)
		queue = next
		renderQueue()
	end)
	context.round.onStateChanged(function()
		renderQueue()
	end)
	local garageState = context.garage.getState()
	local garage = Kit.modal(screen, "Garage", "Garage")
	local garageBody = body(garage)
	local category = "All"
	local rarity = "All"
	local draft = "All"
	local selected: Garage.Vehicle? = nil
	local filters = Kit.modal(screen, "Filters", "Filters")
	local filterBody = body(filters)
	local detail = Kit.modal(screen, "Kart", "Kart details")
	local detailBody = body(detail)
	local renderGarage: () -> ()
	local renderDetail: () -> ()
	for _, value in context.garage.rarities do
		button(filterBody, value, function()
			draft = value
		end)
	end
	button(filterBody, "Apply", function()
		rarity = draft
		filters.setOpen(false)
		renderGarage()
	end)
	button(filterBody, "Cancel", function()
		filters.setOpen(false)
	end)
	renderDetail = function()
		clear(detailBody)
		local kart = selected
		if kart == nil then
			return
		end
		label(detailBody, kart.name .. " • " .. kart.rarity .. " • Lv " .. tostring(kart.level))
		label(detailBody, ("Speed %d\nArmor %d\nFirepower %d"):format(kart.speed, kart.armor, kart.firepower))
		button(detailBody, if garageState.favorites[kart.id] then "Unfavorite" else "Favorite", function()
			context.garage.setFavorite(kart.id, not garageState.favorites[kart.id])
		end)
		button(detailBody, "Spawn", function()
			local result = context.garage.spawn(kart.id)
			if result.ok then
				detail.setOpen(false)
				garage.setOpen(false)
			end
		end)
	end
	renderGarage = function()
		clear(garageBody)
		for _, value in { "All", "Sprint", "Circuit", "Coast", "Favorites" } do
			button(garageBody, value, function()
				category = value
				renderGarage()
			end)
		end
		button(garageBody, "Inventory", function()
			Kit.openPanel("Inventory")
		end)
		button(garageBody, "Filters", function()
			draft = rarity
			filters.setOpen(true)
		end)
		button(garageBody, "Clear Filters", function()
			rarity = "All"
			renderGarage()
		end)
		local count = 0
		for _, kart in context.garage.vehicles do
			if
				(
					category == "All"
					or kart.category == category
					or (category == "Favorites" and garageState.favorites[kart.id])
				) and (rarity == "All" or kart.rarity == rarity)
			then
				count += 1
				button(garageBody, ("%s • Lv %d • %s"):format(kart.name, kart.level, kart.rarity), function()
					selected = kart
					renderDetail()
					detail.setOpen(true)
				end)
			end
		end
		if count == 0 then
			label(garageBody, "No vehicles match")
		end
	end
	local garageButton = button(dock, "Garage", function()
		renderGarage()
		garage.setOpen(true)
	end)
	garageButton.LayoutOrder = 3
	local vehicle = label(status, "")
	vehicle.LayoutOrder = 3
	local exit = button(dock, "Leave Vehicle", function()
		context.garage.exit()
	end)
	exit.LayoutOrder = 1
	exit.BackgroundColor3 = Kit.colors.primary
	exit.TextColor3 = Kit.colors.primaryText
	local function renderVehicle()
		exit.Visible = garageState.spawned ~= nil
		renderQueue()
		vehicle.Text = if garageState.spawned ~= nil then "Drive: W A S D\nExit: Leave Vehicle" else ""
		vehicle.Visible = garageState.spawned ~= nil
	end
	context.garage.onStateChanged(function(next)
		garageState = next
		renderVehicle()
		hudLayout()
		if detail.isOpen() then
			renderDetail()
		end
	end)
	local drivers = Kit.modal(screen, "Drivers", "Drivers")
	local driverBody = body(drivers)
	local driverState = context.drivers.getState()
	local series = "Circuit"
	local chosen: Drivers.Driver? = nil
	local confirm = Kit.modal(screen, "DriverConfirm", "Confirm")
	local confirmBody = body(confirm)
	local confirmText = label(confirmBody, "")
	local pending: (() -> ())? = nil
	button(confirmBody, "Confirm", function()
		local action = pending
		if action ~= nil then
			pending = nil
			action()
		end
		confirm.setOpen(false)
	end)
	button(confirmBody, "Cancel", function()
		pending = nil
		confirm.setOpen(false)
	end)
	local rentReadout: TextLabel? = nil
	local rentEndsAt = 0
	local renderDrivers: () -> ()
	local function pay(driver: Drivers.Driver, rent: boolean)
		local price = if rent then driver.rentPrice else driver.price
		if driverState.coins < price then
			label(driverBody, "Not enough Coins")
			return
		end
		confirmText.Text = if rent
			then ("Rent %s for 10 minutes for %d Coins"):format(driver.name, price)
			else ("Buy %s for %d Coins"):format(driver.name, price)
		pending = function()
			if rent then
				context.drivers.rent(driver.id)
			else
				context.drivers.buy(driver.id)
			end
		end
		confirm.setOpen(true)
	end
	renderDrivers = function()
		clear(driverBody)
		rentReadout = nil
		label(driverBody, Kit.number(driverState.coins) .. " Coins")
		button(driverBody, "Circuit", function()
			series = "Circuit"
			chosen = nil
			renderDrivers()
		end)
		button(driverBody, "Rally", function()
			series = "Rally"
			chosen = nil
			renderDrivers()
		end)
		local driver = chosen
		if driver ~= nil then
			label(driverBody, driver.name)
			label(
				driverBody,
				("Strength %d\nSpeed %d\nDurability %d"):format(driver.strength, driver.speed, driver.durability)
			)
			local rented = driverState.rented[driver.id]
			if rented ~= nil then
				rentEndsAt = rented
				rentReadout = label(driverBody, "Rented: " .. Kit.clock(rented - context.hub.serverNow()) .. " left")
			end
			if driverState.equipped == driver.id then
				label(driverBody, "Equipped")
			end
			if driverState.owned[driver.id] or rented ~= nil then
				button(driverBody, "Equip", function()
					context.drivers.equip(driver.id)
				end)
			end
			if not driverState.owned[driver.id] then
				button(driverBody, "Buy", function()
					pay(driver, false)
				end)
				button(driverBody, "Rent", function()
					pay(driver, true)
				end)
			end
		end
		for _, candidate in context.drivers.drivers do
			if candidate.series == series then
				button(
					driverBody,
					candidate.name
						.. " • "
						.. tostring(candidate.price)
						.. " Coins"
						.. (if driverState.equipped == candidate.id then " • Equipped" else ""),
					function()
						chosen = candidate
						renderDrivers()
					end
				)
			end
		end
	end
	button(dock, "Drivers", function()
		renderDrivers()
		drivers.setOpen(true)
	end)
	context.drivers.onStateChanged(function(next)
		driverState = next
		if drivers.isOpen() then
			renderDrivers()
		end
	end)
	local function renderLoadout()
		local kartName = hub.raceKart
		for _, kart in context.garage.vehicles do
			if kart.id == hub.raceKart then
				kartName = kart.name
			end
		end
		local driverName = hub.raceDriver
		for _, driver in context.drivers.drivers do
			if driver.id == hub.raceDriver then
				driverName = driver.name
			end
		end
		raceWallet.Text = Kit.number(hub.wallet.Coins) .. " Coins • " .. Kit.number(hub.wallet.Gems) .. " Gems"
		loadout.Text = kartName
			.. " / "
			.. driverName
			.. " / Position "
			.. tostring(table.find(hub.positions, "You") or 1)
	end
	context.hub.onStateChanged(function(next)
		hub = next
		renderLoadout()
	end)
	renderLoadout()
	renderEconomy()
	renderQuests()
	renderQueue()
	renderVehicle()
	task.spawn(function()
		while screen.Parent ~= nil do
			renderEconomy()
			renderQueue()
			local readout = rentReadout
			if readout ~= nil and readout.Parent ~= nil then
				readout.Text = "Rented: " .. Kit.clock(rentEndsAt - context.hub.serverNow()) .. " left"
			end
			task.wait(0.5)
		end
	end)
	Kit.focus(playButton)
	return function()
		local orders = {
			Quests = 1,
			Rewards = 2,
			Boosts = 3,
			Offer = 4,
			Drivers = 1,
			Crates = 2,
			Inventory = 3,
			Codes = 1,
			Settings = 2,
		}
		for _, control in dock:GetChildren() do
			if control:IsA("TextButton") then
				local words = string.match(control.Text, "^%S+") or control.Text
				local destination = destinations[words]
				if destination then
					control.BackgroundColor3 = Kit.colors.secondary
					control.TextColor3 = Kit.colors.secondaryText
					control.TextXAlignment = Enum.TextXAlignment.Center
					control.LayoutOrder = orders[words] or 0
					control.Parent = destination
				elseif words == "Shop" then
					control.BackgroundColor3 = Kit.colors.secondary
					control.TextColor3 = Kit.colors.secondaryText
					control.LayoutOrder = 2
				elseif words == "Talk" then
					control.Parent = status
					control.LayoutOrder = 1
					control.Size = UDim2.new(1, 0, 0, 48)
				end
			end
		end
		menuLayout()
		hudLayout()
		local sections: { GuiObject } = {}
		for _, child in menuScroll:GetChildren() do
			if child:IsA("GuiObject") then
				table.insert(sections, child)
			end
		end
		table.sort(sections, function(a: GuiObject, b: GuiObject)
			return a.LayoutOrder < b.LayoutOrder
		end)
		local menuButtons: { TextButton } = { more.close }
		for _, section in sections do
			local controls: { TextButton } = {}
			for _, child in section:GetChildren() do
				if child:IsA("TextButton") then
					table.insert(controls, child)
				end
			end
			table.sort(controls, function(a: TextButton, b: TextButton)
				return a.LayoutOrder < b.LayoutOrder
			end)
			for _, control in controls do
				table.insert(menuButtons, control)
			end
		end
		for index, control in menuButtons do
			control.NextSelectionUp = menuButtons[index - 1] or control
			control.NextSelectionDown = menuButtons[index + 1] or control
			control.NextSelectionLeft = control
			control.NextSelectionRight = control
		end
		local glyphs = {
			Play = { { 0.3, 0.5, 0.7, 90 }, { 0.5, 0.35, 0.7, 30 }, { 0.5, 0.65, 0.7, -30 } },
			Shop = {
				{ 0.2, 0.6, 0.6, 90 },
				{ 0.8, 0.6, 0.6, 90 },
				{ 0.5, 0.9, 0.6, 0 },
				{ 0.5, 0.3, 0.6, 0 },
				{ 0.35, 0.2, 0.2, 90 },
				{ 0.65, 0.2, 0.2, 90 },
				{ 0.5, 0.1, 0.3, 0 },
			},
			Garage = {
				{ 0.5, 0.5, 0.8, 0 },
				{ 0.5, 0.7, 0.8, 0 },
				{ 0.2, 0.6, 0.2, 90 },
				{ 0.8, 0.6, 0.2, 90 },
				{ 0.3, 0.8, 0.2, 90 },
				{ 0.7, 0.8, 0.2, 90 },
				{ 0.35, 0.35, 0.4, -60 },
				{ 0.65, 0.35, 0.4, 60 },
				{ 0.5, 0.2, 0.2, 0 },
			},
			More = { { 0.2, 0.5, 0.12, 0 }, { 0.5, 0.5, 0.12, 0 }, { 0.8, 0.5, 0.12, 0 } },
		}
		for _, control in dock:GetChildren() do
			if control:IsA("TextButton") then
				local row = Kit.create("Frame", {
					Name = "HudAction",
					BackgroundTransparency = 1,
					LayoutOrder = control.LayoutOrder,
					Visible = control.Visible,
					Parent = dock,
				}) :: Frame
				control:GetPropertyChangedSignal("Visible"):Connect(function()
					row.Visible = control.Visible
				end)
				control.Parent = row
				control.TextTransparency = 1
				control.TextTruncate = Enum.TextTruncate.None
				local corner = control:FindFirstChildOfClass("UICorner") :: UICorner
				corner.CornerRadius = UDim.new(0.5, 0)
				local padding = control:FindFirstChildOfClass("UIPadding")
				if padding then
					padding:Destroy()
				end
				Kit.create("UIAspectRatioConstraint", { AspectRatio = 1, Parent = control })
				local caption = Kit.label(control.Text, Kit.size.body, Kit.colors.text, true)
				caption.Name = "ActionLabel"
				caption.AutomaticSize = Enum.AutomaticSize.None
				caption.TextXAlignment = Enum.TextXAlignment.Center
				caption.BackgroundTransparency = 0
				caption.BackgroundColor3 = Kit.colors.panel
				Kit.corner(Kit.space.small / 2).Parent = caption
				caption.Parent = control
				local symbol = Kit.create("Frame", {
					Name = "ActionIcon",
					BackgroundTransparency = 1,
					Position = UDim2.fromScale(0.25, 0.25),
					Size = UDim2.fromScale(0.5, 0.5),
					Parent = control,
				})
				for _, line in glyphs[control.Text] or glyphs.Play do
					Kit.create("Frame", {
						BackgroundColor3 = control.TextColor3,
						BorderSizePixel = 0,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(line[1], line[2]),
						Size = UDim2.new(line[3], 0, 0, Kit.space.small / 4),
						Rotation = line[4],
						Parent = symbol,
					})
				end
				control.Text = ""
			end
		end
	end
end

return { mount = mount }
