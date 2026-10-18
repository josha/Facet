--!strict

type OrderedControls = typeof(require("@repo/tools/typecheck/aliases").OrderedControls)
type RowActions = typeof(require("@repo/tools/typecheck/aliases").RowActions)
type RowAction = typeof(require("@repo/tools/typecheck/aliases").RowAction)
type TableColumn = typeof(require("@repo/tools/typecheck/aliases").TableColumn)
type CollectionStatus = typeof(require("@repo/tools/typecheck/aliases").CollectionStatus)
type FrameNativeProps = typeof(require("@repo/tools/typecheck/aliases").FrameNativeProps)
type ExampleContext = typeof(require("@repo/examples/types").Context)
type RowActionsSpec = typeof(require("@repo/tools/typecheck/aliases").RowActionsSpec)
type Built = typeof(require("@repo/examples/types").Built)
type Readable<T> = { peek: (Readable<T>) -> T }
type Cell<T> = Readable<T> & { set: (Cell<T>, T) -> (), update: (Cell<T>, (T) -> T) -> () }
type Use = <T>(Readable<T>) -> T
export type Row = {
	id: string,
	label: string?,
	lines: number?,
	description: string?,
	from: string?,
	subject: string?,
	preview: string?,
	read: boolean?,
	flagged: boolean?,
	n: number?,
	team: string?,
	best: string?,
}
export type Options = {
	name: string,
	title: string?,
	count: number?,
	rows: { Row }?,
	measure: boolean?,
	variable: boolean?,
	grid: boolean?,
	horizontal: boolean?,
	table: boolean?,
	mail: boolean?,
	actions: boolean?,
	list: boolean?,
	editable: boolean?,
	entrants: boolean?,
	columns: { TableColumn }?,
}
type Flags = { [string]: boolean }
return function(ctx: ExampleContext, options: Options): Built
	local Host, UI, Compose = ctx.Host, ctx.UI, ctx.Compose
	local D, D2, E, V2 = ctx.types.UDim, ctx.types.UDim2, ctx.types.Enum, ctx.types.Vector2
	local initial: { Row } = options.rows or {}
	for index = 1, if options.rows then 0 else options.count or 0 do
		initial[index] = {
			id = tostring(index),
			label = (if options.variable or options.measure then "Post " else "Item ") .. index,
			lines = (index - 1) % 4 + 1,
			description = if options.variable
				then string.rep(`A line from post {index}.\n`, (index - 1) % 4) .. `The final line of post {index}.`
				else string.rep(`A sentence about post {index}. `, (index * 3) % 7 + 1),
		}
	end
	local noSelection: Flags = {}
	local nothing: string? = nil
	local rows: Cell<{ Row }> = Compose.cell(initial)
	local selection: Cell<Flags> = Compose.cell(noSelection)
	local selected: Cell<string?> = Compose.cell(nothing)
	local columns, textOffset, variable = Compose.cell(4), Compose.cell(0), Compose.cell(true)
	local editing, moves = Compose.cell(false), Compose.cell(0)
	local mounted, built = Compose.cell(0), Compose.cell(0)
	local idle: CollectionStatus = {
		mode = "windowed",
		direction = "vertical",
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
	}
	local status: Cell<CollectionStatus> = Compose.cell(idle)
	local controls: OrderedControls = {}
	local noToken: {}? = nil
	local coordinator: Cell<{}?> = Compose.cell(noToken)
	local titleLine, bodyLine = Compose.cell(21), Compose.cell(18)
	local noFlags: Flags = {}
	local readRows: Cell<Flags> = Compose.cell(noFlags)
	local flaggedRows: Cell<Flags> = Compose.cell(noFlags)
	local body: ScrollingFrame?
	local function seedFlags()
		local reads: Flags, flags: Flags = {}, {}
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
	local function flag(key: string)
		local value = table.clone(flaggedRows:peek())
		value[key] = not value[key]
		flaggedRows:set(value)
	end
	local function remove(key: string)
		local nextRows: { Row } = {}
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
	local function actions(key: string): RowActions
		local leading: { RowAction } = {
			{
				id = "read",
				label = "Mark read",
				icon = "checkmark",
				onActivate = function()
					markRead(assert(key))
				end,
			},
		}
		local trailing: { RowAction } = {
			{
				id = "delete",
				label = "Delete",
				icon = "trash",
				role = "destructive",
				onActivate = function()
					remove(key)
				end,
			},
			{
				id = "flag",
				label = "Flag",
				icon = "flag",
				onActivate = function()
					flag(key)
				end,
			},
		}
		return {
			Name = "Row_" .. key,
			coordinator = coordinator,
			editing = editing,
			fullSwipe = true,
			leading = leading,
			trailing = trailing,
		}
	end
	local function observe(node: Instance, property: string, read: () -> Vector2): Cell<Vector2>
		local value: Cell<Vector2> = Compose.cell(read())
		local connection = node:GetPropertyChangedSignal(property):Connect(function()
			value:set(read())
		end)
		Compose.cleanup(function()
			connection:Disconnect()
		end)
		return value
	end
	local extents = Compose.formula(function(use: Use): { [string]: number }
		local result: { [string]: number } = {}
		if options.variable then
			local titleHeight = math.max(use(titleLine), math.ceil((15 + use(textOffset)) * 1.35))
			local bodyHeight = math.max(use(bodyLine), math.ceil((13 + use(textOffset)) * 1.35))
			for _, item in use(rows) do
				result[item.id] = if use(variable) then 24 + titleHeight + bodyHeight * (item.lines or 1) else 84
			end
		end
		return result
	end)
	local function mailBody(current: Readable<Row>, key: string, sender: boolean): GuiObject
		local function words(read: (Row) -> string?): (Use) -> string
			return function(use: Use): string
				return read(use(current)) or ""
			end
		end
		return Host.Frame "Mail" {
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
			Host.Frame "Text" {
				LayoutOrder = 2,
				BackgroundTransparency = 1,
				Size = D2.fromScale(0, 1),
				Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
				Host.UIListLayout({
					SortOrder = E.SortOrder.LayoutOrder,
					VerticalAlignment = E.VerticalAlignment.Center,
					Padding = D.new(0, 2),
				}),
				UI.Text "From" {
					LayoutOrder = 1,
					Visible = sender,
					text = words(function(item: Row): string?
						return item.from
					end),
					textRole = "body",
					truncate = "end",
				},
				UI.Text "Subject" {
					LayoutOrder = 2,
					text = words(function(item: Row): string?
						return item.subject
					end),
					textRole = "label",
					truncate = "end",
				},
				UI.Text "Preview" {
					LayoutOrder = 3,
					text = words(function(item: Row): string?
						return item.preview
					end),
					textRole = "caption",
					role = "secondary",
					truncate = "end",
				},
			},
			UI.Image "Flag" {
				LayoutOrder = 3,
				Size = D2.fromOffset(16, 16),
				tint = ctx.types.Color3.fromRGB(214, 64, 56),
				image = function(use: Use): string
					local theme = ctx.theme
					local package = if theme then use(theme) else ctx.Facet.themes.neutralPackage()
					return ctx.Facet.themes.resolveIcon(package, "flag") or ""
				end,
				Visible = function(use: Use)
					return use(flaggedRows)[key] == true
				end,
			},
		}
	end
	local function row(current: Readable<Row>, placement: unknown, key: string): GuiObject
		mounted:set(mounted:peek() + 1)
		built:set(built:peek() + 1)
		Compose.cleanup(function()
			mounted:set(mounted:peek() - 1)
		end)
		if options.variable or options.measure then
			return Host.Frame("Post_" .. key)({
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
					text = function(use: Use): string
						return use(current).label or ""
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
					text = function(use: Use): string
						return use(current).description or ""
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
				name = function(use: Use): string
					local item = use(current)
					return (item.subject or "") .. " from " .. (item.from or "")
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
				label = function(use: Use): string
					return use(current).label or ""
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
			local rowSpec: RowActionsSpec = {
				Name = spec.Name,
				coordinator = spec.coordinator,
				editing = spec.editing,
				fullSwipe = spec.fullSwipe,
				leading = spec.leading,
				trailing = spec.trailing,
				Size = D2.fromScale(1, 1),
				content = button,
			}
			return UI.RowActions(rowSpec)
		end
		return button
	end
	local function jump(index: number?)
		local offsetOf = controls.offsetOf
		local frame = body
		if not frame or not offsetOf then
			return
		end
		local extent = if options.horizontal then frame.AbsoluteWindowSize.X else frame.AbsoluteWindowSize.Y
		local offset = offsetOf(math.clamp(index or 50, 1, #rows:peek()), "start", extent)
		frame.CanvasPosition = if options.horizontal then V2.new(offset, 0) else V2.new(0, offset)
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
		local value: Flags = {}
		for _, item in rows:peek() do
			local n = item.n or 0
			if n >= 900 and n <= 1100 then
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
	local function itemKey(item: Row): string
		return item.id
	end
	local function onDelete(keys: { string })
		for _, key in keys do
			remove(key)
		end
	end
	local function onActivate(_: Row, key: string)
		selected:set(key)
		if options.mail then
			markRead(assert(key))
		end
	end
	local function rowActions(_: Readable<Row>, key: string): RowActions
		return actions(key)
	end
	local function onCellChange(key: string, column: string, value: unknown)
		local nextRows: { Row } = table.clone(rows:peek())
		for index, item in nextRows do
			if item.id == key then
				local nextItem = table.clone(item)
				local text = if type(value) == "string" then value else nil
				if column == "team" then
					nextItem.team = text
				elseif column == "best" then
					nextItem.best = text
				elseif column == "label" then
					nextItem.label = text
				end
				nextRows[index] = nextItem
			end
		end
		rows:set(nextRows)
	end
	local mailColumns: { TableColumn } = {
		{
			id = "from",
			label = "From",
			width = 170,
			minWidth = 100,
			value = function(item: Row): string?
				return item.from
			end,
		},
		{
			id = "subject",
			label = "Subject",
			minWidth = 160,
			render = function(current: Readable<Row>, _: unknown, key: string): GuiObject
				return mailBody(current, key, false)
			end,
		},
	}
	local function page(): Frame
		local collection: GuiObject
		local side = Compose.cell(false)
		local function collectionSize(use: Use): UDim2
			return if use(side) then D2.new(0, 0, 1, 0) else D2.new(1, 0, 0, 0)
		end
		if options.table then
			local unsorted: { column: string, direction: "ascending" | "descending" }? = nil
			local sort: Cell<{ column: string, direction: "ascending" | "descending" }?> = Compose.cell(unsorted)
			local noWidths: { [string]: number } = {}
			local widths: Cell<{ [string]: number }> = Compose.cell(noWidths)
			local tableView = UI.Table "Collection" {
				from = rows,
				key = itemKey,
				LayoutOrder = 2,
				Size = collectionSize,
				status = status,
				controls = controls,
				Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
				selection = selection,
				selectionMode = "multiple",
				sort = sort,
				widths = widths,
				reorderable = true,
				onReorder = reorder,
				deletable = true,
				onDelete = onDelete,
				onActivate = onActivate,
				itemSize = if options.mail then 76 else nil,
				rowActions = if options.actions then rowActions else nil,
				alternatingRows = if options.editable then true else nil,
				onCellChange = if options.editable then onCellChange else nil,
				columns = options.columns or mailColumns,
			}
			collection = tableView
			local found = tableView:FindFirstChild("Body", true)
			body = if found and found:IsA("ScrollingFrame") then found else nil
		else
			local itemSize: number | (Use) -> number = if options.horizontal
				then 160
				elseif options.mail then 76
				elseif options.measure then 76
				else function(use: Use): number
					return 64 + use(textOffset) * 2
				end
			local list = if options.grid
				then UI.VirtualGrid "Collection" {
					from = rows,
					key = itemKey,
					LayoutOrder = 2,
					Size = collectionSize,
					status = status,
					controls = controls,
					Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
					render = row,
					itemSize = itemSize,
					mode = if options.list then "all" else "windowed",
					gap = 8,
					columns = columns,
					direction = if options.horizontal then "horizontal" else "vertical",
					measure = options.measure,
					measured = if options.variable then extents else nil,
				}
				else UI.VirtualList "Collection" {
					from = rows,
					key = itemKey,
					LayoutOrder = 2,
					Size = collectionSize,
					status = status,
					controls = controls,
					Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
					render = row,
					itemSize = itemSize,
					mode = if options.list then "all" else "windowed",
					gap = 8,
					columns = columns,
					direction = if options.horizontal then "horizontal" else "vertical",
					measure = options.measure,
					measured = if options.variable then extents else nil,
				}
			collection = list
			body = list
		end
		local scroller = assert(body)
		local nativePosition = observe(scroller, "CanvasPosition", function(): Vector2
			return scroller.CanvasPosition
		end)
		local buttons: FrameNativeProps = {
			Name = "Actions",
			LayoutOrder = 2,
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}
		local count = 0
		local function command(
			name: string,
			label: string | (Use) -> string,
			callback: () -> (),
			visible: ((Use) -> boolean)?
		)
			count += 1
			buttons[#buttons + 1] = UI.Button({
				Name = name,
				label = label,
				onActivate = callback,
				LayoutOrder = count,
				Visible = visible,
			})
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
		buttons[#buttons + 1] = Host.UIListLayout({
			FillDirection = E.FillDirection.Horizontal,
			SortOrder = E.SortOrder.LayoutOrder,
			Padding = D.new(0, 8),
			Wraps = true,
		})
		local actionsFrame = Host.Frame(buttons)
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
		local function textBounds(probe: GuiObject): Cell<Vector2>
			return observe(probe, "TextBounds", function(): Vector2
				return if probe:IsA("TextLabel") then probe.TextBounds else Vector2.zero
			end)
		end
		local titleBounds, bodyBounds = textBounds(titleProbe), textBounds(bodyProbe)
		Compose.watch(function(use: Use)
			titleLine:set(use(titleBounds).Y)
			bodyLine:set(use(bodyBounds).Y)
		end)
		local root = Host.Frame(options.name)({
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
					Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = D.new(0, 8) }),
					UI.Text "Title" {
						LayoutOrder = 1,
						Visible = function(use: Use): boolean
							local source = ctx.viewport
							local viewport = if source then use(source) else nil
							return viewport == nil or viewport.height <= 0 or viewport.height >= 480
						end,
						text = options.title or "",
						textRole = "title",
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
		local area = observe(root, "AbsoluteSize", function(): Vector2
			return root.AbsoluteSize
		end)
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
