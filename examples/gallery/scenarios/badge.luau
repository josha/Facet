--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type PickerOption = typeof(require("@repo/tools/typecheck/aliases").PickerOption)
type ControlSize = typeof(require("@repo/tools/typecheck/aliases").ControlSizeValue)
type ControlSizeCell = typeof(require("@repo/tools/typecheck/aliases").ControlSize)
type ExampleContext = typeof(require("@repo/examples/types").Context)
type BadgeStatus = "neutral" | "info" | "success" | "warning" | "error" | "accent" | "voice" | "contrast"
type ReadOnlyValue<T> = { peek: (ReadOnlyValue<T>) -> T }
type Value<T> =
	ReadOnlyValue<T>
	& { set: (Value<T>, T) -> (), update: (Value<T>, (T) -> T) -> (), dispose: (Value<T>) -> () }
return {
	title = "Badges",
	ledgerRows = {},
	build = function(ctx: ExampleContext)
		local UI, Compose: ComposeModule = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local nativeTypes = ctx.types
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local initialStatus: BadgeStatus = "neutral"
		local initialRung: ControlSize = "compact"
		local status: Value<BadgeStatus> = Compose.cell(initialStatus)
		local rung: ControlSizeCell = Compose.cell(initialRung)
		local rootPath: unknown, controller: unknown, record: GuiObject? = nil, nil, nil
		local function report()
			return { status = status:peek(), controlSize = rung:peek() }
		end
		local function choose(word: BadgeStatus)
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
			local statusOptions: { PickerOption } = {
				{ value = "neutral", label = "Neutral" },
				{ value = "warning", label = "Warning" },
				{ value = "error", label = "Error" },
				{ value = "voice", label = "Voice" },
			}
			local sizeOptions: { PickerOption } = {
				{ value = "compact", label = "Compact" },
				{ value = "large", label = "Large" },
			}
			local root = Host.Frame "BadgeRecipe" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 16),
				}),
				UI.Text "Title" {
					LayoutOrder = 1,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Small labels",
					textRole = "heading",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				UI.Text "Guide" {
					LayoutOrder = 2,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Badges identify something. They do not take focus or run actions.",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				Host.Frame "Forms" {
					LayoutOrder = 3,
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 12),
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Wraps = true,
					}),
					UI.Badge "Standard" {
						LayoutOrder = 1,
						label = "Ready",
						icon = "status.info",
						status = status,
						controlSize = rung,
						ref = function(value)
							record = value
						end,
					},
					UI.Badge "Marked" {
						LayoutOrder = 2,
						label = "Server",
						appearance = "status",
						status = status,
						controlSize = rung,
					},
					UI.Badge "Utility" {
						LayoutOrder = 3,
						label = "Beta",
						appearance = "utility",
						icon = "status.info",
						controlSize = rung,
					},
					UI.Badge "Media" {
						LayoutOrder = 4,
						label = "Featured",
						icon = "status.success",

						status = status,
						controlSize = rung,
					},
				},
				UI.Picker "Status" {
					LayoutOrder = 4,
					label = "Status",
					selected = status,
					options = statusOptions,
				},
				UI.Picker "Size" {
					LayoutOrder = 5,
					label = "Size",
					selected = rung,
					options = sizeOptions,
				},
				Host.Frame "Hosts" {
					LayoutOrder = 6,
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 24),
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Wraps = true,
					}),
					UI.badged(UI.Button "Inbox" { LayoutOrder = 1, label = "Inbox" }, 120),
					UI.badged(UI.Button "Alerts" { LayoutOrder = 2, label = "Alerts", icon = "menu" }, true),
					UI.badged(UI.Avatar "Friend" { LayoutOrder = 3, name = "Alder" }, 3),
				},
			}
			return root
		end
		return {
			section = section,
			reset = reset,
			report = report,
			screen = function()
				return Host.Frame "Badge" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					UI.ScrollView "Content" {
						padding = 16,
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 1, 0),
						ScrollBarThickness = 6,
						section(),
					},
				}
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
