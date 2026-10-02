--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type StringCell = typeof(require("@repo/tools/typecheck/aliases").StringCell)
type UnknownCell = typeof(require("@repo/tools/typecheck/aliases").UnknownCell)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type ExampleContext = typeof(require("@repo/examples/types").Context)
return {
	title = "Loading profile pictures",
	build = function(ctx: ExampleContext)
		local UI, Compose: ComposeModule, Host = ctx.UI, ctx.Compose, ctx.Host
		local D, D2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Enum
		local shown = Compose.cell(true)
		local states = {
			(function(value: string): StringCell
				return Compose.cell(value)
			end)("loading"),
			(function(value: string): StringCell
				return Compose.cell(value)
			end)("loading"),
			(function(value: string): StringCell
				return Compose.cell(value)
			end)("loading"),
		}
		local function errorCell(): UnknownCell
			return Compose.cell(nil :: unknown)
		end
		local errors = { errorCell(), errorCell(), errorCell() }
		local pictures = {
			{ id = "AvatarRoblox", image = "rbxthumb://type=AvatarHeadShot&id=1&w=48&h=48" },
			{ id = "AvatarBuilderman", image = "rbxthumb://type=AvatarHeadShot&id=156&w=48&h=48" },
			{ id = "BadAsset", image = "rbxassetid://999999999999999" },
		}
		local function picture(index)
			return UI.AsyncImage({
				Name = pictures[index].id,
				image = pictures[index].image,
				onStatus = function(state: "failed" | "loading" | "ready", message: unknown)
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
				return UI.ScrollView "AsyncImages" {
					padding = 16,
					gap = 12,
					BackgroundTransparency = 1,
					Size = D2.fromScale(1, 1),
					UI.Text({ LayoutOrder = 1, text = "Loading profile pictures", textRole = "title" :: "title" }) :: unknown,
					UI.Text({
						LayoutOrder = 2,
						text = "Pictures keep their space while loading; unavailable pictures keep a placeholder.",
					}),
					UI.Text({
						LayoutOrder = 3,
						text = function(use: Use)
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
						}) :: unknown,
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
				}
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
