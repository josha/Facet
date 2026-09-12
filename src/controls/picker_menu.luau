--!strict
--[[ THE PICKER MENU ENGINE — the popup half of `Controls.Picker` (2026-09-11),
	and the body the deprecated `Controls.PopupButton` still runs on.

	A COMPOSITE over shipped primitives: ONE focusable Button (the "trigger")
	shows the currently-selected option's label with the up/down chevron INSIDE
	it — the pop-up button every desktop draws and the menu picker a phone's
	form row draws — never a separate chevron cell. Activating it presents the
	option rows: anchored to the trigger (a popover, `presentation = "menu"`) or
	as a bottom sheet when a gamepad or a long list on a compact/touch surface
	asks for one (`menu_recipe.resolvePickerPresentation`). Activating a row
	writes the OWNER-HELD selection signal, fires onChange and closes; the
	trigger's value text is a binding, so a pick relabels with zero structural
	churn. Outside tap, Escape and ButtonB close without touching the selection.
	The open rows are ordinary focusable Buttons, so keyboard/gamepad users
	navigate them and Activate to pick; closed, only the trigger is focusable.

	TWO CALLERS, ONE BODY. `Controls.Picker` hands this `style = "menu" |
	"navigationLink"`, picker-shaped options (`{ value, label }`) and its
	`selected` signal. The legacy `Controls.PopupButton` hands `value` /
	`selectedValues` over `{ id, label }` options and its own `presentation`
	ladder (which still knows `inline`); everything below reads the option
	IDENTITY through `selection_model.identity`, so both shapes share every
	row, every route and every dismissal path. Engine-free; Lune-tested in
	tests/picker_style.spec.luau and tests/popup_button.spec.luau. ]]

local controlContract = require("../class_contract")
local coreContract = require("../core/contract")
local selectionModel = require("../selection_model")
local contribution = require("../input/contribution")
local menuRecipe = require("./menu_recipe")
local specGuard = require("../spec_guard")
local surfaceEnv = require("../env/surface_env")
local paths = require("../paths")
local themeSnapshot = require("../themes/snapshot")
local textMetrics = require("../layout/text_metrics")
local themePackage = require("../themes/package")
local chrome_slots = require("../tokens/chrome_slots")

-- a node id is interpolated into a Lua PATTERN below, so its magic characters
-- have to be escaped first. Module scope, not per-instance: it is a pure
-- function of its argument and every `build()` used to allocate its own
-- (Step 5.5 cleanup ledger C-06).
local patternEscape = paths.escape

local popup_button = {}

--[[ AN OPTION IS A VALUE, AND `icon` / `divider` ARE ITS TWO NEW SPELLINGS
	(navigation-and-menus D2, so `r1`'s icon rows work and both menus render from
	one row recipe). This stays a VALUE picker — `value` is a `Signal<string>` and
	picking writes it. A list of VERBS is `Facet.newMenu`, which is a different
	control on purpose: a control that sometimes owns a value Signal and sometimes
	does not is two controls in one.

	`divider = true` is a rule between two groups. It carries no id, no label and
	no selection, and it is skipped by every count, every route and the dump —
	which is what makes it a grouping mark rather than an option that happens to
	do nothing when you press it. ]]
export type Option = {
	description: (string | coreContract.Readable<string>)?,
	enabled: (boolean | coreContract.Readable<boolean>)?,
	id: string?,
	value: any?, -- the picker shape: the identity is the value, the id names the row
	label: (string | coreContract.Readable<string>)?,
	icon: (string | coreContract.Readable<string>)?, -- semantic icon NAME, never an asset id
	divider: boolean?,
}

local OPTION_KEYS = specGuard.keySet({ "divider", "enabled", "icon", "id", "label", "description", "value" })
local STYLES: { [string]: boolean } = { menu = true, navigationLink = true }

export type Spec = {
	required: boolean?,
	onChanging: ((any, any) -> boolean)?,
	enabled: any?,
	id: string?,
	options: { Option } | coreContract.Readable<{ Option }>,
	query: coreContract.Signal<string>?,
	selectedValues: coreContract.Signal<{ [string]: boolean }>?,
	placeholder: string?,
	value: (coreContract.Signal<string> | coreContract.Signal<string?>)?, -- absent for selectedValues
	--[[ THE PICKER SHAPE. `selected` is `Controls.Picker`'s owner-held signal of
		an arbitrary option VALUE; `style` says which popup this is — the anchored
		`menu` or the full-sheet `navigationLink` — and its presence is what turns
		on the picker look (check-marked rows, no Cancel row in a popover, the
		picker presentation ladder). `label` puts the trigger in a FORM ROW beside
		its title; `sizing` is `hug` (the pop-up button) or `fill` (the row). ]]
	selected: any?,
	style: string?,
	label: any?,
	sizing: any?,
	textSize: any?,
	-- Single selection supplies an id (nil for optional clearing); multiple
	-- selection supplies a set. Preserve callbacks narrowed to required ids.
	onChange: (((string) -> ()) | ((string?) -> ()) | (({ [string]: boolean }) -> ()))?,
	-- adaptive presentation (B-DSP3): "automatic" (default) resolves from the
	-- option count, the space class, and whether touch is a LIVE class
	presentation: string?, -- automatic | menu | inline | sheet
	sizeClass: any?, -- string | Readable<string>, e.g. adaptive.conditions().sizeClass
	interactionClasses: any?, -- table | Readable<table>, e.g. env interactionClasses
	--[[ the environment BOTH facts above come from, for a caller that would
		otherwise wire two keys to say one thing. Omitted, an automatic
		presentation finds the one this control's own core published — and refuses
		to construct if there is none. ]]
	env: any?,
}

-- THEME METRICS. This control's own trigger keeps its own metric;
-- the three ROW heights are `menu_recipe`'s, because they are the same three
-- heights the freestanding Menu and the row-action menu use and a theme that
-- retunes its control ladder must retune all three menus together.
local TRIGGER_HEIGHT = "controls.popup.triggerHeight"

--[[ ADAPTIVE PRESENTATION (acceptance row B-DSP3) — MOVED TO `menu_recipe`,
	unchanged, and re-exported here so nothing that already calls it moves.

	It was always a pure function of three primitives with no env read, and it was
	always the rule BOTH menus need: sheet when touch is live or the list is long
	on a compact screen, floating panel otherwise. Two copies of that would drift,
	and the drift would only show on the input class nobody tested — so there is
	one, and this name is an alias for it rather than a second implementation.
	See `src/controls/menu_recipe.luau` for the rules themselves. ]]
popup_button.resolvePresentation = menuRecipe.resolvePresentation

local PRESENTATIONS: { [string]: boolean } = { automatic = true, menu = true, inline = true, sheet = true }

-- CLOSED SPEC (constitution §4). Exactly the fields this control
-- reads — an unknown one is an authoring mistake, never a silent no-op.
local POPUP_BUTTON_KEYS = specGuard.keySet({
	"selected",
	"style",
	"label",
	"sizing",
	"textSize",
	"query",
	"selectedValues",
	"placeholder",
	"required",
	"onChanging",
	"enabled",
	"env",
	"id",
	"interactionClasses",
	"onChange",
	"options",
	"presentation",
	"sizeClass",
	"value",
})

function popup_button.build(Facet: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("newPopupButton", spec, POPUP_BUTTON_KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "PopupButton"
	local scope = core:scope(`popup_button-{id}`)
	local disposed = false
	local mountedNode: any = nil
	local rootPath: string? = nil
	local presentModalFn, presentAnchoredFn, dismissFn, surfaceHandle
	local syncSurface
	local triggerWidth = 0
	local triggerRect: any = nil -- the trigger's last solved rect, read at present time
	local anchorRect: any = nil -- the rect the popover hangs from (chevron or trigger), same cadence
	local triggerPath: () -> string
	local dynamicOptions = type(spec.options) == "table" and spec.options.kind ~= nil
	local describedOptions = false
	if not dynamicOptions and type(spec.options) == "table" then
		for _, option in spec.options do
			if type(option) == "table" and option.description ~= nil then
				describedOptions = true
			end
		end
	end
	-- the PICKER always presents a real surface (anchored popover or sheet); the
	-- legacy popup keeps its in-tree `UI.When` panel for plain static options
	local detached = spec.style ~= nil
		or (
			(spec.query ~= nil or spec.selectedValues ~= nil or dynamicOptions or describedOptions)
			and spec.presentation ~= "inline"
		)
	--[[ THE SHEET IS THE FLOOR UNDER THE POPOVER (2026-09-11): a popover whose
		list is already at its floor and whose frame still cannot fit beside the
		trigger (Fantasy Ornate's 80px frame on a 390px-tall landscape phone at
		+10) would be clamped OVER the control that opened it. It becomes the
		bottom sheet instead — title, rows, Cancel — which is what the reference
		platform does when a menu has no room. Measured, not predicted: the
		popover is tried first, and only its own geometry sync can say. Reset on
		every close so a rotation gets the popover back. Declared HERE, above
		`presentationNow`: a closure only sees the locals that exist when it is
		made, and a later declaration would leave it reading a nil global. ]]
	local sheetFallback = false
	scope:own(function()
		disposed = true
	end)
	local function available()
		return not disposed and not controlContract.isDisabled(mountedNode) and controlContract.enabledNow(spec.enabled)
	end

	local pickerMode = spec.style ~= nil
	assert(not pickerMode or STYLES[spec.style], "Picker menu: style must be menu | navigationLink")
	-- a labelled picker is a FORM ROW: title leading, value + chevron trailing
	-- (the navigation link puts its title INSIDE its one row button instead)
	local rowForm = pickerMode and spec.style == "menu" and spec.label ~= nil
	local multiple = spec.selectedValues ~= nil
	assert(
		(spec.value ~= nil and 1 or 0) + (multiple and 1 or 0) + (spec.selected ~= nil and 1 or 0) == 1,
		"PopupButton: provide exactly one of value or selectedValues"
	)
	local selection = if multiple then spec.selectedValues elseif pickerMode then spec.selected else spec.value
	assert(
		type(selection) == "table" and selection.kind == "signal",
		"PopupButton: value or selectedValues must be a SETTABLE Signal the caller owns"
	)
	assert(not multiple or type(selection:get()) == "table", "PopupButton: selectedValues must hold an identity set")
	if multiple then
		for key, chosen in selection:get() do
			assert(
				type(key) == "string" and type(chosen) == "boolean",
				"PopupButton: selectedValues must be a string-keyed boolean set"
			)
		end
	elseif not pickerMode then
		assert(
			selection:get() == nil or type(selection:get()) == "string",
			"PopupButton: value must hold a string or nil"
		)
	end
	-- the ROW KEY: the path segment an option's row is named by. The legacy shape
	-- names it `id`; the picker shape may carry any non-NaN value and an optional
	-- id, so the key is the id when there is one and the value's string otherwise
	-- (the same rule `picker.luau`'s live strip keys its rows by).
	local function keyOf(option: any): string
		return if option.id ~= nil then option.id else tostring(option.value)
	end
	local enabledValue = selectionModel.read(spec.enabled)
	assert(
		enabledValue == nil or type(enabledValue) == "boolean",
		"PopupButton: enabled must be boolean or readable boolean"
	)
	assert(spec.placeholder == nil or type(spec.placeholder) == "string", "PopupButton: placeholder must be a string")
	assert(
		spec.query == nil
			or (type(spec.query) == "table" and spec.query.kind == "signal" and type(spec.query:get()) == "string"),
		"PopupButton: query must be a caller-owned Signal<string>"
	)
	assert(spec.required == nil or type(spec.required) == "boolean", "PopupButton: required must be boolean")
	assert(spec.onChanging == nil or type(spec.onChanging) == "function", "PopupButton: onChanging must be a function")
	assert(spec.onChange == nil or type(spec.onChange) == "function", "PopupButton: onChange must be a function")
	local function validatedOptions(use)
		local list = selectionModel.read(spec.options, use)
		assert(type(list) == "table", "PopupButton: options must be an array or readable array")
		local count = 0
		for key in list do
			assert(type(key) == "number" and key >= 1 and key % 1 == 0, "PopupButton: options must be a dense array")
			count += 1
		end
		for index = 1, count do
			assert(list[index] ~= nil, "PopupButton: options must be a dense array")
		end
		local seen = {}
		for index, option in list do
			specGuard.assertKnownKeys("newPopupButton", option, OPTION_KEYS, `spec.options[{index}]`)
			assert(option.divider == nil or type(option.divider) == "boolean", "PopupButton: divider must be boolean")
			if option.divider then
				for key in option do
					assert(key == "divider", "PopupButton: a divider carries no option fields")
				end
				continue
			end
			local rowKey = keyOf(option)
			assert(
				type(rowKey) == "string" and rowKey ~= "" and not string.find(rowKey, "/", 1, true),
				"PopupButton: option id must be a nonempty path-safe string"
			)
			assert(not seen[rowKey], `PopupButton: duplicate option id '{rowKey}'`)
			seen[rowKey] = true
			local label = selectionModel.read(option.label, use)
			assert(type(label) == "string" and label ~= "", "PopupButton: option needs a nonempty label")
			local description = selectionModel.read(option.description, use)
			assert(
				description == nil or type(description) == "string",
				"PopupButton: description must be a string or readable string"
			)
			assert(
				option.icon == nil or type(selectionModel.read(option.icon, use)) == "string",
				"PopupButton: icon must be a semantic name"
			)
			local enabledValue = selectionModel.read(option.enabled, use)
			assert(
				enabledValue == nil or type(enabledValue) == "boolean",
				"PopupButton: option enabled must be boolean or readable boolean"
			)
		end
		local mixed = menuRecipe.mixedIconGroup(list)
		assert(
			mixed == nil,
			"PopupButton: option group mixes options that declare an icon with options that do not. Give every option an icon, or none of them"
		)
		return list
	end
	validatedOptions(function(value)
		return value:get()
	end)
	local options = scope:own(core:memo(validatedOptions))
	options:get()
	local function find(identity, use)
		return selectionModel.find(if use then use(options) else options:get(), identity)
	end
	-- a row's option, from the path segment its row is named by
	local function byKey(rowKey: string, use)
		for _, option in (if use then use(options) else options:get()) do
			if not option.divider and keyOf(option) == rowKey then
				return option
			end
		end
		return nil
	end
	local results = scope:own(core:memo(function(use)
		local query = if spec.query then string.lower(use(spec.query)) else ""
		local filtered = {}
		for _, option in use(options) do
			if
				not option.divider
				and (query == "" or string.find(string.lower(selectionModel.read(option.label, use)), query, 1, true))
			then
				table.insert(filtered, option)
			end
		end
		return filtered
	end))
	-- open/closed is the control's only owned state; selection lives in `value`
	local open = scope:own(core:signal(false))
	local enabled = scope:own(core:memo(function(use)
		return controlContract.enabledIn(use, spec.enabled)
	end))
	scope:own(core:observe(enabled, function(value)
		if not value then
			open:set(false)
		end
	end))

	-- the trigger label tracks the selected option (a binding, not a rebuild).
	-- Fallback to the raw id keeps the button truthful if `value` holds an id
	-- that is not (yet) among the options.
	local selectedLabel = scope:own(core:memo(function(use)
		local current = use(selection)
		if multiple then
			local labels = {}
			for identity, chosen in current do
				if chosen then
					local option = find(identity, use)
					table.insert(labels, if option then selectionModel.read(option.label, use) else tostring(identity))
				end
			end
			table.sort(labels)
			return if #labels == 0 then (spec.placeholder or "Choose options") else table.concat(labels, ", ")
		end
		local option = find(current, use)
		return if option
			then selectionModel.read(option.label, use)
			else (if current == nil then (spec.placeholder or "Choose an option") else tostring(current))
	end))
	local api = {} :: any

	local idPattern = patternEscape(id)

	-- commit a selection: write the owner signal (firing onChange only on a
	-- real change), then close. Re-picking the current option just closes.
	local function select(optionId: any)
		if not available() then
			return
		end
		local current = selection:get()
		if multiple then
			if not selectionModel.enabled(find(optionId)) then
				return
			end
			local nextSet = table.clone(current)
			nextSet[optionId] = if nextSet[optionId] then nil else true
			if spec.required == true and next(nextSet) == nil then
				return
			end
			if spec.onChanging then
				local ok, accepted = pcall(spec.onChanging, nextSet, current)
				if not ok or accepted == false then
					return
				end
			end
			if not available() or not selectionModel.enabled(find(optionId)) then
				return
			end
			core:transaction(function()
				selection:set(nextSet)
				if spec.onChange then
					spec.onChange(nextSet)
				end
			end)
		else
			local accepted, nextValue =
				selectionModel.choose(options:get(), current, optionId, spec.required, spec.onChanging)
			if accepted then
				if not available() or (optionId ~= nil and not selectionModel.enabled(find(optionId))) then
					return
				end
				core:transaction(function()
					selection:set(nextValue)
					if spec.onChange then
						spec.onChange(nextValue)
					end
				end)
			elseif optionId ~= current then
				return
			end
			open:set(false)
		end
	end

	-- routes a presenter/tap Activate; returns true when the path was ours.
	-- Trigger toggles open; Cancel and a re-open-toggle close with no change;
	-- an option row selects. meta is accepted for signature parity with the
	-- other controls (no modifier semantics here).
	function api.handleActivate(path: string, _meta: any?): boolean
		if not available() then
			return false
		end
		if string.match(path, if rowForm then `/{idPattern}/Form/.*/Trigger$` else `/{idPattern}/Trigger$`) ~= nil then
			open:set(not open:get())
			return true
		end
		if
			string.match(path, `/{idPattern}/PopupWhen/then/Popup/Cancel$`) ~= nil
			or (detached and string.match(path, "/Popup/Cancel$") ~= nil)
		then
			open:set(false)
			return true
		end
		local rowKey = string.match(
			path,
			-- the key is the row's LAST segment: a card row sits inside its
			-- `+background` wrapper (`.../Opt-x+background/Opt-x`), so a lazy
			-- capture would swallow the wrapper's name into the key
			if detached then "/Popup/.*Opt%-([^/]+)$" else `/{idPattern}/PopupWhen/then/Popup/.*Opt%-([^/]+)$`
		)
		local option = if rowKey ~= nil then byKey(rowKey) else nil
		if option ~= nil then
			select(selectionModel.identity(option))
			return true
		end
		return false
	end

	-- model-level open/close/select for host code that drives without a tap
	function api.open()
		if available() then
			open:set(true)
		end
	end
	function api.close()
		if not disposed then
			open:set(false)
		end
	end
	function api.select(identity: any)
		select(identity)
	end
	api.isOpen = open

	local requestedPresentation = spec.presentation or "automatic"
	assert(
		PRESENTATIONS[requestedPresentation],
		`PopupButton '{id}': unknown presentation '{requestedPresentation}' (automatic | menu | inline | sheet)`
	)
	assert(not pickerMode or requestedPresentation == "automatic", "Picker menu: the style decides the presentation")

	local function readFact(fact: any): any
		if type(fact) == "table" and (fact :: any).get ~= nil then
			return (fact :: any):get()
		end
		return fact
	end

	--[[ THE TWO FACTS THE LADDER RUNS ON, AND WHERE THEY COME FROM.

		Both were spec keys and nothing else, so an automatic PopupButton with
		neither took the pointer/large-screen answer silently — and the census found
		all five shipped call sites wiring `sizeClass` and NONE wiring
		`interactionClasses`, which is why "touch -> sheet", the reference
		platform's own default, had never fired in any reference app. Authored keys
		still win (a screen driving its own class from a Signal keeps working); when
		an automatic presentation is missing either, the surface's environment
		answers, and when there is no environment this control refuses to construct
		the way `tab_view` does. ]]
	local envForFacts: any = nil
	local factsFrom = "spec"
	if
		(requestedPresentation == "automatic" or pickerMode)
		and (spec.sizeClass == nil or spec.interactionClasses == nil)
	then
		local env, source = surfaceEnv.resolve(
			if pickerMode then "newPicker" else "newPopupButton",
			id,
			core,
			spec.env,
			"an automatic presentation adapts to the size class and the live interaction class"
		)
		envForFacts = env
		factsFrom = source
	end
	local sizeClassSource: any = spec.sizeClass or (if envForFacts ~= nil then envForFacts:get("sizeClass") else nil)
	local classesSource: any = spec.interactionClasses
		or (if envForFacts ~= nil then envForFacts:get("interactionClasses") else nil)

	-- resolved at BUILD of each panel, so reopening after a space or input-class
	-- change picks the right idiom without the control holding stale state
	local function presentationNow(): string
		if spec.style == "navigationLink" then
			return "sheet"
		end
		if requestedPresentation ~= "automatic" then
			return requestedPresentation
		end
		-- PRIMARY, not merely present: the one predicate, in the recipe
		local classes = readFact(classesSource)
		local touchLive = menuRecipe.touchPrimary(classes)
		local gamepad = classes ~= nil and classes.primary == "gamepad"
		-- the SELECTABLE count, not the array length: a divider is a rule between
		-- groups, and a menu does not become "long" because it was grouped
		if pickerMode then
			if sheetFallback then
				return "sheet"
			end
			return menuRecipe.resolvePickerPresentation(#results:get(), readFact(sizeClassSource), touchLive, gamepad)
		end
		return menuRecipe.resolvePresentation(#results:get(), readFact(sizeClassSource), touchLive, gamepad)
	end
	api.presentation = presentationNow
	-- the two trigger facts that follow the LIVE interaction class: a phone's
	-- form row draws a plain value in the secondary colour, a desktop draws a
	-- bordered pop-up button that hugs its content
	local touchPrimary = scope:own(core:memo(function(use)
		local classes = classesSource
		if type(classes) == "table" and (classes :: any).get ~= nil then
			classes = use(classes)
		end
		return menuRecipe.touchPrimary(classes)
	end))
	-- the node the popover hangs from: the chevron on a plain touch row (the
	-- last thing the eye sees on a trigger with no visible box), the trigger's
	-- own frame everywhere else. Declared AFTER `touchPrimary`: a closure only
	-- sees the locals that exist when it is made (three memos in this file were
	-- quarantined by that rule this round alone).
	local function anchorSourcePath(): string
		-- a plain touch row hangs its menu from the chevron (the last thing the
		-- eye sees on a row with no box); a boxed trigger hangs it from its frame
		if rowForm and touchPrimary:get() == true then
			return triggerPath() .. "/Row/Trailing/Chevron"
		end
		return triggerPath()
	end

	local function optionRow(option, rowScope)
		local function property(name)
			return rowScope:own(core:memo(function(use)
				local current = byKey(keyOf(option), use)
				local value = if current then selectionModel.read(current[name], use) else nil
				return if name == "description" then (value or "") else value
			end))
		end
		local selected = rowScope:own(core:memo(function(use)
			local current = use(selection)
			return if multiple then current[option.id] == true else current == selectionModel.identity(option)
		end))
		local hidden = rowScope:own(core:memo(function(use)
			return not use(selected)
		end))
		return menuRecipe.row(UI, {
			id = `Opt-{keyOf(option)}`,
			label = property("label"),
			description = if option.description ~= nil
					or spec.query ~= nil
					or dynamicOptions
				then property("description")
				else nil,
			enabled = property("enabled"),
			icon = if dynamicOptions then property("icon") else option.icon,
			core = core,
			scope = rowScope,
			selected = selected,
			textSize = spec.textSize,
			-- the picker's rows wear the CHECK-ONLY slot (the current value, not a
			-- toggle); the legacy popup keeps its check/radio/nothing exactly as shipped
			indicator = if multiple then "check" elseif pickerMode then "mark" elseif spec.query then "radio" else nil,
			--[[ ONE CARD, FLAT ROWS (user review of the side-by-side, 2026-09-11):
				the picker's rows carry no plate of their own — the popover card owns
				the corner and the stroke, a hairline separates the rows, and the
				chosen row shows a subtle fill. The check sits at the row's trailing
				edge on a touch surface (the reference platform's phone menus) and
				leads on a pointer or pad surface (its desktop menus). ]]
			surface = if pickerMode then "plain" else nil,
			indicatorEdge = if pickerMode and touchPrimary:get() == true then "trailing" else "leading",
			markHidden = hidden,
			height = "targetSizes.minimum",
		})
	end
	--[[ THE LIST'S HEIGHT BUDGET (picker sweep, 2026-09-11: three described
		rows at the Larger preference under a roomy package solved to 492px on a
		390px landscape phone and the popover ran off the screen). A picker's
		rows scroll inside the popover or sheet rather than growing past the
		viewport: the budget is the viewport less two gutters for a popover,
		and less the search field, the Cancel row and the padding for a sheet. ]]
	--[[ ...MEASURED, NOT ONLY ESTIMATED. A theme's chrome (image insets, a
		taller field) can outgrow the estimate below; the panel's own `syncGeometry`
		reads its solved rect after each solve and, when it still runs past the
		viewport, takes the excess off this signal — one refresh later the list is
		exactly as tall as the screen allows. Reset on every open. ]]
	local listShrink = scope:own(core:signal(0))
	local feeds = 0 -- shrinks fed this open (convergence guard: the solver caps feedback at 8 rounds)
	local function listMaxPx(presentation: string, use: any?): number
		local shrink = if use ~= nil then use(listShrink) else listShrink:get()
		local env = envForFacts or spec.env
		local metrics = if env ~= nil then env:get("themeMetrics"):get() else nil
		local minimum = if type(metrics) == "table"
				and type(metrics.targetSizes) == "table"
				and type(metrics.targetSizes.minimum) == "number"
			then metrics.targetSizes.minimum
			else themeSnapshot.neutral().targetSizes.minimum
		local vp = if env ~= nil then env:get("viewportRect"):get() else nil
		local h = if type(vp) == "table" and type(vp.h) == "number" then vp.h else 720
		-- the sheet's own chrome, in the theme's metrics: the Cancel row at the
		-- large control height, the search field at the regular one (a native
		-- field grows past it under a roomy package, so it is counted half again),
		-- the panel's `s` padding twice, and a gutter the surface keeps clear
		local neutral = themeSnapshot.neutral()
		local sizes = if type(metrics) == "table" and type(metrics.controlSizes) == "table"
			then metrics.controlSizes
			else neutral.controlSizes
		local space = if type(metrics) == "table"
				and type(metrics.space) == "table"
				and type(metrics.space.s) == "number"
			then metrics.space.s
			else neutral.space.s
		-- ...and every line of that chrome grows with the text preference
		local offsetFact = if env ~= nil then env:get("preferredTextOffset"):get() else 0
		local offset = if type(offsetFact) == "number" then offsetFact else 0
		local chrome = if presentation == "sheet"
			then sizes.large.height
				+ (if spec.query ~= nil then sizes.regular.height * 1.5 else 0)
				+ space * 2
				+ minimum
				+ offset * 4
			else minimum * 2 + offset * 2
		local budget = h - chrome
		--[[ ...AND A POPOVER STAYS ATTACHED (visual review 2026-09-11): its rows
			scroll inside the LARGER of the room below the trigger and the room above
			it, so the placement never has to clamp the panel over the control that
			opened it. The room is read off the trigger's last solved rect and the
			screen's own insets — the same numbers the anchored placement will use —
			and only bounds the popover; a sheet has the whole screen. ]]
		if presentation ~= "sheet" and type(triggerRect) == "table" and type(triggerRect.y) == "number" then
			local xs = if type(metrics) == "table"
					and type(metrics.space) == "table"
					and type(metrics.space.xs) == "number"
				then metrics.space.xs
				else neutral.space.xs
			local m = if type(metrics) == "table"
					and type(metrics.space) == "table"
					and type(metrics.space.m) == "number"
				then metrics.space.m
				else neutral.space.m
			local insets = if env ~= nil then env:get("coreSafeInsets"):get() else nil
			local top = if type(insets) == "table" and type(insets.top) == "number" then insets.top else 0
			--[[ the panel's own chrome — the `raised` slot's content insets a package
				carves (Glossy Touch's 7px, measured at +4 on a landscape phone) plus
				the rows' gap — comes out of the room too, or the rows fit and the
				plate around them does not; the anchor is the source's visible edge,
				which the trigger's box bounds on both sides ]]
			local insetsBySlot = if type(metrics) == "table" then (metrics :: any).chromeInsets else nil
			local plate = if type(insetsBySlot) == "table" then insetsBySlot.panel else nil
			local plateV = if type(plate) == "table"
				then (tonumber(plate.top) or 0) + (tonumber(plate.bottom) or 0)
				else 0
			local source = if type(anchorRect) == "table" and type(anchorRect.y) == "number"
				then anchorRect
				else triggerRect
			local below = h - m - (source.y + source.h + xs)
			local above = source.y - xs - top
			budget = math.min(budget, math.max(below, above) - offset - plateV - space)
		end
		return math.max(minimum * 2, budget - shrink), budget - shrink <= minimum * 2
	end
	-- the picker's static/dynamic row list height, reactive on the shrink
	local listHeight = scope:own(core:memo(function(use)
		return { type = "hug", max = listMaxPx(presentationNow(), use) }
	end))

	--[[ the widest a popover may grow: the viewport less the screen's content
		inset on both sides (the same `m` the anchor's `margin` keeps it inside) ]]
	local function safeWidthNow(): number
		local env = envForFacts or spec.env
		local vp = if env ~= nil then env:get("viewportRect"):get() else nil
		local metrics = if env ~= nil then env:get("themeMetrics"):get() else nil
		local snap = if type(metrics) == "table" and type(metrics.controls) == "table"
			then metrics
			else themeSnapshot.neutral()
		local inset = themeSnapshot.resolveNumber(snap, "space.m") or 16
		local w = if type(vp) == "table" and type(vp.w) == "number" then vp.w else 1280
		return math.max(120, w - 2 * inset)
	end
	--[[ THE WIDEST ROW, ESTIMATED FROM FACTS: the popover hugs it. A fill row
		reports no natural width of its own (fill is "take the offer"), so the
		hug is computed the way the strip's fit is — glyph count x the text size
		the preference and the ten-foot scale make, plus the row's own chrome
		(indicator slot, gap, padding) — and handed to `minMax` as the PREFERRED
		width between the trigger and the safe width. Byte length over-counts a
		pseudo-localized label, which is the safe direction for a hug. ]]
	local function widestRowEstimate(): number
		local env = envForFacts or spec.env
		local function fact(name: string): any
			return if env ~= nil then env:get(name):get() else nil
		end
		local metrics = fact("themeMetrics")
		local snap = if type(metrics) == "table" and type(metrics.controls) == "table"
			then metrics
			else themeSnapshot.neutral()
		local scale = themeSnapshot.typographyScale(fact("displaySize"), fact("preferredTextSize"))
		local offset = themeSnapshot.textOffset(fact("preferredTextOffset"))
		local labelPx = (themeSnapshot.resolveSize(snap, spec.textSize or "control") or 16) * scale + offset
		local captionPx = (themeSnapshot.resolveSize(snap, "caption") or 12) * scale + offset
		local sizes = (snap :: any).controlSizes
		local padX = if type(sizes) == "table"
				and type(sizes.regular) == "table"
				and type(sizes.regular.paddingX) == "number"
			then sizes.regular.paddingX
			else 12
		local slot = themeSnapshot.resolveNumber(snap, "space.l") or 24
		local gap = themeSnapshot.resolveNumber(snap, "space.s") or 8
		-- a themed row is a control with a carved frame of its own (Glossy Touch's
		-- gel: 14px a side) that its label must clear too — without it the rows
		-- hugged an estimate two frames short and truncated every label
		local insetsBySlot = if type(snap) == "table" then (snap :: any).chromeInsets else nil
		local plate = if type(insetsBySlot) == "table" then insetsBySlot.control else nil
		local frame = if type(plate) == "table" then (tonumber(plate.left) or 0) + (tonumber(plate.right) or 0) else 0
		local widest = 0
		for _, option in results:get() do
			if option.divider == true then
				continue
			end
			local label = tostring(readFact(option.label) or "")
			local w = #label * labelPx * textMetrics.AVG_GLYPH_FRACTION
			local description = readFact(option.description)
			if type(description) == "string" then
				w = math.max(w, #description * captionPx * textMetrics.AVG_GLYPH_FRACTION)
			end
			widest = math.max(widest, w + slot + gap + 2 * padX + frame)
		end
		return math.ceil(widest)
	end
	local function describedPanelWidth(): number
		local env = envForFacts or spec.env
		local metrics = if env ~= nil then env:get("themeMetrics"):get() else nil
		local themed = if type(metrics) == "table"
				and type(metrics.controls) == "table"
				and type(metrics.controls.popup) == "table"
				and type(metrics.controls.popup.panelWidth) == "number"
			then metrics.controls.popup.panelWidth
			else themeSnapshot.neutral().controls.popup.panelWidth
		local vp = if env ~= nil then env:get("viewportRect"):get() else nil
		local w = if type(vp) == "table" and type(vp.w) == "number" then vp.w else math.huge
		return math.max(120, math.min(themed, w - 16))
	end

	local searchField, virtualList
	if spec.query then
		searchField = Facet.Controls.TextInput(
			core,
			{ id = "Search", value = spec.query, presentation = "search", enabled = enabled, env = spec.env }
		)
		scope:own(searchField)
		local metrics = scope:own(core:memo(function(use)
			local env = envForFacts
				or spec.env
				or (surfaceEnv.resolve("newPopupButton", id, core, nil, "search results follow theme metrics"))
			local raw = use(env:get("themeMetrics"))
			return if type(raw) == "table" and raw.controls then raw else themeSnapshot.neutral()
		end))
		local rowHeight = scope:own(core:memo(function(use)
			return use(metrics).targetSizes.minimum * 2
		end))
		local viewport = scope:own(core:memo(function(use)
			local env = envForFacts
				or spec.env
				or surfaceEnv.resolve("newPopupButton", id, core, nil, "search viewport")
			local budget = if pickerMode then listMaxPx("sheet", use) else use(env:get("viewportRect")).h * 0.4
			return math.min(use(metrics).targetSizes.minimum * 5, budget)
		end))
		virtualList = Facet.Controls.VirtualList(core, {
			id = "Results",
			rows = results,
			key = keyOf,
			itemExtent = "measured",
			estimatedItemExtent = rowHeight,
			viewportExtent = viewport,
			width = { type = "fill", weight = 1 },
			rowFocusable = function(option)
				return selectionModel.enabled(byKey(keyOf(option)))
			end,
			onActivate = function(option)
				select(selectionModel.identity(option))
			end,
			cell = function(option, ctx)
				local row = optionRow(option, ctx.scope)
				-- VirtualList owns the hit target and semantic activation for this cell.
				return UI.VStack({
					padding = "s",
					enabled = row.props.enabled,
					width = { type = "fill", weight = 1 },
					children = row.children,
				})
			end,
		})
		scope:own(virtualList)
	end
	local emptyHidden = scope:own(core:memo(function(use)
		return #use(results) > 0
	end))
	local staticRows = {}
	if not dynamicOptions and not multiple and spec.query == nil then
		for index, option in options:get() do
			if option.divider then
				table.insert(staticRows, menuRecipe.divider(UI, `Div-{index}`))
			else
				table.insert(staticRows, optionRow(option, scope))
			end
		end
	end
	--[[ A DESCRIBED POPOVER'S WIDTH: the themed panel width, but never wider
		than the screen it opens on. Measured on the compact phone row (2026-09-11):
		a 360px panel on a 360px viewport was shifted to the safe box's left edge
		and painted 8px past its right one — a fixed width the placement solver
		can clamp the position of but not the size. The cap keeps one gutter on
		each side; a plain (undescribed) popover hugs its rows and never needed it. ]]
	local function popupPanel()
		local presentation = presentationNow()
		local rowHeight = menuRecipe.rowHeightFor(presentation)
		local rows = {}
		if virtualList then
			table.insert(rows, searchField.blueprint)
			table.insert(rows, virtualList.blueprint)
			table.insert(rows, UI.Text({ id = "Empty", text = "No matching options", hidden = emptyHidden }))
		else
			local listRows = {}
			if dynamicOptions or multiple then
				table.insert(
					listRows,
					UI.ForEach({
						id = "Options",
						items = results,
						key = keyOf,
						row = optionRow,
					})
				)
			else
				for index, row in staticRows do
					if row.class == "Button" then
						local props = table.clone(row.props)
						props.id = row.id
						props.height = if detached
							then { type = "minMax", min = rowHeight }
							else { type = "fixed", px = rowHeight }
						props.children = row.children
						if pickerMode then
							-- the card's rows: a hairline between neighbours, a subtle
							-- `controlSelected` fill behind the chosen one (see optionRow)
							if index > 1 then
								table.insert(listRows, menuRecipe.divider(UI, `Div-{index}`))
							end
							local chosen = props.selected
							table.insert(
								listRows,
								UI.background(
									UI.Button(props),
									UI.Box({
										id = "Fill",
										tint = { role = "controlSelected", blend = 1 },
										hidden = if type(chosen) == "table"
											then scope:own(core:memo(function(use)
												return use(chosen) ~= true
											end))
											else true,
									})
								)
							)
						else
							table.insert(listRows, UI.Button(props))
						end
					else
						table.insert(listRows, row)
					end
				end
			end
			if pickerMode then
				-- the picker's rows SCROLL inside their budget (see `listMaxPx`)
				table.insert(
					rows,
					UI.ScrollView({
						id = "List",
						axis = "y",
						width = { type = "fill", weight = 1 },
						height = listHeight,
						children = {
							UI.VStack({
								id = "Rows",
								width = { type = "fill", weight = 1 },
								gap = 0, -- flat rows inside one card; the hairlines are the rhythm
								children = listRows,
							}),
						},
					})
				)
			else
				for _, row in listRows do
					table.insert(rows, row)
				end
			end
		end
		--[[ THE CANCEL ROW. An INLINE list has no floating surface to dismiss by
			tapping away from, so it keeps the explicit row; a sheet keeps it too (a
			finger needs a visible way out). The PICKER's anchored popover has none —
			a pop-up menu on every desktop and the menu picker on a phone close on an
			outside tap, Escape or ButtonB, and a Cancel row would be a second way
			to say what those already say. The legacy popup keeps it on every
			presentation, because that behaviour is proven and pinned. ]]
		if not (pickerMode and presentation == "menu") then
			table.insert(
				rows,
				UI.Button({
					id = "Cancel",
					label = "Cancel",
					width = { type = "fill", weight = 1 },
					height = if detached
						then { type = "minMax", min = rowHeight }
						else { type = "fixed", px = rowHeight },
				})
			)
		end
		-- MENU / INLINE sit just below the trigger; a SHEET anchors to the bottom
		-- edge, which is where a thumb reaches. Either way the panel OVERLAYS
		-- following content (the root is an Anchor) rather than pushing layout, so
		-- the transient-surface machinery — outsideDismiss, transientScope,
		-- handleCancel — is untouched by the presentation choice: it keys on `open`.
		local isSheet = presentation == "sheet"
		--[[ THE POPOVER'S WIDTH. A described list keeps the themed panel width
			(the description needs a line to live on); a plain picker popover hugs
			its rows and is floored at the TRIGGER's own width — the pop-up button
			rule: the menu never comes out narrower than the control that opened
			it. `triggerWidth` is the last solved rect, read at present time. ]]
		--[[ ...and it is the THEMED PANEL WIDTH, never narrower than the trigger
			(measured live under Glossy Touch, 2026-09-11: a popover that only
			floored at the trigger hugged a 95px button and wrapped every option
			label onto two lines — a content row has no natural width to hug). ]]
		--[[ ...AND THE VISUAL REVIEW OF 2026-09-11 REVERSED THE PICKER HALF: a
			popover that took the themed panel width (360px) beside a 120px value
			read as "not attached to the thing that opened it". The reference
			platform's menu HUGS its widest row, never narrower than the control it
			hangs from and never wider than the safe area. `minMax` with no
			preferred is exactly "content, then clamped". ]]
		local safeW = math.max(triggerWidth, safeWidthNow())
		local floor = if pickerMode
			then {
				type = "minMax",
				min = triggerWidth,
				preferred = math.clamp(widestRowEstimate(), triggerWidth, safeW),
				max = safeW,
			}
			else { type = "fixed", px = "controls.popup.panelWidth" }
		local panel = UI.VStack({
			id = if pickerMode and not isSheet then "Rows" else "Popup",
			anchor = if isSheet then "bottomLeft" elseif detached then nil else "topLeft",
			offsetY = if detached or isSheet then 0 else TRIGGER_HEIGHT,
			width = if pickerMode and not isSheet
				then { type = "fill", weight = 1 }
				elseif detached and not isSheet then floor
				else { type = "fill", weight = 1 },
			-- "raised" is the floating-panel role. This read `"panel"`, which is
			-- not a role the adapter or the style sheet knows, so the popup list
			-- rendered with NO background at all (found by Milestone 0 enum
			-- validation; an unrecognised role used to be silently ignored).
			-- An INLINE list is part of the trigger's own surface, so it takes the
			-- control role rather than a floating-panel one.
			surface = if presentation == "inline" then "control" else "raised",
			padding = if isSheet then "s" elseif pickerMode then { top = "xs", bottom = "xs" } else nil,
			-- the hairline of surface showing between rows — the recipe's token, so
			-- all three menus space their rows identically
			gap = menuRecipe.ROW_GAP,
			children = rows,
		})
		if not (pickerMode and not isSheet) then
			return panel
		end
		-- the FADE GROUP the materialize transition needs (the presenter's own
		-- toast-row shape): one CanvasGroup around the popover, sized by the
		-- floor above, so the panel grows in as one plate rather than row by row
		return UI.ZStack({
			id = "Popup",
			canvasGroup = true,
			width = floor,
			height = { type = "content" },
			children = { panel },
		})
	end

	-- the row id of the current selection, or nil when nothing is selected
	local function currentRowId(): string?
		local option = if multiple then nil else find(selection:get())
		return if option ~= nil and selectionModel.enabled(option) then `Opt-{keyOf(option)}` else nil
	end

	local function closeSurface()
		local handle = surfaceHandle
		surfaceHandle = nil
		if handle and dismissFn then
			dismissFn(handle)
		end
	end
	syncSurface = function()
		if not detached then
			return
		end
		if not open:get() or disposed then
			closeSurface()
			sheetFallback = false
			return
		end
		if surfaceHandle or not rootPath or not presentAnchoredFn or not presentModalFn then
			return
		end
		listShrink:set(0)
		feeds = 0
		local panel = contribution.attach(popupPanel(), {
			handleActivate = api.handleActivate,
			handleCancel = function()
				api.close()
				return true
			end,
			-- the measured half of `listMaxPx`: a panel that still runs past the
			-- viewport after a solve hands the excess to the list
			syncGeometry = if pickerMode
				then function(rectOf, node)
					if node == nil then
						return
					end
					local rect = rectOf(node.path)
					local env = envForFacts or spec.env
					local vp = if env ~= nil then env:get("viewportRect"):get() else nil
					if type(rect) ~= "table" or type(vp) ~= "table" then
						return
					end
					local over = math.max(-rect.y, rect.y + rect.h - vp.h)
					--[[ ...AND THE ATTACHMENT IS MEASURED TOO (visual review 2026-09-11):
						the placement clamps a panel that fits on neither side of its source
						OVER the control, so the panel must be no taller than the larger of
						the room below the source and the room above it; whatever it is
						taller by is handed back to the list's budget, one solve later,
						exactly like the viewport overflow beside it. Themed panel chrome the
						budget's own arithmetic cannot see (Fantasy Ornate's frame) is what
						this catches. Measured against the ROOM, never the panel's position:
						the anchored placement moves the panel on its own cadence, after this
						loop, so a position-based reading would shrink the same 12px eight
						times and trip the solver's feedback cap (seen on the landscape
						phone under Fantasy Ornate). ONLY ONCE PLACED: a fresh surface's
						first sync reports the panel at the origin. ]]
					local source = if presentationNow() == "sheet" or rect.x <= 0.5 then nil else anchorRect
					if type(source) == "table" and type(source.y) == "number" then
						local metricsNow = if env ~= nil then env:get("themeMetrics"):get() else nil
						local neutralNow = themeSnapshot.neutral()
						local spaceNow = if type(metricsNow) == "table" and type(metricsNow.space) == "table"
							then metricsNow.space
							else neutralNow.space
						local xs = if type(spaceNow.xs) == "number" then spaceNow.xs else neutralNow.space.xs
						local m = if type(spaceNow.m) == "number" then spaceNow.m else neutralNow.space.m
						local insets = env:get("coreSafeInsets"):get()
						local top = if type(insets) == "table" and type(insets.top) == "number" then insets.top else 0
						local room = math.max(vp.h - m - (source.y + source.h + xs), source.y - xs - top)
						over = math.max(over, rect.h - room)
						--[[ ...AND THE PLACED POSITION, because the presenter's safe box is
							not this arithmetic's (its own gutters and insets differ from the
							content margin by a few px under a themed package): a panel placed
							ABOVE the edge it should hang from has been pushed by exactly what
							it is too tall by. Converges because the shrink below is taken off
							the list's measured height and the feed count is bounded. ]]
						local below = rect.y + rect.h / 2 > source.y + source.h / 2
						local pushed = if below
							then (source.y + source.h + xs) - rect.y
							else (rect.y + rect.h) - (source.y - xs)
						over = math.max(over, pushed)
					end
					--[[ BOUNDED, NOT PROGRESS-GATED: a feed that shortened the LIST but not
						the panel (Fantasy Ornate's frame at +10 on a landscape phone: 7px
						over the room) used to stop the loop after one round and leave the
						menu clamped over its trigger. Six feeds is under the solver's cap
						and more than any themed chrome has needed. ]]
					if over > 0.5 and feeds < 6 then
						local _, atFloor = listMaxPx(presentationNow())
						if atFloor and not sheetFallback then
							-- the list cannot give any more: re-present as the sheet
							sheetFallback = true
							closeSurface()
							syncSurface()
							return
						end
						feeds += 1
						--[[ THE SHRINK IS TAKEN OFF THE LIST'S MEASURED HEIGHT, not off the
							budget: a hugging list already below its budget (three rows under
							an ornate frame that is the bigger half of the panel) does not move
							when only its ceiling comes down, so the ceiling is set to what the
							list IS less the overrun — one feed, one fit. ]]
						local listRect = rectOf(node.path .. "/Rows/List")
						local ceiling = listMaxPx(presentationNow())
						local wanted = if type(listRect) == "table" and type(listRect.h) == "number"
							then listRect.h - math.ceil(over)
							else ceiling - math.ceil(over)
						listShrink:set(listShrink:get() + math.max(1, math.ceil(ceiling - wanted)))
					end
				end
				else nil,
		})
		local surfaceId = `Popup-{id}`
		local handle
		if presentationNow() == "sheet" then
			handle = presentModalFn(
				UI.Screen({
					id = surfaceId,
					children = {
						UI.Anchor({
							id = "Layer",
							width = { type = "fill", weight = 1 },
							height = { type = "fill", weight = 1 },
							children = { panel },
						}),
					},
				}),
				{ scrim = "scrim", outsideTapCancel = true, cancelPolicy = "none" }
			)
		else
			handle = presentAnchoredFn(panel, {
				id = surfaceId,
				modal = true,
				-- a form row's value sits at the trailing edge, so its menu hangs
				-- from that edge; a pop-up button's menu hangs from its leading one
				--[[ A PLAIN TRIGGER HAS NO VISIBLE BOX (the touch form row), so the
					menu hangs from the CHEVRON — the last thing the eye sees — with its
					trailing edges flush and a tight gap beneath the glyphs; a bordered
					pop-up button hangs from its own frame at the leading edge. Both keep
					the screen's content inset (`margin`). Visual review 2026-09-11. ]]
				anchor = {
					source = { path = anchorSourcePath() },
					edge = "bottom",
					align = if rowForm then "end" else "start",
					gap = "xs",
					margin = "m",
				},
				scrim = "none",
				outsideTapCancel = true,
				cancelPolicy = "none",
				-- the short fade-and-grow every pop-up menu materializes with
				transition = if pickerMode then { enter = "materialize" } else nil,
				-- ...opening on the CURRENT value, the pop-up button rule: the row
				-- under the focus ring is the one the player already has
				initialFocus = if pickerMode then currentRowId() else nil,
			})
		end
		surfaceHandle = handle
		if handle.onFeedback then
			handle.onFeedback(function(event)
				if event.type == "dismiss" and surfaceHandle == handle then
					surfaceHandle = nil
					open:set(false)
				end
			end)
		end
	end
	scope:own(core:observe(open, syncSurface))
	scope:own(closeSurface)
	local inlineOpen = scope:own(core:memo(function(use)
		return not detached and use(open)
	end))

	--[[ THE TRIGGER: ONE BUTTON, value and chevron inside it (B-BTN1: a Button
		is a container, so the visible text moves into content and `label` stays
		the semantic name). The chevron is the framework's ASCII-safe glyph
		carrying the semantic icon NAME, so a theme package paints its art over
		it; on a phone's form row the value is the secondary colour on a plain
		surface (the menu picker), everywhere else it is a bordered control that
		HUGS its content (the pop-up button). The navigation link wears the
		trailing chevron instead: it leads somewhere rather than dropping down. ]]
	local navLink = spec.style == "navigationLink"
	local chevronName = if navLink then "chevron.trailing" else "chevron.up.chevron.down"
	local valueRole = scope:own(core:memo(function(use)
		--[[ CONTENT on every class (measured live 2026-09-11: the secondary
			role's gold on Fantasy Ornate and its grey on Glossy Touch both
			vanished into their own focus glow on a plain touch trigger). The
			plain surface is what makes the touch row read as a value rather than a
			button; the word itself keeps the colour every other value has. ]]
		return "content"
	end))
	--[[ THE TRIGGER ALWAYS HAS A BOX (user review of the Glossy Touch capture,
		2026-09-11: "the menu doesn't have a background, just a glow"). A plain
		value on a touch form row is the reference platform's look on a FLAT
		package; under a skinned package a bare word beside a plated menu read as
		a control with no background at all, and the moment the menu opened and
		took the focus halo with it, nothing was left. The value is a `control`
		surface on every input class — the same pop-up button the desktop draws,
		which every package paints and whose `selected` state stays lit while the
		menu is up. The navigation link keeps its plain row. ]]
	local triggerSurface = scope:own(core:memo(function(use)
		return if navLink and use(touchPrimary) then "plain" else "control"
	end))
	--[[ THE FORM ROW GOES VERTICAL AT ACCESSIBILITY SIZES — a FACT, not a
		measurement: at the two largest text preferences the title takes the
		whole row and the trigger sits beneath it, which is what the reference
		platform's own labelled rows do at accessibility type sizes. Below that the
		title fills and wraps beside a trigger that hugs its one-line value. ]]
	--[[ ...and one step earlier on a COMPACT screen: at the Large preference a
		localized title's longest word (~1.4x, 21px) no longer fits the room a
		capped trigger leaves beside it on a 320px row (the picker sweep, glossy
		phone, 2026-09-11), and a word that cannot wrap can only truncate. ]]
	local rowAxis = scope:own(core:memo(function(use)
		local offset = if envForFacts ~= nil then use(envForFacts:get("preferredTextOffset")) else 0
		if type(offset) ~= "number" then
			return "x"
		end
		local compact = readFact(sizeClassSource) == "compact"
		if type(sizeClassSource) == "table" and (sizeClassSource :: any).get ~= nil then
			compact = use(sizeClassSource) == "compact"
		end
		return if offset >= 10 or (offset >= 4 and compact) then "y" else "x"
	end))
	local requestedSizing = spec.sizing
	assert(
		requestedSizing == nil or requestedSizing == "hug" or requestedSizing == "fill",
		"Picker menu: sizing must be hug | fill"
	)
	-- ...and it never takes more than a share of the screen's width, so the
	-- title beside it always keeps room to wrap (a cap, not a size: a short
	-- value still hugs). The viewport is the ruler because a form row's own
	-- offer is what this cap exists to protect.
	local VALUE_SHARE = 0.35
	local TRIGGER_SHARE = 0.45
	local function viewportWidth(use)
		local vp = if envForFacts ~= nil then use(envForFacts:get("viewportRect")) else nil
		return if type(vp) == "table" and type(vp.w) == "number" then vp.w else 1280
	end
	--[[ THE STACKED ROW HAS THE WHOLE LINE (visual review 2026-09-11, Glossy
		Touch at the largest preference): when the title sits above the trigger
		(`rowAxis` y) the value's cap is the row less the chevron and the trigger's
		own chrome, not a share of the viewport — a share measured for the
		side-by-side form made the engine's wider glyphs shrink the value to its
		compact rung inside a box reserved at the large one, and the chevron sat
		60px away from the word it belongs to. ]]
	local CHEVRON_ROOM = 64
	local valueWidth = scope:own(core:memo(function(use)
		local vp = viewportWidth(use)
		if use(rowAxis) == "y" then
			return { type = "hug", max = math.max(48, vp - 32 - CHEVRON_ROOM) }
		end
		return { type = "hug", max = math.max(48, math.floor(vp * VALUE_SHARE)) }
	end))
	-- ...and the TRIGGER itself, because a theme's own padding and chevron sit
	-- outside the value: under a roomy package the plate around a capped value
	-- still ate the title's room (the sweep's glossy phone row, 2026-09-11)
	local triggerCap = scope:own(core:memo(function(use)
		local vp = viewportWidth(use)
		if use(rowAxis) == "y" then
			return { type = "hug", max = math.max(96, vp - 32) }
		end
		return { type = "hug", max = math.max(96, math.floor(vp * TRIGGER_SHARE)) }
	end))
	local TRIGGER_FILL = table.freeze({ type = "fill", weight = 1 })
	local TRIGGER_HUG = table.freeze({ type = "content" })
	local triggerWidthDim = scope:own(core:memo(function(use)
		if not pickerMode or navLink then
			-- the legacy popup and the navigation link are ROWS: they fill
			return TRIGGER_FILL
		end
		if rowForm then
			return use(triggerCap)
		end
		local sizing = requestedSizing or (if use(touchPrimary) then "fill" else "hug")
		return if sizing == "hug" then TRIGGER_HUG else TRIGGER_FILL
	end))
	--[[ THE VALUE IS ONE LINE AND MAY TRUNCATE, with the full string one engagement
		away (`disclose`, the large-text plate) — and in the menu itself, a tap
		away. A value that wrapped would grow the trigger past its row; a value
		that could not shrink would push the title off the screen, which is what
		the overflow sweep found on a 320px phone at the largest preference. ]]
	local function valueViews(): { any }
		return {
			UI.Text({
				id = "Value",
				text = selectedLabel,
				textSize = spec.textSize or "control",
				role = valueRole,
				lineLimit = 1,
				disclose = true,
				width = if pickerMode then valueWidth else UI.hug(),
			}),
			chrome_slots.attachHint(
				UI.Text({
					id = "Chevron",
					text = themePackage.iconGlyph(chevronName) or (if navLink then ">" else "^v"),
					textSize = "caption",
					role = valueRole,
				}),
				{ icon = chevronName, iconSize = "small" }
			),
		}
	end
	local function contentViews(): { any }
		local views = valueViews()
		if navLink and spec.label ~= nil then
			return {
				UI.AdaptiveStack({
					id = "Row",
					axis = rowAxis,
					width = { type = "fill", weight = 1 },
					gap = "xs",
					align = "center",
					children = {
						UI.Text({
							id = "Label",
							text = spec.label,
							textSize = spec.textSize or "control",
							width = { type = "fill", weight = 1 },
						}),
						UI.HStack({ id = "Trailing", gap = "xs", width = UI.hug(), align = "center", children = views }),
					},
				}),
			}
		end
		return views
	end
	local openNow = scope:own(core:memo(function(use)
		return use(open) == true
	end))
	local function labelView()
		return UI.Text({
			id = "Label",
			text = spec.label,
			textSize = spec.textSize or "control",
			width = { type = "fill", weight = 1 },
		})
	end
	--[[ THE TOUCH FORM ROW IS ONE ROW (user review of the side-by-side,
		2026-09-11): the title and the value + chevron sit on one line, value and
		chevron flush trailing, no box — the whole row is the tap target, exactly
		as the reference platform's phone form rows are. A pointer or a pad keeps
		the boxed pop-up button beside the title, centred on the title's line,
		because those surfaces need a visible affordance. The two are structural
		(a `UI.When` each) and follow the live primary input class. ]]
	local function touchRowTrigger()
		return UI.Button({
			id = "Trigger",
			label = selectedLabel,
			surface = "plain",
			selected = openNow,
			width = { type = "fill", weight = 1 },
			height = { type = "minMax", min = TRIGGER_HEIGHT },
			gap = "xs",
			align = "center",
			children = {
				UI.AdaptiveStack({
					id = "Row",
					axis = rowAxis,
					width = { type = "fill", weight = 1 },
					gap = "xs",
					align = "center",
					children = {
						labelView(),
						UI.HStack({
							id = "Trailing",
							gap = "xs",
							width = UI.hug(),
							align = "center",
							children = contentViews(),
						}),
					},
				}),
			},
		})
	end
	local function boxedTrigger()
		local button = UI.Button({
			id = "Trigger",
			label = selectedLabel,
			anchor = if rowForm then nil else "topLeft",
			surface = triggerSurface, -- control everywhere but a plain touch navigation link
			-- lit while its menu is up (the `selected` state of whichever slot this
			-- trigger paints as — see the decoration hint below)
			selected = if pickerMode then openNow else nil,
			width = triggerWidthDim,
			height = if detached
				then { type = "minMax", min = TRIGGER_HEIGHT }
				else { type = "fixed", px = TRIGGER_HEIGHT },
			gap = "xs",
			align = "center",
			children = contentViews(),
		})
		if navLink then
			--[[ THE NAVIGATION LINK IS THE ONE TRIGGER WHOSE SURFACE MOVES. It is
				`plain` on a touch row and `control` elsewhere (`triggerSurface` above),
				and a decoration hint is STATIC metadata on a blueprint — so hinting
				`control` here would paint a plate on the very row whose whole point is
				that it has none. It keeps the generic classification; see the report. ]]
			return button
		end
		--[[ A CLOSED TRIGGER IS A CONTROL, AND IT HAS TO SAY SO (user feedback
			item 8, 2026-09-12: "a closed trigger must paint its control surface in
			every theme; the glow alone is wrong").

			`chrome_slots.classify` routes a node to the `selection` slot on
			`hasSelection` — which `render/layout_node` and `client/screen_chrome` both
			derive from `props.selected ~= nil`, a DECLARATION and not a state. This
			trigger declares `selected` precisely so its OPEN state can light up, so a
			CLOSED pop-up button was taking the row-selection plate in every package:
			measured through the same `classify` the solver and the adapter both call,
			`{ class = "Button", surface = "control", hasSelection = true }` answered
			`selection`. Under Glossy Touch that is `glossy_selection_default` — a flat
			near-white wash — where `glossy_button_default`'s gel belongs, which is the
			"no background, just a glow" in the capture; under Fantasy Ornate it is a
			frameless plum plate beside every framed button on the same screen.

			THE HINT IS `classify`'s FIRST CLAUSE ("THE HINT WINS"), so this is the
			supported way for a control that knows its own slot to say so, and it
			reaches BOTH consumers through the one meta channel — the insets
			`layout_node` reserves and the art `screen_chrome` materializes cannot
			split. The open state is unaffected: every skinned package compiles a
			`.facet-selected > .facet-chrome-control` rule, so `selected = openNow`
			still lights the trigger while its menu is up. ]]
		return chrome_slots.attachHint(button, { slot = "control" })
	end
	local head
	if rowForm then
		head = UI.VStack({
			id = "Form",
			anchor = "topLeft",
			width = { type = "fill", weight = 1 },
			children = {
				UI.When({ id = "TouchRow", condition = touchPrimary, thenView = touchRowTrigger }),
				UI.When({
					id = "PointerRow",
					condition = scope:own(core:memo(function(use)
						return not use(touchPrimary)
					end)),
					thenView = function()
						return UI.AdaptiveStack({
							id = "Row",
							axis = rowAxis,
							width = { type = "fill", weight = 1 },
							gap = "s",
							align = "center",
							children = { labelView(), boxedTrigger() },
						})
					end,
				}),
			},
		})
	else
		head = boxedTrigger()
	end
	triggerPath = function(): string
		if not rowForm then
			return (rootPath :: string) .. "/Trigger"
		end
		return (rootPath :: string)
			.. (
				if touchPrimary:get() == true
					then "/Form/TouchRow/then/Trigger"
					else "/Form/PointerRow/then/Row/Trigger"
			)
	end

	local blueprint = UI.Anchor({
		id = id,
		enabled = enabled,
		width = if pickerMode and not rowForm then triggerWidthDim else { type = "fill", weight = 1 },
		height = if detached then { type = "minMax", min = TRIGGER_HEIGHT } else { type = "fill", weight = 1 },
		children = {
			head,
			UI.When({
				id = "PopupWhen",
				condition = inlineOpen,
				thenView = popupPanel,
			}),
		},
	})

	-- deterministic diagnostic summary (§10.2 control contract dump form;
	-- uniform seam: every composite control exposes dump())
	local function dump()
		local dumpedOptions = {}
		for _, option in options:get() do
			-- a divider is reported AS a divider rather than as an option with no
			-- id: a dump that showed `{}` here would read as a corrupt option
			if option.divider == true then
				table.insert(dumpedOptions, { divider = true })
			else
				table.insert(dumpedOptions, { id = option.id, label = option.label, icon = option.icon })
			end
		end
		return {
			schema = if pickerMode then "facet-picker-menu-dump/1" else "facet-popup_button-dump/1",
			style = spec.style,
			presentation = presentationNow(),
			selected = if pickerMode then selection:get() else nil,
			rowForm = rowForm,
			-- where the adaptive facts came from: "spec" (authored) or "core" (the
			-- surface's environment, with no wiring at all)
			factsFrom = factsFrom,
			id = id,
			open = open:get(),
			value = if not multiple then selection:get() else nil,
			selectedValues = if multiple then selection:get() else nil,
			query = if spec.query then spec.query:get() else nil,
			resultCount = #results:get(),
			selectedLabel = selectedLabel:get(),
			options = dumpedOptions,
		}
	end

	return {
		-- attach the input contribution: the presenter auto-routes open/select/
		-- cancel Activate to handleActivate with no consumer opts.
		-- The open option rows are ordinary focusables the flat ring picks up, so
		-- no focusGroups are contributed. The three transient-popup fields close the
		-- matrix §B PopupButton parity GAPs while the popup is a non-modal UI.When:
		--   handleCancel  — gamepad ButtonB closes the open popup (no selection change)
		--   outsideDismiss — a tap outside the popup dismisses it (scrim catcher +
		--                    onNodeTap path test); active tracks `open`, dismiss = close
		--   transientScope — focus is trapped in the control while open and restores
		--                    to the trigger on close (rootPath defaults to the control
		--                    root, keeping the trigger as the scope entry)
		blueprint = contribution.attach(blueprint, {
			bindInputScope = function(inputScope)
				inputScope.onDispose(function()
					open:set(false)
					closeSurface()
					rootPath, mountedNode = nil, nil
					presentModalFn, presentAnchoredFn, dismissFn = nil, nil, nil
				end)
			end,
			bindPresent = function(presentModal, dismiss, presentAnchored)
				presentModalFn, dismissFn, presentAnchoredFn = presentModal, dismiss, presentAnchored
				syncSurface()
			end,
			syncGeometry = function(rectOf, node)
				mountedNode = node
				if node then
					rootPath = node.path
					local rect = rectOf(triggerPath())
					if type(rect) == "table" and type(rect.w) == "number" then
						triggerRect = rect
						-- the popover's width floor is the CONTROL the eye sees: on the
						-- touch form row that is the value + chevron, not the whole row
						local visible = if rowForm and touchPrimary:get() == true
							then rectOf(triggerPath() .. "/Row/Trailing")
							else nil
						triggerWidth = if type(visible) == "table" and type(visible.w) == "number"
							then visible.w
							else rect.w
					end
					local sourceRect = rectOf(anchorSourcePath())
					anchorRect = if type(sourceRect) == "table" then sourceRect else rect
				end
				syncSurface()
				if not available() and not disposed then
					open:set(false)
				end
			end,
			handleActivate = api.handleActivate,
			handleCancel = function(_focusedPath: string?): boolean
				if open:get() then
					open:set(false) -- close WITHOUT changing the selection
					return true
				end
				return false
			end,
			outsideDismiss = {
				active = inlineOpen,
				dismiss = function()
					open:set(false)
				end,
			},
			transientScope = {
				active = inlineOpen,
			},
		}),
		api = api,
		-- the resolved presentation (B-DSP3), exposed on the control itself so a
		-- consumer and a test can read the idiom without reaching into `api`
		presentation = presentationNow,
		dump = dump,
		dispose = function()
			scope:dispose()
		end,
	}
end

return popup_button
