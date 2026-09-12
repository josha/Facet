--!strict
return {
	title = "Choices and filters",
	ledgerRows = { "CONTROL-SELECTION" },
	build = function(ctx)
		local Facet, core = ctx.Facet, ctx.core
		local UI = Facet.UI
		local scope = core:scope("selection-controls")
		local function signal(value)
			return scope:own(core:signal(value))
		end
		local function own(control)
			return scope:own(control)
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
		local switch = own(Facet.Controls.Toggle(core, { id = "Switch", label = "Enable choices", value = enabled }))
		local checkbox = own(Facet.Controls.Toggle(core, {
			id = "Checkbox",
			label = "Include night races and their full race results",
			value = checked,
			mixed = mixed,
			presentation = "checkbox",
			enabled = enabled,
		}))
		local toggle = own(
			Facet.Controls.Toggle(
				core,
				{ id = "Boost", label = "Boost mode", value = boost, presentation = "button", enabled = enabled }
			)
		)
		--[[ ONE SELECTION CONTROL, FOUR STYLES (picker round, 2026-09-11). The
			same `selected` signal drives a radio group, a segmented strip and the
			DEFAULT — `style = "automatic"`, which is the menu on this phone and on
			a desktop (a form row: title leading, value and chevron trailing, the
			options anchored to it) and a focus-navigable strip on a television. A
			searchable list is the navigation link; a set of independent checks is
			a `Menu` with `checked` items, because a picker holds ONE value. ]]
		local radio = own(Facet.Controls.Picker(core, {
			id = "Radio",
			selected = selected,
			options = choices,
			style = "radioGroup",
			enabled = enabled,
		}))
		local segmented = own(Facet.Controls.Picker(core, {
			id = "Segments",
			selected = selected,
			options = { { value = "open", label = "Open" }, { value = "club", label = "Club", enabled = club } },
			style = "segmented",
			enabled = enabled,
		}))
		local popup = own(Facet.Controls.Picker(core, {
			id = "Popup",
			label = "Race group",
			selected = selected,
			options = {
				{ value = "open", label = "Open races" },
				{ value = "club", label = "Club races", description = "Join a club to unlock.", enabled = club },
			},
			enabled = enabled,
		}))
		local trackOptions = {}
		for _, item in tracks do
			table.insert(trackOptions, { value = item.id, label = item.label })
		end
		local search = own(Facet.Controls.Picker(core, {
			id = "Tracks",
			label = "Track",
			selected = track,
			options = trackOptions,
			query = query,
			enabled = enabled,
		}))
		local multi = own(Facet.Controls.Menu(core, {
			id = "Tags",
			trigger = UI.Button({ id = "Trigger", label = "Scenery filters", enabled = enabled }),
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
		}))
		local combo = own(Facet.Controls.ComboBox(core, {
			id = "Vehicle",
			value = comboValue,
			text = comboText,
			options = { { id = "road", label = "Road" }, { id = "rally", label = "Rally" } },
			enabled = enabled,
			acceptCustom = function(text)
				return #text >= 3 and #text <= 24, "Use 3 to 24 characters."
			end,
		}))
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
		end
		local function heading(text)
			return UI.Text({ text = text, textSize = "heading", width = UI.fill() })
		end
		--[[ THE DEMO SAYS WHAT EACH CONTROL IS (user review 2026-09-12): a
			capture of this page could not be read without the source beside it.
			One caption above every control — the control and the style it was
			asked for — so a screenshot names its own subjects. ]]
		local function caption(id: string, text: string)
			return UI.Text({ id = id, text = text, textSize = "caption", role = "secondary", width = UI.fill() })
		end

		local body = UI.VStack({
			width = UI.fill(),
			gap = "m",
			children = {
				UI.Text({ text = "Choices and filters", textSize = "title", width = UI.fill() }),
				UI.Button({ id = "Reset", label = "Reset", onActivate = reset }),
				caption("CapSwitch", "Toggle · switch"),
				switch.blueprint,
				heading("Check and toggle"),
				caption("CapCheck", "Checkbox · mixed state"),
				checkbox.blueprint,
				caption("CapToggle", "Toggle · button presentation"),
				toggle.blueprint,
				heading("Choose a race group"),
				caption("CapRadio", "Picker · radioGroup"),
				radio.blueprint,
				caption("CapSegments", "Picker · segmented"),
				segmented.blueprint,
				caption("CapPopup", "Picker · automatic (menu on touch and pointer; rows on a television)"),
				popup.blueprint,
				UI.Button({
					id = "Join",
					label = "Toggle club membership",
					onActivate = function()
						club:set(not club:get())
					end,
				}),
				heading("Search 250 tracks"),
				caption("CapSearch", "Picker · navigationLink (searchable sheet)"),
				search.blueprint,
				heading("Filter by scenery"),
				caption("CapMenu", "Menu · checked items"),
				multi.blueprint,
				heading("Choose or name a vehicle class"),
				caption("CapCombo", "ComboBox · suggestions with custom text"),
				combo.blueprint,
			},
		})
		local screen = UI.Screen({
			id = "SelectionControls",
			surface = "base",
			padding = "m",
			gap = "s",
			children = {
				UI.ScrollView({ id = "Content", width = UI.fill(), height = UI.fill(), children = { body } }),
			},
		})
		return {
			screen = screen,
			states = function()
				return {
					{
						id = "search",
						kind = "popup",
						open = function()
							search.api.open()
							return true
						end,
					},
					{
						id = "no-results",
						kind = "popup",
						open = function()
							query:set("unlisted")
							search.api.open()
							return true
						end,
					},
					{
						id = "multiple",
						kind = "popup",
						open = function()
							multi.api.open()
							return true
						end,
					},
					{
						id = "race-group",
						kind = "popup",
						open = function()
							popup.api.open()
							return true
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
				replace_options = function()
					choices:set({
						{ id = "open", value = "open", label = "Public races" },
						{ id = "club", value = "club", label = "Member races", enabled = club },
					})
				end,
			},
			report = function()
				return {
					checkbox = checkbox.dump(),
					radio = radio.dump(),
					popup = popup.dump(),
					search = search.dump(),
					multiple = multi.dump(),
					combo = combo.dump(),
				}
			end,
			dispose = function()
				scope:dispose()
			end,
		}
	end,
}
