--!strict
--[[ `placement.anchorPlace` + `placement.innerBox` (Plan C, T2) — THE ONE COPY of
	the corner-anchor maths and the padded-content-box derivation, pinned by hand
	arithmetic so a caller other than the solver (T5's translate lane) can trust the
	numbers without re-deriving them.

	NINE ANCHORS, ONE BOX. `innerX=10, innerY=20, innerW=300, innerH=200`, a
	100x50 child, `offsetX=5, offsetY=-3` — both offsets pass through `offsetPx`
	unchanged because they are plain numbers. `x = 10 + roundPx((300-100)*fx) + 5`
	and `y = 20 + roundPx((200-50)*fy) - 3`; every `fx`/`fy` product below is an
	exact integer (0, 100 or 200 on the x axis; 0, 75 or 150 on the y axis), so
	`roundPx` never has a fraction to round and the pins are the raw arithmetic.

	THE FILL AXIS and the `{ scale, offset }` FORM are `anchorPlace`'s other two
	moving parts, each pinned in isolation against the exact numbers the task brief
	gives; UNKNOWN ANCHOR proves the topLeft fallback and the boolean the solver
	files its diagnostic from.

	`innerBox` (review IM-3) is the second half of the same anti-divergence ruling:
	the padded-box pin and the `math.max(0, …)` clamp are both hand arithmetic, and
	the last case drives a real solve and compares its child's rect against
	`anchorPlace(placement.innerBox(...))` called directly — the pin that keeps
	"one copy" true once T5's lane starts calling both functions the solver calls. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local placement = require("../src/layout/placement")

local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")

local function px(n: number): any
	return { type = "fixed", px = n }
end

local function fill(): any
	return { type = "fill", weight = 1 }
end

describe("placement.anchorPlace: the nine corners, by hand", function()
	local INNER_X, INNER_Y, INNER_W, INNER_H = 10, 20, 300, 200
	local W, H = 100, 50
	local OFFSET_X, OFFSET_Y = 5, -3

	local CASES = {
		{ anchor = "topLeft", x = 15, y = 17 },
		{ anchor = "top", x = 115, y = 17 },
		{ anchor = "topRight", x = 215, y = 17 },
		{ anchor = "left", x = 15, y = 92 },
		{ anchor = "center", x = 115, y = 92 },
		{ anchor = "right", x = 215, y = 92 },
		{ anchor = "bottomLeft", x = 15, y = 167 },
		{ anchor = "bottom", x = 115, y = 167 },
		{ anchor = "bottomRight", x = 215, y = 167 },
	}

	for _, case in CASES do
		it(`{case.anchor}: x={case.x}, y={case.y}, w/h pass through, unknownAnchor=false`, function()
			local x, y, w, h, unknown = placement.anchorPlace(
				INNER_X,
				INNER_Y,
				INNER_W,
				INNER_H,
				W,
				H,
				false,
				false,
				case.anchor,
				OFFSET_X,
				OFFSET_Y
			)
			expect(x).toBe(case.x)
			expect(y).toBe(case.y)
			expect(w).toBe(W)
			expect(h).toBe(H)
			expect(unknown).toBe(false)
		end)
	end

	it("unknown anchor: unknownAnchor=true, placed exactly as topLeft", function()
		local x, y, w, h, unknown =
			placement.anchorPlace(INNER_X, INNER_Y, INNER_W, INNER_H, W, H, false, false, "nowhere", OFFSET_X, OFFSET_Y)
		expect(unknown).toBe(true)
		expect(x).toBe(15)
		expect(y).toBe(17)
		expect(w).toBe(W)
		expect(h).toBe(H)
	end)
end)

describe("placement.anchorPlace: the fill axis and the { scale, offset } form", function()
	it("a fill-width child under topLeft with offsetX=30: w = offsetFill(300, 30, 0) = 270", function()
		local x, y, w, h, unknown = placement.anchorPlace(10, 20, 300, 200, 999, 50, true, false, "topLeft", 30, 0)
		expect(w).toBe(270)
		expect(unknown).toBe(false)
		-- x is computed from the RESOLVED w, not the 999 passed in
		expect(x).toBe(10 + 30)
		expect(y).toBe(20)
		expect(h).toBe(50)
	end)

	it("a { scale = 0.5, offset = -9 } offsetX resolves through offsetPx: roundPx(150 - 9) = 141", function()
		local x =
			placement.anchorPlace(10, 20, 300, 200, 100, 50, false, false, "topLeft", { scale = 0.5, offset = -9 }, 0)
		expect(x).toBe(10 + 141)
	end)
end)

describe("placement.innerBox: the padded content box, one copy (IM-3)", function()
	it("a padded box: innerBox(10, 20, 300, 200, 4, 6, 8, 12) -> 22, 24, 282, 188", function()
		local x, y, w, h = placement.innerBox(10, 20, 300, 200, 4, 6, 8, 12)
		expect(x).toBe(22)
		expect(y).toBe(24)
		expect(w).toBe(282)
		expect(h).toBe(188)
	end)

	it("the clamp case: innerBox(0, 0, 10, 10, 20, 20, 20, 20) -> 20, 20, 0, 0, never negative", function()
		local x, y, w, h = placement.innerBox(0, 0, 10, 10, 20, 20, 20, 20)
		expect(x).toBe(20)
		expect(y).toBe(20)
		expect(w).toBe(0)
		expect(h).toBe(0)
	end)

	it(
		"ANTI-DIVERGENCE (review IM-3): a padded Anchor, a { scale, offset } offset and a fill-parent "
			.. "child, through the SOLVER and through anchorPlace(innerBox(...)) called directly, agree",
		function()
			--[[ THE WORLD, built by hand exactly as `tests/rect_reads_seam.spec.luau` and
			`tests/layout_prop_dirt.spec.luau:395-422` do: `customFactory.new()` /
			`environment.new` / `mountLib.mount` / `fake_target.new()` / `renderer.attach`.
			A padded `Anchor` filling a 300x200 viewport, with one child anchored
			`bottomRight`, a fill WIDTH (so `anchorPlace`'s `offsetFill` branch is
			exercised) and a `{ scale, offset }` form on both offsets — the shape a
			marker overlay needs (`placement.luau`'s own header) and the one
			`row_actions.luau:1987` already hands a solver `offsetY` in production. ]]
			local core = customFactory.new()
			local env = environment.new(core)
			env:set("viewportRect", { x = 0, y = 0, w = 300, h = 200 })
			local bp = UI.Anchor({
				id = "Root",
				padding = 6,
				width = fill(),
				height = fill(),
				children = {
					UI.Box({
						id = "Child",
						anchor = "bottomRight",
						offsetX = { scale = 0.1, offset = -4 },
						offsetY = { scale = -0.2, offset = 3 },
						width = fill(),
						height = px(40),
					}),
				},
			})
			local root = mountLib.mount(core, UI.Screen({ id = "S", children = { bp } }))
			local adapter = fake_target.new()
			local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
			controller.initialRender()

			local rootRect = controller.rectOf("/S/Root")
			assert(rootRect ~= nil, "the Anchor's own rect was not solved")
			local childRect = controller.rectOf("/S/Root/Child")
			assert(childRect ~= nil, "the child's rect was not solved")

			local innerX, innerY, innerW, innerH =
				placement.innerBox(rootRect.x, rootRect.y, rootRect.w, rootRect.h, 6, 6, 6, 6)
			local x, y, w, h, unknown = placement.anchorPlace(
				innerX,
				innerY,
				innerW,
				innerH,
				0, -- w: irrelevant, the fill axis overrides it
				40,
				true,
				false,
				"bottomRight",
				{ scale = 0.1, offset = -4 },
				{ scale = -0.2, offset = 3 }
			)
			expect(unknown).toBe(false)
			expect(x).toBe(childRect.x)
			expect(y).toBe(childRect.y)
			expect(w).toBe(childRect.w)
			expect(h).toBe(childRect.h)
		end
	)
end)
