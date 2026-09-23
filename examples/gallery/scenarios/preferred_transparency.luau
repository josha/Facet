return {
	title = "Background transparency",
	build = function(ctx)
		local Host, UI, Compose = ctx.Host, ctx.UI, ctx.Compose
		local UDim, UDim2, Color3, Enum = ctx.types.UDim, ctx.types.UDim2, ctx.types.Color3, ctx.types.Enum
		local setting, opened = Compose.cell(1), Compose.cell(false)
		local function panel(name, transparency)
			return Host.Frame({
				Name = name,
				Size = UDim2.fromOffset(200, 96),
				BackgroundColor3 = Color3.fromRGB(42, 70, 120),
				BackgroundTransparency = transparency,
				UI.Label({ label = name, TextColor3 = Color3.new(1, 1, 1) }),
			})
		end
		local function screen()
			return Host.ScrollingFrame({
				Name = "PreferredTransparency",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.new(),
				Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12) }),
				UI.Label({ label = "Background transparency", TextSize = 24 }),
				UI.Label({

					label = "Roblox owns the player's accessibility setting. The slider previews native background transparency; an authored group fade remains independent.",
				}),
				UI.Slider({

					Name = "Setting",
					label = "Preview transparency",
					value = setting,
					min = 0,
					max = 1,
					step = 0.05,
				}),
				panel("Backdrop", function(use)
					return use(setting) * 0.5
				end),
				panel("Opaque panel", 0),
				Host.CanvasGroup({

					Name = "AuthoredFade",
					Size = UDim2.fromOffset(200, 96),
					BackgroundTransparency = 1,
					GroupTransparency = 0.5,
					panel("Authored fade", 0),
				}),
				UI.Button({

					Name = "Open",
					label = "Open a dialog",
					onActivate = function()
						opened:set(true)
					end,
				}),
				UI.Alert({

					Name = "Dialog",
					isPresented = opened,
					title = "A native modal backdrop",
					message = "The control reads Roblox's preference for its backdrop.",
					actions = { { id = "Close", label = "Close", role = "cancel" } },
				}),
			})
		end
		local function report()
			return { setting = setting:peek(), dialogOpen = opened:peek() }
		end
		return {
			screen = screen,
			report = report,
			steps = {
				setFull = function()
					setting:set(1)
					return report()
				end,
				setHalf = function()
					setting:set(0.5)
					return report()
				end,
				setOpaque = function()
					setting:set(0)
					return report()
				end,
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
