--!strict
-- Public consumer witness for the Compose-authored surface: `Facet.new()` ->
-- `app.controls.X(spec)`. One call per composite registered in
-- `src/render/compose_controls.luau`, so a rename, a dropped registration or a
-- broken `require` inside a control module (rather than merely inside its own
-- file, which the graph-diagnostics half already ignores by design) shows up
-- here as a target-file diagnostic.
--
-- THIS IS NOT A DEEP TYPE WITNESS. `tools/check_types.py` found empirically
-- (2026-09-20) that `composite()`'s indirection in compose_controls.luau
-- erases every build function's declared `Spec` type at this boundary: even
-- `app.controls.Slider("W")({ value = "nope" })`, where slider.luau declares
-- `spec: Spec`, draws no diagnostic here. The per-field annotations below are
-- for a human reader and for the modules that still export their `Spec` type,
-- not because the analyzer enforces them through `app.controls`.

local Facet = require("../../src")
local navigationStackControl = require("../../src/controls/navigation_stack")
local tableControl = require("../../src/controls/table")
local sliderControl = require("../../src/controls/slider")
local stepperControl = require("../../src/controls/stepper")
local pickerControl = require("../../src/controls/picker")
local popupMenuControl = require("../../src/controls/picker_menu")
local menuControl = require("../../src/controls/menu")
local tabView = require("../../src/controls/tab_view")
local labelControl = require("../../src/controls/label")
local ratingControl = require("../../src/controls/rating")
local textInputControl = require("../../src/controls/text_input")
local progressView = require("../../src/controls/progress_view")
local levelPicker = require("../../src/controls/level_picker")
local disclosureGroup = require("../../src/controls/disclosure_group")
local rowActions = require("../../src/controls/row_actions")
local calloutControl = require("../../src/controls/callout")

local app = Facet.new()

local _button = app.controls.Button("W")({
	label = "Repeat",
	busy = Facet.Compose.cell(false),
	repeatDelay = 0.4,
	shortcut = { keyCode = "F6", modifiers = { shift = true } },
	dialogAction = "default",
	onActivate = function() end,
})

local _toggle = app.controls.Toggle("W")({
	label = "Select all",
	value = Facet.Compose.cell(false),
	mixed = Facet.Compose.cell(true),
	presentation = "checkbox",
	onChange = function(_value: boolean) end,
})

local _combo = app.controls.ComboBox("W")({
	value = Facet.Compose.cell("a"),
	text = Facet.Compose.cell("Alpine"),
	options = { { id = "a", label = "Alpine", description = "Mountain" } },
	acceptCustom = function(text: string): (boolean, string?)
		return #text > 2, "Use at least three characters."
	end,
	onChange = function(_value: string) end,
})

local _split = app.controls.SplitButton("W")({
	label = "Start",
	onActivate = function() end,
	items = { { id = "practice", label = "Practice", onSelect = function() end } },
})

local _navigation = app.controls.NavigationStack("W")({
	-- a path is a cell of entries; say so, because a cell is invariant in what it holds
	path = Facet.Compose.cell({ { id = "details", value = { name = "Alder" } } } :: { navigationStackControl.Entry }),
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
			content = function(_owner, entry: any)
				return app.controls.Text({ text = if entry then entry.id else "Root" })
			end,
		},
	},
	transition = { enter = "slide-left", distance = 100 },
})

local tableControlSpec: tableControl.Spec = nil :: any
local _table = app.controls.Table(tableControlSpec)

local sliderControlSpec: sliderControl.Spec = nil :: any
local _slider = app.controls.Slider(sliderControlSpec)

local stepperControlSpec: stepperControl.Spec = nil :: any
local _stepper = app.controls.Stepper(stepperControlSpec)

local pickerControlSpec: pickerControl.Spec = nil :: any
local _picker = app.controls.Picker(pickerControlSpec)

local initialPickerOptions: { pickerControl.Option } = { { id = "a", value = "a", label = "Alpine" } }
local livePickerOptions = Facet.Compose.cell(initialPickerOptions)
local _livePicker = app.controls.Picker("W")({
	options = livePickerOptions,
	selected = Facet.Compose.cell("a"),
	presentation = "radio",
})

local popupButtonSpec: popupMenuControl.Spec = nil :: any
local _popupbutton = app.controls.PopupButton(popupButtonSpec)

local _multiPopup = app.controls.PopupButton("W")({
	options = { { id = "a", label = "Alpine" } },
	selectedValues = Facet.Compose.cell({ a = true }),
	onChange = function(chosen: { [string]: boolean })
		local _selected: boolean? = chosen.a
	end,
})

local menuControlSpec: menuControl.Spec = nil :: any
local _menu = app.controls.Menu(menuControlSpec)

local _statefulMenu = app.controls.Menu("W")({
	trigger = app.controls.Button("W")({ label = "Filters" }) :: any,
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

local tabViewSpec: tabView.Spec = nil :: any
local _tabview = app.controls.TabView(tabViewSpec)

local labelControlSpec: labelControl.Spec = nil :: any
local _label = app.controls.Label(labelControlSpec)

local _chip = app.controls.Chip("W")({ selected = Facet.Compose.cell(false), label = "Tag" })

local ratingControlSpec: ratingControl.Spec = nil :: any
local _rating = app.controls.Rating(ratingControlSpec)

local textInputSpec: textInputControl.Spec = nil :: any
local _textinput = app.controls.TextInput(textInputSpec)

local _numericText = app.controls.TextInput("W")({
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

local progressViewSpec: progressView.Spec = nil :: any
local _progressview = app.controls.ProgressView(progressViewSpec)

local levelPickerSpec: levelPicker.Spec = nil :: any
local _levelpicker = app.controls.LevelPicker(levelPickerSpec)

local disclosureGroupSpec: disclosureGroup.Spec = nil :: any
local _disclosuregroup = app.controls.DisclosureGroup(disclosureGroupSpec)

local collapsibleControl = require("../../src/controls/collapsible_view")
local collapsibleSpec: collapsibleControl.Spec = nil :: any
local _collapsible = app.controls.CollapsibleView(collapsibleSpec)

local _virtuallist = app.controls.VirtualList("W")({
	rows = Facet.Compose.cell({ "a" }),
	key = function(item: string)
		return item
	end,
	cell = function(item: string)
		return app.controls.Text({ text = item })
	end,
	itemExtent = 40,
})

local _virtualgrid = app.controls.VirtualGrid("W")({
	items = Facet.Compose.cell({ "a" }),
	key = function(item: string)
		return item
	end,
	cell = function(item: string)
		return app.controls.Text({ text = item })
	end,
	columns = 2,
	itemExtent = 40,
})

local rowActionsSpec: rowActions.Spec = nil :: any
local _rowactions = app.controls.RowActions(rowActionsSpec)

local calloutControlSpec: calloutControl.Spec = nil :: any
local _callout = app.controls.Callout(calloutControlSpec)

local _asyncimage =
	app.controls.AsyncImage("W")({ id = "Art", scope = nil :: any, provider = nil :: any, key = "image" })

local radialControl = require("../../src/controls/radial_menu")
local radialSpec: radialControl.Spec = nil :: any
local _radial = app.controls.RadialMenu(radialSpec)

local alertControl = require("../../src/controls/alert")
local alertSpec: alertControl.Spec = nil :: any
local _alert = app.controls.Alert(alertSpec)

local sheetControl = require("../../src/controls/sheet")
local sheetSpec: sheetControl.Spec = nil :: any
local _sheet = app.controls.Sheet(sheetSpec)

local pageViewControl = require("../../src/controls/page_view")
local pageViewSpec: pageViewControl.Spec = nil :: any
local _pageview = app.controls.PageView(pageViewSpec)

--[[ The results are bound so an entry that stopped returning anything at all
	would be visible here too. They are deliberately not annotated: the builders'
	return types are what they are, and pinning them in this file would make it a
	second declaration of a contract that lives in the control modules. ]]
local _bound = {
	table = _table,
	slider = _slider,
	stepper = _stepper,
	picker = _picker,
	popupbutton = _popupbutton,
	menu = _menu,
	tabview = _tabview,
	label = _label,
	chip = _chip,
	rating = _rating,
	textinput = _textinput,
	progressview = _progressview,
	levelpicker = _levelpicker,
	disclosuregroup = _disclosuregroup,
	collapsible = _collapsible,
	virtuallist = _virtuallist,
	virtualgrid = _virtualgrid,
	rowactions = _rowactions,
	callout = _callout,
	asyncimage = _asyncimage,
	radial = _radial,
	alert = _alert,
	sheet = _sheet,
	pageview = _pageview,
}
local _keep: any = _bound
