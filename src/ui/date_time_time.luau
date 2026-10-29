--!strict
local civil = require("./civil_date")
local Shared = require("./types")
local DTP = require("./date_time_picker_types")
local CollectionProps = require("./collection_props")
local NavigationProps = require("./navigation_props")
local ComposeTypes = require("../vendor/compose/core")
local Parts = require("./date_time_parts")
local Options = require("./date_time_options")
local PickerState = require("./date_time_state")
local Calendar = require("./date_time_calendar")

type CivilDate = DTP.CivilDate
type Use = ComposeTypes.Use
type ReadOnlyValue<T> = ComposeTypes.ReadOnlyValue<T>
type TimeRow = { id: string, hour: number, minute: number }

local ROW = Parts.ROW

return function(
	ctx: Shared.Context,
	UI: Parts.Deps,
	options: Options.Options,
	state: PickerState.State,
	calendar: Calendar.Calendar
): () -> Frame
	local Host, Compose = ctx.Host, ctx.Compose
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local draft, minuteStep, hourCycle, clock = options.draft, options.minuteStep, options.hourCycle, options.clock
	local value, anchorDate = state.value, state.anchorDate
	local interactive, propose, commit = state.interactive, state.propose, state.commit
	local downTarget = calendar.downTarget

	local function timeSection(): Frame
		local function base(): CivilDate
			local v = value:peek()
			if v ~= nil and v.hour ~= nil then
				return v
			end
			local d = civil.dateOf(v or anchorDate())
			d.hour, d.minute = 0, 0
			return d
		end
		local function field(
			name: string,
			lo: number,
			hi: number,
			step: number,
			get: (CivilDate) -> number,
			with: (CivilDate, number) -> CivilDate
		): TextBox | Frame
			local text = Compose.cell("")
			local number = Compose.cell(lo)
			Compose.watch(function(use: Use)
				local v = use(value)
				local n = if v ~= nil and v.hour ~= nil then get(v) else lo
				number:set(n)
				text:set(if v ~= nil then string.format("%02d", n) else "")
			end)
			return UI.NumberInput(name)({
				label = name,
				Size = D2.new(0, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
				value = text,
				numericValue = number,
				min = lo,
				max = hi,
				step = step,
				precision = 0,
				stepButtons = true,
				enabled = function(use: Use)
					return interactive(use)
				end,
				format = function(n: number): string
					return string.format("%02d", n)
				end,
				onCommit = function(n: number)
					local v = value:peek()
					if not propose(with(base(), n)) then
						local held = if v ~= nil and v.hour ~= nil then get(v) else lo
						number:set(held)
						text:set(if v ~= nil then string.format("%02d", held) else "")
					elseif not draft then
						commit()
					end
				end,
			})
		end
		local function withHour(d: CivilDate, h: number): CivilDate
			local out = table.clone(d)
			local pm = (d.hour or 0) >= 12
			out.hour = if hourCycle == 12 then (h % 12) + (if pm then 12 else 0) else h
			return out
		end
		local function withMinute(d: CivilDate, m: number): CivilDate
			local out = table.clone(d)
			out.minute = m
			return out
		end
		local hour = field("Hour", if hourCycle == 12 then 1 else 0, if hourCycle == 12 then 12 else 23, 1, function(v)
			local h = v.hour or 0
			return if hourCycle == 12 then (if h % 12 == 0 then 12 else h % 12) else h
		end, withHour)
		local minute = field("Minute", 0, 60 - minuteStep, minuteStep, function(v)
			return v.minute or 0
		end, withMinute)
		downTarget:set(hour:FindFirstChild("Field", true) :: GuiObject?)
		local parts: { Shared.Child } = {}
		if hourCycle == 12 then
			local half = Compose.cell("AM")
			Compose.watch(function(use: Use)
				local v = use(value)
				half:set(if v ~= nil and v.hour ~= nil and v.hour >= 12 then "PM" else "AM")
			end)
			local halfSpec: NavigationProps.SinglePickerSpec<string> = {
				Name = "Half",
				options = { { value = "AM", label = "AM" }, { value = "PM", label = "PM" } },
				selected = half,
				style = "segmented",
				sizing = "hug",
				Size = D2.fromOffset(0, 0),
				AutomaticSize = E.AutomaticSize.XY,
				enabled = function(use: Use)
					return interactive(use)
				end,
				onChanging = function(word: string): boolean?
					local v = value:peek()
					if v == nil or v.hour == nil then
						return false
					end
					local next = table.clone(v)
					next.hour = v.hour % 12 + (if word == "PM" then 12 else 0)
					if not propose(next) then
						return false
					end
					if not draft then
						commit()
					end
					return true
				end,
			}
			table.insert(parts, UI.Picker(halfSpec))
		end
		local fields = ctx.row(
			{ hour, minute },
			{ Name = "Fields", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y }
		)
		assert(fields:FindFirstChildWhichIsA("UIListLayout")).VerticalAlignment = E.VerticalAlignment.Top
		local times: { TimeRow } = {}
		for minutes = 0, 24 * 60 - 1, minuteStep do
			table.insert(times, { id = `{minutes // 60}:{minutes % 60}`, hour = minutes // 60, minute = minutes % 60 })
		end
		local list = Compose.show(function(use: Use)
			return state.prefers(E.PreferredInput.Touch, use)
		end, function()
			local at: CivilDate = value:peek() or clock()
			if at.hour == nil then
				at = clock()
			end
			local first = if at.hour ~= nil then (at.hour * 60 + (at.minute or 0)) // minuteStep else 0
			local timesSpec: CollectionProps.KeyedCollectionSpec<TimeRow, string> = {
				Name = "Times",
				LayoutOrder = 2,
				from = times,
				key = "id",
				itemSize = ROW,
				Size = D2.new(1, 0, 0, 4 * ROW),
				CanvasPosition = V2.new(0, first * ROW),
				render = function(row: ReadOnlyValue<TimeRow>): GuiObject
					local t = row:peek()
					return UI.Button({
						Name = "Time",
						label = civil.formatTime(
							{ year = 2000, month = 1, day = 1, hour = t.hour, minute = t.minute },
							hourCycle
						),
						Size = D2.new(1, 0, 0, ROW),
						AutomaticSize = E.AutomaticSize.None,
						enabled = function(use: Use)
							return interactive(use)
						end,
						selected = function(use: Use)
							local v = use(value)
							return v ~= nil and v.hour == t.hour and v.minute == t.minute
						end,
						onActivate = function()
							local next = civil.dateOf(value:peek() or anchorDate())
							next.hour, next.minute = t.hour, t.minute
							if propose(next) and not draft then
								commit()
							end
						end,
					})
				end,
			}
			return UI.VirtualList(timesSpec)
		end)
		table.insert(parts, 1, fields)
		table.insert(parts, list)
		return ctx.column(parts, { Name = "Time", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
	end

	return timeSection
end
