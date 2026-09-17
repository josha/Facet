--!strict
-- Public consumer witnesses: real specs must survive the namespace signatures.
-- Negative probes in check_types.py separately catch widening to any.

local Facet = require("../../src")
local tableControl = require("../../src/controls/table")
local sliderControl = require("../../src/controls/slider")
local stepperControl = require("../../src/controls/stepper")
local pickerControl = require("../../src/controls/picker")
local popupButton = require("../../src/controls/popup_button")
local menuControl = require("../../src/controls/menu")
local tabView = require("../../src/controls/tab_view")
local labelControl = require("../../src/controls/label")
local ratingControl = require("../../src/controls/rating")
local textInput = require("../../src/controls/text_input")
local progressView = require("../../src/controls/progress_view")
local levelPicker = require("../../src/controls/level_picker")
local disclosureGroup = require("../../src/controls/disclosure_group")
local rowActions = require("../../src/controls/row_actions")
local calloutControl = require("../../src/controls/callout")

local core = Facet.newCore()

-- The new deferred controls publish their specs directly at the entry point.
-- Concrete values exercise required fields, owned signals and callback results.
local buttonSpec: Facet.ButtonSpec = {
	label = "Repeat",
	busy = core:signal(false),
	repeatDelay = 0.4,
	shortcut = { keyCode = "F6", modifiers = { shift = true } },
	dialogAction = "default",
	onActivate = function() end,
}
local _button = Facet.Controls.Button(core, buttonSpec)
local toggleSpec: Facet.ToggleSpec = {
	label = "Select all",
	value = core:signal(false),
	mixed = core:signal(true),
	presentation = "checkbox",
	onChange = function(_value: boolean) end,
}
local _toggle = Facet.Controls.Toggle(core, toggleSpec)
local comboSpec: Facet.ComboBoxSpec = {
	value = core:signal("a"),
	text = core:signal("Alpine"),
	options = { { id = "a", label = "Alpine", description = "Mountain" } },
	acceptCustom = function(text: string): (boolean, string?)
		return #text > 2, "Use at least three characters."
	end,
	onChange = function(_value: string) end,
}
local _combo = Facet.Controls.ComboBox(core, comboSpec)
local splitSpec: Facet.SplitButtonSpec = {
	label = "Start",
	onActivate = function() end,
	items = { { id = "practice", label = "Practice", onSelect = function() end } },
}
local _split = Facet.Controls.SplitButton(core, splitSpec)

local routes: { Facet.NavigationEntry } = { { id = "details", value = { name = "Alder" } } }
local navigationSpec: Facet.NavigationStackSpec = {
	path = core:signal(routes),
	backLabel = "Back",
	root = {
		title = core:signal("Home"),
		content = function(scope: Facet.Scope)
			local title = scope:own(core:signal("Welcome"))
			return Facet.UI.Text({ text = title })
		end,
	},
	destinations = {
		details = {
			title = "Details",
			content = function(_scope: Facet.Scope, entry: Facet.NavigationEntry?)
				return Facet.UI.Text({ text = if entry then entry.id else "Root" })
			end,
		},
	},
	transition = { enter = "slide-left", distance = 100 },
}
local _navigation = Facet.Controls.NavigationStack(core, navigationSpec)

local tableControlSpec: tableControl.Spec = nil :: any
local _table = Facet.Controls.Table(core, tableControlSpec)

local sliderControlSpec: sliderControl.Spec = nil :: any
local _slider = Facet.Controls.Slider(core, sliderControlSpec)

local stepperControlSpec: stepperControl.Spec = nil :: any
local _stepper = Facet.Controls.Stepper(core, stepperControlSpec)

local pickerControlSpec: pickerControl.Spec = nil :: any
local _picker = Facet.Controls.Picker(core, pickerControlSpec)

local initialPickerOptions: { pickerControl.Option } = { { id = "a", value = "a", label = "Alpine" } }
local livePickerOptions: Facet.Signal<{ pickerControl.Option }> = core:signal(initialPickerOptions)
local livePickerSpec: pickerControl.Spec = {
	options = livePickerOptions,
	selected = core:signal("a"),
	presentation = "radio",
}
local _livePicker = Facet.Controls.Picker(core, livePickerSpec)

local popupButtonSpec: popupButton.Spec = nil :: any
local _popupbutton = Facet.Controls.PopupButton(core, popupButtonSpec)

local multiPopupSpec: popupButton.Spec = {
	options = { { id = "a", label = "Alpine" } },
	selectedValues = core:signal({ a = true }),
	onChange = function(chosen: { [string]: boolean })
		local _selected: boolean? = chosen.a
	end,
}
local _multiPopup = Facet.Controls.PopupButton(core, multiPopupSpec)

local menuControlSpec: menuControl.Spec = nil :: any
local _menu = Facet.Controls.Menu(core, menuControlSpec)

local statefulMenuSpec: menuControl.Spec = {
	trigger = Facet.UI.Button({ label = "Filters" }),
	items = {
		{
			id = "a",
			label = "Alpine",
			description = core:signal("Mountain"),
			checked = core:signal(false),
			onChange = function(_checked: boolean) end,
		},
	},
}
local _statefulMenu = Facet.Controls.Menu(core, statefulMenuSpec)

local tabViewSpec: tabView.Spec = nil :: any
local _tabview = Facet.Controls.TabView(core, tabViewSpec)

local labelControlSpec: labelControl.Spec = nil :: any
local _label = Facet.Controls.Label(core, labelControlSpec)

local _chip = Facet.Controls.Chip(core, { selected = core:signal(false), label = "Tag" })

local ratingControlSpec: ratingControl.Spec = nil :: any
local _rating = Facet.Controls.Rating(core, ratingControlSpec)

local textInputSpec: textInput.Spec = nil :: any
local _textinput = Facet.Controls.TextInput(core, textInputSpec)

local numericTextSpec: textInput.Spec = {
	value = core:signal("1"),
	numericValue = core:signal(1),
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
}
local _numericText = Facet.Controls.TextInput(core, numericTextSpec)

local progressViewSpec: progressView.Spec = nil :: any
local _progressview = Facet.Controls.ProgressView(core, progressViewSpec)

local levelPickerSpec: levelPicker.Spec = nil :: any
local _levelpicker = Facet.Controls.LevelPicker(core, levelPickerSpec)

local disclosureGroupSpec: disclosureGroup.Spec = nil :: any
local _disclosuregroup = Facet.Controls.DisclosureGroup(core, disclosureGroupSpec)

local _virtuallist = Facet.Controls.VirtualList(core, {
	rows = core:signal({ "a" }),
	key = function(item: string)
		return item
	end,
	cell = function(item: string)
		return Facet.UI.Text(item)
	end,
	itemExtent = 40,
})

local _virtualgrid = Facet.Controls.VirtualGrid(core, {
	items = core:signal({ "a" }),
	key = function(item: string)
		return item
	end,
	cell = function(item: string)
		return Facet.UI.Text(item)
	end,
	columns = 2,
	itemExtent = 40,
})

local rowActionsSpec: rowActions.Spec = nil :: any
local _rowactions = Facet.Controls.RowActions(core, rowActionsSpec)

local calloutControlSpec: calloutControl.Spec = nil :: any
local _callout = Facet.Controls.Callout(core, calloutControlSpec)

local _asyncimage =
	Facet.Controls.AsyncImage(core, { id = "Art", scope = core:scope(), provider = nil :: any, key = "image" })
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
	virtuallist = _virtuallist,
	virtualgrid = _virtualgrid,
	rowactions = _rowactions,
	callout = _callout,
	asyncimage = _asyncimage,
}
local _keep: any = _bound
