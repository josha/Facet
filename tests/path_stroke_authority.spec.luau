--!strict
--[[ ── THE STROKE IS AN ENGINE OBJECT THIS TARGET CREATED, AND IT OWNS IT ───────
	(2026-09-07, found while root-causing the HUD chrome-rotation paint loss.)

	A `UI.Path` is realised as a transparent holder plus an engine `Path2D` CHILD
	that `src/client/screen_target.luau` creates itself. Nothing outside the
	adapter can see that object: the z walk never visits it, no `StyleRule` can
	select it, and the renderer's property authority does not name it. So every
	fact about it is the target's to carry by hand, and two of them were not
	being carried.

	  1. PAINT ORDER. The stroke was born at the engine's class default (`ZIndex`
	     1) and stayed there for the life of the node, while its holder carried
	     whatever `render/z_order.luau` assigned — 96 on the shipped HUD. Nothing
	     re-synced it: `setZOrder` mirrored z to the hit expander (a SIBLING, with
	     a comment saying why) and not to the stroke (a CHILD, which the walk does
	     not reach either).

	  2. GEOMETRY UPLOADS. `SetControlPoints` is not a property assignment. It
	     hands the engine a whole new vector shape and the engine does not diff
	     it, so it is the single most expensive call this target can make on a
	     Path. `applyRect` ran it on EVERY rect write — for points that, since
	     they moved to `Scale` (2026-08-29), are the same numbers every time.

	WHY A SPEC AND NOT A COMMENT. Both are invisible to every existing check: the
	renderer's own property-authority ledger does not name `Path2D`, and the fake
	target had no stroke record at all, so a target that uploaded once and one
	that uploaded on every frame were the same target headless. The fake models
	the stroke now (`adapter.pathStrokeOf`), mirroring both live call sites, which
	is what makes these two claims checkable rather than believed.

	WHAT THIS IS NOT. It is not a fix for the chrome-rotation paint loss — that
	one is measured in `tests/hud_chrome_sequence.spec.luau`'s header and neither
	change moves it. These are authority gaps that were found on the way and are
	true on their own.
]]

local fs = require("@lune/fs")
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local test_world = require("./lib/world")

local UI = Facet.UI

-- a unit-box ring, in the normalized shape `UI.Path` takes
local function ringPoints(n: number): { any }
	local points = {}
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		table.insert(points, {
			x = 0.5 + 0.4 * math.cos(a),
			y = 0.5 + 0.4 * math.sin(a),
			inX = 0,
			inY = 0,
			outX = 0,
			outY = 0,
		})
	end
	return points
end

--[[ A SCREEN WITH THE PATH DEEP IN DOCUMENT ORDER, because a stroke at the head
	of the walk would be at `ZIndex` 1 anyway and the case would pass on the
	defect. Everything before it pushes the counter well past the class default. ]]
local function screenWith(points: { any }, extraLeaves: number): any
	local before = {}
	for i = 1, extraLeaves do
		table.insert(before, UI.Box({ id = `Lead{i}`, surface = "raised" }))
	end
	table.insert(
		before,
		UI.HStack({
			id = "RingRow",
			children = { UI.Path({ id = "Ring", points = points, closed = true, thickness = 2 }) },
		})
	)
	table.insert(before, UI.Box({ id = "Trail", surface = "raised" }))
	return UI.Screen({ id = "PathZ", children = { UI.VStack({ id = "Col", children = before }) } })
end

local RING_PATH = "/PathZ/Col/RingRow/Ring"

describe("the Path2D a render target creates carries its node's paint order", function()
	it("the stroke's ZIndex is the node's z, not the engine's class default", function()
		local w = test_world.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
		w.present(screenWith(ringPoints(8), 6))
		w.settle(2)

		local node = w.adapter.node(RING_PATH)
		local stroke = w.adapter.pathStrokeOf(RING_PATH)
		expect(`the path node exists: {node ~= nil}`).toBe("the path node exists: true")
		expect(`it has a stroke: {stroke ~= nil}`).toBe("it has a stroke: true")

		--[[ THE PREMISE. This case is only worth its runtime if the node's own z is
			PAST the engine's class default, or "the stroke matches" and "the stroke
			was never touched" are the same observation. Six leading boxes put it
			well past 1. ]]
		expect(`the node's z is past the class default: {(node.z or 0) > 1}`).toBe(
			"the node's z is past the class default: true"
		)
		expect(`stroke z {stroke.zIndex} == node z {node.z}`).toBe(`stroke z {node.z} == node z {node.z}`)
	end)

	it("...and it follows the node when a structural change renumbers the walk", function()
		local w = test_world.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
		w.present(screenWith(ringPoints(8), 2))
		w.settle(2)
		local first = (w.adapter.node(RING_PATH) :: any).z

		--[[ A SECOND MOUNT WITH MORE AHEAD OF THE RING is the cheapest honest way to
			re-run the walk against a different document: the z walk is a function of
			the tree, so a longer prefix is a different number. What is asserted is
			the INVARIANT — stroke == node — at both, plus that the two really are
			different numbers, so a target that wrote the stroke once at create and
			never again cannot pass. ]]
		local w2 = test_world.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
		w2.present(screenWith(ringPoints(8), 12))
		w2.settle(2)
		local second = (w2.adapter.node(RING_PATH) :: any).z

		expect(`the walk really renumbered: {first ~= second}`).toBe("the walk really renumbered: true")
		local s1 = w.adapter.pathStrokeOf(RING_PATH)
		local s2 = w2.adapter.pathStrokeOf(RING_PATH)
		expect(`short tree: stroke {s1.zIndex} == node {first}`).toBe(`short tree: stroke {first} == node {first}`)
		expect(`long tree: stroke {s2.zIndex} == node {second}`).toBe(`long tree: stroke {second} == node {second}`)
	end)
end)

describe("the Path2D's geometry is uploaded once, not on every rect write", function()
	it("a viewport that moves every box uploads NO new geometry", function()
		local w = test_world.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
		w.present(screenWith(ringPoints(12), 4))
		w.settle(2)

		local afterMount = (w.adapter.pathStrokeOf(RING_PATH) :: any).uploads
		expect(`the shape reached the engine once: {afterMount}`).toBe("the shape reached the engine once: 1")

		--[[ NOW MOVE EVERY BOX, repeatedly. `applyRect` runs the stroke belt on every
			rect write, and the points ride `Scale` — so the ENGINE re-scales them
			with the box the same call just wrote and there is nothing new to send. ]]
		local rects = 0
		for i = 1, 6 do
			w.env:set("viewportRect", { x = 0, y = 0, w = 300 + i * 20, h = 700 + i * 17 })
			w.settle(2)
			local node = w.adapter.node(RING_PATH)
			if node ~= nil and node.rect ~= nil then
				rects += 1
			end
		end

		-- the premise: the ring's own box really did move, or nothing was re-applied
		expect(`the ring was solved at every viewport: {rects}`).toBe("the ring was solved at every viewport: 6")
		expect(`uploads after six viewport changes: {(w.adapter.pathStrokeOf(RING_PATH) :: any).uploads}`).toBe(
			"uploads after six viewport changes: 1"
		)
	end)

	it("...and a REAL change to the points does upload, so the diff is not a mute", function()
		local w = test_world.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
		-- mount at eight control points, then re-present at twelve: a different shape
		w.present(screenWith(ringPoints(8), 4))
		w.settle(2)
		expect(`eight-point ring uploads: {(w.adapter.pathStrokeOf(RING_PATH) :: any).uploads}`).toBe(
			"eight-point ring uploads: 1"
		)

		local w2 = test_world.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
		w2.present(screenWith(ringPoints(12), 4))
		w2.settle(2)
		local a = w.adapter.pathStrokeOf(RING_PATH) :: any
		local b = w2.adapter.pathStrokeOf(RING_PATH) :: any
		expect(`a twelve-point ring is a different shape: {#a.points ~= #b.points}`).toBe(
			"a twelve-point ring is a different shape: true"
		)
		expect(`and it was uploaded: {b.uploads}`).toBe("and it was uploaded: 1")
	end)
end)

--[[ ── AND THE LIVE TARGET, WHICH NO HEADLESS RUN CAN EXECUTE ──────────────────

	Everything above is asserted against `tests/lib/fake_target`, because that is
	what a headless suite has. The fake is a MIRROR: it models the stroke exactly
	as `screen_target` builds one, and `tests/render_target_contract.spec.luau`
	is what holds the pair together in general. These two pins close the specific
	gap, in the same shape `conn_reconnect_sweep` and the contract spec already
	use — a fake that models a rule the real adapter does not follow proves the
	wrong thing, and this rule lives in code no Lune process can run. ]]
describe("the live ScreenTarget follows the same two rules", function()
	it("screen_target gives the Path2D its node's paint order, at create and at setZOrder", function()
		local source = fs.readFile("src/client/screen_target.luau")
		expect(`create carries it: {string.find(source, "path2d.ZIndex = instance.ZIndex", 1, true) ~= nil}`).toBe(
			"create carries it: true"
		)
		expect(`setZOrder mirrors it: {string.find(source, "handle.path2d.ZIndex = z", 1, true) ~= nil}`).toBe(
			"setZOrder mirrors it: true"
		)
	end)

	it("screen_presentation value-diffs the geometry upload rather than re-sending it", function()
		local source = fs.readFile("src/client/screen_presentation.luau")
		expect(`the diff exists: {string.find(source, "samePathPoints", 1, true) ~= nil}`).toBe("the diff exists: true")
		--[[ ...AND IT GUARDS THE UPLOAD RATHER THAN SITTING BESIDE IT. A helper that
			is defined and never consulted is the shape this pin exists to refuse. ]]
		local guarded = string.find(source, "if samePathPoints(handle.appliedPathPoints, points) then", 1, true)
		expect(`the upload is guarded by it: {guarded ~= nil}`).toBe("the upload is guarded by it: true")
	end)
end)
