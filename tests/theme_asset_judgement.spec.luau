--!strict
-- WHEN IS SILENCE FROM AN IMAGE EVIDENCE THAT ITS ASSET IS BROKEN? (RS-A16-D5)
--
-- `ImageLabel` has no `LoadingImageFailed`, so the client target infers failure
-- from silence at a grace deadline. That inference is only sound where the engine
-- was actually asked to decode the picture, and it is the same rule the adapter
-- states at its own guard: THE ENGINE NEVER DECODES AN IMAGE THE PLAYER CANNOT
-- SEE. Four faces of it were already known and fixed. This file is the fifth,
-- plus the recoverability half that made the first four dangerous:
--
--   1. the CLIPPED-AWAY clause. A ScrollView's off-window art is Visible,
--      opaque, sized and sourced, so every earlier clause passed and the grace
--      timer condemned the whole shared asset — for the ON-screen consumers too.
--      Measured live on `samsung_galaxy_a06` in both orientations under three
--      packages (rs-a16-matrix.json, take 7): a 673x169 scroll window over a
--      673x507 canvas, 98 of 140 image nodes undecoded, 88 of them entirely
--      off-window, 7 assets and 4 slots declared failed.
--
--   2. the RECOVERABILITY rider. The fallback hid the condemned art at
--      `ImageTransparency = 1`, which is the engine's own "do not decode"
--      signal — so `IsLoaded` could never become true, the one-shot deadline had
--      passed, and a FALSE condemnation was permanent for the session. Measured:
--      a real injected scroll decoded 65 of the undecoded nodes and the 10
--      already flipped stayed failed through two later re-reads.
--
-- Both halves are pure decisions with the geometry passed in, so they are tested
-- here rather than only in a Studio session; the adapter's job is the ancestor
-- walk that gathers the facts, and its source assertions live beside the
-- behaviours they feed (theme_value_displays / theme_layer_application).

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local chrome_slots = require("../src/tokens/chrome_slots")

local themes = Facet.themes
local ornateModule = require("../examples/themes/fantasy_ornate")

local function ornate(): any
	local pkg, report = ornateModule.build(themes)
	assert(pkg ~= nil, `fantasy_ornate must compile: {report and report.errors[1] and report.errors[1].message}`)
	return pkg
end

-- the take-7 landscape row, to scale: a 673x169 scroll window over a 673x507
-- canvas, so two thirds of the fixture is outside the window at any time
local WINDOW = { x = 16, y = 100, w = 673, h = 169 }
local function art(y: number, h: number?): chrome_slots.ArtRect
	return { x = 24, y = y, w = 240, h = h or 46 }
end

-- every fact the judgement takes, defaulted to "an ordinary, drawn, on-window
-- decoration", so each test states ONLY the fact it is about
local function judge(over: { [string]: any }): chrome_slots.ArtJudgement
	local facts: any = {
		attached = true,
		visible = true,
		transparency = 0,
		image = "rbxassetid://12345",
		rect = art(120),
		clips = { WINDOW },
	}
	for key, value in over do
		facts[key] = value
	end
	return chrome_slots.judgeArt(facts)
end

describe("art clipped away by an ancestor is not evidence about its asset (RS-A16-D5)", function()
	it("art entirely outside a ClipsDescendants host is NOT judgeable", function()
		-- the exact shape of the defect: below the window (a scrolled-away row)...
		local below = judge({ rect = art(400) })
		expect(below.judgeable).toBe(false)
		expect(below.reason).toBe("clipped")
		-- ...above it (the canvas scrolled past)...
		expect(judge({ rect = art(-60) }).judgeable).toBe(false)
		-- ...and beside it (a horizontal canvas)
		expect(judge({ rect = { x = 900, y = 120, w = 240, h = 46 } }).judgeable).toBe(false)
	end)

	it("art the player can see any pixel of IS judgeable, including a partial row", function()
		-- the engine decodes what it draws, and it draws the visible sliver — so a
		-- half-scrolled row's silence really is evidence about its asset
		expect(judge({ rect = art(250, 46) }).judgeable).toBe(true) -- straddles the bottom edge
		expect(judge({ rect = art(80, 46) }).judgeable).toBe(true) -- straddles the top edge
		expect(judge({ rect = art(120) }).judgeable).toBe(true) -- fully inside
	end)

	it("a one-pixel overlap is enough, and a shared edge is not", function()
		expect(judge({ rect = { x = 24, y = 268, w = 240, h = 46 } }).judgeable).toBe(true) -- 1px inside
		-- touching edges draw nothing: the window's bottom edge is y = 269
		expect(judge({ rect = { x = 24, y = 269, w = 240, h = 46 } }).reason).toBe("clipped")
	end)

	it("EVERY clipping ancestor has to be satisfied, not just the nearest", function()
		-- a scroll region inside a collapsed drawer inside a panel: the art is
		-- inside its own window and outside the one above it
		local inner = { x = 24, y = 380, w = 300, h = 200 }
		expect(judge({ rect = art(400), clips = { inner } }).judgeable).toBe(true)
		expect(judge({ rect = art(400), clips = { inner, WINDOW } }).reason).toBe("clipped")
		-- order must not matter
		expect(judge({ rect = art(400), clips = { WINDOW, inner } }).reason).toBe("clipped")
	end)

	it("a clipping host with no area clips everything inside it", function()
		-- the bar assembly's own window at 0%: the art is full-track-size and the
		-- window is zero-wide, so the art is sized and sourced and still undrawn
		expect(judge({ clips = { { x = 16, y = 100, w = 0, h = 169 } } }).reason).toBe("clipped")
	end)

	it("an ancestor that does not clip cannot make art unjudgeable", function()
		-- the fact gatherer only collects hosts whose ClipsDescendants is true, so a
		-- node drawn outside a non-clipping parent (an overhanging plaque, a focus
		-- glow) still counts as drawn
		expect(judge({ rect = art(400), clips = {} }).judgeable).toBe(true)
	end)

	it("the four earlier faces still answer, and each names itself", function()
		expect(judge({ attached = false }).reason).toBe("detached")
		expect(judge({ visible = false }).reason).toBe("hidden")
		expect(judge({ transparency = 1 }).reason).toBe("transparent")
		expect(judge({ transparency = 1, mutedByFallback = true }).reason).toBe("muted")
		expect(judge({ rect = { x = 24, y = 120, w = 240, h = 0 } }).reason).toBe("zeroArea")
		expect(judge({ image = "" }).reason).toBe("noSource")
		-- ...and the clause order is stable: an off-window HIDDEN node reports the
		-- stronger reason, so a probe's reason histogram is a diagnosis
		expect(judge({ visible = false, rect = art(400) }).reason).toBe("hidden")
		expect(judge({}).reason).toBeNil()
	end)

	it("the D5 row itself: off-window consumers no longer condemn a shared asset", function()
		-- the composed decision, modelled the way the target's deadline composes it
		-- (one watcher per decoration; the first judgeable one to run decides). The
		-- ornate row's `panel` slot is layered, so this uses its real asset names.
		local state = chrome_slots.newState(ornate())
		local stack = state.layerPlanFor("panel")
		expect(stack ~= nil).toBe(true)
		local asset = (stack :: any).layers[1].assetName
		-- twenty-two off-window decorations of the same asset, at the take-7
		-- geometry, all silent at their deadline
		local judged = 0
		for row = 1, 22 do
			local verdict = judge({ rect = art(300 + row * 46) })
			if verdict.judgeable then
				judged += 1
				state.observeAssetFailed(asset)
			end
		end
		expect(judged).toBe(0)
		expect(state.isFallback("panel")).toBe(false)
		expect(#state.census().failedAssets).toBe(0)
		-- and the on-screen twin that DID decode reports for the whole asset
		state.setAssetLoaded(asset, true)
		expect(state.isFallback("panel")).toBe(false)
	end)

	it("a deferred judgement is not a verdict of healthy: the same art, scrolled in", function()
		-- the other half of "defer, do not skip". If art really is broken, the
		-- deadline has to reach it eventually — a skipped judgement would leave the
		-- node it skins drawing NOTHING, because a skinned node's own plate is
		-- suppressed.
		local state = chrome_slots.newState(ornate())
		local plan = state.planFor("barTrack")
		expect(plan ~= nil).toBe(true)
		local asset = (plan :: any).assetName
		expect(judge({ rect = art(400) }).judgeable).toBe(false)
		expect(state.isFallback("barTrack")).toBe(false)
		-- ...the player scrolls, the same decoration is now inside the window, and
		-- the re-armed deadline judges it
		expect(judge({ rect = art(120) }).judgeable).toBe(true)
		expect(state.observeAssetFailed(asset)).toBe(true)
		expect(state.isFallback("barTrack")).toBe(true)
	end)
end)

describe("a condemned asset can still report its own recovery (RS-A16-D5)", function()
	it("the mute is for the HEALTHY siblings; the failed asset's art keeps drawing", function()
		local state = chrome_slots.newState(ornate())
		local stack = state.layerPlanFor("panel")
		local layers = (stack :: any).layers
		expect(#layers > 1).toBe(true)
		local broken = layers[1].assetName
		local healthy = nil
		for _, layer in layers do
			if layer.assetName ~= broken then
				healthy = layer.assetName
			end
		end
		expect(healthy ~= nil).toBe(true)
		-- nothing is muted while nothing has failed
		expect(state.isArtMuted("panel", broken, false)).toBe(false)
		expect(state.isArtMuted("panel", healthy, true)).toBe(false)
		state.observeAssetFailed(broken)
		expect(state.isFallback("panel")).toBe(true)
		-- THE SPLIT: the healthy ladder hides so the slot reads flat rather than
		-- half-painted; the broken layer's UNDECODED art keeps its rules, because it
		-- draws nothing and it is the only instrument that can report a recovery
		expect(state.isArtMuted("panel", healthy, true)).toBe(true)
		expect(state.isArtMuted("panel", healthy, false)).toBe(true)
		expect(state.isArtMuted("panel", broken, false)).toBe(false)
		-- ...and exactly that narrow: art the engine HAS decoded is no instrument
		-- (its IsLoaded cannot change again), so sparing it would only paint the
		-- picture the fallback replaced over the native fill. It hides — which is
		-- RS-DIR6-F1's case, unchanged by this fix.
		expect(state.isArtMuted("panel", broken, true)).toBe(true)
		-- an art instance with no asset of its own (a per-corner ornament of an
		-- unnamed override) hides with the siblings
		expect(state.isArtMuted("panel", nil, false)).toBe(true)
	end)

	it("...and that art is JUDGEABLE, which is what breaks the deadlock", function()
		-- the deadlock, stated as two judgements of the same decoration. Muted, it
		-- is not judgeable and never decodes, so `IsLoaded` can never become true
		-- and the fallback is permanent. Un-muted, it is ordinary drawn art.
		expect(judge({ transparency = 1, mutedByFallback = true }).judgeable).toBe(false)
		expect(judge({}).judgeable).toBe(true)
	end)

	it("a recovery clears the slot and un-mutes every sibling, once", function()
		local state = chrome_slots.newState(ornate())
		local broken = (state.layerPlanFor("panel") :: any).layers[1].assetName
		local sibling = (state.layerPlanFor("panel") :: any).layers[2].assetName
		state.observeAssetFailed(broken)
		expect(state.isArtMuted("panel", sibling, true)).toBe(true)
		-- the un-muted art decodes and its IsLoaded change reports for the asset
		expect(state.setAssetLoaded(broken, true)).toBe(true)
		expect(state.isFallback("panel")).toBe(false)
		expect(state.isArtMuted("panel", sibling, true)).toBe(false)
		expect(state.setAssetLoaded(broken, true)).toBe(false) -- exactly one flip back
	end)

	it("NO OSCILLATION: the inferred ledger is a monotone lattice", function()
		-- unknown -> failed -> loaded, with `loaded` terminal for the inference the
		-- grace deadline can make. A node cycling flip/unflip every grace period
		-- would be worse than either steady state, so this is the property that
		-- makes the deferred, re-arming deadline safe to run forever.
		local state = chrome_slots.newState(ornate())
		local asset = (state.planFor("barTrack") :: any).assetName
		expect(state.everLoaded(asset)).toBe(false)
		expect(state.observeAssetFailed(asset)).toBe(true) -- unknown -> failed
		expect(state.observeAssetFailed(asset)).toBe(false) -- idempotent
		expect(state.setAssetLoaded(asset, true)).toBe(true) -- failed -> loaded
		expect(state.everLoaded(asset)).toBe(true)
		-- twenty further grace periods of silence from any number of decorations
		-- cannot move it again
		for _ = 1, 20 do
			expect(state.observeAssetFailed(asset)).toBe(false)
			expect(state.isFallback("barTrack")).toBe(false)
		end
		-- so the total number of tag flips this asset can ever cause is 2
	end)

	it("the authoritative provider is still authoritative", function()
		-- two sources answer "is this asset broken": the app's resource provider,
		-- which knows, and the target's own deadline, which infers from silence.
		-- Only the inference is latched — a provider that reports a real failure
		-- after a success still governs, or the seam would be a gag.
		local state = chrome_slots.newState(ornate())
		local asset = (state.planFor("barTrack") :: any).assetName
		state.setAssetLoaded(asset, true)
		expect(state.observeAssetFailed(asset)).toBe(false)
		expect(state.setAssetLoaded(asset, false)).toBe(true)
		expect(state.isFallback("barTrack")).toBe(true)
	end)

	it("a package swap clears the decode history with the failure ledger", function()
		-- `loaded` is terminal for a package, not for a target: the next package's
		-- art has never been seen, and an asset that really is broken must still be
		-- condemnable
		local state = chrome_slots.newState(ornate())
		local asset = (state.planFor("barTrack") :: any).assetName
		state.setAssetLoaded(asset, true)
		expect(state.everLoaded(asset)).toBe(true)
		expect(state.setPackage(themes.neutralPackage())).toBe(true)
		expect(state.setPackage(ornate())).toBe(true)
		expect(state.everLoaded(asset)).toBe(false)
		expect(state.observeAssetFailed(asset)).toBe(true)
	end)
end)
