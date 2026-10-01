--!strict

local outline = {}

function outline.mount(Facet: any, UI: any, Host: any, model: any, actions: any): ScrollingFrame
	local Compose = Facet.Compose
	local selection = Compose.cell({})
	local editing = Compose.cell(nil :: string?)
	local draft = Compose.cell("")
	Compose.watch(function(use)
		local id = use(model).selected
		if use(editing) and use(editing) ~= id then
			editing:set(nil)
		end
		selection:set(if id then { [id] = true } else {})
	end)
	return UI.VirtualList "LayerTree" {
		from = function(use)
			return use(model).rows
		end,
		key = "id",
		itemSize = 44,
		gap = 4,
		selection = selection,
		selectionMode = "single",
		focus = {},
		reorderable = true,
		movable = function(row)
			return row.depth > 0 and editing:peek() == nil
		end,
		onSelectionChange = function(nextSelection)
			for id in nextSelection do
				actions.select(id)
			end
		end,
		onReorder = actions.reorderLayers,
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		UI.fill(),
		Host.UISizeConstraint {
			MaxSize = function(use)
				return Vector2.new(math.huge, math.max(44, #use(model).rows * 48 - 4))
			end,
		},
		render = function(current)
			local id = current:peek().id
			return UI.Button("Layer_" .. id) {
				label = function(use)
					local row = use(current)
					return if use(editing) == id then "" else string.rep("  ", row.depth) .. row.name
				end,
				selected = function(use)
					return use(model).selected == id
				end,
				controlSize = "regular",
				AutomaticSize = Enum.AutomaticSize.None,
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Left,
				help = "Double-click to rename. Drag to move.",
				onActivate = function(input, clicks)
					actions.select(id)
					if
						(input and input.UserInputType == Enum.UserInputType.MouseButton1 and (clicks or 0) >= 1)
						or (input and input.UserInputType == Enum.UserInputType.Keyboard)
					then
						draft:set(current:peek().name)
						editing:set(id)
					end
				end,
				Compose.show(function(use)
					return use(editing) == id
				end, function()
					local field = UI.TextInput("Rename_" .. id) {
						value = draft,
						selectOnFocus = "all",
						maxLength = 120,
						Size = UDim2.fromScale(1, 1),
						ZIndex = 4,
						onCommit = function(name)
							if editing:peek() == id and actions.renameLayer(id, name) then
								editing:set(nil)
							end
						end,
						onCancel = function()
							editing:set(nil)
						end,
					}
					local alive = true
					Compose.cleanup(function()
						alive = false
					end)
					task.defer(function()
						if alive and field.Parent then
							field:CaptureFocus()
						end
					end)
					return field
				end),
			}
		end,
	}
end

return outline
