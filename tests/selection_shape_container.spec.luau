--!strict
--[[ THE CONTAINER IS THE AUTHORITY ON THE FILL'S SILHOUETTE.

	WHAT WAS REPORTED (owner, 2026-09-12, Compact Pointer): a pill-shaped tab
	strip holding a rounded-RECT selected fill. Two silhouettes in one control,
	and the theme was asked for neither of them.

	WHICH HALF IS WRONG. The strip is: the owner photographed that capsule and
	asked to keep it. The FILL is the half that does not follow — it took
	`radii.selection`, a token that follows `radii.control`, and `radii.control` is
	what the picker's own TRACK wears rather than what every strip wears. A
	`TabView`'s adaptable app bar is a `radii.pill` capsule, so under Compact
	Pointer that is a 999 plate around a 4px chip.

	THE RULE, at the fill site (`selection_indicator.fillCornerFor`):

	  * an AUTHORED `radii.selection` still wins — a package is allowed to state
	    its highlight's shape outright, and Pixel Quest, Fantasy Ornate and Glossy
	    Touch all do;
	  * a PILL container gives a PILL fill, by the pill rule and not by
	    `999 - inset`: a package may spell "fully round" as any number past half
	    the box, and arithmetic on a sentinel is arithmetic on nothing;
	  * otherwise the fill is the container's radius LESS the inset it floats by,
	    floored at 0 — two concentric rounded rects, which is what an inset fill
	    inside a plate is.

	NOTHING ABOUT `radii.selection` ITSELF MOVES. The token is shared with a menu
	card's chosen-row shade, whose own contract is that the shade wears the CARD's
	radius at its two ends (`tests/selection_radius.spec.luau`); this file is about
	which shape the segmented fill asks for, never about what the token means.

	THE THREE STRIPS ARE THREE THEMES, because the shape is the theme's:

	    rect     `radii.control = 0`    plate 0     fill 0
	    rounded  `radii.control = 8`    plate 8     fill 4    (8 less the `xs` inset)
	    pill     `radii.control = 999`  plate 999   fill 995  (still a capsule)

	The pill row reaches the ARITHMETIC clause, not the pill one, and deliberately:
	its container is `radii.control` and a theme is free to make that number fully
	round. 995 on a 32px chip is still past half the box, so the fill is still a
	capsule — which is asserted as that ratio rather than as the number. The pill
	ROLE clause is the adaptable app bar's, below, because that bar is the one
	strip that names `radii.pill` outright.

	...and the strip's own plate is asserted UNCHANGED in each, because a fix that
	moved the container would be answering a different report.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/world")

local Facet = require("../src") :: any
local snapshot = require("../src/themes/snapshot")
local styling = require("../src/tokens/styling")
local selectionIndicator = require("../src/controls/selection_indicator")

local UI = Facet.UI

local BAR = "/S/View/Indicator/Layer/Bar"
local TRACK = "/S/View/Indicator/Track"

local PACKAGES = {
	"classic_desktop",
	"compact_pointer",
	"fantasy_ornate",
	"fantasy_parchment",
	"glossy_mobile",
	"glossy_touch",
	"pixel_quest",
	"scifi_hud",
}

-- a package a theme author could really ship: Facet Neutral with its control
-- radius moved, and nothing else
local function packageWith(control: number, selection: number?): any
	local metrics: any = { radii = { control = control } }
	if selection ~= nil then
		metrics.radii.selection = selection
	end
	local pkg, report = Facet.themes.define({
		base = snapshot.neutralPackage(),
		identity = {
			id = `shape-container-{control}-{tostring(selection)}`,
			displayName = "Shape Container",
			schemaVersion = Facet.themes.SCHEMA,
			version = "1.0.0",
		},
		metrics = metrics,
	})
	assert(pkg ~= nil, `package rejected: {tostring(report and report.errors and report.errors[1])}`)
	return snapshot.resolve(pkg, nil, {})
end

-- the painted radius of a node's corner data, resolved against the live metrics
-- exactly as the painter resolves it (a corner spent as a TOKEN is re-resolved
-- against the style it paints with, so reading the prop alone proves nothing)
local function paintedRadius(node: any, metrics: any): number
	local painted = styling.paintCorners(node.props.corners, metrics)
	assert(type(painted) == "table" and painted.radius ~= nil, "the corner is not a uniform radius")
	return painted.radius
end

local function stripWorld(metrics: any)
	local w = worldLib.new({
		viewport = { x = 0, y = 0, w = 640, h = 720 },
		safeInsets = { top = 0, bottom = 0, left = 0, right = 0 },
		themeMetrics = metrics,
	})
	local picker = Facet.Controls.Picker(w.core, {
		id = "View",
		selected = w.core:signal("a"),
		options = { { value = "a", label = "One" }, { value = "b", label = "Two" }, { value = "c", label = "Tri" } },
		env = w.env,
		presentation = "segmented",
	})
	w.present(UI.Screen({ id = "S", children = { picker.blueprint } }))
	return w
end

-- the adaptable app bar in its BAND form: a distant, gamepad-driven screen with
-- the sidebar collapsed, which is the shape the report was made against
local function adaptableBarWorld(metrics: any)
	local w = worldLib.new({
		viewport = { x = 0, y = 0, w = 1920, h = 1080 },
		preferredInput = "Gamepad",
		themeMetrics = metrics,
		env = { viewingDistance = "ten-foot" },
	})
	local tabs = Facet.Controls.TabView(w.core, {
		id = "Tabs",
		env = w.env,
		selection = w.core:signal("a"),
		style = "sidebarAdaptable",
		tabs = {
			{
				id = "a",
				label = "Pages",
				content = function()
					return UI.Text({ id = "A", text = "A" })
				end,
			},
			{
				id = "b",
				label = "Inbox",
				content = function()
					return UI.Text({ id = "B", text = "B" })
				end,
			},
		},
	})
	w.present(UI.Screen({ id = "S", children = { tabs.blueprint } }))
	tabs.collapseSidebar()
	w.settle(4)
	local barPath: string?, fillPath: string? = nil, nil
	for _, path in w.adapter.paths() do
		if string.sub(path, -#"/AdaptableBar") == "/AdaptableBar" then
			barPath = path
		end
		if string.sub(path, -#"/Strip/Indicator/Layer/Bar") == "/Strip/Indicator/Layer/Bar" then
			fillPath = path
		end
	end
	assert(barPath ~= nil, "the adaptable bar did not mount in its band form")
	assert(fillPath ~= nil, "the adaptable strip mounted no selected fill")
	return w, w.adapter.node(barPath :: string), w.adapter.node(fillPath :: string), tabs
end

local INSET = 4 -- the theme's `space.xs`, which is the fill's default inset

local STRIPS = {
	{ label = "rect", control = 0, fill = 0 },
	{ label = "rounded", control = 8, fill = 8 - INSET },
	{ label = "pill", control = 999, fill = 999 - INSET },
}

describe("selection shape: the fill wears the silhouette of the strip that holds it", function()
	it("a tracked segmented picker keeps its track's corner and insets the fill inside it", function()
		for _, case in STRIPS do
			local metrics = packageWith(case.control)
			local w = stripWorld(metrics)
			local track, bar = w.adapter.node(TRACK), w.adapter.node(BAR)
			assert(track ~= nil and bar ~= nil, `{case.label}: the strip did not mount its track and fill`)
			-- the CONTAINER is untouched...
			expect(`{case.label} track {paintedRadius(track, metrics)}`).toBe(`{case.label} track {case.control}`)
			-- ...and the FILL is what follows it
			expect(`{case.label} fill {paintedRadius(bar, metrics)}`).toBe(`{case.label} fill {case.fill}`)
		end
		expect(snapshot.resolveNumber(packageWith(8), "space.xs")).toBe(INSET)
	end)

	it("a pill container gives a pill fill, by the pill RULE and not by 999 minus the inset", function()
		local metrics = packageWith(999)
		local w = stripWorld(metrics)
		local bar = w.adapter.node(BAR)
		-- the engine clamps a corner radius at half the shorter side; a radius past
		-- that point is what makes a rounded rect a capsule
		expect(paintedRadius(bar, metrics) > bar.rect.h / 2).toBe(true)
		-- ...and the rule itself, as the TOKEN it spends. A number computed at the
		-- call site would freeze the near display's radius into a strip a ten-foot
		-- screen then paints with, so what the control names is a token and the
		-- style resolves it
		expect(selectionIndicator.fillCornerFor("pill")).toBe("selection:pill")
		expect(selectionIndicator.fillCornerFor("control")).toBe("selection:control")
		expect(snapshot.resolveNumber(metrics, "radii.selection:pill")).toBe(metrics.radii.pill)
		expect(snapshot.resolveNumber(metrics, "radii.selection:control")).toBe(999 - INSET)
	end)
end)

describe("selection shape: the adaptable app bar keeps its pill, and the fill follows it", function()
	it("the bar is still a capsule and the fill inside it is one too", function()
		for _, case in STRIPS do
			local metrics = packageWith(case.control)
			local w, bar, fill, tabs = adaptableBarWorld(metrics)
			-- the container the owner photographed, unchanged in every theme
			expect(`{case.label} bar {paintedRadius(bar, metrics)}`).toBe(`{case.label} bar {metrics.radii.pill}`)
			-- the pill ROLE, not `radii.pill - inset`: the fill resolves the SAME
			-- token its container declared
			expect(`{case.label} fill {paintedRadius(fill, metrics)}`).toBe(`{case.label} fill {metrics.radii.pill}`)
			tabs.dispose()
			local _ = w
		end
	end)

	--[[ THE RAIL FORM PASSES NOTHING (controller ruling, review round 2). Deriving
		from a container means insetting CONCENTRICALLY inside it, which is a true
		statement about a band — the chip and the capsule share a centre — and not
		about a rail: a selected row sits in the middle of a column, nowhere near
		the rail's outer corner, so `radii.panel - space.xs` would be a number with
		nothing behind it. Rail rows keep the plain `selection` token. ]]
	it("the sidebar rail declares no container, so its rows keep the plain selection token", function()
		local metrics = packageWith(8)
		local w = worldLib.new({
			viewport = { x = 0, y = 0, w = 1440, h = 900 },
			preferredInput = "KeyboardAndMouse",
			capabilities = { mouse = true, keyboard = true },
			themeMetrics = metrics,
		})
		local tabs = Facet.Controls.TabView(w.core, {
			id = "Tabs",
			env = w.env,
			selection = w.core:signal("a"),
			style = "sidebarAdaptable",
			tabs = {
				{
					id = "a",
					label = "Pages",
					content = function()
						return UI.Text({ id = "A", text = "A" })
					end,
				},
				{
					id = "b",
					label = "Inbox",
					content = function()
						return UI.Text({ id = "B", text = "B" })
					end,
				},
			},
		})
		w.present(UI.Screen({ id = "S", children = { tabs.blueprint } }))
		w.settle(4)
		expect(tabs.dump().placement).toBe("sidebar")
		local fillPath: string? = nil
		for _, path in w.adapter.paths() do
			if string.sub(path, -#"/Strip/Indicator/Layer/Bar") == "/Strip/Indicator/Layer/Bar" then
				fillPath = path
			end
		end
		assert(fillPath ~= nil, "the rail mounted no selected fill")
		local corners = w.adapter.node(fillPath :: string).props.corners
		expect(corners.tokens.radius).toBe(selectionIndicator.DEFAULT_CORNER)
		-- ...and that token is the theme's plain highlight radius, not a derivation
		expect(paintedRadius(w.adapter.node(fillPath :: string), metrics)).toBe(metrics.radii.control)
		tabs.dispose()
	end)

	it("...and a plain TabView, whose top band has no plate, passes no container at all", function()
		-- nothing to match means nothing to derive from: the fill keeps the
		-- `radii.selection` token it always took
		local metrics = packageWith(8)
		expect(selectionIndicator.fillCornerFor(nil)).toBe(selectionIndicator.DEFAULT_CORNER)
		expect(snapshot.resolveNumber(metrics, "radii.selection")).toBe(metrics.radii.control)
	end)
end)

--[[ `stripCorner` IS REFUSED RATHER THAN IGNORED, both ways (review round 2). It
	was the one key in `newPicker`'s spec with no assert and it is spent by exactly
	one branch, so a wrong value or a wrong combination resolved to nothing three
	layers down with no word to the author — which is the accepted-and-ignored
	class the closed spec exists to remove. ]]
describe("selection shape: naming a container that cannot answer is an authoring mistake", function()
	local function build(extra: any): (boolean, string)
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 640, h = 720 } })
		local spec: any = {
			id = "View",
			selected = w.core:signal("a"),
			options = { { value = "a", label = "One" }, { value = "b", label = "Two" } },
			env = w.env,
			presentation = "segmented",
		}
		for key, value in extra do
			spec[key] = value
		end
		local ok, err = pcall(function()
			return Facet.Controls.Picker(w.core, spec)
		end)
		return ok, tostring(err)
	end

	it("a container name outside the radius vocabulary refuses, and the message names the vocabulary", function()
		local ok, err = build({ track = false, stripCorner = "capsule" })
		expect(ok).toBe(false)
		expect(string.find(err, "stripCorner must name a container radius", 1, true) ~= nil).toBe(true)
		expect(string.find(err, styling.SELECTION_CONTAINER_LIST, 1, true) ~= nil).toBe(true)
		expect(string.find(err, "'capsule'", 1, true) ~= nil).toBe(true)
		-- ...and the names that DO answer are accepted
		expect(styling.isSelectionContainer("pill")).toBe(true)
		expect(styling.isSelectionContainer("control")).toBe(true)
		expect(styling.isSelectionContainer("panel")).toBe(true)
		-- a namespaced radius is deliberately not a container: the token's own
		-- grammar excludes the colon
		expect(styling.isSelectionContainer("gauge:ring")).toBe(false)
	end)

	--[[ THE VOCABULARY IS THE LIVE STYLE'S WHEN THERE IS ONE (task 7 item 11).
		`SELECTION_CONTAINERS` is derived from the BASE style's `radii`, which is
		the right default and the wrong answer for a package that adds a radius of
		its own: `radii.selection:chip` RESOLVES perfectly well under such a
		package (`snapshot.resolveNumber` reads the live table), and the authoring
		check refused the name before it ever got there. The refusal is a service
		— it names the mistake where it was written — so it has to be checked
		against the radii the fill will actually resolve through, not against a
		vocabulary that predates the package. ]]
	it("a package that authors `radii.chip` may name it, and the base names still work", function()
		local pkg, report = Facet.themes.define({
			base = snapshot.neutralPackage(),
			identity = {
				id = "shape-container-chip",
				displayName = "Shape Container Chip",
				schemaVersion = Facet.themes.SCHEMA,
				version = "1.0.0",
			},
			metrics = { radii = { chip = 6 } },
		})
		assert(pkg ~= nil, `package rejected: {tostring(report and report.errors and report.errors[1])}`)
		local metrics = snapshot.resolve(pkg, nil, {})
		expect((metrics :: any).radii.chip).toBe(6)
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 640, h = 720 }, themeMetrics = metrics })
		local function buildIn(corner: string): (boolean, string)
			local ok, err = pcall(function()
				return Facet.Controls.Picker(w.core, {
					id = "View",
					selected = w.core:signal("a"),
					options = { { value = "a", label = "One" }, { value = "b", label = "Two" } },
					env = w.env,
					presentation = "segmented",
					track = false,
					stripCorner = corner,
				})
			end)
			return ok, tostring(err)
		end
		expect(buildIn("chip")).toBe(true)
		expect(buildIn("pill")).toBe(true) -- the base vocabulary is never NARROWED by a package
		-- ...and the name the fill resolver would actually answer for it
		expect(snapshot.resolveNumber(metrics, "radii.selection:chip") ~= nil).toBe(true)
		-- a name NO radii table has is still refused, and the message lists the
		-- live vocabulary — `chip` included — rather than the base one
		local ok, err = buildIn("capsule")
		expect(ok).toBe(false)
		expect(string.find(err, "chip", 1, true) ~= nil).toBe(true)
		expect(styling.isSelectionContainer("chip", (metrics :: any).radii)).toBe(true)
		expect(styling.isSelectionContainer("chip")).toBe(false)
		-- the colon grammar is unchanged: a namespaced radius a package authors is
		-- still not a container name
		expect(styling.isSelectionContainer("gauge:ring", { ["gauge:ring"] = 4 })).toBe(false)
	end)

	it("a container NO style publishes still errors through the public `UI.corners` (review N6)", function()
		--[[ item 11's first shape made the AUTHORING corner resolve deferrable
			for any `selection:<container>` token when no style was passed. That
			is the form the public `UI.corners`/`UI.cornersData` take, and
			`paintCorners` is total — a token the live style cannot answer keeps
			the authored number silently — so `selection:panle` would have
			resolved to the plain selection radius and painted it forever with
			nothing ever saying a word. The refusal is global again; what moved
			is WHICH STYLE is asked, at the one caller that has a better answer
			than the base one. ]]
		local ok, err = pcall(function()
			return UI.cornersData("selection:panle")
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "unknown radius token 'selection:panle'", 1, true) ~= nil).toBe(true)
		-- ...through the blueprint wrap as well as the data form
		expect(pcall(function()
			return UI.corners(UI.Box({ id = "B" }), "selection:panle")
		end)).toBe(false)
		-- ...and `chip` is refused by the BASE style too, which is exactly why the
		-- indicator hands the normalizer the live snapshot instead
		expect(pcall(function()
			return UI.cornersData("selection:chip")
		end)).toBe(false)
		-- the same token, asked of a style that publishes the container, resolves
		local pkg = Facet.themes.define({
			base = snapshot.neutralPackage(),
			identity = {
				id = "n6-chip",
				displayName = "N6 Chip",
				schemaVersion = Facet.themes.SCHEMA,
				version = "1.0.0",
			},
			metrics = { radii = { chip = 6 } },
		})
		local live = snapshot.resolve(pkg, nil, {})
		expect(pcall(function()
			return UI.cornersData("selection:chip", live)
		end)).toBe(true)
		expect(pcall(function()
			return UI.cornersData("selection:panle", live)
		end)).toBe(false)
	end)

	it("an authored `radii.selection` does not make every spelling resolvable (review D5)", function()
		--[[ the authored-selection shortcut answered BEFORE the container was
			checked, so a package with a square highlight made
			`selection:totally_made_up` resolve to 0 — a typo painting the
			authored highlight forever rather than being refused. Three shipped
			packages author `radii.selection`, so this was the common case, not
			the exotic one. ]]
		local metrics = packageWith(8, 7) -- authors radii.selection = 7
		expect((metrics :: any).radii.selection).toBe(7)
		-- the containers this style DOES publish still take the shortcut
		expect(snapshot.resolveNumber(metrics, "radii.selection:control")).toBe(7)
		expect(snapshot.resolveNumber(metrics, "radii.selection:pill")).toBe(7)
		expect(snapshot.resolveNumber(metrics, "radii.selection:panel")).toBe(7)
		-- ...and one it does not publish is refused, authored highlight or not
		expect(snapshot.resolveNumber(metrics, "radii.selection:totally_made_up")).toBeNil()
		expect(pcall(function()
			return UI.cornersData("selection:totally_made_up", metrics)
		end)).toBe(false)
		-- the plain token is untouched: it names no container to check
		expect(snapshot.resolveNumber(metrics, "radii.selection")).toBe(7)
	end)

	it("a swap AWAY from the package that published the container keeps a corner (review D6)", function()
		--[[ asking the live style makes the answer depend on the live style, so a
			swap away from the package that published `radii.chip` turns a token
			that resolved a frame ago into one this style cannot answer. Inside a
			memo that is QUARANTINED: the bar would lose its corner data entirely
			and paint square — a worse answer than the one the token was reaching
			for. The derived token falls back to the plain `selection` radius, the
			same family, which every style can answer. ]]
		local pkg = Facet.themes.define({
			base = snapshot.neutralPackage(),
			identity = {
				id = "d6-chip",
				displayName = "D6 Chip",
				schemaVersion = Facet.themes.SCHEMA,
				version = "1.0.0",
			},
			metrics = { radii = { chip = 6 } },
		})
		local chipMetrics = snapshot.resolve(pkg, nil, {})
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 640, h = 720 }, themeMetrics = chipMetrics })
		-- a REACTIVE `stripCorner`, which is the shape `TabView` hands in and the
		-- only one whose corner is re-derived on a swap: a static one resolved
		-- once at build and keeps the token it took, which `paintCorners` then
		-- answers for or leaves at the authored number — no memo, nothing to
		-- quarantine
		local container = w.core:signal("chip")
		local picker = Facet.Controls.Picker(w.core, {
			id = "View",
			selected = w.core:signal("a"),
			options = { { value = "a", label = "One" }, { value = "b", label = "Two" } },
			env = w.env,
			presentation = "segmented",
			track = false,
			stripCorner = container,
		})
		w.present(UI.Screen({ id = "S", children = { picker.blueprint } }))
		local bar = w.adapter.node(BAR)
		expect(bar ~= nil).toBe(true)
		expect((bar :: any).props.corners.tokens.radius).toBe("selection:chip")

		-- the swap away: the container this token names no longer exists
		w.env:set("themeMetrics", snapshot.neutral())
		w.pres.refresh()
		local after = w.adapter.node(BAR)
		expect(after ~= nil).toBe(true)
		local corners = (after :: any).props.corners
		expect(`corners present: {corners ~= nil}`).toBe("corners present: true")
		-- THE DIRECT EVIDENCE FIRST: nothing was quarantined. Without the
		-- defensive resolve the memo raises here, `core:lastError()` records it,
		-- and the bar keeps whatever corner data it happened to hold — a stale
		-- token under a style that cannot answer it.
		expect(`quarantined: {tostring(w.core:lastError())}`).toBe("quarantined: nil")
		-- ...and it re-derived to the plain `selection` token, which every style
		-- answers
		expect(corners.tokens.radius).toBe("selection")
		expect(type(corners.radius) == "number").toBe(true)
		-- ...and a swap BACK re-derives the container answer, because the token
		-- was never the thing that broke
		w.env:set("themeMetrics", chipMetrics)
		w.pres.refresh()
		expect((w.adapter.node(BAR) :: any).props.corners.tokens.radius).toBe("selection:chip")
		picker.dispose()
		container:dispose()
	end)

	it("a REACTIVE stripCorner typo is healed, but SAID — once per token", function()
		--[[ the defensive resolve exists for a legitimate case (a theme swapped
			away from the package that publishes the container) and catches an
			illegitimate one just as quietly: a REACTIVE `stripCorner` whose value
			becomes a typo. `newPicker` refuses a typo it can SEE at build and by
			construction cannot see a value set later, so before this the typo
			path was more silent than the pre-fix behaviour, which at least left a
			recorded quarantine. It is noted now — once per token, so a strip that
			re-renders every frame says it once — and `dump().indicator
			.cornerFallbacks` is how that "once" is asserted rather than watched
			for in a log. ]]
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 640, h = 720 } })
		local container = w.core:signal("panel")
		local picker = Facet.Controls.Picker(w.core, {
			id = "View",
			selected = w.core:signal("a"),
			options = { { value = "a", label = "One" }, { value = "b", label = "Two" } },
			env = w.env,
			presentation = "segmented",
			track = false,
			stripCorner = container,
		})
		w.present(UI.Screen({ id = "S", children = { picker.blueprint } }))
		expect((w.adapter.node(BAR) :: any).props.corners.tokens.radius).toBe("selection:panel")
		expect(picker.dump().indicator.cornerFallbacks).toBe(0)

		container:set("panle")
		w.pres.refresh()
		-- healed: the bar still has a corner, the plain one every style answers
		expect((w.adapter.node(BAR) :: any).props.corners.tokens.radius).toBe("selection")
		-- ...and nothing was quarantined, which is what the fallback bought
		expect(`quarantined: {tostring(w.core:lastError())}`).toBe("quarantined: nil")
		-- ...and it was SAID, exactly once
		expect(picker.dump().indicator.cornerFallbacks).toBe(1)

		-- the same bad token again says nothing more, however many re-renders
		container:set("panel")
		w.pres.refresh()
		container:set("panle")
		w.pres.refresh()
		expect(picker.dump().indicator.cornerFallbacks).toBe(1)

		-- a DIFFERENT bad token is its own note
		container:set("panl")
		w.pres.refresh()
		expect(picker.dump().indicator.cornerFallbacks).toBe(2)

		-- and a good one still resolves, so the fallback is not a latch
		container:set("pill")
		w.pres.refresh()
		expect((w.adapter.node(BAR) :: any).props.corners.tokens.radius).toBe("selection:pill")
		picker.dispose()
		container:dispose()
	end)

	it("with NO theme in hand at all the message says the vocabulary is the base style's", function()
		--[[ the picker built without an `env` (and outside any surface, so
			`surfaceEnv.find` answers nothing) has no live radii to check against.
			The refusal is then the base style's vocabulary — which is the honest
			answer, and the message says so rather than implying the framework
			knows every radius that exists. ]]
		-- a BARE core: no presenter, no surface, so `surfaceEnv.find` answers
		-- nothing and there is no live radii table to check against
		local core = Facet.newCore()
		local ok, err = pcall(function()
			return Facet.Controls.Picker(core, {
				id = "View",
				selected = core:signal("a"),
				options = { { value = "a", label = "One" }, { value = "b", label = "Two" } },
				presentation = "segmented",
				track = false,
				stripCorner = "chip",
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "BASE style's", 1, true) ~= nil).toBe(true)
	end)

	it("naming a container on a TRACKED strip refuses, and the message says which of the two to drop", function()
		-- a tracked strip draws its own plate at `SEGMENT_RADIUS`, so the container
		-- is already known and a caller naming another is stating a contradiction
		local ok, err = build({ stripCorner = "pill" })
		expect(ok).toBe(false)
		expect(string.find(err, "a tracked strip draws its own plate", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "track = false", 1, true) ~= nil).toBe(true)
		-- ...and the legitimate combination builds
		expect((build({ track = false, stripCorner = "pill" }))).toBe(true)
	end)
end)

describe("selection shape: an authored `radii.selection` still wins", function()
	it("a package that authors a square highlight keeps one inside a capsule strip", function()
		local metrics = packageWith(999, 0)
		local w = stripWorld(metrics)
		expect(paintedRadius(w.adapter.node(TRACK), metrics)).toBe(999)
		expect(paintedRadius(w.adapter.node(BAR), metrics)).toBe(0)
		-- ...at the rule itself, through every container it could be asked about
		expect(snapshot.resolveNumber(metrics, "radii.selection:pill")).toBe(0)
		expect(snapshot.resolveNumber(metrics, "radii.selection:control")).toBe(0)
	end)

	--[[ THE SHIPPED CORPUS, and Fantasy Ornate is the case that makes it worth
		running: it authors a `chrome.navigation` recipe, so its adaptable bar wears
		ART rather than a painted plate, and it authors `radii.selection = 0` on top
		of that. A fill that resolved to nothing under a package like that is
		exactly the failure a derivation can introduce, so every shipped theme is
		asked for a real number. ]]
	it("every shipped theme resolves a fill radius, art-skinned navigation included", function()
		local ornate = require("../examples/themes/fantasy_ornate").build(Facet.themes)
		expect(type(ornate.chrome.navigation)).toBe("table")
		local checked = 0
		for _, name in PACKAGES do
			local package = (require :: any)(`../examples/themes/{name}`).build(Facet.themes)
			for _, theme in package.style.themes do
				local metrics = Facet.themes.resolve(package, theme.name, {})
				local w = stripWorld(metrics)
				local radius = paintedRadius(w.adapter.node(BAR), metrics)
				checked += 1
				assert(
					type(radius) == "number" and radius >= 0,
					`{name}/{theme.name}: the fill resolved no radius ({tostring(radius)})`
				)
				local authored = metrics.radii.selection
				if type(authored) == "number" then
					assert(
						radius == authored,
						`{name}/{theme.name}: authored selection {authored} lost to a derived {radius}`
					)
				end
			end
		end
		expect(checked > 8).toBe(true)
	end)
end)
