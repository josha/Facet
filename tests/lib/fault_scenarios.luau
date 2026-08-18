--!strict
-- Phase 4 fault-injection scenarios (design §17 Phase 4). One table of named,
-- deterministic scenarios shared by tests/faults.spec.luau (small iteration
-- counts) and tools/lune/faults (scaled runs + artifact). Randomized
-- scenarios go through the seeded fuzz harness, so every failure carries a
-- replayable seed. Every scenario must leave core registries at baseline.

local customCore = require("../../src/core/custom")
local resources = require("../../src/async/resources")
local environment = require("../../src/env/environment")
local mountLib = require("../../src/mount")
local blueprintLib = require("../../src/blueprint")
local fuzz = require("./fuzz")
local fake_target = require("./fake_target")

local fault_scenarios = {}

fault_scenarios.SPEC_ITERATIONS = 40

local function newCore(): any
	return (customCore :: any).new()
end

local function assertBaseline(core: any, baseline: { [string]: number }, context: string)
	local after = core:counters()
	for key, value in baseline do
		if after[key] ~= value then
			error(`[{context}] registry '{key}' not at baseline: {after[key]} != {value}`)
		end
	end
end

-- ============================== async ================================

local function asyncFixed(_iterations: number)
	local core = newCore()
	local baseline = core:counters()
	local scope = core:scope("async-fixed")
	local provider = resources.newProvider(core, { maxConcurrent = 2, cacheBudget = 3, retryAttempts = 1 })

	-- concurrency cap: 5 distinct keys, only 2 active
	local handles = {}
	for i = 1, 5 do
		handles[i] = provider.acquire(scope, `k{i}`)
	end
	local window = provider.pendingRequests()
	assert(#window == 2, `active window must be capped at 2, got {#window}`)
	assert(provider.counters().queued == 3, "3 requests must queue")

	-- completion promotes the queue
	assert(provider.complete(window[1].key, window[1].generation, "v1") == "applied", "complete must apply")
	assert(handles[1].state:get() == "ready" and handles[1].value:get() == "v1", "handle 1 must be ready")
	assert(#provider.pendingRequests() == 2, "queue must promote into the freed slot")

	-- retry: first failure re-queues (fairly, behind waiting requests) under a
	-- NEW generation; the failed attempt's late completion is stale
	local second = provider.pendingRequests()[1]
	assert(provider.fail(second.key, second.generation, "boom") == "retrying", "first failure must retry")
	assert(handles[2].state:get() == "pending", "retrying key stays pending")
	assert(provider.complete(second.key, second.generation, "zombie") == "stale", "old generation must be stale")

	-- cancel: releasing the last pending handle makes its completion stale
	local third = provider.pendingRequests()[1]
	handles[3].release()
	assert(provider.complete(third.key, third.generation, "late") == "stale", "completion after cancel must be stale")

	-- drain everything that is NOT the retried key; the retry then reaches the
	-- active window carrying attempt=2
	local guard = 0
	while true do
		guard += 1
		assert(guard < 20, "drain loop did not converge")
		local window = provider.pendingRequests()
		local other = nil
		for _, request in window do
			if request.key ~= second.key then
				other = request
				break
			end
		end
		if other == nil then
			break
		end
		provider.complete(other.key, other.generation, other.key .. "-value")
	end
	local retried = provider.pendingRequests()[1]
	assert(retried ~= nil and retried.key == second.key, "retried request must reach the window")
	assert(retried.attempt == 2, `retry must carry attempt=2, got {retried.attempt}`)
	assert(provider.fail(retried.key, retried.generation, "boom2") == "failed", "second failure exhausts retries")
	assert(handles[2].state:get() == "failed", "handle must observe failed")
	assert(handles[2].error:get() == "boom2", "failure message must surface")

	-- failed key re-requests on demand
	local again = provider.acquire(scope, second.key)
	assert(again.state:get() == "pending", "re-acquired failed key must re-request")
	local rerequested = provider.pendingRequests()[1]
	assert(rerequested ~= nil and rerequested.key == second.key, "re-request must be in flight")
	provider.complete(rerequested.key, rerequested.generation, "finally")
	assert(again.state:get() == "ready" and again.value:get() == "finally", "re-request must complete")

	-- cache budget honored throughout (budget 3, more than 3 keys completed)
	assert(provider.counters().cached <= 3, `cache budget exceeded: {provider.counters().cached}`)

	-- retry-then-release: cancelling the ONLY waiter of a retried request must
	-- retire it (no leaked slot) and stale-reject its completion (verifier F2)
	do
		local lateScope = core:scope("retry-release")
		local h = provider.acquire(lateScope, "retry-cancel-key")
		local w = provider.pendingRequests()
		local mine = nil
		for _, request in w do
			if request.key == "retry-cancel-key" then
				mine = request
			end
		end
		assert(mine ~= nil, "retry-cancel-key must be requested")
		assert(provider.fail(mine.key, mine.generation, "flaky") == "retrying", "must retry")
		h.release()
		for _, request in provider.pendingRequests() do
			assert(request.key ~= "retry-cancel-key", "cancelled retried request still active (leaked slot)")
		end
		local retriedGen = nil
		-- the retried generation is unknowable after cancel; completing ANY
		-- recent generation for the key must be stale
		for g = mine.generation, mine.generation + 3 do
			assert(provider.complete("retry-cancel-key", g, "zombie") == "stale", `gen {g} must be stale after cancel`)
			retriedGen = g
		end
		assert(retriedGen ~= nil, "loop ran")
		lateScope:dispose()
	end

	scope:dispose()
	assert(provider.counters().handles == 0, "all handles must release with their scope")
	assertBaseline(core, baseline, "async-fixed")
	assert(core:lastError() == nil, `core error: {tostring(core:lastError())}`)
end

local function asyncStormCase(rng: any)
	local core = newCore()
	local baseline = core:counters()
	local scope = core:scope("async-storm")
	local maxConcurrent = rng:range(1, 3)
	local provider = resources.newProvider(core, {
		maxConcurrent = maxConcurrent,
		cacheBudget = rng:range(1, 4),
		retryAttempts = rng:range(0, 2),
	})
	local keys = { "a", "b", "c", "d", "e" }
	local live: { any } = {}
	for _ = 1, rng:range(5, 25) do
		local roll = rng:range(1, 100)
		if roll <= 40 then
			table.insert(live, provider.acquire(scope, rng:pick(keys)))
		elseif roll <= 60 and #live > 0 then
			local index = rng:range(1, #live)
			live[index].release()
			table.remove(live, index)
		elseif roll <= 80 then
			local window = provider.pendingRequests()
			if #window > 0 then
				local request = window[rng:range(1, #window)]
				provider.complete(request.key, request.generation, request.key)
			end
		elseif roll <= 90 then
			local window = provider.pendingRequests()
			if #window > 0 then
				local request = window[rng:range(1, #window)]
				provider.fail(request.key, request.generation, "storm")
			end
		else
			-- inject a STALE completion (random old generation)
			provider.complete(rng:pick(keys), rng:range(1, 3), "stale-garbage")
		end
		assert(#provider.pendingRequests() <= maxConcurrent, "active window exceeded maxConcurrent")
		for _, handle in live do
			local state = handle.state:get()
			assert(state == "pending" or state == "ready" or state == "failed", `illegal state {tostring(state)}`)
		end
	end
	scope:dispose()
	local counters = provider.counters()
	assert(counters.handles == 0, "handles must be zero after scope dispose")
	-- no leaked concurrency slots or queued ghosts (verifier F2)
	assert(counters.active == 0, `active slots leaked: {counters.active}`)
	assert(counters.queued == 0, `queued requests leaked: {counters.queued}`)
	assertBaseline(core, baseline, "async-storm")
	assert(core:lastError() == nil, `core error: {tostring(core:lastError())}`)
end

-- ============================= teardown ==============================

local function teardown(_iterations: number)
	local UI = blueprintLib

	-- 1) dispose with a non-empty dirty queue
	do
		local core = newCore()
		local baseline = core:counters()
		local text = core:signal("hello")
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = { UI.Text({ id = "T", text = text, textSize = 14 }) },
			})
		)
		text:set("dirty-now")
		root.dispose() -- dirty entries pending; must not throw
		assert(root.counters().mounted == 0, "mounted must be 0 after dispose")
		text:dispose()
		assertBaseline(core, baseline, "teardown-dirty")
	end

	-- 2) double disposal is DETECTED (lastError) and idempotent (no throw)
	do
		local core = newCore()
		local root = mountLib.mount(core, UI.Screen({ id = "S", children = {} }))
		root.dispose()
		root.dispose()
		local message = core:lastError()
		assert(
			message ~= nil and string.find(message, "double disposal") ~= nil,
			`double disposal must be detected, got {tostring(message)}`
		)
	end

	-- 3) an observer callback disposing the mounted root mid-notify is safe
	do
		local core = newCore()
		local flag = core:signal(false)
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.When({
						id = "W",
						condition = flag,
						thenView = function()
							return UI.Text({ id = "T", text = "on", textSize = 12 })
						end,
					}),
				},
			})
		)
		local unsubscribe = core:observe(flag, function()
			root.dispose()
		end)
		flag:set(true) -- one observer mounts/unmounts, the other disposes: no crash
		unsubscribe()
		assert(root.counters().mounted == 0, "root must be disposed")
		flag:dispose()
	end

	-- 4) a RUNTIME duplicate key is quarantined: recorded loudly, scheduler survives
	do
		local core = newCore()
		local items = core:signal({ { id = "a" }, { id = "b" } })
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.ForEach({
						id = "L",
						items = items,
						key = function(item: any)
							return item.id
						end,
						row = function(item: any)
							return UI.Text({ id = "R", text = item.id, textSize = 12 })
						end,
					}),
				},
			})
		)
		items:set({ { id = "x" }, { id = "x" } }) -- duplicate: must not crash the writer
		local message = core:lastError()
		assert(
			message ~= nil and string.find(message, "duplicate key") ~= nil,
			`runtime duplicate key must be recorded, got {tostring(message)}`
		)
		-- scheduler must still work afterwards
		local probe = core:signal(1)
		local doubled = core:memo(function(use)
			return use(probe) * 2
		end)
		probe:set(21)
		assert(doubled:get() == 42, "scheduler wedged after quarantined observer error")
		root.dispose()
		items:dispose()
		probe:dispose()
		doubled:dispose()
	end
end

-- ============================== locale ===============================

local function localeCase(rng: any)
	local LONG = {
		"Benutzerkontoverwaltungseinstellungen und Datenschutzerklärung",
		"Iñtërnâtiônàlizætiøn — ÀÇÊÑTÉD psèûdo lôcàlizâtiön expansion string",
		"日本語のとても長い設定画面のテキストサンプルです",
		"🎉🚗💨 emoji with combining marks: éé́é̂é̃",
		"مرحبا بالعالم — bidi sample",
	}
	local core = newCore()
	local env = environment.new(core) -- long-lived per client; outside the churn baseline
	local baseline = core:counters()
	local text = core:signal("hello")
	local root = mountLib.mount(
		core,
		blueprintLib.Screen({
			id = "S",
			children = { blueprintLib.Text({ id = "T", text = text, textSize = 16 }) },
		})
	)
	for step = 1, rng:range(3, 12) do
		env:set("locale", rng:pick({ "en-us", "de-de", "ja-jp", "ar-sa", "zz-zz", "" }))
		-- suffix the step so every write is a REAL change (an equal write
		-- correctly produces no dirty entry)
		text:set(rng:pick(LONG) .. " #" .. step)
		local dirty = root.takeDirty()
		local sawMeasure = false
		for _, entry in dirty do
			if entry.class == "measure" then
				sawMeasure = true
			end
		end
		assert(sawMeasure, "a text change must queue a measure dirty entry")
	end
	root.dispose()
	text:dispose()
	assertBaseline(core, baseline, "locale-storm")
	assert(core:lastError() == nil, `core error: {tostring(core:lastError())}`)
end

-- =========================== accessibility ===========================

local function accessibilityCase(rng: any)
	local core = newCore()
	local env = environment.new(core)
	local garbage = { -5, 0, 0.05, 100, 0 / 0, "big", nil, true }
	for _ = 1, rng:range(4, 12) do
		env:set("preferredTextSize", (garbage :: any)[rng:range(1, #garbage)])
		env:set("preferredTransparency", (garbage :: any)[rng:range(1, #garbage)])
		env:set("reducedMotion", rng:pick({ true, false, 1, "yes" }) :: any)
		env:set(
			"viewportRect",
			rng:pick({
				{ x = 0, y = 0, w = 375, h = 667 },
				{ x = 0, y = 0, w = 0 / 0, h = 100 },
				{ w = "wat" },
				nil,
			}) :: any
		)

		local scale = env:get("typographyScale"):get()
		assert(
			type(scale) == "number" and scale == scale and scale >= 0.5 and scale <= 3,
			`typographyScale out of legal domain: {tostring(scale)}`
		)
		local transparency = env:get("effectiveTransparency"):get()
		assert(
			type(transparency) == "number" and transparency >= 0 and transparency <= 1,
			`effectiveTransparency out of legal domain: {tostring(transparency)}`
		)
		local motion = env:get("motionPolicy"):get()
		assert(motion == "reduced" or motion == "full", `motionPolicy out of legal domain: {tostring(motion)}`)
		local sizeClass = env:get("sizeClass"):get()
		assert(
			sizeClass == "compact" or sizeClass == "regular" or sizeClass == "wide",
			`sizeClass out of legal domain: {tostring(sizeClass)}`
		)
	end
	assert(core:lastError() == nil, `core error: {tostring(core:lastError())}`)
end

-- ============================ input switch ===========================

local function inputSwitchCase(rng: any)
	local Facet = require("../../src") :: any
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local hint = core:memo(function(use)
		local preferred = use(env:get("preferredInput"))
		return if preferred == "Touch" then "Tap" else "Press"
	end)
	local screen = Facet.UI.Screen({
		id = "S",
		children = {
			Facet.UI.Text({ id = "Hint", text = hint, textSize = 14 }),
			Facet.UI.Button({ id = "A", label = "A" }),
			Facet.UI.Button({ id = "B", label = "B" }),
		},
	})
	local pres = Facet.newPresenter(core, env, adapter, system)
	local handle = pres.present(screen)
	local runsBefore = handle.root.counters().factoryRuns
	local mountedBefore = handle.root.counters().mounted

	local INPUTS = { "Touch", "Gamepad", "KeyboardAndMouse", "VRHands", "" }
	for _ = 1, rng:range(5, 40) do
		if rng:bool(0.3) then
			-- flip mid-press: hold a key across the switch, then release
			system.deviceKey("Down", true)
			env:set("preferredInput", rng:pick(INPUTS))
			pres.refresh()
			system.deviceKey("Down", false)
		else
			env:set("preferredInput", rng:pick(INPUTS))
			if rng:bool(0.5) then
				pres.refresh()
			end
		end
		assert(handle.root.counters().factoryRuns == runsBefore, "input switch caused a factory rerun")
		assert(handle.root.counters().mounted == mountedBefore, "input switch caused a remount")
	end

	-- bindings still functional after the storm
	local before = pres.focus.focused:get()
	system.deviceKey("Down", true)
	system.deviceKey("Down", false)
	local after = pres.focus.focused:get()
	assert(after ~= nil, "focus lost after input-switch storm")
	assert(before ~= nil, "focus was never established")
	pres.dismiss(handle)
	assert(core:lastError() == nil, `core error: {tostring(core:lastError())}`)
end

-- ===================== core callback fault paths =====================

-- verifier F1/F4/F5: user-supplied equality callbacks that THROW must
-- quarantine (lastError), never unwind the flush loop (wedged flushing flag)
-- or escape a plain set(); disposing a node with live observers reclaims
-- their registry slots and silences them.
local function coreEqQuarantine(_iterations: number)
	-- 1) throwing eq on an OBSERVED memo: no raise, lastError set, scheduler alive
	do
		local core = newCore()
		local source = core:signal(1)
		local cursed = core:memo(function(use)
			return use(source)
		end, function()
			error("eq boom")
		end)
		local fired = 0
		local unsubscribe = core:observe(cursed, function()
			fired += 1
		end)
		local ok = pcall(function()
			source:set(2)
		end)
		assert(ok, "a throwing eq must not unwind the writer")
		assert(core:lastError() ~= nil, "a throwing eq must record lastError")
		-- the flush loop must NOT be wedged: an unrelated pair still fires
		local other = core:signal(0)
		local otherFired = 0
		local unsubscribeOther = core:observe(other, function()
			otherFired += 1
		end)
		other:set(7)
		assert(otherFired == 1, "flush loop wedged after a throwing eq (verifier F1)")
		unsubscribe()
		unsubscribeOther()
	end

	-- 2) throwing eq on a plain signal set(): no raise, quarantined
	do
		local core = newCore()
		local cursed = core:signal(1, function()
			error("eq boom on write")
		end)
		local ok = pcall(function()
			cursed:set(2)
		end)
		assert(ok, "a throwing signal eq must not unwind set() (verifier F4)")
		assert(core:lastError() ~= nil, "signal eq error must record lastError")
	end

	-- 3) disposing a node with LIVE observers reclaims their counters and
	-- silences them (verifier F5/F6)
	do
		local core = newCore()
		local baseline = core:counters()
		local source = core:signal(1)
		local fired = 0
		local unsubscribe = core:observe(source, function()
			fired += 1
		end)
		source:dispose()
		assert(
			core:counters().observers == baseline.observers,
			`observer registry leaked on node dispose: {core:counters().observers}`
		)
		unsubscribe() -- must be a safe no-op, not a double decrement
		assert(core:counters().observers == baseline.observers, "unsubscribe after node dispose double-decremented")
		assert(core:counters().signals == baseline.signals, "signal registry off after dispose")
		assert(fired == 0, "disposed node's observer fired")
	end
end

-- verifier F7: lock the healthy feedback paths with explicit coverage —
-- effect writes land next round and converge; a true feedback loop hits the
-- round cap, records lastError, and the scheduler stays functional
local function schedulerFeedback(_iterations: number)
	do
		local core = newCore()
		local source = core:signal(1)
		local sink = core:signal(0)
		local dispose = core:effect(function(use)
			sink:set(use(source) * 10)
		end)
		source:set(3)
		assert(sink:get() == 30, `effect write must converge next round, got {sink:get()}`)
		assert(core:lastError() == nil, "legal effect write recorded an error")
		dispose()
	end
	do
		local core = newCore()
		local ouro = core:signal(0)
		local dispose = core:effect(function(use)
			ouro:set(use(ouro) + 1) -- self-feeding loop
		end)
		assert(
			core:lastError() ~= nil and string.find(core:lastError() :: string, "cap") ~= nil,
			`feedback loop must hit the round cap, got {tostring(core:lastError())}`
		)
		dispose()
		-- scheduler alive afterwards
		local probe = core:signal(1)
		local seen = 0
		local unsubscribe = core:observe(probe, function()
			seen += 1
		end)
		probe:set(2)
		assert(seen == 1, "scheduler dead after feedback cap")
		unsubscribe()
	end
end

-- verifier F3: dismissing a NON-top presented screen must remove ITS focus
-- scope, leaving the top scope (the modal) active and reachable
local function presenterDismissNonTop(_iterations: number)
	local Facet = require("../../src") :: any
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local base = pres.present(Facet.UI.Screen({
		id = "Base",
		children = { Facet.UI.Button({ id = "A", label = "A" }), Facet.UI.Button({ id = "B", label = "B" }) },
	}))
	local modal = pres.presentModal(Facet.UI.Screen({
		id = "Modal",
		children = { Facet.UI.Button({ id = "Ok", label = "Ok" }), Facet.UI.Button({ id = "No", label = "No" }) },
	}))
	assert(pres.focus.focused:get() == "/Modal/Ok", "modal must own focus")
	pres.dismiss(base)
	assert(pres.depth() == 1, "base must be gone")
	assert(
		pres.focus.activeScopeName() == "Modal",
		`active scope must stay the modal, got {tostring(pres.focus.activeScopeName())}`
	)
	assert(
		pres.focus.focused:get() == "/Modal/Ok",
		`focus must stay on the live modal, got {tostring(pres.focus.focused:get())}`
	)
	system.deviceKey("Down", true)
	system.deviceKey("Down", false)
	assert(pres.focus.focused:get() == "/Modal/No", "navigation must move within the modal")
	pres.dismiss(modal)
	assert(pres.depth() == 0, "all screens dismissed")
	assert(core:lastError() == nil, `core error: {tostring(core:lastError())}`)
end

-- ============================== table ================================

fault_scenarios.list = {
	{
		name = "async-fixed",
		summary = "cap, retry generations, stale rejection, cancel, cache budget, failed re-request",
		requirements = { "UI-LIFE-001", "UI-LIFE-002" },
		run = function(_iterations: number)
			asyncFixed(1)
		end,
	},
	{
		name = "async-storm",
		summary = "seeded acquire/release/complete/fail/stale storms stay legal and registry-neutral",
		requirements = { "UI-LIFE-001", "UI-LIFE-002" },
		run = function(iterations: number)
			local report =
				fuzz.run({ name = "async-storm", baseSeed = 611001, cases = iterations, case = asyncStormCase })
			if #report.failures > 0 then
				error(`async-storm seed={report.failures[1].seed}: {report.failures[1].error}`)
			end
		end,
	},
	{
		name = "core-eq-quarantine",
		summary = "throwing user eq callbacks quarantine (no wedged flush, no raised set); node dispose reclaims live observers",
		requirements = { "UI-RUNTIME-003", "UI-LIFE-002" },
		run = coreEqQuarantine,
	},
	{
		name = "scheduler-feedback",
		summary = "effect writes converge next round; true feedback loops hit the cap loudly and the scheduler survives",
		requirements = { "UI-RUNTIME-003" },
		run = schedulerFeedback,
	},
	{
		name = "presenter-dismiss-non-top",
		summary = "dismissing a covered screen removes ITS focus scope; the modal stays active and navigable",
		requirements = { "UI-FOCUS-001" },
		run = presenterDismissNonTop,
	},
	{
		name = "teardown",
		summary = "dirty-queue dispose, detected double disposal, dispose-from-observer, quarantined runtime duplicate key",
		requirements = { "UI-LIFE-001", "UI-RUNTIME-003" },
		run = teardown,
	},
	{
		name = "locale",
		summary = "locale/text storms (pseudo-loc, CJK, emoji, bidi) queue measure dirties and stay registry-neutral",
		requirements = { "UI-ENV-001" },
		run = function(iterations: number)
			local report = fuzz.run({ name = "locale", baseSeed = 733210, cases = iterations, case = localeCase })
			if #report.failures > 0 then
				error(`locale seed={report.failures[1].seed}: {report.failures[1].error}`)
			end
		end,
	},
	{
		name = "accessibility",
		summary = "garbage platform facts clamp into legal derived domains (typography/transparency/motion/sizeClass)",
		requirements = { "UI-ENV-001" },
		run = function(iterations: number)
			local report =
				fuzz.run({ name = "accessibility", baseSeed = 845101, cases = iterations, case = accessibilityCase })
			if #report.failures > 0 then
				error(`accessibility seed={report.failures[1].seed}: {report.failures[1].error}`)
			end
		end,
	},
	{
		name = "input-switch",
		summary = "preferred-input storms (incl. mid-press and unknown values) never remount; bindings survive",
		requirements = { "UI-INPUT-002" },
		run = function(iterations: number)
			local report =
				fuzz.run({ name = "input-switch", baseSeed = 917359, cases = iterations, case = inputSwitchCase })
			if #report.failures > 0 then
				error(`input-switch seed={report.failures[1].seed}: {report.failures[1].error}`)
			end
		end,
	},
}

return fault_scenarios
