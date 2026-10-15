--!strict
local civil = require("./civil_date")
local fieldChrome = require("./field_chrome")
local materialize = require("./materialize")
local Shared = require("./types")
local Nav = require("./navigation_types")
local DTP = require("./date_time_picker_types")
local InputProps = require("./input_props")
local ComposeTypes = require("../vendor/compose/core")
local Parts = require("./date_time_parts")
local Options = require("./date_time_options")
local PickerState = require("./date_time_state")
local Calendar = require("./date_time_calendar")

type CivilDate = DTP.CivilDate
type Range = DTP.Range
type Spec = InputProps.DateTimePickerProps
type Use = ComposeTypes.Use
type Readable<T> = ComposeTypes.Readable<T>
type Cell<T> = ComposeTypes.Cell<T>

local CELL, GAP, ROW = Parts.CELL, Parts.GAP, Parts.ROW
local span, monthOf = Parts.span, Parts.monthOf

return function(
	ctx: Shared.Context,
	UI: Parts.Deps,
	surfaces: Nav.Surfaces,
	parts: Parts.Parts,
	chrome: fieldChrome.Chrome,
	spec: Spec,
	options: Options.Options,
	state: PickerState.State,
	calendar: Calendar.Calendar,
	panelView: ((Use) -> string) -> Frame,
	chromeSpec: fieldChrome.Options,
	rootProps: Spec,
	routeCell: Cell<string>
): Frame
	local Host, Compose, runtime = ctx.Host, ctx.Compose, ctx.runtime
	local E, D, D2, V2 = ctx.types.Enum, ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2
	local isRange, draft, locale = options.isRange, options.draft, options.locale
	local viewMonth, room, dual, preferred = state.viewMonth, state.room, state.dual, state.preferred
	local presented, requestPresented, close = state.presented, state.requestPresented, state.close
	local typedError, valueText, typedEntry = state.typedError, state.valueText, state.typedEntry
	local enabled, interactive = state.enabled, state.interactive
	local propose = state.propose
	local landing = calendar.landing

	local function parseOne(s: string): (CivilDate?, string?)
		local d, why = civil.parse(s, locale, options.withTime)
		if d ~= nil and state.isDisabled(d) then
			return nil, "That date is not available."
		end
		return d, why
	end
	local function typed(text: string): boolean
		if text == valueText:peek() then
			typedError:set("")
			return true
		end
		local next: (CivilDate? | Range)? = nil
		local why: string? = nil
		local found = false
		if isRange then
			local at, stop = string.find(text, "–", 1, true)
			if at == nil then
				at, stop = string.find(text, " - ", 1, true)
			end
			if at == nil and string.match(text, "^%s*$") ~= nil then
				next, found = span(nil, nil), true
			elseif at == nil or stop == nil then
				why = "Enter two dates, like "
					.. civil.format({ year = 2026, month = 1, day = 2 }, locale)
					.. " – "
					.. civil.format({ year = 2026, month = 1, day = 9 }, locale)
			else
				local s, f
				s, why = parseOne(string.sub(text, 1, at - 1))
				if s ~= nil then
					f, why = parseOne(string.sub(text, stop + 1))
				end
				if s ~= nil and f ~= nil then
					next = if civil.compare(s, f) <= 0 then span(s, f) else span(f, s)
					found = true
				end
			end
		elseif string.match(text, "^%s*$") ~= nil then
			next, found = nil, true
		else
			local d
			d, why = parseOne(text)
			next, found = d, d ~= nil
		end
		if not found then
			typedError:set(why or "Enter a date.")
			return false
		end
		typedError:set("")
		if propose(next) then
			if not draft then
				state.commit()
			end
			local anchor = if isRange then (next :: Range).start else next :: CivilDate?
			if anchor ~= nil then
				viewMonth:set(monthOf(anchor))
			end
		end
		return true
	end

	local root: Frame
	local entry: TextBox? = nil
	local function calendarButton(): TextButton
		return UI.Button({
			Name = "Open",
			LayoutOrder = 2,
			icon = "calendar",
			name = "Choose a date",
			Size = D2.new(0, ROW, 1, 0),
			AutomaticSize = E.AutomaticSize.None,
			corners = spec.corners,
			appearance = "utility",
			enabled = function(use: Use)
				return interactive(use)
			end,
			onActivate = function()
				requestPresented(not presented:peek())
			end,
		})
	end
	local entryView = Compose.show(function(use: Use)
		return use(typedEntry)
	end, function()
		local box = Host.TextBox "Entry" {
			LayoutOrder = 1,
			Text = valueText:peek(),
			PlaceholderText = spec.placeholder or "",
			ClearTextOnFocus = false,
			BackgroundTransparency = 1,
			Size = D2.new(1, -ROW, 1, 0),
			TextXAlignment = E.TextXAlignment.Left,
			TextEditable = function(use: Use)
				return interactive(use)
			end,
			Selectable = function(use: Use)
				return interactive(use)
			end,
			ctx.padding(12, 0) :: Shared.Child,
		}
		ctx.styled(box, "text")
		entry = box
		Compose.cleanup(function()
			if entry == box then
				entry = nil
			end
		end)
		Compose.watch(function(use: Use)
			box.Text = use(valueText)
			typedError:set("")
		end)
		runtime.connect(box, "FocusLost", function(_: boolean, event: InputObject?)
			if event and (event.KeyCode == E.KeyCode.Escape or event.KeyCode == E.KeyCode.ButtonB) then
				box.Text = valueText:peek()
				return
			end
			if not state.mayEdit() then
				box.Text = valueText:peek()
				return
			end
			if typed(box.Text) and typedError:peek() == "" then
				box.Text = valueText:peek()
			end
		end)
		return box
	end)
	local showView = Compose.show(function(use: Use)
		return not use(typedEntry)
	end, function()
		local show = UI.Button({
			Name = "Show",
			LayoutOrder = 1,
			label = function(use: Use)
				local s = use(valueText)
				return if s ~= "" then s else spec.placeholder or ""
			end,
			Size = D2.new(1, -ROW, 1, 0),
			AutomaticSize = E.AutomaticSize.None,
			TextXAlignment = E.TextXAlignment.Left,
			textSize = "body",
			corners = spec.corners,
			appearance = "utility",
			enabled = function(use: Use)
				return interactive(use)
			end,
			onActivate = function()
				requestPresented(true)
			end,
		})
		parts.tagWhile(show, "facet-secondary", function(use: Use)
			return use(valueText) == ""
		end)
		return show
	end)
	local plate = ctx.row({ entryView, showView, calendarButton() }, {
		Name = "Field",
		Size = D2.new(1, 0, 0, ROW),
		AutomaticSize = E.AutomaticSize.None,
		BackgroundTransparency = 0,
		ClipsDescendants = true,
		ctx.padding(0, 0) :: Shared.Child,
	})
	local layout = assert(plate:FindFirstChildWhichIsA("UIListLayout"))
	layout.VerticalAlignment = E.VerticalAlignment.Center
	layout.Padding = D.new(0, 0)
	ctx.styled(plate, "text-input")
	local failure = chrome.errorOf(chromeSpec, typedError)
	chrome.paint("DateTimePicker", plate, chromeSpec, function(use: Use?): boolean
		return failure(use) ~= ""
	end)
	ctx.skin(plate, "field", {
		disabled = function(use: Use)
			return not enabled(use)
		end,
	})
	root = chrome.wrap({
		control = "DateTimePicker",
		spec = chromeSpec,
		plate = plate,
		focus = function()
			local box = entry
			if box and not box:IsFocused() then
				box:CaptureFocus()
			elseif box == nil then
				requestPresented(true)
			end
		end,
		enabled = enabled,
		message = typedError,
		native = rootProps,
	})
	local anchorAvailable = surfaces.available(plate)
	local anchorSeen = false
	Compose.watch(function(use: Use)
		if use(anchorAvailable) then
			anchorSeen = true
		elseif anchorSeen and presented:peek() then
			close("anchorLost")
		end
	end)
	surfaces.attach(root, {
		surfaces.overlay(plate, presented, function(phase: Nav.PresencePhase?)
			local layer = surfaces.parent(plate)
			local extent = if layer then ctx.observe.AbsoluteSize(layer) else Compose.cell(V2.zero)
			local origin = if layer then ctx.observe.AbsolutePosition(layer) else Compose.cell(V2.zero)
			local position = ctx.observe.AbsolutePosition(plate)
			local bounds = ctx.observe.AbsoluteSize(plate)
			local tenFoot = ctx.tenFoot()
			local atTenFoot = Compose.formula(tenFoot):peek()
			local atTouch = (preferred :: Readable<unknown>):peek() == E.PreferredInput.Touch
			local route = Compose.formula(function(use: Use): string
				if atTenFoot then
					return "sheet"
				end
				local offer = use(extent) :: Vector2
				return if atTouch and offer.X > 0 and offer.X < 600 then "sheet" else "popover"
			end)
			Compose.watch(function(use: Use)
				local offer = use(extent) :: Vector2
				room:set(offer.X - 96)
				routeCell:set(use(route))
			end)
			local function routeOf(use: Use): string
				return use(route)
			end
			local panel: Frame
			local surface: Frame
			local settled = Compose.cell(false)
			local shown = surfaces.appearance(phase, ctx.motionTiming("popover"), settled)
			local modal = surfaces.modal(function()
				panel = panelView(routeOf)
				local scroll = Host.ScrollingFrame "CalendarScroll" {
					Size = D2.fromScale(1, 1),
					BorderSizePixel = 0,
					Selectable = false,
					CanvasSize = D2.fromOffset(0, 0),
					AutomaticCanvasSize = E.AutomaticSize.Y,
					ScrollingDirection = E.ScrollingDirection.Y,
					ScrollBarThickness = 4,
					VerticalScrollBarInset = E.ScrollBarInset.ScrollBar,
					panel :: Shared.Child,
				}
				surface = ctx.fade {
					Name = "CalendarSurface",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					GroupTransparency = function(use: Use): number
						return 1 - shown.opacity(use)
					end,
					scroll :: Shared.Child,
				}
				ctx.styled(scroll, "panel")
				ctx.styled(scroll, "floating")
				surfaces.skin(scroll)
				return surface
			end, function()
				close("cancel")
			end, {
				Name = "Calendar" .. "Modal",
				exiting = if phase then phase.exiting else nil,
				appearance = shown.opacity,
				initialFocus = `D{landing()}`,
				backgroundTransparency = function(use: Use): number
					return if use(route) == "sheet" then 0.5 else 1
				end,
				onOutside = function()
					close("outside")
				end,
			})
			local content = ctx.observe.AbsoluteSize(panel)
			local measured = ctx.observe.AbsoluteSize(surface)
			local function sheet(use: Use): boolean
				return use(route) == "sheet" and not atTenFoot
			end
			runtime.decorate(panel, {
				Size = function(use: Use)
					if sheet(use) then
						return D2.new(1, 0, 0, 0)
					end
					local width = if use(dual) then 2 * 7 * CELL + GAP else 7 * CELL
					return D2.fromOffset(width + 32, 0)
				end,
			})
			local geometry: Shared.CanvasGroupNativeProps = {
				Size = function(use: Use)
					local function carve(side: string): number
						return surfaces.inset(0, side, nil, use)
					end
					local offer = use(extent) :: Vector2
					local height = (use(content) :: Vector2).Y + carve("top") + carve("bottom")
					if offer.Y > 0 then
						height = math.min(height, offer.Y - 16)
					end
					if sheet(use) then
						return D2.new(1, -24, 0, height)
					end
					local width = if use(dual) then 2 * 7 * CELL + GAP else 7 * CELL
					return D2.fromOffset(width + 32 + carve("left") + carve("right"), height)
				end,
				Position = function(use: Use)
					local at, size, offer, box, offset =
						use(position) :: Vector2,
						use(bounds) :: Vector2,
						use(extent) :: Vector2,
						use(measured) :: Vector2,
						use(origin) :: Vector2
					if use(route) == "sheet" then
						if atTenFoot then
							return D2.fromOffset(math.max(8, (offer.X - box.X) / 2), math.max(8, (offer.Y - box.Y) / 2))
						end
						return D2.fromOffset(12, math.max(8, offer.Y - box.Y - 12))
					end
					local left = at.X - offset.X
					local top = at.Y - offset.Y + size.Y + 4
					local above = at.Y - offset.Y - box.Y - 4
					if offer.Y > 0 and top + box.Y > offer.Y - 8 then
						if above >= 8 then
							top = above
						else
							top = math.max(8, offer.Y - box.Y - 8)
						end
					end
					if offer.X > 0 then
						left = math.clamp(left, 8, math.max(8, offer.X - box.X - 8))
					end
					if offer.Y > 0 then
						top = math.clamp(top, 8, math.max(8, offer.Y - box.Y - 8))
					end
					return D2.fromOffset(left, math.max(8, top))
				end,
			}
			runtime.decorate(surface, geometry)
			surfaces.atRest(shown.travel, settled, { surface, panel })
			materialize(ctx, surface, geometry, function(use: Use): number
				local from = ctx.metric("motion.materialize.anchored", use)
				return if use(settled) then from + (1 - from) * shown.travel(use) else 1
			end, nil, true)
			return modal
		end, { motion = ctx.motionTiming("popover") }),
	})
	return root
end
