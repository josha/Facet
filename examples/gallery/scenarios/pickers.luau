--!strict
--[[ Pickers: `UI.ColorPicker` over caller-owned colours (docs/reference/api.md#uicolorpicker)
	and `UI.DateTimePicker` over caller-owned civil dates (#uidatetimepicker).
	Colours: a labelled well with opacity and every technique, a bare well over a
	team palette, a draft well that commits only on Apply, and the panel inline.
	Dates: a race day inside a season with a blackout day, a start time on a
	15-minute grid, and a season window with presets and an Apply/Cancel draft.
	"Today" is a fixed demo day, so the presets read the same everywhere. The
	committed line changes only on a commit; a toggle refuses proposals. ]]
local COPY = {
	refuse = "Refuse changes",
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
	thisWeek = "This week",
	thisMonth = "This month",
	lastYear = "Last year",
}

return {
	title = "Pickers",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local refuse = Compose.cell(false)
		local body = Compose.cell(Color3.fromRGB(46, 125, 255))
		local bodyAlpha = Compose.cell(1)
		local trim = Compose.cell(Color3.fromRGB(255, 196, 0))
		local livery = Compose.cell(Color3.fromRGB(220, 40, 60))
		local fog = Compose.cell(Color3.fromRGB(180, 200, 220))
		local committed = Compose.cell(COPY.none)
		local function accept(cell: any): (any) -> ()
			return function(next: any)
				if not refuse:peek() then
					cell:set(next)
				end
			end
		end
		local civil = ctx.Facet.civilDate
		local TODAY = { year = 2026, month = 9, day = 23 }
		local raceDay = Compose.cell({ year = 2026, month = 10, day = 4 } :: any)
		local starts = Compose.cell({ year = 2026, month = 10, day = 4, hour = 14, minute = 30 } :: any)
		local window = Compose.cell({} :: any)
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
				range = function(today: any)
					-- the window's weeks start on Monday (weekStart = 2)
					local start = civil.addDays(today, -((civil.weekday(today) + 5) % 7))
					return { start = start, finish = civil.addDays(start, 6) }
				end,
			},
			{
				id = "month",
				label = COPY.thisMonth,
				range = function(today: any)
					return {
						start = { year = today.year, month = today.month, day = 1 },
						finish = { year = today.year, month = today.month, day = civil.daysIn(today.year, today.month) },
					}
				end,
			},
			{
				id = "lastYear",
				label = COPY.lastYear,
				range = function(today: any)
					return {
						start = { year = today.year - 1, month = 1, day = 1 },
						finish = { year = today.year - 1, month = 12, day = 31 },
					}
				end,
			},
		}
		local function record(c: any)
			committed:set(
				string.format(
					"#%02X%02X%02X",
					math.floor(c.R * 255 + 0.5),
					math.floor(c.G * 255 + 0.5),
					math.floor(c.B * 255 + 0.5)
				)
			)
		end
		local team = {
			{ color = Color3.fromRGB(255, 196, 0), label = "Gold" },
			{ color = Color3.fromRGB(20, 20, 24), label = "Carbon" },
			{ color = Color3.fromRGB(240, 240, 240), label = "Chalk" },
			{ color = Color3.fromRGB(0, 170, 140), label = "Teal" },
		}

		local function section(): any
			return UI.VStack("Pickers")({
				width = UI.fill(),
				gap = "m",
				UI.Text("ColoursTitle")({ text = COPY.colours, textSize = "label", width = UI.fill() }),
				UI.Toggle("Refuse")({ label = COPY.refuse, value = refuse }),
				UI.Text("Committed")({
					width = UI.fill(),
					text = function(use: any): string
						return `{COPY.committed} {use(committed)}`
					end,
				}),
				UI.ColorPicker("Body")({
					label = COPY.body,
					hint = COPY.bodyHint,
					value = body,
					onChange = accept(body),
					onCommit = record,
					alpha = bodyAlpha,
					onAlphaChange = accept(bodyAlpha),
					modes = { "swatches", "spectrum", "sliders", "brick" },
				}),
				UI.HStack("Wells")({
					gap = "m",
					align = "center",
					UI.Text("TrimLabel")({ text = COPY.trim }),
					UI.ColorPicker("Trim")({
						value = trim,
						onChange = accept(trim),
						onCommit = record,
						swatches = team,
					}),
				}),
				UI.ColorPicker("Livery")({
					label = COPY.livery,
					value = livery,
					onChange = accept(livery),
					onCommit = record,
					draft = true,
				}),
				UI.ColorPicker("Fog")({
					label = COPY.fog,
					style = "inline",
					modes = { "sliders" },
					value = fog,
					onChange = accept(fog),
					onCommit = record,
				}),
				UI.Text("DatesTitle")({ text = COPY.dates, textSize = "label", width = UI.fill() }),
				UI.DateTimePicker("RaceDay")({
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
					clock = function()
						return TODAY
					end,
				}),
				UI.DateTimePicker("Starts")({
					label = COPY.starts,
					value = starts,
					onChange = accept(starts),
					onCommit = recordDate,
					time = true,
					minuteStep = 15,
					clock = function()
						return TODAY
					end,
				}),
				UI.DateTimePicker("Window")({
					label = COPY.window,
					selection = "range",
					range = window,
					onRangeChange = accept(window),
					onRangeCommit = recordRange,
					presets = presets,
					draft = true,
					weekStart = 2,
					clock = function()
						return TODAY
					end,
				}),
			})
		end

		return {
			section = section,
			screen = function()
				return UI.Screen("PickersScreen")({
					surface = "base",
					padding = { top = "m", bottom = "m" },
					UI.ScrollView("Content")({
						width = UI.fill(),
						height = UI.fill(),
						padding = { left = "m", right = "m" },
						section(),
					}),
				})
			end,
			steps = {},
		}
	end,
}
