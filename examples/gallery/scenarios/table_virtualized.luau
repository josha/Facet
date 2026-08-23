--!strict
--[[ Scenario 'table_virtualized' — THE UNIFIED COLLECTION: one container that
	windows, selects and reorders at the same time.

	The comparison document §13 carried "No container unifying
	virtualization + reorder + selection" as a durable gap. `newTable` had the
	reordering, the multi-selection, the columns and the header and mounted EVERY
	row; `newVirtualList` had the windowing. `newTable{ virtualized = true }`
	(2026-08-14) is the closure, and it rides the running-offset index variable
	item extents shipped (`src/virtual_extents.luau`).

	WHAT A STILL SCREENSHOT CANNOT SHOW, and therefore what this fixture is FOR:

	  · THE COUNT IS THE WHOLE ARGUMENT. Two thousand rows; the status line says
	    how many are actually in the instance tree, and it does not move when you
	    fling. A screenshot of a virtualized table and a screenshot of a table that
	    mounted all two thousand rows are the SAME PICTURE — the difference only
	    exists as a number, so the number is on screen.

	  · EVERY VERB REACHES A ROW THAT IS NOT THERE. The three buttons act on row
	    1500, which no window has ever held: reveal it, select a range that spans
	    it, move it. Each is the control's real public funnel — `revealRow`,
	    `select(…, { mode = "range" })`, `moveRow` — never a shortcut into the
	    model. That is what "unified" means and it is invisible in a picture:
	    selection, order and focus are MODEL state, and only the mounting is
	    windowed.

	  · SELECTION SURVIVES THE WINDOW. Select the range, scroll past it until every
	    selected row has been unmounted, scroll back: the rows come back selected.
	    A list that kept selection in its mounted rows would look identical until
	    the moment it lost it.

	NOTHING HERE IS FIXED AGAINST AN UNFIXED VIEWPORT. The table is the one thing
	on this page that takes `fill`, so the chrome above it is sized by the SOLVER
	and the list gets whatever is left — the discipline `variable_extents` had to
	learn the hard way (a literal 210px chrome reserve that the sweep measured
	overflowing by 77px at the largest text preference). No `rowHeight` is declared
	either: the framework derives it from the theme's per-paradigm row description
	and the live text scale, which is exactly why a virtualized Table needs no
	consumer-side extent prediction at all.

	A VIRTUALIZED TABLE OWNS ITS VIEWPORT, and that is not a style choice — a
	windowed list is defined against a viewport, so `scrolls = false` is refused at
	construction. This page therefore has one scroller (the table's own body) and
	keeps its chrome to a title, one wrapping button row and a two-line status.

	TWO HOSTS MOUNT THIS FILE, AND ONLY ONE OF THEM RUNS STEPS (the pair
	`card_rail.luau` documents): the scenario runner drives `steps` by name, and
	the showcase demo picker mounts it with a minimal ctx and NO step ever runs.
	Everything a player can do here is an ordinary control with its own
	`onActivate`.
]]

local ROW_COUNT = 2000
-- the row every verb below acts on, chosen so that no first window can contain
-- it: the whole point is that a row nobody has mounted is still addressable
local FAR_ROW = 1500
local RANGE_FROM, RANGE_TO = 900, 1100

--[[ EVERY PLAYER-VISIBLE STRING, in one flat table and EXPORTED as `copy` — the
	contract `row_capabilities.luau` and `flow_wrap.luau` carry, for the same
	reason: the localization case re-runs the whole fixture with all of them put
	through a ~1.4x pseudo-localizing expansion, and a check that cannot reach the
	strings cannot make that claim. Flat keys only (the pseudo-localizer walks
	values and would throw on a nested table). ]]
local COPY = {
	title = "2 000 rows, 17 real",

	colName = "Entrant",
	colTeam = "Team",
	colBest = "Best lap",

	-- SHORT ON PURPOSE: these four labels share ONE wrapping row, and a second
	-- row of buttons is 48px this page does not have on a 640x320 landscape phone
	-- inside the showcase's reserved band (measured: the row was 96px tall with
	-- five long labels, and the page came out 20px over its own box at the DEFAULT
	-- text preference). Which row each verb acts on is in the status line below.
	btnReveal = "Reveal",
	btnRange = "Range",
	btnMove = "Move up",
	btnEdit = "Edit",

	rowsPrefix = "Rows",
	mountedPrefix = "in the tree",
	selectedPrefix = "selected",
	movesPrefix = "moves",
	canvasPrefix = "canvas",

	lastIdle = "Each button acts on a row no window has held.",
	lastReveal = "revealRow #1500 — no solved rect",
	lastRange = "select range — 201 rows, most unmounted",
	lastMove = "moveRow #1500 up — model-level",
}

local TEAMS = { "Rustbucket", "Chrome Coyote", "Nine Volt", "Paper Lantern", "Bad Weather" }

local function seedRows(): { any }
	local out = {}
	for i = 1, ROW_COUNT do
		table.insert(out, {
			id = `e{i}`,
			n = i,
			team = TEAMS[(i - 1) % #TEAMS + 1],
			-- deterministic, so the fixture is the same list on every run and on
			-- every device
			best = string.format("1:%02d.%03d", 12 + (i * 7) % 40, (i * 137) % 1000),
		})
	end
	return out
end

return {
	title = "Virtualized Table (unified collection)",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local scope = core:scope("table-virtualized")
		-- THE SAME TABLE the module exports, never a snapshot: the localization
		-- case mutates `module.copy` IN PLACE and runs the fixture again.
		local copy: any = COPY

		local rows = scope:own(core:signal(seedRows()))
		local moves = scope:own(core:signal(0))
		local last = scope:own(core:signal(copy.lastIdle))
		-- a tick the status line watches so it re-derives after a verb that changes
		-- only the table's internal window (a reveal scrolls; nothing else moves)
		local pulse = scope:own(core:signal(0))
		--[[ THE FIXTURE OWNS EDIT MODE, and that is a LAYOUT decision as much as a
			behavioural one. Table auto-shows an Edit/Done toolbar ROW whenever edit
			mode is the only route to a capability it declares and the owner supplied
			no `editing` signal — and a toolbar row is height this page does not have
			on a 359px phone at the largest text preference (measured: the page came
			out 23px over its own box with the toolbar in it). Supplying the signal
			takes the row back and puts the same verb in the wrapping button row
			below, where it costs nothing extra. ]]
		local editing = scope:own(core:signal(false))

		local function keyOf(index: number): string
			return `e{index}`
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
			moves:set(moves:get() + 1)
		end

		local tbl = Facet.Controls.Table(core, {
			id = "Entrants",
			rows = rows,
			key = function(item: any)
				return item.id
			end,
			--[[ HEADERLESS, AND IT IS A MEASUREMENT RATHER THAN A TASTE. A header band
				is a `minMax` FLOOR (`controls.table.headerHeight`), so a Table that
				declares one cannot shrink below it — and on a 705x338 landscape phone
				this page's chrome leaves the list 21px, at which point the table's own
				`Main` overflows by 9px before a single row is drawn. Measured across the
				sweep: 77 findings, every one of them that band. The list itself has no
				such floor (its body is `fill` and windows down to nothing), which is the
				property that lets this page fit every swept viewport at every text
				preference. Columns still align — the header is what is gone, not the
				column model — and `02_playlist_table` is the shipped surface that
				carries a header, in a BLOCK table inside a scrolling page. ]]
			header = false,
			--[[ THE ONE PROP THIS FIXTURE EXISTS FOR. Construction-only: the body
				becomes a full-extent Canvas with absolutely-positioned windowed rows
				instead of a flowing stack, and switching that under a live gesture
				would rebuild the native scroll state mid-drag. ]]
			virtualized = true,
			-- ...which means this table OWNS its viewport. `scrolls = false` is a
			-- construction error beside `virtualized`, because a block table has no
			-- viewport to window against.
			selection = "multi",
			editing = editing,
			reorderable = true,
			onReorder = reorder,
			-- NO rowHeight, deliberately — the framework derives it per paradigm and
			-- per text preference. That is the property that lets a virtualized Table
			-- window exactly without asking the consumer to predict anything, which
			-- is the trap `docs/plans/variable-item-extents.md` records.
			--[[ `value`, NOT `cell`: a `value` column is a Text the TABLE authors, so
				the table caps its lines against the row height it derived. A `cell`
				blueprint belongs to the consumer and the table "caps what it makes, not
				what it is given" — measured at 1577 solver findings on the first cut of
				`row_capabilities`, every one a name wrapping past its own row box. ]]
			columns = {
				{
					id = "name",
					title = copy.colName,
					width = UI.fill(3),
					minWidth = 90,
					disclose = true,
					value = function(item: any)
						return `#{item.n}`
					end,
				},
				{
					id = "team",
					title = copy.colTeam,
					width = UI.fill(4),
					minWidth = 80,
					disclose = true,
					value = function(item: any)
						return item.team
					end,
				},
				{
					id = "best",
					title = copy.colBest,
					width = UI.fill(3),
					minWidth = 70,
					value = function(item: any)
						return item.best
					end,
				},
			},
			env = ctx.env,
		})

		local function bump(text: string)
			last:set(text)
			pulse:set(pulse:get() + 1)
		end

		local function selectedCount(): number
			local n = 0
			for _, on in tbl.api.selectedKeys:get() do
				if on then
					n += 1
				end
			end
			return n
		end

		local status = scope:own(core:memo(function(use)
			use(pulse)
			local all = use(rows) :: { any }
			local selected = use(tbl.api.selectedKeys)
			local n = 0
			for _, on in selected do
				if on then
					n += 1
				end
			end
			local d = tbl.dump()
			return `{copy.rowsPrefix} {#all} · {d.windowRows} {copy.mountedPrefix} · {n} {copy.selectedPrefix} · `
				.. `{use(moves)} {copy.movesPrefix}`
		end))

		local function actionButton(id: string, label: string, run: () -> ()): any
			return UI.Button({
				id = id,
				label = label,
				onActivate = run,
			})
		end

		-- hug where there is room, a bounded scroller where there is not (see the
		-- `Chrome` block below); `heightClass` is ADR-0023's own Readable for it
		local conditions = ctx.Facet.adaptive.conditions(core, ctx.env, { scope = scope })
		local chromeHeight = scope:own(core:memo(function(use)
			return if use(conditions.isShort) then UI.fill() else nil
		end))

		local screen = UI.Screen({
			id = "TableVirtualized",
			padding = 12,
			gap = "s",
			children = {
				--[[ THE CHROME IS A SIBLING SCROLLER ON A SHORT CANVAS (O-21, measured
					2026-08-15). The waiver this replaces was right that the page cannot
					delegate its scrolling — `newTable` refuses `virtualized` beside
					`scrolls = false`, so the table's own body is the one scroller this
					surface owns and its chrome has to fit above it. A SIBLING scroller
					is a different claim: `Chrome` and `ListPane` are two boxes in one
					stack, each owning its own window and its own gesture, which is the
					arrangement `scroll_host` exists to prove is legal.
					What was left over after the four earlier repairs was the irreducible
					case the waiver named — at the Largest preference a 320px phone's
					wrapped buttons and two status lines need more than the band the
					showcase leaves. Under the 1.4x `xa` locale it cost the `Last` line
					10px below the fold, cut and unreachable. The chrome hugs wherever
					there is room, so every viewport that already fitted is unmoved. ]]
				UI.ScrollView({
					id = "Chrome",
					axis = "y",
					gap = "s",
					width = UI.fill(),
					height = chromeHeight,
					children = {
						--[[ A WRAPPING BUTTON ROW. Four labels that a ~1.4x localization
					expansion widens together is exactly the shape a fixed row cannot
					hold on a 320px phone, and `UI.HStack{ wrap = true }` is the one
					construct that packs "as many as fit per line" with ragged widths. ]]
						UI.HStack({
							id = "Actions",
							wrap = true,
							gap = "xs",
							width = UI.fill(),
							children = {
								actionButton("Reveal", copy.btnReveal, function()
									tbl.api.revealRow(keyOf(FAR_ROW))
									bump(copy.lastReveal)
								end),
								actionButton("Range", copy.btnRange, function()
									tbl.api.select(keyOf(RANGE_FROM), { mode = "replace" })
									tbl.api.select(keyOf(RANGE_TO), { mode = "range" })
									bump(copy.lastRange)
								end),
								actionButton("MoveFar", copy.btnMove, function()
									tbl.api.moveRow(keyOf(FAR_ROW), -1)
									bump(copy.lastMove)
								end),
								actionButton("Edit", copy.btnEdit, function()
									editing:set(not editing:get())
								end),
							},
						}),
						UI.Text({ id = "Status", text = status, textSize = "caption", disclose = true }),
						UI.Text({
							id = "Last",
							text = last,
							textSize = "caption",
							role = "secondary",
							disclose = true,
							lineLimit = 1,
						}),
					},
				}),
				--[[ THE LIST TAKES `fill`, AND IT IS THE ONLY THING ON THIS PAGE THAT
					DOES. Everything above sizes to its own content, so the window is
					whatever the solver leaves — never a literal reserve subtracted from
					the viewport. The table measures that box itself through
					`syncGeometry`, so nothing here has to know it. ]]
				UI.ZStack({
					id = "ListPane",
					width = UI.fill(),
					-- weight 2 against the chrome's 1 wherever the chrome is a fill: on
					-- a short canvas the table still gets the larger share, and where the
					-- chrome hugs this is the only fill and takes everything left
					height = UI.fill(2),
					children = { tbl.blueprint },
				}),
			},
		})

		return {
			screen = screen,
			present = {},
			-- published for the headless suite: the control and the signals a test
			-- drives, rather than a re-implementation of them
			table_ = tbl,
			rows = rows,
			last = last,

			--[[ THE SCENARIO RUNNER'S STEPS. Each drives the control's own public
				funnel, never the model behind it — a step that reached past the API
				would prove the fixture works and say nothing about the container. ]]
			steps = {
				reveal = function()
					tbl.api.revealRow(keyOf(FAR_ROW))
					bump(copy.lastReveal)
				end,
				range = function()
					tbl.api.select(keyOf(RANGE_FROM), { mode = "replace" })
					tbl.api.select(keyOf(RANGE_TO), { mode = "range" })
					bump(copy.lastRange)
				end,
				move = function()
					tbl.api.moveRow(keyOf(FAR_ROW), -1)
					bump(copy.lastMove)
				end,
			},

			report = function()
				local d = tbl.dump()
				return {
					rows = #(rows:get() :: { any }),
					windowRows = d.windowRows,
					contentExtent = d.contentExtent,
					scrollTop = d.scrollTop,
					selected = selectedCount(),
					moves = moves:get(),
				}
			end,

			dispose = function()
				tbl.dispose()
				scope:dispose()
			end,
		}
	end,
}
