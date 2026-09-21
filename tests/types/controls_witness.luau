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
local app = Facet.new()

local label = Facet.Compose.cell("Repeat")
local _button = app.controls.Button("Repeat")({
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
	label = "Select all",
	value = Facet.Compose.cell(false),
	mixed = Facet.Compose.cell(true),
	presentation = "checkbox",
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
local _chip = app.controls.Chip("Tag")({
	controlSize = "compact",
	appearance = "utility",
	corners = "pill",
	leading = app.controls.Text({ text = "*" }),
	trailing = app.controls.Text({ text = "3" }),
	selected = Facet.Compose.cell(false),
	label = "Tag",
})
local _rating = app.controls.Rating("Rating")({ value = Facet.Compose.cell(3) })
local _textinput = app.controls.TextInput("Name")({ value = Facet.Compose.cell("Alpine") })
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
	onCommit = function(_text: string, _reason: "enter" | "focusLost" | "submit") end,
	onCancel = function() end,
})
local _progressview = app.controls.ProgressView("Progress")({ value = Facet.Compose.cell(0.5) })
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
	expanded = Facet.Compose.cell(false),
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
