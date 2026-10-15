--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local Nav = require("./navigation_types")
local InputProps = require("./input_props")
local Kit = require("./color_picker_kit")
local createState = require("./color_picker_state")
local createPanel = require("./color_picker_panel")
local createWell = require("./color_picker_well")

type Use = ComposeTypes.Use
type Spec = InputProps.ColorPickerProps
type Deps = Kit.Deps

local KEYS = {
	"value",
	"onChange",
	"onCommit",
	"alpha",
	"onAlphaChange",
	"allowEmpty",
	"placeholder",
	"modes",
	"swatches",
	"onSaveSwatch",
	"onRemoveSwatch",
	"style",
	"draft",
	"isPresented",
	"onPresentedChange",
	"onDismiss",
	"enabled",
	"readOnly",
	"label",
	"requiredMark",
	"hint",
	"errorText",
	"controlSize",
	"appearance",
	"corners",
}

return function(ctx: Shared.Context, UI: Deps, surfaces: Nav.Surfaces): ()
	local runtime = ctx.runtime
	local E, D2 = ctx.types.Enum, ctx.types.UDim2
	local kit = Kit.new(ctx)
	local chrome, color = kit.chrome, kit.color

	local function build(spec: Spec): Frame
		local state = createState(ctx, kit, spec)
		local style, labelled, diagnostics = state.style, state.labelled, state.diagnostics
		local held, canon, presented = state.held, state.canon, state.presented
		local placement, hexError = state.placement, state.hexError
		local columns, editing, enabled = state.columns, state.editing, state.enabled
		local panelView = createPanel(ctx, UI, surfaces, kit, state)

		local rootProps = ctx.props(spec, KEYS, {
			Name = "ColorPicker",
			BackgroundTransparency = 1,
			Size = if labelled or style == "inline" then D2.new(1, 0, 0, 0) else D2.fromOffset(0, 0),
			AutomaticSize = if labelled or style == "inline" then E.AutomaticSize.Y else E.AutomaticSize.XY,
		})
		local root: Frame
		if style == "inline" then
			local view = panelView(false, function()
				return false
			end, ctx.Compose.cell(math.huge))
			if chrome.present(spec) then
				root = chrome.wrap({
					control = "ColorPicker",
					spec = {
						label = spec.label,
						requiredMark = spec.requiredMark,
						hint = spec.hint,
						errorText = spec.errorText,
						appearance = spec.appearance,
					},
					plate = view.panel,
					focus = function() end,
					enabled = enabled,
					native = rootProps,
				})
			else
				root = ctx.column({ view.panel }, rootProps)
			end
		else
			root = createWell(ctx, UI, surfaces, kit, state, panelView, rootProps)
		end
		runtime.decorate(root, {
			Attributes = {
				value = function(use: Use): string
					local value = use(held)
					return if value == nil then "" else color.hex(value)
				end,
				text = function(use: Use): string
					return state.valueText(use)
				end,
				hue = function(use: Use): number
					return use(canon).h * 360
				end,
				saturation = function(use: Use): number
					return use(canon).s * 100
				end,
				brightness = function(use: Use): number
					return use(canon).v * 100
				end,
				mode = function(use: Use): string
					return use(state.modeCell)
				end,
				format = function(use: Use): string
					return use(state.formatCell)
				end,
				presented = function(use: Use): boolean
					return presented(use)
				end,
				placement = function(use: Use): string
					return use(placement)
				end,
				hexError = function(use: Use): string
					return use(hexError)
				end,
				columns = function(use: Use): number
					return use(columns)
				end,
				editing = function(use: Use): boolean
					return use(editing)
				end,
				diagnostics = function(use: Use): string
					return table.concat(use(diagnostics), "\n")
				end,
			} :: Shared.Attributes,
		})
		local picker: Frame = root
		return ctx.styled(picker, "color-picker")
	end

	local constructor = ctx.construct("ColorPicker", build)
	UI.ColorPicker = (constructor :: unknown) :: Shared.Constructor<Spec, Frame>
end
