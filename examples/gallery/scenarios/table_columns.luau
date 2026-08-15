--!strict
--[[ Scenario 'table_columns' — THE HEADER, AND THE DIVIDER YOU CAN PULL.

	Column resize has shipped in `src/controls/table.luau` since Phase B — the
	model (`api.setColumnWidth`), the pointer drag on the header divider that
	commits through it on release, and the keyboard/gamepad step
	(`stepColumnWidth`) — and until this fixture existed it had never been driven
	on a real adapter by a real finger, a real key or a real stick. It was proved
	only by `tests/table.spec.luau`, headlessly, against a fake target that
	dispatches a pointer event to the path it is handed. That is exactly the shape
	`docs/lessons/a-button-eats-the-swipe-underneath-it.md` warns about: the fake
	target models handler WIRING, and the engine's rule is that `InputBegan`
	reaches the TOPMOST interactive object only. A 8px divider painted over a
	full-cell header Button is that shape precisely.

	So this fixture is the surface that answers the question, and the director
	asked for it in those words: "something in the showcase shows a table with the
	headers and resizable columns. We haven't tested that."

	WHY IT IS ITS OWN FIXTURE rather than a prop added to one that exists:

	  · `table_virtualized` is DELIBERATELY HEADERLESS, and the reason is measured
	    rather than stylistic — a header band is a `minMax` FLOOR
	    (`controls.table.headerHeight`), and on a 705x338 landscape phone that page's
	    chrome left the list 21px, at which point the band alone overflowed. 77 sweep
	    findings, every one of them that floor. A fixture whose subject IS the header
	    cannot live there.
	  · `02_playlist_table` carries a header and is the shipped tutorial for
	    sorting, filtering and reordering. Its two columns are a `fill` Name and a
	    Rating pinned to a measured 144px, with a long comment explaining why that
	    number is not free to move; making either resizable fights that lesson, and
	    a tutorial has no room for the width readout that makes a resize legible.

	WHAT A STILL SCREENSHOT CANNOT SHOW, and therefore what this fixture is FOR:

	  · A RESIZE IS A CHANGE, NOT A PICTURE. A screenshot of a table whose first
	    column is 218px and one whose first column was ALWAYS 218px are the same
	    image. So the committed width of every column is on screen, live, and it is
	    read from the control's own published state — `api.columnWidthOverrides`,
	    the Readable the model commits into — never from a copy this fixture keeps.
	  · THE THREE ROUTES ARE THE SAME MODEL. A pointer drag on the divider, a
	    keyboard ←/→ after Return on a heading, and a gamepad bumper on a focused
	    heading all commit through `setColumnWidth`. One readout means a route that
	    silently does nothing is visible as a number that does not move, which is
	    what a live drive has to be able to see.
	  · SELECTING A COLUMN PAINTS NOTHING. `api.selectedColumn` is public "so a
	    consumer can paint the selection" and the control draws no state for it —
	    so after a device Activate on a heading the stick silently means something
	    new and the screen does not say so. This fixture puts that state in the hint
	    line, which is both the demo and the honest report of the gap.
	  · A COLUMN THAT REFUSES. `best` is not `resizable`, so it grows no divider and
	    no Adjust key binds while its heading holds focus. A refusal is an ABSENCE
	    until something names it, so the readout says `locked` for it rather than a
	    number that never changes.

	NOTHING HERE IS FIXED AGAINST AN UNFIXED VIEWPORT. The table takes `fill` and
	is the only thing on the page that does; the two caption lines above it size to
	their own content, so a raised text preference or a 1.4x localization expansion
	moves the table down rather than pushing it out of its box. There is no button
	row — `table_virtualized` measured a four-label wrapping row at 96px and went
	20px over its own box on a 640x320 landscape phone, and every verb this fixture
	needs is already reachable through the table's own header.

	TWO HOSTS MOUNT THIS FILE, AND ONLY ONE OF THEM RUNS STEPS (the pair
	`card_rail.luau` documents): the scenario runner drives `steps` by name, and the
	showcase demo picker mounts it with a minimal ctx and NO step ever runs.
	Everything a player can do here is the table's own header — there is no control
	on this page that a scripted drive could substitute for.

	THE STEPS DRIVE THE DEVICE FUNNELS, NOT THE MODEL. `select` is the presenter's
	own `handleActivate` with `source = "action"` (what a Return or an A button
	delivers); `wider`/`narrower` are `handleGrabNavigate`, the stick. A step that
	called `setColumnWidth` directly would prove this fixture works and say nothing
	about whether a device can reach the feature.
]]

--[[ EVERY PLAYER-VISIBLE STRING, in one flat table and EXPORTED as `copy` — the
	contract `table_virtualized.luau`, `row_capabilities.luau` and `flow_wrap.luau`
	all carry, for the same reason: the localization case re-runs the whole fixture
	with all of them put through a ~1.4x pseudo-localizing expansion, and a check
	that cannot reach the strings cannot make that claim. Flat keys only (the
	pseudo-localizer walks values and would throw on a nested table). ]]
local COPY = {
	colName = "Entrant",
	colTeam = "Team",
	colBest = "Best lap",

	-- the width readout's two non-numeric states: a resizable column nobody has
	-- moved yet, and a column that refuses to move at all
	widthAuto = "auto",
	widthLocked = "locked",

	-- the hint line is the SELECTION READOUT and the instruction at once, because
	-- the control paints no state for a selected column and the two facts a player
	-- needs ("which column has the stick" and "what the stick does now") are the
	-- same sentence
	hintIdle = "Drag a divider, or Tab to a heading and press Return",
	--[[ THE KEYS THIS SENTENCE NAMES ARE THE ONES THAT ACTUALLY WORK, and the
		difference was measured live in Studio on 2026-08-14 rather than read off the
		control. `handleGrabNavigate` puts a selected column's resize on ←/→, and on
		the live showcase ←/→ NEVER ARRIVE: Roblox's own `RbxCameraKeypress` is bound
		to `KeyCode.Left`/`Right` at ContextActionService priority 2000 and sinks
		them. Proven by unbinding it in the same session — the identical two presses
		then stepped the column 437px → 469px.

		`,` / `.` are the Adjust keys the presenter binds dynamically while a
		resizable header holds focus, and they are not contended, so they are what a
		player can actually press. See
		docs/lessons/the-camera-still-owns-the-arrow-keys.md. ]]
	hintSelectedSuffix = "has the keys: , and . resize it, ↑/↓ sorts",
}

local TEAMS = { "Rustbucket", "Chrome Coyote", "Nine Volt", "Paper Lantern", "Bad Weather" }

-- enough rows that the body is a real scroller under the header (the header must
-- stay put while the rows move — a resize demo on three rows would never show
-- that the band is not just the first row)
local ROW_COUNT = 28

local function seedRows(): { any }
	local out = {}
	for i = 1, ROW_COUNT do
		table.insert(out, {
			id = `r{i}`,
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
	title = "Table columns (header + resize)",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local LuauUI = ctx.LuauUI
		local UI = LuauUI.UI
		local core = ctx.core
		local scope = core:scope("table-columns")
		-- THE SAME TABLE the module exports, never a snapshot: the localization
		-- case mutates `module.copy` IN PLACE and runs the fixture again.
		local copy: any = COPY

		local rows = scope:own(core:signal(seedRows()))
		--[[ THE OWNER HOLDS THE ORDER AND APPLIES IT (SwiftUI's binding shape): the
			table only cycles the signal from a header tap. It is here because sorting
			and resizing SHARE the header — a pointer tap sorts, a pointer drag on the
			divider resizes, and a device Activate selects the column and hands both
			verbs to the stick. Two gestures on one
			band is the competition this fixture exists to drive. ]]
		local sortOrder = scope:own(core:signal(nil :: any))
		scope:own(core:observe(sortOrder, function(order)
			if order == nil then
				return
			end
			local sorted = table.clone(rows:get() :: { any })
			table.sort(sorted, function(a, b)
				local av, bv = a.n, b.n
				if order.column == "team" then
					av, bv = a.team, b.team
				elseif order.column == "best" then
					av, bv = a.best, b.best
				end
				if order.ascending then
					return av < bv
				end
				return av > bv
			end)
			rows:set(sorted)
		end))

		local tbl = LuauUI.newTable(LuauUI, core, {
			id = "Entrants",
			rows = rows,
			key = function(item: any)
				return item.id
			end,
			-- THE POINT OF THE FIXTURE. Everything else on this page exists to make
			-- what this band does visible.
			header = true,
			sortOrder = sortOrder,
			selection = "single",
			columns = {
				{
					id = "name",
					title = copy.colName,
					width = { type = "fill", weight = 3 },
					minWidth = 90,
					resizable = true,
					disclose = true,
					value = function(item: any)
						return `#{item.n}`
					end,
				},
				{
					id = "team",
					title = copy.colTeam,
					width = { type = "fill", weight = 4 },
					minWidth = 80,
					resizable = true,
					disclose = true,
					value = function(item: any)
						return item.team
					end,
				},
				--[[ THE COLUMN THAT REFUSES, and it is not decoration: `resizable` is
					what gates the divider (`gripFor` is only inserted for a column that
					declares it) AND what gates the Adjust binding (`api.adjustTargets`
					walks resizable headers only, "binding Adjust on a header that cannot
					resize would shadow gameplay bumpers for nothing"). Both refusals are
					invisible, so the readout names this one `locked`. ]]
				{
					id = "best",
					title = copy.colBest,
					width = { type = "fill", weight = 3 },
					minWidth = 70,
					value = function(item: any)
						return item.best
					end,
				},
			},
			env = ctx.env,
		})

		--[[ READ FROM THE CONTROL, NOT FROM A COPY. `api.columnWidthOverrides` is
			the Readable the resize model commits into, so this line moves for a
			pointer drag, a keyboard step and a gamepad bumper alike — including the
			pointer drag, which fires no consumer callback at all and would otherwise
			be unobservable from outside the control. ]]
		local widths = scope:own(core:memo(function(use)
			local overrides = use(tbl.api.columnWidthOverrides) :: { [string]: number }
			local parts = {}
			for _, column in { { "name", copy.colName, true }, { "team", copy.colTeam, true }, { "best", copy.colBest, false } } do
				local id, label, resizable = column[1] :: string, column[2] :: string, column[3] :: boolean
				local px = overrides[id]
				local shown = if px ~= nil
					then `{math.floor(px + 0.5)}px`
					elseif resizable then copy.widthAuto
					else copy.widthLocked
				table.insert(parts, `{label} {shown}`)
			end
			return table.concat(parts, " · ")
		end))

		local hint = scope:own(core:memo(function(use)
			local selected = use(tbl.api.selectedColumn) :: string?
			if selected == nil then
				return copy.hintIdle
			end
			local label = if selected == "name"
				then copy.colName
				elseif selected == "team" then copy.colTeam
				else copy.colBest
			return `{label} {copy.hintSelectedSuffix}`
		end))

		local screen = UI.Screen({
			id = "TableColumns",
			padding = 12,
			gap = 8,
			children = {
				UI.Text({ id = "Widths", text = widths, textSize = "caption", disclose = true }),
				UI.Text({
					id = "Hint",
					text = hint,
					textSize = "caption",
					role = "secondary",
					disclose = true,
					lineLimit = 1,
				}),
				--[[ THE TABLE TAKES `fill`, AND IT IS THE ONLY THING ON THIS PAGE THAT
					DOES. The two captions size to their own content, so a raised text
					preference or a 1.4x expansion moves the table down instead of
					pushing anything out of its box. ]]
				UI.ZStack({
					id = "TablePane",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = { tbl.blueprint },
				}),
			},
		})

		-- the header handle path a device Activate/Adjust lands on. Derived from the
		-- control's OWN published root (`dump().rootPath`) rather than assembled from
		-- a literal, so a change to the table's internal path shape reddens the step
		-- instead of silently driving nothing.
		local function headerHandle(columnId: string): string?
			local root = tbl.dump().rootPath
			return if root ~= nil then `{root}/Main/Header/Head-{columnId}/Column` else nil
		end

		return {
			screen = screen,
			present = {},
			-- published for the headless suite: the control and the signals a test
			-- drives, rather than a re-implementation of them
			table_ = tbl,
			rows = rows,
			widths = widths,
			hint = hint,
			headerHandle = headerHandle,

			--[[ THE SCENARIO RUNNER'S STEPS, and each is a DEVICE funnel. `select` is
				what a keyboard Return or a gamepad A delivers (`meta.source == "action"`);
				`wider`/`narrower` are the stick a selected column owns. Nothing here
				calls `setColumnWidth`, because a step that reached past the input path
				would prove the fixture works and say nothing about whether a device can
				reach the feature at all. ]]
			steps = {
				select = function()
					local path = headerHandle("name")
					if path ~= nil then
						tbl.api.handleActivate(path, { source = "action" })
					end
				end,
				wider = function()
					tbl.api.handleGrabNavigate("right")
				end,
				narrower = function()
					tbl.api.handleGrabNavigate("left")
				end,
			},

			report = function()
				local d = tbl.dump()
				return {
					rows = #(rows:get() :: { any }),
					columns = d.columns,
					selectedColumn = tbl.api.selectedColumn:get(),
					sortOrder = d.sortOrder,
					widths = widths:get(),
					hint = hint:get(),
					rootPath = d.rootPath,
				}
			end,

			dispose = function()
				tbl.dispose()
				scope:dispose()
			end,
		}
	end,
}
