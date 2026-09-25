--!strict
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
	raceHint = "The 13th is closed for maintenance",
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
	build = function(ctx)
		local UI, Compose, Host = ctx.UI, ctx.Compose, ctx.Host
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Color3, Enum = nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Color3, nativeTypes.Enum
		local civil = ctx.Facet.civilDate
		local refuse = Compose.cell(false)
		local accent = Compose.cell(Color3.fromRGB(213, 64, 245))
		local body = Compose.cell(Color3.fromRGB(46, 125, 255))
		local bodyAlpha = Compose.cell(1)
		local trim = Compose.cell(Color3.fromRGB(255, 196, 0))
		local livery = Compose.cell(Color3.fromRGB(220, 40, 60))
		local fog = Compose.cell(Color3.fromRGB(180, 200, 220))
		local committed = Compose.cell(COPY.none)
		local TODAY = { year = 2026, month = 9, day = 23 }
		local raceDay = Compose.cell({ year = 2026, month = 10, day = 4 } :: any)
		local starts = Compose.cell({ year = 2026, month = 10, day = 4, hour = 14, minute = 30 } :: any)
		local window = Compose.cell({} :: any)
		local function accept(cell: any): (any) -> ()
			return function(next: any)
				if not refuse:peek() then
					cell:set(next)
				end
			end
		end
		local function today(): any
			return TODAY
		end
		local function hex(c: any): string
			return string.format(
				"#%02X%02X%02X",
				math.floor(c.R * 255 + 0.5),
				math.floor(c.G * 255 + 0.5),
				math.floor(c.B * 255 + 0.5)
			)
		end
		local function record(c: any)
			committed:set(hex(c))
		end
		local function recordDate(v: any)
			committed:set(if v == nil then COPY.none else civil.format(v))
		end
		local function recordRange(r: any)
			committed:set(`{civil.format(r.start)} – {civil.format(r.finish)}`)
		end
		local presets = {
			{
				id = "week",
				label = COPY.thisWeek,
				range = function(day: any)
					local start = civil.addDays(day, -((civil.weekday(day) + 5) % 7))
					return { start = start, finish = civil.addDays(start, 6) }
				end,
			},
			{
				id = "month",
				label = COPY.thisMonth,
				range = function(day: any)
					return {
						start = { year = day.year, month = day.month, day = 1 },
						finish = { year = day.year, month = day.month, day = civil.daysIn(day.year, day.month) },
					}
				end,
			},
			{
				id = "lastYear",
				label = COPY.lastYear,
				range = function(day: any)
					return {
						start = { year = day.year - 1, month = 1, day = 1 },
						finish = { year = day.year - 1, month = 12, day = 31 },
					}
				end,
			},
		}
		local team = Compose.cell({
			{ color = Color3.fromRGB(255, 196, 0), label = "Gold" },
			{ color = Color3.fromRGB(20, 20, 24), label = "Carbon" },
			{ color = Color3.fromRGB(240, 240, 240), label = "Chalk" },
			{ color = Color3.fromRGB(0, 170, 140), label = "Teal" },
		} :: { any })
		local function saveTeam(c: any)
			local list = table.clone(team:peek())
			table.insert(list, c)
			team:set(list)
		end
		local function removeTeam(item: any)
			local list = {}
			for _, entry in team:peek() do
				local key = if type(entry) == "table" and entry.label ~= nil then entry.label else hex(entry)
				if key ~= item.key then
					table.insert(list, entry)
				end
			end
			team:set(list)
		end
		local function text(name: string, words: any, role: string)
			return UI.Label({
				Name = name,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Text = words,
				textRole = role,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end
		local function page()
			return Host.Frame "Pickers" {
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
				text("Committed", function(use: any): string
					return `{COPY.committed} {use(committed)}`
				end, "body"),
				Host.Frame "Inline" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UISizeConstraint({ MaxSize = nativeTypes.Vector2.new(360, math.huge) }),
					UI.ColorPicker "Accent" {
						label = COPY.accent,
						style = "inline",
						modes = { "spectrum" },
						value = accent,
						onChange = accept(accent),
						onCommit = record,
					},
				},
				UI.ColorPicker "Body" {
					label = COPY.body,
					hint = COPY.bodyHint,
					value = body,
					onChange = accept(body),
					onCommit = record,
					alpha = bodyAlpha,
					onAlphaChange = accept(bodyAlpha),
					modes = { "swatches", "spectrum", "sliders", "brick" },
				},
				Host.Frame "Wells" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 16),
					}),
					UI.Label({
						Name = "TrimLabel",
						LayoutOrder = 1,
						BackgroundTransparency = 1,
						AutomaticSize = Enum.AutomaticSize.XY,
						Text = COPY.trim,
					}),
					UI.ColorPicker "Trim" {
						LayoutOrder = 2,
						value = trim,
						onChange = accept(trim),
						onCommit = record,
						swatches = team,
						onSaveSwatch = saveTeam,
						onRemoveSwatch = removeTeam,
					},
				},
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
					modes = { "sliders" },
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
					max = { year = 2026, month = 11, day = 30 },
					isDateDisabled = function(d: any): boolean
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
			}
		end
		local function screen()
			return Host.Frame "PickersScreen" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				Host.UIPadding({
					PaddingTop = UDim.new(0, 16),
					PaddingBottom = UDim.new(0, 16),
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
				}),
				Host.ScrollingFrame "Content" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					CanvasSize = UDim2.new(),
					ScrollBarThickness = 6,
					Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder }),
					page(),
				},
			}
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
					raceDay = civil.format(raceDay:peek()),
					refuse = refuse:peek(),
				}
			end,
			dispose = function() end,
		}
	end,
}
