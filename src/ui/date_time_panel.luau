--!strict
local civil = require("./civil_date")
local Shared = require("./types")
local DTP = require("./date_time_picker_types")
local InputProps = require("./input_props")
local ComposeTypes = require("../vendor/compose/core")
local Parts = require("./date_time_parts")
local Options = require("./date_time_options")
local PickerState = require("./date_time_state")
local Calendar = require("./date_time_calendar")
local createHeader = require("./date_time_header")
local createTime = require("./date_time_time")

type Range = DTP.Range
type Spec = InputProps.DateTimePickerProps
type Use = ComposeTypes.Use

local GAP = Parts.GAP
local span, monthOf, sameRange = Parts.span, Parts.monthOf, Parts.sameRange

return function(
	ctx: Shared.Context,
	UI: Parts.Deps,
	parts: Parts.Parts,
	spec: Spec,
	options: Options.Options,
	state: PickerState.State,
	calendar: Calendar.Calendar
): ((Use) -> string) -> Frame
	local Compose = ctx.Compose
	local E, D, D2, V2 = ctx.types.Enum, ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2
	local frame = parts.frame
	local isRange, withTime, draft, overlay, presets =
		options.isRange, options.withTime, options.draft, options.overlay, options.presets
	local range, today, minDate, maxDate = state.range, state.today, state.minDate, state.maxDate
	local viewMonth, dual, prefers = state.viewMonth, state.dual, state.prefers
	local interactive, propose, commit, restore = state.interactive, state.propose, state.commit, state.restore
	local takeSnapshot, close = state.takeSnapshot, state.close
	local pane, downTarget = calendar.pane, calendar.downTarget
	local header = createHeader(ctx, UI, options, state, calendar)
	local timeSection = createTime(ctx, UI, options, state, calendar)

	local function presetRow(): Frame
		local chips: { Shared.Child } = {}
		for _, p in presets do
			local clamped = Compose.formula(function(use: Use): Range?
				return civil.clampRange(p.range(use(today)), use(minDate), use(maxDate))
			end)
			local chipSpec: InputProps.ChipProps = {
				Name = `Preset-{p.id}`,
				label = p.label,
				controlSize = "compact" :: "compact",
				selected = function(use: Use): boolean
					local c = use(clamped)
					return c ~= nil and c.start ~= nil and sameRange(use(range), c)
				end,
				enabled = function(use: Use): boolean
					return use(clamped) ~= nil and interactive(use)
				end,
				onToggle = function()
					local c = clamped:peek()
					if c == nil then
						return
					end
					if propose(c) then
						if c.start ~= nil then
							viewMonth:set(monthOf(c.start))
						end
						if not draft then
							commit()
						end
					end
				end,
			}
			table.insert(chips, UI.Chip(chipSpec))
		end
		return ctx.row(chips, { Name = "Presets" })
	end

	local function panelView(route: (Use) -> string): Frame
		local children: { Shared.Child } = {
			header(),
			ctx.styled(
				frame("HeaderRule", { Size = D2.new(1, 0, 0, 1), AnchorPoint = V2.zero, Position = D2.fromScale(0, 0) }),
				"divider"
			),
		}
		local second = Compose.show(function(use: Use)
			return use(dual)
		end, function()
			local p = pane(2)
			p.LayoutOrder = 2
			return p
		end)
		local panesRow = ctx.row({ pane(1), second }, { Name = "Panes" })
		assert(panesRow:FindFirstChildWhichIsA("UIListLayout")).Padding = D.new(0, GAP)
		table.insert(children, panesRow)
		local hintOrder = #children + 1
		local hint = Compose.show(function(use: Use)
			return prefers(E.PreferredInput.Gamepad, use)
		end, function()
			local keys: InputProps.ShortcutHintProps = {
				Name = "PageKeys",
				keys = { { "LB" }, { "RB" } },
				controlSize = "compact" :: "compact",
			}
			local words_ = ctx.styled(ctx.text({ Name = "Words", Text = "Change month" }), "type-caption")
			return ctx.row({ UI.ShortcutHint(keys), words_ }, { Name = "PageHint", LayoutOrder = hintOrder })
		end)
		table.insert(children, hint)
		if withTime then
			table.insert(children, timeSection())
		end
		if #presets > 0 then
			table.insert(children, presetRow())
		end
		local function action(name: string, words_: string, fn: () -> (), look: string?): TextButton
			return UI.Button(name)({
				label = words_,
				onActivate = fn,
				appearance = look,
				enabled = function(use: Use)
					return interactive(use)
				end,
			})
		end
		local actions: Frame? = nil
		if draft then
			local reset = action("ResetAll", "Reset all", function()
				propose(if isRange then span(nil, nil) else nil)
			end, "link")
			local cancel = action("Cancel", "Cancel", function()
				restore()
				takeSnapshot()
				close("cancel")
			end)
			local apply = action("Apply", "Apply", function()
				if isRange then
					local r = range:peek()
					if spec.onRangeCommit ~= nil then
						spec.onRangeCommit(r)
					end
				else
					commit()
				end
				takeSnapshot()
				close("apply")
			end, "emphasis")
			local commitRow = ctx.row({ cancel, apply }, { Name = "Commit" })
			actions = ctx.row(
				{ reset, commitRow },
				{ Name = "Actions", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y }
			)
			downTarget:set(downTarget:peek() or reset)
		elseif overlay then
			local done = Compose.show(function(use: Use)
				return route(use) == "sheet"
			end, function()
				local button = action("Done", "Done", function()
					close("activate")
				end)
				if not withTime then
					downTarget:set(button)
				end
				Compose.cleanup(function()
					if downTarget:peek() == button then
						downTarget:set(nil)
					end
				end)
				return button
			end)
			actions = ctx.row({ done }, {
				Name = "Actions",
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				Visible = function(use: Use)
					return route(use) == "sheet"
				end,
			})
		end
		if actions then
			local layout = assert(actions:FindFirstChildWhichIsA("UIListLayout"))
			layout.VerticalAlignment = E.VerticalAlignment.Center
			layout.HorizontalFlex = if draft then E.UIFlexAlignment.SpaceBetween else E.UIFlexAlignment.None
			layout.HorizontalAlignment = E.HorizontalAlignment.Right
			local footer = ctx.styled(
				frame("FooterRule", {
					Size = D2.new(1, 0, 0, 1),
					AnchorPoint = V2.zero,
					Position = D2.fromScale(0, 0),
					Visible = if draft
						then true
						else function(use: Use)
							return route(use) == "sheet"
						end,
				}),
				"divider"
			)
			table.insert(children, footer)
			table.insert(children, actions)
		end
		local panel = ctx.column(children, {
			Name = "Calendar",
			Size = if overlay then nil else D2.new(1, 0, 0, 0),
			AutomaticSize = if overlay then E.AutomaticSize.Y else E.AutomaticSize.Y,
			ctx.padding(16, 16) :: Shared.Child,
		})
		assert(panel:FindFirstChildWhichIsA("UIListLayout")).Padding = D.new(0, 12)

		calendar.navigate(panel)
		return panel
	end

	return panelView
end
