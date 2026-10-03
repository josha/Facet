--!strict

local values = require("./value")

local function field(key: string, label: string, kind: string, options: any?): any
	return { key = key, label = label, kind = kind, options = options }
end

local spacing = { "xs", "s", "m", "l", "xl" }
local layout = {
	field("width", "Width", "extent"),
	field("height", "Height", "extent"),
	field("gap", "Spacing", "spacing", spacing),
	field("padding", "Padding", "padding", spacing),
	field("align", "Alignment", "choice", { "start", "center", "end", "stretch" }),
}
local textFields = {
	field("text", "Text", "string"),
	field(
		"textRole",
		"Typography",
		"choice",
		{ "body", "title", "heading", "caption", "label", "strong", "control", "numeral" }
	),
	field("role", "Color role", "choice", { "content", "secondary" }),
	field("wrap", "Wrap text", "boolean"),
	field("textAlign", "Alignment", "choice", { "start", "center", "end" }),
}
local definitions: { [string]: any } = {
	Screen = { category = "Layout", container = true, defaults = { gap = "m" }, fields = layout },
	VStack = {
		category = "Layout",
		container = true,
		defaults = { gap = "s", width = "fill" :: "fill" },
		fields = layout,
	},
	HStack = { category = "Layout", container = true, defaults = { gap = "s" }, fields = layout },
	ZStack = {
		category = "Layout",
		container = true,
		defaults = { width = "fill" :: "fill", height = 160 },
		fields = {
			field("width", "Width", "extent"),
			field("height", "Height", "extent"),
			field("padding", "Padding", "padding", spacing),
			field("alignH", "Horizontal", "choice", { "start", "center", "end" }),
			field("alignV", "Vertical", "choice", { "start", "center", "end" }),
		},
	},
	AdaptiveStack = { category = "Layout", container = true, defaults = { gap = "s" }, fields = layout },
	ScrollView = {
		category = "Layout",
		container = true,
		defaults = { gap = "s", width = "fill" :: "fill", height = 240 },
		fields = layout,
	},
	Grid = {
		category = "Layout",
		container = true,
		defaults = { columns = 2, gap = "s", cellHeight = 72 },
		fields = {
			field("columns", "Columns", "number"),
			field("gap", "Spacing", "spacing", spacing),
			field("cellHeight", "Cell height", "number"),
		},
	},
	Text = {
		category = "Content",
		defaults = { text = "A little possibility", textRole = "body" :: "body", wrap = true },
		fields = textFields,
	},
	Label = {
		category = "Content",
		defaults = { title = "Explore", icon = "settings" },
		fields = { field("title", "Title", "string"), field("icon", "Icon", "string") },
	},
	Image = {
		category = "Content",
		defaults = { image = "rbxassetid://0", width = 240, height = 140, scaleMode = "crop" :: "crop" },
		fields = {
			field("image", "Asset URI", "string"),
			field("width", "Width", "number"),
			field("height", "Height", "number"),
			field("scaleMode", "Framing", "choice", { "fit", "fill", "crop", "stretch", "tile", "slice" }),
		},
	},
	Divider = { category = "Layout", defaults = {}, fields = {} },
	Spacer = {
		category = "Layout",
		defaults = { minLength = 16 },
		fields = { field("minLength", "Minimum length", "number") },
	},
	Button = {
		category = "Input",
		defaults = { label = "Continue", appearance = "emphasis" },
		fields = {
			field("label", "Label", "string"),
			field(
				"appearance",
				"Appearance",
				"choice",
				{ "standard", "emphasis", "soft", "utility", "link", "inverse" }
			),
			field("enabled", "Enabled", "boolean"),
			field("icon", "Icon", "string"),
			field("corners", "Corners", "choice", { "pill", "square" }),
		},
	},
	Toggle = {
		category = "Input",
		state = "value",
		defaults = { label = "Notifications", value = true },
		fields = {
			field("label", "Label", "string"),
			field("value", "Initial value", "boolean"),
			field("presentation", "Presentation", "choice", { "switch", "checkbox" }),
		},
	},
	CellEditor = {
		category = "Collections",
		state = "value",
		defaults = { editor = "text", value = "Name" },
		fields = {
			field("editor", "Editor", "choice", { "text" }),
			field("value", "Initial text", "string"),
			field("label", "Field label", "string"),
		},
	},
	TextInput = {
		category = "Input",
		state = "value",
		defaults = { value = "", placeholder = "Your name" },
		fields = {
			field("value", "Initial text", "string"),
			field("placeholder", "Placeholder", "string"),
			field("label", "Field label", "string"),
			field("hint", "Hint", "string"),
			field("multiline", "Multiline", "boolean"),
			field("clearButton", "Clear button", "boolean"),
		},
	},
	NumberInput = {
		category = "Input",
		state = "numericValue",
		defaults = { numericValue = 3, min = 0, max = 100 },
		fields = {
			field("numericValue", "Initial value", "number"),
			field("min", "Minimum", "number"),
			field("max", "Maximum", "number"),
			field("step", "Step", "number"),
		},
	},
	Slider = {
		category = "Input",
		state = "value",
		defaults = { value = 0.65, min = 0, max = 1 },
		fields = {
			field("value", "Initial value", "number"),
			field("min", "Minimum", "number"),
			field("max", "Maximum", "number"),
			field("step", "Step", "number"),
		},
	},
	Stepper = {
		category = "Input",
		state = "value",
		defaults = { value = 3, min = 0, max = 10 },
		fields = {
			field("value", "Initial value", "number"),
			field("min", "Minimum", "number"),
			field("max", "Maximum", "number"),
			field("step", "Step", "number"),
		},
	},
	Rating = {
		category = "Input",
		state = "value",
		defaults = { value = 4, count = 5 },
		fields = { field("value", "Initial value", "number"), field("count", "Stars", "number") },
	},
	Chip = {
		category = "Input",
		state = "selected",
		defaults = { label = "Adventure", selected = false },
		fields = {
			field("label", "Label", "string"),
			field("icon", "Icon", "string"),
			field("selected", "Selected", "boolean"),
		},
	},
	Badge = {
		category = "Status",
		defaults = { label = "NEW", status = "success" },
		fields = {
			field("label", "Label", "string"),
			field("status", "Status", "choice", { "neutral", "info", "success", "warning", "error", "accent" }),
		},
	},
	ProgressView = {
		category = "Status",
		defaults = { value = 0.65, label = "Getting ready", presentation = "bar" :: "bar" },
		fields = {
			field("value", "Progress", "number"),
			field("label", "Label", "string"),
			field("presentation", "Presentation", "choice", { "bar", "circular", "spinner" }),
		},
	},
	Notice = {
		category = "Status",
		defaults = {
			title = "You’re all set",
			message = "Small details make a big difference.",
			severity = "success",
		},
		fields = {
			field("title", "Title", "string"),
			field("message", "Message", "string"),
			field("severity", "Severity", "choice", { "info", "success", "warning", "error" }),
		},
	},
	StatusIndicator = {
		category = "Status",
		defaults = { status = "success", name = "Online" },
		fields = {
			field("name", "Label", "string"),
			field("status", "Status", "choice", { "neutral", "info", "success", "warning", "error", "accent" }),
			field("form", "Shape", "choice", { "dot", "ring", "square", "dash" }),
		},
	},
}

local function add(name: string, category: string, defaults: any, fields: any, options: any?)
	local definition = options or {}
	definition.category, definition.defaults, definition.fields = category, defaults, fields
	definitions[name] = definition
end
local function choice(key, label, options)
	return field(key, label, "choice", options)
end
local function number(key, label)
	return field(key, label, "number")
end
local function text(key, label)
	return field(key, label, "string")
end
local function flag(key, label)
	return field(key, label, "boolean")
end
local function json(key, label)
	return field(key, label, "json")
end
local sizes = { "xsmall", "compact", "regular", "large" }
local options = { { value = "first", label = "First option" }, { value = "second", label = "Second option" } }
local items = { { id = "first", label = "Explore" }, { id = "second", label = "Save for later" } }
local pages = { { id = "first", label = "Discover" }, { id = "second", label = "Favorites" } }
local seed = { { kind = "Text" :: "Text", props = { text = "Make this content yours", wrap = true } } }
add(
	"ViewThatFits",
	"Layout",
	{ width = "fill" :: "fill", height = 80 },
	{ field("width", "Width", "extent"), field("height", "Height", "extent") },
	{ container = true, seeds = seed }
)
add(
	"ErrorBoundary",
	"Layout",
	{ width = "fill" :: "fill" },
	{ field("width", "Width", "extent") },
	{ container = true, seeds = seed }
)
add("Composition", "Layout", { gap = "m", padding = "m" }, {
	field("gap", "Gap", "spacing", spacing),
	field("padding", "Padding", "padding", spacing),
	flag("topbar", "Top bar"),
}, {
	container = true,
	seeds = { { kind = "Region" :: "Region", props = { zone = "center", rank = 1 }, children = seed } },
})
add("Region", "Layout", { zone = "center", rank = 1 }, {
	choice(
		"zone",
		"Zone",
		{ "topLeft", "top", "topRight", "left", "center", "right", "bottomLeft", "bottom", "bottomRight", "topbar" }
	),
	number("rank", "Priority"),
	flag("mayDrop", "May drop"),
	flag("reveal", "Reveal"),
}, { container = true, seeds = seed })
add("LevelPicker", "Input", {
	value = 3,
	count = 5,
	segment = "bar",
	images = { filled = "rbxassetid://108245103349446", empty = "rbxassetid://73716910467356" },
	glyphs = { filled = "★", empty = "☆" },
}, {
	number("value", "Initial value"),
	number("count", "Segments"),
	choice("segment", "Segment", { "bar", "glyph", "image" }),
	json("images", "Segment images"),
	json("glyphs", "Segment glyphs"),
	flag("allowZero", "Allow zero"),
}, { state = "value" })
add("ShortcutHint", "Input", { keys = { { "Ctrl", "S" } }, label = "Save" }, {
	json("keys", "Key combinations"),
	text("label", "Label"),
	choice("labelPosition", "Label position", { "start", "end" }),
})
add("ColorPicker", "Input", { value = "#3B82F6", label = "Accent color", style = "automatic" :: "automatic" }, {
	field("value", "Initial color", "color"),
	text("label", "Label"),
	choice("style", "Presentation", { "automatic", "inline" }),
	flag("draft", "Apply and cancel"),
	number("alpha", "Alpha"),
	flag("readOnly", "Read only"),
	json("modes", "Modes"),
}, { state = "value" })
add("DateTimePicker", "Input", {
	value = { year = 2026, month = 9, day = 30, hour = 0, minute = 0 },
	label = "Date",
	style = "automatic" :: "automatic",
}, {
	json("value", "Initial civil date"),
	text("label", "Label"),
	choice("style", "Presentation", { "automatic", "inline" }),
	flag("time", "Include time"),
	flag("draft", "Apply and cancel"),
	number("minuteStep", "Minute step"),
	number("weekStart", "Week starts"),
	json("min", "Earliest date"),
	json("max", "Latest date"),
}, { state = "value" })
add("Picker", "Navigation", { selected = "first", options = options, style = "segmented" :: "segmented" }, {
	text("selected", "Initial selection"),
	json("options", "Options"),
	choice(
		"style",
		"Presentation",
		{ "automatic", "menu", "navigationLink", "segmented", "inline", "radioGroup", "cards" }
	),
	text("label", "Label"),
	text("placeholder", "Placeholder"),
	choice("axis", "Axis", { "x", "y" }),
	choice("sizing", "Sizing", { "fill", "hug" }),
}, { state = "selected" })
add("Menu", "Navigation", { label = "Actions", items = items }, {
	text("label", "Label"),
	json("items", "Menu items"),
	choice("presentation", "Presentation", { "automatic", "menu", "sheet" }),
	choice("edge", "Edge", { "top", "bottom", "leading", "trailing" }),
	number("maxHeight", "Maximum height"),
})
add(
	"RadialMenu",
	"Navigation",
	{ label = "Actions", items = items, preset = "donut" :: "donut", appearance = "wedges", isPresented = false },
	{
		text("label", "Label"),
		json("items", "Radial items"),
		choice("preset", "Preset", { "donut", "top-left", "top-right", "bottom-left", "bottom-right" }),
		choice("appearance", "Appearance", { "wedges", "buttons" }),
		choice("distribution", "Distribution", { "even", "compass" }),
		flag("isPresented", "Presented"),
		choice("scrim", "Scrim", { "dark", "light", "none" }),
	},
	{ state = "isPresented" }
)
add("SplitButton", "Navigation", { label = "Continue", items = items }, {
	text("label", "Label"),
	json("items", "Menu items"),
	text("menuLabel", "Menu label"),
	flag("enabled", "Enabled"),
	flag("busy", "Busy"),
})
add(
	"ComboBox",
	"Navigation",
	{ value = "first", text = "First option", options = options, placeholder = "Choose or type" },
	{
		text("value", "Initial value"),
		text("text", "Initial text"),
		json("options", "Options"),
		text("placeholder", "Placeholder"),
		flag("commitOnFocusLost", "Commit on blur"),
	},
	{ states = { "value", "text" } }
)
add("DisclosureGroup", "Navigation", { label = "More details", expanded = true, appearance = "contained" }, {
	text("label", "Label"),
	text("description", "Description"),
	flag("expanded", "Expanded"),
	choice("appearance", "Appearance", { "plain", "contained", "divided", "outline" }),
	choice("chevronPosition", "Chevron position", { "leading", "trailing" }),
}, { state = "expanded", container = true, seeds = seed, content = "content" })
add("CollapsibleView", "Navigation", { label = "Expand content", expanded = false }, {
	text("label", "Label"),
	flag("expanded", "Expanded"),
	flag("dismissButton", "Dismiss button"),
	choice("appearance", "Appearance", { "standard", "emphasis", "soft", "utility" }),
}, { state = "expanded", container = true, seeds = seed, content = "content" })
add("TabView", "Navigation", { selection = "first", tabs = pages, placement = "topBar" :: "topBar" }, {
	text("selection", "Initial tab"),
	json("tabs", "Tabs"),
	choice("placement", "Placement", { "automatic", "topBar", "sidebar", "bottomBar", "bottomBarCompact", "none" }),
	choice("style", "Style", { "automatic", "sidebarAdaptable", "collapsible" }),
	choice("retention", "Retention", { "all", "top" }),
	flag("restoreScroll", "Restore scroll"),
	flag("restoreFocus", "Restore focus"),
}, { state = "selection", container = true, seeds = seed })
add("PageView", "Navigation", { selection = "first", pages = pages, indicators = true, controls = true }, {
	text("selection", "Initial page"),
	json("pages", "Pages"),
	flag("indicators", "Indicators"),
	flag("controls", "Navigation controls"),
	flag("summary", "Summary"),
}, { state = "selection", container = true, seeds = seed })
add(
	"NavigationStack",
	"Navigation",
	{ path = {}, root = { title = "Home" }, destinations = { details = { title = "Details" } } },
	{
		json("path", "Initial route"),
		json("root", "Root page"),
		json("destinations", "Destinations"),
		text("backLabel", "Back label"),
	},
	{ state = "path", container = true, seeds = seed }
)
add("Pagination", "Navigation", { page = 1, pageCount = 8, form = "numbers" }, {
	number("page", "Initial page"),
	number("pageCount", "Page count"),
	choice("form", "Presentation", { "numbers", "arrows", "label" }),
	number("siblingCount", "Sibling count"),
	number("boundaryCount", "Boundary count"),
	flag("showFirstLast", "First and last"),
}, { state = "page" })
add("StepIndicator", "Navigation", {
	current = "first",
	steps = {
		{ id = "first", label = "Choose" },
		{ id = "second", label = "Review" },
		{ id = "third", label = "Finish" },
	},
}, {
	text("current", "Current step"),
	json("steps", "Steps"),
	choice("sizing", "Sizing", { "fill", "hug" }),
	text("listLabel", "Accessible label"),
}, { state = "current" })
add("Vote", "Input", { value = "none", summary = "Was this helpful?" }, {
	choice("value", "Initial vote", { "up", "down", "none" }),
	text("summary", "Summary"),
	flag("readOnly", "Read only"),
}, { state = "value" })
add("Card", "Content", {
	title = "A place worth discovering",
	caption = "Your next adventure starts here.",
	image = "rbxassetid://0",
	imageAspectRatio = 1.6,
}, {
	text("title", "Title"),
	text("caption", "Caption"),
	text("image", "Image URI"),
	number("imageAspectRatio", "Artwork ratio"),
	choice("imageFraming", "Image framing", { "fit", "crop" }),
	choice("reveal", "Reveal", { "automatic", "always" }),
	flag("enabled", "Enabled"),
}, { container = true, content = "artwork" })
add("Path", "Content", {
	points = {
		{ x = 0, y = 1, inX = 0, inY = 1, outX = 0, outY = 1 },
		{ x = 1, y = 0, inX = 1, inY = 0, outX = 1, outY = 0 },
	},
	width = 240,
	height = 100,
	thickness = 2,
}, {
	json("points", "Bezier points"),
	number("width", "Width"),
	number("height", "Height"),
	number("thickness", "Thickness"),
	flag("closed", "Closed path"),
	choice("role", "Color role", { "content", "secondary", "accent" }),
})
add("Skeleton", "Content", { form = "line", lines = 3 }, {
	choice("form", "Form", { "box", "circle", "line" }),
	number("lines", "Lines"),
	choice("controlSize", "Size", sizes),
})
add(
	"AsyncImage",
	"Content",
	{ source = "rbxassetid://0", failureLabel = "Image unavailable", width = 240, height = 140 },
	{
		text("source", "Image URI"),
		text("failureLabel", "Failure label"),
		flag("dimmed", "Dimmed"),
		number("width", "Width"),
		number("height", "Height"),
		json("imageProperties", "Image properties"),
	},
	{ nativeSize = true }
)
add("Avatar", "Content", { name = "Alex", presence = "online", diameter = 52 }, {
	text("name", "Name"),
	text("image", "Image URI"),
	number("userId", "User ID"),
	choice("presence", "Presence", { "online", "away", "busy", "offline", "inExperience" }),
	number("diameter", "Diameter"),
	flag("presenceMark", "Presence mark"),
	choice("form", "Form", { "standard", "icon" }),
	text("icon", "Icon"),
})
add("AvatarGroup", "Content", {
	items = { { id = "alex", name = "Alex" }, { id = "sam", name = "Sam" }, { id = "jo", name = "Jo" } },
	max = 3,
	diameter = 40,
}, {
	json("items", "People"),
	number("max", "Maximum visible"),
	number("diameter", "Diameter"),
	choice("layout", "Layout", { "stacked", "spread" }),
	choice("overflow", "Overflow", { "count", "ellipsis" }),
})
add("Stage", "Content", { fieldOfView = 45, width = 240, height = 180 }, {
	number("fieldOfView", "Field of view"),
	number("width", "Width"),
	number("height", "Height"),
	flag("lazy", "Lazy rendering"),
}, { nativeSize = true })
add("VirtualList", "Collections", {
	from = {
		{ id = "one", label = "First item" },
		{ id = "two", label = "Second item" },
		{ id = "three", label = "Third item" },
	},
	key = "id",
	itemSize = 44,
	gap = 6,
	width = 320,
	height = 220,
}, {
	json("from", "Rows"),
	text("key", "Identity field"),
	number("itemSize", "Row height"),
	number("gap", "Gap"),
	number("overscan", "Overscan"),
	choice("selectionMode", "Selection mode", { "none", "single", "multiple" }),
	flag("reorderable", "Reorder rows"),
	flag("deletable", "Delete rows"),
	number("width", "Width"),
	number("height", "Height"),
}, { nativeSize = true })
add("VirtualGrid", "Collections", {
	from = {
		{ id = "one", label = "First item" },
		{ id = "two", label = "Second item" },
		{ id = "three", label = "Third item" },
	},
	key = "id",
	itemSize = 80,
	columns = 2,
	gap = 6,
	width = 320,
	height = 220,
}, {
	json("from", "Items"),
	text("key", "Identity field"),
	number("itemSize", "Cell height"),
	number("columns", "Columns"),
	number("gap", "Gap"),
	number("crossGap", "Column gap"),
	choice("selectionMode", "Selection mode", { "none", "single", "multiple" }),
	number("width", "Width"),
	number("height", "Height"),
}, { nativeSize = true })
add("Table", "Collections", {
	from = { { id = "one", label = "First item", score = 120 }, { id = "two", label = "Second item", score = 95 } },
	key = "id",
	columns = { { id = "label", label = "Player", width = 160 }, { id = "score", label = "Score", width = 100 } },
	itemSize = 44,
	width = 320,
	height = 240,
}, {
	json("from", "Rows"),
	json("columns", "Columns"),
	text("key", "Identity field"),
	number("itemSize", "Row height"),
	number("headerHeight", "Header height"),
	flag("header", "Show header"),
	flag("alternatingRows", "Alternating rows"),
	number("width", "Width"),
	number("height", "Height"),
}, { nativeSize = true })
add("RowActions", "Collections", {
	trailing = {
		{ id = "archive", label = "Archive" },
		{ id = "delete", label = "Delete", role = "destructive" :: "destructive" },
	},
}, {
	json("leading", "Leading actions"),
	json("trailing", "Trailing actions"),
	number("actionWidth", "Action width"),
	flag("fullSwipe", "Full swipe"),
	flag("editing", "Editing"),
}, { container = true, content = "content", seeds = seed })
add("Alert", "Overlays", {
	isPresented = true,
	title = "Ready to continue?",
	message = "Make this moment yours.",
	severity = "information",
	actions = { { id = "okay", label = "Continue" } },
}, {
	flag("isPresented", "Presented"),
	text("title", "Title"),
	text("message", "Message"),
	json("actions", "Actions"),
	choice("severity", "Severity", { "information", "warning", "critical" }),
	choice("surface", "Surface", { "dialog", "fullScreen" }),
	number("maxWidth", "Maximum width"),
}, { state = "isPresented" })
add("Sheet", "Overlays", { isPresented = true, detent = "medium", title = "A little more detail" }, {
	flag("isPresented", "Presented"),
	text("title", "Title"),
	choice("detent", "Initial detent", { "medium", "large", "hug" }),
	json("detents", "Available detents"),
	choice("placement", "Placement", { "automatic", "adaptive", "bottom", "side", "center" }),
	flag("interactiveDismissDisabled", "Disable dismissal"),
	choice("dragIndicator", "Drag indicator", { "automatic", "visible", "hidden" }),
}, { states = { "isPresented", "detent" }, container = true, content = "content", seeds = seed })
add(
	"Dialog",
	"Overlays",
	{ isPresented = true, title = "Make it yours", closeButton = true, actionLabel = "Continue" },
	{
		flag("isPresented", "Presented"),
		text("title", "Title"),
		text("actionLabel", "Action label"),
		flag("closeButton", "Close button"),
		choice("width", "Width", { "automatic", "narrow", "wide" }),
		choice("actionLayout", "Action layout", { "automatic", "row", "stacked" }),
	},
	{ state = "isPresented", container = true, content = "content", seeds = seed }
)
add(
	"Popover",
	"Overlays",
	{ isPresented = false, title = "Details", anchorLabel = "Show details", edge = "bottom" :: "bottom", tail = true },
	{
		flag("isPresented", "Presented"),
		text("title", "Title"),
		text("anchorLabel", "Trigger label"),
		choice("edge", "Edge", { "top", "bottom", "leading", "trailing" }),
		choice("align", "Alignment", { "start", "center", "end" }),
		flag("tail", "Tail"),
		number("gap", "Gap"),
		choice("compact", "Compact form", { "sheet", "popover" }),
	},
	{ state = "isPresented", container = true, content = "content", seeds = seed, anchor = "trigger" :: "trigger" }
)
add(
	"Callout",
	"Overlays",
	{ isPresented = true, title = "A new possibility", anchorLabel = "Explore", closeButton = true },
	{
		flag("isPresented", "Presented"),
		text("title", "Title"),
		text("anchorLabel", "Anchor label"),
		flag("closeButton", "Close button"),
		choice("edge", "Edge", { "top", "bottom" }),
		choice("align", "Alignment", { "leading", "center", "trailing" }),
	},
	{ state = "isPresented", container = true, content = "content", seeds = seed, anchor = "anchor" :: "anchor" }
)
add("Toast", "Overlays", {
	message = "Saved. You’re all set.",
	isPresented = true,
	duration = 0,
	closeButton = true,
	action = { label = "Done" },
}, {
	text("message", "Message"),
	json("action", "Action"),
	flag("isPresented", "Presented"),
	number("duration", "Duration"),
	flag("closeButton", "Close button"),
	choice("position", "Position without action", { "top", "bottom" }),
	choice("width", "Width without action", { "fill", "hug" }),
	flag("fade", "Fade"),
}, { state = "isPresented" })
add("NavBar", "Navigation", { title = "Discover", backLabel = "Back", surface = "pane" }, {
	text("title", "Title"),
	text("backLabel", "Back label"),
	choice("surface", "Surface", { "surface", "panel", "pane" }),
	number("gap", "Gap"),
	number("padding", "Padding"),
})

local function extend(names: { string }, fields: { any })
	for _, name in names do
		local definition = definitions[name]
		definition.fields = table.clone(definition.fields)
		for _, item in fields do
			local found = false
			for _, existing in definition.fields do
				found = found or existing.key == item.key
			end
			if not found then
				table.insert(definition.fields, table.clone(item))
			end
		end
	end
end
local all = {}
for name in definitions do
	table.insert(all, name)
end
extend(all, {
	field("BackgroundColor3", "Background color", "color"),
	number("BackgroundTransparency", "Background transparency"),
	flag("Visible", "Visible"),
	number("Rotation", "Rotation"),
	flag("ClipsDescendants", "Clip contents"),
	number("LayoutOrder", "Layout order"),
})
extend(
	{ "Screen", "VStack", "HStack", "ZStack", "ScrollView", "Grid", "AdaptiveStack", "ViewThatFits", "ErrorBoundary" },
	{
		field("width", "Width", "extent"),
		field("height", "Height", "extent"),
		number("maxWidth", "Maximum width"),
	}
)
extend({ "Screen", "VStack", "HStack", "ScrollView", "AdaptiveStack" }, {
	choice("distribute", "Distribution", { "start", "center", "end", "spaceBetween", "spaceAround", "spaceEvenly" }),
})
extend({ "VStack", "HStack" }, { flag("wrap", "Wrap children") })
extend({ "AdaptiveStack" }, { choice("axis", "Axis", { "x", "y" }) })
extend(
	{ "ScrollView" },
	{ choice("axis", "Scroll axis", { "x", "y", "xy" }), number("ScrollBarThickness", "Scroll bar width") }
)
extend({ "Grid" }, {
	field("padding", "Padding", "padding", spacing),
	field("rowGap", "Row spacing", "spacing", spacing),
	number("aspectRatio", "Cell aspect ratio"),
	choice("flow", "Flow", { "row", "column" }),
	choice("align", "Alignment", { "start", "center", "end" }),
})
extend({ "Divider" }, {
	choice("axis", "Axis", { "x", "y" }),
	number("thickness", "Thickness"),
	choice("appearance", "Appearance", { "standard", "strong" }),
})
extend({ "Text" }, {
	choice("truncate", "Truncation", { "end", "middle" }),
	number("textSize", "Text size"),
	number("lines", "Maximum lines"),
	flag("rich", "Rich text"),
	choice("direction", "Text direction", { "auto", "ltr", "rtl" }),
	field("tint", "Text color", "color"),
})
extend({ "Label" }, {
	choice("presentation", "Presentation", { "titleAndIcon", "titleOnly", "iconOnly" }),
	number("iconSize", "Icon size"),
	number("textSize", "Text size"),
	field("gap", "Spacing", "spacing", spacing),
	choice("iconPosition", "Icon position", { "leading", "trailing" }),
})
extend({ "Image" }, {
	field("tint", "Image tint", "color"),
	choice("resample", "Sampling", { "default", "pixelated" }),
	choice("shape", "Shape", { "rect", "circle" }),
	json("tileSize", "Tile size"),
	json("sliceCenter", "Slice center"),
	number("sliceScale", "Slice scale"),
})
extend({ "Button", "Toggle", "Chip" }, {
	text("subtitle", "Subtitle"),
	text("hint", "Hint"),
	text("trailingIcon", "Trailing icon"),
	text("image", "Image URI"),
	number("imageAspectRatio", "Image ratio"),
	choice("imageFraming", "Image framing", { "fit", "crop" }),
	text("compactLabel", "Compact label"),
	flag("busy", "Busy"),
	flag("enabled", "Enabled"),
	choice("shape", "Shape", { "rect", "circle" }),
	choice("role", "Role", { "default", "cancel", "destructive", "onIndicator" }),
	flag("disclose", "Disclosure indicator"),
	number("textSize", "Text size"),
	text("help", "Help"),
	json("row", "Row content"),
})
extend(
	{ "Toggle" },
	{ flag("mixed", "Mixed value"), choice("indicatorPosition", "Indicator position", { "leading", "trailing" }) }
)
extend({ "TextInput", "NumberInput", "ColorPicker", "DateTimePicker" }, {
	flag("enabled", "Enabled"),
	flag("readOnly", "Read only"),
	text("hint", "Hint"),
	text("errorText", "Error text"),
	choice("requiredMark", "Requirement", { "required", "optional" }),
	choice("appearance", "Appearance", { "standard", "contrast", "utility" }),
	choice("corners", "Corners", { "pill", "square" }),
})
extend({ "TextInput", "NumberInput" }, {
	text("label", "Label"),
	text("placeholder", "Placeholder"),
	flag("multiline", "Multiline"),
	number("visibleLines", "Visible lines"),
	number("maxLength", "Maximum length"),
	flag("clearButton", "Clear button"),
	choice("clearButtonMode", "Clear button mode", { "never", "always", "whileEditing", "unlessEditing" }),
	choice("selectOnFocus", "Select on focus", { "none", "all", "end" }),
})
extend({ "TextInput" }, { choice("presentation", "Presentation", { "plain", "search" }) })
extend({ "NumberInput" }, {
	number("precision", "Precision"),
	flag("stepButtons", "Step buttons"),
	text("prefix", "Prefix"),
	text("suffix", "Suffix"),
	flag("scrub", "Scrub"),
})
extend({ "Slider" }, {
	flag("enabled", "Enabled"),
	text("label", "Label"),
	flag("tapToPosition", "Tap to set"),
	choice("axis", "Axis", { "x", "y" }),
	choice("thumb", "Thumb", { "always", "auto", "none" }),
	flag("contained", "Contained"),
	number("rotation", "Rotation"),
	text("thumbImage", "Thumb image"),
	text("trackImage", "Track image"),
})
extend({ "Stepper" }, {
	flag("enabled", "Enabled"),
	text("label", "Label"),
	number("repeatDelay", "Repeat delay"),
	number("repeatInterval", "Repeat interval"),
})
extend(
	{ "Rating", "LevelPicker" },
	{ flag("readOnly", "Read only"), flag("enabled", "Enabled"), flag("allowZero", "Allow zero") }
)
extend({ "Rating" }, { json("glyphs", "Star glyphs"), choice("starSize", "Star size", { "small", "medium", "large" }) })
extend({ "LevelPicker" }, { choice("segmentSize", "Segment size", { "small", "medium", "large" }) })
extend({ "ProgressView" }, {
	number("min", "Minimum"),
	number("max", "Maximum"),
	text("endLabel", "End label"),
	flag("showValue", "Show value"),
	number("diameter", "Diameter"),
	number("thickness", "Thickness"),
	number("segments", "Segments"),
	json("trail", "Progress trail"),
})
extend({ "Badge" }, {
	text("icon", "Icon"),
	choice("iconPosition", "Icon position", { "leading", "trailing" }),
	choice("appearance", "Appearance", { "standard", "status", "utility" }),
})
extend(
	{ "StatusIndicator" },
	{ number("count", "Count"), number("max", "Maximum"), number("diameter", "Diameter"), flag("cutout", "Cutout") }
)
extend(
	{ "Avatar" },
	{ text("presenceLabel", "Presence label"), flag("backplate", "Backplate"), text("background", "Background role") }
)
extend({ "AvatarGroup" }, { choice("form", "Form", { "standard", "icon" }), text("overflowLabel", "Overflow label") })
extend({ "Path" }, { field("tint", "Path color", "color") })
extend({ "Popover" }, {
	number("crossOffset", "Cross offset"),
	number("maxWidth", "Maximum width"),
	number("maxHeight", "Maximum height"),
	flag("modal", "Modal"),
	choice("cancelPolicy", "Cancel policy", { "dismiss", "none" }),
})
extend(
	{ "Dialog" },
	{ json("actions", "Actions"), flag("contentSelectable", "Selectable content"), json("hero", "Hero image") }
)
extend({ "Notice" }, {
	choice("appearance", "Appearance", { "standard", "emphasis" }),
	choice("placement", "Placement", { "inline", "affixed" }),
	json("actions", "Actions"),
})
extend({ "Toast" }, {
	text("icon", "Icon"),
	text("key", "Identity"),
	number("priority", "Priority"),
	number("readFloor", "Reading time"),
})
extend({ "Card" }, {
	json("primaryAction", "Primary action"),
	json("menu", "Menu"),
	choice("ringTarget", "Focus ring target", { "card", "media" }),
})
extend({
	"Pagination",
	"StepIndicator",
	"Vote",
	"Button",
	"Toggle",
	"Chip",
	"TextInput",
	"NumberInput",
	"ColorPicker",
	"DateTimePicker",
	"Slider",
	"Badge",
	"StatusIndicator",
	"Avatar",
	"AvatarGroup",
	"ShortcutHint",
	"ProgressView",
	"Notice",
}, { choice("controlSize", "Control size", sizes) })
extend({ "Pagination", "StepIndicator" }, { flag("enabled", "Enabled") })

extend({ "Picker" }, {
	flag("required", "Required"),
	flag("enabled", "Enabled"),
	flag("iconOnly", "Icons only"),
	number("textSize", "Text size"),
	number("maxHeight", "Maximum height"),
	choice("indicator", "Indicator", { "automatic", "pill", "underline", "none" }),
	choice("indicatorPosition", "Indicator position", { "leading", "trailing" }),
	choice("valueAlignment", "Value alignment", { "start", "end" }),
	text("hint", "Hint"),
	text("errorText", "Error text"),
	choice("controlSize", "Control size", sizes),
})
extend({ "Menu" }, {
	flag("disclosure", "Disclosure indicator"),
	flag("enabled", "Enabled"),
	text("backLabel", "Back label"),
	choice("align", "Alignment", { "start", "center", "end" }),
	number("width", "Menu width"),
	json("triggers", "Open gestures"),
})
extend({ "ComboBox", "DisclosureGroup" }, { flag("enabled", "Enabled") })
extend(
	{ "DisclosureGroup" },
	{ text("icon", "Icon"), number("textSize", "Text size"), field("indent", "Indent", "spacing", spacing) }
)
extend({ "TabView" }, {
	number("railWidth", "Sidebar width"),
	choice("sidebarPreference", "Sidebar preference", { "automatic", "topBar", "sidebar" }),
	choice("shoulderNavigation", "Shoulder navigation", { "strip", "content" }),
	choice("indicator", "Indicator", { "automatic", "pill", "underline", "none" }),
	flag("iconOnly", "Icons only"),
	number("textSize", "Text size"),
	choice("controlSize", "Control size", sizes),
	flag("enabled", "Enabled"),
	json("sections", "Sections"),
	json("customization", "Tab customization"),
})
extend({ "Sheet" }, {
	choice("edge", "Side edge", { "left", "right" }),
	choice("width", "Width", { "automatic", "narrow", "wide" }),
	flag("closeButton", "Close button"),
	choice("actionLayout", "Action layout", { "automatic", "row", "stacked" }),
	choice("contentInset", "Content inset", { "standard", "none" }),
	choice("scrollPolicy", "Scrolling", { "always", "atLargestDetent" }),
	json("hero", "Hero image"),
	json("actions", "Actions"),
})
extend({ "Alert" }, { text("icon", "Icon"), number("padding", "Padding") })
extend({ "Callout" }, {
	text("dismissLabel", "Dismiss label"),
	number("priority", "Priority"),
	flag("seen", "Seen"),
	flag("featureUsed", "Feature used"),
	number("sessions", "Sessions"),
	number("afterSessions", "Show after sessions"),
	json("steps", "Step progress"),
	json("media", "Media"),
	json("actions", "Actions"),
})
extend({ "ColorPicker" }, { flag("allowEmpty", "Allow empty"), text("placeholder", "Placeholder") })
extend({ "DateTimePicker" }, {
	number("hourCycle", "Hour cycle"),
	text("placeholder", "Placeholder"),
	json("referenceDate", "Reference date"),
	json("locale", "Date words"),
})
extend({ "RowActions" }, { flag("enabled", "Enabled"), flag("reducedMotion", "Reduced motion") })
extend({ "VirtualList", "VirtualGrid", "Table" }, {
	number("overscan", "Overscan"),
	number("gap", "Spacing"),
	flag("editing", "Editing"),
	flag("measure", "Measure rows"),
	flag("reducedMotion", "Reduced motion"),
	choice("follow", "Follow additions", { "end", "none" }),
	number("followThreshold", "Follow threshold"),
	choice("snap", "Snapping", { "none", "item" }),
	flag("reorderable", "Reorder rows"),
	flag("deletable", "Delete rows"),
})
extend({ "VirtualList", "VirtualGrid" }, {
	flag("autoscroll", "Drag scrolling"),
	number("maxRetained", "Retained rows"),
	choice("focusPolicy", "Focus policy", { "key", "index" }),
	flag("autoFocus", "Initial focus"),
	flag("wrapFocus", "Wrap focus"),
	text("initialFocus", "Initial focus key"),
})
extend(
	{ "Table" },
	{ flag("scrolls", "Scrollable"), choice("selectionMode", "Selection mode", { "none", "single", "multiple" }) }
)

local numericFields = {}
for _, descriptor in definitions.NumberInput.fields do
	if descriptor.key ~= "multiline" then
		table.insert(numericFields, descriptor)
	end
end
definitions.NumberInput.fields = numericFields

local exemplars = {
	row = { title = "Row title", description = "Description" },
	primaryAction = { label = "Continue" },
	menu = { label = "Actions", items = { { id = "first", label = "Explore" } } },
	actions = { { id = "continue", label = "Continue" } },
	leading = { { id = "save", label = "Save" } },
	glyphs = { filled = "★", empty = "☆" },
	trail = { delay = 0.2, duration = 0.4 },
	hero = { image = "rbxassetid://0", aspectRatio = 1.6 },
	min = { year = 2026, month = 1, day = 1 },
	max = { year = 2026, month = 12, day = 31 },
	tileSize = { width = 32, height = 32 },
	sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 24 },
	modes = { "swatches", "spectrum", "sliders", "brick" },
	triggers = { "activate", "secondary", "longPress" },
	sections = { { id = "primary", label = "Main" } },
	customization = { order = { "first", "second" }, hidden = {} },
	media = { image = "rbxassetid://0", aspectRatio = 1.6 },
	steps = { index = 1, count = 3 },
	referenceDate = { year = 2026, month = 10, day = 1 },
	imageProperties = { ImageTransparency = 0 },
}
for _, definition in definitions do
	for _, descriptor in definition.fields do
		if descriptor.kind == "json" then
			descriptor.exemplar = definition.defaults[descriptor.key] or exemplars[descriptor.key]
		end
	end
end

for _, kind in { "VirtualList", "VirtualGrid", "Table" } do
	definitions[kind].container = true
	table.insert(definitions[kind].fields, field("dataKey", "Live rows input", "string"))
	table.insert(definitions[kind].fields, field("activationKey", "Row activation callback", "string"))
end
table.insert(definitions.Table.fields, field("rowActions", "Row actions", "json"))

for _, kind in { "Table", "VirtualList", "VirtualGrid" } do
	for _, descriptor in definitions[kind].fields do
		if descriptor.key == "width" then
			descriptor.kind = "nativeWidth"
		end
	end
end
local bindings: { [string]: { [string]: string } } = {
	Text = { text = "string" },
	Label = { title = "string", icon = "string" },
	Badge = { label = "string" },
	Image = { image = "string" },
	Avatar = { name = "string", image = "string" },
	StatusIndicator = { name = "string", count = "number" },
	ProgressView = { value = "number", label = "string" },
}
for kind, targets in bindings do
	local keys = {}
	for key in targets do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		local conversion = targets[key]
		local descriptor = field(key .. "Field", "Bind " .. key .. " to row", "binding")
		descriptor.target, descriptor.conversion = key, conversion
		table.insert(definitions[kind].fields, descriptor)
	end
end

for kind, definition in definitions do
	if kind ~= "Screen" then
		table.insert(definition.fields, field("columnId", "Table column", "column"))
	end
end
local library = { definitions = definitions }

function library.names(): { string }
	local names: { string } = {}
	for name in definitions do
		table.insert(names, name)
	end
	table.sort(names, function(a, b)
		local left, right = definitions[a].category, definitions[b].category
		return if left == right then a < b else left < right
	end)
	return names
end

function library.descriptor(kind: string, key: string): any
	local definition = assert(definitions[kind], `Unsupported control: {kind}`)
	for _, item in definition.fields do
		if item.key == key then
			return item
		end
	end
	return nil
end

function library.visible(kind: string, key: string, props: any): boolean
	if kind == "Image" and key == "tileSize" then
		return props.scaleMode == "tile"
	elseif kind == "Image" and (key == "sliceCenter" or key == "sliceScale") then
		return props.scaleMode == "slice"
	elseif kind == "Picker" and key == "indicatorPosition" then
		return props.style == "radioGroup"
	elseif kind == "Picker" and key == "maxHeight" then
		return table.find({ "automatic", "menu", "navigationLink" }, props.style or "segmented") ~= nil
	elseif kind == "Sheet" and key == "edge" then
		return table.find({ "side", "adaptive" }, props.placement) ~= nil
	elseif kind == "Toggle" and key == "mixed" then
		return props.presentation == "checkbox"
	elseif kind == "Text" and key == "lines" then
		return props.truncate ~= "middle"
	elseif kind == "Skeleton" and key == "lines" then
		return (props.form or definitions.Skeleton.defaults.form) == "line"
	elseif kind == "LevelPicker" and (key == "images" or key == "glyphs") then
		local segment = props.segment or definitions.LevelPicker.defaults.segment
		return if key == "images" then segment == "image" else segment == "glyph"
	elseif kind == "Toast" and (key == "action" or key == "closeButton") then
		return props.position == nil and props.width == nil and props.fade == nil
	end
	return true
end

function library.parse(descriptor: any, value: any): any
	if descriptor.kind == "nativeWidth" then
		return if value == "fill" then value else library.parse({ kind = "number" }, value)
	elseif descriptor.kind == "binding" or descriptor.kind == "column" then
		assert(type(value) == "string" and #value > 0 and #value <= 120, "Choose a row field")
		return value
	elseif descriptor.kind == "padding" then
		if type(value) ~= "table" then
			return library.parse({ kind = "spacing" :: "spacing", options = spacing }, value)
		end
		for key, side in value do
			assert(table.find({ "top", "right", "bottom", "left" }, key), "Choose a padding side")
			assert(
				library.parse({ kind = "spacing" :: "spacing", options = spacing }, side) == side,
				"Use a spacing step or pixels"
			)
		end
		return value
	elseif descriptor.kind == "json" then
		if descriptor.key == "rowActions" then
			assert(type(value) == "table" and #value <= 12, "Use at most 12 row actions")
			local seen = {}
			for index, action in value do
				assert(
					type(index) == "number" and index % 1 == 0 and index >= 1 and index <= #value,
					"Use a dense row action array"
				)
				assert(
					type(action) == "table" and type(action.id) == "string" and action.id ~= "" and not seen[action.id],
					"Use unique row action IDs"
				)
				seen[action.id] = true
				assert(type(action.label) == "string" and action.label ~= "", "A row action needs a label")
				assert(
					action.handler == nil or (type(action.handler) == "string" and action.handler ~= ""),
					"Use a named row callback"
				)
				assert(
					action.role == nil or table.find({ "default", "cancel", "destructive", "onIndicator" }, action.role),
					"Choose a row action role"
				)
				assert(action.enabled == nil or type(action.enabled) == "boolean", "Use a boolean action state")
				assert(action.icon == nil or type(action.icon) == "string", "Use an icon name")
				for key in action do
					assert(
						table.find({ "id", "label", "handler", "role", "enabled", "icon" }, key),
						"Unsupported row action property"
					)
				end
			end
		end
		return values.validate(value)
	elseif descriptor.kind == "color" then
		values.color(value)
		return value
	elseif descriptor.kind == "boolean" then
		assert(type(value) == "boolean", "Expected a boolean")
		return value
	elseif descriptor.kind == "number" then
		local number = tonumber(value)
		assert(number and number == number and math.abs(number) < 1000000, "Enter a finite number below one million")
		if descriptor.key == "BackgroundTransparency" or descriptor.key == "alpha" then
			assert(number >= 0 and number <= 1, "Use a value from 0 to 1")
		end
		return number
	elseif descriptor.kind == "extent" then
		if value == "fill" or value == "hug" then
			return value
		end
		local number = tonumber(value)
		assert(number and number >= 0 and number < 10000, "Use fill, hug, or pixels from 0 to 9999")
		return number
	elseif descriptor.kind == "spacing" then
		if table.find(descriptor.options, value) then
			return value
		end
		local number = tonumber(value)
		assert(number and number >= 0 and number < 10000, "Use a spacing step or a positive pixel value")
		return number
	elseif descriptor.kind == "choice" then
		assert(table.find(descriptor.options, value), "Choose a supported value")
		return value
	end
	assert(type(value) == "string" and #value <= 10000, "Enter text of at most 10000 bytes")
	return value
end

return library
