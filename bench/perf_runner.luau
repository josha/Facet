--!strict
-- Controlled performance runner (design §14.3 benchmark definition; §16.1
-- command contract; §17 Phase 4 "controlled performance runner and
-- floor-device suite"; roadmap Step 4 evidence classes and metric set).
-- Pure/engine-free: drives named scenes under a device profile, records the
-- full §14.3 field set plus the Step-4 metric ledger, and enforces versioned
-- budgets.
--
-- EVIDENCE CLASS is the load-bearing field. Every record carries exactly one
-- of `lune | studio-emulated | desktop-retail | phone-physical |
-- console-physical` and its evidence level. This runner only ever emits
-- `lune`/E1 — it structurally cannot produce any other class — and
-- `checkBudgets` REFUSES to enforce a device budget against rows that are not
-- of that device's class. That refusal is the mechanism that stops a desktop
-- headless number from becoming a phone claim; it is tested, not merely
-- documented.
--
-- Metric ledger (artifacts/cross-platform-proof/acceptance-ledger.md §0):
--   M1 real frame work ....... BLIND here (no engine frame exists)
--   M2 Facet update cost .... measured (per-phase p50/p95/p99)
--   M3 live Instances ........ measured via the adapter node census
--   M4 connections ........... measured via the adapter handler census
--                              + the reactive registry (declared stand-ins)
--   M5 memory ................ measured via gcinfo() floor/rate/slope
--   M6 input-to-visible ...... measured when the scene declares the phase;
--                              deterministic and frame-free, never display latency
--   M7 theme-swap cost ....... scene-supplied extras where the scene swaps themes
-- A metric the instrument cannot see is written as { measured = false, reason }
-- so a reader never mistakes an absent field for a zero cost.
--
-- Public interface:
--   runScene(scene, profile, opts) -> record   -- one scene under one profile
--   run(scenes, profiles, opts)    -> report    -- the full scene×profile matrix
--   ceilingMsFor(profile, budgets) -> number?   -- frame-target ceiling
--   checkBudgets(report, budgets)  -> { ok, violations, skipped }
--
-- Scene contract (see bench/perf_scenes.luau):
--   { name, requirement, dataset,
--     setup: (profile) -> state,          -- state SHOULD expose .core for the
--                                          --   live-registry snapshot and .adapter
--                                          --   for the Instance/connection census
--     run: (state) -> { [phase]: seconds }?,  -- optional per-phase sub-timings;
--                                          --   the phase named "inputToVisible" is
--                                          --   lifted into metrics.inputToVisibleMs
--     teardown: ((state) -> ())?,
--     samples: number?, warmup: number?,   -- per-scene sampling override
--     extras: ((state) -> any)?,           -- scene-specific counters (theme census…)
--     asyncStats: ((state) -> {dropped,stale,completed})? }
--
-- Depends on: @lune/process, the scene modules.

local process = require("@lune/process")

local perf_runner = {}

-- recorded build/host stamp (§14.3 engine/game build + device/OS). Lune has no
-- runtime version symbol; ENGINE names the pinned toolchain (tools/doctor.sh
-- verifies it) — update both together.
local ENGINE = "lune 0.10.4 (Luau)"
local QUALITY = "headless (no engine render; property writes only)"
local HEADLESS_NOTE = "Headless Lune timing is trend screening only — NOT an authoritative device result (§14.3). "
	.. "deviceMeasurement is the empty slot a real on-device capture fills."

-- the five evidence classes the whole system recognizes. Declared here so the
-- artifact can show a reader which classes exist and which have no rows,
-- rather than leaving absence to be inferred from silence.
perf_runner.EVIDENCE_CLASSES = {
	{
		id = "lune",
		level = "E1",
		instrument = "headless Lune on the development host",
		proves = "deterministic regressions in Facet's own decision/commit cost",
		cannotProve = "engine frame work, GPU/paint cost, or any device performance claim",
	},
	{
		id = "studio-emulated",
		level = "E3",
		instrument = "Roblox Studio Play session with a simulated device profile",
		proves = "the integrated adapter's real Instance/connection cost and frame work ON THE HOST",
		cannotProve = "low-end CPU/GPU, memory pressure, thermal or battery behavior",
	},
	{
		id = "desktop-retail",
		level = "E4",
		instrument = "retail Roblox client on the development desktop",
		proves = "non-Studio client behavior and desktop frame work",
		cannotProve = "mobile or console hardware behavior",
	},
	{
		id = "phone-physical",
		level = "E4",
		instrument = "the weakest supported physical Android device",
		proves = "the supported device floor",
		cannotProve = "console/ten-foot behavior or subjective feel",
	},
	{
		id = "console-physical",
		level = "E4",
		instrument = "the supported physical console / ten-foot path",
		proves = "gamepad delivery, overscan and console frame work",
		cannotProve = "mobile device behavior or subjective feel",
	},
}

-- the classes whose budgets describe real hardware. A budget in this set may
-- only ever be checked against records of the SAME class.
local DEVICE_CLASSES: { [string]: boolean } = {
	["desktop-retail"] = true,
	["phone-physical"] = true,
	["console-physical"] = true,
}
perf_runner.DEVICE_CLASSES = DEVICE_CLASSES

-- this runner's own class. A constant, not a parameter: there is no argument
-- a caller could pass that would make a Lune process into a phone.
perf_runner.CLASS = "lune"
perf_runner.LEVEL = "E1"

-- ===========================================================================
-- PROVENANCE: what a physical row has to CARRY, not just claim
-- ===========================================================================
--
-- Making ingestion key on the row's own class stopped a relabelled CONTAINER
-- from relabelling its contents. It did not stop a consistent relabel: a fresh
-- review ran `sed s/studio-emulated/phone-physical/g` over the real Studio
-- capture, both labels then agreed, and five host rows satisfied a measured
-- phone budget with every checker green.
--
-- That fix was a BLOCKLIST — three Studio field names a physical row must not
-- carry — and the next review defeated it by extending the same one-line sed to
-- rename those three fields too. A blocklist of names cannot survive renaming,
-- because renaming is exactly what the attack is.
--
-- So the rule is now POSITIVE. A physical row must CARRY a `provenance` block
-- that says, affirmatively, what took the measurement:
--
--   * `provenance.isStudio` — the boolean `false`, stated;
--   * `provenance.clientKind` — "retail"; a Studio session is not one;
--   * `provenance.instrument` — what ran the capture, in words;
--   * `provenance.deviceModel` — the hardware, as the device itself reports it;
--   * `provenance.capturedAt` and `provenance.attestedBy` — when, and who says so.
--
-- No rename produces those fields. `sed` can delete and it can rewrite, but it
-- cannot invent an attestation, so the cheapest path from a Studio capture to a
-- physical row is now to write one — which is forgery with a name on it, not a
-- relabel. That is the honest limit of what a gate in the same repository can
-- do, and the ledger says so rather than implying more.
--
-- The negative checks stay as a second net (they cost nothing and they catch the
-- lazy version), together with the evidentiary floor:
--
--   * `evidenceLevel = "E4"`, which is what the class inventory publishes for
--     all three physical classes. E3 is the Studio level;
--   * a real M1: `measured = true` with a finite, non-negative `p95_ms`. A
--     twelve-line hand-written file with one number is not a device row;
--   * M2..M6 present, so an absent metric cannot read as a free one;
--   * no `identity.studioVersion`, no `device.live.deviceId`, and no live-fact
--     source naming the Studio device simulator.
-- each entry lists the names the same metric goes by: the capture writes the
-- ledger's `M2_updateMs` form, the headless runner writes the plain form
local PHYSICAL_REQUIRED_METRICS = {
	{ "updateMs", "M2_updateMs" },
	{ "instances", "M3_instances" },
	{ "connections", "M4_connections" },
	{ "memoryKb", "M5_memory", "memory" },
	{ "inputToVisibleMs", "M6_inputToCommittedWrite" },
}

-- provenanceProblems(row) -> { string }; empty means the row may be ingested.
function perf_runner.provenanceProblems(row: any): { string }
	local problems = {}
	if type(row) ~= "table" then
		return { "row is not a table" }
	end
	if DEVICE_CLASSES[row.evidenceClass] ~= true then
		return problems
	end
	if row.evidenceLevel ~= "E4" then
		table.insert(
			problems,
			`evidenceLevel is {tostring(row.evidenceLevel)}; every physical class is published as E4 and E3 is the Studio level`
		)
	end
	-- THE POSITIVE HALF. Renaming a field cannot satisfy this; only writing one
	-- can, and writing one is a signed claim rather than a search-and-replace.
	local provenance = if type(row.provenance) == "table" then row.provenance else nil
	if provenance == nil then
		table.insert(
			problems,
			"carries no `provenance` block; a physical row has to say affirmatively what measured it"
		)
	else
		if provenance.isStudio ~= false then
			table.insert(problems, "provenance.isStudio must be the boolean false, stated, not absent")
		end
		if provenance.clientKind ~= "retail" then
			table.insert(problems, `provenance.clientKind is {tostring(provenance.clientKind)}; expected "retail"`)
		end
		for _, field in { "instrument", "deviceModel", "capturedAt", "attestedBy" } do
			local value = provenance[field]
			if type(value) ~= "string" or value == "" then
				table.insert(problems, `provenance.{field} is missing or empty`)
			end
		end
	end
	local identity = if type(row.identity) == "table" then row.identity else {}
	if identity.studioVersion ~= nil then
		table.insert(
			problems,
			`carries identity.studioVersion '{tostring(identity.studioVersion)}'; a retail client on real hardware has none`
		)
	end
	local device = if type(row.device) == "table" then row.device else {}
	local live = if type(device.live) == "table" then device.live else {}
	if live.deviceId ~= nil then
		table.insert(
			problems,
			`carries device.live.deviceId '{tostring(live.deviceId)}'; that is a Studio device-simulator preset id`
		)
	end
	if type(live.source) == "string" and string.find(live.source, "StudioDeviceSimulator", 1, true) ~= nil then
		table.insert(problems, `device.live.source names the Studio device simulator: '{live.source}'`)
	end
	-- the scaling mode is a Studio fingerprint too, and it was the one left
	-- unread: `Enum.DeviceSimulatorScalingMode.ActualResolution` contains the
	-- word and only the simulator produces it
	if type(live.scalingMode) == "string" and string.find(live.scalingMode, "DeviceSimulator", 1, true) ~= nil then
		table.insert(problems, `device.live.scalingMode is a Studio simulator value: '{live.scalingMode}'`)
	end
	-- AND THE ATTESTATION MUST AGREE WITH THE ROW IT SITS ON. The likeliest
	-- honest mistake the documented workflow invites is copying the Studio
	-- capture as a schema template, writing a real attestation and real numbers,
	-- and forgetting the device block underneath. A row that names two different
	-- devices is not a measurement of either.
	if
		provenance ~= nil
		and type(provenance.deviceModel) == "string"
		and provenance.deviceModel ~= ""
		and type(device.name) == "string"
		and device.name ~= ""
		and provenance.deviceModel ~= device.name
	then
		table.insert(
			problems,
			`provenance.deviceModel '{provenance.deviceModel}' disagrees with device.name '{device.name}'`
		)
	end
	local metrics = if type(row.metrics) == "table" then row.metrics else {}
	local frameWork = metrics.frameWorkMs or metrics.M1_frameWorkMs
	if type(frameWork) ~= "table" or frameWork.measured ~= true then
		table.insert(problems, "carries no MEASURED frame-work metric (M1)")
	else
		local p95 = frameWork.p95_ms
		if type(p95) ~= "number" or p95 ~= p95 or p95 < 0 then
			table.insert(problems, `M1 p95_ms is {tostring(p95)}; a device row needs a finite, non-negative number`)
		end
	end
	for _, names in PHYSICAL_REQUIRED_METRICS do
		local found = false
		for _, name in names do
			if metrics[name] ~= nil then
				found = true
				break
			end
		end
		if not found then
			table.insert(problems, `metric {names[1]} is absent; an absent metric reads as a free one`)
		end
	end
	return problems
end

local DEFAULT_WARMUP = 60
local DEFAULT_SAMPLES = 240

-- the canonical "this instrument cannot see it" value (metric ledger §0)
local function blind(reason: string): any
	return { measured = false, reason = reason }
end
perf_runner.blind = blind

local function nowIso(): string
	-- UTC ISO-8601 to the second; os.date is deterministic given the clock
	return os.date("!%Y-%m-%dT%H:%M:%SZ") :: string
end

local function hostOs(): string
	return `{process.os}/{process.arch}`
end

local function percentile(sorted: { number }, p: number): number
	if #sorted == 0 then
		return 0
	end
	local idx = math.max(1, math.ceil(p * #sorted))
	return sorted[idx]
end

-- least-squares slope of ys against x = 1..n (KB per iteration). Zero when
-- fewer than two samples or a degenerate x-variance.
local function slope(ys: { number }): number
	local n = #ys
	if n < 2 then
		return 0
	end
	local sx, sy, sxx, sxy = 0, 0, 0, 0
	for i = 1, n do
		local x = i
		sx += x
		sy += ys[i]
		sxx += x * x
		sxy += x * ys[i]
	end
	local denom = n * sxx - sx * sx
	if denom == 0 then
		return 0
	end
	return (n * sxy - sx * sy) / denom
end

-- run ONE scene under ONE profile; returns the schema-complete §14.3 + Step-4
-- record.
function perf_runner.runScene(scene: any, profile: any, opts: any?): any
	local warmup = (opts and opts.warmup) or scene.warmup or DEFAULT_WARMUP
	local samples = (opts and opts.samples) or scene.samples or DEFAULT_SAMPLES

	local state = scene.setup(profile)

	-- recorded warm-up (§14.3): run() the scene warmup times, unsampled, to
	-- settle JIT/allocation transients before measuring.
	for _ = 1, warmup do
		scene.run(state)
	end

	-- per-phase sample buckets; "total" is always measured externally around
	-- run(), scene-declared phases (measure/arrange/commit/…) come from run()'s
	-- returned map (§14.3 "p50/p95/p99 time by scheduler phase where measurable").
	local phaseSamples: { [string]: { number } } = { total = table.create(samples) }
	local heapSeries = table.create(samples) -- gcinfo() per iteration -> heap slope

	-- allocation accounting (§14.3 allocations per second): record the heap
	-- floor (gcinfo() = live KB), then measure heap growth over the sampling
	-- window. This is a proxy — the automatic GC may fire mid-window, so the
	-- rate is a lower bound, honest as a trend signal, never a hard
	-- "zero-alloc" claim (Lune's collectgarbage rejects "collect"/"count", so
	-- gcinfo() is the portable heap probe — same one bench.luau uses).
	local heapFloorKb = gcinfo()

	local wallStart = os.clock()
	for i = 1, samples do
		local t0 = os.clock()
		local phases = scene.run(state)
		local total = os.clock() - t0
		phaseSamples.total[i] = total * 1000
		if phases ~= nil then
			for name, seconds in phases do
				local bucket = phaseSamples[name]
				if bucket == nil then
					bucket = table.create(samples)
					phaseSamples[name] = bucket
				end
				table.insert(bucket, seconds * 1000)
			end
		end
		heapSeries[i] = gcinfo()
	end
	local wallSeconds = os.clock() - wallStart
	local allocGrowthKb = gcinfo() - heapFloorKb

	-- live registry counters (§14.3): the reactive graph is what Facet owns
	-- and leaks headless.
	local counters = { signals = 0, memos = 0, observers = 0, effects = 0, scopes = 0 }
	if state.core ~= nil then
		counters = state.core:counters()
	end

	-- M3/M4 (Step 4): the ADAPTER's own census. Headless these are virtual
	-- nodes and handler slots, which is exactly what the renderer asked the
	-- target to hold — the same question the ScreenTarget answers with real
	-- Instances and real connections. A scene whose state exposes no adapter
	-- records `blind` rather than 0.
	local instances: any = blind("scene exposes no adapter to census")
	local adapterHandlers: any = blind("scene exposes no adapter to census")
	if state.adapter ~= nil then
		if state.adapter.liveCount ~= nil then
			instances = state.adapter.liveCount()
		end
		if state.adapter.handlerCount ~= nil then
			adapterHandlers = state.adapter.handlerCount()
		end
	end

	-- dropped/stale async work (§14.3): zeros for scenes without async so the
	-- record SHAPE is identical across the suite (determinism §15.2).
	local async = { dropped = 0, stale = 0, completed = 0 }
	if scene.asyncStats ~= nil then
		async = scene.asyncStats(state)
	end

	local extras: any = nil
	if scene.extras ~= nil then
		extras = scene.extras(state)
	end

	if scene.teardown ~= nil then
		scene.teardown(state)
	end

	local phases: { [string]: any } = {}
	for name, bucket in phaseSamples do
		table.sort(bucket)
		phases[name] = {
			p50_ms = percentile(bucket, 0.50),
			p95_ms = percentile(bucket, 0.95),
			p99_ms = percentile(bucket, 0.99),
			samples = #bucket,
		}
	end

	-- M6: lifted from the scene-declared phase. Deterministic and frame-free —
	-- it is the cost of the semantic action → committed visible write chain,
	-- which is the part Facet owns. It is NOT display latency and the record
	-- says so.
	local inputToVisible: any
	if phases.inputToVisible ~= nil then
		inputToVisible = {
			measured = true,
			p50_ms = phases.inputToVisible.p50_ms,
			p95_ms = phases.inputToVisible.p95_ms,
			p99_ms = phases.inputToVisible.p99_ms,
			note = "action dispatch -> committed visible property write, one synchronous chain; "
				.. "no frame, no scan-out — an upper bound on Facet's share only",
		}
	else
		inputToVisible = blind("scene drives no input")
	end

	return {
		scene = scene.name,
		requirement = scene.requirement,
		dataset = scene.dataset,
		-- EVIDENCE CLASS (Step 4): the field every downstream reader keys on
		evidenceClass = perf_runner.CLASS,
		evidenceLevel = perf_runner.LEVEL,
		-- device / OS / quality (§14.3)
		device = profile.name,
		deviceTitle = profile.title,
		viewport = table.clone(profile.viewport),
		preferredInput = profile.preferredInput,
		displaySize = profile.displaySize,
		frameTargetHz = profile.frameTargetHz,
		quality = QUALITY,
		-- engine build + host + timestamp
		engine = ENGINE,
		host = hostOs(),
		timestamp = nowIso(),
		-- warm-up + sampling duration
		warmup = warmup,
		samples = samples,
		samplingMs = wallSeconds * 1000,
		-- p50/p95/p99 by scheduler phase
		phases = phases,
		-- THE STEP-4 METRIC LEDGER, one field per M-row, `blind` where the
		-- instrument cannot see
		metrics = {
			frameWorkMs = blind("headless Lune renders no frame; M1 requires an engine session"),
			updateMs = {
				measured = true,
				p50_ms = phases.total.p50_ms,
				p95_ms = phases.total.p95_ms,
				p99_ms = phases.total.p99_ms,
			},
			instances = instances,
			connections = {
				measured = true,
				adapterHandlers = adapterHandlers,
				reactiveObservers = counters.observers,
				reactiveEffects = counters.effects,
				note = "adapterHandlers is the headless stand-in for engine connections: it counts the "
					.. "handler slots Facet asked the target to hold, not engine-internal allocations",
			},
			memoryKb = {
				measured = true,
				heapFloorKb = heapFloorKb,
				allocRateKbPerSec = if wallSeconds > 0 then allocGrowthKb / wallSeconds else 0,
				heapSlopeKbPerIter = slope(heapSeries),
			},
			inputToVisibleMs = inputToVisible,
			themeSwap = if extras ~= nil and extras.themeSwap ~= nil
				then extras.themeSwap
				else blind("scene swaps no theme"),
		},
		-- legacy §14.3 fields kept at the top level so existing readers and
		-- gate greps do not break
		allocRateKbPerSec = if wallSeconds > 0 then allocGrowthKb / wallSeconds else 0,
		heapSlopeKbPerIter = slope(heapSeries),
		liveRegistry = counters,
		liveConnections = counters.observers + counters.effects,
		async = async,
		extras = extras,
		-- floor-device honesty: headless is trend-only, never authoritative;
		-- deviceMeasurement is the slot a real on-device run fills.
		deviceRun = false,
		authoritative = false,
		deviceMeasurement = {
			measured = false,
			note = "on-device capture goes here (phase/percentile numbers + build)",
			phases = nil,
		},
		note = HEADLESS_NOTE,
	}
end

-- run the full scene×profile matrix. Deterministic ORDER (scenes as given,
-- profiles as given) so the runs list has a stable shape (§15.2).
function perf_runner.run(scenes: { any }, profiles: { any }, opts: any?): any
	local runs = {}
	for _, scene in scenes do
		for _, profile in profiles do
			table.insert(runs, perf_runner.runScene(scene, profile, opts))
		end
	end
	-- which declared evidence classes actually produced rows in THIS report
	local present: { [string]: number } = {}
	for _, r in runs do
		present[r.evidenceClass] = (present[r.evidenceClass] or 0) + 1
	end
	local classes = {}
	for _, c in perf_runner.EVIDENCE_CLASSES do
		local entry = table.clone(c)
		entry.rows = present[c.id] or 0
		table.insert(classes, entry)
	end
	return {
		schema = "facet-perf/2",
		environment = {
			engine = ENGINE,
			host = hostOs(),
			quality = QUALITY,
			timestamp = nowIso(),
			evidenceClass = perf_runner.CLASS,
			evidenceLevel = perf_runner.LEVEL,
			deviceRun = false,
			authoritative = false,
			note = HEADLESS_NOTE,
		},
		-- the class inventory, INCLUDING the classes with zero rows: absence is
		-- stated, never inferred
		evidenceClasses = classes,
		referenceProfile = nil, -- set by the CLI from the budgets file
		runs = runs,
	}
end

-- The one-directional frame ceiling. The Lune host is faster than every
-- supported device, so `headless > ceiling` proves the scene cannot fit the
-- frame target ANYWHERE. The converse infers nothing, and every consumer of
-- this number is required to say so.
function perf_runner.ceilingMsFor(frameTargetHz: number, uiShare: number): number
	assert(frameTargetHz > 0, "frameTargetHz must be positive")
	return (1000 / frameTargetHz) * uiShare
end

-- enforce versioned budgets. Three independent checks:
--   1. trend budget      — reference-profile p95 against the measured baseline
--   2. frame ceiling     — reference-profile p95 against the frame-target share
--   3. device budgets    — REFUSED unless the report actually contains rows of
--                          that device class; a headless report can never
--                          satisfy (or violate) a phone budget
-- Returns { ok, violations, skipped } where each violation names scene +
-- requirement + device + observed/budget + hint (§16.1).
function perf_runner.checkBudgets(report: any, budgets: any): any
	local ref = budgets.referenceProfile
	local violations = {}
	local skipped = {}

	-- Index reference-device runs by scene — AND ONLY THIS RUNNER'S OWN CLASS.
	--
	-- The trend budgets describe the headless reference profile. Keying on
	-- `device` alone let an INGESTED row that merely named that profile take the
	-- scene's slot and be checked in the real run's place: a fresh review used it
	-- to turn a deliberately injected 8× regression from exit 1 into exit 0,
	-- while the run it displaced was still printed as OVER-TREND one line above.
	-- A device row is never the reference run, whatever it calls its device.
	local byScene: { [string]: any } = {}
	local displaced: { any } = {}
	for _, r in report.runs do
		if r.device == ref then
			-- only a DEVICE-class row can displace the reference run; a record
			-- with no class at all is a plain headless one (schema/1 fixtures)
			if DEVICE_CLASSES[r.evidenceClass] == true then
				table.insert(displaced, { scene = r.scene, evidenceClass = r.evidenceClass })
			else
				byScene[r.scene] = r
			end
		end
	end
	-- and say so: a row that TRIED to take the slot is a finding, not silence
	for _, d in displaced do
		table.insert(violations, {
			kind = "foreign-reference-row",
			scene = d.scene,
			device = ref,
			requirement = "UI-PERF-002",
			observedMs = -1,
			budgetMs = 0,
			hint = `a row of class '{tostring(d.evidenceClass)}' names the reference device '{ref}' for scene `
				.. `'{tostring(d.scene)}'. Only headless rows are the trend reference; a device row cannot stand in `
				.. `for the run it would displace.`,
		})
	end
	for scene, budget in budgets.scenes do
		local run = byScene[scene]
		if run == nil then
			table.insert(violations, {
				kind = "trend",
				scene = scene,
				device = ref,
				requirement = budget.requirement,
				observedMs = -1,
				budgetMs = budget.total_p95_ms,
				hint = `no reference-device run recorded for scene '{scene}' — is it registered in bench/perf_scenes.luau?`,
			})
		else
			local observed = run.phases.total.p95_ms
			if observed > budget.total_p95_ms then
				table.insert(violations, {
					kind = "trend",
					scene = scene,
					device = ref,
					requirement = budget.requirement,
					observedMs = observed,
					budgetMs = budget.total_p95_ms,
					hint = budget.hint,
				})
			end
			-- frame ceiling (one-directional; see ceilingMsFor)
			if budget.ceilingMs ~= nil and observed > budget.ceilingMs then
				table.insert(violations, {
					kind = "frame-ceiling",
					scene = scene,
					device = ref,
					requirement = budget.requirement,
					observedMs = observed,
					budgetMs = budget.ceilingMs,
					hint = `scene '{scene}' costs more than {budget.ceilingMs}ms — the share of a `
						.. `{budget.frameTargetHz}Hz frame Facet may occupy — on a host FASTER than every `
						.. `supported device, so it cannot hold the frame target anywhere. Fix the scene's `
						.. `hot path; re-baselining does not make this one go away.`,
				})
			end
		end
	end

	-- device budgets: only ever checked against rows of their own class
	for className, budget in (budgets.deviceBudgets or {}) do
		local rows = {}
		for _, r in report.runs do
			if r.evidenceClass == className then
				table.insert(rows, r)
			end
		end
		if budget.measured ~= true then
			table.insert(skipped, {
				class = className,
				reason = "budget declared but not yet measured on that hardware (PENDING_PHYSICAL)",
				budgetMs = budget.budgetMs,
			})
		elseif #rows == 0 then
			-- THE REFUSAL. A measured device budget with no rows of that class
			-- is not a pass — it is a report that cannot speak to the claim.
			table.insert(violations, {
				kind = "class-mismatch",
				scene = "*",
				device = className,
				requirement = budget.requirement or "UI-PERF-002",
				observedMs = -1,
				budgetMs = budget.budgetMs,
				-- `report.environment` is optional: the review packet asks a
				-- reviewer to author a capture by hand, and a hand-written report
				-- with no environment block used to make this line THROW — the
				-- refusal crashing instead of refusing.
				hint = `device budget '{className}' cannot be enforced: this report contains no rows of `
					.. `that evidence class (it has {#report.runs} rows, class `
					.. `'{if report.environment ~= nil then tostring(report.environment.evidenceClass) else "unstated"}'). `
					.. `Emulator or headless data must never fill a physical row.`,
			})
		else
			for _, r in rows do
				-- THE MEASUREMENT, not the label. A device budget is satisfied by
				-- a NUMBER; a row that merely carries the right evidence-class
				-- string is not evidence of anything.
				--
				-- Both halves of this were wrong before the fresh-context audit.
				-- (1) A `phone-physical` row with no metrics block satisfied a
				-- 0.001ms phone budget, because the loop only ever recorded a
				-- violation when a measurement existed AND exceeded it — so the
				-- class guard protected the label and nothing else. (2) The old
				-- `and`-chain yielded the BOOLEAN false when `measured == false`,
				-- so `observed ~= nil` passed and the comparison threw
				-- ("attempt to compare number < boolean") on exactly the honest
				-- case the schema uses: a device row that says it could not
				-- measure frame work.
				local frameWork = r.metrics and r.metrics.frameWorkMs
				local observed = if type(frameWork) == "table" and frameWork.measured == true
					then frameWork.p95_ms
					else nil
				-- NaN and negative are not measurements. `observed ~= observed`
				-- is the NaN test; without it a NaN sailed past `>` and a device
				-- budget passed on a number that is not a number.
				if type(observed) == "number" and (observed ~= observed or observed < 0) then
					observed = nil
				end
				if type(observed) ~= "number" then
					table.insert(violations, {
						kind = "unmeasured-device-row",
						scene = r.scene or "*",
						device = className,
						requirement = budget.requirement or "UI-PERF-002",
						observedMs = -1,
						budgetMs = budget.budgetMs,
						hint = `a row labelled '{className}' carries no usable measured frame work (absent, blind, `
							.. `negative or NaN), so it cannot satisfy `
							.. `that device's budget. A device budget is met by a NUMBER, not by an evidence-class `
							.. `string — relabelling a row has never been, and must never become, a way to pass.`,
					})
				elseif observed > budget.budgetMs then
					table.insert(violations, {
						kind = "device",
						scene = r.scene,
						device = className,
						requirement = budget.requirement or "UI-PERF-002",
						observedMs = observed,
						budgetMs = budget.budgetMs,
						hint = `scene '{r.scene}' exceeded the {className} frame budget`,
					})
				end
			end
		end
	end

	return { ok = #violations == 0, violations = violations, skipped = skipped }
end

return perf_runner
