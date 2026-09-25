--!strict
local screens = { CANVAS = { w = 920, h = 640 }, SHORT_HEIGHT = 500 }

function screens.create(Facet: any, runtime: any, actions: any)
	local Compose, Host, civil = Facet.Compose, runtime.constructors, Facet.civilDate
	local model = actions.model
	local types = actions.types or getfenv(0)
	local D, D2, V2, C3, CF, E = types.UDim, types.UDim2, types.Vector2, types.Color3, types.CFrame, types.Enum
	local UI = Facet.controls(runtime, {
		types = types,
		services = actions.services,
		theme = actions.theme,
		reducedMotion = actions.reducedMotion,
		pressHaptic = actions.pressHaptic,
	})
	local services = actions.services
	local environmentGame = getfenv(0).game
	local inputService = (services and services.UserInputService)
		or (environmentGame and environmentGame:GetService("UserInputService"))
	local touchEnabled = Compose.cell(inputService ~= nil and inputService.TouchEnabled == true)
	if inputService then
		Compose.cleanup(runtime.host.observation.observeProperty(inputService, "TouchEnabled", function()
			touchEnabled:set(inputService.TouchEnabled == true)
		end))
	end
	local clock = actions.clock or civil.systemClock()
	local dropTarget
	local selectedCard = Compose.cell(nil)
	local function rounded(radius)
		return Host.UICorner({ CornerRadius = D.new(0, radius or 12) })
	end
	local function merged(spec, props)
		for key, value in props or {} do
			if type(key) == "number" then
				table.insert(spec, value)
			else
				spec[key] = value
			end
		end
		return spec
	end
	local function words(name, value, role, props)
		return UI.Text(merged({
			Name = name,
			text = value,
			textRole = role or "body",
			TextWrapped = true,
			TextYAlignment = E.TextYAlignment.Top,
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
		}, props))
	end
	local function quiet(name, value, role, props)
		local spec = merged({ role = "secondary" }, props)
		return words(name, value, role or "caption", spec)
	end
	local function button(name, label, activate, props)
		return UI.Button(
			merged({ Name = name, label = label, onActivate = activate, Size = D2.fromOffset(0, 36) }, props)
		)
	end
	local function measure(node, value)
		local observation = runtime.host.observation
		Compose.cleanup(observation.observeProperty(node, "AbsoluteSize", function()
			local size = observation.readProperty(node, "AbsoluteSize")
			if size.X > 0 and size.Y > 0 then
				value:set(size)
			end
		end))
		return node
	end
	local function observeSize(node)
		local value = Compose.cell(V2.new(screens.CANVAS.w, screens.CANVAS.h))
		measure(node, value)
		return value
	end
	local function collection(kind, spec, source)
		if source:peek() ~= nil then
			spec.CanvasPosition = function(use)
				use(model.mode)
				return V2.new(0, source:peek())
			end
		end
		local node = UI[kind](spec)
		local observation = runtime.host.observation
		Compose.cleanup(observation.observeProperty(node, "CanvasPosition", function()
			if
				actions.spatial == nil
				or (actions.spatial and model.mode:peek() == "Spatial")
				or (not actions.spatial and model.mode:peek() == "Screen")
			then
				source:set(observation.readProperty(node, "CanvasPosition").Y)
			end
		end))
		return node
	end
	local function stage(name, contentBuilder, props)
		local spec = merged({
			Name = name,
			Size = D2.fromScale(1, 1),
			BorderSizePixel = 0,
			camera = CF.lookAt(types.Vector3.new(-10, 8, -13), types.Vector3.new(0, 1, 0)),
			fieldOfView = 43,
			Ambient = C3.fromRGB(166, 173, 191),
			LightColor = C3.fromRGB(255, 235, 204),
			LightDirection = types.Vector3.new(-1, -1, -0.5),
			content = contentBuilder,
			rounded(),
		}, props)
		return Compose.boundary(function()
			return UI.Stage(spec)
		end, function()
			return UI.Text({
				Name = name .. "Unavailable",
				text = "Preview unavailable",
				textRole = "label",
				role = "secondary",
				Size = spec.Size,
				Position = spec.Position,
				AutomaticSize = E.AutomaticSize.None,
			})
		end)
	end
	local function panelShadow()
		return Facet.themes.skin(runtime, actions.theme, "monitorPanel", { types = types })
	end
	local function toastFor(app)
		local source = model.toasts[app]
		return Compose.keyed({
			from = function(use)
				local toast = use(source)
				return if toast then { toast } else {}
			end,
			key = function(toast)
				return toast.serial
			end,
			render = function(current)
				local toast = current:peek()
				local presented = Compose.formula(function(use)
					local live = use(source)
					return live ~= nil and live.serial == toast.serial
				end)
				return UI.Snackbar(app .. "Toast")({
					isPresented = presented,
					onPresentedChange = function(value)
						if not value then
							model.dismissToast(app, toast.serial)
						end
					end,
					message = toast.message,
					duration = 5,
					action = if toast.undo
						then {
							label = "Undo",
							onActivate = function()
								toast.undo()
								model.dismissToast(app, toast.serial)
							end,
						}
						else nil,
				})
			end,
		})
	end
	local function shell(name, build, collapsed)
		local about = Compose.cell(false)
		local statusOpen = Compose.cell(false)
		local presentationKey = name .. (if actions.spatial then ":Spatial" else ":Screen")
		local presentation = { about = about, status = statusOpen }
		model.presentations[presentationKey] = presentation
		Compose.cleanup(function()
			if model.presentations[presentationKey] == presentation then
				model.presentations[presentationKey] = nil
			end
		end)
		local region = Compose.cell(V2.new(screens.CANVAS.w, screens.CANVAS.h))
		local function wide(use)
			return use(region).X >= 860
		end
		local function switchAppearance()
			model.dark:update(function(value)
				return not value
			end)
		end
		local chrome = { Name = "Chrome", gap = "s", align = "center", Visible = wide }
		if actions.spatial then
			table.insert(
				chrome,
				button("Focus", function(use)
					return if use(model.focused) == name then "All monitors" else "Focus"
				end, function()
					model.focus(name)
				end)
			)
		end
		table.insert(
			chrome,
			button("Presentation", function(use)
				return if use(model.mode) == "Spatial" then "Screen mode" else "Spatial mode"
			end, model.toggleMode)
		)
		table.insert(
			chrome,
			button("Appearance", function(use)
				return if use(model.dark) then "Light mode" else "Dark mode"
			end, switchAppearance)
		)
		table.insert(
			chrome,
			button("About", "About", function()
				about:set(true)
			end)
		)
		local player = actions.player
		local displayName = if player then player.DisplayName else "You"
		local profile = UI.Avatar "Profile" {
			name = displayName,
			userId = if player and player.UserId > 0 then player.UserId else nil,
			presence = model.presence,
			diameter = 36,
			onActivate = function()
				statusOpen:set(true)
			end,
		}
		local presenceWords = { online = "Online", away = "Away", busy = "Busy" }
		local root = UI.ZStack(name)({
			width = "fill",
			height = "fill",
			BackgroundTransparency = 0,
			SelectionGroup = true,
			ClipsDescendants = true,
			UI.Screen "Page" {
				gap = "s",
				padding = { top = "s", right = "m", bottom = "m", left = "m" },
				UI.NavBar "Header" {
					title = if name == "Chat" then "Assistant" else name,
					titleSize = "heading",
					Visible = function(use)
						return not (collapsed and use(collapsed))
					end,
					trailing = UI.HStack "HeaderActions" {
						gap = "s",
						align = "center",
						UI.HStack(chrome),
						UI.Menu "ActionsMenu" {
							trigger = UI.Button "MenuButton" {
								icon = "more",
								name = "Menu",
								shape = "circle",
								appearance = "utility",
							},
							Visible = function(use)
								return not wide(use)
							end,
							items = {
								{ id = "Presentation", label = "Switch presentation", onSelect = model.toggleMode },
								{ id = "Appearance", label = "Switch appearance", onSelect = switchAppearance },
								{
									id = "About",
									label = "About",
									onSelect = function()
										about:set(true)
									end,
								},
								if actions.spatial
									then {
										id = "Focus",
										label = function(use)
											return if use(model.focused) == name then "All monitors" else "Focus"
										end,
										onSelect = function()
											model.focus(name)
										end,
									}
									else nil,
							},
						},
						profile,
					},
				},
				Host.Frame "Content" {
					BackgroundTransparency = 1,
					Size = D2.fromScale(1, 0),
					Interactable = function(use)
						return not actions.spatial or use(model.focused) == name
					end,
					UI.fill(),
					UI.ErrorBoundary "AppBoundary" {
						width = "fill",
						height = "fill",
						view = function()
							local body, extra = build(region)
							return UI.ZStack "AppContent" { width = "fill", height = "fill", body, extra }
						end,
						fallback = function(_, retry)
							return UI.VStack "AppFailure" {
								width = "fill",
								gap = "s",
								padding = "l",
								words(
									"FailureTitle",
									`{if name == "Chat" then "Assistant" else name} stopped`,
									"heading"
								),
								quiet(
									"FailureMessage",
									"Something in this app failed. Your saved games, notes and messages are safe.",
									"label"
								),
								button("Retry", "Try again", retry),
							}
						end,
					},
				},
			},
			button("WakeMonitor", "", function()
				model.focus(name)
			end, {
				Size = D2.fromScale(1, 1),
				BackgroundTransparency = 1,
				TextTransparency = 1,
				ZIndex = 100,
				AutomaticSize = E.AutomaticSize.None,
				Visible = function(use)
					return actions.spatial == true and use(model.focused) ~= name
				end,
			}),
			UI.Popover "StatusPopover" {
				title = "Status",
				source = { node = profile },
				isPresented = statusOpen,
				onPresentedChange = function(value)
					statusOpen:set(value)
				end,
				edge = "bottom",
				align = "end",
				maxWidth = 280,
				content = function()
					return UI.VStack "PresenceCard" {
						width = "fill",
						gap = "s",
						UI.HStack "Identity" {
							gap = "s",
							align = "center",
							UI.StatusIndicator "PresenceDot" {
								status = function(use)
									local presence = use(model.presence)
									return if presence == "online"
										then "success"
										elseif presence == "away" then "warning"
										else "error"
								end,
								name = function(use)
									return presenceWords[use(model.presence)]
								end,
							},
							UI.Text "DisplayName" { text = displayName, textRole = "strong" },
						},
						UI.Picker "Presence" {
							selected = model.presence,
							onChange = function()
								statusOpen:set(false)
							end,
							style = "radioGroup",
							options = {
								{ value = "online", label = "Online" },
								{ value = "away", label = "Away" },
								{ value = "busy", label = "Busy" },
							},
						},
					}
				end,
			},
			UI.Dialog "AboutDialog" {
				isPresented = about,
				onPresentedChange = function(value)
					about:set(value)
				end,
				title = "About Virtual Monitors",
				content = function()
					return UI.VStack "AboutCopy" {
						width = "fill",
						gap = "s",
						stage("AboutScene", actions.discoveryContent, { Size = D2.new(1, 0, 0, 150) }),
						words(
							"AboutMessage",
							"Three complete apps, shared between a spatial desktop and a flat screen. Compose owns every scene and lifetime; Facet supplies controls; Roblox supplies layout and rendering."
						),
						quiet(
							"AboutVersion",
							`Facet {Facet.VERSION} · Compose {string.sub(Facet.COMPOSE_COMMIT, 1, 7)}`,
							"caption"
						),
					}
				end,
				actions = {
					{
						id = "done",
						label = "Done",
						role = "cancel",
						onActivate = function()
							about:set(false)
						end,
					},
				},
			},
		})
		root:AddTag("facet-surface")
		measure(root, region)
		return root
	end
	local function saveAction(current)
		return {
			label = function(use)
				return if use(model.saved)[use(current).id] then "Saved" else "Save"
			end,
			icon = function(use)
				return if use(model.saved)[use(current).id] then "checkmark" else "increment"
			end,
			onActivate = function()
				model.save(current:peek())
			end,
		}
	end
	local function gameMenu(current)
		return {
			items = {
				{
					id = "Share",
					label = "Share",
					onSelect = function()
						model.notify("Discover", `Link to {current:peek().title} copied`)
					end,
				},
				{
					id = "Hide",
					label = "Not interested",
					onSelect = function()
						model.hide(current:peek())
					end,
				},
				{ divider = true },
				{
					id = "Report",
					label = "Report",
					role = "destructive",
					onSelect = function()
						model.notify("Discover", `Thanks. We will review {current:peek().title}.`)
					end,
				},
			},
		}
	end
	local function gameCard(current)
		local item = current:peek()
		local card, preview
		local suppressPointerActivation = false
		local dragOrigin, pointerStateConnection
		local dragged = false
		local function openCard()
			selectedCard:set(card)
			model.selectGame(current:peek())
		end
		local function cancelPointer()
			dragOrigin, dragged = nil, false
			suppressPointerActivation = true
			if pointerStateConnection then
				pointerStateConnection:Disconnect()
				pointerStateConnection = nil
			end
		end
		Compose.cleanup(cancelPointer)
		local drag = Host.UIDragDetector "SaveDrag" {
			ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
			Enabled = function(use)
				return not use(touchEnabled)
			end,
		}
		card = UI.Card("Game_" .. item.id)({
			title = function(use)
				return use(current).title
			end,
			caption = function(use)
				local game = use(current)
				return game.rating .. "  ·  " .. game.players
			end,
			artwork = function()
				local decorated = runtime.timeline({ duration = (1 + item.index % 3) / 60 }).completed
				preview = UI.ZStack "Preview" {
					width = "fill",
					height = "fill",
					ClipsDescendants = true,
					rounded(),
					stage("Scene", if actions.gameContent then actions.gameContent(current) else nil, {
						Active = false,
						lazy = true,
					}),
					Compose.show(decorated, function()
						return UI.StatusIndicator "LiveDot" {
							status = "success",
							name = "Live now",
							AnchorPoint = V2.new(0, 0),
							Position = D2.fromOffset(10, 10),
						}
					end),
					Compose.show(function(use)
						return use(decorated) and #use(current).friends > 0
					end, function()
						return UI.AvatarGroup "Friends" {
							items = function(use)
								return use(current).friends
							end,
							max = 3,
							layout = "stacked",
							diameter = 28,
							Position = D2.new(1, -10, 1, -10),
							AnchorPoint = V2.new(1, 1),
						}
					end),
					drag,
				}
				return preview
			end,
			onActivate = function(input)
				if
					suppressPointerActivation
					and input
					and (
						input.UserInputType == E.UserInputType.Touch
						or input.UserInputType == E.UserInputType.MouseButton1
					)
				then
					return
				end
				openCard()
			end,
			primaryAction = saveAction(current),
			menu = gameMenu(current),
		})
		local function saveAt(position)
			if not dropTarget then
				return
			end
			local at, size = dropTarget.AbsolutePosition, dropTarget.AbsoluteSize
			if
				position.X >= at.X
				and position.X <= at.X + size.X
				and position.Y >= at.Y
				and position.Y <= at.Y + size.Y
				and not model.saved:peek()[item.id]
			then
				model.save(current:peek())
			end
		end
		local function moved(position)
			return dragOrigin ~= nil and (position - dragOrigin).Magnitude > 6
		end
		runtime.connect(drag, "DragStart", function(position)
			dragOrigin = if drag.Enabled then position else nil
			dragged = false
			suppressPointerActivation = true
		end)
		runtime.connect(drag, "DragContinue", function(position)
			dragged = dragged or moved(position)
		end)
		runtime.connect(drag, "DragEnd", function(position)
			local active = drag.Enabled and dragOrigin ~= nil
			local wasDragged = dragged or moved(position)
			cancelPointer()
			drag.Enabled = not touchEnabled:peek()
			if active then
				if wasDragged then
					saveAt(position)
				else
					openCard()
				end
			end
		end)
		if inputService then
			local contact, position, heldScroller, scrollingEnabled
			local positionConnection, stateConnection
			local held = false
			local function finishTouch(commit)
				if held or not commit then
					suppressPointerActivation = true
				end
				local save = commit and held
				local at = position
				contact, position, held = nil, nil, false
				if positionConnection then
					positionConnection:Disconnect()
					positionConnection = nil
				end
				if stateConnection then
					stateConnection:Disconnect()
					stateConnection = nil
				end
				if heldScroller then
					heldScroller.ScrollingEnabled = scrollingEnabled
					heldScroller = nil
				end
				if save and at then
					saveAt(at)
				end
			end
			Compose.cleanup(function()
				finishTouch(false)
			end)
			runtime.connect(preview, "InputBegan", function(input)
				if input.UserInputType == E.UserInputType.Touch then
					cancelPointer()
					suppressPointerActivation = false
					drag.Enabled = false
					if contact then
						finishTouch(false)
						return
					end
					contact, position = input, input.Position
					positionConnection = input:GetPropertyChangedSignal("Position"):Connect(function()
						position = input.Position
					end)
					stateConnection = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
						if input.UserInputState == E.UserInputState.Cancel then
							finishTouch(false)
						end
					end)
				elseif input.UserInputType == E.UserInputType.MouseButton1 then
					suppressPointerActivation = false
					drag.Enabled = true
					if pointerStateConnection then
						pointerStateConnection:Disconnect()
					end
					pointerStateConnection = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
						if input.UserInputState == E.UserInputState.Cancel then
							cancelPointer()
						end
					end)
				end
			end)
			runtime.connect(preview, "TouchLongPress", function(positions, state)
				if state ~= E.UserInputState.Begin or contact == nil or held then
					return
				end
				if #positions ~= 1 then
					finishTouch(false)
					return
				end
				held = true
				suppressPointerActivation = true
				heldScroller = card:FindFirstAncestorWhichIsA("ScrollingFrame")
				if heldScroller then
					scrollingEnabled = heldScroller.ScrollingEnabled
					heldScroller.ScrollingEnabled = false
				end
			end)
			runtime.connect(inputService, "InputEnded", function(input)
				if input == contact then
					position = input.Position
					finishTouch(input.UserInputState ~= E.UserInputState.Cancel)
				end
			end)
			runtime.connect(inputService, "WindowFocusReleased", function()
				cancelPointer()
				finishTouch(false)
				drag.Enabled = not touchEnabled:peek()
			end)
		end
		model.catalog.seen(item.index)
		return card
	end
	local launchSteps = {
		{ id = "find", label = "Find server" },
		{ id = "load", label = "Load world" },
		{ id = "join", label = "Join" },
	}
	local function detailContent(current)
		local selected = current:peek()
		if not selected then
			return Host.Frame({ BackgroundTransparency = 1 })
		end
		local ratingPresented = Compose.cell(false)
		local ratingAnchor = button("AboutRating", selected.rating .. " recommend this game", function()
			ratingPresented:set(true)
		end, { Size = D2.new(1, 0, 0, 36), AutomaticSize = E.AutomaticSize.None })
		local function sparkline()
			local points = {}
			for day = 0, 6 do
				local wobble = ((selected.index * (day + 1) * 37) % 23) / 23
				table.insert(points, types.Path2DControlPoint.new(D2.fromScale(day / 6, 1 - (0.25 + 0.5 * wobble))))
			end
			local path = Host.Path2D "TrendLine" {
				Thickness = 3,
				Color3 = function(use)
					return if use(model.dark) then C3.fromRGB(144, 220, 190) else C3.fromRGB(45, 86, 65)
				end,
			}
			path:SetControlPoints(points)
			return Host.Frame "Sparkline" { Size = D2.new(1, 0, 0, 40), BackgroundTransparency = 1, path }
		end
		local tab = function(use)
			return use(model.detailTab)
		end
		local function launching(use)
			local launch = use(model.launch)
			return if launch and launch.id == selected.id then launch else nil
		end
		local similar = {}
		for _, candidate in model.catalog.items:peek() do
			if candidate.genre == selected.genre and candidate.id ~= selected.id then
				table.insert(similar, candidate)
			end
		end
		local perPage = 6
		local pageCount = math.max(1, math.ceil(#similar / perPage))
		return UI.VStack "GameDetails" {
			width = "fill",
			gap = "s",
			stage(
				"DetailScene",
				if actions.gameContent then actions.gameContent(current) else nil,
				{ Size = D2.new(1, 0, 0, 180) }
			),
			UI.HStack "PlayRow" {
				width = "fill",
				gap = "s",
				align = "center",
				UI.SplitButton "Play" {
					label = "Play",
					menuLabel = "More ways to play",
					onActivate = function()
						model.launchGame(selected.id, "Joining a public server")
					end,
					items = {
						{
							id = "Friends",
							label = if #selected.friends > 0
								then `Join friends ({#selected.friends})`
								else "Join friends",
							enabled = #selected.friends > 0,
							onSelect = function()
								model.launchGame(selected.id, "Joining your friends")
							end,
						},
						{
							id = "Private",
							label = "Start a private server",
							onSelect = function()
								model.launchGame(selected.id, "Starting a private server")
							end,
						},
					},
				},
				quiet("LaunchStatus", function(use)
					local launch = launching(use)
					return if launch == nil
						then ""
						elseif launch.stage > 3 then "Joined (simulated)"
						else `{launch.mode}… (simulated)`
				end, "label", { Size = D2.fromOffset(0, 0), TextWrapped = false, UI.fill() }),
			},
			Compose.show(function(use)
				return launching(use) ~= nil
			end, function()
				return UI.StepIndicator "LaunchSteps" {
					steps = function(use)
						local stage = launching(use).stage
						local steps = {}
						for index, step in launchSteps do
							table.insert(steps, {
								id = step.id,
								label = step.label,
								state = if index < stage
									then "complete"
									elseif index == stage then "current"
									else "upcoming",
							})
						end
						return steps
					end,
					current = function(use)
						local launch = launching(use)
						return if launch and launch.stage <= 3 then launchSteps[launch.stage].id else nil
					end,
					listLabel = "Launch steps",
				}
			end),
			UI.DateTimePicker "Session" {
				label = "Play session",
				time = true,
				minuteStep = 15,
				clock = clock,
				min = civil.dateOf(clock()),
				placeholder = "Not scheduled",
				value = function(use)
					return use(model.sessions)[selected.id]
				end,
				onChange = function(date)
					model.schedule(selected.id, date)
				end,
				hint = function(use)
					local session = use(model.sessions)[selected.id]
					return if session
						then `Friends see {civil.format(session)} at {civil.formatTime(session, 12)}.`
						else "Pick a time to play with friends."
				end,
			},
			words("Description", selected.description),
			UI.Divider "CreatorRule" {},
			UI.HStack "Creator" {
				width = "fill",
				gap = "s",
				align = "center",
				UI.AsyncImage "CreatorAvatar" {
					source = selected.creatorImage,
					loader = actions.creatorImageLoader,
					Size = D2.fromOffset(40, 40),
					placeholder = function()
						return UI.Skeleton "CreatorShimmer" {
							form = "circle",
							Size = D2.fromOffset(40, 40),
							AutomaticSize = E.AutomaticSize.None,
						}
					end,
				},
				UI.Text "CreatorName" { text = selected.creator, textRole = "label", UI.fill() },
			},
			UI.HStack "DetailsTabs" {
				width = "fill",
				gap = "s",
				button("AboutTab", "About", function()
					model.detailTab:set("about")
				end),
				button("SimilarTab", "Similar games", function()
					model.detailTab:set("similar")
				end),
				UI.Spacer "TabsGap" { minLength = "s" },
				button("SaveDetail", saveAction(current).label, function()
					model.save(current:peek())
				end),
			},
			Compose.show(function(use)
				return tab(use) == "about"
			end, function()
				return UI.VStack "AboutGame" {
					width = "fill",
					gap = "s",
					ratingAnchor,
					Compose.show(ratingPresented, function()
						return UI.Callout "RatingPopover" {
							priority = 10,
							anchor = ratingAnchor,
							isPresented = ratingPresented,
							content = function()
								return words(
									"RatingMeaning",
									"The rating is the share of players who would recommend this game to a friend.",
									"label"
								)
							end,
							onRetire = function()
								ratingPresented:set(false)
							end,
						}
					end),
					UI.Label "TrendHeading" { title = "Players this week", icon = "person", textSize = "label" },
					sparkline(),
					quiet("Rating", selected.rating .. " recommend this game · " .. selected.players, "label"),
					words("YourRating", "Your rating", "label"),
					UI.Rating "Stars" {
						value = function(use)
							return use(model.ratings)[selected.id] or selected.stars
						end,
						count = 5,
						allowZero = false,
						onChange = function(value)
							model.rate(selected.id, value)
						end,
						Size = D2.new(1, 0, 0, 44),
						AutomaticSize = E.AutomaticSize.None,
					},
					quiet(
						"RatingExplanation",
						"The rating is the share of players who would recommend this game to a friend."
					),
				}
			end),
			Compose.show(function(use)
				return tab(use) == "similar"
			end, function()
				local function similarRow(candidate)
					return UI.RowActions({
						Name = "SimilarRow_" .. candidate.id,
						Size = D2.new(1, 0, 0, 42),
						content = function()
							return button(
								"Similar_" .. candidate.id,
								candidate.title .. "  ·  " .. candidate.rating,
								function()
									model.selectGame(candidate)
								end,
								{ Size = D2.fromScale(1, 1), AutomaticSize = E.AutomaticSize.None }
							)
						end,
						trailing = {
							{
								id = "SaveSimilar",
								label = "Save",
								onActivate = function()
									model.save(candidate)
								end,
							},
						},
					})
				end
				return UI.VStack "SimilarGames" {
					width = "fill",
					gap = "s",
					Compose.switch(function(use)
						return math.clamp(use(model.similarPage), 1, pageCount)
					end, {}, function()
						local page = math.clamp(model.similarPage:peek(), 1, pageCount)
						local rows = { Name = "SimilarPage", width = "fill", gap = "s" }
						for index = (page - 1) * perPage + 1, math.min(#similar, page * perPage) do
							table.insert(rows, similarRow(similar[index]))
						end
						return UI.VStack(rows)
					end),
					Compose.show(function()
						return pageCount > 1
					end, function()
						return UI.Pagination "SimilarPages" {
							page = model.similarPage,
							pageCount = pageCount,
							onChange = function(page)
								model.similarPage:set(page)
							end,
						}
					end),
				}
			end),
		}
	end
	local function discoverContent(region, collapsed)
		local dimensions = Compose.cell(V2.new(screens.CANVAS.w, screens.CANVAS.h))
		local function short(use)
			return use(region).Y < screens.SHORT_HEIGHT
		end
		local function compact(use)
			return use(dimensions).X < (if short(use) then 480 else 620)
		end
		Compose.watch(function(use)
			local offset = use(model.discoveryScroll) or 0
			local browsing = short(use) and use(model.shelf) == "browse"
			if not browsing or offset < 8 then
				collapsed:set(false)
			elseif offset > 48 then
				collapsed:set(true)
			end
		end)
		local function featured(use)
			return not compact(use) and use(dimensions).Y >= 682 and use(model.shelf) == "browse"
		end
		local genreOptions = { { value = "all", label = "All" } }
		for _, name in require("./catalog").genres do
			table.insert(genreOptions, { value = name, label = name })
		end
		local body
		local focusSearch = Host.InputAction "FocusSearch" {
			Type = E.InputActionType.Bool,
			Enabled = function(use)
				return if actions.spatial then use(model.mode) == "Spatial" else use(model.mode) == "Screen"
			end,
			Released = function()
				local editor = body:FindFirstChild("Editor", true)
				if editor and editor:IsA("TextBox") then
					editor:CaptureFocus()
				end
			end,
			Host.InputBinding({ KeyCode = E.KeyCode.Slash }),
		}
		local chips = {
			Name = "Genres",
			axis = "x",
			gap = "s",
			Size = D2.new(1, 0, 0, 44),
			ScrollBarThickness = 2,
			Visible = function(use)
				return not use(collapsed)
			end,
		}
		for _, option in genreOptions do
			local value = option.value
			table.insert(
				chips,
				UI.Chip({
					Name = "Genre_" .. value,
					label = option.label,
					selected = function(use)
						return use(model.genre) == value
					end,
					onToggle = function()
						model.genre:set(value)
					end,
				})
			)
		end
		local savedShelf = button("Saved", "Saved", function()
			model.shelf:set("saved")
		end)
		local shelves = UI.HStack "Shelves" {
			width = function(use)
				return if short(use) and not compact(use) then "hug" else "fill"
			end,
			gap = "s",
			align = "center",
			button("Browse", "Browse", function()
				model.shelf:set("browse")
			end),
			UI.badged(savedShelf, function(use)
				return #use(model.savedGames)
			end),
			UI.Text "Count" {
				text = function(use)
					return `{#use(model.visibleGames)} games`
				end,
				textRole = "caption",
				role = "secondary",
				TextXAlignment = E.TextXAlignment.Right,
				Visible = function(use)
					return not short(use)
				end,
				UI.fill(),
			},
		}
		dropTarget = shelves
		Compose.cleanup(function()
			if dropTarget == shelves then
				dropTarget = nil
			end
		end)
		local function feedFrame(child)
			return Host.Frame "Feed" {
				BackgroundTransparency = 1,
				Size = D2.fromScale(1, 0),
				UI.fill(),
				child,
			}
		end
		body = UI.VStack "DiscoverBody" {
			width = "fill",
			height = "fill",
			gap = "s",
			Host.InputContext "DiscoverShortcuts" { focusSearch },
			UI.HStack "SearchControls" {
				width = "fill",
				gap = "s",
				align = "center",
				wrap = true,
				UI.ComboBox "Search" {
					value = model.searchSelection,
					text = model.query,
					acceptCustom = function()
						return true
					end,
					options = function(use)
						local query, choices = use(model.query):lower(), {}
						if query ~= "" then
							for _, item in use(model.catalog.items) do
								if item.title:lower():find(query, 1, true) then
									table.insert(choices, { value = item.id, label = item.title })
									if #choices == 8 then
										break
									end
								end
							end
						end
						return choices
					end,
					onChange = function(id)
						for _, item in model.catalog.items:peek() do
							if item.id == id then
								model.selectGame(item)
								break
							end
						end
					end,
					placeholder = "Search games",
					Size = function(use)
						return if compact(use) then D2.new(1, 0, 0, 44) else D2.fromOffset(0, 44)
					end,
					AutomaticSize = E.AutomaticSize.None,
					Host.UIFlexItem({
						FlexMode = function(use)
							return if compact(use) then E.UIFlexMode.None else E.UIFlexMode.Fill
						end,
					}),
				},
				UI.ShortcutHint "SearchShortcut" {
					action = focusSearch,
					Visible = function(use)
						return not compact(use) and not use(touchEnabled)
					end,
				},
				UI.Picker "Sort" {
					selected = model.sort,
					onChange = function(value)
						model.sort:set(value)
					end,
					options = {
						{ value = "recommended", label = "Recommended" },
						{ value = "rating", label = "Top rated" },
						{ value = "playing", label = "Most playing" },
					},
					style = "menu",
					Size = function(use)
						return if compact(use)
							then D2.new(1, 0, 0, 44)
							else D2.fromOffset(if short(use) then 150 else 180, 44)
					end,
					AutomaticSize = E.AutomaticSize.None,
				},
				shelves,
			},
			UI.ScrollView(chips),
			Compose.show(featured, function()
				local pages = {}
				for index = 1, 3 do
					local item = model.catalog.items:peek()[index]
					table.insert(pages, {
						id = item.id,
						label = item.title,
						content = function()
							local card
							card = button("ExploreFeatured_" .. item.id, "", function()
								selectedCard:set(card)
								model.selectGame(item)
							end, {
								Size = D2.fromScale(1, 1),
								AutomaticSize = E.AutomaticSize.None,
								stage(
									"FeaturedScene",
									if item.index == 1
										then actions.discoveryContent
										elseif actions.gameContent then actions.gameContent(Compose.cell(item))
										else nil,
									{ Position = D2.fromOffset(12, 12), Size = D2.new(0.42, -18, 1, -24) }
								),
								UI.VStack "FeaturedCopy" {
									gap = "xs",
									Position = D2.new(0.42, 8, 0, 18),
									Size = D2.new(0.58, -28, 0, 0),
									AutomaticSize = E.AutomaticSize.Y,
									Host.UISizeConstraint({ MaxSize = V2.new(520, 1000000) }),
									quiet("FeaturedGenre", item.genre),
									words("FeaturedTitle", item.title, "heading"),
									quiet("FeaturedDescription", item.description, "body"),
									quiet("FeaturedFacts", item.rating .. " recommend  ·  " .. item.players),
									UI.HStack "FeaturedCreator" {
										gap = "xs",
										align = "center",
										UI.Image "FeaturedCreatorImage" {
											image = item.creatorImage,
											shape = "circle",
											scaleMode = "crop",
											Size = D2.fromOffset(24, 24),
										},
										quiet("FeaturedCreatorName", item.creator, "label", {
											Size = D2.fromOffset(0, 0),
											AutomaticSize = E.AutomaticSize.XY,
											TextWrapped = false,
										}),
									},
								},
								UI.Badge "FeaturedBadge" {
									label = "Featured",
									AnchorPoint = V2.new(1, 0),
									Position = D2.new(1, -12, 0, 8),
								},
							})
							card:AddTag("facet-panel")
							return card
						end,
					})
				end
				return UI.PageView "Featured" {
					pages = pages,
					selection = model.featuredSelection,
					summary = false,
					controls = false,
					Size = D2.new(1, 0, 0, 284),
				}
			end),
			Compose.show(function(use)
				return use(model.shelf) == "browse" and #use(model.visibleGames) == 0
			end, function()
				return UI.Notice "NoResults" {
					title = "No games match",
					message = "Try another genre or a shorter search.",
					actions = {
						{
							id = "ClearFilters",
							label = "Clear filters",
							onActivate = function()
								model.genre:set("all")
								model.query:set("")
								model.searchSelection:set("")
							end,
						},
					},
				}
			end),
			Compose.show(function(use)
				return use(model.shelf) == "saved" and #use(model.savedGames) == 0
			end, function()
				return UI.VStack "Empty" {
					width = "fill",
					gap = "xs",
					padding = "m",
					words("EmptyTitle", "Nothing saved yet", "heading"),
					quiet("EmptyMessage", "Save a game from its page, or drag a card onto Saved.", "label"),
				}
			end),
			Compose.show(function(use)
				return use(model.shelf) == "browse"
			end, function()
				return feedFrame(Compose.switch(function(use)
					return use(model.query) .. "\0" .. use(model.genre) .. "\0" .. use(model.sort)
				end, {}, function()
					return collection("VirtualGrid", {
						Name = "Games",
						from = model.visibleGames,
						key = "id",
						columns = function(use)
							return math.max(1, math.floor((use(dimensions).X + 16) / 280))
						end,
						itemSize = 250,
						measure = true,
						gap = 16,
						overscan = 1,
						render = gameCard,
						Size = D2.fromScale(1, 1),
						BackgroundTransparency = 1,
						ScrollBarThickness = 5,
					}, model.discoveryScroll)
				end))
			end),
			Compose.show(function(use)
				return use(model.shelf) == "saved"
			end, function()
				return feedFrame(UI.Table "SavedGames" {
					from = model.savedGames,
					key = "id",
					selection = model.savedSelection,
					selectionMode = "single",
					sort = model.savedSort,
					widths = model.savedWidths,
					itemSize = 60,
					reorderable = true,
					onReorder = model.reorderSaved,
					dragLabel = function(item)
						return item.title
					end,
					onActivate = function(item)
						model.shelf:set("browse")
						model.selectGame(item)
					end,
					Size = D2.fromScale(1, 1),
					columns = {
						{
							id = "title",
							label = "Game",
							minWidth = 140,
							value = function(item)
								return item.title
							end,
						},
						{
							id = "genre",
							label = "Genre",
							width = 120,
							value = function(item)
								return item.genre
							end,
						},
						{
							id = "session",
							label = "Session",
							width = 120,
							value = function(item)
								local session = model.sessions:peek()[item.id]
								return if session then civil.format(session) else "—"
							end,
						},
						{
							id = "rating",
							label = "Rating",
							width = 80,
							value = function(item)
								return item.rating
							end,
						},
						{
							id = "note",
							label = "Note",
							width = 160,
							sortable = false,
							priority = "always",
							render = function(current)
								local id = current:peek().id
								local draft = Compose.cell(model.notes:peek()[id] or "")
								return UI.TextInput({
									Name = "Note_" .. id,
									value = draft,
									placeholder = "Add a note",
									Size = D2.new(1, 0, 1, -12),
									AutomaticSize = E.AutomaticSize.None,
									onCommit = function(value)
										model.setNote(id, value)
									end,
									onCancel = function()
										draft:set(model.notes:peek()[id] or "")
									end,
								})
							end,
						},
					},
				})
			end),
		}
		measure(body, dimensions)
		return body,
			UI.ZStack "Overlays" {
				width = "fill",
				height = "fill",
				UI.Alert "GameDetail" {
					surface = "fullScreen",
					transition = { source = selectedCard, seconds = 0.32, ease = Compose.easing.outCubic },
					item = model.selectedGame,
					title = function(payload)
						local title = Compose.cell(payload.title)
						Compose.watch(function(use)
							local selected = use(model.selectedGame)
							if selected then
								title:set(selected.title)
							end
						end)
						return title
					end,
					content = function(payload)
						local presentedGame = Compose.cell(payload)
						Compose.watch(function(use)
							local selected = use(model.selectedGame)
							if selected then
								presentedGame:set(selected)
							end
						end)
						return Host.Frame "DetailSelection" {
							BackgroundTransparency = 1,
							Size = D2.new(1, 0, 0, 0),
							AutomaticSize = E.AutomaticSize.Y,
							Compose.keyed({
								from = function(use)
									return { use(presentedGame) }
								end,
								key = function(item)
									return item.id
								end,
								render = detailContent,
							}),
						}
					end,
					actions = { { id = "close", label = "Done", role = "cancel" } },
				},
				toastFor("Discover"),
			}
	end
	local ctx = {
		Facet = Facet,
		Compose = Compose,
		Host = Host,
		UI = UI,
		runtime = runtime,
		model = model,
		types = types,
		D = D,
		D2 = D2,
		V2 = V2,
		C3 = C3,
		CF = CF,
		E = E,
		words = words,
		quiet = quiet,
		button = button,
		stage = stage,
		observeSize = observeSize,
		measure = measure,
		collection = collection,
		actions = actions,
		rounded = rounded,
		panelShadow = panelShadow,
		toastFor = toastFor,
	}
	local function Discover()
		local collapsed = Compose.cell(false)
		return shell("Discover", function(region)
			return discoverContent(region, collapsed)
		end, collapsed)
	end
	local function Avatar()
		return shell("Avatar", function()
			return require("./avatar")(ctx)
		end)
	end
	local function Chat()
		return shell("Chat", function()
			return require("./chat")(ctx)
		end)
	end
	return { Discover = Discover, Avatar = Avatar, Chat = Chat }
end

return screens
