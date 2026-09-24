--!strict
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
	build = function(ctx)
		local UI, Compose = ctx.UI, ctx.Compose
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
			return UI.Screen("Sheet")({
				padding = "m",
				UI.ScrollView("Page")({
					width = UI.fill(),
					height = UI.fill(),
					gap = "m",
					UI.Text({ text = copy.title, textSize = "title" }),
					UI.Text({ text = copy.intro, width = UI.fill() }),
					UI.Text("Status")({ text = status, width = UI.fill() }),
					UI.Button("Open")({ label = copy.open, onActivate = open }),
					UI.Button("OpenLobby")({
						label = copy.openLobby,
						onActivate = function()
							lobbyShown:set(true)
						end,
					}),
					UI.Button("OpenFilters")({
						label = copy.openFilters,
						onActivate = function()
							filtersShown:set(true)
						end,
					}),
				}),
				-- fits its content, a scrolling authored hero under the Close and
				-- Size controls, pinned actions, and a body that hands its pan to
				-- the sheet below the tallest detent
				UI.Sheet("Lobby")({
					title = copy.lobby,
					header = false,
					isPresented = lobbyShown,
					detent = lobbyDetent,
					detents = { "hug", "large" },
					scrollPolicy = "atLargestDetent",
					hero = {
						height = 140,
						background = { role = "accent", blend = 1 },
						content = UI.VStack("Banner")({
							width = UI.fill(),
							padding = "m",
							UI.Text({ text = copy.lobby, textSize = "title", width = UI.fill() }),
						}),
					},
					content = function()
						return UI.Text("LobbyBody")({ text = copy.lobbyBody, width = UI.fill() })
					end,
					actions = {
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
					},
				}),
				UI.Sheet("Filters")({
					title = copy.filters,
					placement = "side",
					width = "narrow",
					isPresented = filtersShown,
					detent = filtersDetent,
					detents = { "medium", "large" },
					content = function()
						return UI.VStack("FilterList")({
							width = UI.fill(),
							gap = "m",
							UI.Text({ text = copy.filtersBody, width = UI.fill() }),
							UI.Toggle("Night")({ label = "Night races only", value = nightOnly }),
							UI.HStack({
								gap = "s",
								UI.Button("Clear")({
									label = copy.clear,
									onActivate = function()
										nightOnly:set(false)
									end,
								}),
								UI.Button("Apply")({
									label = copy.apply,
									onActivate = function()
										filtersShown:set(false)
									end,
								}),
							}),
						})
					end,
				}),
				UI.Sheet("Briefing")({
					title = copy.briefing,
					isPresented = presented,
					detent = detent,
					detents = { { id = "compact", fraction = 0.35 }, "medium", "large" },
					content = function()
						return UI.VStack("Details")({
							width = UI.fill(),
							gap = "m",
							UI.Text("Description")({ text = copy.description, width = UI.fill() }),
							UI.Text({
								text = "Weather: clear skies. Surface: dry. Recommended tires: sport.",
								width = UI.fill(),
							}),
							UI.Toggle("Membership")({ label = copy.join, value = membership }),
							UI.Text({
								text = "The first corner tightens as you exit. Leave room for the next driver, then accelerate toward the harbor straight.",
								width = UI.fill(),
							}),
							UI.Button("Start")({
								label = copy.start,
								width = UI.fill(),
								onActivate = function()
									status:set("Practice started.")
									close()
								end,
							}),
						})
					end,
				}),
			})
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
					{
						id = "lobby",
						kind = "dialog",
						open = function()
							lobbyShown:set(true)
							return true
						end,
					},
					{
						id = "filters",
						kind = "dialog",
						open = function()
							filtersShown:set(true)
							return true
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
			-- nothing outlives the screen
			dispose = function() end,
		}
	end,
}
