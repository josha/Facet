--!strict
--[[ Scenario 'row_capabilities' — THE ROWS THAT SAY NO.

	`rowSelectable`, `rowMovable` and `rowDeletable` shipped in SwiftUI-parity
	round 3 item C (director ruling 2026-08-13: build all three). They are the
	per-row half of three capabilities the CONTAINER declares — this table is
	selectable, reorderable and carries a destructive row action, and three of its
	five rows opt out of exactly one of those each. The standing obligation is
	that every gap closure appears in a gallery scenario the headless suite
	executes and a player can open; this is that scenario.

	WHY THIS SURFACE EXISTS AT ALL, and what a still screenshot cannot show:

	  · A REFUSAL IS AN ABSENCE, AND AN ABSENCE LOOKS LIKE A BUG. Tap the locked
	    row and nothing happens. Press Move up on the pinned row and nothing
	    happens. That is indistinguishable from a broken table unless the surface
	    says who refused and why — so this one does, on a live line, in the
	    framework's own words. The five rows are otherwise identical: same table,
	    same columns, same actions, same gestures. The ONLY difference is the
	    predicate, which is what makes the comparison an argument rather than a
	    claim.

	  · THE LINE IS WRITTEN BY THE PREDICATES THEMSELVES. `narrate` is called from
	    inside `rowSelectable` / `rowMovable` / `rowDeletable` — so what the player
	    reads is not this fixture's guess about what the framework did, it is the
	    framework's own question arriving at the consumer's own callback, at the
	    moment it is asked. Watching it appear the instant a gesture is refused is
	    the clearest available statement of the family's central design rule: the
	    predicates gate the FUNNEL (`api.select`, the move funnel, the destructive
	    commit), not the affordance.

	  · ...WHICH IS ALSO WHY THE AFFORDANCES ARE STILL THERE. A protected row still
	    paints its tray Delete and, in Edit, its ⊖; a pinned row still paints its
	    reorder handle. They do nothing. That is the shipped behaviour and it is
	    deliberate (`row_actions.luau`'s `ponytail:` note at the delete gate: hiding
	    the affordance needs the verdict as a reactive fact, and the already-shipped
	    spelling for removing it is to return no destructive action for that row).
	    A demo that hid them would be advertising a capability the framework does
	    not have yet.

	A PREDICATE WITH A SIDE EFFECT, ON PURPOSE — and it is safe here for a reason
	worth stating rather than assuming. All three predicates are evaluated at
	ATTEMPT time and never at mount: `rowSelectable` inside `api.select`
	(`table.luau`), `rowMovable` inside the one move funnel its five reorder entry
	points resolve through, and `rowDeletable` inside `doCommitAction`
	(`row_actions.luau`), which is where the swipe commit, the tray button, the ⊖,
	the Delete key and the action menu all meet. So there is no mount-time noise to
	filter and every line on screen corresponds to something a player just did. The
	framework quarantines a throwing predicate and fails closed, so the worst this
	side effect can cost is a stale line.

	NARRATES REFUSALS ONLY. A success is already visible — the selection readout
	moves, the order line re-writes itself, the row leaves — so narrating it too
	would bury the one thing this surface is for. It also keeps the line
	deterministic: the move funnel asks about the rows a move would DISPLACE as
	well as the row being moved (a pinned row holds its index), and narrating every
	`yes` would end on whichever neighbour happened to be scanned last.

	NOTHING HERE IS FIXED AGAINST AN UNFIXED VIEWPORT. The table is a BLOCK
	(`scrolls = false`, 02_playlist_table's shipped idiom and the director's own
	2026-07-27 ruling) so the PAGE scrolls, header included, rather than leaving a
	short landscape phone a 144px row window as the only thing that can move. No
	row height is declared: the framework derives it from the theme's per-paradigm
	row description and the live text scale.

	THE ONE INTERACTION THIS FIXTURE CANNOT DRIVE ITSELF is a native swipe on a
	table row — the same standing input-tools limitation `row_actions.luau` records
	for its own table surface. `steps` therefore covers selection and the two move
	verbs (the real public funnels, never a shortcut into the model), and the
	delete route is driven through a real adapter gesture by
	`tests/row_capabilities_scenario.spec.luau`.

	TWO HOSTS MOUNT THIS FILE and only one runs steps, the pair `card_rail.luau`
	and `flow_wrap.luau` document: the scenario runner drives `steps` by name, and
	the showcase demo picker mounts it with a minimal ctx and no step ever runs.
]]

--[[ EVERY PLAYER-VISIBLE STRING, in one flat table and EXPORTED as `copy` — the
	same contract `flow_wrap.luau` and `lifecycle_hidden.luau` carry, and for the
	same reason: the localization case re-runs the whole fixture with all of them
	put through a ~1.4x pseudo-localizing expansion, and a check that cannot reach
	the strings cannot make that claim. Flat keys only (the pseudo-localizer walks
	values and would throw on a nested table), which is why the row names and the
	lock words are individual entries rather than a table of rows. ]]
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

-- the run sheet, in its starting order. `lock` names which single capability the
-- row opts out of; `nil` is a row that participates in all three, and there are
-- two of them on purpose — a fixture where every row refuses something proves
-- nothing about the ones that do not.
local SEED = {
	{ id = "grid", nameKey = "rowGrid", lock = "move" },
	{ id = "warmup", nameKey = "rowWarmup", lock = nil },
	{ id = "main", nameKey = "rowMain", lock = "delete" },
	{ id = "notes", nameKey = "rowNotes", lock = "select" },
	{ id = "cool", nameKey = "rowCool", lock = nil },
}

return {
	title = "Per-row capability opt-outs (round 3 item C)",
	ledgerRows = {},
	copy = COPY,
	seed = SEED,
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local scope = core:scope("row-capabilities")
		-- THE SAME TABLE the module exports, never a snapshot of it: the
		-- localization case mutates `module.copy` IN PLACE and runs the fixture
		-- again, so a build that copied the strings out would be pseudo-localizing
		-- a table nothing on screen reads (`examples_gallery.spec.luau`'s
		-- `underPseudoLocalization`).
		local copy: any = COPY

		local function nameOf(item: any): string
			return copy[item.nameKey]
		end

		local rows = scope:own(core:signal(table.clone(SEED)))
		local refusal = scope:own(core:signal(copy.refusalIdle))
		local refusals = scope:own(core:signal(0))

		-- THE NARRATOR. See the header: this is called from inside the three
		-- predicates, never from a handler, so the line is the framework's own
		-- question rather than this fixture's account of it.
		local function narrate(item: any, question: string)
			refusals:set(refusals:get() + 1)
			refusal:set(`{nameOf(item)} — {question} {copy.answerNo}`)
		end

		local function indexOf(key: string): number?
			for i, item in rows:get() :: { any } do
				if item.id == key then
					return i
				end
			end
			return nil
		end

		-- `toIndex` is the 0-based insertion slot among the rows NOT being moved
		-- (Table's own onReorder contract). The table never mutates caller rows.
		local function reorder(keys: { string }, toIndex: number)
			local moving: { [string]: boolean } = {}
			for _, key in keys do
				moving[key] = true
			end
			local carried, staying = {}, {}
			for _, item in rows:get() :: { any } do
				table.insert(if moving[item.id] then carried else staying, item)
			end
			local out = {}
			for i = 1, toIndex do
				table.insert(out, staying[i])
			end
			for _, item in carried do
				table.insert(out, item)
			end
			for i = toIndex + 1, #staying do
				table.insert(out, staying[i])
			end
			rows:set(out)
		end

		local function removeRow(key: string)
			local out = {}
			for _, item in rows:get() :: { any } do
				if item.id ~= key then
					table.insert(out, item)
				end
			end
			rows:set(out)
		end

		local tbl = Facet.newTable(Facet, core, {
			id = "RunSheet",
			rows = rows,
			key = function(item: any)
				return item.id
			end,
			header = true,
			-- a BLOCK: the page below owns the scrolling (see the header)
			scrolls = false,
			-- NO rowHeight, deliberately — the framework derives it per paradigm
			-- and per text preference, which is what keeps a 1.4x expanded name
			-- from painting through its neighbours
			--[[ `value`, NOT `cell`, and the difference is load-bearing. A `value`
				column is a Text the TABLE authors, so the table caps its lines
				against the row height it derived; a `cell` blueprint belongs to the
				consumer and the table "caps what it makes, not what it is given"
				(`cellContentFor`). Measured on the first cut of this fixture, which
				used `cell`: 1577 solver findings across the theme × viewport × text-
				preference sweep — every one of them a row name wrapping past its own
				row box under Parchment and Pixel Quest, at every text preference.
				`disclose` gives the capped string its full-value path. ]]
			columns = {
				{
					id = "name",
					title = copy.colName,
					width = { type = "fill", weight = 3 },
					minWidth = 90,
					disclose = true,
					value = nameOf,
				},
				{
					id = "lock",
					title = copy.colLock,
					width = { type = "fill", weight = 2 },
					minWidth = 60,
					disclose = true,
					value = function(item: any): string
						if item.lock == "move" then
							return copy.lockPinned
						elseif item.lock == "delete" then
							return copy.lockProtected
						elseif item.lock == "select" then
							return copy.lockLocked
						end
						return copy.lockNone
					end,
				},
			},
			selection = "single",
			reorderable = true,
			onReorder = reorder,
			--[[ THE THREE PREDICATES. Positive polarity — `true` (or a forgotten
				branch returning nil) means "this row may take part"; only an
				explicit `false` refuses. SwiftUI spells the same family negatively
				(`selectionDisabled`/`moveDisabled`/`deleteDisabled`), and the parity
				doc carries the inverse mapping. ]]
			rowSelectable = function(item: any): boolean
				if item.lock ~= "select" then
					return true
				end
				narrate(item, copy.askSelect)
				return false
			end,
			rowMovable = function(item: any): boolean
				if item.lock ~= "move" then
					return true
				end
				narrate(item, copy.askMove)
				return false
			end,
			rowDeletable = function(item: any): boolean
				if item.lock ~= "delete" then
					return true
				end
				narrate(item, copy.askDelete)
				return false
			end,
			rowActions = function(item: any): any
				return {
					trailing = {
						{
							id = "flag",
							role = "normal",
							label = "Flag",
							icon = "flag",
							onAction = function() end,
						},
						{
							id = "delete",
							role = "destructive",
							label = "Delete",
							icon = "trash",
							onAction = function()
								removeRow(item.id)
							end,
						},
					},
					-- NO full swipe. A full swipe is an irrevocable commit, and on a
					-- surface whose whole subject is "some of these refuse" a gesture
					-- that deletes without a confirming tap makes the refused case and
					-- the accepted case feel like different bugs rather than one rule.
					fullSwipe = false,
				}
			end,
			env = ctx.env,
		})

		-- the readouts. Each is a memo over the control's OWN published state, not
		-- a second copy of it: `api.selectedKeys` is the table's live selection set
		-- (a SET, so the readout picks the one key a single-selection table holds).
		local selectedName = scope:own(core:memo(function(use)
			local keys = use(tbl.api.selectedKeys)
			for _, item in use(rows) :: { any } do
				if keys[item.id] == true then
					return `{copy.selectedPrefix}: {nameOf(item)}`
				end
			end
			return `{copy.selectedPrefix}: {copy.selectedNone}`
		end))

		local orderLine = scope:own(core:memo(function(use)
			local names = {}
			for _, item in use(rows) :: { any } do
				table.insert(names, nameOf(item))
			end
			return `{copy.orderPrefix}: {table.concat(names, " · ")}`
		end))

		local refusalCount = scope:own(core:memo(function(use)
			return `{copy.refusedCount}: {use(refusals)}`
		end))

		-- the selected key, for the two move buttons. nil disables neither button:
		-- a move with nothing selected is a no-op the funnel already answers, and a
		-- disabled control that re-enables on selection is a second thing to explain.
		local function selectedKey(): string?
			for key, on in tbl.api.selectedKeys:get() do
				if on then
					return key
				end
			end
			return nil
		end

		local function move(delta: number): boolean
			local key = selectedKey()
			if key == nil then
				return false
			end
			return tbl.api.moveRow(key, delta) == true
		end

		local screen = UI.Screen({
			id = "RowCapabilities",
			padding = 12,
			gap = 8,
			children = {
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = 8,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.Text({ id = "Title", text = copy.title, textSize = "heading" }),
						UI.Text({ id = "Intro", text = copy.intro, textSize = "caption", role = "secondary" }),
						-- WRAPPING, so two buttons whose labels expanded ~1.4x take a
						-- second line instead of walking off a 320px phone. `wrap` is
						-- itself round-3 vocabulary (item A) and this is what it is for.
						UI.HStack({
							id = "Toolbar",
							gap = "s",
							wrap = true,
							width = { type = "fill", weight = 1 },
							children = {
								UI.Button({
									id = "MoveUp",
									label = copy.moveUp,
									onActivate = function()
										move(-1)
									end,
								}),
								UI.Button({
									id = "MoveDown",
									label = copy.moveDown,
									onActivate = function()
										move(1)
									end,
								}),
							},
						}),
						UI.Text({ id = "Selected", text = selectedName, textSize = "label" }),
						tbl.blueprint,
						UI.Text({ id = "Order", text = orderLine, textSize = "caption", role = "secondary" }),
						-- THE LINE THIS WHOLE FIXTURE IS FOR. `role = "danger"` is not
						-- used: a refusal is information, not an error, and painting it
						-- as one would say the table is broken — which is the exact
						-- reading this surface exists to prevent.
						UI.Text({ id = "Refusal", text = refusal, textSize = "label" }),
						UI.Text({ id = "RefusalCount", text = refusalCount, textSize = "caption", role = "secondary" }),
						UI.VStack({
							id = "Legend",
							surface = "control",
							padding = 8,
							gap = 6,
							width = { type = "fill", weight = 1 },
							children = {
								UI.Text({
									id = "LegendPinned",
									text = copy.legendPinned,
									textSize = "caption",
									role = "secondary",
								}),
								UI.Text({
									id = "LegendProtected",
									text = copy.legendProtected,
									textSize = "caption",
									role = "secondary",
								}),
								UI.Text({
									id = "LegendLocked",
									text = copy.legendLocked,
									textSize = "caption",
									role = "secondary",
								}),
							},
						}),
						UI.Text({ id = "Footer", text = copy.footer, textSize = "caption", role = "secondary" }),
					},
				}),
			},
		})

		local function ids(): { string }
			local out = {}
			for _, item in rows:get() :: { any } do
				table.insert(out, item.id)
			end
			return out
		end

		return {
			screen = screen,
			present = {},
			-- published for the headless suite: the control and the signals a test
			-- drives and reads, rather than a re-implementation of them
			table_ = tbl,
			rows = rows,
			refusal = refusal,
			refusals = refusals,
			ids = ids,

			steps = {
				-- the public funnels, exactly as a tap/key/pad press reaches them
				select = function(_built: any, payload: string?)
					tbl.api.select(tostring(payload))
					return { selected = tbl.dump().selectedKeys, refusal = refusal:get() }
				end,
				moveUp = function(_built: any, payload: string?)
					local key = if payload ~= nil and payload ~= "" then payload else selectedKey()
					local ok = key ~= nil and tbl.api.moveRow(key :: string, -1) == true
					return { ok = ok, order = ids(), refusal = refusal:get() }
				end,
				moveDown = function(_built: any, payload: string?)
					local key = if payload ~= nil and payload ~= "" then payload else selectedKey()
					local ok = key ~= nil and tbl.api.moveRow(key :: string, 1) == true
					return { ok = ok, order = ids(), refusal = refusal:get() }
				end,
				edit = function(_built: any, payload: string?)
					tbl.api.editing:set(payload ~= "off")
					return { editing = tbl.api.editing:get() }
				end,
			},

			report = function()
				return {
					order = ids(),
					selected = tbl.dump().selectedKeys,
					refusal = refusal:get(),
					refusals = refusals:get(),
					editing = tbl.api.editing:get(),
				}
			end,

			dispose = function()
				tbl.dispose()
				scope:dispose()
			end,
		}
	end,
}
