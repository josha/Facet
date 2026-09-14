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
		local Facet, core = ctx.Facet, ctx.core
		local UI = Facet.UI
		local copy = ctx.copy or COPY
		local scope = core:scope("sheet-demo")
		local detent = scope:own(core:signal("medium"))
		local membership = scope:own(core:signal(false))
		local status = scope:own(core:signal(copy.status))
		local sheet
		sheet = scope:own(Facet.Controls.Sheet(core, {
			id = "Briefing",
			title = copy.briefing,
			detent = detent,
			detents = { { id = "compact", fraction = 0.35 }, "medium", "large" },
			content = UI.VStack({
				id = "Details",
				width = UI.fill(),
				gap = "m",
				children = {
					UI.Text({ id = "Description", text = copy.description, width = UI.fill() }),
					UI.Text({
						text = "Weather: clear skies. Surface: dry. Recommended tires: sport.",
						width = UI.fill(),
					}),
					UI.Toggle({ id = "Membership", label = copy.join, value = membership }),
					UI.Text({
						text = "The first corner tightens as you exit. Leave room for the next driver, then accelerate toward the harbor straight.",
						width = UI.fill(),
					}),
					UI.Button({
						id = "Start",
						label = copy.start,
						width = UI.fill(),
						onActivate = function()
							status:set("Practice started.")
							sheet.dismiss()
						end,
					}),
				},
			}),
		}))
		local function open()
			if ctx.presenter then
				sheet.present(ctx.presenter)
				return true
			end
			return false
		end
		local function reset()
			sheet.dismiss()
			detent:set("medium")
			membership:set(false)
			status:set(copy.status)
		end
		return {
			screen = UI.Screen({
				id = "Sheet",
				padding = "m",
				children = {
					UI.ScrollView({
						id = "Page",
						width = UI.fill(),
						height = UI.fill(),
						gap = "m",
						children = {
							UI.Text({ text = copy.title, textSize = "title" }),
							UI.Text({ text = copy.intro, width = UI.fill() }),
							UI.Text({ id = "Status", text = status, width = UI.fill() }),
							UI.Button({ id = "Open", label = copy.open, onActivate = open }),
						},
					}),
				},
			}),
			steps = {
				open = open,
				medium = function()
					detent:set("medium")
				end,
				large = function()
					detent:set("large")
				end,
				close = function()
					sheet.dismiss()
				end,
				reset = reset,
			},
			states = function()
				return {
					{ id = "medium", kind = "dialog", open = open },
					{
						id = "large",
						kind = "dialog",
						open = function()
							detent:set("large")
							return open()
						end,
					},
				}
			end,
			report = function()
				return { sheet = sheet.dump(), membership = membership:get(), status = status:get() }
			end,
			dispose = function()
				scope:dispose()
			end,
		}
	end,
}
