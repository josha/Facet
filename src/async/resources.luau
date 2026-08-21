--!strict
-- Async resource provider (design §10.3): ready/pending/failed state over the
-- core contract with bounded concurrency, cache key + cache budget (LRU),
-- owner cancellation (scope-owned handles), request generation/identity,
-- retry policy, stale-completion rejection, and placeholder/failure state the
-- renderer can bind. Engine-free and non-yielding: the TRANSPORT is game- or
-- adapter-owned. It drains provider.pendingRequests() (the active window, capped
-- at maxConcurrent) and answers with provider.complete/fail(key, generation, ..).
-- A completion whose generation does not match the CURRENT request for that
-- key is stale and is rejected ("stale"), never applied — cancelled or
-- superseded requests cannot resurrect (§10.3, §15.1 async stale completion).

local specGuard = require("../spec_guard")

local profile = require("../core/profile")
local num = require("../num")

local resources = {}

type Wave = { count: number } -- live waiters across a request AND its retries
type Request = {
	key: string,
	generation: number,
	attempt: number, -- 1-based; retries increment
	active: boolean, -- inside the concurrency window (visible to transport)
	wave: Wave, -- shared across retries so cancellation survives a retry
	-- (a retry swaps the request OBJECT; waiter accounting must not reset —
	-- phase-4 verifier F2)
	retry: Retry, -- the policy this key is being fetched under
	dueAt: number?, -- a spaced retry waits here, out of the transport's sight
}

-- BOUNDED RETRY (ADR-0022 Decision 8). `count` extra attempts after the
-- first failure, spaced by `delaySeconds` of INJECTED time — the provider is pure
-- and non-yielding, so a delay is a due time the caller's `tick` crosses, never a
-- `task.delay`. `giveUp` is what makes the retry BOUNDED: when the budget is spent
-- the key is failed for the session and no later `acquire` starts it again.
export type Retry = {
	count: number,
	delaySeconds: number,
	giveUp: boolean,
}

export type RetryOpts = {
	count: number?,
	delaySeconds: number?,
	giveUp: boolean?,
}

export type ProviderOpts = {
	maxConcurrent: number?, -- default 4
	cacheBudget: number?, -- max cached values, LRU (default 16)
	-- the LEGACY spelling: N immediate extra attempts, and a failed key still
	-- re-requests whenever it is acquired again. Kept exactly as it was.
	retryAttempts: number?,
	-- the SF-A2 contract: bounded retry, spaced, then a permanent give-up. A
	-- declared `retry` is what buys the give-up — the point of a bounded retry is
	-- that it ends, and the legacy option promised no such thing.
	retry: RetryOpts?,
	now: (() -> number)?, -- injected clock for spaced retries (default os.clock)
}

local isFinite = num.isFinite

local function resolveRetry(spec: any, fallback: Retry?): Retry
	local base: Retry = fallback or { count = 0, delaySeconds = 0, giveUp = false }
	if type(spec) ~= "table" then
		return base
	end
	return {
		count = if isFinite(spec.count) and spec.count >= 0 then math.floor(spec.count) else base.count,
		delaySeconds = if isFinite(spec.delaySeconds) and spec.delaySeconds >= 0
			then spec.delaySeconds
			else base.delaySeconds,
		giveUp = if type(spec.giveUp) == "boolean" then spec.giveUp else true,
	}
end

-- CONSTRUCTION-STRICT (F-12), like `valueModel.new` four files away in the same
-- public surface. `maxConcurrent = 0` is truthy in Lua, so it used to be accepted
-- and then `promote()` could never activate anything: every request queued
-- silently forever and the UI simply never loaded, with no diagnostic anywhere —
-- not even `core:lastError()`. An impossible option is a typo, and a typo is
-- worth an error at the one moment the author is looking at the call site.
local function requireIntegerAtLeast(value: any, minimum: number, name: string)
	if value == nil then
		return
	end
	if not isFinite(value) or math.floor(value) ~= value or value < minimum then
		error(`Facet resource provider: {name} must be an integer >= {minimum} (got {tostring(value)})`, 0)
	end
end

local function requireNonNegativeNumber(value: any, name: string)
	if value == nil then
		return
	end
	if not isFinite(value) or value < 0 then
		error(`Facet resource provider: {name} must be a non-negative number (got {tostring(value)})`, 0)
	end
end

-- CLOSED OPTS (constitution §4). A misspelled `maxConcurent` used to cap
-- nothing and a misspelled `retry` bought no give-up, both silently.
local PROVIDER_OPTS_KEYS = specGuard.keySet({ "cacheBudget", "maxConcurrent", "now", "retry", "retryAttempts" })
local RETRY_OPTS_KEYS = specGuard.keySet({ "count", "delaySeconds", "giveUp" })
-- the per-call tables of `acquire`/`preload`: one key each, which is exactly why
-- a typo in it was invisible
local CALL_OPTS_KEYS = specGuard.keySet({ "retry" })

function resources.newProvider(core: any, opts: ProviderOpts?)
	specGuard.assertKnownKeys("newResourceProvider", opts, PROVIDER_OPTS_KEYS, "opts")
	if opts ~= nil then
		specGuard.assertKnownKeys("newResourceProvider opts.retry", opts.retry, RETRY_OPTS_KEYS, "opts")
	end
	requireIntegerAtLeast(opts and opts.maxConcurrent, 1, "maxConcurrent")
	requireIntegerAtLeast(opts and opts.cacheBudget, 0, "cacheBudget")
	if opts ~= nil and type(opts.retry) == "table" then
		local declared = opts.retry :: RetryOpts
		requireNonNegativeNumber(declared.count, "retry.count")
		requireNonNegativeNumber(declared.delaySeconds, "retry.delaySeconds")
	end
	local maxConcurrent = (opts and opts.maxConcurrent) or 4
	local cacheBudget = (opts and opts.cacheBudget) or 16
	local now = (opts and opts.now) or os.clock
	local defaultRetry: Retry = resolveRetry(opts and opts.retry, {
		count = (opts and opts.retryAttempts) or 0,
		delaySeconds = 0,
		giveUp = false,
	})
	-- keys that spent their retry budget: failed for the session, and an acquire
	-- must not quietly start them over (SF-A2's "permanent-for-session give-up").
	-- `invalidate(key)` is the explicit reset.
	local gaveUp: { [string]: any } = {}
	local waiting: { Request } = {} -- spaced retries, waiting for their due time

	local generationCounter = 0
	local requests: { [string]: Request } = {} -- current request per key
	local queue: { Request } = {} -- waiting for a concurrency slot
	local activeCount = 0
	local cache: { [string]: any } = {}
	local cacheOrder: { string } = {} -- LRU, oldest first
	local counters = { handles = 0, active = 0, queued = 0, cached = 0, staleRejected = 0, dropped = 0 }
	-- per-key state signals shared by all handles on that key
	local keyState: { [string]: { state: any, value: any, error: any, refs: number } } = {}

	local provider = {}
	local disposed = false

	local function syncCounters()
		counters.active = activeCount
		counters.queued = #queue
		local cached = 0
		for _ in cache do
			cached += 1
		end
		counters.cached = cached
	end

	local function touchLru(key: string)
		for i, k in cacheOrder do
			if k == key then
				table.remove(cacheOrder, i)
				break
			end
		end
		table.insert(cacheOrder, key)
	end

	local function evictOverBudget()
		while #cacheOrder > cacheBudget do
			local oldest = table.remove(cacheOrder, 1) :: string
			cache[oldest] = nil
		end
	end

	local function promote()
		while activeCount < maxConcurrent and #queue > 0 do
			local request = table.remove(queue, 1) :: Request
			if requests[request.key] == request then
				request.active = true
				activeCount += 1
			end
		end
	end

	local function stateFor(key: string)
		local existing = keyState[key]
		if existing then
			existing.refs += 1
			return existing
		end
		local entry = {
			-- a key that spent its retry budget opens FAILED, with the message that
			-- ended it: the give-up is a state a late acquirer inherits, not a fact
			-- only the original waiter was told
			state = core:signal(
				if cache[key] ~= nil then "ready" elseif gaveUp[key] ~= nil then "failed" else "pending"
			),
			value = core:signal(cache[key]),
			error = core:signal(gaveUp[key]),
			refs = 1,
		}
		keyState[key] = entry
		return entry
	end

	local function releaseState(key: string)
		local entry = keyState[key]
		if entry == nil then
			return
		end
		entry.refs -= 1
		if entry.refs <= 0 then
			entry.state:dispose()
			entry.value:dispose()
			entry.error:dispose()
			keyState[key] = nil
		end
	end

	local function beginRequest(key: string, retry: Retry?)
		generationCounter += 1
		local request: Request = {
			key = key,
			generation = generationCounter,
			attempt = 1,
			active = false,
			wave = { count = 0 },
			retry = retry or defaultRetry,
		}
		requests[key] = request
		table.insert(queue, request)
		promote()
		return request
	end

	local function retireRequest(request: Request)
		if requests[request.key] == request then
			requests[request.key] = nil
		end
		if request.active then
			request.active = false
			activeCount -= 1
		else
			for i, queued in queue do
				if queued == request then
					table.remove(queue, i)
					break
				end
			end
			-- a spaced retry that never reached the queue is cancelled here too:
			-- releasing the last waiter must stop work that has not started
			for i, held in waiting do
				if held == request then
					table.remove(waiting, i)
					break
				end
			end
		end
		promote()
	end

	-- acquire(scope, key) -> handle. The handle is scope-owned: disposing the
	-- scope releases it; releasing the LAST handle of a pending request
	-- cancels the request (its generation becomes stale).
	-- acquire(scope, key, opts?) -> handle. The handle is scope-owned: disposing the
	-- scope releases it; releasing the LAST handle of a pending request cancels the
	-- request (its generation becomes stale). `opts.retry` overrides the provider's
	-- policy FOR THIS KEY (RL-19: the mechanism is the framework's, the counts and
	-- the spacing are the call site's).
	function provider.acquire(scope: any, key: string, acquireOpts: { retry: RetryOpts? }?)
		specGuard.assertKnownKeys("provider.acquire", acquireOpts, CALL_OPTS_KEYS, "opts")
		--[[ A DISPOSED SESSION DOES NOT RESURRECT (see `provider.dispose`). The
			handle is a real one so the caller's binding still reads a value rather
			than nil-indexing, and it opens FAILED, which is the honest state: this
			key will never fill, and that is what the placeholder should say. ]]
		if disposed then
			return {
				state = core:signal("failed"),
				value = core:signal(nil),
				error = core:signal("resource provider disposed"),
				release = function() end,
			}
		end
		if acquireOpts ~= nil then
			specGuard.assertKnownKeys("provider.acquire opts.retry", acquireOpts.retry, RETRY_OPTS_KEYS, "opts")
		end
		counters.handles += 1
		local entry = stateFor(key)
		local wave: Wave? = nil
		local retry = if acquireOpts ~= nil and acquireOpts.retry ~= nil
			then resolveRetry(acquireOpts.retry, defaultRetry)
			else defaultRetry
		if cache[key] ~= nil then
			touchLru(key)
		elseif gaveUp[key] ~= nil then
			-- PERMANENT FOR THE SESSION (per call site): no request, no wave, no work. The
			-- state signal already reads "failed"; `invalidate(key)` is the reset.
		else
			local request = requests[key]
			if request == nil then
				request = beginRequest(key, retry)
				-- a key that previously failed re-requests on demand
				if entry.state:get() ~= "pending" then
					core:transaction(function()
						entry.error:set(nil)
						entry.state:set("pending")
					end)
				end
			end
			wave = (request :: Request).wave;
			(wave :: Wave).count += 1
		end

		local released = false
		local handle = {
			key = key,
			state = entry.state,
			value = entry.value,
			error = entry.error,
		}
		function handle.release()
			if released then
				return
			end
			released = true
			counters.handles -= 1
			if wave ~= nil then
				wave.count -= 1
				local current = requests[key]
				-- cancel against the CURRENT request for the key, but only if
				-- it still belongs to this handle's wave (a retry keeps the
				-- wave; an unrelated later request does not — verifier F2)
				if current ~= nil and current.wave == wave and wave.count <= 0 then
					counters.dropped += 1
					retireRequest(current)
				end
			end
			releaseState(key)
			syncCounters()
		end
		scope:own(handle.release)
		syncCounters()
		return handle
	end

	-- transport window: the active requests (<= maxConcurrent), oldest first
	function provider.pendingRequests(): { { key: string, generation: number, attempt: number } }
		local out = {}
		for _, request in requests :: { [string]: Request } do
			if request.active then
				table.insert(out, { key = request.key, generation = request.generation, attempt = request.attempt })
			end
		end
		table.sort(out, function(a, b)
			return a.generation < b.generation
		end)
		return out
	end

	-- returns "applied" | "stale"
	-- MICROPROFILER PHASE `Facet/resource` (roadmap Step 9). Completion is where
	-- an async landing turns into UI work — cache admission, LRU/eviction, and the
	-- transaction that pushes the value into the tree — and a capture has to be able
	-- to tell that apart from steady-state framework cost, or a cold-image profile
	-- reads as "the framework got slower". `fail` carries the same scope: a retry
	-- storm is resource work too, and a phase that only names the happy path hides
	-- exactly the case worth profiling.
	function provider.complete(key: string, generation: number, value: any): string
		if disposed then
			return "stale" -- a fetch that lands after teardown, see `provider.dispose`
		end
		return profile.span("resource", function(): string
			local request = requests[key]
			if request == nil or request.generation ~= generation then
				counters.staleRejected += 1
				syncCounters()
				return "stale"
			end
			retireRequest(request)
			cache[key] = value
			touchLru(key)
			evictOverBudget()
			local entry = keyState[key]
			if entry ~= nil then
				core:transaction(function()
					entry.value:set(value)
					entry.error:set(nil)
					entry.state:set("ready")
				end)
			end
			syncCounters()
			return "applied"
		end)
	end

	-- returns "retrying" | "failed" | "stale"
	function provider.fail(key: string, generation: number, message: any): string
		if disposed then
			return "stale" -- see `provider.dispose`
		end
		return profile.span("resource", function(): string
			local request = requests[key]
			if request == nil or request.generation ~= generation then
				counters.staleRejected += 1
				syncCounters()
				return "stale"
			end
			local policy = request.retry or defaultRetry
			if request.attempt <= policy.count then
				-- retry under a NEW generation so the failed attempt's late
				-- completion is stale by construction; the WAVE carries over so
				-- waiter release still cancels the retried request (verifier F2)
				local attempt = request.attempt + 1
				local wave = request.wave
				retireRequest(request)
				generationCounter += 1
				local retry: Request = {
					key = key,
					generation = generationCounter,
					attempt = attempt,
					active = false,
					wave = wave,
					retry = policy,
				}
				requests[key] = retry
				if policy.delaySeconds > 0 then
					-- SPACED: it waits out of the transport's sight until `tick` crosses
					-- its due time. It is still `requests[key]`, so a release still
					-- cancels it and a late completion is still stale.
					retry.dueAt = now() + policy.delaySeconds
					table.insert(waiting, retry)
				else
					table.insert(queue, retry)
					promote()
				end
				syncCounters()
				return "retrying"
			end
			retireRequest(request)
			-- the budget is spent. A DECLARED retry policy gives up permanently for the
			-- session (per call site); the legacy `retryAttempts` spelling keeps its old
			-- promise, where a later acquire simply asks again.
			if policy.giveUp then
				gaveUp[key] = tostring(message)
			end
			local entry = keyState[key]
			if entry ~= nil then
				core:transaction(function()
					entry.error:set(tostring(message))
					entry.state:set("failed")
				end)
			end
			syncCounters()
			return "failed"
		end)
	end

	-- advance the injected clock: spaced retries whose due time has passed join the
	-- queue. Call it once per frame from the same loop that steps the motion clock;
	-- a provider with no spaced retry has nothing to do here.
	function provider.tick()
		if disposed or #waiting == 0 then
			return
		end
		local t = now()
		local due: { Request } = {}
		for i = #waiting, 1, -1 do
			local request = waiting[i]
			if requests[request.key] ~= request then
				table.remove(waiting, i) -- cancelled or superseded while it waited
			elseif request.dueAt ~= nil and t >= (request.dueAt :: number) then
				table.remove(waiting, i)
				table.insert(due, request)
			end
		end
		-- oldest first, so a burst of spaced retries keeps its order
		table.sort(due, function(a, b)
			return a.generation < b.generation
		end)
		for _, request in due do
			request.dueAt = nil
			table.insert(queue, request)
		end
		promote()
		syncCounters()
	end

	-- PRELOAD (SF-A3): warm a declared imminent identity set so a debuting badge
	-- skips the placeholder flash. It is an ACQUIRE without a view — the same
	-- requests, the same concurrency window, the same generations — so the
	-- logical-cancel contract is unchanged: `release()` prevents work that has not
	-- started, and a completion that arrives after it is stale by construction.
	-- Never a global sweep: it fetches exactly the keys it was handed.
	function provider.preload(keys: { string }, preloadOpts: { retry: RetryOpts? }?)
		assert(type(keys) == "table", "provider.preload takes an array of keys")
		specGuard.assertKnownKeys("provider.preload", preloadOpts, CALL_OPTS_KEYS, "opts")
		if preloadOpts ~= nil then
			specGuard.assertKnownKeys("provider.preload opts.retry", preloadOpts.retry, RETRY_OPTS_KEYS, "opts")
		end
		local retry = if preloadOpts ~= nil and preloadOpts.retry ~= nil
			then resolveRetry(preloadOpts.retry, defaultRetry)
			else defaultRetry
		local waves: { { key: string, wave: Wave } } = {}
		for _, key in keys do
			if type(key) == "string" and key ~= "" and cache[key] == nil and gaveUp[key] == nil then
				local request = requests[key]
				if request == nil then
					request = beginRequest(key, retry)
				end
				local wave = (request :: Request).wave
				wave.count += 1
				table.insert(waves, { key = key, wave = wave })
			end
		end
		syncCounters()
		local released = false
		return {
			keys = keys,
			release = function()
				if released then
					return
				end
				released = true
				for _, held in waves do
					held.wave.count -= 1
					local current = requests[held.key]
					if current ~= nil and current.wave == held.wave and held.wave.count <= 0 then
						counters.dropped += 1
						retireRequest(current)
					end
				end
				syncCounters()
			end,
		}
	end

	-- drop a cached value (tests/eviction hooks); a later acquire re-requests. It
	-- also clears a session give-up: this is the one explicit "ask again" seam.
	function provider.invalidate(key: string)
		cache[key] = nil
		gaveUp[key] = nil
		for i, k in cacheOrder do
			if k == key then
				table.remove(cacheOrder, i)
				break
			end
		end
		syncCounters()
	end

	-- has this key spent its retry budget for the session? (the honest read behind
	-- a placeholder that will never fill)
	function provider.gaveUp(key: string): boolean
		return gaveUp[key] ~= nil
	end

	function provider.counters()
		syncCounters()
		return table.clone(counters)
	end

	--[[ THE SESSION ENDS (ARCH-13; constitution §2 "who disposes it", §8).

		This is a `newX` factory holding the most state of anything on the public
		surface — an LRU cache, the in-flight request table, the queue, the spaced
		retry list, the session's `gaveUp` ledger, and one core SIGNAL TRIPLE
		(`state`, `value`, `error`) per live key — with no teardown seam and no
		stated lifetime. A consumer that dropped its reference left every one of
		those signals in the reactive graph for the life of the core.

		WHAT IT DOES NOT DO IS CANCEL YOUR FETCHES. This module is the engine-free
		MODEL: the actual work is somebody else's coroutine calling `complete` or
		`fail` back into it, and it has no handle on that. What it does instead is
		make the landing harmless — `complete` and `fail` answer `"stale"` after
		disposal, which is the same word they already use for a superseded
		generation, so a caller that checks the return needs no new branch. `tick`
		and `acquire` are inert for the same reason: teardown is not a moment, it is
		a window, and everything already in flight arrives inside it.

		Idempotent. `releaseState` frees each key's triple exactly once through the
		refcount it already keeps, so a key still held by a live scope is not
		double-freed when that scope disposes afterwards. ]]
	function provider.dispose()
		if disposed then
			return
		end
		disposed = true
		-- the signal triples first, through the refcount that owns them: drop each
		-- key to zero rather than clearing the table out from under it
		for key, entry in keyState do
			for _ = 1, entry.refs do
				releaseState(key)
			end
		end
		table.clear(keyState)
		table.clear(requests)
		table.clear(queue)
		table.clear(waiting)
		table.clear(gaveUp)
		table.clear(cache)
		table.clear(cacheOrder)
		activeCount = 0
		counters.handles = 0
		counters.staleRejected = 0
		counters.dropped = 0
		syncCounters()
	end

	return provider
end

return resources
