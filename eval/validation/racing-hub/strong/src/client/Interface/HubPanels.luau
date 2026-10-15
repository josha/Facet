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
	local commands = (dock.Parent :: ScrollingFrame).Parent :: Frame
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
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 48),
		Size = UDim2.fromOffset(170, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = screen,
	}, { Kit.list(Enum.FillDirection.Vertical, 8) }) :: Frame
	local wallet = label(counters, "")
	local progress = label(counters, "")
	local income = label(counters, "")
	local summary = Kit.create("Frame", {
		BackgroundColor3 = Kit.colors.panel,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(0.4, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = screen,
	}, { Kit.padding(8), Kit.list(Enum.FillDirection.Vertical, 8) }) :: Frame
	local loadout = label(summary, "")
	local raceWallet = label(summary, "")
	local boosts = Kit.modal(screen, "Boosts", "Boosts")
	local boostBody = body(boosts)
	label(boostBody, "2x Coins for 30 seconds")
	local boostTimer = label(boostBody, "")
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
		local left = economy.offer.endsAt - context.hub.serverNow()
		offerButton.Text = "Offer " .. Kit.clock(left)
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
	local previousPhase: Round.Phase? = nil
	local function phaseChanged(state: Round.State)
		counters.Visible = state.phase == "Intermission"
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
	local queueLabel = label(screen, "")
	queueLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	queueLabel.Position = UDim2.fromScale(0.5, 0.85)
	queueLabel.Size = UDim2.new(0.6, 0, 0, 0)
	queueLabel.TextXAlignment = Enum.TextXAlignment.Center
	queueLabel.BackgroundColor3 = Kit.colors.panel
	queueLabel.BackgroundTransparency = 0.05
	queueLabel.FontFace = Kit.bold
	Kit.corner(12).Parent = queueLabel
	Kit.padding(Kit.space.medium).Parent = queueLabel
	local leaveQueue = button(dock, "Leave Queue", function()
		context.lobby.leave()
	end)
	local function renderQueue()
		local racing = previousPhase == "Round"
		queueLabel.Parent = if racing then commands else screen
		queueLabel.AnchorPoint = if racing then Vector2.zero else Vector2.new(0.5, 0.5)
		queueLabel.Position = if racing then UDim2.new() else UDim2.fromScale(0.5, 0.85)
		queueLabel.Size = UDim2.new(if racing then 1 else 0.6, 0, 0, 0)
		queueLabel.Visible = queue.phase ~= "Lobby"
		playButton.Visible = queue.phase == "Lobby"
		leaveQueue.Visible = queue.phase == "Queue" or queue.phase == "Countdown"
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
		if garageState.spawned == nil then
			renderGarage()
			garage.setOpen(true)
		end
	end)
	local vehicle = label(counters, "")
	local exit = button(dock, "Leave Vehicle", function()
		context.garage.exit()
	end)
	local function renderVehicle()
		exit.Visible = garageState.spawned ~= nil
		garageButton.Visible = garageState.spawned == nil
		vehicle.Text = if garageState.spawned ~= nil then "Drive: W A S D\nExit: Leave Vehicle" else ""
	end
	context.garage.onStateChanged(function(next)
		garageState = next
		renderVehicle()
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
end

return { mount = mount }
