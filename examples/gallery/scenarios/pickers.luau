--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ExampleContext = typeof(require("@repo/examples/types").Context)
type Built = typeof(require("@repo/examples/types").Built)
type CivilDate = typeof(require("@repo/tools/typecheck/aliases").CivilDate)
type CivilDateModule = typeof(require("@repo/tools/typecheck/aliases").CivilDateModule)
type CivilRange = typeof(require("@repo/tools/typecheck/aliases").CivilRange)
type TextValue = typeof(require("@repo/tools/typecheck/aliases").TextPropsText)
type Readable<T> = { peek: (Readable<T>) -> T }
type Settable<T> = { set: (Settable<T>, T) -> () }
type Use = <T>(Readable<T>) -> T
type ColorMode = "brick" | "sliders" | "spectrum" | "swatches"
type Swatch = Color3 | { color: Color3, label: string? }
type SwatchItem = { color: Color3, label: string?, key: string }
type Preset = { id: string, label: string, range: (CivilDate) -> CivilRange }
local COPY = {
	title = "Pickers",
	refuse = "Refuse changes",
	accent = "Accent",
	body = "Kart body",
	bodyHint = "Shown on the track and in the garage",
	trim = "Trim",
	livery = "Livery",
	fog = "Fog colour",
	committed = "Committed:",
	none = "nothing yet",
	colours = "Colours",
	dates = "Dates",
	raceDay = "Race day",
	raceHint = "The season runs March 2026 to November 2027; the 13th is closed for maintenance",
	starts = "Starts",
	window = "Season window",
	windowEmpty = "Choose a start and an end",
	thisWeek = "This week",
	thisMonth = "This month",
	lastYear = "Last year",
}

return {
	title = "Pickers",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: ExampleContext): Built
		local UI, Compose: ComposeModule, Host = ctx.UI, ctx.Compose, ctx.Host
		local nativeTypes = ctx.types
		local UDim, UDim2, Color3, Enum = nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Color3, nativeTypes.Enum
		local civil: CivilDateModule = ctx.Facet.civilDate
		local refuse = Compose.cell(false)
		local accent = Compose.cell(Color3.fromRGB(213, 64, 245))
		local body = Compose.cell(Color3.fromRGB(46, 125, 255))
		local bodyAlpha = Compose.cell(1)
		local trim = Compose.cell(Color3.fromRGB(255, 196, 0))
		local livery = Compose.cell(Color3.fromRGB(220, 40, 60))
		local fog = Compose.cell(Color3.fromRGB(180, 200, 220))
		local committed = Compose.cell(COPY.none)
		local TODAY: CivilDate = { year = 2026, month = 9, day = 23 }
		local initialRaceDay: CivilDate? = { year = 2026, month = 10, day = 4 }
		local raceDay = Compose.cell(initialRaceDay)
		local initialStarts: CivilDate? = { year = 2026, month = 10, day = 4, hour = 14, minute = 30 }
		local starts = Compose.cell(initialStarts)
		local initialWindow: CivilRange = {}
		local window = Compose.cell(initialWindow)
		local function accept<T>(cell: Settable<T>): (T) -> ()
			return function(next: T)
				if not refuse:peek() then
					cell:set(next)
				end
			end
		end
		local function today(): CivilDate
			return TODAY
		end
		local function hex(c: Color3): string
			return string.format(
				"#%02X%02X%02X",
				math.floor(c.R * 255 + 0.5),
				math.floor(c.G * 255 + 0.5),
				math.floor(c.B * 255 + 0.5)
			)
		end
		local function record(c: Color3)
			committed:set(hex(c))
		end
		local function recordDate(v: CivilDate?)
			committed:set(if v == nil then COPY.none else civil.format(v))
		end
		local function recordRange(r: CivilRange)
			committed:set(`{civil.format(assert(r.start))} – {civil.format(assert(r.finish))}`)
		end
		local presets: { Preset } = {
			{
				id = "week",
				label = COPY.thisWeek,
				range = function(day: CivilDate)
					local start = civil.addDays(day, -((civil.weekday(day) + 5) % 7))
					return { start = start, finish = civil.addDays(start, 6) }
				end,
			},
			{
				id = "month",
				label = COPY.thisMonth,
				range = function(day: CivilDate)
					return {
						start = { year = day.year, month = day.month, day = 1 },
						finish = { year = day.year, month = day.month, day = civil.daysIn(day.year, day.month) },
					}
				end,
			},
			{
				id = "lastYear",
				label = COPY.lastYear,
				range = function(day: CivilDate)
					return {
						start = { year = day.year - 1, month = 1, day = 1 },
						finish = { year = day.year - 1, month = 12, day = 31 },
					}
				end,
			},
		}
		local initialTeam: { Swatch } = {
			{ color = Color3.fromRGB(255, 196, 0), label = "Gold" },
			{ color = Color3.fromRGB(20, 20, 24), label = "Carbon" },
			{ color = Color3.fromRGB(240, 240, 240), label = "Chalk" },
			{ color = Color3.fromRGB(0, 170, 140), label = "Teal" },
		}
		local team = Compose.cell(initialTeam)
		local function saveTeam(c: Color3)
			local list = table.clone(team:peek())
			table.insert(list, c)
			team:set(list)
		end
		local function removeTeam(item: SwatchItem)
			local list = {}
			for _, entry in team:peek() do
				local key = if type(entry) == "table" then entry.label or hex(entry.color) else hex(entry)
				if key ~= item.key then
					table.insert(list, entry)
				end
			end
			team:set(list)
		end
		local function text(
			name: string,
			words: TextValue,
			role: "body" | "caption" | "control" | "heading" | "label" | "numeral" | "strong" | "title"
		)
			return UI.Text({
				Name = name,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				text = words,
				textRole = role,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end
		local function page()
			local spectrumModes: { ColorMode } = { "spectrum" }
			local allModes: { ColorMode } = { "swatches", "spectrum", "sliders", "brick" }
			local sliderModes: { ColorMode } = { "sliders" }
			return Host.Frame("Pickers")({
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 16),
				}),
				text("Title", COPY.title, "title"),
				text("ColoursTitle", COPY.colours, "heading"),
				UI.Toggle "Refuse" { label = COPY.refuse, value = refuse },
				text("Committed", function(use: Use): string
					return `{COPY.committed} {use(committed)}`
				end, "body"),
				Host.Frame("Inline")({
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UISizeConstraint({ MaxSize = nativeTypes.Vector2.new(360, math.huge) }),
					UI.ColorPicker "Accent" {
						label = COPY.accent,
						style = "inline",
						modes = spectrumModes,
						value = accent,
						onChange = accept(accent),
						onCommit = record,
					},
				}),
				UI.ColorPicker "Body" {
					label = COPY.body,
					hint = COPY.bodyHint,
					value = body,
					onChange = accept(body),
					onCommit = record,
					alpha = bodyAlpha,
					onAlphaChange = accept(bodyAlpha),
					modes = allModes,
				},
				Host.Frame("Wells")({
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 16),
					}),
					UI.Text "TrimLabel" {
						LayoutOrder = 1,
						BackgroundTransparency = 1,
						AutomaticSize = Enum.AutomaticSize.XY,
						text = COPY.trim,
					},
					UI.ColorPicker "Trim" {
						LayoutOrder = 2,
						value = trim,
						onChange = accept(trim),
						onCommit = record,
						swatches = team,
						onSaveSwatch = saveTeam,
						onRemoveSwatch = removeTeam,
					},
				}),
				UI.ColorPicker "Livery" {
					label = COPY.livery,
					value = livery,
					onChange = accept(livery),
					onCommit = record,
					draft = true,
				},
				UI.ColorPicker "Fog" {
					label = COPY.fog,
					style = "inline",
					modes = sliderModes,
					value = fog,
					onChange = accept(fog),
					onCommit = record,
				},
				text("DatesTitle", COPY.dates, "heading"),
				UI.DateTimePicker "RaceDay" {
					label = COPY.raceDay,
					hint = COPY.raceHint,
					value = raceDay,
					onChange = accept(raceDay),
					onCommit = recordDate,
					min = { year = 2026, month = 3, day = 1 },
					max = { year = 2027, month = 11, day = 30 },
					isDateDisabled = function(d: CivilDate): boolean
						return d.day == 13
					end,
					clock = today,
				},
				UI.DateTimePicker "Starts" {
					label = COPY.starts,
					value = starts,
					onChange = accept(starts),
					onCommit = recordDate,
					time = true,
					minuteStep = 15,
					clock = today,
				},
				UI.DateTimePicker "Window" {
					label = COPY.window,
					placeholder = COPY.windowEmpty,
					selection = "range",
					range = window,
					onRangeChange = accept(window),
					onRangeCommit = recordRange,
					presets = presets,
					draft = true,
					weekStart = 2,
					clock = today,
				},
			})
		end
		local function screen()
			return Host.Frame("PickersScreen")({
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				UI.ScrollView "Content" {
					padding = 16,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					ScrollBarThickness = 6,
					page(),
				},
			})
		end
		return {
			screen = screen,
			steps = {
				refuse = function()
					refuse:set(not refuse:peek())
					return { refuse = refuse:peek() }
				end,
			},
			report = function()
				return {
					committed = committed:peek(),
					accent = hex(accent:peek()),
					body = hex(body:peek()),
					alpha = bodyAlpha:peek(),
					trim = hex(trim:peek()),
					swatches = #team:peek(),
					raceDay = civil.format(assert(raceDay:peek())),
					refuse = refuse:peek(),
				}
			end,
			dispose = function() end,
		}
	end,
}
