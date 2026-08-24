--!strict
--[[
	THE APP METRIC NAMESPACE (ADR-0042, framework-gaps-phase2 gap 1).

	An app's own structural numbers — a tile minimum, a chart band, a dock height
	— are not spacing steps and not control metrics, and before this round there
	was nowhere for them: `snapshot.isMetricPath` validates a name against the
	NEUTRAL snapshot, so a name no shipped package declares is a construction
	error; `themes.resolve` refuses an unknown override and an unknown
	`metrics.tenFoot` path; and the ten-foot density ladder walks a closed set of
	sections, so even a smuggled-in table would receive no distance transform.

	Four separate consumers rediscovered that independently and each wrote the
	same shim (`examples/reference/p2_cartwheel`, `p3_sipworks`, and Rascal Rally
	twice), two of them re-implementing the distance transform BY HAND — and one
	of those applied it to a single number and left three neighbours behind, so
	the ladder was half-applied inside one proof.

	This file is the contract for the channel that replaces them:

	  1. it is DECLARED once per app, under that app's own GROUP
	     (`Facet.themes.declareApp("cartwheel", …)`), and declaring is validated —
	     a name that is not a legal identifier, or a value that is not a finite
	     number, is refused rather than guessed at. The group is what lets the
	     showcase mount five proofs in one process without the second one
	     un-spelling the first one's names;
	  2. a declared name is SPELLABLE — `isMetricPath("app.proof.tileMin")` — so
	     `px = "app.proof.tileMin"` passes the same construction check
	     `px = "iconSizes.large"` passes, and an UNDECLARED `app.*` name is
	     refused exactly as `iconSizes.enormous` is;
	  3. it RESOLVES on every snapshot, whatever package is installed, so a proof
	     that must mount under Studio Neutral AND Fantasy Parchment keeps its
	     numbers;
	  4. it rides the TEN-FOOT LADDER: an app length scales by `metricScale`
	     exactly like a built-in, and an app number whose NAME says it is not a
	     length (a fraction, a count, seconds, a type size) does not — the same
	     open-section vocabulary `controls.*` already spends;
	  5. a package may MOVE a declared name (`metrics.app`) and may name one in
	     `metrics.tenFoot`, and `themes.resolve`'s `overrides` reaches it — so an
	     app number is theme-owned like every other metric, instead of being the
	     one table a theme swap cannot touch.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src")
local snapshot = require("../src/themes/snapshot") :: any
local themes = (Facet :: any).themes

--[[ THE DECLARATION IS PROCESS-WIDE, so every case restores it. `isMetricPath`
	is a STATIC check with no snapshot in scope (it runs at construction, inside
	`blueprint_schema`), which is what forces the namespace to be a declaration
	rather than a per-snapshot fact — and a spec that declared and walked away
	would leak names into every later spec file in this one Lune process. ]]
-- the first refusal a `themes.define` report carries, so a red row here names
-- what the compiler objected to rather than "expected table, got nil"
local function refusal(report: any): string
	local first = if type(report) == "table" and type(report.errors) == "table" then report.errors[1] else nil
	return if type(first) == "table" then tostring(first.message) else "?"
end

local GROUP = "proof"

local function withApp(declaration: any, body: () -> ())
	themes.declareApp(GROUP, declaration)
	local ok, err = pcall(body)
	themes.declareApp(GROUP, nil)
	if not ok then
		error(err, 0)
	end
end

local PROOF = {
	tileMin = 96,
	chartH = 160,
	sponsor = {
		rowHeight = { landscape = 56, portrait = 60 },
		-- the name says it is not a length: the open-section vocabulary
		mapFraction = { landscape = 0.52 },
		toastDurationSeconds = 2.5,
		listRowCount = 8,
		rowNameTextSize = 18,
	},
}

describe("app metrics: declaring the namespace", function()
	it("declares names under its own group, reads them back frozen, and retires them", function()
		withApp(PROOF, function()
			local declared = themes.appMetrics()
			expect(declared.proof.tileMin).toBe(96)
			expect(declared.proof.sponsor.rowHeight.landscape).toBe(56)
			expect(table.isfrozen(declared)).toBe(true)
			expect(table.isfrozen(declared.proof.sponsor)).toBe(true)
		end)
		-- retired: the group is gone and nothing else was touched
		expect(themes.appMetrics().proof).toBe(nil)
	end)

	--[[ THE REASON A GROUP EXISTS. `examples/gallery` mounts five reference
		proofs in ONE place and the picker switches between them at runtime, so a
		declaration that replaced the whole section would let the second proof's
		boot un-spell the first proof's names — and every form the picker rebuilt
		after the switch would refuse to construct. Two groups compose; neither can
		reach the other's. ]]
	it("two apps in one process compose instead of clobbering", function()
		themes.declareApp("alpha", { tileMin = 96 })
		themes.declareApp("beta", { tileMin = 200 })
		expect(snapshot.isMetricPath("app.alpha.tileMin")).toBe(true)
		expect(snapshot.isMetricPath("app.beta.tileMin")).toBe(true)
		local snap = snapshot.neutral()
		expect(snapshot.resolveNumber(snap, "app.alpha.tileMin")).toBe(96)
		expect(snapshot.resolveNumber(snap, "app.beta.tileMin")).toBe(200)
		-- retiring one leaves the other exactly where it was
		themes.declareApp("alpha", nil)
		expect(snapshot.isMetricPath("app.alpha.tileMin")).toBe(false)
		expect(snapshot.isMetricPath("app.beta.tileMin")).toBe(true)
		themes.declareApp("beta", nil)
	end)

	--[[ REFUSE, DON'T GUESS. Every one of these is a shape that would otherwise
		become a silent nil on the first solve of a themed screen. ]]
	it("refuses a name that is not a legal metric identifier", function()
		expect(pcall(themes.declareApp, GROUP, { ["tile-min"] = 96 })).toBe(false)
		expect(pcall(themes.declareApp, GROUP, { ["tile.min"] = 96 })).toBe(false)
		expect(pcall(themes.declareApp, GROUP, { ["9lives"] = 96 })).toBe(false)
		expect(pcall(themes.declareApp, GROUP, { [1] = 96 })).toBe(false)
		expect(themes.appMetrics()[GROUP]).toBe(nil)
	end)

	it("refuses a value that is not a finite number", function()
		expect(pcall(themes.declareApp, GROUP, { tileMin = "96" })).toBe(false)
		expect(pcall(themes.declareApp, GROUP, { tileMin = 0 / 0 })).toBe(false)
		expect(pcall(themes.declareApp, GROUP, { tileMin = math.huge })).toBe(false)
		expect(pcall(themes.declareApp, GROUP, { tileMin = true })).toBe(false)
	end)

	it("refuses a non-table declaration and an illegal group name", function()
		expect(pcall(themes.declareApp, GROUP, 96)).toBe(false)
		expect(pcall(themes.declareApp, GROUP, "tileMin")).toBe(false)
		expect(pcall(themes.declareApp, "not a group", { tileMin = 96 })).toBe(false)
		expect(pcall(themes.declareApp, nil, { tileMin = 96 })).toBe(false)
		expect(pcall(themes.declareApp, "proof.sub", { tileMin = 96 })).toBe(false)
	end)
end)

describe("app metrics: a declared name is spellable", function()
	it("isMetricPath accepts a declared app name and refuses an undeclared one", function()
		expect(snapshot.isMetricPath("app.proof.tileMin")).toBe(false)
		withApp(PROOF, function()
			expect(snapshot.isMetricPath("app.proof.tileMin")).toBe(true)
			expect(snapshot.isMetricPath("app.proof.sponsor.rowHeight.landscape")).toBe(true)
			-- an undeclared name is refused exactly as `iconSizes.enormous` is
			expect(snapshot.isMetricPath("app.proof.tilemin")).toBe(false)
			expect(snapshot.isMetricPath("app.proof.nope")).toBe(false)
			-- a BRANCH is not a metric: only numeric leaves resolve
			expect(snapshot.isMetricPath("app.proof.sponsor")).toBe(false)
			expect(snapshot.isMetricPath("app")).toBe(false)
		end)
		expect(snapshot.isMetricPath("app.proof.tileMin")).toBe(false)
	end)

	it("a dim may carry an app metric name, and an undeclared one is refused at construction", function()
		withApp(PROOF, function()
			local UI = (Facet :: any).UI
			local form = UI.Box({ id = "Tile", width = { type = "fixed", px = "app.proof.tileMin" } })
			expect(form ~= nil).toBe(true)
			expect(pcall(UI.Box, { id = "Bad", width = { type = "fixed", px = "app.proof.tilemin" } })).toBe(false)
		end)
	end)

	it("resolveNumber answers an app name against a live snapshot", function()
		withApp(PROOF, function()
			local snap = snapshot.neutral()
			expect(snapshot.resolveNumber(snap, "app.proof.tileMin")).toBe(96)
			expect(snapshot.resolveNumber(snap, "-app.proof.tileMin")).toBe(-96)
			expect(snapshot.resolveNumber(snap, "app.proof.nope")).toBe(nil)
		end)
	end)
end)

describe("app metrics: every package carries them", function()
	it("resolves on Studio Neutral and on a package that never heard of them", function()
		withApp(PROOF, function()
			local parchment = (require)("../examples/themes/fantasy_parchment").build(themes)
			for _, package in { snapshot.neutralPackage(), parchment } do
				local snap = snapshot.resolve(package, nil, {})
				expect(snap.app.proof.tileMin).toBe(96)
				expect(snap.app.proof.sponsor.rowHeight.portrait).toBe(60)
			end
		end)
	end)

	it("publishes the section even for a group nobody declared", function()
		local snap = snapshot.resolve(snapshot.neutralPackage(), nil, {})
		expect(type(snap.app)).toBe("table")
		-- an UNDECLARED group is absent, not empty: the section is exactly what
		-- was declared and nothing else (other specs in this process declare their
		-- own groups, which is the point of grouping)
		expect(snap.app[GROUP]).toBe(nil)
	end)

	--[[ THE ORDERING TRAP, FOUND MIGRATING `p2_cartwheel` AND CLOSED IN THE
		FRAMEWORK. A host creates the environment and may commit a theme package's
		snapshot; the APP then builds and declares its namespace. The snapshot every
		screen is measured against was therefore resolved against the previous
		vocabulary — and a metric name that resolves to nothing is a missing
		DIMENSION, not an error, so the whole proof measured zero in silence.

		`forDisplay` is the one seam every environment read passes through, and it
		refreshes a base whose declaration generation is stale. The steady state is
		still the identity. ]]
	it("a snapshot resolved BEFORE the declaration still spells the names", function()
		local stale = snapshot.resolve(snapshot.neutralPackage(), nil, {})
		expect(stale.app[GROUP]).toBe(nil)
		withApp(PROOF, function()
			local presented = snapshot.forDisplay(stale, "Medium")
			expect(presented.app.proof.tileMin).toBe(96)
			expect(snapshot.forDisplay(stale, "Large").app.proof.tileMin).toBe(144)
			-- …and a snapshot resolved AFTER it is the identity at a near display,
			-- which is the guarantee the refresh must not cost
			local fresh = snapshot.resolve(snapshot.neutralPackage(), nil, {})
			expect(rawequal(snapshot.forDisplay(fresh, "Medium"), fresh)).toBe(true)
		end)
	end)

	--[[ …AND IT LEAVES A TABLE THAT IS NOT OURS ALONE. `forDisplay` is TOTAL: it
		takes whatever the `themeMetrics` fact holds, and a fixture (or a broken
		adapter) can hand it a plain metrics-shaped table its caller still owns and
		still mutates. Refreshing that would freeze the subtables the copy shares
		with it — the caller's own data, silently immutable. Only a snapshot
		`themes.resolve` produced carries a declaration generation, and only those
		are refreshed. ]]
	it("a hand-built metrics table is passed through untouched", function()
		local handBuilt: any = { density = "near", space = { m = 12 }, targetSizes = { minimum = 44 } }
		withApp(PROOF, function()
			-- the near path is the identity it always was, and NOT because it was
			-- refreshed into a frozen copy of itself
			expect(rawequal(snapshot.forDisplay(handBuilt, "Medium"), handBuilt)).toBe(true)
			expect(table.isfrozen(handBuilt.space)).toBe(false)
			-- …and the distant form scales its leaves without freezing the original
			local far = snapshot.forDisplay(handBuilt, "Large")
			expect(far.space.m).toBe(18)
			expect(far.app).toBe(nil)
			expect(table.isfrozen(handBuilt.space)).toBe(false)
			handBuilt.space.m = 16 -- still the caller's to write
			expect(handBuilt.space.m).toBe(16)
		end)
	end)

	--[[ …AND THE REFRESH IS KEYED BY VOCABULARY, NOT MERELY BY SNAPSHOT. Found
		live in the overflow sweep, which resolves its eight package snapshots once
		at module load and then mounts five proofs against them: the first proof
		declared, a stale base was refreshed and cached, the second proof declared —
		and every read of that base got the FIRST refresh back, which had never heard
		of the second group. A cache that cannot say which vocabulary it holds is a
		stale answer with a fast path in front of it. ]]
	it("a base refreshed for one group is refreshed again for the next", function()
		local stale = snapshot.resolve(snapshot.neutralPackage(), nil, {})
		themes.declareApp("alpha", { tileMin = 96 })
		expect(snapshot.forDisplay(stale, "Medium").app.alpha.tileMin).toBe(96)
		themes.declareApp("beta", { tileMin = 200 })
		local both = snapshot.forDisplay(stale, "Medium")
		expect(both.app.alpha.tileMin).toBe(96)
		expect(both.app.beta.tileMin).toBe(200)
		themes.declareApp("alpha", nil)
		themes.declareApp("beta", nil)
	end)
end)

--[[ THE DECLARATION IS A REACTIVE FACT, and this file is where that is proved.

	`forDisplay` refreshing a stale BASE is only half the answer, and the half that
	is easy to mistake for the whole one. The environment MEMOIZES its
	`themeMetrics` read, and a memo re-runs only when a signal it `use()`d changed
	— so a declaration made after the first read invalidated nothing, the memo
	served its warm value, and `px = "app.x"` went on resolving to nil. Every
	ten-foot test in this repo MASKED it, because setting `displaySize` invalidates
	the memo for an unrelated reason and the declaration rode in on that.

	The live target was `examples/gallery`: one environment per place at boot, a
	runtime picker between five proofs, and each proof declaring its group on the
	build AFTER the environment had long since been read. ]]
describe("app metrics: a declaration reaches a warm environment", function()
	it("a group declared AFTER the first read is spellable on the next one", function()
		local core = (Facet :: any).newCore()
		local env = (Facet :: any).newEnvironment(core)
		-- WARM THE MEMO FIRST — that is the whole point of the case
		local before: any = env:get("themeMetrics"):get()
		expect(before.app.late).toBe(nil)

		themes.declareApp("late", { tileMin = 96 })
		--[[ …and NOTHING ELSE IS TOUCHED. No `displaySize`, no viewport, no theme
			commit: if the memo needs an unrelated fact to change before it will see
			the declaration, this line is the one that fails. ]]
		local after: any = env:get("themeMetrics"):get()
		expect(after.app.late.tileMin).toBe(96)
		expect(snapshot.resolveNumber(after, "app.late.tileMin")).toBe(96)

		-- a SECOND declaration on the same warm environment lands too
		themes.declareApp("later", { chartH = 160 })
		local third: any = env:get("themeMetrics"):get()
		expect(third.app.late.tileMin).toBe(96)
		expect(third.app.later.chartH).toBe(160)

		-- …and the distance transform still applies to what arrived late
		env:set("displaySize", "Large")
		expect(env:get("themeMetrics"):get().app.late.tileMin).toBe(144)

		themes.declareApp("late", nil)
		themes.declareApp("later", nil)
	end)

	--[[ RETIRING A GROUP IS A CHANGE TOO, and a warm memo has to see that one for
		the same reason: a name that is no longer declared must stop being served as
		if the process still owned it. ]]
	it("retiring a group reaches a warm environment as well", function()
		local core = (Facet :: any).newCore()
		local env = (Facet :: any).newEnvironment(core)
		themes.declareApp("transient", { tileMin = 96 })
		expect((env:get("themeMetrics"):get() :: any).app.transient.tileMin).toBe(96)
		themes.declareApp("transient", nil)
		-- the base keeps what it already published (a still-mounted screen's
		-- dimension must not vanish), but a FRESH resolve no longer carries it
		expect(snapshot.resolve(snapshot.neutralPackage(), nil, {}).app.transient).toBe(nil)
		expect(snapshot.isMetricPath("app.transient.tileMin")).toBe(false)
	end)

	--[[ A DECLARATION THAT FAILS TO PUBLISH MUST NOT STRAND THE VOCABULARY.

		`declareApp` WRITES reactive state, so calling it from inside a memo or
		effect body fails — and it fails AFTER the namespace, the generation and the
		dropped neutral memo have all been applied, but BEFORE (or part-way through)
		telling the environments. Left alone that is the silent-zero class through a
		new door, and the value-equality short-circuit makes it PERMANENT: the
		obvious retry with the same table is a no-op, so the environment stays blind
		forever while `isMetricPath` cheerfully answers true.

		Two properties close it:
		  1. a failing observer never costs a WORKING one its notification — every
		     signal is offered the generation before the first failure is reported;
		  2. the publish is SELF-HEALING — any signal whose value trails the
		     generation is caught up on the next `declareApp`, including the
		     short-circuited identical retry.

		WHAT IS *NOT* TRUE, and was claimed here until a reviewer drove the real
		path: this is not "loud". At the throw point that actually occurs — inside a
		memo — `core:memo`'s pull `pcall`s the compute, so the failure QUARANTINES
		the memo and lands on `core:lastError()`; it never reaches the author's call
		site. The direct call below raises because a direct call is not inside a
		pull. Both shapes are cases here, and the third one is the real one. ]]

	--[[ AN OBSERVER REGISTERED BY A CASE OUTLIVES THE CASE. The registry is
		process-wide, so an exploding stand-in left behind by an early `expect`
		failure makes EVERY later `declareApp` in the run fail — one genuine red
		becomes a dozen, and the genuine one is no longer the first. Protected tail,
		original error re-raised: the same shape the Rascal Rally contract spec uses
		on its presenter. ]]
	local function withObservers(observers: { any }, groups: { string }, body: () -> ())
		local unsubscribes: { () -> () } = {}
		for _, observer in observers do
			table.insert(unsubscribes, snapshot.observeAppDeclarations(observer))
		end
		local ok, err = pcall(body)
		-- THE GROUPS COME BACK IN THE PROTECTED TAIL TOO, not after it. A retire
		-- written below the body never runs when the body fails, and the next case
		-- then inherits a group it never declared — which is how the first draft of
		-- these very cases produced a second, fictional red.
		for _, unsubscribe in unsubscribes do
			pcall(unsubscribe)
		end
		for _, group in groups do
			pcall(themes.declareApp, group, nil)
		end
		if not ok then
			error(err, 0)
		end
	end

	local function explodingObserver(): any
		local observer: any = { calls = 0 }
		function observer:set()
			self.calls += 1
			error("writing state during memo evaluation", 0)
		end
		return observer
	end

	local function recordingObserver(): any
		local observer: any = { value = -1 }
		function observer:set(v: number)
			self.value = v
		end
		function observer:get(): number
			return self.value
		end
		return observer
	end

	--[[ TWO EXPLODERS, NOT ONE, AND THAT IS THE WHOLE POINT OF THE SHAPE.

		With ONE exploder and one working signal, "every signal is offered the
		generation before the first failure is reported" has a COIN-FLIP guard: the
		registry is a weak table and iterates in arbitrary order, so a
		stop-at-first-failure implementation passes whenever the exploder happens to
		sort last. Measured by a reviewer: green in 4 of 8 runs.

		With TWO, the earlier one can never be the last one — so a loop that stops at
		the first failure must always miss a call, whatever the order. The assertion
		is on the CALL COUNTS, which is the property, rather than on a downstream
		value that only sometimes reflects it. ]]
	it("every observer is offered the generation, even when an earlier one fails", function()
		local first, second, recorder = explodingObserver(), explodingObserver(), recordingObserver()
		withObservers({ first, second, recorder }, { "probe" }, function()
			pcall(themes.declareApp, "probe", { tileMin = 96 })
			-- THE PROPERTY, stated as the property: BOTH were offered it. Not a call
			-- COUNT — the sweep runs twice per changing declaration (the heal at the
			-- top and the publish at the end), and pinning that number would be
			-- asserting an implementation detail instead of the guarantee.
			expect(`both={first.calls > 0 and second.calls > 0}`).toBe("both=true")
			expect(recorder.value).toBe(snapshot.appGeneration())
		end)
	end)

	it("a DIRECT call re-raises, and the vocabulary is live either way", function()
		local core = (Facet :: any).newCore()
		local env = (Facet :: any).newEnvironment(core)
		expect((env:get("themeMetrics"):get() :: any).app.probe).toBe(nil) -- warm it

		withObservers({ explodingObserver() }, { "probe" }, function()
			-- a DIRECT call is not inside a memo pull, so this one really does raise
			expect(pcall(themes.declareApp, "probe", { tileMin = 96 })).toBe(false)
			-- …and the environment that CAN hear it still did
			expect((env:get("themeMetrics"):get() :: any).app.probe.tileMin).toBe(96)
			expect(snapshot.isMetricPath("app.probe.tileMin")).toBe(true)
			-- the retry the short-circuit would eat is still reported
			expect(pcall(themes.declareApp, "probe", { tileMin = 96 })).toBe(false)
		end)
	end)

	--[[ THE REAL THROW POINT, DRIVEN THROUGH THE REAL PATH.

		This is the shape the documentation used to describe wrongly. A `declareApp`
		made from inside a memo body does NOT reach the author: `pull` `pcall`s the
		compute, so the memo is QUARANTINED (it keeps its old value and answers
		without erroring) and the only artifact is `core:lastError()`. The
		environment that missed its notification stays blind — until any later
		`declareApp` heals it, which is what makes the mistake recoverable instead of
		terminal. ]]
	it("a declaration made inside a memo is quarantined, recorded, and healed later", function()
		-- `warns` (device bug fix round, director 2026-08-23, task-fix2 item 6):
		-- this quarantine used to be "recorded" on `lastError()` alone — an author
		-- who calls `declareApp` from the wrong place never hears about it unless
		-- they think to poll. `core/custom.luau`'s `fail()` now warns on every
		-- quarantine, real `warn()` by default; injected here for an exact assertion.
		local warns: { string } = {}
		local core = (Facet :: any).newCore({
			warn = function(message: string)
				table.insert(warns, message)
			end,
		})
		local env = (Facet :: any).newEnvironment(core)
		expect((env:get("themeMetrics"):get() :: any).app.inmemo).toBe(nil) -- warm it

		local memo = core:memo(function()
			themes.declareApp("inmemo", { tileMin = 96 })
			return "computed"
		end)
		-- the memo answers, and NOTHING is raised at the read
		local ok, value = pcall(function()
			return memo:get()
		end)
		expect(ok).toBe(true)
		expect(value).toBe(nil) -- quarantined on its first evaluation: no value was kept
		-- the ONE artifact
		expect(type(core:lastError())).toBe("string")
		expect(string.find(tostring(core:lastError()), "memo evaluation", 1, true) ~= nil).toBe(true)
		-- ...and now a SECOND artifact: the same string, said out loud once
		expect(#warns).toBe(1)
		expect(warns[1]).toBe(`Facet: quarantined - {core:lastError()}`)

		-- the vocabulary IS live — which is exactly why the environment being blind
		-- would be silent rather than obvious
		expect(snapshot.isMetricPath("app.inmemo.tileMin")).toBe(true)

		-- …and ANY later declaration heals the environment that missed it — a HEALTHY
		-- declaration, so it must not warn again
		themes.declareApp("healer", { chartH = 160 })
		expect((env:get("themeMetrics"):get() :: any).app.inmemo.tileMin).toBe(96)
		expect(#warns).toBe(1)

		memo:dispose()
		themes.declareApp("inmemo", nil)
		themes.declareApp("healer", nil)
	end)

	it("a signal whose value trails the generation is caught up by the next declaration", function()
		local trailing = recordingObserver()
		withObservers({ trailing }, { "heal" }, function()
			themes.declareApp("heal", { tileMin = 96 })
			expect(trailing.value).toBe(snapshot.appGeneration())

			-- strand it by hand, then make the IDENTICAL re-declaration the
			-- short-circuit eats — the heal has to happen before the early return
			trailing.value = -1
			themes.declareApp("heal", { tileMin = 96 })
			expect(trailing.value).toBe(snapshot.appGeneration())
		end)
	end)

	--[[ AN IDENTICAL RE-DECLARATION IS NOT A CHANGE. `installTypeRamp` and
		`ResultsParts.declareMetrics` re-declare the same table on every presenter
		build, and a generation bump per build drops the neutral memo, re-resolves
		every snapshot behind it and re-runs every `themeMetrics` memo in the
		process — churn for a value nobody moved. ]]
	it("re-declaring the same values is a no-op", function()
		local values = { tileMin = 96, group = { chartH = 160 } }
		themes.declareApp("stable", values)
		local first = snapshot.neutral()
		themes.declareApp("stable", { tileMin = 96, group = { chartH = 160 } })
		expect(rawequal(snapshot.neutral(), first)).toBe(true)
		-- …but a real change is still a change
		themes.declareApp("stable", { tileMin = 97, group = { chartH = 160 } })
		expect(rawequal(snapshot.neutral(), first)).toBe(false)
		themes.declareApp("stable", nil)
	end)
end)

describe("app metrics: the ten-foot ladder", function()
	--[[ THE HALF THE HAND-ROLLED SHIMS GOT WRONG. `p2_cartwheel` multiplied ONE
		of its four structural numbers by `metricScale` and left `chartH`, `heroH`
		and `previewMin` at their phone values, so a television measured a 96 -> 144
		tile minimum inside a 160px chart band that had not moved. A named metric
		cannot be half-applied. ]]
	it("classifies an app length as a length and scales it by the factor", function()
		withApp(PROOF, function()
			expect(snapshot.densityClassOf("app.proof.tileMin")).toBe("scale")
			expect(snapshot.densityClassOf("app.proof.sponsor.rowHeight.landscape")).toBe("scale")
			local base = snapshot.resolve(snapshot.neutralPackage(), nil, {})
			local tv = snapshot.forDisplay(base, "Large")
			expect(tv.app.proof.tileMin).toBe(96 * 1.5)
			expect(tv.app.proof.chartH).toBe(160 * 1.5)
			expect(tv.app.proof.sponsor.rowHeight.landscape).toBe(56 * 1.5)
			-- reversible, and the near display is still the identity
			expect(rawequal(snapshot.forDisplay(base, "Medium"), base)).toBe(true)
			expect(snapshot.forDisplay(tv, "Medium").app.proof.tileMin).toBe(96)
		end)
	end)

	--[[ …AND THE HALF A BLANKET RULE WOULD GET WRONG. A fraction multiplied by
		1.5 is 0.78 of a viewport, a count of 8 rows becomes 12, a 2.5 second toast
		becomes 3.75, and a type size scaled here is the 2.25x double-application
		the type floor already guards. The vocabulary is `controls.*`'s, unchanged:
		a name is a LENGTH unless one of its segments says otherwise. ]]
	it("classifies an app number whose name says it is not a length as exempt", function()
		withApp(PROOF, function()
			expect(snapshot.densityClassOf("app.proof.sponsor.mapFraction.landscape")).toBe("exempt")
			expect(snapshot.densityClassOf("app.proof.sponsor.toastDurationSeconds")).toBe("exempt")
			expect(snapshot.densityClassOf("app.proof.sponsor.listRowCount")).toBe("exempt")
			expect(snapshot.densityClassOf("app.proof.sponsor.rowNameTextSize")).toBe("exempt")
			local tv = snapshot.forDisplay(snapshot.resolve(snapshot.neutralPackage(), nil, {}), "Large")
			expect(tv.app.proof.sponsor.mapFraction.landscape).toBe(0.52)
			expect(tv.app.proof.sponsor.toastDurationSeconds).toBe(2.5)
			expect(tv.app.proof.sponsor.listRowCount).toBe(8)
			expect(tv.app.proof.sponsor.rowNameTextSize).toBe(18)
		end)
	end)
end)

describe("app metrics: a theme owns them like every other metric", function()
	it("a package may MOVE a declared app metric", function()
		withApp(PROOF, function()
			local moved, report = themes.define({
				base = themes.neutralPackage(),
				identity = { id = "app-moved", displayName = "Moved", schemaVersion = themes.SCHEMA, version = "1.0.0" },
				metrics = { app = { proof = { tileMin = 128, sponsor = { rowHeight = { landscape = 72 } } } } },
			})
			expect(moved ~= nil).toBe(true)
			if moved == nil then
				error(`themes.define refused: {refusal(report)}`)
			end
			local snap = snapshot.resolve(moved, nil, {})
			expect(snap.app.proof.tileMin).toBe(128)
			expect(snap.app.proof.sponsor.rowHeight.landscape).toBe(72)
			-- everything the package stayed silent about keeps the app's own number
			expect(snap.app.proof.chartH).toBe(160)
			expect(snap.app.proof.sponsor.rowHeight.portrait).toBe(60)
		end)
	end)

	--[[ REFUSE-DON'T-GUESS, on the package side too: a package that invents an
		app name (or misspells one) is authoring against a namespace it does not
		own, and a silent no-op there is a number that never moves and nobody can
		see not moving. ]]
	it("refuses a package that names an app metric the app never declared", function()
		withApp(PROOF, function()
			local invented = themes.define({
				base = themes.neutralPackage(),
				identity = {
					id = "app-invented",
					displayName = "Invented",
					schemaVersion = themes.SCHEMA,
					version = "1.0.0",
				},
				metrics = { app = { proof = { tilemin = 128 } } },
			})
			expect(invented ~= nil).toBe(true)
			expect(pcall(snapshot.resolve, invented, nil, {})).toBe(false)
		end)
	end)

	it("an override reaches an app metric, and an undeclared one still refuses", function()
		withApp(PROOF, function()
			local snap = snapshot.resolve(snapshot.neutralPackage(), nil, {}, { ["app.proof.tileMin"] = 111 })
			expect(snap.app.proof.tileMin).toBe(111)
			expect(pcall(snapshot.resolve, snapshot.neutralPackage(), nil, {}, { ["app.proof.nope"] = 1 })).toBe(false)
		end)
	end)

	it("metrics.tenFoot may name an app metric, and wins over the derived ladder", function()
		withApp(PROOF, function()
			local declared, report = themes.define({
				base = themes.neutralPackage(),
				identity = {
					id = "app-tenfoot",
					displayName = "TenFoot",
					schemaVersion = themes.SCHEMA,
					version = "1.0.0",
				},
				metrics = { tenFoot = { ["app.proof.tileMin"] = 200 } },
			})
			expect(declared ~= nil).toBe(true)
			if declared == nil then
				error(`themes.define refused: {refusal(report)}`)
			end
			local base = snapshot.resolve(declared, nil, {})
			expect(base.app.proof.tileMin).toBe(96)
			expect(snapshot.forDisplay(base, "Large").app.proof.tileMin).toBe(200)
		end)
	end)

	--[[ A PIXEL PACKAGE'S GRID REACHES THE APP SECTION TOO. `resolve` snaps every
		authored length onto the package's own unit so measure and paint agree on
		one coordinate system; an app length that skipped the snap would be the one
		number off the grid, and `forDisplay` snaps it at ten-foot either way — so
		the near answer would disagree with the distant one about which grid it is
		on. A non-length is left exactly where it is. ]]
	it("a pixel package snaps app lengths and leaves app non-lengths alone", function()
		withApp(PROOF, function()
			local quest = (require)("../examples/themes/pixel_quest").build(themes)
			local snap = snapshot.resolve(quest, nil, {})
			local unit = snap.pixelUnit
			expect(type(unit)).toBe("number")
			expect(snap.app.proof.tileMin % unit).toBe(0)
			expect(snap.app.proof.chartH % unit).toBe(0)
			expect(snap.app.proof.sponsor.mapFraction.landscape).toBe(0.52)
			expect(snap.app.proof.sponsor.listRowCount).toBe(8)
		end)
	end)

	--[[ …AND SO DOES A GROUP THAT ARRIVED LATE. Only the leaves the refresh ADDS
		can be off the grid — everything the base already carried was snapped when it
		was resolved — and a late one that skipped the snap would measure off a
		different coordinate system from its neighbours at near distance and back on
		it at ten-foot. A non-length is left exactly where it is: snapping a 0.52 map
		fraction onto a 4px unit is 4. ]]
	it("a group declared AFTER a pixel package resolved is snapped onto its grid too", function()
		local quest = (require)("../examples/themes/pixel_quest").build(themes)
		local stale = snapshot.resolve(quest, nil, {})
		local unit = stale.pixelUnit
		expect(type(unit)).toBe("number")
		withApp({ tileMin = 97, splitRatio = 0.52 }, function()
			local presented = snapshot.forDisplay(stale, "Medium")
			expect(presented.app.proof.tileMin % unit).toBe(0)
			expect(presented.app.proof.tileMin >= 97).toBe(true)
			-- `splitRatio`, not `ratioOfSplit`: the vocabulary is a SUFFIX check on each
			-- segment, so where the word sits in the name is the whole difference
			expect(presented.app.proof.splitRatio).toBe(0.52)
		end)
	end)
end)

describe("app metrics: the theme dump carries them", function()
	it("token_sync emits a record per declared app leaf a package authored", function()
		withApp(PROOF, function()
			local token_sync = require("../src/themes/token_sync") :: any
			local authored = themes.define({
				base = themes.neutralPackage(),
				identity = { id = "app-dump", displayName = "Dump", schemaVersion = themes.SCHEMA, version = "1.0.0" },
				metrics = { app = { proof = { tileMin = 128, sponsor = { rowHeight = { landscape = 72 } } } } },
			})
			local seen: { [string]: any } = {}
			for _, record in token_sync.records(authored) do
				seen[record.path] = record
			end
			expect(seen["app.proof.tileMin"] ~= nil).toBe(true)
			expect(seen["app.proof.tileMin"].value).toBe(128)
			expect(seen["app.proof.sponsor.rowHeight.landscape"].value).toBe(72)
			-- and the round trip: a dump reconstructs the authored section
			local rebuilt = token_sync.metricsFromRecords(token_sync.records(authored))
			expect(rebuilt.app.proof.tileMin).toBe(128)
			expect(rebuilt.app.proof.sponsor.rowHeight.landscape).toBe(72)
		end)
	end)
end)
