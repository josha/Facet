--!strict
--[[ THE HEADER BAND, UNDER EVERY SHIPPED PACKAGE — the axis the Table's specs
	could not test.

	WHY IT EXISTS. `tests/table.spec.luau`, `table_columns.spec.luau` and
	`paradigm_table.spec.luau` between them assert the header band in detail, and
	every one of them mounts it under exactly one theme: the built-in snapshot.
	A corpus uniform along an axis cannot test that axis, so the whole class of
	"correct flat, wrong once a package paints something" was invisible to the
	suite by construction — which is how the director found this one in Studio
	instead:

	  2026-08-14, showcase `table_columns` under Pixel Quest and Glossy Touch:
	  "the triangle table header sort indicator appears outside when themed".

	The mark is a hugging `alignH = "end"` glyph carrying the theme's own
	`controls.table.sortMarkMargin` — "keeps the ▲/▼ clear" — and the solver
	aligned it in the box it had NOT granted (`docs/lessons/a-far-margin-must-buy-
	something.md`), so the reserve bought 0 px under every package including the
	default. Under a flat package the column boundary it landed on is invisible;
	under the five packages that paint a nine-slice or layered plate on the header
	cell, that boundary is the plate's carved border, and the glyph sat outside the
	box.

	WHAT IT ASSERTS, for every package and both table kinds:

	  (a) the mark stops `sortMarkMargin` short of the cell's trailing edge — the
	      one number that read 0 for all nine configurations;
	  (b) the mark clears the plate's own carved border (`contentInsets`), which is
	      the visible symptom rather than its cause, and is therefore the assertion
	      a package author's eye would make;
	  (c) the title never overlaps the mark, whichever way the column is aligned;
	  (d) the solver reports nothing on any of it.

	WHAT IT IS NOT: it cannot see paint, engine text bounds, or clipping — the
	Studio drive stays the real instrument (`docs/guide/11-device-verification.md`).
	It is the part of that drive a machine can check on every commit.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local table_control = require("../src/controls/table")
local fake_target = require("./lib/fake_target")
local chrome_slots = require("../src/tokens/chrome_slots")

-- the eight shipped reference packages (tests/theme_reference_packages.spec.luau
-- holds the same list), plus the built-in snapshot as the ninth row — the flat
-- baseline is a row of this matrix, not the thing it is compared against
local PACKAGES: { [string]: any } = {
	classic_desktop = require("../examples/themes/classic_desktop"),
	glossy_mobile = require("../examples/themes/glossy_mobile"),
	scifi_hud = require("../examples/themes/scifi_hud"),
	fantasy_parchment = require("../examples/themes/fantasy_parchment"),
	fantasy_ornate = require("../examples/themes/fantasy_ornate"),
	pixel_quest = require("../examples/themes/pixel_quest"),
	glossy_touch = require("../examples/themes/glossy_touch"),
	compact_pointer = require("../examples/themes/compact_pointer"),
}
local ROWS = {
	"studio-neutral",
	"classic_desktop",
	"glossy_mobile",
	"scifi_hud",
	"fantasy_parchment",
	"fantasy_ornate",
	"pixel_quest",
	"glossy_touch",
	"compact_pointer",
}

local RACERS = {
	{ id = "razz", name = "Razz Raccoon", team = "Ridge Runners", best = "1:02" },
	{ id = "bolt", name = "Bunny Bolt", team = "Vale", best = "1:04" },
}

-- the shipped `table_columns` fixture's own shape: two resizable leading columns
-- and one that refuses, all three sortable through `value`
local function columnsFor(resizable: boolean): { any }
	return {
		{
			id = "name",
			title = "Entrant",
			width = { type = "fill", weight = 3 },
			minWidth = 90,
			resizable = resizable,
			value = function(item: any)
				return item.name
			end,
		},
		{
			id = "team",
			title = "Team",
			width = { type = "fill", weight = 4 },
			minWidth = 80,
			resizable = resizable,
			value = function(item: any)
				return item.team
			end,
		},
		{
			id = "best",
			title = "A rather long trailing heading",
			width = { type = "fill", weight = 3 },
			minWidth = 70,
			alignment = { h = "trailing" },
			value = function(item: any)
				return item.best
			end,
		},
	}
end

type Row = {
	head: any,
	mark: any,
	title: any,
	reserve: number,
	border: number,
	diagnostics: { any },
}

local function solveRow(packageName: string?, sortColumn: string, resizable: boolean, nameWidth: number?): Row
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 1232, h = 1067 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	-- the engine draws the bar INSIDE the region; the header's third gutter term
	-- is a measurement of that reserve, so a row solved without it lays out wide
	adapter.scrollBarThickness = 8
	local presenter = LuauUI.newPresenter(core, env, adapter, system)
	local chromeState = chrome_slots.newState(nil)
	local tbl = table_control.build(LuauUI, core, {
		id = "Entrants",
		columns = columnsFor(resizable),
		rows = core:signal(RACERS),
		key = function(item: any)
			return item.id
		end,
		rowHeight = 40,
		selection = "single",
		sortOrder = core:signal({ column = sortColumn, ascending = true }),
		env = env,
	})
	local handle = presenter.present(LuauUI.UI.Screen({ id = "S", children = { tbl.blueprint } }), {})
	presenter.refresh()
	local pkg = nil
	if packageName ~= nil then
		pkg = PACKAGES[packageName].build(LuauUI.themes)
		-- both halves of a theme: the chrome plan decides what is PAINTED, the
		-- snapshot decides what is MEASURED (docs/lessons/a-theme-has-two-halves.md)
		chromeState.setPackage(pkg)
		env:set("themeMetrics", LuauUI.themes.resolve(pkg, nil, {}))
		presenter.refresh()
	end
	if nameWidth ~= nil then
		tbl.api.setColumnWidth("name", nameWidth)
		presenter.refresh()
	end
	local base = `/S/Entrants/Main/Header/Head-{sortColumn}`
	local snap = env:get("themeMetrics"):get()
	-- what the package paints on the header cell's own handle: a `control` plate,
	-- nine-slice or layered, full bleed to the node's rect with its own carved
	-- border. `contentInsets` is the package's statement of where that border ends.
	local plan = if pkg ~= nil
		then chrome_slots.layerPlanFor(pkg, "control") or chrome_slots.planFor(pkg, "control")
		else nil
	local insets = if plan ~= nil then plan.contentInsets else nil
	return {
		head = adapter.node(base).rect,
		mark = adapter.node(base .. "/SortMark").rect,
		title = adapter.node(base .. "/Title").rect,
		reserve = snap.controls.table.sortMarkMargin,
		border = if type(insets) == "table" and type(insets.right) == "number" then insets.right else 0,
		-- the SOLVER's own channel, off the render controller — `tbl.api` has no
		-- `diagnostics`, so reading one off it would be a check that proves nothing
		-- (it would answer `{}` forever). `handle.controller.diagnostics()` is what
		-- the overflow sweep and the theme matrix both read.
		diagnostics = handle.controller.diagnostics(),
	}
end

describe("Table header: the sort mark under every shipped theme package", function()
	--[[ (a) THE CAUSE, and the one number that was 0 for every row. A margin the
		author declared and the solver drops is indistinguishable from a margin that
		works right up until something is painted at that edge. ]]
	it("the mark stops the theme's OWN reserve short of the column boundary", function()
		for _, name in ROWS do
			local pkg = if name == "studio-neutral" then nil else name
			for _, resizable in { true, false } do
				local row = solveRow(pkg, "name", resizable)
				local spent = (row.head.x + row.head.w) - (row.mark.x + row.mark.w)
				expect(`{name}/resizable={resizable}: spent {spent} of {row.reserve}`).toBe(
					`{name}/resizable={resizable}: spent {row.reserve} of {row.reserve}`
				)
			end
		end
	end)

	--[[ (b) THE SYMPTOM. Five of the eight packages carve a border into the header
		cell's plate; a glyph inside that border is the "appears outside" the report
		named. Flat packages report a 0 border and pass this trivially, which is the
		honest outcome — they cannot show the defect and never could. ]]
	it("the mark clears the plate's carved border, so it paints INSIDE the box", function()
		local bordered = 0
		for _, name in ROWS do
			local pkg = if name == "studio-neutral" then nil else name
			local row = solveRow(pkg, "name", true)
			if row.border > 0 then
				bordered += 1
			end
			expect(
				`{name}: mark ends {(row.head.x + row.head.w) - (row.mark.x + row.mark.w)}px in, border {row.border}px`
			).toBe(`{name}: mark ends {row.reserve}px in, border {row.border}px`)
			expect(`{name}: inside`).toBe(
				`{name}: {if (row.mark.x + row.mark.w) <= (row.head.x + row.head.w) - row.border
					then "inside"
					else "OUTSIDE THE PLATE"}`
			)
		end
		-- the corpus really does vary along this axis — if every package went flat
		-- this whole file would be the uniform corpus it was written to replace
		expect(bordered >= 4).toBe(true)
	end)

	-- (c) the title and the mark share one ZStack and one trailing edge, whichever
	-- way the column is aligned. `best` is trailing, `name` is leading.
	it("the title never overlaps the mark, leading or trailing", function()
		for _, name in ROWS do
			local pkg = if name == "studio-neutral" then nil else name
			for _, column in { "name", "best" } do
				local row = solveRow(pkg, column, true)
				expect(`{name}/{column}: clear`).toBe(
					`{name}/{column}: {if (row.title.x + row.title.w) <= row.mark.x then "clear" else "OVERLAPS"}`
				)
			end
		end
	end)

	--[[ A RESIZE MOVES THE BOUNDARY, AND THE RESERVE GOES WITH IT. The director
		found this in the RESIZABLE table, so the obvious hypothesis was that a drag
		pushed the mark out past some width. It does not — the defect was
		width-independent — and this is what says so, at the two extremes of the
		column's range, so a future regression that IS width-dependent has a named
		home. ]]
	it("a column resize carries the mark with the boundary, at any width", function()
		for _, name in ROWS do
			local pkg = if name == "studio-neutral" then nil else name
			for _, width in { 200, 600 } do
				local row = solveRow(pkg, "name", true, width)
				local spent = (row.head.x + row.head.w) - (row.mark.x + row.mark.w)
				expect(`{name}@{width}: {spent}`).toBe(`{name}@{width}: {row.reserve}`)
				expect(`{name}@{width}: clear`).toBe(
					`{name}@{width}: {if (row.title.x + row.title.w) <= row.mark.x then "clear" else "OVERLAPS"}`
				)
			end
		end
	end)

	-- (d) and the solver has nothing to report about any of it
	it("no package makes the header band report a layout finding", function()
		for _, name in ROWS do
			local pkg = if name == "studio-neutral" then nil else name
			local row = solveRow(pkg, "name", true)
			expect(`{name}: {#row.diagnostics}`).toBe(`{name}: 0`)
		end
	end)
end)
