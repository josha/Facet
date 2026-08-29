--!strict
-- LAYERED DECORATION SLOTS (ADR-0020 R1, rich-skinning-v2 package P1).
--
-- A slot recipe may declare a bounded STACK of layers — fill, frame, corners,
-- edges, plaque, tile — as DATA with a fixed anchoring vocabulary. The
-- propositions, each of which is only worth anything if it can fail:
--
--   1. every rejection class exists and NAMES the field, the rule and the fix:
--      an unknown kind, a field borrowed from another kind, a stack past the
--      cap, a hole in the array, a sliced layer whose asset has no slice centre;
--   2. the rules a layered package compiles to carry the package's own values,
--      one paint rule per layer, RULE-owned from birth (rs-m2's defeat
--      refinement) with z-order = array order;
--   3. suppression (R9) covers layered nodes exactly as it covers nine-sliced
--      ones, and a flat theme still emits and creates nothing;
--   4. the census counts the ladder per KIND and publishes the plaque overhang,
--      so cost is a number rather than an impression (ledger RS-A17).

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local themes = require("../src/themes/package")
local snapshot = require("../src/themes/snapshot")
local sheet_model = require("../src/tokens/sheet_model")
local chrome_slots = require("../src/tokens/chrome_slots")

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

-- a definition with the art a layered recipe needs, cloned per test so a
-- mutation cannot leak between them
local function def(): any
	local base = snapshot.neutralPackage()
	return {
		identity = {
			id = "layer-test",
			displayName = "Layer Test",
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
		},
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

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

local function errorsOf(report: any, class: string): { any }
	local out: { any } = {}
	for _, entry in report.errors do
		if entry.class == class then
			table.insert(out, entry)
		end
	end
	return out
end

local function ruleNamed(model: any, name: string): any
	for _, rule in model.rules do
		if rule.name == name then
			return rule
		end
	end
	return nil
end

local FULL_STACK = {
	{ kind = "fill", asset = "plate" },
	{ kind = "tile", asset = "stripe", tileSize = { w = 32, h = 24 } },
	{ kind = "frame", asset = "border" },
	{ kind = "edges", asset = "border", sides = { "top", "bottom" }, thickness = 8, margin = 24 },
	{ kind = "corners", asset = "ornament", size = 24, topLeft = "ornamentGold" },
	{ kind = "plaque", asset = "banner", size = { w = 140, h = 36 }, edge = "top", overhang = 18, text = true },
}

describe("themes.define: a layered recipe compiles to inspectable layer data", function()
	it("accepts the whole R1 vocabulary in one stack", function()
		local pkg, report = themes.define(layered(FULL_STACK))
		expect(report.ok).toBe(true)
		expect(pkg ~= nil).toBe(true)
		expect(pkg.chrome.panel.kind).toBe("layered")
		expect(#pkg.chrome.panel.layers).toBe(6)
		expect(pkg.chrome.panel.layers[1].kind).toBe("fill")
		expect(pkg.chrome.panel.layers[6].overhang).toBe(18)
		expect(table.isfrozen(pkg.chrome.panel.layers)).toBe(true)
	end)

	it("plans the stack with z-order = array order and one tag per layer", function()
		local pkg = themes.define(layered(FULL_STACK))
		local stack = chrome_slots.layerPlanFor(pkg, "panel")
		expect(stack ~= nil).toBe(true)
		expect(#stack.layers).toBe(6)
		for index, layer in stack.layers do
			expect(layer.index).toBe(index)
			expect(layer.tag).toBe(`facet-chrome-panel-{index}`)
		end
		-- the stretching kinds slice; the fixed-size tokens paint whole; tile
		-- repeats (rs-m1 proved TileSize rule-settable, so this is a real kind)
		expect(stack.layers[1].scaleType).toBe("Slice")
		expect(stack.layers[2].scaleType).toBe("Tile")
		expect(stack.layers[3].scaleType).toBe("Slice")
		expect(stack.layers[4].scaleType).toBe("Slice")
		expect(stack.layers[5].scaleType).toBe("Stretch")
		expect(stack.layers[6].scaleType).toBe("Stretch")
		-- a tiled edge rail repeats instead of slicing
		local tiledRail = themes.define(layered({
			{ kind = "edges", asset = "border", sides = { "left" }, thickness = 8, tile = 32 },
		}))
		expect(chrome_slots.layerPlanFor(tiledRail, "panel").layers[1].scaleType).toBe("Tile")
	end)

	it("publishes the plaque overhang as reservation metadata, not a runtime surprise", function()
		local pkg = themes.define(layered(FULL_STACK))
		local overhang = chrome_slots.overhangFor(pkg, "panel")
		expect(overhang.top).toBe(18)
		expect(overhang.bottom).toBe(0)
		expect(chrome_slots.hasOverhang(overhang)).toBe(true)
		-- ...and a stack with no plaque publishes zeros, so a caller has one shape
		local flat = themes.define(layered({ { kind = "fill", asset = "plate" } }))
		expect(chrome_slots.hasOverhang(chrome_slots.overhangFor(flat, "panel"))).toBe(false)
		expect(chrome_slots.hasOverhang(chrome_slots.overhangFor(snapshot.neutralPackage(), "panel"))).toBe(false)
	end)

	it("derives that metadata from the LAYER BOXES, one kind at a time", function()
		-- RS-A16-D2. The extent a stack paints outside its rect is not a special
		-- case for one kind: it is a property of the boxes `layerBoxes` already
		-- produces, measured per kind. Deriving it there is what makes the census
		-- and the snapshot's reservation the same number by construction.
		local pkg = themes.define(layered(FULL_STACK))
		local stack = chrome_slots.layerPlanFor(pkg, "panel")
		local perKind: { [string]: any } = {}
		for _, layer in stack.layers do
			perKind[layer.kind] = chrome_slots.layerOutwardExtent(layer)
		end
		-- the plaque is the ONLY v1 kind that paints outside a healthy host: its
		-- box is anchored at the parent's top edge and offset by -overhang
		expect(perKind.plaque.top).toBe(18)
		expect(perKind.plaque.bottom + perKind.plaque.left + perKind.plaque.right).toBe(0)
		-- ...and the other five are pinned INSIDE by their own anchoring idiom.
		-- Asserted, not assumed: a corner ornament anchors its own corner ON the
		-- parent's, a rail's margin holds it in, and a full-bleed inset shrinks.
		for _, kind in { "fill", "frame", "tile", "corners", "edges" } do
			local e = perKind[kind]
			expect(e ~= nil).toBe(true)
			expect(e.top + e.right + e.bottom + e.left).toBe(0)
		end
		-- every kind in the vocabulary answers, so a kind added later cannot
		-- reach the census without an extent
		expect(#chrome_slots.LAYER_KINDS).toBe(6)
		for _, kind in chrome_slots.LAYER_KINDS do
			expect(perKind[kind] ~= nil).toBe(true)
		end
	end)

	it("RESERVES it: the snapshot publishes the plaque overhang as a chrome outset", function()
		-- RS-A16-D2, the defect itself. The overhang was validated, painted and
		-- censused — and never reserved, so the ornate nameplate paints through
		-- the label of the row above it (measured live: 792 px2 at desktop, 1176
		-- at console). `chromeOutsets` is the ONE seam the renderer turns into a
		-- margin; the plaque has to be in it.
		local snap = snapshot.resolve(themes.define(layered(FULL_STACK)), nil, {})
		expect(snap.chromeOutsets.panel ~= nil).toBe(true)
		expect(snap.chromeOutsets.panel.top).toBe(18)
		expect(snap.chromeOutsets.panel.bottom).toBe(0)
		expect(snap.chromeOutsets.panel.left).toBe(0)
		expect(snap.chromeOutsets.panel.right).toBe(0)
		-- the reservation follows the SLOT, so a plaque on a control reserves for
		-- the control and leaves the panel alone
		local onControl = snapshot.resolve(themes.define(layered(FULL_STACK, "control")), nil, {})
		expect(onControl.chromeOutsets.control.top).toBe(18)
		expect(onControl.chromeOutsets.panel).toBeNil()
	end)

	it("a stack with no plaque, and every flat package, publishes NOTHING", function()
		-- the byte-unchanged half: an empty table makes the renderer's margin
		-- block a no-op, which is why swapping between two flat packages cannot
		-- move geometry.
		local noPlaque = themes.define(layered({
			{ kind = "fill", asset = "plate" },
			{ kind = "corners", asset = "ornament", size = 24 },
			{ kind = "edges", asset = "border", sides = { "top" }, thickness = 8, margin = 24 },
		}))
		expect(next(snapshot.resolve(noPlaque, nil, {}).chromeOutsets)).toBeNil()
		expect(next(snapshot.neutral().chromeOutsets)).toBeNil()
	end)

	it("EVERY censused extent is reserved: no slot may publish one without the other", function()
		-- The structural half of RS-A16-D2. The census (inspection) and the
		-- snapshot (reservation) read the same per-kind extents, so a future slot
		-- kind cannot ship "painted and published but never reserved" again.
		local pkg = themes.define(layered(FULL_STACK, "control"))
		local census = sheet_model.buildPackage(pkg).census
		local outsets = snapshot.resolve(pkg, nil, {}).chromeOutsets
		expect(next(census.overhang) ~= nil).toBe(true)
		for slot, extent in census.overhang do
			local reserved = outsets[slot]
			expect(reserved ~= nil).toBe(true)
			for _, side in { "top", "right", "bottom", "left" } do
				expect(reserved[side] >= extent[side]).toBe(true)
			end
		end
	end)

	it("carries every layer's assets into the preload seam", function()
		local pkg = themes.define(layered(FULL_STACK))
		local names: { [string]: boolean } = {}
		for _, entry in chrome_slots.assetsToPreload(pkg, "install") do
			names[entry.name] = true
		end
		for _, name in { "plate", "stripe", "border", "banner", "ornament", "ornamentGold" } do
			expect(names[name]).toBe(true)
		end
	end)
end)

describe("themes.define: every layer rejection names the field, the rule and the fix", function()
	it("rejects an unknown layer kind, listing the legal set", function()
		local _, report = themes.define(layered({ { kind = "shadowe", asset = "plate" } }))
		expect(report.ok).toBe(false)
		local entry = errorsOf(report, "layerKind")[1]
		expect(entry ~= nil).toBe(true)
		expect(entry.field).toBe("chrome.panel.layers[1].kind")
		expect(string.find(entry.message, "shadowe", 1, true) ~= nil).toBe(true)
		expect(string.find(entry.fix, "edges", 1, true) ~= nil).toBe(true)
	end)

	it("rejects a geometry field borrowed from another kind", function()
		local _, report = themes.define(layered({
			{ kind = "corners", asset = "ornament", size = 24, tileSize = { w = 8, h = 8 } },
		}))
		expect(report.ok).toBe(false)
		local entry = errorsOf(report, "layerField")[1]
		expect(entry.field).toBe("chrome.panel.layers[1].tileSize")
		expect(string.find(entry.message, "corners", 1, true) ~= nil).toBe(true)
		-- the reason, not just the refusal: a field from another kind would be
		-- accepted and never read
		expect(string.find(entry.message, "never read", 1, true) ~= nil).toBe(true)
	end)

	-- ===== the FULL-BLEED inset (director round 5b) =========================
	--
	-- glossy-touch's stripe tile painted its square corners over the trough's
	-- rounded ends, so the bar read blocky with no backing to blame. `inset`
	-- shrinks a full-bleed layer's box symmetrically per axis — the ONE field
	-- the three full-bleed kinds share, and a compile error on the other three.

	it("accepts `inset` on every full-bleed kind and rejects it on the rest", function()
		for _, kind in chrome_slots.FULL_BLEED_KINDS do
			local layer: any =
				{ kind = kind, asset = if kind == "tile" then "stripe" else "plate", inset = { x = 6, y = 2 } }
			if kind == "tile" then
				layer.tileSize = { w = 24, h = 24 }
			end
			local pkg, report = themes.define(layered({ layer }))
			expect(report.ok).toBe(true)
			assert(pkg ~= nil, `a '{kind}' layer must accept an inset`)
			expect(pkg.chrome.panel.layers[1].inset.x).toBe(6)
		end
		-- ...and the fixed-size kinds anchor their OWN boxes, so the field would
		-- be accepted and never read. The closed-set error names the kind.
		local rejected = {
			{ kind = "corners", asset = "ornament", size = 24, inset = { x = 4, y = 4 } },
			{ kind = "edges", asset = "border", sides = { "top" }, thickness = 8, inset = { x = 4, y = 4 } },
			{ kind = "plaque", asset = "banner", size = { w = 40, h = 20 }, inset = { x = 4, y = 4 } },
		}
		for _, layer in rejected do
			local _, report = themes.define(layered({ layer }))
			expect(report.ok).toBe(false)
			local entry = errorsOf(report, "layerField")[1]
			expect(entry.field).toBe("chrome.panel.layers[1].inset")
			expect(string.find(entry.message, layer.kind, 1, true) ~= nil).toBe(true)
			expect(string.find(entry.message, "never read", 1, true) ~= nil).toBe(true)
		end
	end)

	it("rejects a malformed inset: negative, infinite, non-table, wrong axis", function()
		local bad = {
			{ x = -1, y = 0 },
			{ x = 0, y = math.huge },
			{ left = 6 }, -- the four-sided vocabulary is NOT this field's
			{ x = "6" },
			6,
		}
		for _, value in bad :: any do
			local _, report = themes.define(layered({
				{ kind = "tile", asset = "stripe", tileSize = { w = 24, h = 24 }, inset = value },
			}))
			expect(report.ok).toBe(false)
			local entry = errorsOf(report, "layerField")[1]
			expect(entry.field).toBe("chrome.panel.layers[1].inset")
			expect(string.find(entry.fix, "x = 6", 1, true) ~= nil).toBe(true)
		end
	end)

	it("the BOX math: symmetric per axis, and absent inset is byte-identical", function()
		local pkg = themes.define(layered({
			{ kind = "fill", asset = "plate" },
			{ kind = "tile", asset = "stripe", tileSize = { w = 24, h = 24 }, inset = { x = 10, y = 2 } },
		}))
		local stack = chrome_slots.layerPlanFor(pkg, "panel")
		local plain = chrome_slots.layerBoxes(stack.layers[1])[1]
		-- no inset: the rectangle full bleed has always produced
		expect(plain.position.xOffset).toBe(0)
		expect(plain.position.yOffset).toBe(0)
		expect(plain.size.xScale).toBe(1)
		expect(plain.size.xOffset).toBe(0)
		expect(plain.size.yOffset).toBe(0)
		local inset = chrome_slots.layerBoxes(stack.layers[2])[1]
		-- x in from the left, 2x narrower => the SAME gap at both ends
		expect(inset.anchor.x).toBe(0)
		expect(inset.position.xScale).toBe(0)
		expect(inset.position.xOffset).toBe(10)
		expect(inset.size.xScale).toBe(1)
		expect(inset.size.xOffset).toBe(-20)
		expect(inset.position.yOffset).toBe(2)
		expect(inset.size.yScale).toBe(1)
		expect(inset.size.yOffset).toBe(-4)
		-- ...and one axis alone leaves the other full-bleed
		expect(chrome_slots.layerInsetOf({ geometry = { inset = { x = 8 } } }).y).toBe(0)
		expect(chrome_slots.layerInsetOf({ geometry = {} }).x).toBe(0)
		expect(chrome_slots.layerInsetOf(nil).x).toBe(0)
	end)

	it("no other reference package declares an inset — they are byte-unchanged", function()
		-- the blast radius, counted rather than asserted by eye
		local declaring: { string } = {}
		for _, name in
			{
				"classic_desktop",
				"fantasy_ornate",
				"pixel_quest",
				"glossy_mobile",
				"scifi_hud",
				"compact_pointer",
				"glossy_touch",
			}
		do
			local pkg = (require(`../examples/themes/{name}`) :: any).build(Facet.themes)
			for _, slot in chrome_slots.SLOTS do
				local stack = chrome_slots.layerPlanFor(pkg, slot)
				if stack == nil then
					continue
				end
				for _, layer in stack.layers do
					local inset = chrome_slots.layerInsetOf(layer)
					if inset.x ~= 0 or inset.y ~= 0 then
						table.insert(declaring, `{name}.{slot}.L{layer.index}`)
					end
				end
			end
		end
		expect(#declaring).toBe(1)
		expect(declaring[1]).toBe("glossy_touch.barTrack.L2")
	end)

	it("glossy-touch's stripe is MASKED to the trough, inset only off its lines", function()
		-- 5c: the mask decides the silhouette, so the inset no longer has to buy
		-- the corner. It drops to the ART's two lines — `bar_track` in
		-- generate_art.py draws a 1px hard rim and a 1px lit bottom lip — while
		-- the pill clips the hatch along the arc.
		local pkg = (require("../examples/themes/glossy_touch") :: any).build(Facet.themes)
		local stack = chrome_slots.layerPlanFor(pkg, "barTrack")
		expect(stack.layers[1].kind).toBe("fill") -- the trough itself: full bleed
		expect(chrome_slots.layerInsetOf(stack.layers[1]).x).toBe(0)
		expect(chrome_slots.layerMaskOf(stack.layers[1])).toBeNil()
		expect(stack.layers[2].kind).toBe("tile")
		expect(chrome_slots.layerMaskOf(stack.layers[2])).toBe("pill")
		local inset = chrome_slots.layerInsetOf(stack.layers[2])
		expect(inset.x).toBe(2)
		expect(inset.y).toBe(2)
		local box = chrome_slots.layerBoxes(stack.layers[2])[1]
		expect(box.position.xOffset).toBe(2)
		expect(box.size.xOffset).toBe(-4)
	end)

	it("no other reference package declares a mask — one canvas in the library", function()
		local declaring: { string } = {}
		for _, name in
			{
				"classic_desktop",
				"fantasy_ornate",
				"pixel_quest",
				"glossy_mobile",
				"scifi_hud",
				"compact_pointer",
				"glossy_touch",
			}
		do
			local pkg = (require(`../examples/themes/{name}`) :: any).build(Facet.themes)
			for _, slot in chrome_slots.SLOTS do
				local stack = chrome_slots.layerPlanFor(pkg, slot)
				if stack == nil then
					continue
				end
				for _, layer in stack.layers do
					if chrome_slots.layerMaskOf(layer) ~= nil then
						table.insert(declaring, `{name}.{slot}.L{layer.index}`)
					end
				end
			end
		end
		expect(#declaring).toBe(1)
		expect(declaring[1]).toBe("glossy_touch.barTrack.L2")
	end)

	-- ===== the FULL-BLEED mask (director round 5c, probe rs-m9) =============

	it("accepts `mask` on every full-bleed kind and rejects it on the rest", function()
		for _, kind in chrome_slots.FULL_BLEED_KINDS do
			local layer: any = { kind = kind, asset = if kind == "tile" then "stripe" else "plate", mask = "pill" }
			if kind == "tile" then
				layer.tileSize = { w = 24, h = 24 }
			end
			local pkg, report = themes.define(layered({ layer }))
			expect(report.ok).toBe(true)
			assert(pkg ~= nil, `a '{kind}' layer must accept a mask`)
			expect(pkg.chrome.panel.layers[1].mask).toBe("pill")
		end
		for _, layer in
			{
				{ kind = "corners", asset = "ornament", size = 24, mask = "pill" },
				{ kind = "edges", asset = "border", sides = { "top" }, thickness = 8, mask = "pill" },
				{ kind = "plaque", asset = "banner", size = { w = 40, h = 20 }, mask = "pill" },
			}
		do
			local _, report = themes.define(layered({ layer }))
			expect(report.ok).toBe(false)
			local entry = errorsOf(report, "layerField")[1]
			expect(entry.field).toBe("chrome.panel.layers[1].mask")
			expect(string.find(entry.message, layer.kind, 1, true) ~= nil).toBe(true)
		end
	end)

	it("the mask set is CLOSED to the shape rs-m9 measured", function()
		-- a vocabulary that ships unmeasured mask shapes is how a skin ends up
		-- almost right — the same reason PLAQUE_EDGES is one edge
		expect(#chrome_slots.LAYER_MASKS).toBe(1)
		expect(chrome_slots.isLayerMask("pill")).toBe(true)
		expect(chrome_slots.isLayerMask("circle")).toBe(false)
		local _, report = themes.define(layered({
			{ kind = "tile", asset = "stripe", tileSize = { w = 24, h = 24 }, mask = "squircle" },
		}))
		expect(report.ok).toBe(false)
		local entry = errorsOf(report, "layerField")[1]
		expect(entry.field).toBe("chrome.panel.layers[1].mask")
		expect(string.find(entry.message, "squircle", 1, true) ~= nil).toBe(true)
		expect(string.find(entry.message, "CanvasGroup", 1, true) ~= nil).toBe(true)
		expect(string.find(entry.fix, "pill", 1, true) ~= nil).toBe(true)
	end)

	it("the plan carries the mask, and an undeclared one reads nil", function()
		local pkg = themes.define(layered({
			{ kind = "fill", asset = "plate" },
			{ kind = "tile", asset = "stripe", tileSize = { w = 24, h = 24 }, mask = "pill", inset = { x = 2, y = 2 } },
		}))
		local stack = chrome_slots.layerPlanFor(pkg, "panel")
		expect(chrome_slots.layerMaskOf(stack.layers[1])).toBeNil()
		expect(chrome_slots.layerMaskOf(stack.layers[2])).toBe("pill")
		expect(chrome_slots.layerMaskOf(nil)).toBeNil()
		-- MASK AND INSET COMPOSE: the mask decides the silhouette, the inset how
		-- far the content is held off the rim, and the BOX still comes from inset
		local box = chrome_slots.layerBoxes(stack.layers[2])[1]
		expect(box.position.xOffset).toBe(2)
		expect(box.size.xOffset).toBe(-4)
	end)

	it("rejects a stack past the cap, and an empty one, and one with a hole", function()
		local tooMany: { any } = {}
		for _ = 1, chrome_slots.MAX_LAYERS + 1 do
			table.insert(tooMany, { kind = "fill", asset = "plate" })
		end
		local _, over = themes.define(layered(tooMany))
		expect(over.ok).toBe(false)
		local entry = errorsOf(over, "layerBounds")[1]
		expect(entry.field).toBe("chrome.panel.layers")
		expect(string.find(entry.message, tostring(chrome_slots.MAX_LAYERS), 1, true) ~= nil).toBe(true)

		local _, empty = themes.define(layered({}))
		expect(empty.ok).toBe(false)
		expect(#errorsOf(empty, "layerBounds") > 0).toBe(true)

		local holed = layered({ { kind = "fill", asset = "plate" } })
		holed.chrome.panel.layers.frame = { kind = "frame", asset = "border" }
		local _, gap = themes.define(holed)
		expect(gap.ok).toBe(false)
		expect(string.find(errorsOf(gap, "layerBounds")[1].message, "contiguous", 1, true) ~= nil).toBe(true)
	end)

	it("rejects a sliced layer whose asset declares no slice centre", function()
		-- the failure this catches is a skin that looks almost right at ONE size
		local _, report = themes.define(layered({ { kind = "fill", asset = "ornament" } }))
		expect(report.ok).toBe(false)
		local entry = errorsOf(report, "nineSliceFallback")[1]
		expect(entry.field).toBe("chrome.panel.layers[1].asset")
		expect(string.find(entry.message, "sliceCenter", 1, true) ~= nil).toBe(true)
	end)

	it("rejects an asset the package never declared, per state", function()
		local _, report = themes.define(layered({ { kind = "fill", asset = "nope" } }))
		expect(report.ok).toBe(false)
		local entry = errorsOf(report, "missingAsset")[1]
		expect(entry.field).toBe("chrome.panel.layers[1].asset")
		expect(string.find(entry.message, "nope", 1, true) ~= nil).toBe(true)
	end)

	it("rejects malformed per-kind geometry with the shape it wanted", function()
		local cases = {
			{ layer = { kind = "corners", asset = "ornament" }, field = "chrome.panel.layers[1].size" },
			{
				layer = { kind = "edges", asset = "border", thickness = 8 },
				field = "chrome.panel.layers[1].sides",
			},
			{
				layer = { kind = "edges", asset = "border", sides = { "top", "top" }, thickness = 8 },
				field = "chrome.panel.layers[1].sides",
			},
			{
				layer = { kind = "edges", asset = "border", sides = { "middle" }, thickness = 8 },
				field = "chrome.panel.layers[1].sides",
			},
			{
				layer = { kind = "edges", asset = "border", sides = { "top" }, thickness = 0 },
				field = "chrome.panel.layers[1].thickness",
			},
			{
				layer = { kind = "plaque", asset = "banner", size = { w = 140 } },
				field = "chrome.panel.layers[1].size",
			},
			{
				layer = { kind = "plaque", asset = "banner", size = { w = 140, h = 36 }, edge = "bottom" },
				field = "chrome.panel.layers[1].edge",
			},
			{
				layer = { kind = "plaque", asset = "banner", size = { w = 1, h = 1 }, overhang = -4 },
				field = "chrome.panel.layers[1].overhang",
			},
			{ layer = { kind = "tile", asset = "stripe" }, field = "chrome.panel.layers[1].tileSize" },
			-- the plaque TEXT sub-slot's padding (arch verifier F2): meaningless
			-- without `text`, and a typo'd side is padding that silently is not there
			{
				layer = {
					kind = "plaque",
					asset = "banner",
					size = { w = 140, h = 36 },
					textInsets = { top = 6 },
				},
				field = "chrome.panel.layers[1].textInsets",
			},
			{
				layer = {
					kind = "plaque",
					asset = "banner",
					size = { w = 140, h = 36 },
					text = true,
					textInsets = { top = 6, rigth = 12 },
				},
				field = "chrome.panel.layers[1].textInsets",
			},
			{
				layer = {
					kind = "plaque",
					asset = "banner",
					size = { w = 140, h = 36 },
					text = true,
					textInsets = { top = -6 },
				},
				field = "chrome.panel.layers[1].textInsets",
			},
		}
		for _, case in cases do
			local _, report = themes.define(layered({ case.layer }))
			expect(report.ok).toBe(false)
			local hit = false
			for _, entry in errorsOf(report, "layerField") do
				hit = hit or entry.field == case.field
			end
			expect(hit).toBe(true)
		end
	end)

	it("rejects layers on a recipe that is not layered, and art on one that is", function()
		local onNine = def()
		onNine.chrome.panel = {
			kind = "nineSlice",
			asset = "plate",
			fallback = "native",
			contentInsets = { top = 8, right = 8, bottom = 8, left = 8 },
			layers = { { kind = "fill", asset = "plate" } },
		}
		local _, report = themes.define(onNine)
		expect(report.ok).toBe(false)
		expect(errorsOf(report, "layerKind")[1].field).toBe("chrome.panel.layers")

		local withAsset = layered({ { kind = "fill", asset = "plate" } })
		withAsset.chrome.panel.asset = "plate"
		local _, second = themes.define(withAsset)
		expect(second.ok).toBe(false)
		expect(errorsOf(second, "layerField")[1].field).toBe("chrome.panel.asset")
	end)

	it("rejects a layered scrollbar for the canvas-space reason", function()
		local d = layered({ { kind = "fill", asset = "plate" } }, "scrollbar")
		local _, report = themes.define(d)
		expect(report.ok).toBe(false)
		local hit = false
		for _, entry in report.errors do
			hit = hit
				or (entry.field == "chrome.scrollbar.kind" and string.find(entry.message, "CANVAS", 1, true) ~= nil)
		end
		expect(hit).toBe(true)
	end)

	it("rejects a layered barFill because the fill is clipped art, not a layer host", function()
		-- P5 found this the expensive way: `layers` on `barFill` compiled clean and
		-- painted NOTHING, because the adapter's value-display branch runs first
		-- (the fill's art lives inside the ClipsDescendants window at FULL track
		-- size — rs-m4) and returns before any stack is built. A stack that is
		-- silently inert is exactly the defect class this stage exists to remove.
		local d = layered({ { kind = "fill", asset = "plate" } }, "barFill")
		local _, report = themes.define(d)
		expect(report.ok).toBe(false)
		local entry: any = nil
		for _, candidate in report.errors do
			if candidate.field == "chrome.barFill.kind" then
				entry = candidate
			end
		end
		expect(entry ~= nil).toBe(true)
		-- names the slot, states the reason, shows the fix (ADR-0019 error contract)
		expect(string.find(entry.message, "barFill", 1, true) ~= nil).toBe(true)
		expect(string.find(entry.message, "clipped", 1, true) ~= nil).toBe(true)
		expect(string.find(entry.message, "PAINT NOTHING", 1, true) ~= nil).toBe(true)
		expect(string.find(entry.fix, "barTrack", 1, true) ~= nil).toBe(true)
		--[[ THE FIX STATES THE MOVE, IT DOES NOT NAME A PACKAGE (wave
			THEME-UNBUNDLE). This used to assert the message named `glossy-touch` as
			the shipped precedent. The reference packages are OPTIONAL artifacts now
			(build/themes/<Name>.rbxm, docs/guide/13-theme-catalog.md) and a
			consumer reading this diagnostic may have installed none of them, so a
			message naming one advertises a file they do not have.
			`tools/check_library_purity.py` is the guard; this is the suite's echo of
			it at the one message that carried the defect. ]]
		expect(string.find(entry.fix, "nineSlice", 1, true) ~= nil).toBe(true)
		expect(string.find(entry.fix, "glossy-touch", 1, true) == nil).toBe(true)
		-- ...and the sibling bar slots that DO host a stack still compile, so the
		-- rejection is a fact about the clipped fill and not about bars
		local track = layered({ { kind = "fill", asset = "plate" } }, "barTrack")
		-- ...on a rail tall enough to hold the helper's 10px contentInsets: the
		-- neutral 6px default cannot, and that is now a compile error of its own
		-- (RS-A16-D3), which is a fact about the TRACK HEIGHT rather than about
		-- whether a bar slot may host a stack
		track.metrics.controls.progress = { trackHeight = 28, rowMinHeight = 36 }
		expect(select(2, themes.define(track)).ok).toBe(true)
	end)

	it("requires the declared native fallback, exactly as a nineSlice recipe does", function()
		local d = layered({ { kind = "fill", asset = "plate" } })
		d.chrome.panel.fallback = nil
		local _, report = themes.define(d)
		expect(report.ok).toBe(false)
		expect(errorsOf(report, "nineSliceFallback")[1].field).toBe("chrome.panel.fallback")
	end)
end)

describe("buildPackage: a layer stack compiles to one rule-owned paint rule per layer", function()
	it("carries the package's own values, in array order", function()
		local pkg = themes.define(layered(FULL_STACK))
		local model = sheet_model.buildPackage(pkg)
		local fill = ruleNamed(model, "Chrome — panel L1 fill")
		expect(fill.selector).toBe(".facet-chrome-panel-1")
		expect(fill.props.Image).toBe(pkg.assets.plate.contentId)
		expect(fill.props.ScaleType.item).toBe("Slice")
		expect(fill.props.SliceCenter.x0).toBe(8)
		expect(fill.props.SliceScale.value).toBe(1)
		expect(fill.props.ImageColor3).toBe("$ChromeTint")
		-- EVERY paint property is rule-owned from birth (rs-m2): the resting
		-- transparency is a rule, never an adapter write, or a later-matching
		-- state rule would be permanently defeated
		expect(fill.props.ImageTransparency.value).toBe(0)

		local tile = ruleNamed(model, "Chrome — panel L2 tile")
		expect(tile.props.ScaleType.item).toBe("Tile")
		expect(tile.props.TileSize.kind).toBe("udim2")
		expect(tile.props.TileSize.xOffset).toBe(32)
		expect(tile.props.TileSize.yOffset).toBe(24)
		-- px offsets are the canonical form: rs-m1 measured scale components as a
		-- fraction of the LABEL, which is a different idiom entirely
		expect(tile.props.TileSize.xScale).toBe(0)

		-- z-order is array order, and the rules keep it
		local order: { number } = {}
		for index, rule in model.rules do
			if string.find(rule.selector, ".facet-chrome-panel-", 1, true) == 1 then
				table.insert(order, index)
			end
		end
		expect(#order > 0).toBe(true)
		expect(order[1] < order[#order]).toBe(true)
	end)

	it("gives a per-corner override its own tag so its three siblings are untouched", function()
		local model = sheet_model.buildPackage(themes.define(layered(FULL_STACK)))
		local shared = ruleNamed(model, "Chrome — panel L5 corners")
		local override = ruleNamed(model, "Chrome — panel L5 corners topLeft")
		expect(shared.selector).toBe(".facet-chrome-panel-5")
		expect(override.selector).toBe(".facet-chrome-panel-5-topLeft")
		expect(override.props.Image).never().toBe(shared.props.Image)
		-- the override lands LATER in the cascade, which is what makes it win on
		-- that one instance (measured cascade: priority then insertion order)
		local sharedAt, overrideAt = 0, 0
		for index, rule in model.rules do
			if rule.name == shared.name then
				sharedAt = index
			elseif rule.name == override.name then
				overrideAt = index
			end
		end
		expect(overrideAt > sharedAt).toBe(true)
	end)

	it("suppresses the native plate under the stack, exactly as under a nine-slice", function()
		local model = sheet_model.buildPackage(themes.define(layered(FULL_STACK)))
		expect(ruleNamed(model, "Skinned — panel").props.BackgroundTransparency.value).toBe(1)
		expect(ruleNamed(model, "Skinned — panel corner").props.CornerRadius.offset).toBe(0)
		expect(ruleNamed(model, "Skinned — panel outline").props.Thickness.value).toBe(0)
	end)

	it("tints and fails over per layer, and yields the whole stack for a field caret", function()
		local model = sheet_model.buildPackage(themes.define(layered(FULL_STACK)))
		expect(ruleNamed(model, "Chrome — panel L1 fill hover").selector).toBe(
			".facet-interactive.facet-pointer-live:Hover > .facet-chrome-panel-1"
		)
		expect(ruleNamed(model, "Chrome — panel L3 frame pressed").props.ImageColor3).toBe("$ChromeTintPressed")
		expect(ruleNamed(model, "Chrome — panel L3 frame disabled").props.ImageTransparency ~= nil).toBe(true)
		-- the BACK layer carries the native fallback paint; the rest only hide,
		-- because a half-painted ladder reads as broken rather than degraded. Since
		-- RS-A16-D5 the hide is a SECOND tag: the layer whose own asset failed keeps
		-- its art rules (it draws nothing, and it is the only instrument that can
		-- report its own recovery), so only the healthy siblings carry `mute`.
		expect(ruleNamed(model, "Chrome — panel L1 fill fallback").props.BackgroundColor3).toBe("$SurfaceStrong")
		expect(ruleNamed(model, "Chrome — panel L1 fill fallback").props.ImageTransparency).toBeNil()
		expect(ruleNamed(model, "Chrome — panel L3 frame fallback")).toBeNil() -- nothing left to say
		local hide = ruleNamed(model, "Chrome — panel L3 frame fallback hide")
		expect(hide.selector).toBe(".facet-chrome-panel-3.facet-chrome-mute")
		expect(hide.props.ImageTransparency.value).toBe(1)
		expect(hide.props.BackgroundColor3).toBeNil()

		-- ONE PARENT TAG yields the whole ladder (rs-m2), and only a field needs it
		expect(ruleNamed(model, "Chrome — panel L1 fill editing")).toBeNil()
		local fieldModel = sheet_model.buildPackage(themes.define(layered(FULL_STACK, "field")))
		local yield = ruleNamed(fieldModel, "Chrome — field L1 fill editing")
		expect(yield.selector).toBe(".facet-chrome-yield > .facet-chrome-field-1")
		expect(yield.props.ImageTransparency.value).toBe(1)
	end)

	it("a layered control still gets its semantic role tints, on every layer", function()
		local model = sheet_model.buildPackage(themes.define(layered(FULL_STACK, "control")))
		expect(ruleNamed(model, "Chrome role — destructive L1").props.ImageColor3).toBe("$ChromeTintDanger")
		expect(ruleNamed(model, "Chrome role — accent L6").props.ImageColor3).toBe("$ChromeTintAccent")
		-- ...and its label is still lifted above the stack
		expect(ruleNamed(model, "Chrome text — button font") ~= nil).toBe(true)
	end)
end)

describe("buildPackage: the layer census makes ornate cost a number", function()
	it("counts layers per KIND, the suppressions, and the overhang", function()
		local model = sheet_model.buildPackage(themes.define(layered(FULL_STACK)))
		local census = model.census
		expect(census.layers).toBe(6)
		expect(census.layersPerKind.fill).toBe(1)
		expect(census.layersPerKind.corners).toBe(1)
		expect(census.layersPerKind.plaque).toBe(1)
		expect(census.layeredSlots[1]).toBe("panel")
		-- 3 for the layered panel + the value family's pre-armed 4x3 baseline
		-- (director round 5): every package suppresses a SKINNED barTrack /
		-- barFill / sliderTrack / sliderThumb, whichever route skinned it
		expect(census.suppressionRules).toBe(3 + 3 * #chrome_slots.OWN_PAINT_SLOTS)
		expect(census.overhang.panel.top).toBe(18)
		-- one paint rule per layer, plus the one per-corner override
		expect(census.layerRules).toBe(7)
	end)

	it("a flat package pays nothing at all", function()
		local model = sheet_model.buildPackage(snapshot.neutralPackage())
		local census = model.census
		expect(census.layers).toBe(0)
		expect(census.layerRules).toBe(0)
		-- ART costs zero. The one non-zero number is the value family's
		-- pre-armed suppression baseline, which every package carries and which
		-- matches nothing until a node is actually skinned (director round 5) —
		-- counted rather than hidden, exactly like every other census number.
		expect(census.suppressionRules).toBe(3 * #chrome_slots.OWN_PAINT_SLOTS)
		-- ART still costs zero. The image rules a flat package now carries are the
		-- framework ICON TINTS: the framework's own icon set (compact-label stage) resolves BELOW a package's map, so a package that declares nothing still DRAWS pictures — and `ImageColor3` is sheet-owned, so each of those names needs its tint rule or the art paints pure white. Found live in the running showcase: Studio Neutral emitted 70 rules and ZERO icon rules while `resolveIcon` returned real art for the same names.
		expect(census.imageRules > 0).toBe(true)
		expect(next(census.layersPerKind)).toBeNil()
		expect(next(census.overhang)).toBeNil()
		for _, rule in model.rules do
			if string.find(rule.selector, chrome_slots.ICON_TAG_PREFIX, 1, true) ~= nil then
				continue
			end
			expect(string.find(rule.selector, "facet-chrome-", 1, true)).toBeNil()
		end
	end)

	it("the headless node census counts a stack per decorated node", function()
		local pkg = themes.define(layered(FULL_STACK))
		local nodes = { { surface = "raised" }, { surface = "raised" }, { surface = "control" } }
		local census = chrome_slots.censusOf(pkg, nodes)
		-- two raised nodes x six layers; the control slot is native here
		expect(census.layers).toBe(12)
		expect(census.perSlot.panel).toBe(12)
		expect(census.layersPerKind.edges).toBe(2)
		expect(census.overhang.panel.top).toBe(18)
		expect(chrome_slots.censusOf(snapshot.neutralPackage(), nodes).layers).toBe(0)
	end)

	it("the per-target state counts layer instances per kind as they are created", function()
		local state = chrome_slots.newState(themes.define(layered(FULL_STACK)))
		local stack = state.layerPlanFor("panel")
		expect(stack ~= nil).toBe(true)
		for _, layer in stack.layers do
			state.noteCreated("panel", layer.kind)
		end
		expect(state.census().layers).toBe(6)
		expect(state.census().layersPerKind.frame).toBe(1)
		state.noteDestroyed("panel", "frame")
		expect(state.census().layersPerKind.frame).toBeNil()
		expect(state.census().layers).toBe(5)
	end)

	it("a broken layer fails the whole stack over, once", function()
		local state = chrome_slots.newState(themes.define(layered(FULL_STACK)))
		expect(state.isFallback("panel")).toBe(false)
		expect(state.setAssetLoaded("banner", false)).toBe(true)
		expect(state.isFallback("panel")).toBe(true)
		expect(state.setAssetLoaded("banner", false)).toBe(false)
		expect(state.setAssetLoaded("banner", true)).toBe(true)
		expect(state.isFallback("panel")).toBe(false)
	end)
end)

describe("the slot vocabulary is ONE list", function()
	it("themes.SLOTS and chrome_slots.SLOTS are the same list", function()
		-- a slot this compiler accepts but the plan machinery does not know is a
		-- package that validates and paints nothing
		expect(themes.SLOTS).toBe(chrome_slots.SLOTS)
	end)

	it("the v2 value-display and toggle slots are registered and classified", function()
		for _, slot in { "barTrack", "barFill", "barCap", "barCenter", "stepperPlate", "toggleTrack", "toggleKnob" } do
			expect(chrome_slots.isSlot(slot)).toBe(true)
		end
		-- whole image vs sliced (ADR-0020 R3): the stretchers slice, the
		-- fixed-size tokens do not
		for _, slot in { "barCap", "barCenter", "stepperPlate", "toggleKnob" } do
			expect(chrome_slots.isWholeImageSlot(slot)).toBe(true)
		end
		for _, slot in { "barTrack", "barFill", "toggleTrack" } do
			expect(chrome_slots.isWholeImageSlot(slot)).toBe(false)
		end
	end)

	it("the bar family owns solid native paint; the toggle keeps togglePalette", function()
		-- R9: barTrack/barFill are what a progress bar IS when unskinned, so they
		-- need the guarantee the rail and thumb got. The toggle's colours are
		-- VALUE-driven, so a solid rule would fight the adapter's own writes.
		expect(chrome_slots.hasOwnPaint("barTrack")).toBe(true)
		expect(chrome_slots.hasOwnPaint("barFill")).toBe(true)
		expect(chrome_slots.hasOwnPaint("barCap")).toBe(false)
		expect(chrome_slots.hasOwnPaint("toggleTrack")).toBe(false)
		local model = sheet_model.buildPackage(snapshot.neutralPackage())
		expect(ruleNamed(model, "Slot — barTrack").props.BackgroundTransparency.value).toBe(0)
		expect(ruleNamed(model, "Slot — barFill").props.BackgroundColor3).toBe("$Accent")
		expect(ruleNamed(model, "Slot — toggleTrack")).toBeNil()
	end)

	it("no wash can reach a value control's chrome, one control down", function()
		-- the thumb's see-through defect, refused for the whole family
		for _, slot in { "barTrack", "barFill", "barCap", "barCenter", "stepperPlate", "toggleTrack", "toggleKnob" } do
			expect(chrome_slots.isGradientable(slot)).toBe(false)
		end
		expect(chrome_slots.isGradientable("panel")).toBe(true)
		local d = def()
		d.style.themes[1].extra = d.style.themes[1].extra or {}
		d.style.themes[1].extra.chromeGradient = {
			toggleKnob = { rotation = 90, stops = { { t = 0, r = 1, g = 1, b = 1 }, { t = 1, r = 0, g = 0, b = 0 } } },
		}
		local pkg, report = themes.define(d)
		expect(pkg).toBeNil()
		expect(report.ok).toBe(false)
	end)
end)

-- ===========================================================================
-- THE GLOW IS NOT CLIPPED AT A SCROLL CONTAINER'S EDGE (director report
-- 2026-07-27, Glossy Mobile on a phone: "the way these controls are cutoff
-- horizontally looks wrong given there's no horizontal scrolling. the view
-- should narrow to accommodate them (and the glow underneath)").
--
-- `chromeBleed` was spent only as a CANVAS allowance, which makes a glow past
-- the last row reachable by SCROLLING to it. That works on the scroll axis and
-- collapses on the other one: a y-axis scroller cannot be scrolled sideways, so
-- the glow is simply cut. The solver reported nothing, correctly — the bleed is
-- paint, not layout, which is why only a device showed it.
-- ===========================================================================
describe("a clipping scroll container reserves the package's shadow bleed", function()
	local UI = Facet.UI
	local fake = require("./lib/fake_target")

	local function widestChildOvershoot(pkgName: string): (number, number)
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		pres.present(UI.Screen({
			id = "S",
			padding = 0,
			children = {
				UI.ScrollView({
					id = "Page",
					padding = 0,
					width = { type = "fill", weight = 1 },
					children = {
						UI.VStack({
							id = "Card",
							surface = "raised",
							padding = 0,
							width = { type = "fill", weight = 1 },
							children = {
								UI.Button({ id = "Deep", label = "Deep", width = { type = "fill", weight = 1 } }),
							},
						}),
					},
				}),
			},
		}))
		pres.refresh()
		local snap = Facet.themes.resolve((require)(`../examples/themes/{pkgName}`).build(Facet.themes), nil, {})
		env:set("themeMetrics", snap)
		pres.refresh()
		local bleed = if type(snap.chromeBleed) == "number" then snap.chromeBleed else 0
		local page = adapter.node("/S/Page").rect
		local deep = adapter.node("/S/Page/Card/Deep").rect
		return (deep.x + deep.w + bleed) - (page.x + page.w), bleed
	end

	it("the deepest control's glow lands INSIDE the clipper, in every shadowed package", function()
		for _, name in { "glossy_mobile", "glossy_touch", "scifi_hud", "fantasy_ornate" } do
			local overshoot, bleed = widestChildOvershoot(name)
			expect(bleed > 0).toBe(true) -- these packages DO cast a shadow
			expect(overshoot <= 0).toBe(true)
		end
	end)

	it("a package with no shadow pays nothing, so a flat theme cannot move", function()
		-- bleed 0 means the reservation adds nothing at all; the content is still
		-- comfortably inside the clipper (its own card reserves a little), which is
		-- the state every flat package was already in and must stay in.
		local overshoot, bleed = widestChildOvershoot("compact_pointer")
		expect(bleed).toBe(0)
		expect(overshoot <= 0).toBe(true)
	end)

	it("nesting does NOT accumulate: reach is measured from each node's own box", function()
		-- a glowing view inside a glowing view overshoots by `bleed`, not twice it,
		-- because an inner box can never lie outside its parent's — which is what
		-- lets ONE reservation at the clipper cover any depth.
		local overshoot = widestChildOvershoot("scifi_hud")
		expect(overshoot <= 0).toBe(true)
	end)

	--[[ TASK SHOWCASE3 (2026-08-29): the playlist table's hidden-column
		disclosure plate clipped the "Rating" heading's own top edge under
		Glossy Mobile at a narrow phone (director photograph) — the FIRST row
		in the plate's y-axis list, sitting flush at `List`'s own top with a
		`shadow = "raised"` glow painting above its box. The reservation above
		only ever grew the CROSS axis (`left`/`right` for a y-axis scroller):
		the block's own comment reasons the SCROLL axis's far edge is
		"reachable by scrolling to it", which is true for the LAST row (more
		canvas beyond it) and false for the FIRST — there is no canvas before
		position 0 to scroll into.

		THIS SUPERSEDES `9eb095a`, REVERTED THE SAME DAY. That commit spent
		this reservation unconditionally in `render/layout_node.luau`'s
		pre-solve conversion, which sees only a node's own AUTHORED extent —
		`math.huge` for the common fill/hug scroll container — never the real
		offer a squeezing parent has, so it collapsed `overflow_sweep`'s
		`tab_view`/`p3_sipworks` to a 0px content box under Sci-Fi HUD at
		narrow-landscape. `src/layout/solver.luau`'s `arrange` now spends it
		instead, floor-aware (`chrome_slots.spendInset`) against the REAL
		resolved rect — the fact the pre-solve conversion never has. The first
		two cases below are `9eb095a`'s own (still true: this box has 400px to
		work with and the floor never bites); the third is the negative
		control `9eb095a` did not carry — the squeeze that broke it — proving
		the floor now gives the reservation back instead of collapsing the box. ]]
	local function firstChildTopOvershoot(pkgName: string, pageHeight: number?): (number, number, boolean)
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local handle = pres.present(UI.Screen({
			id = "S",
			padding = 0,
			children = {
				UI.ScrollView({
					id = "Page",
					axis = "y",
					padding = 0,
					height = { type = "fixed", px = pageHeight or 400 },
					width = { type = "fill", weight = 1 },
					children = {
						UI.Button({ id = "First", label = "First", width = { type = "fill", weight = 1 } }),
						UI.Button({ id = "Second", label = "Second", width = { type = "fill", weight = 1 } }),
					},
				}),
			},
		}))
		pres.refresh()
		local snap = Facet.themes.resolve((require)(`../examples/themes/{pkgName}`).build(Facet.themes), nil, {})
		env:set("themeMetrics", snap)
		pres.refresh()
		local bleed = if type(snap.chromeBleed) == "number" then snap.chromeBleed else 0
		local page = adapter.node("/S/Page").rect
		local first = adapter.node("/S/Page/First").rect
		local collapsed = false
		for _, finding in handle.controller.diagnostics() do
			if string.find(finding.issue, "content box collapses", 1, true) ~= nil then
				collapsed = true
			end
		end
		return page.y - (first.y - bleed), bleed, collapsed
	end

	it("the FIRST child's glow lands INSIDE the clipper's own leading edge too, in every shadowed package", function()
		for _, name in { "glossy_mobile", "glossy_touch", "scifi_hud", "fantasy_ornate" } do
			local overshoot, bleed, collapsed = firstChildTopOvershoot(name)
			expect(bleed > 0).toBe(true) -- these packages DO cast a shadow
			expect(overshoot <= 0).toBe(true)
			expect(collapsed).toBe(false)
		end
	end)

	it("...and a package with no shadow still pays nothing on the leading edge", function()
		local overshoot, bleed, collapsed = firstChildTopOvershoot("compact_pointer")
		expect(bleed).toBe(0)
		expect(overshoot <= 0).toBe(true)
		expect(collapsed).toBe(false)
	end)

	--[[ THE NEGATIVE CONTROL `9eb095a` DID NOT CARRY. A 20px box under Sci-Fi
		HUD's 24px bleed cannot afford the reservation at all (`0 - 24 <= 0`,
		`chrome_slots.spendInset`'s own all-or-nothing floor): the fix must give
		it back rather than collapse the content box to 0, which is exactly
		what shipped-then-reverted `9eb095a` did to `tab_view`/`p3_sipworks` at
		narrow-landscape. The floor bites HERE — `First` sits flush at the
		box's own top, no reservation spent — and the solver reports no
		collapse, because none was forced: the padding that could not be
		afforded was never applied, the same rule `spendInset` already keeps
		for a themed control's own chrome insets. ]]
	it("a box too small for the bleed gives the reservation back instead of collapsing", function()
		local overshoot, bleed, collapsed = firstChildTopOvershoot("scifi_hud", 20)
		expect(bleed).toBe(24)
		expect(collapsed).toBe(false)
		-- the floor bit: NONE of the bleed was spent, so the first child sits
		-- flush at the box's own top (overshoot equals the full, un-afforded
		-- bleed rather than <= 0)
		expect(overshoot).toBe(bleed)
	end)
end)
