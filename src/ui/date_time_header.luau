--!strict
local civil = require("./civil_date")
local Shared = require("./types")
local Nav = require("./navigation_types")
local DTP = require("./date_time_picker_types")
local ComposeTypes = require("../vendor/compose/core")
local Parts = require("./date_time_parts")
local Options = require("./date_time_options")
local PickerState = require("./date_time_state")
local Calendar = require("./date_time_calendar")

type CivilDate = DTP.CivilDate
type Use = ComposeTypes.Use

local CELL, YEAR_SPAN, ROW = Parts.CELL, Parts.YEAR_SPAN, Parts.ROW
local monthOf = Parts.monthOf

return function(
	ctx: Shared.Context,
	UI: Parts.Deps,
	options: Options.Options,
	state: PickerState.State,
	calendar: Calendar.Calendar
): () -> Frame
	local Host, Compose, runtime = ctx.Host, ctx.Compose, ctx.runtime
	local E, D2 = ctx.types.Enum, ctx.types.UDim2
	local viewMonth, minDate, maxDate = state.viewMonth, state.minDate, state.maxDate
	local peekMonth = state.peekMonth
	local interactive = state.interactive
	local upTarget = calendar.upTarget

	local function menu(
		menuName: string,
		options: (Use) -> { { value: number, label: string, enabled: (Use) -> boolean } },
		get: (CivilDate) -> number,
		set: (number) -> (),
		maxHeight: number?
	): GuiObject
		local pick: ComposeTypes.Value<number> = Compose.cell(get(peekMonth()))
		Compose.watch(function(use: Use)
			pick:set(get(use(viewMonth)))
		end)
		local items = function(use: Use): { Nav.MenuItem<number> }
			local out: { Nav.MenuItem<number> } = {}
			for _, option in options(use) do
				local item: Nav.MenuChoice<number> = {
					id = tostring(option.value),
					label = option.label,
					selected = pick,
					value = option.value,
					enabled = option.enabled,
					dismiss = true,
					onChange = set,
				}
				table.insert(out, item)
			end
			return out
		end
		local wordsOf = function(use: Use): string
			local now = use(pick)
			for _, option in options(use) do
				if option.value == now then
					return option.label
				end
			end
			return tostring(now)
		end
		local trigger = ctx.styled(
			UI.Button {
				Name = menuName,
				label = wordsOf,
				trailingIcon = "chevron.down",
				appearance = "utility",
				enabled = function(use: Use)
					return interactive(use)
				end,
			},
			"calendar-choice"
		)
		return UI.Menu {
			items = items,
			trigger = trigger :: GuiObject,
			presentation = "menu" :: "menu",
			align = "center" :: "center",
			maxHeight = maxHeight,
			enabled = function(use: Use)
				return interactive(use)
			end,
		}
	end
	local function landIn(m: CivilDate)
		local lo, hi = minDate:peek(), maxDate:peek()
		if lo ~= nil and civil.compare(m, monthOf(lo)) < 0 then
			m = monthOf(lo)
		elseif hi ~= nil and civil.compare(m, monthOf(hi)) > 0 then
			m = monthOf(hi)
		end
		viewMonth:set(m)
	end
	local function header(): Frame
		local monthMenu = menu("Month", function(use: Use)
			local list = {}
			for m = 1, 12 do
				table.insert(list, {
					value = m,
					label = options.months[m],
					enabled = function(inner: Use): boolean
						return not state.monthClosed({ year = inner(viewMonth).year, month = m, day = 1 }, inner)
					end,
				})
			end
			return list
		end, function(m: CivilDate): number
			return m.month
		end, function(v: number)
			landIn({ year = peekMonth().year, month = v, day = 1 })
		end)
		local yearMenu = menu("Year", function(use: Use)
			local centre = use(viewMonth).year
			local lo, hi = use(minDate), use(maxDate)
			local list = {}
			local first = math.max(centre - YEAR_SPAN, if lo then lo.year else -math.huge)
			for y = first, math.min(centre + YEAR_SPAN, if hi then hi.year else math.huge) do
				table.insert(list, {
					value = y,
					label = tostring(y),
					enabled = function(): boolean
						return true
					end,
				})
			end
			return list
		end, function(m: CivilDate): number
			return m.year
		end, function(v: number)
			landIn({ year = v, month = peekMonth().month, day = 1 })
		end, 5 * CELL)
		upTarget:set(monthMenu)
		local function arrow(name: string, icon: string, words_: string, delta: number): TextButton
			return UI.Button(name)({
				icon = icon,
				name = words_,
				shape = "circle" :: "circle",
				appearance = "utility",
				enabled = function(use: Use)
					return interactive(use) and state.canPage(delta, use)
				end,
				onActivate = function()
					state.page(delta)
				end,
			})
		end
		local choose_ = ctx.row({ monthMenu, yearMenu }, { Name = "Choose" })
		runtime.mountFragment(function()
			return { Host.UIFlexItem { FlexMode = E.UIFlexMode.Fill } }
		end, choose_)
		local row = ctx.row({
			arrow("Previous", "chevron.leading", "Previous month", -1),
			choose_,
			arrow("Next", "chevron.trailing", "Next month", 1),
		}, { Name = "Header", Size = D2.new(1, 0, 0, ROW), AutomaticSize = E.AutomaticSize.None })
		assert(row:FindFirstChildWhichIsA("UIListLayout")).VerticalAlignment = E.VerticalAlignment.Center
		return row
	end

	return header
end
