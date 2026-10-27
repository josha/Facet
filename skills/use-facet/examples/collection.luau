--!strict
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local supplyArt = require(script.Parent.Parent.assets["river-supplies-art"])

export type Record = {
	id: string,
	name: string,
	category: string,
	facts: string,
	value: number,
	price: string?,
	ownership: string?,
}
export type SubjectRenderer = (Facet.App, Facet.ReadOnlyValue<Record>) -> GuiObject
export type Order = string
export type Model = {
	query: Facet.Value<string>,
	category: Facet.Value<string>,
	order: Facet.Value<Order>,
	filterPath: Facet.Value<{ Facet.NavigationEntry<string> }>,
	selected: Facet.Value<string>,
	scroll: Vector2,
}
export type Callbacks = { inspect: (string) -> (), close: () -> () }
export type DetailState = {
	accepted: Facet.ReadOnlyValue<boolean>,
	busy: Facet.ReadOnlyValue<boolean>,
	message: Facet.ReadOnlyValue<string>,
}
export type DetailCallbacks = { commit: (string) -> (), back: () -> () }

local function collectionScreen(app: Facet.App, hasArtwork: boolean, content: GuiObject): Frame
	local C, UI = Facet.Compose, app.UI
	local canvas = UI.ZStack "CollectionCanvas" { width = "fill", height = "fill", UI.fill() }
	local room = UI.environment(canvas)
	UI.VStack "CollectionPanel" {
		Parent = C.static(canvas),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		width = "fill",
		maxWidth = if hasArtwork then 1220 else 720,
		height = function(use: Facet.Use): number
			return math.max(0, math.min(840, use(room.viewportHeight)))
		end,
		content,
	}
	return UI.Screen "CollectionSurface" { padding = "m", canvas }
end

local function riverbankSubject(app: Facet.App, record: Facet.ReadOnlyValue<Record>): GuiObject
	local id = Facet.Compose.formula(function(use: Facet.Use): string
		return use(record).id
	end)
	return app.UI.Stage "SupplyPreview" {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		camera = CFrame.lookAt(Vector3.new(3.4, 2.6, 6.5), Vector3.zero),
		fieldOfView = 38,
		Ambient = Color3.fromRGB(200, 210, 193),
		LightColor = Color3.fromRGB(255, 247, 220),
		lazy = true,
		content = function(runtime, world)
			return supplyArt(runtime, world, id)
		end,
	}
end

local function buildDetail(
	app: Facet.App,
	record: Facet.ReadOnlyValue<Record>,
	state: DetailState,
	callbacks: DetailCallbacks,
	renderSubject: (SubjectRenderer | false)?
): Frame
	local C, UI = Facet.Compose, app.UI
	local artwork: SubjectRenderer? = if renderSubject == false then nil else renderSubject or riverbankSubject
	local viewport = UI.ZStack "DetailViewport" { width = "fill", height = "fill", UI.fill() }
	local viewportRoom = UI.environment(viewport)
	local body = UI.ZStack "SupplyDetailBody" {
		Parent = C.static(viewport),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		width = "fill",
		maxWidth = if artwork then 1040 else 560,
		height = function(use: Facet.Use): number
			return math.max(0, math.min(if artwork then 660 else 480, use(viewportRoom.viewportHeight)))
		end,
	}
	local room = UI.environment(body)
	local function decision(): Frame
		return UI.VStack "SupplyDecision" {
			width = "fill",
			gap = "s",
			UI.Text {
				text = function(use: Facet.Use): string
					return use(record).name
				end,
				textRole = "title",
				wrap = true,
			},
			UI.Text {
				text = function(use: Facet.Use): string
					return use(record).category .. " · " .. use(record).facts
				end,
				wrap = true,
			},
			UI.Text {
				text = function(use: Facet.Use): string
					return use(record).price or ""
				end,
				textRole = "strong",
				wrap = true,
			},
			UI.Text {
				Visible = function(use: Facet.Use): boolean
					return (use(record).ownership or "") ~= ""
				end,
				text = function(use: Facet.Use): string
					return use(record).ownership or ""
				end,
				textRole = "caption",
				role = "secondary",
				wrap = true,
			},
			UI.Button "CommitSupply" {
				label = function(use: Facet.Use): string
					return if use(state.accepted) then "In your field kit" else "Add to field kit"
				end,
				appearance = "emphasis",
				busy = state.busy,
				enabled = function(use: Facet.Use): boolean
					return not use(state.busy) and not use(state.accepted)
				end,
				onActivate = function()
					callbacks.commit(record:peek().id)
				end,
			},
			UI.Text { text = state.message, textRole = "caption", wrap = true },
		}
	end
	UI.ZStack "SupplyDetailForm" {
		Parent = C.static(body),
		width = "fill",
		height = "fill",
		C.show(function(use: Facet.Use): boolean
			return artwork ~= nil and use(room.viewportWidth) >= 640
		end, function()
			return UI.HStack "SubjectAndDecision" {
				width = "fill",
				height = "fill",
				gap = "m",
				align = "stretch",
				UI.ZStack "Subject" { width = "fill", height = "fill", UI.fill(), assert(artwork)(app, record) },
				UI.ScrollView "DecisionScroll" {
					width = 300,
					height = "fill",
					padding = "s",
					UI.VStack "CenteredDecision" { width = "fill", height = "fill", distribute = "center", decision() },
				},
			}
		end, function()
			return UI.ScrollView "CompactSupply" {
				width = "fill",
				height = "fill",
				gap = "s",
				padding = "s",
				C.show(function(): boolean
					return artwork ~= nil
				end, function()
					return UI.ZStack "Subject" {
						width = "fill",
						height = function(use: Facet.Use): number
							return math.max(160, math.min(250, use(room.viewportHeight) * 0.36))
						end,
						assert(artwork)(app, record),
					}
				end),
				decision(),
			}
		end),
	}
	return collectionScreen(
		app,
		artwork ~= nil,
		UI.Screen "SupplyInspection" {
			surface = "surface",
			padding = "s",
			gap = "s",
			UI.NavBar { title = "Riverbank / Field kit", titleSize = "heading", onBack = callbacks.back },
			viewport,
		}
	)
end

local function createModel(): Model
	local C = Facet.Compose
	return {
		query = C.cell(""),
		category = C.cell(""),
		order = C.cell("name" :: Order),
		filterPath = C.cell({} :: { Facet.NavigationEntry<string> }),
		selected = C.cell(""),
		scroll = Vector2.zero,
	}
end

return {
	theme = require(script.Parent.Parent.assets["riverbank-theme"]),
	riverbankSubject = riverbankSubject,
	createModel = createModel,
	buildDetail = buildDetail,
	build = function(
		app: Facet.App,
		records: Facet.ReadOnlyValue<{ Record }>,
		model: Model,
		callbacks: Callbacks,
		renderSubject: (SubjectRenderer | false)?
	): Frame
		local C, UI = Facet.Compose, app.UI
		local artwork: SubjectRenderer? = if renderSubject == false then nil else renderSubject or riverbankSubject
		local recordsBody = UI.ZStack "RecordsBody" { width = "fill", height = "fill", UI.fill() }
		local recordRoom = UI.environment(recordsBody)
		local compact = C.formula(function(use: Facet.Use): boolean
			return artwork == nil or use(recordRoom.viewportWidth) < 620 or use(recordRoom.viewportHeight) < 400
		end)
		local function reset()
			model.query:set("")
			model.category:set("")
			model.order:set("name")
		end
		local categories = C.formula(function(use: Facet.Use): { Facet.PickerOption<string> }
			local seen: { [string]: boolean } = {}
			local names: { string } = {}
			for _, record in use(records) do
				if not seen[record.category] then
					seen[record.category] = true
					table.insert(names, record.category)
				end
			end
			table.sort(names)
			local options: { Facet.PickerOption<string> } = { { value = "", label = "All types" } }
			for _, name in names do
				table.insert(options, { value = name, label = name })
			end
			local selected = use(model.category)
			if selected ~= "" and not seen[selected] then
				table.insert(options, { value = selected, label = selected .. " (unavailable)" })
			end
			return options
		end)
		local visible = C.formula(function(use: Facet.Use): { Record }
			local query, category, order = string.lower(use(model.query)), use(model.category), use(model.order)
			local matches: { Record } = {}
			for _, record in use(records) do
				local text = string.lower(
					record.name
						.. " "
						.. record.category
						.. " "
						.. record.facts
						.. " "
						.. (record.price or "")
						.. " "
						.. (record.ownership or "")
				)
				if (category == "" or record.category == category) and string.find(text, query, 1, true) then
					table.insert(matches, record)
				end
			end
			table.sort(matches, function(a: Record, b: Record): boolean
				if order == "value" and a.value ~= b.value then
					return a.value < b.value
				end
				if a.name ~= b.name then
					return a.name < b.name
				end
				return a.id < b.id
			end)
			return matches
		end)
		local filterKey = C.formula(function(use: Facet.Use): string
			return use(model.query) .. "\0" .. use(model.category) .. "\0" .. use(model.order)
		end)
		local rows: Facet.KeyedCollectionSpec<Record, string> = {
			from = visible,
			key = "id",
			minColumnWidth = if artwork then recordRoom.scaled(320) else nil,
			itemSize = function(use: Facet.Use): number
				return if use(compact) then 170 else 330
			end,
			gap = recordRoom.scaled(16),
			measure = true,
			autoFocus = false,
			focusPolicy = "key",
			scrollReset = filterKey,
			CanvasPosition = model.scroll,
			Size = UDim2.fromScale(1, 1),
			render = function(current)
				local function inspect()
					local id = current:peek().id
					model.selected:set(id)
					callbacks.inspect(id)
				end
				local function title(use: Facet.Use): string
					return use(current).name
				end
				local function subtitle(use: Facet.Use): string
					local record = use(current)
					return record.category .. " · " .. record.facts
				end
				local function price(use: Facet.Use): string
					return use(current).price or ""
				end
				local function ownership(use: Facet.Use): string
					return use(current).ownership or ""
				end
				local function actionLabel(use: Facet.Use): string
					return if use(model.selected) == use(current).id then "Inspect selected" else "Inspect"
				end
				local function art(): GuiObject
					return assert(artwork)(app, current)
				end
				return UI.VStack "SupplyRecord" {
					width = "fill",
					C.show(compact, function()
						return UI.HStack "ThumbnailRecord" {
							width = "fill",
							gap = "s",
							padding = "s",
							surface = "panel",
							align = "center",
							C.show(function(): boolean
								return artwork ~= nil
							end, function()
								return UI.ZStack "Thumbnail" {
									width = recordRoom.scaled(92),
									height = recordRoom.scaled(116),
									art(),
								}
							end),
							UI.VStack "RecordDecision" {
								width = "fill",
								gap = "xs",
								UI.fill(),
								UI.Text { text = title, textRole = "strong", wrap = true },
								UI.Text { text = subtitle, textRole = "caption", role = "secondary", wrap = true },
								UI.Text { text = price, textRole = "strong", wrap = true },
								UI.Text {
									Visible = function(use: Facet.Use): boolean
										return ownership(use) ~= ""
									end,
									text = ownership,
									textRole = "caption",
									role = "secondary",
									wrap = true,
								},
								UI.Button "InspectSupply" {
									label = actionLabel,
									appearance = "utility",
									onActivate = inspect,
								},
							},
						}
					end, function()
						local badges: Facet.CardBadges = {
							leading = { label = ownership },
							trailing = { label = price, status = "contrast" },
						}
						return UI.VStack "VisualRecord" {
							width = "fill",
							gap = "xs",
							UI.Card "SupplyCard" {
								Size = UDim2.new(1, 0, 0, 0),
								title = title,
								caption = subtitle,
								artwork = art,
								imageAspectRatio = 1.65,
								badges = badges,
							},
							UI.Button "InspectSupply" {
								Size = UDim2.new(1, 0, 0, 0),
								label = actionLabel,
								appearance = "utility",
								onActivate = inspect,
							},
						}
					end),
				}
			end,
			UI.fill(),
		}
		local list = if artwork then UI.VirtualGrid "Records"(rows) else UI.VirtualList "Records"(rows)
		list.Parent = recordsBody
		UI.ScrollView "EmptyResults" {
			Parent = C.static(recordsBody),
			Visible = function(use: Facet.Use): boolean
				return #use(visible) == 0
			end,
			width = "fill",
			height = "fill",
			gap = "s",
			UI.Text { text = "No matching stock", textRole = "heading", wrap = true },
			UI.Text { text = "Change the search or reset all filters to see river supplies.", wrap = true },
			UI.Button { label = "Reset search and filters", onActivate = reset },
		}
		local scrollConnection = list:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			model.scroll = list.CanvasPosition
		end)
		C.cleanup(function()
			scrollConnection:Disconnect()
		end)
		local orders: { Facet.PickerOption<Order> } = {
			{ value = "name", label = "Name" },
			{ value = "value", label = "Lowest cost" },
		}
		local search: Facet.TextInputCellProps = {
			Size = UDim2.new(1, 0, 0, 0),
			value = model.query,
			presentation = "search",
			placeholder = "Search river supplies",
			UI.fill(),
		}
		local searchInput: (Facet.TextInputCellProps) -> GuiObject = UI.TextInput "Search"
		local body = UI.ZStack "CollectionBody" {
			width = "fill",
			height = "fill",
			alignH = "center",
			UI.fill(),
			UI.VStack "Browse" {
				width = "fill",
				height = "fill",
				gap = "xs",
				UI.HStack "SearchAndFilters" {
					width = "fill",
					align = "center",
					gap = "s",
					searchInput(search),
					UI.Button "Filters" {
						label = "Filters",
						appearance = "utility",
						onActivate = function()
							model.filterPath:set({ { id = "filters" } })
						end,
					},
				},
				UI.Text "ResultSummary" {
					wrap = true,
					textRole = "caption",
					text = function(use: Facet.Use): string
						local category = use(model.category)
						return `{#use(visible)} in stock · {if category == "" then "All types" else category} · {if use(
								model.order
							) == "name"
							then "Name"
							else "Lowest cost"}`
					end,
				},
				recordsBody,
			},
		}
		local function showRecords()
			model.filterPath:set({})
		end
		local navigation = UI.NavigationStack "CollectionSteps" {
			path = model.filterPath,
			chrome = "hidden",
			root = {
				content = function(): Instance
					local close: GuiObject = UI.Button {
						label = "Close",
						appearance = "utility",
						onActivate = function()
							callbacks.close()
						end,
					}
					return UI.Screen "Collection" {
						surface = "surface",
						padding = "s",
						gap = "s",
						UI.NavBar { title = "Riverbank supplies", titleSize = "heading", trailing = close },
						body,
					}
				end,
			},
			destinations = {
				filters = {
					content = function(): Instance
						local done: GuiObject = UI.Button {
							label = function(use: Facet.Use): string
								return `Show {#use(visible)} items`
							end,
							appearance = "emphasis",
							onActivate = showRecords,
						}
						return UI.Screen "Filters" {
							surface = "surface",
							padding = "s",
							gap = "s",
							UI.NavBar { title = "Filters", titleSize = "heading", onBack = showRecords, trailing = done },
							UI.ZStack "FilterWidth" {
								width = "fill",
								height = "fill",
								alignH = "center",
								UI.fill(),
								UI.ScrollView "FilterStep" {
									width = "fill",
									maxWidth = 560,
									height = "fill",
									gap = "m",
									padding = "s",
									UI.Picker "Type" {
										label = "Type",
										selected = model.category,
										options = categories,
										style = "menu",
									},
									UI.Picker "Sort" {
										label = "Sort",
										selected = model.order,
										options = orders,
										style = "menu",
									},
									UI.Button {
										label = "Reset search and filters",
										appearance = "utility",
										onActivate = reset,
									},
								},
							},
						}
					end,
				},
			},
		}
		return collectionScreen(app, artwork ~= nil, navigation)
	end,
}
