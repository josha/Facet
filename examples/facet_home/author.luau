--!strict

local fs, serde = require("@lune/fs"), require("@lune/serde")
local document = require("../../tools/designer/modules/document")
local exporter = require("../../tools/designer/modules/export")
local agent = require("../../tools/designer/modules/agent")
local model = require("./model")
local output = "examples/facet_home/designs/"
local function design(name: string, title: string, subtitle: string, sections: { any })
	local value = document.new(name)
	local function add(parent: string, kind: string, label: string, props: any): string
		local id
		value, id = document.insert(value, parent, kind)
		value = document.change(value, id, "name", label)
		for key, item in props do
			value = document.change(value, id, key, item)
		end
		return id
	end
	local body = add(value.root.id, "ScrollView", "Content", { height = "fill", gap = "m", padding = "m" })
	add(body, "Text", "Eyebrow", { text = "FACET HOME", textRole = "caption", role = "secondary" })
	add(body, "Text", "Heading", { text = title, textRole = "title" })
	add(body, "Text", "Subtitle", { text = subtitle, role = "secondary" })
	for _, entry in sections do
		local parent = body
		if entry.group then
			parent = add(body, "Grid", entry.group, { columns = entry.columns or 2, cellHeight = 56 })
		end
		for _, child in entry.items do
			add(parent, child.kind or "Button", child.id, child.props)
		end
	end
	if name == "Furnish" then
		local inventory
		for _, row in document.rows(value.root) do
			if row.name == "FurnitureInventory" then
				inventory = row.id
			end
		end
		assert(inventory)
		for _, column in { "name", "quantity", "finish" } do
			local cellId
			value, cellId = document.columnTemplate(value, inventory, column)
			local cell = assert(document.find(value.root, cellId))
			if column == "name" then
				local title = cell.children[1].id
				value = document.change(value, title, "textRole", "strong")
				value = document.change(value, title, "name", "FurnitureName")
				local caption
				value, caption = document.insert(value, cellId, "Text")
				value = document.change(value, caption, "name", "FurnitureCategory")
				value = document.change(value, caption, "textField", "category")
				value = document.change(value, caption, "textRole", "caption")
				value = document.change(value, caption, "role", "secondary")
			elseif column == "quantity" then
				value = document.remove(value, cell.children[1].id)
				local badge
				value, badge = document.insert(value, cellId, "Badge")
				value = document.change(value, badge, "labelField", "quantity")
				value = document.change(value, badge, "label", "0")
			else
				value = document.change(value, cell.children[1].id, "textRole", "caption")
			end
		end
	end
	local operations: { any } = {
		{ op = "set", node = "Heading", property = "textRole", value = "title" },
		{
			op = "set",
			node = "Content",
			property = "padding",
			value = { top = 20, right = 20, bottom = 24, left = 20 },
		},
	}
	local code, authored = agent.patch(exporter.component(value), operations, name)
	fs.writeFile(output .. name .. ".luau", code)
	fs.writeFile(
		output .. name .. ".design.json",
		serde.encode("json", { format = "facet-design-file/1", design = authored })
	)
	fs.writeFile(output .. name .. ".operations.json", serde.encode("json", operations))
	fs.writeFile(output .. name .. ".preview.luau", exporter.preview(name, name))
end
local slots = {}
for index = 1, model.SLOTS do
	table.insert(slots, { id = "Slot_" .. index, props = { label = "Place " .. index, appearance = "standard" } })
end
local function button(id: string, label: string, appearance: string?): any
	return { id = id, props = { label = label, appearance = appearance or "standard" } }
end
local function text(id: string, label: string): any
	return { kind = "Text", id = id, props = { text = label, wrap = true } }
end
design("Home", "Make yourself at home.", "A calm place to create, play, and spend time together.", {
	{
		items = {
			text("Welcome", "Your room is ready. Start with something that makes it yours."),
			text("RoomSummary", "6 places. Endless possibilities."),
		},
	},
	{
		items = {
			button("OpenFurnish", "Furnish your home", "emphasis"),
			button("OpenActivities", "Take a little break"),
			button("OpenPeople", "See who is here"),
			button("Explore", "Explore in 3D", "soft"),
		},
	},
	{
		items = {
			text("Project", "HOME PROJECT · Arrange three pieces, then save your room."),
			text("ProjectProgress", "0 / 3 pieces placed"),
		},
	},
})
design("Furnish", "A room that feels like you.", "Choose a piece. Find its place. Make it yours.", {
	{
		items = {
			text("Selection", "Selected: Cloud sofa · Place 1"),
			{
				kind = "TextInput",
				id = "FurnitureSearch",
				props = { placeholder = "Find furniture", clearButton = true },
			},
		},
	},
	{
		items = {
			text("InventoryHeading", "YOUR INVENTORY"),
			text("InventoryHelp", "Select to choose. Swipe or right-click for actions."),
			{
				kind = "Table",
				id = "FurnitureInventory",
				props = {
					width = "fill",
					height = 340,
					itemSize = 76,
					key = "id",
					dataKey = "InventoryRows",
					activationKey = "ChooseFurniture",
					from = (function()
						local rows = {}
						for _, item in model.catalog do
							table.insert(rows, {
								id = item.id,
								name = item.name,
								category = item.category,
								quantity = 0,
								finish = "Sage",
							})
						end
						return rows
					end)(),
					columns = {
						{
							id = "name",
							label = "Furniture",
							width = 220,
							minWidth = 180,
							priority = "always",
							sortable = true,
						} :: any,
						{ id = "quantity", label = "Placed", width = 82, priority = 2 } :: any,
						{ id = "finish", label = "Next finish", width = 110, priority = 1 } :: any,
					},
					rowActions = {
						{ id = "choose", label = "Choose", handler = "ChooseFurniture" },
						{ id = "place", label = "Place here", handler = "PlaceFurniture" },
					},
				},
			},
		},
	},
	{
		items = {
			text("EmptyFurniture", "No furniture matches. Clear your search."),
			text("RoomPlanHeading", "ROOM PLAN · Pick a place"),
		},
	},
	{ group = "RoomPlan", columns = 3, items = slots },
	{ items = { button("Place", "Place selected furniture", "emphasis") } },
	{ group = "EditActions", items = { button("Rotate", "Rotate"), button("Remove", "Remove") } },
	{ items = { text("ColorHeading", "FINISH · Choose a palette") } },
	{
		group = "Palettes",
		items = {
			button("Palette_sage", "Sage"),
			button("Palette_clay", "Clay"),
			button("Palette_cream", "Cream"),
			button("Palette_midnight", "Midnight"),
		},
	},
	{
		group = "SaveActions",
		items = { button("Save", "Save room", "emphasis"), button("Restore", "Restore saved room") },
	},
})
design(
	"Activities",
	"A moment of play.",
	"Follow the four notes: LEAF → SUN → WATER → BLOOM. A wrong note starts the sequence again.",
	{
		{ items = { text("ActivityProgress", "0 / 4 notes"), text("ActivityResult", "Start with LEAF.") } },
		{
			group = "Notes",
			items = {
				button("Note_1", "WATER"),
				button("Note_2", "LEAF"),
				button("Note_3", "BLOOM"),
				button("Note_4", "SUN"),
			},
		},
		{ items = { button("ResetActivity", "Play again"), button("Garden", "Visit the garden", "soft") } },
	}
)
design(
	"People",
	"Better with company.",
	"These are the people in this server. Everyone has their own room. Walk the neighborhood together.",
	{
		{
			items = {
				text("Presence", "Just you here for now."),
				button("ExploreNeighborhood", "Explore the neighborhood", "emphasis"),
			},
		},
	}
)
design("Settings", "Make yourself comfortable.", "Presentation settings stay available while you build and play.", {
	{
		items = {
			button("TogglePalette", "Switch light / dark"),
			button("ToggleText", "Switch regular / larger text"),
			button("ToggleMode", "Switch flat / immersive view"),
			text(
				"Access",
				"Flat mode keeps every room action available. World prompts support keyboard, touch, and controller. Motion follows your device preference."
			),
		},
	},
})
design("Wall", "Welcome home.", "Create a space that feels like you.", {
	{
		items = {
			text("WallSummary", "Six places for your favorite things."),
			text("WallTip", "Use Home for all actions, or follow the room markers."),
		},
	},
})
print("Facet Home designs authored through Facet Design document, export, and agent APIs")
