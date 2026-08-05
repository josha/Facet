--!strict
-- EXACT TEXT MEASUREMENT (text-measurement milestone, 2026-07-24).
--
-- The estimator's error is VARIANCE, not font: an average-glyph model cannot
-- bound a specific short string within 8% (measured live — "Volume" needs
-- 0.469 em/glyph where the corpus average is 0.395), so tightening the average
-- clips text and leaving it loose reserves a wrap the engine never draws. The
-- fix is to stop averaging and measure WORDS.
--
-- Words, not laid-out strings: exact word widths plus an exact space width
-- give exact greedy wrapping at ANY width, so the cache is keyed
-- (font, size, word) and survives every resize and every device profile. A
-- key including maxWidth would miss on every one of them.
--
-- Two ends of one seam: src/layout/text_metrics owns the pure per-word store
-- and emits the words a solve could not size; src/client/text_premeasure
-- measures them with TextService off the render path and feeds them back.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local text_metrics = require("../src/layout/text_metrics")
local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local fake_target = require("../tests/lib/fake_target")

-- a stand-in engine: 0.45 em per glyph, a quarter-em space. Deliberately
-- NARROWER than the 0.62 conservative estimate (that gap is the whole defect)
-- and wider than the calibrated 0.395 average, i.e. the real BuilderSans band.
local ENGINE_GLYPH = 0.45
local ENGINE_SPACE = 0.25
local function engineWidth(word: string, size: number): number
	if word == " " then
		return size * ENGINE_SPACE
	end
	return (utf8.len(word) :: number) * size * ENGINE_GLYPH
end

local function feed(font: string, size: number, words: { string })
	for _, word in words do
		text_metrics.setMeasured(font, size, word, engineWidth(word, size))
	end
end

local function wordsOf(requests: { any }): { string }
	local out = {}
	for _, r in requests do
		table.insert(out, r.word)
	end
	table.sort(out)
	return out
end

describe("text_metrics: the per-word exact store", function()
	it("an exact width replaces the estimate for that word and no other", function()
		text_metrics.resetMeasured()
		local before = text_metrics.measure("Volume Brightness", "BuilderSans", 20, math.huge)
		local otherBefore = text_metrics.measure("Brightness", "BuilderSans", 20, math.huge).width
		text_metrics.setMeasured("BuilderSans", 20, "Volume", 60)
		local after = text_metrics.measure("Volume Brightness", "BuilderSans", 20, math.huge)
		-- "Volume" estimated at 6 * 20 * 0.62 = 74.4; exact 60 is 14.4 narrower
		-- (210.8 -> 196.4, each ceiled: 211 -> 197)
		expect(before.width).toBe(211)
		expect(after.width).toBe(197)
		-- "Brightness" is untouched: it still carries its estimate
		expect(text_metrics.measure("Brightness", "BuilderSans", 20, math.huge).width).toBe(otherBefore)
		text_metrics.resetMeasured()
	end)

	it("the same word at a different size or font is a different measurement", function()
		text_metrics.resetMeasured()
		text_metrics.setMeasured("BuilderSans", 20, "Save", 40)
		expect(text_metrics.measure("Save", "BuilderSans", 20, math.huge).width).toBe(40)
		-- size 24 has never been measured: still the estimate
		expect(text_metrics.measure("Save", "BuilderSans", 24, math.huge).width).toBe(math.ceil(4 * 24 * 0.62))
		-- a different font has never been measured either
		expect(text_metrics.measure("Save", "SourceSans", 20, math.huge).width).toBe(math.ceil(4 * 20 * 0.62))
		text_metrics.resetMeasured()
	end)

	it("an exact width WIDER than the estimate still wins — exactness is not a tightening-only seam", function()
		text_metrics.resetMeasured()
		local estimated = text_metrics.measure("W", "BuilderSans", 20, math.huge).width
		text_metrics.setMeasured("BuilderSans", 20, "W", 19) -- a real 'W' is nearly a full em
		expect(text_metrics.measure("W", "BuilderSans", 20, math.huge).width > estimated).toBe(true)
		text_metrics.resetMeasured()
	end)

	it("rejects a measurement that could cause a clip, keeping the safe estimate", function()
		text_metrics.resetMeasured()
		local safe = text_metrics.measure("Volume", "BuilderSans", 20, math.huge).width
		expect(text_metrics.setMeasured("BuilderSans", 20, "Volume", 0 / 0)).toBe(false)
		expect(text_metrics.setMeasured("BuilderSans", 20, "Volume", math.huge)).toBe(false)
		expect(text_metrics.setMeasured("BuilderSans", 20, "Volume", -5)).toBe(false)
		expect(text_metrics.setMeasured("BuilderSans", 20, "Volume", 0)).toBe(false)
		expect(text_metrics.measure("Volume", "BuilderSans", 20, math.huge).width).toBe(safe)
		text_metrics.resetMeasured()
	end)

	it("an exact space width is used between words", function()
		text_metrics.resetMeasured()
		text_metrics.setMeasured("BuilderSans", 20, "a", 9)
		text_metrics.setMeasured("BuilderSans", 20, "b", 9)
		local estimatedSpace = text_metrics.measure("a b", "BuilderSans", 20, math.huge).width
		expect(estimatedSpace).toBe(math.ceil(9 + 20 * 0.62 + 9))
		text_metrics.setMeasured("BuilderSans", 20, " ", 5)
		-- 9 + 5 + 9 = 23, PLUS the one 0.5 px grid step the joint reserves since
		-- director round 9 — the engine reports on a 0.5 grid and lays a whole
		-- line out in one pass, so a per-word sum could land a step short of it
		expect(text_metrics.measure("a b", "BuilderSans", 20, math.huge).width).toBe(24)
		text_metrics.resetMeasured()
	end)
end)

describe("text_metrics: the request set a solve emits", function()
	it("collects one request per unknown word plus the space, deduped and ordered", function()
		text_metrics.resetMeasured()
		text_metrics.beginCollect()
		text_metrics.measure("Save changes Save", "BuilderSans", 18, 500)
		local requests = text_metrics.endCollect()
		expect(wordsOf(requests)).toEqual({ " ", "Save", "changes" })
		text_metrics.resetMeasured()
	end)

	it("keys on (font, size, word) — NOT maxWidth, so a resize costs no new measurement", function()
		text_metrics.resetMeasured()
		text_metrics.beginCollect()
		text_metrics.measure("Save changes", "BuilderSans", 18, 500)
		expect(#text_metrics.endCollect()).toBe(3) -- "Save", "changes", " "
		feed("BuilderSans", 18, { "Save", "changes", " " })
		-- the SAME vocabulary at four different widths asks for nothing more
		text_metrics.beginCollect()
		for _, w in { 80, 120, 300, math.huge } do
			text_metrics.measure("Save changes", "BuilderSans", 18, w)
		end
		expect(#text_metrics.endCollect()).toBe(0)
		text_metrics.resetMeasured()
	end)

	it("a word the engine could not measure is never asked for again", function()
		text_metrics.resetMeasured()
		text_metrics.beginCollect()
		text_metrics.measure("Zzz", "Wingdings", 18, 500)
		expect(#text_metrics.endCollect() > 0).toBe(true)
		text_metrics.markUnmeasurable("Wingdings", 18, "Zzz")
		text_metrics.markUnmeasurable("Wingdings", 18, " ")
		text_metrics.beginCollect()
		local again = text_metrics.measure("Zzz", "Wingdings", 18, 500)
		expect(#text_metrics.endCollect()).toBe(0)
		-- and it keeps the conservative full-em fallback rather than guessing
		expect(again.width).toBe(3 * 18)
		text_metrics.resetMeasured()
	end)

	it("nothing is collected outside a collect bracket (the solver stays request-free by default)", function()
		text_metrics.resetMeasured()
		text_metrics.measure("Save changes", "BuilderSans", 18, 500)
		text_metrics.beginCollect()
		local requests = text_metrics.endCollect()
		expect(#requests).toBe(0)
		text_metrics.resetMeasured()
	end)

	it("reports whether a measurement was exact end to end", function()
		text_metrics.resetMeasured()
		expect(text_metrics.measure("Save changes", "BuilderSans", 18, 500).exact).toBe(false)
		feed("BuilderSans", 18, { "Save", "changes" })
		expect(text_metrics.measure("Save changes", "BuilderSans", 18, 500).exact).toBe(false) -- space still unknown
		feed("BuilderSans", 18, { " " })
		expect(text_metrics.measure("Save changes", "BuilderSans", 18, 500).exact).toBe(true)
		-- a single word needs no space to be exact
		expect(text_metrics.measure("Save", "BuilderSans", 18, 500).exact).toBe(true)
		text_metrics.resetMeasured()
	end)

	it("exact word widths wrap greedily exactly where the engine would", function()
		text_metrics.resetMeasured()
		feed("BuilderSans", 20, { "aaaa", "bbbb", "cccc", " " })
		-- each word is 4 * 20 * 0.45 = 36; a space is 5
		local twoPerLine = text_metrics.measure("aaaa bbbb cccc", "BuilderSans", 20, 80)
		expect(twoPerLine.lines).toBe(2) -- 36+5.5+36 = 77.5 fits 80; a third would be 119
		expect(twoPerLine.width).toBe(78) -- 77.5 with the joint's grid step, ceiled
		local onePerLine = text_metrics.measure("aaaa bbbb cccc", "BuilderSans", 20, 76)
		expect(onePerLine.lines).toBe(3)
		expect(onePerLine.width).toBe(36)
		text_metrics.resetMeasured()
	end)
end)

-- ---------------------------------------------------------------------------
-- The loop: solve (estimate) -> measure off the render path -> ONE re-solve.
-- ---------------------------------------------------------------------------

local function actionSlice()
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 800 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local bp = UI.Screen({
		id = "S",
		padding = 0,
		children = {
			-- the real fixture shape: an action button whose label the ESTIMATOR
			-- wraps and the ENGINE does not
			UI.Button({ id = "Save", label = "Save changes", width = { type = "fixed", px = 130 } }),
		},
	})
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {})
	controller.initialRender()
	return env, root, adapter, controller
end

describe("renderer: engine premeasurement round", function()
	it("reserves the estimate on the first frame and the EXACT box after one re-solve", function()
		text_metrics.resetMeasured()
		local _, root, adapter, controller = actionSlice()
		-- first frame: 12+12 padding leaves 106px; the estimate says
		-- "Save changes" needs 133.9px, so it reserves a second line it will
		-- never draw. This is the shipped defect, at its shipped numbers.
		-- ("Save changes" is a PHRASE, so it legitimately wraps — round 13's
		-- single-line rule applies to one-word labels, which have no legal break.)
		expect(adapter.node("/S/Save").rect.h).toBe(68)
		local solvesBefore = controller.stats().solves
		expect(adapter.textBatchCount()).toBe(1)
		expect(adapter.pendingTextWords()).toEqual({ " ", "Save", "changes" })
		adapter.deliverTextWidths(engineWidth)
		-- exactly ONE re-solve, and the box is now what the engine draws
		expect(controller.stats().solves - solvesBefore).toBe(1)
		expect(adapter.node("/S/Save").rect.h).toBe(46)
		root.dispose()
		text_metrics.resetMeasured()
	end)

	it("publishes a MEASURE EPOCH, so a consumer memo can depend on exactness", function()
		--[[ DIRECTOR 2026-08-04, the finish-screen size pop.

			The re-solve above fixes the SOLVER's boxes. It does nothing for a
			consumer MEMO that called `LuauUI.text.fit/.size/.measure` to derive its
			own reservation — the exact-width store is plain, non-reactive data, so
			such a memo has no dependency to invalidate. It evaluated once, against
			the ESTIMATOR, and then changed at whatever arbitrary later moment some
			unrelated dependency happened to tick. That is what a size change with no
			visible cause is.

			`textMeasureEpoch` is the missing dependency. It must bump exactly when
			the store LEARNS something — not per frame (which would re-derive every
			memo forever) and not per delivery (a round that taught nothing must cost
			nothing). ]]
		text_metrics.resetMeasured()
		local env, root, adapter = actionSlice()
		local epoch = env:get("textMeasureEpoch")
		local before = epoch:get()
		adapter.deliverTextWidths(engineWidth)
		-- EXACTLY one, not merely "more": an epoch that over-counts re-derives
		-- every dependent memo more often than the store actually changed
		expect(`bumped={epoch:get() - before}`).toBe("bumped=1")
		--[[ ...and a SECOND delivery that teaches nothing does not bump it. This is
			the half that keeps the fact honest: an epoch that ticked on every round
			would re-derive every dependent memo forever, which trades a pop for a
			permanent cost. ]]
		local settled = epoch:get()
		adapter.deliverTextWidths(engineWidth)
		expect(`quiet={epoch:get()}`).toBe(`quiet={settled}`)
		root.dispose()
		text_metrics.resetMeasured()
	end)

	it("a known vocabulary asks for nothing on later solves", function()
		text_metrics.resetMeasured()
		local env, root, adapter, controller = actionSlice()
		adapter.deliverTextWidths(engineWidth)
		-- the re-solve the delivery triggered found every word already exact,
		-- so it opened no second round
		expect(adapter.textBatchCount()).toBe(0)
		-- and a REAL re-solve (a resize — the case a maxWidth-keyed cache would
		-- miss on) still asks for nothing, at four different widths
		local solves = controller.stats().solves
		for _, w in { 320, 500, 240, 1000 } do
			env:set("viewportRect", { x = 0, y = 0, w = w, h = 800 })
		end
		expect(controller.stats().solves).toBe(solves + 4)
		expect(adapter.textBatchCount()).toBe(0)
		root.dispose()
		text_metrics.resetMeasured()
	end)

	it("an adapter with no premeasurement seam keeps today's conservative geometry", function()
		text_metrics.resetMeasured()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 800 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				padding = 0,
				children = { UI.Button({ id = "Save", label = "Save changes", width = { type = "fixed", px = 130 } }) },
			})
		)
		local adapter = fake_target.new()
		adapter.measureTextWidths = nil
		local controller = renderer.attach(core, root, env, adapter, {})
		controller.initialRender()
		expect(adapter.node("/S/Save").rect.h).toBe(68)
		expect(controller.stats().solves).toBe(1)
		root.dispose()
		text_metrics.resetMeasured()
	end)

	it("a measurement arriving after dispose neither crashes nor re-solves", function()
		text_metrics.resetMeasured()
		local _, root, adapter, controller = actionSlice()
		local solves = controller.stats().solves
		controller.dispose()
		root.dispose()
		adapter.deliverTextWidths(engineWidth)
		expect(controller.stats().solves).toBe(solves)
		text_metrics.resetMeasured()
	end)

	-- BOOT-WINDOW CORRECTION (found live 2026-07-24). The engine's bounds API
	-- answers differently during the first moments of a session — stably, and
	-- without complaint — so the adapter re-reads each batch once the session
	-- has settled and answers the SAME batch a second time with corrections.
	-- A cached wrong width is permanent (a measured word is never re-requested),
	-- so this second answer is the only thing that makes the exactness claim
	-- true rather than lucky.
	it("a corrected width from a second answer to the same batch replaces the first", function()
		text_metrics.resetMeasured()
		local _, root, adapter, controller = actionSlice()
		-- a boot answer wide enough to change the layout. The live error was
		-- 4-6% (Volume@16 measured 47 at boot against a settled 45); it is
		-- widened here so the correction is visible in geometry and not only in
		-- the store.
		adapter.deliverTextWidths(function(word, size)
			return engineWidth(word, size) * 1.2
		end)
		local bootHeight = adapter.node("/S/Save").rect.h
		local solves = controller.stats().solves
		-- the settled re-read, delivered against the same batch
		adapter.answerAgain(function(word, size)
			return engineWidth(word, size)
		end)
		expect(text_metrics.measuredWidth("BuilderSans", 18, "changes")).toBe(engineWidth("changes", 18))
		expect(controller.stats().solves).toBe(solves + 1)
		expect(adapter.node("/S/Save").rect.h).toBe(46)
		expect(bootHeight).toBe(68) -- the boot answer still wrapped
		root.dispose()
		text_metrics.resetMeasured()
	end)

	it("a second answer that agrees with the first costs no re-solve", function()
		text_metrics.resetMeasured()
		local _, root, adapter, controller = actionSlice()
		adapter.deliverTextWidths(engineWidth)
		local solves = controller.stats().solves
		adapter.answerAgain(engineWidth)
		expect(controller.stats().solves).toBe(solves)
		root.dispose()
		text_metrics.resetMeasured()
	end)

	it("an engine that cannot measure a word leaves the safe estimate and stops asking", function()
		text_metrics.resetMeasured()
		local env, root, adapter, controller = actionSlice()
		adapter.deliverTextWidths(function()
			return nil -- the engine refused every word
		end)
		expect(adapter.node("/S/Save").rect.h).toBe(68) -- unchanged, still safe
		-- a genuine re-solve does not re-open the question: a word nobody can
		-- measure would otherwise be asked for on every single solve, forever
		env:set("viewportRect", { x = 0, y = 0, w = 360, h = 800 })
		expect(controller.stats().solves > 1).toBe(true)
		expect(adapter.textBatchCount()).toBe(0)
		root.dispose()
		text_metrics.resetMeasured()
	end)
end)

-- ---------------------------------------------------------------------------
-- NO POP: a surface can wait for exact text before it is ever seen.
--
-- The reflow is small and always shrinks (the estimate can only over-reserve),
-- but "usually doesn't jump" is not a property anyone can build on. A screen
-- that opts in mounts and measures while its ROOT is hidden and reveals itself
-- already exact. The gate is bounded by a deadline, because a hidden UI is a
-- worse failure than a jumpy one.
-- ---------------------------------------------------------------------------

local presenterLib = require("../src/present/presenter")
local actionsLib = require("../src/input/actions")

local function gatedScreen(opts: any)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 800 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local adapter = fake_target.new()
	local system = actionsLib.newSystem(core)
	local pres = presenterLib.new(core, env, adapter, system)
	local screen = UI.Screen({
		id = "Gated",
		padding = 0,
		children = { UI.Button({ id = "Save", label = "Save changes", width = { type = "fixed", px = 130 } }) },
	})
	local handle = pres.present(screen, opts)
	return adapter, pres, handle
end

describe("presenter: revealWhenTextExact", function()
	it("keeps the surface hidden until the text round closes, then reveals it exact", function()
		text_metrics.resetMeasured()
		local adapter, pres = gatedScreen({ revealWhenTextExact = true })
		expect(adapter.rootVisibleOf("Gated")).toBe(false)
		-- the conservative first solve has already happened underneath
		expect(adapter.node("/Gated/Save").rect.h).toBe(68)
		pres.refresh()
		expect(adapter.rootVisibleOf("Gated")).toBe(false) -- still measuring
		adapter.deliverTextWidths(engineWidth)
		pres.refresh()
		expect(adapter.rootVisibleOf("Gated")).toBe(true)
		-- and what it revealed was the exact box, never the fat one
		expect(adapter.node("/Gated/Save").rect.h).toBe(46)
		text_metrics.resetMeasured()
	end)

	it("keeps waiting through a NON-FINAL answer, so a boot-window correction cannot pop after the reveal", function()
		text_metrics.resetMeasured()
		local adapter, pres = gatedScreen({ revealWhenTextExact = true })
		-- the adapter answers early with untrusted widths and says so
		adapter.deliverTextWidths(function(word, size)
			return engineWidth(word, size) * 1.2
		end, false)
		pres.refresh()
		expect(adapter.rootVisibleOf("Gated")).toBe(false)
		-- ...and only the settled answer closes the round
		adapter.answerAgain(engineWidth, true)
		pres.refresh()
		expect(adapter.rootVisibleOf("Gated")).toBe(true)
		expect(adapter.node("/Gated/Save").rect.h).toBe(46)
		text_metrics.resetMeasured()
	end)

	it("reveals anyway when the deadline passes: a hidden UI is worse than a jumpy one", function()
		text_metrics.resetMeasured()
		local adapter, pres = gatedScreen({ revealWhenTextExact = true, revealTimeout = 0 })
		pres.refresh()
		expect(adapter.rootVisibleOf("Gated")).toBe(true)
		expect(adapter.node("/Gated/Save").rect.h).toBe(68) -- the safe box, never a clipped one
		text_metrics.resetMeasured()
	end)

	it("does not gate a surface that never asked to be gated", function()
		text_metrics.resetMeasured()
		local adapter = gatedScreen({})
		expect(adapter.rootVisibleOf("Gated")).never().toBe(false)
		text_metrics.resetMeasured()
	end)

	it("never hides a surface on an adapter that cannot show it again", function()
		text_metrics.resetMeasured()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 800 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		adapter.setRootVisible = nil -- an adapter with no whole-root visibility
		local pres = presenterLib.new(core, env, adapter, actionsLib.newSystem(core))
		pres.present(
			UI.Screen({
				id = "Gated",
				padding = 0,
				children = { UI.Button({ id = "Save", label = "Save changes", width = { type = "fixed", px = 130 } }) },
			}),
			{ revealWhenTextExact = true }
		)
		-- gating is impossible here, so the surface is simply NOT gated: it must
		-- never end up in a hidden state nothing can clear
		expect(adapter.rootVisibleOf("Gated")).toBeNil()
		pres.refresh()
		expect(adapter.rootVisibleOf("Gated")).toBeNil()
		expect(adapter.node("/Gated/Save") ~= nil).toBe(true)
		text_metrics.resetMeasured()
	end)

	it("reveals immediately on an adapter with no premeasurement seam", function()
		text_metrics.resetMeasured()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 800 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		adapter.measureTextWidths = nil
		local pres = presenterLib.new(core, env, adapter, actionsLib.newSystem(core))
		pres.present(UI.Screen({ id = "Gated", children = { UI.Text({ id = "T", text = "hi" }) } }), {
			revealWhenTextExact = true,
		})
		pres.refresh()
		expect(adapter.rootVisibleOf("Gated")).toBe(true)
		text_metrics.resetMeasured()
	end)
end)
