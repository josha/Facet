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
	borders, at the three viewports where each surface's ladder builds its rich
	form (`tablet-landscape`, `compact-phone-landscape` and the narrowest supported
	box) — plus, for item 9, a sweep of the one package METRIC that decides it. The
	corpus-wide number the same oracle reports is recorded in the task report and
	is NOT green yet — this is a floor under the four, not a claim about the
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
			adapter.scrollBarThickness = fake_target.SCROLL_BAR_RESERVE
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

--[[ THE HUD'S PLATE LEDGER — AND IT IS EMPTY NOW, WHICH IS WHAT IT WAS FOR.

	It held eleven rows, every one the SAME defect: `glass()` in
	`examples/gallery/scenarios/hud.luau` was `ZStack{ Box(surface = "raised",
	fill x fill), content }`, so the plate was the content's SIBLING and the
	package's carved border was reserved on a node with no children. ADR-0059
	Decision 2 declined the obvious repair (handing a WINDOW's frame to a chip
	turns a 116x41 objective chip into a 92x85 blob under Fantasy Ornate —
	measured) and booked the real question for a round that could re-spec: which
	slot a small plate should classify into.

	CLOSED 2026-08-29 on a director report ("the 'win a round' text, '84' text,
	'12' at the top, and the circular progress bar ... all overlap the chrome. we
	should not allow this overlap"). The answer was not to reserve the window —
	it was that a 21x28 score pill is not a window: `glass` now declares
	`surface = "chip"` for everything that is not a panel, which classifies into
	the `control` slot, and pays THAT carve out of one shared `plateInsets` memo.
	Pixel Quest spends 8 where it used to be handed 24, and no flat package moves
	a pixel (the fill is the plate's own `tint`, the corner its own `UI.corners`).

	THE RULES THE LIST WAS UNDER, kept because the type and the machinery below
	are still the honest way to book the NEXT one:
	  * `px` is the largest overhang measured across this file's packages x
	    viewports. A finding above it FAILS — the defect got worse.
	  * a row that never fires FAILS too (the case below counts them), so the list
	    can only shrink and the number means something. That rule is what makes
	    this emptying checkable rather than asserted: with the rows deleted, any
	    surviving overhang is now an ordinary failure of the group above.
	  * a row is a NODE PATTERN, because one wrong construction is one defect and
	    not eleven.
	  * nothing here is a `zero-box`. There is no design in which a string the
	    player is meant to read solves to nothing, and no row may pardon one. ]]
type PlateRow = { node: string, px: number, why: string }
local HUD_PLATE_LEDGER: { PlateRow } = {}
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
end)

--[[ THE COUNT SEAL VS. ITS OWN SEGMENT'S CHROME (task THEME2, director item:
	"the badge has no padding and overlaps the edge of the control", i2.png — a
	purple "7" straddling a Pixel Quest segment's golden plank border).

	A DIFFERENT CLASS FROM EVERYTHING ABOVE IN THIS FILE, and worth saying so in
	one place: every other group here asks "is this rect inside the box its
	ANCESTOR CHAIN gives it" (`overflow_guard.violations`, Rule 2's sibling-plate
	extension included). The count seal is NOT outside anything by that question —
	it is a corner-aligned overlay sized well within its own cell, so it never
	fires a single `overflow_guard` finding at any inset. What it does is sit ON
	TOP of a DIFFERENT sibling's own carved border, which is a decoration-vs-
	decoration collision, not a containment escape — `overflow_guard` has no
	vocabulary for "does my rect intersect a sibling's own painted border band",
	only for "did I exceed the box a boundary computation handed me". Measured:
	mounting the fixture below under Pixel Quest with the pre-fix (flush, zero
	inset) badge geometry and running `overflow_guard.violations` against it
	reports ZERO findings — the class is STRUCTURALLY INVISIBLE to the sweep's
	oracle. This group is therefore its own instrument, reading node rects
	directly, the same way item 9's own class group above does for the identical
	reason (a size floor colliding with a gutter is not a containment question
	either).

	THE FIX (`src/controls/picker.luau`): the badge's own wrapper reads
	`chromeInsets.control` off the LIVE theme snapshot — the same slot
	`selection_indicator.luau`'s `barSurfaceSlot` already carves clear of for the
	sliding pill itself (ADR-0059 Decision 3, director item 8) — and pads its
	top/right by the carved amount before the "Count" text aligns to the corner.
	Zero carve (every flat package) reproduces the exact pre-fix geometry. ]]
-- carvedInsetSide(snapshot, slot, side) -> the RAW declared inset for one
-- AXIS of one slot, or 0 with no package/slot/side declared (review finding
-- T1). Independent of BOTH `chrome_slots.carvedBorder` (the scalar max) and
-- `chrome_slots.carvedSide` (the fix's own per-axis primitive) — re-derived
-- from the raw snapshot on each axis separately, so this oracle cannot pass
-- merely because it shares an arithmetic mistake with the code under test.
-- That sharing was exactly T1's finding: the old oracle here computed the
-- SAME four-sided max the pre-fix code applied to both axes, so an
-- asymmetric carve (fantasy_ornate's `control` is
-- `{top=10,right=14,bottom=10,left=14}`) could never be seen — both sides
-- read "14" and agreed with the over-inset. Module-scoped so BOTH consumer
-- groups below (the Picker's count seal and adaptive_controls' HUD-tile
-- badge) share one oracle rather than each re-deriving it a second time.
local function carvedInsetSide(snapshot: any?, slot: string, side: string): number
	if type(snapshot) ~= "table" then
		return 0
	end
	local insets = (snapshot :: any).chromeInsets
	local plate = if type(insets) == "table" then (insets :: any)[slot] else nil
	if type(plate) ~= "table" then
		return 0
	end
	local px = (plate :: any)[side]
	return if type(px) == "number" then px else 0
end

describe("themed containment: the count seal clears its own segment's chrome (director item 2)", function()
	local function badgeScreen(core: any, env: any, selected: any): any
		local picker = Facet.Controls.Picker(core, {
			id = "Seg",
			label = "Segments",
			presentation = "segmented",
			options = {
				{ value = "a", label = "Alpha", badge = "7" },
				{ value = "b", label = "Beta" },
			},
			selected = selected,
			-- WITHOUT THIS the fix's own `metricsSig` memo never sees a live
			-- swap (it falls back to `themeSnapshot.neutral()` whenever
			-- `spec.env == nil`) — found by this exact test going red for
			-- the wrong reason (picker.luau's `badgeCornerInset` computing 0
			-- under every package, matching the flat-package expectation by
			-- accident rather than proving anything about a carving one)
			env = env,
		})
		return UI.Screen({ id = "BadgeScreen", padding = 0, children = { picker.blueprint } }), picker
	end

	-- badgeHits(snapshot) -> one row per mounted "Count" badge: how far its own
	-- top/right edge clears the CELL's top/right edge, minus what the package
	-- carves. `>= -0.5` (never NEGATIVE beyond sub-pixel slack) is "cleared";
	-- anything past that is the director's overlap, reproduced.
	local function badgeHits(
		w: any,
		snapshot: any?
	): { { node: string, carved: number, rightClear: number, topClear: number } }
		local selected = w.core:signal("a")
		local screen = badgeScreen(w.core, w.env, selected)
		w.presenter.present(screen, {})
		settle(w)
		if snapshot ~= nil then
			w.env:set("themeMetrics", snapshot)
			settle(w)
		end
		local topCarved = carvedInsetSide(snapshot, "control", "top")
		local rightCarved = carvedInsetSide(snapshot, "control", "right")
		local out = {}
		for _, path in w.adapter.paths() do
			if #path < 12 or string.sub(path, -12) ~= "/Badge/Count" then
				continue
			end
			local cellPath = string.sub(path, 1, #path - 12)
			local badge = w.adapter.node(path)
			local cell = w.adapter.node(cellPath)
			if badge == nil or cell == nil or badge.rect == nil or cell.rect == nil then
				continue
			end
			table.insert(out, {
				node = path,
				carved = math.max(topCarved, rightCarved), -- anti-vacuity only
				topCarved = topCarved,
				rightCarved = rightCarved,
				rightClear = (cell.rect.x + cell.rect.w - rightCarved) - (badge.rect.x + badge.rect.w),
				topClear = badge.rect.y - (cell.rect.y + topCarved),
			})
		end
		return out
	end

	it("with no package installed, the badge sits flush at the corner — shipped geometry, unchanged", function()
		local w = world(VIEWS[1])
		local hits = badgeHits(w, nil)
		expect(#hits > 0).toBe(true) -- anti-vacuity: the fixture really has a badge
		for _, hit in hits do
			expect(hit.carved).toBe(0)
			-- FLUSH means AT the corner (clearance ~0), not clear of it by a margin
			expect(math.abs(hit.rightClear) <= 0.5).toBe(true)
			expect(math.abs(hit.topClear) <= 0.5).toBe(true)
		end
	end)

	for _, pkg in PACKAGES do
		it(`under {pkg.id}, the count seal clears the segment's own carved border, PER AXIS (T1)`, function()
			local w = world(VIEWS[1])
			local hits = badgeHits(w, pkg.snapshot)
			expect(#hits > 0).toBe(true)
			for _, hit in hits do
				-- anti-vacuity: this package really does carve a `control` border,
				-- or the case below would pass for having asked nothing
				expect(hit.carved > 0).toBe(true)
				expect(hit.rightClear >= -0.5).toBe(true)
				expect(hit.topClear >= -0.5).toBe(true)
				-- THE T1 PIN. Over-clearing is a defect too: a badge that pads BOTH
				-- axes by the SHARED max of all four sides (the pre-fix shape) clears
				-- an asymmetric package's short axis by more than that axis carves.
				-- fantasy_ornate's `control` is {top=10,right=14,...} — a shared-max
				-- badge clears top by 14 (should be 10), 4px past its own carve, and
				-- the `>= -0.5` checks above cannot see it (over-clear never goes
				-- negative). An exact per-axis clearance is ~0; tolerate sub-pixel
				-- slack only.
				expect(hit.topClear <= 0.5).toBe(true)
				expect(hit.rightClear <= 0.5).toBe(true)
			end
		end)
	end

	it("...and overflow_guard itself reports NOTHING here — the class is structurally invisible to it", function()
		-- the disclosure this file's header makes precise: the sweep's own
		-- oracle, asked directly, finds no violation on this exact fixture under
		-- the fattest carving package — proving the SWEEP lane's containment
		-- census is not already covering this class before this group existed
		local w = world(VIEWS[1])
		local selected = w.core:signal("a")
		local screen = badgeScreen(w.core, w.env, selected)
		w.presenter.present(screen, {})
		settle(w)
		w.env:set("themeMetrics", PACKAGES[1].snapshot)
		settle(w)
		local found = overflow_guard.violations(w.adapter, overflow_guard.newLedger({}), PACKAGES[1].snapshot)
		expect(#found).toBe(0)
	end)
end)

--[[ THE SECOND CONSUMER OF THE SAME CLASS: `adaptive_controls.luau`'s HUD-tile
	badge (task THEME2, second round). The showcase's own count-seal badge
	(above) is `src/controls/picker.luau`'s shared mechanism; this scenario's
	`badgedTile` is a SEPARATE, hand-rolled construction (`UI.overlay` + a raw
	`UI.Text` carrying its own `alignH`/`alignV`) that never went through the
	Picker at all — so closing the Picker's copy of the defect did not close
	this one. Measured, before this round's second fix: the tile's own `2`px
	`UI.padding` is the seal's INTERNAL glyph inset (its own comment says so),
	never a corner offset — `UI.padding`/`UI.alignment` write straight onto a
	node's own props, no wrapper — so the badge sat flush at the tile's raw
	corner exactly like the Picker's did, and Pixel Quest's `control` chrome
	(8px/side) landed under it. `t4`'s badge is "7", which is the value in the
	director's own photograph.

	THE FIX REUSES THE SAME PRIMITIVE the Picker fix's own refactor extracted
	for exactly this reason: `chrome_slots.carvedBorder(snapshot, "control")`,
	now required directly by the fixture (the same precedented reach
	`nested_compositing.luau`/`sensory_feedback.luau` already make for a
	utility with no public-surface equivalent). ]]
describe(
	"themed containment: adaptive_controls' HUD-tile badge clears its own tile's chrome (director item 2, second consumer)",
	function()
		local TILE_IDS = { "t1", "t2", "t3", "t4" }

		local function tileHits(
			w: any,
			snapshot: any?
		): { { tile: string, carved: number, rightClear: number, topClear: number } }
			local built = mountScenario(w, "adaptive_controls")
			settle(w)
			if snapshot ~= nil then
				w.env:set("themeMetrics", snapshot)
				settle(w)
			end
			-- independently derived per axis (T1) — see `carvedInsetSide` above,
			-- the Picker group's oracle: this group used to call
			-- `chrome_slots.carvedBorder` DIRECTLY (the production scalar-max
			-- helper), so the oracle and the code under test shared the exact
			-- same arithmetic mistake. Re-derived here so the two can disagree.
			local topCarved = carvedInsetSide(snapshot, "control", "top")
			local rightCarved = carvedInsetSide(snapshot, "control", "right")
			local out = {}
			for _, tileId in TILE_IDS do
				local boxSuffix = `/{tileId}+overlay/{tileId}`
				local badgeSuffix = `/{tileId}+overlay/{tileId}BadgeCorner/{tileId}Badge`
				local boxPath, badgePath = nil, nil
				for _, path in w.adapter.paths() do
					if string.sub(path, -#boxSuffix) == boxSuffix then
						boxPath = path
					elseif string.sub(path, -#badgeSuffix) == badgeSuffix then
						badgePath = path
					end
				end
				if boxPath == nil or badgePath == nil then
					continue
				end
				local box = w.adapter.node(boxPath)
				local badge = w.adapter.node(badgePath)
				if box == nil or badge == nil or box.rect == nil or badge.rect == nil then
					continue
				end
				table.insert(out, {
					tile = tileId,
					carved = math.max(topCarved, rightCarved), -- anti-vacuity only
					topCarved = topCarved,
					rightCarved = rightCarved,
					rightClear = (box.rect.x + box.rect.w - rightCarved) - (badge.rect.x + badge.rect.w),
					topClear = badge.rect.y - (box.rect.y + topCarved),
				})
			end
			return out
		end

		it(
			"with no package installed, every tile's badge sits flush at the corner — shipped geometry, unchanged",
			function()
				local w = world(VIEWS[1])
				local hits = tileHits(w, nil)
				expect(#hits).toBe(#TILE_IDS) -- anti-vacuity: all four tiles found
				for _, hit in hits do
					expect(hit.carved).toBe(0)
					expect(math.abs(hit.rightClear) <= 0.5).toBe(true)
					expect(math.abs(hit.topClear) <= 0.5).toBe(true)
				end
			end
		)

		for _, pkg in PACKAGES do
			it(`under {pkg.id}, every tile's badge clears its own tile's carved border, PER AXIS (T1)`, function()
				local w = world(VIEWS[1])
				local hits = tileHits(w, pkg.snapshot)
				expect(#hits).toBe(#TILE_IDS)
				for _, hit in hits do
					expect(hit.carved > 0).toBe(true) -- anti-vacuity: this package really carves `control`
					expect(hit.rightClear >= -0.5).toBe(true)
					expect(hit.topClear >= -0.5).toBe(true)
					-- THE T1 PIN (see the Picker group above for the full mechanism):
					-- a shared-max badge over-clears the short axis of an asymmetric
					-- package (fantasy_ornate top=10/right=14) by 4px, which the
					-- `>= -0.5` checks above cannot see.
					expect(hit.topClear <= 0.5).toBe(true)
					expect(hit.rightClear <= 0.5).toBe(true)
				end
			end)
		end
	end
)
