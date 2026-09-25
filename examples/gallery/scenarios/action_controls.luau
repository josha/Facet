--!strict
return {
	title = "Actions and menus",
	ledgerRows = { "CONTROL-ACTIONS" },
	build = function(ctx)
		local UI, Compose = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local sceneViewport = ctx.sceneViewport or ctx.viewport
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local function frame(properties)
			local index = 0
			for _, child in ipairs(properties) do
				if
					(typeof(child) == "Instance" or type(child) == "table")
					and type(child.IsA) == "function"
					and child:IsA("GuiObject")
				then
					index += 1
					ctx.runtime.decorate(child, { LayoutOrder = index })
				end
			end
			return Host.Frame(properties)
		end
		local function wide(use)
			return use(sceneViewport).width >= 1000
		end
		local function sectionWidth(use)
			return if wide(use) then UDim2.new(0.5, -12, 0, 0) else UDim2.new(1, 0, 0, 0)
		end
		local signal = Compose.cell
		local busy = signal(false)
		local enabled = signal(true)
		local count = signal(0)
		local status = signal("Ready to race.")
		local favorites = signal(false)
		local weather = signal("any")
		local scrollTarget = signal(nil)
		local scrollProgress = signal(0)
		local heroVisible = signal(true)
		local rowVolume = signal(60)
		local assist = signal(true)
		local confirming = signal(false)
		local tokens = signal({ "Rain", "No assists", "Friends" })
		local editingTags = signal(false)
		local chosenTags = signal({} :: { [string]: boolean })
		local mounted = false
		local seconds = 0
		local readRung = function(): string?
			return nil
		end
		local setRung = function(_rung: string) end
		local function VocabularySection()
			local rung = Compose.cell("compact")
			readRung = function()
				return rung:peek()
			end
			setRung = function(value)
				rung:set(value)
			end
			Compose.cleanup(function()
				readRung = function()
					return nil
				end
				setRung = function(_value) end
			end)
			local ladder, looks, chips = {}, {}, {}
			for _, step in { "xsmall", "compact", "regular", "large" } do
				table.insert(
					ladder,
					UI.Button({
						Name = "Rung" .. step:sub(1, 1):upper() .. step:sub(2),
						label = step,
						controlSize = step,
						appearance = if step == "large" then "emphasis" else "standard",
						enabled = enabled,
						onActivate = function()
							rung:set(step)
							status:set(step .. " size chosen.")
						end,
					})
				)
			end
			for _, word in { "standard", "emphasis", "soft", "utility", "link", "inverse" } do
				table.insert(
					looks,
					UI.Button({
						Name = "Look" .. word:sub(1, 1):upper() .. word:sub(2),
						label = word,
						appearance = word,
						underline = if word == "link" then "hover" else nil,
						controlSize = function(use)
							return use(rung)
						end,
						enabled = enabled,
						onActivate = function()
							status:set(word .. " emphasis chosen.")
						end,
					})
				)
			end
			for _, entry in { { "Dry", "compact" }, { "Wet", "regular" }, { "Snow", "large" } } do
				table.insert(
					chips,
					UI.Chip({
						Name = "Chip" .. entry[1],
						label = entry[1],
						selected = Compose.cell(entry[1] == "Dry"),
						controlSize = entry[2],
						appearance = if entry[1] == "Snow" then "utility" else "standard",
					})
				)
			end
			return frame({
				Name = "Vocabulary",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 16),
				}),
				UI.Text "CapVocabulary" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = function(use)
						return `The appearance row uses the {use(rung)} size. Compact plates keep full-size tap targets.`
					end,
					textRole = "caption",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				frame({
					Name = "SizeLadder",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
						Wraps = true,
					}),
					table.unpack(ladder),
				}),
				frame({
					Name = "Appearances",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
						Wraps = true,
					}),
					table.unpack(looks),
				}),
				frame({
					Name = "SizedChips",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
						Wraps = true,
					}),
					table.unpack(chips),
				}),
				UI.Button "IconLabelled" {
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					label = "Go",
					icon = "facet:search",
					controlSize = rung,
					enabled = enabled,
					onActivate = function()
						status:set("Race search opened.")
					end,
				},
				frame({
					Name = "IconForms",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
						Wraps = true,
					}),
					UI.Button "IconOnly" {
						icon = "close",
						name = "Dismiss the race card",
						corners = "pill",
						controlSize = rung,
						enabled = enabled,
						onActivate = function()
							status:set("Race card dismissed.")
						end,
					},
					UI.Button "SquareAction" {
						label = "Square",
						corners = "square",
						controlSize = rung,
						appearance = "utility",
						enabled = enabled,
						onActivate = function()
							status:set("Square action chosen.")
						end,
					},
				}),
				Host.ImageLabel "OverMedia" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 96),
					Image = "rbxthumb://type=AvatarHeadShot&id=1&w=420&h=420",
					ScaleType = Enum.ScaleType.Crop,
					UI.Button "OverMediaAction" {
						label = "Play this replay",
						controlSize = "large",
						enabled = enabled,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						onActivate = function()
							status:set("Replay opened.")
						end,
					},
				},
			})
		end

		local function openDialog()
			confirming:set(true)
		end
		local function reset()
			tokens:set({ "Rain", "No assists", "Friends" })
			editingTags:set(false)
			chosenTags:set({})
			setRung("compact")
			busy:set(false)
			enabled:set(true)
			count:set(0)
			favorites:set(false)
			weather:set("any")
			status:set("Ready to race.")
			confirming:set(false)
		end

		local function Example()
			mounted = true
			Compose.cleanup(function()
				mounted = false
			end)
			local rowToggle = UI.Toggle "Assist" {
				label = "Driving assistance",
				value = assist,
				row = { description = "Keep the car stable on rough terrain", icon = "settings" },
			}
			local rowSlider = UI.Slider "Music" {
				label = "Music volume",
				value = rowVolume,
				min = 0,
				max = 100,
				step = 5,
				row = { description = "Balance music against race sounds", icon = "settings" },
			}
			local rowAction = UI.Button "Equipment" {
				label = "Manage equipment",
				row = { description = "Choose a driver for the next race", value = "2 drivers", icon = "person" },
				onActivate = function()
					scrollTarget:set(nil)
					scrollTarget:set("Drivers")
				end,
			}
			local save = UI.Button "Save" {
				label = "Prepare race",
				busy = busy,
				enabled = enabled,
				onActivate = function()
					busy:set(true)
					seconds = 1.5
					status:set("Preparing your race…")
				end,
			}
			if ctx.runService then
				local connection = ctx.runService.Heartbeat:Connect(function(dt)
					if busy:peek() then
						seconds -= dt
						if seconds <= 0 then
							busy:set(false)
							status:set("Your race is ready.")
						end
					end
				end)
				Compose.cleanup(function()
					connection:Disconnect()
				end)
			end
			local repeatButton = UI.Button "Repeat" {
				label = "Add a lap · hold to repeat",
				enabled = enabled,
				repeatDelay = 0.4,
				repeatInterval = 0.1,
				onActivate = function()
					count:set(count:peek() + 1)
				end,
			}
			local shortcut = UI.Button "Shortcut" {
				label = "Restart count · F6",
				shortcut = { keyCode = "F6" },
				enabled = enabled,
				onActivate = function()
					count:set(0)
					status:set("Lap count restarted.")
				end,
			}
			local items = {
				{ id = "favorites", label = "Favorites only", checked = favorites },
				{ divider = true },
				{ id = "any", label = "Any weather", selected = weather, value = "any" },
				{ id = "dry", label = "Dry weather", selected = weather, value = "dry" },
				{
					id = "snow",
					label = "Snow",
					selected = weather,
					value = "snow",
					enabled = false,
					description = "Winter races are closed.",
				},
				{ divider = true },
				{
					id = "done",
					label = "Apply filters",
					onSelect = function()
						status:set("Filters applied.")
					end,
				},
			}
			local menu = UI.Menu "Filters" {
				label = "Race filters",
				items = items,
			}
			local split = UI.SplitButton "Split" {
				label = "Start race",
				enabled = enabled,
				onActivate = function()
					status:set("Race started.")
				end,
				items = {
					{
						id = "practice",
						label = "Practice",
						onSelect = function()
							status:set("Practice started.")
						end,
					},
					{
						id = "time",
						label = "Time trial",
						onSelect = function()
							status:set("Time trial started.")
						end,
					},
				},
			}
			local dialog = UI.Alert "RaceConfirmation" {
				isPresented = confirming,
				title = "Start this race?",
				message = "Your selected driver is ready.",
				actions = {
					{
						id = "Cancel",
						label = "Cancel",
						role = "cancel",
						onActivate = function()
							status:set("Race cancelled.")
						end,
					},
					{
						id = "Accept",
						label = "Start",
						role = "default",
						onActivate = function()
							status:set("Race confirmed.")
						end,
					},
				},
			}
			local function heading(text)
				return UI.Text({
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = text,
					textRole = "heading",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				})
			end

			local drivers: { [any]: any } = {}
			for i, name in { "Classic driver", "Trailblazer" } do
				local card = UI.Button({
					Name = "Driver" .. i,
					Size = UDim2.fromScale(1, 1),
					AutomaticSize = Enum.AutomaticSize.None,
					LayoutOrder = i,
					label = name,
					subtitle = "Choose for the next race",
					image = `rbxthumb://type=AvatarHeadShot&id={i}&w=420&h=420`,
					imageAspectRatio = 1,
					imageFraming = "crop",
					enabled = enabled,
					onActivate = function()
						status:set(name .. " selected.")
					end,
				})
				table.insert(drivers, card)
			end
			local driverGrid = frame({
				Name = "Drivers",
				Size = UDim2.new(1, 0, 0, 0),
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIGridLayout({
					CellSize = function(use)
						local columns = if use(sceneViewport).width < 650 then 1 else 2
						return UDim2.new(1 / columns, if columns == 1 then 0 else -8, 0, 240)
					end,
					CellPadding = UDim2.fromOffset(16, 16),
				}),
				table.unpack(drivers),
			})

			local previews: { [any]: any } = {}
			for _, mode in { "crop", "none" } do
				table.insert(
					previews,
					frame({
						Name = "Backdrop" .. mode,
						BackgroundTransparency = 1,
						Size = UDim2.fromScale(1, 1),
						AutomaticSize = Enum.AutomaticSize.None,
						Host.UIListLayout({
							FillDirection = Enum.FillDirection.Vertical,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 8),
						}),
						Host.UIPadding({
							PaddingTop = UDim.new(0, 16),
							PaddingBottom = UDim.new(0, 16),
							PaddingLeft = UDim.new(0, 16),
							PaddingRight = UDim.new(0, 16),
						}),
						Host.ImageLabel "Preview" {
							Image = "rbxthumb://type=AvatarHeadShot&id=1&w=420&h=420",
							ScaleType = if mode == "crop" then Enum.ScaleType.Crop else Enum.ScaleType.Fit,
							BackgroundTransparency = 1,
							Size = UDim2.new(1, 0, 0, 180),
						},
						UI.Text({
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							text = if mode == "crop"
								then "Focal crop · keeps the face in view"
								else "Natural pixels · crop as the view shrinks",
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
					})
				)
			end

			local hero = Host.ImageLabel "Hero" {
				Image = "rbxthumb://type=AvatarHeadShot&id=1&w=420&h=420",
				ImageColor3 = Color3.fromRGB(150, 156, 170),
				ScaleType = Enum.ScaleType.Crop,
				BackgroundColor3 = Color3.fromRGB(28, 31, 38),
				BackgroundTransparency = 0,
				ClipsDescendants = true,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UICorner({ CornerRadius = UDim.new(0, 12) }),
				Host.UISizeConstraint({ MinSize = Vector2.new(0, 240) }),
				Host.Frame "Scrim" {
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = Color3.new(0, 0, 0),
					BorderSizePixel = 0,
					Host.UIGradient({
						Transparency = ctx.types.NumberSequence.new({
							ctx.types.NumberSequenceKeypoint.new(0, 0.05),
							ctx.types.NumberSequenceKeypoint.new(0.55, 0.35),
							ctx.types.NumberSequenceKeypoint.new(1, 1),
						}),
					}),
				},
				Host.Frame "Copy" {
					Size = UDim2.fromScale(0.62, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 12),
					}),
					Host.UIPadding({
						PaddingLeft = UDim.new(0, 24),
						PaddingRight = UDim.new(0, 12),
						PaddingTop = UDim.new(0, 24),
						PaddingBottom = UDim.new(0, 24),
					}),
					UI.Text "HeroTitle" {
						LayoutOrder = 1,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = "Your next race starts here",
						textRole = "title",
						TextWrapped = true,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
					UI.Text "HeroBody" {
						LayoutOrder = 2,
						role = "secondary",
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = "Choose your driver. Tune your ride. Find your next challenge.",
						TextWrapped = true,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
					UI.Button "ChooseDriver" {
						LayoutOrder = 3,
						label = "Choose a driver",
						appearance = "emphasis",
						onActivate = function()
							scrollTarget:set(nil)
							scrollTarget:set("Drivers")
						end,
					},
				},
			}

			local showroom = frame({
				Name = "Showroom",
				BackgroundTransparency = 1,
				Size = sectionWidth,
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 16),
				}),
				hero,
				heading("Choose your driver"),
				driverGrid,
				heading("Image backgrounds"),
				frame({
					Name = "Backgrounds",
					Size = UDim2.new(1, 0, 0, 0),
					BackgroundTransparency = 1,
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIGridLayout({
						CellSize = function(use)
							local width = use(sceneViewport).width
							local columns = if width < 650 or (wide(use) and width < 1080) then 1 else 2
							return UDim2.new(1 / columns, if columns == 1 then 0 else -8, 0, 260)
						end,
						CellPadding = UDim2.fromOffset(16, 16),
					}),
					table.unpack(previews),
				}),
			})
			local raceSetup = frame({
				Name = "RaceSetup",
				BackgroundTransparency = 1,
				Size = sectionWidth,
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 16),
				}),
				frame({
					Name = "SettingsRows",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 16),
					}),
					rowAction,
					rowToggle,
					rowSlider,
				}),
				heading("Race tags"),
				UI.Button "EditTags" {
					label = function(use)
						return if use(editingTags) then "Done" else "Edit"
					end,
					appearance = "soft",
					controlSize = "compact",
					onActivate = function()
						editingTags:set(not editingTags:peek())
					end,
				},
				Host.ScrollingFrame "Tokens" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 44),
					AutomaticSize = Enum.AutomaticSize.None,
					AutomaticCanvasSize = Enum.AutomaticSize.X,
					CanvasSize = UDim2.new(),
					ScrollBarThickness = 6,
					frame({
						Name = "Row",
						BackgroundTransparency = 1,
						Size = UDim2.new(0, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.XY,
						Host.UIListLayout({
							FillDirection = Enum.FillDirection.Horizontal,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 8),
						}),
						Compose.OrderedCollection({
							from = tokens,
							key = function(item)
								return item
							end,
							render = function(current, placement, key)
								local item = current:peek()
								return UI.Chip "Token" {
									label = item,
									controlSize = "compact",
									selected = function(use)
										return use(chosenTags)[item] == true
									end,
									onToggle = function(value)
										local nextChosen = table.clone(chosenTags:peek())
										nextChosen[item] = value
										chosenTags:set(nextChosen)
									end,
									editing = editingTags,
									onRemove = function()
										local nextItems = {}
										for _, value in tokens:peek() do
											if value ~= item then
												table.insert(nextItems, value)
											end
										end
										tokens:set(nextItems)
									end,
								}
							end,
						}),
					}),
				},
				heading("Prepare a race"),
				save,
				UI.Text "Status" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = status,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				heading("Set the lap count"),
				repeatButton,
				UI.Text "Count" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = Compose.formula(function(use)
						return tostring(use(count)) .. " laps"
					end),
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				shortcut,
				heading("Filter the grid"),
				menu,
				UI.Text({
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = Compose.formula(function(use)
						return (if use(favorites) then "Favorites" else "All races")
							.. " · "
							.. use(weather)
							.. " weather"
					end),
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				heading("Start or choose a mode"),
				UI.Text "CapSplit" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Split button · one control: the action, and its menu (pointer: split; touch: long-press, with a chevron)",
					textRole = "caption",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				split,
				UI.Button "Confirm" {
					label = "Confirm race…",
					enabled = enabled,
					onActivate = openDialog,
				},
			})
			local body = frame({
				Name = "Sections",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = function(use)
						return if wide(use) then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
					end,
					VerticalAlignment = Enum.VerticalAlignment.Top,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 24),
				}),
				showroom,
				raceSetup,
			})
			local page = frame({
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 16),
				}),
				UI.Text({
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Actions and menus",
					textRole = "title",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				frame({
					Name = "Toolbar",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
						Wraps = true,
					}),
					UI.Button "Reset" {
						label = "Reset",
						onActivate = reset,
					},
					UI.Button "Enable" {
						label = "Toggle enabled",
						onActivate = function()
							enabled:set(not enabled:peek())
						end,
					},
				}),
				body,
				UI.Text({
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Size and emphasis",
					textRole = "heading",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				VocabularySection(),
			})
			local scroller = Host.ScrollingFrame "Content" {
				BorderSizePixel = 0,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.new(),
				ScrollBarThickness = 6,
				Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder }),
				page,
			}
			Compose.watch(function(use)
				local selected = use(scrollTarget)
				local node = selected and scroller:FindFirstChild(selected, true)
				if node then
					scroller.CanvasPosition = Vector2.new(
						0,
						node.AbsolutePosition.Y - scroller.AbsolutePosition.Y + scroller.CanvasPosition.Y
					)
				end
			end)
			local connection = scroller:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
				local span = math.max(1, scroller.AbsoluteCanvasSize.Y - scroller.AbsoluteWindowSize.Y)
				scrollProgress:set(math.clamp(scroller.CanvasPosition.Y / span, 0, 1))
			end)
			Compose.cleanup(function()
				connection:Disconnect()
			end)
			return frame({
				Name = "ActionControls",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				Host.UIPadding({
					PaddingTop = UDim.new(0, 16),
					PaddingBottom = UDim.new(0, 16),
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
				}),
				scroller,
				dialog,
			})
		end

		return {
			screen = Example,
			states = function()
				return {
					{
						id = "confirmation",
						kind = "dialog",
						open = function()
							openDialog()
							return true
						end,
					},
					{
						id = "busy",
						kind = "busy",
						open = function()
							busy:set(true)
							return true
						end,
					},
				}
			end,
			steps = {
				sizeCompact = function()
					setRung("compact")
				end,
				sizeRegular = function()
					setRung("regular")
				end,
				sizeLarge = function()
					setRung("large")
				end,
				showDrivers = function()
					scrollTarget:set(nil)
					scrollTarget:set("Drivers")
				end,
				showHero = function()
					scrollTarget:set(nil)
					scrollTarget:set("Hero")
				end,
				showSettings = function()
					scrollTarget:set(nil)
					scrollTarget:set("SettingsRows")
				end,
				reset = reset,
				disable = function()
					enabled:set(false)
				end,
				busy = function()
					busy:set(true)
					seconds = 1.5
				end,
			},
			report = function()
				if not mounted then
					return nil
				end
				return {
					tokenCount = #tokens:peek(),
					editingTags = editingTags:peek(),
					controlSize = readRung(),
					count = count:peek(),
					settings = { assistance = assist:peek(), music = rowVolume:peek() },
					scrollProgress = scrollProgress:peek(),
					heroVisible = heroVisible:peek(),
					busy = busy:peek(),
					status = status:peek(),
				}
			end,
			dispose = function() end,
		}
	end,
}
