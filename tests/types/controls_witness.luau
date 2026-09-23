--!strict
-- Named, valid literal specs for every registered composite. The checker also
-- probes both constructor spellings with invalid fields. Primitives and returned
-- nodes still ride an open `any` surface; collection item inference through
-- Controls.VirtualList/Grid<any> is not proved by these explicitly typed rows.
-- This file is analyzed, not mounted or claimed as runtime evidence.
local Facet = require("../../src")
local coreTypes = require("../../src/core/contract")
local navigationTypes = require("../../src/spec_types/navigation_stack")
local pickerTypes = require("../../src/spec_types/picker")
local levelPickerTypes = require("../../src/spec_types/level_picker")
local statusTypes = require("../../src/spec_types/status_indicator")
local primitiveTypes = require("../../src/blueprint")
local _circleBox: primitiveTypes.BoxSpec = {
	shape = "circle" :: "circle",
	width = { type = "percent", fraction = 0.5 },
	tint = { role = "control", blend = 1 },
}
local _circleImage: primitiveTypes.ImageSpec =
	{ shape = "circle" :: "circle", width = { type = "fill" }, image = "rbxassetid://1" }
local app = Facet.new()

local label = Facet.Compose.cell("Repeat")
local _button = app.controls.Button("Repeat")({
	animation = { scale = "object" },
	label = function(use: coreTypes.Use): string
		return use(label)
	end,
	controlSize = Facet.Compose.cell("compact" :: "compact" | "regular" | "large"),
	appearance = function(_use: coreTypes.Use): "emphasis"
		return "emphasis"
	end,
	corners = "square",
	over = "media",
	icon = "search",
	trailingIcon = "chevron.trailing",
	busy = Facet.Compose.cell(false),
	repeatDelay = 0.4,
	shortcut = { keyCode = "F6", modifiers = { shift = true } },
	dialogAction = "default",
	onActivate = function() end,
})
-- Untracked thunks remain accepted; a callback may ignore the supplied Use.
local _thunkButton = app.controls.Button("Ready")({
	label = function(): string
		return "Ready"
	end,
})
local _toggle = app.controls.Toggle("SelectAll")({
	width = Facet.Compose.cell({ type = "hug" }),
	label = "Select all",
	value = Facet.Compose.cell(false),
	mixed = Facet.Compose.cell(true),
	presentation = "checkbox",
	hint = Facet.Compose.cell("Choose every row"),
	indicatorPosition = "trailing",
	controlSize = "compact",
	onChange = function(_value: boolean) end,
})
local approved = Facet.Compose.cell(false)
local _controlledToggle = app.controls.Toggle("Music")({
	label = "Music",
	value = Facet.Compose.formula(function(use)
		return use(approved)
	end),
	mixed = function(use)
		return not use(approved)
	end,
	presentation = "checkbox",
	onChange = function(value: boolean)
		approved:set(value)
	end,
})
local _combo = app.controls.ComboBox("Mountain")({
	value = Facet.Compose.cell("a"),
	text = Facet.Compose.cell("Alpine"),
	options = { { id = "a", label = "Alpine", description = "Mountain" } },
	acceptCustom = function(text: string): (boolean, string?)
		return #text > 2, "Use at least three characters."
	end,
	onChange = function(_value: string) end,
})
local _split = app.controls.SplitButton("Start")({
	label = "Start",
	onActivate = function() end,
	items = { { id = "practice", label = "Practice", onSelect = function() end } },
})
local _navigation = app.controls.NavigationStack("Navigation")({
	path = Facet.Compose.cell({ { id = "details", value = { name = "Alder" } } } :: { navigationTypes.Entry }),
	backLabel = "Back",
	root = {
		title = Facet.Compose.cell("Home"),
		content = function(_owner)
			return app.controls.Text({ text = "Welcome" })
		end,
	},
	destinations = {
		details = {
			title = "Details",
			content = function(_owner, entry: navigationTypes.Entry?)
				return app.controls.Text({ text = if entry then entry.id else "Root" })
			end,
		},
	},
	transition = { enter = "slide-left", distance = 100 },
})
local _table = app.controls.Table("Table")({
	rows = Facet.Compose.cell({ "Alpine" }),
	key = function(item: string)
		return item
	end,
	columns = {
		{
			id = "name",
			title = "Name",
			width = { type = "fixed", px = 120 },
			value = function(item: string)
				return item
			end,
		},
	},
})
local _slider = app.controls.Slider("Volume")({ value = Facet.Compose.cell(0.5), min = 0, max = 1 })
local _rangeSlider = app.controls.Slider({
	value = Facet.Compose.cell({ lower = 2, upper = 8 }),
	min = 0,
	max = 10,
	range = true,
	minGap = 1,
	axis = "y",
	thumb = "auto",
	rotation = function(_use)
		return 90
	end,
	controlSize = "compact",
	thumbContent = function(info)
		local _ = info.thumb
		return nil
	end,
	onChange = function(_value: any, _info) end,
})
local _stepper = app.controls.Stepper("Laps")({ value = Facet.Compose.cell(2), min = 1, max = 8 })
local _picker = app.controls.Picker("Picker")({
	options = { { id = "a", value = "a", label = "Alpine" } },
	selected = Facet.Compose.cell("a"),
})
local pickerOptions: { pickerTypes.Option } = { { id = "a", value = "a", label = "Alpine" } }
local _livePicker = app.controls.Picker("LivePicker")({
	options = Facet.Compose.cell(pickerOptions),
	selected = Facet.Compose.cell("a"),
	presentation = "radio",
})
local _pickerField = app.controls.Picker({
	options = { { value = "a", label = "Ada", avatar = { name = "Ada" }, badge = 2, sectionTitle = "Crew" } },
	selected = Facet.Compose.cell("a"),
	style = "menu",
	requiredMark = "required",
	hint = "Who drives",
	errorText = Facet.Compose.cell(""),
	controlSize = "compact",
	appearance = "contrast",
	corners = "pill",
	maxHeight = 96,
})
local _popupbutton = app.controls.PopupButton("Popup")({
	options = { { id = "a", label = "Alpine" } },
	value = Facet.Compose.cell("a"),
})
local _multiPopup = app.controls.PopupButton("MultiPopup")({
	options = { { id = "a", label = "Alpine" } },
	selectedValues = Facet.Compose.cell({ a = true }),
	onChange = function(chosen: { [string]: boolean })
		local _selected: boolean? = chosen.a
	end,
})
local _menu = app.controls.Menu("Filters")({
	label = "Filters",
	items = {
		{
			id = "a",
			label = "Alpine",
			description = Facet.Compose.cell("Mountain"),
			checked = Facet.Compose.cell(false),
			onChange = function(_checked: boolean) end,
		},
	},
})
local _tabview = app.controls.TabView("Tabs")({
	selection = Facet.Compose.cell("home"),
	tabs = {
		{
			id = "home",
			label = "Home",
			content = function(_owner)
				return app.controls.Text({ text = "Home" })
			end,
		},
	},
})
local labelTitle = Facet.Compose.cell("Alpine")
local _label = app.controls.Label("Label")({ title = labelTitle, icon = "facet:search" })
local _anonymousLabel = app.controls.Label({
	title = function(use)
		return use(labelTitle)
	end,
})
local statusWord =
	Facet.Compose.cell("neutral" :: "neutral" | "info" | "success" | "warning" | "error" | "accent" | nil)
local _status = app.controls.StatusIndicator("Unread")({ count = Facet.Compose.cell(4), status = statusWord, max = 99 })
local _anonymousStatus = app.controls.StatusIndicator({
	form = "ring",
	status = function(use: coreTypes.Use): statusTypes.Status?
		return if use(statusWord) == "error" then "error" else "neutral"
	end,
	cutout = true,
	ref = function(record)
		local _text = record.api.semanticText:peek()
	end,
})
local _badge =
	app.controls.Badge("Ready")({ label = Facet.Compose.cell("Ready"), status = statusWord, appearance = "status" })
local _anonymousBadge =
	app.controls.Badge({ icon = "status.info", name = "Information", iconPosition = "trailing", over = "media" })
local _skeleton = app.controls.Skeleton("Loading")({ form = "line", lines = 3, controlSize = "compact" })
local _circleSkeleton = app.controls.Skeleton({
	form = "circle",
	width = { type = "fixed", px = 72 },
	ref = function(record)
		local _dump = record.dump()
	end,
})
local _avatar = app.controls.Avatar("Ada")({
	name = "Ada Quill",
	presence = Facet.Compose.cell("online" :: "online" | "away" | "busy" | "offline" | nil),
	controlSize = "compact",
	onActivate = function() end,
})
local _anonymousAvatar = app.controls.Avatar({
	name = "Émile Noël",
	image = Facet.Compose.cell("rbxassetid://1"),
	form = "icon",
	ref = function(record)
		local _label = record.dump().label
	end,
})
local _avatarGroup = app.controls.AvatarGroup("Team")({
	items = { { id = "ada", name = "Ada Quill", presence = "online" :: "online" } },
	max = 3,
	controlSize = "compact",
	onOverflow = function() end,
})
local _anonymousAvatarGroup = app.controls.AvatarGroup({
	items = function(_use)
		return { { id = "noel", name = "Émile Noël", image = "rbxassetid://1" } }
	end,
	layout = "spread",
	overflow = "ellipsis",
	form = "icon",
	ref = function(record)
		local _shown = record.dump().shown
	end,
})
local _hint = app.controls.ShortcutHint("Shortcut")({ action = "Activate", controlSize = "compact" })
local _explicitHint = app.controls.ShortcutHint({
	keys = { { "Ctrl", "K" }, { "F1" } },
	separator = function(use)
		return use(labelTitle)
	end,
	over = "media",
})
local _chip = app.controls.Chip("Tag")({
	animation = { scale = "object" },
	controlSize = "compact",
	appearance = "utility",
	corners = "pill",
	leading = app.controls.Text({ text = "*" }),
	trailing = app.controls.Text({ text = "3" }),
	selected = Facet.Compose.cell(false),
	label = "Tag",
})
local _editableTag = app.controls.Chip("EditTag")({
	label = "Tag",
	selected = Facet.Compose.cell(false),
	editing = Facet.Compose.cell(false),
	onRemove = function() end,
})
local _removeOnly = app.controls.Chip("RemoveTag")({
	label = "Tag",
	onRemove = function() end,
	removeLabel = "Remove tag",
	removeFocusFallback = Facet.Compose.cell("/Screen/Restore"),
})
local _anonymousRemoveOnly = app.controls.Chip({
	label = "Tag",
	onRemove = function() end,
	removeFocusFallback = function(_use: coreTypes.Use): string
		return "/Screen/Restore"
	end,
})
local _anonymousSetting = app.controls.Toggle({
	label = "Music",
	value = Facet.Compose.cell(false),
	hint = "Play music",
	indicatorPosition = "leading",
	controlSize = "large",
})
local _rating = app.controls.Rating("Rating")({ value = Facet.Compose.cell(3) })
local _textinput = app.controls.TextInput("Name")({ value = Facet.Compose.cell("Alpine") })
local _fieldChrome = app.controls.TextInput({
	value = Facet.Compose.cell(""),
	label = "Display name",
	requiredMark = "required",
	hint = function(_use)
		return "Shown to other players"
	end,
	errorText = Facet.Compose.cell(""),
	controlSize = "compact",
	appearance = "contrast",
	corners = "pill",
})
local _numberInput = app.controls.NumberInput("Fee")({
	value = Facet.Compose.cell("2.00"),
	numericValue = Facet.Compose.cell(2),
	min = 0,
	max = 50,
	step = 0.5,
	precision = 2,
	stepButtons = true,
	prefix = "$",
	suffix = function(_use)
		return "ea"
	end,
	parse = Facet.recipes.arithmetic.parse,
})
local _anonymousNumber =
	app.controls.NumberInput({ value = Facet.Compose.cell("1"), numericValue = Facet.Compose.cell(1) })
local _readOnlyNotes = app.controls.TextInput("Notes")({
	value = Facet.Compose.cell(""),
	multiline = true,
	visibleLines = 3,
	readOnly = function(_use)
		return true
	end,
	selectOnFocus = "all",
})
local _scrubbed = app.controls.NumberInput("Laps")({
	value = Facet.Compose.cell("1"),
	numericValue = Facet.Compose.cell(1),
	scrub = true,
})
local _numericText = app.controls.TextInput("Number")({
	value = Facet.Compose.cell("1"),
	numericValue = Facet.Compose.cell(1),
	presentation = "number",
	min = 0,
	max = 10,
	parse = function(text: string): number?
		return tonumber(text)
	end,
	format = function(number: number): string
		return tostring(number)
	end,
	-- the number presentation reports a number, and "clamped" when a bound moved it
	onCommit = function(_value: string | number, _reason: "enter" | "focusLost" | "submit" | "clamped") end,
	onCancel = function() end,
})
local _progressview =
	app.controls.ProgressView("Progress")({ value = Facet.Compose.cell(0.5), endLabel = Facet.Compose.cell("2 of 5") })
local _rungProgress = app.controls.ProgressView({
	presentation = "spinner",
	controlSize = "compact",
	endLabel = function(_use)
		return "Connecting"
	end,
})
local _levelpicker = app.controls.LevelPicker("Level")({ value = Facet.Compose.cell(2) })
local _levelConfig: levelPickerTypes.Config = {
	constructor = "LevelPicker",
	names = { run = "Run", mark = "Mark" },
	id = "Level",
	value = Facet.Compose.cell(2),
	count = 5,
	minValue = 1,
	segment = "bar",
	sizeRole = "medium",
	tint = {},
	targetFloor = true,
	readOnly = false,
	diagnostics = {},
}
local _disclosuregroup = app.controls.DisclosureGroup("More")({
	label = "More",
	description = Facet.Compose.cell("Optional settings"),
	icon = "settings",
	chevronPosition = "trailing",
	appearance = "contained",
	controlSize = "compact",
	expanded = Facet.Compose.cell(false),
	content = function()
		return app.controls.Text({ text = "Details" })
	end,
})
local _anonymousDisclosure = app.controls.DisclosureGroup({
	label = "Settings",
	expanded = Facet.Compose.cell(false),
	description = "Optional",
	appearance = "divided",
	chevronPosition = "leading",
	content = function()
		return app.controls.Text({ text = "Details" })
	end,
})
local _collapsible = app.controls.CollapsibleView("Collapsible")({
	label = "More",
	expanded = Facet.Compose.cell(false),
	content = function()
		return app.controls.Text({ text = "Details" })
	end,
})

type Row = { id: string, label: string }
local rows = Facet.Compose.cell({ { id = "a", label = "Alpine" } } :: { Row })
local function currentRows(use: coreTypes.Use): { Row }
	return use(rows)
end
local _virtuallist = app.controls.VirtualList("History")({
	rows = currentRows,
	key = "id",
	cell = function(item: Row)
		return app.controls.Text({ text = item.label })
	end,
	itemExtent = 40,
	follow = function(use: coreTypes.Use): "end" | "none"
		return if use(approved) then "end" else "none"
	end,
	followThreshold = 48,
	scrollNavigation = { position = Facet.Compose.cell(0), active = approved },
})
local _virtualgrid = app.controls.VirtualGrid("Inventory")({
	items = currentRows,
	key = "id",
	cell = function(item: Row)
		return app.controls.Text({ text = item.label })
	end,
	columns = 2,
	itemExtent = 40,
})
-- Explicit generic specs preserve Row agreement even though the constructor's
-- item parameter remains any. These are valid data, never nil/any seeded specs.
local _listSpec: Facet.VirtualListSpec<Row> = {
	rows = currentRows,
	key = "id",
	cell = function(item: Row)
		return app.controls.Text({ text = item.label })
	end,
	itemExtent = 40,
}
local _gridSpec: Facet.VirtualGridSpec<Row> = {
	items = currentRows,
	key = "id",
	cell = function(item: Row)
		return app.controls.Text({ text = item.label })
	end,
	columns = 2,
	itemExtent = 40,
}
local _rowactions = app.controls.RowActions("RowActions")({
	content = app.controls.Text({ text = "Alpine" }),
	trailing = { { label = "Delete", onAction = function() end } },
})
local _callout = app.controls.Callout("Tip")({
	anchor = app.controls.Button({ label = "Help" }),
	content = function()
		return app.controls.Text({ text = "Help text" })
	end,
	onRetire = function(_reason: string) end,
})
local _richCallout = app.controls.Callout({
	anchor = app.controls.Button({ label = "Help" }),
	title = "Try it",
	media = { image = "rbxassetid://1", aspectRatio = 2, scaleMode = "crop" :: "crop" },
	steps = { index = 1, count = 3 },
	actions = { { id = "Go", label = "Show me", role = "default" :: "default", onActivate = function() end } },
	closeButton = true,
	onRetire = function(_reason: string) end,
})
local popoverOpen = Facet.Compose.cell(false)
local _popover = app.controls.Popover("Info")({
	isPresented = popoverOpen,
	onPresentedChange = function(next: boolean)
		popoverOpen:set(next)
	end,
	onDismiss = function(_reason) end,
	trigger = app.controls.Button({ label = "Info" }),
	edge = "trailing",
	align = "center",
	crossOffset = 4,
	maxWidth = 320,
	compact = "popover",
	content = function()
		return app.controls.Text({ text = "Body" })
	end,
})
local _sourcePopover = app.controls.Popover({
	isPresented = function(use)
		return use(popoverOpen)
	end,
	source = { rect = { x = 0, y = 0, w = 10, h = 10 } },
	content = function()
		return app.controls.Text({ text = "Body" })
	end,
})
local dialogOpen = Facet.Compose.cell(true)
local _dialog = app.controls.Dialog("Confirm")({
	isPresented = dialogOpen,
	onPresentedChange = function(next: boolean)
		dialogOpen:set(next)
	end,
	onDismiss = function(_reason) end,
	title = "Leave?",
	content = function()
		return app.controls.Text({ text = "Body" })
	end,
	hero = { image = "rbxassetid://1", height = 120 },
	actionLabel = "Choose",
	actions = { { id = "Stay", label = "Stay", role = "cancel" :: "cancel", onActivate = function() end } },
	actionLayout = "automatic",
	width = "wide",
	contentSelectable = false,
})
local _notice = app.controls.Notice("Conn")({
	message = "Offline",
	title = function(use)
		return use(labelTitle)
	end,
	severity = "warning",
	appearance = "emphasis",
	placement = "affixed",
	icon = false,
	link = { label = "Details", onActivate = function() end },
	actions = { { id = "Retry", label = "Retry", onActivate = function() end } },
	onDismiss = function() end,
	controlSize = "compact",
})
local _navBar = app.controls.NavBar("Top")({
	onBack = function() end,
	backLabel = "Back",
	title = "Garage",
	leading = app.controls.Button({ label = "Home" }),
	trailing = app.controls.Button({ label = "More" }),
})
local _asyncimage = app.controls.AsyncImage("Art")({
	key = "image",
	scaleMode = "slice",
	sliceCenter = { x0 = 8, y0 = 8, x1 = 56, y1 = 56 },
	sliceScale = 1,
	resample = Facet.Compose.cell("pixelated" :: "default" | "pixelated"),
	provider = {
		acquire = function(_owner, _key, _options)
			return {
				state = Facet.Compose.cell("ready"),
				value = Facet.Compose.cell("rbxassetid://1"),
				error = Facet.Compose.cell(nil),
				release = function() end,
			}
		end,
	},
})
local _tileImage = app.controls.AsyncImage({
	key = "tile",
	provider = {
		acquire = function(): never
			error("analyzer only")
		end,
	},
	scaleMode = "tile",
	tileSize = { width = 24, height = 24 },
	resample = function(_use)
		return "pixelated"
	end,
})
local _radial = app.controls.RadialMenu("Actions")({
	label = "Actions",
	items = { { id = "watch", label = "Watch", onSelect = function() end } },
})
local _alert = app.controls.Alert("Confirm")({
	title = "Continue?",
	isPresented = Facet.Compose.cell(false),
	actions = { { id = "ok", label = "Continue", onActivate = function() end } },
})
local _sheet = app.controls.Sheet("Details")({
	title = "Details",
	detent = Facet.Compose.cell("medium"),
	content = function()
		return app.controls.Text({ text = "Details" })
	end,
})
local _sheetParts = app.controls.Sheet("Lobby")({
	title = function(_use)
		return "Lobby"
	end,
	detent = Facet.Compose.cell("hug"),
	detents = { "hug" :: "hug" | "large", "large" },
	placement = "side",
	edge = "left",
	width = "narrow",
	closeButton = false,
	header = false,
	hero = { image = "rbxassetid://1", aspectRatio = 16 / 9, sticky = true },
	actions = { { id = "join", label = "Join", role = "default" :: "default", onActivate = function() end } },
	actionLayout = "stacked",
	contentInset = "none",
	scrollPolicy = "atLargestDetent",
	content = function()
		return app.controls.Text({ text = "Lobby" })
	end,
})
local snackShown = Facet.Compose.cell(false)
local _snackbar = app.controls.Snackbar("Saved")({
	isPresented = snackShown,
	message = "Saved to your garage",
	icon = "status.success",
	action = { label = "Undo", onActivate = function() end },
	onPresentedChange = function(next: boolean)
		snackShown:set(next)
	end,
	onDismiss = function(_reason) end,
	duration = 4,
	priority = 1,
})
local _card = app.controls.Card("Nebula")({
	image = "rbxassetid://1",
	title = Facet.Compose.cell("Nebula Racers"),
	caption = "Friends playing",
	imageAspectRatio = 16 / 9,
	onActivate = function() end,
	primaryAction = { label = "Play", icon = "chevron.trailing", onActivate = function() end, busy = false },
	menu = { items = { { id = "hide", label = "Not interested", onSelect = function() end } }, label = "More" },
	reveal = "automatic",
	browseTarget = function(): string?
		return nil
	end,
})
local _pageview = app.controls.PageView("Pages")({
	selection = Facet.Compose.cell("home"),
	pages = { { id = "home", title = "Home", content = app.controls.Text({ text = "Home" }) } },
})

local _iconOnly = app.controls.Button({ icon = "close", name = "Close", controlSize = "compact" })

local chipLook = Facet.Compose.cell("utility" :: "standard" | "utility" | nil)
local _anonymousChip = app.controls.Chip({
	label = "Rain",
	selected = Facet.Compose.cell(false),
	controlSize = function(_use: coreTypes.Use): "compact"?
		return "compact"
	end,
	appearance = chipLook,
})

-- THE PRIMITIVES, in both spellings and with every kind of live value an author
-- passes: a plain value, a cell, a formula and a `function(use)` binding, with
-- positional children.
local UI = app.controls
local spacing = Facet.Compose.cell(8)
local title = Facet.Compose.formula(function()
	return "Title"
end)
local _layout = UI.Screen("Witness")({
	padding = 12,
	gap = "m",
	UI.VStack({
		gap = spacing,
		width = { type = "fill" },
		UI.Text({ text = title, textSize = "heading" }),
		UI.Text("Count")({
			text = function(use)
				return `{use(spacing)} px`
			end,
			textSize = 14,
		}),
		UI.HStack("Row")({
			gap = 4,
			wrap = true,
			UI.Box({ width = { type = "fixed", px = 24 }, height = { type = "fixed", px = 24 }, surface = "control" }),
			UI.Spacer({ minLength = 8 }),
			UI.Image({ image = "rbxassetid://1", width = { type = "fixed", px = 24 } }),
		}),
		UI.Divider({}),
		UI.ZStack("Layers")({ alignH = "center", UI.Text({ text = 7 }) }),
		UI.ScrollView("Scroll")({ axis = "y", UI.Text({ text = "scrolls" }) }),
		UI.Grid("Cells")({ columns = 2, gap = "s", UI.Text({ text = "a" }), UI.Text({ text = "b" }) }),
	}),
})
