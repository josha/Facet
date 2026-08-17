--!strict
--[[ WHAT MUST NOT DRIFT WHILE THE TREE IS STILL FLAT (ADR-0032 step 2).

	These are instruments, not features. The nested-tree migration is measured
	against them, and ADR-0032 is explicit about the order: they "are worth
	nothing if written after the change they are meant to catch". So every case
	below asserts what is true TODAY, on the flat tree, including the two cases
	that a later step is EXPECTED to reverse — because a pin that reddens by name
	when Decision 4 lands is the difference between a deliberate change and a
	discovered one.

	THREE THINGS, and the third is the one this spec exists for.

	1. DFS DOCUMENT ORDER IS `Sibling` ORDER (ADR-0032 Decision 3). `ZIndexBehavior`
	   on every live ScreenGui is `Sibling`, measured — not `Global`, which both the
	   brief and the coordinator predicted and which ADR-0009's verifier F1 refuses
	   outright (a child at ZIndex 20 under a parent at 50 renders INVISIBLE, and
	   this framework pins every button icon at 20). Under `Sibling` the engine
	   paints a parent, then its subtree, then the parent's next sibling — which is
	   exactly the order `syncZOrder`'s depth-first counter already produces across
	   the flat set. That is why nesting needs no new ordering code, and this pins
	   the claim rather than leaving it in a comment.

	2. `tapAt` AND THE Z COUNTER AGREE. `tapAt`'s correctness rests on the comment
	   "last match wins: document order IS paint order" — asserted in prose, in a
	   file that does not compute paint order. `syncZOrder` is the thing that
	   computes paint order. ADR-0032's Consequences asks for this to be pinned;
	   pinning them AGAINST EACH OTHER is worth more than pinning either alone,
	   because it is the disagreement that would be the defect.

	3. AN ANCESTOR'S `scale`/`rotation` DOES NOT REACH ITS CONTENTS — TODAY, AND
	   THAT IS THE DEFECT (ADR-0032 Decision 4). Measured live through the real
	   framework: a container at `rotation = 30, scale = 1.5` with an 80x40 child
	   leaves that child 80x40 and unrotated. Not "nothing happens" — a container
	   visibly detaching from its own contents. Step 4 makes the engine carry it,
	   and when it does THIS CASE MUST GO RED. It is written to name what it is
	   holding so the reversal reads as intended rather than as breakage.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local rendererLib = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")

-- `tapAt` IS A DRIVE, NOT A QUERY, and it says so by answering `nil` when the
-- surface has no `onNodeTap` — it resolves the target, dispatches the press, and
-- only then reports who took it. So the taps below are attached with a handler and
-- record what it was given, which is also the stronger assertion: the path
-- `tapAt` RETURNS and the path the surface is TOLD about cannot drift apart.
local function render(screen: any, taps: { string }?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local root = mountLib.mount(core, screen)
	local adapter = fake_target.new()
	local controller = rendererLib.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		onNodeTap = if taps ~= nil
			then function(path: string)
				table.insert(taps, path)
			end
			else nil,
	})
	controller.initialRender()
	return adapter, controller
end

-- A GROUP AND A SIBLING AFTER IT. The group is a `canvasGroup`, which is the one
-- container shape that is ALREADY a real instance parent today — so this surface
-- exercises the nested case on the flat tree, which is the only way step 2 can
-- pin nesting's ordering before step 3 creates any more of it.
local function groupAndSibling()
	return UI.Screen({
		id = "S",
		padding = 0,
		gap = 0,
		children = {
			UI.ZStack({
				id = "Group",
				canvasGroup = true,
				children = {
					UI.Box({ id = "Inner1", surface = "raised" }),
					UI.Box({ id = "Inner2", surface = "raised" }),
				},
			}),
			UI.Box({ id = "After", surface = "raised" }),
		},
	})
end

describe("ADR-0032 D3: the depth-first z counter IS Sibling paint order", function()
	it("a parent is below its own subtree, and its subtree is below its next sibling", function()
		local adapter = render(groupAndSibling())
		local zOf = function(path: string): number
			local node = adapter.node(path)
			expect(node).never().toBeNil()
			expect(type(node.z)).toBe("number")
			return node.z
		end

		local group, inner1, inner2, after =
			zOf("/S/Group"), zOf("/S/Group/Inner1"), zOf("/S/Group/Inner2"), zOf("/S/After")

		-- a child's counter is always higher than its parent's, whatever its zIndex
		-- (`syncZOrder`'s own comment, and `Sibling`'s own rule)
		expect(group < inner1).toBe(true)
		-- declaration order among siblings
		expect(inner1 < inner2).toBe(true)
		-- ...AND THE WHOLE SUBTREE CLEARS BEFORE THE NEXT SIBLING STARTS. This is the
		-- one that makes nesting free: it is precisely what the engine does when
		-- `Group` is a real parent and `After` is its sibling under `Sibling`, so the
		-- framework's hand-computed order and the engine's tree order are the same
		-- order and neither has to be taught the other.
		expect(inner2 < after).toBe(true)
	end)

	it("the counter is strictly increasing — no two nodes share a slot", function()
		local adapter = render(groupAndSibling())
		local seen: { [number]: string } = {}
		for _, path in { "/S", "/S/Group", "/S/Group/Inner1", "/S/Group/Inner2", "/S/After" } do
			local node = adapter.node(path)
			if node ~= nil and type(node.z) == "number" then
				-- a TIE is broken by the engine's insertion order, i.e. by exactly the
				-- non-determinism the explicit walk exists to remove
				expect(seen[node.z]).toBeNil()
				seen[node.z] = path
			end
		end
	end)

	it("a zIndex lift reorders siblings and still carries its own subtree with it", function()
		local adapter = render(UI.Screen({
			id = "S",
			padding = 0,
			gap = 0,
			children = {
				UI.ZStack({
					id = "Lifted",
					zIndex = 5,
					canvasGroup = true,
					children = { UI.Box({ id = "Kid", surface = "raised" }) },
				}),
				UI.Box({ id = "Plain", surface = "raised" }),
			},
		}))
		local lifted = adapter.node("/S/Lifted").z
		local kid = adapter.node("/S/Lifted/Kid").z
		local plain = adapter.node("/S/Plain").z
		-- the lift moves `Lifted` past `Plain` in the walk...
		expect(plain < lifted).toBe(true)
		-- ...and its subtree travels with it, because the walk is depth-first over
		-- ONE counter. This is the half a host would foreclose if `zIndex` were the
		-- escape mechanism; it is not — a surface on its own DisplayOrder is
		-- (ADR-0028), which is why a host being an ordering wall costs nothing.
		expect(lifted < kid).toBe(true)
	end)
end)

describe("ADR-0032 Consequences: tapAt and the z counter cannot disagree", function()
	it("the tapped node is the one the counter puts on top", function()
		-- a ZStack overlaps its children by construction, so both boxes cover the
		-- same point and only paint order decides
		local taps: { string } = {}
		local adapter, controller = render(
			UI.Screen({
				id = "S",
				padding = 0,
				gap = 0,
				children = {
					UI.ZStack({
						id = "Stack",
						children = {
							UI.Button({ id = "Under", label = "under", onActivate = function() end }),
							UI.Button({ id = "Over", label = "over", onActivate = function() end }),
						},
					}),
				},
			}),
			taps
		)

		local under = adapter.node("/S/Stack/Under")
		local over = adapter.node("/S/Stack/Over")
		-- a point inside both
		local x = under.rect.x + 2
		local y = under.rect.y + 2

		local tapped = controller.tapAt(x, y)
		expect(tapped).toBe("/S/Stack/Over")
		-- the surface was TOLD about the same node it reported
		expect(#taps).toBe(1)
		expect(taps[1]).toBe("/S/Stack/Over")
		-- ...and that IS the higher counter. If these two ever disagree, `tapAt`'s
		-- "document order IS paint order" comment has stopped being true and a
		-- player is pressing a control they cannot see.
		expect(over.z > under.z).toBe(true)
	end)
end)

describe("ADR-0032 D4/D5: an authored transform reaches ONE node — today", function()
	local function scaledContainer()
		return UI.Screen({
			id = "S",
			padding = 0,
			gap = 0,
			children = {
				UI.ZStack({
					id = "Turned",
					scale = 1.5,
					rotation = 30,
					children = { UI.Box({ id = "Content", surface = "raised" }) },
				}),
			},
		})
	end

	it("the container carries the scale and the rotation", function()
		local adapter = render(scaledContainer())
		local turned = adapter.node("/S/Turned")
		expect(type(turned.props.transform)).toBe("table")
		expect(turned.props.transform.scale).toBeCloseTo(1.5)
		expect(turned.props.transform.rotation).toBeCloseTo(30)
	end)

	it("PINNED FOR REVERSAL (step 4): its contents do not, and that is the defect", function()
		--[[ THIS CASE IS EXPECTED TO GO RED WHEN ADR-0032 STEP 4 LANDS, and it is
			written that way deliberately. Measured live through the real framework:
			two identical ZStacks at `rotation = 30, scale = 1.5` with identical
			80x40 children — flat leaves the children 80x40 and `Rotation = 0`;
			`canvasGroup = true` makes them 120x60 riding the parent's pivot, and NO
			FRAMEWORK CODE DID THAT, the engine did.

			So the flat result is not a missing feature, it is a container visibly
			detaching from its own contents. When the step that fixes it arrives,
			this case must be UPDATED with a stated reason rather than quietly
			deleted — which is the whole point of writing it before the change.
		]]
		local adapter = render(scaledContainer())
		local content = adapter.node("/S/Turned/Content")
		-- no transform of its own: the framework writes one term on one node and
		-- never accumulates paint down the subtree (ADR-0026 Decision 7)
		expect(content.props.transform).toBeNil()
		-- ...so nothing scales its painted box either
		expect(content.presentedVisualRect).toBeNil()
	end)

	it("the POSITION half does accumulate, and that is the mechanism nesting replaces", function()
		-- `presentationShift` sums every ancestor's offset by walking the path
		-- string, stopping at the nearest real parent. It is Luau hand-computing
		-- what an engine parent gives free — every host registered shortens that
		-- walk, so the thing that makes nesting correct is the same thing that
		-- exists today to compensate for its absence.
		local adapter, controller = render(scaledContainer())
		local before = adapter.node("/S/Turned/Content").rect
		controller.setPresentationTransform("/S/Turned", { x = 17, y = -9 })
		local content = adapter.node("/S/Turned/Content")
		expect(content.presentedPosition.x).toBe(before.x + 17)
		expect(content.presentedPosition.y).toBe(before.y - 9)
		-- the SOLVER's rect never moved: a motion writes paint, never layout
		expect(content.rect.x).toBe(before.x)
	end)
end)
