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
		local UI, Compose = ctx.UI, ctx.Compose
		local shapes = ctx.Facet.pathShapes
		local progress = Compose.cell(0.25)
		local ringPoints = Compose.formula(function(use)
			local p = math.clamp(use(progress), 0, 1)
			return shapes.arc(0, 360 * p, { segments = 8, radius = 0.9 })
		end)
		local function needlePoints(use)
			return shapes.needle(360 * math.clamp(use(progress), 0, 1), { innerRadius = 0.1, radius = 0.62 })
		end
		local function label(use)
			return string.format("progress %d%%", use(progress) * 100 + 0.5)
		end
		local GAUGE = { type = "fixed", px = 180 }

		-- The 180x180 gauge is a fixed-size decorative square (the ring reads
		-- wrong at any other aspect), so it cannot shrink to fit a short landscape
		-- phone. The column is hosted in a `fill` ScrollView so it stays reachable
		-- instead of clipping off the bottom.
		local function screen()
			return UI.Screen("PathRing")({
				padding = "m",

				UI.ScrollView("Page")({
					axis = "y",
					gap = "s",
					width = UI.fill(),
					height = UI.fill(),

					UI.Text("Title")({ text = "Path2D progress ring", textSize = 22 }),
					UI.Text("Value")({ text = label, textSize = "label" }),
					UI.ZStack("Gauge")({
						width = GAUGE,
						height = GAUGE,

						UI.Path("Track")({
							points = shapes.ring({ radius = 0.9 }),
							thickness = 3,
							role = "secondary",
							width = GAUGE,
							height = GAUGE,
						}),
						UI.Path("Ring")({
							points = ringPoints,
							thickness = 8,
							role = "accent",
							width = GAUGE,
							height = GAUGE,
						}),
						UI.Path("Needle")({
							points = needlePoints,
							thickness = 4,
							width = GAUGE,
							height = GAUGE,
						}),
					}),
				}),
			})
		end

		local function set(value: number)
			return function()
				progress:set(value)
				return progress:peek()
			end
		end
		return {
			screen = screen,
			present = {},
			steps = {
				setProgress10 = set(0.10),
				setProgress65 = set(0.65),
				setProgress100 = set(1.0),
			},
			report = function()
				return { progress = progress:peek(), ringPointCount = #ringPoints:peek() }
			end,
		}
	end,
}
