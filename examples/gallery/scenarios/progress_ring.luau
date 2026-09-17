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
		local Facet, UI = ctx.Facet, ctx.Facet.View
		local progress, writeProgress
		local Progress = Facet.component(function(ui)
			progress, writeProgress = ui.state(0.25)
			local function percent(v)
				return string.format("%d%%", math.floor(v * 100 + 0.5))
			end
			return UI.Screen({
				id = "ProgressRing",
				padding = "m",
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = "s",
					width = UI.fill(),
					height = UI.fill(),
					UI.Text({ id = "Title", text = COPY.title, textSize = "heading" }),
					UI.Text({ id = "Caption", text = COPY.caption, textSize = "caption", role = "secondary" }),
					UI.Text({ text = COPY.adjust, width = UI.fill() }),
					UI.Slider({
						id = "AdjustProgress",
						value = progress,
						onChange = writeProgress,
						min = 0,
						max = 1,
						step = 0.05,
					}),
					UI.Text({ text = COPY.bar, width = UI.fill() }),
					UI.ProgressView({
						id = "Bar",
						value = progress,
						showValue = true,
						format = percent,
						segments = 5,
						trail = { delay = 0.3, duration = 0.35 },
					}),
					UI.ProgressView({
						id = "Ring",
						label = COPY.determinate,
						value = progress,
						presentation = "circular",
						diameter = 120,
						showValue = true,
						format = percent,
					}),
					UI.ProgressView({ id = "Busy", label = COPY.indeterminate, presentation = "circular" }),
					UI.ProgressView({ id = "Dots", label = COPY.spinner, presentation = "spinner" }),
				}),
			})
		end)
		local function report()
			return { progress = progress(), fraction = progress(), reduced = ctx.presenter.motionClock:isReduced() }
		end
		local function setProgress(value)
			writeProgress(math.clamp(value, 0, 1))
			return report()
		end
		return {
			screen = Progress({}),
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
			dispose = function() end,
		}
	end,
}
