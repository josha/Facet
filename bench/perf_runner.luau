--!strict

local process = require("@lune/process")

local perf_runner = {}

local ENGINE = "lune 0.10.4 (Luau)"
local QUALITY = "headless (no engine render; property writes only)"
local HEADLESS_NOTE = "Headless Lune timing is trend screening only — NOT an authoritative device result (§14.3). "
	.. "deviceMeasurement is the empty slot a real on-device capture fills."

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

local DEVICE_CLASSES: { [string]: boolean } = {
	["desktop-retail"] = true,
	["phone-physical"] = true,
	["console-physical"] = true,
}
perf_runner.DEVICE_CLASSES = DEVICE_CLASSES

perf_runner.CLASS = "lune"
perf_runner.LEVEL = "E1"

local PHYSICAL_REQUIRED_METRICS = {
	{ "updateMs", "M2_updateMs" },
	{ "instances", "M3_instances" },
	{ "connections", "M4_connections" },
	{ "memoryKb", "M5_memory", "memory" },
	{ "inputToVisibleMs", "M6_inputToCommittedWrite" },
}

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

	if type(live.scalingMode) == "string" and string.find(live.scalingMode, "DeviceSimulator", 1, true) ~= nil then
		table.insert(problems, `device.live.scalingMode is a Studio simulator value: '{live.scalingMode}'`)
	end

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

local function blind(reason: string): any
	return { measured = false, reason = reason }
end
perf_runner.blind = blind

local function nowIso(): string
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

function perf_runner.runScene(scene: any, profile: any, opts: any?): any
	local warmup = (opts and opts.warmup) or scene.warmup or DEFAULT_WARMUP
	local samples = (opts and opts.samples) or scene.samples or DEFAULT_SAMPLES

	local state = scene.setup(profile)

	for _ = 1, warmup do
		scene.run(state)
		if scene.afterRun then
			scene.afterRun(state)
		end
	end

	local phaseSamples: { [string]: { number } } = { total = table.create(samples) }
	local heapSeries = table.create(samples)

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
		if scene.afterRun then
			local settleStart = os.clock()
			scene.afterRun(state)
			local bucket = phaseSamples.settle or {}
			phaseSamples.settle = bucket
			table.insert(bucket, (os.clock() - settleStart) * 1000)
		end
		heapSeries[i] = gcinfo()
	end
	local wallSeconds = os.clock() - wallStart
	local allocGrowthKb = gcinfo() - heapFloorKb

	local registrations: any = blind("Compose owns registrations; no private runtime census")
	local instances: any = blind("scene exposes no native engine boundary")
	local adapterHandlers: any = blind("native engine connection allocation requires engine capture")
	if state.engine and state.target then
		instances = #state.target:GetDescendants()
	end

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

		evidenceClass = perf_runner.CLASS,
		evidenceLevel = perf_runner.LEVEL,

		device = profile.name,
		deviceTitle = profile.title,
		viewport = table.clone(profile.viewport),
		preferredInput = profile.preferredInput,
		displaySize = profile.displaySize,
		frameTargetHz = profile.frameTargetHz,
		quality = QUALITY,

		engine = ENGINE,
		host = hostOs(),
		timestamp = nowIso(),

		warmup = warmup,
		samples = samples,
		samplingMs = wallSeconds * 1000,

		phases = phases,

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
				measured = false,
				reason = "Compose owns reactive registrations; native Engine connections require engine capture.",
				adapterHandlers = adapterHandlers,
				reactiveRegistrations = registrations,
				note = "Compose owns reactive registrations; engine connections require native capture.",
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

		allocRateKbPerSec = if wallSeconds > 0 then allocGrowthKb / wallSeconds else 0,
		heapSlopeKbPerIter = slope(heapSeries),
		liveRegistry = { registrations = registrations },
		liveConnections = registrations,
		async = async,
		extras = extras,

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

function perf_runner.run(scenes: { any }, profiles: { any }, opts: any?): any
	local runs = {}
	for _, scene in scenes do
		for _, profile in profiles do
			table.insert(runs, perf_runner.runScene(scene, profile, opts))
		end
	end

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

		evidenceClasses = classes,
		referenceProfile = nil,
		runs = runs,
	}
end

function perf_runner.ceilingMsFor(frameTargetHz: number, uiShare: number): number
	assert(frameTargetHz > 0, "frameTargetHz must be positive")
	return (1000 / frameTargetHz) * uiShare
end

function perf_runner.checkBudgets(report: any, budgets: any): any
	local ref = budgets.referenceProfile
	local violations = {}
	local skipped = {}

	local byScene: { [string]: any } = {}
	local displaced: { any } = {}
	for _, r in report.runs do
		if r.device == ref then
			if DEVICE_CLASSES[r.evidenceClass] == true then
				table.insert(displaced, { scene = r.scene, evidenceClass = r.evidenceClass })
			else
				byScene[r.scene] = r
			end
		end
	end

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
			table.insert(violations, {
				kind = "class-mismatch",
				scene = "*",
				device = className,
				requirement = budget.requirement or "UI-PERF-002",
				observedMs = -1,
				budgetMs = budget.budgetMs,

				hint = `device budget '{className}' cannot be enforced: this report contains no rows of `
					.. `that evidence class (it has {#report.runs} rows, class `
					.. `'{if report.environment ~= nil then tostring(report.environment.evidenceClass) else "unstated"}'). `
					.. `Emulator or headless data must never fill a physical row.`,
			})
		else
			for _, r in rows do
				local frameWork = r.metrics and r.metrics.frameWorkMs
				local observed = if type(frameWork) == "table" and frameWork.measured == true
					then frameWork.p95_ms
					else nil

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
