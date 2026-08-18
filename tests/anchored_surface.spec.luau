--!strict
--[[ D1 — THE ANCHORED-SURFACE SEAM (navigation-and-menus brief §2 D1).

	A presenter surface positioned against a SOURCE VIEW'S screen rect rather
	than a parent corner: preferred edge, safe-area flip, along-edge shift, an
	arrow tail that is suppressed when the shift carries it off the source, and
	a moving source followed on the cadence that already exists.

	Three layers are proved here, in order:

	  1. `anchor_placement.solve` — the PURE decision. Plain numbers in, a plain
	     placement out, no env, no signals, no engine. Every flip/shift/tail rule
	     lives here, which is what lets the two hand-rolled precedents and the new
	     surface share ONE answer instead of three.
	  2. `presenter.presentAnchored` — the surface. It REUSES the presenter's own
	     stack, focus scopes, layering and tap-away catcher; the only thing it adds
	     is where the panel lands and the tail that points back at the source.
	  3. the two precedents, now consuming (1): the presenter's own disclosure
	     plate and `row_actions`' floating menu.

	The fixture is `docs/plans/reference-media/2026-08-16-roblox-app-navigation/
	f1-avatar-editor.jpeg` — the "Post Avatars to Marketplace" plate, anchored
	under a top-right `+` button, arrow pointing UP at it, body shifted LEFT to
	stay on screen. It has its own describe block below.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local anchorPlacement = require("../src/layout/anchor_placement")
local chrome_slots = require("../src/tokens/chrome_slots")
local contribution = require("../src/input/contribution")
local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local environment = require("../src/env/environment")
local actionsLib = require("../src/input/actions")
local presenterLib = require("../src/present/presenter")
local fake_target = require("../tests/lib/fake_target")

-- ===== layer 1: the pure solver =========================================

local SAFE = { x = 0, y = 0, w = 400, h = 800 }

local function solve(req: any): any
	return anchorPlacement.solve(req)
end

describe("D1 placement solver: the preferred edge, and the gap off the source", function()
	it("places the surface on the preferred edge, gapped off the source", function()
		local p = solve({
			source = { x = 100, y = 100, w = 80, h = 40 },
			size = { w = 120, h = 60 },
			safe = SAFE,
			edge = "bottom",
			align = "center",
			gap = 8,
		})
		-- below the source by the gap, centred on it
		expect(p.y).toBe(148)
		expect(p.x).toBe(80)
		expect(p.edge).toBe("bottom")
		expect(p.flipped).toBe(false)
		expect(p.shift).toBe(0)
		expect(p.fits).toBe(true)
	end)

	it("alignment start, center and end place the surface along the edge", function()
		local src = { x = 100, y = 100, w = 80, h = 40 }
		local size = { w = 120, h = 60 }
		local function at(align: string): number
			return solve({ source = src, size = size, safe = SAFE, edge = "bottom", align = align, gap = 0 }).x
		end
		expect(at("start")).toBe(100)
		expect(at("center")).toBe(80)
		expect(at("end")).toBe(60)
	end)

	it("leading and trailing resolve to left and right", function()
		local src = { x = 200, y = 300, w = 80, h = 40 }
		local size = { w = 60, h = 60 }
		local lead = solve({ source = src, size = size, safe = SAFE, edge = "leading", align = "center", gap = 10 })
		local trail = solve({ source = src, size = size, safe = SAFE, edge = "trailing", align = "center", gap = 10 })
		expect(lead.edge).toBe("left")
		expect(lead.x).toBe(130) -- 200 - 10 - 60
		expect(trail.edge).toBe("right")
		expect(trail.x).toBe(290) -- 200 + 80 + 10
	end)

	it("refuses an unknown edge, alignment or overflow policy", function()
		local base = { source = { x = 0, y = 0, w = 10, h = 10 }, size = { w = 10, h = 10 }, safe = SAFE }
		local function bad(over: any): string
			local merged: any = table.clone(base)
			for k, v in over do
				merged[k] = v
			end
			local ok, err = pcall(solve, merged)
			expect(ok).toBe(false)
			return tostring(err)
		end
		expect(string.find(bad({ edge = "above" }), "edge", 1, true) ~= nil).toBe(true)
		expect(string.find(bad({ align = "middle" }), "align", 1, true) ~= nil).toBe(true)
		expect(string.find(bad({ overflow = "hide" }), "overflow", 1, true) ~= nil).toBe(true)
	end)
end)

describe("D1 placement solver: the flip, and the rule that it never lands somewhere worse", function()
	it("flips to the opposite edge when the preferred one crosses the safe inset", function()
		-- a source near the bottom: below would run past the safe box, above fits
		local p = solve({
			source = { x = 100, y = 700, w = 80, h = 40 },
			size = { w = 120, h = 90 },
			safe = { x = 0, y = 40, w = 400, h = 726 }, -- a notch and a home indicator
			edge = "bottom",
			align = "center",
			gap = 8,
		})
		expect(p.edge).toBe("top")
		expect(p.flipped).toBe(true)
		expect(p.y).toBe(602) -- 700 - 8 - 90
		expect(p.fits).toBe(true)
	end)

	it("never flips into a worse place — no room either way keeps the preferred edge", function()
		--[[ row_actions.luau:1902-1905 states the rule this encodes: "IT NEVER
			FLIPS INTO A WORSE PLACE. Both conditions have to hold: a menu too tall
			for the space above stays below (partly clipped is better than partly
			clipped AND upside down)." ]]
		local p = solve({
			source = { x = 0, y = 300, w = 80, h = 40 },
			size = { w = 120, h = 600 }, -- taller than the space either side of the source
			safe = { x = 0, y = 0, w = 400, h = 800 },
			edge = "bottom",
			align = "start",
			gap = 0,
			overflow = "keep",
		})
		expect(p.edge).toBe("bottom")
		expect(p.flipped).toBe(false)
		expect(p.y).toBe(340)
		expect(p.fits).toBe(false)
	end)

	it("overflow 'clamp' pulls a surface that fits nowhere back inside the safe box", function()
		local p = solve({
			source = { x = 0, y = 300, w = 80, h = 40 },
			size = { w = 120, h = 600 },
			safe = { x = 0, y = 40, w = 400, h = 720 },
			edge = "bottom",
			align = "start",
			gap = 0,
		})
		expect(p.flipped).toBe(false)
		expect(p.y).toBe(160) -- 40 + 720 - 600
		expect(p.y >= 40).toBe(true)
	end)
end)

describe("D1 placement solver: the along-edge shift", function()
	it("shifts along the edge to stay inside the safe box, and reports how far", function()
		-- a source hard against the right edge with a wide surface: it must move left
		local p = solve({
			source = { x = 340, y = 100, w = 44, h = 44 },
			size = { w = 260, h = 120 },
			safe = { x = 0, y = 0, w = 400, h = 800 },
			edge = "bottom",
			align = "center",
			gap = 8,
		})
		expect(p.x).toBe(140) -- 400 - 260
		expect(p.x + p.w <= 400).toBe(true)
		-- aligned centre would have been 340 + 22 - 130 = 232; it moved 92px left
		expect(p.shift).toBe(-92)
	end)

	it("a surface TALLER than the safe box pins to the top inset rather than hanging off the bottom", function()
		-- the placement-axis twin of the rule below, and the same expression: a
		-- surface with no legal range shows its head rather than sitting wherever
		-- the preferred edge put it
		local p = solve({
			source = { x = 0, y = 700, w = 80, h = 40 },
			size = { w = 120, h = 900 },
			safe = { x = 0, y = 40, w = 400, h = 760 },
			edge = "bottom",
			align = "start",
			gap = 0,
		})
		expect(p.y).toBe(40)
		expect(p.fits).toBe(false)
	end)

	it("a surface wider than the safe box pins to the leading inset rather than centring off-screen", function()
		local p = solve({
			source = { x = 100, y = 100, w = 40, h = 40 },
			size = { w = 500, h = 60 },
			safe = { x = 16, y = 0, w = 368, h = 800 },
			edge = "bottom",
			align = "center",
			gap = 0,
		})
		expect(p.x).toBe(16)
	end)
end)

describe("D1 placement solver: the arrow tail", function()
	it("the tail centres on the source and rides the shared border", function()
		local p = solve({
			source = { x = 100, y = 100, w = 80, h = 40 },
			size = { w = 120, h = 60 },
			safe = SAFE,
			edge = "bottom",
			align = "center",
			gap = 8,
			tail = 20,
			tailInset = 12,
		})
		expect(p.tailSuppressed).toBe(false)
		expect(p.tailX).toBe(140) -- the source's own centre
		expect(p.tailY).toBe(p.y) -- the surface's top edge: the border it shares with the source
	end)

	it("the tail keeps clear of the surface's own corners", function()
		local p = solve({
			source = { x = 0, y = 100, w = 30, h = 40 },
			size = { w = 200, h = 60 },
			safe = SAFE,
			edge = "bottom",
			align = "start",
			gap = 0,
			tail = 20,
			tailInset = 12,
		})
		-- the source's centre is x=15, which is inside the surface but inside its
		-- corner keep-out too (12 + half the tail = 22), so the tail stops at 22 —
		-- still over the source (0..30), so it is kept
		expect(p.tailX).toBe(22)
		expect(p.tailSuppressed).toBe(false)
	end)

	it("a shift that carries the tail off the source SUPPRESSES it", function()
		-- the surface is shoved so far along the edge that the nearest legal tail
		-- position is no longer over the source at all: an arrow pointing at
		-- nothing is worse than no arrow
		local p = solve({
			source = { x = 380, y = 100, w = 20, h = 40 },
			size = { w = 200, h = 60 },
			safe = { x = 0, y = 0, w = 400, h = 800 },
			edge = "bottom",
			align = "center",
			gap = 0,
			tail = 20,
			tailInset = 60,
		})
		expect(p.x).toBe(200)
		expect(p.tailSuppressed).toBe(true)
	end)

	it("a surface the overflow clamp pulled OFF its edge suppresses the tail too", function()
		-- the across-the-edge half of the suppression rule: a panel that fits on
		-- neither side is dragged back inside the safe box, and a wedge left on its
		-- border there is an arrow with a gap under it
		local p = solve({
			source = { x = 100, y = 700, w = 80, h = 40 },
			size = { w = 200, h = 900 },
			safe = { x = 0, y = 40, w = 400, h = 760 },
			edge = "bottom",
			align = "center",
			gap = 0,
			tail = 20,
			tailInset = 12,
		})
		expect(p.y).toBe(40) -- clamped: it fits neither below nor above
		expect(p.tailSuppressed).toBe(true)
	end)

	it("a surface too narrow to host the tail inside its corners suppresses it", function()
		local p = solve({
			source = { x = 100, y = 100, w = 80, h = 40 },
			size = { w = 20, h = 60 },
			safe = SAFE,
			edge = "bottom",
			align = "center",
			gap = 0,
			tail = 20,
			tailInset = 12,
		})
		expect(p.tailSuppressed).toBe(true)
	end)

	it("a tail on a side edge rides the vertical border and centres on the source's own middle", function()
		local p = solve({
			source = { x = 100, y = 300, w = 40, h = 60 },
			size = { w = 120, h = 200 },
			safe = SAFE,
			edge = "trailing",
			align = "center",
			gap = 6,
			tail = 20,
			tailInset = 12,
		})
		expect(p.edge).toBe("right")
		expect(p.tailX).toBe(p.x)
		expect(p.tailY).toBe(330)
		expect(p.tailSuppressed).toBe(false)
	end)

	it("no tail requested means no tail decided", function()
		local p = solve({
			source = { x = 100, y = 100, w = 80, h = 40 },
			size = { w = 120, h = 60 },
			safe = SAFE,
			edge = "bottom",
			align = "center",
			gap = 8,
		})
		expect(p.tailSuppressed).toBe(true)
		expect(p.tailX).toBeNil()
	end)
end)

-- ===== layer 2: the presented surface ===================================

local PANEL_TEXT = "Post Avatars to Marketplace"

local function makeWorld(w: number?, h: number?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = w or 390, h = h or 844 })
	local adapter = fake_target.new()
	local system = actionsLib.newSystem(core)
	local pres = presenterLib.new(core, env, adapter, system)
	return core, env, adapter, system, pres
end

-- a screen with one 44px square button pinned to the top-RIGHT corner: the `+`
-- in the fixture image
local function plusScreen(): any
	return UI.Screen({
		id = "Editor",
		children = {
			UI.Anchor({
				id = "Bar",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					UI.Button({
						id = "Plus",
						label = "+",
						anchor = "topRight",
						width = { type = "fixed", px = 44 },
						height = { type = "fixed", px = 44 },
					}),
				},
			}),
		},
	})
end

local function calloutPanel(width: number): any
	return UI.VStack({
		id = "Callout",
		surface = "raised",
		padding = "s",
		width = { type = "fixed", px = width },
		children = { UI.Text({ id = "Body", text = PANEL_TEXT, textSize = 16 }) },
	})
end

local SURFACE = "/Tip/Layer/Surface"
local TAIL = "/Tip/Layer/Tail"
local TAIL_SEAM = "/Tip/Layer/TailSeam"

local ROOT_TWO = math.sqrt(2)

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 0.01)
end

describe("D1 anchored surface: presented against a source view's screen rect", function()
	it("presentAnchored places the panel against the source path's screen rect", function()
		local _, _, adapter, _, pres = makeWorld()
		pres.present(plusScreen(), { initialFocus = "none" })
		pres.presentAnchored(calloutPanel(200), {
			id = "Tip",
			initialFocus = "none",
			anchor = { source = { path = "/Editor/Bar/Plus" }, edge = "bottom", align = "center" },
		})
		local plus = adapter.node("/Editor/Bar/Plus").rect
		local panel = adapter.node(SURFACE).rect
		expect(panel.y > plus.y + plus.h).toBe(true)
		expect(panel.x + panel.w <= 390).toBe(true)
	end)

	it("an anchored surface joins the presenter's own stack rather than forking one", function()
		local _, _, _, _, pres = makeWorld()
		pres.present(plusScreen(), { initialFocus = "none" })
		expect(pres.depth()).toBe(1)
		local handle = pres.presentAnchored(calloutPanel(200), {
			id = "Tip",
			initialFocus = "none",
			anchor = { source = { path = "/Editor/Bar/Plus" } },
		})
		expect(pres.depth()).toBe(2)
		pres.dismiss(handle)
		expect(pres.depth()).toBe(1)
		expect(pres.anchoredSurfaces().count).toBe(0)
	end)

	it("a modal anchored surface traps focus through the presenter's own modal path", function()
		local _, _, _, _, pres = makeWorld()
		pres.present(plusScreen(), { initialFocus = "none" })
		local handle = pres.presentAnchored(
			UI.VStack({
				id = "Menu",
				surface = "raised",
				children = { UI.Button({ id = "One", label = "One" }), UI.Button({ id = "Two", label = "Two" }) },
			}),
			{ id = "Tip", modal = true, anchor = { source = { path = "/Editor/Bar/Plus" } } }
		)
		expect(handle.kind).toBe("modal")
		expect(pres.focus.focused:get()).toBe("/Tip/Layer/Surface/Menu/One")
	end)

	it("a moving source is followed on the existing refresh cadence", function()
		local _, env, adapter, _, pres = makeWorld()
		pres.present(plusScreen(), { initialFocus = "none" })
		pres.presentAnchored(calloutPanel(200), {
			id = "Tip",
			initialFocus = "none",
			anchor = { source = { path = "/Editor/Bar/Plus" }, edge = "bottom" },
		})
		local before = adapter.node(SURFACE).rect
		-- the source moves because the world under it moved: a narrower viewport
		-- pulls the top-right button left, and nothing else asked for anything
		env:set("viewportRect", { x = 0, y = 0, w = 320, h = 844 })
		pres.refresh()
		local after = adapter.node(SURFACE).rect
		expect(after.x < before.x).toBe(true)
		expect(after.x + after.w <= 320).toBe(true)
	end)

	it("a source that is not mounted leaves the surface where it is instead of erroring", function()
		local _, _, _, _, pres = makeWorld()
		pres.present(plusScreen(), { initialFocus = "none" })
		pres.presentAnchored(calloutPanel(200), {
			id = "Tip",
			initialFocus = "none",
			anchor = { source = { path = "/Editor/Bar/Nope" } },
		})
		pres.refresh()
		pres.tick(1 / 60)
		expect(pres.anchoredSurfaces().surfaces[1].placed).toBe(false)
	end)

	it("a raw source rect needs no mounted view at all", function()
		local _, _, adapter, _, pres = makeWorld()
		pres.present(plusScreen(), { initialFocus = "none" })
		pres.presentAnchored(calloutPanel(120), {
			id = "Tip",
			initialFocus = "none",
			anchor = { source = { rect = { x = 40, y = 400, w = 60, h = 60 } }, edge = "bottom", align = "start" },
		})
		expect(adapter.node(SURFACE).rect.y > 460).toBe(true)
	end)

	it("an unknown anchor key is an authoring error, not a silent no-op", function()
		local _, _, _, _, pres = makeWorld()
		pres.present(plusScreen(), { initialFocus = "none" })
		local ok, err = pcall(function()
			pres.presentAnchored(calloutPanel(120), {
				id = "Tip",
				anchor = { source = { path = "/Editor/Bar/Plus" }, arrowEdge = "top" },
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "arrowEdge", 1, true) ~= nil).toBe(true)
	end)

	it("an anchored surface refuses a root policy its window-space offsets cannot mean", function()
		local _, _, _, _, pres = makeWorld()
		pres.present(plusScreen(), { initialFocus = "none" })
		local ok, err = pcall(function()
			pres.presentAnchored(calloutPanel(120), {
				id = "Tip",
				rootPolicy = "coreSafeContent",
				anchor = { source = { path = "/Editor/Bar/Plus" } },
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "edgeToEdge", 1, true) ~= nil).toBe(true)
	end)

	it("the dump is deterministic and names the resolved edge", function()
		local _, _, _, _, pres = makeWorld()
		pres.present(plusScreen(), { initialFocus = "none" })
		pres.presentAnchored(calloutPanel(200), {
			id = "Tip",
			initialFocus = "none",
			anchor = { source = { path = "/Editor/Bar/Plus" }, edge = "bottom", tail = true },
		})
		local a = pres.anchoredSurfaces()
		local b = pres.anchoredSurfaces()
		expect(a.schema).toBe("facet-anchored-dump/1")
		expect(a.text).toBe(b.text)
		expect(a.surfaces[1].edge).toBe("bottom")
		expect(string.find(a.text, "Tip", 1, true) ~= nil).toBe(true)
	end)
end)

describe("D1 anchored surface: the arrow tail is a decoration, never a claim", function()
	it("the tail paints behind the panel it belongs to", function()
		local _, _, adapter, _, pres = makeWorld()
		pres.present(plusScreen(), { initialFocus = "none" })
		pres.presentAnchored(calloutPanel(200), {
			id = "Tip",
			initialFocus = "none",
			anchor = { source = { path = "/Editor/Bar/Plus" }, edge = "bottom", tail = true },
		})
		local tail = adapter.node(TAIL)
		expect(tail).never().toBe(nil)
		-- a rotated square, half of it covered by the panel drawn over it
		expect(tail.rotation).toBe(45)
		expect(adapter.visibleOf(TAIL)).toBe(true)
		expect(tail.z < adapter.node(SURFACE).z).toBe(true)
	end)

	--[[ THE WEDGE IS A TRIANGLE, NOT A BLOB (director, 2026-08-17). `surface =
		"raised"` carries the panel's phantom `::UICorner`, and `radii.panel` (12
		under Studio Neutral) against a `space.m` = 16px box CLAMPS to half the side
		— so the "arrow" was a circle and what protruded was a semicircular bump.
		Pinned as the authored value, because no rect assertion can see a radius. ]]
	it("the wedge carries a ZERO corner radius, so the panel's rounding cannot reach it", function()
		local _, _, adapter, _, pres = makeWorld()
		pres.present(plusScreen(), { initialFocus = "none" })
		pres.presentAnchored(calloutPanel(200), {
			id = "Tip",
			initialFocus = "none",
			anchor = { source = { path = "/Editor/Bar/Plus" }, edge = "bottom", tail = true },
		})
		local tail = adapter.node(TAIL)
		expect(tail).never().toBe(nil)
		expect(type(tail.props.corners)).toBe("table")
		expect(tail.props.corners.form).toBe("uniform")
		expect(tail.props.corners.radius).toBe(0)
	end)

	--[[ NO LINE ACROSS THE ARROW'S BASE (director, 2026-08-17, from a zoomed device
		capture: *"can we eliminate the line at the bottom of the triangle?"*). That
		line is the PANEL'S OWN hairline running through the join, and it is what
		keeps a correctly-shaped wedge reading as a separate shape. The band paints
		over it. Three claims, because getting any one wrong reopens the defect: it is
		ON TOP, it is the RIGHT WIDTH, and it STRADDLES the edge. ]]
	it("the seam band paints OVER the panel's border, spanning exactly the wedge's base", function()
		local _, _, adapter, _, pres = makeWorld()
		pres.present(plusScreen(), { initialFocus = "none" })
		pres.presentAnchored(calloutPanel(200), {
			id = "Tip",
			initialFocus = "none",
			anchor = { source = { path = "/Editor/Bar/Plus" }, edge = "bottom", tail = true },
		})
		local tail = adapter.node(TAIL)
		local seam = adapter.node(TAIL_SEAM)
		local surface = adapter.node(SURFACE)
		expect(seam).never().toBe(nil)
		expect(seam.z > surface.z).toBe(true)
		-- ...and the wedge is still BEHIND, which is what hides its inner two edges
		expect(tail.z < surface.z).toBe(true)
		-- THE RIGHT WIDTH: the rotated square's DIAGONAL, not its side
		expect(near(seam.rect.w, tail.rect.w * ROOT_TWO)).toBe(true)
		-- STRADDLING the border: `edge = "bottom"` puts the plate BELOW the source,
		-- so the shared border is the panel's TOP and the band is centred on it
		expect(near(seam.rect.y + seam.rect.h / 2, surface.rect.y)).toBe(true)
		expect(near(seam.rect.x + seam.rect.w / 2, tail.rect.x + tail.rect.w / 2)).toBe(true)
		-- a band, never a second plate
		expect(seam.rect.h < seam.rect.w).toBe(true)
	end)

	--[[ THE BAND CARRIES NO BORDER AND NO CORNER OF ITS OWN. `surface = "base"` is
		the one native surface with neither phantom modifier, which is exactly what a
		cover band needs — a rounded end or a hairline here would replace one visible
		line with two. ]]
	it("the seam band wears the panel's fill and neither a corner nor a border of its own", function()
		local _, _, adapter, _, pres = makeWorld()
		pres.present(plusScreen(), { initialFocus = "none" })
		pres.presentAnchored(calloutPanel(200), {
			id = "Tip",
			initialFocus = "none",
			anchor = { source = { path = "/Editor/Bar/Plus" }, edge = "bottom", tail = true },
		})
		local seam = adapter.node(TAIL_SEAM)
		expect(seam.props.surface).toBe("base")
		expect(seam.props.corners.radius).toBe(0)
		expect(seam.props.stroke).toBe(nil)
		expect(seam.tintSpec.role).toBe("surfaceStrong")
		expect(seam.tintSpec.blend).toBe(1)
		expect(seam.tintColor).never().toBe(nil)
	end)

	--[[ THE GUARD THAT MAKES THE TINT SAFE, and it exists because nothing else in
		this repo can see the failure. The band RECONSTRUCTS the panel's colour from a
		tint role; the panel gets its colour from the emitted `.facet-surface-raised`
		rule. Two authorities over one value. Measured live 2026-08-17: a plain
		property read on both the plate and the wedge reports rgb(163,162,165) while
		both PAINT rgb(28,31,40) — `GetStyled` is the only instrument that sees sheet
		paint — so a package that moved one authority and not the other would ship a
		mismatched bar across the plate with every headless assertion still green.
		Swept across every shipped package rather than pinned to the neutral one. ]]
	it(
		"SEAM AUTHORITY: the band's tint role and the panel's own rule name the same colour, in every package",
		function()
			local sheet_model = require("../src/tokens/sheet_model")
			local Facet = require("../src") :: any
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
			local function sameColour(a: any, b: any): boolean
				return a ~= nil and b ~= nil and near(a.r, b.r, 1e-9) and near(a.g, b.g, 1e-9) and near(a.b, b.b, 1e-9)
			end
			for _, name in PACKAGES do
				local pkg = (require)(`../examples/themes/{name}`).build(Facet.themes)
				for _, theme in pkg.style.themes do
					-- what the BAND paints: the tint role resolved through the palette
					local band = sheet_model.tintColor(theme, { role = "surfaceStrong", blend = 1 }, "Box")
					-- what the PANEL paints: the token `.facet-surface-raised` declares
					local panel = sheet_model.paletteColor(theme, "surfaceStrong")
					expect(`{name}/{tostring(theme.name)}: band matches panel? {sameColour(band, panel)}`).toBe(
						`{name}/{tostring(theme.name)}: band matches panel? true`
					)
				end
			end
		end
	)

	it("a suppressed tail takes its seam band with it", function()
		local _, _, adapter, _, pres = makeWorld()
		pres.present(plusScreen(), { initialFocus = "none" })
		pres.presentAnchored(calloutPanel(360), {
			id = "Tip",
			initialFocus = "none",
			anchor = { source = { path = "/Editor/Bar/Plus" }, edge = "bottom", align = "start", tail = true },
		})
		expect(adapter.visibleOf(TAIL)).toBe(adapter.visibleOf(TAIL_SEAM))
	end)

	it("no tail requested means no seam band either", function()
		local _, _, adapter, _, pres = makeWorld()
		pres.present(plusScreen(), { initialFocus = "none" })
		pres.presentAnchored(calloutPanel(200), {
			id = "Tip",
			initialFocus = "none",
			anchor = { source = { path = "/Editor/Bar/Plus" }, edge = "bottom" },
		})
		expect(adapter.node(TAIL)).toBe(nil)
		expect(adapter.node(TAIL_SEAM)).toBe(nil)
	end)

	it("a safe-area flip re-seats the seam band on the plate's other border", function()
		local _, _, adapter, _, pres = makeWorld()
		pres.present(
			UI.Screen({
				id = "Editor",
				children = {
					UI.Anchor({
						id = "Bar",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = {
							UI.Button({
								id = "Plus",
								label = "+",
								anchor = "bottomRight",
								width = { type = "fixed", px = 44 },
								height = { type = "fixed", px = 44 },
							}),
						},
					}),
				},
			}),
			{ initialFocus = "none" }
		)
		pres.presentAnchored(calloutPanel(200), {
			id = "Tip",
			initialFocus = "none",
			anchor = { source = { path = "/Editor/Bar/Plus" }, edge = "bottom", tail = true },
		})
		expect(pres.anchoredSurfaces().surfaces[1].edge).toBe("top")
		local seam = adapter.node(TAIL_SEAM)
		local surface = adapter.node(SURFACE)
		-- the plate is now ABOVE its source, so the shared border is its BOTTOM
		expect(near(seam.rect.y + seam.rect.h / 2, surface.rect.y + surface.rect.h)).toBe(true)
		expect(seam.rect.h < seam.rect.w).toBe(true)
	end)

	it("a side-edge plate turns the seam band through ninety degrees", function()
		local _, _, adapter, _, pres = makeWorld()
		pres.present(plusScreen(), { initialFocus = "none" })
		-- TALL ENOUGH TO HOST THE ARROW: a side tail spends the corner keep-out on
		-- HEIGHT, and the default 36px plate cannot clear two 12px radii plus the
		-- wedge, so it would be suppressed
		pres.presentAnchored(
			UI.VStack({
				id = "Callout",
				surface = "raised",
				padding = "s",
				width = { type = "fixed", px = 120 },
				height = { type = "fixed", px = 140 },
				children = { UI.Text({ id = "Body", text = PANEL_TEXT, textSize = 16 }) },
			}),
			{
				id = "Tip",
				initialFocus = "none",
				anchor = { source = { path = "/Editor/Bar/Plus" }, edge = "leading", tail = true },
			}
		)
		local seam = adapter.node(TAIL_SEAM)
		local surface = adapter.node(SURFACE)
		expect(adapter.visibleOf(TAIL)).toBe(true)
		expect(seam.rect.w < seam.rect.h).toBe(true)
		expect(near(seam.rect.h, adapter.node(TAIL).rect.h * ROOT_TWO)).toBe(true)
		-- the plate sits to the LEFT of its source: the shared border is its TRAILING
		expect(near(seam.rect.x + seam.rect.w / 2, surface.rect.x + surface.rect.w)).toBe(true)
	end)

	it("the tail is suppressed when the shift carries it off the source", function()
		local _, _, adapter, _, pres = makeWorld()
		-- a source in the middle of the screen with a panel far wider than the
		-- room beside it cannot be reached by a corner-respecting tail
		pres.present(
			UI.Screen({
				id = "Editor",
				children = {
					UI.Anchor({
						id = "Bar",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = {
							UI.Button({
								id = "Plus",
								label = "+",
								anchor = "topRight",
								width = { type = "fixed", px = 8 },
								height = { type = "fixed", px = 8 },
							}),
						},
					}),
				},
			}),
			{ initialFocus = "none" }
		)
		pres.presentAnchored(calloutPanel(360), {
			id = "Tip",
			initialFocus = "none",
			anchor = { source = { path = "/Editor/Bar/Plus" }, edge = "bottom", tail = true },
		})
		expect(adapter.visibleOf(TAIL)).toBe(false)
		expect(pres.anchoredSurfaces().surfaces[1].tailSuppressed).toBe(true)
	end)

	--[[ A ROTATED NODE MUST NOT WEAR AN ORIENTATION-DEPENDENT SKIN (device review
		2026-08-16, F5). Director, on the callout demo under Fantasy Ornate: the
		tail came out as *"a long diagonal slab with the package's gold border
		running down both of its long edges"* — unmistakably a rotated FRAME rather
		than a wedge.

		THE MECHANISM, AND WHY THE FLAT DEFAULT HID IT COMPLETELY. The tail is a
		`Box` turned 45°, and it declared `surface = "raised"` so that "it wears the
		panel's own role and a theme swap moves both". That reasoning holds exactly
		as long as a surface is a FILL. `chrome_slots.classify` maps `raised` to the
		`panel` slot, and under an image-driven package `panel` is not a fill: in
		`examples/themes/fantasy_ornate.luau` it is a six-layer recipe — a tiled
		velvet, a fill, a NINE-SLICE FRAME, tiled edge rails and four corner
		ornaments. Rotate a nine-slice frame 45° and its border rotates with it. With
		no package installed no decoration instance is ever materialized, so the
		defect is invisible in the default the whole suite runs in.

		THIS IS `popup_catcher_paint.spec`'s DEFECT, TURNED FORTY-FIVE DEGREES —
		a synthesized node that never said what it was, dressed by a package that
		had no way to know better. Same oracle, deliberately: `chrome_slots.classify`
		is the call `screen_chrome.luau` makes on the live adapter, and a nil answer
		is "no package will ever draw a frame here". `surface` stays `raised` so the
		NATIVE sheet fill — `.facet-surface-raised`, which every package restyles
		with its own `surfaceStrong` — still paints the wedge in the panel's own
		colour. The panel's fill, never the panel's frame. ]]
	it("the tail is a WEDGE under every package: no chrome slot on a rotated node", function()
		local _, _, adapter, _, pres = makeWorld()
		pres.present(plusScreen(), { initialFocus = "none" })
		pres.presentAnchored(calloutPanel(200), {
			id = "Tip",
			initialFocus = "none",
			anchor = { source = { path = "/Editor/Bar/Plus" }, edge = "bottom", tail = true },
		})
		--[[ THE TWO INPUTS THE LIVE ADAPTER CLASSIFIES FROM, and they are read off
			the node the ADAPTER was handed rather than off the blueprint: the
			declared `surface`, and the decoration hint the renderer passed to
			`create`. `chrome_slots.readHint` is the blueprint-side reader and answers
			nil for an adapter node — using it here would have made this case pass on
			a hint that never left the tree (`popup_catcher_paint.spec`'s own oracle
			gets away with it only because its fix is `surface = "plain"`). ]]
		local function slotOf(path: string): string?
			local node = adapter.node(path)
			local hint = node.decorationHint
			return chrome_slots.classify({
				class = node.class,
				surface = node.props.surface,
				hint = if type(hint) == "table" then hint.slot else nil,
			})
		end
		local tail = adapter.node(TAIL)
		expect(tail.rotation).toBe(45) -- it really is the rotated node
		expect(`the tail classifies into slot {tostring(slotOf(TAIL))}`).toBe("the tail classifies into slot nil")
		--[[ ...and the PANEL still does, which is the half that must not move: the
			plate is unrotated, so an ornate frame around it is the package working
			exactly as intended. A fix that quietly stripped both would have made this
			case green and the screen worse. ]]
		expect(`the panel classifies into slot {tostring(slotOf(`{SURFACE}/Callout`))}`).toBe(
			"the panel classifies into slot panel"
		)
		-- the wedge is still PAINTED, in the panel's own surface role — suppressing
		-- the slot must not turn the arrow into nothing
		expect(adapter.node(TAIL).props.surface).toBe("raised")
		expect(adapter.visibleOf(TAIL)).toBe(true)
	end)

	--[[ THE TAIL COSTS THE PLATE NO LAYOUT, which is the OTHER thing the same
		device report raised: a *"large empty dark band across the top of the
		plate"*, guessed to be the tail's own box pushing the body down. It is not,
		and this is the case that says so rather than a paragraph claiming it.

		The tail is a sibling of `Surface` inside an `Anchor`, placed by absolute
		offsets, so it can move the plate's POSITION and never its interior: asking
		for a tail lifts the whole surface by the wedge's protrusion (half its
		diagonal, so the ARROW TIP rather than the panel edge lands `gap` short of
		the source) and leaves every distance inside the plate identical. Anything
		still banding the top of an ornate plate is that package's own
		`contentInsets` — a separate finding, on the recipe rather than on D1. ]]
	--[[ THE RULE, ENCODED WHERE THE NEXT ONE WILL TRIP OVER IT. The case above
		proves today's tail; this proves the CLASS, because "a rotated node must not
		wear an orientation-dependent skin" is worth exactly as much as the next
		rotated node's compliance with it.

		WHY A SOURCE SWEEP RATHER THAN A THEMED MOUNT SWEEP. `chrome_slots.classify`
		is a pure function of (class, surface, hint) — it never reads the installed
		package — so the mounted assertion above already answers for all eight
		shipped packages at once, and re-running it per package would sweep an axis
		the answer does not depend on. What the packages actually change is whether
		a recipe gets MATERIALIZED for a slot, and `fake_target.setThemePackage`
		declines the decoration surface (it returns false), so no headless target can
		witness that instance. The fact that IS checkable headlessly is the
		declaration, and the declaration is what decides the instance.

		One node in `src/` declares a rotation today. The sweep names the count so
		that adding a second is a decision someone has to make on purpose. ]]
	it("EVERY rotated node in src declares NO_SLOT — the rule, not just this tail", function()
		local fs = require("@lune/fs")
		local files = { "src/present/anchored.luau" }
		-- the sweep's own premise, checked: if a rotated node appears anywhere else
		-- in the blueprint-authoring half of `src/`, this list is stale and the case
		-- says so rather than passing over it
		local function scan(dir: string, out: { string })
			for _, entry in fs.readDir(dir) do
				local path = `{dir}/{entry}`
				if fs.isDir(path) then
					scan(path, out)
				elseif string.sub(entry, -5) == ".luau" then
					table.insert(out, path)
				end
			end
		end
		local all: { string } = {}
		scan("src", all)
		local rotating: { string } = {}
		for _, path in all do
			-- the RENDER/CLIENT halves consume the prop rather than declaring it, and
			-- the schema/styling modules define it; a blueprint AUTHOR writes the
			-- literal assignment with a number
			if
				string.find(path, "^src/render/") ~= nil
				or string.find(path, "^src/client/") ~= nil
				or string.find(path, "^src/tokens/") ~= nil
				or path == "src/blueprint_schema.luau"
				or path == "src/input/touch_gestures.luau"
			then
				continue
			end
			if string.find(fs.readFile(path), "rotation = %d") ~= nil then
				table.insert(rotating, path)
			end
		end
		table.sort(rotating)
		expect(`rotated authors: {table.concat(rotating, ",")}`).toBe(`rotated authors: {table.concat(files, ",")}`)
		for _, path in rotating do
			local text = fs.readFile(path)
			expect(`{path} declares NO_SLOT? {string.find(text, "chrome_slots.NO_SLOT", 1, true) ~= nil}`).toBe(
				`{path} declares NO_SLOT? true`
			)
		end
	end)

	it("asking for a tail moves the plate, and changes NOTHING inside it", function()
		local function measure(tail: boolean): (any, any)
			local _, _, adapter, _, pres = makeWorld()
			pres.present(plusScreen(), { initialFocus = "none" })
			pres.presentAnchored(calloutPanel(200), {
				id = "Tip",
				initialFocus = "none",
				anchor = { source = { path = "/Editor/Bar/Plus" }, edge = "bottom", tail = tail },
			})
			return adapter.node(`{SURFACE}/Callout`).rect, adapter.node(`{SURFACE}/Callout/Body`).rect
		end
		local withPanel, withBody = measure(true)
		local withoutPanel, withoutBody = measure(false)
		-- the plate is the SAME SIZE and its body sits at the same inset
		expect(`{withPanel.w}x{withPanel.h}`).toBe(`{withoutPanel.w}x{withoutPanel.h}`)
		-- rounded to the tenth: the offsets differ by a float epsilon the eye and
		-- the engine both quantize away, and pinning raw doubles would make this a
		-- test of IEEE arithmetic rather than of layout
		local function inset(body: any, plate: any): string
			return string.format("%.1f", body.y - plate.y)
		end
		expect(`body inset {inset(withBody, withPanel)}`).toBe(`body inset {inset(withoutBody, withoutPanel)}`)
		-- ...and the whole surface simply stood off further, by the wedge's own
		-- protrusion rather than by some band inside it
		local stood = withPanel.y - withoutPanel.y
		expect(`the plate stood off by {stood > 0 and stood < withPanel.h}`).toBe("the plate stood off by true")
	end)
end)

describe("D1 anchored surface: the tap-away catcher is the presenter's own", function()
	it("an anchored panel that declares outsideDismiss gets the presenter's catcher, non-consuming", function()
		--[[ The "reuses, does not fork" claim, driven rather than asserted from
			source. The panel attaches an ORDINARY input contribution — the same
			`outsideDismiss` seam PopupButton and row_actions use — and the presenter
			discovers it by walking this surface's own mounted tree, exactly as it
			does for a control on any other surface. `consume = false` is the
			non-blocking mode D3b's Callout needs: the tap dismisses and is not
			swallowed, so the control underneath stays operable. ]]
		local core, _, adapter, _, pres = makeWorld()
		pres.present(plusScreen(), { initialFocus = "none" })
		local open = core:signal(true)
		local dismissals = 0
		local handle: any = nil
		local panel = contribution.attach(calloutPanel(200), {
			outsideDismiss = {
				active = open,
				dismiss = function()
					dismissals += 1
					open:set(false)
					pres.dismiss(handle)
				end,
				consume = false,
			},
		})
		handle = pres.presentAnchored(panel, {
			id = "Tip",
			initialFocus = "none",
			anchor = { source = { path = "/Editor/Bar/Plus" }, edge = "bottom" },
		})
		pres.refresh()
		local catcher = pres.topPopupCatcherPath()
		expect(catcher).never().toBeNil()
		-- Zone B: empty space far from the plate
		adapter.tap(catcher :: string, { x = 8, y = 780 })
		pres.refresh()
		expect(dismissals).toBe(1)
		expect(pres.depth()).toBe(1)
		expect(pres.anchoredSurfaces().count).toBe(0)
	end)
end)

describe("D1 fixture f1: the avatar-editor callout", function()
	it("f1: anchored under a top-right button, arrow up at it, body shifted left", function()
		--[[ docs/plans/reference-media/2026-08-16-roblox-app-navigation/
			f1-avatar-editor.jpeg — the "Post Avatars to Marketplace" plate. Three
			facts to reproduce, and all three are placement decisions:
			  * it hangs BELOW a `+` button in the top-right corner;
			  * its arrow points UP, at that button, not at the plate's own centre;
			  * its body is SHIFTED LEFT, because a centred plate that wide would
			    run off the right edge of the phone. ]]
		local _, _, adapter, _, pres = makeWorld(390, 844)
		pres.present(plusScreen(), { initialFocus = "none" })
		pres.presentAnchored(calloutPanel(260), {
			id = "Tip",
			initialFocus = "none",
			anchor = { source = { path = "/Editor/Bar/Plus" }, edge = "bottom", align = "center", tail = true },
		})
		local plus = adapter.node("/Editor/Bar/Plus").rect
		local panel = adapter.node(SURFACE).rect
		local dump = pres.anchoredSurfaces().surfaces[1]

		-- BELOW the source, on screen, and never under the right edge
		expect(dump.edge).toBe("bottom")
		expect(dump.flipped).toBe(false)
		expect(panel.y > plus.y + plus.h).toBe(true)
		expect(panel.x + panel.w <= 390).toBe(true)

		-- SHIFTED LEFT: a centred 260px plate under a button whose centre sits at
		-- x=368 would start at 238 and end at 498, 108px off the screen
		expect(dump.shift < 0).toBe(true)

		-- ...and the arrow still points UP at the button it came from
		expect(dump.tailSuppressed).toBe(false)
		expect(dump.tailX >= plus.x and dump.tailX <= plus.x + plus.w).toBe(true)
		expect(adapter.visibleOf(TAIL)).toBe(true)
	end)
end)

-- ===== layer 3: the two precedents, unified =============================

describe("D1: the hand-rolled precedents now share one solver", function()
	it("the disclosure plate places through the shared solver and never flips into a worse place", function()
		--[[ presenter.luau's `clampDisclosure` was the first hand-rolled copy of
			this decision: prefer below, flip above when below does not fit, clamp
			into the safe box. It flipped UNCONDITIONALLY, so a plate too tall for
			the space above went above anyway — the "worse place" row_actions'
			ruling 4 exists to forbid. It now asks the shared solver. ]]
		local _, env, adapter, _, pres = makeWorld(390, 844)
		env:set("coreSafeInsets", { top = 40, bottom = 34, left = 0, right = 0 })
		pres.present(UI.Screen({
			id = "Roster",
			children = {
				UI.Spacer({ id = "Push", height = { type = "fill", weight = 1 } }),
				UI.Button({
					id = "RowA",
					label = "",
					width = { type = "fixed", px = 120 },
					height = { type = "fixed", px = 44 },
					children = {
						UI.Text({
							id = "Name",
							text = "Bartholomewwwwwwwwwwwwwwwwww",
							textSize = 16,
							disclose = true,
						}),
					},
				}),
			},
		}))
		expect(pres.disclosure().present).toBe(true)
		local r = adapter.node("/__disclose__/Layer/Plate").rect
		expect(r.x >= 0).toBe(true)
		expect(r.x + r.w <= 390).toBe(true)
		expect(r.y >= 40).toBe(true)
		expect(r.y + r.h <= 844 - 34).toBe(true)
	end)

	it("row actions' menu flip is the shared solver's rule, not a second copy", function()
		--[[ `row_actions.computeMenuAnchor` encoded the same two conditions by
			hand. Its behaviour is unchanged — it still cannot shift horizontally,
			because it never learns the menu's width — but the flip decision is now
			the one function. Asserted as the solver would answer it, with the
			control's own inputs. ]]
		local below = solve({
			source = { x = 20, y = 508, w = 760, h = 48 },
			size = { w = 0, h = 73 },
			safe = { x = 0, y = 0, w = 800, h = 600 },
			edge = "bottom",
			align = "start",
			gap = 0,
			overflow = "keep",
		})
		expect(below.edge).toBe("top") -- 556 + 73 = 629 > 600, and 508 - 73 >= 0
		expect(below.flipped).toBe(true)

		local stays = solve({
			source = { x = 20, y = 40, w = 760, h = 48 },
			size = { w = 0, h = 73 },
			safe = { x = 0, y = 0, w = 800, h = 600 },
			edge = "bottom",
			align = "start",
			gap = 0,
			overflow = "keep",
		})
		expect(stays.edge).toBe("bottom")
		expect(stays.flipped).toBe(false)
	end)
end)
