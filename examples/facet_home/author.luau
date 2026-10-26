--!strict

local fs = require("@std/fs")
local Facet = require("../../src")
local Kit = Facet.design()
local Design = Kit.Design
local model = require("./model")

type Literal = Facet.DesignLiteral
type Props = { [string]: Literal }
type Entry = { kind: string?, id: string, props: Props }
type Section = {
	group: string?,
	columns: number?,
	items: { Entry },
	after: ((value: Facet.DesignDocument, body: string) -> Facet.DesignDocument)?,
}

local library = Kit.library({
	UI = {},
	rgb = function(r: number, g: number, b: number): unknown
		return { r, g, b }
	end,
	udim2 = function(a: number, b: number, c: number, d: number): unknown
		return { a, b, c, d }
	end,
	offset = function(x: number, y: number): unknown
		return { 0, x, 0, y }
	end,
})

local output = "examples/facet_home/designs/"

local function author(name: string, build: (value: Facet.DesignDocument) -> Facet.DesignDocument)
	local value = build(Design.document.new(name, library, "Screen"))
	fs.writeStringToFile(output .. name .. ".luau", Design.emit(value, library, { name = name }))
end

local function add(
	value: Facet.DesignDocument,
	parent: string,
	kind: string,
	label: string,
	props: Props
): (Facet.DesignDocument, string)
	local id
	value, id = Design.document.insert(value, library, parent, kind)
	value = Design.document.rename(value, library, id, label)
	for key, item in props do
		value = Design.document.change(value, library, id, key, { literal = item })
	end
	return value, id
end

local function page(title: string, subtitle: string, sections: { Section })
	return function(value: Facet.DesignDocument): Facet.DesignDocument
		local padding: Props = { top = 20, right = 20, bottom = 24, left = 20 }
		local body
		value, body = add(value, "n1", "ScrollView", "Content", {
			height = "fill",
			width = "fill",
			gap = "m",
			padding = padding,
		})
		value = add(value, body, "Text", "Eyebrow", { text = "FACET HOME", textRole = "caption", role = "secondary" })
		value = add(value, body, "Text", "Heading", { text = title, textRole = "title" })
		value = add(value, body, "Text", "Subtitle", { text = subtitle, role = "secondary" })
		for _, section in sections do
			local parent = body
			if section.group then
				value, parent =
					add(value, body, "Grid", section.group, { columns = section.columns or 2, cellHeight = 56 })
			end
			for _, entry in section.items do
				value = add(value, parent, entry.kind or "Button", entry.id, entry.props)
			end
			local after = section.after
			if after then
				value = after(value, body)
			end
		end
		return value
	end
end

local function button(id: string, label: string, appearance: string?): Entry
	return { id = id, props = { label = label, appearance = appearance or "standard" } }
end

local function text(id: string, label: string): Entry
	return { kind = "Text", id = id, props = { text = label } }
end

local function inventory(value: Facet.DesignDocument, body: string): Facet.DesignDocument
	local rowFields: { Facet.DesignItemField } = {
		{ id = "id", type = "string" },
		{ id = "name", type = "string" },
		{ id = "category", type = "string" },
		{ id = "quantity", type = "number" },
		{ id = "finish", type = "string" },
	}
	local preview: { Literal } = {}
	for _, item in model.catalog do
		local row: Props = { id = item.id, name = item.name, category = item.category, quantity = 0, finish = "Sage" }
		table.insert(preview, row)
	end
	value = Design.document.setContract(value, library, {
		inputs = {
			{
				id = "inventoryRows",
				kind = "readable",
				type = "list",
				preview = preview,
				fields = rowFields,
				required = true,
			},
		},
		outputs = {
			{ id = "onChooseFurniture", row = "inventoryRows" },
			{ id = "onPlaceFurniture", row = "inventoryRows" },
		},
	})
	local search: Facet.DesignNode? = nil
	local function find(node: Facet.DesignNode)
		if node.name == "FurnitureSearch" then
			search = node
		end
		for _, child in node.children do
			find(child)
		end
	end
	find(value.root)
	local query: Facet.DesignState = { id = "furnitureQuery", type = "string", initial = "" }
	value = Design.document.setState(value, library, { query })
	value = Design.document.change(value, library, assert(search).id, "value", { state = "furnitureQuery" })
	local list
	value, list = add(value, body, "Table", "FurnitureInventory", { width = "fill", height = 340, itemSize = 76 })
	value = Design.document.bind(value, library, list, { from = "inventoryRows", key = "id" })
	local nameCell, title, caption, quantity, finish
	value, nameCell = add(value, list, "VStack", "FurnitureCell", { gap = "xs" })
	value, title = add(value, nameCell, "Text", "FurnitureName", { textRole = "strong" })
	value = Design.document.change(value, library, title, "text", { item = "name" })
	value, caption = add(value, nameCell, "Text", "FurnitureCategory", { textRole = "caption", role = "secondary" })
	value = Design.document.change(value, library, caption, "text", { item = "category" })
	value, quantity = add(value, list, "Badge", "FurnitureQuantity", {})
	value = Design.document.change(value, library, quantity, "label", { item = "quantity" })
	value, finish = add(value, list, "Text", "FurnitureFinish", { textRole = "caption" })
	value = Design.document.change(value, library, finish, "text", { item = "finish" })
	local function column(id: string, label: string, width: number, cell: string, more: Props): Literal
		local render: Props = { ["$template"] = cell }
		local entry: Props = { id = id, label = label, width = width, render = render }
		for key, item in more do
			entry[key] = item
		end
		return entry
	end
	local nameLimits: Props = { minWidth = 180, priority = "always", sortable = true }
	local quantityLimits: Props = { priority = 2 }
	local finishLimits: Props = { priority = 1 }
	local columns: { Literal } = {
		column("name", "Furniture", 220, nameCell, nameLimits),
		column("quantity", "Placed", 82, quantity, quantityLimits),
		column("finish", "Next finish", 110, finish, finishLimits),
	}
	value = Design.document.change(value, library, list, "columns", { literal = columns })
	value = Design.document.change(value, library, list, "onActivate", { output = "onChooseFurniture" })
	local function action(id: string, label: string, output: string): Literal
		local activate: Props = { ["$output"] = output, ["$row"] = true }
		local entry: Props = { id = id, label = label, onActivate = activate }
		return entry
	end
	local rowActions: Props = {
		trailing = {
			action("choose", "Choose", "onChooseFurniture"),
			action("place", "Place here", "onPlaceFurniture"),
		},
		fullSwipe = false,
	}
	return Design.document.change(value, library, list, "rowActions", { literal = rowActions })
end

author(
	"Home",
	page("Make yourself at home.", "A calm place to create, play, and spend time together.", {
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
)

local slots: { Entry } = {}
for index = 1, model.SLOTS do
	table.insert(slots, { id = "Slot_" .. index, props = { label = "Place " .. index, appearance = "standard" } })
end

author(
	"Furnish",
	page("A room that feels like you.", "Choose a piece. Find its place. Make it yours.", {
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
			},
			after = inventory,
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
)

author(
	"Activities",
	page(
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
)

author(
	"People",
	page(
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
)

author(
	"Settings",
	page("Make yourself comfortable.", "Presentation settings stay available while you build and play.", {
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
)

author(
	"Wall",
	page("Welcome home.", "Create a space that feels like you.", {
		{
			items = {
				text("WallSummary", "Six places for your favorite things."),
				text("WallTip", "Use Home for all actions, or follow the room markers."),
			},
		},
	})
)
