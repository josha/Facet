--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hub = require(ReplicatedStorage.Shared.Hub)
local Crates = require(ReplicatedStorage.Shared.Hub.Crates)
local Kit = require(script.Parent.Kit)

export type Context = {
	player: Player,
	playerGui: PlayerGui,
	crates: Crates.Client,
	hub: Hub.Client,
}

type View = "store" | "confirm" | "reveal" | "collection"

local RARITIES: { Crates.Rarity } = { "Common", "Rare", "Epic", "Legendary" }

local function chance(odds: Crates.Odds, rarity: string): number
	return if rarity == "Common"
		then odds.Common
		elseif rarity == "Rare" then odds.Rare
		elseif rarity == "Epic" then odds.Epic
		else odds.Legendary
end

local function mount(context: Context)
	local api = context.crates
	local state = api.getState()
	local view: View = "store"
	local chosen: Crates.Crate? = nil
	local pending = false
	local drawn: { Crates.Card } = {}
	local revealed = 0

	local screen = Kit.screen(context.playerGui, "CratesInterface")
	Kit.scale(screen)
	local hud = Kit.hud(screen)
	local openButton = Kit.button("Crates", "primary")
	openButton.Name = "OpenCrates"
	openButton.Parent = hud

	local modal = Kit.modal(screen, "CratesPanel", "Crates", Vector2.new(980, 680))
	modal.hides(openButton)

	local function page(name: string): ScrollingFrame
		local frame = Kit.scroller()
		frame.Name = name
		frame.Visible = false
		frame.Parent = modal.body
		Kit.list(Enum.FillDirection.Vertical, Kit.space.medium).Parent = frame
		return frame
	end

	local store = page("Store")
	local reveal = page("Reveal")
	local collection = page("Collection")

	local balance = Kit.label("", Kit.size.heading, Kit.colors.text, true)
	balance.LayoutOrder = 1
	balance.Parent = store
	local storeNote, showStoreNote = Kit.message(store)
	storeNote.LayoutOrder = 2
	local shelf = Kit.create("Frame", {
		Name = "Shelf",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		Parent = store,
	}) :: Frame
	local shelfGrid = Kit.create("UIGridLayout", {
		CellSize = UDim2.new(1 / 3, -8, 0, 260),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = shelf,
	}) :: UIGridLayout
	local collectionButton = Kit.button("Collection", "secondary")
	collectionButton.Name = "Collection"
	collectionButton.LayoutOrder = 4
	collectionButton.Parent = store

	local firstOpen: TextButton? = nil
	local setView: (View) -> ()
	for index, crate in api.crates do
		local card = Kit.card()
		card.Name = crate.id
		card.LayoutOrder = index
		card.AutomaticSize = Enum.AutomaticSize.None
		card.Parent = shelf
		Kit.list(Enum.FillDirection.Vertical, 4).Parent = card
		local title = Kit.label(crate.name, Kit.size.heading, Kit.colors.text, true)
		title.LayoutOrder = 1
		title.Parent = card
		local price = Kit.label(
			("%d Gems  ·  %d cards"):format(crate.price, crate.cards),
			Kit.size.body,
			Kit.colors.primary,
			true
		)
		price.LayoutOrder = 2
		price.Parent = card
		local odds: { string } = {}
		for _, rarity in RARITIES do
			table.insert(odds, ("%s %d%%"):format(rarity, chance(crate.odds, rarity)))
		end
		local oddsLabel = Kit.label(table.concat(odds, "\n"), Kit.size.small, Kit.colors.muted)
		oddsLabel.LayoutOrder = 3
		oddsLabel.Parent = card
		local open = Kit.button("Open", "primary")
		open.Name = "Open"
		open.LayoutOrder = 4
		open.Parent = card
		open.Activated:Connect(function()
			if pending then
				return
			end
			if state.gems < crate.price then
				showStoreNote("Not enough Gems")
				return
			end
			showStoreNote(nil)
			chosen = crate
			setView("confirm")
		end)
		if firstOpen == nil then
			firstOpen = open
		end
	end

	local dialog = Kit.create("Frame", {
		Name = "Confirm",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -32, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Kit.colors.cardRaised,
		Visible = false,
		ZIndex = 20,
		Parent = modal.body,
	}, {
		Kit.corner(14),
		Kit.padding(Kit.space.large),
		Kit.create("UISizeConstraint", { MaxSize = Vector2.new(460, math.huge) }),
		Kit.list(Enum.FillDirection.Vertical, Kit.space.medium),
	}) :: Frame
	dialog.SelectionGroup = true
	local question = Kit.label("", Kit.size.heading, Kit.colors.text, true)
	question.LayoutOrder = 1
	question.Parent = dialog
	local confirmOpen = Kit.button("Open", "primary")
	confirmOpen.Name = "ConfirmOpen"
	confirmOpen.LayoutOrder = 2
	confirmOpen.Parent = dialog
	local cancel = Kit.button("Cancel", "secondary")
	cancel.Name = "Cancel"
	cancel.LayoutOrder = 3
	cancel.Parent = dialog

	local revealTitle = Kit.label("", Kit.size.heading, Kit.colors.text, true)
	revealTitle.LayoutOrder = 1
	revealTitle.Parent = reveal
	local table_ = Kit.create("Frame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = reveal,
	}, {
		Kit.create("UIGridLayout", {
			CellSize = UDim2.fromOffset(150, 120),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame
	local revealButton = Kit.button("Reveal", "primary")
	revealButton.Name = "Reveal"
	revealButton.LayoutOrder = 3
	revealButton.Parent = reveal
	local revealAll = Kit.button("Reveal All", "secondary")
	revealAll.Name = "RevealAll"
	revealAll.LayoutOrder = 4
	revealAll.Parent = reveal
	local done = Kit.button("Done", "primary")
	done.Name = "Done"
	done.LayoutOrder = 5
	done.Parent = reveal

	local progress = Kit.label("", Kit.size.heading, Kit.colors.text, true)
	progress.LayoutOrder = 1
	progress.Parent = collection
	local album = Kit.create("Frame", {
		Name = "Album",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = collection,
	}) :: Frame
	local albumGrid = Kit.create("UIGridLayout", {
		CellSize = UDim2.fromOffset(160, 96),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = album,
	}) :: UIGridLayout
	local back = Kit.button("Back", "secondary")
	back.Name = "Back"
	back.LayoutOrder = 3
	back.Visible = false
	back.Parent = collection

	local function tile(parent: Instance, order: number, title: string, subtitle: string, color: Color3): Frame
		local frame = Kit.create("Frame", {
			LayoutOrder = order,
			BackgroundColor3 = Kit.colors.card,
			Parent = parent,
		}, {
			Kit.corner(12),
			Kit.padding(Kit.space.small),
			Kit.create("UIStroke", { Color = color, Thickness = 2 }),
			Kit.list(Enum.FillDirection.Vertical, 4),
		}) :: Frame
		local name = Kit.label(title, Kit.size.body, Kit.colors.text, true)
		name.LayoutOrder = 1
		name.Parent = frame
		local detail = Kit.label(subtitle, Kit.size.small, Kit.colors.muted, true)
		detail.LayoutOrder = 2
		detail.Parent = frame
		return frame
	end

	local function renderReveal()
		for _, child in table_:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		revealTitle.Text = if pending then "Opening" else ("%d of %d cards"):format(revealed, #drawn)
		for index, card in drawn do
			if index <= revealed then
				tile(table_, index, card.name, card.rarity, Kit.colors.rarity[card.rarity] or Kit.colors.muted)
			else
				tile(table_, index, "Face down", "Press Reveal", Kit.colors.cardRaised)
			end
		end
		local finished = not pending and revealed >= #drawn
		revealButton.Visible = not pending and not finished
		revealAll.Visible = not pending and not finished
		done.Visible = finished
	end

	local function renderCollection()
		for _, child in album:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local owned = 0
		for index, card in api.cards do
			local count = state.collection[card.id] or 0
			if count > 0 then
				owned += 1
				tile(
					album,
					index,
					card.name,
					("%s  x%d"):format(card.rarity, count),
					Kit.colors.rarity[card.rarity] or Kit.colors.muted
				)
			else
				tile(album, index, "???", card.rarity, Kit.colors.cardRaised)
			end
		end
		progress.Text = ("%d / %d cards"):format(owned, #api.cards)
	end

	local function layout()
		local width = modal.body.AbsoluteSize.X
		local columns = if width < 520 then 1 elseif width < 820 then 2 else 3
		shelfGrid.CellSize = UDim2.new(1 / columns, -8, 0, 250)
		local cells = math.max(2, math.floor((width + 8) / 168))
		albumGrid.CellSize = UDim2.fromOffset(math.floor((width + 8) / cells) - 8, 96)
	end
	modal.body:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

	setView = function(next: View)
		view = next
		store.Visible = next == "store"
		dialog.Visible = next == "confirm"
		reveal.Visible = next == "reveal"
		collection.Visible = next == "collection"
		balance.Text = ("%d Gems"):format(state.gems)
		modal.title.Text = if next == "collection" then "Collection" else "Crates"
		modal.close.Visible = true
		modal.close.Text = if next == "store" then "Close" else "Back"
		if next == "confirm" and chosen ~= nil then
			question.Text = ("Open %s for %d Gems?"):format(
				(chosen :: Crates.Crate).name,
				(chosen :: Crates.Crate).price
			)
			if (chosen :: Crates.Crate).id == "starter" and context.hub.getState().crates > 0 then
				question.Text = "Open your free Starter Crate?"
			end
			Kit.focus(confirmOpen)
		elseif next == "reveal" then
			renderReveal()
			Kit.focus(revealButton)
		elseif next == "collection" then
			renderCollection()
			Kit.focus(modal.close)
		else
			Kit.focus(firstOpen)
		end
	end

	local baseSetOpen = modal.setOpen
	modal.setOpen = function(open: boolean, focus: GuiObject?)
		if not open and view ~= "store" and modal.isOpen() then
			setView("store")
		else
			baseSetOpen(open, focus)
		end
	end
	Kit.bindBack(modal, function()
		if view == "store" then
			modal.setOpen(false)
		else
			setView("store")
		end
	end)
	confirmOpen.Activated:Connect(function()
		local crate = chosen
		if pending or crate == nil then
			return
		end
		pending = true
		drawn = {}
		revealed = 0
		setView("reveal")
		task.spawn(function()
			local ok, result = pcall(api.open, (crate :: Crates.Crate).id)
			pending = false
			if ok and result.ok then
				state = result.state
				drawn = result.cards
				setView("reveal")
			else
				if ok then
					state = result.state
				end
				setView("store")
				showStoreNote(if ok and result.reason == "insufficient_funds" then "Not enough Gems" else "Try again")
			end
		end)
	end)
	cancel.Activated:Connect(function()
		chosen = nil
		setView("store")
	end)
	revealButton.Activated:Connect(function()
		revealed = math.min(#drawn, revealed + 1)
		renderReveal()
		if revealed >= #drawn then
			Kit.focus(done)
		end
	end)
	revealAll.Activated:Connect(function()
		revealed = #drawn
		renderReveal()
		Kit.focus(done)
	end)
	done.Activated:Connect(function()
		setView("store")
	end)
	collectionButton.Activated:Connect(function()
		setView("collection")
	end)
	back.Activated:Connect(function()
		setView("store")
	end)
	openButton.Activated:Connect(function()
		state = api.getState()
		showStoreNote(nil)
		modal.setOpen(true, firstOpen)
		layout()
		setView("store")
	end)
	api.onStateChanged(function(next: Crates.State)
		state = next
		balance.Text = ("%d Gems"):format(state.gems)
		if view == "collection" then
			renderCollection()
		end
	end)
	layout()
end

return {
	mount = mount,
}
