--!strict
local harness = require("./lib/harness")
--[[ A TAB STRIP DOES NOT TOUCH ITS PAGE.

	WHAT WAS REPORTED (owner, 2026-09-12, Compact Pointer and others): the tab
	strip and the content under it are butted together. The strip is a plate with
	its own corner and its own fill, and the page starts on the pixel below it, so
	two surfaces meet with no air between them and the strip reads as part of the
	page rather than as the control above it.

	WHAT IT ACTUALLY WAS. `tab_view`'s root stack spent a gap for exactly one of
	the four placements:

	    gap = if use(sidebar) then "m" else 0

	— and its neighbouring comment said so out loud ("a top or bottom band takes
	no extra vertical gap"). So a rail beside a page got 16px of theme spacing and
	a band above one got zero, in every theme, at every text size. That is not a
	per-theme accident: Facet Neutral butts them together too. It is one branch.

	THE FIX. The gap is one decision for the placements that have room for one —
	the theme's `m` step beside a rail, its `s` step above or below a band — spent
	as a METRIC NAME, so a package that retunes its spacing retunes the tab gap
	with it and a ten-foot display's scaled steps reach it with nothing to update.

	...AND `bottomBarCompact` SPENDS NONE, which is not an exception so much as
	the placement's own reason for existing. The policy picks it when the screen
	is too short for the ordinary thumb-zone band, and the chrome gives way before
	the content does. Measured: a uniform `s` cost `examples/reference/p4_foyer`
	8px it did not have — at 640x320 and the largest text preference its page
	already overflows by 19px, and the gap made it 27, with the construct's own
	`Nav` overflowing by 4-6 under three packages beside it
	(`tests/overflow_sweep.spec.luau`).

	WHAT IS PINNED HERE:

	  1. Every placement with room for a gap leaves one, measured between the
	     strip's own home band and the content pane, on that placement's own axis.
	  2. It is the THEME's number and not a literal: the same placements measured
	     under a package that doubles its spacing scale come out doubled.
	  3. The sidebar's own gap is unchanged, so the fix adds cases rather than
	     re-deciding the one that already worked.
	  4. The compact band's zero is pinned as a decision, beside the reason.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/harness_world")

local Facet = require("../src") :: any
local default_style = require("../src/tokens/default_style")
local Compose = require("../src/vendor/compose/core")

local UI = harness.UI

-- viewport → the placement the policy resolves, but every case declares the
-- placement it means so the measurement cannot silently move to another home
local VIEW: { [string]: { w: number, h: number } } = {
	bottomBar = { w = 320, h = 640 },
	bottomBarCompact = { w = 800, h = 400 },
	topBar = { w = 900, h = 900 },
	sidebar = { w = 1200, h = 900 },
}

local BAND_OF: { [string]: string } = {
	topBar = "TopHome/then/TopBandCenter/TopBand",
	sidebar = "RailHome/then/Rail",
	bottomBar = "BottomHome/then/BottomBand",
	bottomBarCompact = "CompactHome/then/CompactBandCenter/CompactBand",
}

local function body(name: string)
	return function(_scope: any)
		return UI.Text({ id = name .. "Body", text = name })
	end
end

local function world(placement: string, themePackage: any?)
	local view = VIEW[placement]
	local w = worldLib.new({
		viewport = { x = 0, y = 0, w = view.w, h = view.h },
		safeInsets = { top = 0, bottom = 0, left = 0, right = 0 },
		themeMetrics = if themePackage ~= nil then Facet.themes.resolve(themePackage, nil, {}) else nil,
	})
	local tv = harness.Controls.TabView(w.core, {
		id = "Tabs",
		selection = Compose.cell("home"),
		env = w.env,
		placement = placement,
		tabs = {
			{ id = "home", label = "Home", content = body("home") },
			{ id = "feed", label = "Feed", content = body("feed") },
			{ id = "me", label = "Me", content = body("me") },
		},
	})
	w.present(UI.Screen({ id = "S", children = { tv.blueprint } }), { sinkNavigation = true })
	return { adapter = w.adapter, tv = tv }
end

-- the clear distance between the strip's home band and the content pane, on the
-- axis that separates them. Measured from the solved rects, never read off a
-- prop: a gap declared and not spent is exactly the defect this file is about.
local function gapFor(placement: string, themePackage: any?): number
	local w = world(placement, themePackage)
	assert(w.tv.dump().placement == placement, `the policy did not honour placement '{placement}'`)
	local band = w.adapter.node(`/S/Tabs/{BAND_OF[placement]}`)
	local content = w.adapter.node("/S/Tabs/Content")
	assert(band ~= nil and content ~= nil, `{placement}: the home or the content pane did not mount`)
	if placement == "sidebar" then
		return content.rect.x - (band.rect.x + band.rect.w)
	elseif placement == "topBar" then
		return content.rect.y - (band.rect.y + band.rect.h)
	end
	return band.rect.y - (content.rect.y + content.rect.h)
end

describe("tab strip gap: the strip never touches the page", function()
	it("a top band leaves the theme's `s` step between itself and the content", function()
		expect(gapFor("topBar")).toBe(default_style.space.s)
	end)

	it("...and so does a thumb-zone band", function()
		expect(gapFor("bottomBar")).toBe(default_style.space.s)
	end)

	--[[ THE SHORT SCREEN'S BAND IS THE ONE THAT SPENDS NOTHING, and it is pinned
		rather than merely allowed: a future round that "finishes" the rule by
		making this uniform would take 8px off a 320px-tall landscape, which is
		what `p4_foyer` measured and what this zero exists to prevent. ]]
	it("the compact band spends none, because a screen that short has none to spend", function()
		expect(gapFor("bottomBarCompact")).toBe(0)
	end)

	it("the sidebar rail keeps the wider `m` step it already had", function()
		expect(gapFor("sidebar")).toBe(default_style.space.m)
	end)
end)

describe("tab strip gap: it is the theme's number, not a literal", function()
	--[[ A package that spends different spacing steps moves the gap with it. The
		proof has to be a real package rather than a hand-made metrics table,
		because the metric reaches the solver through `themes.resolve` and a table
		that skipped that path would prove the test's arithmetic and not the
		control's. ]]
	local function doubledSpacing(): any
		local snapshot = require("../src/themes/snapshot")
		local base = snapshot.neutralPackage()
		return Facet.themes.define({
			base = base,
			identity = {
				id = "tab-gap-test",
				displayName = "Tab Gap Test",
				schemaVersion = Facet.themes.SCHEMA,
				version = "1.0.0",
			},
			metrics = { space = { xs = 8, s = 16, m = 32, l = 48, xl = 80 } },
		})
	end

	it("every placement's gap follows the package's own spacing steps", function()
		local package = doubledSpacing()
		expect(gapFor("topBar", package)).toBe(16)
		expect(gapFor("bottomBar", package)).toBe(16)
		expect(gapFor("sidebar", package)).toBe(32)
		-- ...and the one that spends nothing spends nothing under any package
		expect(gapFor("bottomBarCompact", package)).toBe(0)
	end)
end)
