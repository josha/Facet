--!strict

return {
	title = "Notices",
	ledgerRows = {},
	build = function(ctx: any)
		local UI, Compose, Host = ctx.UI, ctx.Compose, ctx.Host
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Enum = Enum }
		local UDim, UDim2, Enum = nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Enum
		local shown = Compose.cell(true)
		local banner = Compose.cell(false)
		local last = Compose.cell("Last: nothing yet")
		local refuse = Compose.cell(false)
		local undone = Compose.cell(0)
		type Entry = { id: number, fact: any, spec: { [string]: any } }
		local entries = Compose.cell({} :: { Entry })
		local serial = 0

		local function release(id: number)
			local kept = {}
			for _, entry in entries:peek() do
				if entry.id ~= id then
					table.insert(kept, entry)
				end
			end
			entries:set(kept)
		end

		local function show(message: string, extra: { [string]: any }?)
			if #entries:peek() >= 9 then
				last:set("Last: refused, the snackbar queue is full")
				return
			end
			serial += 1
			local id = serial
			local fact = Compose.cell(true)
			local spec: { [string]: any } = {
				isPresented = fact,
				message = message,
				onPresentedChange = function(nextValue: boolean)
					if not refuse:peek() then
						fact:set(nextValue)
					end
				end,
				onDismiss = function(reason: string)
					last:set(`Last: snackbar {reason}`)
					release(id)
				end,
			}
			for key, value in extra or {} do
				spec[key] = value
			end
			local list = table.clone(entries:peek())
			table.insert(list, { id = id, fact = fact, spec = spec })
			entries:set(list)
		end

		local undo = {
			label = "Undo",
			onActivate = function()
				undone:set(undone:peek() + 1)
			end,
		}

		local function label(name: string, text: any, order: number, role: string?): any
			return UI.Label({
				Name = name,
				LayoutOrder = order,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Text = text,
				textRole = role,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end

		local function row(name: string, order: number, children: { any }): any
			local props: { [any]: any } = {
				Name = name,
				LayoutOrder = order,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 8),
					Wraps = true,
				}),
			}
			for index, child in children do
				props[#props + 1] = child
				child.LayoutOrder = index
			end
			return Host.Frame(props)
		end

		local function snackbars(): any
			return Host.Frame "Snackbars" {
				LayoutOrder = 5,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 8),
				}),
				label("SnackbarTitle", "Snackbars", 1, "heading"),
				label("Undone", function(use: any): string
					local n = use(undone)
					return `Undo pressed {n} {if n == 1 then "time" else "times"}; the snackbar stays until you close it.`
				end, 2),
				row("Compositions", 3, {
					UI.Button "SnackMessage" {
						label = "Message",
						onActivate = function()
							show("Saved to your garage.", { closeButton = false, duration = 4 })
						end,
					},
					UI.Button "SnackIcon" {
						label = "Icon and message",
						onActivate = function()
							show("Lap record saved.", { icon = "status.success", closeButton = false, duration = 4 })
						end,
					},
					UI.Button "SnackAction" {
						label = "With action",
						onActivate = function()
							show("Kart sold.", { action = undo, closeButton = false, duration = 6 })
						end,
					},
					UI.Button "SnackClose" {
						label = "With close",
						onActivate = function()
							show("Friend request sent.")
						end,
					},
					UI.Button "SnackAll" {
						label = "Everything",
						onActivate = function()
							show(
								"Offline: your times will upload when you reconnect.",
								{ icon = "status.warning", action = undo, duration = 8 }
							)
						end,
					},
				}),
				row("Policies", 4, {
					UI.Toggle "Refuse" { label = "Refuse closes", value = refuse },
					UI.Button "SnackUrgent" {
						label = "Urgent (priority 5)",
						onActivate = function()
							show("Race starting in 10 seconds.", { priority = 5, duration = 5 })
						end,
					},
					UI.Button "SnackBurst" {
						label = "Burst of ten",
						onActivate = function()
							for index = 1, 10 do
								show(`Queued message {index} of 10.`, { duration = 3 })
							end
						end,
					},
				}),
				Compose.keyed({
					from = entries,
					key = function(entry: Entry): number
						return entry.id
					end,
					render = function(item: any)
						local entry: Entry = item:peek()
						return Host.Folder({
							Name = `SnackSlot{entry.id}`,
							Compose.boundary(function()
								return UI.Snackbar(`Snack{entry.id}`)(entry.spec :: any)
							end, function()
								last:set("Last: refused, the snackbar queue is full")
								return Host.Folder "Refused" {}
							end),
						})
					end,
				}),
			}
		end

		local function reset()
			shown:set(true)
			banner:set(false)
			last:set("Last: nothing yet")
			refuse:set(false)
			undone:set(0)
			entries:set({})
		end

		local function section(order: number?): any
			local severities: { any } = {}
			for index, severity in { "info", "success", "warning", "error" } do
				table.insert(
					severities,
					UI.Notice {
						Name = `Severity-{severity}`,
						LayoutOrder = index,
						severity = severity,
						appearance = "emphasis",
						message = `{if severity == "info" or severity == "error" then "An" else "A"} {severity} notice, in its severity's colour.`,
					}
				)
			end
			local severityProps: { [any]: any } = {
				Name = "Severities",
				LayoutOrder = 4,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 8),
				}),
			}
			for _, notice in severities do
				severityProps[#severityProps + 1] = notice
			end
			return Host.Frame "NoticeRecipe" {
				LayoutOrder = order or 1,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 16),
				}),
				label("NoticeTitle", "Notices", 1, "heading"),
				label("Last", last, 2),
				Compose.show(shown, function()
					return UI.Notice "Update" {
						LayoutOrder = 3,
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
					}
				end),
				Host.Frame(severityProps),
				snackbars(),
				row("Commands", 6, {
					UI.Button "ShowBanner" {
						label = "Pin an offline banner",
						onActivate = function()
							banner:set(not banner:peek())
						end,
					},
					UI.Button "ShowUpdate" {
						label = "Bring the update back",
						onActivate = function()
							shown:set(true)
						end,
					},
				}),
			}
		end

		local function affixed(): any
			return Compose.show(banner, function()
				return UI.Notice "Offline" {
					placement = "affixed",
					severity = "warning",
					message = "Connection interrupted. Reconnecting.",
					onDismiss = function()
						banner:set(false)
					end,
				}
			end)
		end

		return {
			section = section,
			affixed = affixed,
			reset = reset,
			banner = banner,
			show = show,
			entries = entries,
			last = last,
			screen = function()
				return Host.Frame "Notices" {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Host.ScrollingFrame "Content" {
						BackgroundTransparency = 1,
						Size = UDim2.fromScale(1, 1),
						AutomaticCanvasSize = Enum.AutomaticSize.Y,
						CanvasSize = UDim2.new(),
						ScrollBarThickness = 6,
						Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder }),
						section(),
					},
					affixed(),
				}
			end,
			steps = {
				reset = reset,
				banner = function()
					banner:set(true)
				end,
			},
			report = function()
				return { banner = banner:peek(), update = shown:peek(), last = last:peek(), queued = #entries:peek() }
			end,
		}
	end,
}
