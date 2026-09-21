--!strict
-- The pending branch owns its silhouettes. Loading state survives a remount.
return {
	title = "Loading silhouettes",
	ledgerRows = {},
	build = function(ctx)
		local UI, Compose = ctx.UI, ctx.Compose
		local loading, first = Compose.cell(true), Compose.cell(true)
		local rootPath, controller
		local records = {}
		local function report()
			if not rootPath or not controller then
				return nil
			end
			ctx.presenter.refresh()
			local function rect(suffix)
				return controller.rectOf(rootPath .. suffix)
			end
			return {
				loading = rect("/Pending/then/Placeholders") ~= nil,
				box = rect("/Pending/then/Placeholders/First/then/Card"),
				circle = rect("/Pending/then/Placeholders/Face"),
				paragraph = rect("/Pending/then/Placeholders/Copy"),
				animating = records.face and records.face.dump().animating or false,
				reduced = ctx.presenter.motionClock:isReduced(),
			}
		end
		local function command(cell, value)
			cell:set(value)
			return report()
		end
		local function motion(value)
			ctx.env:set("reducedMotion", value)
			return report()
		end
		local function section()
			Compose.cleanup(function()
				rootPath, controller = nil, nil
				table.clear(records)
			end)
			local root = UI.VStack("SkeletonRecipe")({
				width = UI.fill(),
				gap = "m",
				UI.Text("Title")({ text = "Loading silhouettes", textSize = "heading", width = UI.fill() }),
				UI.Text("Note")({
					text = "Reserve a place for content while it loads. Reduced motion keeps the shapes still.",
					width = UI.fill(),
				}),
				UI.HStack("Commands")({
					gap = "s",
					wrap = true,
					UI.Button("Load")({
						label = "Loading",
						onActivate = function()
							loading:set(true)
						end,
					}),
					UI.Button("Ready")({
						label = "Loaded",
						onActivate = function()
							loading:set(false)
						end,
					}),
					UI.Button("Reduce")({
						label = "Reduce motion",
						onActivate = function()
							motion(true)
						end,
					}),
					UI.Button("Animate")({
						label = "Full motion",
						onActivate = function()
							motion(false)
						end,
					}),
				}),
				UI.When("Pending")({
					condition = loading,
					thenView = function()
						Compose.cleanup(function()
							table.clear(records)
						end)
						return UI.VStack("Placeholders")({
							width = UI.fill(),
							gap = "m",
							UI.When("First")({
								condition = first,
								thenView = function()
									return UI.Skeleton("Card")({ form = "box" })
								end,
							}),
							UI.Skeleton("Face")({
								form = "circle",
								ref = function(record)
									records.face = record
								end,
							}),
							UI.Skeleton("Copy")({ form = "line", lines = 3 }),
						})
					end,
					elseView = function()
						return UI.Text("ReadyCopy")({ text = "Your next race is ready.", width = UI.fill() })
					end,
				}),
			})
			return ctx.Facet.contribution.attach(root, {
				bindController = function(value)
					controller = value
				end,
				syncGeometry = function(_, node)
					if node then
						rootPath = node.path
					end
				end,
			})
		end
		return {
			section = section,
			screen = function()
				return UI.Screen("Skeleton")({
					padding = "m",
					UI.ScrollView("Content")({ width = UI.fill(), height = UI.fill(), section() }),
				})
			end,
			report = report,
			steps = {
				loading = function()
					return command(loading, true)
				end,
				loaded = function()
					return command(loading, false)
				end,
				removeFirst = function()
					return command(first, false)
				end,
				restoreFirst = function()
					return command(first, true)
				end,
				reduced = function()
					return motion(true)
				end,
				full = function()
					return motion(false)
				end,
			},
			reset = function()
				loading:set(true)
				first:set(true)
				motion(false)
			end,
		}
	end,
}
