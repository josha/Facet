--!strict
local harness = require("./lib/harness")
--[[ A LIST ROW READS AGAINST A PLATE, IN EVERY THEME.

	WHAT WAS REPORTED (owner, 2026-09-12, live capture of the showcase under Pixel
	Quest): the swipe-actions fixture's List surface had lost its rows. Not their
	text — their PLATE. Six rows of copy floating on the app background with
	nothing behind them and nothing between them.

	WHAT IT ACTUALLY WAS. `6a65baef` ("Classify a decoration slot by the surface a
	node declared, not by its class") made a declared surface outrank the class
	map in `chrome_slots.classify`, so a `UI.Button` declaring `surface = "base"`
	stopped being handed the package's CONTROL recipe by its class. That rule is
	right and stays. What it exposed is that this fixture's rows had been drawing
	their plate out of exactly that accident: the row declares `base`, `base` is
	the APP BACKGROUND, and the screen the rows sit on declares `base` too — so
	once `base` meant what it says, the row painted the identical token as the
	surface behind it and the list disappeared. The commit's own spec recorded
	"neither wants a control plate", and for this row that half was wrong.

	WHY THE PLATE IS NOT BACK ON THE ROW. Measured, not assumed: `control` and
	`panel` are the only two decoration slots a plate surface can reach, and under
	Glossy Mobile and Glossy Touch BOTH declare `shadow = "raised"` — blur 14,
	offset y+3, `zIndex = -1` — resolving to a `chromeBleed` of 17px. A list lays
	its rows back to back, so a per-row plate paints that far into its neighbours
	at any gap a list would plausibly use. That is the owner's OWN earlier report
	("a crowded list that's overlapping", `tests/row_hit_paint.spec.luau`), and
	re-declaring `control` on the row would simply swap this defect for that one.

	WHAT THE FIXTURE DOES INSTEAD. The plate is a node of its own — `ListPlate`, a
	stack that fills the band and holds the scroller — so there is ONE panel: its
	shadow falls on the app background rather than on a neighbouring row, its
	carved frame, its hairline and its `radii.panel` corner frame the pane a player
	looks at, and every row's own `base` fill now reads against a token that
	differs from it in every shipped theme. The 1px `gap` the list already had is
	the separator between them.

	AND THE SLOT IS PINNED BESIDE THE SURFACE NAME, because a surface name alone
	does not decide a recipe. `chrome_slots.classify` answers for three CLASSES —
	Divider, ScrollView, TextField — BEFORE it reads `surface == "raised"`, since
	each of those names its own chrome and a ScrollView's chrome is its SCROLLBAR.
	Declared on the scroller this plate classified into `scrollbar`, which every
	shipped package declares as `{ kind = "native" }` with no insets and no shadow:
	a flat fill wearing the name of a card.

	AND THE PLATE COST THE ROW SOMETHING, which is the second half of the change.
	A slot's carved `chromeInsets` are added to the node's own padding
	(`render/layout_node.luau`), and `panel` asks for 30px a side under Fantasy
	Ornate and 18 under Fantasy Parchment. On a 320px portrait the row's `TopLine`
	— a content-sized sender name beside a flag glyph, with nothing able to give —
	then painted up to 35px past its own box, which is the OTHER finding
	`6a65baef` closed, reappearing one node up. The sender fills and truncates now.
	`tests/overflow_sweep.spec.luau` is what reported it, both times.

	WHAT IS PINNED HERE:

	  1. The two nodes declare the two surfaces AND the plate reaches the `panel`
	     slot, so the card is a DECLARATION and never a class accident again. It
	     fills the band with the scroller inside it, so a nine-slice package's
	     carved frame wraps the pane a player looks at instead of hugging whatever
	     the rows happen to measure and scrolling away with them — and it gives way
	     on a screen with no room for one.
	  2. The row still takes no decoration slot — `6a65baef`'s rule, unmoved.
	  3. THE PAINT, resolved the way the engine resolves it: each node's
	     classification tags run through the compiled sheet's cascade and the
	     winning `BackgroundColor3` token is looked up in the theme. A raw property
	     read would report the UNSTYLED value and a default-valued write claims
	     nothing, so neither could see this defect at all. Run over Facet Neutral
	     and every theme of every shipped example package: plate and row are both
	     opaque, and their fills differ.
	  4. The sender line can give, so the plate's carved border comes out of the
	     name rather than out of the box.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/harness_world")

local Facet = require("../src") :: any
local chrome_slots = require("../src/tokens/chrome_slots")
local sheet_model = require("../src/tokens/sheet_model")
local default_style = require("../src/tokens/default_style")

local rowActions = require("../examples/gallery/scenarios/row_actions") :: any

local PLATE_PATH = "/MailActions/ListWhen/ListPlate"
local ROW_PATH = "/MailActions/ListWhen/ListPlate/List/Rows/RowsForEach/[m1]/m1/Content/Row"

-- the engine instance each node class is materialized as, so a bare class
-- selector in the sheet can be matched headlessly (`src/client/screen_vocabulary
-- .luau`'s `CLASS_TO_INSTANCE`; only the two classes this spec reads)
local ENGINE_CLASS: { [string]: string } = { Button = "TextButton", VStack = "Frame" }
local TOP_LINE = "/MailActions/ListWhen/ListPlate/List/Rows/RowsForEach/[m1]/m1/Content/Row/Text/TopLine"

local PACKAGES: { { name: string, module: any } } = {
	{ name = "classic_desktop", module = require("../examples/themes/classic_desktop") },
	{ name = "compact_pointer", module = require("../examples/themes/compact_pointer") },
	{ name = "fantasy_ornate", module = require("../examples/themes/fantasy_ornate") },
	{ name = "fantasy_parchment", module = require("../examples/themes/fantasy_parchment") },
	{ name = "glossy_mobile", module = require("../examples/themes/glossy_mobile") },
	{ name = "glossy_touch", module = require("../examples/themes/glossy_touch") },
	{ name = "pixel_quest", module = require("../examples/themes/pixel_quest") },
	{ name = "scifi_hud", module = require("../examples/themes/scifi_hud") },
}

local function scenarioWorld(module: any, viewport: any?, textOffset: number?, metrics: any?)
	local w = worldLib.new({
		viewport = viewport or { x = 0, y = 0, w = 1232, h = 1067 },
		themeMetrics = metrics,
		env = if textOffset ~= nil then { preferredTextOffset = textOffset } else nil,
	})
	local built = module.build({
		Facet = Facet,
		UI = (harness.libraryOf(w.core)),
		Compose = Facet.Compose,
		core = w.core,
		env = w.env,
		adapter = w.adapter,
		presenter = w.pres,
		actionSystem = w.system,
		record = function() end,
		flags = {},
		geometry = function()
			return {}
		end,
		bindResourceTransport = function()
			return function() end
		end,
	})
	built.handle = w.pres.present(built.screen, built.present)
	for _ = 1, 4 do
		w.pres.refresh()
	end
	return w, built
end

--[[ THE STYLED READ, headless. A selector this spec has to understand is one of
	four shapes: a bare engine class, `.tag`, `EngineClass.tag`, or a compound of
	tags. Anything carrying a pseudo-state, a phantom child (`::UICorner`) or a
	combinator is skipped — none of them decide a resting fill. The cascade is
	insertion order with no specificity (docs/guide/05-styling.md), so the LAST
	match wins, which is what the engine's StyleSheet does. ]]
local function selectorMatches(selector: string, engineClass: string, tags: { [string]: boolean }): boolean
	if string.find(selector, "::", 1, true) ~= nil then
		return false
	end
	if string.find(selector, ":") ~= nil or string.find(selector, "%s") ~= nil or string.find(selector, ">") ~= nil then
		return false
	end
	local head, rest = string.match(selector, "^([%w_]*)(.*)$")
	if head == nil then
		return false
	end
	if head ~= "" and head ~= engineClass then
		return false
	end
	for tag in string.gmatch(rest :: string, "%.([%w%-_]+)") do
		if not tags[tag] then
			return false
		end
	end
	return true
end

local function styledProp(model: any, engineClass: string, tags: { [string]: boolean }, prop: string): any
	local won: any = nil
	for _, rule in model.rules do
		if selectorMatches(rule.selector, engineClass, tags) and rule.props[prop] ~= nil then
			won = rule.props[prop]
		end
	end
	return won
end

local function tokenValue(theme: any, value: any): any
	if type(value) == "string" and string.sub(value, 1, 1) == "$" then
		return theme.tokens[string.sub(value, 2)]
	end
	return value
end

-- the resting fill a node paints under one compiled theme: "r,g,b" when the
-- sheet claims one at full opacity, nil when nothing paints it
local function restingFill(model: any, theme: any, engineClass: string, tags: { [string]: boolean }): string?
	local transparency = tokenValue(theme, styledProp(model, engineClass, tags, "BackgroundTransparency"))
	if type(transparency) ~= "table" or transparency.value ~= 0 then
		return nil
	end
	local colour = tokenValue(theme, styledProp(model, engineClass, tags, "BackgroundColor3"))
	if type(colour) ~= "table" or type(colour.r) ~= "number" then
		return nil
	end
	return `{colour.r},{colour.g},{colour.b}`
end

-- every compiled model a shipped theme can install, plus the one a screen with
-- no package installed runs on. Compiled once: eight packages is the expensive
-- half of this file and every case wants the same list.
local compiled: { { label: string, model: any, theme: any } }? = nil
local function models(): { { label: string, model: any, theme: any } }
	if compiled ~= nil then
		return compiled
	end
	local out: { { label: string, model: any, theme: any } } = {}
	local neutral = sheet_model.build({ themes = { { name = "Facet Neutral", style = default_style } } })
	table.insert(out, { label = "Facet Neutral", model = neutral, theme = neutral.themes[1] })
	for _, entry in PACKAGES do
		local package, report = entry.module.build(Facet.themes)
		assert(package ~= nil, `{entry.name} failed its own package gate: {report and report.errors[1]}`)
		local model = sheet_model.buildPackage(package, {})
		for _, theme in model.themes do
			table.insert(out, { label = `{entry.name}/{theme.name}`, model = model, theme = theme })
		end
	end
	compiled = out
	return out
end

local function tagsOf(node: any): { [string]: boolean }
	return sheet_model.classifyTags({
		surface = node.props.surface,
		interactive = node.class == "Button" or node.class == "Toggle",
		selected = false,
	})
end

describe("list row plate: the fixture declares the plate it paints", function()
	it("the list declares the raised plate and the row declares the app surface", function()
		local w = scenarioWorld(rowActions)
		local plate = w.adapter.node(PLATE_PATH)
		expect(plate.props.surface).toBe("raised")
		expect(plate.class).toBe("VStack")
		--[[ ...AND IT REACHES THE `panel` SLOT, which is the half a surface NAME
			does not prove. `chrome_slots.classify` answers for three CLASSES —
			Divider, ScrollView, TextField — BEFORE it reads `surface == "raised"`,
			because each of those names its own chrome and a ScrollView's chrome is
			its SCROLLBAR. Declared on the scroller itself this plate classified into
			`scrollbar`, which every shipped package declares as
			`{ kind = "native" }` with no insets and no shadow: a flat fill wearing
			the name of a card, while the CHANGELOG and this header claimed a carved
			frame. The same three inputs `render/layout_node.luau` and the live
			adapter read off the node, exactly as `surface_slot_precedence.spec`
			reads them. ]]
		expect(chrome_slots.classify({
			class = plate.class,
			surface = plate.props.surface,
			hasSelection = plate.props.selected ~= nil,
		})).toBe("panel")
		expect(w.adapter.node(ROW_PATH).props.surface).toBe("base")
		-- the plate frames the VISIBLE pane: it fills its band with the scroller,
		-- and the row stack inside that is only as tall as the rows
		local list = w.adapter.node(PLATE_PATH .. "/List")
		expect(list.rect.y > plate.rect.y).toBe(true)
		expect(list.rect.y + list.rect.h < plate.rect.y + plate.rect.h).toBe(true)
		expect(plate.rect.h > w.adapter.node(PLATE_PATH .. "/List/Rows").rect.h).toBe(true)
	end)

	--[[ ...AND IT GIVES WAY ONLY WHEN THE BAND CANNOT HOLD IT, which is a
		MEASUREMENT and not a viewport class (controller ruling, round 3, from a live
		capture of the rebuilt showcase under Pixel Quest).

		The first gate was `conditions.isShort`, "the viewport is under 600px tall".
		The showcase's emulated device is 677x338, so it fired on an ORDINARY PHONE
		LANDSCAPE and the plate vanished in every theme — the owner's original report
		reintroduced by its own fix, while only the two nine-slice packages ever
		overflowed anything. The rule is arithmetic on two measured numbers now: the
		band's solved height against the package's own carved frame
		(`chromeInsets.panel`) plus one tappable row (`targetSizes.minimum`). A
		package that carves nothing can squeeze nothing, so it never loses its plate
		at any size. ]]
	it("the showcase's own device keeps the plate, and the `panel` slot, in every package", function()
		-- 677x338, default text: the shape the live capture was taken at
		local view = { x = 0, y = 0, w = 677, h = 338 }
		for _, entry in PACKAGES do
			local package, report = entry.module.build(Facet.themes)
			assert(package ~= nil, `{entry.name} failed its own package gate: {report and report.errors[1]}`)
			local metrics = Facet.themes.resolve(package, nil, {})
			local plate = scenarioWorld(rowActions, view, 0, metrics).adapter.node(PLATE_PATH)
			assert(plate ~= nil, `{entry.name}: the list mounted no plate at 677x338`)
			local carved = metrics.chromeInsets.panel.top + metrics.chromeInsets.panel.bottom
			assert(
				plate.props.surface == "raised",
				`{entry.name}: the plate gave way at 677x338 — band {plate.rect.h}px, carved {carved}px, `
					.. `floor {metrics.targetSizes.minimum}px`
			)
			expect(`{entry.name} {chrome_slots.classify({ class = plate.class, surface = plate.props.surface })}`).toBe(
				`{entry.name} panel`
			)
		end
	end)

	--[[ THE CELL THE SWEEP ACTUALLY EXERCISES, reproduced here. The overflow
		sweep's narrow-landscape row is 640x320 MINUS the showcase's own top
		reservation (the CoreGui inset plus its two picker chips), which is what
		leaves the band at single digits; in this bare harness the same band arrives
		at 640x200. Measured at both, so the number is on the record rather than
		implied: at 640x320 the band is 128px under Fantasy Parchment and 122 under
		Glossy Touch and the card STAYS (36 + 44 and 28 + 44 both fit); at 640x200 it
		is 8px and 2px and the card goes. ]]
	it("a band too small for the carved frame drops the card, in the packages that carve one", function()
		for _, name in { "fantasy_parchment", "glossy_touch" } do
			local package = (require :: any)(`../examples/themes/{name}`).build(Facet.themes)
			local metrics = Facet.themes.resolve(package, nil, {})
			local carved = metrics.chromeInsets.panel.top + metrics.chromeInsets.panel.bottom
			expect(`{name} carves {carved > 0}`).toBe(`{name} carves true`)

			local roomy = scenarioWorld(rowActions, { x = 0, y = 0, w = 640, h = 320 }, 14, metrics)
			local roomyPlate = roomy.adapter.node(PLATE_PATH)
			assert(
				roomyPlate.props.surface == "raised",
				`{name}: the card went at 640x320 (+14), where the band is {roomyPlate.rect.h}px`
			)

			local tight = scenarioWorld(rowActions, { x = 0, y = 0, w = 640, h = 200 }, 14, metrics)
			local tightPlate = tight.adapter.node(PLATE_PATH)
			assert(
				tightPlate.props.surface == nil,
				`{name}: the card stayed on a {tightPlate.rect.h}px band against a {carved}px frame`
			)
			-- ...and the rows are still there, still separated, still on the page
			expect(tight.adapter.node(ROW_PATH).props.surface).toBe("base")
		end
	end)

	--[[ A THEME SWAP IS A NEW SHAPE, and it arrives WITHOUT a remount. The
		showcase's theme picker writes `themeMetrics` in place on a persistent demo
		scope (`examples/gallery/client/init.client.luau`), so nothing about the
		viewport or the preference changes — and the band cached under the previous
		package would otherwise answer for the new one. Measured under a thin-chrome
		package and switched to Fantasy Ornate's 30px frame, that is the card
		staying on a band the frame cannot hold: the 0px-content collapse this whole
		rule exists to prevent, reached from the one direction no fresh-world case
		can see.

		The oracle is a FRESH world built at the same viewport under the same
		package, so the assertion is "the swapped screen decides what a screen that
		started there decides", not a number this file chose. ]]
	it("a theme swapped IN PLACE re-measures the band, and decides as a fresh world would", function()
		local ornate = Facet.themes.resolve(require("../examples/themes/fantasy_ornate").build(Facet.themes), nil, {})
		--[[ 640x260 at the largest preference is where the two packages DISAGREE,
			which is what makes this case able to fail: the band is 177px under Facet
			Neutral (which carves nothing, so it keeps its card at any size) and 60px
			under Ornate against a 60px frame plus a 44px floor, so Ornate drops it.
			At the showcase's own 677x338 both keep the card, so a stale band there
			is invisible to a decision-shaped assertion — the swap is asserted at
			both, and the disagreeing viewport is the one that bites. ]]
		for _, view in { { x = 0, y = 0, w = 640, h = 260 }, { x = 0, y = 0, w = 677, h = 338 } } do
			local freshNeutral = scenarioWorld(rowActions, view, 14).adapter.node(PLATE_PATH).props.surface
			local freshOrnate = scenarioWorld(rowActions, view, 14, ornate).adapter.node(PLATE_PATH).props.surface

			-- ONE world, no remount: the picker's own gesture
			local w = scenarioWorld(rowActions, view, 14)
			local label = `{view.w}x{view.h}`
			expect(`{label} start {w.adapter.node(PLATE_PATH).props.surface}`).toBe(`{label} start {freshNeutral}`)

			--[[ `pres.refresh`, not `world.settle`, and for the same reason
				`scenarioWorld` above presents the way it does: `settle` also runs the
				containment guard, and this fixture already trips that at these narrow
				cells for a reason with nothing to do with the plate — a row measures
				8px wider than its scroller at the moment the guard looks, under Facet
				Neutral, before any swap. Driving the swap the same way every other
				case in this file drives its mount keeps this one about the band. ]]
			w.env:set("themeMetrics", ornate)
			for _ = 1, 4 do
				w.pres.refresh()
			end
			expect(`{label} swapped {w.adapter.node(PLATE_PATH).props.surface}`).toBe(`{label} swapped {freshOrnate}`)

			w.env:set("themeMetrics", nil)
			for _ = 1, 4 do
				w.pres.refresh()
			end
			expect(`{label} back {w.adapter.node(PLATE_PATH).props.surface}`).toBe(`{label} back {freshNeutral}`)
		end
	end)

	it("...and the two packages really do disagree at that viewport, or the swap proves nothing", function()
		local view = { x = 0, y = 0, w = 640, h = 260 }
		local ornate = Facet.themes.resolve(require("../examples/themes/fantasy_ornate").build(Facet.themes), nil, {})
		expect(scenarioWorld(rowActions, view, 14).adapter.node(PLATE_PATH).props.surface).toBe("raised")
		expect(scenarioWorld(rowActions, view, 14, ornate).adapter.node(PLATE_PATH).props.surface).toBeNil()
	end)

	it("...and a package that carves nothing keeps its plate on the same bands", function()
		-- Facet Neutral publishes no panel insets, so its card cannot squeeze
		-- anything and the band's height never enters the question
		for _, height in { 320, 200 } do
			local w = scenarioWorld(rowActions, { x = 0, y = 0, w = 640, h = height }, 14)
			local plate = w.adapter.node(PLATE_PATH)
			assert(
				plate.props.surface == "raised",
				`Facet Neutral at 640x{height} +14: the card went on a {plate.rect.h}px band`
			)
		end
	end)

	it("...and the row still takes no decoration slot, so no package shadow reaches a neighbour", function()
		local w = scenarioWorld(rowActions)
		local row = w.adapter.node(ROW_PATH)
		expect(chrome_slots.classify({ class = row.class, surface = row.props.surface })).toBe(nil)
	end)

	it("the premise: a plate surface DOES reach a slot that carries a shadow under the glossy packages", function()
		for _, name in { "glossy_mobile", "glossy_touch" } do
			local module = (require :: any)(`../examples/themes/{name}`)
			local package = module.build(Facet.themes)
			expect(chrome_slots.shadowFor(package, "panel") ~= nil).toBe(true)
			expect(Facet.themes.resolve(package, nil, {}).chromeBleed > 0).toBe(true)
		end
	end)

	it("...and the SECOND premise: a panel recipe carves a border the solver spends as padding", function()
		local ornate = require("../examples/themes/fantasy_ornate").build(Facet.themes)
		local insets = Facet.themes.resolve(ornate, nil, {}).chromeInsets
		expect(insets.panel.left > 16).toBe(true)
		--[[ ...which is why the sender line has to be able to give, asserted as
			the SOLVED consequence rather than as the declaration: a dim is consumed
			by the solver and never reaches the target, so `props.width` is nil on a
			mounted node and a pin on it would pass for anything. The line fills its
			column, so a squeeze lands on the name; the name is one line tall, so it
			truncates instead of wrapping the row taller. ]]
		local w = scenarioWorld(rowActions)
		local top = w.adapter.node(TOP_LINE)
		local column = w.adapter.node("/MailActions/ListWhen/ListPlate/List/Rows/RowsForEach/[m1]/m1/Content/Row/Text")
		local from = w.adapter.node(TOP_LINE .. "/From")
		assert(top ~= nil and column ~= nil and from ~= nil, "the row did not mount its sender line")
		expect(top.rect.w).toBe(column.rect.w)
		expect(from.rect.h <= top.rect.h).toBe(true)
	end)
end)

describe("list row plate: the paint, resolved through the sheet", function()
	it("the plate and the row both paint, and they never paint the same fill", function()
		local w = scenarioWorld(rowActions)
		local plate = w.adapter.node(PLATE_PATH)
		local row = w.adapter.node(ROW_PATH)
		local plateTags, rowTags = tagsOf(plate), tagsOf(row)
		local plateClass = ENGINE_CLASS[plate.class] or "Frame"
		local rowClass = ENGINE_CLASS[row.class] or "Frame"
		for _, entry in models() do
			local plateFill = restingFill(entry.model, entry.theme, plateClass, plateTags)
			local rowFill = restingFill(entry.model, entry.theme, rowClass, rowTags)
			assert(plateFill ~= nil, `{entry.label}: the list plate paints nothing`)
			assert(rowFill ~= nil, `{entry.label}: the row paints nothing`)
			assert(plateFill ~= rowFill, `{entry.label}: the plate and the row paint the same fill ({plateFill})`)
		end
		expect(#models() > 8).toBe(true)
	end)
end)
