local CELLS = {
	{ id = "Standings", label = "Standings", spans = { 3, 4, 6 } },
	{ id = "Lap", label = "Lap times", spans = { 3, 2, 3 } },
	{ id = "Media", label = "Replays" },
	{ id = "Notes", label = "Notes", spans = { 3, 6, 12 } },
}
return {
	title = "Measured container grid",
	build = function(ctx)
		local Host, UI, Compose = ctx.Host, ctx.UI, ctx.Compose
		local D, D2, V2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
		local sidebarWidth, guides, media = Compose.cell(360), Compose.cell(false), Compose.cell(true)
		local panels = {}
		local function observe(node, property, cell)
			cell:set(node[property])
			local connection = node:GetPropertyChangedSignal(property):Connect(function()
				cell:set(node[property])
			end)
			Compose.cleanup(function()
				connection:Disconnect()
			end)
		end
		local function panel(name, scale, maxWidth)
			local extent = Compose.cell(V2.zero)
			local geometry = Compose.formula(function(use)
				local width = use(extent).X
				local band = if width >= 960 then 3 elseif width >= 600 then 2 else 1
				local columns = ({ 3, 6, 12 })[band]
				return {
					width = width,
					columns = columns,
					band = band,
					lane = math.max(1, (width - 32 - (columns - 1) * 8) / columns),
				}
			end)
			panels[name] = geometry
			local bodySize = Compose.cell(V2.zero)
			local children = {
				Host.UIListLayout({
					SortOrder = E.SortOrder.LayoutOrder,
					FillDirection = E.FillDirection.Horizontal,
					Wraps = true,
					Padding = D.new(0, 8),
				}),
			}
			for index, item in CELLS do
				local frame = Host.Frame({
					Name = item.id,
					LayoutOrder = index,
					BackgroundTransparency = 0,
					Visible = function(use)
						return item.id ~= "Media" or use(media)
					end,
					Size = function(use)
						local g = use(geometry)
						local span = if item.spans then item.spans[g.band] else math.min(4, g.columns)
						return D2.fromOffset(span * g.lane + (span - 1) * 8, 0)
					end,
					AutomaticSize = E.AutomaticSize.Y,
					Host.UISizeConstraint({ MinSize = V2.new(0, 44) }),
					Host.UIPadding({
						PaddingLeft = D.new(0, 8),
						PaddingRight = D.new(0, 8),
						PaddingTop = D.new(0, 8),
						PaddingBottom = D.new(0, 8),
					}),
					UI.Label({
						Text = item.label,
						TextWrapped = true,
						Size = D2.new(1, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.Y,
					}),
				})
				frame:AddTag("facet-control")
				table.insert(children, frame)
			end
			local cells = Host.Frame({
				Name = "Cells",
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				BackgroundTransparency = 1,
				table.unpack(children),
			})
			observe(cells, "AbsoluteSize", bodySize)
			local lanes = {}
			for index = 1, 12 do
				table.insert(
					lanes,
					Host.Frame({
						Name = "Lane" .. index,
						BorderSizePixel = 0,
						BackgroundTransparency = 0.82,
						Visible = function(use)
							return use(guides) and index <= use(geometry).columns
						end,
						Size = function(use)
							return D2.fromOffset(use(geometry).lane, use(bodySize).Y)
						end,
						Position = function(use)
							return D2.fromOffset((index - 1) * (use(geometry).lane + 8), 0)
						end,
					})
				)
			end
			local root = Host.Frame({
				Name = name,
				Size = D2.new(scale, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Host.UISizeConstraint({ MaxSize = V2.new(maxWidth and maxWidth:peek() or 100000, 100000) }),
				Host.UIPadding({
					PaddingLeft = D.new(0, 16),
					PaddingRight = D.new(0, 16),
					PaddingTop = D.new(0, 12),
					PaddingBottom = D.new(0, 12),
				}),
				Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = D.new(0, 8) }),
				UI.Label({
					Name = "Heading",
					Text = function(use)
						local g = use(geometry)
						return string.format("%s · %d px · %d columns", name, g.width, g.columns)
					end,
					TextWrapped = true,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
				}),
				Host.Frame({
					Name = "Grid",
					BackgroundTransparency = 1,
					Size = function(use)
						return D2.new(1, 0, 0, use(bodySize).Y)
					end,
					cells,
					Host.Frame({
						Name = "Guides",
						BackgroundTransparency = 1,
						Size = D2.fromScale(1, 1),
						ZIndex = 2,
						table.unpack(lanes),
					}),
				}),
			})
			if maxWidth then
				ctx.runtime.decorate(root:FindFirstChildWhichIsA("UISizeConstraint"), {
					MaxSize = function(use)
						return V2.new(use(maxWidth), 100000)
					end,
				})
			end
			observe(root, "AbsoluteSize", extent)
			root:AddTag("facet-surface")
			return root
		end
		return {
			screen = function()
				return Host.ScrollingFrame({
					Name = "ContainerGrid",
					Size = D2.fromScale(1, 1),
					AutomaticCanvasSize = E.AutomaticSize.Y,
					CanvasSize = D2.new(),
					BackgroundTransparency = 1,
					Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = D.new(0, 12) }),
					UI.Label({ Text = "One screen, three containers", textRole = "title" }),
					UI.Label({
						Text = "Each panel reads its own width; its cells use the actual space inside the frame.",
						TextWrapped = true,
					}),
					Host.Frame({
						Name = "Actions",
						Size = D2.new(1, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.Y,
						BackgroundTransparency = 1,
						Host.UIListLayout({
							SortOrder = E.SortOrder.LayoutOrder,
							FillDirection = E.FillDirection.Horizontal,
							Wraps = true,
							Padding = D.new(0, 8),
						}),
						UI.Button({
							Name = "Resize",
							label = "Resize sidebar",
							onActivate = function()
								sidebarWidth:set(if sidebarWidth:peek() == 360 then 1040 else 360)
							end,
						}),
						UI.Button({
							Name = "GuidesToggle",
							label = "Toggle grid guides",
							onActivate = function()
								guides:set(not guides:peek())
							end,
						}),
						UI.Button({
							Name = "Replays",
							label = "Toggle replays",
							onActivate = function()
								media:set(not media:peek())
							end,
						}),
					}),
					panel("Sidebar", 1, sidebarWidth),
					panel("Column", 0.65),
					panel("Board", 1),
				})
			end,
			report = function()
				local result = { guides = guides:peek(), media = media:peek(), sidebarWidth = sidebarWidth:peek() }
				for name, geometry in panels do
					result[name] = geometry:peek()
				end
				return result
			end,
		}
	end,
}
