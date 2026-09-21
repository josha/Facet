--!strict
return {
	title = "Status marks",
	ledgerRows = {},
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local status, form, count = Compose.cell("neutral"), Compose.cell("dot"), Compose.cell(0)
		local rootPath, controller, record
		local function report()
			if not rootPath or not controller or not record then
				return nil
			end
			ctx.presenter.refresh()
			return {
				count = record.dump(),
				rect = controller.rectOf(rootPath .. "/Live/Count"),
				form = form:peek(),
				status = status:peek(),
			}
		end
		local function choose(word)
			status:set(word)
			return report()
		end
		local function section()
			Compose.cleanup(function()
				rootPath, controller, record = nil, nil, nil
			end)
			local shapes, words = {}, {}
			for _, word in { "dot", "ring", "square", "dash" } do
				table.insert(
					shapes,
					UI.HStack(word)({
						gap = "s",
						align = "center",
						UI.StatusIndicator("Mark")({ form = word, status = status, name = word }),
						UI.Text("Name")({ text = word }),
					})
				)
			end
			for _, word in { "neutral", "info", "success", "warning", "error", "accent" } do
				table.insert(
					words,
					UI.Button(word)({
						label = word,
						onActivate = function()
							choose(word)
						end,
					})
				)
			end
			local root = UI.VStack("StatusRecipe")({
				width = UI.fill(),
				gap = "m",
				UI.Text("Title")({ text = "Status marks", textSize = "heading", width = UI.fill() }),
				UI.Text("Guide")({
					text = "Shapes carry meaning alongside color. Counts stop growing at 99+.",
					width = UI.fill(),
				}),
				UI.HStack("Shapes")({ gap = "l", wrap = true, table.unpack(shapes) }),
				UI.HStack("Live")({
					gap = "m",
					align = "center",
					UI.StatusIndicator("Count")({
						count = count,
						status = status,
						name = "Unread",
						ref = function(value)
							record = value
						end,
					}),
					UI.StatusIndicator("Cutout")({ form = form, status = status, cutout = true, controlSize = "large" }),
				}),
				UI.HStack("Statuses")({ gap = "s", wrap = true, table.unpack(words) }),
				UI.HStack("Commands")({
					gap = "s",
					wrap = true,
					UI.Button("More")({
						label = "Add 25",
						onActivate = function()
							count:set(count:peek() + 25)
						end,
					}),
					UI.Button("Reset")({
						label = "Clear count",
						onActivate = function()
							count:set(0)
						end,
					}),
					UI.Button("Shape")({
						label = "Toggle ring",
						onActivate = function()
							form:set(if form:peek() == "dot" then "ring" else "dot")
						end,
					}),
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
			report = report,
			screen = function()
				return UI.Screen("StatusIndicator")({
					surface = "base",
					padding = "m",
					UI.ScrollView("Content")({ width = UI.fill(), height = UI.fill(), section() }),
				})
			end,
			steps = {
				warning = function()
					return choose("warning")
				end,
				error = function()
					return choose("error")
				end,
				neutral = function()
					return choose("neutral")
				end,
				capped = function()
					count:set(1000)
					return report()
				end,
				ring = function()
					form:set("ring")
					return report()
				end,
			},
		}
	end,
}
