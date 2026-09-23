--!strict
-- Notices: inline status copy in each severity, with a link, an action and a
-- close, and the affixed banner the Status tab pins to its own top. Snackbars:
-- the six compositions through `app.presentSnackbar`, a refusing caller, a
-- finite and a persistent dwell, a priority, and a burst past the queue.
return {
	title = "Notices",
	ledgerRows = {},
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local shown = Compose.cell(true)
		local banner = Compose.cell(false)
		local last = Compose.cell("Last: nothing yet")
		-- ===== snackbars (an application service; absent in a bare harness) ======
		local present = if ctx.app ~= nil then ctx.app.presentSnackbar else nil
		local refuse = Compose.cell(false)
		local undone = Compose.cell(0)
		local live: { () -> () } = {}
		local function show(message: any, extra: any?)
			if present == nil then
				return
			end
			local fact = Compose.cell(true)
			local release: (() -> ())? = nil
			local spec: any = {
				isPresented = fact,
				message = message,
				onPresentedChange = function(next: boolean)
					if not refuse:peek() then
						fact:set(next)
					end
				end,
				onDismiss = function(reason: string)
					last:set(`Last: snackbar {reason}`)
					if release ~= nil then
						release()
					end
				end,
			}
			for k, v in extra or {} do
				spec[k] = v
			end
			local ok, result = pcall(present, spec)
			if ok then
				release = result
				table.insert(live, result)
			else
				last:set("Last: refused — the snackbar queue is full")
			end
		end
		local undo = {
			label = "Undo",
			onActivate = function()
				undone:set(undone:peek() + 1)
			end,
		}
		local function snackbars(): any
			return UI.VStack("Snackbars")({
				width = UI.fill(),
				gap = "s",
				UI.Text("SnackbarTitle")({ text = "Snackbars", textSize = "heading", width = UI.fill() }),
				UI.Text("Undone")({
					text = function(use: any): string
						return `Undo pressed {use(undone)} times; the snackbar stays until you close it.`
					end,
					width = UI.fill(),
				}),
				UI.HStack("Compositions")({
					gap = "s",
					wrap = true,
					UI.Button("SnackMessage")({
						label = "Message",
						onActivate = function()
							show("Saved to your garage.", { closeButton = false, duration = 4 })
						end,
					}),
					UI.Button("SnackIcon")({
						label = "Icon and message",
						onActivate = function()
							show("Lap record saved.", { icon = "status.success", closeButton = false, duration = 4 })
						end,
					}),
					UI.Button("SnackAction")({
						label = "With action",
						onActivate = function()
							show("Kart sold.", { action = undo, closeButton = false, duration = 6 })
						end,
					}),
					UI.Button("SnackClose")({
						label = "With close",
						onActivate = function()
							show("Friend request sent.")
						end,
					}),
					UI.Button("SnackBoth")({
						label = "Action and close",
						onActivate = function()
							show("Paint job removed.", { action = undo })
						end,
					}),
					UI.Button("SnackAll")({
						label = "Everything",
						onActivate = function()
							show("Offline: your times will upload when you reconnect.", {
								icon = "status.warning",
								action = undo,
								duration = 8,
							})
						end,
					}),
				}),
				UI.HStack("Policies")({
					gap = "s",
					wrap = true,
					UI.Toggle("Refuse")({ label = "Refuse closes", value = refuse }),
					UI.Button("SnackUrgent")({
						label = "Urgent (priority 5)",
						onActivate = function()
							show("Race starting in 10 seconds.", { priority = 5, duration = 5 })
						end,
					}),
					UI.Button("SnackBurst")({
						label = "Burst of ten",
						onActivate = function()
							for i = 1, 10 do
								show(`Queued message {i} of 10.`, { duration = 3 })
							end
						end,
					}),
				}),
			})
		end

		local function reset()
			shown:set(true)
			banner:set(false)
			last:set("Last: nothing yet")
			refuse:set(false)
			undone:set(0)
			for _, release in live do
				release()
			end
			table.clear(live)
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
				snackbars(),
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
