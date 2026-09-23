--!strict
return {
	title = "Loading profile pictures",
	build = function(ctx)
		local UI, Compose, Host = ctx.UI, ctx.Compose, ctx.Host
		local D, D2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Enum
		local shown = Compose.cell(true)
		local states = { Compose.cell("loading"), Compose.cell("loading"), Compose.cell("loading") }
		local errors = { Compose.cell(nil), Compose.cell(nil), Compose.cell(nil) }
		local pictures = {
			{ id = "AvatarRoblox", image = "rbxthumb://type=AvatarHeadShot&id=1&w=48&h=48" },
			{ id = "AvatarBuilderman", image = "rbxthumb://type=AvatarHeadShot&id=156&w=48&h=48" },
			{ id = "BadAsset", image = "rbxassetid://999999999999999" },
		}
		local function picture(index)
			return UI.AsyncImage({
				Name = pictures[index].id,
				image = pictures[index].image,
				onStatus = function(state, message)
					states[index]:set(state)
					errors[index]:set(message)
				end,
			})
		end
		local function report()
			return {
				states = { states[1]:peek(), states[2]:peek(), states[3]:peek() },
				errors = { tostring(errors[3]:peek()) },
			}
		end
		return {
			screen = function()
				return Host.ScrollingFrame({
					Name = "AsyncImages",
					BackgroundTransparency = 1,
					Size = D2.fromScale(1, 1),
					CanvasSize = D2.new(),
					AutomaticCanvasSize = E.AutomaticSize.Y,
					Host.UIListLayout({ Padding = D.new(0, 12), SortOrder = E.SortOrder.LayoutOrder }),
					UI.Label({ LayoutOrder = 1, text = "Loading profile pictures", textRole = "title" }),
					UI.Label({
						LayoutOrder = 2,
						text = "Pictures keep their space while loading; unavailable pictures keep a placeholder.",
					}),
					UI.Label({
						LayoutOrder = 3,
						text = function(use)
							return string.format(
								"Roblox: %s • Builderman: %s • Unavailable picture: %s",
								use(states[1]),
								use(states[2]),
								use(states[3])
							)
						end,
					}),
					Host.Frame({
						LayoutOrder = 4,
						Name = "Row",
						BackgroundTransparency = 1,
						Size = D2.new(1, 0, 0, 48),
						Host.UIListLayout({
							SortOrder = E.SortOrder.LayoutOrder,
							FillDirection = E.FillDirection.Horizontal,
							Padding = D.new(0, 12),
						}),
						picture(1),
						Compose.show(shown, function()
							return picture(2)
						end),
						picture(3),
					}),
					UI.Button({
						LayoutOrder = 5,
						label = "Release second picture",
						onActivate = function()
							shown:set(false)
							states[2]:set("released")
						end,
					}),
				})
			end,
			report = report,
			steps = {
				releaseSecond = function()
					shown:set(false)
					states[2]:set("released")
					return { stateAfter = "released" }
				end,
			},
			reset = function()
				shown:set(true)
			end,
		}
	end,
}
