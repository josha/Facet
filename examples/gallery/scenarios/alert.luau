--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type AlertAction = typeof(require("@repo/tools/typecheck/aliases").AlertAction)
type ExampleContext = typeof(require("@repo/examples/types").Context)
type Built = typeof(require("@repo/examples/types").Built)
return {
	title = "Alerts and confirmations",
	ledgerRows = {},
	build = function(ctx: ExampleContext): Built
		local UI, Compose: ComposeModule = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local nativeTypes = ctx.types
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local status = Compose.cell("The save is ready to replace.")
		local presented = Compose.cell(false)
		local function open()
			presented:set(true)
			return true
		end
		local function reset()
			presented:set(false)
			status:set("The save is ready to replace.")
		end
		local function Example()
			local actions: { AlertAction } = {
				{
					id = "Cancel",
					label = "Keep previous",
					role = "cancel",
					onActivate = function()
						status:set("Previous save kept.")
					end,
				},
				{
					id = "Replace",
					label = "Replace save",
					role = "destructive",
					onActivate = function()
						status:set("Checkpoint replaced.")
					end,
				},
			}
			return Host.Frame "Alert" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				UI.ScrollView "Page" {
					padding = 16,
					gap = 16,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					ScrollBarThickness = 6,
					UI.Text({
						LayoutOrder = 1,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = "Alerts and confirmations",
						textRole = "title",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					UI.Text({
						LayoutOrder = 2,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = "A brief decision stays compact. Cancel leads a desktop row; phones and televisions stack the actions with cancel last.",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					UI.Text "Status" {
						LayoutOrder = 3,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = status,
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
					UI.Button "Open" {
						LayoutOrder = 4,
						label = "Replace checkpoint…",
						onActivate = open,
					},
					UI.Button "Reset" {
						LayoutOrder = 5,
						label = "Reset",
						onActivate = reset,
					},
				},
				UI.Alert "ReplaceSave" {
					title = "Replace this save?",
					severity = "critical",
					message = "Your current progress will replace the previous checkpoint.",
					isPresented = presented,
					suppression = { isSuppressed = Compose.cell(false), label = "Do not ask again" },
					actions = actions,
				},
			}
		end
		return {
			screen = Example,
			steps = { open = open, reset = reset },
			states = function(): { { id: string, kind: "dialog", open: () -> boolean } }
				return { { id = "confirmation", kind = "dialog", open = open } }
			end,
			report = function()
				return { status = status:peek(), alert = { presented = presented:peek() } }
			end,
			dispose = function() end,
		}
	end,
}
