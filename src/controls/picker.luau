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
--
-- ===== THE SLIDING INDICATOR (navigation-and-menus D4) =====================
--
-- `indicator = "none" (default) | "underline" | "pill"` is the PUBLIC authoring
-- surface for the D4 seam — the mechanism is internal
-- (`src/controls/selection_indicator.luau`) and nobody instantiates it directly.
-- When it is on, the selection chip or bar SLIDES from the previously selected
-- option's solved rect to the new one instead of the fill cross-fading.
--
-- Two consequences, both deliberate and both stated here because they change
-- what the control paints:
--
--   * THE INDICATOR IS THEN THE SELECTION PAINT. The option Buttons stop
--     carrying the `selected` style tag and are declared `surface = "plain"`,
--     because a tag AND a chip is the same statement twice — and worse, an
--     opaque Button would paint OVER the chip that is meant to sit behind its
--     label. Selection stays fully reported by `dump()`.
--   * `axis` becomes meaningful. `axis = "y"` with the SEGMENTED presentation is
--     f1's vertical rail: a real vertical pill, which is a different shape from
--     the `inline` row list and does not overload it.
--
-- `indicator = "none"` leaves every byte of the pre-D4 control unchanged.

local controlContract = require("./contract")
local contribution = require("../input/contribution")
local selectionIndicator = require("./selection_indicator")
local specGuard = require("../spec_guard")

local picker = {}

export type Option = { value: any, label: string }

export type Spec = {
	id: string?,
	label: string?,
	options: { Option },
	selected: any, -- owner-held Signal
	presentation: string?, -- "automatic" (default) | "segmented" | "inline"
	-- "none" (default) | "underline" | "pill" — the D4 sliding selection indicator
	indicator: string?,
	-- "x" (default) | "y" — the SEGMENTED presentation's axis. "y" is a vertical
	-- PILL (f1's left rail), which is a different shape from the `inline` row list
	-- and deliberately does not overload it. Inert under `inline`, which is a
	-- column by definition.
	axis: string?,
	sizeClass: any?, -- string | Readable<string> from LuauUI.adaptive.conditions
	env: any?, -- optional environment, so the indicator's metrics follow a live theme
	enabled: any?,
	onChange: ((value: any) -> ())?,
}

local PRESENTATIONS: { [string]: boolean } = { automatic = true, segmented = true, inline = true }
local INDICATORS: { [string]: boolean } = { none = true, underline = true, pill = true }
local AXES: { [string]: boolean } = { x = true, y = true }

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

-- CLOSED SPEC (constitution §4; ARCH-1). Exactly the fields this control
-- reads — an unknown one is an authoring mistake, never a silent no-op.
local PICKER_KEYS = specGuard.keySet({
	"axis",
	"enabled",
	"env",
	"id",
	"indicator",
	"label",
	"onChange",
	"options",
	"presentation",
	"selected",
	"sizeClass",
})

function picker.build(LuauUI: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("newPicker", spec, PICKER_KEYS, "spec")
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
	local indicator = spec.indicator or "none"
	if not INDICATORS[indicator] then
		error(
			`LuauUI newPicker('{id}'): unknown indicator '{tostring(indicator)}'. One of none | underline | pill. `
				.. "The sliding indicator is a PROPERTY of this control, not a construct you build yourself.",
			0
		)
	end
	local segmentedAxis = spec.axis or "x"
	if not AXES[segmentedAxis] then
		error(
			`LuauUI newPicker('{id}'): unknown axis '{tostring(segmentedAxis)}'. One of x | y. `
				.. '`axis = "y"` is the VERTICAL segmented pill; the stacked row list is `presentation = "inline"`.',
			0
		)
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

	-- one row per option. Without an indicator, `selected` is a BINDING prop that
	-- rides a style tag; WITH one, the indicator is the selection paint and the
	-- buttons go plain so nothing paints over the chip behind them (see header).
	local slides = indicator ~= "none"
	local rows: { any } = {}
	local byId: { [string]: any } = {}
	local segments: { any } = {}
	for i, option in spec.options do
		local optionId = "Opt" .. i
		byId[optionId] = option.value
		table.insert(segments, { value = option.value, id = optionId })
		table.insert(
			rows,
			UI.Button({
				id = optionId,
				label = option.label,
				enabled = spec.enabled,
				surface = if slides then "plain" else nil,
				selected = if slides
					then nil
					else scope:own(core:memo(function(use)
						return use(selected) == option.value
					end)),
				width = { type = "fill", weight = 1 },
				height = { type = "minMax", min = "targetSizes.minimum" },
			})
		)
	end

	-- ONE class with a reactive axis, so a presentation flip is a re-solve and the
	-- option buttons keep their identity, focus and state (the A-AL2 rule).
	-- `axis = "y"` on the SEGMENTED presentation is the vertical PILL; `inline` is
	-- a column by definition and ignores it.
	local axis = scope:own(core:memo(function(use)
		return if use(presentation) == "segmented" then segmentedAxis else "y"
	end))

	local group = UI.AdaptiveStack({
		id = "Options",
		axis = axis,
		gap = "xs",
		width = { type = "fill", weight = 1 },
		children = rows,
	})

	-- the D4 seam. It WRAPS the option stack, so the indicator layer and the
	-- options share one parent and the offsets it spends are in that parent's own
	-- space (see selection_indicator.luau on rectOf vs screenRectOf).
	local indicatorApi: any = nil
	if slides then
		indicatorApi = selectionIndicator.build(LuauUI, core, {
			id = "Indicator",
			content = group,
			segments = segments,
			selected = selected,
			skin = indicator,
			axis = axis, -- the LIVE axis: a presentation flip must move the edge with it
			env = spec.env,
			-- the wrapper inherits the option stack's own dimension, or the `fill`
			-- options inside it have nothing to fill and solve to ZERO width
			width = { type = "fill", weight = 1 },
		})
		scope:own(indicatorApi) -- the seam's whole lifetime is this control's
		group = indicatorApi.blueprint
	end

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
			axis = axis:get(),
			selectedLabel = chosenLabel,
			-- the D4 seam has no dump schema of its own (it is internal); its state
			-- is reported HERE, where a bug report about a bar in the wrong place
			-- already is
			indicator = if indicatorApi ~= nil then indicatorApi.state() else "none",
			semanticText = `{spec.label or "selection"}: {chosenLabel or "none"}`,
		}
	end

	function api.dispose()
		scope:dispose()
	end

	return api
end

return picker
