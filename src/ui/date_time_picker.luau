--!strict
local fieldChrome = require("./field_chrome")
local Shared = require("./types")
local Nav = require("./navigation_types")
local InputProps = require("./input_props")
local ComposeTypes = require("../vendor/compose/core")
local Parts = require("./date_time_parts")
local readOptions = require("./date_time_options")
local createState = require("./date_time_state")
local createCalendar = require("./date_time_calendar")
local createPanel = require("./date_time_panel")
local createField = require("./date_time_field")

type Spec = InputProps.DateTimePickerProps
type Use = ComposeTypes.Use
type Deps = Parts.Deps

local KEYS = {
	"selection",
	"value",
	"onChange",
	"onCommit",
	"range",
	"onRangeChange",
	"onRangeCommit",
	"time",
	"minuteStep",
	"hourCycle",
	"min",
	"max",
	"isDateDisabled",
	"weekStart",
	"locale",
	"clock",
	"referenceDate",
	"presets",
	"draft",
	"style",
	"format",
	"placeholder",
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
	local Compose, runtime = ctx.Compose, ctx.runtime
	local chrome = fieldChrome(ctx)
	local parts = Parts.new(ctx)
	local gui = parts.gui

	local function build(spec: Spec): Frame
		local rootProps = ctx.props(spec, KEYS, { Name = "DateTimePicker" })
		local options = readOptions(ctx, chrome, spec)
		local state = createState(ctx, parts, spec, options)
		local calendar = createCalendar(ctx, UI, parts, options, state)
		local panelView = createPanel(ctx, UI, parts, spec, options, state, calendar)
		local overlay = options.overlay
		local diagnostics, viewMonth, room, dual = state.diagnostics, state.viewMonth, state.room, state.dual
		local presented, valueText, typedError, enabled =
			state.presented, state.valueText, state.typedError, state.enabled
		local cells, landing = calendar.cells, calendar.landing

		local chromeSpec: fieldChrome.Options = {
			label = spec.label,
			requiredMark = spec.requiredMark,
			hint = spec.hint,
			errorText = spec.errorText,
			controlSize = if overlay then spec.controlSize else nil,
			appearance = spec.appearance,
			corners = spec.corners,
		}
		local root: Frame
		local routeCell = Compose.cell(if overlay then "popover" else "inline")
		if not overlay then
			local panel = panelView(function(): string
				return "inline"
			end)
			root = chrome.wrap({
				control = "DateTimePicker",
				spec = chromeSpec,
				plate = panel,
				focus = function()
					local list = cells[1]
					if gui and list and list[landing()] then
						gui.SelectedObject = list[landing()]
					end
				end,
				enabled = enabled,
				message = typedError,
				native = rootProps,
			})
			local size = ctx.observe.AbsoluteSize(root)
			Compose.watch(function(use: Use)
				local measured = use(size) :: Vector2
				room:set(measured.X)
			end)
		else
			root = createField(
				ctx,
				UI,
				surfaces,
				parts,
				chrome,
				spec,
				options,
				state,
				calendar,
				panelView,
				chromeSpec,
				rootProps,
				routeCell
			)
		end
		runtime.decorate(root, {
			Attributes = {
				month = function(use: Use): string
					local m = use(viewMonth)
					return string.format("%04d-%02d", m.year, m.month)
				end,
				dual = function(use: Use): boolean
					return use(dual)
				end,
				route = function(use: Use): string
					return use(routeCell)
				end,
				presented = function(use: Use): boolean
					return use(presented)
				end,
				text = function(use: Use): string
					return use(valueText)
				end,
				typedError = function(use: Use): string
					return use(typedError)
				end,
				diagnostics = function(use: Use): number
					return #use(diagnostics)
				end,
			} :: Shared.Attributes,
		})
		root:AddTag("facet-date-time-picker")
		return root
	end

	local constructor = ctx.construct("DateTimePicker", build)
	UI.DateTimePicker = (constructor :: unknown) :: Shared.Constructor<Spec, Frame>
end
