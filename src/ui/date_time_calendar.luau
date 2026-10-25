--!strict
local civil = require("./civil_date")
local Shared = require("./types")
local DTP = require("./date_time_picker_types")
local ComposeTypes = require("../vendor/compose/core")
local Parts = require("./date_time_parts")
local Options = require("./date_time_options")
local PickerState = require("./date_time_state")

type CivilDate = DTP.CivilDate
type Range = DTP.Range
type Use = ComposeTypes.Use
type Cell<T> = ComposeTypes.Cell<T>
type Grab = { other: CivilDate, from: Range, last: CivilDate, moved: boolean }
export type Calendar = {
	cells: { [number]: { [number]: TextButton } },
	cellIndex: { [Instance]: { k: number, i: number } },
	cellFor: (CivilDate, Use?) -> (number?, number?),
	landing: () -> number,
	upTarget: Cell<GuiObject?>,
	downTarget: Cell<GuiObject?>,
	pane: (number) -> Frame,
	navigate: (Frame) -> (),
}

local CELLS, CELL, DISC = Parts.CELLS, Parts.CELL, Parts.DISC
local span = Parts.span

return function(
	ctx: Shared.Context,
	UI: Parts.Deps,
	parts: Parts.Parts,
	options: Options.Options,
	state: PickerState.State
): Calendar
	local Host, Compose, runtime = ctx.Host, ctx.Compose, ctx.runtime
	local E, D, D2, V2 = ctx.types.Enum, ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2
	local gui, input, tagWhile, frame = parts.gui, parts.input, parts.tagWhile, parts.frame
	local isRange, draft = options.isRange, options.draft
	local months = options.months
	local value, range, today, selected = state.value, state.range, state.today, state.selected
	local paneMonth, paneGrid = state.paneMonth, state.paneGrid
	local canPage, page = state.canPage, state.page
	local interactive, isDisabled = state.interactive, state.isDisabled
	local propose = state.propose

	local cells: { [number]: { [number]: TextButton } } = {}
	local cellIndex: { [Instance]: { k: number, i: number } } = {}
	local function gridDate(k: number, i: number): CivilDate
		return paneGrid(k)[i]
	end
	local function cellFor(d: CivilDate, use: Use?): (number?, number?)
		for k = 1, state.panes(use) do
			local m = paneMonth(k, use)
			if d.year == m.year and d.month == m.month then
				for i, g in paneGrid(k, use) do
					if civil.compare(g, d) == 0 then
						return k, i
					end
				end
			end
		end
		return nil, nil
	end
	local function landing(): number
		local m = state.peekMonth()
		local grid = paneGrid(1)
		local want = if isRange then range:peek().start else value:peek()
		local candidates: { CivilDate } = { today:peek() }
		if want ~= nil then
			table.insert(candidates, 1, want)
		end
		for _, candidate in candidates do
			for i, d in grid do
				if civil.compare(d, candidate) == 0 and d.month == m.month and not isDisabled(d) then
					return i
				end
			end
		end
		for i, d in grid do
			if d.month == m.month and not isDisabled(d) then
				return i
			end
		end
		return 1
	end

	local grab: Grab? = nil
	local swallowTap = false
	local function dayUnder(x: number, y: number): CivilDate?
		for k, list in cells do
			for i, cell in list do
				local at, size = cell.AbsolutePosition, cell.AbsoluteSize
				if x >= at.X and x < at.X + size.X and y >= at.Y and y < at.Y + size.Y then
					return gridDate(k, i)
				end
			end
		end
		return nil
	end
	local function grabEnd(d: CivilDate): boolean
		local r = range:peek()
		if not isRange or r.start == nil or r.finish == nil or not state.mayEdit() then
			return false
		end
		local other = if civil.compare(d, r.start) == 0
			then r.finish
			elseif civil.compare(d, r.finish) == 0 then r.start
			else nil
		if other == nil then
			return false
		end
		grab = { other = other, from = r, last = d, moved = false }
		return true
	end
	local function dragTo(x: number, y: number)
		local held = grab
		if held == nil then
			return
		end
		local d = dayUnder(x, y)
		if d == nil or isDisabled(d) or civil.compare(d, held.last) == 0 then
			return
		end
		held.last, held.moved = d, true
		local a, b = held.other, civil.dateOf(d)
		propose(if civil.compare(b, a) < 0 then span(b, a) else span(a, b))
	end
	local function release(cancelled: boolean)
		local held = grab
		grab = nil
		if held == nil or not held.moved then
			return
		end
		swallowTap = not cancelled
		if cancelled then
			propose(held.from)
		elseif not draft then
			state.commit()
		end
	end
	if isRange and input then
		local function pointer(event: InputObject): boolean
			return event.UserInputType == E.UserInputType.MouseButton1
				or event.UserInputType == E.UserInputType.MouseMovement
				or event.UserInputType == E.UserInputType.Touch
		end
		runtime.connect(input, "InputChanged", function(event: InputObject)
			if grab ~= nil and pointer(event) then
				if event.UserInputState == E.UserInputState.Cancel then
					release(true)
				else
					dragTo(event.Position.X, event.Position.Y)
				end
			end
		end)
		runtime.connect(input, "InputEnded", function(event: InputObject)
			if grab ~= nil and pointer(event) then
				release(event.UserInputState == E.UserInputState.Cancel)
			end
		end)
		runtime.connect(input, "WindowFocusReleased", function()
			release(true)
		end)
	end

	local upTarget = Compose.cell(nil :: GuiObject?)
	local downTarget = Compose.cell(nil :: GuiObject?)
	local function shownAway(k: number, i: number, step: number, use: Use): boolean
		local target = civil.addDays(paneGrid(k, use)[i], step)
		return cellFor(target, use) ~= nil
	end

	local function dayCell(k: number, i: number): TextButton
		local date = Compose.formula(function(use: Use): CivilDate
			return paneGrid(k, use)[i]
		end)
		local outside = Compose.formula(function(use: Use): boolean
			return use(date).month ~= paneMonth(k, use).month
		end)
		local disabled = Compose.formula(function(use: Use): boolean
			return isDisabled(use(date), use)
		end)
		local chosen = Compose.formula(function(use: Use): boolean
			local d = use(date)
			if use(outside) then
				return false
			end
			if isRange then
				local r = use(range)
				return (r.start ~= nil and civil.compare(d, r.start) == 0)
					or (r.finish ~= nil and civil.compare(d, r.finish) == 0)
			end
			local v = use(value)
			return v ~= nil and civil.compare(d, v) == 0
		end)
		local banded = Compose.formula(function(use: Use): boolean
			if not isRange or use(outside) then
				return false
			end
			local r = use(range)
			return r.start ~= nil and r.finish ~= nil and civil.within(use(date), r.start, r.finish)
		end)
		local column = (i - 1) % 7 + 1
		local function edge(side: "leading" | "trailing", use: Use): boolean
			if not use(banded) then
				return true
			end
			local r = use(range)
			local stop = assert(if side == "leading" then r.start else r.finish)
			return civil.compare(use(date), stop) == 0 or column == (if side == "leading" then 1 else 7)
		end
		local function capped(use: Use): boolean
			return use(banded) and (edge("leading", use) or edge("trailing", use)) and not use(chosen)
		end
		local disc = frame("Disc", {
			Visible = function(use: Use)
				return use(chosen)
			end,
			ZIndex = 3,
			ctx.corner(DISC),
		})
		disc:AddTag("facet-calendar-disc")
		if isRange then
			disc:AddTag("facet-calendar-end")
		end
		local band = frame("Band", {
			Size = D2.new(1, 0, 0, DISC),
			Visible = function(use: Use)
				return use(banded)
			end,
			BackgroundTransparency = 1,
			ZIndex = 1,
			frame("Leading", {
				Size = D2.new(0.5, 0, 1, 0),
				AnchorPoint = V2.new(0, 0),
				Position = D2.fromScale(0, 0),
				Visible = function(use: Use)
					return not edge("leading", use)
				end,
			}),
			frame("Trailing", {
				Size = D2.new(0.5, 0, 1, 0),
				AnchorPoint = V2.new(0, 0),
				Position = D2.fromScale(0.5, 0),
				Visible = function(use: Use)
					return not edge("trailing", use)
				end,
			}),
		})
		for _, part in band:GetChildren() do
			part:AddTag("facet-calendar-band")
		end
		local cap = frame("Cap", {
			Visible = capped,
			ZIndex = 2,
			ctx.corner(DISC),
		})
		cap:AddTag("facet-calendar-band")
		local ring = frame("Today", {
			Visible = function(use: Use)
				return civil.compare(use(date), use(today)) == 0
			end,
			ZIndex = 4,
			BackgroundTransparency = 1,
			ctx.corner(DISC) :: Shared.Child,
			Host.UIStroke({ Thickness = 1 }) :: Shared.Child,
		})
		ring:AddTag("facet-calendar-today")
		local number = ctx.text({
			Name = "Day",
			Text = function(use: Use)
				return tostring(use(date).day)
			end,
			AutomaticSize = E.AutomaticSize.None,
			Size = D2.fromScale(1, 1),
			TextXAlignment = E.TextXAlignment.Center,
			ZIndex = 5,
		})
		number:AddTag("facet-calendar-number")
		tagWhile(number, "facet-calendar-banded", function(use: Use)
			return use(banded)
		end)
		tagWhile(number, "facet-calendar-dim", function(use: Use)
			return use(outside) or use(disabled)
		end)
		tagWhile(number, if isRange then "facet-calendar-chosen-end" else "facet-calendar-chosen", function(use: Use)
			return use(chosen)
		end)
		local strike = frame("Strike", {
			Size = D2.new(0.5, 0, 0, 1),
			Visible = function(use: Use)
				return use(disabled)
			end,
			ZIndex = 6,
		})
		strike:AddTag("facet-calendar-strike")
		local cell: TextButton
		local up = function(use: Use): GuiObject?
			if shownAway(k, i, -7, use) then
				return nil
			end
			return use(upTarget)
		end
		local down = function(use: Use): GuiObject?
			if shownAway(k, i, 7, use) then
				return nil
			end
			return use(downTarget)
		end
		cell = UI.Button({
			Name = `D{i}`,
			LayoutOrder = i,
			label = "",
			name = function(use: Use)
				return state.longName(use(date)) .. (if use(disabled) then ", unavailable" else "")
			end,
			Size = D2.fromOffset(CELL, CELL),
			AutomaticSize = E.AutomaticSize.None,
			enabled = function(use: Use)
				return interactive(use)
			end,
			Selectable = function(use: Use)
				return interactive(use) and not use(outside)
			end,
			NextSelectionUp = (up :: unknown) :: Shared.Value<GuiObject?>,
			NextSelectionDown = (down :: unknown) :: Shared.Value<GuiObject?>,
			onActivate = function()
				if swallowTap then
					swallowTap = false
					return
				end
				state.choose(date:peek())
			end,
			Host.Frame "Layers" {
				BackgroundTransparency = 1,
				Size = D2.fromScale(1, 1),
				band :: Shared.Child,
				cap :: Shared.Child,
				disc :: Shared.Child,
				ring :: Shared.Child,
				number :: Shared.Child,
				strike :: Shared.Child,
			},
		})
		cell:AddTag("facet-calendar-day")
		if isRange then
			runtime.connect(cell, "InputBegan", function(event: InputObject)
				if
					event.UserInputType == E.UserInputType.MouseButton1
					or event.UserInputType == E.UserInputType.Touch
				then
					swallowTap = false
					if not outside:peek() then
						grabEnd(date:peek())
					end
				end
			end)
		end
		cells[k] = cells[k] or {}
		cells[k][i] = cell
		cellIndex[cell] = { k = k, i = i }
		Compose.cleanup(function()
			if cells[k] and cells[k][i] == cell then
				cells[k][i] = nil
			end
			cellIndex[cell] = nil
		end)
		return cell
	end

	local function pane(k: number): Frame
		local names: { Shared.Child } = {}
		for c = 0, 6 do
			local dayIndex = (options.weekStart - 1 + c) % 7 + 1
			table.insert(
				names,
				ctx.styled(
					ctx.text({
						Name = `W{c + 1}`,
						Text = options.weekdays[dayIndex],
						Size = D2.fromOffset(CELL, 20),
						AutomaticSize = E.AutomaticSize.None,
						TextXAlignment = E.TextXAlignment.Center,
					}),
					"type-caption"
				)
			)
		end
		local weekdayRow = ctx.row(names, { Name = "Weekdays" })
		assert(weekdayRow:FindFirstChildWhichIsA("UIListLayout")).Padding = D.new(0, 0)
		local days: { Shared.Child } = {
			Host.UIListLayout({
				FillDirection = E.FillDirection.Horizontal,
				Wraps = true,
				Padding = D.new(0, 0),
				SortOrder = E.SortOrder.LayoutOrder,
			}),
		}
		for i = 1, CELLS do
			table.insert(days, dayCell(k, i))
		end
		local grid = Host.Frame "Days" {
			BackgroundTransparency = 1,
			Size = D2.fromOffset(7 * CELL, 6 * CELL),
			table.unpack(days),
		}
		local title = ctx.styled(
			ctx.text({
				Name = "Title",
				Text = function(use: Use)
					local m = paneMonth(k, use)
					return `{months[m.month]} {m.year}`
				end,
				Visible = function(use: Use)
					return use(state.dual)
				end,
			}),
			"type-label"
		)
		local parts: { Shared.Child } = { title, weekdayRow, grid }
		return ctx.column(parts, { Name = `Pane{k}` })
	end

	local function navigate(panel: Frame)
		local function focusedCell(use: Use?): (number?, number?)
			local node = if use then use(selected) else selected:peek()
			local at = if node ~= nil then cellIndex[node] else nil
			if at == nil then
				return nil, nil
			end
			return at.k, at.i
		end
		local function plan(step: number, use: Use?): (string?, CivilDate?)
			local k, i = focusedCell(use)
			if k == nil or i == nil then
				return nil, nil
			end
			local target = civil.addDays(paneGrid(k, use)[i], step)
			if cellFor(target, use) ~= nil then
				return "move", target
			end
			if math.abs(step) == 1 and canPage(step, use) then
				return "page", target
			end
			return nil, nil
		end
		local function focusDay(d: CivilDate)
			local k, i = cellFor(d)
			local list = if k then cells[k] else nil
			local cell = if list and i then list[i] else nil
			if gui and cell then
				gui.SelectedObject = cell
			end
		end
		local function walk(name: string, step: number, keys: { Shared.ActionBinding })
			ctx.action(panel, name, keys, function(use: Use)
				return interactive(use) and (plan(step, use)) ~= nil
			end, function()
				local how, target = plan(step)
				if how == "page" then
					page(if step > 0 then 1 else -1)
				end
				if target then
					focusDay(target)
				end
			end, { priority = 2200 })
		end
		walk("CalendarLeft", -1, { E.KeyCode.Left, E.KeyCode.DPadLeft })
		walk("CalendarRight", 1, { E.KeyCode.Right, E.KeyCode.DPadRight })
		walk("CalendarUp", -7, { E.KeyCode.Up, E.KeyCode.DPadUp })
		walk("CalendarDown", 7, { E.KeyCode.Down, E.KeyCode.DPadDown })
		local function turn(name: string, delta: number, keys: { Shared.ActionBinding })
			ctx.action(panel, name, keys, function(use: Use)
				return interactive(use) and (focusedCell(use)) ~= nil and canPage(delta, use)
			end, function()
				page(delta)
			end, { priority = 2200 })
		end
		turn("CalendarPreviousMonth", -1, { E.KeyCode.ButtonL1, E.KeyCode.Comma })
		turn("CalendarNextMonth", 1, { E.KeyCode.ButtonR1, E.KeyCode.Period })
		if gui then
			local last: unknown = selected:peek()
			Compose.watch(function(use: Use)
				local now = use(selected)
				local entering = now ~= nil
					and cellIndex[(now :: unknown) :: Instance] ~= nil
					and last ~= nil
					and cellIndex[(last :: unknown) :: Instance] == nil
				last = now
				if entering then
					local list = cells[1]
					local target = if list then list[landing()] else nil
					if target and (target :: unknown) ~= now and target.Selectable then
						gui.SelectedObject = target
					end
				end
			end)
		end
	end

	return {
		cells = cells,
		cellIndex = cellIndex,
		cellFor = cellFor,
		landing = landing,
		upTarget = upTarget,
		downTarget = downTarget,
		pane = pane,
		navigate = navigate,
	}
end
