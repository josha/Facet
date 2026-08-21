--!strict
--[[ THE TYPE WITNESS for `Facet.Controls` (wave T15, director ruling 2026-08-21).

	WHAT THIS FILE IS FOR. `src/init.luau` defers each control's `require` into the
	closure that needs it and keeps the parameter type through
	`typeof(require(...))` — an idiom whose ENTIRE justification is "the nineteen
	typed signatures survive". Nothing in this repository could see a type until
	the analyzer was pinned, so that justification was a claim no check could
	falsify. This file is the half of the instrument the analyzer reads.

	IT IS RUN BY `tools/check_types.py`, NOT BY THE LUAU SUITE. It is never
	executed: every value in it is `(nil :: any)`. Running it would index nil on
	the first line, which is why it lives under `tests/types/` and is excluded from
	the spec glob.

	HOW EACH CASE PROVES SOMETHING. A local is declared with the CONTROL MODULE'S
	OWN `Spec` type and handed to the namespace entry. If the entry's parameter
	type were some OTHER type, this reddens; if it were narrowed, this reddens.
	What it cannot catch on its own is the entry WIDENING to `any` — `any` accepts
	everything, including this. That direction is the negative probe's, in
	`check_types.py`: a control whose entry still carries a real `Spec` must REJECT
	a number, and the four entries that are `any` today are pinned as such by name.
	Neither half is sufficient alone and the checker runs both.

	FOUR ENTRIES TAKE `any` TODAY — Chip, VirtualList, VirtualGrid, AsyncImage —
	and that is a pre-existing fact about `src/init.luau`, not something this wave
	introduced or endorses. They are pinned by name in the checker so the set
	cannot grow quietly.
]]

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

local tableControlSpec: tableControl.Spec = nil :: any
local _table = Facet.Controls.Table(core, tableControlSpec)

local sliderControlSpec: sliderControl.Spec = nil :: any
local _slider = Facet.Controls.Slider(core, sliderControlSpec)

local stepperControlSpec: stepperControl.Spec = nil :: any
local _stepper = Facet.Controls.Stepper(core, stepperControlSpec)

local pickerControlSpec: pickerControl.Spec = nil :: any
local _picker = Facet.Controls.Picker(core, pickerControlSpec)

local popupButtonSpec: popupButton.Spec = nil :: any
local _popupbutton = Facet.Controls.PopupButton(core, popupButtonSpec)

local menuControlSpec: menuControl.Spec = nil :: any
local _menu = Facet.Controls.Menu(core, menuControlSpec)

local tabViewSpec: tabView.Spec = nil :: any
local _tabview = Facet.Controls.TabView(core, tabViewSpec)

local labelControlSpec: labelControl.Spec = nil :: any
local _label = Facet.Controls.Label(core, labelControlSpec)

-- `Chip` declares `spec: any` in src/init.luau; pinned in check_types.py
local _chip = Facet.Controls.Chip(core, nil :: any)

local ratingControlSpec: ratingControl.Spec = nil :: any
local _rating = Facet.Controls.Rating(core, ratingControlSpec)

local textInputSpec: textInput.Spec = nil :: any
local _textinput = Facet.Controls.TextInput(core, textInputSpec)

local progressViewSpec: progressView.Spec = nil :: any
local _progressview = Facet.Controls.ProgressView(core, progressViewSpec)

local levelPickerSpec: levelPicker.Spec = nil :: any
local _levelpicker = Facet.Controls.LevelPicker(core, levelPickerSpec)

local disclosureGroupSpec: disclosureGroup.Spec = nil :: any
local _disclosuregroup = Facet.Controls.DisclosureGroup(core, disclosureGroupSpec)

-- `VirtualList` declares `spec: any` in src/init.luau; pinned in check_types.py
local _virtuallist = Facet.Controls.VirtualList(core, nil :: any)

-- `VirtualGrid` declares `spec: any` in src/init.luau; pinned in check_types.py
local _virtualgrid = Facet.Controls.VirtualGrid(core, nil :: any)

local rowActionsSpec: rowActions.Spec = nil :: any
local _rowactions = Facet.Controls.RowActions(core, rowActionsSpec)

local calloutControlSpec: calloutControl.Spec = nil :: any
local _callout = Facet.Controls.Callout(core, calloutControlSpec)

-- `AsyncImage` declares `spec: any` in src/init.luau; pinned in check_types.py
local _asyncimage = Facet.Controls.AsyncImage(core, nil :: any)
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
