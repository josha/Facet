--!strict
return {
	title = "World markers",
	ledgerRows = {},
	build = function(ctx: any)
		local Facet, env, pres = ctx.Facet, ctx.env, ctx.presenter
		local UI, Compose = ctx.UI, ctx.Compose
		local bounds = Compose.cell({ x = 0, y = 0, w = 1, h = 1 })
		local shifted, crowded, hidden = Compose.cell(false), Compose.cell(false), Compose.cell(false)
		local geometry = Compose.formula(function(use)
			local box = use(bounds)
			local facts = Facet.text.facts({ env = env, use = use })
			local line = Facet.text.lineBox({ facts = facts, size = "label", lines = 1 })
			local gap = facts.metrics.space.s
			local inset = facts.metrics.insets.panel
			local side = line + gap * 2 + math.max(inset.left + inset.right, inset.top + inset.bottom)
			local x = if use(shifted) then 1.4 else 0.6
			local y = if use(crowded) then 0.5 else 0.3
			local exclusions = {}
			for _, entry in use(pres.hudReservations) do
				local r = entry.rect
				table.insert(exclusions, { x = r.x - box.x, y = r.y - box.y, w = r.w, h = r.h })
			end
			return Facet.layout.worldMarkers({
				bounds = { x = 0, y = 0, w = box.w, h = box.h },
				gap = gap,
				exclusions = exclusions,
				markers = {
					{ id = "A", x = box.w * x, y = box.h * 0.5, width = side, height = side, priority = 10 },
					{ id = "B", x = box.w * 0.6, y = box.h * y, width = side, height = side, priority = 2 },
					{
						id = "C",
						x = box.w * 0.62,
						y = box.h * (if use(crowded) then 0.5 else 0.72),
						width = side,
						height = side,
						visible = not use(hidden),
					},
				},
			})
		end)
		local function pinView(index: number, id: string)
			local function property(fn)
				return function(use)
					return fn(use(geometry)[index])
				end
			end
			return UI.When(id .. "Visible")({
				Compose.show(
					property(function(row)
						return row.visible
					end),
					function()
						return UI.ZStack(id)({
							anchor = "topLeft",
							surface = "raised",
							corners = UI.cornersData("control"),
							offsetX = property(function(row)
								return if row.rect then row.rect.x else 0
							end),
							offsetY = property(function(row)
								return if row.rect then row.rect.y else 0
							end),
							width = property(function(row)
								return { type = "fixed", px = if row.rect then row.rect.w else 1 }
							end),
							height = property(function(row)
								return { type = "fixed", px = if row.rect then row.rect.h else 1 }
							end),

							UI.Text("Label")({ text = id, textSize = "label", alignH = "center", alignV = "center" }),
							UI.Path("Direction")({
								role = "accent",
								thickness = "strokes.hairline",
								width = UI.fill(),
								height = UI.fill(),
								hidden = property(function(row)
									return not row.edge
								end),
								points = property(function(row)
									return Facet.pathShapes.needle(row.angle or 0, { innerRadius = 0.65, radius = 0.9 })
								end),
							}),
						})
					end
				),
			})
		end
		local function screen()
			local map = { width = UI.fill(), height = UI.fill() } :: { [any]: any }
			for index, id in { "A", "B", "C" } do
				table.insert(map, pinView(index, id))
			end
			return UI.Screen("WorldMarkers")({
				padding = "m",
				gap = "s",

				UI.Anchor("Map")(map),
				UI.ScrollView("Controls")({
					width = UI.fill(),
					height = UI.fill(),
					gap = "s",

					UI.Text({ text = "A · Objective   B · Ally   C · Supplies", textSize = "label" }),
					UI.Toggle("Move")({ label = "Move objective offscreen", value = shifted }),
					UI.Toggle("Crowd")({ label = "Bring markers together", value = crowded }),
					UI.Toggle("Hide")({ label = "Occlude supplies", value = hidden }),
				}),
			})
		end
		return {
			screen = screen,
			present = {
				onGeometry = function(rectOf)
					local r = rectOf("/WorldMarkers/Map")
					local old = bounds:peek()
					if r and (r.x ~= old.x or r.y ~= old.y or r.w ~= old.w or r.h ~= old.h) then
						bounds:set(table.clone(r))
					end
				end,
			},
			steps = {
				reset = function()
					shifted:set(false)
					crowded:set(false)
					hidden:set(false)
				end,
				move = function()
					shifted:set(not shifted:peek())
				end,
				crowd = function()
					crowded:set(not crowded:peek())
				end,
			},
			report = function()
				return { markers = geometry:peek() }
			end,
			-- nothing outlives the screen
			dispose = function() end,
		}
	end,
}
