--!strict

local COPY = {
	title = "Overlays on request",
	intro = "These surfaces open only when asked. The screen owns whether a popover or a dialog is open: it can accept or refuse every close.",
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
	coachDone = "Done",
	coachLater = "Later",
	status = "Last: nothing yet",
	dialog = "Leave the race",
	dialogTitle = "Leave the race?",
	dialogBody = "Your lap will not count, and your place in the grid goes to the next driver. You can rejoin from the lobby at any time.",
	dialogLabel = "Leaving now forfeits this heat.",
	stay = "Stay",
	leave = "Leave",
	lockedDialog = "Terms of the league",
	lockedDialogTitle = "League terms",
	accept = "I have read the terms",
	search = "Search tracks",
	filter = "Filter",
	reset = "Reset",
}

local ART = "rbxassetid://75342910516929"
local TOUR_STEPS = 3

return {
	title = "Overlays",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local UI, Compose, Host = ctx.UI, ctx.Compose, ctx.Host
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Enum = Enum }
		local UDim, UDim2, Enum = nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Enum
		local aboutOpen = Compose.cell(false)
		local lockedOpen = Compose.cell(false)
		local allowClose = Compose.cell(false)
		local sourceOpen = Compose.cell(false)
		local tourAsked = Compose.cell(false)
		local tourStep = Compose.cell(1)
		local tourSession = Compose.cell(1)
		local dialogOpen = Compose.cell(false)
		local termsOpen = Compose.cell(false)
		local termsRead = Compose.cell(false)
		local query = Compose.cell("")
		local status = Compose.cell(COPY.status)
		local advancing = false

		local function note(text: string)
			status:set(text)
		end

		local function reset()
			aboutOpen:set(false)
			lockedOpen:set(false)
			allowClose:set(false)
			sourceOpen:set(false)
			tourAsked:set(false)
			tourStep:set(1)
			tourSession:set(tourSession:peek() + 1)
			dialogOpen:set(false)
			termsOpen:set(false)
			termsRead:set(false)
			query:set("")
			status:set(COPY.status)
		end

		local function label(name: string, text: any, order: number, role: string?): any
			return UI.Label({
				Name = name,
				LayoutOrder = order,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Text = text,
				textRole = role,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end

		local function body(text: string): () -> any
			return function()
				return label("Body", text, 1)
			end
		end

		local function tour(anchor: any): any
			return Compose.keyed({
				from = function(use: any)
					return { `{use(tourSession)}:{use(tourStep)}` }
				end,
				render = function()
					local step = tourStep:peek()
					return UI.Callout({
						Name = if step == 1 then "Tour" else `Tour{step}`,
						anchor = anchor,
						isPresented = tourAsked,
						title = COPY.coachTitle,
						media = { image = ART, aspectRatio = 2, scaleMode = "crop" },
						content = body(COPY.coachBody),
						steps = { index = step, count = TOUR_STEPS },
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
								label = if step < TOUR_STEPS then COPY.coachGo else COPY.coachDone,
								role = "default",
								onActivate = function()
									if step < TOUR_STEPS then
										advancing = true
										note(`Last: tour step {step + 1} of {TOUR_STEPS}`)
									else
										note("Last: tour finished")
									end
								end,
							},
						},
						onRetire = function(reason: string)
							if advancing then
								advancing = false
								tourStep:set(step + 1)
								return
							end
							tourAsked:set(false)
							if reason ~= "action" then
								note(`Last: tour retired ({reason})`)
							end
						end,
					})
				end,
			})
		end

		local function screen()
			local tourButton = UI.Button "TourButton" {
				label = COPY.coach,
				onActivate = function()
					tourAsked:set(true)
				end,
			}
			local sourceRow = label("SourceRow", COPY.sourceRow, 8)
			return Host.Frame "Overlays" {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Host.UIPadding({
					PaddingTop = UDim.new(0, 16),
					PaddingBottom = UDim.new(0, 16),
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
				}),
				Host.ScrollingFrame "Content" {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					CanvasSize = UDim2.new(),
					ScrollBarThickness = 6,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 16),
					}),
					label("Title", COPY.title, 1, "title"),
					label("Intro", COPY.intro, 2),
					label("Status", status, 3),
					UI.Button "Reset" { LayoutOrder = 4, label = COPY.reset, onActivate = reset },
					UI.NavBar "Header" {
						LayoutOrder = 5,
						center = UI.TextInput "Search" { value = query, placeholder = COPY.search },
						trailing = UI.Button "Filter" { label = COPY.filter, icon = "menu" },
					},
					UI.Popover "About" {
						LayoutOrder = 6,
						isPresented = aboutOpen,
						onPresentedChange = function(nextValue: boolean)
							aboutOpen:set(nextValue)
						end,
						onDismiss = function(reason: string)
							note(`Last: about closed ({reason})`)
						end,
						trigger = UI.Button "AboutButton" {
							label = COPY.about,
							help = { title = COPY.aboutHelpTitle, body = COPY.aboutHelp, shortcut = { { "F1" } } },
						},
						maxWidth = 320,
						content = body(COPY.aboutBody),
					},
					label("AboutHelpPrinted", COPY.aboutHelp, 7, "caption"),
					UI.Popover "Locked" {
						LayoutOrder = 9,
						isPresented = lockedOpen,
						onPresentedChange = function(nextValue: boolean)
							if nextValue or allowClose:peek() then
								lockedOpen:set(nextValue)
							else
								note("Last: close refused")
							end
						end,
						trigger = UI.Button "LockedButton" { label = COPY.locked },
						content = function()
							return Host.Frame "Body" {
								BackgroundTransparency = 1,
								Size = UDim2.fromOffset(280, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								Host.UIListLayout({
									FillDirection = Enum.FillDirection.Vertical,
									SortOrder = Enum.SortOrder.LayoutOrder,
									Padding = UDim.new(0, 8),
								}),
								label("Line", COPY.lockedBody, 1),
								UI.Toggle "Allow" { LayoutOrder = 2, label = COPY.allow, value = allowClose },
								UI.Button "Close" {
									LayoutOrder = 3,
									label = COPY.close,
									onActivate = function()
										if allowClose:peek() then
											lockedOpen:set(false)
										end
									end,
								},
							}
						end,
					},
					sourceRow,
					UI.Button "SourceButton" {
						LayoutOrder = 10,
						label = COPY.sourceShow,
						onActivate = function()
							sourceOpen:set(not sourceOpen:peek())
						end,
					},
					UI.Popover "Source" {
						isPresented = sourceOpen,
						onPresentedChange = function(nextValue: boolean)
							sourceOpen:set(nextValue)
						end,
						source = { node = sourceRow },
						edge = "bottom",
						align = "start",
						content = body(COPY.sourceBody),
					},
					Host.Frame "TourRow" {
						LayoutOrder = 11,
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Host.UIListLayout({
							FillDirection = Enum.FillDirection.Horizontal,
							SortOrder = Enum.SortOrder.LayoutOrder,
						}),
						tourButton,
						tour(tourButton),
					},
					UI.Button "DialogButton" {
						LayoutOrder = 12,
						label = COPY.dialog,
						onActivate = function()
							dialogOpen:set(true)
						end,
					},
					UI.Dialog "Leave" {
						isPresented = dialogOpen,
						onPresentedChange = function(nextValue: boolean)
							dialogOpen:set(nextValue)
						end,
						onDismiss = function(reason: string)
							note(`Last: dialog closed ({reason})`)
						end,
						hero = { image = ART, aspectRatio = 2, scaleMode = "crop" },
						title = COPY.dialogTitle,
						content = body(COPY.dialogBody),
						actionLabel = COPY.dialogLabel,
						actions = {
							{
								id = "Stay",
								label = COPY.stay,
								role = "cancel",
								onActivate = function()
									dialogOpen:set(false)
								end,
							},
							{
								id = "Leave",
								label = COPY.leave,
								role = "destructive",
								onActivate = function()
									note("Last: left the race")
									dialogOpen:set(false)
								end,
							},
						},
					},
					UI.Button "TermsButton" {
						LayoutOrder = 13,
						label = COPY.lockedDialog,
						onActivate = function()
							termsOpen:set(true)
						end,
					},
					UI.Dialog "Terms" {
						isPresented = termsOpen,
						onPresentedChange = function(nextValue: boolean)
							if nextValue or termsRead:peek() then
								termsOpen:set(nextValue)
							else
								note("Last: close refused")
							end
						end,
						onDismiss = function(reason: string)
							note(`Last: terms closed ({reason})`)
						end,
						title = COPY.lockedDialogTitle,
						width = "narrow",
						content = function()
							return UI.Toggle "Read" { label = COPY.accept, value = termsRead }
						end,
					},
				},
			}
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
				openDialog = function()
					dialogOpen:set(true)
				end,
				tour = function()
					tourAsked:set(true)
				end,
			},
			report = function()
				return {
					about = aboutOpen:peek(),
					locked = lockedOpen:peek(),
					source = sourceOpen:peek(),
					tour = tourAsked:peek(),
					step = tourStep:peek(),
					dialog = dialogOpen:peek(),
					terms = termsOpen:peek(),
					status = status:peek(),
				}
			end,
		}
	end,
}
