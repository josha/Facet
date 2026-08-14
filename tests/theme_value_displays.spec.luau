--!strict
-- IMAGE VALUE DISPLAYS (ADR-0020 R3, rich-skinning-v2 package P3): the bar
-- family, the stepper plate and the toggle's two image slots.
--
-- This stage's standing lesson is EMISSION ≠ APPLICATION — the Step 3.5 fix
-- round shipped a green suite that asserted every rule a package compiled to and
-- nothing about the tag those rules select on ever landing. So every proposition
-- below is paired: what the package COMPILES to, and what has to actually happen
-- on a mounted node for that rule to matter.
--
--   1. the clip is DATA (probe rs-m4): a window over a fill that stays FULL TRACK
--      SIZE at every percent, expressed as boxes so the adapter materializes
--      UDim2s and decides nothing — and so "the art is byte-stable from 1% to
--      100%" is a headless proposition rather than a capture;
--   2. the bar family owns SOLID native paint when flat (R9's OWN_PAINT_SLOTS)
--      and a value control's chrome still refuses every gradient;
--   3. a v2 slot may never UN-SKIN a v1 theme: `stepperPlate` falls back to the
--      `control` recipe for every package that does not declare one;
--   4. a switch's ON state is a VALUE, so its art keys on a tag the adapter flips
--      beside `togglePalette`'s colour writes — and that tag rides the desired set
--      `syncTags` diffs against, or it survives exactly one classification pass;
--   5. the knob's TRAVEL is the same two absolute positions skinned or flat: art
--      never moves geometry.
--
-- Source-contract assertions read the live adapter and pin ORDER, the fix-round
-- instrument: reverting an application line turns exactly one of these red rather
-- than leaving the suite green and the screen wrong.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")

local customFactory = require("../src/core/custom")
local LuauUI = require("../src") :: any
local UI = require("../src/blueprint")
local environment = require("../src/env/environment")
local presenterLib = require("../src/present/presenter")
local actionsLib = require("../src/input/actions")
local fake_target = require("./lib/fake_target")

local themes = require("../src/themes/package")
local snapshot = require("../src/themes/snapshot")
local sheet_model = require("../src/tokens/sheet_model")
local chrome_slots = require("../src/tokens/chrome_slots")
local adapter_source = require("./lib/adapter_source")

-- the LIVE adapter as ONE text: it is three files since the 200k `Source`
-- write-cap split (tests/lib/adapter_source names them and says why)
local source = adapter_source.live()
-- the chrome/decoration materializer was extracted to a sibling module when
-- screen_target.luau reached Studio's 200_000-byte Source ceiling. Every anchor
-- below is unchanged and every assertion keeps its strength — `section` simply
-- looks in both halves of the adapter for the one that carries the anchor.
local chromeSource = fs.readFile("src/client/screen_chrome.luau")

local function section(fromNeedle: string, toNeedle: string): string
	local text = source
	local from = string.find(text, fromNeedle, 1, true)
	if from == nil then
		text = chromeSource
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

local function has(haystack: string, needle: string): boolean
	return string.find(haystack, needle, 1, true) ~= nil
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

local function ruleNamed(model: any, name: string): any
	for _, rule in model.rules do
		if rule.name == name then
			return rule
		end
	end
	return nil
end

local function errorsOn(report: any, field: string): { any }
	local out: { any } = {}
	for _, entry in report.errors do
		if entry.field == field then
			table.insert(out, entry)
		end
	end
	return out
end

-- a definition carrying the art an image value display needs
local function def(): any
	local base = snapshot.neutralPackage()
	return {
		identity = {
			id = "value-display-test",
			displayName = "Value Display Test",
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
		},
		style = copy(base.style),
		metrics = copy(base.metrics),
		chrome = copy(base.chrome),
		assets = {
			barTrack = {
				content = "rbxassetid://21",
				sliceCenter = { x0 = 12, y0 = 12, x1 = 84, y1 = 16 },
				sliceScale = 1,
				preload = "install",
				fallback = "native",
			},
			barFill = {
				content = "rbxassetid://22",
				sliceCenter = { x0 = 8, y0 = 8, x1 = 88, y1 = 12 },
				sliceScale = 1,
				preload = "install",
				fallback = "native",
			},
			capStart = { content = "rbxassetid://23", preload = "install", fallback = "native" },
			capEnd = { content = "rbxassetid://24", preload = "install", fallback = "native" },
			crown = { content = "rbxassetid://25", preload = "install", fallback = "native" },
			trackOff = {
				content = "rbxassetid://26",
				sliceCenter = { x0 = 14, y0 = 14, x1 = 58, y1 = 18 },
				sliceScale = 1,
				preload = "install",
				fallback = "native",
			},
			trackOn = {
				content = "rbxassetid://27",
				sliceCenter = { x0 = 14, y0 = 14, x1 = 58, y1 = 18 },
				sliceScale = 1,
				preload = "install",
				fallback = "native",
			},
			knob = { content = "rbxassetid://28", preload = "install", fallback = "native" },
			knobHot = { content = "rbxassetid://29", preload = "install", fallback = "native" },
			plate = {
				content = "rbxassetid://30",
				sliceCenter = { x0 = 12, y0 = 12, x1 = 28, y1 = 28 },
				sliceScale = 1,
				preload = "install",
				fallback = "native",
			},
		},
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

-- the whole R3 vocabulary in one package: a sliced track, a directed fill, two
-- differently-arted end caps, a centrepiece, per-state toggle art on BOTH slots,
-- and a stepper plate
local function valueDisplays(): any
	local d = def()
	d.chrome.barTrack = {
		kind = "nineSlice",
		asset = "barTrack",
		fallback = "native",
		contentInsets = { top = 0, right = 0, bottom = 0, left = 0 },
	}
	d.chrome.barFill = { kind = "nineSlice", asset = "barFill", fallback = "native", direction = "ltr" }
	d.chrome.barCap = {
		kind = "nineSlice",
		asset = "capStart",
		fallback = "native",
		size = { w = 28, h = 36 },
		startAsset = "capStart",
		endAsset = "capEnd",
	}
	d.chrome.barCenter = { kind = "nineSlice", asset = "crown", fallback = "native", size = { w = 36, h = 28 } }
	d.chrome.toggleTrack = {
		kind = "nineSlice",
		asset = { default = "trackOff", selected = "trackOn" },
		fallback = "native",
	}
	d.chrome.toggleKnob = {
		kind = "nineSlice",
		asset = { default = "knob", hover = "knobHot", pressed = "knobHot" },
		fallback = "native",
	}
	d.chrome.stepperPlate = { kind = "nineSlice", asset = "plate", fallback = "native" }
	return d
end

local function built(): any
	local pkg, report = themes.define(valueDisplays())
	expect(report.ok).toBe(true)
	assert(pkg ~= nil, "the value-display fixture package must compile")
	return pkg
end

local function harness()
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local adapter = fake_target.new()
	local system = actionsLib.newSystem(core)
	local pres = presenterLib.new(core, env, adapter, system)
	return core, env, adapter, system, pres
end

-- ===== 1. the clip is DATA (probe rs-m4) ===================================

describe("chrome_slots: the window clip, expressed as numbers", function()
	it("the art inside the window is the WHOLE track on the driven axis", function()
		-- rs-m4: "fill stays 300px wide at every pct". That is the entire reason
		-- the window wins over an ImageRect crop — the nine-patch is never
		-- re-derived, so the rail texture and the caps are byte-stable at 1%.
		local box = chrome_slots.barFillBox("ltr", 300)
		expect(box.name).toBe("LuauUIBarFill")
		expect(box.size.xOffset).toBe(300)
		expect(box.size.xScale).toBe(0)
		expect(box.size.yScale).toBe(1) -- full bleed on the cross axis
		-- pinned to the window's ORIGIN edge, so what the window reveals is the
		-- start of the art rather than a floating middle
		expect(box.anchor.x).toBe(0)
		expect(box.position.xScale).toBe(0)
	end)

	it("direction decides the axis and the pinned edge, and nothing else", function()
		local rtl = chrome_slots.barFillBox("rtl", 300)
		expect(rtl.anchor.x).toBe(1)
		expect(rtl.position.xScale).toBe(1)
		expect(rtl.size.xOffset).toBe(300)
		local ttb = chrome_slots.barFillBox("ttb", 120)
		expect(ttb.size.yOffset).toBe(120)
		expect(ttb.size.xScale).toBe(1)
		expect(ttb.anchor.y).toBe(0)
		local btt = chrome_slots.barFillBox("btt", 120)
		expect(btt.anchor.y).toBe(1)
		expect(btt.position.yScale).toBe(1)
		expect(chrome_slots.isVerticalBar("ttb")).toBe(true)
		expect(chrome_slots.isVerticalBar("ltr")).toBe(false)
	end)

	it("an end cap is CENTRED on the track's edge and survives every percent", function()
		-- centred rather than inset, so a 36px jewel on a 28px rail overhangs
		-- evenly and reads as a cap instead of a block at the end
		local start = chrome_slots.barCapBox("start", "ltr", { w = 28, h = 36 })
		expect(start.name).toBe("LuauUIBarCapStart")
		expect(start.anchor.x).toBe(0.5)
		expect(start.anchor.y).toBe(0.5)
		expect(start.position.xScale).toBe(0)
		expect(start.position.yScale).toBe(0.5)
		expect(start.size.xOffset).toBe(28)
		expect(start.size.yOffset).toBe(36)
		local finish = chrome_slots.barCapBox("finish", "ltr", { w = 28, h = 36 })
		expect(finish.name).toBe("LuauUIBarCapEnd")
		expect(finish.position.xScale).toBe(1)
	end)

	it("'start' follows the fill's origin when the direction flips", function()
		-- the two names have to keep MEANING the same thing, or an author who
		-- declares a rounded start cap gets it welded to the wrong end
		expect(chrome_slots.barCapBox("start", "rtl", { w = 8, h = 8 }).position.xScale).toBe(1)
		expect(chrome_slots.barCapBox("finish", "rtl", { w = 8, h = 8 }).position.xScale).toBe(0)
		expect(chrome_slots.barCapBox("start", "btt", { w = 8, h = 8 }).position.yScale).toBe(1)
		expect(chrome_slots.barCapBox("finish", "ttb", { w = 8, h = 8 }).position.yScale).toBe(1)
	end)

	it("the centrepiece is dead centre on both axes, direction-independently", function()
		local box = chrome_slots.barCenterBox({ w = 36, h = 28 })
		expect(box.name).toBe("LuauUIBarCenter")
		expect(box.anchor.x).toBe(0.5)
		expect(box.anchor.y).toBe(0.5)
		expect(box.position.xScale).toBe(0.5)
		expect(box.position.yScale).toBe(0.5)
		expect(box.size.xOffset).toBe(36)
	end)

	it("a per-end cap asset resolves, and both ends share one when it does not", function()
		local pkg = built()
		local recipe = pkg.chrome.barCap
		expect(chrome_slots.barCapAssetOf(recipe, "start")).toBe("capStart")
		expect(chrome_slots.barCapAssetOf(recipe, "finish")).toBe("capEnd")
		expect(chrome_slots.barCapAssetOf({ asset = "capStart" }, "finish")).toBe("capStart")
		expect(chrome_slots.barCapTagFor("start")).toBe("luau-chrome-barCap-start")
		expect(chrome_slots.barOrnamentSize(recipe).w).toBe(28)
		expect(chrome_slots.barOrnamentSize({}).w).toBe(0)
	end)

	it("the declared direction reaches the plan, and an absent one is ltr", function()
		expect(chrome_slots.barDirectionOf(built(), "barFill")).toBe("ltr")
		expect(chrome_slots.barDirectionOf(snapshot.neutralPackage(), "barFill")).toBe("ltr")
		expect(chrome_slots.isBarDirection("btt")).toBe(true)
		expect(chrome_slots.isBarDirection("sideways")).toBe(false)
	end)
end)

-- ===== 2. the schema refuses what rs-m4 measured as wrong ==================

describe("themes.define: the bar family's declared geometry", function()
	it("an unknown fill direction names the vocabulary", function()
		local d = valueDisplays()
		d.chrome.barFill.direction = "sideways"
		local pkg, report = themes.define(d)
		expect(pkg).toBeNil()
		local errs = errorsOn(report, "chrome.barFill.direction")
		expect(#errs).toBe(1)
		expect(string.find(errs[1].fix, "ltr", 1, true) ~= nil).toBe(true)
	end)

	it("a field is legal only on the slot that can act on it", function()
		local d = valueDisplays()
		d.chrome.panel.direction = "ltr"
		local pkg, report = themes.define(d)
		expect(pkg).toBeNil()
		local errs = errorsOn(report, "chrome.panel.direction")
		expect(#errs).toBe(1)
		expect(string.find(errs[1].fix, "barFill", 1, true) ~= nil).toBe(true)
	end)

	it("an ImageRect crop is REFUSED, citing the probe that rejected it", function()
		-- rs-m4: ImageRect and ScaleType=Slice both address the texture, so the
		-- nine-patch re-derives from the cropped rect and the end cap comes out of
		-- mid-texture. The measurement is encoded, not left as prose.
		local d = valueDisplays()
		d.chrome.barFill.imageRectSize = { x = 48, y = 20 }
		local pkg, report = themes.define(d)
		expect(pkg).toBeNil()
		local errs = errorsOn(report, "chrome.barFill.imageRectSize")
		expect(#errs).toBe(1)
		expect(string.find(errs[1].message, "rs-m4", 1, true) ~= nil).toBe(true)
	end)

	it("an ornament with no declared px box is an authoring error", function()
		local d = valueDisplays()
		d.chrome.barCenter.size = nil
		local pkg, report = themes.define(d)
		expect(pkg).toBeNil()
		expect(#errorsOn(report, "chrome.barCenter.size")).toBe(1)
	end)

	it("a per-end cap naming art the package does not declare is refused", function()
		local d = valueDisplays()
		d.chrome.barCap.endAsset = "nosuchcap"
		local pkg, report = themes.define(d)
		expect(pkg).toBeNil()
		expect(#errorsOn(report, "chrome.barCap.endAsset")).toBe(1)
	end)
end)

-- ===== 2b. the ORNAMENT RESERVATION (director fix round 2026-07-25) ========
--
-- "Caps/centrepiece imagery overlaps the value/label text at either end of the
-- bar AND the row above." The art was never wrong — `barCapBox` centres a cap ON
-- the track's edge on purpose — but the declared extents never reached the
-- SOLVER, so nothing made the neighbours move. Measured live at desktop under
-- pixel-quest: a 40x40 heart on an 8px track spanned 20px past each end and 16px
-- past each edge, overlapping "Download" by 12px, "0.35" by 12px, and the
-- toolbar row above by 2px.
--
-- Three propositions, because the defect could have been fixed in a way that
-- only moved it: the MATH, the snapshot that publishes it, and the SOLVED
-- consequence on a mounted bar with both neighbours present.

describe("the bar's ornaments reserve the space they paint in", function()
	it("chrome_slots.barReservation derives the overhang from the declared boxes", function()
		local pkg = built()
		-- caps 28x36 on the ends, a 36x28 crown in the middle, over a 6px track:
		-- half a cap past each end, half of (tallest ornament - track) past each edge
		local r = chrome_slots.barReservation(pkg, 6)
		expect(r.left).toBe(14)
		expect(r.right).toBe(14)
		expect(r.top).toBe(15)
		expect(r.bottom).toBe(15)
		-- a taller track eats the cross reservation; it never goes negative
		expect(chrome_slots.barReservation(pkg, 36).top).toBe(0)
		expect(chrome_slots.barReservation(pkg, 200).bottom).toBe(0)
		-- ...and the ends do not shrink with it: a cap is centred on the EDGE
		expect(chrome_slots.barReservation(pkg, 200).left).toBe(14)
	end)

	it("a vertical fill swaps which axis the caps overhang", function()
		local d = valueDisplays()
		d.chrome.barFill.direction = "ttb"
		local pkg = themes.define(d)
		assert(pkg ~= nil, "the vertical fixture must compile")
		local r = chrome_slots.barReservation(pkg, 6)
		expect(r.top).toBe(18) -- half the cap's HEIGHT now sits past the end
		expect(r.bottom).toBe(18)
		expect(r.left).toBe(15) -- and the widest ornament (36) crosses the rail
		expect(r.right).toBe(15)
	end)

	it("a package with no ornaments reserves NOTHING, and neither does a flat one", function()
		local d = valueDisplays()
		d.chrome.barCap = nil
		d.chrome.barCenter = nil
		local bare = themes.define(d)
		assert(bare ~= nil, "the ornament-free fixture must compile")
		local r = chrome_slots.barReservation(bare, 6)
		expect(r.left + r.right + r.top + r.bottom).toBe(0)
		local neutral = chrome_slots.barReservation(snapshot.neutralPackage(), 6)
		expect(neutral.left + neutral.right + neutral.top + neutral.bottom).toBe(0)
		-- the snapshot publishes the same nothing, so the renderer's block is a
		-- no-op for every flat package (byte-identical geometry)
		expect(next(snapshot.resolve(bare, nil, {}).chromeOutsets)).toBeNil()
		expect(next(snapshot.neutral().chromeOutsets)).toBeNil()
	end)

	it("the snapshot publishes it against the track's RESOLVED cross extent", function()
		local snap = snapshot.resolve(built(), nil, {})
		expect(snap.chromeOutsets.barTrack ~= nil).toBe(true)
		expect(snap.chromeOutsets.barTrack.left).toBe(14)
		expect(snap.chromeOutsets.barTrack.top).toBe(15)
		-- a package whose track is as tall as its ornaments reserves the ends only
		local d = valueDisplays()
		d.metrics.controls = d.metrics.controls or {}
		d.metrics.controls.progress = { trackHeight = 36, rowMinHeight = 44 }
		local tall = themes.define(d)
		assert(tall ~= nil, "the tall-track fixture must compile")
		local tallSnap = snapshot.resolve(tall, nil, {})
		expect(tallSnap.chromeOutsets.barTrack.top).toBe(0)
		expect(tallSnap.chromeOutsets.barTrack.left).toBe(14)
	end)

	it("the SOLVER clears the label, the readout and the rows above and below", function()
		local core, env, adapter, _, pres = harness()
		local p =
			LuauUI.newProgressView(LuauUI, core, { id = "Load", label = "Download", value = 0.35, showValue = true })
		pres.present(UI.Screen({
			id = "S",
			children = {
				UI.Text({ id = "Above", text = "Status" }),
				p.blueprint,
				UI.Text({ id = "Below", text = "Saved" }),
			},
		}))
		pres.refresh()
		env:set("themeMetrics", snapshot.resolve(built(), nil, {}))
		pres.refresh()

		local pkg = built()
		local size = chrome_slots.barOrnamentSize(pkg.chrome.barCap)
		local track = adapter.node("/S/Load/Bar").rect
		local label = adapter.node("/S/Load/Label").rect
		local value = adapter.node("/S/Load/Value").rect
		local above = adapter.node("/S/Above").rect
		local below = adapter.node("/S/Below").rect
		-- the two cap boxes, exactly where `barCapBox` puts them: centred on the
		-- track's edges, centred across the rail
		local capTop = track.y + track.h / 2 - size.h / 2
		local capBottom = capTop + size.h
		local startLeft = track.x - size.w / 2
		local endRight = track.x + track.w + size.w / 2

		expect(startLeft >= label.x + label.w).toBe(true)
		expect(endRight <= value.x).toBe(true)
		expect(capTop >= above.y + above.h).toBe(true)
		expect(capBottom <= below.y).toBe(true)
		p.dispose()
	end)
end)

-- ===== 2b. insets that eat the whole track (RS-A16-D3) =====================
--
-- Measured live under pixel-quest: `barTrack.contentInsets = { 8, 8, 8, 8 }` on a
-- track the same package resolves to 8px tall, so the fill solved to
-- max(0, 8 - 16) = ZERO height. The bar drew its trough and both heart end-caps
-- and no fill at all — at 35 % the left third of the trough was indistinguishable
-- from the rest, and `solverDiagnostics` stayed 0. Silent-zero is the
-- accepted-but-invisible class this stage exists to kill, so BOTH halves report:
-- the compiler where the extent is a metric the package itself resolves, and the
-- solver for every case only a live solve can know.

describe("insets that leave no content box are REFUSED or REPORTED", function()
	it("themes.define rejects insets that eat the track height the package resolves", function()
		local d = valueDisplays()
		d.chrome.barTrack.contentInsets = { top = 8, right = 8, bottom = 8, left = 8 }
		d.metrics.controls = d.metrics.controls or {}
		d.metrics.controls.progress = { trackHeight = 16, rowMinHeight = 24 }
		local pkg, report = themes.define(d)
		expect(report.ok).toBe(false)
		expect(pkg).toBeNil()
		local errs = errorsOn(report, "chrome.barTrack.contentInsets")
		expect(#errs).toBe(1)
		expect(errs[1].class).toBe("insetsExceedHost")
		-- the message names the slot, the axis, both numbers and the metric that
		-- decides the extent, because "it renders nothing" is not a diagnosis
		expect(string.find(errs[1].message, "controls.progress.trackHeight", 1, true) ~= nil).toBe(true)
		expect(string.find(errs[1].message, "16", 1, true) ~= nil).toBe(true)

		-- one pixel of content is enough to be legal: this refuses a ZERO box, it
		-- does not invent a minimum
		d.metrics.controls.progress = { trackHeight = 17, rowMinHeight = 24 }
		expect(themes.define(d) ~= nil).toBe(true)
	end)

	it("it measures against the PIXEL-SNAPPED metric, like the reservation does", function()
		-- a pixel package's own snap-up is part of the resolved extent, so the
		-- check has to see the same number the solver will
		local d = valueDisplays()
		d.identity.rendering = "pixel"
		d.identity.pixelUnit = 4
		d.chrome.barTrack.contentInsets = { top = 8, right = 8, bottom = 8, left = 8 }
		d.metrics.controls = d.metrics.controls or {}
		-- 18 snaps UP to 20, which is still not enough for 16px of inset plus
		-- content... it is: 20 - 16 = 4. 14 snaps to 16, which is exactly zero.
		d.metrics.controls.progress = { trackHeight = 14, rowMinHeight = 24 }
		local _, snapped = themes.define(d)
		expect(#errorsOn(snapped, "chrome.barTrack.contentInsets")).toBe(1)
		d.metrics.controls.progress = { trackHeight = 18, rowMinHeight = 24 }
		expect(#errorsOn(select(2, themes.define(d)), "chrome.barTrack.contentInsets")).toBe(0)
	end)

	it("the SOLVER reports an inset the track could not afford, and the fill still draws", function()
		-- the half no compiler can know: the control was given an explicit height
		-- the package's insets cannot afford. Same condition, same numbers, and it
		-- names the chrome slot the insets came from.
		--
		-- THE OUTCOME CHANGED ON 2026-07-28 and this is the record of why. The
		-- reported condition used to be terminal: the fill solved to ZERO and the
		-- bar drew "a trough, two heart caps and no value" (RS-A16-D3's own words).
		-- The director report that closed defect 3 established that a chrome inset
		-- is a REQUEST — spent only if the content box survives it — so the 16px of
		-- barTrack inset on a 12px track is now given back and the value draws at
		-- full height. Same diagnosis, repaired instead of merely announced. The
		-- assertion below is the fill's height precisely because that is the thing
		-- the user could not see.
		local core, env, adapter, _, pres = harness()
		local d = valueDisplays()
		d.chrome.barTrack.contentInsets = { top = 8, right = 8, bottom = 8, left = 8 }
		d.metrics.controls = d.metrics.controls or {}
		d.metrics.controls.progress = { trackHeight = 40, rowMinHeight = 56 }
		local pkg = themes.define(d)
		assert(pkg ~= nil, "the deep-inset fixture must compile at a 40px track")
		local p = LuauUI.newProgressView(LuauUI, core, { id = "Load", value = 0.35, height = 12 })
		local handle = pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		env:set("themeMetrics", snapshot.resolve(pkg, nil, {}))
		pres.refresh()

		expect(adapter.node("/S/Load/Bar").rect.h).toBe(12)
		-- the value is VISIBLE now: the unaffordable inset was given back, so the
		-- fill gets the whole track instead of nothing
		expect(adapter.node("/S/Load/Bar/Fill").rect.h).toBe(12)
		local reported = nil
		for _, entry in handle.controller.diagnostics() do
			if entry.node == "/S/Load/Bar" and string.find(entry.issue, "could not be spent", 1, true) ~= nil then
				reported = entry
			end
		end
		expect(reported ~= nil).toBe(true)
		expect(string.find(reported.issue, "barTrack", 1, true) ~= nil).toBe(true)
		expect(string.find(reported.issue, "16px of border", 1, true) ~= nil).toBe(true)
		expect(string.find(reported.issue, "12px", 1, true) ~= nil).toBe(true)
		-- and a track that CAN afford its insets reports nothing
		local ok = LuauUI.newProgressView(LuauUI, core, { id = "Fine", value = 0.35 })
		pres.present(UI.Screen({ id = "T", children = { ok.blueprint } })).controller.diagnostics()
		pres.refresh()
		p.dispose()
		ok.dispose()
	end)
end)

-- ===== 3. what a value-display package COMPILES to =========================

describe("sheet_model.buildPackage: the value displays' rules", function()
	it("the bar's four slots each get their resting art rule", function()
		local model = sheet_model.buildPackage(built())
		expect(ruleNamed(model, "Chrome — barTrack").props.Image).toBe("rbxassetid://21")
		expect(ruleNamed(model, "Chrome — barTrack").selector).toBe(".luau-chrome-barTrack")
		expect(ruleNamed(model, "Chrome — barFill").props.Image).toBe("rbxassetid://22")
		-- the fill SLICES: it is a stretcher, and its texture is what the window
		-- reveals, so losing the nine-patch is exactly the rs-m4 failure
		expect(ruleNamed(model, "Chrome — barFill").props.ScaleType.item).toBe("Slice")
		-- a cap and a centrepiece are fixed-size tokens: whole image, no slice
		expect(ruleNamed(model, "Chrome — barCap").props.ScaleType.item).toBe("Stretch")
		expect(ruleNamed(model, "Chrome — barCenter").props.Image).toBe("rbxassetid://25")
	end)

	it("an end that named its OWN art gets a second, later-winning rule", function()
		local model = sheet_model.buildPackage(built())
		-- the per-corner idiom one control down: the slot tag paints both caps,
		-- and the per-end rule lands later in insertion order and wins on one
		local startRule = ruleNamed(model, "Chrome — barCap start")
		local endRule = ruleNamed(model, "Chrome — barCap finish")
		expect(startRule).toBeNil() -- it IS the recipe's `asset`, so no second rule
		expect(endRule.selector).toBe(".luau-chrome-barCap-finish")
		expect(endRule.props.Image).toBe("rbxassetid://24")
	end)

	it("a flat bar keeps SOLID native paint through the luau-slot-* family", function()
		-- R9's OWN_PAINT_SLOTS: barTrack/barFill are what a progress bar IS when
		-- unskinned, so they carry the guarantee the slider rail and thumb got
		local flat = sheet_model.buildPackage(snapshot.neutralPackage())
		expect(ruleNamed(flat, "Slot — barTrack").props.BackgroundTransparency.value).toBe(0)
		expect(ruleNamed(flat, "Slot — barTrack").props.BackgroundColor3).toBe("$Control")
		expect(ruleNamed(flat, "Slot — barFill").props.BackgroundColor3).toBe("$Accent")
		-- ...and a flat package emits NO bar art at all
		expect(ruleNamed(flat, "Chrome — barFill")).toBeNil()
		expect(ruleNamed(flat, "Chrome — barCap")).toBeNil()
	end)

	it("the image is the element: a skinned bar's own plate is suppressed", function()
		local model = sheet_model.buildPackage(built())
		expect(ruleNamed(model, "Skinned — barFill").selector).toBe(".luau-skinned-barFill")
		expect(ruleNamed(model, "Skinned — barFill").props.BackgroundTransparency.value).toBe(1)
		expect(ruleNamed(model, "Skinned — barTrack").props.BackgroundTransparency.value).toBe(1)
		expect(ruleNamed(model, "Skinned — toggleTrack").props.BackgroundTransparency.value).toBe(1)
		expect(ruleNamed(model, "Skinned — toggleKnob corner").props.CornerRadius.offset).toBe(0)
	end)

	-- ===== director round 5: the value family's suppression is PRE-ARMED =====
	--
	-- Reported: the glossy-touch download bar's ends read blocky. The measured
	-- generalization is bigger than one package — the suppression was keyed on
	-- the package DECLARING a recipe for the slot, while the tag that selects it
	-- is earned by the NODE, from three different routes. The third route (the
	-- rung-2 per-view override) can skin a slot on a package that declares
	-- nothing for it, which is a tag with no rule: measured live under
	-- glossy-touch, whose rung-2 slider thumb sat on a square opaque plate.

	it("EVERY package suppresses the four value slots, flat ones included", function()
		for _, pkg in { snapshot.neutralPackage(), built() } do
			local model = sheet_model.buildPackage(pkg)
			for _, slot in chrome_slots.OWN_PAINT_SLOTS do
				local plate = ruleNamed(model, `Skinned — {slot}`)
				expect(plate.selector).toBe(`.luau-skinned-{slot}`)
				expect(plate.props.BackgroundTransparency.value).toBe(1)
				local corner = ruleNamed(model, `Skinned — {slot} corner`)
				expect(corner.selector).toBe(`.luau-skinned-{slot}::UICorner`)
				expect(corner.props.CornerRadius.offset).toBe(0)
				expect(corner.props.CornerRadius.scale).toBe(0)
				local outline = ruleNamed(model, `Skinned — {slot} outline`)
				expect(outline.props.Thickness.value).toBe(0)
				expect(outline.props.Transparency.value).toBe(1)
			end
		end
	end)

	it("PAINT FIRST, THEN SUPPRESS: the ordering holds on every one of the four", function()
		-- the flat guarantee is the ACCESSIBILITY floor and has to be the earlier
		-- rule; the suppression only lifts it on a node that carries the art
		for _, pkg in { snapshot.neutralPackage(), built() } do
			local model = sheet_model.buildPackage(pkg)
			local index: { [string]: number } = {}
			for i, rule in model.rules do
				index[rule.name] = i
			end
			for _, slot in chrome_slots.OWN_PAINT_SLOTS do
				expect(index[`Skinned — {slot}`] > index[`Slot — {slot}`]).toBe(true)
				expect(index[`Skinned — {slot} corner`] > index[`Slot — {slot} corner`]).toBe(true)
				expect(index[`Skinned — {slot} outline`] > index[`Slot — {slot} outline`]).toBe(true)
			end
		end
	end)

	it("ONE rule per name, even when the package ALSO declares the recipe", function()
		-- a rule name is identity (the Style Editor lists it, `setRuleProperty`
		-- looks it up); the pre-arm and the recipe loop must not both emit
		local model = sheet_model.buildPackage(built())
		local seen: { [string]: number } = {}
		for _, rule in model.rules do
			seen[rule.name] = (seen[rule.name] or 0) + 1
		end
		for _, slot in chrome_slots.OWN_PAINT_SLOTS do
			expect(seen[`Skinned — {slot}`]).toBe(1)
			expect(seen[`Skinned — {slot} corner`]).toBe(1)
			expect(seen[`Skinned — {slot} outline`]).toBe(1)
		end
		-- and the fixture really is the both-routes case: it declares bar art
		expect(chrome_slots.planFor(built(), "barFill") ~= nil).toBe(true)
	end)

	it("the RUNG-2 hole: a slot the package never declares still has its rule", function()
		-- the live defect. `glossy-touch` declares barTrack/barFill and NO slider
		-- recipe at all, so before this round a view that supplied its own thumb
		-- image earned `luau-skinned-sliderThumb` and nothing matched it.
		local glossy = (require("../examples/themes/glossy_touch") :: any).build(LuauUI.themes)
		expect(chrome_slots.planFor(glossy, "sliderThumb")).toBeNil() -- no recipe
		local override = chrome_slots.planFor(glossy, "sliderThumb", { image = "rbxassetid://991" })
		expect(override.localOverride).toBe(true) -- ...but a view can still skin it
		local model = sheet_model.buildPackage(glossy)
		expect(ruleNamed(model, "Skinned — sliderThumb").props.BackgroundTransparency.value).toBe(1)
		expect(ruleNamed(model, "Skinned — sliderTrack").props.BackgroundTransparency.value).toBe(1)
		-- ...and the node the adapter builds for it carries BOTH tags, so the
		-- solid `Slot —` paint and the suppression select the same instance
		local tags = sheet_model.classifyTags({ slotHint = "sliderThumb", skinnedSlot = "sliderThumb" })
		expect(tags["luau-slot-sliderThumb"]).toBe(true)
		expect(tags["luau-skinned-sliderThumb"]).toBe(true)
	end)

	it("an UNSKINNED value node is byte-unchanged: solid paint, no skinned tag", function()
		-- the other half of the ruling. The accessibility guarantee is for native
		-- paint, and a node with no art never earns the tag that lifts it.
		local flat = sheet_model.buildPackage(snapshot.neutralPackage())
		for _, slot in chrome_slots.OWN_PAINT_SLOTS do
			expect(ruleNamed(flat, `Slot — {slot}`).props.BackgroundTransparency.value).toBe(0)
			local tags = sheet_model.classifyTags({ slotHint = slot })
			expect(tags[`luau-slot-{slot}`]).toBe(true)
			expect(tags[`luau-skinned-{slot}`]).toBeNil()
		end
		-- and a NATIVE gradient still cannot reach any of them: the hazard the
		-- Step 3.5 ruling was written for is untouched by this refinement
		for _, slot in chrome_slots.OWN_PAINT_SLOTS do
			expect(chrome_slots.isGradientable(slot)).toBe(false)
		end
	end)

	it("the census counts the pre-armed baseline instead of hiding it", function()
		local baseline = 3 * #chrome_slots.OWN_PAINT_SLOTS
		expect(sheet_model.buildPackage(snapshot.neutralPackage()).census.suppressionRules).toBe(baseline)
		-- a package that skins non-value slots pays the baseline PLUS its own
		local rich = sheet_model.buildPackage(built()).census.suppressionRules
		expect(rich >= baseline).toBe(true)
		expect(rich % 3).toBe(0)
	end)

	it("a switch's ON art keys on the VALUE tag, never on row selection", function()
		local model = sheet_model.buildPackage(built())
		-- `luau-selected` carries the row treatment (`TextButton.luau-selected`
		-- repaints the whole button); a toggle being on is not a row being chosen
		local on = ruleNamed(model, "Chrome — toggleTrack selected art")
		expect(on.selector).toBe(".luau-toggle-on > .luau-chrome-toggleTrack")
		expect(on.props.Image).toBe("rbxassetid://27")
		expect(ruleNamed(model, "Chrome — toggleTrack selected").selector).toBe(
			".luau-toggle-on > .luau-chrome-toggleTrack"
		)
		-- ...while a panel's `selected` still means row selection
		expect(ruleNamed(model, "Chrome — barTrack selected").selector).toBe(".luau-selected > .luau-chrome-barTrack")
	end)

	it("the knob's per-state art is a CHILD COMBINATOR off the interactive node", function()
		-- which is why P3 moved the knob out of the track: one level deeper and
		-- these rules would be emitted and never match anything
		local model = sheet_model.buildPackage(built())
		expect(ruleNamed(model, "Chrome — toggleKnob hover art").selector).toBe(
			".luau-interactive.luau-pointer-live:Hover > .luau-chrome-toggleKnob"
		)
		expect(ruleNamed(model, "Chrome — toggleKnob pressed art").selector).toBe(
			".luau-interactive:Press > .luau-chrome-toggleKnob"
		)
	end)

	it("every cap asset joins the preload seam, per-end overrides included", function()
		local names: { [string]: boolean } = {}
		for _, entry in chrome_slots.assetsToPreload(built(), "install") do
			names[entry.name] = true
		end
		expect(names.capStart).toBe(true)
		expect(names.capEnd).toBe(true) -- only reachable through `endAsset`
		expect(names.crown).toBe(true)
		expect(names.trackOn).toBe(true) -- only reachable through a variant map
	end)

	it("no wash may reach a value display, and the compiler says so", function()
		local d = valueDisplays()
		d.style.themes[1].extra = d.style.themes[1].extra or {}
		d.style.themes[1].extra.chromeGradient =
			{ barFill = { rotation = 90, stops = { { t = 0, r = 1, g = 1, b = 1 }, { t = 1, r = 0, g = 0, b = 0 } } } }
		local pkg, report = themes.define(d)
		expect(pkg).toBeNil()
		expect(report.ok).toBe(false)
	end)
end)

-- ===== 4. a v2 slot may never UN-SKIN a v1 theme ===========================

describe("chrome_slots.resolveSlot: the stepper plate's fallback", function()
	it("a package with no stepperPlate keeps skinning the stepper as a control", function()
		local d = def()
		d.chrome.control = {
			kind = "nineSlice",
			asset = "plate",
			fallback = "native",
			contentInsets = { top = 4, right = 8, bottom = 4, left = 8 },
		}
		local pkg = themes.define(d)
		assert(pkg ~= nil, "the control-only fixture must compile")
		expect(chrome_slots.resolveSlot(pkg, "stepperPlate")).toBe("control")
		expect(chrome_slots.planFor(pkg, chrome_slots.resolveSlot(pkg, "stepperPlate")) ~= nil).toBe(true)
	end)

	it("a package that DOES declare one wins the slot back", function()
		expect(chrome_slots.resolveSlot(built(), "stepperPlate")).toBe("stepperPlate")
	end)

	it("the bar family is deliberately absent from the fallback map", function()
		-- falling back to `control` is precisely the Step 3.5 leak this row closes:
		-- the track borrowed `surface = "control"` and an ornate package stretched
		-- a button plate across it
		expect(chrome_slots.SLOT_FALLBACK.barTrack).toBeNil()
		expect(chrome_slots.SLOT_FALLBACK.barFill).toBeNil()
		expect(chrome_slots.resolveSlot(snapshot.neutralPackage(), "barTrack")).toBe("barTrack")
		expect(chrome_slots.resolveSlot(built(), nil)).toBeNil()
	end)
end)

describe("sheet_model.classifyTags: the switch's value is a tag", function()
	it("ON emits luau-toggle-on and never the row-selection tag", function()
		local tags = sheet_model.classifyTags({ surface = "control", interactive = true, toggleOn = true })
		expect(tags["luau-toggle-on"]).toBe(true)
		expect(tags["luau-selected"]).toBeNil()
		expect(sheet_model.classifyTags({ surface = "control", interactive = true })["luau-toggle-on"]).toBeNil()
	end)
end)

-- ===== 5. APPLICATION: what the adapter actually builds ====================

describe("screen_target: the bar assembly is materialized as rs-m4 measured", function()
	it("the window CLIPS and is full-bleed over the solved percent rect", function()
		local build = section("local function buildBarFill", "watchChromeAsset(art, plan.assetName)")
		expect(has(build, "window.ClipsDescendants = true")).toBe(true)
		expect(has(build, "window.Size = UDim2.fromScale(1, 1)")).toBe(true)
		expect(has(build, "window.Active = false")).toBe(true)
	end)

	it("the art inside it is sized from the PURE box, never from arithmetic here", function()
		local refresh = section("local function refreshBarFillExtent", "local function buildBarFill")
		expect(has(refresh, "chrome_slots.barFillBox(direction, px)")).toBe(true)
		-- A RESIZE, NEVER A VALUE CHANGE: the extent guard makes every call a no-op
		-- unless the TRACK itself moved, so a percent sweep costs zero writes here
		expect(has(refresh, "if handle.barFillExtent == px then")).toBe(true)
		expect(has(refresh, 'GetPropertyChangedSignal("AbsoluteSize")')).toBe(true)
		-- ...and the track watch is attached on the first call that FINDS a parent.
		-- Live-found: the chrome can be built before the node joins its track, and
		-- a connection made against nil would never fire — the art stayed 0 wide and
		-- its asset was then reported failed for never decoding.
		expect(at(refresh, "if handle.barConn == nil then") < at(refresh, "local px = barTrackExtent")).toBe(true)
	end)

	it("the TRACK is found through the PATH, not through instance.Parent", function()
		-- live-found: this target renders a FLAT instance tree (every node is a
		-- direct child of its root with an absolute rect), so `instance.Parent` was
		-- the ScreenGui and the art was sized from the viewport on one screen and
		-- from nothing on another. The path IS the containment relation here.
		local lookup = section("local function barTrackHandleOf", "local function barTrackExtent")
		expect(has(lookup, 'string.match(path, "^(.*)/[^/]+$")')).toBe(true)
		expect(has(lookup, 'if hint == "barTrack" then')).toBe(true)
		expect(
			has(section("local function barTrackExtent", "local function destroyBarFill"), "barTrackHandleOf(handle)")
		).toBe(true)
	end)

	it("the art's tag is added BEFORE the instance joins the tree", function()
		-- rs-m2's defeat refinement: a rule can only beat a pre-join value if it is
		-- already matching at first application
		local build = section("local function buildBarFill", "watchChromeAsset(art, plan.assetName)")
		expect(at(build, "CollectionService:AddTag(art, plan.tag)") < at(build, "art.Parent = window")).toBe(true)
	end)

	it("NOT ONE paint property is written in native mode", function()
		local build = section("local function buildBarFill", "watchChromeAsset(art, plan.assetName)")
		expect(at(build, "if not nativeMode then") < at(build, "barPaintFor(art, plan)")).toBe(true)
		-- the window is a MASK, not paint: untagged, and the `Frame default` rule
		-- every package emits already holds it transparent
		expect(at(build, "if not nativeMode then") < at(build, "window.BackgroundTransparency = 1")).toBe(true)
	end)

	it("the caps and the centrepiece hang off the TRACK, above the window", function()
		local build = section("local function buildBarOrnaments", "handle.barOrnaments = if #built > 0")
		expect(has(build, "child.ZIndex = 2")).toBe(true)
		expect(has(build, "child.Parent = instance")).toBe(true)
		expect(has(build, "child.Active = false")).toBe(true)
		expect(has(build, "chrome_slots.barCapBox(which, direction, size)")).toBe(true)
		expect(has(build, "chrome_slots.barCenterBox(")).toBe(true)
		-- the window sits BELOW them, so a cap survives 100%
		expect(has(section("local function buildBarFill", "local art = Instance.new"), "window.ZIndex = 1")).toBe(true)
	end)

	it("a value node paints its own plate FIRST and suppresses it after", function()
		-- director round 5, the fallback half. Native mode does this with the
		-- `Slot — <slot>` / `Skinned — <slot>` pair; on a target with no
		-- StyleSheets the adapter writes both, and the ORDER is the whole
		-- guarantee — suppression after paint, or the plate wins and a round
		-- thumb sits on a square slab.
		-- to the END of the chrome module (`return {` is its export table), which
		-- is the rest of syncChromeInner — a tighter window than the anchor this
		-- used before the module was extracted, not a looser one
		local sync = section("applySlotNativePaint(instance, slot, handle)", "\n\treturn {")
		expect(
			at(sync, "applySlotNativePaint(instance, slot, handle)")
				< at(sync, "applySkinnedSuppression(instance, true)")
		).toBe(true)
		-- the fill's own branch returns early, so it carries its own pair
		local fill = section('elseif slot == "barFill" then', "if stack ~= nil then")
		expect(has(fill, "applySkinnedSuppression(instance, true)")).toBe(true)
		-- ...and the suppression is keyed on the node being SKINNED, never on the
		-- package declaring a recipe: a rung-2 override takes the decoration
		-- branch with `plan.localOverride`, and that branch suppresses too
		local deco = section("-- run on EVERY sync, not only at creation", "syncChromeText(handle, deco :: ImageLabel")
		expect(has(deco, "applySkinnedSuppression(instance, true)")).toBe(true)
		-- and it is a NO-OP in native mode, where an explicit write would defeat
		-- the rule it duplicates
		local suppress = section("local function applySkinnedSuppression", "-- ===== SEMANTIC ICONS")
		expect(at(suppress, "if nativeMode then") < at(suppress, "instance.BackgroundTransparency = 1")).toBe(true)
	end)

	it("the assembly's connection and census fall with the node", function()
		local remove = section("function adapter.remove(handle: any)", "handle.instance:Destroy()")
		expect(has(remove, "destroyBarFill(handle)")).toBe(true)
		expect(has(remove, "destroyBarOrnaments(handle)")).toBe(true)
		local destroy = section("local function destroyBarFill", "local function refreshBarFillExtent")
		expect(has(destroy, 'for _, key in { "barConn", "barWindowConn" } do')).toBe(true)
		expect(has(destroy, "handle[key]:Disconnect()")).toBe(true)
		expect(has(destroy, 'chromeState.noteDestroyed("barFill")')).toBe(true)
	end)

	it("a zero-sized image is not a FAILED image (live-found)", function()
		-- the engine decodes nothing it cannot draw, so an art label that is briefly
		-- 0 wide — before its track is laid out, or at 0% — is silent for a reason
		-- that is not failure. The same lesson as the transparency clause beside it.
		local function judge(over: any): any
			local facts: any = {
				attached = true,
				visible = true,
				transparency = 0,
				image = "rbxassetid://1",
				rect = { x = 0, y = 0, w = 473, h = 28 },
				clips = {},
			}
			for k, v in over do
				facts[k] = v
			end
			return chrome_slots.judgeArt(facts)
		end
		expect(judge({ rect = { x = 0, y = 0, w = 0, h = 28 } }).reason).toBe("zeroArea")
		expect(judge({ rect = { x = 0, y = 0, w = 473, h = 0 } }).reason).toBe("zeroArea")
		-- ...and neither is an image with NO SOURCE. Between a target being built
		-- and its package sheet being linked, every decoration is tagged, rule-owned
		-- and blank; the grace timer read that silence as failure and flagged EVERY
		-- asset in the package, including the ones that went on to paint.
		expect(judge({ image = "" }).reason).toBe("noSource")
		-- a laid-out, sourced, on-window bar fill IS evidence
		expect(judge({}).judgeable).toBe(true)
		-- the adapter reads both facts through the STYLED accessor, because both are
		-- rule-owned in native mode
		local facts = section("local function chromeArtJudgement", "return chrome_slots.judgeArt({")
		expect(has(facts, "deco.AbsoluteSize")).toBe(true)
		expect(has(facts, 'GetStyled("Image")')).toBe(true)
	end)
end)

describe("screen_target: the toggle's art rides the instances that already exist", function()
	it("both parts are ImageLabels and DIRECT children of the button", function()
		local build = section("local function buildToggleVisual", "syncToggleArt(handle)")
		expect(has(build, 'local track = Instance.new("ImageLabel")')).toBe(true)
		expect(has(build, 'local knob = Instance.new("ImageLabel")')).toBe(true)
		expect(has(build, "track.Parent = button")).toBe(true)
		expect(has(build, "knob.Parent = button")).toBe(true)
		expect(has(build, "knob.ZIndex = 2")).toBe(true)
	end)

	it("TRAVEL is the same two positions, and art never moves them", function()
		-- both the create and the value site read ONE pair of constants: a magic
		-- number in two places is how a travel assertion quietly stops being about
		-- the same geometry
		expect(has(source, "local TOGGLE_KNOB_OFF = UDim2.new(1, -54, 0.5, 0)")).toBe(true)
		expect(has(source, "local TOGGLE_KNOB_ON = UDim2.new(1, -34, 0.5, 0)")).toBe(true)
		expect(
			has(section("local function buildToggleVisual", "knob.Parent = button"), "knob.Position = TOGGLE_KNOB_OFF")
		).toBe(true)
		local apply = section("local function applyToggleValue", "handle.toggleTrackTween = tween")
		expect(has(apply, "local knobPos = if on then TOGGLE_KNOB_ON else TOGGLE_KNOB_OFF")).toBe(true)
		-- ...and nothing in the art path writes Position or Size on either part
		local art = section("local function syncToggleArt", "watchChromeAsset(target :: any, plan.assetName)")
		expect(has(art, "Position")).toBe(false)
		expect(has(art, ".Size")).toBe(false)
	end)

	-- ===== the REAL chrome children (director round 6, 2026-07-25) ==========
	--
	-- The reported defect: `glossy-touch`'s toggle track rendered as a cluster of
	-- circles and diamonds. It reads exactly like overlapping nine-slice caps —
	-- 72x32 art with a 14px border painted into 44x24, so 28 of vertical cap in
	-- 24px — and that diagnosis is FALSE. The isolating live probe rendered the
	-- same art at 44x24, 44x8 and 20x8 with SliceScale 1 and with the exactly
	-- fitting scale: clean capsules, indistinguishable. **Roblox clamps
	-- overlapping slice caps itself** (`docs/lessons/roblox-slice-and-uicorner.md`).
	--
	-- The one variable that DID reproduce it is a real `UICorner` child on a
	-- `ScaleType = Slice` ImageLabel: the engine rounds each of the nine patches
	-- independently. R9's suppression could not reach it because it works through
	-- PHANTOM `::UICorner` rules and a real child of that class suppresses the
	-- phantom — and the toggle is the one slot whose chrome is real children.
	it("a SKINNED part's real pill and hairline are turned off — no rule can reach them", function()
		local art = section("local function syncToggleArt", "watchChromeAsset(target :: any, plan.assetName)")
		expect(has(art, "setTogglePartChrome(target, true)")).toBe(true)
		local suppress = section("local function setTogglePartChrome", "\n\tend")
		-- it is the CORNER RADIUS that matters: a UICorner on a sliced ImageLabel
		-- rounds every patch, which is the artifact
		expect(has(suppress, 'child:IsA("UICorner")')).toBe(true)
		expect(has(suppress, "UDim.new(0, 0)")).toBe(true)
		expect(has(suppress, 'child:IsA("UIStroke") and child.Name == "Hairline"')).toBe(true)
		-- and it runs in BOTH modes: in native mode there is no rule that could
		expect(has(suppress, "nativeMode")).toBe(false)
	end)

	it("...and RESTORED when the package stops skinning it, so flat is byte-identical", function()
		local off = section("-- back to the palette-true switch", "continue\n\t\t\tend")
		expect(has(off, "setTogglePartChrome(target, false)")).toBe(true)
		local suppress = section("local function setTogglePartChrome", "\n\tend")
		-- the restore reads the SAME theme values the assembly was built from
		expect(has(suppress, "style.radii.pill")).toBe(true)
		expect(has(suppress, "style.strokes.hairline")).toBe(true)
		expect(has(suppress, "style.extra.hairlineOpacity")).toBe(true)
		local build = section("local function buildToggleVisual", "handle.knob = knob")
		expect(has(build, "corner(track, style.radii.pill, true)")).toBe(true)
		expect(has(build, "hairline(track, true)")).toBe(true)
	end)

	it("a decoration built AFTER its texture arrived reports loaded (live-found recovery)", function()
		-- `IsLoaded` is a CHANGE signal and an already-resident image never
		-- changes, so the only recovery path never fired for a decoration built
		-- after the texture landed — an asset marked failed during a cold start
		-- stayed failed for the session. Measured live: every panel/control
		-- decoration in the value fixture carried `luau-chrome-fallback` with
		-- `IsLoaded = true`, and the disabled row then drew its art at 0.4 over
		-- the fallback's native fill.
		local watch = section("local function watchChromeAsset", "\n\tend")
		local judge = string.find(watch, "judge = function()", 1, true) :: number
		local recover = string.find(watch, "setChromeAssetLoaded(assetName, true)", judge, true)
		local fail = string.find(watch, "chromeState.observeAssetFailed(assetName)", judge, true)
		expect(recover ~= nil and fail ~= nil).toBe(true)
		-- the recovery reads IsLoaded at the DEADLINE, not at create: before the
		-- rule applies `Image` is "" and an empty image reports loaded
		expect(recover < (fail :: number)).toBe(true)
		expect(has(watch, "if deco.IsLoaded then")).toBe(true)
		-- ...and the deadline is armed at the grace window and RE-ARMED while the
		-- art is not judgeable (RS-A16-D5), never skipped
		expect(has(watch, "task.delay(CHROME_ASSET_GRACE_SECONDS, judge)")).toBe(true)
	end)

	it("it acts on the two parts only, and moves no geometry", function()
		local suppress = section("local function setTogglePartChrome", "\n\tend")
		for _, forbidden in { "Position", ".Size", "Instance.new", "Destroy" } do
			expect(has(suppress, forbidden)).toBe(false)
		end
		local art = section("local function syncToggleArt", "watchChromeAsset(target :: any, plan.assetName)")
		expect(has(art, "local parts = { toggleTrack = handle.track, toggleKnob = handle.knob }")).toBe(true)
	end)

	it("the ON tag goes through syncTags, so the next pass cannot strip it", function()
		-- the Step 3.5 defect class, one control down: every luau-* tag on this
		-- instance is diffed against classifyTags' desired set
		local apply = section("local function applyToggleValue", "local palette = togglePalette()")
		expect(has(apply, "syncTags(handle)")).toBe(true)
		expect(
			has(
				section("local function syncTags", "for _, tag in CollectionService:GetTags(instance) do"),
				"toggleOn = handle.toggleOn == true"
			)
		).toBe(true)
	end)

	it("art is applied the moment the assembly exists, and on every value change", function()
		-- a toggle built while a skinned package is installed must be BORN in its
		-- art, not repainted into it on the first tap
		expect(
			has(section("local function buildToggleVisual", "-- applyToggleValue(handle, on)"), "syncToggleArt(handle)")
		).toBe(true)
		expect(
			has(section("local function applyToggleValue", "local palette = togglePalette()"), "syncToggleArt(handle)")
		).toBe(true)
	end)

	it("the skinned tag rides both parts, so one suppression set covers them", function()
		local art = section("local function syncToggleArt", "watchChromeAsset(target :: any, plan.assetName)")
		expect(has(art, "chrome_slots.skinnedTagFor(slot)")).toBe(true)
		expect(has(art, "chrome_slots.tagFor(slot)")).toBe(true)
		expect(has(art, "CollectionService:RemoveTag(target, slotTag)")).toBe(true)
	end)
end)

-- ===== 6. the controls declare the slots, and they travel to the adapter ===

describe("the value controls declare their slots on the internal channel", function()
	it("a ProgressView's track and fill reach adapter.create as hints", function()
		local core, _, adapter, _, pres = harness()
		local p = LuauUI.newProgressView(LuauUI, core, { id = "Load", value = 0.4 })
		pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		expect(adapter.node("/S/Load/Bar").decorationHint.slot).toBe("barTrack")
		expect(adapter.node("/S/Load/Bar/Fill").decorationHint.slot).toBe("barFill")
		p.dispose()
	end)

	it("the fill's solved rect is still the percent — geometry stays solver-owned", function()
		local core, _, adapter, _, pres = harness()
		local v = core:signal(0.25)
		local p = LuauUI.newProgressView(LuauUI, core, { id = "Load", value = v })
		pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		local track = adapter.node("/S/Load/Bar").rect
		expect(adapter.node("/S/Load/Bar/Fill").rect.w).toBe(math.floor(track.w * 0.25 + 0.5))
		v:set(1)
		pres.refresh()
		expect(adapter.node("/S/Load/Bar/Fill").rect.w).toBe(track.w)
		p.dispose()
	end)

	it("a Stepper's two affordances declare the plate slot", function()
		local core, _, adapter, _, pres = harness()
		local s = LuauUI.newStepper(LuauUI, core, { id = "Qty", value = core:signal(2), min = 0, max = 9 })
		pres.present(UI.Screen({ id = "S", children = { s.blueprint } }))
		pres.refresh()
		expect(adapter.node("/S/Qty/Dec").decorationHint.slot).toBe("stepperPlate")
		expect(adapter.node("/S/Qty/Inc").decorationHint.slot).toBe("stepperPlate")
		-- the readout is not a plate, and never earns one by accident
		expect(adapter.node("/S/Qty/Value").decorationHint).toBeNil()
		s.dispose()
	end)
end)

-- ===== 7. the bar family's census can FALL (verifier fix round) ============
--
-- runtime + platform verifier F5. `adapter.remove` tore the bar family down;
-- `adapter.destroyRoot` — the whole-root path a screen change or a place teardown
-- actually takes — did not. Every `noteCreated("barFill")` on that path was
-- therefore unpaired, so RS-A17's "367 created / 367 destroyed" was evidence
-- about ONE path rather than an invariant, and the clip window's AbsoluteSize
-- connection outlived the track it was watching.

describe("the bar family's census falls on EVERY teardown path", function()
	it("the ledger itself pairs create with destroy and returns to zero", function()
		local state = chrome_slots.newState(built())
		expect(state.census().perSlot.barFill).toBeNil()
		for _ = 1, 3 do
			state.noteCreated("barFill")
			state.noteCreated("barCap")
			state.noteCreated("barCenter")
		end
		expect(state.census().perSlot.barFill.live).toBe(3)
		expect(state.census().live).toBe(9)
		for _ = 1, 3 do
			state.noteDestroyed("barFill")
			state.noteDestroyed("barCap")
			state.noteDestroyed("barCenter")
		end
		local census = state.census()
		expect(census.perSlot.barFill.live).toBe(0)
		expect(census.perSlot.barFill.created).toBe(3)
		expect(census.perSlot.barFill.destroyed).toBe(3)
		expect(census.live).toBe(0)
		-- ...and the churn is visible: a census that only ever grew could not
		-- distinguish "nothing leaked" from "nothing was ever torn down"
		expect(census.created).toBe(9)
		expect(census.destroyed).toBe(9)
	end)

	-- platform verifier F6. The fill art is sized in OFFSET px inside a space an
	-- ancestor UIScale may have scaled, and the extent was read from AbsoluteSize
	-- — which the engine has ALREADY multiplied by that same scale. Under
	-- UIScale = 2 the art came out at twice the track's width; the pressed dip
	-- (0.985) and the ten-foot focus lift (1.05) mis-register it by a few px in
	-- the ordinary case, which is worse because it reads as a rendering artefact.
	it("the fill extent comes from the SOLVED px, not from post-scale AbsoluteSize", function()
		local extent = section("local function barTrackExtent(handle: any, vertical: boolean): number", "\n\tend")
		-- the solved rect first...
		expect(string.find(extent, "local rect = track.windowRect", 1, true) ~= nil).toBe(true)
		expect(at(extent, "track.windowRect") < at(extent, "AbsoluteSize")).toBe(true)
		-- ...and AbsoluteSize only as the fallback for a track nothing laid out
		expect(string.find(extent, 'if type(rect) == "table" then', 1, true) ~= nil).toBe(true)
		-- the SOLVER's number is what the presenter actually publishes for the
		-- track, in unscaled px, and the fill box is derived from it verbatim
		local core, _, adapter, _, pres = harness()
		local p = LuauUI.newProgressView(LuauUI, core, { id = "Load", value = 0.5 })
		pres.present(UI.Screen({ id = "S", children = { p.blueprint } }))
		pres.refresh()
		local track = adapter.node("/S/Load/Bar").rect
		local box = chrome_slots.barFillBox("ltr", track.w)
		expect(box.size.xOffset).toBe(track.w)
		expect(box.size.xScale).toBe(0)
		p.dispose()
	end)

	it("destroyRoot runs the SAME bar teardown remove does, in reverse order", function()
		local remove = section("function adapter.remove(handle: any)", "handle.instance:Destroy()")
		local destroyRoot = section("function adapter.destroyRoot(rootHandle: any)", "rootHandle.gui:Destroy()")
		for _, call in { "destroyBarFill(handle)", "destroyBarOrnaments(handle)" } do
			expect(string.find(remove, call, 1, true) ~= nil).toBe(true)
			expect(string.find(destroyRoot, call, 1, true) ~= nil).toBe(true)
		end
		-- reverse order of creation on BOTH paths (stack, then bars, then conns)
		expect(at(destroyRoot, "destroyChromeStack(handle)") < at(destroyRoot, "destroyBarFill(handle)")).toBe(true)
		expect(at(destroyRoot, "destroyBarFill(handle)") < at(destroyRoot, "destroyBarOrnaments(handle)")).toBe(true)
		expect(at(destroyRoot, "destroyBarOrnaments(handle)") < at(destroyRoot, "handle.chromeOverrideConn")).toBe(true)
		-- and the destroyer is what pairs the ledger entry the builder opened
		local destroy = section("local function destroyBarFill(handle: any)", "\n\tend")
		expect(string.find(destroy, 'chromeState.noteDestroyed("barFill")', 1, true) ~= nil).toBe(true)
		-- the AbsoluteSize watches go with it, or they keep resizing a corpse
		expect(string.find(destroy, "barConn", 1, true) ~= nil).toBe(true)
		expect(string.find(destroy, "barWindowConn", 1, true) ~= nil).toBe(true)
	end)
end)
