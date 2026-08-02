--!strict
-- Scenario 'path_ring' (ledger row NS-A7): UI.Path renders a countdown-style
-- progress ring and a gauge needle via the engine's Path2D, with the arc
-- BOUND to a progress signal — steps sweep the value and the stroke updates
-- as paint-only prop writes (never a re-solve). Shape math is the pure,
-- headlessly-tested LuauUI.pathShapes; the engine only strokes.

return {
	title = "Path2D ring + needle (NS-A7)",
	ledgerRows = { "NS-A7" },
	build = function(ctx: any)
		local UI = ctx.LuauUI.UI
		local shapes = ctx.LuauUI.pathShapes
		local core = ctx.core

		local progress = core:signal(0.25)
		local ringPoints = core:memo(function(use)
			local p = math.clamp(use(progress), 0, 1)
			return shapes.arc(0, 360 * p, { segments = 8, radius = 0.9 })
		end)
		local needlePoints = core:memo(function(use)
			return shapes.needle(360 * math.clamp(use(progress), 0, 1), { innerRadius = 0.1, radius = 0.62 })
		end)
		local label = core:memo(function(use)
			return string.format("progress %d%%", use(progress) * 100 + 0.5)
		end)

		local screen = UI.Screen({
			id = "PathRing",
			padding = 16,
			gap = 8,
			children = {
				UI.Text({ id = "Title", text = "Path2D progress ring", textSize = 22 }),
				UI.Text({ id = "Value", text = label, textSize = 14 }),
				UI.ZStack({
					id = "Gauge",
					width = { type = "fixed", px = 180 },
					height = { type = "fixed", px = 180 },
					children = {
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
					},
				}),
			},
		})

		return {
			screen = screen,
			present = {},
			steps = {
				setProgress10 = function()
					progress:set(0.10)
					return progress:get()
				end,
				setProgress65 = function()
					progress:set(0.65)
					return progress:get()
				end,
				setProgress100 = function()
					progress:set(1.0)
					return progress:get()
				end,
			},
			report = function()
				return { progress = progress:get(), ringPointCount = #ringPoints:get() }
			end,
		}
	end,
}
