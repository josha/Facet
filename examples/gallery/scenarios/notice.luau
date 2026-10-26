--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ExampleContext = typeof(require("@repo/examples/types").Context)
type BooleanCell = typeof(require("@repo/tools/typecheck/aliases").BooleanCell)
type OverlayAction = typeof(require("@repo/tools/typecheck/aliases").OverlayAction)
type TextValue = typeof(require("@repo/tools/typecheck/aliases").TextPropsText)
type ToastSpec = typeof(require("@repo/tools/typecheck/aliases").ToastSpec)
type ReadOnlyValue<T> = { peek: (ReadOnlyValue<T>) -> T }
type Use = <T>(ReadOnlyValue<T>) -> T
type NoticeSeverity = "info" | "success" | "warning" | "error"
type ToastAction = { label: string, onActivate: () -> () }
type ToastExtra = {
	duration: number?,
	icon: string?,
	action: ToastAction?,
	closeButton: boolean?,
	priority: number?,
}
type Entry = { id: number, fact: BooleanCell, spec: ToastSpec }

return {
	title = "Notices",
	ledgerRows = {},
	build = function(ctx: ExampleContext)
		local UI, Compose: ComposeModule, Host = ctx.UI, ctx.Compose, ctx.Host
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Enum = Enum }
		local UDim, UDim2, Enum = nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Enum
		local shown = Compose.cell(true)
		local banner = Compose.cell(false)
		local last = Compose.cell("Last: nothing yet")
		local refuse = Compose.cell(false)
		local undone = Compose.cell(0)
		local initialEntries: { Entry } = {}
		local entries = Compose.cell(initialEntries)
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

		local function show(message: string, extra: ToastExtra?)
			serial += 1
			local id = serial
			local fact = Compose.cell(true)
			local options: ToastExtra = extra or {}
			local spec: ToastSpec = {
				Name = `Snack{id}`,
				isPresented = fact,
				message = message,
				onPresentedChange = function(nextValue: boolean)
					if not refuse:peek() then
						fact:set(nextValue)
					end
				end,
				onDismiss = function(reason: string)
					last:set(`Last: toast {reason}`)
					release(id)
				end,
				duration = options.duration,
				icon = options.icon,
				action = options.action,
				closeButton = options.closeButton,
				priority = options.priority,
			}
			local list = table.clone(entries:peek())
			table.insert(list, { id = id, fact = fact, spec = spec })
			entries:set(list)
		end

		local undo: ToastAction = {
			label = "Undo",
			onActivate = function()
				undone:set(undone:peek() + 1)
			end,
		}

		local function label(name: string, text: TextValue, order: number, role: "heading"?)
			return UI.Text({
				Name = name,
				LayoutOrder = order,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				text = text,
				textRole = role,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end

		local function row(name: string, order: number, children: { GuiObject }): Frame
			for index, child in children do
				child.LayoutOrder = index
			end
			return Host.Frame(name)({
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
				table.unpack(children),
			})
		end

		local function snackbars(): Frame
			return Host.Frame("Toasts")({
				LayoutOrder = 5,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 8),
				}),
				label("ToastTitle", "Toasts", 1, "heading"),
				label("Undone", function(use: Use): string
					local n = use(undone)
					return `Undo pressed {n} {if n == 1 then "time" else "times"}; the toast stays until you close it.`
				end, 2),
				row("Compositions", 3, {
					UI.Button "SnackMessage" {
						label = "Message",
						onActivate = function()
							show("Saved to your garage.", { duration = 4 })
						end,
					},
					UI.Button "SnackIcon" {
						label = "Icon and message",
						onActivate = function()
							show("Lap record saved.", { icon = "status.success", duration = 4 })
						end,
					},
					UI.Button "SnackAction" {
						label = "With action",
						onActivate = function()
							show("Kart sold.", { action = undo, closeButton = false, duration = 6 })
						end,
					},
					UI.Button "SnackClose" {
						label = "Action and close",
						onActivate = function()
							show("Friend request sent.", { action = undo })
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
						label = "Burst of twelve",
						onActivate = function()
							for index = 1, 12 do
								show(`Queued message {index} of 12.`, { duration = 3 })
							end
						end,
					},
				}),
				Compose.keyed({
					from = entries,
					key = function(entry: Entry): number
						return entry.id
					end,
					render = function(item: ReadOnlyValue<Entry>): GuiObject
						local entry: Entry = item:peek()
						return UI.Toast(entry.spec)
					end,
				}),
			})
		end

		local function reset()
			shown:set(true)
			banner:set(false)
			last:set("Last: nothing yet")
			refuse:set(false)
			undone:set(0)
			entries:set({})
		end

		local function section(order: number?): Frame
			local severities: { GuiObject } = {}
			local severityOrder: { NoticeSeverity } = { "info", "success", "warning", "error" }
			for index, severity: NoticeSeverity in severityOrder do
				table.insert(
					severities,
					UI.Notice({
						Name = `Severity-{severity}`,
						LayoutOrder = index,
						severity = severity,
						appearance = "emphasis",
						message = `{if severity == "info" or severity == "error" then "An" else "A"} {severity} notice, in its severity's colour.`,
					})
				)
			end
			local installActions: { OverlayAction } = {
				{
					id = "Install",
					label = "Install",
					role = "default",
					onActivate = function()
						last:set("Last: install")
					end,
				},
			}
			return Host.Frame("NoticeRecipe")({
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
						actions = installActions,
						onDismiss = function()
							shown:set(false)
						end,
					}
				end),
				Host.Frame("Severities")({
					LayoutOrder = 4,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					}),
					table.unpack(severities),
				}),
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
			})
		end

		local function affixed()
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
				return Host.Frame("Notices")({
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					UI.ScrollView "Content" {
						padding = 16,
						BackgroundTransparency = 1,
						Size = UDim2.fromScale(1, 1),
						ScrollBarThickness = 6,
						section(),
					},
					affixed(),
				})
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
