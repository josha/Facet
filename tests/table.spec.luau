--!strict
-- Table control Phase A tests (ADR-0007): column alignment via shared dims,
-- variable row heights, headerless mode, selection single/multi through the
-- activate path + keyboard focus, custom cells with live nested controls,
-- the resize MODEL (setColumnWidth), dump determinism, churn neutrality.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local serde = require("@lune/serde")

local Facet = require("../src")
local table_control = require("../src/controls/table")
local snapshot = require("../src/themes/snapshot")
local fake_target = require("../tests/lib/fake_target")

local RACERS = {
	{ id = "razz", name = "Razz Raccoon", laps = 3 },
	{ id = "bolt", name = "Bunny Bolt", laps = 3 },
	{ id = "josh", name = "Josh", laps = 2 },
}

local function hasColumnCells(columns: { any }): boolean
	for _, column in columns do
		if column.cell ~= nil or column.value ~= nil then
			return true
		end
	end
	return false
end

local function world(spec: any)
	local core = spec.core or Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	-- Task 10: `spec.now` is an OPTIONAL scripted clock (row_actions_input.
	-- spec.luau's own `pointerWorld` pattern) — every existing caller omits
	-- it and gets the unchanged default (`presenterOpts.now or os.clock`,
	-- presenter.luau). A row-actions gesture test needs one: without it,
	-- `nowFn` is REAL wall-clock time, and `drag_velocity`'s tracker divides
	-- a real position delta by a near-zero REAL-time delta between two
	-- synchronous pushes — an explosive, nondeterministic "velocity" that
	-- seeds the release spring with garbage (a live-found repro building
	-- this task: a huge bogus overshoot before decaying back to whatever it
	-- decayed to). Reorder's own drag math never reads velocity at all,
	-- which is why no table.spec.luau test needed this before row_actions
	-- rode the same harness.
	local pres = Facet.newPresenter(core, env, adapter, system, if spec.now then { now = spec.now } else nil)
	local rows = core:signal(spec.rowsOverride or RACERS)
	local tbl = table_control.build(Facet, core, {
		id = "Racers",
		columns = spec.columns or {
			{ id = "name", title = "Racer", width = { type = "fill", weight = 1 }, minWidth = 80, resizable = true },
			{ id = "laps", title = "Laps", width = { type = "fixed", px = 64 } },
		},
		rows = rows,
		-- NEW-3: the row's own gap is part of what the columns divide, so a case
		-- about column widths has to be able to declare one
		gap = spec.gap,
		key = function(item)
			return item.id
		end,
		cellFor = if spec.cellFor ~= nil
				or spec.noCellFor
				or (spec.columns and hasColumnCells(spec.columns))
			then spec.cellFor
			else function(columnId, item)
				return Facet.UI.Text({
					id = "Value",
					text = if columnId == "name" then item.name else tostring(item.laps),
					textSize = 16,
				})
			end,
		rowHeight = spec.rowHeight or 40,
		header = spec.header,
		selection = spec.selection or "single",
		rowGap = spec.rowGap,
		sortOrder = spec.sortOrder,
		reorderable = spec.reorderable,
		onReorder = spec.onReorder,
		dragLabel = spec.dragLabel,
		editing = spec.editing,
		rowActions = spec.rowActions,
		-- AN ENV BY DEFAULT (director round 12, 2026-07-27). The auto Edit/Done
		-- toggle is a TOUCH affordance — "mouse users scroll with the wheel and
		-- drag directly, so they never need edit mode" — but a table with NO env
		-- cannot know the input class, so it shows the toggle unconditionally.
		-- These specs drive mouse drags at hard-coded coordinates, so they were
		-- silently exercising a configuration that does not exist on a real
		-- pointer device, and the toolbar row the toggle now occupies moved every
		-- one of those coordinates. Passing the env makes them what they claim to
		-- be: pointer tests, on a pointer. `passEnv = false` opts back out.
		env = if spec.passEnv == false then nil else env,
		height = spec.height,
	})
	local screen = Facet.UI.Screen({ id = "S", children = { tbl.blueprint } })
	local handle = pres.present(screen, {
		-- this legacy harness drives the table's FLAT-ring story (grip in the
		-- ring, wrap-around, shift+Navigate reorder); it opts out of the
		-- ADR-0013 auto-grouping the Table contribution now advertises so its
		-- flat-ring assertions stay unchanged (grouped nav omits the header grip
		-- and routes reorder through grab mode instead of shift+Navigate).
		navigationGroups = false,
		onActivate = function(path, meta)
			tbl.api.handleActivate(path, meta)
		end,
		onAdjust = function(path, dir, rectOf)
			tbl.api.handleAdjust(path, dir, rectOf)
		end,
		onReorderNav = function(path, dir)
			return tbl.api.handleReorderNav(path, dir)
		end,
		onFocusNav = function(path)
			tbl.api.handleFocusMoved(path)
		end,
	})
	pres.refresh()
	return core, adapter, pres, tbl, rows, handle, system, env
end

-- Phase B: the table root is an Anchor (overlay host for resize/drop guides)
-- with the content under /Main — paths carry that segment
local function rowHitPath(version: number, key: string): string
	return `/S/Racers/Main/Body/Rows/[{key}@{version}]/Row/Hit`
end
local function cellPath(version: number, key: string, columnId: string): string
	return `/S/Racers/Main/Body/Rows/[{key}@{version}]/Row/Cells/Cell-{columnId}`
end

describe("Table: layout", function()
	it("columns align across header and every row (fill + fixed)", function()
		local _, adapter, _, tbl = world({})
		local headerName = adapter.node("/S/Racers/Main/Header/Head-name").rect
		local headerLaps = adapter.node("/S/Racers/Main/Header/Head-laps").rect
		expect(headerLaps.w).toBe(64)
		for _, racer in RACERS do
			local nameCell = adapter.node(cellPath(0, racer.id, "name")).rect
			local lapsCell = adapter.node(cellPath(0, racer.id, "laps")).rect
			expect(nameCell.x).toBe(headerName.x)
			expect(nameCell.w).toBe(headerName.w)
			expect(lapsCell.x).toBe(headerLaps.x)
			expect(lapsCell.w).toBe(64)
		end
	end)

	--[[ ...AND THEY STAY ALIGNED WHEN EDIT MODE OPENS (bug FIX-SHOW C, director
		report 2026-08-22: "the header pills keep their pre-edit x positions and
		widths, so every header is misaligned with its column — Name sits over the
		minus circles").

		Edit mode gives a row up to TWO leading affordances, and the row's cells
		pay for both: the table's own ≡/◉ gutter (`cellsEditPadding`, HANDLE_GUTTER)
		and — on a row wrapped by `row_actions` because it carries a destructive
		action — the composite's ⊖ gutter, which `row_actions_root` spends as the
		LEFT PADDING of the row content it was handed. The heading band sits outside
		every row, so it has to add the same two or the columns come apart the
		instant the mode opens.

		Measured before the fix, at 800px with two columns: the body cell moved from
		x=0 to x=32 (unwrapped) / x=68 (wrapped) and narrowed by the same amount,
		while the header cell stayed at x=0 w=736. THE INVARIANT IS THE ONE THE CASE
		ABOVE ALREADY STATES, asserted in the state the case above never enters —
		which is why this is a second case on the same rule rather than a number
		somebody chose. ]]
	local function editAlignmentWorld(spec: any)
		local core, adapter, pres, tbl = world(spec)
		local editing = tbl.api.editing
		editing:set(true)
		pres.refresh()
		return core, adapter, pres, tbl
	end

	local function expectAligned(adapter: any, rowCellPath: string)
		local headerName = adapter.node("/S/Racers/Main/Header/Head-name").rect
		local nameCell = adapter.node(rowCellPath).rect
		expect(nameCell.x).toBe(headerName.x)
		expect(nameCell.w).toBe(headerName.w)
	end

	it("columns stay aligned in edit mode: the ≡ gutter", function()
		local _, adapter = editAlignmentWorld({ reorderable = true, onReorder = function() end })
		expectAligned(adapter, cellPath(0, "razz", "name"))
	end)

	-- ...and the ◉/◯ half of the same gutter, on the OTHER route into edit mode:
	-- an owner-held `editing` signal is what makes `canEditMode` true here, and
	-- without it this arm would assert alignment on a table that never insets at
	-- all — a case that cannot fail. `world` forwards `spec.editing` verbatim.
	it("columns stay aligned in edit mode: the selection gutter", function()
		local core = Facet.newCore()
		local _, adapter = editAlignmentWorld({ core = core, selection = "multi", editing = core:signal(false) })
		expectAligned(adapter, cellPath(0, "razz", "name"))
	end)

	--[[ THE THIRD ARM — a row WRAPPED by `row_actions` for its destructive action.
		That row's content carries a SECOND leading gutter, the composite's own ⊖,
		which `row_actions_root` spends as the LEFT PADDING of the row content it was
		handed. The heading band sits outside every row, so it has to add that number
		too, and `headerPadding` was ALREADY WRITTEN to — `rowEditGutter` reads
		whatever `table_rows`' `noteEditGutter` is handed.

		WHAT WAS MISSING WAS ONE ASSIGNMENT, and it is why this arm was carried as a
		blocked note for one round rather than as a fix: the composite published
		`api.editGutterPx` only from inside its `if isHosted then` block, so in the
		WRAP mode Table uses the field was nil and `noteEditGutter` returned at its
		first line. There was no second route to the number —
		`controls.rowActions.rowGutter` is not exported from
		`row_actions_metrics.luau` — and re-deriving the sum in the table would have
		been a second implementation of a number the composite already owns, which is
		exactly how the two come apart again.

		Measured red before the publication, at 800px with two columns: header
		x=32 w=704 against a cell at x=68 w=668 — 36px, which is
		`controls.rowActions.editAffordance` (28) plus
		`controls.rowActions.rowGutter` (8). Live evidence and the full packet are in
		`artifacts/framework-gaps-phase2/bugC-wrapped-row-blocked.txt`. ]]
	it("columns stay aligned in edit mode: the ≡ gutter AND the row-actions ⊖", function()
		local _, adapter = editAlignmentWorld({
			reorderable = true,
			onReorder = function() end,
			rowActions = function()
				return {
					trailing = {
						{ id = "delete", role = "destructive", label = "Delete", onAction = function() end },
					},
				}
			end,
		})
		expectAligned(adapter, "/S/Racers/Main/Body/Rows/[razz@0]/RowActions-razz/Content/Row/Cells/Cell-name")
	end)

	it("variable row heights position rows correctly", function()
		local _, adapter = world({
			rowHeight = function(item)
				return if item.id == "josh" then 72 else 40
			end,
			header = false,
		})
		local razz = adapter.node(rowHitPath(0, "razz")).rect
		local bolt = adapter.node(rowHitPath(0, "bolt")).rect
		local josh = adapter.node(rowHitPath(0, "josh")).rect
		expect(razz.h).toBe(40)
		expect(josh.h).toBe(72)
		expect(bolt.y).toBe(razz.y + 40)
		expect(josh.y).toBe(bolt.y + 40)
	end)

	it("headerless mode renders no header row (the racer-list shape)", function()
		local _, adapter = world({ header = false })
		expect(adapter.node("/S/Racers/Main/Header")).toBe(nil)
		expect(adapter.node(rowHitPath(0, "razz")) ~= nil).toBe(true)
	end)
end)

describe("Table: selection", function()
	it("single: activate selects exactly one; selection survives without remount", function()
		local _, adapter, pres, tbl, _, handle, system = world({ selection = "single" })
		local runsBefore = handle.root.counters().factoryRuns
		adapter.tap(rowHitPath(0, "bolt"))
		pres.refresh()
		expect(tbl.api.selectedKeys:get().bolt).toBe(true)
		expect(adapter.node(rowHitPath(0, "bolt")).props.selected).toBe(true)
		adapter.tap(rowHitPath(0, "josh"))
		pres.refresh()
		expect(tbl.api.selectedKeys:get().bolt).toBe(nil) -- single: replaced
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
		expect(adapter.node(rowHitPath(0, "bolt")).props.selected).toBe(false)
		expect(handle.root.counters().factoryRuns).toBe(runsBefore) -- state-driven
	end)

	it("multi: activates toggle additively (tap idiom)", function()
		local _, adapter, pres, tbl = world({ selection = "multi" })
		adapter.tap(rowHitPath(0, "razz"))
		adapter.tap(rowHitPath(0, "josh"))
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(true)
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
		adapter.tap(rowHitPath(0, "razz")) -- toggle off
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(nil)
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
	end)

	it("keyboard: focus walks row hits and Activate selects", function()
		local _, _, pres, tbl, _, _, system = world({ selection = "single" })
		-- THE COLUMN HANDLE LEADS (director 2026-07-29): a resizable column's header
		-- is its single focus stop, and the header precedes the rows.
		expect(pres.focus.focused:get()).toBe("/S/Racers/Main/Header/Head-name/Column")
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:get()).toBe(rowHitPath(0, "razz"))
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:get()).toBe(rowHitPath(0, "bolt"))
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		expect(tbl.api.selectedKeys:get().bolt).toBe(true)
	end)
end)

describe("Table: custom cells and resize model", function()
	it("custom cells host live nested controls (director: results list w/ custom cell)", function()
		local core, adapter, pres, tbl = world({
			header = false,
			cellFor = function(columnId, item)
				if columnId == "name" then
					return Facet.UI.Toggle({ id = "Fav", label = item.name, value = false })
				end
				return Facet.UI.Text({ id = "Value", text = tostring(item.laps), textSize = 16 })
			end,
		})
		local favPath = cellPath(0, "razz", "name") .. "/Fav"
		expect(adapter.node(favPath) ~= nil).toBe(true)
		expect(adapter.node(favPath).props.label).toBe("Razz Raccoon")
		-- the nested control keeps its own tap handler (renders above the hit)
		expect(adapter.node(favPath).onActivate ~= nil).toBe(true)
	end)

	it("setColumnWidth commits a new width to every row and the header", function()
		local _, adapter, pres, tbl = world({})
		tbl.api.setColumnWidth("name", 200)
		pres.refresh()
		-- version bumped: rows remounted under @1 keys
		expect(adapter.node(cellPath(1, "razz", "name")).rect.w).toBe(200)
		expect(adapter.node(cellPath(1, "bolt", "name")).rect.w).toBe(200)
		expect(adapter.node(rowHitPath(0, "razz"))).toBe(nil) -- old rows gone
		-- non-resizable columns refuse
		tbl.api.setColumnWidth("laps", 200)
		pres.refresh()
		expect(adapter.node(cellPath(1, "razz", "laps")).rect.w).toBe(64)
	end)

	--[[ DIR-4 (director device round 2026-08-17): resize Name and Artist wide in
		landscape, rotate to portrait — Rating was pushed off screen and the header
		still read "Name 297px · Artist 168px" on a 393px viewport. `setColumnWidth`
		commits an ABSOLUTE `{ type = "fixed", px }`, and a fixed dim has no relation
		to the width it is laid out in, so a resized table was the one shape whose
		columns could not answer a viewport change at all.

		The rule is proved twice: as arithmetic on `controls/table_columns.luau`
		(pure, so a rotation is three numbers), and end to end on the mounted table
		at the two viewports the director used. ]]
	it("committed overrides RESOLVE narrower when the viewport cannot hold them (DIR-4)", function()
		local table_columns = require("../src/controls/table_columns")
		local columns = {
			{ id = "name", width = { type = "fill", weight = 1 }, minWidth = 80, resizable = true },
			{ id = "artist", width = { type = "fill", weight = 1 }, minWidth = 60, resizable = true },
			{ id = "rating", width = { type = "fixed", px = 96 } },
		}
		local committed = { name = 297, artist = 168 }

		-- WIDE: everything fits, so the commitment is honoured to the pixel
		local wide = table_columns.fitOverrides(columns, committed, 800)
		expect(wide.name).toBe(297)
		expect(wide.artist).toBe(168)

		-- NARROW (the director's 393px phone, less the rating column): the
		-- overridden pair scales, the locked column keeps its declared width, and
		-- everything still fits
		local narrow = table_columns.fitOverrides(columns, committed, 361)
		expect(narrow.name < 297).toBe(true)
		expect(narrow.artist < 168).toBe(true)
		expect(narrow.name >= 80).toBe(true)
		expect(narrow.artist >= 60).toBe(true)
		expect(math.abs((narrow.name + narrow.artist + 96) - 361) < 0.001).toBe(true)
		-- proportional to the room above each floor, so the wide column yields more
		expect((297 - narrow.name) > (168 - narrow.artist)).toBe(true)

		-- ...and the model never moved: widening restores the commitment exactly
		expect(table_columns.fitOverrides(columns, committed, 800).name).toBe(297)
		expect(committed.name).toBe(297)

		-- FLOORS ARE FLOORS: when even the minimums do not fit, the clamp stops
		local crushed = table_columns.fitOverrides(columns, committed, 100)
		expect(crushed.name).toBe(80)
		expect(crushed.artist).toBe(60)
	end)

	--[[ ADAPT-19 — A DECLARED COLUMN FLOOR IS A FLOOR, INCLUDING ON `fill`.
		(`artifacts/release-candidate-review/adapt-audit/matrix.md` J-2, severity
		highest: "at 390px a `minWidth = 120` column resolves to 73px and a
		`minWidth = 100` column to 37px, and the cell text is truncated = true".)

		THE DEFECT. `minWidth` was spent in exactly two places — an OVERRIDE's clamp
		and a `percent` dim's `min` — and `fill`, which is the dim kind a responsive
		table uses for nearly every column, was `return dim`, untouched. The solver
		divides `fill` slack strictly by weight and honours no `min` on it at all
		(`arrangeStack`'s fill block), so a floor declared on a fill column was a
		property the framework accepted and never spent. It is also what made
		ADAPT-18 invisible rather than merely unhandled: columns that shrink below
		their own floors LOOK like a table that is coping.

		THE RULE IS THE TABLE'S, NOT THE SOLVER'S, and deliberately: `table.luau`
		already measures the post-reserve content width the rows divide, and already
		resolves one dim per column against it. So the floor is applied where that
		division happens — a fill column whose SHARE would fall under its floor is
		pinned to the floor and leaves the slack pool, which is the ordinary
		flex-with-minimum negotiation, run once, purely, on numbers.

		WHAT IT DELIBERATELY DOES NOT DO: measure. A `content`/`hug` column's
		appetite is a measurement, so it contributes nothing to the consumed width
		here and the fills keep dividing what is left — the behaviour that ships
		today, unchanged. ]]
	it("a `fill` column's declared minWidth is a floor, and pinning it leaves the pool (ADAPT-19)", function()
		local table_columns = require("../src/controls/table_columns")
		--[[ EVERY COLUMN IS PINNED AGAINST COLLAPSE, so this case is about the FLOOR
			alone: the first column never collapses and the other two say `"always"`,
			which leaves the rule nothing it may remove. That is the honest way to
			read ADAPT-19 on its own — ADAPT-18's own cases below let it fire. ]]
		local columns = {
			{ id = "name", width = { type = "fill", weight = 1 }, minWidth = 120 },
			{ id = "artist", width = { type = "fill", weight = 1 }, minWidth = 100, priority = "always" },
			{ id = "rating", width = { type = "fixed", px = 96 }, priority = "always" },
		}
		-- the audit measured this on a five-column table at 390px; the same
		-- arithmetic, smaller: 300 wide with 96 already spoken for leaves 204 for
		-- two fills that declared 220 between them, so both floors bind and the
		-- table overflows HONESTLY rather than pretending 102 was 120
		local narrow = table_columns.layout(columns, {}, 300, 0, nil)
		expect(narrow.dims.name.type).toBe("fixed")
		expect(narrow.dims.name.px).toBe(120)
		expect(narrow.dims.artist.type).toBe("fixed")
		expect(narrow.dims.artist.px).toBe(100)
		-- ...and WIDE, nothing is pinned: a floor that binds at every width is a
		-- fixed column wearing a fill's name
		local wide = table_columns.layout(columns, {}, 900, 0, nil)
		expect(wide.dims.name.type).toBe("fill")
		expect(wide.dims.artist.type).toBe("fill")

		-- THE ASYMMETRIC CASE, which is what "leaves the pool" means: one fill
		-- clears its floor and the other does not, so the pinned one takes exactly
		-- its floor and the survivor takes ALL the rest rather than half of it.
		local mixed = table_columns.layout({
			{ id = "name", width = { type = "fill", weight = 1 } },
			{ id = "artist", width = { type = "fill", weight = 1 }, minWidth = 200 },
		}, {}, 300, 0, nil)
		expect(mixed.dims.artist.px).toBe(200)
		expect(mixed.dims.name.type).toBe("fill")

		-- NO MEASUREMENT YET IS NOT A NARROW VIEWPORT: the first frame resolves
		-- what the author declared and the measurement corrects it, exactly as the
		-- DIR-4 clamp already does
		expect(table_columns.layout(columns, {}, nil, 0, nil).dims.name.type).toBe("fill")
	end)

	--[[ ADAPT-18 · COLUMN PRIORITY-COLLAPSE — the arithmetic.
		(director-approved paradigm; audit J-1, severity highest.) The device case
		and the disclosure live in `tests/table_input.spec.luau`, where they are
		driven through the real input seams; these are the numbers underneath. ]]
	it("the lowest-priority column collapses first, one at a time, until it fits (ADAPT-18)", function()
		local table_columns = require("../src/controls/table_columns")
		local columns = {
			{ id = "name", width = { type = "fill", weight = 1 }, minWidth = 120 },
			{ id = "artist", width = { type = "fill", weight = 1 }, minWidth = 100 },
			{ id = "rating", width = { type = "fixed", px = 96 } },
		}
		-- WIDE: 316 of declared floor in 800 of room. Nothing goes.
		expect(#table_columns.layout(columns, {}, 800, 0, nil).hidden).toBe(0)
		-- 300: the floors want 316. The LAST-declared collapsible column goes, and
		-- ONE is enough — the rule stops the moment the remainder fits rather than
		-- clearing the deck.
		local narrow = table_columns.layout(columns, {}, 300, 0, nil)
		expect(#narrow.hidden).toBe(1)
		expect(narrow.hidden[1]).toBe("rating")
		expect(narrow.dims.rating.px).toBe(0)
		-- 150: 220 still does not fit, so a SECOND column goes — and the first
		-- declared one never does, whatever is left over
		local crushed = table_columns.layout(columns, {}, 150, 0, nil)
		expect(#crushed.hidden).toBe(2)
		expect(crushed.hidden[1]).toBe("artist")
		expect(crushed.hidden[2]).toBe("rating")
		expect(crushed.hiddenSet.name).toBe(nil)
		-- 10: the first column cannot fit its own floor and STILL does not go. A
		-- table whose rows have no name is not a narrower table.
		expect(table_columns.layout(columns, {}, 10, 0, nil).hiddenSet.name).toBe(nil)
	end)

	it("a declared `priority` overrides declaration order, and `always` is a refusal (ADAPT-18)", function()
		local table_columns = require("../src/controls/table_columns")
		--[[ `rating` is declared LAST and is the most important thing on the row
			after the name; `artist` is declared second and is the first to go. The
			ordering the author wrote down is not always the ordering they meant, which
			is the whole reason the key exists. ]]
		local columns = {
			{ id = "name", width = { type = "fill", weight = 1 }, minWidth = 120 },
			{ id = "artist", width = { type = "fill", weight = 1 }, minWidth = 100, priority = 9 },
			{ id = "rating", width = { type = "fixed", px = 96 }, priority = 2 },
		}
		local narrow = table_columns.layout(columns, {}, 300, 0, nil)
		expect(#narrow.hidden).toBe(1)
		expect(narrow.hidden[1]).toBe("artist")

		-- `"always"` is not a very high priority — it is a refusal, so no number
		-- anywhere else can beat it and the table overflows rather than dropping it
		local pinned = {
			{ id = "name", width = { type = "fill", weight = 1 }, minWidth = 120 },
			{ id = "artist", width = { type = "fill", weight = 1 }, minWidth = 100, priority = "always" },
			{ id = "rating", width = { type = "fixed", px = 96 }, priority = "always" },
		}
		expect(#table_columns.layout(pinned, {}, 100, 0, nil).hidden).toBe(0)
	end)

	it("collapse re-evaluates in BOTH directions, and the model never moved (ADAPT-18)", function()
		local table_columns = require("../src/controls/table_columns")
		local columns = {
			{ id = "name", width = { type = "fill", weight = 1 }, minWidth = 120 },
			{ id = "artist", width = { type = "fill", weight = 1 }, minWidth = 100 },
			{ id = "rating", width = { type = "fixed", px = 96 } },
		}
		expect(#table_columns.layout(columns, {}, 800, 0, nil).hidden).toBe(0)
		expect(#table_columns.layout(columns, {}, 300, 0, nil).hidden).toBe(1)
		-- ...and back. The rule is a pure function of the width, so widening cannot
		-- leave a column behind: there is no state to get stuck.
		expect(#table_columns.layout(columns, {}, 800, 0, nil).hidden).toBe(0)
		-- an unmeasured width collapses NOTHING, so a first frame is never the
		-- emptiest frame
		expect(#table_columns.layout(columns, {}, nil, 0, nil).hidden).toBe(0)
	end)

	it("J-3: a WIDE ALL-FIXED table at compact collapses instead of clipping", function()
		local table_columns = require("../src/controls/table_columns")
		--[[ The audit's own J-3 shape: 720px of FIXED columns in a 390px body whose
			scroll region is `axis = y` only. "The framework files the right diagnostic
			twice — content overflows this hstack by 330px, wrap it in a ScrollView —
			advice the control cannot take about its own header." A fixed column's
			floor IS its width, so the rule reaches this shape without a `minWidth`
			anywhere, and drops columns right to left until what is left fits. ]]
		local columns = {
			{ id = "name", width = { type = "fixed", px = 240 } },
			{ id = "team", width = { type = "fixed", px = 160 } },
			{ id = "best", width = { type = "fixed", px = 160 } },
			{ id = "rating", width = { type = "fixed", px = 160 } },
		}
		expect(#table_columns.layout(columns, {}, 720, 0, nil).hidden).toBe(0)
		-- 420: 240 + 160 fits and the last two do not, so exactly two go
		local mid = table_columns.layout(columns, {}, 420, 0, nil)
		expect(mid.hidden).toEqual({ "best", "rating" })
		expect(mid.dims.name.px + mid.dims.team.px <= 420).toBe(true)
		-- 390: not even two fit, so the rule keeps going until one does — and stops
		-- at the row's identity, which never leaves however narrow it gets
		local compact = table_columns.layout(columns, {}, 390, 0, nil)
		expect(compact.hidden).toEqual({ "team", "best", "rating" })
		expect(compact.dims.name.px <= 390).toBe(true)
	end)

	it("a sum that equals `room` FITS — the collapse test is not an exact float compare (R1-H2)", function()
		local table_columns = require("../src/controls/table_columns")
		--[[ REVIEW ROUND 1, HIGH-2. `fitOverrides` computes each fitted width as
			`px - take * (room_i / slack)`, so whenever the clamp is active the fitted
			widths sum to `available - reserved` BY CONSTRUCTION. `layout` then re-sums
			those same numbers with a left fold and asked `demand <= room` EXACTLY —
			and IEEE accumulation lands the re-sum epsilon over its own target, so the
			loop reads "does not fit" and deletes a column whose widths demonstrably
			do.

			The reviewer's own reproduction, verbatim: two `fill` columns with floors
			100 and 90, committed overrides 377 and 304, available 241.

			    fitOverrides -> 128.77189409368637 + 112.22810590631366
			                  = 241.00000000000003
			    layout()     -> hidden = b

			Measured across the band: 53 of the 1,011 widths in 190..1200 collapsed a
			column whose floors fit. Player-visible as "drag two dividers wide, narrow
			the window, and over a contiguous stripe of widths the trailing column
			vanishes" — where this module's own DIR-4 contract says the clamp absorbs
			it. ]]
		local columns = {
			{ id = "a", width = { type = "fill", weight = 1 }, minWidth = 100, resizable = true },
			{ id = "b", width = { type = "fill", weight = 1 }, minWidth = 90, resizable = true },
		}
		local overrides = { a = 377, b = 304 }
		-- the exact width the reviewer measured: the fitted pair sums to 241 + 3e-14
		expect(#table_columns.layout(columns, overrides, 241, 0, nil).hidden).toBe(0)
		-- ...and the neighbouring case they also measured, where the floors fit with
		-- three whole pixels to spare
		expect(#table_columns.layout(columns, overrides, 193, 0, nil).hidden).toBe(0)

		--[[ THE WHOLE BAND, not the two widths that happened to be reported. A
			regression here is a STRIPE of widths rather than a point, so the guard is
			a stripe too: every width from the floors' own sum upward must keep both
			columns, because the clamp's whole contract is that it absorbs the
			difference down to the floors. ]]
		local collapsedAbove = {}
		for width = 190, 1200 do
			if #table_columns.layout(columns, overrides, width, 0, nil).hidden > 0 then
				table.insert(collapsedAbove, width)
			end
		end
		expect(`collapsed above the floors: {#collapsedAbove}`).toBe("collapsed above the floors: 0")

		-- ...and the NULL HYPOTHESIS, so the tolerance cannot become "never
		-- collapse": one pixel under the floors' own sum, the rule still fires
		expect(#table_columns.layout(columns, overrides, 189, 0, nil).hidden).toBe(1)
	end)

	it("a table whose columns declare no floor never collapses anything (ADAPT-18)", function()
		local table_columns = require("../src/controls/table_columns")
		-- three pure fills with no `minWidth`: the demand is zero, zero always fits,
		-- and every table shipping today that declares nothing behaves exactly as it
		-- did. This is the case that makes the paradigm safe to turn on by default.
		local columns = {
			{ id = "a", width = { type = "fill", weight = 1 } },
			{ id = "b", width = { type = "fill", weight = 1 } },
			{ id = "c", width = { type = "fill", weight = 1 } },
		}
		expect(#table_columns.layout(columns, {}, 40, 0, nil).hidden).toBe(0)
	end)

	it("a COMMITTED override is clamped first and only then counted (ADAPT-18 x DIR-4)", function()
		local table_columns = require("../src/controls/table_columns")
		--[[ THE ORDER MATTERS AND IT IS THE BRIEF'S: the resize-override clamp that
			already ships runs FIRST, so a player who dragged Name to 600px in
			landscape does not lose the Rating column on rotation merely because a
			stale commitment says 600. The clamp brings 600 back to what fits, and
			only what is left over decides whether anything collapses. ]]
		local columns = {
			{ id = "name", width = { type = "fill", weight = 1 }, minWidth = 80, resizable = true },
			{ id = "rating", width = { type = "fixed", px = 96 } },
		}
		local out = table_columns.layout(columns, { name = 600 }, 300, 0, nil)
		expect(#out.hidden).toBe(0)
		expect(out.dims.name.px <= 300 - 96).toBe(true)
		expect(out.dims.name.px >= 80).toBe(true)
	end)

	it("the mounted table gives a fill column its floor rather than a weighted share (ADAPT-19)", function()
		-- 3:1 weights on two fills whose floors BOTH fit: the light column's share
		-- of a ~300px band is ~75px against a declared 100, so the floor has to
		-- take it out of the pool and hand the remainder to its neighbour. Nothing
		-- collapses here (the floors fit), which is what keeps this a floor case.
		local _, adapter, pres, _tbl, _rows, _handle, _system, env = world({
			columns = {
				{ id = "name", title = "Racer", width = { type = "fill", weight = 3 }, minWidth = 120 },
				{ id = "laps", title = "Laps", width = { type = "fill", weight = 1 }, minWidth = 100 },
			},
		})
		env:set("viewportRect", { x = 0, y = 0, w = 300, h = 600 })
		pres.refresh()
		pres.refresh() -- the measurement lands on the solve, the floor on the next
		local laps = adapter.node(cellPath(0, "razz", "laps"))
		local name = adapter.node(cellPath(0, "razz", "name"))
		expect(laps ~= nil and name ~= nil).toBe(true)
		expect(laps.rect.w >= 100).toBe(true)
		-- ...and the pin did not turn the table into two equal columns: the survivor
		-- takes what the pinned column left, which is the "leaves the pool" half
		expect(name.rect.w > laps.rect.w).toBe(true)
	end)

	it("a non-resizable column is never clamped below its declared width (DIR-4)", function()
		local table_columns = require("../src/controls/table_columns")
		local columns = {
			{ id = "name", width = { type = "fill", weight = 1 }, minWidth = 40, resizable = true },
			{ id = "laps", width = { type = "fixed", px = 64 } },
		}
		-- an override on a LOCKED column cannot take it below what the author declared
		local fitted = table_columns.fitOverrides(columns, { name = 300, laps = 200 }, 200)
		expect(fitted.laps >= 64).toBe(true)
		expect(fitted.name >= 40).toBe(true)
	end)

	it("the mounted table honours the clamp at a narrow viewport, and restores it (DIR-4)", function()
		local _, adapter, pres, tbl, _rows, _handle, _system, env = world({
			columns = {
				{
					id = "name",
					title = "Racer",
					width = { type = "fill", weight = 1 },
					minWidth = 60,
					resizable = true,
				},
				{ id = "laps", title = "Laps", width = { type = "fixed", px = 64 } },
			},
		})
		tbl.api.setColumnWidth("name", 600)
		pres.refresh()
		expect(adapter.node(cellPath(1, "razz", "name")).rect.w).toBe(600)

		-- THE ROTATION: the 800px landscape window becomes a 393px portrait one
		env:set("viewportRect", { x = 0, y = 0, w = 393, h = 800 })
		pres.refresh()
		pres.refresh() -- the measurement lands on the solve, the clamp on the next
		local clamped = adapter.node(cellPath(1, "razz", "name")).rect.w
		expect(clamped < 600).toBe(true)
		expect(clamped >= 60).toBe(true)
		-- the LOCKED column is still on screen at its declared width
		local laps = adapter.node(cellPath(1, "razz", "laps"))
		expect(laps.rect.w).toBe(64)
		expect(laps.rect.x + laps.rect.w <= 393 + 0.001).toBe(true)
		-- ...and the header divides the SAME width as the cells
		expect(adapter.node("/S/Racers/Main/Header/Head-name").rect.w).toBe(clamped)

		-- ...and the commitment is intact: widening restores it to the pixel
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		pres.refresh()
		pres.refresh()
		expect(adapter.node(cellPath(1, "razz", "name")).rect.w).toBe(600)
		expect(tbl.api.columnWidthOverrides:get().name).toBe(600)
	end)

	it("the clamp reserves the row's own GAP, so the last column still fits (NEW-3)", function()
		--[[ The first version of the clamp fitted `sum(widths) <= bodyWidth` and the
			cells live in an HStack with `gap` between them, so it under-reserved by
			`gap * (n - 1)` and the director's symptom reproduced for any table that
			declares one. Measured on this very harness before the fix:

			    no gap  -> name 329  laps x=329 w=64  right edge 393  fits
			    12px gap -> name 329  laps x=341 w=64  right edge 405  OVERFLOWS

			`world()` never set a gap, which is why the original mounted case passed. ]]
		local GAP = 12
		local _, adapter, pres, tbl, _rows, _handle, _system, env = world({
			gap = GAP,
			columns = {
				{
					id = "name",
					title = "Racer",
					width = { type = "fill", weight = 1 },
					minWidth = 60,
					resizable = true,
				},
				{ id = "laps", title = "Laps", width = { type = "fixed", px = 64 } },
			},
		})
		tbl.api.setColumnWidth("name", 600)
		pres.refresh()
		env:set("viewportRect", { x = 0, y = 0, w = 393, h = 800 })
		pres.refresh()
		pres.refresh()

		local laps = adapter.node(cellPath(1, "razz", "laps"))
		local name = adapter.node(cellPath(1, "razz", "name"))
		expect(laps ~= nil and name ~= nil).toBe(true)
		-- the gap really is spent between them — otherwise this proves nothing
		expect(math.abs((laps.rect.x - (name.rect.x + name.rect.w)) - GAP) <= 0.001).toBe(true)
		-- ...and the trailing edge is still inside the window
		expect(`right edge {laps.rect.x + laps.rect.w} <= 393: {tostring(laps.rect.x + laps.rect.w <= 393.001)}`).toBe(
			`right edge {laps.rect.x + laps.rect.w} <= 393: true`
		)
		-- the locked column keeps its declared width; only the overridden one paid
		expect(laps.rect.w).toBe(64)
		expect(name.rect.w < 600).toBe(true)
	end)

	it("the pure rule takes the reservation as a number, and zero is the old behaviour", function()
		local table_columns = require("../src/controls/table_columns")
		local columns = {
			{ id = "a", width = { type = "fill", weight = 1 }, minWidth = 40, resizable = true },
			{ id = "b", width = { type = "fill", weight = 1 }, minWidth = 40, resizable = true },
			{ id = "c", width = { type = "fixed", px = 60 } },
		}
		local committed = { a = 200, b = 200 }
		-- no reservation: the columns divide the whole 460 and nothing clamps
		expect(table_columns.fitOverrides(columns, committed, 460, 0).a).toBe(200)
		-- 24px of gap (two gaps of 12) plus 16px of card padding has to come out
		local fitted = table_columns.fitOverrides(columns, committed, 460, 40)
		expect(fitted.a < 200).toBe(true)
		expect(math.abs((fitted.a + fitted.b + 60 + 40) - 460) < 0.001).toBe(true)
		-- a reservation larger than the space leaves the floors standing
		local crushed = table_columns.fitOverrides(columns, committed, 100, 400)
		expect(crushed.a).toBe(40)
		expect(crushed.b).toBe(40)
	end)

	it("remounted rows keep hits painted beneath cell content (deterministic z-order)", function()
		-- the flat sibling render relies on paint order; creation order is NOT
		-- deterministic across a structural sync, so z-order must be assigned
		-- explicitly from the tree walk (live-found defect, 2026-07-19)
		local _, adapter, pres, tbl = world({})
		tbl.api.setColumnWidth("name", 200)
		pres.refresh()
		for _, key in { "razz", "bolt", "josh" } do
			local hit = adapter.node(rowHitPath(1, key))
			local value = adapter.node(cellPath(1, key, "name") .. "/Value")
			expect(hit.z ~= nil).toBe(true)
			expect(value.z ~= nil).toBe(true)
			expect(hit.z < value.z).toBe(true)
		end
	end)

	it("removed rows are pruned from the selection and anchor", function()
		local _, adapter, pres, tbl, rows = world({ selection = "multi", header = false })
		adapter.tap(rowHitPath(0, "razz"))
		adapter.tap(rowHitPath(0, "josh"))
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(true)
		rows:set({ RACERS[2] }) -- only bolt survives
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(nil)
		expect(tbl.api.selectedKeys:get().josh).toBe(nil)
	end)

	it("table ids containing Lua pattern magic still route rows and grips", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local rows = core:signal(RACERS)
		local tbl = table_control.build(Facet, core, {
			id = "results-list", -- '-' is pattern magic
			columns = {
				{
					id = "name",
					title = "Racer",
					width = { type = "fill", weight = 1 },
					minWidth = 80,
					resizable = true,
				},
			},
			rows = rows,
			key = function(item)
				return item.id
			end,
			cellFor = function(_columnId, item)
				return Facet.UI.Text({ id = "Value", text = item.name, textSize = 16 })
			end,
			rowHeight = 40,
			selection = "single",
		})
		local screen = Facet.UI.Screen({ id = "S", children = { tbl.blueprint } })
		pres.present(screen, {
			onActivate = function(path, meta)
				tbl.api.handleActivate(path, meta)
			end,
			onAdjust = function(path, dir, rectOf)
				tbl.api.handleAdjust(path, dir, rectOf)
			end,
		})
		pres.refresh()
		adapter.tap("/S/results-list/Main/Body/Rows/[razz@0]/Row/Hit")
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(true)
		tbl.dispose()
	end)

	it("row churn + dispose are registry-neutral and dumps deterministic", function()
		local core, adapter, pres, tbl, rows, handle = world({ header = false })
		local d1 = serde.encode("json", handle.root.dump(), true)
		expect(d1).toBe(serde.encode("json", handle.root.dump(), true))
		local baseline = core:counters()
		for i = 1, 10 do
			rows:set({ RACERS[1], RACERS[2], RACERS[3], { id = `extra{i}`, name = "X", laps = 0 } })
			pres.refresh()
			rows:set(RACERS)
			pres.refresh()
		end
		local after = core:counters()
		for k, v in baseline :: any do
			expect((after :: any)[k]).toBe(v)
		end
	end)

	-- CTRL-08a (api-architecture-consistency F-25). Every `.dump()` in this file
	-- was `handle.root.dump()` — the MOUNT tree — so the CONTROL's own dump, the
	-- largest one in the library, was never exercised at all and its schema
	-- string appeared nowhere in the repo.
	it("the CONTROL dump is deterministic and carries its schema string", function()
		local _, adapter, pres, tbl = world({})
		expect(tbl.dump().schema).toBe("facet-table-dump/1")
		local d1 = serde.encode("json", tbl.dump(), true)
		expect(d1).toBe(serde.encode("json", tbl.dump(), true))
		-- ...and it stays deterministic after live interaction moved the state
		adapter.tap(rowHitPath(0, "razz"))
		pres.refresh()
		local d2 = serde.encode("json", tbl.dump(), true)
		expect(d2).toBe(serde.encode("json", tbl.dump(), true))
		expect(d2 ~= d1).toBe(true)
	end)

	-- the live interaction state a bug report actually needs (playbook §2.5).
	-- VirtualList's dump carried all of its equivalents; Table's carried none.
	it("the control dump carries the live interaction state a bug report needs", function()
		local core, adapter, pres, tbl = world({ selection = "multi", editing = nil })
		local d = tbl.dump()
		expect(type(d.selectedKeys)).toBe("table")
		expect(#d.selectedKeys).toBe(0)
		expect(d.grabbedKey).toBeNil()
		expect(d.editing).toBe(false)
		expect(d.scrollTop).toBe(0)
		adapter.tap(rowHitPath(0, "razz"))
		pres.refresh()
		expect(tbl.dump().selectedKeys).toEqual({ "razz" })
		local _ = core
	end)

	-- `selectedKeys` is a SET inside the control, and a set's iteration order is
	-- not the insertion order and not stable across processes — so an unsorted
	-- array would make the largest control's dump non-deterministic the moment a
	-- second row was selected, which is exactly the promise the dump makes.
	it("the dump's selectedKeys are SORTED, so a multi-selection stays deterministic", function()
		local wide = {}
		for _, key in { "zeta", "alpha", "mango", "delta", "kilo", "bravo", "yankee", "echo" } do
			table.insert(wide, { id = key, name = key, laps = 1 })
		end
		local _, _, _, tbl = world({ selection = "multi", rowsOverride = wide })
		for _, key in { "zeta", "mango", "kilo", "bravo", "yankee", "echo", "alpha", "delta" } do
			tbl.api.select(key, { mode = "toggle" })
		end
		expect(tbl.dump().selectedKeys).toEqual({
			"alpha",
			"bravo",
			"delta",
			"echo",
			"kilo",
			"mango",
			"yankee",
			"zeta",
		})
	end)
end)

describe("Table: column-owned columns (director round 5)", function()
	it("per-column alignment positions cell content; vertical center is the default", function()
		local _, adapter = world({
			header = false,
			columns = {
				{ id = "name", title = "Racer", width = { type = "fill", weight = 1 } },
				-- numeric column, modifier-style trailing alignment
				{ id = "laps", title = "Laps", width = 64, alignment = { h = "trailing" } },
			},
		})
		local lapsCell = adapter.node(cellPath(0, "razz", "laps"))
		local lapsText = adapter.node(cellPath(0, "razz", "laps") .. "/Value")
		-- trailing: content hugs the cell's right inset (cellPadding 8)
		expect(lapsText.rect.x + lapsText.rect.w).toBe(lapsCell.rect.x + lapsCell.rect.w - 8)
		-- vertical center stays the default
		local topGap = lapsText.rect.y - lapsCell.rect.y
		local bottomGap = (lapsCell.rect.y + lapsCell.rect.h) - (lapsText.rect.y + lapsText.rect.h)
		expect(math.abs(topGap - bottomGap) <= 1).toBe(true)
		-- leading (default) column content keeps the left inset
		local nameText = adapter.node(cellPath(0, "razz", "name") .. "/Value")
		expect(nameText.rect.x).toBe(adapter.node(cellPath(0, "razz", "name")).rect.x + 8)
	end)

	-- api-architecture-consistency F-27: `column.alignment` was honoured on the
	-- CELLS and ignored by the header title, so a trailing-aligned numeric column
	-- showed a left-aligned heading over right-aligned numbers — a
	-- partially-honoured property, which is worse than an unsupported one.
	it("the header title honours the column alignment, exactly like the column's cells", function()
		local _, adapter = world({
			columns = {
				{ id = "name", title = "Racer", width = { type = "fill", weight = 1 } },
				{ id = "laps", title = "Laps", width = 64, alignment = { h = "trailing" } },
			},
		})
		local lapsHead = adapter.node("/S/Racers/Main/Header/Head-laps").rect
		local lapsTitle = adapter.node("/S/Racers/Main/Header/Head-laps/Title")
		-- the title's text box is inset by the same cellPadding the cells use...
		expect(lapsTitle.rect.x).toBe(lapsHead.x + 8)
		expect(lapsTitle.rect.x + lapsTitle.rect.w).toBe(lapsHead.x + lapsHead.w - 8)
		-- ...and the glyphs sit at the TRAILING edge of it, over their column
		expect(lapsTitle.props.textAlign).toBe("end")

		-- the leading default is unchanged: box and glyphs both start at the inset
		local nameHead = adapter.node("/S/Racers/Main/Header/Head-name").rect
		local nameTitle = adapter.node("/S/Racers/Main/Header/Head-name/Title")
		expect(nameTitle.rect.x).toBe(nameHead.x + 8)
		expect(nameTitle.props.textAlign).toBe("start")
	end)

	--[[ The sort mark lives at the trailing edge of the same header ZStack, so
		EVERY title can collide with it — a trailing one immediately, a leading one
		as soon as its text reaches that edge. It must not, either way.

		RE-AIMED 2026-08-15 (director, Studio: "the triangle sort indicator appears
		outside when themed"). Two numbers moved, both because the mark itself
		finally lands where it was declared to: the reserve is now
		`sortMarkMargin + sortMarkTextSize` (clearance + the glyph's own column, not
		clearance alone), and it is paid by a LEADING title too. The leading half is
		asserted below, since it was the case with no coverage at all. ]]
	it("a trailing title on a SORTABLE column clears the sort mark", function()
		local core = Facet.newCore()
		local sortOrder = core:signal({ column = "laps", ascending = true })
		local _, adapter = world({
			core = core,
			sortOrder = sortOrder,
			columns = {
				{ id = "name", title = "Racer", width = { type = "fill", weight = 1 } },
				{
					id = "laps",
					title = "Laps",
					width = 120,
					alignment = { h = "trailing" },
					sortable = true,
				},
			},
		})
		local head = adapter.node("/S/Racers/Main/Header/Head-laps").rect
		local title = adapter.node("/S/Racers/Main/Header/Head-laps/Title").rect
		local mark = adapter.node("/S/Racers/Main/Header/Head-laps/SortMark").rect
		expect(adapter.node("/S/Racers/Main/Header/Head-laps/SortMark").props.text).toBe("▲")
		-- the trailing inset is the THEME's mark reserve, and it is BOTH terms:
		-- controls.table.sortMarkMargin (14, the mark's own clearance from the
		-- column boundary it shares with the resize grip) + sortMarkTextSize (11,
		-- the glyph's own column). Inset by the clearance alone, a title ended
		-- exactly where the mark ends and ran its whole width.
		expect((head.x + head.w) - (title.x + title.w)).toBe(25)
		expect(title.x + title.w <= mark.x).toBe(true)
		-- ...and the mark itself stops the clearance short of the boundary rather
		-- than sitting ON it. This is the director's defect in one number: it read
		-- 0 for every package, so under a nine-slice header plate the glyph painted
		-- on the carved border outside the box.
		expect((head.x + head.w) - (mark.x + mark.w)).toBe(14)
		-- and a NON-sortable trailing column keeps the plain cell inset, so the
		-- reserve is paid only where there is something to clear
		local _, adapter2 = world({
			columns = {
				{ id = "name", title = "Racer", width = { type = "fill", weight = 1 } },
				{ id = "laps", title = "Laps", width = 120, alignment = { h = "trailing" } },
			},
		})
		local head2 = adapter2.node("/S/Racers/Main/Header/Head-laps").rect
		local title2 = adapter2.node("/S/Racers/Main/Header/Head-laps/Title").rect
		expect((head2.x + head2.w) - (title2.x + title2.w)).toBe(8)
	end)

	-- THE HALF THAT HAD NO COVERAGE, and the one the shipped playlist header
	-- fixture is made of: every column there is LEADING and sortable. A leading
	-- title fills the cell, so under the old one-sided rule its ellipsis landed
	-- under the triangle the moment the heading outgrew its column — the 1.4x
	-- localization case, which this asserts by measuring the box rather than by
	-- hoping the corpus contains a long enough word.
	it("a LEADING title on a sortable column reserves the mark's room too", function()
		local core = Facet.newCore()
		local sortOrder = core:signal({ column = "laps", ascending = true })
		local _, adapter = world({
			core = core,
			sortOrder = sortOrder,
			columns = {
				{ id = "name", title = "Racer", width = { type = "fill", weight = 1 } },
				{ id = "laps", title = "A very long heading indeed", width = 120, sortable = true },
			},
		})
		local head = adapter.node("/S/Racers/Main/Header/Head-laps").rect
		local title = adapter.node("/S/Racers/Main/Header/Head-laps/Title").rect
		local mark = adapter.node("/S/Racers/Main/Header/Head-laps/SortMark").rect
		expect(adapter.node("/S/Racers/Main/Header/Head-laps/Title").props.textAlign).toBe("start")
		expect((head.x + head.w) - (title.x + title.w)).toBe(25)
		expect(title.x + title.w <= mark.x).toBe(true)
		-- the leading edge is untouched: the reserve is spent at the far side only
		expect(title.x - head.x).toBe(8)
	end)

	it("a centered column centers its header title too", function()
		local _, adapter = world({
			columns = {
				{ id = "name", title = "Racer", width = { type = "fill", weight = 1 } },
				{ id = "laps", title = "Laps", width = 64, alignment = { h = "center" } },
			},
		})
		expect(adapter.node("/S/Racers/Main/Header/Head-laps/Title").props.textAlign).toBe("center")
	end)

	it("columns own their cells: `value` renders a default Text, `cell` renders custom", function()
		local _, adapter = world({
			header = false,
			cellFor = nil, -- no global fallback: columns carry their content
			columns = {
				{
					id = "name",
					width = { type = "fill", weight = 1 },
					cell = function(item)
						return Facet.UI.Text({ id = "Custom", text = item.name, textSize = 15 })
					end,
				},
				{
					id = "laps",
					width = 64,
					value = function(item)
						return tostring(item.laps)
					end,
				},
			},
		})
		expect(adapter.node(cellPath(0, "razz", "name") .. "/Custom").props.text).toBe("Razz Raccoon")
		expect(adapter.node(cellPath(0, "razz", "laps") .. "/Value").props.text).toBe("3")
	end)

	it("width sugar: a number is fixed px; {min, ideal, max} is a minMax band", function()
		local _, adapter = world({
			header = false,
			columns = {
				{ id = "name", width = { type = "fill", weight = 1 } },
				{ id = "laps", width = { min = 50, ideal = 80, max = 100 } },
			},
		})
		expect(adapter.node(cellPath(0, "razz", "laps")).rect.w).toBe(80)
	end)

	it("partial width sugar defaults the band's preferred ({min} alone is valid)", function()
		local _, adapter = world({
			header = false,
			columns = {
				{ id = "name", width = { type = "fill", weight = 1 } },
				{ id = "laps", width = { min = 50 } },
			},
		})
		expect(adapter.node(cellPath(0, "razz", "laps")).rect.w).toBe(50)
	end)

	it("a content-less column asserts AT BUILD, even with zero rows; ids must be path-safe", function()
		local core = Facet.newCore()
		local okEmpty = pcall(function()
			table_control.build(Facet, core, {
				id = "Bare",
				columns = { { id = "name", width = { type = "fill", weight = 1 } } },
				rows = core:signal({}),
				key = function(item)
					return item.id
				end,
				rowHeight = 40,
			})
		end)
		expect(okEmpty).toBe(false)
		local okSlash = pcall(function()
			table_control.build(Facet, core, {
				id = "Slashy",
				columns = {
					{
						id = "a/b",
						width = { type = "fill", weight = 1 },
						cell = function()
							return Facet.UI.Text({ id = "X", text = "", textSize = 12 })
						end,
					},
				},
				rows = core:signal({}),
				key = function(item)
					return item.id
				end,
				rowHeight = 40,
			})
		end)
		expect(okSlash).toBe(false)
	end)

	it("value() results are coerced to text (a raw number never reaches the Text prop)", function()
		local _, adapter = world({
			header = false,
			columns = {
				{
					id = "name",
					width = { type = "fill", weight = 1 },
					cell = function(item)
						return Facet.UI.Text({ id = "Custom", text = item.name, textSize = 15 })
					end,
				},
				{
					id = "laps",
					width = 64,
					value = function(item)
						return item.laps :: any -- a raw number, not a string
					end,
				},
			},
		})
		expect(adapter.node(cellPath(0, "razz", "laps") .. "/Value").props.text).toBe("3")
	end)

	it("header taps cycle the owner-held sortOrder; the table never sorts the data", function()
		local core = Facet.newCore()
		local sortOrder = core:signal(nil :: any)
		local _, adapter, pres, tbl, rows = world({
			core = core,
			sortOrder = sortOrder,
			columns = {
				{
					id = "name",
					title = "Racer",
					width = { type = "fill", weight = 1 },
					-- a `cell` column WITHOUT sortable=true stays out of sorting
					cell = function(item)
						return Facet.UI.Text({ id = "Custom", text = item.name, textSize = 16 })
					end,
				},
				{
					id = "laps",
					title = "Laps",
					width = 64,
					value = function(item)
						return tostring(item.laps)
					end,
				},
			},
		})
		local sortHit = "/S/Racers/Main/Header/Head-laps/Column"
		expect(adapter.node(sortHit) ~= nil).toBe(true)
		local razzYBefore = adapter.node(rowHitPath(0, "razz")).rect.y
		adapter.tap(sortHit, { pointer = "mouse" })
		pres.refresh()
		expect(sortOrder:get().column).toBe("laps")
		expect(sortOrder:get().ascending).toBe(true)
		expect(adapter.node("/S/Racers/Main/Header/Head-laps/SortMark").props.text).toBe("▲")
		adapter.tap(sortHit, { pointer = "mouse" })
		pres.refresh()
		expect(sortOrder:get().ascending).toBe(false)
		expect(adapter.node("/S/Racers/Main/Header/Head-laps/SortMark").props.text).toBe("▼")
		-- The DATA OWNER applies the sort — rows untouched
		expect(adapter.node(rowHitPath(0, "razz")).rect.y).toBe(razzYBefore)
		-- non-sortable columns expose no sort hit
		expect(adapter.node("/S/Racers/Main/Header/Head-name/Column")).toBe(nil)
		-- INVERTED (ui_todo §0; artifacts/input-adaptation-audit/wp-b-composites.md
		-- header-sort keyboard/gamepad = MISSING): this line USED to assert the
		-- sort hit stayed OUT of the focus ring (focus == razz), encoding the
		-- pre-§0 "sort is pointer-only" design. §0 overruled that — every
		-- interactive surface needs a focus + Activate story on every input — so
		-- the sort hit is now focusable. In this legacy FLAT-ring harness
		-- (navigationGroups=false) it is the first focusable in document order
		-- (header precedes the body), so initial focus lands on it. The grouped
		-- "headers" NavigationGroup path is proven device-true in table_input.spec.
		expect(pres.focus.focused:get()).toBe(sortHit)
	end)
end)

describe("Table: row gaps (director round 4 — cards must not touch)", function()
	it("rowGap spaces the cards and the drop indicator lands mid-gap", function()
		local reorders: { any } = {}
		local _, adapter, pres = world({
			header = false,
			rowGap = 4,
			reorderable = true,
			onReorder = function(keys, toIndex)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
			end,
		})
		-- rows at 40px + 4px gaps: razz 0, bolt 44, josh 88
		expect(adapter.node(rowHitPath(0, "razz")).rect.y).toBe(0)
		expect(adapter.node(rowHitPath(0, "bolt")).rect.y).toBe(44)
		expect(adapter.node(rowHitPath(0, "josh")).rect.y).toBe(88)
		-- drag razz below bolt's midpoint (44+20=64): slot 2 full-list,
		-- indicator centered in the gap after bolt (44+40+2 = 86)
		adapter.pointerDown(rowHitPath(0, "razz"), 100, 20)
		adapter.pointerMove(100, 70)
		pres.refresh()
		expect(adapter.node("/S/Racers/DropWhen/then/DropLine").rect.y).toBe(86)
		adapter.pointerUp(100, 70)
		expect(reorders[1].keys[1]).toBe("razz")
		expect(reorders[1].toIndex).toBe(1)
	end)
end)

describe("Table: row drag-and-drop (Phase B)", function()
	local function dragWorld()
		local reorders: { any } = {}
		local core, adapter, pres, tbl, rows, handle, system = world({
			header = false,
			reorderable = true,
			onReorder = function(keys: { string }, toIndex: number)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
			end,
			dragLabel = function(item: any)
				return item.name
			end,
		})
		return reorders, adapter, pres, tbl, rows, system, core
	end

	it("a drag shows ghost + indicator with the row IN PLACE; drop converts to post-removal slots", function()
		-- director 2026-07-20 round 2: do NOT remove the row while dragging
		-- (the table jump read badly) — the ghost chip + drop line carry the
		-- "picked up" read; the row stays until the drop commits
		local reorders, adapter, pres, _, _, _, core = dragWorld()
		local baseline = core:counters()
		local razzPath = rowHitPath(0, "razz")
		adapter.pointerDown(razzPath, 100, 20)
		adapter.pointerMove(100, 24) -- below the drag threshold
		pres.refresh()
		expect(adapter.node("/S/Racers/DropWhen/then/DropLine")).toBe(nil)
		adapter.pointerMove(100, 90)
		pres.refresh()
		-- the origin row STAYS in the flow
		expect(adapter.node(razzPath) ~= nil).toBe(true)
		expect(adapter.node(rowHitPath(0, "bolt")).rect.y).toBe(40)
		-- ghost + indicator present; y=90 sits past razz(20) and bolt(60) mids
		-- single-row drag: exactly one chip, label on the front chip
		expect(adapter.node("/S/Racers/GhostWhen/then/DragGhost/Chip1/Label").props.text).toBe("Razz Raccoon")
		expect(adapter.node("/S/Racers/GhostWhen/then/DragGhost/Chip2")).toBe(nil)
		expect(adapter.node("/S/Racers/DropWhen/then/DropLine").rect.y).toBe(80)
		adapter.pointerUp(100, 90)
		pres.refresh()
		expect(#reorders).toBe(1)
		expect(#reorders[1].keys).toBe(1)
		expect(reorders[1].keys[1]).toBe("razz")
		-- full-list slot 2 converts to post-removal slot 1 (bolt, razz, josh)
		expect(reorders[1].toIndex).toBe(1)
		expect(adapter.node("/S/Racers/GhostWhen/then/DragGhost")).toBe(nil)
		expect(adapter.node("/S/Racers/DropWhen/then/DropLine")).toBe(nil)
		pres.refresh()
		local after = core:counters()
		for k, v in baseline :: any do
			expect((after :: any)[k]).toBe(v)
		end
	end)

	it("dragging a selected row drags the WHOLE selection as a block (director example)", function()
		-- rows r1..r5; select r1, r3, r5; drag on r3; drop after current r2
		-- -> onReorder({r1, r3, r5}, 1): remaining 2,4 with the block after 2
		-- -> consumer order 2,1,3,5,4
		local reorders: { any } = {}
		local five = {
			{ id = "r1", name = "One", laps = 1 },
			{ id = "r2", name = "Two", laps = 2 },
			{ id = "r3", name = "Three", laps = 3 },
			{ id = "r4", name = "Four", laps = 4 },
			{ id = "r5", name = "Five", laps = 5 },
		}
		local _, adapter, pres, tbl = world({
			header = false,
			selection = "multi",
			rowsOverride = five,
			reorderable = true,
			onReorder = function(keys: { string }, toIndex: number)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
			end,
			dragLabel = function(item: any)
				return item.name
			end,
		})
		local function hit(key: string): string
			return `/S/Racers/Main/Body/Rows/[{key}@0]/Row/Hit`
		end
		adapter.tap(hit("r1"), { pointer = "mouse" })
		adapter.tap(hit("r3"), { pointer = "mouse", toggle = true })
		adapter.tap(hit("r5"), { pointer = "mouse", toggle = true })
		pres.refresh()
		-- drag on r3 (selected): the whole selection lifts together
		adapter.pointerDown(hit("r3"), 100, 100) -- r3 spans 80..120
		adapter.pointerMove(100, 70) -- between r2's mid (60) and r3's (100)
		pres.refresh()
		-- ghost shows a chip STACK: up to 3 chips offset (0,0)/(2,2)/(4,4),
		-- front chip carries the label (no "+N" text)
		local chip1 = adapter.node("/S/Racers/GhostWhen/then/DragGhost/Chip1")
		local chip2 = adapter.node("/S/Racers/GhostWhen/then/DragGhost/Chip2")
		local chip3 = adapter.node("/S/Racers/GhostWhen/then/DragGhost/Chip3")
		expect(chip1 ~= nil and chip2 ~= nil and chip3 ~= nil).toBe(true)
		-- chips carry the outlined "chip" surface so the stack reads cleanly
		expect(chip1.props.surface).toBe("chip")
		expect(chip3.props.surface).toBe("chip")
		expect(adapter.node("/S/Racers/GhostWhen/then/DragGhost/Chip1/Label").props.text).toBe("Three")
		-- THE SAME 2 px STEP ON BOTH AXES (2026-08-15). X always stepped 2; Y only
		-- appeared to, because each chip's `alignV = "center"` — written to center
		-- its LABEL — was read by the DragGhost stack as the chip's own placement,
		-- and centring-in-the-full-box-then-displacing happened to land on 2 as
		-- well. Once `arrange` started spending margins honestly that route stepped
		-- 1 and the deck read as a smear; the word now lives on the Label, where it
		-- means one thing. `docs/lessons/one-word-two-subsystems.md`.
		expect(chip2.rect.x).toBe(chip1.rect.x + 2)
		expect(chip2.rect.y).toBe(chip1.rect.y + 2)
		expect(chip3.rect.x).toBe(chip1.rect.x + 4)
		expect(chip3.rect.y).toBe(chip1.rect.y + 4)
		-- and the label is still centred in the chip that carries it
		local label = adapter.node("/S/Racers/GhostWhen/then/DragGhost/Chip1/Label").rect
		expect(math.abs((label.y - chip1.rect.y) - ((chip1.rect.y + chip1.rect.h) - (label.y + label.h))) <= 1).toBe(
			true
		)
		-- the FRONT chip paints on top (deterministic z: later walk = higher z)
		expect(chip1.z > chip2.z and chip2.z > chip3.z).toBe(true)
		adapter.pointerUp(100, 70)
		pres.refresh()
		expect(#reorders).toBe(1)
		expect(#reorders[1].keys).toBe(3)
		expect(reorders[1].keys[1]).toBe("r1") -- document order, not click order
		expect(reorders[1].keys[2]).toBe("r3")
		expect(reorders[1].keys[3]).toBe("r5")
		expect(reorders[1].toIndex).toBe(1) -- one remaining row (r2) above
	end)

	it("a five-row group still shows at most three chips", function()
		local reorders: { any } = {}
		local five = {
			{ id = "r1", name = "One", laps = 1 },
			{ id = "r2", name = "Two", laps = 2 },
			{ id = "r3", name = "Three", laps = 3 },
			{ id = "r4", name = "Four", laps = 4 },
			{ id = "r5", name = "Five", laps = 5 },
		}
		local _, adapter, pres, tbl = world({
			header = false,
			selection = "multi",
			rowsOverride = five,
			reorderable = true,
			onReorder = function(keys: { string }, toIndex: number)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
			end,
			dragLabel = function(item: any)
				return item.name
			end,
		})
		local function hit(key: string): string
			return `/S/Racers/Main/Body/Rows/[{key}@0]/Row/Hit`
		end
		for _, key in { "r1", "r2", "r3", "r4", "r5" } do
			adapter.tap(hit(key), { pointer = "mouse", toggle = true })
		end
		pres.refresh()
		adapter.pointerDown(hit("r3"), 100, 100)
		adapter.pointerMove(100, 130)
		pres.refresh()
		expect(adapter.node("/S/Racers/GhostWhen/then/DragGhost/Chip3") ~= nil).toBe(true)
		expect(adapter.node("/S/Racers/GhostWhen/then/DragGhost/Chip4")).toBe(nil)
		adapter.pointerUp(900, 130) -- off-table: abort
	end)

	it("dragging an UNSELECTED row drags only that row", function()
		local reorders, adapter, pres, tbl = dragWorld()
		adapter.tap(rowHitPath(0, "josh"), { pointer = "mouse" }) -- select josh
		pres.refresh()
		adapter.pointerDown(rowHitPath(0, "razz"), 100, 20) -- drag razz (unselected)
		adapter.pointerMove(100, 90)
		pres.refresh()
		adapter.pointerUp(100, 90)
		expect(#reorders).toBe(1)
		expect(#reorders[1].keys).toBe(1)
		expect(reorders[1].keys[1]).toBe("razz")
		expect(tbl.api.selectedKeys:get().josh).toBe(true) -- selection untouched
	end)

	it("a group drop that reproduces the current order commits nothing", function()
		local reorders, adapter, pres, tbl = dragWorld()
		adapter.tap(rowHitPath(0, "razz"), { pointer = "mouse" })
		adapter.tap(rowHitPath(0, "bolt"), { pointer = "mouse", toggle = true })
		pres.refresh()
		-- dragging the razz+bolt block to the very top is a no-op
		adapter.pointerDown(rowHitPath(0, "razz"), 100, 20)
		adapter.pointerMove(100, 10)
		pres.refresh()
		adapter.pointerUp(100, 10)
		pres.refresh()
		expect(#reorders).toBe(0)
	end)

	it("dropping a row back onto itself commits nothing", function()
		local reorders, adapter, pres = dragWorld()
		adapter.pointerDown(rowHitPath(0, "bolt"), 100, 60)
		adapter.pointerMove(100, 70) -- past the threshold, still within bolt
		pres.refresh()
		adapter.pointerUp(100, 70)
		pres.refresh()
		expect(#reorders).toBe(0)
	end)

	it("a system interrupt (Roblox menu opened) aborts the drag cleanly", function()
		-- director 2026-07-20: Esc opens the CoreGui menu mid-drag and the
		-- drag state got stuck. Escape is engine-reserved (D1) so it cannot
		-- be intercepted — instead ANY pointer capture aborts when the menu
		-- opens (adapter-level, all draggables)
		local reorders, adapter, pres, tbl = dragWorld()
		adapter.pointerDown(rowHitPath(0, "razz"), 100, 20)
		adapter.pointerMove(100, 90)
		pres.refresh()
		expect(adapter.node("/S/Racers/DropWhen/then/DropLine") ~= nil).toBe(true)
		adapter.interruptCapture() -- the menu opened
		pres.refresh()
		pres.refresh()
		expect(adapter.node("/S/Racers/DropWhen/then/DropLine")).toBe(nil)
		expect(adapter.node("/S/Racers/GhostWhen/then/DragGhost")).toBe(nil)
		expect(#reorders).toBe(0)
		-- and the table is fully usable afterwards
		adapter.tap(rowHitPath(0, "bolt"), { pointer = "mouse" })
		pres.refresh()
		expect(tbl.api.selectedKeys:get().bolt).toBe(true)
	end)

	it("an invalid drop (outside the table) commits nothing", function()
		local reorders, adapter, pres = dragWorld()
		local razzPath = rowHitPath(0, "razz")
		adapter.pointerDown(razzPath, 100, 20)
		adapter.pointerMove(100, 90)
		pres.refresh()
		expect(adapter.node(razzPath) ~= nil).toBe(true) -- row stays put
		adapter.pointerUp(900, 90) -- released outside the table root
		pres.refresh()
		expect(#reorders).toBe(0)
		expect(adapter.node("/S/Racers/DropWhen/then/DropLine")).toBe(nil)
	end)

	it("one-step downward drag reports the post-removal insertion slot", function()
		-- full-list mids: razz 20, bolt 60, josh 100; y=115 -> full slot 3 ->
		-- dragged bolt (0-based 1) sits above it -> post-removal slot 2
		local reorders, adapter, pres = dragWorld()
		adapter.pointerDown(rowHitPath(0, "bolt"), 100, 60)
		adapter.pointerMove(100, 115)
		pres.refresh()
		expect(adapter.node("/S/Racers/DropWhen/then/DropLine").rect.y).toBe(120)
		adapter.pointerUp(100, 115)
		expect(reorders[1].keys[1]).toBe("bolt")
		expect(reorders[1].toIndex).toBe(2)
	end)

	it("keyboard: shift+Navigate moves the focused row without moving focus", function()
		local reorders, adapter, pres, tbl, rows, system = dragWorld()
		expect(pres.focus.focused:get()).toBe(rowHitPath(0, "razz"))
		system.deviceKey("LeftShift", true)
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		system.deviceKey("LeftShift", false)
		expect(#reorders).toBe(1)
		expect(reorders[1].keys[1]).toBe("razz")
		expect(reorders[1].toIndex).toBe(1) -- down one: post-removal slot = i
		expect(pres.focus.focused:get()).toBe(rowHitPath(0, "razz"))
		-- plain Navigate still walks focus
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:get()).toBe(rowHitPath(0, "bolt"))
	end)

	it("an impossible shift+Navigate reorder moves NOTHING — not the row, not focus", function()
		-- verifier 2026-07-20 F1: shift+Up on the top row used to fall through
		-- the failed reorder into navigate(), which now WRAPS — teleporting
		-- focus to the bottom. Shift+arrow means "move the row", never focus.
		local reorders, adapter, pres, tbl, rows, system = dragWorld()
		expect(pres.focus.focused:get()).toBe(rowHitPath(0, "razz")) -- top row
		system.deviceKey("LeftShift", true)
		system.deviceKey("Up", true)
		system.deviceKey("Up", false)
		system.deviceKey("LeftShift", false)
		expect(#reorders).toBe(0)
		expect(pres.focus.focused:get()).toBe(rowHitPath(0, "razz")) -- unmoved
	end)

	it("dismissing the screen mid-drag tears the capture down", function()
		-- verifier 2026-07-20 F4: destroyRoot must always end the capture
		local reorders: { any } = {}
		local core, adapter, pres, tbl, rows, handle = world({
			header = false,
			reorderable = true,
			onReorder = function(key: string, toIndex: number)
				table.insert(reorders, { key = key, toIndex = toIndex })
			end,
		})
		adapter.pointerDown(rowHitPath(0, "razz"), 100, 20)
		adapter.pointerMove(100, 90)
		pres.refresh()
		pres.dismiss(handle) -- destroys the root mid-drag
		adapter.pointerUp(100, 90) -- must route nowhere
		expect(#reorders).toBe(0)
	end)

	it("non-reorderable tables ignore row drags entirely", function()
		local _, adapter, pres, tbl = world({ header = false })
		local razzPath = rowHitPath(0, "razz")
		adapter.pointerDown(razzPath, 100, 20)
		adapter.pointerMove(100, 90)
		pres.refresh()
		expect(adapter.node("/S/Racers/DropWhen/then/DropLine")).toBe(nil)
	end)
end)

describe("Table: standard-model focus and selection (director round 2)", function()
	it("clicking a row moves keyboard focus there", function()
		local _, adapter, pres, tbl = world({ selection = "single" })
		expect(pres.focus.focused:get()).toBe("/S/Racers/Main/Header/Head-name/Column")
		adapter.tap(rowHitPath(0, "bolt"), { pointer = "mouse" })
		pres.refresh()
		expect(pres.focus.focused:get()).toBe(rowHitPath(0, "bolt"))
		-- navigation continues from the clicked row
		local _, _, _, _, _, _, system = nil, nil, nil, nil, nil, nil, nil
	end)

	it("arrow navigation moves the SELECTION with focus (the standard table model)", function()
		local _, adapter, pres, tbl, _, _, system = world({ selection = "single" })
		system.deviceKey("Down", true) -- off the column handle onto razz
		system.deviceKey("Down", false)
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		pres.refresh()
		expect(pres.focus.focused:get()).toBe(rowHitPath(0, "bolt"))
		expect(tbl.api.selectedKeys:get().bolt).toBe(true) -- selection followed
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		pres.refresh()
		expect(tbl.api.selectedKeys:get().bolt).toBe(nil) -- replaced
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
	end)

	it("arrow-selection anchors the range: arrow to a later row, shift-click an earlier one", function()
		local _, adapter, pres, tbl, _, _, system = world({ selection = "multi" })
		system.deviceKey("Down", true) -- off the column handle onto razz
		system.deviceKey("Down", false)
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		system.deviceKey("Down", true)
		system.deviceKey("Down", false) -- josh selected + anchored by arrows
		pres.refresh()
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
		adapter.tap(rowHitPath(0, "razz"), { pointer = "mouse", shift = true })
		pres.refresh()
		-- reverse range: prior row up to the anchor
		expect(tbl.api.selectedKeys:get().razz).toBe(true)
		expect(tbl.api.selectedKeys:get().bolt).toBe(true)
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
	end)

	it("shift-clicking from a later row to a prior one range-selects (reversed)", function()
		local _, adapter, pres, tbl = world({ selection = "multi" })
		adapter.tap(rowHitPath(0, "josh"), { pointer = "mouse" }) -- anchor = josh
		adapter.tap(rowHitPath(0, "razz"), { pointer = "mouse", shift = true })
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(true)
		expect(tbl.api.selectedKeys:get().bolt).toBe(true)
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
	end)
end)

describe("Table: modifier selection semantics (Phase B)", function()
	it("plain mouse click replaces a multi selection", function()
		local _, adapter, pres, tbl = world({ selection = "multi" })
		adapter.tap(rowHitPath(0, "razz"))
		adapter.tap(rowHitPath(0, "bolt"))
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(true)
		expect(tbl.api.selectedKeys:get().bolt).toBe(true)
		adapter.tap(rowHitPath(0, "josh"), { pointer = "mouse" })
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(nil)
		expect(tbl.api.selectedKeys:get().bolt).toBe(nil)
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
	end)

	it("ctrl/cmd-click toggles rows in and out of a multi selection", function()
		local _, adapter, pres, tbl = world({ selection = "multi" })
		adapter.tap(rowHitPath(0, "razz"), { pointer = "mouse" })
		adapter.tap(rowHitPath(0, "josh"), { pointer = "mouse", toggle = true })
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(true)
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
		adapter.tap(rowHitPath(0, "razz"), { pointer = "mouse", toggle = true })
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(nil)
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
	end)

	it("shift-click extends a contiguous range from the anchor", function()
		local _, adapter, pres, tbl = world({ selection = "multi" })
		adapter.tap(rowHitPath(0, "razz"), { pointer = "mouse" }) -- anchor
		adapter.tap(rowHitPath(0, "josh"), { pointer = "mouse", shift = true })
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(true)
		expect(tbl.api.selectedKeys:get().bolt).toBe(true) -- between anchor and target
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
		-- a new shift-click re-ranges from the SAME anchor
		adapter.tap(rowHitPath(0, "bolt"), { pointer = "mouse", shift = true })
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(true)
		expect(tbl.api.selectedKeys:get().bolt).toBe(true)
		expect(tbl.api.selectedKeys:get().josh).toBe(nil)
	end)

	it("keyboard Activate honors held modifiers from the action system", function()
		-- standard model: arrows already REPLACE the selection as focus moves
		-- (anchor follows), so keyboard ranges collapse to the focused row —
		-- range extension is pointer territory (shift+arrows = reorder).
		-- The seam to pin: held modifiers reach handleActivate for Return.
		local _, _, pres, tbl, _, _, system = world({ selection = "multi" })
		system.deviceKey("Down", true) -- off the column handle onto razz
		system.deviceKey("Down", false)
		system.deviceKey("Return", true)
		system.deviceKey("Return", false) -- plain: replace-select razz
		expect(tbl.api.selectedKeys:get().razz).toBe(true)
		system.deviceKey("LeftControl", true)
		system.deviceKey("Return", true)
		system.deviceKey("Return", false) -- ctrl: toggle razz back off
		system.deviceKey("LeftControl", false)
		expect(tbl.api.selectedKeys:get().razz).toBe(nil)
	end)

	it("touch taps keep the additive-toggle idiom (no modifier keys on device)", function()
		local _, adapter, pres, tbl = world({ selection = "multi" })
		adapter.tap(rowHitPath(0, "razz"), { pointer = "touch" })
		adapter.tap(rowHitPath(0, "josh"), { pointer = "touch" })
		pres.refresh()
		expect(tbl.api.selectedKeys:get().razz).toBe(true)
		expect(tbl.api.selectedKeys:get().josh).toBe(true)
	end)
end)

describe("Table: column resize interaction (Phase B)", function()
	it("resizable columns render a cursor-hinted grip; fixed columns do not", function()
		local _, adapter = world({})
		local grip = adapter.node("/S/Racers/Main/Header/Head-name/Grip")
		expect(grip ~= nil).toBe(true)
		expect(grip.props.cursorHint).toBe("colResize")
		expect(adapter.node("/S/Racers/Main/Header/Head-laps/Grip")).toBe(nil)
	end)

	it("grip drag previews a guide line and commits the width on release", function()
		local _, adapter, pres = world({})
		local gripPath = "/S/Racers/Main/Header/Head-name/Grip"
		local cellRect = adapter.node("/S/Racers/Main/Header/Head-name").rect
		expect(cellRect.w).toBe(736) -- fill column: 800 viewport - 64 fixed
		adapter.pointerDown(gripPath, cellRect.x + cellRect.w, 10)
		adapter.pointerMove(cellRect.x + cellRect.w - 100, 12)
		pres.refresh()
		local line = adapter.node("/S/Racers/ResizeWhen/then/ResizeLine")
		expect(line ~= nil).toBe(true)
		expect(line.rect.x).toBe(636) -- guide sits at the dragged boundary
		-- preview only: rows still mounted under @0 keys until release
		expect(adapter.node(cellPath(0, "razz", "name")) ~= nil).toBe(true)
		adapter.pointerUp(cellRect.x + cellRect.w - 100, 12)
		pres.refresh()
		expect(adapter.node("/S/Racers/ResizeWhen/then/ResizeLine")).toBe(nil)
		expect(adapter.node(cellPath(1, "razz", "name")).rect.w).toBe(636)
		expect(adapter.node("/S/Racers/Main/Header/Head-name").rect.w).toBe(636)
	end)

	it("focus cycles through the column handle and the rows, and wraps around", function()
		-- hand-test finding 2026-07-20: focus used to reach the resize GRIP (a thin
		-- sliver) and appear lost. The grip is no longer a focus stop at all — the
		-- column's header is (director 2026-07-29) — and it LEADS rather than
		-- trails, because a header precedes its rows.
		local _, _, pres, _, _, _, system = world({})
		expect(pres.focus.focused:get()).toBe("/S/Racers/Main/Header/Head-name/Column")
		for _ = 1, 3 do
			system.deviceKey("Down", true)
			system.deviceKey("Down", false)
		end
		expect(pres.focus.focused:get()).toBe(rowHitPath(0, "josh"))
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:get()).toBe("/S/Racers/Main/Header/Head-name/Column") -- wrapped
		system.deviceKey("Up", true)
		system.deviceKey("Up", false)
		expect(pres.focus.focused:get()).toBe(rowHitPath(0, "josh")) -- and back
	end)

	it("cells inset content from the left and center it vertically; headers read at full contrast", function()
		-- hand-test findings 2026-07-20: header text was unreadable (secondary
		-- tint over the world) and cell content sat flush at the cell origin
		local _, adapter = world({})
		local cellNode = adapter.node(cellPath(0, "razz", "name"))
		local value = adapter.node(cellPath(0, "razz", "name") .. "/Value")
		expect(value.rect.x).toBe(cellNode.rect.x + 8) -- default cellPadding
		-- vertically centered within the row (± rounding)
		local topGap = value.rect.y - cellNode.rect.y
		local bottomGap = (cellNode.rect.y + cellNode.rect.h) - (value.rect.y + value.rect.h)
		expect(math.abs(topGap - bottomGap) <= 1).toBe(true)
		expect(topGap > 0).toBe(true)
		-- header title: no dim role, inset like the cells
		local title = adapter.node("/S/Racers/Main/Header/Head-name/Title")
		expect(title.props.role).toBe(nil)
		expect(title.rect.x).toBe(adapter.node("/S/Racers/Main/Header/Head-name").rect.x + 8)
	end)

	it("gamepad/keyboard: a focused column handle resizes its column via the Adjust action", function()
		local _, adapter, pres, tbl, _, _, system = world({})
		-- the column handle leads the ring; Adjust binds only while it holds focus
		expect(pres.focus.focused:get()).toBe("/S/Racers/Main/Header/Head-name/Column")
		-- keyboard Left: one 16px step narrower, committed through the model
		system.deviceKey("Left", true)
		system.deviceKey("Left", false)
		pres.refresh()
		expect(adapter.node(cellPath(1, "razz", "name")).rect.w).toBe(720)
		expect(adapter.node("/S/Racers/Main/Header/Head-name").rect.w).toBe(720)
		-- gamepad bumper: another step (the virtual cursor ignores MouseIcon,
		-- so this focus+bumper path IS the gamepad resize affordance)
		system.deviceKey("ButtonL1", true)
		system.deviceKey("ButtonL1", false)
		pres.refresh()
		expect(adapter.node(cellPath(2, "razz", "name")).rect.w).toBe(704)
	end)

	it("grip drag clamps to the column minWidth", function()
		local _, adapter, pres = world({})
		local gripPath = "/S/Racers/Main/Header/Head-name/Grip"
		local cellRect = adapter.node("/S/Racers/Main/Header/Head-name").rect
		adapter.pointerDown(gripPath, cellRect.x + cellRect.w, 10)
		adapter.pointerMove(cellRect.x + 10, 12) -- far past the minimum
		pres.refresh()
		adapter.pointerUp(cellRect.x + 10, 12)
		pres.refresh()
		expect(adapter.node(cellPath(1, "razz", "name")).rect.w).toBe(80) -- minWidth
	end)
end)

describe("Table: capture ownership (playlist place defect 2026-07-20)", function()
	it("a second pointer-down on ANOTHER row mid-drag cannot steal the capture; the drop still commits", function()
		-- live-found: dragging across rows fired InputBegan on the row being
		-- crossed, which silently killed the original capture (no cancel
		-- reason), leaving a stuck ghost and no reorder. A live capture OWNS
		-- the pointer until it ends.
		local reorders: { any } = {}
		local _, adapter, pres = world({
			header = false,
			reorderable = true,
			onReorder = function(keys: { string }, toIndex: number)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
			end,
			dragLabel = function(item: any)
				return item.name
			end,
		})
		local razzPath = rowHitPath(0, "razz")
		adapter.pointerDown(razzPath, 100, 20)
		adapter.pointerMove(100, 60) -- past the threshold: drag is live
		pres.refresh()
		expect(adapter.node("/S/Racers/GhostWhen/then/DragGhost") ~= nil).toBe(true)
		-- the pointer crosses ANOTHER row's hit zone: the engine can deliver a
		-- fresh began there — it must be IGNORED while a capture is live
		adapter.pointerDown(rowHitPath(0, "bolt"), 100, 62)
		adapter.pointerMove(100, 90)
		adapter.pointerUp(100, 90)
		pres.refresh()
		expect(#reorders).toBe(1)
		expect(reorders[1].keys[1]).toBe("razz") -- the ORIGINAL drag committed
		expect(adapter.node("/S/Racers/GhostWhen/then/DragGhost")).toBe(nil)
	end)
end)

describe("Table: touch scroll vs edit-mode reorder (director design 2026-07-20)", function()
	local function bigRows(n: number): { any }
		local out = {}
		for i = 1, n do
			table.insert(out, { id = `r{i}`, name = `Row {i}`, laps = i })
		end
		return out
	end
	local function scrollWorld(extra: any?)
		local reorders: { any } = {}
		local spec = {
			header = false,
			rowsOverride = bigRows(20),
			rowHeight = 40,
			height = { type = "fixed", px = 200 }, -- 5 visible of 20
			reorderable = true,
			selection = "none",
			onReorder = function(keys: { string }, toIndex: number)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
			end,
		}
		for k, v in (extra or {}) :: any do
			spec[k] = v
		end
		local core, adapter, pres, tbl, rows, handle, system, env = world(spec)
		return reorders, adapter, pres, tbl, core, env
	end
	local function hit(key: string): string
		return `/S/Racers/Main/Body/Rows/[{key}@0]/Row/Hit`
	end

	it("a touch drag on the row body defers to the native scroll and never reorders", function()
		local reorders, adapter, pres = scrollWorld()
		-- a one-finger touch on the row body DECLINES the pointer capture so the
		-- native ScrollingFrame owns the pan-scroll (native §4); it never starts a
		-- reorder and never lifts a ghost.
		local start = adapter.node(hit("r2")).rect
		adapter.pointerDown(hit("r2"), 100, start.y + 10, "touch")
		adapter.pointerMove(100, start.y - 50, "touch") -- finger moves UP 60
		pres.refresh()
		adapter.pointerUp(100, start.y - 50, "touch")
		pres.refresh()
		expect(#reorders).toBe(0)
		expect(adapter.node("/S/Racers/GhostWhen/then/DragGhost")).toBe(nil)
	end)

	it("the body is a native scroll region: it declares the full content canvas and clips", function()
		local _, adapter = scrollWorld()
		local body = adapter.node("/S/Racers/Main/Body")
		-- the body is a native ScrollingFrame: it clips partial rows and declares
		-- its solved content extent as the scroll canvas (native-substrate NS-A2)
		expect(body.props.clipChildren).toBe(true)
		expect(body.scrollRegion ~= nil).toBe(true)
		expect(body.scrollRegion.axis).toBe("y")
		-- 20 rows x 40px = 800 (the FULL content height, engine wheel-scrolls it)
		expect(body.scrollRegion.contentH).toBe(800)
	end)

	it("rows sit at absolute canvas offsets (the engine translates by CanvasPosition)", function()
		local _, adapter = scrollWorld()
		-- rows flow at their NATURAL document positions inside the scroll host —
		-- no hand-rolled -scrollOffset; a scroll moves CanvasPosition, not the rects
		local body = adapter.node("/S/Racers/Main/Body")
		expect(adapter.node(hit("r1")).rect.y).toBe(body.rect.y)
		expect(adapter.node(hit("r8")).rect.y).toBe(body.rect.y + 7 * 40)
	end)

	it("edit mode shows a LEADING ≡ glyph and insets the cells into a gutter", function()
		local _, adapter, pres, tbl = scrollWorld()
		local cellBefore = adapter.node("/S/Racers/Main/Body/Rows/[r1@0]/Row/Cells/Cell-name").rect.x
		tbl.api.editing:set(true)
		pres.refresh()
		local glyph = adapter.node("/S/Racers/Main/Body/Rows/[r1@0]/Row/EditWhen/then/HandleZone/HandleGlyph")
		expect(glyph ~= nil).toBe(true)
		expect(glyph.props.text).toBe("≡")
		-- the handle gutter is LEADING: cells shift right to clear it
		local cellAfter = adapter.node("/S/Racers/Main/Body/Rows/[r1@0]/Row/Cells/Cell-name").rect.x
		expect(cellAfter).toBe(cellBefore + 32)
		tbl.api.editing:set(false)
		pres.refresh()
		expect(adapter.node("/S/Racers/Main/Body/Rows/[r1@0]/Row/Cells/Cell-name").rect.x).toBe(cellBefore)
	end)

	it("the ≡ handle clears the row CARD, not just the row rect (skinned themes)", function()
		-- Director report 2026-07-28, defect 4: "pixel quest playlist table drag
		-- icon overflows row on the left in edit mode."
		--
		-- Measured live under Pixel Quest: the row rect began at x=16 and the row's
		-- card art (`FacetChromeL1`) at x=28 — a 12px carved border. Every other
		-- element of the row pays that inset: the cells through `cellsEditPadding`,
		-- the header through its own explicit padding. The handle zone did not, so
		-- it sat at the raw row x and the ≡ drew 12px OUTSIDE the card it belongs
		-- to.
		--
		-- The inset is read as a theme METRIC, so this is one assertion over every
		-- package: zero under a flat one (nothing moves) and exactly the carved
		-- border under a skinned one.
		local packages = {
			{ name = "flat", pkg = nil },
			{ name = "pixel_quest", pkg = (require)("../examples/themes/pixel_quest").build(Facet.themes) },
			{ name = "fantasy_ornate", pkg = (require)("../examples/themes/fantasy_ornate").build(Facet.themes) },
			{ name = "glossy_touch", pkg = (require)("../examples/themes/glossy_touch").build(Facet.themes) },
		}
		for _, config in packages do
			local _, adapter, pres, tbl, _, env = scrollWorld()
			local inset = 0
			if config.pkg ~= nil then
				local snap = snapshot.resolve(config.pkg, nil, {})
				env:set("themeMetrics", snap)
				inset = snap.chromeInsets.selection.left
			end
			tbl.api.editing:set(true)
			pres.refresh()
			local row = adapter.node("/S/Racers/Main/Body/Rows/[r1@0]/Row").rect
			local zone = adapter.node("/S/Racers/Main/Body/Rows/[r1@0]/Row/EditWhen/then/HandleZone").rect
			expect(`{config.name}: zone starts at +{zone.x - row.x}, card at +{inset}`).toBe(
				`{config.name}: zone starts at +{inset}, card at +{inset}`
			)
			-- ...and the cells clear the handle AND the card, not one instead of
			-- the other: the gutter used to REPLACE the art inset rather than stack
			-- on it, so under a skinned package the first cell was under-inset too
			local cell = adapter.node("/S/Racers/Main/Body/Rows/[r1@0]/Row/Cells/Cell-name").rect
			expect(`{config.name}: cell at +{cell.x - row.x}`).toBe(`{config.name}: cell at +{inset + 32}`)
		end
	end)

	it("engine double-dispatch: the row body DECLINES gutter touches so the handle wins either order", function()
		-- the engine fires InputBegan on EVERY element under the point; if the
		-- row hit receives it before the grip, the old ownership rule locked
		-- the gesture as a pan and the handle drag never started (live-found:
		-- edit-mode drop did not reorder)
		local reorders, adapter, pres, tbl = scrollWorld()
		tbl.api.editing:set(true)
		pres.refresh()
		local handlePath = "/S/Racers/Main/Body/Rows/[r1@0]/Row/EditWhen/then/HandleZone/Handle"
		local handleRect = adapter.node(handlePath).rect
		-- engine order A: hit first, then grip — the hit must decline
		adapter.pointerDown(hit("r1"), handleRect.x + 5, handleRect.y + 5, "touch")
		adapter.pointerDown(handlePath, handleRect.x + 5, handleRect.y + 5, "touch")
		adapter.pointerMove(handleRect.x + 5, handleRect.y + 65, "touch")
		pres.refresh()
		adapter.pointerUp(handleRect.x + 5, handleRect.y + 65, "touch")
		pres.refresh()
		expect(#reorders).toBe(1)
		expect(reorders[1].keys[1]).toBe("r1")
		-- and a touch OUTSIDE the gutter also defers to the native scroll (the row
		-- hit declines every touch now; only the ≡ handle reorders on touch)
		local rowRect = adapter.node(hit("r2")).rect
		adapter.pointerDown(hit("r2"), rowRect.x + 200, rowRect.y + 5, "touch")
		adapter.pointerMove(rowRect.x + 200, rowRect.y - 55, "touch")
		pres.refresh()
		adapter.pointerUp(rowRect.x + 200, rowRect.y - 55, "touch")
		expect(#reorders).toBe(1) -- unchanged: a body touch never reorders
	end)

	it("mobile multi-reorder: tap-select rows, then a handle drag moves the WHOLE selection", function()
		local reorders, adapter, pres, tbl = scrollWorld({ selection = "multi" })
		tbl.api.editing:set(true)
		pres.refresh()
		-- tap-select r1 and r3 (touch taps = zero-length pans + Activated)
		tbl.api.handleActivate(hit("r1"), nil)
		tbl.api.handleActivate(hit("r3"), nil)
		pres.refresh()
		local handlePath = "/S/Racers/Main/Body/Rows/[r1@0]/Row/EditWhen/then/HandleZone/Handle"
		local handleRect = adapter.node(handlePath).rect
		adapter.pointerDown(handlePath, handleRect.x + 5, handleRect.y + 5, "touch")
		adapter.pointerMove(handleRect.x + 5, handleRect.y + 175, "touch")
		pres.refresh()
		adapter.pointerUp(handleRect.x + 5, handleRect.y + 175, "touch")
		pres.refresh()
		expect(#reorders).toBe(1)
		expect(#reorders[1].keys).toBe(2) -- the selected BLOCK moved
		expect(reorders[1].keys[1]).toBe("r1")
		expect(reorders[1].keys[2]).toBe("r3")
	end)

	it("edit mode grows a trailing handle per row; a TOUCH drag on the handle reorders", function()
		local reorders, adapter, pres, tbl = scrollWorld()
		local handlePath = "/S/Racers/Main/Body/Rows/[r1@0]/Row/EditWhen/then/HandleZone/Handle"
		expect(adapter.node(handlePath)).toBe(nil) -- not editing yet
		tbl.api.editing:set(true)
		pres.refresh()
		expect(adapter.node(handlePath) ~= nil).toBe(true)
		local handleRect = adapter.node(handlePath).rect
		adapter.pointerDown(handlePath, handleRect.x + 5, handleRect.y + 5, "touch")
		adapter.pointerMove(handleRect.x + 5, handleRect.y + 65, "touch")
		pres.refresh()
		adapter.pointerUp(handleRect.x + 5, handleRect.y + 65, "touch")
		pres.refresh()
		expect(#reorders).toBe(1)
		expect(reorders[1].keys[1]).toBe("r1")
	end)

	it("a touch drag on the row body while editing defers to native scroll (handle-only reorder)", function()
		local reorders, adapter, pres, tbl = scrollWorld()
		tbl.api.editing:set(true)
		pres.refresh()
		-- while editing, a touch on the row BODY still declines to the native
		-- scroll — only the ≡ handle reorders on touch (native §4)
		local start = adapter.node(hit("r2")).rect
		adapter.pointerDown(hit("r2"), 100, start.y + 10, "touch")
		adapter.pointerMove(100, start.y - 50, "touch")
		pres.refresh()
		adapter.pointerUp(100, start.y - 50, "touch")
		pres.refresh()
		expect(#reorders).toBe(0)
	end)

	it("a MOUSE drag on the row body still reorders directly (desktop idiom)", function()
		local reorders, adapter, pres = scrollWorld()
		local start = adapter.node(hit("r1")).rect
		adapter.pointerDown(hit("r1"), 100, start.y + 5, "mouse")
		adapter.pointerMove(100, start.y + 75, "mouse")
		pres.refresh()
		adapter.pointerUp(100, start.y + 75, "mouse")
		pres.refresh()
		expect(#reorders).toBe(1)
	end)

	it("auto Edit/Done toggle: shown for touch input, hidden for mouse, toggles the handles", function()
		local _, adapter, pres, tbl, _, env = scrollWorld({ header = true, passEnv = true })
		local togglePath = "/S/Racers/Main/ToggleWhen/then/Toolbar/EditToggle"
		-- env defaults to KeyboardAndMouse: no toggle
		expect(adapter.node(togglePath)).toBe(nil)
		env:set("preferredInput", "Touch")
		pres.refresh()
		expect(adapter.node(togglePath) ~= nil).toBe(true)
		expect(adapter.node(togglePath).props.label).toBe("Edit")
		tbl.api.handleActivate(togglePath, nil)
		pres.refresh()
		expect(adapter.node(togglePath).props.label).toBe("Done")
		expect(adapter.node("/S/Racers/Main/Body/Rows/[r1@0]/Row/EditWhen/then/HandleZone/Handle") ~= nil).toBe(true)
	end)

	-- REGRESSION (director live repro 2026-07-21, example 02): a physical
	-- gamepad session where UserInputService.PreferredInput never leaves
	-- KeyboardAndMouse (mouse was the last-used device — e.g. clicking Play)
	-- must STILL surface the Edit affordance. Affordances derive from the LIVE
	-- capability set + preferredInput, never preferredInput alone (ADR-0015).
	it(
		"auto Edit/Done toggle: shown when a gamepad capability is live even though preferredInput stays KeyboardAndMouse",
		function()
			local _, adapter, pres, _, _, env = scrollWorld({ header = true, passEnv = true })
			local togglePath = "/S/Racers/Main/ToggleWhen/then/Toolbar/EditToggle"
			expect(adapter.node(togglePath)).toBe(nil)
			-- the pad connects mid-session; preferredInput does NOT flip
			env:set("capabilities", { keyboard = true, mouse = true, touch = false, gamepad = true })
			pres.refresh()
			expect(adapter.node(togglePath) ~= nil).toBe(true)
			-- the pad disconnects again: back to a pure mouse world, toggle leaves
			env:set("capabilities", { keyboard = true, mouse = true, touch = false, gamepad = false })
			pres.refresh()
			expect(adapter.node(togglePath)).toBe(nil)
		end
	)

	it(
		"auto Edit/Done toggle: a live touch capability shows it under a KeyboardAndMouse preferredInput (hybrid handheld)",
		function()
			local _, adapter, pres, _, _, env = scrollWorld({ header = true, passEnv = true })
			local togglePath = "/S/Racers/Main/ToggleWhen/then/Toolbar/EditToggle"
			env:set("capabilities", { keyboard = true, mouse = true, touch = true, gamepad = false })
			pres.refresh()
			expect(adapter.node(togglePath) ~= nil).toBe(true)
		end
	)
end)

describe("Table: gamepad support (director 2026-07-20 — every input, every control)", function()
	local function bigRows(n: number): { any }
		local out = {}
		for i = 1, n do
			table.insert(out, { id = `r{i}`, name = `Row {i}`, laps = i })
		end
		return out
	end
	local function padWorld(extra: any?)
		local reorders: { any } = {}
		local rowsRef: any = nil
		local spec = {
			header = false,
			rowsOverride = bigRows(5),
			rowHeight = 40,
			reorderable = true,
			selection = "multi",
			passEnv = true,
			-- a REAL consumer: record AND apply the post-removal splice
			onReorder = function(keys: { string }, toIndex: number)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
				local movingSet: { [string]: boolean } = {}
				for _, key in keys do
					movingSet[key] = true
				end
				local moving, staying = {}, {}
				for _, item in rowsRef:get() do
					table.insert(if movingSet[item.id] then moving else staying, item)
				end
				local out = {}
				for i = 1, toIndex do
					table.insert(out, staying[i])
				end
				for _, item in moving do
					table.insert(out, item)
				end
				for i = toIndex + 1, #staying do
					table.insert(out, staying[i])
				end
				rowsRef:set(out)
			end,
		}
		for k, v in (extra or {}) :: any do
			spec[k] = v
		end
		local core, adapter, pres, tbl, rows, handle, system, env = world(spec)
		rowsRef = rows
		return reorders, adapter, pres, tbl, rows, handle, env, core
	end
	local function hit(key: string): string
		return `/S/Racers/Main/Body/Rows/[{key}@0]/Row/Hit`
	end

	it("buildFocusGroups maps the toggle plus one horizontal group per row, in document order", function()
		local _, _, pres, tbl, _, handle, env = padWorld()
		env:set("preferredInput", "Gamepad")
		pres.refresh()
		local groups = tbl.api.buildFocusGroups(handle.root.node)
		expect(#groups).toBe(6) -- Edit toggle + 5 rows
		expect(string.find(groups[1].order[1], "EditToggle") ~= nil).toBe(true)
		expect(groups[2].axis).toBe("horizontal")
		expect(groups[2].order[1]).toBe(hit("r1"))
		expect(groups[6].order[1]).toBe(hit("r5"))
		-- without the toggle mounted (mouse env), only the row groups remain
		env:set("preferredInput", "KeyboardAndMouse")
		pres.refresh()
		expect(#tbl.api.buildFocusGroups(handle.root.node)).toBe(5)
	end)

	it("A-button (action) grab: grab, d-pad step-move, drop; focus path survives; visuals show grabbed", function()
		local reorders, adapter, pres, tbl, rows = padWorld()
		tbl.api.editing:set(true)
		pres.refresh()
		-- gamepad activate = action source
		tbl.api.handleActivate(hit("r2"), { source = "action" })
		expect(tbl.api.grabbedKey:get()).toBe("r2")
		pres.refresh()
		expect(adapter.node(hit("r2")).props.selected).toBe(true) -- grabbed visual
		-- d-pad down: the grabbed row moves one slot; the move is CONSUMED
		expect(tbl.api.handleGrabNavigate("down")).toBe(true)
		local order = {}
		for _, item in rows:get() do
			table.insert(order, item.id)
		end
		expect(order[2]).toBe("r3") -- r2 stepped below r3
		expect(order[3]).toBe("r2")
		expect(tbl.api.handleGrabNavigate("up")).toBe(true)
		local back = {}
		for _, item in rows:get() do
			table.insert(back, item.id)
		end
		expect(back[2]).toBe("r2") -- stepped back
		-- drop with A again
		tbl.api.handleActivate(hit("r2"), { source = "action" })
		expect(tbl.api.grabbedKey:get()).toBeNil()
		expect(tbl.api.handleGrabNavigate("down")).toBe(false) -- nothing grabbed
		-- grab is edit-mode only: leaving edit clears it
		tbl.api.handleActivate(hit("r2"), { source = "action" })
		expect(tbl.api.grabbedKey:get()).toBe("r2")
		tbl.api.editing:set(false)
		expect(tbl.api.grabbedKey:get()).toBeNil()
		local _ = reorders
	end)

	it("focus moves anywhere INSIDE a row (stars included) re-select that row (standard model)", function()
		local _, adapter, pres, tbl = padWorld()
		pres.refresh()
		tbl.api.handleActivate(hit("r1"), { pointer = "mouse" })
		pres.refresh()
		expect(adapter.node(hit("r1")).props.selected).toBe(true)
		-- focus lands on a cell DESCENDANT of r2 (not the hit): selection follows
		tbl.api.handleFocusMoved("/S/Racers/Main/Body/Rows/[r2@0]/Row/Cells/Cell-name/Value")
		pres.refresh()
		expect(adapter.node(hit("r2")).props.selected).toBe(true)
		expect(adapter.node(hit("r1")).props.selected).toBe(false) -- replace-select
		-- non-row paths (the Edit toggle) leave selection untouched
		tbl.api.handleFocusMoved("/S/Racers/Main/ToggleWhen/then/Toolbar/EditToggle")
		pres.refresh()
		expect(adapter.node(hit("r2")).props.selected).toBe(true)
	end)

	it("a grabbed SELECTED row steps the whole selection block", function()
		local _, _, pres, tbl, rows = padWorld()
		tbl.api.editing:set(true)
		pres.refresh()
		-- pointer taps still select in edit mode (mouse/touch meta)
		tbl.api.handleActivate(hit("r1"), { pointer = "mouse" })
		tbl.api.handleActivate(hit("r3"), { pointer = "mouse", toggle = true })
		tbl.api.handleActivate(hit("r1"), { source = "action" }) -- grab r1 (selected)
		expect(tbl.api.grabbedKey:get()).toBe("r1")
		expect(tbl.api.handleGrabNavigate("down")).toBe(true)
		local order = {}
		for _, item in rows:get() do
			table.insert(order, item.id)
		end
		-- block {r1,r3} inserted after r2: r2, r1, r3, r4, r5
		expect(order[1]).toBe("r2")
		expect(order[2]).toBe("r1")
		expect(order[3]).toBe("r3")
	end)
end)

-- ===========================================================================
-- THE ROW'S ART RESERVES ROOM AND THE CELLS HONOUR IT
-- (director round 10, found live 2026-07-26 on a phone)
--
-- A row is a full-bleed hit Button with the cell stack as its SIBLING — it has
-- to be, because a Button's content may hold no focusable and a rating cell is
-- five of them. That shape is fine for input and was wrong for paint: the
-- renderer adds a slot's `chromeInsets` to the padding of the node that CARRIES
-- the slot, and that node (the hit button) has no children, so the reservation
-- was inert. Cells then laid out against the row's raw rect while the theme
-- painted its selection card INSIDE that rect, so under Glossy Touch, Pixel
-- Quest and Compact Pointer the first cell's text started outside the card it
-- was meant to sit in, and Compact's last column ran off the other end.
-- ===========================================================================
describe("table rows sit inside the theme's own selection card", function()
	local themes = Facet.themes

	local function cellXUnder(pkgModule: any?): (number, number)
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 320, h = 640 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local rows = core:signal(RACERS)
		local tbl = table_control.build(Facet, core, {
			id = "T",
			columns = {
				{ id = "name", title = "Name", width = { type = "fill", weight = 1 } },
				{ id = "laps", title = "Laps", width = { type = "fixed", px = 64 } },
			},
			rows = rows,
			key = function(item)
				return item.id
			end,
			cellFor = function(columnId, item)
				return Facet.UI.Text({
					id = "Value",
					text = if columnId == "name" then item.name else tostring(item.laps),
					textSize = 16,
				})
			end,
			rowHeight = 48,
			header = true,
			selection = "multi",
		})
		pres.present(Facet.UI.Screen({ id = "S", padding = 16, children = { tbl.blueprint } }))
		pres.refresh()
		if pkgModule ~= nil then
			env:set("themeMetrics", themes.resolve(pkgModule, nil, {}))
			pres.refresh()
		end
		return adapter.node("/S/T/Main/Body/Rows/[razz@0]/Row/Cells/Cell-name").rect.x,
			adapter.node("/S/T/Main/Header/Head-name").rect.x
	end

	it("a flat package does not move a single pixel", function()
		local cell, head = cellXUnder(nil)
		expect(cell).toBe(16) -- the screen's own padding, and nothing else
		expect(head).toBe(16)
	end)

	it("a skinning package insets the cells by what its card reserves PLUS its glow gutter", function()
		-- Two gutters at two nesting levels, and the rows pay both (2026-07-27):
		-- the rows' viewport is a clipping ScrollView, so it insets its content by
		-- the package's `chromeBleed` or the shadow is cut at its edge; then each
		-- row's own card reserves its carved border inside that. A package with no
		-- shadow has bleed 0 and this is exactly the old assertion.
		for _, name in { "glossy_touch", "pixel_quest", "compact_pointer" } do
			local pkg = (require)(`../examples/themes/{name}`).build(themes)
			local snap = themes.resolve(pkg, nil, {})
			local reserve = snap.chromeInsets.selection.left
			local bleed = if type(snap.chromeBleed) == "number" then snap.chromeBleed else 0
			expect(reserve > 0).toBe(true) -- these three DO carve a border
			local cell = cellXUnder(pkg)
			expect(cell).toBe(16 + bleed + reserve)
		end
	end)

	it("the header tracks the rows, so the columns never come apart", function()
		for _, name in { "glossy_touch", "pixel_quest", "compact_pointer" } do
			local pkg = (require)(`../examples/themes/{name}`).build(themes)
			local cell, head = cellXUnder(pkg)
			expect(head).toBe(cell)
		end
	end)
end)

-- ===========================================================================
-- WHO OWNS THE SCROLLING (director report 2026-07-27, the playlist example in
-- landscape: "just the table scrolls. really the whole view should scroll, as
-- it's unusable having just the table scroll").
--
-- A table's body is a viewport by default and that is right when the table IS
-- the screen. It is wrong when the table is one block on a page: the title,
-- filter and hint above it took 45-55% of a short landscape viewport and the
-- ONLY thing that could move was the rows, inside whatever was left.
-- ===========================================================================
describe("Table: `scrolls = false` makes it a block for a scrolling host", function()
	local function blockWorld(scrolls: boolean?, w: number, h: number)
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local rows = core:signal(RACERS)
		local tbl = table_control.build(Facet, core, {
			id = "Racers",
			env = env,
			scrolls = scrolls,
			rowHeight = 48,
			header = true,
			columns = { { id = "name", title = "Racer", width = { type = "fill", weight = 1 } } },
			rows = rows,
			key = function(item)
				return item.id
			end,
			cellFor = function(_columnId, item)
				return Facet.UI.Text({ id = "Value", text = item.name, textSize = 15 })
			end,
		})
		pres.present(Facet.UI.Screen({
			id = "S",
			padding = 8,
			children = {
				Facet.UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = 8,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						Facet.UI.Text({ id = "Title", text = "Racers", textSize = 24 }),
						tbl.blueprint,
					},
				}),
			},
		}))
		pres.refresh()
		return adapter
	end

	local function scrollers(adapter: any): { string }
		local out = {}
		for _, path in adapter.paths() do
			local n = adapter.node(path)
			if n ~= nil and n.scrollRegion ~= nil then
				table.insert(out, path)
			end
		end
		return out
	end

	it("as a BLOCK there is exactly ONE scroller, and it is the host's page", function()
		-- nesting a scroller inside a scrolling page makes a vertical drag over the
		-- rows ambiguous, and the inner one always wins — which is the defect
		local found = scrollers(blockWorld(false, 844, 390))
		expect(#found).toBe(1)
		expect(found[1]).toBe("/S/Page")
	end)

	it("...and the page's canvas carries the WHOLE view, header included", function()
		-- 160px tall: shorter than this fixture's three 48px rows plus a header and
		-- a title, which is the landscape case the report came from
		local adapter = blockWorld(false, 844, 160)
		local page = adapter.node("/S/Page")
		-- more content than box = the page is what scrolls, and the title above the
		-- table scrolls away with the rows
		expect(page.scrollRegion.contentH > page.rect.h).toBe(true)
		expect(adapter.node("/S/Page/Title") ~= nil).toBe(true)
	end)

	it("every row is laid out rather than clipped to a window", function()
		local adapter = blockWorld(false, 844, 390)
		for _, racer in RACERS do
			expect(adapter.node(`/S/Page/Racers/Main/Body/Rows/[{racer.id}@0]/Row`) ~= nil).toBe(true)
		end
	end)

	it("the DEFAULT is unchanged: the table still owns its own viewport", function()
		local found = scrollers(blockWorld(nil, 844, 390))
		local hasBody = false
		for _, p in found do
			if string.find(p, "/Racers/Main/Body", 1, true) ~= nil then
				hasBody = true
			end
		end
		expect(hasBody).toBe(true)
	end)
end)

describe("Table column disclosure (Step 8.5 LT-G2)", function()
	-- the default `value` cell and the header title are Texts the TABLE authors;
	-- a column's `disclose = true` is the consumer's only way to declare their
	-- identity strings disclosable (a custom `cell` declares its own)
	local LONG = "Maximiliana-Wilhelmina Rennfahrerin-Steuerbord III"

	local function discloseWorld(disclose: boolean?)
		return world({
			columns = {
				{
					id = "name",
					title = "Racer",
					width = { type = "fixed", px = 120 },
					value = function(item: any)
						return if item.id == "razz" then LONG else item.name
					end,
					disclose = disclose,
				},
				{
					id = "laps",
					title = "Laps",
					width = { type = "fixed", px = 64 },
					value = function(item: any)
						return tostring(item.laps)
					end,
				},
			},
			header = true,
		})
	end

	it("a disclosing column stamps disclose on its value cells AND its header title", function()
		-- construction-only props never reach the adapter; the solve's textFacts
		-- are the observable channel (the same one the presenter's plate reads)
		local _, _, _, _, _, handle = discloseWorld(true)
		local cell = handle.controller.textAt("/S/Racers/Main/Body/Rows/[razz@0]/Row/Cells/Cell-name/Value")
		expect(cell ~= nil).toBe(true)
		expect((cell :: any).disclose).toBe(true)
		expect((cell :: any).truncated).toBe(true) -- the LONG fixture really is cut
		local title = handle.controller.textAt("/S/Racers/Main/Header/Head-name/Title")
		expect(title ~= nil).toBe(true)
		expect((title :: any).disclose).toBe(true)
	end)

	it("...and an ordinary column stamps nothing — the default is byte-identical", function()
		local _, _, _, _, _, handle = discloseWorld(nil)
		local cell = handle.controller.textAt("/S/Racers/Main/Body/Rows/[razz@0]/Row/Cells/Cell-name/Value")
		expect((cell :: any).disclose ~= true).toBe(true)
		local laps = handle.controller.textAt("/S/Racers/Main/Body/Rows/[razz@0]/Row/Cells/Cell-laps/Value")
		expect((laps :: any).disclose ~= true).toBe(true)
	end)

	it("engaging the truncated disclosing cell presents its FULL value through the presenter", function()
		--[[ RE-POINTED 2026-08-19 (ADAPT-20). This used to drive the touch long
			press onto a screen where nothing else had disclosed anything, and assert
			the release took the plate away. Since the FOCUS route reaches a table row
			(the row's `Hit` is the focus stop and the disclosed cell is its sibling —
			`table.luau`'s own `discloseScope`), the first row is already disclosing by
			the time this case runs, and the long press is correctly IDEMPOTENT on a
			plate that is already answering for the same label. Both facts are asserted
			rather than one of them being arranged away. ]]
		local _, adapter, pres, _tbl, _rows, _handle, _system = discloseWorld(true)
		local CELL = "/S/Racers/Main/Body/Rows/[razz@0]/Row/Cells/Cell-name/Value"
		-- FOCUS already answered for it, which is ADAPT-20 and is what makes the
		-- ten-foot combination reachable at all
		expect(pres.disclosure().present).toBe(true)
		expect(pres.disclosure().text).toBe(LONG)
		expect(pres.disclosure().source).toBe("focus")

		-- the long press on the same label is a no-op rather than a second plate
		pres._discloseLongPress(CELL)
		expect(pres.disclosure().present).toBe(true)
		expect(pres.disclosure().text).toBe(LONG)

		-- ...and the TOUCH route stands on its own: move the ring off every
		-- disclosing label, then press and release
		-- `bolt`'s name is short, so the row the ring lands on owes nothing
		pres.focus.focusOn(rowHitPath(0, "bolt"))
		for _ = 1, 40 do
			pres.tick(1 / 60)
			pres.refresh()
		end
		expect(pres.disclosure().present).toBe(false)
		pres._discloseLongPress(CELL)
		local d = pres.disclosure()
		expect(d.present).toBe(true)
		expect(d.text).toBe(LONG)
		expect(d.source).toBe("touch")
		pres._discloseLongPress(nil)
		expect(pres.disclosure().present).toBe(false)
		local _ = adapter
	end)
end)

describe("Table column boundary is strict (architecture review F-4)", function()
	local function build(column: any)
		return table_control.build(Facet, Facet.newCore(), {
			id = "T",
			columns = { column },
			rows = Facet.newCore():signal({}),
			key = function(item: any)
				return item.id
			end,
			rowHeight = 40,
		})
	end

	it(
		"an unknown column key is refused, naming the column — a disclose typo cannot silently drop the guarantee",
		function()
			local ok, err = pcall(function()
				return build({
					id = "name",
					width = { type = "fixed", px = 100 },
					value = function()
						return "x"
					end,
					disclos = true,
				})
			end)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), "disclos") ~= nil).toBe(true)
		end
	)

	it("a non-boolean disclose is refused with the type it got", function()
		local ok, err = pcall(function()
			return build({
				id = "name",
				width = { type = "fixed", px = 100 },
				value = function()
					return "x"
				end,
				disclose = "yes",
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "boolean") ~= nil).toBe(true)
	end)
end)

-- ============================================================================
-- `rowGap` TAKES A THEME METRIC NAME (example-quality-pass, 2026-08-06).
--
-- `cellPadding` has accepted "a number or a theme metric name" since it shipped,
-- because it is only ever handed to a blueprint prop. `rowGap` is ALSO read in
-- Luau — the cumulative row tops, the content extent and the drop slot — so a
-- metric name reached `cum += height + rowGap` and threw "attempt to perform
-- arithmetic on number and string". Found by pointing the playlist example at
-- `controls.table.rowGap` instead of the literal 2 it had been carrying.
--
-- The default is unchanged (0): this widens what the option ACCEPTS, and moves
-- nothing for a caller that passes a number or nothing at all.
-- ============================================================================
describe("Table.rowGap: a number or a theme metric name", function()
	local function gapBetweenFirstTwoRows(rowGap: any): number
		local _, adapter = world({ rowGap = rowGap, header = false })
		local first = adapter.node(rowHitPath(0, RACERS[1].id)).rect
		local second = adapter.node(rowHitPath(0, RACERS[2].id)).rect
		return second.y - (first.y + first.h)
	end

	it("a number behaves exactly as it always has", function()
		expect(gapBetweenFirstTwoRows(6)).toBe(6)
		expect(gapBetweenFirstTwoRows(nil)).toBe(0)
	end)

	it("a SPACING STEP resolves to the theme's own step, not to a crash", function()
		local neutral = snapshot.resolve(Facet.themes.neutralPackage(), nil, {})
		local expected = snapshot.resolveNumber(neutral, "s")
		expect(type(expected)).toBe("number")
		expect(gapBetweenFirstTwoRows("s")).toBe(expected)
	end)

	it("a DOTTED METRIC PATH resolves too — the spelling the playlist example uses", function()
		local neutral = snapshot.resolve(Facet.themes.neutralPackage(), nil, {})
		local expected = snapshot.resolveNumber(neutral, "controls.table.rowGap")
		expect(type(expected)).toBe("number")
		expect(expected > 0).toBe(true)
		expect(gapBetweenFirstTwoRows("controls.table.rowGap")).toBe(expected)
	end)

	it("the DROP SLOT arithmetic uses the resolved pixels, not the name", function()
		-- this is the seam that threw: `insertSlotAt` walks cumulative row tops
		-- and divides the gap in half to centre the drop indicator
		local core, adapter, pres = world({ rowGap = "controls.table.rowGap", reorderable = true, header = false })
		pres.refresh()
		expect(adapter.node(rowHitPath(0, RACERS[2].id)) ~= nil).toBe(true)
		expect(core:lastError()).toBeNil()
	end)

	it("a name that resolves to NOTHING is refused at the authoring boundary, naming it", function()
		-- better than the arithmetic quietly reading 0: the blueprint's `metric`
		-- check owns this ruling and it fires before anything is measured
		local ok, err = pcall(function()
			return gapBetweenFirstTwoRows("controls.table.noSuchMetric")
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "noSuchMetric", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "names no theme metric", 1, true) ~= nil).toBe(true)
	end)
end)

-- =============================================================================
-- THE TABLE'S OWN CHROME STACKS — AT EVERY TEXT PREFERENCE (EQ-6 / LT-F3)
--
-- Device report 2026-08-06, compact phone portrait AND landscape, both reference
-- packages, Largest text: "the edit button overlaps the heading". The header
-- band was a FIXED `controls.table.headerHeight` box (28px). At the Largest
-- preference a ONE-LINE column title measures 34px, so the title painted 6px out
-- of its own ZStack — over the toolbar row above it and the first row below.
--
-- The solver had been reporting it the whole time: `Head-<id>/Title` filed
-- "overflows its zstack by 0x6px ... give the box room — a `minMax` FLOOR rather
-- than a fixed CAP". Nothing FAILED on it, so nobody read it. That is the whole
-- lesson of docs/lessons/the-solver-already-told-you.md, and it is why the first
-- assertion here is the diagnostics list itself.
--
-- The director's framing is the fix: "if height is the issue why can't we make
-- the whole table have more height as text size increases". It can, and now it
-- does — the band floors at the token and grows to the line it must hold, so the
-- header pushes the body down instead of drawing through its neighbours.
--
-- Swept with the auto Edit toggle UP (reorderable + touch + no owner editing
-- signal), because the toolbar is the neighbour the header hit.
-- =============================================================================
describe("Table: toolbar, header and body stack at every text preference", function()
	local PREFERENCES = { 0, 4, 10, 14 }

	-- one real table, solved on a compact phone with the auto toolbar showing;
	-- returns the three band rects plus the solver's own verdict
	local function solveChrome(offset: number, viewport: any): any
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", viewport)
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		env:set("capabilities", { keyboard = false, mouse = false, touch = true, gamepad = false })
		env:set("preferredInput", "Touch")
		env:set("preferredTextOffset", offset)
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)

		local rows = core:signal({ { id = "a", name = "Drift City Nights" }, { id = "b", name = "Neon Overpass" } })
		local tbl = table_control.build(Facet, core, {
			id = "T",
			columns = {
				{
					id = "name",
					title = "Name",
					width = { type = "fill", weight = 1 },
					value = function(i: any)
						return i.name
					end,
				},
				{
					id = "rate",
					title = "Rating",
					width = { type = "fixed", px = 120 },
					value = function()
						return "***"
					end,
				},
			},
			rows = rows,
			key = function(i: any)
				return i.id
			end,
			scrolls = false,
			header = true,
			reorderable = true,
			onReorder = function() end,
			env = env,
		})
		local handle = pres.present(Facet.UI.Screen({ id = "S", padding = 16, children = { tbl.blueprint } }))
		local rectOf = handle.controller.rectOf
		local out = {
			toolbar = rectOf("/S/T/Main/ToggleWhen/then/Toolbar"),
			toggle = rectOf("/S/T/Main/ToggleWhen/then/Toolbar/EditToggle"),
			header = rectOf("/S/T/Main/Header"),
			headName = rectOf("/S/T/Main/Header/Head-name"),
			-- the PAINTED heading, not the band that holds it: the band stacked
			-- correctly all along, and the title drew out of it
			titleName = rectOf("/S/T/Main/Header/Head-name/Title"),
			titleRate = rectOf("/S/T/Main/Header/Head-rate/Title"),
			body = rectOf("/S/T/Main/Body"),
			diagnostics = handle.controller.diagnostics(),
		}
		pres.dismiss(handle)
		tbl.dispose()
		rows:dispose()
		return out
	end

	local VIEWPORTS = {
		{ id = "compact-portrait", rect = { x = 0, y = 0, w = 393, h = 852 } },
		{ id = "compact-landscape", rect = { x = 0, y = 0, w = 852, h = 393 } },
	}

	it("the solver files NO overflow anywhere in the table's chrome, at any preference", function()
		for _, viewport in VIEWPORTS do
			for _, offset in PREFERENCES do
				local r = solveChrome(offset, viewport.rect)
				local found = r.diagnostics or {}
				if #found > 0 then
					local lines = {}
					for _, entry in found :: any do
						table.insert(lines, `  {tostring((entry :: any).node)} :: {tostring((entry :: any).issue)}`)
					end
					error(
						`{viewport.id} @+{offset}: the solver filed {#found} finding(s) against the table's own `
							.. `chrome:\n{table.concat(lines, "\n")}`,
						0
					)
				end
			end
		end
	end)

	it("the toolbar, the header and the body never overlap — the reported defect", function()
		for _, viewport in VIEWPORTS do
			for _, offset in PREFERENCES do
				local r = solveChrome(offset, viewport.rect)
				expect(r.toolbar ~= nil).toBe(true)
				expect(r.header ~= nil).toBe(true)
				expect(r.body ~= nil).toBe(true)
				-- THE PAINTED PAIR, not the two bands. The bands stacked correctly
				-- even while the defect was live — it was the heading TEXT that
				-- drew up out of its band and into the toolbar, so the assertion
				-- has to name the two rects the director actually saw collide.
				local bottomOfToolbar = r.toggle.y + r.toggle.h
				for id, title in { name = r.titleName, rate = r.titleRate } do
					expect(title ~= nil).toBe(true)
					if title.y < bottomOfToolbar then
						error(
							`{viewport.id} @+{offset}: the '{id}' heading (y={title.y} h={title.h}) is painted `
								.. `INSIDE the Edit toggle (y={r.toggle.y} h={r.toggle.h}, bottom={bottomOfToolbar}) `
								.. `— the two overlap by {bottomOfToolbar - title.y}px`,
							0
						)
					end
					if title.y + title.h > r.body.y then
						error(
							`{viewport.id} @+{offset}: the '{id}' heading (y={title.y} h={title.h}) is painted `
								.. `into the first row (body y={r.body.y})`,
							0
						)
					end
				end
				if r.header.y + r.header.h > r.body.y then
					error(
						`{viewport.id} @+{offset}: the header (y={r.header.y} h={r.header.h}) paints into `
							.. `the body (y={r.body.y})`,
						0
					)
				end
			end
		end
	end)

	it("the header band GROWS with the preference instead of holding its token", function()
		local viewport = VIEWPORTS[1].rect
		local plain = solveChrome(0, viewport)
		local largest = solveChrome(14, viewport)
		-- the token is the FLOOR: unchanged at the shipped size...
		expect(plain.header.h).toBe(28)
		-- ...and taller when the text it must hold is taller. Without this the
		-- title overflowed by exactly the difference.
		expect(largest.header.h > plain.header.h).toBe(true)
		-- and the whole table is taller for it, which is the point: the bands
		-- move down together rather than one drawing through another
		expect(largest.body.y > plain.body.y).toBe(true)
	end)
end)

-- ============================================================================
-- Task 10: `spec.rowActions` — Table integration (docs/plans/row-actions-
-- implementation.md). A wrapped row mounts at `.../[key@v]/RowActions-<key>/...`
-- (row_actions.build's own root `id = "RowActions-<rowKey>"`, one `Content` ZStack
-- inside it, THIS row's own blueprint — Hit/Cells/EditWhen, unchanged —
-- mounted inside THAT); an unwrapped row (nil `rowActions`, or the callback
-- returns nil for that item) stays exactly `.../[key@v]/Row/...`, byte-
-- identical to every table before this task (the PERF directive: zero new
-- nodes, zero new subscriptions per row when unused).
describe("Table: row actions (Task 10)", function()
	-- row_actions.build's own root `id = "RowActions-<rowKey>"` (table.luau) —
	-- UNIQUE per row, not the literal "RowActions": two instances sharing one
	-- id corrupted each other's in-flight gesture state (see
	-- `derowActionsPath`'s own comment in table.luau for the live-found repro
	-- this test suite caught it with).
	local function rowActionsRoot(version: number, key: string): string
		return `/S/Racers/Main/Body/Rows/[{key}@{version}]/RowActions-{key}`
	end
	local function wrappedRowHitPath(version: number, key: string): string
		return `{rowActionsRoot(version, key)}/Content/Row/Hit`
	end
	local function trayButtonPath(version: number, key: string, edge: "leading" | "trailing", actionId: string): string
		local tid = if edge == "leading" then "TrayLeading" else "TrayTrailing"
		return `{rowActionsRoot(version, key)}/{tid}When/then/{tid}/Action:{actionId}`
	end
	local function editAffordancePath(version: number, key: string): string
		return `{rowActionsRoot(version, key)}/EditAffordanceWhen/then/EditAffordance`
	end
	local function deleteAction(fired: { string }?, opts: any?): any
		opts = opts or {}
		return {
			id = opts.id or "delete",
			role = opts.role or "destructive",
			label = opts.label or "Delete",
			onAction = function()
				if fired ~= nil then
					table.insert(fired, "fired")
				end
				-- an optional probe run AT the fire, for the one case that has to
				-- ask what the row looked like at that instant rather than at the
				-- end of the tick that contained it
				if opts.onFire ~= nil then
					opts.onFire()
				end
			end,
		}
	end

	-- a SCRIPTED clock (row_actions_input.spec.luau's own `pointerWorld`
	-- pattern) — see `world`'s own comment on `spec.now` for why any test
	-- that drives a real drag-velocity-seeded gesture needs one. `tick`
	-- pairs `pres.tick` (springs) with `pres.refresh()` (syncGeometry — the
	-- ONLY pass that measures a just-revealed tray's live button widths;
	-- pointerWorld's own comment: skipping it leaves `leadingWidth`/
	-- `trailingWidth` frozen at 0 forever).
	local function raWorld(spec: any)
		local clockTime = 0
		spec.now = function()
			return clockTime
		end
		local core, adapter, pres, tbl, rows, handle, system, env = world(spec)
		local function tick(dt: number)
			clockTime += dt
			pres.tick(dt)
			pres.refresh()
		end
		local function settle(frames: number?)
			for _ = 1, frames or 90 do
				tick(1 / 60)
			end
		end
		return {
			core = core,
			adapter = adapter,
			pres = pres,
			tbl = tbl,
			rows = rows,
			handle = handle,
			system = system,
			env = env,
			tick = tick,
			settle = settle,
		}
	end

	it("wraps only rows whose callback returns actions; nil rows get no RowActions node", function()
		local _, adapter = world({
			header = false,
			rowActions = function(item)
				if item.id == "razz" then
					return { trailing = { deleteAction() } }
				end
				return nil
			end,
		})
		expect(adapter.node(rowActionsRoot(0, "razz")) ~= nil).toBe(true)
		expect(adapter.node(wrappedRowHitPath(0, "razz")) ~= nil).toBe(true)
		-- unwrapped rows are byte-identical to an ordinary table: no RowActions
		-- node at all, `Row` sits directly under the ForEach slot
		expect(adapter.node(rowActionsRoot(0, "bolt"))).toBe(nil)
		expect(adapter.node(rowHitPath(0, "bolt")) ~= nil).toBe(true)
	end)

	it("unknown keys inside the returned action table error at build, naming the offending row", function()
		local ok, err = pcall(function()
			world({
				header = false,
				rowActions = function(item)
					if item.id == "razz" then
						return { trailing = { deleteAction() }, bogus = true }
					end
					return nil
				end,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "bogus") ~= nil).toBe(true)
		expect(string.find(tostring(err), "razz") ~= nil).toBe(true)
	end)

	it("swiping row B open closes row A (one shared coordinator through Table)", function()
		local w = raWorld({
			header = false,
			rowActions = function(_item)
				-- fullSwipe = false: any drag distance can only ever snap OPEN,
				-- never commit — isolates the coordinator's claim/release from
				-- the commit sequence entirely.
				return { trailing = { deleteAction() }, fullSwipe = false }
			end,
		})
		local razzHit = wrappedRowHitPath(0, "razz")
		local boltHit = wrappedRowHitPath(0, "bolt")
		local razzClosedX = w.adapter.node(razzHit).rect.x
		local boltClosedX = w.adapter.node(boltHit).rect.x

		local function openVia(hitPath: string, y: number)
			w.adapter.pointerDown(hitPath, 100, y, "mouse")
			w.tick(0.01)
			w.adapter.pointerMove(60, y) -- past the 8px axis lock, horizontal
			w.tick(1.0) -- calm gap: velocity's contribution is negligible
			w.adapter.pointerMove(-200, y) -- huge leftward drag (well past any tray)
			w.tick(1 / 60)
			w.adapter.pointerUp(-200, y)
			w.settle()
		end

		openVia(razzHit, 20)
		expect(w.adapter.node(razzHit).rect.x < razzClosedX).toBe(true) -- razz open

		openVia(boltHit, 60)
		expect(w.adapter.node(boltHit).rect.x < boltClosedX).toBe(true) -- bolt now open
		-- razz closed AS A RESULT of bolt's claim through the shared coordinator
		-- (bolt's own gesture never touched razz directly)
		expect(w.adapter.node(razzHit).rect.x).toBe(razzClosedX)
	end)

	it("mouse vertical drag on a reorderable + wrapped row still reorders", function()
		local reorders: { any } = {}
		local w = raWorld({
			header = false,
			reorderable = true,
			onReorder = function(keys: { string }, toIndex: number)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
			end,
			rowActions = function(_item)
				return { trailing = { deleteAction() } }
			end,
		})
		local razzHit = wrappedRowHitPath(0, "razz")
		w.adapter.pointerDown(razzHit, 100, 20)
		w.adapter.pointerMove(100, 90) -- purely vertical, well past the reorder threshold
		w.pres.refresh()
		expect(w.adapter.node("/S/Racers/DropWhen/then/DropLine") ~= nil).toBe(true) -- reorder engaged
		w.adapter.pointerUp(100, 90)
		expect(#reorders).toBe(1)
		expect(reorders[1].keys[1]).toBe("razz")
	end)

	-- REDTEAM ITEM 15 (LOW; table.luau's own former comment above
	-- `externalGesture`, corrected). A wrapped, REORDERABLE row's own
	-- internal `Content/Hit` Grip used to mount unconditionally even when
	-- `externalGesture = true` left it fully unwired (every handler nil) —
	-- a real, if inert, extra Active (hit-testable) Instance the old
	-- comment's "must not ALSO wire its own competing Content Grip" phrasing
	-- glossed over (unwired is not the same as absent). Fixed by omitting
	-- the node entirely rather than merely leaving it unwired.
	it(
		"a reorderable + wrapped row mounts NO internal Content/Hit Grip at all (only Table's own composed Hit)",
		function()
			local w = raWorld({
				header = false,
				reorderable = true,
				onReorder = function() end,
				rowActions = function(_item)
					return { trailing = { deleteAction() } }
				end,
			})
			expect(w.adapter.node(wrappedRowHitPath(0, "razz")) ~= nil).toBe(true) -- Table's own Hit: present
			expect(w.adapter.node(`{rowActionsRoot(0, "razz")}/Content/Hit`)).toBe(nil) -- row_actions' OWN Grip: gone
		end
	)

	-- a NON-reorderable wrapped row is unaffected: `externalGesture` stays
	-- false, so the composite's own internal Grip remains its one pointer
	-- surface, byte-identical to Tasks 3-9's shipped shape.
	it("a wrapped, NON-reorderable row still mounts its own internal Content/Hit Grip", function()
		local w = raWorld({
			header = false,
			rowActions = function(_item)
				return { trailing = { deleteAction() } }
			end,
		})
		expect(w.adapter.node(`{rowActionsRoot(0, "razz")}/Content/Hit`) ~= nil).toBe(true)
	end)

	it("mouse horizontal drag on the same reorderable + wrapped row reveals actions instead of reordering", function()
		local reorders: { any } = {}
		local w = raWorld({
			header = false,
			reorderable = true,
			onReorder = function(keys: { string }, toIndex: number)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
			end,
			rowActions = function(_item)
				return { trailing = { deleteAction() }, fullSwipe = false }
			end,
		})
		local razzHit = wrappedRowHitPath(0, "razz")
		local closedX = w.adapter.node(razzHit).rect.x
		w.adapter.pointerDown(razzHit, 100, 20)
		w.tick(0.01)
		w.adapter.pointerMove(60, 20) -- purely horizontal, past the axis lock
		w.tick(1.0)
		w.adapter.pointerMove(-100, 20)
		w.tick(1 / 60)
		w.adapter.pointerUp(-100, 20)
		w.settle()
		expect(#reorders).toBe(0) -- reorder never engaged
		expect(w.adapter.node(razzHit).rect.x < closedX).toBe(true) -- content slid: tray revealed
		expect(w.adapter.node("/S/Racers/DropWhen/then/DropLine")).toBe(nil)
	end)

	-- REDTEAM ITEM 11 (MEDIUM). `rowKeyForPath` only ever recognizes a row's
	-- OWN `Row/Hit`/reorder-handle path — a tap on a wrapped row's own TRAY
	-- BUTTON matches neither, so `api.handleActivate` always fell through
	-- and returned `false` for it. Harmless when the presenter reaches
	-- `api.handleActivate` the normal way (its own longest-prefix
	-- contribution walk finds row_actions' own `handleActivate` FIRST,
	-- deeper than Table's) — but EVERY world in this file presents with
	-- `opts.onActivate = function(path, meta) tbl.api.handleActivate(path,
	-- meta) end` (see `world`'s own `pres.present` call, top of file) — a
	-- consumer override that bypasses that walk ENTIRELY (presenter.luau:
	-- "wins outright") — so a tray-button TAP (as opposed to a drag
	-- gesture, which every other row-actions test in this file uses)
	-- silently did nothing under the exact harness every one of these
	-- tests already runs. `trayButtonPath` (declared above) had never
	-- actually been used by any test until this one.
	it("a tray-button TAP still fires onAction under Table's own opts.onActivate override", function()
		local fired: { string } = {}
		local w = raWorld({
			header = false,
			rowActions = function(_item)
				return { trailing = { deleteAction(fired, { role = "normal" }) }, fullSwipe = false }
			end,
		})
		local razzHit = wrappedRowHitPath(0, "razz")
		-- reveal (not commit) the tray via an ordinary horizontal drag
		w.adapter.pointerDown(razzHit, 100, 20, "mouse")
		w.tick(0.01)
		w.adapter.pointerMove(60, 20)
		w.tick(1.0)
		w.adapter.pointerMove(-90, 20)
		w.tick(1 / 60)
		w.adapter.pointerUp(-90, 20)
		w.settle()
		expect(#fired).toBe(0) -- revealed, not fired

		w.adapter.tap(trayButtonPath(0, "razz", "trailing", "delete"))
		expect(fired).toEqual({ "fired" })
	end)

	-- REDTEAM ITEM 10 (MEDIUM; spec: docs/plans/row-actions.md:136). The
	-- reorder ≡ handle ALWAYS starts a reorder, unconditionally, regardless
	-- of the row's own tray state — a handle-zone press used to leave an
	-- already-open tray stranded, sliding along with (or detached from) a
	-- row being dragged out from under it. Fixed at `handleDragHandlers`'s
	-- own `onPointerDown` in table.luau (the same `rowActionsByKey` lookup
	-- the row-tap handler already uses).
	it(
		"starting a reorder-handle drag on a row whose tray is open closes the tray FIRST, before reorder proceeds",
		function()
			local core = Facet.newCore()
			local editingSignal = core:signal(true) -- edit mode: the ≡ handle is mounted
			local w = raWorld({
				core = core,
				header = false,
				reorderable = true,
				editing = editingSignal,
				onReorder = function() end,
				rowActions = function(_item)
					return { trailing = { deleteAction() }, fullSwipe = false }
				end,
			})
			local razzHit = wrappedRowHitPath(0, "razz")
			local closedX = w.adapter.node(razzHit).rect.x

			-- open the tray via an ordinary horizontal drag on the row's own Hit
			w.adapter.pointerDown(razzHit, 100, 20, "mouse")
			w.tick(0.01)
			w.adapter.pointerMove(60, 20)
			w.tick(1.0)
			w.adapter.pointerMove(-200, 20)
			w.tick(1 / 60)
			w.adapter.pointerUp(-200, 20)
			w.settle()
			expect(w.adapter.node(razzHit).rect.x < closedX).toBe(true) -- open

			-- grab the ≡ handle: the tray's CLOSE is triggered the instant the
			-- press lands (before any move, before reorder itself even
			-- begins) — `_close()` retargets the same reveal spring the
			-- gesture itself rides, so the pixel position animates back over
			-- subsequent frames rather than snapping; settle to observe it.
			local handlePath = `{rowActionsRoot(0, "razz")}/Content/Row/EditWhen/then/HandleZone/Handle`
			w.adapter.pointerDown(handlePath, 100, 20, "mouse")
			w.settle()
			expect(w.adapter.node(razzHit).rect.x).toBe(closedX)

			-- and reorder itself still proceeds normally afterward — the fix
			-- only closes the tray, it does not eat or defer the handle press
			w.adapter.pointerMove(100, 90)
			w.pres.refresh()
			expect(w.adapter.node("/S/Racers/DropWhen/then/DropLine") ~= nil).toBe(true) -- reorder engaged
			w.adapter.pointerUp(100, 90)
		end
	)

	-- ===========================================================================
	-- FINAL FIX WAVE, item 2 (MAJOR; final-review-findings.md — the reorder-vs-
	-- tray HALF-fix). Item 10's own fix above only ever closed the tray from the
	-- edit-mode ≡ HANDLE's own onPointerDown (`handleDragHandlers`); the composed
	-- BODY-drag path (this composite's `_pointerHandlers` composed with
	-- `dragHandlers` via `row_actions.composeWithReorder`) and the
	-- gamepad/keyboard grab branch in `api.handleActivate` never went through
	-- either copy, so dragging a wrapped+reorderable row's own BODY — or
	-- grabbing it with a controller — while its tray was open left the tray
	-- stranded exactly like the ≡ handle used to before item 10. Fixed by
	-- hoisting the close into `rowPointerHandlers`'s own onPointerDown, the ONE
	-- funnel a plain reorderable row's Hit press, the ≡ handle's own press
	-- (`handleDragHandlers`'s `base = rowPointerHandlers()`), AND the composed
	-- body-drag replay (`composeWithReorder`'s own `reorderHandlers.onPointerDown`)
	-- all share — deleting the now-redundant duplicate at the ≡ handle — and
	-- adding the identical guard at the grab branch's own separate entry point.
	-- ===========================================================================
	it("mouse BODY-drag reorder (not the ≡ handle) on a row whose tray is open closes the tray first", function()
		local reorders: { any } = {}
		local w = raWorld({
			header = false,
			reorderable = true,
			onReorder = function(keys: { string }, toIndex: number)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
			end,
			rowActions = function(_item)
				return { trailing = { deleteAction() } }
			end,
		})
		local razzHit = wrappedRowHitPath(0, "razz")
		local closedX = w.adapter.node(razzHit).rect.x

		-- open the tray via an ordinary horizontal drag on the row's own Hit
		w.adapter.pointerDown(razzHit, 100, 20, "mouse")
		w.tick(0.01)
		w.adapter.pointerMove(60, 20)
		w.tick(1.0)
		w.adapter.pointerMove(-200, 20)
		w.tick(1 / 60)
		w.adapter.pointerUp(-200, 20)
		w.settle()
		expect(w.adapter.node(razzHit).rect.x < closedX).toBe(true) -- open

		-- a FRESH press on the SAME Hit, dragged VERTICAL this time: the
		-- composed body-drag path (`composeWithReorder`, NOT the ≡ handle)
		-- resolves "reorder" once the axis lock crosses vertical. The tray
		-- must close, same as the handle-drag case (item 10) above.
		w.adapter.pointerDown(razzHit, 100, 20, "mouse")
		w.adapter.pointerMove(100, 90) -- purely vertical, past the reorder threshold
		w.pres.refresh()
		expect(w.adapter.node("/S/Racers/DropWhen/then/DropLine") ~= nil).toBe(true) -- reorder engaged
		w.settle()
		expect(w.adapter.node(razzHit).rect.x).toBe(closedX) -- tray closed, not stranded
		w.adapter.pointerUp(100, 90)
		expect(#reorders).toBe(1)
	end)

	it(
		"gamepad/keyboard grab (A / action-source Activate) on a row whose tray is open closes the tray first",
		function()
			local w = raWorld({
				header = false,
				reorderable = true,
				onReorder = function() end,
				rowActions = function(_item)
					return { trailing = { deleteAction() } }
				end,
			})
			w.tbl.api.editing:set(true) -- grab is edit-mode only
			w.pres.refresh()
			local razzHit = wrappedRowHitPath(0, "razz")
			local closedX = w.adapter.node(razzHit).rect.x

			w.adapter.pointerDown(razzHit, 100, 20, "mouse")
			w.tick(0.01)
			w.adapter.pointerMove(60, 20)
			w.tick(1.0)
			w.adapter.pointerMove(-200, 20)
			w.tick(1 / 60)
			w.adapter.pointerUp(-200, 20)
			w.settle()
			expect(w.adapter.node(razzHit).rect.x < closedX).toBe(true) -- open

			w.tbl.api.handleActivate(razzHit, { source = "action" }) -- grab
			expect(w.tbl.api.grabbedKey:get()).toBe("razz")
			w.settle()
			expect(w.adapter.node(razzHit).rect.x).toBe(closedX) -- tray closed, not stranded
		end
	)

	it("editing signal shows the minus on rows with a destructive action", function()
		local core = Facet.newCore()
		local editingSignal = core:signal(false)
		local _, adapter, pres = world({
			core = core,
			header = false,
			editing = editingSignal,
			rowActions = function(item)
				if item.id == "razz" then
					return { trailing = { deleteAction() } }
				end
				return nil
			end,
		})
		expect(adapter.node(editAffordancePath(0, "razz"))).toBe(nil) -- not editing yet
		editingSignal:set(true)
		pres.refresh()
		expect(adapter.node(editAffordancePath(0, "razz")) ~= nil).toBe(true)
	end)

	it("rows removed from spec.rows dispose their wrapper (no leak)", function()
		local core = Facet.newCore()
		local _, adapter, pres, _tbl, rows = world({
			core = core,
			header = false,
			rowsOverride = { RACERS[1] }, -- razz only; nothing wrapped yet
			rowActions = function(item)
				if item.id == "bolt" then
					return { trailing = { deleteAction() } }
				end
				return nil
			end,
		})
		local baseline = core:counters()
		rows:set({ RACERS[1], RACERS[2] }) -- add bolt: wraps
		pres.refresh()
		expect(adapter.node(rowActionsRoot(0, "bolt")) ~= nil).toBe(true)
		rows:set({ RACERS[1] }) -- remove bolt: wrapper must dispose
		pres.refresh()
		expect(adapter.node(rowActionsRoot(0, "bolt"))).toBe(nil)
		local after = core:counters()
		for key, v in baseline :: { [string]: number } do
			expect((after :: any)[key]).toBe(v)
		end
	end)

	it("a data refresh mid-gesture cancels: onAction never fires for a key removed mid-commit", function()
		local fired: { string } = {}
		local w = raWorld({
			header = false,
			rowActions = function(item)
				if item.id == "razz" then
					return { trailing = { deleteAction(fired) } }
				end
				return nil
			end,
		})
		local razzHit = wrappedRowHitPath(0, "razz")
		local rowW = w.adapter.node(razzHit).rect.w
		w.adapter.pointerDown(razzHit, 100, 20)
		w.tick(0.01)
		w.adapter.pointerMove(60, 20)
		w.tick(1.0)
		local releaseX = 100 - rowW * 0.9 -- past the 60% full-swipe commit threshold
		w.adapter.pointerMove(releaseX, 20)
		w.tick(1 / 60)
		w.adapter.pointerUp(releaseX, 20)
		-- a couple of frames into the slide-off — comfortably before onArrive
		w.tick(1 / 60)
		w.tick(1 / 60)
		expect(#fired).toBe(0)
		-- mid-flight data refresh: razz's key vanishes from the data entirely
		w.rows:set({ RACERS[2], RACERS[3] })
		w.pres.refresh()
		w.settle()
		expect(#fired).toBe(0) -- never fires for the replaced/vanished key
	end)

	it("Delete key on a focused row deletes via the row's destructive action", function()
		local fired: { string } = {}
		local core = Facet.newCore()
		local _, adapter, pres, _tbl, _rows, _handle, system = world({
			core = core,
			header = false,
			rowActions = function(item)
				if item.id == "razz" then
					return { trailing = { deleteAction(fired) } }
				end
				return nil
			end,
		})
		pres.focus.focusOn(wrappedRowHitPath(0, "razz"))
		system.deviceKey("Delete", true)
		system.deviceKey("Delete", false)
		pres.refresh()
		-- TWO sequential springs settle here (slide-off, then the height
		-- collapse — row_actions.luau's own `doCommitAction` chain), each up
		-- to ~90 frames on its own (row_actions.spec.luau's own
		-- SETTLE_FRAMES convention) — a wide fill-column row (this table's
		-- own 800px viewport) slides the FULL row width off-screen, so 90
		-- frames alone (enough for ONE spring) left the second stranded
		-- mid-flight. Paired with `pres.refresh()` throughout (syncGeometry
		-- has to keep running for `currentRowHeight()`'s own live read).
		for _ = 1, 240 do
			pres.tick(1 / 60)
			pres.refresh()
		end
		expect(#fired).toBe(1)
	end)

	it(
		"tap-to-close: a tap on a row's own content while ITS tray is open closes it — no select, no activate",
		function()
			local w = raWorld({
				header = false,
				selection = "single",
				rowActions = function(item)
					if item.id == "razz" then
						return { trailing = { deleteAction() }, fullSwipe = false }
					end
					return nil
				end,
			})
			local razzHit = wrappedRowHitPath(0, "razz")
			local closedX = w.adapter.node(razzHit).rect.x
			w.adapter.pointerDown(razzHit, 100, 20)
			w.tick(0.01)
			w.adapter.pointerMove(60, 20)
			w.tick(1.0)
			w.adapter.pointerMove(-200, 20)
			w.tick(1 / 60)
			-- THE SWIPE'S OWN RELEASE ACTIVATE IS PART OF THE SWIPE (redteam
			-- BLOCKER, 2026-08-13). The engine fires the row `Hit`'s `Activated`
			-- at the end of this gesture whether it was a tap or a swipe, and the
			-- control swallows exactly that one — so a case that omits it is not
			-- only missing a signal, it leaves the suppression armed and makes the
			-- NEXT tap look swallowed too. Delivered here, this case now proves
			-- both halves at once: the swipe's own artifact does NOT close the
			-- tray it just opened, and a genuine tap afterwards does.
			w.adapter.pointerUpActivating(-200, 20, "after")
			w.settle()
			expect(w.adapter.node(razzHit).rect.x < closedX).toBe(true) -- confirmed open

			w.adapter.tap(razzHit) -- a genuine tap/Activate on the row's own content
			w.pres.refresh()
			expect(w.tbl.api.selectedKeys:get().razz).toBe(nil) -- no select
			w.settle()
			expect(w.adapter.node(razzHit).rect.x).toBe(closedX) -- tray closed
		end
	)

	it(
		"a committed delete shrinks the row's own box and moves following rows up, THEN fires onAction and lets the owner remove it via keyed diff",
		function()
			local fired: { string } = {}
			--[[ THE HEIGHT AT THE FIRE, READ AT THE FIRE (2026-08-15). This used to
				sample the rect after the tick that fired, which stopped being the
				same question once the renderer began draining a solve's own
				`syncGeometry` writes inside that solve: `drainPostCommitRestore` runs
				from the very sync this frame's solve announces, so the collapsed box
				and the restored one now both happen inside one tick and the later
				sample sees the restore. Reading it from INSIDE `onAction` asks the
				invariant where it lives — the adapter still holds the solved,
				collapsed rect, and the restore is still two statements away
				(`finishCommit` -> the next `syncGeometry`). Strictly stronger than
				the end-of-tick sample it replaces. ]]
			local heightAtFire: number? = nil
			local wRef: any = nil
			local razzHit = wrappedRowHitPath(0, "razz")
			local razzOuter = rowActionsRoot(0, "razz")
			local w = raWorld({
				header = false,
				rowActions = function(item)
					if item.id == "razz" then
						return {
							trailing = {
								deleteAction(fired, {
									onFire = function()
										heightAtFire = wRef.adapter.node(razzOuter).rect.h
									end,
								}),
							},
						}
					end
					return nil
				end,
			})
			wRef = w
			local boltYBefore = w.adapter.node(rowHitPath(0, "bolt")).rect.y
			local razzHeightBefore = w.adapter.node(razzOuter).rect.h
			expect(razzHeightBefore > 0).toBe(true)

			local rowW = w.adapter.node(razzHit).rect.w
			w.adapter.pointerDown(razzHit, 100, 20)
			w.tick(0.01)
			w.adapter.pointerMove(60, 20)
			w.tick(1.0)
			local releaseX = 100 - rowW * 0.9
			w.adapter.pointerMove(releaseX, 20)
			w.tick(1 / 60)
			w.adapter.pointerUp(releaseX, 20)

			--[[ MID-FLIGHT, DERIVED RATHER THAN COUNTED (2026-08-13) ───────────
				This used to run a fixed 100 frames and assert "still animating"
				there, with a comment describing the slide sitting untouched
				through frame ~65 and the collapse only starting from ~75. That
				number was measured against a commit whose two springs ran
				STRICTLY IN SERIES — and the 27-frame dead window between them
				is the "odd pause once the row goes away before the others
				animate up" the director reported on 2026-08-13. The flights are
				concurrent now and the whole commit completes around frame 54,
				so 100 is past the end and the old sample point measured nothing.

				The invariant this case is actually about needs no frame budget
				at all: `onAction` must never fire while the row still has
				height, whatever the timing — so ask that of EVERY frame instead
				of one. Strictly stronger than the single sample it replaces, and
				immune to the next motion retune.
			]]
			local sawShrink, sawBoltUp, fireFrame = false, false, nil :: number?
			for i = 1, 240 do
				w.tick(1 / 60)
				local h = w.adapter.node(razzOuter).rect.h
				if #fired > 0 then
					-- NEVER EARLY: at the fire the row is already carried away. The
					-- collapse settles NUMERICALLY (motion.luau's settle epsilon), so
					-- the height at the fire is sub-pixel rather than bit-identical
					-- zero — measured 0.000064px here, against ~40 for an early fire.
					expect(`frame {i}: row height at fire < 1px: {(heightAtFire or math.huge) < 1}`).toBe(
						`frame {i}: row height at fire < 1px: true`
					)
					fireFrame = i
					break
				end
				if h < razzHeightBefore then
					sawShrink = true -- the row's OWN box shrank
				end
				if w.adapter.node(rowHitPath(0, "bolt")).rect.y < boltYBefore then
					sawBoltUp = true -- ...and bolt moved up behind it
				end
			end
			-- both halves of the flight were genuinely observed BEFORE the fire,
			-- so "never fires early" is a statement about a real animation
			expect(sawShrink).toBe(true)
			expect(sawBoltUp).toBe(true)
			expect(fireFrame ~= nil).toBe(true)

			w.settle(240)
			expect(#fired).toBe(1) -- fires exactly once, after the animation

			-- the owner's data mutation removes the row via keyed diff — NOT the
			-- composite itself; row_actions only ever animates and reports
			w.rows:set({ RACERS[2], RACERS[3] })
			w.pres.refresh()
			expect(w.adapter.node(razzHit)).toBe(nil)
			expect(w.adapter.node(rowHitPath(0, "bolt")) ~= nil).toBe(true)
		end
	)

	it("edit mode shows BOTH the row_actions minus and Table's own reorder handle at once", function()
		local core = Facet.newCore()
		local editingSignal = core:signal(true) -- start in edit mode
		local _, adapter = world({
			core = core,
			header = false,
			reorderable = true,
			editing = editingSignal,
			onReorder = function() end,
			rowActions = function(item)
				if item.id == "razz" then
					return { trailing = { deleteAction() } }
				end
				return nil
			end,
		})
		expect(adapter.node(editAffordancePath(0, "razz")) ~= nil).toBe(true) -- the minus
		expect(adapter.node(`{rowActionsRoot(0, "razz")}/Content/Row/EditWhen/then/HandleZone/Handle`) ~= nil).toBe(
			true
		) -- Table's own reorder handle, still there
	end)

	-- REDTEAM ITEM 2 (BLOCKER): the director's own regression test's TABLE
	-- variant — the shape the old design could never satisfy at all, since
	-- Table hands each row an explicit `{ type = "fixed", px = rowHeight }`
	-- (never `fill`), so even `popup_button.luau`'s own fill-height escape
	-- never had a lever to pull here (redteam-fixwave-report.md item 2's own
	-- investigation). Fixed by re-homing the menu onto its own presentModal
	-- surface (row_actions.luau, the big comment above `local function
	-- openMenu`) — a sibling top-level surface can never contribute to ANY
	-- row's measured box, Table's own arithmetic rowHeight included.
	it(
		"opening a wrapped row's menu leaves every OTHER row's solved rect byte-identical — Table's own authored rowHeight survives",
		function()
			local fired: { string } = {}
			local w = raWorld({
				header = false,
				rowActions = function(item)
					if item.id == "razz" then
						return { trailing = { deleteAction(fired) } }
					end
					return nil -- bolt/josh stay UNWRAPPED — plain rows, the
					-- clean oracle for "did anything about a sibling change"
				end,
			})
			local razzHit = wrappedRowHitPath(0, "razz")
			local boltPath = rowHitPath(0, "bolt")
			local joshPath = rowHitPath(0, "josh")
			local boltBefore = (w.adapter.node(boltPath) :: any).rect
			local joshBefore = (w.adapter.node(joshPath) :: any).rect

			w.pres.focus.focusOn(razzHit)
			w.system.deviceKey("ButtonX", true)
			w.system.deviceKey("ButtonX", false)
			w.pres.refresh()

			-- the menu really opened (independent proof — not just trusting
			-- the fixture): its OWN presented surface mounted a real row.
			-- Table's own row_actions id is `RowActions-<rowKey>`
			-- (table.luau), so this row's menu surface is
			-- `RowActionsMenu-RowActions-razz`.
			expect(w.adapter.node("/RowActionsMenu-RowActions-razz/Menu/MenuRows/Action:delete") ~= nil).toBe(true)

			local boltAfter = (w.adapter.node(boltPath) :: any).rect
			local joshAfter = (w.adapter.node(joshPath) :: any).rect
			expect(boltAfter.y).toBe(boltBefore.y)
			expect(boltAfter.h).toBe(boltBefore.h)
			expect(joshAfter.y).toBe(joshBefore.y)
			expect(joshAfter.h).toBe(joshBefore.h)

			-- razz's own row keeps Table's authored rowHeight too — the
			-- exact 48px->73px repro number the red team's own charter
			-- names, now pinned at zero delta rather than merely "smaller."
			local razzRoot = w.adapter.node(rowActionsRoot(0, "razz")) :: any
			expect(razzRoot.rect.h).toBe(40) -- world()'s own default rowHeight
		end
	)
end)

--[[ ═══ RULING 3 (director, 2026-08-13): A BLOCK TABLE PUBLISHES NOTHING ══════
	`api.scrollPath()` used to return `<root>/Main/Body` unconditionally, with no
	`spec.scrolls` check — but a BLOCK table's Body is a plain `UI.VStack`, not a
	`UI.ScrollView`, so that path names a node that never scrolls (and which the
	renderer ELIDES entirely, which is how the crash half of this was found).

	The crash half is fixed in `screen_target.observeScroll`. THIS is the design
	half, and it is the reported symptom: open a swipe tray in the shipped
	playlist, scroll the PAGE, and the tray rides along still open — because
	"any scroll closes the tray" (`row_actions.newCoordinator`'s `bindScroll`)
	was bound to that never-scrolling node.

	Ruled fix A: publish nothing when the table does not scroll, so the
	tray-closing rule binds to the REAL scrolling ancestor
	(`controller.scrollHostFor`, which already exists for Table's own reorder
	autoscroll and whose own comment names "a block Table inside a scrolling
	page" as the shipped shape). ]]
describe("Table: a BLOCK table publishes no scroll path of its own (ruling 3)", function()
	local function pageWorld(spec: any)
		local core = spec.core or Facet.newCore()
		local clockTime = 0
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system, {
			now = function()
				return clockTime
			end,
		})
		local rows = core:signal(RACERS)
		local tbl = table_control.build(Facet, core, {
			id = "Racers",
			env = env,
			scrolls = spec.scrolls,
			header = false,
			rowHeight = 40,
			columns = { { id = "name", title = "Racer", width = { type = "fill", weight = 1 } } },
			rows = rows,
			key = function(item)
				return item.id
			end,
			cellFor = function(_columnId, item)
				return Facet.UI.Text({ id = "Value", text = item.name, textSize = 16 })
			end,
			rowActions = function(_item)
				return {
					trailing = { { id = "delete", role = "destructive", label = "Delete", onAction = function() end } },
					fullSwipe = false,
				}
			end,
		})
		-- THE HOST OWNS THE SCROLLING (the shipped playlist's own shape,
		-- examples/gallery/examples/02_playlist_table.luau): a page ScrollView
		-- wrapping a table that is a block inside it.
		local handle = pres.present(Facet.UI.Screen({
			id = "S",
			children = {
				Facet.UI.ScrollView({
					id = "Page",
					axis = "y",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = { tbl.blueprint },
				}),
			},
		}))
		pres.refresh()
		local function tick(dt: number)
			clockTime += dt
			pres.tick(dt)
			pres.refresh()
		end
		local function settle(frames: number?)
			for _ = 1, frames or 90 do
				tick(1 / 60)
			end
		end
		return { core = core, adapter = adapter, pres = pres, tbl = tbl, handle = handle, tick = tick, settle = settle }
	end

	local function rowHit(key: string): string
		return `/S/Page/Racers/Main/Body/Rows/[{key}@0]/RowActions-{key}/Content/Row/Hit`
	end

	-- open razz's trailing tray with a real horizontal drag on its own Hit
	local function openTray(w: any): number
		local hit = rowHit("razz")
		local closedX = (w.adapter.node(hit) :: any).rect.x
		w.adapter.pointerDown(hit, 100, 20, "mouse")
		w.tick(0.01)
		w.adapter.pointerMove(60, 20)
		w.tick(1.0)
		w.adapter.pointerMove(-200, 20)
		w.tick(1 / 60)
		w.adapter.pointerUp(-200, 20)
		w.settle()
		expect(`opened: {(w.adapter.node(hit) :: any).rect.x < closedX}`).toBe("opened: true")
		return closedX
	end

	it("a VIEWPORT table publishes its own Body; a BLOCK table publishes nothing", function()
		local viewport = pageWorld({ scrolls = true })
		expect(viewport.tbl.api.scrollPath()).toBe("/S/Page/Racers/Main/Body")
		local block = pageWorld({ scrolls = false })
		expect(block.tbl.api.scrollPath()).toBe(nil)
	end)

	it("the BLOCK table's published Body is not a scroller at all — which is why publishing it lied", function()
		local block = pageWorld({ scrolls = false })
		local body = block.adapter.node("/S/Page/Racers/Main/Body")
		-- present, but with no scroll region: driving a scroll on it is a no-op
		expect(`body mounted: {body ~= nil}`).toBe("body mounted: true")
		expect(`body scrolls: {(body :: any).scrollRegion ~= nil}`).toBe("body scrolls: false")
	end)

	it("THE SYMPTOM: a PAGE scroll closes an open tray in a BLOCK table", function()
		local w = pageWorld({ scrolls = false })
		local closedX = openTray(w)
		w.tbl.api.bindNativeScroll(w.handle.controller)
		w.adapter.driveScroll("/S/Page", { x = 0, y = 30 })
		w.settle()
		expect((w.adapter.node(rowHit("razz")) :: any).rect.x).toBe(closedX)
		--[[ ...AND THE PAGE'S OFFSET STAYS OUT OF THE TABLE'S OWN MIRROR. It is
			tempting to point the CanvasPosition mirror at the ancestor too, since
			that is where the movement is — and it is wrong: `scrollTop` is spent by
			the reorder drop-slot arithmetic as `pos.y - bodyRect.y + scrollTop`, and
			`bodyRect` is WINDOW space (renderer.luau ESC-2), so a block table's rect
			ALREADY moves with the page. Mirroring the page there counts its offset
			twice and puts every drop slot wrong by exactly the page scroll. A block
			table has no canvas of its own; its mirror stays at zero. ]]
		expect(w.tbl.dump().scrollTop).toBe(0)
	end)

	it("...and a VIEWPORT table still closes its tray on its OWN body scroll (unchanged)", function()
		local w = pageWorld({ scrolls = true })
		local closedX = openTray(w)
		w.tbl.api.bindNativeScroll(w.handle.controller)
		w.adapter.driveScroll("/S/Page/Racers/Main/Body", { x = 0, y = 30 })
		w.settle()
		expect((w.adapter.node(rowHit("razz")) :: any).rect.x).toBe(closedX)
	end)

	it("binding a BLOCK table still reports the mount error when it was never presented", function()
		local core = Facet.newCore()
		local tbl = table_control.build(Facet, core, {
			id = "Loose",
			scrolls = false,
			columns = { { id = "name", title = "N", width = { type = "fill", weight = 1 } } },
			rows = core:signal(RACERS),
			key = function(item)
				return item.id
			end,
			cellFor = function()
				return Facet.UI.Text({ id = "V", text = "x", textSize = 16 })
			end,
		})
		local ok, err = pcall(function()
			tbl.api.bindNativeScroll({})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "scroll path unknown", 1, true) ~= nil).toBe(true)
	end)
end)
