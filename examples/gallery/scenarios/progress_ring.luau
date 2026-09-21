--!strict
-- Activity indicators inherit the mounted view's owner and presenter clock.
-- Path2D is not clipped by Roblox ClipsDescendants; this fixture also exposes
-- that engine limitation when a circular indicator scrolls out of the viewport.
local COPY = {
	title = "Progress and activity",
	caption = "Adjust progress to compare the bar and ring. Activity indicators keep moving while work is running.",
	determinate = "Downloading",
	indeterminate = "Working",
	spinner = "Spinner (dots)",
	bar = "Download progress",
	adjust = "Adjust progress",
}

return {
	title = "Progress and activity",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local progress = Compose.cell(0.25)
		local placeholders = require("./skeleton").build(ctx)
		local function percent(v)
			return string.format("%d%%", math.floor(v * 100 + 0.5))
		end
		local function screen()
			return UI.Screen("ProgressRing")({
				padding = "m",
				UI.ScrollView("Page")({
					axis = "y",
					gap = "s",
					width = UI.fill(),
					height = UI.fill(),
					UI.Text("Title")({ text = COPY.title, textSize = "heading" }),
					UI.Text("Caption")({ text = COPY.caption, textSize = "caption", role = "secondary" }),
					UI.Text({ text = COPY.adjust, width = UI.fill() }),
					UI.Slider("AdjustProgress")({
						value = progress,
						min = 0,
						max = 1,
						step = 0.05,
					}),
					UI.Text({ text = COPY.bar, width = UI.fill() }),
					UI.ProgressView("Bar")({
						value = progress,
						showValue = true,
						format = percent,
						segments = 5,
						trail = { delay = 0.3, duration = 0.35 },
					}),
					UI.ProgressView("Ring")({
						label = COPY.determinate,
						value = progress,
						presentation = "circular",
						diameter = 120,
						showValue = true,
						format = percent,
					}),
					UI.ProgressView("Busy")({ label = COPY.indeterminate, presentation = "circular" }),
					UI.ProgressView("Dots")({ label = COPY.spinner, presentation = "spinner" }),
					placeholders.section(),
				}),
			})
		end
		local function report()
			local value = progress:peek()
			return { progress = value, fraction = value, reduced = ctx.presenter.motionClock:isReduced() }
		end
		local function setProgress(value)
			progress:set(math.clamp(value, 0, 1))
			return report()
		end
		return {
			screen = screen,
			present = {},
			steps = {
				setProgress10 = function()
					return setProgress(0.10)
				end,
				setProgress65 = function()
					return setProgress(0.65)
				end,
				setProgress100 = function()
					return setProgress(1)
				end,
				advance = function(_built, payload)
					local frames = tonumber(payload or "") or 30
					for _ = 1, math.clamp(math.floor(frames), 1, 600) do
						ctx.presenter.tick(1 / 60)
					end
					return report()
				end,
			},
			report = report,
		}
	end,
}
