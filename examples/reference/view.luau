--!strict
return function(ctx)
	local Host, UI, Compose = ctx.Host, ctx.UI, ctx.Compose
	local D, D2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Enum
	local view = {}
	function view.text(label, size)
		return UI.Text({
			text = label,
			TextSize = size or 16,
			TextWrapped = true,
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
		})
	end
	function view.column(name, children, spacing)
		local props = {
			Name = name,
			BackgroundTransparency = 1,
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
			Host.UIListLayout({
				FillDirection = E.FillDirection.Vertical,
				SortOrder = E.SortOrder.LayoutOrder,
				Padding = D.new(0, spacing or 12),
			}),
		}
		for i, child in children do
			if typeof(child) == "Instance" or type(child) == "table" and child.ClassName then
				child.LayoutOrder = i
			end
			table.insert(props, child)
		end
		return Host.Frame(props)
	end
	function view.page(name, children)
		return Host.ScrollingFrame({
			Name = name,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = D2.fromScale(1, 1),
			CanvasSize = D2.fromOffset(0, 0),
			AutomaticCanvasSize = E.AutomaticSize.Y,
			ScrollBarThickness = 6,
			Host.UIPadding({
				PaddingTop = D.new(0, 16),
				PaddingBottom = D.new(0, 16),
				PaddingLeft = D.new(0, 16),
				PaddingRight = D.new(0, 16),
			}),
			Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }),
			view.column("Content", children, 16),
		})
	end
	function view.action(name, label, command, enabled)
		return UI.Button({
			Name = name,
			label = label,
			onActivate = command,
			enabled = enabled,
			Size = D2.new(1, 0, 0, 44),
			AutomaticSize = E.AutomaticSize.None,
		})
	end
	function view.list(source, render)
		return Compose.keyed({
			from = if Compose.isReadable(source) or type(source) == "function"
				then source
				else function()
					return source
				end,
			key = function(item)
				return item.id
			end,
			render = function(current, index, key)
				local node = render(current, key)
				ctx.runtime.decorate(node, { LayoutOrder = index })
				return node
			end,
		})
	end
	return view
end
