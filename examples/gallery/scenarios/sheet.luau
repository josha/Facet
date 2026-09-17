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
		local Facet, UI = ctx.Facet, ctx.Facet.View
		local copy = ctx.copy or COPY
		local detent, setDetent, membership, setMembership, status, setStatus, presented, setPresented
		local function open()
			setPresented(true)
			return true
		end
		local function close()
			setPresented(false)
		end
		local function reset()
			close()
			setDetent("medium")
			setMembership(false)
			setStatus(copy.status)
		end
		local Briefing = Facet.component(function(ui)
			detent, setDetent = ui.state("medium")
			membership, setMembership = ui.state(false)
			status, setStatus = ui.state(copy.status)
			presented, setPresented = ui.state(false)
			return UI.Screen({
				id = "Sheet",
				padding = "m",
				UI.ScrollView({
					id = "Page",
					width = UI.fill(),
					height = UI.fill(),
					gap = "m",
					UI.Text({ text = copy.title, textSize = "title" }),
					UI.Text({ text = copy.intro, width = UI.fill() }),
					UI.Text({ id = "Status", text = status, width = UI.fill() }),
					UI.Button({ id = "Open", label = copy.open, onActivate = open }),
				}),
				UI.Sheet({
					id = "Briefing",
					title = copy.briefing,
					isPresented = presented,
					onPresentedChange = setPresented,
					detent = detent,
					onDetentChange = setDetent,
					detents = { { id = "compact", fraction = 0.35 }, "medium", "large" },
					content = UI.VStack({
						id = "Details",
						width = UI.fill(),
						gap = "m",
						UI.Text({ id = "Description", text = copy.description, width = UI.fill() }),
						UI.Text({
							text = "Weather: clear skies. Surface: dry. Recommended tires: sport.",
							width = UI.fill(),
						}),
						UI.Toggle({
							id = "Membership",
							label = copy.join,
							value = membership,
							onChange = setMembership,
						}),
						UI.Text({
							text = "The first corner tightens as you exit. Leave room for the next driver, then accelerate toward the harbor straight.",
							width = UI.fill(),
						}),
						UI.Button({
							id = "Start",
							label = copy.start,
							width = UI.fill(),
							onActivate = function()
								setStatus("Practice started.")
								close()
							end,
						}),
					}),
				}),
			})
		end)
		return {
			screen = Briefing({}),
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
					sheet = { presented = presented(), detent = detent() },
					membership = membership(),
					status = status(),
				}
			end,
			dispose = function() end,
		}
	end,
}
