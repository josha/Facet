--!strict

local document = require("./document")

local function node(id: number, kind: string, name: string, props: any, children: any?): any
	return { id = `n{id}`, kind = kind, name = name, props = props, children = children or {} }
end

local templates = {
	{
		schema = "facet-designer/1",
		name = "Trail companion",
		nextId = 10,
		root = node(1, "Screen", "TrailCompanion", { gap = "m" }, {
			node(2, "Badge", "Season", { label = "YOUR NEXT CHAPTER", status = "success" }),
			node(3, "Text", "Heading", { text = "Find your next adventure.", textRole = "title", wrap = true }),
			node(
				4,
				"Text",
				"Introduction",
				{ text = "A little planning. A lot of possibility.", role = "secondary", wrap = true }
			),
			node(5, "VStack", "Preferences", { gap = "m", padding = "m", width = "fill" }, {
				node(6, "Toggle", "Nearby", { label = "Show nearby trails", value = true }),
				node(
					7,
					"TextInput",
					"Destination",
					{ label = "Where to?", value = "", placeholder = "A place worth exploring", clearButton = true }
				),
				node(8, "Button", "Explore", { label = "Let’s explore", appearance = "emphasis" }),
			}),
			node(9, "Notice", "Tip", {
				title = "Make it yours",
				message = "Select any control to change its content, layout, and style.",
				severity = "info",
			}),
		}),
	},
	{
		schema = "facet-designer/1",
		name = "Player settings",
		nextId = 8,
		root = node(1, "Screen", "Settings", { gap = "m" }, {
			node(2, "Text", "Title", { text = "Your game. Your way.", textRole = "title", wrap = true }),
			node(3, "Text", "VolumeLabel", { text = "Music volume", textRole = "heading" }),
			node(4, "Slider", "Volume", { value = 0.65, min = 0, max = 1 }),
			node(5, "Toggle", "Effects", { label = "Sound effects", value = true }),
			node(6, "Toggle", "Invites", { label = "Allow party invitations", value = false }),
			node(7, "Button", "Save", { label = "Save preferences", appearance = "emphasis" }),
		}),
	},
	document.new("Blank canvas"),
}

local function shapeNode(kind: string, name: string, props: any, children: { any }?): any
	return { kind = kind, name = name, props = props, children = children or {} }
end

local function design(name: string, shape: any)
	local index = 1
	local function build(item: any): any
		local id = index
		index += 1
		local children = {}
		for _, child in item.children do
			table.insert(children, build(child))
		end
		return node(id, item.kind, item.name, item.props, children)
	end
	local root = build(shape)
	table.insert(templates, { schema = "facet-designer/1", name = name, root = root, nextId = index })
end

design(
	"Expedition inventory",
	shapeNode("Screen", "Inventory", { gap = "m" }, {
		shapeNode("HStack", "Player", { gap = "m", align = "center", width = "fill" }, {
			shapeNode("Avatar", "Portrait", { name = "Alex", presence = "online", diameter = 52 }),
			shapeNode("VStack", "PlayerInfo", { gap = "xs", width = "fill" }, {
				shapeNode("Text", "Name", { text = "Alex’s expedition", textRole = "heading" }),
				shapeNode(
					"Text",
					"Capacity",
					{ text = "12 of 24 slots used", role = "secondary", textRole = "caption" }
				),
			}),
		}),
		shapeNode("Text", "Title", { text = "Ready for the wild.", textRole = "title", wrap = true }),
		shapeNode(
			"TextInput",
			"Search",
			{ value = "", placeholder = "Find equipment", presentation = "search", clearButton = true }
		),
		shapeNode("Picker", "Category", {
			selected = "all",
			style = "segmented",
			options = {
				{ value = "all", label = "All" },
				{ value = "gear", label = "Gear" },
				{ value = "supplies", label = "Supplies" },
			},
		}),
		shapeNode("Table", "Items", {
			from = {
				{ id = "compass", label = "Trail compass", count = 1 },
				{ id = "potion", label = "Healing potion", count = 4 },
				{ id = "rope", label = "Climbing rope", count = 2 },
			},
			key = "id",
			columns = {
				{ id = "label", label = "Equipment", width = 210 },
				{ id = "count", label = "Qty", width = 64 },
			},
			itemSize = 48,
			width = 320,
			height = 220,
		}),
		shapeNode("Button", "Equip", { label = "Equip selected item", appearance = "emphasis" }),
	})
)
design(
	"Quest journal",
	shapeNode("Screen", "QuestJournal", { gap = "m" }, {
		shapeNode("Badge", "Chapter", { label = "CHAPTER 04", status = "accent" }),
		shapeNode("Text", "Title", { text = "A new horizon.", textRole = "title", wrap = true }),
		shapeNode("Text", "Intro", { text = "Follow the path. Find your story.", role = "secondary", wrap = true }),
		shapeNode("ProgressView", "Progress", { value = 0.6, label = "Chapter progress", showValue = true }),
		shapeNode("DisclosureGroup", "MainQuest", {
			label = "The missing cartographer",
			description = "Explore the north ridge",
			expanded = true,
			appearance = "contained",
		}, {
			shapeNode("Text", "Task", { text = "Find three survey markers and return to camp.", wrap = true }),
			shapeNode("StepIndicator", "Steps", {
				current = "survey",
				steps = {
					{ id = "camp", label = "Camp" },
					{ id = "survey", label = "Survey" },
					{ id = "return", label = "Return" },
				},
			}),
			shapeNode("Button", "Track", { label = "Track quest", appearance = "soft" }),
		}),
		shapeNode("DisclosureGroup", "SideQuest", {
			label = "A favor for a friend",
			description = "Collect 5 herbs",
			expanded = false,
			appearance = "contained",
		}, {
			shapeNode("Text", "Reward", { text = "Reward: 150 coins", wrap = true }),
		}),
	})
)
design(
	"Party lobby",
	shapeNode("Screen", "PartyLobby", { gap = "m" }, {
		shapeNode("Badge", "Mode", { label = "COOPERATIVE", status = "success" }),
		shapeNode("Text", "Title", { text = "Better together.", textRole = "title", wrap = true }),
		shapeNode("AvatarGroup", "Party", {
			items = {
				{ id = "alex", name = "Alex", presence = "online" },
				{ id = "sam", name = "Sam", presence = "online" },
				{ id = "lee", name = "Lee", presence = "away" },
			},
			layout = "spread",
			diameter = 52,
			max = 4,
		}),
		shapeNode("Text", "Members", { text = "3 of 4 players joined", role = "secondary" }),
		shapeNode("Picker", "Difficulty", {
			selected = "normal",
			style = "cards",
			options = {
				{ value = "normal", label = "Explore", description = "A relaxed expedition" },
				{ value = "hard", label = "Challenge", description = "Every choice matters" },
			},
		}),
		shapeNode("Toggle", "Private", { label = "Friends only", value = true }),
		shapeNode("Button", "Invite", { label = "Invite a friend", appearance = "soft" }),
		shapeNode("Button", "Start", { label = "Start expedition", appearance = "emphasis" }),
	})
)

for _, value in templates do
	document.validate(value)
end

return templates
