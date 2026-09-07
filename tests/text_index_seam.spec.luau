--!strict
--[[ ── THE WORD INDEX, DRIVEN DIRECTLY (RED-TEAM C-5 / C-7 / C-9) ────────────────

	`render/text_index` is reached through a whole renderer everywhere else in this
	suite, and that is right for what those files assert: the push, the closure and
	the probe are only meaningful against a real solve. THESE three are not. They are
	properties of the index's own bookkeeping — what `dispose` gives back, what a
	throw inside the probe leaves behind, and which two values its unchanged-guard is
	allowed to call the same — and each has NO PRODUCER in a mounted tree:

	  * C-5 the leak: retention is bounded by the index object's own lifetime, so it
	    only bites where a disposed controller is still referenced. Nothing a
	    renderer-level fixture can see.
	  * C-7 the throw: `text_metrics.measure` throws on a `node.text` that is a table,
	    and a real tree cannot get one past the mount schema onto a node the probe has
	    a cached width for.
	  * C-9 the `-0`: `pathText[path] == text` compared the RAW value while the derived
	    set is `tostring`-based, and `-0 == 0` is true while `tostring(-0)` is `"-0"`.
	    A signal has to hand the solver a negative zero for that to reach a tree.

	So this file drives `text_index.new()` itself, with hand-built layout-node literals
	standing in for the ones the solver records. That is honest here for the reason the
	renderer-level files state in reverse: the question being asked is about THIS
	module's own state, and a fixture that reached it through a solve would be asserting
	the solve as well.

	THE CAP IS A CALLER ARGUMENT, which is what makes a two-node fixture reach the
	over-cap probe at all: the arm is `#entries > cap`, and the narrow answer is
	`#moved <= cap`. So `take(true, 0)` puts one entry over the cap (and can only come
	back as `full`), and `take(true, 1)` puts two over it while leaving room for one to
	move — which is the shape the C-9 cases need.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local text_index = require("../src/render/text_index")
local text_metrics = require("../src/layout/text_metrics")

local FONT = "BuilderSans"
local SIZE = 13

-- the layout-node literal the solver would have recorded: one word, a cached
-- unbounded width, no compact form and no fit band, which is the whole population
-- the probe answers for (RED-TEAM C-1's positive list)
local function leaf(text: any, cachedWidth: number?): any
	return { text = text, singleLine = true, mTextW = cachedWidth }
end

describe("RED-TEAM C-5: `dispose` gives back every per-path map, not most of them", function()
	it("the census reads 0 after dispose, and it counted something before", function()
		--[[ THE LEAK PIN. `dispose` cleared `byKey`, `pathFont`, `pathSize`, `pathNode`
			and `always` and left D6c's `pathText`/`pathWords` standing — one string and
			one word set per text path the index had ever measured, retained for as long
			as anything still referenced the disposed controller (a presenter holding a
			torn-down surface, a Studio module reload).

			`census()` is ONE number across all six maps plus the key buckets, for the
			reason the leak happened: six separate assertions are six things to forget,
			and D6c's two were forgotten. A non-zero reading BEFORE is what stops the
			zero after from being a fixture that recorded nothing. ]]
		local before = text_index.liveCount()
		local index = text_index.new()
		for i = 1, 40 do
			index.record(`/Root/L{i}`, FONT, SIZE, false, leaf(`c5word{i}`, 10 + i))
		end
		local filled = index.census()
		index.dispose()
		expect(`filled>0={tostring(filled > 0)} after dispose={index.census()} live={text_index.liveCount() - before}`).toBe(
			"filled>0=true after dispose=0 live=0"
		)
	end)
end)

describe("RED-TEAM C-7: a throw inside the probe still hands the collector back", function()
	it("the collector is still open after the probe raises, and the error is the measure's own", function()
		--[[ THE SILENCE THIS REFUSES. `take`'s over-cap arm suspends the word collector
			across the probe loop and resumes it after. A throw inside
			`text_metrics.measure` skipped the resume, so `collecting` stayed nil for the
			REST OF THE SOLVE and every word that solve would have collected was dropped
			with no counter moving — the exact failure this module's own doctrine ("the
			collector's own silence, made loud") exists to refuse.

			The throw is manufactured the only way it can be: a `node.text` that is a
			table, on a node the index has a cached width for. `text_metrics.measure`
			indexes it as a string and raises.

			THE ASSERTION IS THE COLLECTOR, NOT THE ERROR. After the throw a measure of an
			unknown word must still be COLLECTED, which is only true if `resumeCollect`
			ran. At the parent commit `asked` reads 0 here. ]]
		text_metrics.resetMeasured()
		local index = text_index.new()
		index.record("/Root/Bad", FONT, SIZE, false, leaf({ not_a_string = true }, 40))
		index.mark(text_metrics.metricKey(FONT, SIZE), "c7Word")

		text_metrics.beginCollect()
		local ok, err = pcall(index.take, true, 0)
		-- the throw really happened, and it is the MEASURE's message rather than a
		-- wrapper this file invented
		expect(`threw={tostring(not ok)} fromMeasure={tostring(string.find(tostring(err), "text", 1, true) ~= nil)}`).toBe(
			"threw=true fromMeasure=true"
		)
		text_metrics.measure("c7AfterTheThrow", FONT, SIZE, math.huge)
		local asked = text_metrics.endCollect()
		expect(`asked={#asked}`).toBe("asked=1")
		index.dispose()
		text_metrics.resetMeasured()
	end)
end)

describe("RED-TEAM C-9: the unchanged-guard compares the string the label DRAWS", function()
	it("a numeric label moving from 0 to -0 re-derives its word set", function()
		--[[ TWO VALUES `==` CALLS EQUAL AND THE ENGINE DRAWS DIFFERENTLY. `noteWords`
			returned on `pathText[path] == text` with the RAW value on both sides, so a
			label going from `0` to `-0` kept a `pathWords` naming `"0"` — and the
			over-cap probe then word-skipped it for a correction to `"-0"`, the token it
			is actually drawing. The engine draws `tostring(text)` and
			`text_metrics.measure` coerces the same way, so the guard has to.

			DRIVEN THROUGH THE PUSH, because that is where the stale set is spent: the
			path is recorded at `0`, re-recorded at `-0`, and a correction to `"-0"` must
			PUSH it. `paths=1` here; before the fix it is 0 with `skips=2`.

			TWO PATHS AND `cap = 1`, because one path cannot express this: the over-cap
			arm is `#entries > cap` and the narrow answer is `#moved <= cap`, so a single
			entry at `cap = 0` can only come back as `full`. The second leaf draws a word
			nothing corrects, so it is the D6c skip that puts the push over the cap and
			the numeric leaf is the only thing that can move. ]]
		text_metrics.resetMeasured()
		local index = text_index.new()
		local key = text_metrics.metricKey(FONT, SIZE)
		index.record("/Root/Num", FONT, SIZE, false, leaf(0, 12))
		--[[ THE SAME LITERAL WOULD NOT DO: `record` writes `pathNode` unconditionally and
			`noteWords` reads `node.text` off whatever it was handed, so the second call
			is the rebuilt literal a text change produces. `mTextW` is deliberately a
			width the probe's own measure cannot reproduce, so a leaf that REACHES the
			measure is kept and the only way to read `paths=0` is the word skip. ]]
		index.record("/Root/Num", FONT, SIZE, false, leaf(-0, 12))
		index.record("/Root/Other", FONT, SIZE, false, leaf("c9Other", 12))
		index.mark(key, "-0")
		local plan = index.take(true, 1)
		expect(plan ~= nil).toBe(true)
		local p = plan :: any
		expect(`full={tostring(p.full)} paths={p.n} probes={p.probed} skips={p.skipped}`).toBe(
			"full=false paths=1 probes=1 skips=1"
		)
		index.dispose()
		text_metrics.resetMeasured()
	end)

	it("...and the CONTROL: a numeric label that did not move is still skipped", function()
		--[[ THE OTHER DIRECTION, so the fix cannot be "stop skipping". A label drawing
			`12` and a correction to `"99"` is the D6c narrowing doing exactly its job,
			and it must still read `skips=1 probes=0` — the guard's coercion changed which
			STRING is compared, never which question is asked. ]]
		text_metrics.resetMeasured()
		local index = text_index.new()
		local key = text_metrics.metricKey(FONT, SIZE)
		index.record("/Root/Num", FONT, SIZE, false, leaf(12, 12))
		index.record("/Root/Other", FONT, SIZE, false, leaf("c9Other", 12))
		index.mark(key, "99")
		local plan = index.take(true, 1)
		local p = plan :: any
		expect(`paths={p.n} probes={p.probed} skips={p.skipped}`).toBe("paths=0 probes=0 skips=2")
		index.dispose()
		text_metrics.resetMeasured()
	end)
end)
