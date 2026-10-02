--!strict
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type ExampleContext = typeof(require("@repo/examples/types")(nil :: any))
return {
	title = "Background transparency",
	build = function(ctx: ExampleContext)
		local Host, UI, Compose: typeof(require("@repo/src/vendor/compose/core")) = ctx.Host, ctx.UI, ctx.Compose
		local UDim, UDim2, Color3, Enum = ctx.types.UDim, ctx.types.UDim2, ctx.types.Color3, ctx.types.Enum
		local gui = ctx.guiService
		local opened = Compose.cell(false)
		local function current()
			local value = if gui then gui.PreferredTransparency else nil
			return if type(value) == "number" then value else 1
		end
		local preference = Compose.cell(current())
		if gui then
			local connection = gui:GetPropertyChangedSignal("PreferredTransparency"):Connect(function()
				preference:set(current())
			end)
			Compose.cleanup(function()
				connection:Disconnect()
			end)
		end
		local function panel(name, transparency)
			return Host.Frame({
				Name = name,
				Size = UDim2.fromOffset(200, 96),
				BackgroundColor3 = Color3.fromRGB(42, 70, 120),
				BackgroundTransparency = transparency,
				UI.Text({ text = name, TextColor3 = Color3.new(1, 1, 1) }),
			})
		end
		local function screen()
			return UI.ScrollView "PreferredTransparency" {
				padding = 16,
				gap = 12,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				UI.Text({ text = "Background transparency", TextSize = 24 }) :: unknown,
				UI.Text({
					text = "Change Background transparency in the Roblox menu under Settings. Facet scales translucent theme surfaces and modal backdrops by your setting. An authored group fade stays independent.",
				}),
				UI.Text "Reading" {
					text = function(use: Use)
						return `Your setting: {math.round(use(preference) * 100)}%`
					end,
				},
				panel("Translucent surface", function(use: Use)
					return 0.5 * use(preference)
				end),
				panel("Opaque panel", 0),
				Host.CanvasGroup "AuthoredFade" {
					Size = UDim2.fromOffset(200, 96),
					BackgroundTransparency = 1,
					GroupTransparency = 0.5,
					panel("Authored fade", 0),
				},
				UI.Button "Open" {
					label = "Open a dialog",
					onActivate = function()
						opened:set(true)
					end,
				},
				UI.Alert "Dialog" {
					isPresented = opened,
					title = "Modal backdrop",
					message = "This backdrop darkens as you lower Background transparency.",
					actions = {
						{ id = "Close", label = "Close", role = "cancel" :: "cancel" } :: typeof(require("@repo/tools/typecheck/example_shapes").AlertAction_any(nil :: any)),
					},
				},
			}
		end
		local function report()
			return { preference = preference:peek(), dialogOpen = opened:peek() }
		end
		return {
			screen = screen,
			report = report,
			steps = {
				openDialog = function()
					opened:set(true)
					return report()
				end,
				closeDialog = function()
					opened:set(false)
					return report()
				end,
			},
		}
	end,
}
