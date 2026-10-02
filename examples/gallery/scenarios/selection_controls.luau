--!strict
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type ExampleContext = typeof(require("@repo/examples/types")(nil :: any))
return {
	title = "Choices and filters",
	ledgerRows = { "CONTROL-SELECTION" },
	build = function(ctx: ExampleContext)
		local UI, Compose: typeof(require("@repo/src/vendor/compose/core")) = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose: typeof(require("@repo/src/vendor/compose/core")) = ctx.Compose
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
		local driver = signal("d3")
		local driverError = signal("")
		local mode = signal("sprint")
		local laps = signal("5")
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
			return UI.Toggle "Switch" {
				label = "Enable choices",
				value = enabled,
			}
		end
		local function checkbox()
			return UI.Toggle "Checkbox" {
				label = "Include night races and their full race results",
				value = checked,
				mixed = mixed,
				presentation = "checkbox" :: "checkbox",
				enabled = enabled,
			}
		end
		local function plainCheckbox()
			return UI.Toggle "PlainCheckbox" {
				label = "Reduced motion",
				value = checked,
				presentation = "checkbox" :: "checkbox",
				appearance = "plain",
				controlSize = "compact" :: "compact",
				textSize = "label",
				enabled = enabled,
			}
		end
		local function toggle()
			return UI.Toggle "Boost" {
				label = "Boost mode",
				value = boost,
				presentation = "button" :: "button",
				enabled = enabled,
			}
		end

		local function radio()
			return UI.Picker "Radio" {
				selected = selected,
				options = choices,
				style = "radioGroup" :: "radioGroup",
				enabled = enabled,
			}
		end
		local function segmented()
			return UI.Picker "Segments" {
				selected = selected,
				options = {
					{ value = "open", label = "Open" } :: typeof(require("@repo/tools/typecheck/example_shapes").PickerOption_any(nil :: any)),
					{ value = "club", label = "Club", enabled = club } :: typeof(require("@repo/tools/typecheck/example_shapes").PickerOption_any(nil :: any)),
				},
				style = "segmented" :: "segmented",
				enabled = enabled,
			}
		end
		local function popup()
			return UI.Picker "Popup" {
				label = "Race group",
				selected = selected,
				options = {
					{ value = "open", label = "Open races" } :: typeof(require("@repo/tools/typecheck/example_shapes").PickerOption_any(nil :: any)),
					{ value = "club", label = "Club races", description = "Join a club to unlock.", enabled = club } :: typeof(require("@repo/tools/typecheck/example_shapes").PickerOption_any(nil :: any)),
				},
				enabled = enabled,
			}
		end
		local trackOptions = {}
		for _, item in tracks do
			table.insert(trackOptions, { value = item.id, label = item.label })
		end
		local function search()
			return UI.Picker "Tracks" {
				label = "Track",
				selected = track,
				options = trackOptions,
				query = query,
				enabled = enabled,
			}
		end
		local function multi()
			return UI.Menu {
				trigger = UI.Button "Tags" {
					label = "Scenery filters",
					enabled = enabled,
					onActivate = function() end,
				} :: GuiObject,
				items = {
					{ id = "coastal", label = "Coastal", checked = tagCoastal } :: typeof(require("@repo/tools/typecheck/example_shapes").MenuItem_any(nil :: any)),
					{ id = "forest", label = "Forest", checked = tagForest } :: typeof(require("@repo/tools/typecheck/example_shapes").MenuItem_any(nil :: any)),
					{
						id = "snow",
						label = "Snow",
						checked = tagSnow,
						enabled = false,
						description = "Winter routes are closed.",
					} :: typeof(require("@repo/tools/typecheck/example_shapes").MenuItem_any(nil :: any)),
				},
			}
		end
		local function combo()
			return UI.ComboBox "Vehicle" {
				value = comboValue,
				text = comboText,
				options = {
					{ id = "road", label = "Road" } :: typeof(require("@repo/tools/typecheck/example_shapes").PickerOption_string(nil :: any)),
					{ id = "rally", label = "Rally" } :: typeof(require("@repo/tools/typecheck/example_shapes").PickerOption_string(nil :: any)),
				},
				enabled = enabled,
				acceptCustom = function(text)
					return #text >= 3 and #text <= 24, "Use 3 to 24 characters."
				end,
			}
		end
		local vote = (function(
			value: "up" | "down" | "none"
		): typeof(require("@repo/tools/typecheck/example_shapes").voteCell(nil :: any))
			return signal(value)
		end)("none")
		local function votes()
			return Host.Frame "Votes" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 16),
				}) :: unknown,
				UI.Vote "TrackVote" {
					LayoutOrder = 1,
					value = vote,
					summary = function(use: Use)
						return if use(vote) == "up" then "You and 98% liked this" else "98% liked this"
					end,
					onChange = function(nextValue: "down" | "none" | "up")
						vote:set(nextValue)
					end,
				},
				UI.Vote "PastVote" {
					LayoutOrder = 2,
					value = "down" :: "down",
					readOnly = true,
					controlSize = "compact" :: "compact",
				},
				UI.Chip "VoteTag" { LayoutOrder = 3, label = "Rally", selected = signal(false) },
			}
		end
		local function reset()
			vote:set("none")
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
		local function driverField()
			return UI.Picker "Driver" {
				label = "Driver",
				requiredMark = "required" :: "required",
				hint = "Who takes the wheel for this race.",
				errorText = driverError,
				style = "menu" :: "menu",
				maxHeight = 220,
				selected = driver,
				options = DRIVERS,
				enabled = enabled,
			}
		end
		local function cards()
			return UI.Picker "Mode" {
				label = "Race mode",
				style = "cards" :: "cards",
				axis = "x" :: "x",
				required = false,
				selected = mode,
				options = {
					{ value = "sprint", label = "Sprint", description = "Three short laps", meta = "3 laps" } :: typeof(require("@repo/tools/typecheck/example_shapes").PickerOption_any(nil :: any)),
					{ value = "endurance", label = "Endurance", description = "A long race", meta = "20 laps" } :: typeof(require("@repo/tools/typecheck/example_shapes").PickerOption_any(nil :: any)),
					{
						value = "night",
						label = "Night",
						description = "Unlocks at level 10",
						meta = "Soon",
						enabled = false,
					} :: typeof(require("@repo/tools/typecheck/example_shapes").PickerOption_any(nil :: any)),
				},
				enabled = enabled,
			}
		end
		local function lapStrip()
			return UI.Picker "Laps" {
				style = "segmented" :: "segmented",
				appearance = "stroke",
				corners = "pill" :: "pill",
				controlSize = "compact" :: "compact",
				selected = laps,
				options = {
					{ value = "3", label = "3" } :: typeof(require("@repo/tools/typecheck/example_shapes").PickerOption_any(nil :: any)),
					{ value = "5", label = "5" } :: typeof(require("@repo/tools/typecheck/example_shapes").PickerOption_any(nil :: any)),
					{ value = "10", label = "10" } :: typeof(require("@repo/tools/typecheck/example_shapes").PickerOption_any(nil :: any)),
				},
				enabled = enabled,
			}
		end
		local function heading(text)
			return UI.Text({
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				text = text,
				textRole = "heading" :: "heading",
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end

		local function caption(id: string, text: string)
			return UI.Text({
				Name = id,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				text = text,
				textRole = "caption" :: "caption",
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end

		local function body()
			return Host.Frame "Body" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 16),
				}) :: unknown,
				UI.Text({

					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Choices and filters",
					textRole = "title" :: "title",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Button "Reset" { label = "Reset", onActivate = reset },
				caption("CapSwitch", "Toggle · switch"),
				switch(),
				heading("Check and toggle"),
				caption("CapCheck", "Checkbox · mixed state"),
				checkbox(),
				caption("CapPlain", "Checkbox · plain, compact"),
				plainCheckbox(),
				caption("CapToggle", "Toggle · button presentation"),
				toggle(),
				heading("Pick a driver and a race"),
				caption("CapDriver", "Picker · menu field (required, hint or error, avatars, sections, maxHeight)"),
				driverField(),
				caption("CapMode", "Picker · cards (choose again to clear)"),
				cards(),
				caption("CapLaps", "Picker · segmented, stroke, pill, compact"),
				lapStrip(),
				heading("Choose a race group"),
				caption("CapRadio", "Picker · radioGroup"),
				radio(),
				caption("CapSegments", "Picker · segmented"),
				segmented(),
				caption("CapPopup", "Picker · automatic (menu on touch and pointer; rows on a television)"),
				popup(),
				UI.Button "Join" {
					label = "Toggle club membership",
					onActivate = function()
						club:set(not club:peek())
					end,
				},
				heading("Search 250 tracks"),
				caption("CapSearch", "Picker · navigationLink (searchable sheet)"),
				search(),
				heading("Filter by scenery"),
				caption("CapMenu", "Menu · checked items"),
				multi(),
				heading("Choose or name a vehicle class"),
				caption("CapCombo", "ComboBox · suggestions with custom text"),
				combo(),
				heading("Vote on a track"),
				caption("CapVote", "Vote · up, down or none (press again to clear), and a read-only one"),
				votes(),
			}
		end
		local function screen()
			return Host.Frame "SelectionControls" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				UI.ScrollView "Content" {
					padding = 16,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					ScrollBarThickness = 6,
					body(),
				},
			}
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
				driverError = function()
					driverError:set(if driverError:peek() == "" then "Pick a driver to continue." else "")
					return { error = driverError:peek() }
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
					driver = driver:peek(),
					driverError = driverError:peek(),
					mode = mode:peek(),
					laps = laps:peek(),
					vote = vote:peek(),
				}
			end,

			dispose = function() end,
		}
	end,
}
