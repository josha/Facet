--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Inventory = require(ReplicatedStorage.Shared.Hub.Inventory)
local Kit = require(script.Parent.Kit)

export type Context = {
	player: Player,
	playerGui: PlayerGui,
	inventory: Inventory.Client,
}

local function mount(context: Context)
	local api = context.inventory
	local state = api.getState()
	local selectedId: string? = nil
	local pending = false

	local byId: { [string]: Inventory.Definition } = {}
	for _, definition in api.definitions do
		byId[definition.id] = definition
	end

	local screen = Kit.screen(context.playerGui, "InventoryInterface")
	Kit.scale(screen)
	local hud = Kit.hud(screen)
	local openButton = Kit.button("Inventory", "primary")
	openButton.Name = "OpenInventory"
	openButton.Parent = hud

	local modal = Kit.modal(screen, "InventoryPanel", "Inventory", Vector2.new(980, 680))
	modal.hides(openButton)

	local gear = Kit.create("Frame", {
		Name = "Gear",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 56),
		Parent = modal.body,
	}) :: Frame
	local gearLayout = Kit.create("UIGridLayout", {
		CellSize = UDim2.new(0.25, -6, 0, 52),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = gear,
	}) :: UIGridLayout
	local slotLabels: { [string]: TextLabel } = {}
	for index, slot in api.slots do
		local chip = Kit.label("", Kit.size.small, Kit.colors.text, true)
		chip.Name = slot
		chip.AutomaticSize = Enum.AutomaticSize.None
		chip.LayoutOrder = index
		chip.BackgroundTransparency = 0
		chip.BackgroundColor3 = Kit.colors.card
		chip.TextXAlignment = Enum.TextXAlignment.Center
		chip.TextTruncate = Enum.TextTruncate.AtEnd
		Kit.corner(10).Parent = chip
		Kit.padding(6).Parent = chip
		chip.Parent = gear
		slotLabels[slot] = chip
	end

	local content = Kit.create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 1, -64),
		Parent = modal.body,
	}) :: Frame
	local gridHolder = Kit.scroller()
	gridHolder.Name = "Items"
	gridHolder.Parent = content
	local grid = Kit.create("UIGridLayout", {
		CellSize = UDim2.fromOffset(150, 72),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = gridHolder,
	}) :: UIGridLayout

	local details = Kit.create("Frame", {
		Name = "Details",
		BackgroundColor3 = Kit.colors.card,
		Parent = content,
	}, { Kit.corner(12) }) :: Frame
	local detailScroll = Kit.scroller()
	detailScroll.Parent = details
	Kit.padding(Kit.space.medium).Parent = detailScroll
	Kit.list(Enum.FillDirection.Vertical, Kit.space.small).Parent = detailScroll
	local nameLabel = Kit.label("Choose an item", Kit.size.heading, Kit.colors.text, true)
	nameLabel.LayoutOrder = 1
	nameLabel.Parent = detailScroll
	local metaLabel = Kit.label("", Kit.size.body, Kit.colors.muted)
	metaLabel.LayoutOrder = 2
	metaLabel.Parent = detailScroll
	local powerLabel = Kit.label("", Kit.size.body, Kit.colors.text, true)
	powerLabel.LayoutOrder = 3
	powerLabel.Parent = detailScroll
	local descriptionLabel = Kit.label("", Kit.size.body, Kit.colors.text)
	descriptionLabel.LayoutOrder = 4
	descriptionLabel.Parent = detailScroll
	local statusLabel = Kit.label("", Kit.size.body, Kit.colors.primary, true)
	statusLabel.LayoutOrder = 5
	statusLabel.Parent = detailScroll
	local action = Kit.button("Equip", "primary")
	action.Name = "Action"
	action.LayoutOrder = 6
	action.Visible = false
	action.Parent = detailScroll
	local note, show = Kit.message(detailScroll)
	note.LayoutOrder = 7

	local function layout()
		local gearColumns = if modal.body.AbsoluteSize.X < 480 then 2 else 4
		local rows = math.ceil(#api.slots / gearColumns)
		local gearHeight = rows * 52 + (rows - 1) * 8
		gearLayout.CellSize = UDim2.new(1 / gearColumns, -6, 0, 52)
		gear.Size = UDim2.new(1, 0, 0, gearHeight)
		content.Position = UDim2.fromOffset(0, gearHeight + 8)
		content.Size = UDim2.new(1, 0, 1, -(gearHeight + 8))
		local width = content.AbsoluteSize.X
		local stacked = width < 620
		if stacked then
			gridHolder.Size = UDim2.new(1, 0, 0.55, -4)
			details.Position = UDim2.new(0, 0, 0.55, 4)
			details.Size = UDim2.new(1, 0, 0.45, -4)
		else
			gridHolder.Size = UDim2.new(0.6, -6, 1, 0)
			details.Position = UDim2.new(0.6, 6, 0, 0)
			details.Size = UDim2.new(0.4, -6, 1, 0)
		end
		local gridWidth = gridHolder.AbsoluteWindowSize.X
		local columns = math.max(2, math.floor((gridWidth + 8) / 150))
		grid.CellSize = UDim2.fromOffset(math.floor((gridWidth + 8) / columns) - 8, 72)
	end
	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	modal.body:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

	local tiles: { [string]: TextButton } = {}

	local function equippedSlot(id: string): string?
		for slot, item in state.equipped do
			if item == id then
				return slot
			end
		end
		return nil
	end

	local function renderDetails()
		local definition = if selectedId ~= nil then byId[selectedId :: string] else nil
		if definition == nil then
			nameLabel.Text = "Choose an item"
			metaLabel.Text = "Select an item to see its details."
			powerLabel.Text = ""
			descriptionLabel.Text = ""
			statusLabel.Text = ""
			action.Visible = false
			return
		end
		local item = definition :: Inventory.Definition
		nameLabel.Text = item.name
		metaLabel.Text = ("%s %s"):format(item.rarity, item.slot)
		metaLabel.TextColor3 = Kit.colors.rarity[item.rarity] or Kit.colors.muted
		powerLabel.Text = ("Power %d"):format(item.power)
		descriptionLabel.Text = item.description
		local slot = equippedSlot(item.id)
		statusLabel.Text = if slot ~= nil then "Equipped" else ""
		action.Visible = true
		action.Text = if pending then "Saving" elseif slot ~= nil then "Unequip" else "Equip"
		action.BackgroundColor3 = if slot ~= nil then Kit.colors.secondary else Kit.colors.primary
		action.TextColor3 = if slot ~= nil then Kit.colors.secondaryText else Kit.colors.primaryText
		action.Interactable = not pending
	end

	local function renderGear()
		for _, slot in api.slots do
			local id = state.equipped[slot :: Inventory.Slot]
			local name = if id ~= nil and byId[id] ~= nil then byId[id].name else "Empty"
			slotLabels[slot].Text = ("%s\n%s"):format(slot, name)
		end
	end

	local function renderGrid()
		local owned: { [string]: boolean } = {}
		for _, id in state.owned do
			owned[id] = true
		end
		for id, tile in tiles do
			if not owned[id] then
				tile:Destroy()
				tiles[id] = nil
			end
		end
		for order, definition in api.definitions do
			if owned[definition.id] then
				local tile: TextButton? = tiles[definition.id]
				if tile == nil then
					local created = Kit.button("", "ghost")
					created.Name = definition.id
					created.Text = ""
					created.LayoutOrder = order
					local stripe = Kit.create("Frame", {
						Name = "Rarity",
						BackgroundColor3 = Kit.colors.rarity[definition.rarity] or Kit.colors.muted,
						Size = UDim2.new(0, 4, 1, 0),
						Parent = created,
					}) :: Frame
					local _ = stripe
					local title = Kit.label(definition.name, Kit.size.body, Kit.colors.text, true)
					title.Name = "Name"
					title.AutomaticSize = Enum.AutomaticSize.None
					title.Size = UDim2.new(1, -12, 0, 24)
					title.Position = UDim2.fromOffset(12, 0)
					title.TextTruncate = Enum.TextTruncate.AtEnd
					title.TextWrapped = false
					title.Parent = created
					local rarity = Kit.label(definition.rarity, Kit.size.small, Kit.colors.muted)
					rarity.Name = "RarityName"
					rarity.AutomaticSize = Enum.AutomaticSize.None
					rarity.Size = UDim2.new(1, -12, 0, 20)
					rarity.Position = UDim2.fromOffset(12, 26)
					rarity.Parent = created
					local badge = Kit.label("", Kit.size.small, Kit.colors.primary, true)
					badge.Name = "Badge"
					badge.AutomaticSize = Enum.AutomaticSize.None
					badge.Size = UDim2.new(1, -12, 0, 18)
					badge.Position = UDim2.fromOffset(12, 46)
					badge.Parent = created
					created.Activated:Connect(function()
						selectedId = definition.id
						show(nil)
						renderDetails()
						Kit.focus(action)
					end)
					created.Parent = gridHolder
					tiles[definition.id] = created
					tile = created
				end
				local badge = (tile :: TextButton):FindFirstChild("Badge") :: TextLabel
				badge.Text = if equippedSlot(definition.id) ~= nil then "Equipped" else ""
			end
		end
	end

	local function render()
		renderGear()
		renderGrid()
		renderDetails()
	end

	action.Activated:Connect(function()
		if pending or selectedId == nil then
			return
		end
		local id = selectedId :: string
		local slot = equippedSlot(id)
		pending = true
		renderDetails()
		task.spawn(function()
			local ok, result = pcall(function(): Inventory.Result
				if slot ~= nil then
					return api.unequip(slot :: Inventory.Slot)
				end
				return api.equip(id)
			end)
			pending = false
			if not ok then
				show("Could not save. Try again.")
			elseif not result.ok then
				show(if result.reason == "not_owned" then "You do not own this item" else "Could not save. Try again.")
				state = result.state
			else
				state = result.state
				show(nil)
			end
			render()
		end)
	end)

	openButton.Activated:Connect(function()
		state = api.getState()
		render()
		modal.setOpen(true)
		layout()
		local first = if #state.owned > 0 then tiles[state.owned[1]] else nil
		Kit.focus(first)
	end)
	api.onChanged(function(next: Inventory.State)
		state = next
		render()
	end)
	render()
	layout()
end

return {
	mount = mount,
}
