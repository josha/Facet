--!strict
-- Scenario 'row_actions' (roadmap Task 11, docs/plans/row-actions-
-- implementation.md; hosted mode: docs/plans/row-actions-hosted-mode-design.
-- md). A mail-style list: the SwiftUI-parity swipe-actions gallery fixture, in
-- the three shapes a game actually builds a list with.
--
-- THREE SURFACES, one shared mail model per surface (independent state, so
-- deleting in one never touches the others):
--   "list"  a plain ScrollView > VStack of HAND-WRAPPED rows, each built with
--           `LuauUI.newRowActions` directly and sharing ONE
--           `LuauUI.newRowActionsCoordinator()` — the non-Table path Task 7
--           exists for. Every row carries an explicit `id` (required the
--           moment a coordinator is shared — row_actions.luau refuses a
--           collision-prone default id at build time).
--   "table" a reorderable, editable `LuauUI.newTable` using the public
--           `rowActions` spec key (Task 10) — Table owns the wrapping, the
--           shared coordinator, and the reorder/swipe axis-lock dispatcher.
--   "vlist" a `LuauUI.newVirtualList` using its own public `rowActions` spec
--           key (row-actions perf mission) — a CLOSED row here mounts NOTHING
--           beyond the row `Hit` it always had; the gesture engine builds
--           lazily on the first gesture that resolves horizontal past the
--           axis lock. There is no per-row wrapper to reach into (unlike
--           "list"'s `_open`/`_close`/`_commitFirst`), so this surface has no
--           scripted open/close/commit steps of its own — a real swipe is the
--           only way in, the same standing limitation the "table" surface's
--           own comment below already names for its own swipe.
--
-- Actions (same shape on both surfaces): trailing = Delete (destructive) +
-- Flag; leading = Mark Read. `fullSwipe = true` on both edges, so a full
-- swipe commits the edge's first action (Delete on the right, Mark Read on
-- the left) — the SwiftUI behavior this whole feature exists to match.
--
-- DRIVE SURFACE. Every interaction a real player has is also a scripted
-- STATE/ACTION driver here (never counterfeited hardware input, exactly like
-- every other scenario's `steps`): open/close/commit a list row directly
-- through its `_open`/`_close`/`_commitFirst` seams (the same internal hooks
-- Table's own dispatcher calls), toggle table edit mode, and drive the
-- keyboard Delete / Shift+Return menu chords through the REAL action system
-- (`ctx.actionSystem.deviceKey` — a scripted device-state driver in every
-- environment, headless or Studio, not a hardware injector). A native touch/
-- mouse swipe on the TABLE surface is the one interaction this scenario
-- cannot drive itself; that is the standing input-tools limitation the
-- device-matrix artifact records per row.

local SEED = {
	{
		id = "m1",
		from = "Ari Foyer",
		subject = "Kickoff notes",
		preview = "Quick recap from the sync — three follow-ups, none urgent.",
		read = false,
		flagged = false,
	},
	{
		id = "m2",
		from = "Sip Works",
		subject = "Order confirmed",
		preview = "Your order #4521 ships Thursday.",
		read = true,
		flagged = false,
	},
	{
		id = "m3",
		from = "Glade Team",
		subject = "Weekly digest",
		preview = "Here's what happened in the glade this week.",
		read = false,
		flagged = true,
	},
	{
		id = "m4",
		from = "Wardrobe Co",
		subject = "Restock alert",
		preview = "Back in stock: the item you asked about.",
		read = true,
		flagged = false,
	},
	{
		id = "m5",
		from = "Cartwheel Studio",
		subject = "Beta invite",
		preview = "You're in — here's how to get started.",
		read = false,
		flagged = false,
	},
	{
		id = "m6",
		from = "Rally Ops",
		subject = "Standings update",
		preview = "Leaderboard shuffled after today's heats.",
		read = true,
		flagged = false,
	},
}

local function cloneRows(): { any }
	local out = {}
	for i, m in SEED do
		out[i] = { id = m.id, from = m.from, subject = m.subject, preview = m.preview }
	end
	return out
end

-- ONE mail model per surface: a `rows` signal (add/remove/reorder) plus
-- per-id read/flagged signals (fine-grained — an action never rebuilds the
-- whole row list, mirroring examples/gallery/examples/02_playlist_table's
-- own `ratingFor` shape).
local function newMailModel(core: any)
	local rows = core:signal(cloneRows())
	local readFor: { [string]: any }, flaggedFor: { [string]: any } = {}, {}
	for _, m in SEED do
		readFor[m.id] = core:signal(m.read == true)
		flaggedFor[m.id] = core:signal(m.flagged == true)
	end
	local model: any = { rows = rows, readFor = readFor, flaggedFor = flaggedFor }
	function model.markRead(id: string)
		local sig = readFor[id]
		if sig ~= nil then
			sig:set(true)
		end
	end
	function model.toggleFlag(id: string)
		local sig = flaggedFor[id]
		if sig ~= nil then
			sig:set(not sig:get())
		end
	end
	function model.remove(id: string)
		local out = {}
		for _, m in rows:get() do
			if m.id ~= id then
				table.insert(out, m)
			end
		end
		rows:set(out)
	end
	function model.ids(): { string }
		local out = {}
		for _, m in rows:get() do
			table.insert(out, m.id)
		end
		return out
	end
	-- `reorderable = true` only shows the drop line — the table never mutates
	-- caller rows (02_playlist_table's own `onReorder` comment). `keys` are
	-- the moving rows (single-select drag: always one), `toIndex` the
	-- destination among the STAYING rows.
	function model.reorder(keys: { string }, toIndex: number)
		local movingSet: { [string]: boolean } = {}
		for _, key in keys do
			movingSet[key] = true
		end
		local moving, staying = {}, {}
		for _, m in rows:get() do
			table.insert(if movingSet[m.id] then moving else staying, m)
		end
		local out = {}
		for i = 1, toIndex do
			table.insert(out, staying[i])
		end
		for _, m in moving do
			table.insert(out, m)
		end
		for i = toIndex + 1, #staying do
			table.insert(out, staying[i])
		end
		rows:set(out)
	end
	return model
end

-- The ActionSpec triple every row on both surfaces shares. `label`s are short
-- on purpose (localization-safe: a 1.4x pseudo-loc expansion of "Delete" or
-- "Mark Read" still fits a 64px tray button — the framework floor, not this
-- fixture's).
local function actionsFor(model: any, itemId: string): any
	return {
		leading = {
			{
				id = "read",
				role = "normal",
				label = "Mark Read",
				onAction = function()
					model.markRead(itemId)
				end,
			},
		},
		trailing = {
			{
				id = "delete",
				role = "destructive",
				label = "Delete",
				-- Task 15: the framework's own trash glyph, carried on the
				-- tray button as `compactLabel = { icon = … }` (row_actions.luau's
				-- `buildTray`/`buildMenuRows` — `Button.icon` itself is
				-- circle-only). "Delete" draws in full at rest; this row's
				-- own icon shows only once its button narrows below that,
				-- mid-swipe. `trash`/`flag` are LIVE content ids now
				-- (assets/icons/provenance.md "Upload closed" —
				-- rbxassetid://84398508341623 / rbxassetid://109067109704366,
				-- both verified Approved/Image), so this row draws the real
				-- glyph rather than the ASCII fallback.
				icon = "trash",
				onAction = function()
					model.remove(itemId)
				end,
			},
			{
				id = "flag",
				role = "normal",
				label = "Flag",
				icon = "flag",
				onAction = function()
					model.toggleFlag(itemId)
				end,
			},
		},
		fullSwipe = true,
	}
end

return {
	title = "Row actions (Task 11 + row-actions perf mission): mail-style list + table + hosted VirtualList",
	ledgerRows = { "ROW-ACTIONS-EX1", "ROW-ACTIONS-EX2", "ROW-ACTIONS-EX3" },
	build = function(ctx: any)
		local LuauUI = ctx.LuauUI
		local UI = LuauUI.UI
		local core = ctx.core

		local mode = core:signal("list")

		-- ===== surface 1: plain ScrollView > VStack, hand-wrapped rows =========
		local listModel = newMailModel(core)
		local coordinator = LuauUI.newRowActionsCoordinator(core)
		local listRows: { [string]: any } = {}

		local function rowContent(model: any, item: any): any
			local unreadDot = model.readFor[item.id]
			local flagged = model.flaggedFor[item.id]
			local showDot = core:memo(function(use)
				return not use(unreadDot)
			end)
			return UI.Button({
				id = "Row",
				label = `{item.subject} from {item.from}`,
				gap = "s",
				align = "center",
				width = { type = "fill", weight = 1 },
				padding = { top = 10, bottom = 10, left = 14, right = 14 },
				surface = "base",
				onActivate = function()
					model.markRead(item.id)
				end,
				children = {
					UI.When({
						id = "DotWhen",
						condition = showDot,
						thenView = function()
							return UI.Box({
								id = "Dot",
								width = { type = "fixed", px = 8 },
								height = { type = "fixed", px = 8 },
								surface = "accent",
							})
						end,
					}),
					UI.VStack({
						id = "Text",
						gap = 2,
						width = { type = "fill", weight = 1 },
						children = {
							UI.HStack({
								id = "TopLine",
								gap = "s",
								children = {
									UI.Text({ id = "From", text = item.from, textSize = 15 }),
									UI.When({
										id = "FlagWhen",
										condition = flagged,
										thenView = function()
											return UI.Text({ id = "Flag", text = "\u{1F6A9}", textSize = 13 })
										end,
									}),
								},
							}),
							UI.Text({ id = "Subject", text = item.subject, textSize = 14 }),
							UI.Text({ id = "Preview", text = item.preview, textSize = 12, role = "secondary" }),
						},
					}),
				},
			})
		end

		local rowsForEach = UI.ForEach({
			id = "RowsForEach",
			items = listModel.rows,
			key = function(item)
				return item.id
			end,
			row = function(item, itemScope)
				local actions = actionsFor(listModel, item.id)
				local built = LuauUI.newRowActions(LuauUI, core, {
					id = item.id,
					-- restores the row's normal list-flow width — `content` is
					-- itself `width = fill` with nothing to measure against once
					-- it sits inside a content-sized composite root (row_actions.
					-- luau's own `width` field comment; table.luau's identical fix)
					width = { type = "fill", weight = 1 },
					content = rowContent(listModel, item),
					leading = actions.leading,
					trailing = actions.trailing,
					fullSwipe = actions.fullSwipe,
					coordinator = coordinator,
				})
				listRows[item.id] = built
				itemScope:own(function()
					listRows[item.id] = nil
					built.dispose()
				end)
				return built.blueprint
			end,
		})

		-- ScrollView > VStack: the VStack is what makes this the hand-wrapped,
		-- non-Table shape (a ScrollView can stack children on its own axis, but
		-- a caller building a plain reactive list of rows writes it the same way
		-- as any other VStack list — the ScrollView only adds the scroll host).
		local listBody = UI.ScrollView({
			id = "List",
			axis = "y",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			children = {
				UI.VStack({
					id = "Rows",
					gap = 1,
					width = { type = "fill", weight = 1 },
					children = { rowsForEach },
				}),
			},
		})

		-- ===== surface 2: reorderable, editable Table with `rowActions` ========
		local tableModel = newMailModel(core)
		local editingSignal = core:signal(false)
		local tbl = LuauUI.newTable(LuauUI, core, {
			id = "MailTable",
			columns = {
				{ id = "from", title = "From", width = { type = "fixed", px = 150 } },
				{ id = "subject", title = "Subject", width = { type = "fill", weight = 1 }, minWidth = 120 },
			},
			rows = tableModel.rows,
			key = function(item)
				return item.id
			end,
			cellFor = function(columnId: string, item: any): any
				local text = if columnId == "from" then item.from else item.subject
				return UI.Text({ id = "Value", text = text, textSize = 14 })
			end,
			rowHeight = 44,
			header = true,
			selection = "single",
			reorderable = true,
			onReorder = function(keys: { string }, toIndex: number)
				tableModel.reorder(keys, toIndex)
			end,
			editing = editingSignal,
			rowActions = function(item: any): any
				local actions = actionsFor(tableModel, item.id)
				return { leading = actions.leading, trailing = actions.trailing, fullSwipe = actions.fullSwipe }
			end,
			env = ctx.env,
		})

		local tableBody = UI.VStack({
			id = "TablePane",
			gap = "s",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			children = {
				UI.HStack({
					id = "TableToolbar",
					gap = "s",
					children = {
						UI.Button({
							id = "EditToggle",
							label = core:memo(function(use)
								return if use(editingSignal) then "Done" else "Edit"
							end),
							onActivate = function()
								editingSignal:set(not editingSignal:get())
							end,
						}),
					},
				}),
				tbl.blueprint,
			},
		})

		-- ===== surface 3: `newVirtualList` with hosted `rowActions` ============
		-- No composite, no per-row wrapper: a closed row here is the SAME row a
		-- plain (no-`rowActions`) VirtualList would mount, plus four static
		-- handler props on its `Hit`. `cell` returns plain row content — the
		-- list's own `Hit` already supplies the whole-row focus ring and
		-- tap/Return/ButtonA activate, so unlike "list"'s `rowContent` this one
		-- is not itself a `UI.Button`.
		local vlModel = newMailModel(core)
		local function vlRowContent(item: any): any
			local unreadDot = vlModel.readFor[item.id]
			local flagged = vlModel.flaggedFor[item.id]
			local showDot = core:memo(function(use)
				return not use(unreadDot)
			end)
			return UI.HStack({
				id = "RowBody",
				gap = "s",
				align = "center",
				width = { type = "fill", weight = 1 },
				padding = { top = 10, bottom = 10, left = 14, right = 14 },
				children = {
					UI.When({
						id = "DotWhen",
						condition = showDot,
						thenView = function()
							return UI.Box({
								id = "Dot",
								width = { type = "fixed", px = 8 },
								height = { type = "fixed", px = 8 },
								surface = "accent",
							})
						end,
					}),
					UI.VStack({
						id = "Text",
						gap = 2,
						width = { type = "fill", weight = 1 },
						children = {
							UI.HStack({
								id = "TopLine",
								gap = "s",
								children = {
									UI.Text({ id = "From", text = item.from, textSize = 15 }),
									UI.When({
										id = "FlagWhen",
										condition = flagged,
										thenView = function()
											return UI.Text({ id = "Flag", text = "\u{1F6A9}", textSize = 13 })
										end,
									}),
								},
							}),
							UI.Text({ id = "Subject", text = item.subject, textSize = 14 }),
							UI.Text({ id = "Preview", text = item.preview, textSize = 12, role = "secondary" }),
						},
					}),
				},
			})
		end

		local vlist = LuauUI.newVirtualList(LuauUI, core, {
			id = "VList",
			rows = vlModel.rows,
			key = function(item: any)
				return item.id
			end,
			rowHeight = 84,
			viewportHeight = 336, -- 4 rows visible
			overscan = 2,
			cell = function(item: any)
				return vlRowContent(item)
			end,
			onActivate = function(item: any)
				vlModel.markRead(item.id)
			end,
			-- the public hosted-mode seam (docs/reference/api.md's `newVirtualList`
			-- `rowActions` field): same three-key shape "list"/"table" already
			-- share via `actionsFor`, so the fixture proves one action set draws
			-- identically wrapped, hosted, or standalone.
			rowActions = function(item: any): any
				local actions = actionsFor(vlModel, item.id)
				return { leading = actions.leading, trailing = actions.trailing, fullSwipe = actions.fullSwipe }
			end,
			env = ctx.env,
		})

		local vlistBody = UI.VStack({
			id = "VListPane",
			gap = "s",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			children = {
				UI.Text({
					id = "VListHint",
					text = "Swipe a row (real touch/mouse — no scripted step reaches this surface)",
					textSize = 12,
					role = "secondary",
				}),
				vlist.blueprint,
			},
		})

		local screen = UI.Screen({
			id = "MailActions",
			surface = "base",
			padding = "m",
			gap = "s",
			children = {
				UI.Text({ id = "Title", text = "Row actions — Mail", textSize = "title" }),
				UI.HStack({
					id = "ModeBar",
					gap = "s",
					children = {
						UI.Button({
							id = "ModeList",
							label = "List",
							onActivate = function()
								mode:set("list")
							end,
						}),
						UI.Button({
							id = "ModeTable",
							label = "Table",
							onActivate = function()
								mode:set("table")
							end,
						}),
						UI.Button({
							id = "ModeVList",
							label = "VirtualList",
							onActivate = function()
								mode:set("vlist")
							end,
						}),
					},
				}),
				UI.When({
					id = "ListWhen",
					condition = core:memo(function(use)
						return use(mode) == "list"
					end),
					thenView = function()
						return listBody
					end,
				}),
				UI.When({
					id = "TableWhen",
					condition = core:memo(function(use)
						return use(mode) == "table"
					end),
					thenView = function()
						return tableBody
					end,
				}),
				UI.When({
					id = "VListWhen",
					condition = core:memo(function(use)
						return use(mode) == "vlist"
					end),
					thenView = function()
						return vlistBody
					end,
				}),
			},
		})

		local function pressKey(key: string)
			ctx.actionSystem.deviceKey(key, true)
			ctx.actionSystem.deviceKey(key, false)
		end

		return {
			screen = screen,
			present = {},

			steps = {
				-- state drivers -----------------------------------------------------
				mode = function(_built: any, payload: string?)
					local m = tostring(payload)
					if m ~= "list" and m ~= "table" and m ~= "vlist" then
						return { ok = false, reason = "mode must be 'list', 'table' or 'vlist'" }
					end
					mode:set(m)
					return { ok = true, mode = m }
				end,
				-- "id:edge" — the same internal seam Table's own dispatcher calls
				-- (row_actions.luau `_open`); a scripted stand-in for a swipe past
				-- the axis lock
				open = function(_built: any, payload: string?)
					local id, edge = string.match(payload or "", "^([^:]+):(.+)$")
					local row = id and listRows[id]
					if row == nil then
						return { ok = false, reason = `no list row '{tostring(id)}'` }
					end
					row._open(edge)
					return { ok = true, dump = row.dump() }
				end,
				close = function(_built: any, payload: string?)
					local row = listRows[tostring(payload)]
					if row == nil then
						return { ok = false, reason = `no list row '{tostring(payload)}'` }
					end
					row._close()
					return { ok = true, dump = row.dump() }
				end,
				-- "id:edge" — fires the edge's FIRST action (Delete on trailing,
				-- Mark Read on leading), same as a full swipe or the keyboard
				-- Delete path
				commit = function(_built: any, payload: string?)
					local id, edge = string.match(payload or "", "^([^:]+):(.+)$")
					local row = id and listRows[id]
					if row == nil then
						return { ok = false, reason = `no list row '{tostring(id)}'` }
					end
					local fired = row._commitFirst(edge)
					return { ok = true, fired = fired, remainingIds = listModel.ids() }
				end,
				editing = function(_built: any, payload: string?)
					editingSignal:set(payload == "on")
					return { editing = editingSignal:get() }
				end,
				-- REAL keyboard Delete, through the real action system, on a
				-- focused list row's content — not a shortcut to _commitFirst
				keyDeleteList = function(_built: any, payload: string?)
					local id = tostring(payload)
					local path = `/MailActions/ListWhen/then/List/Rows/RowsForEach/[{id}]/{id}/Content/Row`
					ctx.presenter.focus.focusOn(path)
					pressKey("Delete")
					return { ok = true, remainingIds = listModel.ids() }
				end,
				-- REAL Shift+Return chord (Task 8b), focused on a list row
				menuList = function(_built: any, payload: string?)
					local id = tostring(payload)
					local path = `/MailActions/ListWhen/then/List/Rows/RowsForEach/[{id}]/{id}/Content/Row`
					ctx.presenter.focus.focusOn(path)
					ctx.actionSystem.deviceKey("LeftShift", true)
					ctx.actionSystem.deviceKey("Return", true)
					ctx.actionSystem.deviceKey("Return", false)
					ctx.actionSystem.deviceKey("LeftShift", false)
					local row = listRows[id]
					return { ok = true, dump = row and row.dump() }
				end,
				bindScroll = function(built: any)
					if built.handle == nil then
						return { ok = false, reason = "not presented yet" }
					end
					local unbind = coordinator.bindScroll(built.handle.controller, "/MailActions/ListWhen/then/List")
					return { ok = true, unbind = unbind ~= nil }
				end,
				list = function()
					return { list = listModel.ids(), table = tableModel.ids(), vlist = vlModel.ids() }
				end,
				-- the hosted surface's own debug seam (`_hostedDebug`, the SAME
				-- leading-underscore driving-hook convention as the "list" surface's
				-- `_open`/`_close`/`_commitFirst`): how many gesture engines exist and
				-- which row is engaged, without a per-row handle to ask
				vlistDebug = function()
					return vlist._hostedDebug()
				end,
			},

			report = function()
				local dumps: { [string]: any } = {}
				for id, row in listRows do
					dumps[id] = row.dump()
				end
				return {
					mode = mode:get(),
					listIds = listModel.ids(),
					tableIds = tableModel.ids(),
					vlistIds = vlModel.ids(),
					tableEditing = editingSignal:get(),
					listRowDumps = dumps,
					vlistHosted = vlist._hostedDebug(),
				}
			end,

			dispose = function()
				if tbl.dispose ~= nil then
					tbl.dispose()
				end
				vlist.dispose()
			end,
		}
	end,
}
