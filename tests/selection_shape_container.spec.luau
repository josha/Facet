--!strict
--[[ THE HIGHLIGHT WEARS THE SHAPE OF THE STRIP THAT HOLDS IT.

	WHAT WAS REPORTED (owner, 2026-09-12, Compact Pointer): a pill-shaped tab
	strip holding a rounded-RECT selected fill. Two silhouettes in one control,
	and the theme was asked for neither of them.

	WHAT IT ACTUALLY WAS. Every strip plate in the framework takes its corner from
	`selection_indicator.TRACK_CORNER` — the theme's `radii.control` — and the fill
	inside it takes `radii.selection`, which FOLLOWS `radii.control` unless a
	package authors it (user ruling 2026-09-12, `tests/selection_radius.spec.luau`).
	So the plate and the fill are one decision, and they agree in every theme: a
	square package gets a square strip holding a square fill, a round one a capsule
	holding a capsule.

	`tab_view`'s adaptable app bar was the one strip that opted out. Its band form
	hard-coded `UI.cornersData("pill")` — `radii.pill`, a role no other strip
	spends and one every shipped package sets to 999 — while the fill inside it
	still took `radii.selection`. Under Compact Pointer that is a 999 capsule
	holding a 4px chip. The same commit round that removed the picker's own
	hard-coded pill ("only its outer ends round, with the theme's `radii.control`
	rather than a hard-coded pill") left this one behind.

	THE FIX. The band form takes `selection_indicator.TRACK_CORNER`, exactly as
	every other strip plate does, so the bar, the track and the fill are one
	decision in every theme. The rail form keeps `radii.panel`: a sidebar is a
	panel down the side of a screen, not a strip.

	WHAT IS PINNED HERE, and the three strips the brief asks for are three THEMES
	rather than three call sites, because the shape is the theme's:

	  * rect    `radii.control = 0`   -> square strip, square fill
	  * rounded `radii.control = 8`   -> 8px strip, 8px fill
	  * pill    `radii.control = 999` -> a capsule holding a capsule (the radius
	            exceeds half the bar's own cross extent, which is what the engine
	            clamps into a capsule — so this is asserted as a RATIO, not as a
	            number that would pass for a 999px square)

	...and the exception is pinned with them: a package that AUTHORS
	`radii.selection` still wins, because the fill's shape is the theme's decision
	and this file is about which decision it is, not about overriding it.
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
	local barPath: string? = nil
	for _, path in w.adapter.paths() do
		if string.sub(path, -#"/AdaptableBar") == "/AdaptableBar" then
			barPath = path
		end
	end
	assert(barPath ~= nil, "the adaptable bar did not mount in its band form")
	return w, w.adapter.node(barPath :: string), tabs
end

local STRIPS = {
	{ label = "rect", control = 0 },
	{ label = "rounded", control = 8 },
	{ label = "pill", control = 999 },
}

describe("selection shape: the strip's plate and the fill inside it are one decision", function()
	it("a tracked segmented picker paints its track and its fill on the same radius", function()
		for _, case in STRIPS do
			local metrics = packageWith(case.control)
			local w = stripWorld(metrics)
			local track = w.adapter.node(TRACK)
			local bar = w.adapter.node(BAR)
			assert(track ~= nil and bar ~= nil, `{case.label}: the strip did not mount its track and fill`)
			expect(`{case.label} track {paintedRadius(track, metrics)}`).toBe(`{case.label} track {case.control}`)
			expect(`{case.label} fill {paintedRadius(bar, metrics)}`).toBe(`{case.label} fill {case.control}`)
		end
	end)

	it("...and the pill case really is a capsule, not a very large square", function()
		local metrics = packageWith(999)
		local w = stripWorld(metrics)
		local bar = w.adapter.node(BAR)
		-- the engine clamps a corner radius at half the shorter side; a radius past
		-- that point is what makes a rounded rect a capsule
		expect(paintedRadius(bar, metrics) > bar.rect.h / 2).toBe(true)
		local rect = stripWorld(packageWith(0)).adapter.node(BAR)
		expect(0 > rect.rect.h / 2).toBe(false)
	end)
end)

describe("selection shape: the adaptable app bar is a strip like any other", function()
	it("its band form takes the strip corner, so the bar and the fill agree in every theme", function()
		for _, case in STRIPS do
			local metrics = packageWith(case.control)
			local w, bar, tabs = adaptableBarWorld(metrics)
			local fill = stripWorld(metrics).adapter.node(BAR)
			expect(`{case.label} bar {paintedRadius(bar, metrics)}`).toBe(
				`{case.label} bar {paintedRadius(fill, metrics)}`
			)
			tabs.dispose()
			local _ = w
		end
	end)

	it("the corner it spends is the strip token, named rather than copied", function()
		expect(selectionIndicator.TRACK_CORNER).toBe("control")
		local metrics = packageWith(4)
		local _, bar = adaptableBarWorld(metrics)
		expect(paintedRadius(bar, metrics)).toBe(4)
		-- ...and it is NOT the pill role, which is what it used to spend
		expect(metrics.radii.pill > 4).toBe(true)
	end)
end)

describe("selection shape: an authored `radii.selection` still wins", function()
	it("a package that authors a square highlight keeps one inside a capsule strip", function()
		local metrics = packageWith(999, 0)
		local w = stripWorld(metrics)
		expect(paintedRadius(w.adapter.node(TRACK), metrics)).toBe(999)
		expect(paintedRadius(w.adapter.node(BAR), metrics)).toBe(0)
	end)
end)
