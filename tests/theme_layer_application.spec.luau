--!strict
-- LAYER STACKS, APPLIED (rich-skinning-v2 package P2).
--
-- P1 made a layered package COMPILE to rules. This file is the other half, and
-- it exists because of the exact defect class the Step 3.5 fix round found: a
-- fully green suite that asserted every EMISSION and no APPLICATION, while the
-- live thumb was invisible because the tag those rules select on never landed.
--
-- So every proposition below is about the thing that has to actually happen on
-- a mounted node:
--
--   1. the anchoring vocabulary is DATA — how many children a layer needs, where
--      each one sits, and which tags it carries (rs-m3's measured idiom, so the
--      adapter materializes UDim2s and decides nothing);
--   2. the adapter builds that ladder in z-order, tags before parenting, and
--      writes NOT ONE paint property in native mode (rs-m2's defeat refinement);
--   3. every tag that rides the DECORATED NODE — the skinned tag, the stack
--      yield, the error state — is in the desired set `syncTags` diffs against,
--      or it survives exactly until the next classification pass;
--   4. the rung-2 grammar is the rung-1 grammar (one normalizer), it reaches the
--      adapter through the hint channel, and the untagged decoration it produces
--      is repainted by the adapter on the same state precedence the emitted
--      cascade produces.
--
-- Source-contract assertions here read the live adapter file and pin ORDER (the
-- fix-round instrument): reverting the application line turns exactly one of
-- these red rather than leaving the suite green and the screen wrong.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local adapter_source = require("./lib/adapter_source")

local Facet = require("../src") :: any
local UI = require("../src/blueprint")
local customFactory = require("../src/core/custom")
local environment = require("../src/env/environment")
local presenterLib = require("../src/present/presenter")
local actionsLib = require("../src/input/actions")
local fake_target = require("./lib/fake_target")

local themes = require("../src/themes/package")
local snapshot = require("../src/themes/snapshot")
local sheet_model = require("../src/tokens/sheet_model")
local chrome_slots = require("../src/tokens/chrome_slots")

local source = fs.readFile("src/client/screen_target.luau")
-- the adapter was split into siblings when screen_target.luau reached Studio's
-- 200_000-byte Source ceiling. Every anchor below is unchanged and every
-- assertion keeps its strength — `section` simply looks in each part of the
-- adapter for the one that carries the anchor. The list is `adapter_source`'s,
-- so a future extraction is registered in ONE place; screen_chrome is appended
-- because it left before that file existed and is deliberately not in `live()`.
local PARTS: { string } = { source }
for _, path in adapter_source.PARTS do
	if path ~= "src/client/screen_target.luau" then
		table.insert(PARTS, fs.readFile(path))
	end
end
table.insert(PARTS, fs.readFile("src/client/screen_chrome.luau"))

local function section(fromNeedle: string, toNeedle: string): string
	local text = PARTS[1]
	local from = string.find(text, fromNeedle, 1, true)
	for i = 2, #PARTS do
		if from ~= nil then
			break
		end
		text = PARTS[i]
		from = string.find(text, fromNeedle, 1, true)
	end
	expect(from ~= nil).toBe(true)
	local to = string.find(text, toNeedle, from :: number, true)
	expect(to ~= nil).toBe(true)
	return string.sub(text, from :: number, to :: number)
end

local function at(haystack: string, needle: string): number
	local i = string.find(haystack, needle, 1, true)
	expect(i ~= nil).toBe(true)
	return i :: number
end

local function copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out: any = {}
	for k, inner in v do
		out[k] = copy(inner)
	end
	return out
end

local function def(): any
	local base = snapshot.neutralPackage()
	return {
		identity = {
			id = "layer-apply-test",
			displayName = "Layer Application Test",
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
		},
		style = copy(base.style),
		metrics = copy(base.metrics),
		chrome = copy(base.chrome),
		assets = {
			plate = {
				content = "rbxassetid://11",
				sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 24 },
				sliceScale = 1,
				preload = "install",
				fallback = "native",
			},
			border = {
				content = "rbxassetid://12",
				sliceCenter = { x0 = 6, y0 = 6, x1 = 26, y1 = 26 },
				preload = "install",
				fallback = "native",
			},
			ornament = { content = "rbxassetid://13", preload = "install", fallback = "native" },
			ornamentGold = { content = "rbxassetid://14", preload = "install", fallback = "native" },
			banner = { content = "rbxassetid://15", preload = "install", fallback = "native" },
			stripe = { content = "rbxassetid://16", preload = "install", fallback = "native" },
			plateHot = { content = "rbxassetid://17", preload = "install", fallback = "native" },
		},
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

local FULL_STACK = {
	{ kind = "fill", asset = "plate" },
	{ kind = "tile", asset = "stripe", tileSize = { w = 32, h = 24 } },
	{ kind = "frame", asset = "border" },
	{ kind = "edges", asset = "border", sides = { "bottom", "top" }, thickness = 8, margin = 24 },
	{ kind = "corners", asset = "ornament", size = 24, topLeft = "ornamentGold" },
	{ kind = "plaque", asset = "banner", size = { w = 140, h = 36 }, edge = "top", overhang = 18, text = true },
}

local function layered(layers: { any }, slot: string?): any
	local d = def()
	d.chrome[slot or "panel"] = {
		kind = "layered",
		fallback = "native",
		contentInsets = { top = 10, right = 10, bottom = 10, left = 10 },
		layers = layers,
	}
	return d
end

local function stackOf(layers: { any }, slot: string?): any
	local pkg = themes.define(layered(layers, slot))
	assert(pkg ~= nil, "the layered fixture package must compile")
	return chrome_slots.layerPlanFor(pkg, slot or "panel")
end

-- ===== 1. the anchoring vocabulary is DATA (rs-m3) ==========================

describe("chrome_slots.layerBoxes: rs-m3's idiom, expressed as numbers", function()
	it("a fill, a frame and a tile are one full-bleed child each", function()
		local stack = stackOf(FULL_STACK)
		for _, index in { 1, 2, 3 } do
			local boxes = chrome_slots.layerBoxes(stack.layers[index])
			expect(#boxes).toBe(1)
			local box = boxes[1]
			expect(box.anchor.x).toBe(0)
			expect(box.anchor.y).toBe(0)
			expect(box.size.xScale).toBe(1)
			expect(box.size.yScale).toBe(1)
			expect(box.size.xOffset).toBe(0)
			expect(box.name).toBe(`FacetChromeL{index}`)
			expect(box.corner).toBeNil()
		end
	end)

	it("a corners layer is FOUR fixed-px ornaments, anchored at the four corners", function()
		local stack = stackOf(FULL_STACK)
		local boxes = chrome_slots.layerBoxes(stack.layers[5])
		expect(#boxes).toBe(4)
		-- rs-m3 measured this exact idiom: AnchorPoint(cx,cy) at Position scale
		-- (cx,cy), fixed px size, so the ornament pins at every width and height
		-- (TR x = w-24 at 360/520/240 -> 336/496/216)
		local expected = {
			{ key = "topLeft", ax = 0, ay = 0 },
			{ key = "topRight", ax = 1, ay = 0 },
			{ key = "bottomLeft", ax = 0, ay = 1 },
			{ key = "bottomRight", ax = 1, ay = 1 },
		}
		for index, want in expected do
			local box = boxes[index]
			expect(box.key).toBe(want.key)
			expect(box.anchor.x).toBe(want.ax)
			expect(box.anchor.y).toBe(want.ay)
			expect(box.position.xScale).toBe(want.ax)
			expect(box.position.yScale).toBe(want.ay)
			expect(box.position.xOffset).toBe(0)
			expect(box.position.yOffset).toBe(0)
			expect(box.size.xScale).toBe(0)
			expect(box.size.xOffset).toBe(24)
			expect(box.size.yOffset).toBe(24)
		end
		expect(boxes[1].name).toBe("FacetChromeL5TopLeft")
	end)

	it("only a corner with its OWN art carries the second tag", function()
		local stack = stackOf(FULL_STACK)
		local boxes = chrome_slots.layerBoxes(stack.layers[5])
		-- the fixture declares topLeft = "ornamentGold" and nothing else: a tag on
		-- a corner with no rule would be a selector that matches and says nothing
		expect(boxes[1].corner).toBe("topLeft")
		expect(boxes[2].corner).toBeNil()
		expect(boxes[3].corner).toBeNil()
		expect(boxes[4].corner).toBeNil()
		expect(chrome_slots.cornerTagFor("panel", 5, "topLeft")).toBe("facet-chrome-panel-5-topLeft")
	end)

	it("an edges layer is one rail per DECLARED side, in canonical order", function()
		local stack = stackOf(FULL_STACK)
		local boxes = chrome_slots.layerBoxes(stack.layers[4])
		expect(#boxes).toBe(2)
		-- the recipe declared { "bottom", "top" }; the ladder is built in the
		-- canonical order, or two packages that differ only in how the author
		-- typed the list would churn instances on a swap
		expect(boxes[1].key).toBe("top")
		expect(boxes[2].key).toBe("bottom")
		-- rs-m3: x = margin, width = w - 2*margin (24 -> 312 at w=360), thickness px
		expect(boxes[1].position.xOffset).toBe(24)
		expect(boxes[1].size.xScale).toBe(1)
		expect(boxes[1].size.xOffset).toBe(-48)
		expect(boxes[1].size.yOffset).toBe(8)
		expect(boxes[1].anchor.y).toBe(0)
		expect(boxes[1].position.yScale).toBe(0)
		-- the bottom rail pins its BOTTOM edge: anchor y=1 at scale y=1 => y = h-8
		expect(boxes[2].anchor.y).toBe(1)
		expect(boxes[2].position.yScale).toBe(1)
		expect(boxes[2].position.yOffset).toBe(0)
		expect(boxes[2].name).toBe("FacetChromeL4Bottom")
	end)

	it("a left/right rail stretches on the OTHER axis", function()
		local stack = stackOf({
			{ kind = "edges", asset = "border", sides = { "left", "right" }, thickness = 6, margin = 12 },
		})
		local boxes = chrome_slots.layerBoxes(stack.layers[1])
		expect(#boxes).toBe(2)
		expect(boxes[1].key).toBe("left")
		expect(boxes[1].size.xOffset).toBe(6)
		expect(boxes[1].size.yScale).toBe(1)
		expect(boxes[1].size.yOffset).toBe(-24)
		expect(boxes[1].position.yOffset).toBe(12)
		expect(boxes[2].key).toBe("right")
		expect(boxes[2].anchor.x).toBe(1)
		expect(boxes[2].position.xScale).toBe(1)
	end)

	it("a plaque overhangs its edge by the DECLARED pixels", function()
		local stack = stackOf(FULL_STACK)
		local boxes = chrome_slots.layerBoxes(stack.layers[6])
		expect(#boxes).toBe(1)
		local box = boxes[1]
		expect(box.anchor.x).toBe(0.5)
		expect(box.position.xScale).toBe(0.5)
		expect(box.size.xOffset).toBe(140)
		expect(box.size.yOffset).toBe(36)
		-- rs-m3 measured a 140x36 plaque centred at y=0 with AnchorPoint(.5,.5),
		-- i.e. spanning -18..18 — the same rectangle this writes as "top edge at
		-- -overhang", so the declared number IS the pixels outside the parent
		expect(box.anchor.y).toBe(0)
		expect(box.position.yScale).toBe(0)
		expect(box.position.yOffset).toBe(-18)
	end)

	-- architecture verifier F2. `plaque.text = true` was validated, documented and
	-- shipped in TWO reference packages, and NOTHING read it: no instance, no
	-- geometry, no tag, no rule. The accepted-and-ignored class the Step 3 fix
	-- round found in container `align`, under a green suite.
	--
	-- It is implemented as GEOMETRY ONLY, wired through the machinery that already
	-- exists: the chrome text lift is a copy of the decorated node's own text
	-- riding above the whole ladder, and a plaque that declares `text` moves that
	-- copy onto the plaque rect instead of the node's content rect. So a nameplate
	-- panel's title reads on the plaque, and nothing new mirrors, connects, or
	-- can go stale.
	it("a plaque's TEXT sub-slot is the plaque rect minus its declared insets", function()
		local stack = stackOf(FULL_STACK)
		-- no insets declared: the box IS the plaque rect (same numbers as above)
		local box = chrome_slots.plaqueTextBox(stack)
		expect(box ~= nil).toBe(true)
		expect((box :: any).anchor.x).toBe(0.5)
		expect((box :: any).anchor.y).toBe(0)
		expect((box :: any).position.xScale).toBe(0.5)
		expect((box :: any).position.yScale).toBe(0)
		expect((box :: any).position.yOffset).toBe(-18)
		expect((box :: any).size.xOffset).toBe(140)
		expect((box :: any).size.yOffset).toBe(36)

		-- ...and with insets the text box shrinks INSIDE the plate, so a carved
		-- banner's border never eats its own title
		local inset = stackOf({
			{ kind = "fill", asset = "plate" },
			{
				kind = "plaque",
				asset = "banner",
				size = { w = 140, h = 36 },
				edge = "top",
				overhang = 18,
				text = true,
				textInsets = { top = 6, right = 12, bottom = 4, left = 10 },
			},
		})
		local tight = chrome_slots.plaqueTextBox(inset) :: any
		expect(tight.position.yOffset).toBe(-18 + 6)
		expect(tight.position.xOffset).toBe((10 - 12) / 2) -- centred: asymmetric insets shift it
		expect(tight.size.xOffset).toBe(140 - 22)
		expect(tight.size.yOffset).toBe(36 - 10)

		-- a stack with no plaque, and a plaque that does NOT ask for text, both
		-- answer nil — the lift stays on the node's own content rect
		expect(chrome_slots.plaqueTextBox(stackOf({ { kind = "fill", asset = "plate" } }))).toBeNil()
		expect(chrome_slots.plaqueTextBox(stackOf({
			{ kind = "plaque", asset = "banner", size = { w = 60, h = 20 }, edge = "top" },
		}))).toBeNil()
		expect(chrome_slots.plaqueTextBox(nil)).toBeNil()

		-- the ADAPTER uses it: the lift's geometry comes from the plaque when one
		-- declares text, and from the recipe's contentInsets otherwise
		-- the second parameter is the HOST HANDLE, which is what lets the recipe's
		-- inset be checked against the space the node actually has rather than
		-- assumed affordable (director report 2026-07-28: a lift inset by more than
		-- its host's padded box solved to zero width and drew nothing)
		local geom = section("local function liftGeometry(plan: any, handle: any?)", "\n\tend")
		-- ...and the two FLOORS (task THEME): the label's own line box, so this seam
		-- and `spendInset` reach the same verdict about a control too small for its frame
		expect(
			string.find(geom, "plaque or chrome_slots.liftGeometry(plan, hostW, hostH, lineBox, lineBox)", 1, true)
				~= nil
		).toBe(true)
		expect(string.find(geom, "local plaque = chrome_slots.plaqueTextBox(plan)", 1, true) ~= nil).toBe(true)
		-- ...and the PLAQUE path takes no full-bleed compensation. The generic lift is
		-- scale-1 against the host's padded content box and must add that padding back
		-- (a 60px button with 12+12 padding gave its label 8px and drew nothing); a
		-- plaque rect is already the absolute box the recipe declared, so compensating
		-- it would push the title off its own plate.
		expect(string.find(geom, "if plaque == nil then", 1, true) ~= nil).toBe(true)
		expect(string.find(geom, "chrome_slots.fullBleedBox(padL, padR, padT, padB)", 1, true) ~= nil).toBe(true)
		-- ...and the label follows the plaque's own ANCHOR, or a centred plaque
		-- would place its title from the wrong corner
		local lift = section("local function syncChromeText(handle: any", "\n\tend")
		expect(string.find(lift, "label.AnchorPoint = anchor", 1, true) ~= nil).toBe(true)
		expect(string.find(lift, "handle.chromeText.AnchorPoint = anchor", 1, true) ~= nil).toBe(true)
		-- ...and it is NOT a layer instance: a text box that created an ImageLabel
		-- would put an empty picture over the plate
		expect(chrome_slots.stackInstanceCount(inset)).toBe(2)
	end)

	it("layers and INSTANCES are different numbers, and both are published", function()
		local stack = stackOf(FULL_STACK)
		expect(#stack.layers).toBe(6)
		-- fill + tile + frame + 2 rails + 4 ornaments + plaque
		expect(chrome_slots.stackInstanceCount(stack)).toBe(10)
		expect(chrome_slots.stackInstanceCount(nil)).toBe(0)
	end)

	-- A DECORATION IS A BACKDROP, AND THE LADDER FORGOT (director report 2026-08-05:
	-- "the Ready toggle has no label under the ornate theme").
	--
	-- The single-decoration path parents `FacetChrome` at ZIndex 0 — *below anything
	-- the node's own content draws*. The layered path numbered its layers 1..N, and a
	-- control's own adapter-built content sits at 1 (`Label`, `Track`) and 2 (`Knob`).
	-- Equal ZIndex breaks by SIBLING ORDER and a decoration is built after the content
	-- it decorates, so an opaque full-bleed `FacetChromeL1` painted over both.
	--
	-- Measured live at 360x691: under fantasy-ornate (layered) `Label z=1, Track z=1,
	-- FacetChromeL1 z=1` and the word "Ready" was invisible; under pixel-quest (one
	-- nine-slice) `FacetChrome z=0` and the same control read correctly. Same defect
	-- shape as `applyFullBleed` (L-25) — a ruling that lived at one call site.
	describe("the ladder is a BACKDROP: every layer sits below the node's own content", function()
		it("the band is <= 0, and the topmost layer lands where a single decoration does", function()
			expect(chrome_slots.DECORATION_Z_INDEX).toBe(0)
			-- a one-layer package is byte-identical to the single-decoration case
			expect(chrome_slots.layerZIndexFor(1, 1)).toBe(chrome_slots.DECORATION_Z_INDEX)
			-- ...and a ladder keeps its own order inside the band
			expect(chrome_slots.layerZIndexFor(1, 6)).toBe(-5)
			expect(chrome_slots.layerZIndexFor(6, 6)).toBe(0)
		end)

		it("no layer of any depth can reach the CONTENT band, which starts at 1", function()
			-- the invariant stated over the whole shipped range rather than at the one
			-- depth the report happened to use
			for count = 1, 12 do
				for index = 1, count do
					local z = chrome_slots.layerZIndexFor(index, count)
					expect(`L{index}/{count} z={z} belowContent={z <= chrome_slots.DECORATION_Z_INDEX}`).toBe(
						`L{index}/{count} z={z} belowContent=true`
					)
				end
			end
		end)

		it("the ladder is strictly ordered, so no two layers share a slot", function()
			-- sibling order would be the alternative and a re-sync rebuilds only what
			-- changed, so an order the array does not control is one that drifts
			for count = 1, 12 do
				for index = 2, count do
					expect(chrome_slots.layerZIndexFor(index, count) > chrome_slots.layerZIndexFor(index - 1, count)).toBe(
						true
					)
				end
			end
		end)

		it("...and the lift still clears the whole ladder AND the content band", function()
			local stack = stackOf(FULL_STACK)
			expect(chrome_slots.liftZIndexFor(stack) > chrome_slots.layerZIndexFor(#stack.layers, #stack.layers)).toBe(
				true
			)
			expect(chrome_slots.liftZIndexFor(stack) > 2).toBe(true)
		end)
	end)

	it("the text lift rides above the WHOLE ladder", function()
		-- rs-m2: a layer covers the parent's engine text at any ZIndex, so the
		-- lift is mandatory at every depth and has to clear N
		expect(chrome_slots.liftZIndexFor(stackOf(FULL_STACK))).toBe(7)
		expect(chrome_slots.liftZIndexFor(stackOf({ { kind = "fill", asset = "plate" } }))).toBe(2)
		expect(chrome_slots.liftZIndexFor(nil)).toBe(1)
	end)
end)

-- ===== 2. the adapter builds that ladder (application, order-pinned) ========

describe("screen_target: the layer ladder is materialized as the plan describes", function()
	it("one ImageLabel per BOX, ZIndex = array order, Active=false", function()
		local build = section("local function buildChromeStack", "handle.chromeStack = built")
		expect(string.find(build, "for _, spec in chrome_slots.layerBoxes(layer) do", 1, true) ~= nil).toBe(true)
		-- ARRAY ORDER, INSIDE THE DECORATION BAND. The z comes from the shared
		-- function rather than from `layer.index` directly (director report
		-- 2026-08-05): 1..N put the ladder on top of the node's own content.
		expect(
			string.find(build, "child.ZIndex = chrome_slots.layerZIndexFor(layer.index, layerCount)", 1, true) ~= nil
		).toBe(true)
		expect(string.find(build, "made.ZIndex = chrome_slots.layerZIndexFor(layer.index, layerCount)", 1, true) ~= nil).toBe(
			true
		)
		expect(string.find(build, "child.Active = false", 1, true) ~= nil).toBe(true)
		expect(string.find(build, "child.Selectable = false", 1, true) ~= nil).toBe(true)
		-- geometry comes from the pure boxes, never from arithmetic here
		expect(string.find(build, "Vector2.new(spec.anchor.x, spec.anchor.y)", 1, true) ~= nil).toBe(true)
		expect(string.find(build, "spec.position.xScale,", 1, true) ~= nil).toBe(true)
		expect(string.find(build, "spec.size.xScale, spec.size.xOffset", 1, true) ~= nil).toBe(true)
	end)

	it("layers are DIRECT children of the decorated node (the child combinator)", function()
		-- every state rule the package emits is `.<parentTag> > .<layerTag>`; one
		-- intervening container Frame would break all of them at once.
		-- A MASKED layer (R1 `mask`, probe rs-m9) is the ONE sanctioned exception:
		-- its art sits inside the adapter's CanvasGroup, which is itself a direct
		-- child — so the ladder's own ZIndex order and the `.<parentTag> > ` rules
		-- that select the WRAPPER's siblings are unchanged, and the child-combinator
		-- rules that select the ART are why the wrapper stays untagged.
		local build = section("local function buildChromeStack", "handle.chromeStack = built")
		expect(string.find(build, "child.Parent = mask or instance", 1, true) ~= nil).toBe(true)
		expect(string.find(build, "made.Parent = instance", 1, true) ~= nil).toBe(true)
	end)

	it("the tag is added BEFORE the instance joins the tree", function()
		-- rs-m2's defeat refinement: a rule can only win over a pre-join value if
		-- it is already matching at first application
		local build = section("local function buildChromeStack", "handle.chromeStack = built")
		local tagAt = at(build, "CollectionService:AddTag(child, layer.tag)")
		local parentAt = at(build, "child.Parent = mask or instance")
		expect(tagAt < parentAt).toBe(true)
	end)

	-- ===== the MASK wrapper (R1 `mask`, probe rs-m9) =========================

	it("a masked layer wraps its art in an adapter-owned, UNTAGGED CanvasGroup", function()
		local build = section("local function buildChromeStack", "handle.chromeStack = built")
		-- the wrapper is GATED on the plan's own mask decision, read through the
		-- one pure accessor — not on the kind, not on a second guess here
		expect(string.find(build, "local maskKind = chrome_slots.layerMaskOf(layer)", 1, true) ~= nil).toBe(true)
		expect(at(build, "local maskKind = chrome_slots.layerMaskOf(layer)") < at(build, "if maskKind ~= nil then")).toBe(
			true
		)
		expect(at(build, "if maskKind ~= nil then") < at(build, 'Instance.new("CanvasGroup")')).toBe(true)
		expect(string.find(build, 'Instance.new("CanvasGroup")', 1, true) ~= nil).toBe(true)
		expect(string.find(build, "chrome_slots.LAYER_MASK_SUFFIX", 1, true) ~= nil).toBe(true)
		expect(string.find(build, "corner.CornerRadius = UDim.new(0.5, 0)", 1, true) ~= nil).toBe(true)
		expect(string.find(build, "made.Active = false", 1, true) ~= nil).toBe(true)
		expect(string.find(build, "made.Selectable = false", 1, true) ~= nil).toBe(true)
		-- THE WRAPPER IS A SHAPE, NEVER PAINT. It carries no tag, so no rule can
		-- reach it and every existing rule path still selects the ART child.
		expect(string.find(build, "CollectionService:AddTag(made", 1, true)).toBeNil()
		expect(string.find(build, "made.Image", 1, true)).toBeNil()
		expect(string.find(build, "made.BackgroundColor3", 1, true)).toBeNil()
		-- the BOX goes on the wrapper and the art is full-bleed inside it, or the
		-- mask would clip a rectangle that is already the right shape
		expect(at(build, "made.Size = UDim2.new(spec.size.xScale") < at(build, "child.Size = UDim2.fromScale(1, 1)")).toBe(
			true
		)
		-- and it is CENSUSED: a canvas costs ~7KB and ~18us (rs-m9 Q5)
		expect(string.find(build, "chromeState.noteCanvasMask(true)", 1, true) ~= nil).toBe(true)
	end)

	it("the wrapper is TRANSPARENT by class rule, not by an adapter write", function()
		-- LIVE-FOUND (stamp 62b6cdeb-1689276): a fresh CanvasGroup sits at
		-- BackgroundTransparency 0, and no class rule reached it — so the mask
		-- painted a solid pill behind the very art it was shaping. A silhouette
		-- must not paint. Owned by a RULE like every other class default, because
		-- an explicit write at create would permanently defeat one (spike m10).
		local model = sheet_model.buildPackage(snapshot.neutralPackage())
		local found = nil
		for _, r in model.rules do
			if r.selector == "CanvasGroup" then
				found = r
			end
		end
		expect(found ~= nil).toBe(true)
		expect(found.name).toBe("Canvas default")
		expect(found.props.BackgroundTransparency.value).toBe(1)
		expect(found.group).toBe("base")
		-- and the adapter writes nothing on it
		local build = section("local function buildChromeStack", "handle.chromeStack = built")
		expect(string.find(build, "made.BackgroundTransparency", 1, true)).toBeNil()
	end)

	it("the wrapper falls with its layer, census included", function()
		local destroy = section("local function destroyChromeStack", "handle.chromeStack = nil")
		expect(string.find(destroy, "entry.mask:Destroy()", 1, true) ~= nil).toBe(true)
		expect(string.find(destroy, "chromeState.noteCanvasMask(false)", 1, true) ~= nil).toBe(true)
		-- and its path entry, or a later lookup would hand out a dead instance
		expect(string.find(destroy, 'instancesByPath[handle.path .. "/" .. entry.mask.Name] = nil', 1, true) ~= nil).toBe(
			true
		)
	end)

	it("the focus ring hugs the WRAPPER when the plate layer is masked", function()
		-- the art inside a mask is full-bleed, so ringing it would trace exactly
		-- the rectangle the mask exists to hide
		local host = section("local function focusArtHost", "local syncChromeInner")
		expect(string.find(host, "return entry.mask or entry.instance", 1, true) ~= nil).toBe(true)
	end)

	it("NOT ONE paint property is written in native mode", function()
		local build = section("local function buildChromeStack", "handle.chromeStack = built")
		-- the only paint call site is gated
		expect(string.find(build, "if not nativeMode then\n\t\t\t\t\tapplyChromeLayerPaint", 1, true) ~= nil).toBe(true)
		-- ...and nothing paints outside it
		expect(string.find(build, "child.Image =", 1, true)).toBeNil()
		expect(string.find(build, "child.ImageColor3", 1, true)).toBeNil()
		expect(string.find(build, "child.BackgroundTransparency", 1, true)).toBeNil()
	end)

	it("the per-corner tag lands only on the corner that declared art", function()
		local build = section("local function buildChromeStack", "handle.chromeStack = built")
		expect(string.find(build, "if spec.corner ~= nil then", 1, true) ~= nil).toBe(true)
		expect(
			string.find(
				build,
				"CollectionService:AddTag(child, chrome_slots.cornerTagFor(slot, layer.index, spec.corner))",
				1,
				true
			) ~= nil
		).toBe(true)
	end)

	it("one asset-failure grace timer per LAYER, not per ornament", function()
		local build = section("local function buildChromeStack", "handle.chromeStack = built")
		expect(string.find(build, "watchChromeAsset(child, layer.assetName)", 1, true) ~= nil).toBe(true)
		expect(string.find(build, "if first then", 1, true) ~= nil).toBe(true)
	end)

	it("every layer instance is addressable by path, so GetStyled can read it", function()
		local build = section("local function buildChromeStack", "handle.chromeStack = built")
		expect(string.find(build, 'instancesByPath[handle.path .. "/" .. spec.name] = child', 1, true) ~= nil).toBe(
			true
		)
		local destroy = section("local function destroyChromeStack", "handle.chromeStack = nil")
		expect(string.find(destroy, 'instancesByPath[handle.path .. "/" .. entry.instance.Name] = nil', 1, true) ~= nil).toBe(
			true
		)
	end)

	it("the census counts LAYERS, and the DataModel count is taken independently", function()
		local build = section("local function buildChromeStack", "handle.chromeStack = built")
		expect(string.find(build, "chromeState.noteCreated(slot, layer.kind)", 1, true) ~= nil).toBe(true)
		local destroy = section("local function destroyChromeStack", "handle.chromeStack = nil")
		expect(string.find(destroy, "chromeState.noteDestroyed(handle.chromeStackSlot, kind)", 1, true) ~= nil).toBe(
			true
		)
		local census = section("function adapter.chromeCensus", "return census")
		expect(string.find(census, "census.actualLayerInstances = actualLayerInstances", 1, true) ~= nil).toBe(true)
		expect(string.find(census, "census.overhang = overhang", 1, true) ~= nil).toBe(true)
	end)

	it("the LIFTED LABEL falls with the ladder (live-found orphan)", function()
		-- the nine-slice rebuild path has always torn the lift down with the
		-- decoration; the ladder did not, so a swap from a layered package to a
		-- flat one left an orphan `FacetChromeText` still boxed by the OUTGOING
		-- recipe's contentInsets. Measured live at the director round: after
		-- fantasy-ornate -> studio-neutral the toolbar's three buttons each kept a
		-- lift at `{1, -28}` inside a 36px box — minus sixteen pixels wide. It drew
		-- nothing at that size, which is exactly why it survived.
		local destroy = section("local function destroyChromeStack", "\n\tend")
		expect(string.find(destroy, "destroyChromeText(handle)", 1, true) ~= nil).toBe(true)
		-- ...and a stack being REBUILT gets it back on the next pass
		local sync = section("if stack ~= nil then", "syncChromeShadow(handle, slot, instance,")
		expect(string.find(sync, "buildChromeStack(handle, slot :: string, stack)", 1, true) ~= nil).toBe(true)
		expect(string.find(sync, "syncChromeText(handle, nil, stack,", 1, true) ~= nil).toBe(true)
	end)

	it("the ladder falls with the node, in BOTH teardown paths", function()
		local remove = section("function adapter.remove(handle: any)", "handle.instance:Destroy()")
		expect(string.find(remove, "destroyChromeStack(handle)", 1, true) ~= nil).toBe(true)
		local destroyRoot = section("function adapter.destroyRoot(rootHandle: any)", "rootHandle.gui:Destroy()")
		expect(string.find(destroyRoot, "destroyChromeStack(handle)", 1, true) ~= nil).toBe(true)
	end)
end)

describe("screen_target: the stack branch keeps the fix round's ORDER", function()
	local sync = section("function syncChrome(handle: any)", "if plan == nil then")

	it("a hinted node's own identity still lands before any return", function()
		-- the invisible-thumb regression, one slot down: the layered branch
		-- returns, so both halves of the hint have to happen above it
		local tagAt = at(sync, "local hintedSlot = if type(handle.decorationHint)")
		local paintAt = at(sync, "applySlotNativePaint(instance, slot, handle)")
		local stackReturnAt = at(sync, "syncChromeStackFallback(handle, slot :: string)")
		expect(tagAt < stackReturnAt).toBe(true)
		expect(paintAt < stackReturnAt).toBe(true)
	end)

	it("it paints BEFORE it suppresses, exactly as the nine-slice branch does", function()
		local paintAt = at(sync, "applySlotNativePaint(instance, slot, handle)")
		local suppressAt = at(sync, "applySkinnedSuppression(instance, true)")
		expect(paintAt < suppressAt).toBe(true)
	end)

	it("the skinned tag is synced AFTER the ladder exists, never before", function()
		local build = at(sync, "buildChromeStack(handle, slot :: string, stack)")
		local slotAt = at(sync, "handle.chromeSlot = slot\n\t\t\t\tsyncTags(handle)")
		expect(build < slotAt).toBe(true)
	end)

	it("a RUNG-2 override beats the ladder (the standing opt-out rule)", function()
		expect(
			string.find(sync, "local stack = if slot ~= nil and not (plan ~= nil and plan.localOverride)", 1, true)
				~= nil
		).toBe(true)
	end)

	it("a changed ladder shape REBUILDS, because the tags are what rules key on", function()
		expect(
			string.find(sync, "handle.chromeStackSignature ~= stackSignature(slot :: string, stack)", 1, true) ~= nil
		).toBe(true)
		expect(string.find(sync, "destroyChromeStack(handle)", 1, true) ~= nil).toBe(true)
	end)
end)

-- ===== 3. every node-side tag rides the desired set ========================

describe("the decorated node's tags survive the syncTags diff", function()
	-- the classification block, from the declaration to the point the desired set is
	-- finished. The old terminator was the removal loop's own `for`; that loop is
	-- now one call to `render/tag_sync.diff` (SCREEN-X, 2026-08-22), so the bound
	-- moves to the call and the window is the same region it always was.
	local tags = section("local function syncTags(handle: any)", "local plan = tag_sync.diff(")

	it("the stack yield rides it (it is on the NODE, not the decoration)", function()
		expect(string.find(tags, "chromeYield = handle.chromeYield == true", 1, true) ~= nil).toBe(true)
		local setter = section("function setChromeYield(handle: any, on: boolean)", "\n\tend")
		expect(string.find(setter, "syncTags(handle)", 1, true) ~= nil).toBe(true)
	end)

	it("the error state rides it", function()
		expect(string.find(tags, "errorState = handle.errorState == true", 1, true) ~= nil).toBe(true)
		local setter = section("function adapter.setChromeErrorState", "\n\tend")
		expect(string.find(setter, "syncTags(handle)", 1, true) ~= nil).toBe(true)
		expect(string.find(setter, "applyOverrideVariantArt(handle)", 1, true) ~= nil).toBe(true)
	end)

	it("classifyTags is the ONE builder, and it emits both", function()
		local yielded = sheet_model.classifyTags({ chromeYield = true })
		expect(yielded["facet-chrome-yield"]).toBe(true)
		local errored = sheet_model.classifyTags({ errorState = true })
		expect(errored["facet-state-error"]).toBe(true)
		-- ...and neither appears unless asked for, so nothing a package published
		-- before this stage renders can carry them
		local quiet = sheet_model.classifyTags({ surface = "control", interactive = true })
		expect(quiet["facet-chrome-yield"]).toBeNil()
		expect(quiet["facet-state-error"]).toBeNil()
	end)

	it("the emitted yield rule is a child combinator off that exact tag", function()
		local model = sheet_model.buildPackage(themes.define(layered(FULL_STACK, "field")))
		local found = false
		for _, rule in model.rules do
			if rule.name == "Chrome — field L1 fill editing" then
				found = true
				expect(rule.selector).toBe(".facet-chrome-yield > .facet-chrome-field-1")
			end
		end
		expect(found).toBe(true)
	end)

	it("a TextBox over a STACK flips the tag; over one decoration it tags the child", function()
		local focused = section("(instance :: TextBox).Focused:Connect(function()", "FocusLost:Connect")
		expect(string.find(focused, "CollectionService:AddTag(deco, chrome_slots.TAGS.editing)", 1, true) ~= nil).toBe(
			true
		)
		expect(string.find(focused, "setChromeYield(handle, true)", 1, true) ~= nil).toBe(true)
		local lost = section("(instance :: TextBox).FocusLost:Connect(function()", "label.Visible = true")
		expect(string.find(lost, "setChromeYield(handle, false)", 1, true) ~= nil).toBe(true)
	end)
end)

describe("suppression (R9) reaches a layered node through the SAME machinery", function()
	it("a layered slot emits the three suppression rules a nine-sliced one does", function()
		local model = sheet_model.buildPackage(themes.define(layered(FULL_STACK)))
		local names: { [string]: boolean } = {}
		for _, rule in model.rules do
			names[rule.name] = true
		end
		expect(names["Skinned — panel"]).toBe(true)
		expect(names["Skinned — panel corner"]).toBe(true)
		expect(names["Skinned — panel outline"]).toBe(true)
	end)

	it("the tag those rules select on is the one the stack branch sets", function()
		expect(chrome_slots.skinnedTagFor("panel")).toBe("facet-skinned-panel")
		expect(sheet_model.classifyTags({ skinnedSlot = "panel" })["facet-skinned-panel"]).toBe(true)
		local sync = section("function syncChrome(handle: any)", "if plan == nil then")
		expect(string.find(sync, "handle.chromeSlot = slot\n\t\t\t\tsyncTags(handle)", 1, true) ~= nil).toBe(true)
	end)

	it("and it is removed the moment the ladder goes", function()
		local sync = section("function syncChrome(handle: any)", "if plan == nil then")
		expect(string.find(sync, "handle.chromeSlot = nil\n\t\t\t\t\tsyncTags(handle)", 1, true) ~= nil).toBe(true)
	end)

	-- RS-DIR6-F1: the disabled dim reaches a LAYER through the same child
	-- combinator it reaches a nine-slice decoration through, so a broken ladder
	-- on a disabled control had every rail back at 0.4 over the fallback fill
	it("every LAYER's fallback hide beats the disabled dim too", function()
		local model = sheet_model.buildPackage(themes.define(layered(FULL_STACK)))
		local index: { [string]: number } = {}
		for i, rule in model.rules do
			index[rule.name] = i
		end
		for layerIndex = 1, #FULL_STACK do
			local kind = FULL_STACK[layerIndex].kind
			local base = `Chrome — panel L{layerIndex} {kind}`
			expect(index[`{base} fallback over states`] > index[`{base} disabled`]).toBe(true)
			local hide = nil
			for _, rule in model.rules do
				if rule.name == `{base} fallback over states` then
					hide = rule
				end
			end
			expect(hide.props.ImageTransparency.value).toBe(1)
			-- on the MUTE tag since RS-A16-D5: the hide is what a disabled state must
			-- not undo, and the layer whose own asset failed never carries it
			expect(hide.selector).toBe(`.{chrome_slots.layerTagFor("panel", layerIndex)}.{chrome_slots.TAGS.mute}`)
		end
	end)
end)

describe("the whole stack fails and recovers as a UNIT", function()
	it("one broken layer puts the slot in fallback", function()
		local state = chrome_slots.newState(themes.define(layered(FULL_STACK)))
		expect(state.isFallback("panel")).toBe(false)
		expect(state.setAssetLoaded("banner", false)).toBe(true)
		expect(state.isFallback("panel")).toBe(true)
	end)

	it("the adapter flips the tags on EVERY layer instance, PER LAYER", function()
		local flip = section("local function syncChromeStackFallback", "\n\tend")
		expect(string.find(flip, "for _, entry in handle.chromeStack or {} do", 1, true) ~= nil).toBe(true)
		-- ONE decision site for both tags (RS-A16-D5), asked per layer with THAT
		-- layer's own asset name — a stack-wide `want` could not tell the broken
		-- layer from its healthy siblings
		expect(string.find(flip, "syncChromeFallbackTags(child, slot, entry.layer.assetName, true)", 1, true) ~= nil).toBe(
			true
		)
		local tags = section("local function syncChromeFallbackTags", "\n\tend")
		expect(string.find(tags, "chromeState.isFallback(slot)", 1, true) ~= nil).toBe(true)
		expect(string.find(tags, "chromeState.isArtMuted(slot, assetName, child.IsLoaded)", 1, true) ~= nil).toBe(true)
		expect(string.find(tags, "chrome_slots.TAGS.fallback", 1, true) ~= nil).toBe(true)
		expect(string.find(tags, "chrome_slots.TAGS.mute", 1, true) ~= nil).toBe(true)
	end)

	it("a fallback stack cannot flag its OWN siblings as failed (live-found)", function()
		-- LIVE REGRESSION 2026-07-25. One broken layer puts every healthy layer of
		-- the stack at ImageTransparency 1 through the fallback rules. The engine
		-- does not decode an invisible image, so IsLoaded stayed false on all of
		-- them, the grace timer flagged all their assets as failed too, and
		-- recovering the ORIGINAL asset could never clear the slot: five healthy
		-- assets were reported broken and the panel stayed in fallback forever.
		local muted = chrome_slots.judgeArt({
			attached = true,
			visible = true,
			transparency = 1, -- the fallback's own hide
			mutedByFallback = true,
			image = "rbxassetid://1",
			rect = { x = 0, y = 0, w = 120, h = 40 },
			clips = {},
		})
		expect(muted.judgeable).toBe(false)
		-- and the REASON names the fallback rather than the package, which is the
		-- distinction RS-A16-D5's recoverability half turns on
		expect(muted.reason).toBe("muted")
		expect(chrome_slots.judgeArt({
			attached = true,
			visible = true,
			transparency = 1,
			image = "rbxassetid://1",
			rect = { x = 0, y = 0, w = 120, h = 40 },
			clips = {},
		}).reason).toBe("transparent")
		-- ...and the adapter's read is the STYLED one, because in native mode the
		-- layer's transparency is rule-owned and a plain read is blind
		local facts = section("local function chromeArtJudgement", "return chrome_slots.judgeArt({")
		expect(string.find(facts, 'GetStyled("ImageTransparency")', 1, true) ~= nil).toBe(true)
	end)

	it("a layered handle — and a BAR — is re-synced when an asset's state changes", function()
		-- `handle.chrome` is nil for a layered node, and nil for a bar too: without
		-- these the broken layer would never reach its fallback rules and a
		-- recovered bar would never leave them (RS-A16-D5)
		local refresh = section("local function refreshChromeFallback", "\n\tend")
		expect(string.find(refresh, "handle.chrome ~= nil", 1, true) ~= nil).toBe(true)
		expect(string.find(refresh, "handle.chromeStack ~= nil", 1, true) ~= nil).toBe(true)
		expect(string.find(refresh, "handle.barFill ~= nil", 1, true) ~= nil).toBe(true)
		expect(string.find(refresh, "handle.barOrnaments ~= nil", 1, true) ~= nil).toBe(true)
	end)
end)

-- ===== 4. rung 2 shares the rung-1 grammar, and is APPLIED =================

describe("rung 2: one grammar, one normalizer, both rungs", function()
	it("a bare string and a per-state map both plan an untagged local decoration", function()
		local pkg = themes.define(def())
		local bare = chrome_slots.planFor(pkg, "sliderThumb", { image = "rbxassetid://4242" })
		expect(bare.localOverride).toBe(true)
		expect(bare.tag).toBeNil()
		expect(bare.contentId).toBe("rbxassetid://4242")
		expect(bare.variants).toBeNil()

		local variant = themes.normalizeVariant({
			default = "rbxassetid://1",
			hover = "rbxassetid://2",
			disabled = "rbxassetid://3",
		}, "thumbImage")
		local mapped = chrome_slots.planFor(pkg, "sliderThumb", { imageVariants = variant })
		expect(mapped.localOverride).toBe(true)
		expect(mapped.tag).toBeNil()
		-- the map's `default` IS the resting picture
		expect(mapped.contentId).toBe("rbxassetid://1")
		expect(mapped.variants.hover.contentId).toBe("rbxassetid://2")
		expect(mapped.variants.disabled.contentId).toBe("rbxassetid://3")
	end)

	it("the precedence the adapter picks with IS the emitted cascade", function()
		-- rule groups run base < surfaces < roles < chrome < hover < press <
		-- disabled and the later rule wins, so a hand-picked order that disagreed
		-- would make an overridden control behave unlike its themed neighbour
		local groupIndex: { [string]: number } = {}
		for index, name in sheet_model.RULE_GROUPS do
			groupIndex[name] = index
		end
		expect(groupIndex.disabled > groupIndex.press).toBe(true)
		expect(groupIndex.press > groupIndex.hover).toBe(true)
		expect(groupIndex.hover > groupIndex.chrome).toBe(true)
		expect(chrome_slots.VARIANT_PRECEDENCE[1]).toBe("disabled")
		expect(chrome_slots.VARIANT_PRECEDENCE[2]).toBe("pressed")
		expect(chrome_slots.VARIANT_PRECEDENCE[3]).toBe("hover")
		-- within the chrome group the per-state art rules are emitted in
		-- VARIANT_STATES order, which puts `error` after `selected`
		expect(chrome_slots.VARIANT_PRECEDENCE[4]).toBe("error")
		expect(chrome_slots.VARIANT_PRECEDENCE[5]).toBe("selected")
	end)

	it("unstated states fall back to default, and disabled beats pressed", function()
		local variants = {
			default = { contentId = "d" },
			hover = { contentId = "h" },
			disabled = { contentId = "x" },
		}
		expect(chrome_slots.variantContentFor(variants, {})).toBe("d")
		expect(chrome_slots.variantContentFor(variants, { hover = true })).toBe("h")
		-- pressed is unstated: it falls back to default rather than to nothing
		expect(chrome_slots.variantContentFor(variants, { pressed = true })).toBe("d")
		expect(chrome_slots.variantContentFor(variants, { disabled = true, pressed = true })).toBe("x")
		expect(chrome_slots.variantStateFor({ selected = true, hover = true })).toBe("hover")
	end)

	it("a bad rung-2 map is an authoring error naming the prop", function()
		local core = customFactory.new()
		local ok, err = pcall(function()
			return Facet.Controls.Slider(core, {
				id = "Bad",
				value = core:signal(1),
				min = 0,
				max = 10,
				thumbImage = { hover = "rbxassetid://1" }, -- no `default`
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "thumbImage", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "default", 1, true) ~= nil).toBe(true)
	end)
end)

describe("rung 2: the per-state map REACHES the adapter", function()
	local function mountSlider(specOverrides: any?)
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		local value = core:signal(50)
		local spec: any = { id = "Vol", label = "Vol", value = value, min = 0, max = 100 }
		for k, v in (specOverrides or {}) :: any do
			spec[k] = v
		end
		local control = Facet.Controls.Slider(core, spec)
		pres.present(UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		return adapter, control
	end

	it("blueprint -> mount -> renderer -> adapter.create carries the normalized map", function()
		local adapter, control = mountSlider({
			thumbImage = { default = "rbxassetid://100", hover = "rbxassetid://101" },
			trackImage = "rbxassetid://200",
		})
		local thumb = adapter.node("/S/Vol/TrackHost/Groove/Thumb")
		local rail = adapter.node("/S/Vol/TrackHost/Groove/Rail")
		expect(thumb.decorationHint.slot).toBe("sliderThumb")
		-- the MAP travels normalized, so the adapter reads one shape
		expect(thumb.decorationHint.imageVariants.default.asset).toBe("rbxassetid://100")
		expect(thumb.decorationHint.imageVariants.hover.asset).toBe("rbxassetid://101")
		expect(thumb.decorationHint.image).toBeNil()
		-- ...and a bare string still travels as a bare string
		expect(rail.decorationHint.image).toBe("rbxassetid://200")
		expect(rail.decorationHint.imageVariants).toBeNil()
		-- the ladder rung stays truthful for BOTH shapes
		expect(control.dump().skinRung).toBe("view")
	end)

	it("a slider with no override stays on the theme", function()
		local adapter, control = mountSlider()
		expect(adapter.node("/S/Vol/TrackHost/Groove/Thumb").decorationHint.image).toBeNil()
		expect(adapter.node("/S/Vol/TrackHost/Groove/Thumb").decorationHint.imageVariants).toBeNil()
		expect(control.dump().skinRung).toBe("theme")
	end)

	it("the adapter turns that hint into an override plan, not a theme plan", function()
		local adapter = mountSlider({ thumbImage = { default = "rbxassetid://100", hover = "rbxassetid://101" } })
		local hint = adapter.node("/S/Vol/TrackHost/Groove/Thumb").decorationHint
		-- the exact call the client target makes with that hint
		local pkg = themes.define(def())
		local plan = chrome_slots.planFor(pkg, hint.slot, { image = hint.image, imageVariants = hint.imageVariants })
		expect(plan.localOverride).toBe(true)
		expect(plan.tag).toBeNil()
		expect(plan.contentId).toBe("rbxassetid://100")
		expect(chrome_slots.variantContentFor(plan.variants, { hover = true })).toBe("rbxassetid://101")
	end)

	it("the adapter reads the hint's map, watches state, and writes the art", function()
		local read = section("local function chromeOverrideOf(handle: any): any", "\n\tend")
		expect(string.find(read, "hint.imageVariants", 1, true) ~= nil).toBe(true)
		local watch = section("local function syncOverrideVariants(handle: any, plan: any)", "\n\tend")
		expect(string.find(watch, 'GetPropertyChangedSignal("GuiState")', 1, true) ~= nil).toBe(true)
		expect(string.find(watch, "applyOverrideVariantArt(handle)", 1, true) ~= nil).toBe(true)
		local apply = section("local function applyOverrideVariantArt(handle: any)", "\n\tend")
		expect(string.find(apply, "chrome_slots.variantContentFor(variants", 1, true) ~= nil).toBe(true)
		expect(string.find(apply, "deco.Image = contentId", 1, true) ~= nil).toBe(true)
		-- ...and it is driven from every state seam the node has
		local sync = section("function syncChromeInner(handle: any)", "\n\tend\n")
		expect(string.find(sync, "syncOverrideVariants(handle, plan)", 1, true) ~= nil).toBe(true)
		local selected = section('elseif prop == "selected" then', 'elseif prop == "value" then')
		expect(string.find(selected, "applyOverrideVariantArt(handle)", 1, true) ~= nil).toBe(true)
	end)

	-- arch-F3 (rich-skinning-v2 verifier fix round). The rule: "If the map omits
	-- `disabled`, the standard disabled treatment applies over `default`
	-- (accessibility floor preserved)." A rung-2 override decoration is UNTAGGED by
	-- construction, so the emitted `:NonInteractable > .<tag>` rule cannot reach it
	-- and the floor was simply absent — a disabled overridden control rendered its
	-- resting art at FULL opacity beside a themed sibling dimmed to 0.4.
	it("the rung-2 disabled floor is the SAME number rung 1's rule carries", function()
		-- one constant, two consumers: the emitted rule's default and the adapter's
		local floor = chrome_slots.DISABLED_CONTENT_OPACITY
		expect(type(floor)).toBe("number")
		local model = sheet_model.buildPackage(themes.define(layered(FULL_STACK)))
		local disabledRule = nil
		for _, rule in model.rules do
			if
				string.find(rule.selector, ":NonInteractable", 1, true) ~= nil
				and rule.props ~= nil
				and rule.props.ImageTransparency ~= nil
			then
				disabledRule = rule
				break
			end
		end
		expect(disabledRule ~= nil).toBe(true)
		expect((disabledRule :: any).props.ImageTransparency.value).toBe(floor)

		-- the PURE decision the adapter applies: disabled dims to the floor,
		-- every other state returns the plan's resting transparency — and this
		-- holds whether or not the map declared `disabled` art, because rung 1's
		-- rule is unconditional too (the Image swap and the dim both match)
		expect(chrome_slots.variantOpacityFor({ disabled = true }, 0, floor)).toBe(floor)
		expect(chrome_slots.variantOpacityFor({ disabled = true, hover = true }, 0, floor)).toBe(floor)
		expect(chrome_slots.variantOpacityFor({ hover = true }, 0, floor)).toBe(0)
		expect(chrome_slots.variantOpacityFor({}, 0.25, floor)).toBe(0.25)
		expect(chrome_slots.variantOpacityFor({ disabled = true }, 0.25, nil)).toBe(floor)

		-- a map that omits `disabled` still resolves its RESTING art there (so the
		-- dim is the whole treatment — exactly the themed sibling's behaviour)
		local plan = chrome_slots.planFor(themes.define(def()), "sliderThumb", {
			imageVariants = { default = { asset = "rbxassetid://1" }, hover = { asset = "rbxassetid://2" } },
		})
		expect(chrome_slots.variantContentFor(plan.variants, { disabled = true })).toBe("rbxassetid://1")

		-- ...and the adapter actually writes it, from the shared constant
		local apply = section("local function applyOverrideVariantArt(handle: any)", "\n\tend")
		expect(string.find(apply, "chrome_slots.variantOpacityFor(", 1, true) ~= nil).toBe(true)
		expect(string.find(apply, "deco.ImageTransparency", 1, true) ~= nil).toBe(true)
		local shared = fs.readFile("src/tokens/chrome_slots.luau")
		expect(string.find(shared, "chrome_slots.DISABLED_CONTENT_OPACITY", 1, true) ~= nil).toBe(true)
		local sm = fs.readFile("src/tokens/sheet_model.luau")
		expect(string.find(sm, 'fill("disabledContentOpacity", chrome_slots.DISABLED_CONTENT_OPACITY)', 1, true) ~= nil).toBe(
			true
		)
	end)

	it("the watch is disconnected with the node, so nothing outlives it", function()
		local remove = section("function adapter.remove(handle: any)", "handle.instance:Destroy()")
		expect(string.find(remove, "handle.chromeOverrideConn:Disconnect()", 1, true) ~= nil).toBe(true)
		local destroyRoot = section("function adapter.destroyRoot(rootHandle: any)", "rootHandle.gui:Destroy()")
		expect(string.find(destroyRoot, "handle.chromeOverrideConn:Disconnect()", 1, true) ~= nil).toBe(true)
	end)
end)

-- ===== 5. THE FOCUS VISUAL RIDES THE DRAWN ART ============================
--
-- Director fix round 2026-07-25: "the green selection outline around the volume-
-- down stepper has excessive horizontal negative space." Root-caused live at
-- desktop under pixel-quest: the Dec button solved to 53x68 at x=265 while its
-- plate painted 29x68 at x=277, because a Button carries a UIPadding so its
-- ENGINE label clears the edges and that padding insets the DECORATION too (a
-- decoration is a child). The ring hung off the node, so it wrapped the padded
-- solved rect and left a 12px band of air on each side of the plate.
--
-- Two halves, as always: the PURE decision about which instance is the plate,
-- and the application line that actually parents the ring there.

describe("focus hugs the art, not the padded rect", function()
	it("the plate of a stack is its back-most FULL-BLEED layer, never an ornament", function()
		local stack = chrome_slots.layerPlanFor(themes.define(layered(FULL_STACK)), "panel")
		-- FULL_STACK is fill, tile, frame, edges, corners, plaque
		expect(chrome_slots.focusArtLayer(stack)).toBe(1)
		-- ...and it is the FIRST full-bleed layer, whatever precedes it
		local ornamentsFirst = chrome_slots.layerPlanFor(
			themes.define(layered({
				{ kind = "corners", asset = "ornament", size = 24 },
				{ kind = "fill", asset = "plate" },
				{ kind = "frame", asset = "border" },
			})),
			"panel"
		)
		expect(chrome_slots.focusArtLayer(ornamentsFirst)).toBe(2)
		-- a stack that paints no plate at all has nothing to hug: the caller
		-- keeps the node's own rect rather than ringing one corner ornament
		local ornamentsOnly = chrome_slots.layerPlanFor(
			themes.define(layered({ { kind = "corners", asset = "ornament", size = 24 } })),
			"panel"
		)
		expect(chrome_slots.focusArtLayer(ornamentsOnly)).toBeNil()
		-- and a node with no stack at all (nil in, nil out)
		expect(chrome_slots.focusArtLayer(nil)).toBeNil()
	end)

	it("the adapter parents the ring and the glow to the ART host, not the node", function()
		local focus = section("function adapter.setFocusVisual(handle: any, on: boolean, profile: string?)", "\n\tend")
		-- the host is chosen from the art, falling back to the node
		expect(string.find(focus, "focusArtHost(handle) or instance", 1, true) ~= nil).toBe(true)
		-- BOTH treatments land on it — a glow left on the node would reproduce
		-- the defect one package over
		expect(string.find(focus, "glow.Parent = host", 1, true) ~= nil).toBe(true)
		-- the stroke's parent DERIVES from the host: the host itself, or the
		-- clip-inset holder built ON the host (director virtual-controller round —
		-- a Border stroke under a scroll clip drew outside and got eaten)
		expect(string.find(focus, "local strokeParent: GuiObject = host", 1, true) ~= nil).toBe(true)
		expect(string.find(focus, "stroke.Parent = strokeParent", 1, true) ~= nil).toBe(true)
		-- ...and the ring is LOOKED UP on the host (direct or inside the inset
		-- holder), or a swap that moved the art would build a second one
		expect(string.find(focus, 'host:FindFirstChild("FocusRing")', 1, true) ~= nil).toBe(true)
		-- clip-hosted nodes ride the FLOAT ring: a topmost-z SIBLING inside the
		-- clip host (flat tree + Sibling z means nothing else can cover it)
		expect(string.find(focus, "FocusRingFloat", 1, true) ~= nil).toBe(true)
		expect(string.find(focus, "handle.instanceHost.instance", 1, true) ~= nil).toBe(true)
		-- the previous host is cleared before the new one is painted
		expect(at(focus, "handle.focusVisualHost") < at(focus, "glow.Parent = host")).toBe(true)

		-- the host decision itself is the PURE one, and it prefers the single
		-- nine-slice decoration before consulting the ladder
		local host = section("local function focusArtHost(handle: any): GuiObject?", "\n\tend")
		expect(at(host, "handle.chrome") < at(host, "handle.chromeStack")).toBe(true)
		expect(string.find(host, "chrome_slots.focusArtLayer(", 1, true) ~= nil).toBe(true)

		-- APPLICATION, not only emission: a chrome sync that creates or destroys
		-- the art under a focused node re-places the visual
		local sync = section("\tfunction syncChrome(handle: any)", "\n\tend")
		expect(at(sync, "syncChromeInner(handle)") < at(sync, "ctx.setFocusVisual(handle, true")).toBe(true)

		-- THE FLOAT RING IS DESTROYED WITH ITS NODE. Every other focus visual is a
		-- CHILD of the focused instance and falls with it; the float is deliberately
		-- a SIBLING parented to the clip host, so `handle.instance:Destroy()` leaves
		-- it behind as an orphan accent rectangle at the rect the row used to have.
		-- A windowed list slides rows in and out under a live focus constantly,
		-- which is how a shipped capture came to show two accent rings at once — one
		-- real, one a ghost of a row that had scrolled away (found 2026-07-31 in the
		-- parallel-Sponsor review, F4/ruling (c) (iv)).
		local remove = section("\tfunction adapter.remove(handle: any)", "\n\t\thandle.instance:Destroy()")
		expect(string.find(remove, "handle.focusRingFloat:Destroy()", 1, true) ~= nil).toBe(true)
		expect(at(remove, "handle.focusRingFloat:Destroy()") < at(remove, "handle.focusVisualHost = nil")).toBe(true)
		-- ...and it is nil'd, so a reused handle cannot re-aim a destroyed frame
		expect(string.find(remove, "handle.focusRingFloat = nil", 1, true) ~= nil).toBe(true)
	end)

	it("hit geometry is NOT the ring's instance, so the 47px floor is untouched", function()
		-- the expander is a SIBLING sized from the solver's hit rect; nothing in
		-- the focus path reads or writes it
		local focus = section("function adapter.setFocusVisual(handle: any, on: boolean, profile: string?)", "\n\tend")
		expect(string.find(focus, "hitExpander", 1, true)).toBeNil()
		-- the sizing moved into the shared placement helper with RS-A16-D1b (the
		-- expander is now re-based by the same function that re-bases the control),
		-- so the anchor follows it; the claim is unchanged — the hit surface is sized
		-- from the solver's hit rect and nothing in the focus path touches it
		local hit = section("local function applyHitExpander(handle: any)", "\n\tend")
		expect(string.find(hit, "expander.Size = UDim2.fromOffset(rect.w, rect.h)", 1, true) ~= nil).toBe(true)
		expect(string.find(hit, "handle.hitRectWant", 1, true) ~= nil).toBe(true)
	end)
end)
