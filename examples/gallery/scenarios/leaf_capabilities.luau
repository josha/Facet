--!strict

return {
	title = "Leaf capabilities",
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI, Compose = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum

		local TRACK = "Coastal circuit reverse night lap 14"

		local GUEST = "Racer <Nightfall> & Co."

		local ART = "rbxassetid://133513168894379"

		local frozen = Compose.cell(false)
		local narrow = Compose.cell(true)

		local nodes = {}
		local function solvedNameWidth(_built, name)
			local node = nodes[name or "CutMiddle"]
			return if node then node.AbsoluteSize.X else nil
		end
		local function boardOffset(_built)
			return if nodes.Board then nodes.Board.CanvasPosition else nil
		end

		local function Page()
			local function nameWidth(use)
				return if use(narrow) then 160 else 320
			end

			local board = {
				UI.Text "BoardNote" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Touch-drag or scroll in both directions",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
			}
			for row = 1, 3 do
				local tiles = {}
				for col = 1, 4 do
					table.insert(
						tiles,

						Host.Frame({
							Name = `Tile{row}{col}`,
							BackgroundTransparency = 1,
							Size = UDim2.new(0, 140, 0, 56),
							AutomaticSize = Enum.AutomaticSize.Y,
							UI.Text "Label" {
								BackgroundTransparency = 1,
								BorderSizePixel = 0,
								Size = UDim2.new(1, 0, 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								text = `sector {row}-{col}`,
								textRole = "body",
								TextWrapped = true,
								TextYAlignment = Enum.TextYAlignment.Top,
								TextXAlignment = Enum.TextXAlignment.Left,
								Host.UIPadding({
									PaddingTop = UDim.new(0, 4),
									PaddingBottom = UDim.new(0, 4),
									PaddingLeft = UDim.new(0, 4),
									PaddingRight = UDim.new(0, 4),
								}),
							},
						})
					)
				end
				table.insert(
					board,
					Host.Frame({
						Name = `BoardRow{row}`,
						BackgroundTransparency = 1,
						Size = UDim2.new(0, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.XY,
						Host.UIListLayout({
							FillDirection = Enum.FillDirection.Horizontal,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 8),
						}),
						table.unpack(tiles),
					})
				)
			end

			return Host.Frame "Body" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 16),
				}),
				UI.Text "Title" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Leaf capabilities",
					textRole = "title",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				Host.Frame "Actions" {
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
						Wraps = true,
					}),
					UI.Button({
						LayoutOrder = 1,
						Name = "Width",
						label = function(use)
							return if use(narrow) then "Widen" else "Narrow"
						end,
						onActivate = function()
							narrow:set(not narrow:peek())
						end,
					}),
					UI.Button({
						LayoutOrder = 2,
						Name = "Freeze",
						label = function(use)
							return if use(frozen) then "Thaw" else "Freeze"
						end,
						onActivate = function()
							frozen:set(not frozen:peek())
						end,
					}),
				},
				UI.Text "MarkupHeading" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Markup, and the box it reserves",
					textRole = "heading",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				UI.Text "Plain" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Lap record",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
					Host.UIPadding({
						PaddingTop = UDim.new(0, 4),
						PaddingBottom = UDim.new(0, 4),
						PaddingLeft = UDim.new(0, 4),
						PaddingRight = UDim.new(0, 4),
					}),
				},
				UI.Text "Marked" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = '<mark color="#20304a" transparency="0.2"><font color="#cfe4ff">Lap record</font></mark>',
					RichText = true,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
					Host.UIPadding({
						PaddingTop = UDim.new(0, 4),
						PaddingBottom = UDim.new(0, 4),
						PaddingLeft = UDim.new(0, 4),
						PaddingRight = UDim.new(0, 4),
					}),
				},
				UI.Text "Bold" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "<b>Lap record</b>",
					RichText = true,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
					Host.UIPadding({
						PaddingTop = UDim.new(0, 4),
						PaddingBottom = UDim.new(0, 4),
						PaddingLeft = UDim.new(0, 4),
						PaddingRight = UDim.new(0, 4),
					}),
				},
				UI.Text "Heavy" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = '<font weight="heavy">Lap record</font>',
					RichText = true,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
					Host.UIPadding({
						PaddingTop = UDim.new(0, 4),
						PaddingBottom = UDim.new(0, 4),
						PaddingLeft = UDim.new(0, 4),
						PaddingRight = UDim.new(0, 4),
					}),
				},
				UI.Text "Escaped" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "<b>" .. (GUEST:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) .. "</b> joined",
					RichText = true,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				UI.Text "Rtl" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Direction: right to left",
					direction = "rtl",
					TextWrapped = true,
				},
				UI.Text "CutHeading" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Where the cut goes",
					textRole = "heading",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				UI.Text "CutEnd" {
					ref = function(node)
						nodes.CutEnd = node
					end,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = function(use)
						return UDim2.new(0, nameWidth(use), 0, 0)
					end,
					AutomaticSize = Enum.AutomaticSize.Y,
					text = TRACK,
					truncate = "end",
				},
				UI.Text "CutMiddle" {
					ref = function(node)
						nodes.CutMiddle = node
					end,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = function(use)
						return UDim2.new(0, nameWidth(use), 0, 0)
					end,
					AutomaticSize = Enum.AutomaticSize.Y,
					text = TRACK,
					truncate = "middle",
				},
				UI.Text "PictureHeading" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "One picture, two modes",
					textRole = "heading",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				Host.Frame "Pictures" {
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					}),
					Host.ImageLabel({
						LayoutOrder = 1,
						Name = "Tiled",
						ScaleType = Enum.ScaleType.Tile,
						TileSize = UDim2.fromOffset(32, 32),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(0, 96, 0, 64),
						Image = ART,
					}),
					Host.ImageLabel({
						LayoutOrder = 2,
						Name = "Sliced",
						ScaleType = Enum.ScaleType.Slice,
						SliceCenter = ctx.types.Rect.new(16, 16, 48, 48),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(0, 96, 0, 64),
						Image = ART,
					}),
				},
				UI.Text "BoardHeading" {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "A canvas with two axes",
					textRole = "heading",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				(function()
					local node = Host.ScrollingFrame({
						LayoutOrder = 16,
						Name = "Board",
						BackgroundTransparency = 1,
						Size = UDim2.new(0, 320, 0, 140),
						AutomaticCanvasSize = Enum.AutomaticSize.XY,
						CanvasSize = UDim2.new(),
						ScrollingDirection = Enum.ScrollingDirection.XY,
						ScrollingEnabled = function(use)
							return not use(frozen)
						end,
						ScrollBarThickness = 6,
						Host.UIListLayout({
							FillDirection = Enum.FillDirection.Vertical,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 8),
						}),
						Host.UIPadding({
							PaddingTop = UDim.new(0, 8),
							PaddingBottom = UDim.new(0, 8),
							PaddingLeft = UDim.new(0, 8),
							PaddingRight = UDim.new(0, 8),
						}),
						table.unpack(board),
					})
					nodes.Board = node
					return node
				end)(),
			}
		end

		local built: any
		built = {
			screen = function()
				return Host.Frame "LeafCapabilities" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					Host.UIPadding({
						PaddingTop = UDim.new(0, 16),
						PaddingBottom = UDim.new(0, 16),
						PaddingLeft = UDim.new(0, 16),
						PaddingRight = UDim.new(0, 16),
					}),
					Host.ScrollingFrame "Content" {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 1, 0),
						AutomaticCanvasSize = Enum.AutomaticSize.Y,
						CanvasSize = UDim2.new(),
						ScrollBarThickness = 6,
						Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder }),
						Page(),
					},
				}
			end,
			steps = {

				widen = function(built: any)
					narrow:set(false)
					return { width = solvedNameWidth(built) }
				end,
				narrow = function(built: any)
					narrow:set(true)
					return { width = solvedNameWidth(built) }
				end,

				freeze = function(built: any)
					local before = boardOffset(built)
					frozen:set(true)
					return { requestedFrozen = true, offsetBefore = before }
				end,
				thaw = function()
					frozen:set(false)
					return { requestedFrozen = false }
				end,
			},
			report = function()
				return {
					requestedFrozen = frozen:peek(),
					narrow = narrow:peek(),
					track = TRACK,
					guest = GUEST,
					escaped = (GUEST:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")),
					art = ART,
					width = solvedNameWidth(built),
					endWidth = solvedNameWidth(built, "CutEnd"),
					offset = boardOffset(built),
				}
			end,
			reset = function()
				frozen:set(false)
				narrow:set(true)
			end,
		}
		return built
	end,
}
