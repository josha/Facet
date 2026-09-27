return {
	title = "Toasts",
	build = function(ctx)
		local Host, UI, Compose, runtime = ctx.Host, ctx.UI, ctx.Compose, ctx.runtime
		local D, D2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Enum
		local rows, presses, edge, widthMode =
			Compose.cell({}), Compose.cell(0), Compose.cell("bottom"), Compose.cell("fill")
		local clock = runtime.timeline({ duration = 86400, repeats = math.huge })
		local nextId, dropped, superseded = 0, 0, 0
		local anchors = setmetatable({}, { __mode = "v" })
		local revision = Compose.cell(0)
		local function update(id, change)
			local next = {}
			for _, row in rows:peek() do
				if id == nil or row.id == id then
					row = table.clone(row)
					change(row)
				end
				table.insert(next, row)
			end
			rows:set(next)
		end
		local function show(title, detail, options)
			local o = options or {}
			nextId += 1
			local next = table.clone(rows:peek())
			table.insert(next, {
				id = nextId,
				title = title,
				detail = detail,
				priority = o.priority or 0,
				duration = o.duration or 4,
				readFloor = o.readFloor,
				key = o.subject,
				position = edge:peek(),
				width = widthMode:peek(),
				presented = true,
			})
			rows:set(next)
			return nextId
		end
		local function dismiss(id)
			update(id, function(row)
				row.presented = false
			end)
		end
		local function retire(id, reason)
			if reason == "capacity" then
				dropped += 1
			elseif reason == "supersede" then
				superseded += 1
			end
			update(id, function(row)
				row.presented, row.retired = false, clock.elapsed:peek()
			end)
		end
		Compose.watch(function(use)
			local now = use(clock.elapsed)
			local kept, pruned = {}, false
			for _, row in rows:peek() do
				if row.retired and now - row.retired >= 0.3 then
					pruned = true
				else
					table.insert(kept, row)
				end
			end
			if pruned then
				rows:set(kept)
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
			local visible, queued, exiting, ids, states = 0, 0, 0, {}, {}
			for _, row in rows:peek() do
				local anchor = anchors[row.id]
				local state = if anchor and anchor:GetAttribute("ToastVisible")
					then "visible"
					elseif anchor and anchor:GetAttribute("ToastQueued") then "queued"
					else "exiting"
				states[row.id] = state
				if state == "visible" then
					visible += 1
					table.insert(ids, row.id)
				elseif state == "queued" then
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
				states = states,
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
				UI.ScrollView "Actions" {
					padding = 16,
					gap = 12,
					Size = D2.fromScale(1, 1),
					BackgroundTransparency = 1,
					UI.Text({ text = "Toasts", textRole = "title" }),
					UI.Text({
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
					UI.Text "Status" {
						text = function(use)
							use(rows)
							use(revision)
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
					Size = D2.fromScale(0, 0),
					Compose.OrderedCollection({
						from = rows,
						key = function(row)
							return row.id
						end,
						render = function(current)
							local row = current:peek()
							local id = row.id
							local hug = row.width == "hug"
							local function line(name, props)
								props.Name = name
								props.TextWrapped = true
								props.Size = if hug then D2.fromOffset(0, 0) else D2.fromScale(1, 0)
								props.AutomaticSize = if hug then E.AutomaticSize.XY else E.AutomaticSize.Y
								return UI.Text(props)
							end
							local anchor = UI.Toast "Toast" {
								isPresented = Compose.formula(function(use)
									return use(current).presented
								end),
								onPresentedChange = function(presented)
									if not presented then
										dismiss(id)
									end
								end,
								onDismiss = function(reason)
									retire(id, reason)
								end,
								key = row.key,
								priority = row.priority,
								duration = row.duration,
								readFloor = row.readFloor,
								position = row.position,
								width = row.width,
								content = function()
									return UI.VStack "Body" {
										gap = 4,
										width = if hug then "hug" else "fill",
										line("Title", { textRole = "strong", text = row.title }),
										line("Detail", { role = "secondary", text = row.detail }),
									}
								end,
							}
							anchors[id] = anchor
							for _, name in { "ToastVisible", "ToastQueued" } do
								local connection = anchor:GetAttributeChangedSignal(name):Connect(function()
									revision:set(revision:peek() + 1)
								end)
								Compose.cleanup(function()
									connection:Disconnect()
								end)
							end
							return anchor
						end,
					}),
				},
			}
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
