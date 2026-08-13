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
--
-- `reflow` is the CALLER'S deletion animation (see `animateReflow` in `build`
-- below): a deletion is the one mutation on this model that moves every row
-- after it, and nothing animated that. Optional, and it defaults to running the
-- mutation bare, so a harness with no presenter builds the same model.
local function newMailModel(core: any, reflow: ((fn: () -> ()) -> ())?)
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
	--[[ THE RE-FLOW IS THE ANIMATION (device bug round 2026-08-12, finding C8a:
		"...and the next row doesn't animate vertically smoothly").

		The framework had already fixed the row's own departure; what nobody was
		animating is what happens to every row BELOW it, which simply teleported up
		by one row height on the commit frame. That is not a row-actions defect —
		the composite has no idea the owner's data changed — it is the ordinary
		SwiftUI pattern, and `presenter.withAnimation(class, fn)` is what shipped
		for it in this same mission (docs/plans/swiftui-parity-round2.md §Phase 1).
		The deletion is committed HERE, by the screen, which is the object that has
		the presenter, so there is no new plumbing at all.

		THE SLIDE ITSELF STAYS ON ITS OWN SPRING and must: `withAnimation` diffs
		committed layout between commits, so it structurally cannot express a
		continuous per-frame drag. It animates the consequence of a discrete
		mutation, which is exactly what a deletion is. ]]
	function model.remove(id: string)
		local out = {}
		for _, m in rows:get() do
			if m.id ~= id then
				table.insert(out, m)
			end
		end
		if reflow ~= nil then
			reflow(function()
				rows:set(out)
			end)
		else
			rows:set(out)
		end
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
				-- The framework's own trash glyph, carried on the tray button
				-- as `compactLabel = { icon = …, prefer = true }` (row_actions
				-- `buildTray` — `Button.icon` itself is circle-only). ICON-FIRST
				-- since the director's device round 2026-08-12: the tray plate
				-- wears the mark at every width and "Delete" stays the semantic
				-- name — still the drawn text of this action's MENU row, which is
				-- the reading of the tray one activation away. `Mark Read` above
				-- declares no icon and so keeps its word in the tray too.
				-- `trash`/`flag` are LIVE content ids now
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
		local scope = core:scope("row-actions-scenario")

		-- THE CHROME GIVES WAY, NOT THE CONTENT (device report 2026-08-12,
		-- IMG_3689). In landscape the showcase's picker strip takes 120px off the
		-- top, and this screen's own chrome — a `title`-sized heading, a mode bar
		-- and the Table's Edit toolbar — took the rest: the mail table solved to
		-- 27px and then to ZERO, entirely below the fold, with a `fill` pane
		-- absorbing the squeeze so quietly that no diagnostic fired until the last
		-- 3px. A screen whose subject is a list has to spend a short viewport on
		-- the list.
		--
		-- `heightClass` is the framework's own signal for "the vertical room is
		-- scarce" (`adaptive.HEIGHT_BREAKPOINTS`, ADR-0023) and it is a READABLE, so
		-- it re-resolves on rotation instead of freezing whichever orientation
		-- booted first (docs/lessons/the-solver-already-told-you.md §5). The heading
		-- is what goes: the demo picker's own chip already names this demo on screen,
		-- so on a short viewport it is the one piece of chrome that says nothing the
		-- player cannot already see.
		local conditions = LuauUI.adaptive.conditions(core, ctx.env, { scope = scope })
		local showHeading = scope:own(core:memo(function(use)
			return not use(conditions.isShort)
		end))

		local mode = core:signal("list")

		--[[ THE DELETION'S RE-FLOW, ANIMATED (device bug round 2026-08-12, finding
			C8a's third part — see `model.remove`'s own comment above for the why).
			`"container"` is the class for a large surface re-settling; the row's own
			finger-tracked slide keeps its own `"object"` spring, untouched.

			Guarded, and not for tidiness: a harness that builds this scenario without
			a presenter (or against an older one) must still be able to delete a row —
			the animation is the decoration, the mutation is the fact. Reduced motion
			needs no branch here at all: `withAnimation` installs no records under it
			(presenter.luau), so `fn` runs and the layout lands exactly, instantly. ]]
		local function animateReflow(fn: () -> ())
			local presenter = ctx.presenter
			if presenter == nil or type(presenter.withAnimation) ~= "function" then
				fn()
				return
			end
			presenter.withAnimation("container", fn)
		end

		-- ===== surface 1: plain ScrollView > VStack, hand-wrapped rows =========
		local listModel = newMailModel(core, animateReflow)
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
		local tableModel = newMailModel(core, animateReflow)
		-- the row `onPrimaryAction` last opened (nil until one is)
		local openedKey = scope:own(core:signal(nil :: string?))
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
			-- THE SECOND VERB (parity round 2 §3.4). Selecting a row and OPENING it
			-- are different things, and this surface is where you can feel the
			-- difference: click a row once and it is selected, DOUBLE-click (or
			-- Return / ButtonA on the focused row, or — on touch — tap the row you
			-- already selected) and it opens, which here means "read it". The tray
			-- gestures are untouched: a tap that closes an open tray is consumed
			-- before this ever runs, so swiping never opens a message by accident.
			onPrimaryAction = function(item: any, key: string)
				openedKey:set(key)
				tableModel.markRead(item.id)
			end,
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
		local vlModel = newMailModel(core, animateReflow)
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

		-- the hosted list's window, published from its own solved pane (see
		-- `viewportHeight` below). 336 is the boot value only — the first solve
		-- replaces it with the height this device really has.
		local ROW_HEIGHT = 84
		local VLIST_GAP = 8 -- VListPane's own "s" gap, between the hint and the list
		local VLIST_PANE = "/MailActions/VListWhen/then/VListPane"
		local vlistWindow = core:signal(336)

		local vlist = LuauUI.newVirtualList(LuauUI, core, {
			id = "VList",
			rows = vlModel.rows,
			key = function(item: any)
				return item.id
			end,
			rowHeight = ROW_HEIGHT,
			-- THE WINDOW IS THE PANE THE SOLVER GAVE IT (device report 2026-08-12,
			-- IMG_3689's sibling defect). This was a literal `336 -- 4 rows visible`,
			-- measured once on a desktop: on a landscape phone the list painted
			-- 227-245px past its own pane and over everything below it, and the solver
			-- said so at every landscape viewport. A constant that does not adapt is a
			-- constant that is wrong on some real device
			-- (docs/lessons/the-solver-already-told-you.md).
			--
			-- A Readable is what `newVirtualList` documents for exactly this ("a list
			-- filling a container... hands in a Readable and BOTH consumers of the
			-- number track it"). What it must NOT be is arithmetic over the viewport:
			-- the first attempt at this fix was `viewportHeight - chrome` and it was
			-- wrong on a portrait phone by 64px, because the mode bar re-columns to
			-- two rows there and the chrome is the SOLVER's decision, not a number
			-- this file can hold. Lesson §9: reproduce a framework's inputs, never its
			-- result — and here the input IS the solved pane, fed back through the
			-- presenter's `onGeometry` seam below, exactly as the showcase's picker
			-- strip publishes its own measured height.
			--
			-- IT CANNOT CHASE ITS OWN TAIL: `VListPane` takes `fill`, so its height is
			-- decided by the screen and never by the list inside it. One solve after a
			-- resize the window is exact; the literal below is only the value for the
			-- frame before any geometry exists.
			viewportHeight = vlistWindow,
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

		-- I5 fix: the vlist surface's own native-scroll binding. A "fixture"
		-- scenario (this file) gets NONE of the host's generic per-example
		-- auto-bind (examples/gallery/client/init.client.luau's
		-- `nativeScrollBinderOf` loop only runs on the tutorial-example path,
		-- ~347-356) — and unlike "list"'s row_actions coordinator, which the
		-- driven `bindScroll` step binds on demand, real touch/mouse on
		-- "vlist" can land before any step ever runs at all (its own hint
		-- below: "no scripted step reaches this surface"). Without this,
		-- `boundScrollPath` stays nil forever, so keep-visible never scrolls a
		-- focused row into view and `scrollTop` never mirrors the engine.
		-- Self-wired the same idiom sponsor_list.luau/sponsor_drop.luau use
		-- (`ensureBound`/`ensureWired` off `pres.onTick`), keyed off `result`
		-- below — the same table `init.client.luau` mutates with `.handle`
		-- right after `pres.present`, so the first tick after the surface
		-- actually exists is the one that binds it.
		local unbindVlistScroll: any = nil
		local unbindVlistTick: any = nil

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
			-- ...and the GUTTERS give way too, for the same reason and off the same
			-- Readable: on a 320px-tall landscape phone the screen's own frame and
			-- inter-band gaps were 40px of the 200px it had. Spacing-step NAMES, so a
			-- theme package still owns what "s" and "m" are worth.
			padding = scope:own(core:memo(function(use)
				return if use(conditions.isShort) then "s" else "m"
			end)),
			gap = scope:own(core:memo(function(use)
				return if use(conditions.isShort) then "xs" else "s"
			end)),
			children = {
				UI.When({
					id = "HeadingWhen",
					condition = showHeading,
					thenView = function()
						return UI.Text({ id = "Title", text = "Row actions — Mail", textSize = "title" })
					end,
				}),
				-- A GRID, NOT AN HSTACK (same device round, 320x640: "content
				-- overflows this hstack by 24px on the main axis" — "VirtualList" is a
				-- long word and three buttons of it do not fit a 288px content box).
				-- `minColumnWidth = "intrinsic"` derives the column count from the
				-- widest button's own measured width under the ACTIVE theme, every
				-- solve, so the bar re-columns on a narrow phone and on a theme swap
				-- without a single viewport number in this file. The three buttons stay
				-- direct children, so `/MailActions/ModeBar/Mode*` is unchanged.
				UI.Grid({
					id = "ModeBar",
					minColumnWidth = "intrinsic",
					gap = "s",
					width = { type = "fill", weight = 1 },
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

		local result: any
		result = {
			screen = screen,
			present = {
				-- THE HOSTED LIST'S WINDOW, FED FROM ITS OWN SOLVED PANE. `onGeometry`
				-- is a broadcast (presenter.luau: "solved rects are a notification"),
				-- so composing it here costs the screen's own controls nothing. The
				-- pane exists only in "vlist" mode; in the other two `rectOf` answers
				-- nil and the last good window simply stands.
				onGeometry = function(rectOf: (string) -> any)
					local pane = rectOf(VLIST_PANE)
					if pane == nil or type(pane.h) ~= "number" then
						return
					end
					local hint = rectOf(VLIST_PANE .. "/VListHint")
					local spent = if hint ~= nil and type(hint.h) == "number" then hint.h + VLIST_GAP else 0
					-- one row is the floor: a one-row list on a 320px-tall landscape
					-- phone is small, and it is ON SCREEN, which is the whole point
					local window = math.max(ROW_HEIGHT, math.floor(pane.h - spent))
					if window ~= vlistWindow:get() then
						vlistWindow:set(window)
					end
				end,
			},

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
					tableOpenedKey = openedKey:get(),
					listRowDumps = dumps,
					vlistHosted = vlist._hostedDebug(),
				}
			end,

			dispose = function()
				if unbindVlistTick ~= nil then
					unbindVlistTick()
				end
				if unbindVlistScroll ~= nil then
					unbindVlistScroll()
				end
				if tbl.dispose ~= nil then
					tbl.dispose()
				end
				vlist.dispose()
				-- the heightClass memos die with the fixture (RR-8), exactly like
				-- adaptive_controls' own `adaptive.conditions` scope
				scope:dispose()
			end,
		}

		unbindVlistTick = ctx.presenter.onTick(function()
			if unbindVlistScroll ~= nil or result.handle == nil then
				return
			end
			-- "vlist" is one of three surfaces a shared `UI.When` alternates
			-- (default mode is "list"), so this list's own mounted path is nil
			-- until the player actually switches to it — `bindNativeScroll`
			-- asserts on a nil path, so wait for a real mount and retry every
			-- tick until then. The path is stable once mounted (fixed `id`s),
			-- so binding once is enough even across a later switch away and back.
			if vlist.scrollPath() == nil then
				return
			end
			unbindVlistScroll = vlist.bindNativeScroll(result.handle.controller)
		end)

		return result
	end,
}
