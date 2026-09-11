--!strict
--[[ A SCALE-ONLY TRANSFORM WRITE IS ONE NODE'S PAINT, NOT A SUBTREE RE-APPLY
	(perf round 2026-09-11).

	Every frame of a `materialize` transition (a Picker menu popover, a radial
	menu's rings, any `withAnimation` scale) writes a presentation transform whose
	OFFSET half — x, y, w, h — is unchanged and whose SCALE moved. The live
	adapter's `setTransform` re-walked the node's whole subtree on every such
	write (`recomputePresentationOffset` + `applyRect` per descendant), and the
	headless mirror re-composed every node in the tree. Attributed headless on the
	`picker-menu-open-close` scene: 33 writes x ~57 us on a six-row popover, half
	the scene; on a phone that is the per-frame bill of every pop-up menu's fade.

	The rule both adapters now follow: a descendant's composed position depends
	ONLY on the offset half of its ancestors' transforms (scale and rotation are
	paint on the node's own instance — the UIScale child and `Rotation`), so a
	write that leaves the offset half where it was re-applies the node itself
	(its anchor may flip at the first non-1 scale) and nothing below it. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local fake_target = require("./lib/fake_target")
local adapter_source = require("./lib/adapter_source")

local ROWS = 12

local function world()
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local UI = Facet.UI
	local rows = {}
	for i = 1, ROWS do
		table.insert(rows, UI.Text({ id = `R{i}`, text = `Row {i}` }))
	end
	local screen = UI.Screen({
		id = "S",
		padding = 0,
		gap = 0,
		children = {
			UI.ZStack({
				id = "Group",
				canvasGroup = true,
				height = { type = "fixed", px = 300 },
				children = { UI.VStack({ id = "Rows", gap = 2, children = rows }) },
			}),
		},
	})
	local handle = pres.present(screen)
	pres.refresh()
	return { adapter = adapter, pres = pres, handle = handle }
end

describe("presentation transform: a scale-only write re-applies one node, an offset write the subtree", function()
	it("the headless mirror recomposes only the written node when the offset half is unchanged", function()
		local w = world()
		local c = w.handle.controller
		local subtree = ROWS + 2 -- Group, Rows, the rows
		local before = w.adapter.presentationRecomposes()
		c.setPresentationTransform("/S/Group", { x = 0, y = 0, scale = 0.9 })
		-- the FIRST write carries no offset either: the mirror must not walk the
		-- tree to learn that nothing below moved
		expect(w.adapter.presentationRecomposes() - before).toBe(1)
		before = w.adapter.presentationRecomposes()
		c.setPresentationTransform("/S/Group", { x = 0, y = 0, scale = 0.95 })
		expect(w.adapter.presentationRecomposes() - before).toBe(1)
		-- ...and the node's own composed fact still moved with the scale
		local group = w.adapter.node("/S/Group")
		expect(group.presentedVisualRect ~= nil).toBe(true)
		expect(group.presentedVisualRect.w).toBeCloseTo(group.rect.w * 0.95)
		-- an OFFSET write is the case the walk exists for: every descendant moves
		before = w.adapter.presentationRecomposes()
		c.setPresentationTransform("/S/Group", { x = 10, y = 0, scale = 0.95 })
		expect(w.adapter.presentationRecomposes() - before).toBe(subtree)
		expect(w.adapter.node("/S/Group/Rows/R3").presentedPosition.x).toBe(
			w.adapter.node("/S/Group/Rows/R3").rect.x + 10
		)
		-- clearing a transform whose offset half was zero is a one-node write too
		c.setPresentationTransform("/S/Group", { x = 0, y = 0, scale = 1 })
		before = w.adapter.presentationRecomposes()
		c.setPresentationTransform("/S/Group", nil)
		expect(w.adapter.presentationRecomposes() - before).toBe(1)
		expect(w.adapter.node("/S/Group").presentedVisualRect).toBe(nil)
	end)

	it("the live adapter's setTransform carries the same rule, read off its own source", function()
		local body = adapter_source.bodyOf(adapter_source.live(), "local function setTransform(")
		expect(#body > 0).toBe(true)
		-- the offset-half compare gates the subtree walk
		expect(string.find(body, "offsetHalfMoved", 1, true) ~= nil).toBe(true)
		expect(string.find(body, "for _, other in subtreeOf(handle.path) do", 1, true) ~= nil).toBe(true)
		-- ...and the node itself is still re-applied on the short path (its anchor
		-- flips at the first non-1 scale, which moves its own Position)
		expect(string.find(body, "applyRect(handle)", 1, true) ~= nil).toBe(true)
	end)
end)
