--!strict
-- PopupButton control (a composite; the menu-picker
-- informed). A COMPOSITE over shipped primitives: a single focusable Button
-- (the "trigger") shows the currently-selected option's label; activating it
-- opens a popup — a floating panel of activatable option rows plus a Cancel
-- row — via the ONE structural seam (UI.When on an `open` signal). Activating
-- an option writes the OWNER-HELD `value` signal, fires onChange, and closes;
-- the trigger's label is a binding on `value`, so a selection relabels the
-- button with zero structural churn. Re-activating the trigger, or the Cancel
-- row, closes without touching the selection. The open panel's rows are
-- ordinary focusable Buttons, so the presenter's focus ring picks them up on
-- refresh — keyboard/gamepad users navigate the options and Activate to pick;
-- closed, only the trigger is focusable. Selection state that must outlive the
-- control lives in the caller's `value` signal (§10.5), never inside here.
-- Engine-free; Lune-tested in tests/popup_button.spec.luau.

local controlContract = require("../class_contract")
local coreContract = require("../core/contract")
local selectionModel = require("../selection_model")
local contribution = require("../input/contribution")
local menuRecipe = require("./menu_recipe")
local specGuard = require("../spec_guard")
local surfaceEnv = require("../env/surface_env")
local paths = require("../paths")
local themeSnapshot = require("../themes/snapshot")

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
	label: (string | coreContract.Readable<string>)?,
	icon: (string | coreContract.Readable<string>)?, -- semantic icon NAME, never an asset id
	divider: boolean?,
}

local OPTION_KEYS = specGuard.keySet({ "divider", "enabled", "icon", "id", "label", "description" })

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
	local dynamicOptions = type(spec.options) == "table" and spec.options.kind ~= nil
	local describedOptions = false
	if not dynamicOptions and type(spec.options) == "table" then
		for _, option in spec.options do
			if type(option) == "table" and option.description ~= nil then
				describedOptions = true
			end
		end
	end
	local detached = (spec.query ~= nil or spec.selectedValues ~= nil or dynamicOptions or describedOptions)
		and spec.presentation ~= "inline"
	scope:own(function()
		disposed = true
	end)
	local function available()
		return not disposed and not controlContract.isDisabled(mountedNode) and controlContract.enabledNow(spec.enabled)
	end

	local multiple = spec.selectedValues ~= nil
	assert((spec.value ~= nil) ~= multiple, "PopupButton: provide exactly one of value or selectedValues")
	local selection = if multiple then spec.selectedValues else spec.value
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
	else
		assert(
			selection:get() == nil or type(selection:get()) == "string",
			"PopupButton: value must hold a string or nil"
		)
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
			assert(
				type(option.id) == "string" and option.id ~= "" and not string.find(option.id, "/", 1, true),
				"PopupButton: option id must be a nonempty path-safe string"
			)
			assert(not seen[option.id], `PopupButton: duplicate option id '{option.id}'`)
			seen[option.id] = true
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
	local function find(optionId, use)
		return selectionModel.find(if use then use(options) else options:get(), optionId)
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
	local function select(optionId: string?)
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
		if string.match(path, `/{idPattern}/Trigger$`) ~= nil then
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
		local optionId = string.match(
			path,
			if detached then "/Popup/.-Opt%-(.+)$" else `/{idPattern}/PopupWhen/then/Popup/.-Opt%-(.+)$`
		)
		if optionId ~= nil and find(optionId) ~= nil then
			select(optionId)
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
	function api.select(optionId: string)
		select(optionId)
	end
	api.isOpen = open

	local requestedPresentation = spec.presentation or "automatic"
	assert(
		PRESENTATIONS[requestedPresentation],
		`PopupButton '{id}': unknown presentation '{requestedPresentation}' (automatic | menu | inline | sheet)`
	)

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
	if requestedPresentation == "automatic" and (spec.sizeClass == nil or spec.interactionClasses == nil) then
		local env, source = surfaceEnv.resolve(
			"newPopupButton",
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
		if requestedPresentation ~= "automatic" then
			return requestedPresentation
		end
		-- PRIMARY, not merely present: the one predicate, in the recipe
		local touchLive = menuRecipe.touchPrimary(readFact(classesSource))
		-- the SELECTABLE count, not the array length: a divider is a rule between
		-- groups, and a menu does not become "long" because it was grouped
		return menuRecipe.resolvePresentation(#results:get(), readFact(sizeClassSource), touchLive)
	end
	api.presentation = presentationNow

	local function optionRow(option, rowScope)
		local function property(name)
			return rowScope:own(core:memo(function(use)
				local current = find(option.id, use)
				local value = if current then selectionModel.read(current[name], use) else nil
				return if name == "description" then (value or "") else value
			end))
		end
		local selected = rowScope:own(core:memo(function(use)
			local current = use(selection)
			return if multiple then current[option.id] == true else current == option.id
		end))
		local hidden = rowScope:own(core:memo(function(use)
			return not use(selected)
		end))
		return menuRecipe.row(UI, {
			id = `Opt-{option.id}`,
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
			indicator = if multiple then "check" elseif spec.query then "radio" else nil,
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
			key = function(option)
				return option.id
			end,
			itemExtent = "measured",
			estimatedItemExtent = rowHeight,
			viewportExtent = viewport,
			width = { type = "fill", weight = 1 },
			rowFocusable = function(option)
				return selectionModel.enabled(find(option.id))
			end,
			onActivate = function(option)
				select(option.id)
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
					key = function(option)
						return option.id
					end,
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
		-- an INLINE list has no floating surface to dismiss by tapping away from, so
		-- it keeps the explicit Cancel row; a sheet keeps it too (a finger needs a
		-- visible way out). Only the pointer MENU relies on tap-away alone... and it
		-- keeps Cancel as well, because that behaviour is already proven and this row
		-- is about presentation, not about removing an affordance.
		table.insert(
			rows,
			UI.Button({
				id = "Cancel",
				label = "Cancel",
				width = { type = "fill", weight = 1 },
				height = if detached then { type = "minMax", min = rowHeight } else { type = "fixed", px = rowHeight },
			})
		)
		-- MENU / INLINE sit just below the trigger; a SHEET anchors to the bottom
		-- edge, which is where a thumb reaches. Either way the panel OVERLAYS
		-- following content (the root is an Anchor) rather than pushing layout, so
		-- the transient-surface machinery — outsideDismiss, transientScope,
		-- handleCancel — is untouched by the presentation choice: it keys on `open`.
		local isSheet = presentation == "sheet"
		return UI.VStack({
			id = "Popup",
			anchor = if isSheet then "bottomLeft" elseif detached then nil else "topLeft",
			offsetY = if detached or isSheet then 0 else TRIGGER_HEIGHT,
			width = if detached and not isSheet
				then { type = "fixed", px = "controls.popup.panelWidth" }
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
				anchor = { source = { path = rootPath .. "/Trigger" }, edge = "bottom", align = "start" },
				scrim = "none",
				outsideTapCancel = true,
				cancelPolicy = "none",
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

	local blueprint = UI.Anchor({
		id = id,
		enabled = enabled,
		width = { type = "fill", weight = 1 },
		height = if detached then { type = "minMax", min = TRIGGER_HEIGHT } else { type = "fill", weight = 1 },
		children = {
			UI.Button({
				id = "Trigger",
				label = selectedLabel,
				anchor = "topLeft",
				width = { type = "fill", weight = 1 },
				height = if detached
					then { type = "minMax", min = TRIGGER_HEIGHT }
					else { type = "fixed", px = TRIGGER_HEIGHT },
			}),
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
			schema = "facet-popup_button-dump/1",
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
			syncGeometry = function(_rectOf, node)
				mountedNode = node
				if node then
					rootPath = node.path
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
