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
	scope:own(function()
		disposed = true
	end)
	local function available()
		return not disposed and not controlContract.isDisabled(mountedNode) and controlContract.enabledNow(spec.enabled)
	end

	local pickerMode = spec.style ~= nil
	assert(not pickerMode or STYLES[spec.style], "Picker menu: style must be menu | navigationLink")
	-- a labelled picker is a FORM ROW: title leading, value + chevron trailing
	local rowForm = pickerMode and spec.label ~= nil
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
		if string.match(path, if rowForm then `/{idPattern}/Row/Trigger$` else `/{idPattern}/Trigger$`) ~= nil then
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
			if detached then "/Popup/.-Opt%-(.+)$" else `/{idPattern}/PopupWhen/then/Popup/.-Opt%-(.+)$`
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
			markHidden = hidden,
			height = "targetSizes.minimum",
		})
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
			return math.min(use(metrics).targetSizes.minimum * 5, use(env:get("viewportRect")).h * 0.4)
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
	local function popupPanel()
		local presentation = presentationNow()
		local rowHeight = menuRecipe.rowHeightFor(presentation)
		local rows = {}
		if virtualList then
			table.insert(rows, searchField.blueprint)
			table.insert(rows, virtualList.blueprint)
			table.insert(rows, UI.Text({ id = "Empty", text = "No matching options", hidden = emptyHidden }))
		elseif dynamicOptions or multiple then
			table.insert(
				rows,
				UI.ForEach({
					id = "Options",
					items = results,
					key = keyOf,
					row = optionRow,
				})
			)
		else
			for _, row in staticRows do
				if row.class == "Button" then
					local props = table.clone(row.props)
					props.id = row.id
					props.height = if detached
						then { type = "minMax", min = rowHeight }
						else { type = "fixed", px = rowHeight }
					props.children = row.children
					table.insert(rows, UI.Button(props))
				else
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
		local floor = if pickerMode
				and not describedOptions
				and spec.query == nil
			then { type = "minMax", min = math.max(triggerWidth, 0) }
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
			padding = if isSheet then "s" else nil,
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
			return
		end
		if surfaceHandle or not rootPath or not presentAnchoredFn or not presentModalFn then
			return
		end
		local panel = contribution.attach(popupPanel(), {
			handleActivate = api.handleActivate,
			handleCancel = function()
				api.close()
				return true
			end,
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
				anchor = {
					source = { path = triggerPath() },
					edge = "bottom",
					align = if rowForm then "end" else "start",
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
		return if pickerMode and use(touchPrimary) then "secondary" else "content"
	end))
	local triggerSurface = scope:own(core:memo(function(use)
		return if rowForm and use(touchPrimary) then "plain" else "control"
	end))
	local requestedSizing = spec.sizing
	assert(
		requestedSizing == nil or requestedSizing == "hug" or requestedSizing == "fill",
		"Picker menu: sizing must be hug | fill"
	)
	local TRIGGER_FILL = table.freeze({ type = "fill", weight = 1 })
	local TRIGGER_HUG = table.freeze({ type = "content" })
	local triggerWidthDim = scope:own(core:memo(function(use)
		if not pickerMode then
			return TRIGGER_FILL
		end
		if rowForm then
			return if navLink then TRIGGER_FILL else TRIGGER_HUG
		end
		local sizing = requestedSizing or (if use(touchPrimary) then "fill" else "hug")
		return if sizing == "hug" then TRIGGER_HUG else TRIGGER_FILL
	end))
	local trigger = UI.Button({
		id = "Trigger",
		label = selectedLabel,
		anchor = if rowForm then nil else "topLeft",
		surface = triggerSurface,
		width = triggerWidthDim,
		height = if detached
			then { type = "minMax", min = TRIGGER_HEIGHT }
			else { type = "fixed", px = TRIGGER_HEIGHT },
		gap = "xs",
		children = {
			UI.Text({
				id = "Value",
				text = selectedLabel,
				textSize = spec.textSize or "control",
				role = valueRole,
				width = UI.hug(),
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
		},
	})
	--[[ THE FORM ROW: title at the leading edge, trigger at the trailing one,
		and a WRAPPING row rather than a fixed pair — under a large text
		preference the trigger drops to its own line beneath the title instead of
		squeezing it to an ellipsis, which is what the reference platform's own
		labelled rows do at accessibility sizes. ]]
	local head = if rowForm
		then UI.HStack({
			id = "Row",
			anchor = "topLeft",
			width = { type = "fill", weight = 1 },
			gap = "s",
			wrap = true,
			distribute = "spaceBetween",
			children = {
				UI.Text({
					id = "Label",
					text = spec.label,
					textSize = spec.textSize or "control",
					width = UI.hug(),
				}),
				trigger,
			},
		})
		else trigger
	triggerPath = function(): string
		return (rootPath :: string) .. (if rowForm then "/Row/Trigger" else "/Trigger")
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
						triggerWidth = rect.w
					end
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
