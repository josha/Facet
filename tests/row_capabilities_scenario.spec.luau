--!strict
--[[ THE SHOWCASE SURFACE FOR THE PER-ROW CAPABILITY OPT-OUTS (parity round 3
	item C) — `examples/gallery/scenarios/row_capabilities.luau`.

	`tests/row_capability_optouts.spec.luau` proves the three predicates against
	hand-built worlds. This file proves the thing a player actually opens: that the
	shipped fixture demonstrates all three refusals through the routes a finger, a
	key and a pad really take, that it says WHO refused, and that it holds its
	layout at every viewport under every shipped theme and a ~1.4x localization.

	WHY THE "WHO REFUSED" CASE IS THE LOAD-BEARING ONE. The fixture's live line is
	written from inside the three predicates rather than from its button handlers,
	and the difference is only observable in one place: a move refused by the
	DESTINATION. Moving `warmup` up past the pinned `grid` is refused because a
	pinned row holds its index — so the line must name **Grid formation**, the row
	the framework asked about, and not **Warm-up lap**, the row the player pressed.
	A fixture that narrated from its handler would name the wrong row and every
	other case here would still pass.

	AND ONE FRAMEWORK DEFECT THIS FILE RECORDS RATHER THAN HIDES. Under Pixel Quest
	a Table's derived row box is ~16px shorter than the cell Text the table itself
	authors inside it, at every viewport and already at the default text
	preference. It is NOT this fixture's: the shipped `02_playlist_table` files the
	same class under the same package, and the `PRE-EXISTING` case below asserts
	exactly that, so the exception cannot quietly become a pardon for something
	this surface breaks later. It is invisible to `tests/overflow_sweep.spec.luau`
	because that sweep installs no theme package at all — it runs the flat
	(Studio Neutral) resolution only, which is the gap standing rule 4 names when
	it says "Pixel Quest and Parchment have both broken layouts that Studio
	Neutral survived".
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local fake_target = require("./lib/fake_target")
local snapshot = require("../src/themes/snapshot") :: any
local l10n = require("./fixtures/a11y_l10n_fixtures")
local fs = require("@lune/fs")
local demo_picker = require("../examples/gallery/client/demo_picker") :: any
local module = require("../examples/gallery/scenarios/row_capabilities") :: any
local playlist = require("../examples/gallery/examples/02_playlist_table") :: any

local ROOT = "/RowCapabilities/Page/RunSheet/Main/Body/Rows"

local function world(view: { w: number, h: number }, package: string?)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	if package ~= nil then
		-- built through the PUBLIC facade and resolved through the snapshot
		-- compiler — the same pair `tests/flow_wrap.spec.luau` §9 uses
		env:set(
			"themeMetrics",
			snapshot.resolve((require)(`../examples/themes/{package}`).build(LuauUI.themes), nil, {})
		)
	end
	local built = module.build({
		LuauUI = LuauUI,
		core = core,
		env = env,
		adapter = adapter,
		presenter = pres,
		actionSystem = system,
	})
	built.handle = pres.present(built.screen, built.present)
	for _ = 1, 3 do
		pres.refresh()
	end
	local w: any = { core = core, env = env, adapter = adapter, pres = pres }
	function w.settle(frames: number?)
		for _ = 1, frames or 120 do
			pres.tick(1 / 60)
			pres.refresh()
		end
	end
	function w.rowRoot(key: string): string
		return `{ROOT}/[{key}@0]/RowActions-{key}`
	end
	-- the row's own Hit — a real engine GuiButton, and the surface a tap, a
	-- Return and a ButtonA all land on
	function w.tapRow(key: string)
		adapter.touchTap(`{w.rowRoot(key)}/Content/Row/Hit`)
		pres.refresh()
	end
	--[[ a trailing (leftward) swipe past the reveal threshold, ending the way a
		real gesture does: the release Activates the row's own Hit on either side
		of InputEnded (`row_actions.luau`'s redteam BLOCKER, 2026-08-13), and a
		helper that stopped at pointerUp would be driving a sequence no engine
		produces. `frac` is of the row's OWN width, so a row-size change under a
		theme cannot silently stop this crossing the threshold. ]]
	function w.swipeOpen(key: string)
		local hit = `{w.rowRoot(key)}/Content/Row/Hit`
		local rect = adapter.node(hit).rect
		local startX, y = rect.x + rect.w - 8, rect.y + rect.h / 2
		local dx = -rect.w * 0.6
		adapter.pointerDown(hit, startX, y, "touch")
		for i = 1, 8 do
			adapter.pointerMove(startX + dx * (i / 8), y, "touch")
		end
		pres.refresh()
		adapter.pointerUpActivating(startX + dx, y, "after")
		w.settle()
	end
	function w.tapTray(key: string, actionId: string): boolean
		local path = `{w.rowRoot(key)}/TrayTrailingWhen/then/TrayTrailing/Action:{actionId}`
		if adapter.node(path) == nil then
			return false
		end
		adapter.touchTap(path)
		w.settle()
		return true
	end
	return w, built
end

local PHONE = { w = 320, h = 640 }

describe("row_capabilities showcase: the three refusals, through the routes a player takes", function()
	it("rowSelectable: a tap on the LOCKED row leaves the selection where it was", function()
		local w, built = world(PHONE)
		w.tapRow("warmup")
		expect(built.table_.dump().selectedKeys).toEqual({ "warmup" })
		-- ...and the locked row's own tap changes nothing. The selection staying
		-- put is the whole assertion: a refusal here is an ABSENCE, which is why
		-- the fixture also has to say who refused (below).
		w.tapRow("notes")
		expect(built.table_.dump().selectedKeys).toEqual({ "warmup" })
		-- the NEGATIVE CONTROL, in the same case: an ordinary row does take it,
		-- so `tapRow` is genuinely reaching the funnel
		w.tapRow("cool")
		expect(built.table_.dump().selectedKeys).toEqual({ "cool" })
		built.dispose()
	end)

	it("rowMovable: the PINNED row refuses to move, and the order does not change", function()
		--[[ MOVE DOWN, NOT UP, AND THE REASON IS A TEST THAT PASSED FOR THE WRONG
			REASON. `grid` is the FIRST row, so `moveRow(grid, -1)` lands on a slot
			below zero and the funnel refuses it on geometry before the predicate is
			ever consulted — mutating `rowMovable` to allow everything left that
			assertion green (mutation M2, 2026-08-14). Moving the first row DOWN is
			geometrically legal, so the predicate is the only thing that can refuse it. ]]
		local w, built = world(PHONE)
		local before = table.concat(built.ids(), ",")
		expect(built.steps.moveDown(built, "grid").ok).toBe(false)
		expect(table.concat(built.ids(), ",")).toBe(before)
		-- ...and an ordinary row moves, so the refusal is the predicate
		expect(built.steps.moveUp(built, "cool").ok).toBe(true)
		expect(table.concat(built.ids(), ",")).toBe("grid,warmup,main,cool,notes")
		built.dispose()
	end)

	it("rowDeletable: swipe the PROTECTED row, press Delete — and it is still there", function()
		local w, built = world(PHONE)
		w.swipeOpen("main")
		-- THE AFFORDANCE IS STILL DRAWN, deliberately, and this asserts it rather
		-- than assuming it: `row_actions.luau`'s delete gate is a commit-time
		-- thunk, so hiding the button would need the verdict as a reactive fact.
		-- A demo that quietly stopped painting it would be advertising a
		-- capability the framework does not have.
		expect(w.tapTray("main", "delete")).toBe(true)
		expect(table.concat(built.ids(), ",")).toBe("grid,warmup,main,notes,cool")
		-- the same gesture on an ordinary row removes it — the control without
		-- which "nothing happened" could just mean the swipe missed
		w.swipeOpen("cool")
		expect(w.tapTray("cool", "delete")).toBe(true)
		expect(table.concat(built.ids(), ",")).toBe("grid,warmup,main,notes")
		built.dispose()
	end)
end)

describe("row_capabilities showcase: the refusal is legible, and the PREDICATE is what wrote it", function()
	it("it names the row the FRAMEWORK asked about, not the row the player pressed", function()
		-- see this file's header: the destination case is the only place a
		-- predicate-written line and a handler-written line differ. `warmup` is
		-- what the player moves; `grid` is what the framework refuses over.
		local w, built = world(PHONE)
		expect(built.steps.moveUp(built, "warmup").ok).toBe(false)
		expect(built.refusal:get()).toBe(`{module.copy.rowGrid} — {module.copy.askMove} {module.copy.answerNo}`)
		built.dispose()
	end)

	it("each of the three refusals writes its OWN question, so the line says which capability said no", function()
		local w, built = world(PHONE)
		w.tapRow("notes")
		expect(built.refusal:get()).toBe(`{module.copy.rowNotes} — {module.copy.askSelect} {module.copy.answerNo}`)
		built.steps.moveUp(built, "grid")
		expect(built.refusal:get()).toBe(`{module.copy.rowGrid} — {module.copy.askMove} {module.copy.answerNo}`)
		w.swipeOpen("main")
		w.tapTray("main", "delete")
		expect(built.refusal:get()).toBe(`{module.copy.rowMain} — {module.copy.askDelete} {module.copy.answerNo}`)
		expect(built.refusals:get()).toBe(3)
		built.dispose()
	end)

	it("NEGATIVE CONTROL: nothing a permitted row does ever writes a line or moves the counter", function()
		-- without this, a fixture that narrated unconditionally would satisfy
		-- every case above while telling the player a lie on every gesture
		local w, built = world(PHONE)
		w.tapRow("warmup")
		expect(built.steps.moveUp(built, "cool").ok).toBe(true)
		w.swipeOpen("cool")
		expect(w.tapTray("cool", "flag")).toBe(true)
		expect(built.refusal:get()).toBe(module.copy.refusalIdle)
		expect(built.refusals:get()).toBe(0)
		built.dispose()
	end)
end)

--[[ ── STANDING RULE 4: REGISTERED IN BOTH PLACES ────────────────────────────

	"registered in `scenarios/init.luau` ORDER **and** `demo_picker.DEMOS`". The
	DEMOS -> ORDER direction is already an invariant over the whole catalogue
	(`tests/gallery_demo_picker.spec.luau`, "every fixture the picker offers is
	registered in the scenario registry's ORDER"), and the sweep covers the ORDER
	side. What neither of them can see is the direction that actually failed in
	round 3: a scenario reaching ORDER and the sweep while never entering DEMOS —
	`lifecycle_hidden` shipped that way on 2026-08-13 and was booked as O-15,
	selectable by workspace attribute and unreachable in-experience. So this asks
	the missing question, for both fixtures, by name.

	READ FROM THE SOURCE TEXT because `scenarios/init.luau` resolves each entry
	through `script:WaitForChild` and cannot be required headlessly — the same
	technique and the same reason as the demo-picker spec's own registry audit. ]]
describe("row_capabilities showcase: standing rule 4 — registered in BOTH places", function()
	local function orderNames(): { [string]: boolean }
		local source = fs.readFile("examples/gallery/scenarios/init.luau")
		local block = string.match(source, "local ORDER = (%b{})")
		assert(block ~= nil, "scenarios/init.luau no longer has a `local ORDER = { ... }` block to read")
		local names: { [string]: boolean } = {}
		local count = 0
		for name in string.gmatch(block :: string, '"([%w_]+)"') do
			names[name] = true
			count += 1
		end
		-- the parse has to be believable before anything is asserted on it
		assert(count > 20, `the ORDER parse found only {count} entries — the block shape changed`)
		return names
	end

	it("both round-3 fixtures are in ORDER and in DEMOS — the direction O-15 fell through", function()
		local order = orderNames()
		local missing: { string } = {}
		for id, scenario in { ["row-capabilities"] = "row_capabilities", ["lifecycle-hidden"] = "lifecycle_hidden" } do
			local demo = demo_picker.find(id)
			if order[scenario] ~= true then
				table.insert(missing, `scenarios/init.luau ORDER is missing '{scenario}'`)
			end
			if demo == nil then
				table.insert(missing, `demo_picker.DEMOS is missing '{id}'`)
			elseif (demo :: any).module ~= scenario then
				table.insert(missing, `demo '{id}' names module '{(demo :: any).module}', not '{scenario}'`)
			end
		end
		expect(table.concat(missing, "; ")).toBe("")
	end)

	it("...and the always-on sweep names it, so dropping it is a failure and not a smaller green run", function()
		-- the third half of standing rule 4 ("swept by tests/overflow_sweep.spec.luau
		-- at all viewports"). A surface absent from that list produces no case at
		-- all, and a missing case is indistinguishable from a passing one on any
		-- transcript — the failure mode `an instrument nobody runs is a comment`
		-- names. Read from the source text so the assertion is about the REGISTRY
		-- rather than about whichever cases happened to run in this process.
		local sweep = fs.readFile("tests/overflow_sweep.spec.luau")
		local block = string.match(sweep, "local SCENARIOS = (%b{})")
		assert(block ~= nil, "overflow_sweep.spec.luau no longer has a `local SCENARIOS = { ... }` block")
		expect(string.find(block :: string, '"row_capabilities"', 1, true) ~= nil).toBe(true)
	end)
end)

--[[ ── THE SHIPPED PACKAGES ───────────────────────────────────────────────────

	STUDIO NEUTRAL IS NOT EVIDENCE ON ITS OWN, and `tests/overflow_sweep.spec.luau`
	only has Studio Neutral: it installs no `themeMetrics` at all, so the always-on
	sweep's eight viewports and four text preferences all run the flat resolution.
	Every geometry claim about this surface under a real package is made here.
]]
local PACKAGES = {
	"glossy_mobile",
	"glossy_touch",
	"pixel_quest",
	"fantasy_ornate",
	"scifi_hud",
	"compact_pointer",
	"classic_desktop",
	"fantasy_parchment",
}
-- the narrowest supported viewport in both orientations plus a desktop: a
-- landscape-only defect is how the 2026-08-12 round's B5 survived a portrait
-- capture set
local VIEWS = { { w = 320, h = 640 }, { w = 640, h = 320 }, { w = 1232, h = 1067 } }

-- THE ONE EXCEPTION, DERIVED RATHER THAN LISTED: a Table cell Text the TABLE
-- itself authored, overflowing the row box the TABLE itself derived. Nothing this
-- fixture declares participates in either number — no `rowHeight`, no custom
-- `cell` — which is what makes it recognisable as somebody else's.
local function isTableRowBoxClass(finding: any): boolean
	return string.find(finding.issue, "overflows its zstack", 1, true) ~= nil
		and string.find(finding.node, "/Cells/", 1, true) ~= nil
end

-- ...AND IT IS A CEILING, NOT A PARDON (`overflow_sweep.spec.luau`'s waiver rule
-- 2). Measured 2026-08-14: Pixel Quest, 16px, every row and both columns, at all
-- three viewports. Without the bound the class name alone would excuse anything
-- that ever lands in a table cell — mutation M8 put a custom `cell` blueprint
-- back in the name column, produced 27-74px overflows of exactly this shape, and
-- the unbounded version stayed green.
local ROW_BOX_CEILING = 16

local function largestPx(issue: string): number
	local best = 0
	for a, b in string.gmatch(issue, "(%d+)x(%d+)px") do
		best = math.max(best, tonumber(a) or 0, tonumber(b) or 0)
	end
	for n in string.gmatch(issue, "(%d+)px") do
		best = math.max(best, tonumber(n) or 0)
	end
	return best
end

local function isWaived(finding: any): boolean
	return isTableRowBoxClass(finding) and largestPx(finding.issue) <= ROW_BOX_CEILING
end

describe("row_capabilities showcase: it holds under every shipped package", function()
	it("no finding of its OWN in any package at any of the three viewports", function()
		local problems: { string } = {}
		for _, package in { false, table.unpack(PACKAGES) } do
			local name = if package == false then "flat" else tostring(package)
			for _, view in VIEWS do
				local w, built = world(view, if package == false then nil else tostring(package))
				for _, finding in built.handle.controller.diagnostics() do
					if isWaived(finding) then
						continue
					end
					table.insert(problems, `  {name} at {view.w}x{view.h}: {finding.node} — {finding.issue}`)
				end
				expect(w.core:lastError()).toBeNil()
				built.dispose()
			end
		end
		if #problems > 0 then
			error(
				`row_capabilities files {#problems} finding(s) of its own under a shipped package:\n`
					.. table.concat(problems, "\n"),
				0
			)
		end
	end)

	it("PRE-EXISTING: the one waived class fires on the shipped playlist too, under the same package", function()
		--[[ A WAIVER IS A CEILING AND A CONTROL, NEVER A PARDON. The case above
			excuses a class; this one proves the class belongs to `newTable` and not
			to this fixture, by finding it on a surface this mission did not write —
			and it fails if somebody ever FIXES the framework defect, which is the
			point (a waiver that fires nowhere is fiction, `overflow_sweep`'s own
			rule 4). Measured 2026-08-14: Pixel Quest, 30 findings across the three
			viewports, none larger than 16px. ]]
		local worst, mine = 0, 0
		for _, view in VIEWS do
			local _, built = world(view, "pixel_quest")
			for _, finding in built.handle.controller.diagnostics() do
				if isTableRowBoxClass(finding) then
					mine += 1
					worst = math.max(worst, largestPx(finding.issue))
				end
			end
			built.dispose()
		end
		expect(mine > 0).toBe(true)
		expect(`worst waived overflow: {worst}px (ceiling {ROW_BOX_CEILING}px)`).toBe(
			`worst waived overflow: {ROW_BOX_CEILING}px (ceiling {ROW_BOX_CEILING}px)`
		)

		-- ...and the control: the shipped playlist example, same package, same class
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = PHONE.w, h = PHONE.h })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		env:set(
			"themeMetrics",
			snapshot.resolve((require)("../examples/themes/pixel_quest").build(LuauUI.themes), nil, {})
		)
		local built =
			playlist.build(LuauUI, core, { env = env, actionSystem = system, presenter = pres, adapter = adapter })
		built.handle = built.handle or pres.present(built.screen, built.present)
		for _ = 1, 3 do
			pres.refresh()
		end
		local theirs = 0
		for _, finding in built.handle.controller.diagnostics() do
			if isTableRowBoxClass(finding) then
				theirs += 1
			end
		end
		if theirs == 0 then
			error(
				"the Table row-box class no longer fires on 02_playlist_table under pixel_quest — "
					.. "if the framework was fixed, delete the waiver in the case above (that is the point "
					.. "of it); if it moved, re-record it. It must never be excused for this fixture alone.",
				0
			)
		end
	end)
end)

describe("row_capabilities showcase: the copy survives a ~1.4x pseudo-localization", function()
	it("every player-visible string expands, and nothing this fixture owns overflows", function()
		--[[ The module's `copy` table is mutated IN PLACE and restored on every
			path including a throw — the same shape `examples_gallery.spec.luau`'s
			`underPseudoLocalization` uses, and for the same reason: the fixture reads
			that exact table at build time, so expanding a copy of it would be
			pseudo-localizing strings nothing on screen renders. ]]
		local original: { [string]: string } = {}
		for key, value in module.copy do
			original[key] = value
			module.copy[key] = l10n.pseudoLocalize(value)
		end
		local ok, err = pcall(function()
			local problems: { string } = {}
			for _, view in VIEWS do
				local _, built = world(view)
				for _, finding in built.handle.controller.diagnostics() do
					if isWaived(finding) then
						continue
					end
					table.insert(problems, `  {view.w}x{view.h}: {finding.node} — {finding.issue}`)
				end
				built.dispose()
			end
			if #problems > 0 then
				error(`pseudo-localized row_capabilities overflows:\n{table.concat(problems, "\n")}`, 0)
			end
		end)
		for key, value in original do
			module.copy[key] = value
		end
		if not ok then
			error(err, 0)
		end
		-- ...and the expansion really happened: a case that restored before it
		-- asserted would be green against the English strings
		expect(#module.copy.title < #l10n.pseudoLocalize(module.copy.title)).toBe(true)
	end)
end)
