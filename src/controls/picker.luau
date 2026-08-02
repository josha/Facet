--!strict
-- Picker: single-selection from a small option set (docs/plans/swiftui-parity-next.md
-- investment 7; acceptance row B-DSP2). Two presentations over ONE selection model:
--
--   segmented — options side by side, always visible. Good for 2–4 short options.
--   inline    — options stacked as rows. Good for longer labels or more options.
--
-- The presentation is ADAPTIVE, not a platform branch: `presentation = "automatic"`
-- (the default) chooses from the option count and the available space class the
-- caller passes in, exactly as `LuauUI.adaptive` computes it. A device name never
-- appears. For a popup presentation use `newPopupButton`, which owns the transient
-- surface machinery.
--
-- THREE AXES: every option is a focusable Button, so reachability and the 44px
-- floor come from the primitive; the selected option carries `selected`, which is
-- a style TAG, not a bespoke fill. hotSwitch = false (selection is atomic).
--
-- OWNERSHIP: `selected` is the CALLER's Signal.

local controlContract = require("./contract")
local contribution = require("../input/contribution")

local picker = {}

export type Option = { value: any, label: string }

export type Spec = {
	id: string?,
	label: string?,
	options: { Option },
	selected: any, -- owner-held Signal
	presentation: string?, -- "automatic" (default) | "segmented" | "inline"
	sizeClass: any?, -- string | Readable<string> from LuauUI.adaptive.conditions
	enabled: any?,
	onChange: ((value: any) -> ())?,
}

local PRESENTATIONS: { [string]: boolean } = { automatic = true, segmented = true, inline = true }

-- the adaptive rule, pure and exported so a caller can predict it
function picker.resolvePresentation(optionCount: number, sizeClass: string?, longestLabel: number): string
	-- stack when the options cannot sit side by side legibly: too many of them, or
	-- long labels in a compact space. This is a SPACE decision, not a device one.
	if optionCount > 4 then
		return "inline"
	end
	if sizeClass == "compact" and (optionCount > 3 or longestLabel > 10) then
		return "inline"
	end
	return "segmented"
end

function picker.build(LuauUI: any, core: any, spec: Spec)
	local UI = LuauUI.UI
	local id = spec.id or "Picker"
	local scope = core:scope("picker-" .. tostring(id))
	if type(spec.options) ~= "table" or #spec.options == 0 then
		error(`LuauUI newPicker('{id}'): \`options\` must be a non-empty array of value/label pairs`, 0)
	end
	local selected = spec.selected
	if type(selected) ~= "table" or (selected :: any).kind ~= "signal" then
		error(`LuauUI newPicker('{id}'): \`selected\` must be a SETTABLE Signal the caller owns`, 0)
	end
	local requested = spec.presentation or "automatic"
	if not PRESENTATIONS[requested] then
		error(`LuauUI newPicker('{id}'): unknown presentation '{requested}'. One of automatic | segmented | inline.`, 0)
	end

	local longest = 0
	for _, option in spec.options do
		longest = math.max(longest, #option.label)
	end

	local function readSizeClass(use: any?): string?
		local sc = spec.sizeClass
		if sc == nil then
			return nil
		end
		if type(sc) == "table" then
			return if use ~= nil then use(sc) else (sc :: any):get()
		end
		return sc :: string
	end

	local presentation = scope:own(core:memo(function(use)
		if requested ~= "automatic" then
			return requested
		end
		return picker.resolvePresentation(#spec.options, readSizeClass(use), longest)
	end))

	-- the contract's one reading of `enabled` (a one-shot read: never subscribes)
	local function isEnabled(): boolean
		return controlContract.enabledNow(spec.enabled)
	end

	local function choose(value: any): boolean
		if not isEnabled() or selected:get() == value then
			return false
		end
		selected:set(value)
		if spec.onChange ~= nil then
			spec.onChange(value)
		end
		return true
	end

	-- one row per option; `selected` is a BINDING prop that rides a style tag
	local rows: { any } = {}
	local byId: { [string]: any } = {}
	for i, option in spec.options do
		local optionId = "Opt" .. i
		byId[optionId] = option.value
		table.insert(
			rows,
			UI.Button({
				id = optionId,
				label = option.label,
				enabled = spec.enabled,
				selected = scope:own(core:memo(function(use)
					return use(selected) == option.value
				end)),
				width = { type = "fill", weight = 1 },
				height = { type = "minMax", min = "targetSizes.minimum" },
			})
		)
	end

	-- ONE class with a reactive axis, so a presentation flip is a re-solve and the
	-- option buttons keep their identity, focus and state (the A-AL2 rule)
	local axis = scope:own(core:memo(function(use)
		return if use(presentation) == "segmented" then "x" else "y"
	end))

	local group = UI.AdaptiveStack({
		id = "Options",
		axis = axis,
		gap = "xs",
		width = { type = "fill", weight = 1 },
		children = rows,
	})

	local root = if spec.label ~= nil
		then UI.VStack({
			id = id,
			gap = "xs",
			width = { type = "fill", weight = 1 },
			children = { UI.Text({ id = "Label", text = spec.label, textSize = "label" }), group },
		})
		else UI.VStack({ id = id, width = { type = "fill", weight = 1 }, children = { group } })

	local built = contribution.attach(root, {
		handleActivate = function(path: string): boolean
			local leaf = string.match(path, "([^/]+)$")
			if leaf ~= nil and byId[leaf] ~= nil then
				choose(byId[leaf])
				return true
			end
			return false
		end,
	})

	local api = {}
	api.blueprint = built
	api.presentation = presentation

	function api.dump()
		local current = selected:get()
		local chosenLabel: string? = nil
		for _, option in spec.options do
			if option.value == current then
				chosenLabel = option.label
			end
		end
		return {
			schema = "luauui-picker-dump/1",
			id = id,
			optionCount = #spec.options,
			requestedPresentation = requested,
			presentation = presentation:get(),
			selectedLabel = chosenLabel,
			semanticText = `{spec.label or "selection"}: {chosenLabel or "none"}`,
		}
	end

	function api.dispose()
		scope:dispose()
	end

	return api
end

return picker
