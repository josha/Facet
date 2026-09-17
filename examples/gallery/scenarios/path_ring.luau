--!strict
-- Scenario 'path_ring' (ledger row NS-A7): UI.Path renders a countdown-style
-- progress ring and a gauge needle via the engine's Path2D, with the arc
-- BOUND to a progress signal — steps sweep the value and the stroke updates
-- as paint-only prop writes (never a re-solve). Shape math is the pure,
-- headlessly-tested Facet.pathShapes; the engine only strokes. The column
-- (Title/Value/gauge) is hosted in a `fill` ScrollView so it stays reachable
-- on a short landscape phone instead of clipping off the bottom.

return {
	title = "Path2D ring + needle (NS-A7)",
	ledgerRows = { "NS-A7" },
	build = function(ctx: any)
		local UI = ctx.Facet.View
		local shapes = ctx.Facet.pathShapes
		local progress, setProgress, ringPoints
		local Gauge = ctx.Facet.component(function(ui)
			progress, setProgress = ui.state(0.25)
			ringPoints = ui.memo(function()
				local p = math.clamp(progress(), 0, 1)
				return shapes.arc(0, 360 * p, { segments = 8, radius = 0.9 })
			end)
			local needlePoints = function()
				return shapes.needle(360 * math.clamp(progress(), 0, 1), { innerRadius = 0.1, radius = 0.62 })
			end
			local label = function()
				return string.format("progress %d%%", progress() * 100 + 0.5)
			end

			-- The 180x180 gauge is a fixed-size decorative square (the ring reads
			-- wrong at any other aspect), so it cannot itself shrink to fit a short
			-- landscape phone the way `scroll_host`'s demo regions do. The page as
			-- a whole is what overflowed (Title + Value + a 180px gauge taller than
			-- a short landscape safe area — overflow_sweep, device bug round
			-- 2026-08-12), and there is no pre-existing ScrollView here to nest
			-- inside, so the shipped precedent applies directly (`adaptive_controls`
			-- BodyScroll / tutorial example 01): host the column in a `fill`
			-- ScrollView so it's reachable instead of clipped off the bottom.
			return UI.Screen({
				id = "PathRing",
				padding = "m",

				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = "s",
					width = UI.fill(),
					height = UI.fill(),

					UI.Text({ id = "Title", text = "Path2D progress ring", textSize = 22 }),
					UI.Text({ id = "Value", text = label, textSize = "label" }),
					UI.ZStack({
						id = "Gauge",
						width = { type = "fixed", px = 180 },
						height = { type = "fixed", px = 180 },

						UI.Path({
							id = "Track",
							points = shapes.ring({ radius = 0.9 }),
							thickness = 3,
							role = "secondary",
							width = { type = "fixed", px = 180 },
							height = { type = "fixed", px = 180 },
						}),
						UI.Path({
							id = "Ring",
							points = ringPoints,
							thickness = 8,
							role = "accent",
							width = { type = "fixed", px = 180 },
							height = { type = "fixed", px = 180 },
						}),
						UI.Path({
							id = "Needle",
							points = needlePoints,
							thickness = 4,
							width = { type = "fixed", px = 180 },
							height = { type = "fixed", px = 180 },
						}),
					}),
				}),
			})
		end)

		return {
			screen = Gauge({}),
			present = {},
			steps = {
				setProgress10 = function()
					setProgress(0.10)
					return progress()
				end,
				setProgress65 = function()
					setProgress(0.65)
					return progress()
				end,
				setProgress100 = function()
					setProgress(1.0)
					return progress()
				end,
			},
			report = function()
				return { progress = progress(), ringPointCount = #ringPoints() }
			end,
		}
	end,
}
