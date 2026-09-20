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
					membership = membership:peek(),
					status = status:peek(),
				}
			end,
			-- nothing outlives the screen
			dispose = function() end,
		}
	end,
}
