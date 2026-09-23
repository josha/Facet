--!strict
--[[ Scenario 'overlays' — content that appears on request, next to what it is
	about: a Popover whose open state the screen owns (one caller accepts every
	close, one refuses until a switch allows it), a Popover against a source path
	instead of a trigger, a rich coach mark, the structured `help` form and a long
	menu that scrolls inside its own bound. Every piece is reachable by pointer,
	touch, keyboard and gamepad; the words are printed as well as helped. ]]

local COPY = {
	title = "Overlays on request",
	intro = "These surfaces open only when asked. The screen owns whether a popover is open: it can accept or refuse every close.",
	about = "About scoring",
	aboutBody = "Laps score by finishing position and clean overtakes.",
	aboutHelpTitle = "Scoring",
	aboutHelp = "Opens how laps are scored.",
	locked = "Locked details",
	lockedBody = "This popover stays open until the switch below allows closing.",
	allow = "Allow closing",
	close = "Close",
	sourceRow = "Next race: Coastal loop",
	sourceShow = "Explain the next race",
	sourceBody = "A short coastal circuit with two hairpins.",
	coach = "Show the tour",
	coachTitle = "Welcome to the garage",
	coachBody = "Tune your car here before a race.",
	coachGo = "Show me",
	coachLater = "Later",
	menu = "All tracks",
	recent = "Recent",
	everything = "Everything",
	status = "Last: nothing yet",
}

local ART = "rbxassetid://75342910516929"

return {
	title = "Overlays",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local aboutOpen = Compose.cell(false)
		local lockedOpen = Compose.cell(false)
		local allowClose = Compose.cell(false)
		local sourceOpen = Compose.cell(false)
		local tourAsked = Compose.cell(false)
		local status = Compose.cell(COPY.status)
		local tour: any = nil

		local function note(text: string)
			status:set(text)
		end

		local function reset()
			aboutOpen:set(false)
			lockedOpen:set(false)
			allowClose:set(false)
			sourceOpen:set(false)
			tourAsked:set(false)
			status:set(COPY.status)
			-- a new session: the retired coach mark may be shown again
			if tour ~= nil then
				tour.rearm()
			end
		end

		local function tracks(): { any }
			local items: { any } = {}
			for i = 1, 16 do
				table.insert(items, {
					id = `track{i}`,
					label = `Track {i}`,
					badge = if i <= 2 then "New" else nil,
					sectionTitle = if i == 1 then COPY.recent elseif i == 3 then COPY.everything else nil,
					shortcutLabel = if i == 1 then "Ctrl+1" else nil,
					onSelect = function()
						note(`Last: Track {i}`)
					end,
				})
			end
			return items
		end

		local function screen()
			return UI.Screen("Overlays")({
				surface = "base",
				padding = { top = "m", bottom = "m" },
				UI.ScrollView("Content")({
					width = UI.fill(),
					height = UI.fill(),
					padding = { left = "m", right = "m" },
					UI.VStack("Sections")({
						width = UI.fill(),
						gap = "l",
						UI.Text("Title")({ text = COPY.title, textSize = "title", width = UI.fill() }),
						UI.Text("Intro")({ text = COPY.intro, width = UI.fill() }),
						UI.Text("Status")({ text = status, width = UI.fill() }),
						UI.Button("Reset")({ label = "Reset", onActivate = reset }),
						-- an accepting caller, with the structured help form on its trigger
						UI.Popover("About")({
							isPresented = aboutOpen,
							onPresentedChange = function(next: boolean)
								aboutOpen:set(next)
							end,
							onDismiss = function(reason: string)
								note(`Last: about closed ({reason})`)
							end,
							trigger = UI.Button("AboutButton")({
								label = COPY.about,
								help = { title = COPY.aboutHelpTitle, body = COPY.aboutHelp, shortcut = { { "F1" } } },
							}),
							maxWidth = 320,
							content = function()
								return UI.Text("Body")({ text = COPY.aboutBody, width = UI.fill() })
							end,
						}),
						UI.Text("AboutHelpPrinted")({ text = COPY.aboutHelp, role = "secondary", width = UI.fill() }),
						-- a refusing caller: the switch decides whether a close is accepted
						UI.Popover("Locked")({
							isPresented = lockedOpen,
							onPresentedChange = function(next: boolean)
								if next or allowClose:peek() then
									lockedOpen:set(next)
								else
									note("Last: close refused")
								end
							end,
							trigger = UI.Button("LockedButton")({ label = COPY.locked }),
							content = function()
								return UI.VStack("Body")({
									gap = "s",
									UI.Text("Line")({ text = COPY.lockedBody, width = UI.fill() }),
									UI.Toggle("Allow")({ label = COPY.allow, value = allowClose }),
									UI.Button("Close")({
										label = COPY.close,
										onActivate = function()
											if allowClose:peek() then
												lockedOpen:set(false)
											end
										end,
									}),
								})
							end,
						}),
						-- a source popover: the row is the anchor, a separate button asks
						UI.Text("SourceRow")({ text = COPY.sourceRow, width = UI.fill() }),
						UI.Button("SourceButton")({
							label = COPY.sourceShow,
							onActivate = function()
								sourceOpen:set(not sourceOpen:peek())
							end,
						}),
						UI.Popover("Source")({
							isPresented = sourceOpen,
							onPresentedChange = function(next: boolean)
								sourceOpen:set(next)
							end,
							source = { path = "/Overlays/Content/Sections/SourceRow" },
							edge = "bottom",
							align = "start",
							content = function()
								return UI.Text("Body")({ text = COPY.sourceBody, width = UI.fill() })
							end,
						}),
						-- a rich coach mark: title, media, steps and two actions
						UI.Callout("Tour")({
							anchor = UI.Button("TourButton")({
								label = COPY.coach,
								onActivate = function()
									tourAsked:set(true)
								end,
							}),
							isPresented = tourAsked,
							title = COPY.coachTitle,
							media = { image = ART, aspectRatio = 2, scaleMode = "crop" },
							content = UI.Text("Body")({ text = COPY.coachBody, width = UI.fill() }),
							steps = { index = 1, count = 3 },
							closeButton = true,
							actions = {
								{
									id = "Later",
									label = COPY.coachLater,
									onActivate = function()
										note("Last: tour later")
									end,
								},
								{
									id = "Go",
									label = COPY.coachGo,
									role = "default",
									onActivate = function()
										note("Last: tour started")
									end,
								},
							},
							ref = function(record: any)
								tour = record.api
							end,
							onRetire = function(reason: string)
								tourAsked:set(false)
								note(`Last: tour retired ({reason})`)
							end,
						}),
						-- a long menu bounded to a height, with the shared row words
						UI.Menu("Tracks")({
							label = COPY.menu,
							maxHeight = 280,
							items = tracks(),
						}),
					}),
				}),
			})
		end

		return {
			screen = screen,
			reset = reset,
			steps = {
				reset = reset,
				openAbout = function()
					aboutOpen:set(true)
				end,
				openSource = function()
					sourceOpen:set(true)
				end,
			},
		}
	end,
}
