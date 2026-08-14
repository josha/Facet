--!strict
-- THE PER-NODE PRESENTATION CHANNEL (ADR-0022 Decision 2; acceptance row SF-M9).
--
-- The channel existed on paper before this stage: the authority manifest declared
-- `transform`/`transparency` as presentation properties, the presenter drove the
-- keyboard keep-visible shift through `setPresentationOffset`, FakeTarget recorded
-- the prop, and every headless assertion passed. `screen_target.setProp` had no
-- branch for either name, so on a device the shift never landed — a
-- headless-green/live-broken channel that shipped for as long as the feature did.
--
-- So this spec proves BOTH halves: the composition rule (headless, through the
-- fake adapter's structural mirror) and the live adapter's implementation of it
-- (source contracts — screen_target is client-only and cannot be required under
-- Lune, which is precisely why the parity conformance in
-- render_target_contract.spec exists alongside these).

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local rendererLib = require("../src/render/renderer")
local authority = require("../src/render/authority")
local fake_target = require("./lib/fake_target")

local adapterSource = fs.readFile("src/client/screen_target.luau")

local function render(screen: any, w: number?, h: number?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = w or 400, h = h or 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local root = mountLib.mount(core, screen)
	local adapter = fake_target.new()
	local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return adapter, controller, core, env
end

local function fails(fn: () -> ()): string
	local ok, err = pcall(fn)
	expect(ok).toBe(false)
	return tostring(err)
end

local function screen()
	return UI.Screen({
		id = "S",
		padding = 0,
		gap = 0,
		children = {
			UI.Box({ id = "Panel", surface = "raised", height = { type = "fixed", px = 100 }, children = nil }),
			UI.Text({ id = "Label", text = "Row" }),
		},
	})
end

describe("presentation transform: composition onto the solved rect", function()
	it("a transform on a leaf offsets its painted position and leaves the rect alone", function()
		local adapter, controller = render(screen())
		local before = adapter.node("/S/Label").rect
		controller.setPresentationTransform("/S/Label", { x = 12, y = -30 })
		local node = adapter.node("/S/Label")
		-- the SOLVER's rect is untouched: a motion never writes layout geometry
		expect(node.rect.x).toBe(before.x)
		expect(node.rect.y).toBe(before.y)
		expect(node.presentedPosition.x).toBe(before.x + 12)
		expect(node.presentedPosition.y).toBe(before.y - 30)
	end)

	it("nil clears the transform and the node returns to its solved position", function()
		local adapter, controller = render(screen())
		local before = adapter.node("/S/Label").rect
		controller.setPresentationTransform("/S/Label", { x = 0, y = -40 })
		expect(adapter.node("/S/Label").presentedPosition.y).toBe(before.y - 40)
		controller.setPresentationTransform("/S/Label", nil)
		expect(adapter.node("/S/Label").presentedPosition.y).toBe(before.y)
	end)

	it("a RECT WRITE re-applies the stored transform (a re-solve never drops a motion)", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local label = core:signal("Row")
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				padding = 0,
				gap = 0,
				children = {
					UI.Text({ id = "Head", text = label }),
					UI.Text({ id = "Label", text = "Row" }),
				},
			})
		)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		controller.setPresentationTransform("/S/Label", { x = 0, y = -25 })
		local shifted = adapter.node("/S/Label").presentedPosition.y
		-- a text change above re-solves and moves the row's rect: the offset must
		-- still be composed into the new position, not lost with the old one
		label:set("A much longer heading that wraps onto a second line in this box")
		controller.refresh()
		local node = adapter.node("/S/Label")
		expect(node.presentedPosition.y).toBe(node.rect.y - 25)
		expect(node.presentedPosition.y ~= shifted).toBe(true)
	end)

	it("a settled motion re-asserting its value costs no adapter write (minimal writes)", function()
		local adapter, controller = render(screen())
		controller.setPresentationTransform("/S/Label", { x = 0, y = -10 })
		adapter.takeOps()
		controller.setPresentationTransform("/S/Label", { x = 0, y = -10 })
		controller.setPresentationTransform("/S/Label", { x = 0, y = -10 })
		expect(#adapter.takeOps()).toBe(0)
	end)

	it("scale materializes a named transient UIScale and removes it at rest", function()
		local adapter, controller = render(screen())
		controller.setPresentationTransform("/S/Panel", { x = 0, y = 0, scale = 0.96 })
		local live = adapter.node("/S/Panel").motionScaleInstance
		expect(live ~= nil).toBe(true)
		expect(live.name).toBe(authority.INSTANCE_NAMES.motionScale)
		expect(live.scale).toBe(0.96)
		controller.setPresentationTransform("/S/Panel", { x = 0, y = 0, scale = 1 })
		expect(adapter.node("/S/Panel").motionScaleInstance).toBeNil()
	end)

	it("scale pivots on the node's CENTER: the visual rect inflates in place", function()
		-- director fix round (RR parity): the live adapter re-anchors a
		-- motion-scaled instance to (0.5, 0.5), so a pop grows from the middle —
		-- never crawling down-right from the top-left. The fake records the same
		-- composed fact as `presentedVisualRect`.
		local adapter, controller = render(screen())
		local node = adapter.node("/S/Panel")
		local r = node.rect
		controller.setPresentationTransform("/S/Panel", { x = 0, y = 0, scale = 1.5 })
		local v = adapter.node("/S/Panel").presentedVisualRect
		expect(v ~= nil).toBe(true)
		expect(v.w).toBe(r.w * 1.5)
		expect(v.h).toBe(r.h * 1.5)
		-- the CENTER did not move
		expect(v.x + v.w / 2).toBe(r.x + r.w / 2)
		expect(v.y + v.h / 2).toBe(r.y + r.h / 2)
		controller.setPresentationTransform("/S/Panel", nil)
		expect(adapter.node("/S/Panel").presentedVisualRect).toBeNil()
	end)

	it("rotation is recorded as paint and never as geometry", function()
		local adapter, controller = render(screen())
		local before = adapter.node("/S/Panel").rect
		controller.setPresentationTransform("/S/Panel", { x = 0, y = 0, rotation = 8 })
		expect(adapter.node("/S/Panel").rotation).toBe(8)
		expect(adapter.node("/S/Panel").rect.w).toBe(before.w)
		controller.setPresentationTransform("/S/Panel", nil)
		expect(adapter.node("/S/Panel").rotation).toBe(0)
	end)

	it("the write asserts the PRESENTATION authority for the node's own class", function()
		-- the manifest is the contract; a writer claiming a property it does not own
		-- is an error rather than a silent win
		expect(authority.authorityFor("Box", "transform")).toBe("presentation")
		expect(authority.authorityFor("Text", "transparency")).toBe("presentation")
		expect(authority.authorityFor("Screen", "transform")).toBe("presentation")
	end)

	it("an unmounted path is a no-op, not an error (a motion may outlive its node)", function()
		local _, controller = render(screen())
		controller.setPresentationTransform("/S/Gone", { x = 0, y = -10 })
		controller.setPresentationTransparency("/S/Gone", 0.5)
	end)
end)

describe("presentation transform: the keep-visible root shift (SF-M9)", function()
	it("setPresentationOffset composes onto the ROOT's painted position", function()
		local adapter, controller = render(screen())
		local rootRect = adapter.node("/S").rect
		controller.setPresentationOffset(120)
		local node = adapter.node("/S")
		expect(node.props.transform.y).toBe(-120)
		expect(node.presentedPosition.y).toBe(rootRect.y - 120)
	end)

	it("...and onto every node in the surface, which is what makes it visible at all", function()
		-- THE DEFECT'S ROOT CAUSE. On the client the instance tree is FLAT
		-- (docs/lessons/screen-target-tree-is-flat.md), so shifting the root node's
		-- own instance moves one transparent frame. The offset has to reach the
		-- subtree, and this is the assertion that says so.
		local adapter, controller = render(screen())
		local labelRect = adapter.node("/S/Label").rect
		local panelRect = adapter.node("/S/Panel").rect
		controller.setPresentationOffset(90)
		expect(adapter.node("/S/Label").presentedPosition.y).toBe(labelRect.y - 90)
		expect(adapter.node("/S/Panel").presentedPosition.y).toBe(panelRect.y - 90)
	end)

	it("dy = 0 restores: the transform is written as zero, not cleared", function()
		-- the presenter's own specs read `props.transform.y == 0` back as "restored"
		local adapter, controller = render(screen())
		local labelRect = adapter.node("/S/Label").rect
		controller.setPresentationOffset(60)
		controller.setPresentationOffset(0)
		expect(adapter.node("/S").props.transform.y).toBe(0)
		expect(adapter.node("/S/Label").presentedPosition.y).toBe(labelRect.y)
	end)

	it("a node created UNDER a live shift starts composed (no one-frame jump)", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local show = core:signal(false)
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				padding = 0,
				gap = 0,
				children = {
					UI.Text({ id = "Head", text = "Head" }),
					UI.When({
						id = "Later",
						condition = show,
						thenView = function()
							return UI.Text({ id = "Row", text = "Row" })
						end,
					}),
				},
			})
		)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		controller.setPresentationOffset(70)
		show:set(true)
		controller.refresh()
		local node = adapter.node("/S/Later/then/Row")
		expect(node ~= nil).toBe(true)
		expect(node.presentedPosition.y).toBe(node.rect.y - 70)
	end)

	it("a removed node forgets its transform, so a re-created path starts at rest", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local show = core:signal(true)
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				padding = 0,
				gap = 0,
				children = {
					UI.When({
						id = "Gate",
						condition = show,
						thenView = function()
							return UI.Text({ id = "Row", text = "Row" })
						end,
					}),
				},
			})
		)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		controller.setPresentationTransform("/S/Gate/then/Row", { x = 0, y = -50 })
		show:set(false)
		controller.refresh()
		show:set(true)
		controller.refresh()
		local node = adapter.node("/S/Gate/then/Row")
		-- the cache must have been dropped with the node: a stale "already -50"
		-- verdict would suppress the write that puts the new instance at rest
		expect(node.presentedPosition.y).toBe(node.rect.y)
		controller.setPresentationTransform("/S/Gate/then/Row", { x = 0, y = -50 })
		expect(adapter.node("/S/Gate/then/Row").presentedPosition.y).toBe(node.rect.y - 50)
	end)
end)

describe("presentation transparency: the declared fade group", function()
	local function groupScreen()
		return UI.Screen({
			id = "S",
			padding = 0,
			gap = 0,
			children = {
				UI.Box({
					id = "Group",
					canvasGroup = true,
					height = { type = "fixed", px = 80 },
				}),
				UI.Text({ id = "Plain", text = "Plain" }),
			},
		})
	end

	it("a declared canvasGroup node becomes a fade group and takes GroupTransparency", function()
		local adapter, controller = render(groupScreen())
		local group = adapter.node("/S/Group")
		expect(group.canvasGroupInstance ~= nil).toBe(true)
		expect(group.canvasGroupInstance.className).toBe("CanvasGroup")
		controller.setPresentationTransparency("/S/Group", 0.4)
		expect(adapter.node("/S/Group").canvasGroupInstance.groupTransparency).toBe(0.4)
		controller.setPresentationTransparency("/S/Group", nil)
		expect(adapter.node("/S/Group").canvasGroupInstance.groupTransparency).toBe(0)
	end)

	it("fading an UNDECLARED node is refused, and the error names the fix", function()
		local _, controller = render(groupScreen())
		local err = fails(function()
			controller.setPresentationTransparency("/S/Plain", 0.5)
		end)
		expect(string.find(err, "canvasGroup = true", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "GroupTransparency", 1, true) ~= nil).toBe(true)
	end)

	it("the declaration is not reactive and rejects a Signal at construction", function()
		local core = customFactory.new()
		local err = fails(function()
			UI.Box({ id = "G", canvasGroup = core:signal(true) })
		end)
		expect(string.find(err, "does not accept a Signal/Memo", 1, true) ~= nil).toBe(true)
	end)

	it("GroupTransparency is NOT a native-sheet-owned property (that is the whole point)", function()
		-- the fade never contests sheet paint, which per-node transparency writes
		-- (BackgroundTransparency / TextTransparency) permanently would
		expect(authority.nativeSheetOwned("GroupTransparency")).toBe(false)
		expect(authority.nativeSheetOwned("BackgroundTransparency")).toBe(true)
		expect(authority.nativeSheetOwned("TextTransparency")).toBe(true)
	end)
end)

describe("screen_target: the presentation channel (source contract)", function()
	it("setProp handles BOTH presentation prop names (the SF-M9 branches)", function()
		expect(string.find(adapterSource, 'prop == "transform"', 1, true) ~= nil).toBe(true)
		expect(string.find(adapterSource, 'prop == "transparency"', 1, true) ~= nil).toBe(true)
	end)

	-- the window is generous on purpose: it exists to prove the composition is IN
	-- `applyRect`, not to pin how many bytes of comment sit above it. A 900-byte
	-- window went red on a comment edit, which is a check reporting on the wrong
	-- thing.
	local function applyRectBody(): string
		local from = string.find(adapterSource, "local function applyRect(handle: any)", 1, true)
		expect(from ~= nil).toBe(true)
		local stop = string.find(adapterSource, "\n\tend", from :: number, true)
		return string.sub(adapterSource, from :: number, if stop ~= nil then stop else (from :: number) + 2000)
	end

	it("applyRect — the ONE Position write — composes the presentation offset", function()
		local body = applyRectBody()
		expect(string.find(body, "handle.instance.Position = UDim2.fromOffset(", 1, true) ~= nil).toBe(true)
		expect(string.find(body, "handle.presentationOffsetX or 0", 1, true) ~= nil).toBe(true)
		expect(string.find(body, "handle.presentationOffsetY or 0", 1, true) ~= nil).toBe(true)
	end)

	--[[ THE SIZE HALF (withAnimation size, 2026-08-14).

		`applyRect` is the ONE place an engine `Size` is written, exactly as it is
		the one place a `Position` is. That is what lets a painted size delta
		compose at the write instead of anywhere near the solver — the whole
		reason the round-2 deferral's "adding a size channel means touching
		applyRect's four passengers" turned out to be the wrong worry: those
		passengers already run on every frame of a POSITION flight.

		Source contract, not behaviour: the behavioural proof is
		tests/with_animation.spec's size block against the fake adapter. This one
		exists because the fake adapter cannot see the real `UDim2` write, and a
		Lune suite has never once executed this file. ]]
	it("applyRect — the ONE Size write — composes the presentation SIZE delta", function()
		local body = applyRectBody()
		expect(string.find(body, "rect.w + (handle.presentationSizeW or 0)", 1, true) ~= nil).toBe(true)
		expect(string.find(body, "rect.h + (handle.presentationSizeH or 0)", 1, true) ~= nil).toBe(true)
		-- and the write itself uses the composed extent, not the raw rect
		expect(string.find(body, "handle.instance.Size = UDim2.fromOffset(pw, ph)", 1, true) ~= nil).toBe(true)
	end)

	it("the SIZE half does NOT accumulate — one own-path lookup, never an ancestor walk", function()
		local from = string.find(adapterSource, "local function recomputePresentationOffset(handle: any)", 1, true)
		expect(from ~= nil).toBe(true)
		local stop = string.find(adapterSource, "\n\tend", from :: number, true)
		local body = string.sub(adapterSource, from :: number, if stop ~= nil then stop else (from :: number) + 2400)
		-- the size delta comes from THIS node's own transform...
		expect(string.find(body, "presentationTransforms[handle.path]", 1, true) ~= nil).toBe(true)
		expect(string.find(body, "handle.presentationSizeW", 1, true) ~= nil).toBe(true)
		expect(string.find(body, "handle.presentationSizeH", 1, true) ~= nil).toBe(true)
		-- ...and the ancestor loop is the OFFSET's alone: `ox`/`oy` are the only
		-- things it adds to. A `sw +=` or `sh +=` inside that walk would mean every
		-- child of a growing panel inflated with it.
		expect(string.find(body, "sw +=", 1, true)).toBe(nil)
		expect(string.find(body, "sh +=", 1, true)).toBe(nil)
	end)

	it("the offset ACCUMULATES down the subtree, because the instance tree is flat", function()
		local from = string.find(adapterSource, "local function recomputePresentationOffset(handle: any)", 1, true)
		expect(from ~= nil).toBe(true)
		local body = string.sub(adapterSource, from :: number, (from :: number) + 1200)
		-- ancestors contribute...
		expect(string.find(body, "presentationTransforms[ancestor]", 1, true) ~= nil).toBe(true)
		-- ...and a REAL PARENT stops the walk, since its own move carries its children
		expect(string.find(body, "handle.clipHost", 1, true) ~= nil).toBe(true)
		-- the transform write re-places the whole subtree
		local write = string.find(adapterSource, 'elseif prop == "transform" then', 1, true)
		expect(write ~= nil).toBe(true)
		local writeBody = string.sub(adapterSource, write :: number, (write :: number) + 1600)
		expect(string.find(writeBody, "recomputePresentationOffset(other)", 1, true) ~= nil).toBe(true)
		expect(string.find(writeBody, "applyRect(other)", 1, true) ~= nil).toBe(true)
	end)

	it("a running motion re-places its SUBTREE, not the whole target", function()
		-- a motion writes every frame while it runs, so the per-write cost has to be
		-- the subtree's size and not the target's. The index is derived from the handle
		-- map and dropped on any structural change rather than patched.
		local from = string.find(adapterSource, "local function subtreeOf(path: string): { any }", 1, true)
		expect(from ~= nil).toBe(true)
		local body = string.sub(adapterSource, from :: number, (from :: number) + 700)
		expect(string.find(body, "subtreeCache[path]", 1, true) ~= nil).toBe(true)
		local write = string.find(adapterSource, 'elseif prop == "transform" then', 1, true)
		local writeBody = string.sub(adapterSource, write :: number, (write :: number) + 1200)
		expect(string.find(writeBody, "subtreeOf(handle.path)", 1, true) ~= nil).toBe(true)
		-- FIVE invalidation sites: create, remove, whole-root teardown, and the two
		-- halves of instance recycling (park takes a node out of the tree, adopt puts
		-- one back under a new path). Both are structural changes to the flat tree, so
		-- both must drop the derived subtree index — a recycled node that kept a stale
		-- entry would re-place some other node's subtree on the next transform write.
		local invalidations = 0
		for _ in string.gmatch(adapterSource, "subtreeCache = {}") do
			invalidations += 1
		end
		expect(invalidations).toBe(5)
	end)

	it("the hit expander travels with the paint (a shifted control stays pressable)", function()
		local from = string.find(adapterSource, "local function applyHitExpander(handle: any)", 1, true)
		expect(from ~= nil).toBe(true)
		local body = string.sub(adapterSource, from :: number, (from :: number) + 900)
		expect(string.find(body, "handle.presentationOffsetX or 0", 1, true) ~= nil).toBe(true)
	end)

	it("the motion scale SHARES the press dip's UIScale (the engine honours one)", function()
		local from = string.find(adapterSource, "local function applyPresentationPaint(handle: any, t: any)", 1, true)
		expect(from ~= nil).toBe(true)
		local body = string.sub(adapterSource, from :: number, (from :: number) + 1200)
		expect(string.find(body, "handle.motionScale or handle.uiScale", 1, true) ~= nil).toBe(true)
		-- The naming used to live here. It now lives in `ensureScale`, which is the
		-- SINGLE place either path creates a UIScale — the press dip creates one lazily
		-- on first press, so a second creation site would be exactly how the engine ends
		-- up with two and honours neither. Pinning "one creation site" is stronger than
		-- pinning where the name is written.
		expect(string.find(body, "ensureScale(instance, handle)", 1, true) ~= nil).toBe(true)
		local _, creations = string.gsub(adapterSource, 'Instance%.new%("UIScale"%)', "")
		-- ensureScale, plus the focus ring's own scale, and nothing else
		expect(creations).toBe(2)
		local ensureFrom = string.find(adapterSource, "local function ensureScale(", 1, true)
		expect(ensureFrom ~= nil).toBe(true)
		local ensureBody = string.sub(adapterSource, ensureFrom :: number, (ensureFrom :: number) + 600)
		expect(string.find(ensureBody, "authority.INSTANCE_NAMES.motionScale", 1, true) ~= nil).toBe(true)
		expect(string.find(ensureBody, "handle.motionScale or handle.uiScale", 1, true) ~= nil).toBe(true)
	end)

	it("an invisible hairline is not built at all (modifier elision)", function()
		-- A `UIStroke` with zero thickness or full transparency draws nothing, so
		-- creating one is a pure instance cost. Both shipped themes keep hairlines
		-- visible, so this saves nothing on them — the guard is for a theme package
		-- that turns them off, which would otherwise pay ~30 invisible strokes per
		-- five rows on the shape measured in the performance lab.
		--
		-- SOURCE-SHAPE, and said so: the fake target does not build engine modifiers,
		-- so a headless test cannot count real `UIStroke` instances. What is pinned is
		-- that the guard exists and runs BEFORE construction — an elision checked
		-- after `Instance.new` would save nothing.
		local from = string.find(adapterSource, "local function hairlineWouldShow(): boolean", 1, true)
		expect(from ~= nil).toBe(true)
		local guard = string.sub(adapterSource, from :: number, (from :: number) + 500)
		expect(string.find(guard, "thickness <= 0", 1, true) ~= nil).toBe(true)
		expect(string.find(guard, "opacity >= 1", 1, true) ~= nil).toBe(true)

		local hf = string.find(adapterSource, "local function hairline(instance: Instance", 1, true)
		expect(hf ~= nil).toBe(true)
		local body = string.sub(adapterSource, hf :: number, (hf :: number) + 400)
		local guardAt = string.find(body, "if not hairlineWouldShow() then", 1, true)
		local buildAt = string.find(body, 'Instance.new("UIStroke")', 1, true)
		expect(guardAt ~= nil).toBe(true)
		expect(buildAt ~= nil).toBe(true)
		expect((guardAt :: number) < (buildAt :: number)).toBe(true)
	end)

	it("a fade group is created as a CanvasGroup, capability-probed, and is a real parent", function()
		expect(string.find(adapterSource, 'instanceClass = "CanvasGroup"', 1, true) ~= nil).toBe(true)
		expect(string.find(adapterSource, "hasCanvasGroup", 1, true) ~= nil).toBe(true)
		local from = string.find(adapterSource, 'if instance:IsA("CanvasGroup") then', 1, true)
		expect(from ~= nil).toBe(true)
		local body = string.sub(adapterSource, from :: number, (from :: number) + 1400)
		-- the real-parent record (which is what re-bases the subtree into it)
		expect(string.find(body, "clipHosts[path] =", 1, true) ~= nil).toBe(true)
		-- ...and the DECLARED CLAIM that keeps its own plate invisible in native mode,
		-- where no class-default rule selects a CanvasGroup
		expect(string.find(body, 'claimPaint(handle, "BackgroundTransparency")', 1, true) ~= nil).toBe(true)
	end)

	it("teardown drops the transform record, the real-parent entry and both instances", function()
		local from = string.find(adapterSource, "function adapter.remove(handle: any)", 1, true)
		expect(from ~= nil).toBe(true)
		local body = string.sub(adapterSource, from :: number, (from :: number) + 1600)
		expect(string.find(body, "presentationTransforms[handle.path] = nil", 1, true) ~= nil).toBe(true)
		expect(string.find(body, "presentationCount -= 1", 1, true) ~= nil).toBe(true)
		expect(string.find(body, "clipHosts[handle.path] = nil", 1, true) ~= nil).toBe(true)
		expect(string.find(body, "handle.motionScale:Destroy()", 1, true) ~= nil).toBe(true)
		expect(string.find(body, "handle.strokeInstance:Destroy()", 1, true) ~= nil).toBe(true)
	end)
end)
