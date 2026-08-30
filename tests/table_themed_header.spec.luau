--!strict
--[[ THE HEADER BAND, UNDER EVERY SHIPPED PACKAGE — the axis the Table's specs
	could not test.

	WHY IT EXISTS. `tests/table.spec.luau`, `playlist_columns.spec.luau` and
	`paradigm_table.spec.luau` between them assert the header band in detail, and
	every one of them mounts it under exactly one theme: the built-in snapshot.
	A corpus uniform along an axis cannot test that axis, so the whole class of
	"correct flat, wrong once a package paints something" was invisible to the
	suite by construction — which is how the director found this one in Studio
	instead:

	  2026-08-14, showcase `table_columns` (retired 2026-08-16) under Pixel Quest and Glossy Touch:
	  "the triangle table header sort indicator appears outside when themed".

	The mark is a hugging `alignH = "end"` glyph carrying the theme's own
	`controls.table.sortMarkMargin` — "keeps the ▲/▼ clear" — and the solver
	aligned it in the box it had NOT granted — a far margin must buy something —
	so the reserve bought 0 px under every package including the
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

local Facet = require("../src") :: any
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

-- the shipped playlist table's own shape: two resizable leading columns
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
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 1232, h = 1067 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	-- the engine draws the bar INSIDE the region; the header's third gutter term
	-- is a measurement of that reserve, so a row solved without it lays out wide
	adapter.scrollBarThickness = fake_target.SCROLL_BAR_RESERVE
	local presenter = Facet.newPresenter(core, env, adapter, system)
	local chromeState = chrome_slots.newState(nil)
	local tbl = table_control.build(Facet, core, {
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
	local handle = presenter.present(Facet.UI.Screen({ id = "S", children = { tbl.blueprint } }), {})
	presenter.refresh()
	local pkg = nil
	if packageName ~= nil then
		pkg = PACKAGES[packageName].build(Facet.themes)
		-- both halves of a theme: the chrome plan decides what is PAINTED, the
		-- snapshot decides what is MEASURED
		chromeState.setPackage(pkg)
		env:set("themeMetrics", Facet.themes.resolve(pkg, nil, {}))
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

--[[ ── THE BODY-SHAPE AXIS (device review 2026-08-16) ────────────────────────

	THE SECOND UNIFORM AXIS IN THE TABLE'S CORPUS, and the file above only closed
	the first. Every case up to here — and `tests/table.spec.luau`'s "the header
	tracks the rows, so the columns never come apart", which sweeps the same nine
	packages — mounts a table in exactly ONE body shape: the default, where the
	Table's own Body is a scrolling ScrollView AND the outermost clipper on the
	screen. `spec.scrolls = false` (the shipped `02_playlist_table`'s own idiom,
	and `row_capabilities`') was never mounted under a package at all, so the one
	shape a consumer actually ships was the shape nobody themed.

	WHAT THE DEVICE SAW, on the `ex02` playlist under a Glossy package:
	the header pills stood clear of the rows beneath them and the trailing
	heading ran past the last column. Measured headless afterwards at every swept
	viewport and every text preference: the header sat 17px inside its own rows on
	each side under Fantasy Ornate, Fantasy Parchment, Glossy Mobile and Glossy
	Touch, and 24px under Sci-Fi HUD — a heading that is not over its column.

	THE MECHANISM, and it is one number spent for a box that does not exist.
	`chromeBleed` is the glow gutter a CLIPPER owes its content, and
	`src/render/layout_node.luau` reserves it on the OUTERMOST clipper only. The
	header is a sibling of the body rather than a node inside it, so it pays that
	gutter itself — and it paid it unconditionally, on the assumption in its own
	comment that "the rows live in a ScrollView". A `scrolls = false` block table
	has no ScrollView and no clip: the body reserved nothing and the header
	reserved the bleed, so the two halves resolved their `fill` columns against
	width budgets that differed by 2x the bleed. The number is 0 under every flat
	package, which is why the defect could only ever be seen through a theme.

	It is the SAME argument `hasAlignedHeader` already makes one gutter over — a
	block table "has no viewport of its own to grow a bar in" — reached for the
	bar and missed for the glow.

	WHAT THIS ASSERTS: for all three shapes a Table's body can take, and every
	shipped package, a header cell and its column's body cell occupy the SAME
	horizontal span. Not "close" — the same, because a column boundary is the one
	place in a table where a pixel of drift is visible to the eye. ]]
describe("Table header: the columns line up with the rows in every body shape", function()
	local SHAPES = { "block", "viewport", "nested" }

	-- two `fill` columns, so a difference in the available width is DIVIDED
	-- between them and shows up as drift at every boundary rather than only at
	-- the trailing edge (the shape `02_playlist_table` ships)
	local function alignmentColumns(): { any }
		return {
			{
				id = "name",
				title = "Entrant",
				width = { type = "fill", weight = 3 },
				value = function(item: any)
					return item.name
				end,
			},
			{
				id = "team",
				title = "Team",
				width = { type = "fill", weight = 2 },
				value = function(item: any)
					return item.team
				end,
			},
		}
	end

	type Alignment = { drift: number, detail: string, bleed: number, toolbar: string }

	local function solveShape(packageName: string?, shape: string): Alignment
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
		-- a TOUCH session, so the auto Edit/Done toolbar mounts and the band has the
		-- third sibling the device report caught (`reorderable` below is its route)
		env:set("preferredInput", "Touch")
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new();
		(adapter :: any).scrollBarThickness = fake_target.SCROLL_BAR_RESERVE
		local presenter = Facet.newPresenter(core, env, adapter, system)
		local tbl = table_control.build(Facet, core, {
			id = "Entrants",
			columns = alignmentColumns(),
			rows = core:signal(RACERS),
			key = function(item: any)
				return item.id
			end,
			rowHeight = 40,
			selection = "single",
			-- a BLOCK delegates its scrolling to the host page; the other two own a
			-- viewport, and differ only in whether anything above them clips
			scrolls = if shape == "block" then false else nil,
			-- the auto Edit/Done route, so the toolbar row is in the band
			reorderable = true,
			onReorder = function() end,
			env = env,
		})
		local content: any = tbl.blueprint
		if shape ~= "viewport" then
			-- a page that scrolls: the host a block table is built for, and the
			-- ancestor that makes a viewport table's own body an INNER clipper
			content = Facet.UI.ScrollView({
				id = "Page",
				axis = "y",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = { content },
			})
		end
		presenter.present(Facet.UI.Screen({ id = "S", children = { content } }), {})
		for _ = 1, 4 do
			presenter.refresh()
		end
		if packageName ~= nil then
			local pkg = PACKAGES[packageName].build(Facet.themes)
			env:set("themeMetrics", Facet.themes.resolve(pkg, nil, {}))
			for _ = 1, 4 do
				presenter.refresh()
			end
		end
		local root = if shape == "viewport" then "/S/Entrants" else "/S/Page/Entrants"
		-- the row's own path is the ForEach key, and `rowActions` is absent here, so
		-- it is found rather than spelled: one grammar change must not silently turn
		-- this case into a check that compares nothing
		local cells: string? = nil
		for _, path in adapter.paths() do
			local match = string.match(path, "^(.*/Cells)/Cell%-name$")
			if match ~= nil then
				cells = match
				break
			end
		end
		assert(cells ~= nil, `{shape}: no body cell mounted, so there is nothing to line the header up with`)
		local drift = 0
		local detail = ""
		for _, columnId in { "name", "team" } do
			local head = adapter.node(`{root}/Main/Header/Head-{columnId}`)
			local cell = adapter.node(`{cells}/Cell-{columnId}`)
			assert(
				head ~= nil and cell ~= nil,
				`{shape}: column '{columnId}' has no {if head == nil then "header" else "body"} cell`
			)
			drift = math.max(
				drift,
				math.abs(head.rect.x - cell.rect.x),
				math.abs((head.rect.x + head.rect.w) - (cell.rect.x + cell.rect.w))
			)
			detail ..= string.format(
				" %s head %.0f..%.0f cell %.0f..%.0f",
				columnId,
				head.rect.x,
				head.rect.x + head.rect.w,
				cell.rect.x,
				cell.rect.x + cell.rect.w
			)
		end
		-- ...and the third sibling in the band. The Edit/Done toggle is right-aligned
		-- in a toolbar ROW (never a floating badge), so its trailing edge is the
		-- table's trailing content edge — the same one the last column ends on.
		local toolbar = adapter.node(`{root}/Main/ToggleWhen/then/Toolbar`)
		local toggle = adapter.node(`{root}/Main/ToggleWhen/then/Toolbar/EditToggle`)
		local band = adapter.node(`{root}/Main/Header`)
		local trailing = adapter.node(`{root}/Main/Header/Head-team`)
		assert(
			toolbar ~= nil and toggle ~= nil and band ~= nil and trailing ~= nil,
			`{shape}: the auto Edit toolbar did not mount, so its alignment proves nothing`
		)
		local snapshot = env:get("themeMetrics"):get()
		return {
			drift = drift,
			detail = detail,
			bleed = if type(snapshot.chromeBleed) == "number" then snapshot.chromeBleed else 0,
			toolbar = string.format(
				"editRight %.0f trailingColumnRight %.0f clearsHeaderBy %.0f",
				toggle.rect.x + toggle.rect.w,
				trailing.rect.x + trailing.rect.w,
				band.rect.y - (toolbar.rect.y + toolbar.rect.h)
			),
		}
	end

	it("a header cell and its body cell occupy the same span, in every shape and package", function()
		for _, shape in SHAPES do
			for _, name in ROWS do
				local pkg = if name == "studio-neutral" then nil else name
				local row = solveShape(pkg, shape)
				expect(`{shape}/{name}: drift 0px —{row.detail}`).toBe(
					`{shape}/{name}: drift {row.drift}px —{row.detail}`
				)
			end
		end
	end)

	--[[ THE THIRD SIBLING IN THE BAND, and the review's second sentence: "the Edit
		button sits ON TOP of the Rating header pill, overlapping it, drawn above and
		to the right".

		IT WAS NEVER A LAYOUT OVERLAP AND NEVER A Z-ORDER ONE. The toggle is a
		toolbar ROW inserted at the front of `Main`'s flow (director round 12 already
		moved it out of an Anchor for exactly this complaint), so it pushes the header
		down instead of covering it — asserted here as a NON-NEGATIVE clearance, at
		every package and every shape, so the flow can never quietly become an overlay
		again.

		WHAT WAS REAL WAS HORIZONTAL, and it is the same defect as the case above:
		the toolbar spelled no gutters, the header spelled its own, and the rows
		spelled a third set — three siblings, three budgets. Under the five packages
		that carve a border or a glow the button hung 17-27px past the trailing
		heading, over a heading that was itself 17px short of its own rows. One
		`bandPadding` now feeds all of them, so the button's trailing edge IS the
		trailing column's. ]]
	it("the Edit toolbar clears the header band and ends on the trailing column", function()
		for _, shape in SHAPES do
			for _, name in ROWS do
				local pkg = if name == "studio-neutral" then nil else name
				local row = solveShape(pkg, shape)
				local editRight, columnRight, clearance =
					string.match(row.toolbar, "editRight (%-?%d+) trailingColumnRight (%-?%d+) clearsHeaderBy (%-?%d+)")
				expect(`{shape}/{name}: button ends on the column, clearance {clearance}`).toBe(
					`{shape}/{name}: button ends {if editRight == columnRight
						then "on the column"
						else `{editRight} against a column at {columnRight}`}, clearance {clearance}`
				)
				expect(`{shape}/{name}: clears`).toBe(
					`{shape}/{name}: {if tonumber(clearance) :: number >= 0 then "clears" else "OVERLAPS THE HEADER"}`
				)
			end
		end
	end)

	--[[ THE CLEARANCE COVERS THE GLOW, NOT JUST ZERO (task SHOWCASE3, director
		repro: Samsung Galaxy S22 Ultra preset, Glossy Mobile — "the Edit
		button, Artist column pill, and '1 more' button sit right on top of
		each other, 0-1px spacing"). The case above only asserted a
		NON-NEGATIVE box clearance, which `controls.table.rowGap`'s flat 2px
		literal already satisfied — the two boxes never overlapped, so that
		assertion passed even while every shadowed package's own `chrome
		.control`/`chrome.chip` glow (up to `chromeBleed` px past each box)
		reached clean through the 2px seam into its neighbour, which is what
		reads on a device as "sitting right on top of each other" despite a
		technically-clearing gap. This asserts the REAL bar: the clearance
		must be at least the package's own `chromeBleed`, the same
		`math.max`-not-`+` idiom every sibling fix in this task uses for the
		identical class of fact. A flat package (`bleed` 0) still only needs
		`>= 0`, so this subsumes the case above rather than replacing it. ]]
	it("the Edit toolbar's clearance covers the chrome glow, not merely the zero floor", function()
		for _, shape in SHAPES do
			for _, name in ROWS do
				local pkg = if name == "studio-neutral" then nil else name
				local row = solveShape(pkg, shape)
				local clearance = tonumber(string.match(row.toolbar, "clearsHeaderBy (%-?%d+)"))
				expect(`{shape}/{name}: clearance {clearance}, bleed {row.bleed}`).toBe(
					`{shape}/{name}: clearance {math.max(clearance :: number, row.bleed)}, bleed {row.bleed}`
				)
			end
		end
	end)

	--[[ AND THE CORPUS REALLY DOES VARY ALONG THIS AXIS. The case above passes
		trivially for any package whose `chromeBleed` is 0 — it could pass forever
		with the defect intact if the reference packages ever went flat, which is the
		"instrument claiming more coverage than it has" class this whole file exists
		to close. So the bleed that makes the shapes differ is asserted to be there. ]]
	it("the swept packages really do declare a glow gutter, or this axis proves nothing", function()
		local bleeding = 0
		for _, name in ROWS do
			local pkg = if name == "studio-neutral" then nil else name
			if solveShape(pkg, "viewport").bleed > 0 then
				bleeding += 1
			end
		end
		expect(`{bleeding} of {#ROWS} packages carve a glow gutter`).toBe(`5 of {#ROWS} packages carve a glow gutter`)
	end)
end)
