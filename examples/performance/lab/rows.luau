--!strict
local rows = { VERSION = "native-perf-rows/2", ITEM_SIZE = 56, COMPACT_ITEM_SIZE = 152 }
function rows.estimate(ctx)
	return if ctx.viewport and ctx.viewport.w < 720 then rows.COMPACT_ITEM_SIZE else rows.ITEM_SIZE
end
function rows.build(ctx, current, options)
	local Compose, Host, UI, T = ctx.Facet.Compose, ctx.Host, ctx.UI, ctx.types
	local D2, E = T.UDim2, T.Enum
	local full = not options or options.full ~= false
	local item = current:peek()
	ctx.rowModels = ctx.rowModels or { values = {}, toggles = {} }
	local models = ctx.rowModels
	models.values[item.id] = models.values[item.id] or Compose.cell(item.value or 0.5)
	models.toggles[item.id] = models.toggles[item.id] or Compose.cell(item.enabled == true)
	local checked, value = if full then models.toggles[item.id] else Compose.cell(false), models.values[item.id]
	local minimum = Compose.cell(if full then rows.estimate(ctx) else rows.ITEM_SIZE)
	local image = {
		Name = "Portrait",
		LayoutOrder = 1,
		Size = D2.fromOffset(40, 40),
		BackgroundTransparency = 1,
	}
	if full then
		image.source = function(use)
			return use(current).imageKey
		end
		if ctx.engine then
			image.loader = function(content, resolve)
				resolve(content)
			end
		end
	else
		image.Image = function(use)
			return use(current).imageKey
		end
	end
	local children = {
		Size = function(use)
			return D2.new(1, 0, 0, use(minimum))
		end,
		AutomaticSize = E.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Host.UIListLayout({
			FillDirection = E.FillDirection.Horizontal,
			VerticalAlignment = E.VerticalAlignment.Center,
			SortOrder = E.SortOrder.LayoutOrder,
			Wraps = true,
			Padding = T.UDim.new(0, 8),
		}),
		if full then UI.AsyncImage(image) else Host.ImageLabel(image),
		Host.Frame({
			Name = "Copy",
			LayoutOrder = 2,
			Size = D2.fromOffset(0, 0),
			AutomaticSize = E.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Host.UISizeConstraint({ MinSize = T.Vector2.new(120, 40) }),
			Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
			Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = T.UDim.new(0, 2) }),
			UI.Label({
				Name = "Title",
				TextSize = if full then nil else 16,
				LayoutOrder = 1,
				text = function(use)
					return use(current).name
				end,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				TextXAlignment = E.TextXAlignment.Left,
				TextTruncate = E.TextTruncate.AtEnd,
			}),
			UI.Label({
				Name = "Detail",
				TextSize = if full then nil else 13,
				LayoutOrder = 2,
				text = function(use)
					return use(current).detail or "Lap 1"
				end,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				TextXAlignment = E.TextXAlignment.Left,
				TextTruncate = E.TextTruncate.AtEnd,
			}),
		}),
		UI.Toggle({
			Name = "Ready",
			LayoutOrder = 3,
			label = if full then "Ready" else "Favourite",
			value = checked,
		}),
	}
	if full then
		table.insert(
			children,
			UI.Stepper({
				Name = "Rate",
				LayoutOrder = 4,
				label = "Rate",
				value = value,
				min = 0,
				max = 1,
				step = 0.05,
				format = function(next)
					return string.format("%d%%", math.floor(next * 100 + 0.5))
				end,
			})
		)
		table.insert(
			children,
			UI.Button({
				Name = "Open",
				LayoutOrder = 5,
				label = "Open",
				onActivate = function()
					if ctx.onRowActivate then
						ctx.onRowActivate(current:peek())
					end
				end,
			})
		)
	end
	local node = Host.Frame(children)
	if full then
		local connection = node:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			local width = node.AbsoluteSize.X
			if width > 0 then
				minimum:set(if width < 720 then rows.COMPACT_ITEM_SIZE else rows.ITEM_SIZE)
			end
		end)
		Compose.cleanup(function()
			connection:Disconnect()
		end)
	end
	return node
end
return rows
