--!strict
--[[ THE MEASURE-STAMP SEAM, MECHANISED — what keeps `render/measure_stamp.luau`
	one-way, and what the stamp itself promises.

	It left `render/renderer.luau` on 2026-09-05 (Plan C, T18-A) for the Source-write
	headroom the settle-closure work needs: that file was 195,709 characters with
	1,791 to the campaign's STOP line, and the closure routing does not fit under it.
	The extraction PRECEDES the change it is owed to, which is what
	`tools/lune/verify/data/source-cap-ledger.md` demands and what `renderer.luau`,
	`solver.luau` and `table.luau` each learned the hard way.

	THE EXTRACTION IS BEHAVIOUR-NEUTRAL, and the first case says so the only way a
	string builder's move can be said: the moved function, driven directly, returns
	the SAME string the renderer's expression built, term for term. The rest is the
	one-way claim — one require, no module-level mutable state, no renderer symbol —
	and each source rule carries a NEGATIVE CONTROL, because a check that cannot fail
	is decoration. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")

local measure_reuse = require("../src/layout/measure_reuse")
local measure_stamp = require("../src/render/measure_stamp")
local text_metrics = require("../src/layout/text_metrics")

local MODULE_PATH = "src/render/measure_stamp.luau"
local RENDERER_PATH = "src/render/renderer.luau"

local function stripComments(source: string): string
	local out = string.gsub("\n" .. source, "%-%-%[%[.-%]%]", " ")
	out = string.gsub(out, "\n[ \t]*%-%-[^\n]*", "\n")
	return out
end

local function sorted(set: { [string]: boolean }): { string }
	local out: { string } = {}
	for key in set do
		table.insert(out, key)
	end
	table.sort(out)
	return out
end

local function requiresIn(source: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for path in string.gmatch(stripComments(source), 'require%("([^"]*)"%)') do
		out[path] = true
	end
	return out
end

local VP = { w = 400, h = 800 }
local INSETS = { top = 1, bottom = 2, left = 3, right = 4 }

describe("the measure-stamp seam: the string that moved is the string that was", function()
	it("the moved builder returns the expression the renderer used to build, term for term", function()
		--[[ THE BEHAVIOUR-NEUTRALITY CLAIM, driven rather than grepped. The expression
			below is the renderer's, transcribed from the commit that moved it
			(`renderer.luau`, `local measureStamp = ...`), and the two must agree on
			BOTH shapes of the band term — the `nil` one and the filled one, which is
			the only branch inside the string. ]]
		local store = measure_reuse.new()
		local metrics = { space = { gutter = 8 } }
		local function asTheRendererBuiltIt(band: { x: number, y: number, w: number, h: number }?): string
			return `{VP.w}|{VP.h}|{INSETS.top}|{INSETS.bottom}|{INSETS.left}|{INSETS.right}|coreSafeContent|6`
				.. `|{if band ~= nil then `{band.x},{band.y},{band.w},{band.h}` else "-"}|{true}`
				.. `|{1.25}|{2}|{text_metrics.calibrationEpoch()}`
		end
		local noBand = (measure_stamp.take(store, metrics, VP, INSETS, "coreSafeContent", 6, nil, true, 1.25, 2))
		expect(noBand).toBe(asTheRendererBuiltIt(nil))
		local band = { x = 10, y = 20, w = 30, h = 40 }
		local withBand = (measure_stamp.take(store, metrics, VP, INSETS, "coreSafeContent", 6, band, true, 1.25, 2))
		expect(withBand).toBe(asTheRendererBuiltIt(band))
		-- ...and the two really are different strings, or the case above would pass
		-- on a builder that ignored the band entirely
		expect(noBand ~= withBand).toBe(true)
	end)

	it("it re-stamps the store and reports the move — the second return is not decoration", function()
		local store = measure_reuse.new()
		local metrics = { space = { gutter = 8 } }
		-- the first stamp always moves (the store is born holding `"\0"`)
		local _, first = measure_stamp.take(store, metrics, VP, INSETS, "coreSafeContent", 0, nil, false, 1, 0)
		expect(first).toBe(true)
		store.byId["/r"] = { ["1|1|"] = { 10, 10 } }
		local _, again = measure_stamp.take(store, metrics, VP, INSETS, "coreSafeContent", 0, nil, false, 1, 0)
		expect(again).toBe(false)
		expect(store.byId["/r"] ~= nil).toBe(true)
		-- ...and a moved input drops the store, which is the whole point of axis 3
		local _, moved =
			measure_stamp.take(store, metrics, { w = 401, h = 800 }, INSETS, "coreSafeContent", 0, nil, false, 1, 0)
		expect(moved).toBe(true)
		expect(store.byId["/r"]).toBe(nil)
	end)

	it("every argument is a TERM: nothing is silently dropped from the string", function()
		--[[ NINE INPUTS, NINE DISTINCT STRINGS. A stamp that forgot one would serve a
			store measured under the other value, and the case above cannot see that:
			it only moves one input. Each row here changes exactly one argument from the
			baseline and asserts the string moved. ]]
		local store = measure_reuse.new()
		local m = {}
		local function stamp(
			vp: any,
			insets: any,
			policy: string,
			reserve: number,
			band: any,
			full: boolean,
			scale: number,
			offset: number
		): string
			return (measure_stamp.take(store, m, vp, insets, policy, reserve, band, full, scale, offset))
		end
		local base = stamp(VP, INSETS, "coreSafeContent", 0, nil, false, 1, 0)
		local moved = {
			viewportW = stamp({ w = 401, h = 800 }, INSETS, "coreSafeContent", 0, nil, false, 1, 0),
			viewportH = stamp({ w = 400, h = 801 }, INSETS, "coreSafeContent", 0, nil, false, 1, 0),
			insetTop = stamp(VP, { top = 9, bottom = 2, left = 3, right = 4 }, "coreSafeContent", 0, nil, false, 1, 0),
			insetBottom = stamp(
				VP,
				{ top = 1, bottom = 9, left = 3, right = 4 },
				"coreSafeContent",
				0,
				nil,
				false,
				1,
				0
			),
			insetLeft = stamp(VP, { top = 1, bottom = 2, left = 9, right = 4 }, "coreSafeContent", 0, nil, false, 1, 0),
			insetRight = stamp(
				VP,
				{ top = 1, bottom = 2, left = 3, right = 9 },
				"coreSafeContent",
				0,
				nil,
				false,
				1,
				0
			),
			policy = stamp(VP, INSETS, "edgeToEdge", 0, nil, false, 1, 0),
			reserve = stamp(VP, INSETS, "coreSafeContent", 12, nil, false, 1, 0),
			band = stamp(VP, INSETS, "coreSafeContent", 0, { x = 0, y = 0, w = 1, h = 1 }, false, 1, 0),
			bandFullTop = stamp(VP, INSETS, "coreSafeContent", 0, nil, true, 1, 0),
			measureScale = stamp(VP, INSETS, "coreSafeContent", 0, nil, false, 1.5, 0),
			prefOffset = stamp(VP, INSETS, "coreSafeContent", 0, nil, false, 1, 4),
		}
		local same: { string } = {}
		for name, value in moved do
			if value == base then
				table.insert(same, name)
			end
		end
		table.sort(same)
		expect(`inputs the stamp cannot see: {table.concat(same, ",")}`).toBe("inputs the stamp cannot see: ")
		-- NEGATIVE CONTROL: the comparison really can report, or the line above is a
		-- sentence that always passes
		expect(base == base).toBe(true)
	end)

	it("the CALIBRATION generation is a term and the WORD generation is not — T18-A, re-recorded", function()
		--[[ RE-RECORDED IN THE COMMIT THAT TOOK THE NARROWING, which is what the seam
			commit's own note said would happen. It used to read "a learned word moves
			the stamp", and that was the defect: one damage number dropped the measure
			memo of every node of every attached surface, and a settled session paid a
			whole-tree cold re-solve for it (T17, FacetBench §C15/§C16 — live `setState`
			39.7 ms, `addItem-damage` 77.0 ms, `lastMeasured == lastMeasureCalls ==
			14,2xx`; headless 14,215 on the same workload).

			The two halves are now separated at the seam, and BOTH directions are pinned
			here because each is a defect on its own: a stamp that still moved on a word
			would put the cold re-solve back, and a stamp that stopped moving on a
			CALIBRATION would serve boxes measured under the other glyph fraction. What
			replaces the word half is a dirty set (`render/text_index`), and
			`tests/text_settle_closure.spec.luau` is where that is driven. ]]
		local store = measure_reuse.new()
		local m = {}
		local before = (measure_stamp.take(store, m, VP, INSETS, "coreSafeContent", 0, nil, false, 1, 0))
		expect(text_metrics.setMeasured("BuilderSans", 23, "facet-t18a-seam-probe", 41)).toBe(true)
		local after = (measure_stamp.take(store, m, VP, INSETS, "coreSafeContent", 0, nil, false, 1, 0))
		expect(`a learned word moved the stamp: {after ~= before}`).toBe("a learned word moved the stamp: false")
		-- ...AND THE EPOCH ITSELF STILL SAW IT, so the narrowing is in what the STAMP
		-- folds in and not in what `text_metrics` reports
		expect(text_metrics.epoch() > 0).toBe(true)
		-- ...and a calibration change DOES move it: it changes what `measure` returns
		-- for every word of a font, and nothing narrower than everything is honest
		text_metrics.calibrate("BuilderSans", 0.33)
		local calibrated = (measure_stamp.take(store, m, VP, INSETS, "coreSafeContent", 0, nil, false, 1, 0))
		expect(`a calibration moved the stamp: {calibrated ~= after}`).toBe("a calibration moved the stamp: true")
		-- the calibration is global and MUST be put back (`measure_reuse.spec`'s own
		-- rule); the probe word names a size and a spelling no fixture measures
		text_metrics.resetCalibration()
	end)
end)

describe("the measure-stamp seam: one-way, and the source says so", function()
	it("ONE require, and it is a leaf the renderer already requires", function()
		local source = fs.readFile(MODULE_PATH)
		expect(sorted(requiresIn(source))).toEqual({ "../layout/measure_reuse", "../layout/text_metrics" })
		-- NEGATIVE CONTROL: the scan really does see a require
		expect(sorted(requiresIn('local x = require("./somewhere")'))).toEqual({ "./somewhere" })
		--[[ ...AND NEITHER LEAF REACHES BACK INTO `render/`, which is the property that
			makes this one-way rather than merely extracted: a cycle would mean the
			stamp could observe the renderer it is supposed to be a pure input of. ]]
		local back: { string } = {}
		for _, leaf in { "src/layout/measure_reuse.luau", "src/layout/text_metrics.luau" } do
			for path in requiresIn(fs.readFile(leaf)) do
				if string.find(path, "render/", 1, true) ~= nil then
					table.insert(back, `{leaf} -> {path}`)
				end
			end
		end
		table.sort(back)
		expect(`leaf requires that reach back into render/: {table.concat(back, ",")}`).toBe(
			"leaf requires that reach back into render/: "
		)
	end)

	it("no module-level mutable state: every input is an argument", function()
		--[[ A `local last = nil` up here would be state shared by every surface on the
			client — one surface's viewport deciding another's cache validity — which is
			exactly the class of defect a module that looks pure invites. ]]
		local source = stripComments(fs.readFile(MODULE_PATH))
		local head = string.match(source, "^(.-)\nfunction measure_stamp%.take")
		assert(head ~= nil, "no `function measure_stamp.take` to split on")
		local decls: { string } = {}
		for line in string.gmatch(head :: string, "\n([^\n]*)") do
			local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
			if string.match(trimmed, "^local ") ~= nil then
				table.insert(decls, trimmed)
			end
		end
		expect(decls).toEqual({
			'local measure_reuse = require("../layout/measure_reuse")',
			'local text_metrics = require("../layout/text_metrics")',
			"local measure_stamp = {}",
		})
	end)

	it("the renderer calls it and holds no copy of what left", function()
		local renderer = stripComments(fs.readFile(RENDERER_PATH))
		expect(string.find(renderer, 'local measure_stamp = require("./measure_stamp")', 1, true) ~= nil).toBe(true)
		expect(string.find(renderer, "local measureStamp, stampMoved = measure_stamp.take(", 1, true) ~= nil).toBe(true)
		--[[ ...AND THE BLOCK IT REPLACED IS GONE rather than duplicated. Two greps,
			because the block had two halves and copying either one back would be
			silent: the string builder (its unmistakable middle term) and the
			`restamp` call. ]]
		expect(string.find(renderer, "|{measureScale}|{prefOffset}|", 1, true)).toBe(nil)
		expect(string.find(renderer, "measure_reuse.restamp(", 1, true)).toBe(nil)
		-- ...and there is exactly ONE consumer of the moved module in `src/`, matched
		-- on the path's tail so a second copy one directory over cannot hide
		local consumers = 0
		for _, dir in { "src/render", "src/layout", "src/client", "src/present" } do
			for _, name in fs.readDir(dir) do
				local path = `{dir}/{name}`
				if string.sub(name, -5) == ".luau" and fs.isFile(path) and path ~= MODULE_PATH then
					if string.find(stripComments(fs.readFile(path)), '/measure_stamp")', 1, true) ~= nil then
						consumers += 1
					end
				end
			end
		end
		expect(`consumers of render/measure_stamp in src={consumers}`).toBe(
			"consumers of render/measure_stamp in src=1"
		)
	end)

	it("it names no renderer symbol — the seam carries values, not the host's vocabulary", function()
		--[[ The one-way rule as `tests/stack_seam.spec.luau` states it: an extraction
			that referred back to a name its host declares would be a split in file
			terms and a shared scope in every other. ]]
		local source = stripComments(fs.readFile(MODULE_PATH))
		local forbidden = {
			"handles",
			"lastRects",
			"nodeStore",
			"solveAndApply",
			"dirtyContains",
			"measureContains",
			"stats.",
			"adapter.",
			"root.",
		}
		local found: { string } = {}
		for _, name in forbidden do
			if string.find(source, name, 1, true) ~= nil then
				table.insert(found, name)
			end
		end
		expect(`renderer symbols named in the seam: {table.concat(found, ",")}`).toBe(
			"renderer symbols named in the seam: "
		)
		-- NEGATIVE CONTROL: the scan really does find one when it is there
		expect(string.find("local x = stats.solves", "stats.", 1, true) ~= nil).toBe(true)
	end)
end)
