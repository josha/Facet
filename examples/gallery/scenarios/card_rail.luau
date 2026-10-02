--!strict
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type ExampleContext = typeof(require("@repo/examples/types")(nil :: any))
local BADGES = { "Rally", "Drift", "Circuit", "Sprint", "Endurance" }
local COPY = {
	title = "Card rail — your racing collection",
	hint = "Browse each shelf sideways · Up/Down changes shelves · A or Return picks",
	selectedNone = "Selected: none yet — activate a card",
	selectedPrefix = "Selected: ",
	weekendTitle = "Weekend races",
	recommendedTitle = "Recommended for you",
}
return {
	title = "Card rail (horizontal VirtualList)",
	copy = COPY,
	build = function(ctx: ExampleContext)
		local Compose: typeof(require("@repo/src/vendor/compose/core")), UI, Host = ctx.Compose, ctx.UI, ctx.Host
		local D, D2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Enum
		local copy = ctx.copy or COPY
		local cards = {}
		for index = 1, 400 do
			cards[index] = {
				id = "c" .. index,
				name = string.format("Livery %03d", index),
				badge = BADGES[(index - 1) % #BADGES + 1],
			}
		end
		local items, selected = Compose.cell(cards), Compose.cell(nil :: string | nil)
		local rails = {}
		local function observe(
			node: GuiObject,
			property: string
		): typeof(require("@repo/tools/typecheck/example_shapes").vectorCell(nil :: any))
			local value = Compose.cell((node :: any)[property] :: Vector2)
			local connection = node:GetPropertyChangedSignal(property):Connect(function()
				value:set((node :: any)[property])
			end)
			Compose.cleanup(function()
				connection:Disconnect()
			end)
			return value
		end
		local function label(name, text, order, size)
			return UI.Text({
				Name = name,
				text = text,
				TextSize = size or 18,
				LayoutOrder = order,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				TextWrapped = true,
				BackgroundTransparency = 1,
			})
		end
		local function rail(name, order)
			local cardWidth = Compose.cell(240)
			local nameProbe = UI.Text "NameMeasure" {
				Visible = false,
				text = "Livery 000",
				textRole = "label" :: "label",
				Size = D2.new(),
				AutomaticSize = E.AutomaticSize.XY,
			}
			local badgeProbe = UI.Text "BadgeMeasure" {
				Visible = false,
				text = "Endurance",
				textRole = "caption" :: "caption",
				Size = D2.new(),
				AutomaticSize = E.AutomaticSize.XY,
			}
			local nameBounds, badgeBounds = observe(nameProbe, "TextBounds"), observe(badgeProbe, "TextBounds")
			local height = Compose.formula(function(use: Use)
				return math.ceil(math.max(1, use(cardWidth) - 16) * 9 / 16)
					+ math.max(20, use(nameBounds).Y)
					+ math.max(18, use(badgeBounds).Y)
					+ 28
			end)
			local status = (function(): typeof(require("@repo/tools/typecheck/example_shapes").collectionStatusCell(
				nil :: any
			))
				return Compose.cell({
					mode = "windowed" :: "windowed" | "all",
					direction = "horizontal" :: "horizontal" | "vertical",
					total = 0,
					retained = 0,
					first = 0,
					last = 0,
					firstRow = 0,
					lastRow = 0,
					rowCount = 0,
					extent = 0,
					following = false,
					measured = 0,
				})
			end)()
			local node = UI.VirtualList({
				Name = name,
				from = items,
				key = function(item)
					return item.id
				end,
				direction = "horizontal" :: "horizontal" | "vertical",
				itemSize = "cards" :: "cards",
				gap = 8,
				overscan = 2,
				status = status,
				LayoutOrder = order,
				Size = function(use: Use)
					return D2.new(1, 0, 0, use(height))
				end,
				render = function(current, placement, key): GuiObject
					Compose.watch(function(use: Use)
						local extent = use(placement).size
						if extent > 1 and cardWidth:peek() ~= extent then
							cardWidth:set(extent)
						end
					end)
					local track = Host.Path2D "Track" { Thickness = 5 }
					local points = {}
					local pointType = ctx.types.Path2DControlPoint or Path2DControlPoint
					for index = 0, 16 do
						local angle = index * math.pi / 8
						points[index + 1] =
							pointType.new(D2.fromScale(0.5 + math.cos(angle) * 0.36, 0.5 + math.sin(angle) * 0.36))
					end
					track:SetControlPoints(points)
					return UI.Button({
						Name = "Card_" .. key,
						label = "",
						Size = D2.fromScale(1, 1),
						AutomaticSize = E.AutomaticSize.None,
						onActivate = function()
							selected:set(key)
						end,
						Host.Frame "Card" {
							BackgroundTransparency = 1,
							Size = D2.new(1, -16, 1, -16),
							Position = D2.fromOffset(8, 8),
							Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = D.new(0, 2) }) :: unknown,
							Host.Frame "Preview" {
								LayoutOrder = 1,
								Size = D2.new(1, 0, 0, 0),
								BackgroundTransparency = 0.82,
								Host.UIAspectRatioConstraint({
									AspectRatio = 16 / 9,
									DominantAxis = E.DominantAxis.Width,
								}) :: unknown,
								track,
							},
							UI.Text "Name" {
								text = function(use: Use)
									return use(current).name
								end,
								textRole = "label" :: "label",
								LayoutOrder = 2,
								Size = D2.new(1, 0, 0, 0),
								AutomaticSize = E.AutomaticSize.Y,
								TextWrapped = false,
								TextTruncate = E.TextTruncate.AtEnd,
								BackgroundTransparency = 1,
							},
							UI.Text "Badge" {
								text = function(use: Use)
									return use(current).badge
								end,
								textRole = "caption" :: "caption",
								LayoutOrder = 3,
								Size = D2.new(1, 0, 0, 0),
								AutomaticSize = E.AutomaticSize.Y,
								TextWrapped = false,
								TextTruncate = E.TextTruncate.AtEnd,
								BackgroundTransparency = 1,
							},
						},
					})
				end,
				nameProbe :: unknown,
				badgeProbe,
			})
			rails[name] = { node = node, cardWidth = cardWidth, status = status }
			return node
		end
		return {
			screen = function()
				return UI.ScrollView "CardRail" {
					padding = 16,
					gap = 8,
					Size = D2.fromScale(1, 1),
					BackgroundTransparency = 1,
					label("Title", copy.title, 1, 24) :: unknown,
					label("Hint", copy.hint, 2, 14),
					rail("Rail", 3),
					label("Selected", function(use: Use)
						local key = use(selected)
						for _, card in use(items) do
							if card.id == key then
								return copy.selectedPrefix .. card.name .. " · " .. card.badge
							end
						end
						return copy.selectedNone
					end, 4, 13),
					label("WeekendTitle", copy.weekendTitle, 5, 22),
					rail("WeekendRail", 6),
					label("RecommendedTitle", copy.recommendedTitle, 7, 22),
					rail("RecommendedRail", 8),
				}
			end,
			report = function()
				local result =
					{ axis = "x" :: "x", shelves = 3, total = #items:peek(), selectedKey = selected:peek(), rails = {} }
				for name, value in rails do
					result.rails[name] = {
						itemExtent = value.cardWidth:peek(),
						status = value.status:peek(),
						offset = value.node.CanvasPosition.X,
					}
				end
				return result
			end,
		}
	end,
}
