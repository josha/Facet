--!strict
-- Glade (RA-P1) — the two composites: GladeScene (spec §5) and SupplyRing (§6).
--
-- GLADESCENE is the proof's ONE pictorial surface (visual invariant 2): a
-- `ZStack` of layers placed by `UI.Anchor` fractional offsets, a reactive sky
-- gradient driven by the day-phase memo, and the visiting wisp as a small stack
-- of tinted layers. Every control in the proof sits on token surfaces beside it,
-- never over it.
--
-- DEVIATION, RECORDED: the spec writes each layer as a `UI.Image` over original
-- art. This stage ships no uploaded assets (uploading is not in the package's
-- scope and an invented asset id draws NOTHING on a real client — the lesson the
-- gallery's own art table carries), so the layers are tinted `UI.Box` shapes with
-- the identical structure: same ZStack, same anchors, same fractional offsets,
-- same per-layer identity tints. Swapping in art later is a per-layer change from
-- `UI.Box{ tint = … }` to `UI.Image{ image = …, tint = … }` and nothing else.
--
-- SUPPLYRING is a `UI.Path` track plus a `UI.Path` arc whose sweep chases the
-- level memo through a spring. Hue is supply IDENTITY only (nectar vs dew); the
-- low and empty states are carried by form — the arc emptying, a chip, and a
-- strengthened caption — never by a second hue (visual invariant 1).

local seedData = require("../content/seed")
local parts = require("./parts")

local scene = {}

-- ---- SupplyRing --------------------------------------------------------------

local FULL_TURN = 360

export type RingSpec = {
	id: string,
	glade: string,
	kind: string, -- "nectar" | "dew"
	size: number,
	scope: any,
}

function scene.ring(ctx: any, spec: RingSpec): any
	local UI = ctx.UI
	local core = ctx.core
	local level = ctx.supply.level(spec.glade, spec.kind)

	-- the painted arc chases the level through a spring (§11, class `object`).
	-- Under reduced motion `setTarget` places instantly and fires the same
	-- settle — the framework's parity contract, not a branch here.
	local painted = spec.scope:own(ctx.clock:spring(level:get(), "object"))
	spec.scope:own(core:observe(level, function(value: number)
		painted:setTarget(value)
	end))

	local sweep = spec.scope:own(core:memo(function(use)
		local value = use(painted)
		if value < 0 then
			value = 0
		elseif value > 1 then
			value = 1
		end
		return value * FULL_TURN
	end))
	local visible = spec.scope:own(core:memo(function(use)
		return use(sweep) > 1
	end))
	local points = spec.scope:own(core:memo(function(use)
		local degrees = use(sweep)
		local segments = math.clamp(math.ceil(degrees / 24), 2, 24)
		return ctx.LuauUI.pathShapes.arc(0, degrees, { segments = segments })
	end))

	local mark
	if spec.kind == "nectar" then
		local jarTint = spec.scope:own(core:memo(function(use)
			local nectarId = use(ctx.supply.nectarOf(spec.glade))
			local nectar = seedData.NECTAR_BY_ID[nectarId]
			return ctx.tint(if nectar ~= nil then nectar.art else seedData.WHITE)
		end))
		-- the gauge icon swap (§11): a keyed region over the assigned nectar id,
		-- so changing the jar materializes rather than cutting.
		local assignedList = spec.scope:own(core:memo(function(use)
			return { { id = use(ctx.supply.nectarOf(spec.glade)) } }
		end))
		mark = UI.ForEach({
			id = "Jar",
			items = assignedList,
			key = function(item: any): string
				return item.id
			end,
			transition = { enter = "materialize", class = "container" },
			row = function(): any
				return UI.corners(
					UI.ZStack({
						id = "Swap",
						canvasGroup = true,
						width = { type = "fixed", px = math.floor(spec.size * 0.46) },
						height = { type = "fixed", px = math.floor(spec.size * 0.46) },
						children = {
							UI.corners(
								UI.Box({
									id = "Fill",
									tint = jarTint,
									width = { type = "fill", weight = 1 },
									height = { type = "fill", weight = 1 },
								}),
								"pill"
							),
						},
					}),
					"pill"
				)
			end,
		})
	else
		mark = UI.corners(
			UI.Box({
				id = "Drop",
				tint = ctx.tint(seedData.DEWWATER),
				width = { type = "fixed", px = math.floor(spec.size * 0.40) },
				height = { type = "fixed", px = math.floor(spec.size * 0.40) },
			}),
			"pill"
		)
	end

	return UI.ZStack({
		id = spec.id,
		width = { type = "fixed", px = spec.size },
		height = { type = "fixed", px = spec.size },
		children = {
			UI.Path({
				id = "Track",
				points = ctx.LuauUI.pathShapes.ring({}),
				thickness = "xs",
				role = "secondary",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
			}),
			UI.When({
				id = "Arc",
				condition = visible,
				thenView = function(): any
					return UI.Path({
						id = "Fill",
						points = points,
						thickness = "xs",
						tint = ctx.supplyTint(spec.kind),
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
					})
				end,
			}),
			mark,
		},
	})
end

-- ---- GladeScene --------------------------------------------------------------

-- the fern layer: fractional offsets down each side, staggered for depth
local FERNS = {
	{ id = "FernA", x = 0.08, y = 0.70, w = 22, h = 40 },
	{ id = "FernB", x = 0.18, y = 0.78, w = 16, h = 28 },
	{ id = "FernC", x = 0.86, y = 0.72, w = 20, h = 36 },
	{ id = "FernD", x = 0.76, y = 0.80, w = 14, h = 24 },
}

export type SceneSpec = {
	id: string,
	glade: string,
	form: string, -- "card" | "hero"
	scope: any,
	height: any, -- a dimension table
}

function scene.glade(ctx: any, spec: SceneSpec): any
	local UI = ctx.UI
	local core = ctx.core
	local glade = seedData.GLADE_BY_ID[spec.glade]

	local phase = spec.scope:own(core:memo(function(use)
		return seedData.phaseAt(glade.phaseOffset, use(ctx.now))
	end))
	local sky = spec.scope:own(core:memo(function(use)
		local ramp = seedData.SKY[use(phase)]
		return UI.gradientData({ colors = { ctx.rgb(ramp.high), ctx.rgb(ramp.low) } })
	end))
	local silhouette = spec.scope:own(core:memo(function(use)
		return ctx.tint(seedData.SKY[use(phase)].silhouette)
	end))

	local layers: { any } = {
		UI.Box({
			id = "Sky",
			tint = ctx.tint(seedData.WHITE),
			gradient = sky,
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
		}),
		-- weighted-fill columns, not percent: a percent height inside the page
		-- scroller's unbounded measure axis is the exact shape the solver
		-- diagnoses (matrix row 2026-08-08, 33k repeats), and a weight ratio
		-- states the same 42%/20% bands against the scene's own box
		UI.VStack({
			id = "TreesBand",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			children = {
				UI.Spacer({ height = { type = "fill", weight = 58 } }),
				UI.Box({
					id = "TreesFar",
					tint = silhouette,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 42 },
				}),
			},
		}),
		UI.VStack({
			id = "FloorBand",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			children = {
				UI.Spacer({ height = { type = "fill", weight = 80 } }),
				UI.Box({
					id = "Floor",
					tint = ctx.tint(seedData.MOSS),
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 20 },
				}),
			},
		}),
	}

	local fernChildren: { any } = {}
	for _, fern in FERNS do
		table.insert(
			fernChildren,
			UI.corners(
				UI.Box({
					id = fern.id,
					anchor = "topLeft",
					offsetX = { scale = fern.x },
					offsetY = { scale = fern.y },
					tint = ctx.tint(seedData.FERN),
					width = { type = "fixed", px = fern.w },
					height = { type = "fixed", px = fern.h },
				}),
				"control"
			)
		)
	end
	table.insert(
		layers,
		UI.Anchor({
			id = "Flora",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			children = fernChildren,
		})
	)

	table.insert(
		layers,
		UI.corners(
			UI.Box({
				id = "Dewstone",
				tint = ctx.tint(seedData.DEWSTONE),
				alignH = "center",
				alignV = "end",
				margin = { bottom = "m" },
				width = { type = "fixed", px = if spec.form == "hero" then 56 else 34 },
				height = { type = "fixed", px = if spec.form == "hero" then 18 else 12 },
			}),
			"pill"
		)
	)

	-- THE VISITOR. `When` over the scheduler's current-visit memo, so a window
	-- opening or closing mounts and unmounts the wisp with a real transition and
	-- nothing paints an invisible sprite at rest.
	local visitor = spec.scope:own(core:memo(function(use)
		return use(ctx.visits.current(spec.glade)) ~= nil
	end))
	local motion = ctx.wispMotion(spec.glade, spec.form)
	local wispSize = spec.scope:own(core:memo(function(use)
		local live = use(ctx.visits.current(spec.glade))
		local species = if live ~= nil then seedData.WISP_BY_ID[live.wisp] else nil
		local natural = if species ~= nil then species.scale else 1
		local base = seedData.METRICS.wispSize * (if spec.form == "hero" then 1 else 0.62)
		return math.max(8, math.floor(base * natural))
	end))
	local coreTint = spec.scope:own(core:memo(function(use)
		local live = use(ctx.visits.current(spec.glade))
		local species = if live ~= nil then seedData.WISP_BY_ID[live.wisp] else nil
		return ctx.tint(if species ~= nil then species.core else seedData.WHITE)
	end))
	local glowTint = spec.scope:own(core:memo(function(use)
		local live = use(ctx.visits.current(spec.glade))
		local species = if live ~= nil then seedData.WISP_BY_ID[live.wisp] else nil
		-- the delight glow (§11, class `decay`): one transparency swell after a
		-- refill, then back. Decorative — the toast carries the information.
		return ctx.tint(if species ~= nil then species.glow else seedData.WHITE, use(motion.glow))
	end))
	local trailTint = spec.scope:own(core:memo(function(use)
		local live = use(ctx.visits.current(spec.glade))
		local species = if live ~= nil then seedData.WISP_BY_ID[live.wisp] else nil
		return ctx.tint(if species ~= nil then species.glow else seedData.WHITE, 0.55)
	end))
	local offsetX = spec.scope:own(core:memo(function(use)
		return { scale = use(motion.x) }
	end))
	local offsetY = spec.scope:own(core:memo(function(use)
		return { scale = use(motion.y) }
	end))
	local haloSize = spec.scope:own(core:memo(function(use)
		return { type = "fixed", px = math.floor(use(wispSize) * 1.9) }
	end))
	local bodySize = spec.scope:own(core:memo(function(use)
		return { type = "fixed", px = use(wispSize) }
	end))
	local trailSize = spec.scope:own(core:memo(function(use)
		return { type = "fixed", px = math.floor(use(wispSize) * 0.5) }
	end))

	table.insert(
		layers,
		UI.When({
			id = "Visitor",
			condition = visitor,
			transition = { enter = "fade", class = "container" },
			thenView = function(): any
				return UI.ZStack({
					id = "VisitorLayer",
					canvasGroup = true,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.Anchor({
							id = "Flight",
							width = { type = "fill", weight = 1 },
							height = { type = "fill", weight = 1 },
							children = {
								UI.ZStack({
									id = "Wisp",
									anchor = "topLeft",
									offsetX = offsetX,
									offsetY = offsetY,
									width = haloSize,
									height = haloSize,
									children = {
										UI.corners(
											UI.Box({
												id = "Glow",
												tint = glowTint,
												width = { type = "fill", weight = 1 },
												height = { type = "fill", weight = 1 },
											}),
											"pill"
										),
										UI.corners(
											UI.Box({
												id = "Core",
												tint = coreTint,
												alignH = "center",
												alignV = "center",
												width = bodySize,
												height = bodySize,
											}),
											"pill"
										),
										UI.corners(
											UI.Box({
												id = "Trail",
												tint = trailTint,
												alignH = "start",
												alignV = "end",
												width = trailSize,
												height = trailSize,
											}),
											"pill"
										),
									},
								}),
							},
						}),
					},
				})
			end,
		})
	)

	return UI.stroke(
		UI.corners(
			UI.ZStack({
				id = spec.id,
				canvasGroup = true,
				overflow = "clip",
				width = { type = "fill", weight = 1 },
				height = spec.height,
				children = layers,
			}),
			"panel"
		),
		{}
	)
end

-- ---- the wisp portrait -------------------------------------------------------
-- The one avatar treatment (spec §10), reused by the visitor rows, S6 and S5's
-- hero: the species' layer stack over a mini sky at its preferred phase.
function scene.portrait(ctx: any, id: string, wispId: string, size: number): any
	local UI = ctx.UI
	local species = seedData.WISP_BY_ID[wispId]
	local ramp = seedData.SKY[if species ~= nil then species.phase else "day"]
	local body = math.max(6, math.floor(size * 0.42))
	return UI.corners(
		UI.ZStack({
			id = id,
			surface = "raised",
			overflow = "clip",
			width = { type = "fixed", px = size },
			height = { type = "fixed", px = size },
			children = {
				UI.Box({
					id = "Mini",
					tint = ctx.tint(seedData.WHITE),
					gradient = UI.gradientData({ colors = { ctx.rgb(ramp.high), ctx.rgb(ramp.low) } }),
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
				}),
				UI.corners(
					UI.Box({
						id = "Glow",
						tint = ctx.tint(if species ~= nil then species.glow else seedData.WHITE, 0.35),
						alignH = "center",
						alignV = "center",
						width = { type = "fixed", px = math.floor(body * 1.8) },
						height = { type = "fixed", px = math.floor(body * 1.8) },
					}),
					"pill"
				),
				UI.corners(
					UI.Box({
						id = "Core",
						tint = ctx.tint(if species ~= nil then species.core else seedData.WHITE),
						alignH = "center",
						alignV = "center",
						width = { type = "fixed", px = body },
						height = { type = "fixed", px = body },
					}),
					"pill"
				),
			},
		}),
		"pill"
	)
end

scene.parts = parts

return scene
