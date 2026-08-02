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

-- a node id is interpolated into a Lua PATTERN below, so its magic characters
-- have to be escaped first. Module scope, not per-instance: it is a pure
-- function of its argument and every `build()` used to allocate its own
-- (Step 5.5 cleanup ledger C-06).
local function patternEscape(s: string): string
	return (s:gsub("%W", "%%%0"))
end

local popup_button = {}

export type Option = {
	id: string,
	label: string,
}

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

-- THEME METRICS (ADR-0019 §2). The three row heights ARE the three control
-- sizes — compact for the pointer menu, regular for the inline list, large for
-- the touch sheet — so a theme that retunes its control ladder retunes this
-- control's presentations with it. A touch SHEET uses a visually larger row,
-- not just a hit-floored one: on a finger the target should look as big as it
-- is (B-DSP3).
local TRIGGER_HEIGHT = "controls.popup.triggerHeight"
local ROW_HEIGHT = "controlSizes.compact.height"
local SHEET_ROW_HEIGHT = "controlSizes.large.height"
local INLINE_ROW_HEIGHT = "controlSizes.regular.height"

-- Adaptive presentation (acceptance row B-DSP3). The choice comes from the option
-- count, the available SPACE class, and whether touch is a LIVE interaction class
-- — never from a device name. Pure and exported so a caller can predict it.
--
--   menu    the floating panel below the trigger. The desktop/pointer idiom.
--   inline  rows in place under the trigger, no separate panel surface. Good for
--           a couple of options with room to show them.
--   sheet   a bottom-anchored, full-width surface with larger rows. The touch
--           idiom, and the fallback when a compact space cannot hold a long menu.
function popup_button.resolvePresentation(optionCount: number, sizeClass: string?, touchLive: boolean?): string
	if touchLive == true then
		return "sheet"
	end
	if sizeClass == "compact" and optionCount > 6 then
		return "sheet"
	end
	if optionCount <= 3 and sizeClass ~= "compact" then
		return "inline"
	end
	return "menu"
end

local PRESENTATIONS: { [string]: boolean } = { automatic = true, menu = true, inline = true, sheet = true }

function popup_button.build(LuauUI: any, core: any, spec: Spec)
	local UI = LuauUI.UI
	local id = spec.id or "PopupButton"
	local scope = core:scope(`popup_button-{id}`)

	assert(type(spec.options) == "table" and #spec.options > 0, `PopupButton '{id}': options must be a non-empty array`)
	assert(
		type(spec.value) == "table" and (spec.value.kind == "signal" or spec.value.kind == "memo"),
		`PopupButton '{id}': value must be a Signal/Memo of the selected option id`
	)

	-- option ids become `Opt-<id>` path segments; a "/" would corrupt routing
	-- everywhere downstream — fail at BUILD (ADR-0010), not first render
	local optionsById: { [string]: Option } = {}
	for _, option in spec.options do
		assert(
			not string.find(option.id, "/", 1, true),
			`PopupButton '{id}': option id '{option.id}' must be path-safe (no "/")`
		)
		optionsById[option.id] = option
	end

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
	for _, option in spec.options do
		local optionId = option.id
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
		return popup_button.resolvePresentation(#spec.options, readFact(spec.sizeClass), touchLive)
	end
	api.presentation = presentationNow

	local function popupPanel(): any
		local presentation = presentationNow()
		local rowHeight = if presentation == "sheet"
			then SHEET_ROW_HEIGHT
			elseif presentation == "inline" then INLINE_ROW_HEIGHT
			else ROW_HEIGHT
		local rows = {}
		for _, option in spec.options do
			table.insert(
				rows,
				UI.Button({
					id = `Opt-{option.id}`,
					label = option.label,
					selected = selectedMemoById[option.id],
					width = { type = "fill", weight = 1 },
					height = { type = "fixed", px = rowHeight },
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
			-- the hairline of surface showing between rows
			gap = "strokes.hairline",
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
			table.insert(options, { id = option.id, label = option.label })
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
