--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local Facet = require(ReplicatedStorage.Packages.Facet)
local C = Facet.Compose
local Art = require(script.Parent.Art)
local makeTheme = require(script.Parent.Themes)

local bakeryData = {
	{ name = "Blueberry", detail = "Jammy & bright" },
	{ name = "Apple", detail = "Soft & spiced" },
	{ name = "Chocolate", detail = "Dark & smooth" },
}
local droneData = {
	{ name = "Kite", detail = "Fast · 2 kg" },
	{ name = "Mule", detail = "Heavy · 8 kg" },
	{ name = "Wisp", detail = "Quiet · 1 kg" },
}

return function(example: string, weak: boolean, actionEnabled: Facet.ValueBoolean?)
	local bakery = example == "Bakery"
	local export = example == "Export"
	local art = if bakery then Art.Bakery else Art.Drone
	local theme = makeTheme(bakery, weak or export)
	if export then
		theme.style.defaultTheme = "Light"
	end
	local app = Facet.app({
		name = "FreshGuidanceExamples",
		theme = theme,
		suspendGameplay = true,
		screen = { DisplayOrder = 20 },
	})
	local UI, Host = app.UI, Facet.host(app.runtime)
	local oldTouchControls = GuiService.TouchControlsEnabled
	GuiService.TouchControlsEnabled = false
	local function dispose()
		app.dispose()
		GuiService.TouchControlsEnabled = oldTouchControls
	end
	app.mount(function()
		local open, chosen, result = C.cell(false), C.cell(1), C.cell("")
		if export then
			local actions: { Facet.DialogAction } = {
				{ id = "Cancel", label = "Cancel", role = "cancel", onActivate = function() end },
				{ id = "Export", label = "Export PDF", role = "default", enabled = actionEnabled, onActivate = function()
					result:set("Export requested")
				end },
			}
			return UI.Screen {
				surface = "surface", align = "center", distribute = "center", gap = 12,
				UI.Text { text = "Quarterly summary", textRole = "heading", TextXAlignment = Enum.TextXAlignment.Center },
				UI.Button "ExportOptions" {
					label = "Export document", enabled = actionEnabled,
					onActivate = function() open:set(true) end,
				},
				UI.Text "Feedback" {
					text = result, Size = UDim2.fromOffset(220, 24), AutomaticSize = Enum.AutomaticSize.None,
					TextXAlignment = Enum.TextXAlignment.Center,
				},
				UI.Dialog "ExportDialog" {
					title = "Export document", width = "narrow", isPresented = open,
					onPresentedChange = function(value) open:set(value) end,
					content = function()
						return UI.VStack { gap = 6, width = "fill",
							UI.Text { text = "Quarterly summary.pdf", textRole = "strong", wrap = true },
							UI.Text { text = "PDF · 12 pages", wrap = true },
						}
					end,
					actions = actions,
				},
			}
		end
		local env = UI.environment()
		local portrait = C.formula(function(use: Facet.Use)
			return use(env.viewportWidth) < 600
		end)
		local short = C.formula(function(use: Facet.Use)
			return use(env.viewportHeight) < 520
		end)
		local data = if bakery then bakeryData else droneData
		local kicker = if bakery then "FIRST LIGHT BAKERY" else "RELAY 03"
		local title = if bakery then "Morning bun" else "Relay Dispatch"
		local description = if bakery then "Choose a filling for the morning batch." else "Send one drone to the ridge relay."
		local action = if bakery then "Bake batch" else "Dispatch drone"
		local idle = if bakery then "Ready to bake" else "Ready for dispatch"
		local choiceName = C.formula(function(use: Facet.Use) return data[use(chosen)].name end)
		local status = C.formula(function(use: Facet.Use)
			local value = use(result)
			return if value == "" then idle .. " · " .. use(choiceName) else value
		end)
		local actions: { Facet.DialogAction } = {
			{ id = "Cancel", label = "Cancel", role = "cancel", onActivate = function() end },
			{
				id = "Commit", label = action, role = "default", enabled = actionEnabled,
				onActivate = function()
					local name = choiceName:peek()
					result:set(if bakery then "Last batch · " .. name else "Last dispatch · " .. name)
				end,
			},
		}
		local dialog = UI.Dialog "Confirm" {
			isPresented = open,
			onPresentedChange = function(value) open:set(value) end,
			title = if bakery then "Start this batch?" else "Confirm dispatch",
			content = function()
				return UI.Text {
					text = function(use: Facet.Use)
						local name = use(choiceName)
						return if bakery then name .. " filling · Morning bun" else name .. " → Ridge relay"
					end,
					wrap = true,
				}
			end,
			actions = actions,
		}

		local choiceRows: { GuiButton } = {}
		for i, record in data do
			local selected = C.formula(function(use: Facet.Use) return use(chosen) == i end)
			choiceRows[i] = UI.Button(record.name) {
				label = function(use: Facet.Use): string
					return if use(short) then record.name .. " · " .. record.detail else record.name
				end,
				subtitle = function(use: Facet.Use): string
					return if use(short) then "" else record.detail
				end,
				textSize = function(use: Facet.Use): number | Facet.TextRole
					return if weak then "body" elseif use(short) then 15 elseif use(portrait) then "strong" else "control"
				end,
				glyph = if bakery and not weak then function()
					return Host.ImageLabel {
						BackgroundTransparency = 1,
						Image = Art.Bakery.ingredients,
						ImageRectSize = Vector2.new(128, 128),
						ScaleType = Enum.ScaleType.Fit,
						ImageRectOffset = Vector2.new((i - 1) * 128, 0),
					}
				end else nil,
				trailingIcon = function(use: Facet.Use): string return if use(selected) then "checkmark" else "" end,
				selected = selected,
				LayoutOrder = i,
				SelectionOrder = i,
				TextXAlignment = Enum.TextXAlignment.Left,
				controlSize = function(use: Facet.Use): Facet.ControlSize return if use(short) then "compact" else "large" end,
				Size = function(use: Facet.Use)
					if weak then
						return UDim2.new(1, 0, 0, if use(short) then 44 else 63)
					elseif bakery then
						return UDim2.new(1, 0, 0, if use(short) then 44 elseif use(portrait) then 67 else 91)
					elseif use(portrait) then
						return UDim2.new(1, 0, 0, 70)
					end
					return UDim2.new(1 / 3, -6, 1, 0)
				end,
				AutomaticSize = Enum.AutomaticSize.None,
				onActivate = function() chosen:set(i) end,
			}
			if not bakery and not weak then
				choiceRows[i]:AddTag("drone-choice")
			end
		end

		local actionSize = function(use: Facet.Use)
			local height = if use(short) then 44 elseif use(portrait) or weak then 52 else if bakery then 66 else 58
			return if bakery or weak or use(portrait) then UDim2.new(1, 0, 0, height) else UDim2.fromOffset(230, height)
		end
		local function present()
			open:set(true)
		end
		local commit: GuiButton
		if weak then
			commit = UI.Button "Primary" {
				label = action, appearance = "emphasis", Size = actionSize,
				SelectionOrder = 4, AutomaticSize = Enum.AutomaticSize.None, enabled = actionEnabled, onActivate = present,
			}
		else
			commit = UI.Button "Primary" {
				label = "", name = action, appearance = "utility", Size = actionSize,
				BackgroundTransparency = 1,
				SelectionOrder = 4, AutomaticSize = Enum.AutomaticSize.None, enabled = actionEnabled, onActivate = present,
				Host.ImageLabel "ActionArt" {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Image = art.action,
					ScaleType = Enum.ScaleType.Slice,
					SliceCenter = if bakery then Rect.new(36, 26, 732, 130) else Rect.new(56, 43, 712, 113),
					SliceScale = if bakery then 0.48 else 0.40,
					Host.TextLabel "ActionLabel" {
						Text = action, Size = UDim2.new(1, -40, 1, 0),
						AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
						BackgroundTransparency = 1,
						TextColor3 = if bakery then Color3.fromRGB(255, 245, 222) else Color3.fromRGB(26, 22, 12),
						FontFace = Font.new(if bakery then "rbxasset://fonts/families/Guru.json" else "rbxasset://fonts/families/RobotoCondensed.json", Enum.FontWeight.Bold),
						TextSize = function(use: Facet.Use) return if use(short) then 20 elseif use(portrait) then 23 else if bakery then 34 else 29 end,
						TextTruncate = Enum.TextTruncate.AtEnd,
					},
				},
			}
			commit:AddTag("example-action")
		end

		local function list(direction: Enum.FillDirection, spacing: number)
			return Host.UIListLayout { FillDirection = direction, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, spacing) }
		end
		local V, H = Enum.FillDirection.Vertical, Enum.FillDirection.Horizontal
		local function header(onArt: boolean)
			local light = Color3.fromRGB(239, 246, 250)
			return UI.VStack "TitleBlock" {
				width = "fill", gap = 2, LayoutOrder = 1,
				UI.Text {
					text = kicker, textRole = "label",
					TextSize = function(use: Facet.Use)
						return if weak or use(short) or use(portrait) then 14 elseif bakery then 17 else 16
					end,
					FontFace = if weak then nil else Font.new(
						if bakery then "rbxasset://fonts/families/Guru.json" else "rbxasset://fonts/families/RobotoMono.json",
						Enum.FontWeight.Bold
					),
					TextColor3 = if weak then nil else if bakery then Color3.fromRGB(131, 27, 58) else Color3.fromRGB(255, 177, 67),
				},
				UI.Text {
					text = title, textRole = "title",
					TextSize = function(use: Facet.Use)
						return if weak then 26 elseif use(short) then 28 elseif use(portrait) then 40 else if bakery then 74 else 54
					end,
					TextColor3 = if onArt then light else nil,
				},
				UI.Text {
					text = description, textRole = "body", wrap = true, TextColor3 = if onArt then light else nil,
					TextSize = function(use: Facet.Use)
						return if weak or use(short) or use(portrait) then 16 elseif bakery then 20 else 18
					end,
				},
			}
		end
		local function subject(size: UDim2 | ((Facet.Use) -> UDim2), position: UDim2, source: (string | ((Facet.Use) -> string))?)
			return Host.ImageLabel "Subject" {
				Size = size, Position = position,
				BackgroundColor3 = if bakery then Color3.fromRGB(143, 87, 59) else Color3.fromRGB(16, 24, 30),
				BorderSizePixel = 0,
				Image = source or art.hero, ScaleType = Enum.ScaleType.Crop,
			}
		end
		local function feedback(size: UDim2 | ((Facet.Use) -> UDim2), position: UDim2, order: number)
			return UI.Text "Feedback" {
				text = status, textRole = "label", Size = size, Position = position, LayoutOrder = order,
				AutomaticSize = Enum.AutomaticSize.None, truncate = "end",
			}
		end

		local body: GuiObject
		if weak then
			commit.LayoutOrder = 7
			body = Host.ScrollingFrame "WeakTranslation" {
				Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
				AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.fromOffset(0, 0),
				ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 4,
				Host.UISizeConstraint { MaxSize = Vector2.new(440, 510) },
				list(V, 7), header(false),
				Host.Frame {
					LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 58), BackgroundTransparency = 1,
					subject(UDim2.fromOffset(94, 58), UDim2.fromOffset(0, 0)),
					UI.Text {
						text = if bakery then "Blueberry · Bakery sample" else "Kite · Bay reference",
						TextSize = 14, Size = UDim2.new(1, -107, 1, 0), Position = UDim2.fromOffset(107, 0),
						AutomaticSize = Enum.AutomaticSize.None,
					},
				},
				Host.Frame {
					LayoutOrder = 3, Size = function(use: Facet.Use)
						return UDim2.new(1, 0, 0, if use(short) then 142 else 199)
					end,
					BackgroundTransparency = 1, list(V, 5), table.unpack(choiceRows),
				},
				commit, feedback(UDim2.new(1, 0, 0, 24), UDim2.fromOffset(0, 0), 8),
			}
		elseif bakery then
			commit.LayoutOrder = 3
			body = Host.Frame "RecipeSheet" {
				Size = UDim2.fromScale(1, 1), BorderSizePixel = 0,
				BackgroundColor3 = Color3.fromRGB(91, 36, 40),
				Host.UISizeConstraint { MaxSize = Vector2.new(1210, 674) },
				subject(function(use: Facet.Use)
					return if use(portrait) then UDim2.new(1, 0, 0.32, 0) else UDim2.new(0.51, 0, 1, 0)
				end, UDim2.fromOffset(0, 0)),
				Host.TextLabel "BakerySample" {
					Size = UDim2.fromOffset(182, 22),
					Position = function(use: Facet.Use)
						return if use(portrait) then UDim2.new(0, 12, 0.32, -31) else UDim2.new(0, 12, 1, -34)
					end,
					Text = "Blueberry · Bakery sample", TextSize = 14, Font = Enum.Font.Garamond,
					TextColor3 = Color3.fromRGB(255, 243, 210), BackgroundColor3 = Color3.fromRGB(91, 36, 40),
					BorderSizePixel = 0,
				},
				Host.ImageLabel "RecipeNotes" {
					Image = Art.Bakery.paper, ScaleType = Enum.ScaleType.Stretch,
					Size = function(use: Facet.Use)
						return if use(portrait) then UDim2.new(1, 0, 0.68, 0) else UDim2.new(0.49, 0, 1, 0)
					end,
					Position = function(use: Facet.Use)
						return if use(portrait) then UDim2.fromScale(0, 0.32) else UDim2.fromScale(0.51, 0)
					end,
					BackgroundTransparency = 1,
					Host.UIPadding {
						PaddingTop = function(use: Facet.Use) return UDim.new(0, if use(short) or use(portrait) then 15 else 16) end,
						PaddingBottom = UDim.new(0, 4),
						PaddingLeft = function(use: Facet.Use) return UDim.new(0, if use(short) or use(portrait) then 14 else 30) end,
						PaddingRight = function(use: Facet.Use) return UDim.new(0, if use(short) or use(portrait) then 14 else 30) end,
					},
					Host.UIListLayout {
						SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = function(use: Facet.Use) return UDim.new(0, if use(short) then 3 elseif use(portrait) then 6 else 12) end,
					},
					header(false),
					Host.Frame "Fillings" {
						LayoutOrder = 2, BackgroundTransparency = 1,
						Size = function(use: Facet.Use) return UDim2.new(1, 0, 0, if use(short) then 144 elseif use(portrait) then 213 else 285) end,
						list(V, 6), table.unpack(choiceRows),
					},
					commit, feedback(function(use: Facet.Use)
						return UDim2.new(1, 0, 0, if use(short) then 16 else 20)
					end, UDim2.fromOffset(0, 0), 4),
				},
			}
		else
			local function railHeight(use: Facet.Use) return if use(portrait) then 86 elseif use(short) then 50 else 65 end
			local function fleetHeight(use: Facet.Use)
				return if use(portrait) then 222 elseif use(short) then 53 else 80
			end
			local function belowBay(use: Facet.Use)
				return fleetHeight(use) + railHeight(use) + 21
			end
			body = Host.Frame "DispatchBay" {
				Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(18, 26, 34),
				Host.UISizeConstraint { MaxSize = Vector2.new(1160, 690) },
				subject(function(use: Facet.Use)
					return UDim2.new(1, 0, 1, -belowBay(use))
				end, UDim2.fromOffset(0, 0), function(use: Facet.Use)
					return if use(portrait) then Art.Drone.portrait else art.hero
				end),
				Host.Frame "LegendShade" {
					Size = function(use: Facet.Use)
						return UDim2.new(if use(portrait) then 1 else 0.52, 0, 0, 104)
					end,
					Visible = function(use: Facet.Use) return use(short) or use(portrait) end,
					BackgroundColor3 = Color3.fromRGB(11, 19, 25), BorderSizePixel = 0,
					Host.UIGradient {
						Rotation = function(use: Facet.Use) return if use(portrait) then 90 else 0 end,
						Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 0.08),
							NumberSequenceKeypoint.new(0.62, 0.16),
							NumberSequenceKeypoint.new(1, 1),
						}),
					},
				},
				Host.Frame "BayLegend" {
					Position = UDim2.fromOffset(18, 14),
					Size = UDim2.new(1, -36, 0, 0),
					BackgroundTransparency = 1,
					header(true),
				},
				Host.TextLabel "BayReference" {
					Size = UDim2.fromOffset(164, 24),
					Position = function(use: Facet.Use) return UDim2.new(0, 12, 1, -belowBay(use) - 35) end,
					Text = "Kite · Bay reference", TextSize = 14, Font = Enum.Font.RobotoMono,
					TextColor3 = Color3.fromRGB(249, 180, 88), BackgroundColor3 = Color3.fromRGB(16, 25, 32),
					BorderSizePixel = 0,
				},
				Host.Frame "Fleet" {
					Size = function(use: Facet.Use) return UDim2.new(1, -28, 0, fleetHeight(use)) end,
					Position = function(use: Facet.Use) return UDim2.new(0, 14, 1, -belowBay(use) + 9) end,
					BackgroundTransparency = 1,
					Host.UIListLayout {
						SortOrder = Enum.SortOrder.LayoutOrder,
						FillDirection = function(use: Facet.Use) return if use(portrait) then V else H end,
						Padding = function(use: Facet.Use) return UDim.new(0, if use(portrait) then 6 else 9) end,
					},
					table.unpack(choiceRows),
				},
				Host.Frame "CommandRail" {
					Size = function(use: Facet.Use) return UDim2.new(1, -28, 0, railHeight(use)) end,
					Position = function(use: Facet.Use) return UDim2.new(0, 14, 1, -railHeight(use) - 4) end,
					BackgroundTransparency = 1,
					Host.UIListLayout {
						FillDirection = function(use: Facet.Use) return if use(portrait) then V else H end,
						Padding = UDim.new(0, 4), VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					feedback(function(use: Facet.Use)
						return if use(portrait) then UDim2.new(1, 0, 0, 24) else UDim2.new(1, -234, 0, 36)
					end, UDim2.fromOffset(0, 0), 0),
					commit,
				},
			}
			commit.LayoutOrder = 1
		end
		return UI.Screen {
			padding = 12, surface = "surface", align = "center", distribute = "center",
			BackgroundColor3 = if bakery and not weak then Color3.fromRGB(74, 31, 33) else nil,
			body, dialog,
		}
	end)
	return dispose
end
