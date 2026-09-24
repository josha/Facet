--!strict
return {
	title = "Badges",
	ledgerRows = {},
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local status, rung = Compose.cell("neutral"), Compose.cell("compact")
		local rootPath, controller, record
		local function report()
			if not rootPath or not controller or not record then
				return nil
			end
			ctx.presenter.refresh()
			return {
				badge = record.dump(),
				rect = controller.rectOf(rootPath .. "/Forms/Standard+background"),
				icon = controller.rectOf(rootPath .. "/Forms/Standard+background/Standard/Icon"),
			}
		end
		local function choose(word)
			status:set(word)
			return report()
		end
		local function reset()
			status:set("neutral")
			rung:set("compact")
		end
		local function section()
			Compose.cleanup(function()
				rootPath, controller, record = nil, nil, nil
			end)
			local root = UI.VStack("BadgeRecipe")({
				width = UI.fill(),
				gap = "m",
				UI.Text("Title")({ text = "Small labels", textSize = "heading", width = UI.fill() }),
				UI.Text("Guide")({
					text = "Badges identify something. They do not take focus or run actions.",
					width = UI.fill(),
				}),
				UI.HStack("Forms")({
					gap = "m",
					wrap = true,
					align = "center",
					UI.Badge("Standard")({
						label = "Ready",
						icon = "status.info",
						status = status,
						controlSize = rung,
						ref = function(value)
							record = value
						end,
					}),
					UI.Badge("Marked")({ label = "Server", appearance = "status", status = status, controlSize = rung }),
					UI.Badge("Utility")({
						label = "Beta",
						appearance = "utility",
						icon = "status.info",
						controlSize = rung,
					}),
					UI.Badge("Media")({
						label = "Featured",
						icon = "status.success",
						over = "media",
						status = status,
						controlSize = rung,
					}),
				}),
				-- on a host a count sits on its corner (Badge placement A): a Button, an
				-- icon button past 99, and an Avatar's dot; rows keep the trailing pill
				UI.HStack("Hosts")({
					gap = "l",
					wrap = true,
					align = "center",
					UI.badged(UI.Button("Inbox")({ label = "Inbox", onActivate = function() end }), 3),
					UI.badged(
						UI.Button("Alerts")({
							shape = "circle",
							icon = "menu",
							name = "Alerts",
							onActivate = function() end,
						}),
						120
					),
					UI.badged(UI.Avatar("Friend")({ name = "Ada Quill" }), true),
				}),
				UI.HStack("Commands")({
					gap = "s",
					wrap = true,
					UI.Button("Neutral")({
						label = "Neutral",
						onActivate = function()
							choose("neutral")
						end,
					}),
					UI.Button("Warning")({
						label = "Warning",
						onActivate = function()
							choose("warning")
						end,
					}),
					UI.Button("Error")({
						label = "Error",
						onActivate = function()
							choose("error")
						end,
					}),
					UI.Button("Size")({
						label = "Change size",
						onActivate = function()
							rung:set(if rung:peek() == "compact" then "large" else "compact")
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
			reset = reset,
			report = report,
			screen = function()
				return UI.Screen("Badge")({
					surface = "base",
					padding = { top = "m", bottom = "m" },
					UI.ScrollView("Content")({
						width = UI.fill(),
						height = UI.fill(),
						padding = { left = "m", right = "m" },
						section(),
					}),
				})
			end,
			steps = {
				neutral = function()
					return choose("neutral")
				end,
				warning = function()
					return choose("warning")
				end,
				error = function()
					return choose("error")
				end,
			},
		}
	end,
}
