--!strict
local ControlTypes = require("./control_types")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local Nav = require("./navigation_types")
local MenuItems = require("./nav_menu_items")
local Theme = require("./theme_types")

export type RowState = {
	hitFloor: (ComposeTypes.Use?) -> number,
	sheeted: ComposeTypes.Readable<boolean>,
	path: ComposeTypes.Readable<{ string }>,
	rowNodes: { [string]: GuiObject },
	widths: ComposeTypes.Cell<{ [string]: number }>,
	enter: (string, GuiObject?, { string }?) -> (),
	close: () -> (),
}
export type AncestorLevel<V> = { id: string, items: { Nav.MenuItem<V> }, prefix: { string }, depth: number }

return function(ctx: Types.Context, UI: ControlTypes.BuilderControls, surfaces: Nav.Surfaces)
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local E, D2, V2, D = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2, ctx.types.UDim
	local itemModel = MenuItems(ctx)
	local actionItem, commitItem = itemModel.actionItem, itemModel.commitItem
	local function trailingMark(
		row: GuiObject,
		name: string,
		selected: (ComposeTypes.Use) -> boolean,
		enabled: Types.Value<boolean>
	)
		row:AddTag("facet-menu-mark")
		local state = if ctx.iconVaries(name) then ctx.observe.GuiState(row) else nil
		runtime.mountFragment(function()
			return {
				Host.UIPadding({
					PaddingRight = if ctx.config.theme == nil
						then D.new(0, ctx.controlSize(nil, "iconSize") + 8)
						else nil,
				}),
				ctx.icon(
					name,
					{
						Name = "TrailingIcon",
						AnchorPoint = V2.new(1, 0.5),
						Position = function(use: ComposeTypes.Use): UDim2
							return D2.new(1, ctx.controlSize(nil, "iconSize", use) + 8, 0.5, 0)
						end,
					},
					if state
						then function(use: ComposeTypes.Use): Theme.SkinState
							return if read(enabled, use) == false
								then "disabled"
								elseif use(state) == E.GuiState.Press then "pressed"
								elseif use(state) == E.GuiState.Hover then "hover"
								elseif selected(use) then "selected"
								else "default"
						end
						else nil
				),
			}
		end, row)
	end
	local function fillTitle(button: GuiObject)
		local content = button:FindFirstChild("Content")
		local words = content and (content:FindFirstChild("Captions") or content:FindFirstChild("Title"))
		if content and content:IsA("GuiObject") and content.Size.X.Scale == 0 then
			content.Size = ctx.types.UDim2.new(1, 0, content.Size.Y.Scale, content.Size.Y.Offset)
			content.AutomaticSize = if content.AutomaticSize == ctx.types.Enum.AutomaticSize.None
				then ctx.types.Enum.AutomaticSize.None
				else ctx.types.Enum.AutomaticSize.Y
		end
		if words and not words:FindFirstChildWhichIsA("UIFlexItem") then
			runtime.mount(function()
				return Host.UIFlexItem({ FlexMode = ctx.types.Enum.UIFlexMode.Fill })
			end, words)
		end
	end
	local function entryRow<V>(
		entrySource: ComposeTypes.Readable<MenuItems.MenuEntry<V>>,
		index: ComposeTypes.Readable<number>,
		state: RowState
	): GuiObject
		local hitFloor, sheeted, rowNodes, widths, enter, close =
			state.hitFloor, state.sheeted, state.rowNodes, state.widths, state.enter, state.close
		local entry = entrySource:peek()
		if entry.heading then
			local title = ctx.text({
				Name = "SectionTitle",
				Text = function(use: ComposeTypes.Use): string
					return use(entrySource).heading or ""
				end,
			})
			title:AddTag("facet-type-caption")
			title:AddTag("facet-secondary")
			return Host.Frame(entry.key)({
				LayoutOrder = index,
				BackgroundTransparency = 1,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				ctx.padding(12, 4) :: Types.Child,
				title :: Types.Child,
			})
		end
		local source = Compose.formula(function(use: ComposeTypes.Use): Nav.MenuItem<V>
			return assert(use(entrySource).item)
		end)
		local item = source:peek()
		if item.divider then
			return ctx.styled(Host.Frame "Divider" { Size = D2.new(1, 0, 0, 1), LayoutOrder = index }, "divider")
		end
		local rowKey = tostring(item.id or index:peek())
		local trailing = if item.children
			then "chevron.trailing"
			elseif item.checked ~= nil or item.selected ~= nil or item.marked ~= nil then "checkmark"
			else nil
		local simple = item.icon == nil
			and item.description == nil
			and item.avatar == nil
			and ctx.config.controlSize == nil
		local function selected(use: ComposeTypes.Use): boolean
			local live = actionItem(use(source))
			return if live.checked
				then use(live.checked)
				elseif live.selected then use(live.selected) == live.value
				else read(live.marked, use) == true
		end
		local function enabled(use: ComposeTypes.Use): boolean
			return read(actionItem(use(source)).enabled, use) ~= false
		end
		local row: TextButton
		row = UI.Button({
			Name = rowKey,
			LayoutOrder = index,
			Size = function(use: ComposeTypes.Use)
				return D2.new(1, 0, 0, hitFloor(use))
			end,
			label = function(use: ComposeTypes.Use)
				return read(actionItem(use(source)).label, use)
			end,
			icon = item.icon,
			role = item.role,
			trailingIcon = if simple then nil else trailing,
			subtitle = if item.description ~= nil or item.avatar ~= nil
				then function(use: ComposeTypes.Use)
					return read(actionItem(use(source)).description, use) or ""
				end
				else nil,
			TextXAlignment = E.TextXAlignment.Left,
			enabled = enabled,
			selected = selected,
			onActivate = function()
				local live = actionItem(source:peek())
				if read(live.enabled) == false then
					return
				end
				if live.children then
					enter(assert(live.id), row)
				elseif
					commitItem(live)
					and (live.dismiss == true or (live.dismiss ~= false and not live.checked and not live.selected))
				then
					close()
				end
			end,
		})
		if simple and trailing then
			trailingMark(row, trailing, selected, enabled)
		end
		row:AddTag("facet-menu-item")
		rowNodes[rowKey] = row
		Compose.cleanup(function()
			if rowNodes[rowKey] == row then
				rowNodes[rowKey] = nil
			end
		end)
		fillTitle(row)
		surfaces.attach(row, {
			ctx.styled(
				Host.Frame({
					Name = "Hairline",
					Size = D2.new(1, 0, 0, 1),
					ZIndex = 3,
					Visible = function(use: ComposeTypes.Use)
						return use(entrySource).ruled == true and not use(sheeted)
					end,
				}),
				"menu-hairline"
			) :: Types.Child,
		})
		Compose.watch(function(use: ComposeTypes.Use)
			if hitFloor(use) < ctx.metric("targetSizes.minimum", use) then
				row:AddTag("facet-menu-dense")
			elseif row:HasTag("facet-menu-dense") then
				row:RemoveTag("facet-menu-dense")
			end
		end)
		local accessories: { Types.Child } = {}
		if item.badge ~= nil then
			table.insert(
				accessories,
				UI.Badge({
					Name = "Count",
					LayoutOrder = 1,
					label = function(use: ComposeTypes.Use): string
						local badge = read(actionItem(use(source)).badge, use)
						return if badge == nil then "" else tostring(badge)
					end,
				}) :: Types.Child
			)
		end
		if item.meta ~= nil then
			local meta = ctx.text({
				Name = "Meta",
				LayoutOrder = 0,
				Text = function(use: ComposeTypes.Use): string
					return read(actionItem(use(source)).meta, use) or ""
				end,
			})
			meta:AddTag("facet-secondary")
			table.insert(accessories, meta :: Types.Child)
		end
		if item.shortcutLabel ~= nil then
			local shortcut = ctx.text({
				Name = "Shortcut",
				LayoutOrder = 2,
				Text = function(use: ComposeTypes.Use): string
					return read(actionItem(use(source)).shortcutLabel, use) or ""
				end,
			})
			shortcut:AddTag("facet-secondary")
			table.insert(accessories, shortcut :: Types.Child)
		end
		if #accessories > 0 then
			surfaces.attach(row, {
				Host.Frame "Accessories" {
					BackgroundTransparency = 1,
					AnchorPoint = V2.new(1, 0.5),
					Position = D2.new(1, if item.checked or item.selected or item.marked then -32 else 0, 0.5, 0),
					Size = D2.fromOffset(0, 0),
					AutomaticSize = E.AutomaticSize.XY,
					ZIndex = 2,
					Host.UIListLayout({
						FillDirection = E.FillDirection.Horizontal,
						SortOrder = E.SortOrder.LayoutOrder,
						VerticalAlignment = E.VerticalAlignment.Center,
						Padding = D.new(0, 8),
					}),
					table.unpack(accessories),
				} :: Types.Child,
			})
		end
		local avatar = item.avatar
		local rowContent = row:FindFirstChild("Content")
		if avatar and rowContent then
			runtime.mount(function()
				return UI.Avatar({
					Name = "Avatar",
					LayoutOrder = 0,
					name = avatar.name,
					image = avatar.image,
					userId = avatar.userId,
					controlSize = "compact" :: Types.ControlSize,
					Selectable = false,
					Active = false,
					Interactable = false,
				})
			end, rowContent)
		end
		local check = if item.children then nil else row:FindFirstChild("TrailingIcon", true)
		if check and check:IsA("GuiObject") then
			Compose.watch(function(use: ComposeTypes.Use)
				local live = actionItem(use(source))
				check.Visible = if live.checked
					then use(live.checked) == true
					elseif live.selected then use(live.selected) == live.value
					else read(live.marked, use) == true
			end)
		end
		if item.role == "destructive" then
			row:AddTag("facet-menu-destructive")
		end
		local content = row:FindFirstChild("Content") or row
		if content:IsA("GuiObject") then
			local layout = content:FindFirstChildWhichIsA("UIListLayout")
			if layout then
				layout.HorizontalAlignment = E.HorizontalAlignment.Left
			end
			local natural: ComposeTypes.Readable<Vector2> = if content == row
				then ctx.observe.TextBounds(row)
				else ctx.observe.AbsoluteSize(content)
			local words = content:FindFirstChild("Captions") or content:FindFirstChild("Title")
			local wordsBox: ComposeTypes.Readable<Vector2>? = nil
			local wordsNatural: ComposeTypes.Readable<Vector2>? = nil
			if words and words:IsA("TextLabel") then
				wordsBox, wordsNatural = ctx.observe.AbsoluteSize(words), ctx.observe.TextBounds(words)
			elseif words and words:IsA("GuiObject") then
				local stack = words:FindFirstChildWhichIsA("UIListLayout")
				if stack then
					wordsBox, wordsNatural = ctx.observe.AbsoluteSize(words), ctx.observe.AbsoluteContentSize(stack)
				end
			end
			Compose.watch(function(use: ComposeTypes.Use)
				local width = use(natural).X
				if simple and trailing then
					width += ctx.controlSize(nil, "iconSize", use) + 8
				end
				if wordsBox and wordsNatural then
					width = width - use(wordsBox).X + use(wordsNatural).X
				end
				local next = table.clone(widths:peek())
				next[rowKey] = width
				widths:set(next)
			end)
			Compose.cleanup(function()
				local next = table.clone(widths:peek())
				next[rowKey] = nil
				widths:set(next)
			end)
		end
		return row
	end
	local function ancestorRow<V>(
		row: ComposeTypes.Readable<Nav.MenuItem<V>>,
		index: ComposeTypes.Readable<number>,
		source: ComposeTypes.Readable<AncestorLevel<V>>,
		state: RowState
	): GuiObject
		local hitFloor, path, enter, close = state.hitFloor, state.path, state.enter, state.close
		local item = row:peek()
		if item.divider then
			return ctx.styled(Host.Frame({ Size = D2.new(1, 0, 0, 1), LayoutOrder = index }), "divider")
		end
		local button: GuiObject
		button = UI.Button({
			Name = item.id,
			label = item.label,
			enabled = item.enabled,
			icon = item.icon,
			subtitle = item.description,
			TextXAlignment = E.TextXAlignment.Left,
			LayoutOrder = index,
			Size = function(use: ComposeTypes.Use)
				return D2.new(1, 0, 0, hitFloor(use))
			end,
			selected = function(use: ComposeTypes.Use)
				if use(path)[use(source).depth] == item.id then
					return true
				end
				local live = actionItem(item)
				return if live.checked
					then use(live.checked)
					elseif live.selected then use(live.selected) == live.value
					else read(live.marked, use) == true
			end,
			trailingIcon = if item.children
				then "chevron.trailing"
				elseif item.checked ~= nil or item.selected ~= nil or item.marked ~= nil then "checkmark"
				else nil,
			onActivate = function()
				if item.children then
					enter(assert(item.id), button, source:peek().prefix)
				elseif
					commitItem(item)
					and (item.dismiss == true or (item.dismiss ~= false and not item.checked and not item.selected))
				then
					close()
				end
			end,
		})
		button:AddTag("facet-menu-item")
		fillTitle(button)
		if item.role == "destructive" then
			button:AddTag("facet-menu-destructive")
		end
		local mark = if item.children then nil else button:FindFirstChild("TrailingIcon", true)
		if mark and mark:IsA("GuiObject") then
			Compose.watch(function(use: ComposeTypes.Use)
				local live = actionItem(item)
				mark.Visible = if live.checked
					then use(live.checked) == true
					elseif live.selected then use(live.selected) == live.value
					else read(live.marked, use) == true
			end)
		end
		local content = button:FindFirstChild("Content")
		local layout = if content then content:FindFirstChildWhichIsA("UIListLayout") else nil
		if layout then
			layout.HorizontalAlignment = E.HorizontalAlignment.Left
		end
		surfaces.attach(button, {
			ctx.styled(
				Host.Frame({
					Name = "Hairline",
					Size = D2.new(1, 0, 0, 1),
					ZIndex = 3,
					Visible = function(use: ComposeTypes.Use)
						local before = use(source).items[use(index) - 1]
						return before ~= nil and before.divider ~= true
					end,
				}),
				"menu-hairline"
			) :: Types.Child,
		})
		return button
	end
	return { entry = entryRow, ancestor = ancestorRow }
end
