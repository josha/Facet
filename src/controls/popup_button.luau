--!strict
-- PopupButton control (ADR-0007 composite; NSPopUpButton / SwiftUI Menu-picker
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

local contribution = require("../input/contribution")
local menuRecipe = require("./menu_recipe")
local specGuard = require("../spec_guard")

-- a node id is interpolated into a Lua PATTERN below, so its magic characters
-- have to be escaped first. Module scope, not per-instance: it is a pure
-- function of its argument and every `build()` used to allocate its own
-- (Step 5.5 cleanup ledger C-06).
local function patternEscape(s: string): string
	return (s:gsub("%W", "%%%0"))
end

local popup_button = {}

--[[ AN OPTION IS A VALUE, AND `icon` / `divider` ARE ITS TWO NEW SPELLINGS
	(navigation-and-menus D2, so `r1`'s icon rows work and both menus render from
	one row recipe). This stays a VALUE picker — `value` is a `Signal<string>` and
	picking writes it. A list of VERBS is `LuauUI.newMenu`, which is a different
	control on purpose: a control that sometimes owns a value Signal and sometimes
	does not is two controls in one.

	`divider = true` is a rule between two groups. It carries no id, no label and
	no selection, and it is skipped by every count, every route and the dump —
	which is what makes it a grouping mark rather than an option that happens to
	do nothing when you press it. ]]
export type Option = {
	id: string?,
	label: string?,
	icon: string?, -- semantic icon NAME, never an asset id
	divider: boolean?,
}

local OPTION_KEYS = specGuard.keySet({ "divider", "icon", "id", "label" })

export type Spec = {
	id: string?,
	options: { Option },
	value: any, -- Signal<string>: the selected option id (owner-held)
	onChange: ((id: string) -> ())?,
	-- adaptive presentation (B-DSP3): "automatic" (default) resolves from the
	-- option count, the space class, and whether touch is a LIVE class
	presentation: string?, -- automatic | menu | inline | sheet
	sizeClass: any?, -- string | Readable<string>, e.g. adaptive.conditions().sizeClass
	interactionClasses: any?, -- table | Readable<table>, e.g. env interactionClasses
}

-- THEME METRICS (ADR-0019 §2). This control's own trigger keeps its own metric;
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

-- CLOSED SPEC (constitution §4; ARCH-1). Exactly the fields this control
-- reads — an unknown one is an authoring mistake, never a silent no-op.
local POPUP_BUTTON_KEYS = specGuard.keySet({
	"id",
	"interactionClasses",
	"onChange",
	"options",
	"presentation",
	"sizeClass",
	"value",
})

function popup_button.build(LuauUI: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("newPopupButton", spec, POPUP_BUTTON_KEYS, "spec")
	local UI = LuauUI.UI
	local id = spec.id or "PopupButton"
	local scope = core:scope(`popup_button-{id}`)

	assert(type(spec.options) == "table" and #spec.options > 0, `PopupButton '{id}': options must be a non-empty array`)
	-- a read-only Memo has kind "memo" and a :set that asserts, so accepting one
	-- here deferred the crash to the user's FIRST selection (`select()` writes
	-- `value`) — reject it at BUILD, exactly as the six siblings do (CTRL-01)
	if type(spec.value) ~= "table" or (spec.value :: any).kind ~= "signal" then
		error(
			`LuauUI newPopupButton('{id}'): \`value\` must be a SETTABLE Signal<string> the caller owns `
				.. `(the control never creates it, because the selection must outlive the control)`,
			0
		)
	end

	-- option ids become `Opt-<id>` path segments; a "/" would corrupt routing
	-- everywhere downstream — fail at BUILD (ADR-0010), not first render.
	-- A DIVIDER is skipped by all of it: no id, no route, no selection.
	local optionsById: { [string]: Option } = {}
	local selectableCount = 0
	for index, option in spec.options do
		specGuard.assertKnownKeys("newPopupButton", option, OPTION_KEYS, `spec.options[{index}]`)
		if option.divider == true then
			continue
		end
		assert(
			type(option.id) == "string" and type(option.label) == "string",
			`PopupButton '{id}': option {index} needs an id and a label `
				.. "(or divider = true to draw a rule between two groups)"
		)
		assert(
			not string.find(option.id :: string, "/", 1, true),
			`PopupButton '{id}': option id '{option.id}' must be path-safe (no "/")`
		)
		optionsById[option.id :: string] = option
		selectableCount += 1
	end
	--[[ THE HIG'S ICON LINT, at authoring time (D2): "provide icons for all menu
		items in a group, or none of them". A group is the run between two dividers,
		which is why this is checkable at all — the author already said where the
		groups are. A half-iconned group looks fine in the one fixture it was
		authored in and reads as a rendering bug everywhere else. ]]
	local mixed = menuRecipe.mixedIconGroup(spec.options)
	assert(
		mixed == nil,
		`PopupButton '{id}': the option group starting at index {tostring(mixed)} mixes options that declare an `
			.. "icon with options that do not. Give every option in a group an icon, or none of them "
			.. "(HIG: Menus). A divider = true option starts a new group."
	)

	-- open/closed is the control's only owned state; selection lives in `value`
	local open = scope:own(core:signal(false))

	-- the trigger label tracks the selected option (a binding, not a rebuild).
	-- Fallback to the raw id keeps the button truthful if `value` holds an id
	-- that is not (yet) among the options.
	local selectedLabel = scope:own(core:memo(function(use)
		local current = use(spec.value)
		local option = optionsById[current]
		return if option ~= nil then option.label else tostring(current)
	end))

	-- per-option "is this the current selection?" memos, owned by the control
	-- scope so open/close never churns them (options are static)
	local selectedMemoById: { [string]: any } = {}
	for optionId in optionsById do
		selectedMemoById[optionId] = scope:own(core:memo(function(use)
			return use(spec.value) == optionId
		end))
	end

	local api = {} :: any

	local idPattern = patternEscape(id)

	-- commit a selection: write the owner signal (firing onChange only on a
	-- real change), then close. Re-picking the current option just closes.
	local function select(optionId: string)
		if optionsById[optionId] == nil then
			return
		end
		if spec.value:get() ~= optionId then
			spec.value:set(optionId)
			if spec.onChange ~= nil then
				spec.onChange(optionId)
			end
		end
		open:set(false)
	end

	-- routes a presenter/tap Activate; returns true when the path was ours.
	-- Trigger toggles open; Cancel and a re-open-toggle close with no change;
	-- an option row selects. meta is accepted for signature parity with the
	-- other controls (no modifier semantics here).
	function api.handleActivate(path: string, _meta: any?): boolean
		if string.match(path, `/{idPattern}/Trigger$`) ~= nil then
			open:set(not open:get())
			return true
		end
		if string.match(path, `/{idPattern}/PopupWhen/then/Popup/Cancel$`) ~= nil then
			open:set(false)
			return true
		end
		local optionId = string.match(path, `/{idPattern}/PopupWhen/then/Popup/Opt%-(.+)$`)
		if optionId ~= nil and optionsById[optionId] ~= nil then
			select(optionId)
			return true
		end
		return false
	end

	-- model-level open/close/select for host code that drives without a tap
	function api.open()
		open:set(true)
	end
	function api.close()
		open:set(false)
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

	-- resolved at BUILD of each panel, so reopening after a space or input-class
	-- change picks the right idiom without the control holding stale state
	local function presentationNow(): string
		if requestedPresentation ~= "automatic" then
			return requestedPresentation
		end
		local classes = readFact(spec.interactionClasses)
		local touchLive = type(classes) == "table" and (classes :: any).touch == true
		-- the SELECTABLE count, not the array length: a divider is a rule between
		-- groups, and a menu does not become "long" because it was grouped
		return menuRecipe.resolvePresentation(selectableCount, readFact(spec.sizeClass), touchLive)
	end
	api.presentation = presentationNow

	local function popupPanel(): any
		local presentation = presentationNow()
		local rowHeight = menuRecipe.rowHeightFor(presentation)
		local rows = {}
		-- EVERY ROW COMES OUT OF THE ONE RECIPE (D2). Same props, same tokens and
		-- the same icon ruling the row-action menu and the freestanding Menu use —
		-- three copies of a menu row is how that ruling gets silently lost.
		for index, option in spec.options do
			if option.divider == true then
				table.insert(rows, menuRecipe.divider(UI, `Div-{index}`))
				continue
			end
			table.insert(
				rows,
				menuRecipe.row(UI, {
					id = `Opt-{option.id}`,
					label = option.label,
					icon = option.icon,
					selected = selectedMemoById[option.id :: string],
					height = rowHeight,
				})
			)
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
				height = { type = "fixed", px = rowHeight },
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
			anchor = if isSheet then "bottomLeft" else "topLeft",
			offsetY = if isSheet then 0 else TRIGGER_HEIGHT,
			width = { type = "fill", weight = 1 },
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

	local blueprint = UI.Anchor({
		id = id,
		width = { type = "fill", weight = 1 },
		height = { type = "fill", weight = 1 },
		children = {
			UI.Button({
				id = "Trigger",
				label = selectedLabel,
				anchor = "topLeft",
				width = { type = "fill", weight = 1 },
				height = { type = "fixed", px = TRIGGER_HEIGHT },
			}),
			UI.When({
				id = "PopupWhen",
				condition = open,
				thenView = popupPanel,
			}),
		},
	})

	-- deterministic diagnostic summary (§10.2 control contract dump form;
	-- uniform seam: every composite control exposes dump())
	local function dump()
		local options = {}
		for _, option in spec.options do
			-- a divider is reported AS a divider rather than as an option with no
			-- id: a dump that showed `{}` here would read as a corrupt option
			if option.divider == true then
				table.insert(options, { divider = true })
			else
				table.insert(options, { id = option.id, label = option.label, icon = option.icon })
			end
		end
		return {
			schema = "luauui-popup_button-dump/1",
			id = id,
			open = open:get(),
			value = spec.value:get(),
			selectedLabel = selectedLabel:get(),
			options = options,
		}
	end

	return {
		-- attach the input contribution: the presenter auto-routes open/select/
		-- cancel Activate to handleActivate with no consumer opts (ADR-0013).
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
			handleActivate = api.handleActivate,
			handleCancel = function(_focusedPath: string?): boolean
				if open:get() then
					open:set(false) -- close WITHOUT changing the selection
					return true
				end
				return false
			end,
			outsideDismiss = {
				active = open,
				dismiss = function()
					open:set(false)
				end,
			},
			transientScope = {
				active = open,
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
