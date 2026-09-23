--!strict
return {
	title = "Choices and filters",
	ledgerRows = { "CONTROL-SELECTION" },
	build = function(ctx)
		local UI, Compose = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local signal = Compose.cell
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
		local function switch()
			return UI.Toggle({
				Name = "Switch",
				label = "Enable choices",
				value = enabled,
			})
		end
		local function checkbox()
			return UI.Toggle({
				Name = "Checkbox",
				label = "Include night races and their full race results",
				value = checked,
				mixed = mixed,
				presentation = "checkbox",
				enabled = enabled,
			})
		end
		local function toggle()
			return UI.Toggle({
				Name = "Boost",
				label = "Boost mode",
				value = boost,
				presentation = "button",
				enabled = enabled,
			})
		end

		local function radio()
			return UI.Picker({
				Name = "Radio",
				selected = selected,
				options = choices,
				style = "radioGroup",
				enabled = enabled,
			})
		end
		local function segmented()
			return UI.Picker({
				Name = "Segments",
				selected = selected,
				options = { { value = "open", label = "Open" }, { value = "club", label = "Club", enabled = club } },
				style = "segmented",
				enabled = enabled,
			})
		end
		local function popup()
			return UI.Picker({
				Name = "Popup",
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
			return UI.Picker({
				Name = "Tracks",
				label = "Track",
				selected = track,
				options = trackOptions,
				query = query,
				enabled = enabled,
			})
		end
		local function multi()
			return UI.Menu({
				Name = "Tags",
				trigger = UI.Button({
					Name = "Trigger",
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
		local function combo()
			return UI.ComboBox({
				Name = "Vehicle",
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
		end
		local function heading(text)
			return UI.Label({
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Text = text,
				TextSize = 22,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end

		local function caption(id: string, text: string)
			return UI.Label({
				Name = id,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Text = text,
				TextSize = 12,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end

		local function body()
			return Host.Frame({
				Name = "Body",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 16),
				}),
				UI.Label({

					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = "Choices and filters",
					TextSize = 28,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Button({ Name = "Reset", label = "Reset", onActivate = reset }),
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
				UI.Button({

					Name = "Join",
					label = "Toggle club membership",
					onActivate = function()
						club:set(not club:peek())
					end,
				}),
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
			return Host.Frame({
				Name = "SelectionControls",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				Host.UIPadding({
					PaddingTop = UDim.new(0, 16),
					PaddingBottom = UDim.new(0, 16),
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
				}),
				Host.ScrollingFrame({
					Name = "Content",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					CanvasSize = UDim2.new(),
					ScrollBarThickness = 6,
					body(),
				}),
			})
		end
		return {
			screen = screen,
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
					checked = checked:peek(),
					mixed = mixed:peek(),
					selection = selected:peek(),
					track = track:peek(),
					query = query:peek(),
					tags = { coastal = tagCoastal:peek(), forest = tagForest:peek(), snow = tagSnow:peek() },
					vehicle = comboValue:peek(),
				}
			end,

			dispose = function() end,
		}
	end,
}
