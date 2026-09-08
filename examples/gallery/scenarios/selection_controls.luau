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
		local tags = signal({ coastal = true })
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
		local radio = own(Facet.Controls.Picker(core, {
			id = "Radio",
			selected = selected,
			options = choices,
			presentation = "radio",
			axis = "y",
			enabled = enabled,
		}))
		local segmented = own(Facet.Controls.Picker(core, {
			id = "Segments",
			selected = selected,
			options = { { value = "open", label = "Open" }, { value = "club", label = "Club", enabled = club } },
			presentation = "segmented",
			enabled = enabled,
		}))
		local popup = own(Facet.Controls.PopupButton(core, {
			id = "Popup",
			value = selected,
			options = {
				{ id = "open", label = "Open races" },
				{ id = "club", label = "Club races", description = "Join a club to unlock.", enabled = club },
			},
			enabled = enabled,
		}))
		local search = own(
			Facet.Controls.PopupButton(
				core,
				{ id = "Tracks", value = track, options = tracks, query = query, enabled = enabled }
			)
		)
		local multi = own(Facet.Controls.PopupButton(core, {
			id = "Tags",
			selectedValues = tags,
			options = {
				{ id = "coastal", label = "Coastal" },
				{ id = "forest", label = "Forest" },
				{ id = "snow", label = "Snow", enabled = false, description = "Winter routes are closed." },
			},
			enabled = enabled,
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
			tags:set({ coastal = true })
			comboValue:set("road")
			comboText:set("Road")
		end
		local function heading(text)
			return UI.Text({ text = text, textSize = "heading", width = UI.fill() })
		end
		local function popupSlot(control)
			return UI.VStack({
				height = { type = "minMax", min = "controls.popup.triggerHeight" },
				width = UI.fill(),
				children = { control.blueprint },
			})
		end

		local body = UI.VStack({
			width = UI.fill(),
			gap = "m",
			children = {
				UI.Text({ text = "Choices and filters", textSize = "title", width = UI.fill() }),
				UI.Button({ id = "Reset", label = "Reset", onActivate = reset }),
				switch.blueprint,
				heading("Check and toggle"),
				checkbox.blueprint,
				toggle.blueprint,
				heading("Choose a race group"),
				radio.blueprint,
				segmented.blueprint,
				popupSlot(popup),
				UI.Button({
					id = "Join",
					label = "Toggle club membership",
					onActivate = function()
						club:set(not club:get())
					end,
				}),
				heading("Search 250 tracks"),
				popupSlot(search),
				heading("Filter by scenery"),
				popupSlot(multi),
				heading("Choose or name a vehicle class"),
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
