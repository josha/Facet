--!strict
local COPY = {
	title = "Rows that say no",
	intro = "One table. Five rows. Three of them opt out of something the others allow.",

	colName = "Run sheet",
	colLock = "Opt-out",

	rowGrid = "Grid formation",
	rowWarmup = "Warm-up lap",
	rowMain = "Main event",
	rowNotes = "Marshal notes",
	rowCool = "Cool-down lap",

	lockNone = "—",
	lockPinned = "pinned",
	lockProtected = "protected",
	lockLocked = "locked",

	moveUp = "Move up",
	moveDown = "Move down",

	selectedPrefix = "Selected",
	selectedNone = "nothing yet — tap a row",
	orderPrefix = "Order",
	refusedCount = "Refusals",

	refusalIdle = "Nothing refused yet. Tap the locked row, move the pinned one, or delete the protected one.",
	askSelect = "may this row be selected?",
	askMove = "may this row be moved?",
	askDelete = "may this row be deleted?",
	answerNo = "no",

	legendPinned = "pinned (rowMovable) — select it and press Move up. The order does not change, and nothing can move past it either: a pinned row holds its index.",
	legendProtected = "protected (rowDeletable) — swipe it and press Delete, or press the minus in Edit. The row stays. The buttons are still drawn, and they do nothing.",
	legendLocked = "locked (rowSelectable) — tap it. The selection above does not move.",
	footer = "The refusal line is written by the three predicates themselves, at the instant the framework asks them.",
}

local SEED = {
	{ id = "grid", nameKey = "rowGrid", lock = "move" },
	{ id = "warmup", nameKey = "rowWarmup", lock = nil },
	{ id = "main", nameKey = "rowMain", lock = "delete" },
	{ id = "notes", nameKey = "rowNotes", lock = "select" },
	{ id = "cool", nameKey = "rowCool", lock = nil },
}

return {
	title = "Rows that say no",
	copy = COPY,
	seed = SEED,
	build = function(ctx)
		local Host, UI, Compose = ctx.Host, ctx.UI, ctx.Compose
		local UDim, UDim2, Enum = ctx.types.UDim, ctx.types.UDim2, ctx.types.Enum
		local rows = Compose.cell(table.clone(SEED))
		local selection = Compose.cell({})
		local message = Compose.cell(COPY.refusalIdle)
		local function remove(id)
			local next = {}
			for _, item in rows:peek() do
				if item.id == id and item.lock == "delete" then
					message:set("This row is protected.")
					return
				end
				if item.id ~= id then
					table.insert(next, item)
				end
			end
			rows:set(next)
		end
		local function reorder(keys, index)
			local moving, rest = {}, {}
			for _, item in rows:peek() do
				table.insert(if table.find(keys, item.id) then moving else rest, item)
			end
			local next = {}
			for i = 1, index do
				table.insert(next, rest[i])
			end
			for _, item in moving do
				table.insert(next, item)
			end
			for i = index + 1, #rest do
				table.insert(next, rest[i])
			end
			rows:set(next)
		end
		return {
			screen = function()
				return Host.Frame({
					Name = "RowCapabilities",
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					UI.Label({
						Name = "Title",
						Text = COPY.title,
						TextSize = 24,
						Size = UDim2.new(1, 0, 0, 36),
						BackgroundTransparency = 1,
					}),
					UI.Label({
						Name = "Explanation",
						Text = "Pinned rows cannot move. Protected rows cannot be deleted. Locked rows cannot be selected.",
						TextWrapped = true,
						Position = UDim2.fromOffset(0, 40),
						Size = UDim2.new(1, 0, 0, 56),
						BackgroundTransparency = 1,
					}),
					UI.Table({
						Name = "RunSheet",
						Position = UDim2.fromOffset(0, 100),
						Size = UDim2.new(1, 0, 1, -164),
						from = rows,
						key = function(item)
							return item.id
						end,
						selection = selection,
						selectionMode = "single",
						selectable = function(item)
							return item.lock ~= "select"
						end,
						movable = function(item)
							return item.lock ~= "move"
						end,
						reorderable = true,
						onReorder = reorder,
						columns = {
							{
								id = "name",
								label = COPY.colName,
								width = 260,
								value = function(item)
									return COPY[item.nameKey]
								end,
							},
							{
								id = "lock",
								label = COPY.colLock,
								width = 140,
								value = function(item)
									return item.lock or "—"
								end,
							},
						},
						rowActions = function(current, key)
							return {
								trailing = {
									{
										id = "delete",
										label = "Delete",
										role = "destructive",
										enabled = function(use)
											return use(current).lock ~= "delete"
										end,
										onActivate = function()
											remove(key)
										end,
									},
								},
							}
						end,
					}),
					UI.Label({
						Name = "Status",
						Position = UDim2.new(0, 0, 1, -56),
						Size = UDim2.new(1, 0, 0, 56),
						Text = message,
						TextWrapped = true,
						BackgroundTransparency = 1,
					}),
				})
			end,
			report = function()
				return { rows = rows:peek(), selection = selection:peek(), message = message:peek() }
			end,
		}
	end,
}
