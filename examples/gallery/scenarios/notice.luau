--!strict
-- Notices: inline status copy in each severity, with a link, an action and a
-- close, and the affixed banner the Status tab pins to its own top.
return {
	title = "Notices",
	ledgerRows = {},
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local shown = Compose.cell(true)
		local banner = Compose.cell(false)
		local last = Compose.cell("Last: nothing yet")
		local function reset()
			shown:set(true)
			banner:set(false)
			last:set("Last: nothing yet")
		end
		local function section()
			local severities: { any } = {}
			for _, severity in { "info", "success", "warning", "error" } do
				table.insert(
					severities,
					UI.Notice(`Severity-{severity}`)({
						severity = severity,
						message = `A {severity} notice keeps its words when the icon is gone.`,
					})
				)
			end
			return UI.VStack("NoticeRecipe")({
				width = UI.fill(),
				gap = "m",
				UI.Text("Title")({ text = "Notices", textSize = "heading", width = UI.fill() }),
				UI.Text("Last")({ text = last, width = UI.fill() }),
				UI.When("Update")({
					condition = shown,
					thenView = function()
						return UI.Notice("Update")({
							severity = "info",
							appearance = "emphasis",
							title = "Update available",
							message = "A new track pack is ready to install.",
							link = {
								label = "Release notes",
								onActivate = function()
									last:set("Last: release notes")
								end,
							},
							actions = {
								{
									id = "Install",
									label = "Install",
									role = "default",
									onActivate = function()
										last:set("Last: install")
									end,
								},
							},
							onDismiss = function()
								shown:set(false)
							end,
						})
					end,
				}),
				UI.VStack("Severities")({ width = UI.fill(), gap = "s", table.unpack(severities) }),
				UI.HStack("Commands")({
					gap = "s",
					wrap = true,
					UI.Button("ShowBanner")({
						label = "Pin an offline banner",
						onActivate = function()
							banner:set(not banner:peek())
						end,
					}),
					UI.Button("ShowUpdate")({
						label = "Bring the update back",
						onActivate = function()
							shown:set(true)
						end,
					}),
				}),
			})
		end
		-- the affixed banner: a page-local top notice the tab's content avoids
		local function affixed()
			return UI.When("Banner")({
				condition = banner,
				thenView = function()
					return UI.Notice("Offline")({
						placement = "affixed",
						severity = "warning",
						message = "Connection interrupted. Reconnecting…",
						onDismiss = function()
							banner:set(false)
						end,
					})
				end,
			})
		end
		return {
			section = section,
			affixed = affixed,
			reset = reset,
			banner = banner,
			-- standalone, the section scrolls on its own screen (the sweep mounts this)
			screen = function()
				return UI.Screen("Notices")({
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
				reset = reset,
				banner = function()
					banner:set(true)
				end,
			},
		}
	end,
}
