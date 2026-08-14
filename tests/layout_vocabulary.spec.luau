--!strict
-- Milestone A — the everyday layout vocabulary (docs/plans/swiftui-parity-next.md
-- investment 6; acceptance rows A-LV1..A-LV4).
--
-- A-LV1 was found LIVE before it was found headlessly: an authoring fixture in
-- Studio rendered a three-cell Grid whose cells were positioned at the right
-- column origins (x = 16 / 118 / 220) and were 0 px wide, so the grid was
-- invisible. Fill children did not occupy their column, and a cell's alignment
-- props were accepted and ignored.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local solver = require("../src/layout/solver")

local function fill(weight: number?)
	return { type = "fill", weight = weight or 1 }
end

local function fixed(px: number)
	return { type = "fixed", px = px }
end

local function solve(root: any, w: number, h: number)
	return solver.solve(root, { w = w, h = h }, { rootPolicy = "edgeToEdge" })
end

describe("A-LV1: Grid children with fill dimensions", function()
	it("a fill-width cell occupies its whole column instead of collapsing to content", function()
		local result = solve({
			kind = "grid",
			id = "G",
			columns = 3,
			gap = 10,
			children = {
				{ kind = "box", id = "a", width = fill(), height = fixed(40) },
				{ kind = "box", id = "b", width = fill(), height = fixed(40) },
				{ kind = "box", id = "c", width = fill(), height = fixed(40) },
			},
		}, 320, 200)
		-- inner 320, gap 10 x2 => 300 across 3 columns => 100 each
		expect(result.rects.a.rect.w).toBe(100)
		expect(result.rects.b.rect.w).toBe(100)
		expect(result.rects.c.rect.w).toBe(100)
		expect(result.rects.a.rect.x).toBe(0)
		expect(result.rects.b.rect.x).toBe(110)
		expect(result.rects.c.rect.x).toBe(220)
	end)

	it("a fill-height cell occupies the row height set by its tallest sibling", function()
		local result = solve({
			kind = "grid",
			id = "G",
			columns = 2,
			children = {
				{ kind = "box", id = "tall", width = fill(), height = fixed(60) },
				{ kind = "box", id = "stretchy", width = fill(), height = fill() },
			},
		}, 200, 200)
		expect(result.rects.tall.rect.h).toBe(60)
		expect(result.rects.stretchy.rect.h).toBe(60)
	end)

	it("a minColumnWidth grid derives its column count and still fills", function()
		local result = solve({
			kind = "grid",
			id = "G",
			minColumnWidth = 90,
			gap = 6,
			children = {
				{ kind = "box", id = "a", width = fill(), height = fixed(40) },
				{ kind = "box", id = "b", width = fill(), height = fixed(40) },
				{ kind = "box", id = "c", width = fill(), height = fixed(40) },
			},
		}, 300, 200)
		-- (300 + 6) / (90 + 6) = 3.18 -> 3 columns; (300 - 12) / 3 = 96
		expect(result.rects.a.rect.w).toBe(96)
		expect(result.rects.c.rect.x).toBe(204)
	end)

	it("a non-fill cell keeps content sizing and aligns inside its column", function()
		local result = solve({
			kind = "grid",
			id = "G",
			columns = 2,
			children = {
				{ kind = "box", id = "left", width = fixed(40), height = fixed(20), alignH = "start" },
				{ kind = "box", id = "mid", width = fixed(40), height = fixed(20), alignH = "center" },
			},
		}, 200, 200)
		expect(result.rects.left.rect.w).toBe(40)
		expect(result.rects.left.rect.x).toBe(0)
		-- column 2 starts at 100 and is 100 wide; a 40px cell centres at 100+30
		expect(result.rects.mid.rect.x).toBe(130)
	end)

	it("a cell aligns vertically inside a taller row", function()
		local result = solve({
			kind = "grid",
			id = "G",
			columns = 2,
			children = {
				{ kind = "box", id = "tall", width = fill(), height = fixed(80) },
				{ kind = "box", id = "short", width = fill(), height = fixed(20), alignV = "center" },
			},
		}, 200, 200)
		expect(result.rects.short.rect.h).toBe(20)
		expect(result.rects.short.rect.y).toBe(30)
	end)

	it("the grid never produces a negative cell width when gaps exceed the container", function()
		local result = solve({
			kind = "grid",
			id = "G",
			columns = 4,
			gap = 100,
			children = {
				{ kind = "box", id = "a", width = fill(), height = fixed(10) },
				{ kind = "box", id = "b", width = fill(), height = fixed(10) },
			},
		}, 120, 200)
		expect(result.rects.a.rect.w >= 0).toBe(true)
		expect(result.rects.b.rect.w >= 0).toBe(true)
	end)
end)

describe("A-LV1: Spacer expands along the stack's main axis by default", function()
	it("a bare Spacer pushes its siblings apart in a VStack", function()
		local result = solve({
			kind = "vstack",
			id = "V",
			-- the root honors its own dims (solver.solve): a content-sized root
			-- would shrink to its children and leave a Spacer nothing to take
			width = fill(),
			height = fill(),
			children = {
				{ kind = "box", id = "top", height = fixed(20), width = fill() },
				{ kind = "spacer", id = "gapper" },
				{ kind = "box", id = "bottom", height = fixed(20), width = fill() },
			},
		}, 200, 300)
		expect(result.rects.gapper.rect.h).toBe(260)
		expect(result.rects.bottom.rect.y).toBe(280)
	end)

	it("a bare Spacer expands horizontally inside an HStack", function()
		local result = solve({
			kind = "hstack",
			id = "H",
			width = fill(),
			height = fill(),
			children = {
				{ kind = "box", id = "left", width = fixed(30), height = fill() },
				{ kind = "spacer", id = "gapper" },
				{ kind = "box", id = "right", width = fixed(30), height = fill() },
			},
		}, 300, 50)
		expect(result.rects.gapper.rect.w).toBe(240)
		expect(result.rects.right.rect.x).toBe(270)
	end)

	it("two bare Spacers share the leftover space equally (centring idiom)", function()
		local result = solve({
			kind = "hstack",
			id = "H",
			width = fill(),
			height = fill(),
			children = {
				{ kind = "spacer", id = "s1" },
				{ kind = "box", id = "mid", width = fixed(40), height = fill() },
				{ kind = "spacer", id = "s2" },
			},
		}, 240, 50)
		expect(result.rects.s1.rect.w).toBe(100)
		expect(result.rects.s2.rect.w).toBe(100)
		expect(result.rects.mid.rect.x).toBe(100)
	end)

	it("an explicit dimension on a Spacer still wins", function()
		local result = solve({
			kind = "vstack",
			id = "V",
			width = fill(),
			height = fill(),
			children = {
				{ kind = "spacer", id = "fixedGap", height = fixed(12) },
				{ kind = "box", id = "b", height = fixed(20), width = fill() },
			},
		}, 200, 300)
		expect(result.rects.fixedGap.rect.h).toBe(12)
		expect(result.rects.b.rect.y).toBe(12)
	end)

	it("a Spacer outside a stack axis stays inert (no unbounded growth)", function()
		local result = solve({
			kind = "zstack",
			id = "Z",
			children = { { kind = "spacer", id = "s" } },
		}, 200, 200)
		expect(result.rects.s.rect.w).toBe(0)
		expect(result.rects.s.rect.h).toBe(0)
	end)
end)

-- ===== A-LV2: composable layout modifiers ==================================
-- Each modifier returns a NEW blueprint (blueprints are frozen) and writes only
-- properties the schema already declares, so the authority manifest still owns
-- every engine write and a modifier can never silently claim a value another
-- subsystem owns. Order is explicit: the LAST writer of a property wins.

local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local rendererLib = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("../tests/lib/fake_target")

local function render(bp: any, w: number, h: number)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return adapter, controller, root
end

describe("A-LV2: frame", function()
	it("sets fixed dimensions", function()
		local bp = UI.Screen({ id = "S", children = { UI.frame(UI.Box({ id = "B" }), { width = 120, height = 40 }) } })
		local adapter = render(bp, 300, 300)
		expect(adapter.node("/S/B").rect.w).toBe(120)
		expect(adapter.node("/S/B").rect.h).toBe(40)
	end)

	it("expresses a min/max band", function()
		local bp = UI.Screen({
			id = "S",
			children = { UI.frame(UI.Text({ id = "T", text = "hello" }), { minWidth = 200, maxWidth = 260 }) },
		})
		local adapter = render(bp, 300, 300)
		expect(adapter.node("/S/T").rect.w >= 200).toBe(true)
		expect(adapter.node("/S/T").rect.w <= 260).toBe(true)
	end)

	it('`maxWidth = "infinity"` fills the available space, like SwiftUI', function()
		local bp = UI.Screen({
			id = "S",
			children = { UI.frame(UI.Box({ id = "B" }), { maxWidth = "infinity", height = 20 }) },
		})
		local adapter = render(bp, 300, 300)
		expect(adapter.node("/S/B").rect.w).toBe(300)
	end)

	it("rejects an unknown frame field instead of ignoring it", function()
		local ok = pcall(function()
			return UI.frame(UI.Box({ id = "B" }), { with = 10 })
		end)
		expect(ok).toBe(false)
	end)
end)

describe("A-LV2: padding, offset, aspectRatio, alignment", function()
	it("padding insets a container's children", function()
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.padding(
					UI.VStack({
						id = "V",
						children = {
							UI.Box({
								id = "B",
								width = { type = "fill", weight = 1 },
								height = { type = "fixed", px = 10 },
							}),
						},
					}),
					16
				),
			},
		})
		local adapter = render(bp, 300, 300)
		expect(adapter.node("/S/V/B").rect.x).toBe(16)
	end)

	it("padding works on a label without wrapping it", function()
		local bp = UI.Screen({ id = "S", children = { UI.padding(UI.Text({ id = "T", text = "hi" }), 10) } })
		local adapter = render(bp, 300, 300)
		local bare = render(UI.Screen({ id = "S", children = { UI.Text({ id = "T", text = "hi" }) } }), 300, 300)
		expect(adapter.node("/S/T").rect.w).toBe(bare.node("/S/T").rect.w + 20)
	end)

	it("padding accepts per-side values", function()
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.padding(
					UI.VStack({
						id = "V",
						children = {
							UI.Box({
								id = "B",
								width = { type = "fill", weight = 1 },
								height = { type = "fixed", px = 10 },
							}),
						},
					}),
					{ left = 24 }
				),
			},
		})
		local adapter = render(bp, 300, 300)
		expect(adapter.node("/S/V/B").rect.x).toBe(24)
	end)

	it("padding on a class that cannot inset says so", function()
		local ok, err = pcall(function()
			return UI.padding(UI.Image({ id = "I", image = "rbxassetid://1" }), 8)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "wrap it", 1, true) ~= nil).toBe(true)
	end)

	it("offset moves a node inside an Anchor without affecting siblings", function()
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.Anchor({
					id = "A",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.offset(
							UI.Box({
								id = "B",
								anchor = "topLeft",
								width = { type = "fixed", px = 10 },
								height = { type = "fixed", px = 10 },
							}),
							30,
							40
						),
					},
				}),
			},
		})
		local adapter = render(bp, 300, 300)
		expect(adapter.node("/S/A/B").rect.x).toBe(30)
		expect(adapter.node("/S/A/B").rect.y).toBe(40)
	end)

	it("aspectRatio derives the height from the width", function()
		local bp = UI.Screen({
			id = "S",
			children = { UI.aspectRatio(UI.frame(UI.Box({ id = "B" }), { width = 160 }), 16 / 9) },
		})
		local adapter = render(bp, 300, 300)
		local r = adapter.node("/S/B").rect
		expect(r.w).toBe(160)
		expect(r.h).toBe(90)
	end)

	it("aspectRatio rejects a non-positive ratio", function()
		expect(pcall(function()
			return UI.aspectRatio(UI.Box({ id = "B" }), 0)
		end)).toBe(false)
	end)

	it("alignment sets the ZStack placement props", function()
		local aligned = UI.alignment(UI.Box({ id = "B" }), "center", "end")
		expect(aligned.props.alignH).toBe("center")
		expect(aligned.props.alignV).toBe("end")
	end)

	it("an unknown alignment value fails at construction", function()
		-- modifiers write through the SAME validation as a constructor, so they are
		-- not a hole through strict authoring
		local ok, err = pcall(function()
			return UI.alignment(UI.Box({ id = "B" }), "middle")
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "one of start | center | end", 1, true) ~= nil).toBe(true)
	end)

	it("a modifier writing a property the class does not have is rejected", function()
		local ok, err = pcall(function()
			return UI.padding(UI.Path({ id = "P", points = {} }), 4)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "wrap it", 1, true) ~= nil).toBe(true)
	end)
end)

describe("A-LV2: overlay and background", function()
	it("overlay layers content ABOVE the node in a ZStack", function()
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.overlay(
					UI.Box({ id = "Base", width = { type = "fixed", px = 100 }, height = { type = "fixed", px = 100 } }),
					UI.Box({ id = "Badge", width = { type = "fixed", px = 20 }, height = { type = "fixed", px = 20 } })
				),
			},
		})
		local adapter = render(bp, 300, 300)
		-- both render, wrapped in a generated ZStack keyed off the base's id
		expect(adapter.node("/S/Base+overlay/Base") ~= nil).toBe(true)
		expect(adapter.node("/S/Base+overlay/Badge") ~= nil).toBe(true)
	end)

	it("background layers content BEHIND the node", function()
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.background(UI.Text({ id = "Label", text = "hi" }), UI.Box({ id = "Plate", surface = "raised" })),
			},
		})
		local adapter = render(bp, 300, 300)
		local ops = adapter.takeOps()
		expect(adapter.node("/S/Label+background/Plate") ~= nil).toBe(true)
		expect(adapter.node("/S/Label+background/Label") ~= nil).toBe(true)
		-- the plate is created BEFORE the label, so it paints behind it
		local plateAt, labelAt = nil, nil
		for i, op in ops do
			if plateAt == nil and string.find(op, "Plate", 1, true) then
				plateAt = i
			end
			if labelAt == nil and string.find(op, "/Label+background/Label", 1, true) then
				labelAt = i
			end
		end
		expect(plateAt ~= nil and labelAt ~= nil and plateAt < labelAt).toBe(true)
	end)

	it("the background layer FILLS what it is backing", function()
		-- RS-A16-D2's second half, found by the headless matrix audit. A background
		-- is the SwiftUI modifier: it backs the thing it is behind. A ZStack child
		-- keeps its content size unless it declares `fill`, so a plate with no dims
		-- of its own solved to 0x0 — invisible, and worse than invisible once a
		-- package skins it: the adapter anchors a `corners` ornament to each corner
		-- of the host, so on a ZERO-size host the bottom pair hangs a whole
		-- ornament ABOVE the row (measured live under fantasy-ornate: 21 stat tiles,
		-- 84 px2 each, into the panel border of the row above).
		local bp = UI.Screen({
			id = "S",
			padding = 0,
			children = {
				UI.background(
					UI.padding(UI.Text({ id = "Label", text = "hi", textSize = 12 }), 6),
					UI.Box({ id = "Plate", surface = "control" })
				),
			},
		})
		local adapter = render(bp, 300, 300)
		local wrapper = adapter.node("/S/Label+background").rect
		local plate = adapter.node("/S/Label+background/Plate").rect
		expect(plate.w).toBe(wrapper.w)
		expect(plate.h).toBe(wrapper.h)
		expect(plate.x).toBe(wrapper.x)
		expect(plate.y).toBe(wrapper.y)
		expect(plate.w > 0 and plate.h > 0).toBe(true)
		-- ...and a content layer that declares its OWN dimensions still keeps them,
		-- so an intentionally smaller backing plate is unchanged
		local sized = UI.Screen({
			id = "T",
			padding = 0,
			children = {
				UI.background(
					UI.padding(UI.Text({ id = "L2", text = "hi", textSize = 12 }), 6),
					UI.Box({ id = "Chip", surface = "control", width = { type = "fixed", px = 8 } })
				),
			},
		})
		expect(render(sized, 300, 300).node("/T/L2+background/Chip").rect.w).toBe(8)
	end)

	it("an OVERLAY is still an ornament: it keeps its own size", function()
		-- the other half of the same decision. An overlay is a badge, a caret, a
		-- corner ribbon — it is aligned ON the base, not stretched over it.
		local bp = UI.Screen({
			id = "S",
			padding = 0,
			children = {
				UI.overlay(
					UI.Box({ id = "Tile", width = { type = "fixed", px = 80 }, height = { type = "fixed", px = 40 } }),
					UI.Text({ id = "Badge", text = "3", textSize = 12 })
				),
			},
		})
		local adapter = render(bp, 300, 300)
		expect(adapter.node("/S/Tile+overlay/Tile").rect.w).toBe(80)
		expect(adapter.node("/S/Tile+overlay/Badge").rect.w < 80).toBe(true)
	end)

	it("the base node keeps its own id inside the wrapper, so it stays addressable", function()
		local wrapped = UI.overlay(UI.Box({ id = "Base" }), UI.Box({ id = "Badge" }))
		expect(wrapped.class).toBe("ZStack")
		expect(wrapped.id).toBe("Base+overlay")
		expect((wrapped.children :: any)[1].id).toBe("Base")
	end)

	it("both modifiers require the base to carry an id", function()
		expect(pcall(function()
			return UI.overlay(UI.Box({}), UI.Box({ id = "x" }))
		end)).toBe(false)
	end)
end)

describe("A-LV2: modifier order is explicit", function()
	it("the LAST writer of a property wins", function()
		local bp = UI.Screen({
			id = "S",
			children = { UI.frame(UI.frame(UI.Box({ id = "B" }), { width = 50 }), { width = 90 }) },
		})
		local adapter = render(bp, 300, 300)
		expect(adapter.node("/S/B").rect.w).toBe(90)
	end)

	it("a modifier never mutates the blueprint it was given", function()
		local base = UI.Box({ id = "B" })
		local framed = UI.frame(base, { width = 40 })
		expect(base.props.width).toBe(nil)
		expect((framed.props.width :: any).px).toBe(40)
	end)
end)

-- ===== A-LV4: shapes the dense-HUD fixture exposed =========================
-- Both of these were found LIVE, in a fixture built from the shipped modifiers.
-- They are the same class of bug the stage exists to remove: a declaration that
-- was accepted and then produced nothing usable.

describe("A-LV4: aspectRatio against a fill sibling", function()
	it("derives the height from the RESOLVED fill width, not from zero", function()
		-- `fill` has no measure-time size, so measure could only compute 0 / ratio.
		-- Live result before the fix: a 16:9 media box 592px wide and 0px TALL.
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.aspectRatio(UI.Box({ id = "Media", surface = "raised", width = fill() }), 16 / 9),
			},
		})
		local adapter = render(bp, 640, 480)
		local r = adapter.node("/S/Media").rect
		expect(r.w).toBe(640)
		expect(r.h).toBe(360) -- 640 / (16/9)
	end)

	it("works in an HStack's cross axis too", function()
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.HStack({
					id = "Row",
					width = fill(),
					height = fill(),
					children = {
						UI.aspectRatio(UI.Box({ id = "Media", width = fill() }), 2),
					},
				}),
			},
		})
		local adapter = render(bp, 400, 400)
		expect(adapter.node("/S/Row/Media").rect.h > 0).toBe(true)
	end)

	it("a grid cell derives its aspect from the derived column width", function()
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.Grid({
					id = "G",
					columns = 2,
					gap = 0,
					width = fill(),
					children = {
						UI.aspectRatio(UI.Box({ id = "a", width = fill() }), 1),
						UI.aspectRatio(UI.Box({ id = "b", width = fill() }), 1),
					},
				}),
			},
		})
		local adapter = render(bp, 400, 600)
		local a = adapter.node("/S/G/a").rect
		expect(a.w).toBe(200)
		expect(a.h).toBe(200) -- square cells from a 1:1 ratio
	end)

	it("an explicit height still wins over the aspect derivation", function()
		local bp = UI.Screen({
			id = "S",
			children = { UI.frame(UI.aspectRatio(UI.Box({ id = "B", width = fill() }), 2), { height = 77 }) },
		})
		local adapter = render(bp, 400, 400)
		expect(adapter.node("/S/B").rect.h).toBe(77)
	end)
end)

describe("A-LV4: overlay does not collapse its base", function()
	it("the wrapper inherits the base's dimensions", function()
		-- live result before the fix: a badged grid tile rendered 12px wide — the
		-- width of its BADGE — instead of filling its column
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.Grid({
					id = "G",
					columns = 2,
					gap = 0,
					width = fill(),
					children = {
						UI.overlay(
							UI.Box({ id = "tile", surface = "control", width = fill(), height = fixed(44) }),
							UI.Text({ id = "badge", text = "3", textSize = 12 })
						),
						UI.Box({ id = "plain", width = fill(), height = fixed(44) }),
					},
				}),
			},
		})
		local adapter = render(bp, 400, 200)
		expect(adapter.node("/S/G/tile+overlay/tile").rect.w).toBe(200)
		expect(adapter.node("/S/G/tile+overlay/tile").rect.h).toBe(44)
		-- the badge is still layered on top, at its own content size
		expect(adapter.node("/S/G/tile+overlay/badge").rect.w < 200).toBe(true)
	end)

	it("background inherits them too", function()
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.background(
					UI.Text({ id = "Label", text = "hi", width = fill() }),
					UI.Box({ id = "Plate", surface = "raised", width = fill() })
				),
			},
		})
		local adapter = render(bp, 300, 200)
		expect(adapter.node("/S/Label+background/Label").rect.w).toBe(300)
	end)

	it("a base with no explicit dims still content-sizes as before", function()
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.overlay(UI.Text({ id = "T", text = "hello" }), UI.Text({ id = "B", text = "!" })),
			},
		})
		local adapter = render(bp, 300, 200)
		expect(adapter.node("/S/T+overlay/T").rect.w > 0).toBe(true)
		expect(adapter.node("/S/T+overlay/T").rect.w < 300).toBe(true)
	end)
end)

-- ===========================================================================
-- DIRECTOR ROUND 9 (2026-07-26): a grid whose columns are MEASURED
-- ===========================================================================

describe('RS-DIR9: Grid minColumnWidth = "intrinsic"', function()
	-- The gallery theme picker sized its chip grid from a fixed 132 device px.
	-- That is a guess about a FONT: under classic-desktop (13 px BuilderSans)
	-- it is far too wide and under sci-fi (14 px Michroma, a display face) far
	-- too narrow, so the same picker over-wrapped in one theme and under-wrapped
	-- in the other. "intrinsic" asks the solver for the number it already has —
	-- the widest child's own measured width under the ACTIVE theme's font — so
	-- the answer moves with the theme instead of with the author's guess.
	local function textCell(id: string, text: string)
		return { id = id, kind = "text", text = text, textSize = 20 }
	end

	local function grid(node: any, w: number)
		return solve(node, w, 600).rects
	end

	it("columns are derived from the WIDEST child, not from a literal", function()
		local node = {
			id = "G",
			kind = "grid",
			width = { type = "fixed", px = 400 },
			gap = 4,
			minColumnWidth = "intrinsic",
			children = { textCell("a", "aa"), textCell("b", "wide wide wide"), textCell("c", "c") },
		}
		local wide = grid(node, 400)
		-- the widest cell decides the column, so every cell starts on that grid
		local a, b, c = wide.a, wide.b, wide.c
		expect(a ~= nil and b ~= nil and c ~= nil).toBe(true)
		local colStride = c.rect.x - a.rect.x
		-- three cells on one row would need 3 * widest; with 400 px and a widest
		-- of ~140 that is two columns, so `c` wraps onto row 2 under `a`
		expect(colStride == 0).toBe(true)
		expect(c.rect.y > a.rect.y).toBe(true)
		expect(b.rect.x > a.rect.x).toBe(true)
	end)

	it("a narrower font packs MORE columns from the same declaration", function()
		local function gridAt(size: number)
			return {
				id = "G",
				kind = "grid",
				width = { type = "fixed", px = 400 },
				gap = 4,
				minColumnWidth = "intrinsic",
				children = {
					{ id = "a", kind = "text", text = "Glossy Touch", textSize = size },
					{ id = "b", kind = "text", text = "Pixel Quest", textSize = size },
					{ id = "c", kind = "text", text = "Sci-Fi HUD", textSize = size },
					{ id = "d", kind = "text", text = "Studio Neutral", textSize = size },
				},
			}
		end
		local big = grid(gridAt(24), 400)
		local small = grid(gridAt(10), 400)
		-- at 24 px the labels are wide and the grid falls to fewer columns; at
		-- 10 px they all fit on one row. The DECLARATION never changed.
		local bigRows, smallRows = {}, {}
		for _, id in { "a", "b", "c", "d" } do
			bigRows[big[id].rect.y] = true
			smallRows[small[id].rect.y] = true
		end
		local function count(t)
			local n = 0
			for _ in t do
				n += 1
			end
			return n
		end
		expect(count(bigRows) > count(smallRows)).toBe(true)
		expect(count(smallRows)).toBe(1)
	end)

	it("a numeric minColumnWidth is untouched", function()
		local node = {
			id = "G",
			kind = "grid",
			width = { type = "fixed", px = 400 },
			gap = 4,
			minColumnWidth = 90,
			children = { textCell("a", "aa"), textCell("b", "bb"), textCell("c", "cc"), textCell("d", "dd") },
		}
		local out = grid(node, 400)
		-- 400 + 4 over 94 = 4 columns, exactly as before
		expect(out.a.rect.y).toBe(out.d.rect.y)
	end)

	it("the schema accepts the one string and refuses every other", function()
		local schema = require("../src/blueprint_schema")
		local UI = (require("../src") :: any).UI
		expect(pcall(function()
			return UI.Grid({ id = "G", minColumnWidth = "intrinsic", children = {} })
		end)).toBe(true)
		expect(pcall(function()
			return UI.Grid({ id = "G", minColumnWidth = "widest", children = {} })
		end)).toBe(false)
		expect(schema ~= nil).toBe(true)
	end)
end)

describe("RS-DIR9: a container measures in the box it will OCCUPY", function()
	-- The picker's own shape: a capped panel inside a much wider dock. Its grid
	-- was MEASURED against the dock (two rows) and ARRANGED against the cap (five
	-- rows), so the panel's raised plate stopped 65 px above its own last row.
	-- ViewThatFits was given this fix in director round 3; every other container
	-- still measured against the offer.
	it("a percent-capped panel contains the grid it arranges", function()
		local chips = {}
		for i = 1, 10 do
			table.insert(chips, { id = `c{i}`, kind = "text", text = "Fantasy Parchment", textSize = 18 })
		end
		local result = solve({
			kind = "zstack",
			id = "Dock",
			width = fill(),
			height = fill(),
			children = {
				{
					kind = "vstack",
					id = "Panel",
					width = { type = "percent", fraction = 1, offset = -16, max = 560 },
					padding = 8,
					gap = 4,
					children = { { kind = "grid", id = "G", minColumnWidth = "intrinsic", gap = 4, children = chips } },
				},
			},
		}, 1217, 993)
		local panel = result.rects.Panel.rect
		local grid = result.rects.G.rect
		expect(panel.w).toBe(560)
		-- the plate has to reach past its own content, padding included
		expect(panel.h >= grid.h + 16).toBe(true)
		for i = 1, 10 do
			local cell = result.rects[`c{i}`].rect
			expect(cell.y + cell.h <= panel.y + panel.h).toBe(true)
			expect(cell.x + cell.w <= panel.x + panel.w).toBe(true)
		end
	end)

	it("a FIXED-width container is clamped the same way", function()
		local result = solve({
			kind = "vstack",
			id = "Card",
			width = fixed(200),
			children = { { kind = "text", id = "t", text = "one two three four five six seven", textSize = 16 } },
		}, 1200, 800)
		-- measured inside 200, not inside 1200: the label wraps and the card grows
		expect(result.rects.Card.rect.w).toBe(200)
		expect(result.rects.Card.rect.h >= result.rects.t.rect.h).toBe(true)
		expect(result.rects.t.rect.h > 20).toBe(true)
	end)
end)

describe('RS-DIR9: Grid itemSizing = "uniform"', function()
	-- DIRECTOR RULING (2026-07-26): variable-width item layouts need an OPT-IN
	-- uniform sizing mode. `natural` (the default) keeps content sizing, exactly
	-- as every existing grid gets it; `uniform` measures every child under the
	-- ACTIVE theme's font, takes the MAX measured cell size across items and
	-- applies it to every cell — so a set of ragged chips becomes a clean grid of
	-- equal plates, and a wide display face grows all of them together.
	local function label(id: string, text: string, size: number?)
		return { id = id, kind = "text", text = text, textSize = size or 20 }
	end

	local function uniformGrid(size: number?, mode: string?, width: number?)
		return {
			kind = "grid",
			id = "G",
			width = fixed(width or 600),
			gap = 4,
			columns = 3,
			itemSizing = mode,
			children = {
				label("a", "Sci-Fi HUD", size),
				label("b", "Fantasy Parchment (stub)", size),
				label("c", "Pixel", size),
			},
		}
	end

	it("every cell takes the MAX measured size, on both axes", function()
		local out = solve(uniformGrid(20, "uniform"), 700, 400).rects
		local a, b, c = out.a.rect, out.b.rect, out.c.rect
		expect(a.w).toBe(b.w)
		expect(b.w).toBe(c.w)
		expect(a.h).toBe(b.h)
		expect(b.h).toBe(c.h)
		-- ...and the max is a real MEASUREMENT, not the column width: naturally the
		-- three cells are 124 / 112 / 62 wide (the long label WRAPS inside its
		-- column, so its widest LINE is 112 — narrower than the one-line
		-- "Sci-Fi HUD"), and uniform takes 124, the true max, for all three.
		local natural = solve(uniformGrid(20, nil), 700, 400).rects
		expect(natural.c.rect.w < natural.a.rect.w).toBe(true)
		expect(natural.b.rect.w < natural.a.rect.w).toBe(true)
		expect(a.w).toBe(natural.a.rect.w)
		-- the tallest cell decides the height, so the wrapped label is not clipped
		expect(a.h).toBe(natural.b.rect.h)
	end)

	it("the default is byte-unchanged: `natural` and an absent option agree", function()
		local absent = solve(uniformGrid(20, nil), 700, 400).rects
		local natural = solve(uniformGrid(20, "natural"), 700, 400).rects
		for _, id in { "a", "b", "c" } do
			expect(natural[id].rect.w).toBe(absent[id].rect.w)
			expect(natural[id].rect.h).toBe(absent[id].rect.h)
			expect(natural[id].rect.x).toBe(absent[id].rect.x)
		end
		-- and the cells are RAGGED there, which is the whole reason the option exists
		expect(absent.a.rect.w ~= absent.c.rect.w).toBe(true)
	end)

	it("a bigger font grows every cell together (the theme-swap property)", function()
		-- wide enough that nothing is capped by its column: the FONT is the variable
		local small = solve(uniformGrid(12, "uniform", 1200), 1400, 400).rects
		local big = solve(uniformGrid(24, "uniform", 1200), 1400, 400).rects
		expect(big.a.rect.w > small.a.rect.w).toBe(true)
		expect(big.a.rect.w).toBe(big.c.rect.w)
		expect(small.a.rect.w).toBe(small.c.rect.w)
	end)

	it("the grid's own measured height counts uniform rows", function()
		-- 6 children over 3 columns = 2 rows, and both rows are the uniform height
		local node = {
			kind = "grid",
			id = "G",
			width = fixed(600),
			gap = 4,
			columns = 3,
			itemSizing = "uniform",
			children = {
				label("a", "one"),
				label("b", "two"),
				label("c", "a much longer label that wraps somewhere"),
				label("d", "four"),
				label("e", "five"),
				label("f", "six"),
			},
		}
		local out = solve(node, 700, 800).rects
		local cell = out.a.rect.h
		expect(out.f.rect.y).toBe(out.a.rect.y + cell + 4)
		expect(out.G.rect.h).toBe(cell * 2 + 4)
	end)

	it("the schema accepts the two modes and refuses anything else", function()
		local UI = (require("../src") :: any).UI
		expect(pcall(function()
			return UI.Grid({ id = "G", itemSizing = "uniform", children = {} })
		end)).toBe(true)
		expect(pcall(function()
			return UI.Grid({ id = "G", itemSizing = "natural", children = {} })
		end)).toBe(true)
		expect(pcall(function()
			return UI.Grid({ id = "G", itemSizing = "equal", children = {} })
		end)).toBe(false)
	end)
end)

describe("RS-DIR14: a Grid's ROW gap is its own axis", function()
	-- DIRECTOR FINDING 14 (2026-07-26): "the picker grid needs more VERTICAL
	-- space between rows, especially studio-neutral and compact-pointer".
	--
	-- Measured live at the reported stamp, studio-neutral, 1233x1067: ten 196x36
	-- chips in a 544px grid, rows **4 px** apart (`gap`) and columns **78 px**
	-- apart — because the column pitch is `innerW / cols` while the row pitch is
	-- the gap itself. One number was doing two jobs with wildly different
	-- consequences: raising it to open the rows would have re-columned the grid,
	-- which is a director ruling.
	--
	-- So the two axes separate. `rowGap` defaults to `gap` — every existing grid
	-- in the library, the examples and the fixtures is byte-unchanged — and a
	-- caller that wants air between rows without touching the column count says
	-- so in one word.
	local function rows(rowGap: any)
		return {
			kind = "grid",
			id = "G",
			width = fixed(600),
			gap = 4,
			rowGap = rowGap,
			columns = 2,
			children = {
				{ id = "a", kind = "box", width = fixed(100), height = fixed(20) },
				{ id = "b", kind = "box", width = fixed(100), height = fixed(20) },
				{ id = "c", kind = "box", width = fixed(100), height = fixed(20) },
				{ id = "d", kind = "box", width = fixed(100), height = fixed(20) },
			},
		}
	end

	it("opens the ROWS without moving a single column", function()
		local tight = solve(rows(nil), 700, 400).rects
		local open = solve(rows(16), 700, 400).rects
		-- columns: identical x for every cell, both pitches
		expect(open.a.rect.x).toBe(tight.a.rect.x)
		expect(open.b.rect.x).toBe(tight.b.rect.x)
		expect(open.d.rect.x).toBe(tight.b.rect.x)
		-- rows: the second row moves by exactly the difference
		expect(tight.c.rect.y - tight.a.rect.y).toBe(20 + 4)
		expect(open.c.rect.y - open.a.rect.y).toBe(20 + 16)
	end)

	it("counts in the grid's own measured height, so a taller grid reports taller", function()
		local tight = solve(rows(nil), 700, 400).rects
		local open = solve(rows(16), 700, 400).rects
		expect(tight.G.rect.h).toBe(20 * 2 + 4)
		expect(open.G.rect.h).toBe(20 * 2 + 16)
	end)

	it("defaults to `gap`: an absent rowGap is byte-identical to today", function()
		local absent = solve(rows(nil), 700, 400).rects
		local same = solve(rows(4), 700, 400).rects
		for _, id in { "a", "b", "c", "d", "G" } do
			expect(same[id].rect.x).toBe(absent[id].rect.x)
			expect(same[id].rect.y).toBe(absent[id].rect.y)
			expect(same[id].rect.w).toBe(absent[id].rect.w)
			expect(same[id].rect.h).toBe(absent[id].rect.h)
		end
	end)

	it("never touches the COLUMN COUNT — the property the director's ruling needs", function()
		-- `minColumnWidth` divides the inner width by (minCol + gap): a row gap
		-- that leaked into that arithmetic would re-column the grid on a package
		-- with a wider space ladder, which is exactly what the literal was
		-- protecting against.
		local function intrinsic(rowGap: any)
			return {
				kind = "grid",
				id = "G",
				width = fixed(600),
				gap = 4,
				rowGap = rowGap,
				minColumnWidth = 180,
				children = {
					{ id = "a", kind = "box", width = fixed(100), height = fixed(20) },
					{ id = "b", kind = "box", width = fixed(100), height = fixed(20) },
					{ id = "c", kind = "box", width = fixed(100), height = fixed(20) },
					{ id = "d", kind = "box", width = fixed(100), height = fixed(20) },
				},
			}
		end
		local tight = solve(intrinsic(nil), 700, 400).rects
		local open = solve(intrinsic(40), 700, 400).rects
		-- three columns either way: a, b, c on row 1 and d alone on row 2
		expect(tight.d.rect.x).toBe(tight.a.rect.x)
		expect(open.d.rect.x).toBe(open.a.rect.x)
		expect(open.c.rect.x).toBe(tight.c.rect.x)
	end)

	it("is a spacing METRIC at the boundary, so a theme swap moves it", function()
		local UI = (require("../src") :: any).UI
		expect(pcall(function()
			return UI.Grid({ id = "G", rowGap = "s", children = {} })
		end)).toBe(true)
		expect(pcall(function()
			return UI.Grid({ id = "G", rowGap = 12, children = {} })
		end)).toBe(true)
		expect(pcall(function()
			return UI.Grid({ id = "G", rowGap = "enormous", children = {} })
		end)).toBe(false)
	end)
end)

-- ===========================================================================
-- F-3 (ledger/blueprints.md BP-F3): UI.background inflated a dimension-less
-- backing layer by REBUILDING the frozen node — and the rebuild dropped `meta`,
-- the library's framework channel. A drag declaration or an input contribution
-- on the backing plate disappeared silently, and only in the COMMON case (no
-- explicit width AND height). Nothing pinned meta survival through either
-- structural modifier.
-- ===========================================================================

describe("F-3: a structural modifier carries the content's meta channel", function()
	local dragContract = require("../src/input/drag_contract")
	local contribution = require("../src/input/contribution")

	it("an INFLATED backing layer keeps its drag declaration", function()
		local plate = UI.draggable(UI.Box({ id = "Plate", surface = "control" }), { payload = 2 })
		expect(dragContract.readSource(plate) ~= nil).toBe(true)

		local wrapper = UI.background(UI.Text({ id = "Tile", text = "hi" }), plate)
		local backing = (wrapper.children :: any)[1]
		expect(backing.id).toBe("Plate")
		-- it really WAS inflated (this is the path that used to drop meta)
		expect(backing.props.width.type).toBe("fill")
		expect(backing.props.height.type).toBe("fill")
		local source = dragContract.readSource(backing)
		expect(source ~= nil).toBe(true)
		expect((source :: any).payload).toBe(2)
	end)

	it("an input-contribution bundle survives the same inflate", function()
		local plate = contribution.attach(UI.Box({ id = "Plate" }), { rootPath = "/Tile+background/Plate" } :: any)
		local wrapper = UI.background(UI.Text({ id = "Tile", text = "hi" }), plate)
		expect(contribution.read((wrapper.children :: any)[1]) ~= nil).toBe(true)
	end)

	it("a backing layer with its OWN dimensions is passed through untouched, meta included", function()
		local plate = UI.draggable(
			UI.Box({ id = "Plate", width = { type = "fixed", px = 20 }, height = { type = "fixed", px = 20 } }),
			{ payload = 7 }
		)
		local wrapper = UI.background(UI.Text({ id = "Tile", text = "hi" }), plate)
		local backing = (wrapper.children :: any)[1]
		expect(backing).toBe(plate)
		expect((dragContract.readSource(backing) :: any).payload).toBe(7)
	end)

	it("UI.overlay never rebuilt its content, and still does not", function()
		local badge = UI.draggable(UI.Box({ id = "Badge" }), { payload = 3 })
		local wrapper = UI.overlay(UI.Text({ id = "Tile", text = "hi" }), badge)
		expect((dragContract.readSource((wrapper.children :: any)[2]) :: any).payload).toBe(3)
	end)
end)

--[[ THE SHRINK PASS'S TWO UNDECIDED EDGES (round-2 RED-TEAM, carried into round 3).

	Both were named in round 3's brief as "shrink-pass design gaps", both were
	measured on 2026-08-13, and both are TRUE. Neither is changed here: these cases
	PIN the behaviour that ships, so that changing it later is a deliberate act with
	a red test rather than a silent drift. Where a ruling is owed, it says so.
]]
describe("shrink pass: the two edges the RED-TEAM named, pinned as they actually behave", function()
	it("(a) IS BEST-EFFORT: a shrinkable label can still land outside its box, and the solver SAYS SO", function()
		-- three shrinkable texts in a box far too small for them. The pass absorbs
		-- what it can and then stops: `absorbTier` can only take back the sum of
		-- (basis - floor), and a text node's floor is relative to its CONTENT (its
		-- minimum wrap width), never to the space available. Residual deficit is
		-- simply not absorbed, and arrange places the children anyway.
		local r = solve({
			kind = "hstack",
			id = "R",
			gap = 0,
			children = {
				{ kind = "text", id = "t1", text = "Alphabetical", shrinkWeight = 1 },
				{ kind = "text", id = "t2", text = "Chronological", shrinkWeight = 1 },
				{ kind = "text", id = "t3", text = "Relevance", shrinkWeight = 1 },
			},
		}, 120, 60)
		-- MEASURED: t1 fills the box, t2 and t3 land wholly outside it.
		expect(r.rects.t2.rect.x >= 120).toBe(true)
		expect(r.rects.t3.rect.x >= 120).toBe(true)

		-- ...and this is why it is not a silent wrong result: the solver files the
		-- overflow AND names the pass that could not close it. A shrink pass that
		-- absorbed nothing and said nothing would be the defect; this one reports.
		local said = false
		for _, d in r.diagnostics or {} do
			if d.node == "R" and string.find(tostring(d.issue), "already at its floor", 1, true) ~= nil then
				said = true
			end
		end
		expect(said).toBe(true)
	end)

	it("(b) shrinkWeight CHANGES WHICH ViewThatFits CANDIDATE WINS — and round 2's design doc denied it", function()
		--[[ `swiftui-parity-round2.md` §2.4 states that `ViewThatFits` "picks its
			candidate BEFORE any of this and is therefore unaffected". That was true
			of the arrange-only shrink it was written for, and PASS 1.5 — the
			measure-side shrink that landed a day later — invalidated it.

			The mechanism: `chosenCandidate` picks the first candidate whose
			`measure` fits the offer. If that candidate is a stack whose children
			declare `shrinkWeight`, its measure reaches PASS 1.5, absorbs the
			deficit, and reports the SHRUNK extent — so it fits where it otherwise
			would not, and wins.

			MEASURED: swept 150-420px in 10px steps, adding `shrinkWeight = 1` to the
			wide candidate's children flips the winner at 10 of 28 widths.

			A RULING IS OWED, and this case does not pre-empt it. The behaviour is
			arguably CORRECT — a candidate that can shrink to fit does fit — but it
			is undefined, it contradicts the shipped design doc, and the winner now
			depends on a prop declared on the candidate's CHILDREN, which the
			`ViewThatFits` author may not own. Until the director rules, the
			behaviour is pinned here so it cannot drift unnoticed in either
			direction. ]]
		local function winnerAt(width: number, withShrink: boolean): string
			local sw = if withShrink then 1 else nil
			local res = solve({
				kind = "fits",
				id = "F",
				children = {
					{
						kind = "hstack",
						id = "Wide",
						gap = 0,
						children = {
							{ kind = "text", id = "w1", text = "Sort alphabetically", shrinkWeight = sw },
							{ kind = "text", id = "w2", text = "Sort chronologically", shrinkWeight = sw },
						},
					},
					{ kind = "text", id = "Fallback", text = "Sort" },
				},
			}, width, 60)
			local wide = res.rects.Wide
			return if wide ~= nil and wide.rect.w > 0 then "Wide" else "Fallback"
		end

		-- THE WHOLE SWEPT RANGE, not a sample of it. Any width where the two runs
		-- disagree is named in the failure message, so a regression says WHERE.
		local flipped: { string } = {}
		for width = 150, 420, 10 do
			local without, with = winnerAt(width, false), winnerAt(width, true)
			if without ~= with then
				table.insert(flipped, `{width}:{without}->{with}`)
			end
		end
		expect(`flipped=[{table.concat(flipped, " ")}]`).toBe("flipped=[]")

		-- ...and the sweep is only meaningful because the winner actually MOVES
		-- across it — a fixture that answered "Fallback" at all 28 widths would pass
		-- the line above while proving nothing.
		expect(winnerAt(150, false)).toBe("Fallback")
		expect(winnerAt(420, false)).toBe("Wide")
	end)

	it("(c) ...and the candidate that WINS is still shrunk to the offer it is given", function()
		--[[ The second half of SwiftUI's contract, and the reason (b) is a rule about
			the CHOICE rather than a switch that turns the feature off: the chosen
			child is laid out against the proposal `ViewThatFits` itself received.

			The fixture forces the LAST candidate (rule 8's declared fallback: nothing
			fits, so the last one shows). Its children declare `shrinkWeight`, so once
			it is showing it must absorb the deficit — if the fit probe's "no shrink"
			leaked into the real layout, these two would still be at their natural
			widths and w1 would run past the box. ]]
		local function fallbackWidths(): (number, number)
			local res = solve({
				kind = "fits",
				id = "F",
				children = {
					{ kind = "text", id = "Wide", text = "Sort alphabetically and then chronologically" },
					{
						kind = "hstack",
						id = "Narrow",
						gap = 0,
						children = {
							{ kind = "text", id = "n1", text = "Alphabetical", shrinkWeight = 1 },
							{ kind = "text", id = "n2", text = "Chronological", shrinkWeight = 1 },
						},
					},
				},
			}, 150, 60)
			return res.rects.n1.rect.w, res.rects.n2.rect.w
		end
		local w1, w2 = fallbackWidths()
		-- the pair is squeezed INTO the 150px box rather than reported at its
		-- natural ~220px; shrink is best-effort (case (a)), so the assertion is
		-- "compressed", not "exactly 150"
		expect(`n1={w1 < 110} n2={w2 < 110}`).toBe("n1=true n2=true")
	end)

	it("(d) the fit probe is part of the MEASURE MEMO's key, or a row reserves the wrong height", function()
		--[[ THE THIRD PIECE, and the one that is invisible without a ScrollView. The
			probe answers a DIFFERENT question about the same node at the same offer —
			"how big without the shrink" — so it has to be a different cache key
			(`ctx.scopeKey`'s fifth writer). Sharing one key means the real measure of
			the WINNING candidate hits the probe's entry and gets the unshrunk answer.

			The consequence is not academic: the row here holds two labels squeezed
			into a fixed 260px, and squeezed labels WRAP. Unshrunk they are one line
			(20px); shrunk they are two (39px). A shared key reserves 20 and paints
			39 — `docs/lessons/measure-the-requirement-not-the-render.md`, the class
			this solver has now fixed five times.

			IT MUST BE UNDER A SCROLLVIEW: the memo is gated on `ctx.hasScroll`, so a
			fixture without one runs uncached and can say nothing about the key. The
			no-scroll run is asserted beside it as the control — same tree, same
			answer, and the difference between them is entirely the cache. ]]
		local function rowHeight(withScroll: boolean): number
			local fits = {
				kind = "fits",
				id = "F",
				children = {
					{
						kind = "vstack",
						id = "Wide",
						gap = 0,
						children = {
							{
								kind = "hstack",
								id = "S",
								gap = 0,
								width = { type = "fixed", px = 260 },
								children = {
									{ kind = "text", id = "s1", text = "Alphabetical order today", shrinkWeight = 1 },
									{ kind = "text", id = "s2", text = "Chronological order today", shrinkWeight = 1 },
								},
							},
						},
					},
					{ kind = "text", id = "Fb", text = "x" },
				},
			}
			local root: any = fits
			if withScroll then
				root = {
					kind = "scroll",
					id = "Sc",
					axis = "y",
					width = { type = "fill" },
					height = { type = "fill" },
					children = { fits },
				}
			end
			return solve(root, 400, 600).rects.S.rect.h
		end
		expect(`scrolled={rowHeight(true)} plain={rowHeight(false)}`).toBe("scrolled=39 plain=39")
	end)
end)
