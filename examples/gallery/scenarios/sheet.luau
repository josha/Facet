--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type SheetDetent = typeof(require("@repo/tools/typecheck/aliases").SheetDetent)
type OverlayAction = typeof(require("@repo/tools/typecheck/aliases").OverlayAction)
type ExampleContext = typeof(require("@repo/examples/types").Context)
local COPY = {
	title = "Detent sheets",
	intro = "Open a race briefing. Drag its header to resize, or focus Size and use Left / Right. On a distant screen the panel moves to the center.",
	open = "Open race briefing",
	briefing = "Coastal circuit",
	description = "Three laps along the harbor, through the old town, and back to the starting grid. Resize this briefing to see more while keeping the track in view.",
	join = "Join the club event",
	start = "Start practice",
	status = "Ready for practice.",
	openLobby = "Open lobby",
	lobby = "Harbor sprint lobby",
	lobbyBody = "Eight drivers, three laps. The grid fills in joining order; the host starts the countdown once everyone is ready.",
	joinLobby = "Join lobby",
	notNow = "Not now",
	openFilters = "Filters",
	filters = "Race filters",
	filtersBody = "Show only races that match these settings.",
	apply = "Apply",
	clear = "Clear",
}
return {
	title = "Detent sheets",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: ExampleContext)
		local UI, Compose: ComposeModule = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local nativeTypes = ctx.types
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local copy = ctx.copy or COPY
		local detent = Compose.cell("medium")
		local membership = Compose.cell(false)
		local status = Compose.cell(copy.status)
		local presented = Compose.cell(false)
		local lobbyShown, lobbyDetent = Compose.cell(false), Compose.cell("hug")
		local filtersShown, filtersDetent = Compose.cell(false), Compose.cell("large")
		local nightOnly = Compose.cell(false)
		local function open()
			presented:set(true)
			return true
		end
		local function close()
			presented:set(false)
		end
		local function setDetent(value)
			detent:set(value)
		end
		local function reset()
			close()
			detent:set("medium")
			membership:set(false)
			status:set(copy.status)
			lobbyShown:set(false)
			lobbyDetent:set("hug")
			filtersShown:set(false)
			nightOnly:set(false)
		end
		local function Briefing()
			local banner: Instance = UI.Text "Banner" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				text = copy.lobby,
				textRole = "title",
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			}
			local lobbyDetents: { SheetDetent } = { "hug", "large" }
			local lobbyActions: { OverlayAction } = {
				{
					id = "NotNow",
					label = copy.notNow,
					role = "cancel",
					onActivate = function()
						lobbyShown:set(false)
					end,
				},
				{
					id = "Join",
					label = copy.joinLobby,
					role = "default",
					onActivate = function()
						status:set("Joined the harbor sprint.")
						lobbyShown:set(false)
					end,
				},
			}
			local filterDetents: { SheetDetent } = { "medium", "large" }
			local briefingDetents: { SheetDetent } = { { id = "compact", fraction = 0.35 }, "medium", "large" }
			return Host.Frame "Sheet" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				UI.ScrollView "Page" {
					padding = 16,
					gap = 16,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					ScrollBarThickness = 6,
					UI.Text {
						LayoutOrder = 1,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = copy.title,
						textRole = "title",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
					UI.Text {
						LayoutOrder = 2,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = copy.intro,
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
					UI.Text "Status" {
						LayoutOrder = 3,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = status,
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
					UI.Button "Open" {
						LayoutOrder = 4,
						label = copy.open,
						onActivate = function()
							open()
						end,
					},
					UI.Button "OpenLobby" {
						LayoutOrder = 5,
						label = copy.openLobby,
						onActivate = function()
							lobbyShown:set(true)
						end,
					},
					UI.Button "OpenFilters" {
						LayoutOrder = 6,
						label = copy.openFilters,
						onActivate = function()
							filtersShown:set(true)
						end,
					},
				},
				UI.Sheet "Lobby" {
					title = copy.lobby,
					header = false,
					isPresented = lobbyShown,
					detent = lobbyDetent,
					detents = lobbyDetents,
					scrollPolicy = "atLargestDetent",
					hero = {
						height = 140,
						background = Color3.fromRGB(44, 98, 210),
						content = banner,
					},
					content = function(): Instance
						return UI.Text "LobbyBody" {
							BackgroundTransparency = 1,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							text = copy.lobbyBody,
							TextWrapped = true,
							TextXAlignment = Enum.TextXAlignment.Left,
						}
					end,
					actions = lobbyActions,
				},
				UI.Sheet "Filters" {
					title = copy.filters,
					placement = "side",
					width = "narrow",
					isPresented = filtersShown,
					detent = filtersDetent,
					detents = filterDetents,
					content = function(): Instance
						return Host.Frame "FilterList" {
							BackgroundTransparency = 1,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							Host.UIListLayout {
								FillDirection = Enum.FillDirection.Vertical,
								SortOrder = Enum.SortOrder.LayoutOrder,
								Padding = UDim.new(0, 16),
							},
							UI.Text {
								LayoutOrder = 1,
								BackgroundTransparency = 1,
								Size = UDim2.new(1, 0, 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								text = copy.filtersBody,
								TextWrapped = true,
								TextXAlignment = Enum.TextXAlignment.Left,
							},
							UI.Toggle "Night" {
								LayoutOrder = 2,
								label = "Night races only",
								value = nightOnly,
							},
							UI.Button "Clear" {
								LayoutOrder = 3,
								label = copy.clear,
								onActivate = function()
									nightOnly:set(false)
								end,
							},
							UI.Button "Apply" {
								LayoutOrder = 4,
								label = copy.apply,
								onActivate = function()
									filtersShown:set(false)
								end,
							},
						}
					end,
				},
				UI.Sheet "Briefing" {
					title = copy.briefing,
					isPresented = presented,
					detent = detent,
					detents = briefingDetents,
					content = function(): Instance
						return Host.Frame "Details" {
							BackgroundTransparency = 1,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							Host.UIListLayout {
								FillDirection = Enum.FillDirection.Vertical,
								SortOrder = Enum.SortOrder.LayoutOrder,
								Padding = UDim.new(0, 16),
							},
							UI.Text "Description" {
								LayoutOrder = 1,
								BackgroundTransparency = 1,
								BorderSizePixel = 0,
								Size = UDim2.new(1, 0, 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								text = copy.description,
								TextWrapped = true,
								TextYAlignment = Enum.TextYAlignment.Top,
								TextXAlignment = Enum.TextXAlignment.Left,
							},
							UI.Text {
								LayoutOrder = 2,
								BackgroundTransparency = 1,
								BorderSizePixel = 0,
								Size = UDim2.new(1, 0, 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								text = "Weather: clear skies. Surface: dry. Recommended tires: sport.",
								TextWrapped = true,
								TextYAlignment = Enum.TextYAlignment.Top,
								TextXAlignment = Enum.TextXAlignment.Left,
							},
							UI.Toggle "Membership" {
								LayoutOrder = 3,
								label = copy.join,
								value = membership,
							},
							UI.Text {
								LayoutOrder = 4,
								BackgroundTransparency = 1,
								BorderSizePixel = 0,
								Size = UDim2.new(1, 0, 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								text = "The first corner tightens as you exit. Leave room for the next driver, then accelerate toward the harbor straight.",
								TextWrapped = true,
								TextYAlignment = Enum.TextYAlignment.Top,
								TextXAlignment = Enum.TextXAlignment.Left,
							},
							UI.Button "Start" {
								LayoutOrder = 5,
								Size = UDim2.new(1, 0, 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								label = copy.start,
								onActivate = function()
									status:set("Practice started.")
									close()
								end,
							},
						}
					end,
				},
			}
		end
		return {
			screen = Briefing,
			steps = {
				open = open,
				close = close,
				reset = reset,
				medium = function()
					setDetent("medium")
				end,
				large = function()
					setDetent("large")
				end,
				lobby = function()
					lobbyShown:set(true)
				end,
				filters = function()
					filtersShown:set(true)
				end,
			},
			states = function()
				return {
					{ id = "medium", kind = "dialog", open = open },
					{
						id = "large",
						kind = "dialog",
						open = function()
							setDetent("large")
							return open()
						end,
					},
				}
			end,
			report = function()
				return {
					sheet = { presented = presented:peek(), detent = detent:peek() },
					lobby = { presented = lobbyShown:peek(), detent = lobbyDetent:peek() },
					filters = { presented = filtersShown:peek(), nightOnly = nightOnly:peek() },
					membership = membership:peek(),
					status = status:peek(),
				}
			end,

			dispose = function() end,
		}
	end,
}
