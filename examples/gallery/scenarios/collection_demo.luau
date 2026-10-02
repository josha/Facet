--!strict
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type Row = { [string]: any, id: string, label: string }
return function(ctx: any, options: any)
	local Host, UI, Compose: typeof(require("@repo/src/vendor/compose/core")) = ctx.Host, ctx.UI, ctx.Compose
	local D, D2, E, V2 = ctx.types.UDim, ctx.types.UDim2, ctx.types.Enum, ctx.types.Vector2
	local initial: { Row } = options.rows or {}
	for index = 1, if options.rows then 0 else options.count do
		initial[index] = {
			id = tostring(index),
			label = (if options.variable or options.measure then "Post " else "Item ") .. index,
			lines = (index - 1) % 4 + 1,
			description = if options.variable
				then string.rep(`A line from post {index}.\n`, (index - 1) % 4) .. `The final line of post {index}.`
				else string.rep(`A sentence about post {index}. `, (index * 3) % 7 + 1),
		}
	end
	local rows, selection, selected =
		Compose.cell(initial),
		Compose.cell({}),
		(function(value: string?): typeof(require("@repo/tools/typecheck/example_shapes").optionalStringCell(nil))
			return Compose.cell(value)
		end)(nil)
	local columns, textOffset, variable = Compose.cell(4), Compose.cell(0), Compose.cell(true)
	local editing, moves = Compose.cell(false), Compose.cell(0)
	local mounted, built = Compose.cell(0), Compose.cell(0)
	local status = Compose.cell({
		mode = "windowed" :: "windowed",
		direction = "vertical" :: "vertical",
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
	local controls: typeof(require("@repo/tools/typecheck/example_shapes").orderedControls(nil :: any)) = {}
	local coordinator = Compose.cell(nil :: string?)
	local titleLine, bodyLine = Compose.cell(21), Compose.cell(18)
	local readRows, flaggedRows = Compose.cell({}), Compose.cell({})
	local body: ScrollingFrame?
	local function seedFlags()
		local reads, flags = {}, {}
		for _, item in initial do
			reads[item.id], flags[item.id] = item.read == true, item.flagged == true
		end
		readRows:set(reads)
		flaggedRows:set(flags)
	end
	seedFlags()
	local function markRead(key: string)
		local value = table.clone(readRows:peek())
		value[key] = true
		readRows:set(value)
	end
	local function flag(key)
		local value = table.clone(flaggedRows:peek())
		value[key] = not value[key]
		flaggedRows:set(value)
	end
	local function remove(key)
		local nextRows = {}
		for _, item in rows:peek() do
			if item.id ~= key then
				table.insert(nextRows, item)
			end
		end
		rows:set(nextRows)
	end
	local function reorder(keys: { string }, slot: number)
		local carried: { Row } = {}
		local remaining: { Row } = {}
		for _, item in rows:peek() do
			table.insert(if table.find(keys, item.id) then carried else remaining, item)
		end
		for index, item in carried do
			table.insert(remaining, slot + index, item)
		end
		rows:set(remaining)
		moves:set(moves:peek() + 1)
	end
	local function edit()
		editing:set(not editing:peek())
	end
	local function actions(key: string): typeof(require("@repo/tools/typecheck/example_shapes").rowActions(nil :: any))
		return {
			Name = "Row_" .. key,
			coordinator = coordinator,
			editing = editing,
			fullSwipe = true,
			leading = {
				{
					id = "read",
					label = "Mark read",
					icon = "checkmark",
					onActivate = function()
						markRead(assert(key))
					end,
				},
			},
			trailing = {
				{
					id = "delete",
					label = "Delete",
					icon = "trash",
					role = "destructive" :: "destructive",
					onActivate = function()
						remove(key)
					end,
				} :: typeof(require("@repo/tools/typecheck/example_shapes").rowAction(nil :: any)),
				{
					id = "flag",
					label = "Flag",
					icon = "flag",
					onActivate = function()
						flag(key)
					end,
				},
			},
		}
	end
	local function observe(node: ScrollingFrame, property: string)
		local value = Compose.cell((node :: any)[property])
		local connection = node:GetPropertyChangedSignal(property):Connect(function()
			value:set((node :: any)[property])
		end)
		Compose.cleanup(function()
			connection:Disconnect()
		end)
		return value
	end
	local extents = Compose.formula(function(use: Use)
		local result = {}
		if options.variable then
			local titleHeight = math.max(use(titleLine), math.ceil((15 + use(textOffset)) * 1.35))
			local bodyHeight = math.max(use(bodyLine), math.ceil((13 + use(textOffset)) * 1.35))
			for _, item in use(rows) do
				result[item.id] = if use(variable) then 24 + titleHeight + bodyHeight * item.lines else 84
			end
		end
		return result
	end)
	local function mailBody(current: Readable<Row>, key: string, sender: boolean): GuiObject
		local function words(field)
			return function(use: Use)
				return use(current)[field]
			end
		end
		return Host.Frame({
			Name = "Mail",
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Host.UIPadding({ PaddingLeft = D.new(0, 4), PaddingRight = D.new(0, 4) }),
			Host.UIListLayout({
				FillDirection = E.FillDirection.Horizontal,
				VerticalAlignment = E.VerticalAlignment.Center,
				SortOrder = E.SortOrder.LayoutOrder,
				Padding = D.new(0, 8),
			}),
			UI.StatusIndicator "Unread" {
				LayoutOrder = 1,
				form = "dot",
				status = "accent",
				name = "Unread",
				Visible = function(use: Use)
					return not use(readRows)[key]
				end,
			},
			Host.Frame({
				Name = "Text",
				LayoutOrder = 2,
				BackgroundTransparency = 1,
				Size = D2.fromScale(0, 1),
				Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }) :: unknown,
				Host.UIListLayout({
					SortOrder = E.SortOrder.LayoutOrder,
					VerticalAlignment = E.VerticalAlignment.Center,
					Padding = D.new(0, 2),
				}),
				UI.Text "From" {
					LayoutOrder = 1,
					Visible = sender,
					text = words("from"),
					textRole = "body" :: "body",
					truncate = "end",
				},
				UI.Text "Subject" {
					LayoutOrder = 2,
					text = words("subject"),
					textRole = "label" :: "label",
					truncate = "end",
				},
				UI.Text "Preview" {
					LayoutOrder = 3,
					text = words("preview"),
					textRole = "caption" :: "caption",
					role = "secondary" :: "secondary",
					truncate = "end",
				},
			}),
			UI.Image "Flag" {
				LayoutOrder = 3,
				Size = D2.fromOffset(16, 16),
				tint = ctx.types.Color3.fromRGB(214, 64, 56),
				image = function(use: Use)
					local package = if ctx.theme then use(ctx.theme) else ctx.Facet.themes.neutralPackage()
					return ctx.Facet.themes.resolveIcon(package, "flag") or ""
				end,
				Visible = function(use: Use)
					return use(flaggedRows)[key] == true
				end,
			},
		})
	end
	local function row(current: Readable<Row>, placement: unknown, key: string): GuiObject
		mounted:set(mounted:peek() + 1)
		built:set(built:peek() + 1)
		Compose.cleanup(function()
			mounted:set(mounted:peek() - 1)
		end)
		if options.variable or options.measure then
			return Host.Frame({
				Name = "Post_" .. key,
				BackgroundTransparency = 1,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				Host.UIPadding({
					PaddingLeft = D.new(0, 10),
					PaddingRight = D.new(0, 10),
					PaddingTop = D.new(0, 10),
					PaddingBottom = D.new(0, 10),
				}),
				Host.UIListLayout({ Padding = D.new(0, 4), SortOrder = E.SortOrder.LayoutOrder }),
				UI.Text "PostTitle" {
					LayoutOrder = 1,
					text = function(use: Use)
						return use(current).label
					end,
					TextSize = function(use: Use)
						return 15 + use(textOffset)
					end,
					TextWrapped = false,
					TextTruncate = E.TextTruncate.AtEnd,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					BackgroundTransparency = 1,
				},
				UI.Text "PostBody" {
					LayoutOrder = 2,
					text = function(use: Use)
						return use(current).description
					end,
					TextSize = function(use: Use)
						return 13 + use(textOffset)
					end,
					TextWrapped = options.measure == true,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					BackgroundTransparency = 1,
				},
			})
		end
		local button = if options.mail
			then UI.Button({
				Name = "Item_" .. key,
				label = "",
				name = function(use: Use)
					return use(current).subject .. " from " .. use(current).from
				end,
				Size = D2.fromScale(1, 1),
				AutomaticSize = E.AutomaticSize.None,
				onActivate = function()
					selected:set(key)
					markRead(assert(key))
				end,
				mailBody(current, key, true),
			})
			else UI.Button({
				Name = "Item_" .. key,
				label = function(use: Use)
					return use(current).label
				end,
				TextSize = function(use: Use)
					return 16 + use(textOffset)
				end,
				TextWrapped = true,
				Size = D2.fromScale(1, 1),
				AutomaticSize = E.AutomaticSize.None,
				onActivate = function()
					selected:set(key)
				end,
			})
		if options.actions then
			local spec = actions(key)
			return UI.RowActions({
				Name = spec.Name,
				coordinator = spec.coordinator,
				editing = spec.editing,
				fullSwipe = spec.fullSwipe,
				leading = spec.leading,
				trailing = spec.trailing,
				Size = D2.fromScale(1, 1),
				content = button,
			})
		end
		return button
	end
	local function jump(index)
		if not body or not controls.offsetOf then
			return
		end
		local extent = if options.horizontal then body.AbsoluteWindowSize.X else body.AbsoluteWindowSize.Y
		local offset = controls.offsetOf(math.clamp(index or 50, 1, #rows:peek()), "start", extent)
		body.CanvasPosition = if options.horizontal then V2.new(offset, 0) else V2.new(0, offset)
	end
	local function reverse()
		local value = table.clone(rows:peek())
		for i = 1, math.floor(#value / 2) do
			value[i], value[#value - i + 1] = value[#value - i + 1], value[i]
		end
		rows:set(value)
	end
	local function reset()
		rows:set(initial)
		selection:set({})
		selected:set(nil)
		editing:set(false)
		moves:set(0)
		seedFlags()
		if body then
			body.CanvasPosition = V2.zero
		end
	end
	local function selectRange()
		local value = {}
		for _, item in rows:peek() do
			if item.n >= 900 and item.n <= 1100 then
				value[item.id] = true
			end
		end
		selection:set(value)
	end
	local function moveFar()
		local index
		for at, item in rows:peek() do
			if item.id == "e1500" then
				index = at
				break
			end
		end
		if index and index > 1 then
			reorder({ "e1500" }, index - 2)
		end
	end
	local function page()
		local collection
		local side = Compose.cell(false)
		local common: { [any]: any } = {
			Name = "Collection",
			from = rows,
			key = function(item)
				return item.id
			end,
			LayoutOrder = 2,
			Size = function(use: Use)
				return if use(side) then D2.new(0, 0, 1, 0) else D2.new(1, 0, 0, 0)
			end,
			status = status,
			controls = controls,
			Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
		}
		if options.table then
			common.selection, common.selectionMode = selection, "multiple"
			common.sort, common.widths = Compose.cell(nil), Compose.cell({})
			common.reorderable, common.onReorder = true, reorder
			common.deletable, common.onDelete =
				true, function(keys)
					for _, key in keys do
						remove(key)
					end
				end
			common.onActivate = function(item, key)
				selected:set(key)
				if options.mail then
					markRead(assert(key))
				end
			end
			common.itemSize = if options.mail then 76 else nil
			common.rowActions = if options.actions
				then function(_, key)
					return actions(key)
				end
				else nil
			if options.editable then
				common.alternatingRows = true
				common.onCellChange = function(key, column, value)
					local nextRows: { Row } = table.clone(rows:peek())
					for index, item in nextRows do
						if item.id == key then
							local nextItem = table.clone(item)
							nextItem[column] = value
							nextRows[index] = nextItem
						end
					end
					rows:set(nextRows)
				end
			end
			common.columns = options.columns
				or {
					{
						id = "from",
						label = "From",
						width = 170,
						minWidth = 100,
						value = function(item)
							return item.from
						end,
					},
					{
						id = "subject",
						label = "Subject",
						minWidth = 160,
						render = function(current, _, key): GuiObject
							return mailBody(current, key, false)
						end,
					},
				} :: { typeof(require("@repo/tools/typecheck/example_shapes").TableColumn_any(nil :: any)) }
			collection = UI.Table(common)
			body = collection:FindFirstChild("Body")
		else
			common.render = row
			common.itemSize = if options.horizontal
				then 160
				elseif options.mail then 76
				elseif options.measure then 76
				else function(use: Use)
					return 64 + use(textOffset) * 2
				end
			common.mode = if options.list then "all" else "windowed"
			common.gap, common.columns = 8, columns
			common.direction = if options.horizontal then "horizontal" else "vertical"
			common.measure = options.measure
			common.measured = if options.variable then extents else nil
			collection = if options.grid then UI.VirtualGrid(common) else UI.VirtualList(common)
			body = collection
		end
		local nativePosition = observe(assert(body), "CanvasPosition")
		local buttons = {}
		local function command(name, label, callback, visible)
			table.insert(
				buttons,
				UI.Button({
					Name = name,
					label = label,
					onActivate = callback,
					LayoutOrder = #buttons + 1,
					Visible = visible,
				})
			)
		end
		if options.entrants then
			command("Reveal", "Reveal #1500", function()
				jump(1500)
			end)
			command("Range", "Select 900–1100", selectRange)
			command("Move", "Move #1500 up", moveFar)
		else
			command("Jump", "Jump", function()
				jump(if options.mail then 4 else 50)
			end)
		end
		if options.mail and not options.table then
			local env = UI.environment()
			command(
				"Edit",
				function(use: Use)
					return if use(editing) then "Done" else "Edit"
				end,
				edit,
				function(use: Use)
					return use(env.effectiveInput) ~= "KeyboardAndMouse" or use(editing)
				end
			)
		end
		if options.grid then
			command("Reverse", "Reverse", reverse)
			command("Columns", "Change columns", function()
				columns:set(if columns:peek() == 4 then 2 else 4)
			end)
		end
		if options.variable then
			command("Mode", function(use: Use)
				return if use(variable) then "Variable heights" else "Uniform 84px"
			end, function()
				variable:set(not variable:peek())
			end)
		end
		if options.variable or options.measure then
			for _, offset in { 0, 4, 10, 14 } do
				command("TextOffset" .. offset, "Text +" .. offset, function()
					textOffset:set(offset)
				end)
			end
		elseif options.grid then
			command("TextSize", "Larger text", function()
				textOffset:set(if textOffset:peek() == 0 then 8 else 0)
			end)
		end
		command("Reset", "Reset", reset)
		table.insert(
			buttons,
			Host.UIListLayout({
				FillDirection = E.FillDirection.Horizontal,
				SortOrder = E.SortOrder.LayoutOrder,
				Padding = D.new(0, 8),
				Wraps = true,
			})
		)
		local actionsFrame = Host.Frame "Actions" {
			LayoutOrder = 2,
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
			BackgroundTransparency = 1,
			table.unpack((buttons :: unknown) :: { unknown }),
		}
		local titleProbe = UI.Text "TitleLineMeasure" {
			Visible = false,
			text = "Ag",
			TextSize = function(use: Use)
				return 15 + use(textOffset)
			end,
			AutomaticSize = E.AutomaticSize.XY,
			Size = D2.fromOffset(0, 0),
		}
		local bodyProbe = UI.Text "BodyLineMeasure" {
			Visible = false,
			text = "Ag",
			TextSize = function(use: Use)
				return 13 + use(textOffset)
			end,
			AutomaticSize = E.AutomaticSize.XY,
			Size = D2.fromOffset(0, 0),
		}
		local titleBounds, bodyBounds = observe(titleProbe, "TextBounds"), observe(bodyProbe, "TextBounds")
		Compose.watch(function(use: Use)
			titleLine:set(use(titleBounds).Y)
			bodyLine:set(use(bodyBounds).Y)
		end)
		local root = Host.Frame({
			Name = options.name,
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Host.UIPadding({
				PaddingTop = D.new(0, 16),
				PaddingBottom = D.new(0, 16),
				PaddingLeft = D.new(0, 16),
				PaddingRight = D.new(0, 16),
			}),
			Host.UIListLayout({
				SortOrder = E.SortOrder.LayoutOrder,
				Padding = D.new(0, 8),
				FillDirection = function(use: Use)
					return if use(side) then E.FillDirection.Horizontal else E.FillDirection.Vertical
				end,
			}),
			Host.ScrollingFrame "ToolbarScroll" {
				LayoutOrder = 1,
				Size = function(use: Use)
					return if use(side) then D2.new(0.4, 0, 1, 0) else D2.new(1, 0, 0, 0)
				end,
				AutomaticSize = function(use: Use)
					return if use(side) then E.AutomaticSize.None else E.AutomaticSize.Y
				end,
				CanvasSize = D2.new(0, 0, 0, 0),
				AutomaticCanvasSize = E.AutomaticSize.Y,
				ScrollingDirection = E.ScrollingDirection.Y,
				ScrollBarThickness = function(use: Use)
					return if use(side) then 4 else 0
				end,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Host.Frame "Toolbar" {
					LayoutOrder = 1,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = D.new(0, 8) }) :: unknown,
					UI.Text "Title" {
						LayoutOrder = 1,
						Visible = function(use: Use)
							local viewport = ctx.viewport and use(ctx.viewport)
							return viewport == nil or viewport.height <= 0 or viewport.height >= 480
						end,
						text = options.title,
						textRole = "title" :: "title",
						TextWrapped = true,
						Size = D2.new(1, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.Y,
						BackgroundTransparency = 1,
					},
					actionsFrame,
					UI.Text "Status" {
						LayoutOrder = 3,
						text = function(use: Use)
							local snapshot, count = use(status), 0
							for _, on in use(selection) do
								if on then
									count += 1
								end
							end
							local at = use(nativePosition)
							return `{#use(rows)} rows · {snapshot.retained} mounted · {use(built)} built · {count} selected · {use(
								moves
							)} moves\nwindow {snapshot.first}–{snapshot.last} · text +{use(textOffset)} · offset {math.floor(
								if options.horizontal then at.X else at.Y
							)}`
						end,
						TextWrapped = true,
						Size = D2.new(1, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.Y,
						BackgroundTransparency = 1,
					},
				},
			},
			collection,
			titleProbe,
			bodyProbe,
		})
		local area = observe(root, "AbsoluteSize")
		Compose.watch(function(use: Use)
			local size = use(area)
			side:set(size.Y > 0 and size.Y < 360 and size.X >= 480)
		end)
		return root
	end
	return {
		screen = page,
		reset = reset,
		steps = { reverse = reverse, reset = reset },
		report = function()
			local selectedCount = 0
			for _, on in selection:peek() do
				if on then
					selectedCount += 1
				end
			end
			return {
				count = #rows:peek(),
				rows = rows:peek(),
				built = built:peek(),
				mounted = mounted:peek(),
				status = status:peek(),
				selected = selected:peek(),
				selection = selection:peek(),
				selectedCount = selectedCount,
				moves = moves:peek(),
				editing = editing:peek(),
				textOffset = textOffset:peek(),
				variable = variable:peek(),
				read = readRows:peek(),
				flagged = flaggedRows:peek(),
				offset = if body then body.CanvasPosition else V2.zero,
				extents = extents:peek(),
			}
		end,
	}
end
