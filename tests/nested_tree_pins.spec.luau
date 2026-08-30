--!strict
--[[ WHAT MUST NOT DRIFT WHILE THE TREE IS STILL FLAT.

	These are instruments, not features. The nested-tree migration is measured
	against them, and the migration is explicit about the order: they "are worth
	nothing if written after the change they are meant to catch". So every case
	below asserts what is true TODAY, on the flat tree, including the two cases
	that a later step is EXPECTED to reverse — because a pin that reddens by name
	when Decision 4 lands is the difference between a deliberate change and a
	discovered one.

	THREE THINGS, and the third is the one this spec exists for.

	1. DFS DOCUMENT ORDER IS `Sibling` ORDER. `ZIndexBehavior`
	   on every live ScreenGui is `Sibling`, measured — not `Global`, which both the
	   brief and the coordinator predicted and which the billboard verifier refuses
	   outright (a child at ZIndex 20 under a parent at 50 renders INVISIBLE, and
	   this framework pins every button icon at 20). Under `Sibling` the engine
	   paints a parent, then its subtree, then the parent's next sibling — which is
	   exactly the order `syncZOrder`'s depth-first counter already produces across
	   the flat set. That is why nesting needs no new ordering code, and this pins
	   the claim rather than leaving it in a comment.

	2. `tapAt` AND THE Z COUNTER AGREE. `tapAt`'s correctness rests on the comment
	   "last match wins: document order IS paint order" — asserted in prose, in a
	   file that does not compute paint order. `syncZOrder` is the thing that
	   computes paint order. The migration asks for this to be pinned;
	   pinning them AGAINST EACH OTHER is worth more than pinning either alone,
	   because it is the disagreement that would be the defect.

	3. AN ANCESTOR'S `scale`/`rotation` DOES NOT REACH ITS CONTENTS — TODAY, AND
	   THAT IS THE DEFECT. Measured live through the real
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
local profile = require("../src/core/profile")
local screen_presentation = require("../src/client/screen_presentation")
require("./lib/gui_value_shim").install()

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

describe("the depth-first z counter IS Sibling paint order", function()
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
		-- escape mechanism; it is not — a surface on its own DisplayOrder is, which is why a host being an ordering wall costs nothing.
		expect(lifted < kid).toBe(true)
	end)
end)

describe("tapAt and the z counter cannot disagree", function()
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

describe("the framework writes ONE node, the engine carries the subtree", function()
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

	it("UPDATED WHEN STEP 4 LANDED: the framework still writes ONE node — the engine carries it", function()
		--[[ THIS CASE WAS WRITTEN TO BE REVERSED, AND HERE IS THE REVERSAL, WITH ITS
			REASON, WHICH IS THE ONLY HONEST WAY TO CHANGE A PIN.

			It was written in step 2, while the tree was still flat, asserting that a
			container's `scale`/`rotation` reached ONE node and its contents did not
			move — measured live as two identical ZStacks at `rotation = 30,
			scale = 1.5` with identical 80x40 children, where flat left the children
			80x40 and `Rotation = 0`: a rotated plate with its contents sitting bolt
			upright beside it. Not a missing feature; a container visibly detaching
			from its own contents.

			STEP 4 CHANGED THE ENGINE'S ANSWER AND NOT THE FRAMEWORK'S, and that
			distinction is why half of this case is unchanged. The framework still
			writes exactly one term on exactly one node — the one-writer rule holds
			verbatim, and the assertion below is the same one it always was. What
			changed is that the node is now a real instance parent, so the ENGINE
			composes both terms for the subtree: an
			engine-composed descendant effect is not a second writer, because it is
			not a write to the descendant's property at all.

			SO WHAT THIS CASE CAN AND CANNOT SEE. It runs against the fake target,
			which models the framework and not the engine — it has no `Rotation`, no
			`UIScale`, and no compositor. It can prove the framework's restraint and
			the DELIVERY MECHANISM (the container is a host, the child parents under
			it), which is exactly what the case below asserts. It CANNOT prove the
			engine actually composes; that claim is live-only and is owed a Studio
			capture. Labelled here rather than implied, because a headless green that
			reads like an engine claim is how this project has shipped defects before.
		]]
		local adapter = render(scaledContainer())
		local content = adapter.node("/S/Turned/Content")
		-- unchanged, and still the point: the framework writes one term on one node
		-- and never accumulates paint down the subtree
		expect(content.props.transform).toBeNil()
		-- ...and no per-descendant scaling appeared in the framework's own model
		expect(content.presentedVisualRect).toBeNil()
	end)

	it("STEP 4: the delivery mechanism — the container became a real parent", function()
		local adapter = render(scaledContainer())
		-- THIS is what step 4 actually built. `Rotation` and `UIScale` were always
		-- written on this node's own instance; the only thing missing was that its
		-- subtree was not inside it.
		expect(adapter.isHost("/S/Turned")).toBe(true)
		expect((adapter.hostOf("/S/Turned/Content") :: any).path).toBe("/S/Turned")
		-- A PLAIN FRAME, NOT A GROUP. A CanvasGroup would compose the same two terms
		-- and charge an offscreen render buffer for it, which is a cost the live
		-- consumer already declines by name. `opacity` still needs the group —
		-- `GroupTransparency` is the only property that fades a subtree as one —
		-- so `crops` is what separates them, and a plain host crops nothing.
		expect((adapter.hostOf("/S/Turned/Content") :: any).crops).toBe(false)
	end)

	it("STEP 4 IS BOUNDED: a rotated LEAF earns nothing, and neither does an empty container", function()
		local adapter = render(UI.Screen({
			id = "S",
			padding = 0,
			gap = 0,
			children = {
				-- a leaf already rotates correctly: it has no subtree for an engine to
				-- carry anything down, so a host would cost a pool refusal to deliver
				-- nothing
				UI.Box({ id = "Leaf", surface = "raised", rotation = 30 }),
				-- ...and a container with the prop but nothing in it is the same case
				UI.ZStack({ id = "Empty", scale = 1.5, children = {} }),
				-- ...and a container with children but NEITHER prop is untouched,
				-- which is what makes step 4 additive
				UI.ZStack({ id = "Ordinary", children = { UI.Box({ id = "Kid", surface = "raised" }) } }),
			},
		}))
		expect(adapter.isHost("/S/Leaf")).toBe(false)
		expect(adapter.isHost("/S/Empty")).toBe(false)
		expect(adapter.isHost("/S/Ordinary")).toBe(false)
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

describe("a host's rect lands BEFORE its descendants', or they re-base against a ghost", function()
	--[[ FOUND LIVE, 2026-08-17, and it is the reason the arrange win was not being
		delivered. Measured in Studio on a 120-node list inside a `ScrollView` whose
		container grew 40px: **240 engine `Position` changes across 120 descendants**
		— two each — with the minimal-write contract already in. `GetPropertyChangedSignal`
		fires only on a real VALUE change, so these were not redundant writes the
		skip should have caught. They were two DIFFERENT values:

		    1. cell   -> y = 60     WRONG: its new window rect against the host's OLD origin
		    2. list   -> y = 60     the host finally moves, and its entry origin updates
		    3. cell   -> y = 20     corrected, when the host re-bases its own children

		The net change is zero — which is exactly what the parent-relative argument
		predicts — but the path pays 2N writes to get there and, for one moment,
		every descendant of a moved container is drawn in the wrong place. A frame
		landing between 1 and 3 shows the whole subtree jump.

		THE CAUSE IS AN UNORDERED ITERATION, and the renderer's own comment named it
		before anyone connected it to this: the rect loop ran `for path, entry in
		result.rects do` over a hash, described two lines above as "the unordered
		rect hash below". A descendant reached before its host re-bases against an
		origin that has not moved yet. The adapter compensated by having a host
		re-base every child on its own `setRect` — which is why the value is
		eventually right, and why it costs twice.

		SO THIS PINS THE ORDER RATHER THAN THE COUNT, because the count is an engine
		fact this target cannot see. Document order is ancestors-first by
		construction, so every host's own rect must be written before any rect
		beneath it. The count is measured live, in
		artifacts/nested-instance-tree/live-probes.md.
	]]
	local function hostOrderProblems(adapter: any): { string }
		local seenRectAt: { [string]: number } = {}
		local i = 0
		for _, op in adapter.ops() do
			local path = string.match(op, "^rect (%S+)")
			if path ~= nil then
				i += 1
				if seenRectAt[path] == nil then
					seenRectAt[path] = i
				end
			end
		end
		local problems: { string } = {}
		for path, at in seenRectAt do
			for other, otherAt in seenRectAt do
				-- `other` is a strict descendant of `path`
				if other ~= path and string.sub(other, 1, #path + 1) == path .. "/" then
					if adapter.isHost(path) and otherAt < at then
						table.insert(problems, `{other} (op {otherAt}) was placed before its host {path} (op {at})`)
					end
				end
			end
		end
		return problems
	end

	it("on a first render, every host is placed before anything inside it", function()
		local rows: { any } = {}
		for i = 1, 6 do
			table.insert(
				rows,
				UI.HStack({
					id = `R{i}`,
					children = {
						UI.Box({ id = "A", surface = "raised" }),
						UI.Box({ id = "B", surface = "raised" }),
					},
				})
			)
		end
		local adapter = render(UI.Screen({
			id = "S",
			padding = 0,
			gap = 0,
			children = {
				UI.Box({ id = "Head", surface = "raised" }),
				UI.ScrollView({ id = "List", children = rows }),
			},
		}))
		local problems = hostOrderProblems(adapter)
		expect(#problems).toBe(0)
	end)

	it("...and a NESTED host is placed before its own subtree too", function()
		local adapter = render(UI.Screen({
			id = "S",
			padding = 0,
			gap = 0,
			children = {
				UI.ScrollView({
					id = "Outer",
					children = {
						UI.ZStack({
							id = "Group",
							canvasGroup = true,
							children = {
								UI.Box({ id = "Deep", surface = "raised" }),
								UI.Box({ id = "Deeper", surface = "raised" }),
							},
						}),
					},
				}),
			},
		}))
		-- both hosts, and the deeper one is inside the outer one
		expect(adapter.isHost("/S/Outer")).toBe(true)
		expect(adapter.isHost("/S/Outer/Group")).toBe(true)
		expect(#hostOrderProblems(adapter)).toBe(0)
	end)
end)

describe("a layout-only frame does not open a commit scope that commits nothing", function()
	--[[ FOUND IN THE DEVICE CAPTURES, 2026-08-17, and it is a measurement error as
		much as a cost.

		`Facet/commit` names TWO different passes on purpose — the adapter commit
		after a solve (rects, visibility, z-order, transforms) and the paint/semantics
		PROP-WRITE pass — because "is the framework's output cheap relative to its
		solve" is better answered by one bar than by eight. Fine. But the prop pass
		was guarded on `#dirty > 0`, which asks "is there dirt", not "is there dirt I
		will act on".

		MEASURED on the `host-move` workload, whose rep changes exactly one LAYOUT
		prop (the header's height): **0.00 prop writes per rep over 24 reps**, while
		`commit` opened 2.07 times per frame in every device capture. Half of every
		`commit` occurrence was this pass, walking the dirty list and writing nothing
		— which is precisely the annotation overhead the guard's own comment warns
		about, arriving THROUGH the guard rather than past it. It also diluted the
		round's own headline: the −18.9 % measured on `commit` mixes a pass that does
		the work with one that cannot.

		So the guard now asks the real question. The loop body is only ever
		paint/semantics writes, so "no paint/semantics entry" and "this loop is a
		no-op" are the same statement, and skipping it cannot change behaviour.
	]]
	local function withRecorder<T>(fn: (log: { string }) -> T): T
		local log: { string } = {}
		profile.resetCounters()
		profile.setEnabled(true)
		profile.setHooks(function(label: string)
			table.insert(log, label)
		end, function() end)
		local ok, result = pcall(fn, log)
		profile.setHooks(nil, nil)
		profile.setEnabled(false)
		profile.resetCounters()
		if not ok then
			error(result, 0)
		end
		return result :: T
	end

	local function countCommits(log: { string }): number
		local n = 0
		for _, label in log do
			if label == "Facet/commit" then
				n += 1
			end
		end
		return n
	end

	it("a LAYOUT-only change opens commit once, and writes no props", function()
		local core = customFactory.new()
		local tall = core:signal(true)
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				padding = 0,
				gap = 0,
				children = {
					UI.Box({
						id = "Header",
						surface = "raised",
						height = core:memo(function(use)
							return { type = "fixed", px = if use(tall) then 60 else 20 }
						end),
					}),
					UI.Box({ id = "Body", surface = "raised" }),
				},
			})
		)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local before = controller.stats().propWrites

		local commits = withRecorder(function(log)
			tall:set(false)
			controller.refresh()
			return countCommits(log)
		end)

		-- the frame really did nothing paint-shaped, which is what makes the
		-- second scope unearned rather than merely cheap
		expect(controller.stats().propWrites - before).toBe(0)
		-- ...and the geometry really did change, or this proves nothing at all
		expect(adapter.node("/S/Body").rect.y).toBe(20)
		expect(commits).toBe(1)
	end)

	it("NEGATIVE CONTROL: a PAINT change still opens the prop pass", function()
		local core = customFactory.new()
		local label = core:signal("one")
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				padding = 0,
				gap = 0,
				children = { UI.Text({ id = "T", text = core:memo(function(use)
					return use(label)
				end) }) },
			})
		)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local before = controller.stats().propWrites
		local commits = withRecorder(function(log)
			label:set("two")
			controller.refresh()
			return countCommits(log)
		end)
		-- without this case, "never open the second scope" would pass everything
		expect(controller.stats().propWrites - before > 0).toBe(true)
		expect(commits).toBe(2)
	end)
end)

describe("a scale that went back to 1 must come back — the UIScale corpse", function()
	--[[ FOUND ON A PHYSICAL DEVICE by the director, 2026-08-17: press Turn on the
		nested-compositing demo, turn it off, turn it on again, and the scale does
		not come back. Rotation does, because that is a direct property on the
		instance; scale does not, because it needs a `UIScale` CHILD.

		REPRODUCED IN STUDIO through the real presenter, and the numbers name it:

		    TURN1  Carried Abs=150x105  UIScale=1.500 x1   Plate 105x60  Marker 30x30
		    REST2  Carried Abs=100x70   UIScale=none  x0   Plate  70x40  Marker 20x20
		    TURN2  Carried Abs=100x70   UIScale=none  x0   Plate  70x40  Marker 20x20
		                   ^^^^^^^^^^^ turned, rotated 30 degrees, and NOT SCALED

		THE ROOT CAUSE IS A CORPSE IN A HANDLE FIELD, the same family as the
		instance-pool corpse this repo already has a spec for. `screen_paint`'s
		`ensureScale` records the instance it makes on `handle.uiScale`;
		`applyPresentationPaint` then records the SAME instance on
		`handle.motionScale`. Two fields, one object. Going back to scale 1
		destroys the object and clears `motionScale` — and leaves `uiScale`
		pointing at the destroyed one.

		The next scale then reads `handle.motionScale or handle.uiScale`, finds the
		corpse, decides an instance already exists, and writes `Scale = 1.5` to it.
		A destroyed instance ACCEPTS EVERY WRITE EXCEPT A NON-NIL PARENT — this
		codebase states that verbatim in `parkEligible`'s corpse gate — so the write
		succeeds, silently, onto something that is not in the tree.

		WHY IT MATTERS BEYOND THIS DEMO: any authored `scale` that is ever animated
		to 1 and back is affected, and since nesting that now includes a container
		whose whole subtree rides the term. The failure is silent in both
		directions — nothing errors, and the node simply stops scaling.
	]]
	local function harness()
		local handlesByPath: { [string]: any } = {}
		local made: { any } = {}
		-- a stand-in for screen_paint's lazy UIScale, mimicking the real one's TWO
		-- recording sites: it sets `handle.uiScale`, and the caller sets
		-- `handle.motionScale` to the same object. That duplication IS the bug's
		-- shape, so a harness that models only one field would prove nothing.
		local function ensureScale(_instance: any, handle: any): any
			local existing = handle.motionScale or handle.uiScale
			if existing ~= nil then
				return existing
			end
			local obj = { Scale = 1, dead = false }
			function obj.Destroy(self: any)
				self.dead = true
			end
			handle.uiScale = obj
			table.insert(made, obj)
			return obj
		end
		local region = screen_presentation.new({
			handlesByPath = handlesByPath,
			refitIconArt = function() end,
			ensureScale = ensureScale,
		})
		-- the node's own instance: `applyPresentationPaint` guards on `IsA("GuiObject")`
		-- and writes `Rotation` / `AnchorPoint`, so the stand-in answers both
		local instance: any = {
			Rotation = 0,
			AnchorPoint = false,
			IsA = function(_self: any, class: string): boolean
				return class == "GuiObject"
			end,
		}
		local handle = {
			path = "/S/Turned",
			instance = instance,
			windowRect = { x = 0, y = 0, w = 100, h = 70 },
		}
		handlesByPath["/S/Turned"] = handle
		return region, handle, made
	end

	it("turn on, off, and on again: the scale is live and carries its value", function()
		local region, handle, made = harness()

		region.setTransform(handle, { scale = 1.5, rotation = 30 })
		expect(#made).toBe(1)
		expect(made[1].Scale).toBeCloseTo(1.5)

		region.setTransform(handle, nil)
		expect(made[1].dead).toBe(true)

		region.setTransform(handle, { scale = 1.5, rotation = 30 })
		-- the corpse must not be reused. Either a NEW instance was made, or the old
		-- one was somehow revived — the only thing that matters is that whatever the
		-- node is scaling by now is ALIVE and carries the value.
		local live = handle.motionScale or handle.uiScale
		expect(live).never().toBeNil()
		expect((live :: any).dead).toBe(false)
		expect((live :: any).Scale).toBeCloseTo(1.5)
	end)

	it("...and the fields do not keep a destroyed instance after the scale clears", function()
		local region, handle, made = harness()
		region.setTransform(handle, { scale = 1.5 })
		region.setTransform(handle, nil)
		expect(made[1].dead).toBe(true)
		-- NEITHER field may hold the corpse. This is the assertion the fix is
		-- actually about; the case above is what a player sees when it is wrong.
		expect(handle.motionScale).toBeNil()
		expect(handle.uiScale).toBeNil()
	end)
end)
