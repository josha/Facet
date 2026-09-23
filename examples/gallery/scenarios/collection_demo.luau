--!strict
return function(ctx: any, options: any)
	local Host, UI, Compose = ctx.Host, ctx.UI, ctx.Compose
	local D, D2, E, V2 = ctx.types.UDim, ctx.types.UDim2, ctx.types.Enum, ctx.types.Vector2
	local initial = options.rows or {}
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
	local rows, selection, selected = Compose.cell(initial), Compose.cell({}), Compose.cell(nil)
	local columns, textOffset, variable = Compose.cell(4), Compose.cell(0), Compose.cell(true)
	local editing, moves = Compose.cell(false), Compose.cell(0)
	local mounted, built = Compose.cell(0), Compose.cell(0)
	local status = Compose.cell({
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
	})
	local controls, coordinator = {}, Compose.cell(nil)
	local titleLine, bodyLine = Compose.cell(21), Compose.cell(18)
	local readRows, flaggedRows = Compose.cell({}), Compose.cell({})
	local body
	local function seedFlags()
		local reads, flags = {}, {}
		for _, item in initial do
			reads[item.id], flags[item.id] = item.read == true, item.flagged == true
		end
		readRows:set(reads)
		flaggedRows:set(flags)
	end
	seedFlags()
	local function markRead(key)
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
	local function reorder(keys, slot)
		local carried, remaining = {}, {}
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
		local value = not editing:peek()
		editing:set(value)
		local nextRows = {}
		for index, item in rows:peek() do
			local nextItem = table.clone(item)
			nextItem.editing = value
			nextRows[index] = nextItem
		end
		rows:set(nextRows)
	end
	local function actions(key)
		return {
			Name = "Row_" .. key,
			coordinator = coordinator,
			editing = editing,
			fullSwipe = true,
			leading = {
				{
					id = "read",
					label = "Mark read",
					onActivate = function()
						markRead(key)
					end,
				},
			},
			trailing = {
				{
					id = "delete",
					label = "Delete",
					role = "destructive",
					onActivate = function()
						remove(key)
					end,
				},
				{
					id = "flag",
					label = "Flag",
					onActivate = function()
						flag(key)
					end,
				},
			},
		}
	end
	local function observe(node, property)
		local value = Compose.cell(node[property])
		local connection = node:GetPropertyChangedSignal(property):Connect(function()
			value:set(node[property])
		end)
		Compose.cleanup(function()
			connection:Disconnect()
		end)
		return value
	end
	local extents = Compose.formula(function(use)
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
	local function row(current, placement, key)
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
				UI.Label({
					Name = "PostTitle",
					LayoutOrder = 1,
					Text = function(use)
						return use(current).label
					end,
					TextSize = function(use)
						return 15 + use(textOffset)
					end,
					TextWrapped = false,
					TextTruncate = E.TextTruncate.AtEnd,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					BackgroundTransparency = 1,
				}),
				UI.Label({
					Name = "PostBody",
					LayoutOrder = 2,
					Text = function(use)
						return use(current).description
					end,
					TextSize = function(use)
						return 13 + use(textOffset)
					end,
					TextWrapped = options.measure == true,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					BackgroundTransparency = 1,
				}),
			})
		end
		local button = UI.Button({
			Name = "Item_" .. key,
			label = function(use)
				local item = use(current)
				if options.mail then
					return (if use(readRows)[key] then "Read · " else "Unread · ")
						.. (if use(flaggedRows)[key] then "Flagged · " else "")
						.. item.subject
				end
				return item.label
			end,
			subtitle = if options.mail
				then function(use)
					return use(current).from .. "\n" .. use(current).preview
				end
				else nil,
			TextSize = function(use)
				return 16 + use(textOffset)
			end,
			TextWrapped = true,
			Size = D2.fromScale(1, 1),
			AutomaticSize = E.AutomaticSize.None,
			onActivate = function()
				selected:set(key)
				if options.mail then
					markRead(key)
				end
			end,
		})
		if options.actions then
			local spec = actions(key)
			spec.Size, spec.content = D2.fromScale(1, 1), button
			return UI.RowActions(spec)
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
		local index = controls.indexOfKey and controls.indexOfKey("e1500")
		if index and index > 1 then
			reorder({ "e1500" }, index - 2)
		end
	end
	local function page()
		local collection
		local common = {
			Name = "Collection",
			from = rows,
			key = function(item)
				return item.id
			end,
			LayoutOrder = 2,
			Size = D2.new(1, 0, 0, 0),
			status = status,
			controls = controls,
			Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
		}
		if options.table then
			common.selection, common.selectionMode = selection, "multi"
			common.sort, common.widths = Compose.cell(nil), Compose.cell({})
			common.editing, common.reorderable, common.onReorder = editing, true, reorder
			common.movable = function(item)
				return item.editing == true
			end
			common.onActivate = function(item, key)
				selected:set(key)
				if options.mail then
					markRead(key)
				end
			end
			common.itemSize = if options.mail then 100 else nil
			common.rowActions = if options.actions
				then function(_, key)
					return actions(key)
				end
				else nil
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
						render = function(current, _, key)
							return UI.Label({
								Name = "Message",
								Text = function(use)
									return (if use(readRows)[key] then "Read · " else "Unread · ")
										.. (if use(flaggedRows)[key] then "Flagged · " else "")
										.. use(current).subject
										.. "\n"
										.. use(current).preview
								end,
								TextWrapped = true,
								Size = D2.fromScale(1, 1),
								BackgroundTransparency = 1,
							})
						end,
					},
				}
			collection = UI.Table(common)
			body = collection:FindFirstChild("Body")
		else
			common.render = row
			common.itemSize = if options.horizontal
				then 160
				elseif options.mail then 112
				elseif options.measure then 76
				else function(use)
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
		local nativePosition = observe(body, "CanvasPosition")
		local buttons = {}
		local function command(name, label, callback)
			table.insert(
				buttons,
				UI.Button({ Name = name, label = label, onActivate = callback, LayoutOrder = #buttons + 1 })
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
		if options.mail or options.entrants then
			command("Edit", function(use)
				return if use(editing) then "Done" else "Edit"
			end, edit)
		end
		if options.grid then
			command("Reverse", "Reverse", reverse)
			command("Columns", "Change columns", function()
				columns:set(if columns:peek() == 4 then 2 else 4)
			end)
		end
		if options.variable then
			command("Mode", function(use)
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
		local actionsFrame = Host.Frame({
			Name = "Actions",
			LayoutOrder = 2,
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
			BackgroundTransparency = 1,
			table.unpack(buttons),
		})
		local titleProbe = UI.Label({
			Name = "TitleLineMeasure",
			Visible = false,
			Text = "Ag",
			TextSize = function(use)
				return 15 + use(textOffset)
			end,
			AutomaticSize = E.AutomaticSize.XY,
			Size = D2.fromOffset(0, 0),
		})
		local bodyProbe = UI.Label({
			Name = "BodyLineMeasure",
			Visible = false,
			Text = "Ag",
			TextSize = function(use)
				return 13 + use(textOffset)
			end,
			AutomaticSize = E.AutomaticSize.XY,
			Size = D2.fromOffset(0, 0),
		})
		local titleBounds, bodyBounds = observe(titleProbe, "TextBounds"), observe(bodyProbe, "TextBounds")
		Compose.watch(function(use)
			titleLine:set(use(titleBounds).Y)
			bodyLine:set(use(bodyBounds).Y)
		end)
		return Host.Frame({
			Name = options.name,
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = D.new(0, 8) }),
			Host.Frame({
				Name = "Toolbar",
				LayoutOrder = 1,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = D.new(0, 8) }),
				UI.Label({
					Name = "Title",
					LayoutOrder = 1,
					Text = options.title,
					TextSize = 24,
					TextWrapped = true,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					BackgroundTransparency = 1,
				}),
				actionsFrame,
				UI.Label({
					Name = "Status",
					LayoutOrder = 3,
					Text = function(use)
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
				}),
			}),
			collection,
			titleProbe,
			bodyProbe,
		})
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
