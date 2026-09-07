--!strict
--[[
	AN IN-FLIGHT WORD STOPS EATING THE COLLECTOR BUDGET (Plan D, D3a — scout S2,
	FacetBench §8b).

	WHAT WAS WRONG, MEASURED LIVE. `layout/text_metrics`'s per-solve word collector
	carries `COLLECT_CAP = 1024`, filled in DOCUMENT ORDER, and its only test is
	`known == nil` — the store's answer. A word that has been REQUESTED and not yet
	ANSWERED is still `nil` in the store, so the whole outstanding backlog re-consumed
	the budget on every whole-tree solve. Live in the boot window the first batch
	cannot be answered inline (`client/text_premeasure.measureBatch` warms the font
	first and `ContentProvider:PreloadAsync` yields; FacetBench's loop driver applies
	its steps in one unbroken Luau run, so that thread never resumes), so with a
	1,023-word backlog a solve had room for exactly ONE new word. FacetBench §8b
	recorded the walk to the digit on `battle_hud` L: `#1 n=1 "744"`, `#2 "724"`,
	`#3 "725"`, `#4 "726"` … `#65 "786"`, all at `BuilderSans#Regular#Normal/12` —
	sixty-five rounds, each of which is a learned word marking a 1,000-user key over
	the push cap and therefore a ~52 ms whole-tree cold solve.

	§8b read that walk as boxes moving ("each learned width brings the next unmeasured
	row into the measured set"). It is not: nothing in the layout stops measurement
	early, so a full solve that re-measured 1,000 labels would have collected ALL their
	unmeasured words in one round. The budget is the mechanism, and this file is S2's
	owed experiment — mount a vocabulary larger than the cap, leave the first batch
	outstanding, and read the NEW request set per round.

	THE FIXTURE IS THE LIVE SHAPE, NOT A MINIATURE. 1,200 distinct words at one
	(font, size) — over the cap by 176 — one `UI.Text` each, the fake target QUEUEING
	(never `answerTextInline`), and the per-round driver is the production trigger:
	edit one leaf's text to a new word, answer THAT batch alone
	(`deliverLatestTextWidths`, the boot-window asymmetry — see its header), which
	teaches the store one word, announces the (font,size), marks 1,200 paths against
	the push cap and therefore takes the WIDE-KEY `full` route: a whole-tree cold
	solve. That solve is the one whose collector is the subject.

	READ OFF THE RUN AT `7f85b15f` + the counters alone (the D2 head, mechanism
	absent), five rounds: the vocabulary this surface has ASKED ABOUT reads
	`1025, 1026, 1027, 1028, 1029` — one more word per whole-tree solve, ascending in
	document order from the mount's truncation frontier, with 171 of the 176 dropped
	words never asked about at all and nothing bounding how long that goes on. Eleven
	engine batches for six words. AFTER: `1200, 1200, 1200, 1200, 1200` — the whole
	tail rides out on the first solve that follows the mount — and six batches.

	THE MECHANISM IS "UNCHARGED", NOT "SKIPPED", AND THAT IS A DELIBERATE DEPARTURE
	from the plan's line (`(inFlight[key] or 0) == 0` as a term of the collect
	condition). An in-flight word is still COLLECTED — it simply does not spend the
	budget — because the surface that owns the flight is not the only surface that can
	need the answer. `tests/text_premeasure.spec.luau`'s "...AND SO DOES A SECOND HOST
	THAT ASKED FOR THE SAME WORD ITSELF" is a shipped fix for exactly that: two hosts
	opening cold in the same frame both ask, and the second one's re-solve is decided
	by ITS OWN in-flight set, not by the process-global store. A collector that refused
	to collect an in-flight word would leave host B with no batch, no answer and no
	re-solve — the estimator's box for the life of the session. Not charging is also
	the fail-safe direction: a refcount that ever leaked upward would only relax the
	budget, where a skip would strand a word forever.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")
local text_metrics = require("../src/layout/text_metrics")

-- over `COLLECT_CAP` (1024) by 176: the tail is the quantity every pin below is a
-- function of, and it is stated here rather than spelled into each one
local VOCAB = 1200
local CAP = 1024
local TAIL = VOCAB - CAP
local ROUNDS = 5
local SIZE = 13
--[[ a PRIVATE vocabulary, per DESCRIBE BLOCK. `layout/text_metrics` is process-global,
	so a word another spec measured is a word this fixture never asks about — and the
	batch counts here are the whole point (`text_premeasure.spec`'s own header records
	the same trap). The refcount cases below carry their own prefix for a second reason:
	a case that FAILS never reaches its `dispose`, and a surface left standing with words
	outstanding is a count the next case would inherit. ]]
local function wordAt(prefix: string, i: number): string
	return string.format("zqx%s%04d", prefix, i)
end

type World = {
	core: any,
	env: any,
	controller: any,
	adapter: any,
	texts: { any },
}

local function world(opts: { prefix: string, count: number? }): World
	local count = opts.count or VOCAB
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 480, h = 720 })
	local texts: { any } = {}
	local children: { any } = {}
	for i = 1, count do
		texts[i] = core:signal(wordAt(opts.prefix, i))
		children[i] = UI.Text({ id = `T{i}`, textSize = SIZE, text = texts[i] })
	end
	local bp = UI.Screen({
		id = "S",
		children = {
			UI.VStack({ id = "L", padding = 0, gap = 0, children = children }),
		},
	})
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter)
	controller.initialRender()
	return { core = core, env = env, controller = controller, adapter = adapter, texts = texts }
end

-- the engine's answer, deterministic and the same on every arm so the store two arms
-- converge to is byte-comparable
local function widthOf(word: string, size: number, _font: string): number?
	return math.max(1, #word * size * 0.5)
end

local function pendingSet(adapter: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, request in adapter.pendingTextRequests() do
		out[request.word] = true
	end
	return out
end

-- every live node's rect and props, the geometry channel the oracle compares
local function painted(adapter: any): string
	local out: { string } = {}
	for path, node in adapter.liveNodes() do
		local props: { string } = {}
		for k, v in node.props or {} do
			if type(v) ~= "table" then
				table.insert(props, `{k}={tostring(v)}`)
			end
		end
		table.sort(props)
		local r = node.rect
		table.insert(out, `{path}|{if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}|{table.concat(props, ",")}`)
	end
	table.sort(out)
	return table.concat(out, "\n")
end

local function dump(): string
	local out: { string } = {}
	for _, row in text_metrics.measuredDump() do
		table.insert(out, `{row.font}|{row.size}|{row.word}|{tostring(row.width)}`)
	end
	return table.concat(out, "\n")
end

-- drive to SETTLED: solve, answer everything outstanding, repeat. A drive that stops
-- early is measuring the boot window (T17 §4).
local function settle(w: World)
	for _ = 1, 12 do
		w.controller.refresh()
		if w.adapter.textBatchCount() == 0 then
			break
		end
		w.adapter.deliverTextWidths(widthOf)
	end
	w.controller.refresh()
end

describe("the collector budget: an in-flight word is not charged for it", function()
	it("THE RED ARM: a 1,200-word vocabulary, the first batch outstanding, five whole-tree solves", function()
		--[[ S2'S OWED EXPERIMENT. Every number below is read off the run, and the two
			that carry the finding are the per-round NEW request set and the size of the
			first batch a whole-tree solve dispatches once one word has been learned. ]]
		text_metrics.resetMeasured()
		--[[ THE COUNTER IS A PROCESS TOTAL, so every reading of it here is a DELTA over
			this case's own drive. Read absolutely it would carry whatever the 8,700 cases
			before this one left behind. ]]
		local base = text_metrics.collectTruncated()
		local w = world({ prefix = "w" })
		local st0 = w.controller.stats()

		-- THE CAP IS REAL, AND NOTHING SAID SO BEFORE THIS COUNTER: the mount solve
		-- asked for 1,024 of the 1,200 words it measured and dropped 176 in silence.
		local first = w.adapter.pendingTextRequests()
		expect(`batch1={#first} batches={st0.textMeasureBatches} truncated={st0.textCollectTruncated - base}`).toBe(
			"batch1=1024 batches=1 truncated=1"
		)
		-- ...in DOCUMENT ORDER, which is what makes the frontier a position and not a set
		expect(`lo={first[1].word} hi={first[#first].word}`).toBe(`lo={wordAt("w", 1)} hi={wordAt("w", CAP)}`)

		--[[ THE OBSERVABLE IS CUMULATIVE, and that is not a convenience. A round dispatches
			its batch at whichever solve first measures the word, and the fix moves that
			solve one step EARLIER (the edit's own re-solve already carries the tail, where
			the parent SHA needs the LEARNED word's solve to find one more) — so a set
			differenced across one point inside the round reports where the batch landed,
			not how much of the vocabulary the surface has asked about. `asked` is the union
			of every word ever dispatched, sampled on both sides of the answer, and the
			number that matters is how much of the 1,200-word VOCABULARY it holds. ]]
		local asked: { [string]: boolean } = {}
		local function noteAsked()
			for _, request in w.adapter.pendingTextRequests() do
				asked[request.word] = true
			end
		end
		local function vocabularyAsked(): (number, string)
			local n, hi = 0, "-"
			for word in asked do
				if string.sub(word, 1, 4) == "zqxw" then
					n += 1
					if word > hi then
						hi = word
					end
				end
			end
			return n, hi
		end
		noteAsked()
		local rounds: { string } = {}
		for round = 1, ROUNDS do
			--[[ THE PRODUCTION TRIGGER. One leaf's text becomes a NEW word, and answering
				THAT batch alone (never the outstanding one) teaches the store one word —
				which announces the (font,size), marks all 1,200 paths, blows the push cap
				and takes the wide-key `full` route: a whole-tree cold solve, which is the
				shape whose collector this file is about. ]]
			w.texts[round]:set(`zqxe{round}`)
			w.controller.refresh()
			noteAsked()
			w.adapter.deliverLatestTextWidths(widthOf)
			noteAsked()
			local n = vocabularyAsked()
			table.insert(rounds, `{n}`)
		end
		--[[ THE WALK, MECHANISED. ARM C (the counters alone, no uncharged term — read off
			the run 2026-09-06) reads `asked=1025,1026,1027,1028,1029`: ONE more word of the
			vocabulary per whole-tree solve, exactly FacetBench §8b's "744, 724, 725, 726
			…", with 171 of the 176 dropped words never asked about at all and no bound on
			how long that would go on. AFTER: the whole tail goes out on the first solve
			that follows the mount and the number stands still. ]]
		expect(`asked={table.concat(rounds, ",")}`).toBe(`asked={VOCAB},{VOCAB},{VOCAB},{VOCAB},{VOCAB}`)
		--[[ ...AND THE REST OF THE SHAPE IN ONE STRING, because these three numbers are
			only meaningful together. `hi` says the tail was taken from the mount's
			truncation FRONTIER and not from some arbitrary position; `truncated` says the
			cap is still real (the vocabulary IS bigger than the budget, so the mount still
			truncates — the fix is what happens NEXT, not that the cap stops firing);
			`batches` is the mount, the five edits, and the tail riding out with the first
			of them. ARM C: `hi=zqxw1029 truncated=7 batches=11` — a truncating solve on
			every single round, and five extra engine round trips to learn five words. ]]
		local n, hi = vocabularyAsked()
		local st = w.controller.stats()
		expect(`asked={n} hi={hi} truncated={st.textCollectTruncated - base} batches={st.textMeasureBatches}`).toBe(
			`asked={VOCAB} hi={wordAt("w", VOCAB)} truncated=1 batches=6`
		)
		w.controller.dispose()
		text_metrics.resetMeasured()
	end)

	it("...and answering both batches settles the surface: nothing pending, no deferred round", function()
		--[[ A NULL BY DESIGN, and it is here to say so. A drive that ANSWERS what it asked
			for never builds a backlog, so the settled path is the one shape the defect
			could not reach — every number below is the same on both arms, and a change in
			any of them would be this task breaking something it was not supposed to touch.
			(`drainDeferrals` is the C-3 round-cap trip: zero here, and it stays zero.) ]]
		text_metrics.resetMeasured()
		local base = text_metrics.collectTruncated()
		local w = world({ prefix = "w" })
		settle(w)
		local st = w.controller.stats()
		expect(
			`pending={tostring(w.controller.textPending())} batches={st.textMeasureBatches}`
				.. ` solves={st.solves} deferrals={st.drainDeferrals} truncated={st.textCollectTruncated - base}`
		).toBe("pending=false batches=2 solves=3 deferrals=0 truncated=1")
		-- every word of the vocabulary is in the store, which is what "settled" means
		expect(`measured={text_metrics.measuredCount()}`).toBe(`measured={VOCAB}`)
		w.controller.dispose()
		text_metrics.resetMeasured()
	end)

	it("THE ORACLE: a surface handed the whole vocabulary before mount lands the same tree", function()
		--[[ AN ORACLE THAT DOES NOT SHARE THE SWITCH (Plan D global constraint, and the
			RED-TEAM lesson of 2026-09-06). The pre-measured arm never enters `wordWidth`'s
			collect branch at all — every word is a store hit — so it exercises none of this
			task's code and is the fixed point both routes must converge to. Two channels,
			byte-equal: the painted tree and the measured store. ]]
		text_metrics.resetMeasured()
		local a = world({ prefix = "w" })
		settle(a)
		local paintedA = painted(a.adapter)
		local dumpA = dump()
		a.controller.dispose()
		text_metrics.resetMeasured()

		--[[ THE FONT IS READ OFF THE SEAM, never re-derived: the store is keyed by the
			descriptor the SOLVER measured with, and a spec that guessed one would compare
			two arms that measured different things. Arm a's dump is that reading. ]]
		local font = string.match(dumpA, "^([^|]+)|") :: string
		for i = 1, VOCAB do
			local word = wordAt("w", i)
			text_metrics.setMeasured(font, SIZE, word, widthOf(word, SIZE, font))
		end
		local b = world({ prefix = "w" })
		-- no batch at all: there was nothing the store could not answer
		expect(`batches={b.controller.stats().textMeasureBatches}`).toBe("batches=0")
		settle(b)
		expect(`painted equal: {tostring(painted(b.adapter) == paintedA)}`).toBe("painted equal: true")
		expect(`store equal: {tostring(dump() == dumpA)}`).toBe("store equal: true")
		-- ...and the channels are not empty, which is the trap a string compare invites
		expect(#paintedA > 10000 and #dumpA > 10000).toBe(true)
		b.controller.dispose()
		text_metrics.resetMeasured()
	end)
end)

describe("the collector budget: the flight refcount is what makes a process-global set safe", function()
	it("two surfaces, one word: a dispose decrements, the last answer clears, nothing is stranded", function()
		--[[ THE REFCOUNT IS THE DISPOSE-SAFETY MECHANISM. The set is process-global (the
			collector is), and the surfaces that fill it are not: a surface that dies with
			words outstanding has to give them back, and a second surface waiting on the same
			word has to keep them. A plain boolean set could do neither. ]]
		text_metrics.resetMeasured()
		local a = world({ prefix = "d", count = 3 })
		local first = a.adapter.pendingTextRequests()[1]
		local key = `{text_metrics.canonicalFont(first.font)}\0{first.size}\0{first.word}`
		expect(`one surface: {text_metrics.inFlightCount(key)}`).toBe("one surface: 1")

		--[[ THE SECOND SURFACE ASKS TOO, and that it CAN is the departure this file's
			header states: the collector does not refuse an in-flight word, it only stops
			charging the budget for it. `text_premeasure.spec`'s second-host case is the
			shipped behaviour that depends on it. ]]
		local b = world({ prefix = "d", count = 3 })
		expect(`two surfaces: {text_metrics.inFlightCount(key)}`).toBe("two surfaces: 2")
		expect(`b asked: {tostring(pendingSet(b.adapter)[first.word] == true)}`).toBe("b asked: true")

		a.controller.dispose()
		expect(`after dispose: {text_metrics.inFlightCount(key)}`).toBe("after dispose: 1")
		b.adapter.deliverTextWidths(widthOf)
		expect(`after the answer: {text_metrics.inFlightCount(key)}`).toBe("after the answer: 0")
		b.controller.dispose()
		text_metrics.resetMeasured()

		--[[ ...AND A THIRD SURFACE ASKS FOR IT AGAIN once the store has been forgotten,
			which is the property a leaked count would destroy: a word stuck in flight in a
			SKIPPING collector is a word nobody ever measures again. ]]
		local c = world({ prefix = "d", count = 3 })
		expect(`c asked: {tostring(pendingSet(c.adapter)[first.word] == true)}`).toBe("c asked: true")
		expect(`c in flight: {text_metrics.inFlightCount(key)}`).toBe("c in flight: 1")
		c.controller.dispose()
		expect(`after c's dispose: {text_metrics.inFlightCount(key)}`).toBe("after c's dispose: 0")
		text_metrics.resetMeasured()
	end)

	it("an EARLY answer keeps the word in flight, and the settled re-read releases it", function()
		--[[ THE `"answered"` STATE. A `final == false` answer is the engine's boot window
			talking: `premeasure_round` keeps the word in flight so the settled re-read is
			not refused as a duplicate request, and the refcount has to agree with that set
			or the two would disagree about what is outstanding. ]]
		text_metrics.resetMeasured()
		local w = world({ prefix = "e", count = 3 })
		local first = w.adapter.pendingTextRequests()[1]
		local key = `{text_metrics.canonicalFont(first.font)}\0{first.size}\0{first.word}`
		w.adapter.deliverTextWidths(widthOf, false)
		expect(`early answer: {text_metrics.inFlightCount(key)} pending={tostring(w.controller.textPending())}`).toBe(
			"early answer: 1 pending=true"
		)
		w.adapter.answerAgain(widthOf, true)
		expect(`settled: {text_metrics.inFlightCount(key)} pending={tostring(w.controller.textPending())}`).toBe(
			"settled: 0 pending=false"
		)
		w.controller.dispose()
		text_metrics.resetMeasured()
	end)

	it("...and an answer for a word this surface is no longer owed moves nothing at all", function()
		--[[ THE MIRROR RULE, AND ITS OWN READER. The `-1` is guarded on the per-surface set
			actually HOLDING the key, because a delivery may name a word this surface is not
			(or is no longer) waiting on: the live adapter re-answers a settled batch, and
			`answerAgain` replays exactly that. An unguarded decrement would take the count
			down for a word ANOTHER surface is still waiting on — the process count drifting
			under the per-surface sets it is supposed to mirror — and a floor at zero hides
			it rather than preventing it. Two surfaces make that visible; one cannot. ]]
		text_metrics.resetMeasured()
		local a = world({ prefix = "f", count = 3 })
		local first = a.adapter.pendingTextRequests()[1]
		local key = `{text_metrics.canonicalFont(first.font)}\0{first.size}\0{first.word}`
		local b = world({ prefix = "f", count = 3 })
		expect(`both waiting: {text_metrics.inFlightCount(key)}`).toBe("both waiting: 2")
		b.adapter.deliverTextWidths(widthOf)
		expect(`b answered: {text_metrics.inFlightCount(key)}`).toBe("b answered: 1")
		-- the SAME batch answered a second time: a is still owed its word
		b.adapter.answerAgain(widthOf)
		b.adapter.answerAgain(widthOf)
		expect(`re-answered twice: {text_metrics.inFlightCount(key)}`).toBe("re-answered twice: 1")
		a.controller.dispose()
		expect(`a gone: {text_metrics.inFlightCount(key)}`).toBe("a gone: 0")
		b.controller.dispose()
		text_metrics.resetMeasured()
	end)
end)

--[[ ── THE WORDS THE BUDGET REFUSED ARE HELD, NOT DROPPED (Plan D, D6d) ──────────

	FOUND BY D5's publish-list sweep, and measured HERE before it was built. A word
	past `COLLECT_CAP` used to be discarded: nothing measured it and nothing marked its
	owner dirty, so the only thing that ever brought the tail out was something else
	re-measuring the label for its own reasons.

	THE RED ARM, read off the run at `2c463891` (the mechanism absent, this file's
	fixture unchanged): a SETTLED 300-row surface whose body label becomes a 1,200-word
	paragraph asks for 1,024 words and drops 176, and the next FOUR solves — rows
	changing while the engine has not answered yet, which is the live boot window — ask
	for NONE of them: `asked=1024 batches=2` on every one. They come back only when the
	outstanding batch is finally answered and the correction's re-solve happens to
	re-measure that label, which costs a whole-tree measure (`lastMeasured=305` of 304
	nodes) and a SECOND answer round.

	AND THE ACCIDENT IS ONE THIS CAMPAIGN NEARLY REMOVED: D5's mount serve (built,
	refuted on its own gate, reverted at `2c463891`) made a solve serve its clean
	labels, and with that arm standing the 176 labels kept an estimated width for the
	life of the surface. The tail should not depend on an accident, which is why this is
	a correctness fix rather than a performance one — though it is both: with the queue
	the drain finishes in ONE answer round and that round measures 4 nodes, not 305.
]]
describe("the collector budget: a word the budget refused is held for the next collector", function()
	local BODY = 1200
	local BOOT_ROWS = 300

	local function bodyWord(i: number): string
		return string.format("zqxb%04d", i)
	end
	local function rowWordAt(i: number): string
		return string.format("zqxr%04d", i)
	end

	type BootWorld = {
		controller: any,
		adapter: any,
		body: any,
		rows: { any },
	}

	local function bootWorld(): BootWorld
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 480, h = 720 })
		local body = core:signal("alpha beta gamma")
		local rows: { any } = {}
		local rowChildren: { any } = {}
		for i = 1, BOOT_ROWS do
			rows[i] = core:signal(rowWordAt(i))
			-- a SECOND size, so the rows and the body do not share a (font,size) key:
			-- the row edits below must not be the thing that re-measures the body
			rowChildren[i] = UI.Text({ id = `R{i}`, textSize = 14, text = rows[i] })
		end
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "L",
					padding = 0,
					gap = 0,
					children = {
						UI.Text({ id = "P", textSize = SIZE, text = body }),
						UI.VStack({ id = "M", padding = 0, gap = 0, children = rowChildren }),
					},
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter)
		controller.initialRender()
		return { controller = controller, adapter = adapter, body = body, rows = rows }
	end

	it("THE BOOT WINDOW: a settled surface takes a 1,200-word body, and the tail goes out next solve", function()
		text_metrics.resetMeasured()
		local base = text_metrics.collectTruncated()
		local w = bootWorld()
		--[[ SETTLE FIRST, and that is the half of the shape that makes it a real test.
			A solve that follows a MOUNT re-measures the whole tree for want of anything
			to serve from, so a truncation at mount is covered by the accident this fix
			replaces; a truncation on an INCREMENTAL solve of a settled surface is not. ]]
		for _ = 1, 12 do
			w.controller.refresh()
			if w.adapter.textBatchCount() == 0 then
				break
			end
			w.adapter.deliverTextWidths(widthOf)
		end
		w.controller.refresh()
		expect(`settled={tostring(w.controller.textPending() == false)} measured={text_metrics.measuredCount()}`).toBe(
			"settled=true measured=304"
		)

		local asked: { [string]: boolean } = {}
		local function noteAsked()
			for _, request in w.adapter.pendingTextRequests() do
				asked[request.word] = true
			end
		end
		local function bodyAsked(): number
			local n = 0
			for word in asked do
				if string.sub(word, 1, 4) == "zqxb" then
					n += 1
				end
			end
			return n
		end

		local words: { string } = {}
		for i = 1, BODY do
			words[i] = bodyWord(i)
		end
		w.body:set(table.concat(words, " "))
		w.controller.refresh()
		noteAsked()
		local st1 = w.controller.stats()
		-- THE TRUNCATION, both arms: 1,024 of the 1,200 words asked about, and the
		-- counter says out loud that the collector ran out
		expect(`asked={bodyAsked()} truncated={st1.textCollectTruncated - base} batches={st1.textMeasureBatches}`).toBe(
			"asked=1024 truncated=1 batches=2"
		)

		--[[ FOUR MORE SOLVES WITH THE ENGINE STILL SILENT. The rows change (a live
			surface does not stop because a batch is outstanding), and none of those
			solves re-measures the body label — it is clean and served. ARM A reads
			`asked=1024 batches=2` on every one of them. ]]
		local rounds: { string } = {}
		for round = 1, 4 do
			w.rows[round]:set(rowWordAt(BOOT_ROWS - round))
			w.controller.refresh()
			noteAsked()
			table.insert(rounds, `{bodyAsked()}`)
		end
		expect(`asked={table.concat(rounds, ",")}`).toBe(`asked={BODY},{BODY},{BODY},{BODY}`)
		expect(`batches={w.controller.stats().textMeasureBatches}`).toBe("batches=3")

		--[[ ...AND THE ANSWER ROUND IS THEN THE LAST ONE. ARM A needs TWO: the first
			answer re-measures the whole tree (`lastMeasured=305` of 304 nodes) purely to
			re-discover the words it dropped, and dispatches them as a second batch. Here
			the store already holds every word the surface draws, so the settle re-solve
			measures the four nodes the correction actually moved. ]]
		local answers = 0
		local lastMeasured = -1
		for _ = 1, 6 do
			if w.adapter.textBatchCount() == 0 then
				break
			end
			answers += 1
			w.adapter.deliverTextWidths(widthOf)
			w.controller.refresh()
			lastMeasured = w.controller.stats().lastMeasured
		end
		expect(
			`answers={answers} lastMeasured={lastMeasured} pending={tostring(w.controller.textPending())}`
				.. ` measured={text_metrics.measuredCount()}`
		).toBe("answers=1 lastMeasured=4 pending=false measured=1504")
		w.controller.dispose()
		text_metrics.resetMeasured()
	end)

	it("...and the second collector takes what the first could not afford, charged against the same budget", function()
		--[[ THE MECHANISM ITSELF, driven through `text_metrics` alone: no surface, no
			renderer, no in-flight set. The bound is what makes the queue safe to have —
			the engine still sees at most `COLLECT_CAP` new words per frame — so it is
			asserted here rather than argued, on a vocabulary more than twice the cap. ]]
		text_metrics.resetMeasured()
		local words: { string } = {}
		for i = 1, 2300 do
			words[i] = string.format("zqxq%04d", i)
		end
		local text = table.concat(words, " ")
		text_metrics.beginCollect()
		text_metrics.measure(text, "TestSans", SIZE, math.huge)
		local first = #text_metrics.endCollect()
		--[[ ...AND THE THREE COLLECTORS THAT FOLLOW MEASURE NOTHING AT ALL, which is the
			property the whole fix turns on: the tail does not wait for anything to
			re-measure its owner. 2,300 words plus the ONE space they are joined by =
			2,301 requests, and the second collector is 1,024 and not 1,277 — the budget
			is still the bound, exactly as it is on the fresh path. Read off the run. ]]
		local empty: { number } = {}
		for _ = 1, 3 do
			text_metrics.beginCollect()
			table.insert(empty, #text_metrics.endCollect())
		end
		expect(`first={first} then={table.concat(empty, ",")}`).toBe("first=1024 then=1024,253,0")
		text_metrics.resetMeasured()
	end)

	it("...a held word the store has since learned is dropped rather than re-asked", function()
		--[[ THE QUEUE IS A REQUEST LIST, NOT A DEBT. Another surface may have asked for
			the same word and been answered while these sat here, and re-asking would
			spend this frame's budget on a word the store can already answer. The word is
			taken off the queue either way — `overflowCount` is decremented for what
			LEAVES, not for what is dispatched — so the ceiling cannot fill up with words
			nobody will ever ask about again. ]]
		text_metrics.resetMeasured()
		local words: { string } = {}
		for i = 1, 1100 do
			words[i] = string.format("zqxs%04d", i)
		end
		text_metrics.beginCollect()
		text_metrics.measure(table.concat(words, " "), "TestSans", SIZE, math.huge)
		local first = text_metrics.endCollect()
		local font = first[1].font
		-- teach the store three of the words the budget refused, exactly as an answer
		-- for another surface would
		local held: { string } = {}
		for i = 1096, 1100 do
			table.insert(held, words[i])
		end
		for i = 1, 3 do
			text_metrics.setMeasured(font, SIZE, held[i], 12)
		end
		text_metrics.beginCollect()
		local second = text_metrics.endCollect()
		local asked: { [string]: boolean } = {}
		for _, request in second do
			asked[request.word] = true
		end
		expect(
			`second={#second} learned1={tostring(asked[held[1]] == true)} unlearned={tostring(asked[held[4]] == true)}`
		).toBe("second=74 learned1=false unlearned=true")
		text_metrics.resetMeasured()
	end)

	it("RED-TEAM C-8: ...and the same thing through a solve that actually throws", function()
		--[[ THE SHAPE, not the mechanism. A settled 300-row surface takes a 1,200-word
			body, holds 176 past the budget, and then the NEXT solve throws — a row's text
			signal handed a table, which `text_metrics.measure` raises on from inside the
			solve, so `beginCollect` has run and `endCollect` has not. The recovery solve
			after it must still ask for the held tail.

			`pcall` around `refresh` is the whole point: this is what a consumer's own
			error boundary, or a Studio script erroring mid-frame, does to the collector.
			Before the fix the tail is gone and `tailAfter` reads 0. ]]
		text_metrics.resetMeasured()
		local w = bootWorld()
		for _ = 1, 12 do
			w.controller.refresh()
			if w.adapter.textBatchCount() == 0 then
				break
			end
			w.adapter.deliverTextWidths(widthOf)
		end
		w.controller.refresh()
		local words: { string } = {}
		for i = 1, BODY do
			words[i] = bodyWord(i)
		end
		w.body:set(table.concat(words, " "))
		w.controller.refresh()
		local function bodyAsked(): number
			local n = 0
			for _, request in w.adapter.pendingTextRequests() do
				if string.sub(request.word, 1, 4) == "zqxb" then
					n += 1
				end
			end
			return n
		end
		local firstRound = bodyAsked()

		-- THE THROWING SOLVE: a row's text is handed a table, which the measure raises on
		w.rows[1]:set({ notAString = true } :: any)
		local ok = pcall(function()
			w.controller.refresh()
		end)
		-- the row is put back so the recovery solve is an ordinary one
		w.rows[1]:set(rowWordAt(1))
		w.controller.refresh()
		local tailAfter = bodyAsked() - firstRound
		expect(`threw={tostring(not ok)} first={firstRound} tail={tailAfter}`).toBe(
			`threw=true first={CAP} tail={BODY - CAP}`
		)
		w.controller.dispose()
		text_metrics.resetMeasured()
	end)

	it("RED-TEAM C-8: WHICH held words leave first is the KEY ORDER, not the hash order", function()
		--[[ THE OBSERVABLE IS `pendingTextRequests()`, so the selection has to be a pure
			function of the SET rather than of the order a hash happens to enumerate in —
			the rule this campaign states at `patchIndices` and `candidateIndices` and did
			not follow here. With a held tail WIDER than the budget the loop breaks partway
			through, so before this the second batch was an arbitrary 1,024 of 1,277 and
			the third was whatever was left: two runs of the same program could disagree.

			2,300 words plus the one space that joins them = 2,301 requests. The first
			collector takes 1,024 in DOCUMENT order (the space and words 1-1,023) and holds
			1,277; the second takes the 1,024 lexicographically smallest of those, which
			for a zero-padded name is words 1,024-2,047; the third takes the remaining 253.
			Contiguous ranges are the signature of an ordered drain — a hash-ordered one
			cannot produce them. ]]
		text_metrics.resetMeasured()
		local words: { string } = {}
		for i = 1, 2300 do
			words[i] = string.format("zqxo%04d", i)
		end
		text_metrics.beginCollect()
		text_metrics.measure(table.concat(words, " "), "TestSans", SIZE, math.huge)
		local first = text_metrics.endCollect()
		local function rangeOf(batch: { any }): string
			local names: { string } = {}
			for _, request in batch do
				if request.word ~= " " then
					table.insert(names, request.word)
				end
			end
			table.sort(names)
			return if #names == 0 then "-" else `{names[1]}..{names[#names]}`
		end
		text_metrics.beginCollect()
		local second = text_metrics.endCollect()
		text_metrics.beginCollect()
		local third = text_metrics.endCollect()
		expect(`first={#first} {rangeOf(first)} | second={#second} {rangeOf(second)} | third={#third} {rangeOf(third)}`).toBe(
			"first=1024 zqxo0001..zqxo1023 | second=1024 zqxo1024..zqxo2047 | third=253 zqxo2048..zqxo2300"
		)
		text_metrics.resetMeasured()
	end)

	it("RED-TEAM C-8: a collector that never drained leaves its held words held", function()
		--[[ THE ONE HOLE IN "held, not dropped". `beginCollect` deleted the request from
			`overflow` BEFORE the batch was dispatched, so a solve that threw between
			`beginCollect` and `endCollect` lost those words from BOTH structures — the
			next `beginCollect` discards `collecting`, and nothing else remembers them.
			Held until the drain actually hands them over, the throw costs a round.

			DRIVEN THROUGH `text_metrics` ALONE here, and through a real thrown solve in
			the case below: this one is the mechanism, that one is the shape. The second
			`beginCollect` stands in for the collector the throwing solve opened and never
			closed; the third is the next solve. Before the fix `again` reads 253 and 1,024
			words are gone for the life of the process. ]]
		text_metrics.resetMeasured()
		local words: { string } = {}
		for i = 1, 2300 do
			words[i] = string.format("zqxt%04d", i)
		end
		text_metrics.beginCollect()
		text_metrics.measure(table.concat(words, " "), "TestSans", SIZE, math.huge)
		expect(`first={#text_metrics.endCollect()}`).toBe("first=1024")
		-- the collector a throwing solve opened, and never drained
		text_metrics.beginCollect()
		-- ...and the next solve's, which must find the same tail waiting
		text_metrics.beginCollect()
		local again = text_metrics.endCollect()
		local names: { string } = {}
		for _, request in again do
			if request.word ~= " " then
				table.insert(names, request.word)
			end
		end
		table.sort(names)
		expect(`again={#again} {names[1]}..{names[#names]}`).toBe("again=1024 zqxt1024..zqxt2047")
		text_metrics.resetMeasured()
	end)

	it("...and forgetting the store forgets the queue", function()
		--[[ `resetMeasured` is "this process no longer remembers anything", and a queue
			of requests for a store that remembers nothing is a queue for a different
			process — every one of those words will be asked about again by the solve that
			needs it, through the front door. ]]
		text_metrics.resetMeasured()
		local words: { string } = {}
		for i = 1, 1100 do
			words[i] = string.format("zqxu%04d", i)
		end
		text_metrics.beginCollect()
		text_metrics.measure(table.concat(words, " "), "TestSans", SIZE, math.huge)
		expect(`first={#text_metrics.endCollect()}`).toBe("first=1024")
		text_metrics.resetMeasured()
		text_metrics.beginCollect()
		expect(`after reset={#text_metrics.endCollect()}`).toBe("after reset=0")
		text_metrics.resetMeasured()
	end)
end)
