--!strict
--[[ THEMED CONTAINMENT — the invariant asked under a PACKAGE (task THEME,
	director items 6-9, 2026-08-27).

	THE ESCAPE THIS ANSWERS, and it is one sentence: THE CONTAINMENT INVARIANT HAD
	NEVER BEEN RUN UNDER A THEME. `tests/overflow_sweep.spec.luau` swings all eight
	shipped packages onto every swept surface — and on those passes it collects
	`controller.diagnostics()` and nothing else; `overflow_guard.violations` runs
	once per viewport, on the freshly-mounted NEUTRAL tree, before the first
	`env:set("themeMetrics")`. So the one instrument that asks "is this rect inside
	the box it lives in" was structurally blind to every package that carves a
	border, which is every ornate package this library ships. Measured the day this
	file was written: the neutral pass reports ZERO across the showcase corpus and
	the eight packages report 92 violations the suite had never asked about — before
	the guard was taught what a themed edge even is.

	THE FOUR PHOTOGRAPHS, root-caused, because this file is where their numbers live
	(IMG_3785-8, a physical handheld under Pixel Quest):

	  6  Three round HUD buttons painting NO mark at all. Pixel Quest's `control`
	     recipe carves 16px per side; the buttons are `controlSizes.compact.height`
	     = 36. `chrome_slots.spendInset` asked "is anything left" — 4 is a positive
	     number — so the solver reserved a 4x4 content box and the paint seam drew a
	     16px glyph into it. The floor is now the node's own text size at BOTH
	     seams, so the reservation comes back, the glyph draws, and the solver's
	     `chromeYield` diagnostic says the control is smaller than its theme expects.
	  7  The task panel's `+50`/`+120`/`+300` reward chips painting over the plank
	     frame's right border. The HUD's `glass()` is `ZStack{ Box(surface, fill),
	     content }` — the plate is the content's SIBLING, so the framework's chrome
	     reservation landed on a childless node and the content cleared nothing.
	     Measured at 1079x809: the panel is 288 wide at x=8 (a content box of
	     32..272 under a 24px `panel` inset) and `Reward1` ended at 286.
	  8  Tab labels with no padding, overlapping the focus plate.
	     `selection_indicator`'s pill inset the plate by `space.xs` INSIDE a segment
	     whose own label spans the whole segment: 128x36 of plate under a 136x44
	     label, and the plate's themed content box is 96x4. The pill's decorative
	     inset now gives way to the package's carved border first.
	  9  The edit-mode delete disc overlapping the row's leading edge. The disc is
	     `shape = "circle"` + `icon`, and the icon floor raised it to `iconSizes` +
	     ITS OWN CHROME PADDING (32 + 32 = 64) while the gutter `row_actions`
	     reserves is `editAffordance + rowGutter` = 36 — two theme facts, nothing
	     making them agree. With the inset given back the disc is 32 and the gutter
	     holds it.

	     ...AND THAT FIXED THE PACKAGE, NOT THE CLASS (fix round, 2026-08-28,
	     review finding C1). The disc's floor still grew without any bound, so the
	     photograph came straight back under a package one design pixel thinner: at
	     a `control` inset of 4 per side the inset is SPENDABLE, the floor wants 40
	     and the gutter is 36. The room the row reserves is now DECLARED
	     (`chrome_slots.Hint.footprint`, from the same `EDIT_FOOTPRINT` list
	     `editGutterPx` resolves), the floor stops there, and the solver files
	     `sizeRefused`. The last group in this file sweeps the inset instead of
	     pinning one package's rects, which is the difference between the two.

	WHAT THIS FILE IS. The always-on floor for the class, at the MEASURED MINIMUM
	that catches it rather than the whole cross product: the three surfaces the
	director photographed (plus the playlist in the STATE he photographed it in),
	under the two ornate packages with the fattest and the second-fattest carved
	borders, at the two viewports where each surface's ladder builds its rich form.
	The corpus-wide number the same oracle reports is recorded in the task report
	and is NOT green yet — this is a floor under the four, not a claim about the
	library.

	AND ITS NEGATIVE CONTROLS. Two of the guard's three themed rules are new here,
	so each is shown BITING on a screen built to break it and SILENT on the screen
	one edit away that is legal. Without those a green file above is a file that
	might not be looking.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local UI = require("../src/blueprint")
local fake_target = require("./lib/fake_target")
local worldLib = require("./lib/world")
local overflow_guard = require("./lib/overflow_guard")
local device_views = require("./lib/device_views")
local chrome_slots = require("../src/tokens/chrome_slots")
local demo_picker = require("../examples/gallery/client/demo_picker") :: any

-- the showcase's own chrome reservation, read from the picker exactly as
-- `tests/overflow_sweep.spec.luau` reads it, so both files lay out against the
-- screen a player actually gets rather than a 62px-taller one
local SHOWCASE_TOP = demo_picker.barReservation(device_views.CORE_TOP, nil, 8)

-- THE TWO ORNATE PACKAGES, and the pair is the measurement rather than a
-- preference: Pixel Quest carves the most (`panel` 24, `control`/`selection` 16)
-- and Fantasy Ornate the second most (`panel` 30, `control` 10/14) with a
-- 17px shadow bleed on top, and they disagree about every metric that decides
-- these four surfaces. A fix that is pixel-quest-shaped fails on the second one.
local PACKAGES: { { id: string, snapshot: any } } = {}
for _, id in { "pixel_quest", "fantasy_ornate" } do
	local module = require(`../examples/themes/{id}`) :: any
	local pkg, report = module.build(Facet.themes)
	assert(pkg ~= nil, `{id} failed its own package gate: {report and report.errors[1] and report.errors[1].message}`)
	table.insert(PACKAGES, { id = id, snapshot = Facet.themes.resolve(pkg, nil, {}) })
end

local VIEWS: { any } = {}
for _, view in device_views.VIEWS do
	-- the two rows every one of these surfaces builds its RICH form at (the HUD's
	-- task panel steps down to a chip below them, and the nested tab strip has no
	-- second bar on a phone) plus the narrowest supported box, which is where a
	-- carved border costs the largest fraction of the screen
	if view.id == "tablet-landscape" or view.id == "compact-phone-landscape" or view.id == "narrow-portrait" then
		table.insert(VIEWS, view)
	end
end
assert(#VIEWS == 3, "the three swept views did not resolve — device_views.VIEWS was renamed")

--[[ THE SHARED SUBSTRATE, not a hand-rolled builder (R12's follow-up trigger,
	mechanised by `tests/world_substrate.spec`: the next spec file that ADDS a
	builder migrates its file instead). `tests/lib/world.luau` owns the two
	construction invariants this file would otherwise have to remember — the
	viewport is set BEFORE the presenter exists, and the adapter is built before it
	and never shared — and it takes the scroll-bar thickness through `newAdapter`,
	which is the seam that exists for exactly this.

	ITS OWN CONTAINMENT GUARD IS OFF, WITH THE REASON IN THE CONSTRUCTOR, because
	this file's whole job is to ask the guard BY HAND with a package in its hands,
	and three of its fixtures are deliberately broken screens. The neutral question
	the substrate would ask is already asked of every one of these surfaces by
	`tests/overflow_sweep.spec.luau`. ]]
local GUARD_OFF = "this file asks the guard BY HAND under a theme package, and its "
	.. "negative controls are deliberately broken screens"

local function world(view: any): any
	local w = worldLib.new({
		viewport = { x = 0, y = 0, w = view.w, h = view.h },
		safeInsets = { top = SHOWCASE_TOP, bottom = 0, left = 0, right = 0 },
		displaySize = view.displaySize,
		preferredInput = view.input,
		capabilities = device_views.CAPABILITIES[view.input],
		newAdapter = function()
			local adapter = fake_target.new() :: any
			adapter.scrollBarThickness = fake_target.SCROLL_BAR_THICKNESS
			return adapter
		end,
		overflowGuardOff = GUARD_OFF,
	})
	-- the scenario contract calls its presenter `presenter`; the substrate calls it
	-- `pres`. One object, both names, so nothing below has to know which.
	w.presenter = w.pres
	return w
end

local function settle(w: any)
	for _ = 1, 3 do
		w.presenter.refresh()
	end
end

local function scenarioCtx(w: any): any
	return {
		Facet = Facet,
		core = w.core,
		env = w.env,
		adapter = w.adapter,
		presenter = w.presenter,
		actionSystem = w.system,
		record = function() end,
		flags = {},
		geometry = function(paths: { string }): { [string]: any }
			local out: { [string]: any } = {}
			for _, path in paths do
				local node = w.adapter.node(path)
				if node ~= nil and node.rect ~= nil then
					out[path] = node.rect
				end
			end
			return out
		end,
		bindResourceTransport = function()
			return function() end
		end,
	}
end

local function mountScenario(w: any, name: string): any
	local module = require(`../examples/gallery/scenarios/{name}`) :: any
	local built = module.build(scenarioCtx(w))
	if built.handle == nil and built.screen ~= nil then
		built.handle = w.presenter.present(built.screen, built.present)
	end
	return built
end

local function mountExample(w: any, name: string): any
	local module = require(`../examples/gallery/examples/{name}`) :: any
	local built = module.build(
		Facet,
		w.core,
		{ env = w.env, actionSystem = w.system, presenter = w.presenter, adapter = w.adapter }
	)
	if built.handle == nil and built.screen ~= nil then
		built.handle = w.presenter.present(built.screen, built.present)
	end
	return built
end

--[[ THE HUD'S PLATE LEDGER, and it is a to-do list with a measurement on every
	line rather than a list of things that are allowed.

	Every row here is the SAME defect — `glass()` in `examples/gallery/scenarios/hud.luau`
	is `ZStack{ Box(surface = "raised", fill x fill), content }`, so the plate is the
	content's SIBLING and the package's carved border is reserved on a node with no
	children (ADR-0059 Decision 2 says at length why the framework declines to spend
	it for them: on a HUD pill, Fantasy Ornate's `panel` recipe is a 30px window
	border, and handing it over turns a 116x41 objective chip into a 92x85 blob —
	measured). The task PANEL, which is the one plate here big enough to wear its own
	frame and the one the director photographed, is fixed at its declaration and is
	deliberately absent from this list.

	THE RULES, the same four the overflow sweep's own waiver list is under:
	  * `px` is the largest overhang measured on 2026-08-27 across this file's
	    packages x viewports. A finding above it FAILS — the defect got worse.
	  * a row that never fires FAILS too (the case below counts them), so this list
	    can only shrink and the number means something.
	  * a row is a NODE PATTERN, because one wrong construction is one defect and
	    not eleven: the three rail slots and the three probe lines are one plate
	    idiom each.
	  * nothing here is a `zero-box`. There is no design in which a string the
	    player is meant to read solves to nothing, and no row may pardon one. ]]
type PlateRow = { node: string, px: number, why: string }
local HUD_PLATE_LEDGER: { PlateRow } = {
	{ node = "/Clock/ClockStack/ScoreAway/", px = 20, why = "a score pill's numeral on the plank frame" },
	{ node = "/Clock/ClockStack/ScoreHome/", px = 20, why = "its twin at the other end of the clock" },
	{ node = "/Clock/ClockStack/TimerPod/", px = 20, why = "the timer's ring and its figure, same pill" },
	{ node = "/Clock/TimerOnlyPod/", px = 20, why = "the narrow-viewport rung of the same pill" },
	{ node = "/Health/HealthPod/", px = 20, why = "the health pill's numeral" },
	{ node = "/Health/HealthOnly/", px = 20, why = "the narrow-viewport rung of the health pill" },
	{ node = "/Rail/RailTall/", px = 20, why = "the weapon rail's three slots, one construction" },
	{ node = "/Rail/W1c/", px = 20, why = "the rail's compact rung" },
	{ node = "/Strip/StripChip/", px = 20, why = "the objective chip" },
	{ node = "/Tasks/TasksChip/", px = 20, why = "the task zone's stepped-down chip" },
	{
		node = "/PaintProbe/",
		px = 16,
		why = "the fixture's OWN readout plate — an instrument, not a HUD surface, and it wears the same idiom",
	},
}
local PLATE_HITS: { [string]: number } = {}
for _, row in HUD_PLATE_LEDGER do
	PLATE_HITS[row.node] = 0
end

local function ledgered(violation: any, ledger: { PlateRow }?): string?
	if ledger == nil or violation.kind ~= "outside-parent" then
		return nil
	end
	for _, row in ledger do
		if string.find(violation.node, row.node, 1, true) == nil then
			continue
		end
		if violation.overhang > row.px then
			return `WORSE than the recorded row: {violation.overhang}px against a {row.px}px ceiling`
		end
		PLATE_HITS[row.node] += 1
		return nil
	end
	return nil
end

--[[ THE PACKAGE IS SWUNG ONTO A STANDING MOUNT, which is the seam the theme
	picker itself drives and the one the overflow sweep already proved equivalent to
	a fresh mount over its whole cross product. `after` runs once the package is
	live, so a state this surface can only be opened INTO is opened while wearing
	the theme rather than before it. ]]
local function judge(label: string, mount: (any) -> any, after: ((any, any) -> ())?, ledger: { PlateRow }?)
	local problems: { string } = {}
	for _, view in VIEWS do
		for _, pkg in PACKAGES do
			local w = world(view)
			local built = mount(w)
			settle(w)
			w.env:set("themeMetrics", pkg.snapshot)
			settle(w)
			if after ~= nil then
				after(w, built)
				settle(w)
			end
			for _, violation in overflow_guard.violations(w.adapter, overflow_guard.newLedger({}), pkg.snapshot) do
				local worse = ledgered(violation, ledger)
				if ledger ~= nil and worse == nil and violation.kind == "outside-parent" then
					local known = false
					for _, row in ledger do
						known = known or string.find(violation.node, row.node, 1, true) ~= nil
					end
					if known then
						continue
					end
				end
				table.insert(
					problems,
					`  {view.id} ({view.w}x{view.h}) under {pkg.id}: `
						.. overflow_guard.describe(violation)
						.. (if worse ~= nil then `\n      ^ {worse}` else "")
				)
			end
		end
	end
	if #problems > 0 then
		error(
			`{label}: {#problems} themed containment violation(s) — content painting outside the box a `
				.. `PACKAGE draws, which is the class director items 6-9 came through `
				.. `(tests/themed_containment.spec.luau):\n{table.concat(problems, "\n")}`,
			0
		)
	end
end

describe("themed containment: the surfaces the director photographed", function()
	it("the screen-anchored HUD keeps every mark inside its themed plates (items 6 and 7)", function()
		judge("scenario 'hud'", function(w)
			return mountScenario(w, "hud")
		end, nil, HUD_PLATE_LEDGER)
	end)

	it("the nested tab view keeps every label inside its themed plates (item 8)", function()
		judge("scenario 'tab_view'", function(w)
			return mountScenario(w, "tab_view")
		end)
	end)

	it("the playlist table keeps every cell inside its themed plates", function()
		judge("example '02_playlist_table'", function(w)
			return mountExample(w, "02_playlist_table")
		end)
	end)

	--[[ EDIT MODE IS A STATE, AND A SWEEP THAT ONLY JUDGES THE SETTLED SCREEN IS
		BLIND TO IT — the same hole `stateProblems` closes one file over. Item 9 is
		only reachable after the Edit toggle, so the toggle is pressed here, THROUGH
		THE SHIPPED AFFORDANCE (a tap on the toolbar's `EditToggle`) rather than by
		reaching for a signal, so what is judged is the journey a player takes. ]]
	it("...and in EDIT MODE, where the delete disc lives (item 9)", function()
		local pressed = 0
		judge("example '02_playlist_table' in edit mode", function(w)
			return mountExample(w, "02_playlist_table")
		end, function(w, _built)
			for _, path in w.adapter.paths() do
				if string.find(path, "EditToggle", 1, true) ~= nil then
					w.adapter.tap(path)
					pressed += 1
					break
				end
			end
		end)
		-- THE ANTI-VACUITY CLAUSE: a green pass over a surface that never entered
		-- edit mode is a green pass over the surface the case above already judged.
		expect(pressed).toBe(#VIEWS * #PACKAGES)
	end)
end)

describe("themed containment: the four measurements, pinned", function()
	local PIXEL = PACKAGES[1].snapshot
	assert(PACKAGES[1].id == "pixel_quest", "the pinned numbers below are Pixel Quest's")

	local function tabletHud(): (any, any)
		local view: any = nil
		for _, v in device_views.VIEWS do
			if v.id == "tablet-landscape" then
				view = v
			end
		end
		local w = world(view)
		local built = mountScenario(w, "hud")
		settle(w)
		w.env:set("themeMetrics", PIXEL)
		settle(w)
		return w, built
	end

	it("item 6: the round HUD chip has room for its own mark, and the framework can prove it", function()
		local w, built = tabletHud()
		local disc = w.adapter.node("/HudScreen/Hud/Rounds/RoundStrip/R1")
		expect(disc ~= nil).toBe(true)
		-- the disc keeps the diameter its theme asked for
		expect(disc.rect.w).toBe(36)
		expect(disc.rect.h).toBe(36)
		--[[ ...and the package no longer asks for a frame it cannot fit inside that
			diameter: `pixel_quest`'s `control` recipe reserves the TWO design pixels
			its art actually carves rather than the four its nine-slice border needs for
			the stretch rule, so 36 - 16 leaves 20 for a 16px glyph and the framework
			has nothing to report. Before the correction the reservation was 32 and the
			glyph was drawn into 4x4 — which nothing anywhere said a word about. ]]
		for _, finding in built.handle.controller.diagnostics() do
			if string.find(finding.node, "/RoundStrip/", 1, true) ~= nil then
				error(`the HUD chip strip still files: {finding.issue}`, 0)
			end
		end
	end)

	--[[ ...AND THE FRAMEWORK HALF, which is the half that has to hold when the NEXT
		package gets this wrong. `spendInset`'s affordability test used to be "is
		anything left", and 4 is a positive number; it is now "is enough left for what
		this node draws", and the node's own text size is that number. Both directions
		are asserted, on the exact arithmetic the director's item 6 was made of. ]]
	it("item 6, the framework half: a chrome inset may not eat through the node's own line box", function()
		-- 36px disc, no authored padding, 32px of frame: 4 left
		expect(chrome_slots.spendInset(36, 0, 32, 16)).toBe(0)
		-- ...and with no floor declared, the pre-2026-08-27 rule, byte for byte
		expect(chrome_slots.spendInset(36, 0, 32)).toBe(32)
		-- 16px of frame on the same disc leaves 20, which is room for the glyph
		expect(chrome_slots.spendInset(36, 0, 16, 16)).toBe(16)
		-- an unbounded axis affords everything, floor or no floor
		expect(chrome_slots.spendInset(math.huge, 0, 32, 16)).toBe(32)
		-- ...and the PAINT seam reaches the same verdict from the same number, or
		-- the label is drawn into a box the solver no longer believes in
		local starved = chrome_slots.liftGeometry(
			{ contentInsets = { top = 16, right = 16, bottom = 16, left = 16 } },
			36,
			36,
			16,
			16
		)
		expect(starved.size.xOffset).toBe(0)
		expect(starved.size.yOffset).toBe(0)
		local fits =
			chrome_slots.liftGeometry({ contentInsets = { top = 8, right = 8, bottom = 8, left = 8 } }, 36, 36, 16, 16)
		expect(fits.size.xOffset).toBe(-16)
	end)

	it("item 7: the task panel's reward chip clears the plank frame it sits in", function()
		local w = tabletHud()
		local panel = w.adapter.node("/HudScreen/Hud/Tasks/TasksFull")
		local reward = w.adapter.node("/HudScreen/Hud/Tasks/TasksFull/TasksFullBody/TaskRow1/Reward1")
		expect(panel ~= nil and reward ~= nil).toBe(true)
		-- Pixel Quest's `panel` recipe carves 24 per side out of the plate
		local inner = { x = panel.rect.x + 24, right = panel.rect.x + panel.rect.w - 24 }
		expect(reward.rect.x >= inner.x).toBe(true)
		expect(reward.rect.x + reward.rect.w <= inner.right).toBe(true)
	end)

	it("item 8: the pill covers the whole segment it marks instead of shrinking inside it", function()
		local view: any = nil
		for _, v in device_views.VIEWS do
			if v.id == "compact-phone-landscape" then
				view = v
			end
		end
		local w = world(view)
		mountScenario(w, "tab_view")
		settle(w)
		w.env:set("themeMetrics", PIXEL)
		settle(w)
		local root = "/TabViewDemo/Root/App/Content/Tab-pages/then/Page/TopHome/then/TopBandCenter/TopBand/Strip"
		local bar = w.adapter.node(`{root}/Indicator/Layer/Bar`)
		local seg = w.adapter.node(`{root}/Indicator/Options/Opt1`)
		expect(bar ~= nil and seg ~= nil).toBe(true)
		expect(bar.rect.w).toBe(seg.rect.w)
		expect(bar.rect.h).toBe(seg.rect.h)
	end)

	it("item 9: the edit-mode delete disc fits the gutter the row leaves for it", function()
		local view: any = nil
		for _, v in device_views.VIEWS do
			if v.id == "compact-phone-portrait" then
				view = v
			end
		end
		local w = world(view)
		mountExample(w, "02_playlist_table")
		settle(w)
		w.env:set("themeMetrics", PIXEL)
		settle(w)
		for _, path in w.adapter.paths() do
			if string.find(path, "EditToggle", 1, true) ~= nil then
				w.adapter.tap(path)
				break
			end
		end
		settle(w)
		local judged = 0
		for _, path in w.adapter.paths() do
			if string.find(path, "/EditAffordanceWhen/then/EditAffordance", 1, true) == nil then
				continue
			end
			local disc = w.adapter.node(path)
			local rowPath = string.gsub(path, "/EditAffordanceWhen/then/EditAffordance$", "/Content/Row")
			local row = w.adapter.node(rowPath)
			expect(row ~= nil).toBe(true)
			-- the disc ends where the row begins: no overlap, at any row
			expect(disc.rect.x + disc.rect.w <= row.rect.x).toBe(true)
			judged += 1
		end
		expect(judged >= 6).toBe(true)
	end)
end)

--[[ ITEM 9 AS A PROPERTY, NOT AS TWO NUMBERS (task THEME fix round, 2026-08-28;
	review finding C1; ADR-0059 Decision 6).

	THE CASE ABOVE PINS THE SHIPPED RECTS, and that is not the same claim as "the
	class is dead". It reproduced under a package one design pixel thinner: with
	Pixel Quest's `control` inset at 4 per side — still a multiple of its own
	`pixelUnit`, still green against its own package gate — the inset became
	SPENDABLE (32 - 8 = 24 is above the 16px line-box floor), the disc's padding
	became 4, the `shape = "circle"` icon floor raised it to `iconSizes.medium` 32
	plus 8 = 40, and a 40px disc at x=16 painted onto a row starting at x=52. Four
	pixels onto EVERY row: IMG_3788, from a legal package, with the round that
	"fixed item 9" already landed.

	SO THIS SWEEPS THE INSET rather than one package's value, and asserts the
	INVARIANT the row and the disc are really about: the affordance never exceeds
	the room the row reserved for it. Three values, chosen by measurement rather
	than taste — 4 is the one that used to break (the inset is spent AND the floor
	then wants more than the gutter), 8 is the shipped value (spent, floor fits),
	12 is the largest that snaps below the refusal boundary (the inset is given
	back entirely). Each is a package the gate accepts.

	AND THE OTHER HALF OF REFUSE-OR-CATCH. A cap that silently shrank the disc
	would pass the invariant while hiding a package whose icon does not fit its own
	control, so the arm that used to overflow must also FILE — one `sizeRefused`
	per row, naming both numbers. ]]
describe("themed containment: item 9's class, at every legal package", function()
	local pixel_quest = require("../examples/themes/pixel_quest") :: any

	local INSETS = { 4, 8, 12 }

	local function snapshotAt(px: number): any
		local def = pixel_quest.definition(Facet.themes)
		if px ~= 8 then
			for _, slot in { "control", "field", "selection", "stepperPlate" } do
				def.chrome[slot].contentInsets = { top = px, right = px, bottom = px, left = px }
			end
			def.identity.id = `{pixel_quest.id}-inset{px}`
		end
		local pkg, report = Facet.themes.define(def)
		assert(
			pkg ~= nil,
			`pixel_quest at control inset {px} is NOT a legal package, so it cannot stand for one: `
				.. `{report and report.errors[1] and report.errors[1].message}`
		)
		return Facet.themes.resolve(pkg, nil, {})
	end

	it("the edit affordance never exceeds the gutter the row reserved for it", function()
		local view: any = nil
		for _, v in device_views.VIEWS do
			if v.id == "compact-phone-portrait" then
				view = v
			end
		end
		local problems: { string } = {}
		local refusedAt: { [number]: number } = {}
		local judgedAt: { [number]: number } = {}
		for _, px in INSETS do
			local w = world(view)
			local built = mountExample(w, "02_playlist_table")
			settle(w)
			w.env:set("themeMetrics", snapshotAt(px))
			settle(w)
			for _, path in w.adapter.paths() do
				if string.find(path, "EditToggle", 1, true) ~= nil then
					w.adapter.tap(path)
					break
				end
			end
			settle(w)
			judgedAt[px] = 0
			for _, path in w.adapter.paths() do
				if string.find(path, "/EditAffordanceWhen/then/EditAffordance", 1, true) == nil then
					continue
				end
				local disc = w.adapter.node(path)
				local row =
					w.adapter.node(string.gsub(path, "/EditAffordanceWhen/then/EditAffordance$", "/Content/Row"))
				if disc == nil or row == nil then
					continue
				end
				judgedAt[px] += 1
				local over = (disc.rect.x + disc.rect.w) - row.rect.x
				if over > 0 then
					table.insert(
						problems,
						`  control inset {px}/side: {disc.rect.w}x{disc.rect.h} disc at x={disc.rect.x} runs `
							.. `{over}px onto a row starting at x={row.rect.x} ({path})`
					)
				end
			end
			refusedAt[px] = 0
			for _, finding in built.handle.controller.diagnostics() do
				if string.find(finding.issue, "icon floor wanted", 1, true) ~= nil then
					refusedAt[px] += 1
				end
			end
		end
		if #problems > 0 then
			error(
				`the edit affordance escaped the gutter under a LEGAL package — director item 9's class, `
					.. `not its numbers:\n{table.concat(problems, "\n")}`,
				0
			)
		end
		-- ANTI-VACUITY: every arm really entered edit mode and found its discs
		for _, px in INSETS do
			expect(`inset {px}: {judgedAt[px] >= 6}`).toBe(`inset {px}: true`)
		end
		-- ...AND THE CATCH. Only the arm whose floor wanted more than the row
		-- reserved files, and it files once per row rather than once per screen —
		-- a cap that shrank the disc in silence would pass the invariant above
		-- while hiding the package defect that forced it.
		expect(refusedAt[4] >= 6).toBe(true)
		expect(`8:{refusedAt[8]} 12:{refusedAt[12]}`).toBe("8:0 12:0")
	end)
end)

describe("themed containment: the guard's new rules bite", function()
	local PIXEL = PACKAGES[1].snapshot

	--[[ RULE 1 — THE THEMED CONTENT BOX. A 200px panel holding a 176px row is
		legal against the RECT — it ends exactly on the edge — and illegal against
		the box a 24px-per-side plank frame leaves. Same screen, same numbers, two
		verdicts: that difference IS the rule. A ZStack, because a stack CLAMPS a
		child to the offer it hands out (a `fixed` 180 inside a 152px content box
		solves 152) and a clamped child can never demonstrate an escape. ]]
	local function panelScreen(rowWidth: number): any
		return UI.Screen({
			id = "ThemedPlate",
			padding = 0,
			children = {
				UI.ZStack({
					id = "Panel",
					surface = "raised",
					padding = 0,
					width = { type = "fixed", px = 200 },
					height = { type = "fixed", px = 200 },
					children = {
						UI.Box({
							id = "Row",
							surface = "control",
							width = { type = "fixed", px = rowWidth },
							height = { type = "fixed", px = 20 },
						}),
					},
				}),
			},
		})
	end

	local function violationsOf(screen: any, snapshot: any?): { any }
		local w = world(VIEWS[1])
		w.presenter.present(screen)
		settle(w)
		if snapshot ~= nil then
			w.env:set("themeMetrics", snapshot)
			settle(w)
		end
		return overflow_guard.violations(w.adapter, overflow_guard.newLedger({}), snapshot)
	end

	it("a row inside the RECT but over the package's carved border is reported", function()
		local found = violationsOf(panelScreen(176), PIXEL)
		expect(#found).toBe(1)
		expect(found[1].kind).toBe("outside-parent")
		expect(string.find(found[1].node, "/Row", 1, true) ~= nil).toBe(true)
		-- placed at the frame's inner edge (24) and 176 wide, so 24 past the far one
		expect(found[1].overhang).toBe(24)
	end)

	it("...and the SAME screen with no package is silent, because the rect is the edge", function()
		expect(#violationsOf(panelScreen(176), nil)).toBe(0)
	end)

	it("...and one edit narrower it clears the frame and is silent under the package too", function()
		expect(#violationsOf(panelScreen(150), PIXEL)).toBe(0)
	end)

	--[[ RULE 2 — THE SIBLING PLATE, and its two halves in one pair of fixtures.
		The library's tinted-panel idiom puts the surface on a fill x fill Box BESIDE
		the content rather than above it (the tint channel is a Box's, so the plate
		cannot be the stack itself), so the only instrument that could see the edge
		has to look sideways.

		A CONTAINER sibling is REPAIRED by the framework — `layout_node` hands it the
		plate's carved border as padding, which `arrange` really spends — so the
		second fixture is silent. A LEAF sibling is not, and deliberately: a leaf's
		padding reaches the engine through `commit_walks.padding`, which writes the
		AUTHORED value, so reserving it here would be a box the glyphs never honour.
		What the framework cannot repair, this guard reports. ]]
	local function inkPlate(wrapped: boolean): any
		local ink = UI.Box({
			id = "Ink",
			surface = "control",
			width = { type = "fixed", px = 140 },
			height = { type = "fixed", px = 8 },
		})
		return UI.Screen({
			id = "SiblingPlate",
			padding = 0,
			children = {
				UI.ZStack({
					id = "Card",
					width = { type = "fixed", px = 200 },
					height = { type = "fixed", px = 60 },
					children = {
						UI.Box({ id = "Plate", surface = "raised", width = UI.fill(), height = UI.fill() }),
						if wrapped then UI.VStack({ id = "Body", children = { ink } }) else ink,
					},
				}),
			},
		})
	end

	it("a LEAF laid straight on a sibling plate is judged against the plate's carved border", function()
		local hits = violationsOf(inkPlate(false), PIXEL)
		expect(#hits).toBe(1)
		expect(string.find(hits[1].node, "/Ink", 1, true) ~= nil).toBe(true)
		expect(hits[1].boundary).toBe("/SiblingPlate/Card")
		-- the leaf starts at the card's own origin; the frame's inner edge is 24 in
		expect(hits[1].overhang).toBe(24)
	end)

	--[[ ...AND THE FRAMEWORK DOES NOT REPAIR THE CONTAINER CASE EITHER, which is
		ADR-0059 Decision 2's rejected repair pinned as a fact rather than left to be
		re-derived. Wrapping the ink in a `VStack` moves nothing: the stack is still a
		sibling of the plate and the framework declines to hand it the plate's border,
		because on a HUD pill the same border is a 30px window frame. The guard
		reports both shapes; only a DECLARATION can fix them. ]]
	it("...and wrapping the ink in a container does not repair it — the guard still reports", function()
		local hits = violationsOf(inkPlate(true), PIXEL)
		expect(#hits).toBe(1)
		expect(string.find(hits[1].node, "/Ink", 1, true) ~= nil).toBe(true)
	end)

	it("...and with no package the sibling plate is not a boundary at all", function()
		expect(#violationsOf(inkPlate(false), nil)).toBe(0)
	end)
end)

describe("themed containment: the HUD plate ledger cannot rot", function()
	--[[ A LEDGER ROW THAT NEVER FIRES IS A FIXED DEFECT, and the line should go.
		This case runs after the HUD is judged (testkit executes in registration
		order), so the counts are complete. ]]
	it("every row in the HUD plate ledger still fires", function()
		local stale: { string } = {}
		for _, row in HUD_PLATE_LEDGER do
			if PLATE_HITS[row.node] == 0 then
				table.insert(stale, `{row.node} ({row.why})`)
			end
		end
		if #stale > 0 then
			error(
				`{#stale} HUD plate-ledger row(s) no longer fire. If the plate was fixed, DELETE the line — `
					.. `that is the point of the ledger; if the node moved, re-record it:\n  `
					.. table.concat(stale, "\n  "),
				0
			)
		end
	end)

	--[[ RULE 2's SELF-EXCLUSION, AT THE ARITY THAT BROKE IT (review finding I2,
		fixed 2026-08-28). "Never the branch the question came up" covered ONE plate:
		with a second full-bleed surfaced sibling in the same stack, each plate was
		excluded from its OWN lookup and then judged against the other, so both
		reported the identical false escape — three violations where one is real.
		The rule is now on the QUESTIONER (a node already drawing the host's own edge
		has no plate), which is one line for both arities, and this case is the one
		that can tell them apart. ]]
	local function twoPlates(): any
		return UI.Screen({
			id = "TwoPlates",
			padding = 0,
			children = {
				UI.ZStack({
					id = "Stack",
					width = { type = "fixed", px = 200 },
					height = { type = "fixed", px = 200 },
					children = {
						UI.Box({ id = "PlateA", surface = "raised", width = UI.fill(), height = UI.fill() }),
						UI.Box({ id = "PlateB", surface = "raised", width = UI.fill(), height = UI.fill() }),
						UI.Box({
							id = "Ink",
							surface = "control",
							width = { type = "fixed", px = 200 },
							height = { type = "fixed", px = 8 },
						}),
					},
				}),
			},
		})
	end

	it("two full-bleed plates in one stack report the ink ONCE and neither other", function()
		local hits = violationsOf(twoPlates(), PIXEL)
		expect(#hits).toBe(1)
		expect(string.find(hits[1].node, "/Ink", 1, true) ~= nil).toBe(true)
		expect(hits[1].overhang).toBe(24)
		-- ...and the message names the box that was actually compared, so a reader
		-- is not sent looking for an inset on the stack (Minor 5)
		expect(
			string.find(overflow_guard.describe(hits[1]), "via its sibling plate /TwoPlates/Stack/PlateA", 1, true)
				~= nil
		).toBe(true)
	end)
end)
