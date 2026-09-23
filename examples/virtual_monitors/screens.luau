--!strict
local screens = { CANVAS = { w = 920, h = 640 } }

function screens.create(Facet: any, runtime: any, actions: any)
	local Compose, Host = Facet.Compose, runtime.constructors
	local model = actions.model
	local types = actions.types or getfenv(0)
	local D, D2, V2, C3, CF, E = types.UDim, types.UDim2, types.Vector2, types.Color3, types.CFrame, types.Enum
	local UI = Facet.controls(
		runtime,
		{ types = types, services = actions.services, theme = actions.theme, reducedMotion = actions.reducedMotion }
	)
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
	local dropTarget
	local selectedCard = Compose.cell(nil)
	local function rounded(radius)
		return Host.UICorner({ CornerRadius = D.new(0, radius or 12) })
	end
	local function padding(value)
		return Host.UIPadding({
			PaddingLeft = D.new(0, value),
			PaddingRight = D.new(0, value),
			PaddingTop = D.new(0, value),
			PaddingBottom = D.new(0, value),
		})
	end
	local function text(name, value, size, props, tag)
		local spec = {
			Name = name,
			Text = value,
			TextSize = size or 18,
			Font = E.Font.BuilderSans,
			TextXAlignment = E.TextXAlignment.Left,
			TextYAlignment = E.TextYAlignment.Top,
			TextWrapped = true,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
		}
		for key, value in props or {} do
			if type(key) == "number" then
				table.insert(spec, value)
			else
				spec[key] = value
			end
		end
		local node = Host.TextLabel(spec)
		node:AddTag("facet-text")
		if tag then
			node:AddTag(tag)
		end
		return node
	end
	local function row(name, children, props)
		local spec = {
			Name = name,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = D2.new(1, 0, 0, 38),
			Host.UIListLayout({
				FillDirection = E.FillDirection.Horizontal,
				SortOrder = E.SortOrder.LayoutOrder,
				VerticalAlignment = E.VerticalAlignment.Center,
				Padding = D.new(0, 8),
			}),
		}
		for index, child in children do
			runtime.decorate(child, { LayoutOrder = index })
			table.insert(spec, child)
		end
		for key, value in props or {} do
			if type(key) == "number" then
				table.insert(spec, value)
			else
				spec[key] = value
			end
		end
		return Host.Frame(spec)
	end
	local function scrollRow(name, children, props)
		local spec = {
			Name = name,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = D2.new(1, 0, 0, 40),
			CanvasSize = D2.fromOffset(0, 0),
			AutomaticCanvasSize = E.AutomaticSize.X,
			ScrollingDirection = E.ScrollingDirection.X,
			ScrollBarThickness = 2,
			Host.UIListLayout({
				FillDirection = E.FillDirection.Horizontal,
				SortOrder = E.SortOrder.LayoutOrder,
				VerticalAlignment = E.VerticalAlignment.Center,
				Padding = D.new(0, 8),
			}),
		}
		for index, child in children do
			runtime.decorate(child, { LayoutOrder = index })
			table.insert(spec, child)
		end
		for key, value in props or {} do
			if type(key) == "number" then
				table.insert(spec, value)
			else
				spec[key] = value
			end
		end
		return Host.ScrollingFrame(spec)
	end
	local function column(name, children, props, tag)
		local spec = {
			Name = name,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
			Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = D.new(0, 10) }),
		}
		for index, child in children do
			if type(child) ~= "function" then
				runtime.decorate(child, { LayoutOrder = index })
			end
			table.insert(spec, child)
		end
		for key, value in props or {} do
			if type(key) == "number" then
				table.insert(spec, value)
			else
				spec[key] = value
			end
		end
		if tag then
			spec.BackgroundTransparency = nil
		end
		local node = Host.Frame(spec)
		if tag then
			node:AddTag(tag)
		end
		return node
	end
	local function button(name, label, activate, props)
		local spec = { Name = name, label = label, onActivate = activate, Size = D2.fromOffset(0, 36), TextSize = 16 }
		for key, value in props or {} do
			if type(key) == "number" then
				table.insert(spec, value)
			else
				spec[key] = value
			end
		end
		return UI.Button(spec)
	end
	local function observeSize(node)
		local value = Compose.cell(V2.new(screens.CANVAS.w, screens.CANVAS.h))
		local observation = runtime.host.observation
		Compose.cleanup(observation.observeProperty(node, "AbsoluteSize", function()
			local size = observation.readProperty(node, "AbsoluteSize")
			if size.X > 0 and size.Y > 0 then
				value:set(size)
			end
		end))
		return value
	end
	local function collection(kind, spec, source)
		if source:peek() ~= nil then
			spec.CanvasPosition = function(use)
				use(model.mode)
				return V2.new(0, use(source))
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
		local spec = {
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
		}
		for key, value in props or {} do
			if type(key) == "number" then
				table.insert(spec, value)
			else
				spec[key] = value
			end
		end
		return Compose.boundary(function()
			return UI.Stage(spec)
		end, function()
			return text(
				name .. "Unavailable",
				"Preview unavailable",
				16,
				{ Size = spec.Size, Position = spec.Position, AutomaticSize = E.AutomaticSize.None }
			)
		end)
	end
	local function shell(name, body)
		local about = Compose.cell(false)
		local width = Compose.cell(920)
		local actionsRow = {}
		if actions.spatial then
			table.insert(
				actionsRow,
				button("Focus", function(use)
					return if use(model.focused) == name then "All monitors" else "Focus"
				end, function()
					model.focus(name)
				end)
			)
		end
		table.insert(
			actionsRow,
			button("Presentation", function(use)
				return if use(model.mode) == "Spatial" then "Screen mode" else "Spatial mode"
			end, model.toggleMode)
		)
		table.insert(
			actionsRow,
			button("Appearance", function(use)
				return if use(model.dark) then "Light mode" else "Dark mode"
			end, function()
				model.dark:update(function(value)
					return not value
				end)
			end)
		)
		table.insert(
			actionsRow,
			button("About", "About", function()
				about:set(true)
			end)
		)
		local chrome = scrollRow("Chrome", actionsRow, {
			Position = D2.new(0.3, 0, 0, 8),
			Size = D2.new(0.7, -16, 0, 42),
			Visible = function(use)
				return use(width) >= 650
			end,
		})
		runtime.decorate(chrome:FindFirstChildWhichIsA("UIListLayout"), {
			HorizontalAlignment = E.HorizontalAlignment.Right,
		})
		local root = Host.Frame({
			Name = name,
			Size = D2.fromScale(1, 1),
			BorderSizePixel = 0,
			SelectionGroup = true,
			ClipsDescendants = true,
			text("Title", if name == "Chat" then "Assistant" else name, 27, {
				Position = D2.fromOffset(16, 12),
				Size = function(use)
					return if use(width) < 650 then D2.new(1, -132, 0, 36) else D2.new(0.3, -20, 0, 36)
				end,
				AutomaticSize = E.AutomaticSize.None,
				TextTruncate = E.TextTruncate.AtEnd,
				Font = E.Font.BuilderSansBold,
			}),
			chrome,
			UI.Menu({
				Name = "ActionsMenu",
				label = "Menu",
				Position = D2.new(1, -100, 0, 8),
				Visible = function(use)
					return use(width) < 650
				end,
				items = {
					{ id = "Presentation", label = "Switch presentation", onSelect = model.toggleMode },
					{
						id = "Appearance",
						label = "Switch appearance",
						onSelect = function()
							model.dark:update(function(value)
								return not value
							end)
						end,
					},
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
			}),
			Host.Frame({
				Name = "Content",
				Position = D2.fromOffset(16, 62),
				Size = D2.new(1, -32, 1, -78),
				BackgroundTransparency = 1,
				Interactable = function(use)
					return not actions.spatial or use(model.focused) == name
				end,
				body,
			}),
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
			UI.Alert({
				Name = "AboutDialog",
				isPresented = about,
				title = "About Virtual Monitors",
				message = "Three complete apps, shared between a spatial desktop and a flat screen. Compose owns every scene and lifetime; Facet supplies controls; Roblox supplies layout and rendering.",
				actions = { { id = "done", label = "Done", role = "cancel" } },
			}),
		})
		root:AddTag("facet-surface")
		local dimensions = observeSize(root)
		Compose.watch(function(use)
			width:set(use(dimensions).X)
		end)
		return root
	end
	local function saveButton(current, name)
		return button(name or "Save", function(use)
			return if use(model.saved)[use(current).id] then "Saved" else "Save"
		end, function()
			model.toggleSaved(current:peek().id)
		end)
	end
	local function gameCard(current)
		local item = current:peek()
		local card
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
		local footer = column("CardFooter", {
			text("Title", function(use)
				return use(current).title
			end, 18, { TextWrapped = false, TextTruncate = E.TextTruncate.AtEnd, Font = E.Font.BuilderSansBold }),
			text("Facts", function(use)
				local game = use(current)
				return game.rating .. "  ·  " .. game.players
			end, 13, { TextWrapped = false, TextTruncate = E.TextTruncate.AtEnd }, "facet-secondary"),
		}, {
			Position = D2.new(0, 12, 1, -8),
			AnchorPoint = V2.new(0, 1),
			Size = D2.new(1, -100, 0, 0),
		})
		local footerHeight = Compose.cell(42)
		Compose.cleanup(runtime.host.observation.observeProperty(footer, "AbsoluteSize", function()
			if footer.AbsoluteSize.Y > 0 then
				footerHeight:set(footer.AbsoluteSize.Y)
			end
		end))
		card = UI.Button({
			Name = "Game_" .. item.id,
			label = "",
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
			Size = D2.fromScale(1, 1),
			AutomaticSize = E.AutomaticSize.None,
			BorderSizePixel = 0,
			rounded(),
			padding(0),
			stage("Scene", if actions.gameContent then actions.gameContent(current) else nil, {
				Size = function(use)
					return D2.new(1, 0, 1, -math.max(58, use(footerHeight) + 16))
				end,
				Active = false,
			}),
			footer,
			button("Save", function(use)
				return if use(model.saved)[use(current).id] then "Saved" else "Save"
			end, function()
				model.toggleSaved(current:peek().id)
			end, {
				Position = D2.new(1, -10, 1, -10),
				AnchorPoint = V2.new(1, 1),
				Size = D2.fromOffset(72, 36),
				AutomaticSize = E.AutomaticSize.None,
				controlSize = "compact",
				TextSize = 13,
				BackgroundTransparency = 1,
				role = "cancel",
			}),
		})
		card:AddTag("facet-panel")
		local drag = Host.UIDragDetector({
			Name = "SaveDrag",
			ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
			Enabled = function(use)
				return not use(touchEnabled)
			end,
		})
		runtime.mount(function()
			return drag
		end, card)
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
				model.toggleSaved(item.id)
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
			runtime.connect(card, "InputBegan", function(input)
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
			runtime.connect(card, "TouchLongPress", function(positions, state)
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
			local path = Host.Path2D({
				Name = "TrendLine",
				Thickness = 3,
				Color3 = function(use)
					return if use(model.dark) then C3.fromRGB(144, 220, 190) else C3.fromRGB(45, 86, 65)
				end,
			})
			path:SetControlPoints(points)
			return Host.Frame({ Name = "Sparkline", Size = D2.new(1, 0, 0, 40), BackgroundTransparency = 1, path })
		end
		local tab = function(use)
			return use(model.detailTab)
		end
		local contentFrame = Host.Frame({
			Name = "GameDetails",
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		})
		runtime.mount(function()
			return column("DetailBody", {
				stage(
					"DetailScene",
					if actions.gameContent then actions.gameContent(current) else nil,
					{ Size = D2.new(1, 0, 0, 180) }
				),
				text("Description", selected.description, 18),
				row("Creator", {
					UI.AsyncImage({
						Name = "CreatorAvatar",
						source = selected.creatorImage,
						loader = actions.creatorImageLoader,
						Size = D2.fromOffset(40, 40),
						placeholder = function()
							return UI.Skeleton({
								Name = "CreatorShimmer",
								form = "circle",
								Size = D2.fromOffset(40, 40),
								AutomaticSize = E.AutomaticSize.None,
							})
						end,
					}),
					text(
						"CreatorName",
						selected.creator,
						15,
						{ Size = D2.new(1, -52, 0, 38), AutomaticSize = E.AutomaticSize.None }
					),
				}, { Size = D2.new(1, 0, 0, 40) }),
				row("DetailsTabs", {
					button("AboutTab", "About", function()
						model.detailTab:set("about")
					end),
					button("SimilarTab", "Similar games", function()
						model.detailTab:set("similar")
					end),
					saveButton(current, "SaveDetail"),
				}),
				Compose.show(function(use)
					return tab(use) == "about"
				end, function()
					return column("AboutGame", {
						ratingAnchor,
						Compose.show(ratingPresented, function()
							return UI.Callout({
								Name = "RatingPopover",
								priority = 10,
								anchor = ratingAnchor,
								isPresented = ratingPresented,
								content = function()
									return text(
										"RatingMeaning",
										"The rating is the share of players who would recommend this game to a friend.",
										16
									)
								end,
								onRetire = function()
									ratingPresented:set(false)
								end,
							})
						end),
						text("TrendHeading", "Players this week", 16),
						sparkline(),
						text(
							"Rating",
							selected.rating .. " recommend this game · " .. selected.players,
							15,
							{},
							"facet-secondary"
						),
						text("YourRating", "Your rating", 17),
						UI.Rating({
							Name = "Stars",
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
						}),
						text(
							"RatingExplanation",
							"The rating is the share of players who would recommend this game to a friend.",
							14,
							{},
							"facet-secondary"
						),
					}, { LayoutOrder = 5 })
				end),
				Compose.show(function(use)
					return tab(use) == "similar"
				end, function()
					local children = {}
					for _, candidate in model.catalog.items:peek() do
						if candidate.genre == selected.genre and candidate.id ~= selected.id and #children < 6 then
							table.insert(
								children,
								UI.RowActions({
									Name = "SimilarRow_" .. candidate.id,
									Size = D2.new(1, 0, 0, 42),
									content = function()
										return button(
											"Similar_" .. candidate.id,
											candidate.title .. "  ·  " .. candidate.rating,
											function()
												model.selectGame(candidate)
											end,
											{
												Size = D2.fromScale(1, 1),
												AutomaticSize = E.AutomaticSize.None,
											}
										)
									end,
									trailing = {
										{
											id = "SaveSimilar",
											label = "Save",
											onActivate = function()
												model.toggleSaved(candidate.id)
											end,
										},
									},
								})
							)
						end
					end
					return column("SimilarGames", children, { LayoutOrder = 5 })
				end),
			})
		end, contentFrame)
		return contentFrame
	end
	local function Discover()
		local body = Host.Frame({ Name = "DiscoverBody", Size = D2.fromScale(1, 1), BackgroundTransparency = 1 })
		local dimensions = observeSize(body)
		local function compact(use)
			return use(dimensions).X < 620
		end
		local function filtersStacked(use)
			return use(dimensions).X < 288
		end
		local function heroHeight(use)
			return if not compact(use) and use(dimensions).Y >= 682 then 292 else 0
		end
		local function filterHeight(use)
			return if filtersStacked(use) then 96 else 44
		end
		local function searchHeight(use)
			return if compact(use) then filterHeight(use) + 52 else 44
		end
		local function headerHeight(use)
			return if compact(use) then searchHeight(use) + 54 else searchHeight(use) + 106
		end
		local function feedY(use)
			return headerHeight(use) + heroHeight(use)
		end
		local genreOptions = { { value = "all", label = "All genres" } }
		for _, name in require("./catalog").genres do
			table.insert(genreOptions, { value = name, label = name })
		end
		runtime.mountFragment(function()
			return {
				Host.Frame({
					Name = "SearchControls",
					BackgroundTransparency = 1,
					Size = function(use)
						return D2.new(1, 0, 0, searchHeight(use))
					end,
					Host.UIListLayout({
						FillDirection = function(use)
							return if compact(use) then E.FillDirection.Vertical else E.FillDirection.Horizontal
						end,
						SortOrder = E.SortOrder.LayoutOrder,
						Padding = D.new(0, 8),
					}),
					UI.ComboBox({
						Name = "Search",
						LayoutOrder = function(use)
							return if compact(use) then 2 else 1
						end,
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
						Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
					}),
					Host.Frame({
						Name = "SortControl",
						LayoutOrder = function(use)
							return if compact(use) then 1 else 2
						end,
						BackgroundTransparency = 1,
						Size = function(use)
							return if compact(use) then D2.new(1, 0, 0, filterHeight(use)) else D2.fromOffset(180, 44)
						end,
						Host.UIListLayout({
							FillDirection = function(use)
								return if filtersStacked(use)
									then E.FillDirection.Vertical
									else E.FillDirection.Horizontal
							end,
							SortOrder = E.SortOrder.LayoutOrder,
							Padding = D.new(0, 8),
						}),
						UI.Picker({
							Name = "Sort",
							LayoutOrder = 1,
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
								return if filtersStacked(use) then D2.new(1, 0, 0, 44) else D2.fromOffset(0, 44)
							end,
							AutomaticSize = E.AutomaticSize.None,
							Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
						}),
						Compose.show(compact, function()
							return UI.Picker({
								Name = "Genre",
								LayoutOrder = 2,
								selected = model.genre,
								onChange = function(value)
									model.genre:set(value)
								end,
								options = genreOptions,
								style = "menu",
								Size = function(use)
									return if filtersStacked(use) then D2.new(1, 0, 0, 44) else D2.fromOffset(0, 44)
								end,
								AutomaticSize = E.AutomaticSize.None,
								Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
							})
						end),
					}),
				}),
				Compose.keyed({
					from = function(use)
						return if compact(use) then {} else { if use(dimensions).X >= 900 then "segmented" else "menu" }
					end,
					render = function(current)
						return UI.Picker({
							Name = "Genre",
							selected = model.genre,
							onChange = function(value)
								model.genre:set(value)
							end,
							options = genreOptions,
							style = current:peek(),
							Position = function(use)
								return D2.fromOffset(0, searchHeight(use) + 8)
							end,
							Size = D2.new(1, 0, 0, 44),
							AutomaticSize = E.AutomaticSize.None,
						})
					end,
				}),
				(function()
					local shelves = row("Shelves", {
						button("Browse", "Browse", function()
							model.shelf:set("browse")
						end),
						button("Saved", function(use)
							return `Saved ({#use(model.savedGames)})`
						end, function()
							model.shelf:set("saved")
						end),
						text(
							"Count",
							function(use)
								return `{#use(model.visibleGames)} games`
							end,
							14,
							{
								Size = D2.fromOffset(0, 24),
								Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
								TextXAlignment = E.TextXAlignment.Right,
								AutomaticSize = E.AutomaticSize.None,
							},
							"facet-secondary"
						),
					}, {
						Position = function(use)
							return D2.fromOffset(0, headerHeight(use) - 46)
						end,
					})
					dropTarget = shelves
					Compose.cleanup(function()
						if dropTarget == shelves then
							dropTarget = nil
						end
					end)
					return shelves
				end)(),
				Compose.show(function(use)
					return heroHeight(use) > 0 and use(model.shelf) == "browse"
				end, function()
					local pages = {}
					for index = 1, 3 do
						local featured = model.catalog.items:peek()[index]
						table.insert(pages, {
							id = featured.id,
							label = featured.title,
							content = function()
								local card
								card = button("ExploreFeatured_" .. featured.id, "", function()
									selectedCard:set(card)
									model.selectGame(featured)
								end, {
									Size = D2.fromScale(1, 1),
									AutomaticSize = E.AutomaticSize.None,
									stage(
										"FeaturedScene",
										if featured.index == 1
											then actions.discoveryContent
											elseif actions.gameContent then actions.gameContent(
												Compose.cell(featured)
											)
											else nil,
										{ Position = D2.fromOffset(12, 12), Size = D2.new(0.42, -18, 1, -24) }
									),
									column("FeaturedCopy", {
										text("FeaturedGenre", featured.genre, 13, {}, "facet-secondary"),
										text("FeaturedTitle", featured.title, 25),
										text("FeaturedDescription", featured.description, 18, {}, "facet-secondary"),
										text(
											"FeaturedFacts",
											featured.rating .. " recommend  ·  " .. featured.players,
											13,
											{},
											"facet-secondary"
										),
									}, {
										Position = D2.new(0.42, 8, 0, 18),
										Size = D2.new(0.58, -28, 0, 0),
										Host.UISizeConstraint({ MaxSize = V2.new(520, 1000000) }),
									}),
									UI.Badge({
										Name = "FeaturedBadge",
										label = "Featured",
										AnchorPoint = V2.new(1, 0),
										Position = D2.new(1, -12, 0, 8),
									}),
								})
								card:AddTag("facet-panel")
								return card
							end,
						})
					end
					return UI.PageView({
						Name = "Featured",
						pages = pages,
						selection = model.featuredSelection,
						summary = false,
						controls = false,
						Position = function(use)
							return D2.fromOffset(0, headerHeight(use))
						end,
						Size = D2.new(1, 0, 0, 284),
					})
				end),
				Compose.show(function(use)
					return use(model.shelf) == "browse"
				end, function()
					return Compose.switch(function(use)
						return use(model.query) .. "\0" .. use(model.genre) .. "\0" .. use(model.sort)
					end, {}, function()
						return collection("VirtualGrid", {
							Name = "Games",
							from = model.visibleGames,
							key = function(item)
								return item.id
							end,
							columns = function(use)
								return math.max(1, math.floor((use(dimensions).X + 12) / 265))
							end,
							itemSize = 224,
							gap = 12,
							overscan = 1,
							render = gameCard,
							Position = function(use)
								return D2.fromOffset(0, feedY(use))
							end,
							Size = function(use)
								return D2.new(1, 0, 1, -feedY(use))
							end,
							BackgroundTransparency = 1,
							ScrollBarThickness = 5,
						}, model.discoveryScroll)
					end)
				end),
				Compose.show(function(use)
					return use(model.shelf) == "saved"
				end, function()
					return UI.Table({
						Name = "SavedGames",
						from = model.savedGames,
						key = function(item)
							return item.id
						end,
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
						Position = function(use)
							return D2.fromOffset(0, headerHeight(use))
						end,
						Size = function(use)
							return D2.new(1, 0, 1, -headerHeight(use))
						end,
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
								width = 140,
								value = function(item)
									return item.genre
								end,
							},
							{
								id = "rating",
								label = "Rating",
								width = 96,
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
				Compose.show(function(use)
					return (use(model.shelf) == "saved" and #use(model.savedGames) == 0)
						or (use(model.shelf) == "browse" and #use(model.visibleGames) == 0)
				end, function()
					return column("Empty", {
						text("EmptyTitle", function(use)
							return if use(model.shelf) == "saved" then "Nothing saved yet" else "No games match"
						end, 20),
						text("EmptyMessage", function(use)
							return if use(model.shelf) == "saved"
								then "Save a game from its page, or drag a card onto Saved."
								else "Try another genre or a shorter search."
						end, 16, {}, "facet-secondary"),
						button("ClearFilters", "Clear filters", function()
							model.genre:set("all")
							model.query:set("")
							model.searchSelection:set("")
						end, {
							Visible = function(use)
								return use(model.shelf) == "browse"
							end,
						}),
					}, {
						Position = function(use)
							return D2.fromOffset(16, headerHeight(use) + 12)
						end,
						Size = D2.new(1, -32, 0, 0),
					})
				end),
				UI.Alert({
					Name = "GameDetail",
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
						return Host.Frame({
							Name = "DetailSelection",
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
						})
					end,
					actions = { { id = "close", label = "Done", role = "cancel" } },
				}),
			}
		end, body)
		return shell("Discover", body)
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
		text = text,
		row = row,
		column = column,
		scrollRow = scrollRow,
		button = button,
		stage = stage,
		observeSize = observeSize,
		collection = collection,
		actions = actions,
		padding = padding,
		rounded = rounded,
	}
	local function Avatar()
		return shell("Avatar", require("./avatar")(ctx))
	end
	local function Chat()
		return shell("Chat", require("./chat")(ctx))
	end
	return { Discover = Discover, Avatar = Avatar, Chat = Chat }
end

return screens
