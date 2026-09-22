--!strict
return {
	title = "Choices and filters",
	ledgerRows = { "CONTROL-SELECTION" },
	build = function(ctx)
		local UI, Compose = ctx.UI, ctx.Compose
		local signal = Compose.cell
		-- The host may expose a control's record for drivers and reports.
		local function record(id: string): any
			return if ctx.controlRecord ~= nil then ctx.controlRecord(id) else nil
		end
		local function open(id: string): boolean
			local control = record(id)
			if control == nil then
				return false
			end
			control.api.open()
			return true
		end
		local function dumpOf(id: string): any
			local control = record(id)
			return if control ~= nil then control.dump() else nil
		end
		local enabled = signal(true)
		local checked = signal(false)
		local mixed = signal(true)
		local boost = signal(false)
		local selected = signal("open")
		local club = signal(false)
		local choices = signal({
			{ id = "open", value = "open", label = "Open races" },
			{
				id = "club",
				value = "club",
				label = "Club races",
				description = "Join a club to unlock these races.",
				enabled = club,
			},
		})
		local query = signal("")
		local track = signal("track-1")
		local tagCoastal, tagForest, tagSnow = signal(true), signal(false), signal(false)
		-- the picker as a field, cards and a stroked strip
		local driver = signal("d3")
		local driverError = signal("")
		local mode = signal("sprint")
		local laps = signal("5")
		local rootPath: string? = nil
		local records: { [string]: any } = {}
		local function keep(id: string)
			return function(r: any)
				records[id] = r
			end
		end
		local comboValue = signal("road")
		local comboText = signal("Road")
		local tracks = {}
		for i = 1, 250 do
			table.insert(tracks, {
				id = "track-" .. i,
				label = string.format(
					"Track %03d · %s",
					i,
					({ "Coastal circuit", "Forest sprint", "Mountain pass", "Harbor loop" })[(i - 1) % 4 + 1]
				),
			})
		end
		local function switch()
			return UI.Toggle("Switch")({ label = "Enable choices", value = enabled })
		end
		local function checkbox()
			return UI.Toggle("Checkbox")({
				label = "Include night races and their full race results",
				value = checked,
				mixed = mixed,
				presentation = "checkbox",
				enabled = enabled,
			})
		end
		local function toggle()
			return UI.Toggle("Boost")({
				label = "Boost mode",
				value = boost,
				presentation = "button",
				enabled = enabled,
			})
		end
		--[[ ONE SELECTION CONTROL, FOUR STYLES (picker round, 2026-09-11). The
			same `selected` signal drives a radio group, a segmented strip and the
			DEFAULT — `style = "automatic"`, which is the menu on this phone and on
			a desktop (a form row: title leading, value and chevron trailing, the
			options anchored to it) and a focus-navigable strip on a television. A
			searchable list is the navigation link; a set of independent checks is
			a `Menu` with `checked` items, because a picker holds ONE value. ]]
		local function radio()
			return UI.Picker("Radio")({
				selected = selected,
				options = choices,
				style = "radioGroup",
				enabled = enabled,
			})
		end
		local function segmented()
			return UI.Picker("Segments")({
				selected = selected,
				options = { { value = "open", label = "Open" }, { value = "club", label = "Club", enabled = club } },
				style = "segmented",
				enabled = enabled,
			})
		end
		local function popup()
			return UI.Picker("Popup")({
				label = "Race group",
				selected = selected,
				options = {
					{ value = "open", label = "Open races" },
					{ value = "club", label = "Club races", description = "Join a club to unlock.", enabled = club },
				},
				enabled = enabled,
			})
		end
		local trackOptions = {}
		for _, item in tracks do
			table.insert(trackOptions, { value = item.id, label = item.label })
		end
		local function search()
			return UI.Picker("Tracks")({
				label = "Track",
				selected = track,
				options = trackOptions,
				query = query,
				enabled = enabled,
			})
		end
		local function multi()
			return UI.Menu("Tags")({
				trigger = UI.Button("Trigger")({
					label = "Scenery filters",
					enabled = enabled,
					onActivate = function() end,
				}),
				items = {
					{ id = "coastal", label = "Coastal", checked = tagCoastal },
					{ id = "forest", label = "Forest", checked = tagForest },
					{
						id = "snow",
						label = "Snow",
						checked = tagSnow,
						enabled = false,
						description = "Winter routes are closed.",
					},
				},
			})
		end
		local DRIVERS = {}
		for i, name in { "Ada", "Bo", "Cy", "Dee", "Eli", "Fay", "Gus", "Hal", "Ivy", "Jo", "Kai", "Lu" } do
			table.insert(DRIVERS, {
				value = "d" .. i,
				label = name,
				avatar = { name = name },
				badge = if i == 2 then 3 else nil,
				sectionTitle = if i == 1 then "Crew" elseif i == 5 then "Rivals" else nil,
			})
		end
		local function driverField()
			return UI.Picker("Driver")({
				label = "Driver",
				requiredMark = "required",
				hint = "Who takes the wheel for this race.",
				errorText = driverError,
				style = "menu",
				maxHeight = 220,
				selected = driver,
				options = DRIVERS,
				enabled = enabled,
				ref = keep("Driver"),
			})
		end
		local function cards()
			return UI.Picker("Mode")({
				label = "Race mode",
				style = "cards",
				axis = "x",
				required = false,
				selected = mode,
				options = {
					{ value = "sprint", label = "Sprint", description = "Three short laps", meta = "3 laps" },
					{ value = "endurance", label = "Endurance", description = "A long race", meta = "20 laps" },
					{
						value = "night",
						label = "Night",
						description = "Unlocks at level 10",
						meta = "Soon",
						enabled = false,
					},
				},
				enabled = enabled,
			})
		end
		local function lapStrip()
			return UI.Picker("Laps")({
				style = "segmented",
				appearance = "stroke",
				corners = "pill",
				controlSize = "compact",
				selected = laps,
				options = { { value = "3", label = "3" }, { value = "5", label = "5" }, { value = "10", label = "10" } },
				enabled = enabled,
			})
		end
		local function combo()
			return UI.ComboBox("Vehicle")({
				value = comboValue,
				text = comboText,
				options = { { id = "road", label = "Road" }, { id = "rally", label = "Rally" } },
				enabled = enabled,
				acceptCustom = function(text)
					return #text >= 3 and #text <= 24, "Use 3 to 24 characters."
				end,
			})
		end
		local function reset()
			enabled:set(true)
			checked:set(false)
			mixed:set(true)
			boost:set(false)
			club:set(false)
			selected:set("open")
			query:set("")
			track:set("track-1")
			tagCoastal:set(true)
			tagForest:set(false)
			tagSnow:set(false)
			comboValue:set("road")
			comboText:set("Road")
			driver:set("d3")
			driverError:set("")
			mode:set("sprint")
			laps:set("5")
		end
		local function heading(text)
			return UI.Text({ text = text, textSize = "heading", width = UI.fill() })
		end
		--[[ THE DEMO SAYS WHAT EACH CONTROL IS (user review 2026-09-12): a
			capture of this page could not be read without the source beside it.
			One caption above every control — the control and the style it was
			asked for — so a screenshot names its own subjects. ]]
		local function caption(id: string, text: string)
			return UI.Text(id)({ text = text, textSize = "caption", role = "secondary", width = UI.fill() })
		end

		local function body()
			return UI.VStack("Body")({
				width = UI.fill(),
				gap = "m",

				UI.Text({ text = "Choices and filters", textSize = "title", width = UI.fill() }),
				UI.Button("Reset")({ label = "Reset", onActivate = reset }),
				caption("CapSwitch", "Toggle · switch"),
				switch(),
				heading("Check and toggle"),
				caption("CapCheck", "Checkbox · mixed state"),
				checkbox(),
				caption("CapToggle", "Toggle · button presentation"),
				toggle(),
				heading("Choose a race group"),
				caption("CapRadio", "Picker · radioGroup"),
				radio(),
				caption("CapSegments", "Picker · segmented"),
				segmented(),
				caption("CapPopup", "Picker · automatic (menu on touch and pointer; rows on a television)"),
				popup(),
				UI.Button("Join")({
					label = "Toggle club membership",
					onActivate = function()
						club:set(not club:peek())
					end,
				}),
				heading("Pick a driver and a race"),
				caption("CapDriver", "Picker · menu field (required, hint or error, avatars, sections, maxHeight)"),
				driverField(),
				caption("CapMode", "Picker · cards (choose again to clear)"),
				cards(),
				caption("CapLaps", "Picker · segmented, stroke, pill, compact"),
				lapStrip(),
				heading("Search 250 tracks"),
				caption("CapSearch", "Picker · navigationLink (searchable sheet)"),
				search(),
				heading("Filter by scenery"),
				caption("CapMenu", "Menu · checked items"),
				multi(),
				heading("Choose or name a vehicle class"),
				caption("CapCombo", "ComboBox · suggestions with custom text"),
				combo(),
			})
		end
		local function screen()
			return UI.Screen("SelectionControls")({
				surface = "base",
				onAppear = function(path)
					rootPath = path
				end,
				onDisappear = function()
					rootPath = nil
				end,
				padding = { top = "m", bottom = "m" },
				gap = "s",

				UI.ScrollView("Content")({
					width = UI.fill(),
					height = UI.fill(),
					padding = { left = "m", right = "m" },
					body(),
				}),
			})
		end
		return {
			screen = screen,
			states = function()
				return {
					{
						id = "search",
						kind = "popup",
						open = function()
							return open("Tracks")
						end,
					},
					{
						id = "no-results",
						kind = "popup",
						open = function()
							query:set("unlisted")
							return open("Tracks")
						end,
					},
					{
						id = "multiple",
						kind = "popup",
						open = function()
							return open("Tags")
						end,
					},
					{
						id = "race-group",
						kind = "popup",
						open = function()
							return open("Popup")
						end,
					},
				}
			end,
			steps = {
				reset = reset,
				disable = function()
					enabled:set(false)
				end,
				no_results = function()
					query:set("unlisted")
				end,
				-- the error line swaps in place under the driver field
				driverError = function(b)
					driverError:set(if driverError:peek() == "" then "Pick a driver to continue." else "")
					local controller = if type(b) == "table" and b.handle ~= nil then b.handle.controller else nil
					if controller == nil or rootPath == nil then
						return { error = driverError:peek() }
					end
					controller.refresh()
					local base = rootPath .. "/Content/Body/Driver"
					return {
						error = driverError:peek(),
						mark = controller.rectOf(base .. "/Message/MarkWhen/then/MessageMark") ~= nil,
						line = controller.rectOf(base .. "/Message/Validation") ~= nil,
					}
				end,
				-- the row of cards wraps rather than running off a narrow screen
				modeWrap = function(b)
					local controller = if type(b) == "table" and b.handle ~= nil then b.handle.controller else nil
					if controller == nil or rootPath == nil then
						return {}
					end
					controller.refresh()
					local rows, seen, inside = 0, {}, true
					local band = controller.rectOf(rootPath .. "/Content/Body/Mode")
					for _, key in { "sprint", "endurance", "night" } do
						local r = controller.rectOf(`{rootPath}/Content/Body/Mode/Options/Cards/[{key}]/Card-{key}`)
						if r ~= nil then
							if not seen[r.y] then
								seen[r.y] = true
								rows += 1
							end
							inside = inside and band ~= nil and r.x + r.w <= band.x + band.w + 0.5
						end
					end
					return { rows = rows, inside = inside }
				end,
				replace_options = function()
					choices:set({
						{ id = "open", value = "open", label = "Public races" },
						{ id = "club", value = "club", label = "Member races", enabled = club },
					})
				end,
			},
			report = function()
				return {
					checkbox = dumpOf("Checkbox"),
					radio = dumpOf("Radio"),
					popup = dumpOf("Popup"),
					search = dumpOf("Tracks"),
					multiple = dumpOf("Tags"),
					combo = dumpOf("Vehicle"),
					driver = if records.Driver then records.Driver.dump() else nil,
					mode = mode:peek(),
				}
			end,
			-- nothing outlives the screen
			dispose = function() end,
		}
	end,
}
