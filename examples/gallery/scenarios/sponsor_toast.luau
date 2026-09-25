return {
	title = "Toasts",
	build = function(ctx)
		local Host, UI, Compose, runtime = ctx.Host, ctx.UI, ctx.Compose, ctx.runtime
		local D, D2, V2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
		local rows, presses, edge, widthMode =
			Compose.cell({}), Compose.cell(0), Compose.cell("bottom"), Compose.cell("fill")
		local clock = runtime.timeline({ duration = 86400, repeats = math.huge })
		local nextId, dropped, superseded = 0, 0, 0
		local stackEdge = Compose.cell("bottom")
		local availableWidth = Compose.cell(560)
		local heights = Compose.cell({})
		local layout = Compose.formula(function(use)
			local positions, y = {}, 0
			local measured = use(heights)
			for _, row in use(rows) do
				if row.state ~= "queued" then
					positions[row.id] = y
					y += (measured[row.id] or 72) + 8
				end
			end
			return { positions = positions, height = math.max(0, y - 8) }
		end)
		local stackHeight = runtime.spring(function(use)
			return use(layout).height
		end, { period = 0.3, damping = 1 })
		local function reduced()
			return ctx.reducedMotion and ctx.reducedMotion:peek() or false
		end
		local function reconcile(input, now)
			local result, visible, queued = {}, {}, {}
			for _, source in input do
				local row = table.clone(source)
				if row.state == "visible" and now >= row.shown + math.max(row.duration, row.readFloor) then
					row.state, row.departed = "exiting", now
				end
				if row.state ~= "exiting" or (not reduced() and now - row.departed < 0.25) then
					table.insert(result, row)
					if row.state == "visible" then
						table.insert(visible, row)
					elseif row.state == "queued" then
						table.insert(queued, row)
					end
				end
			end
			table.sort(queued, function(a, b)
				return if a.priority == b.priority then a.id < b.id else a.priority > b.priority
			end)
			while #visible < 3 and #queued > 0 do
				local row = table.remove(queued, 1)
				row.state, row.shown = "visible", now
				table.insert(visible, row)
			end
			if #queued > 0 then
				local victim
				for _, row in visible do
					if
						now - row.shown >= row.readFloor
						and queued[1].priority > row.priority
						and (not victim or row.priority < victim.priority)
					then
						victim = row
					end
				end
				if victim then
					victim.state, victim.departed = "exiting", now
					local row = table.remove(queued, 1)
					row.state, row.shown = "visible", now
				end
			end
			local rejected = {}
			while #queued > 8 do
				local row = table.remove(queued)
				rejected[row.id] = true
				dropped += 1
			end
			local kept = {}
			for _, row in result do
				if not rejected[row.id] then
					table.insert(kept, row)
				end
			end
			return kept
		end
		local function publish(next)
			rows:set(reconcile(next, clock.elapsed:peek()))
		end
		local function show(title, detail, options)
			local o = options or {}
			local next = table.clone(rows:peek())
			if #next == 0 then
				stackEdge:set(edge:peek())
			end
			if o.subject then
				for index, old in next do
					if old.subject == o.subject then
						local row = table.clone(old)
						row.title, row.detail, row.duration, row.readFloor =
							title, detail, o.duration or 4, o.readFloor or 0.5
						row.priority, row.shown, row.departed = o.priority or old.priority, clock.elapsed:peek(), nil
						row.state = if old.state == "queued" then "queued" else "visible"
						next[index] = row
						superseded += 1
						publish(next)
						return row.id
					end
				end
			end
			nextId += 1
			table.insert(next, {
				id = nextId,
				title = title,
				detail = detail,
				priority = o.priority or 0,
				duration = o.duration or 4,
				readFloor = o.readFloor or 0.5,
				subject = o.subject,
				state = "queued",
			})
			publish(next)
			return nextId
		end
		local function dismiss(id)
			local next = {}
			for _, old in rows:peek() do
				local row = table.clone(old)
				if id == nil or row.id == id then
					row.state, row.departed = "exiting", clock.elapsed:peek()
				end
				table.insert(next, row)
			end
			publish(next)
		end
		Compose.watch(function(use)
			local now = use(clock.elapsed)
			local next = reconcile(rows:peek(), now)
			local before = rows:peek()
			local changed = #before ~= #next
			for index, row in next do
				if not before[index] or before[index].state ~= row.state then
					changed = true
				end
			end
			if changed then
				rows:set(next)
			end
		end)
		local function send()
			return show("Notice", "A single transient message")
		end
		local function burst()
			for i = 1, 12 do
				show(
					"Burst " .. i,
					"Queued behind the visible three",
					{ priority = i % 3, duration = 1.2, readFloor = 0.4 }
				)
			end
		end
		local function report()
			local visible, queued, exiting, ids = 0, 0, 0, {}
			for _, row in rows:peek() do
				if row.state == "visible" then
					visible += 1
					table.insert(ids, row.id)
				elseif row.state == "queued" then
					queued += 1
				else
					exiting += 1
				end
			end
			return {
				messages = visible,
				visible = visible,
				queued = queued,
				exiting = exiting,
				dropped = dropped,
				superseded = superseded,
				ids = ids,
				rows = rows:peek(),
				presses = presses:peek(),
				edge = edge:peek(),
				width = widthMode:peek(),
			}
		end
		local function screen()
			local root = Host.Frame "ToastLab" {
				Size = D2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Host.ScrollingFrame "Actions" {
					Size = D2.fromScale(1, 1),
					BackgroundTransparency = 1,
					AutomaticCanvasSize = E.AutomaticSize.Y,
					CanvasSize = D2.new(),
					Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = D.new(0, 12) }),
					UI.Label({ text = "Toasts", textRole = "title" }),
					UI.Label({
						text = "Show a toast, then try Test input. Notifications leave the controls below usable.",
						TextWrapped = true,
					}),
					UI.Picker "Edge" {
						label = "Edge for new stacks",
						selected = edge,
						options = { { value = "top", label = "Top" }, { value = "bottom", label = "Bottom" } },
					},
					UI.Picker "Width" {
						label = "Toast width",
						selected = widthMode,
						options = { { value = "fill", label = "Wide" }, { value = "hug", label = "Fit content" } },
					},
					Host.Frame "Commands" {
						Size = D2.new(1, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.Y,
						BackgroundTransparency = 1,
						Host.UIListLayout({
							SortOrder = E.SortOrder.LayoutOrder,
							FillDirection = E.FillDirection.Horizontal,
							Wraps = true,
							Padding = D.new(0, 8),
						}),
						UI.Button "Send" { label = "Show toast", onActivate = send },
						UI.Button "Pair" {
							label = "Show pair",
							onActivate = function()
								show(
									"First message",
									"The other toast slides into this space",
									{ duration = 3, readFloor = 0 }
								)
								show(
									"Second message",
									"Still here after the first leaves",
									{ duration = 8, readFloor = 0 }
								)
							end,
						},
						UI.Button "Burst" { label = "Burst", onActivate = burst },
						UI.Button "Priority" {
							label = "Priority",
							onActivate = function()
								show("Urgent", "Arrived during another toast's read floor", { priority = 9 })
							end,
						},
						UI.Button "Supersede" {
							label = "Supersede",
							onActivate = function()
								show("Subject", "Revision " .. (superseded + 1), { subject = "lap-time" })
							end,
						},
						UI.Button "Clear" {
							label = "Dismiss messages",
							onActivate = function()
								dismiss()
							end,
						},
					},
					UI.Button "Beneath" {
						label = function(use)
							return "Test input: " .. use(presses)
						end,
						onActivate = function()
							presses:set(presses:peek() + 1)
						end,
					},
					UI.Label "Status" {
						text = function(use)
							use(rows)
							local r = report()
							return string.format(
								"Visible %d · queued %d · dropped %d",
								r.visible,
								r.queued,
								r.dropped
							)
						end,
						TextWrapped = true,
					},
				},
				Host.Frame "Messages" {
					BackgroundTransparency = 1,
					Active = false,
					ZIndex = 10,
					Position = function(use)
						return if use(stackEdge) == "top" then D2.fromOffset(8, 8) else D2.new(0, 8, 1, -8)
					end,
					AnchorPoint = function(use)
						return V2.new(0, if use(stackEdge) == "top" then 0 else 1)
					end,
					Size = function(use)
						return D2.new(
							1,
							-16,
							0,
							if ctx.reducedMotion and use(ctx.reducedMotion)
								then use(layout).height
								else use(stackHeight)
						)
					end,
					Compose.OrderedCollection({
						from = function(use)
							local visible = {}
							for _, row in use(rows) do
								if row.state ~= "queued" then
									table.insert(visible, row)
								end
							end
							return visible
						end,
						key = function(row)
							return row.id
						end,
						render = function(current, placement)
							local id = current:peek().id
							local top = runtime.spring(function(use)
								return use(layout).positions[id] or 0
							end, { period = 0.3, damping = 1 })
							local arrived = Compose.cell(false)
							local alpha = runtime.tween(function(use)
								return if use(arrived) and use(current).state == "visible" then 1 else 0
							end, { seconds = 0.2 })
							arrived:set(true)
							local natural = Compose.cell(0)
							local measurements = {}
							for _, field in { "title", "detail" } do
								local text = UI.Label({
									Name = "Measure_" .. field,
									text = function(use)
										return use(current)[field]
									end,
									TextWrapped = false,
									Visible = false,
									AutomaticSize = E.AutomaticSize.XY,
									Size = D2.new(),
								})
								measurements[field] = text
							end
							local function measure()
								natural:set(
									math.max(measurements.title.TextBounds.X, measurements.detail.TextBounds.X) + 24
								)
							end
							for _, text in measurements do
								local connection = text:GetPropertyChangedSignal("TextBounds"):Connect(measure)
								Compose.cleanup(function()
									connection:Disconnect()
								end)
							end
							measure()
							local card = Host.CanvasGroup "Toast" {
								Active = false,
								Selectable = false,
								AutomaticSize = E.AutomaticSize.Y,
								LayoutOrder = function(use)
									return use(placement).index
								end,
								AnchorPoint = V2.new(0.5, 0),
								Position = function(use)
									return D2.new(
										0.5,
										0,
										0,
										if ctx.reducedMotion and use(ctx.reducedMotion)
											then use(layout).positions[id] or 0
											else use(top)
									)
								end,
								Size = function(use)
									return if use(widthMode) == "hug"
										then D2.fromOffset(
											math.min(560, use(availableWidth), math.max(80, use(natural))),
											0
										)
										else D2.new(1, 0, 0, 0)
								end,
								GroupTransparency = function(use)
									return 1
										- (
											if ctx.reducedMotion and use(ctx.reducedMotion)
												then (if use(current).state == "visible" then 1 else 0)
												else use(alpha)
										)
								end,
								measurements.title,
								measurements.detail,
								Host.UIPadding({
									PaddingLeft = D.new(0, 12),
									PaddingRight = D.new(0, 12),
									PaddingTop = D.new(0, 8),
									PaddingBottom = D.new(0, 8),
								}),
								Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = D.new(0, 4) }),
								UI.Label "Title" {
									textRole = "strong",
									text = function(use)
										return use(current).title
									end,
									TextWrapped = true,
									Size = D2.new(1, 0, 0, 0),
									AutomaticSize = E.AutomaticSize.Y,
								},
								UI.Label "Detail" {
									role = "secondary",
									text = function(use)
										return use(current).detail
									end,
									TextWrapped = true,
									Size = D2.new(1, 0, 0, 0),
									AutomaticSize = E.AutomaticSize.Y,
								},
							}
							local connection = card:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
								if card.AbsoluteSize.Y > 0 and heights:peek()[id] ~= card.AbsoluteSize.Y then
									local next = table.clone(heights:peek())
									next[id] = card.AbsoluteSize.Y
									heights:set(next)
								end
							end)
							Compose.cleanup(function()
								connection:Disconnect()
								local next = table.clone(heights:peek())
								next[id] = nil
								heights:set(next)
							end)
							card:AddTag("facet-panel")
							return card
						end,
					}),
				},
			}
			local messages = root:FindFirstChild("Messages")
			local connection = messages:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				if messages.AbsoluteSize.X > 0 then
					availableWidth:set(messages.AbsoluteSize.X)
				end
			end)
			Compose.cleanup(function()
				connection:Disconnect()
			end)
			return root
		end
		return {
			screen = screen,
			steps = {
				send = send,
				clear = function()
					dismiss()
				end,
				burst = burst,
			},
			show = show,
			dismiss = dismiss,
			edge = edge,
			width = widthMode,
			report = report,
		}
	end,
}
