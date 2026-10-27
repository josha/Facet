--!strict
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local relicArt = require(script.Parent.Parent.assets["relic-art"])

type Relic = { id: string, name: string, subtitle: string, description: string, trait: string, color: Color3 }
export type InspectionModel = {
	selection: Facet.Value<{ [string]: boolean }>,
	column: Facet.Value<"sidebar" | "detail">,
	notesExpanded: Facet.Value<boolean>,
}
export type State = {
	accepted: Facet.ReadOnlyValue<string>,
	busy: Facet.ReadOnlyValue<boolean>,
	message: Facet.ReadOnlyValue<string>,
	inspection: InspectionModel?,
}
export type Callbacks = { commit: (string) -> (), close: () -> () }

local relics: { Relic } = {
	{
		id = "sun",
		name = "Sun prism",
		subtitle = "East Observatory · amber",
		description = "Recovered from the East Observatory. The brass cradle still carries the surveyors' sun marks.",
		trait = "Warm light · brass cradle",
		color = Color3.fromRGB(197, 133, 68),
	},
	{
		id = "tide",
		name = "Tide lens",
		subtitle = "Tidal chamber · sea glass",
		description = "Found below the tide line. The lens once guided returning survey boats through the reef.",
		trait = "Cool light · polished glass",
		color = Color3.fromRGB(78, 137, 147),
	},
}

return {
	theme = require(script.Parent.Parent.assets["field-station-theme"]),
	build = function(app: Facet.App, state: State, callbacks: Callbacks): Frame
		local C, UI = Facet.Compose, app.UI
		local model: InspectionModel = state.inspection
			or {
				selection = C.cell({ sun = true }),
				column = C.cell("sidebar" :: "sidebar" | "detail"),
				notesExpanded = C.cell(false),
			}
		state.inspection = model
		local selection, column, notesExpanded = model.selection, model.column, model.notesExpanded
		local back = C.cell(false)
		local taskBody = UI.ZStack "TaskBody" { width = "fill", height = "fill", UI.fill() }
		local chosen = C.formula(function(use: Facet.Use): Relic
			for _, relic in relics do
				if use(selection)[relic.id] then
					return relic
				end
			end
			return relics[1]
		end)
		local chosenId = C.formula(function(use: Facet.Use): string
			return use(chosen).id
		end)
		local function subject(): ViewportFrame
			return UI.Stage "Relic" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				camera = CFrame.lookAt(Vector3.new(4, 2.4, 6.5), Vector3.new(0, -0.1, 0)),
				fieldOfView = 36,
				content = function(runtime, world)
					return relicArt(runtime, world, chosenId, relics[1].color, relics[2].color)
				end,
			}
		end
		local function decision(): Frame
			return UI.VStack "Decision" {
				width = "fill",
				gap = "s",
				align = "stretch",
				UI.Text {
					text = function(use: Facet.Use)
						return use(chosen).name
					end,
					textRole = "title",
					wrap = true,
				},
				UI.Text {
					text = function(use: Facet.Use)
						return use(chosen).trait
					end,
					wrap = true,
				},
				UI.Button "CommitRelic" {
					label = function(use: Facet.Use)
						return if use(state.accepted) == use(chosen).id
							then "Selected for display"
							else "Display this relic"
					end,
					appearance = "emphasis",
					busy = state.busy,
					enabled = function(use: Facet.Use)
						return not use(state.busy) and use(state.accepted) ~= use(chosen).id
					end,
					onActivate = function()
						callbacks.commit(chosen:peek().id)
					end,
				},
				UI.Text { text = state.message, textRole = "caption", wrap = true },
				UI.DisclosureGroup "ObjectNotes" {
					label = "Field notes",
					expanded = notesExpanded,
					content = function(): Instance
						return UI.Text {
							text = function(use: Facet.Use)
								return use(chosen).description
							end,
							wrap = true,
						}
					end,
				},
			}
		end
		local list: Facet.KeyedCollectionSpec<Relic, string> = {
			from = relics,
			key = "id",
			selection = selection,
			selectionMode = "single",
			itemSize = 96,
			measure = true,
			autoFocus = false,
			focusPolicy = "key",
			Size = UDim2.fromScale(1, 1),
			onActivate = function()
				column:set("detail")
			end,
			render = function(current)
				return UI.Card "RelicCard" {
					title = function(use: Facet.Use)
						return (if use(selection)[use(current).id] then "Selected: " else "") .. use(current).name
					end,
					caption = function(use: Facet.Use)
						return use(current).subtitle
					end,
				}
			end,
			UI.fill(),
		}
		local panes: Facet.NavigationSplitViewProps = {
			Parent = C.static(taskBody),
			preferredCompactColumn = column,
			compactBack = back,
			detailLabel = false,
			resizable = false,
			compactWidth = 1000,
			compactHeight = 500,
			minSidebarWidth = 220,
			maxSidebarWidth = 300,
			minDetailWidth = 500,
			sidebar = function(): Instance
				return UI.ZStack "BrowseBody" {
					width = "fill",
					height = "fill",
					alignH = "center",
					UI.VStack "Collection" {
						width = "fill",
						maxWidth = 520,
						height = "fill",
						padding = "s",
						UI.VirtualList "Relics"(list),
					},
				}
			end,
			detail = function(): Instance
				local body = UI.ZStack "InspectionBody" {
					width = "fill",
					height = "fill",
					alignH = "center",
					alignV = "center",
					UI.fill(),
				}
				local room = UI.environment(body)
				local sideBySide = C.formula(function(use: Facet.Use): boolean
					return use(room.viewportWidth) >= 560
				end)
				UI.ZStack "InspectionContent" {
					Parent = C.static(body),
					width = "fill",
					height = "fill",
					alignH = "center",
					alignV = "center",
					C.show(sideBySide, function()
						return UI.HStack "SubjectAndDecision" {
							width = "fill",
							maxWidth = 960,
							height = function(use: Facet.Use): number
								return math.max(0, use(room.viewportHeight))
							end,
							gap = "m",
							padding = "s",
							align = "stretch",
							UI.ZStack "Subject" { width = "fill", height = "fill", UI.fill(), subject() },
							UI.ScrollView "DecisionScroll" {
								width = function(use: Facet.Use): number
									return if use(room.viewportWidth) < 800 then 280 else 340
								end,
								height = "fill",
								gap = "s",
								padding = "s",
								decision(),
							},
						}
					end, function()
						return UI.ScrollView "PortraitInspection" {
							width = "fill",
							maxWidth = 520,
							height = "fill",
							gap = "s",
							padding = "s",
							UI.ZStack "Subject" {
								width = "fill",
								height = function(use: Facet.Use): number
									return math.max(144, math.min(230, use(room.viewportHeight) * 0.36))
								end,
								subject(),
							},
							decision(),
						}
					end),
				}
				return body
			end,
			UI.fill(),
		}
		UI.NavigationSplitView "RelicPanes"(panes)
		local close: GuiObject = UI.Button {
			label = "Close",
			appearance = "utility",
			onActivate = function()
				callbacks.close()
			end,
		}
		local navigation: Facet.NavBarSpec = {
			title = "Field Station / Relics",
			titleSize = "heading",
			onBack = back,
			trailing = close,
		}
		local canvas = UI.ZStack "ArchiveCanvas" {
			width = "fill",
			height = "fill",
			UI.fill(),
		}
		local room = UI.environment(canvas)
		UI.VStack "ArchivePanel" {
			Parent = C.static(canvas),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			width = "fill",
			maxWidth = 1240,
			height = function(use: Facet.Use): number
				return math.max(0, math.min(720, use(room.viewportHeight)))
			end,
			surface = "surface",
			padding = "s",
			gap = 0,
			UI.NavBar(navigation),
			taskBody,
		}
		return UI.Screen "RelicInspection" { padding = "m", canvas }
	end,
}
