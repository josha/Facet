--!strict
-- Roblox Signals owns values, lazy computeds and graph invalidation. Facet adds
-- deterministic callback delivery, lifecycle, diagnostics and layout settling.
-- Subscription records below manage lifetime/error recovery; they never walk
-- dependencies to invalidate or recompute the graph.
local contract = require("./contract")
local profile = require("./profile")
local scope_impl = require("./scope_impl")
local Signals = require("../vendor/signals/signals")
local Scheduler = require("../vendor/signals/scheduler")
local tracking = require("./tracking")
local FEEDBACK_ROUND_CAP = 100
local function defaultEq(a: any, b: any): boolean
	return a == b or (a ~= a and b ~= b)
end
local function noop() end
local function deliveryOrder(a: any, b: any): boolean
	if (a.kind == "effect") ~= (b.kind == "effect") then
		return b.kind == "effect"
	end
	return a.seq < b.seq
end
local factory =
	{ name = "signals", claims = { dynamicDependencies = true, cycleDetection = true, writeDuringMemoError = true } }
export type Options = { warn: ((string) -> ())? }
function factory.new(opts: Options?): any
	local counts = { signals = 0, memos = 0, observers = 0, effects = 0, scopes = 0, settles = 0 }
	local emitWarn = if opts and opts.warn then opts.warn else warn
	local lastError: string? = nil
	local txDepth, running, writing = 0, 0, 0
	local flushing, scheduled = false, false
	local writeSet: { [any]: boolean } = {}
	local pending: { [any]: boolean } = {}
	local deliveryQueue: { any } = {}
	local evalStack: { any } = {}
	local settles: { any } = {}
	local settlesDirty = false
	local seq, observerSeq = 0, 0
	local core: any
	local flush: () -> ()
	local function fail(message: string)
		if message ~= lastError then
			emitWarn(`Facet: quarantined - {message}`)
		end
		lastError = message
	end
	local newScope = scope_impl.factory(counts, fail)
	local function safeEq(node: any, a: any, b: any): boolean
		if node.eq == defaultEq then
			return defaultEq(a, b)
		end
		local ok, result = pcall(node.eq, a, b)
		if not ok then
			fail(`Facet: equality callback error quarantined: {tostring(result)}`)
			return false
		end
		return result == true
	end
	local function nodeName(node: any): string
		if node.name == nil then
			node.name = `{node.kind}#{node.seq}`
			if node.compute then
				local source, line = debug.info(node.compute, "sl")
				node.name = `{node.kind}@{string.match(source, "[^/]+$") or source}:{line}`
			end
		end
		return node.name
	end
	local function reportFrozen(node: any)
		if node.frozenBy then
			local name = node.frozenBy
			node.frozenBy = nil
			fail(
				`Facet: '{nodeName(node)}' can no longer update — '{name}', which it was subscribed to, was disposed while this node was still live; it will answer this value forever`
			)
		end
	end
	local function hasWork(): boolean
		return next(writeSet) ~= nil or next(pending) ~= nil
	end
	local function scheduledFlush()
		scheduled = false
		if txDepth == 0 and running == 0 and writing == 0 then
			flush()
		end
	end
	local function enqueue(record: any)
		if record.disposed then
			return
		end
		pending[record] = true
		if not scheduled and not flushing and txDepth == 0 and running == 0 and writing == 0 then
			scheduled = true
			Scheduler.schedule(scheduledFlush)
		end
	end
	local function detach(record: any)
		for source, observer in record.sources do
			source(observer, true)
		end
		for dep in record.deps do
			dep.subs[record] = nil
		end
		table.clear(record.sources)
		table.clear(record.deps)
		if record.nextSources then
			table.clear(record.nextSources)
			table.clear(record.nextDeps)
		end
		record.trackScope, record.readScope = nil, nil
	end
	local function evaluate(record: any, scope: any, fn: any, memo: boolean): any
		local sources, deps = record.nextSources, record.nextDeps
		table.clear(sources)
		table.clear(deps)
		record.trackScope = scope
		if memo then
			table.insert(evalStack, record)
		end
		running += 1
		local ok, result = tracking.run(record.track, fn, record.use)
		running -= 1
		if memo then
			table.remove(evalStack)
		end
		if record.disposed then
			for source, observer in sources do
				source(observer, true)
			end
			return record.value
		end
		if not ok then
			fail(tostring(result))
			if memo and next(record.sources) ~= nil then
				-- Upstream disconnects before evaluation. Restore the last good
				-- subscriptions after an error, without adding an invalidation walk.
				for source, observer in sources do
					if not record.sources[source] then
						source(observer, true)
					end
				end
				for source in record.sources do
					local observer = scope(source)
					source(observer)
					record.sources[source] = observer
				end
				return record.value
			end
		end
		for dep in record.deps do
			if not deps[dep] then
				dep.subs[record] = nil
			end
		end
		for dep in deps do
			if not record.deps[dep] then
				dep.subs[record] = true
			end
		end
		record.nextSources, record.nextDeps = record.sources, record.deps
		record.sources, record.deps = sources, deps
		record.retry = memo and not ok and next(sources) == nil
		if ok then
			record.value = result
			record.frozenBy = nil
		end
		return record.value
	end
	local function readNode(node: any, scope: any): any
		if node.disposed then
			return node.value
		end
		if node.evaluating then
			local names = {}
			for _, entry in evalStack do
				table.insert(names, nodeName(entry))
			end
			table.insert(names, nodeName(node))
			error(`Facet cycle: {table.concat(names, " -> ")}`, 0)
		end
		if node.retry then
			-- No inputs exist to invalidate a first failed computation.
			node.raw = node.createComputed()
			node.retry = false
		end
		local value
		if scope then
			node.readScope = scope
			value = node.raw(node.connect)
		else
			value = node.raw(false)
		end
		reportFrozen(node)
		return value
	end
	local function notify(node: any)
		--[[ THE ONE-OBSERVER PATH ALLOCATES NOTHING. The reactive review found
			every flush allocating unavoidably — a snapshot table and a
			`table.sort` per notified node, three tables per propagation round, and a
			closure plus a dependency set per pull (measured wave T15).

			The snapshot below exists for two reasons and one of them evaporates at a
			fan-out of one. ORDER is the first: `node.observers` is a hash table, so
			iteration order is not registration order and a sort is the only way to
			make a flush reproducible — but a single observer has no order to
			establish. SAFETY is the second and it survives, so it is kept here
			explicitly: the record is read into a local BEFORE the callback runs, so
			an observer that disposes itself or registers a sibling mid-callback
			cannot be mutating a table this loop is walking.

			A fan-out of one is not the rare case. It is the ordinary shape of a
			mounted tree — one binding per property — which is why a table plus a
			`table.sort` per notified node was the largest allocation in a flush.

			MEASURED IN SCENES, not merely in a microbenchmark (tools/perf.sh p95,
			five interleaved samples a side): `animation-interruption` 0.347 -> 0.106
			ms, `collection-mutation` 1.214 -> 0.864, `hud-binding-storm` 0.220 ->
			0.206. Every guarantee the snapshot gave is pinned at fan-out ONE in
			tests/reactive_recovery.spec.luau, each case proved to bite by
			mutating this branch. ]]
		local only: any = nil
		local count = 0
		for observer in node.observers do
			count += 1
			if count > 1 then
				break
			end
			only = observer
		end
		if count == 0 then
			return
		end
		if count == 1 then
			local observer = only
			if not observer.disposed and not safeEq(node, observer.lastSeen, node.value) then
				observer.lastSeen = node.value
				-- the same quarantine as the loop below, for the same reason
				local ok, err = pcall(observer.fn, node.value)
				if not ok then
					fail(tostring(err))
				end
			end
			return
		end
		local snapshot = {}
		for observer in node.observers do
			table.insert(snapshot, observer)
		end
		table.sort(snapshot, function(a, b)
			return a.seq < b.seq
		end)
		for _, observer in snapshot do
			if not observer.disposed and not safeEq(node, observer.lastSeen, node.value) then
				observer.lastSeen = node.value
				-- quarantine (§6.2): an erroring observer callback (e.g. a
				-- structural region hitting a runtime duplicate key) records
				-- lastError; it must never wedge the flush loop mid-notify
				-- (phase-4 fault injection: teardown/runtime-dup-key)
				local ok, err = pcall(observer.fn, node.value)
				if not ok then
					fail(tostring(err))
				end
			end
		end
	end

	local function runEffect(record: any)
		if record.disposed then
			return
		end
		detach(record)
		evaluate(record, record.effectScope, record.fn, false)
	end
	local function propagateRound()
		local queue = deliveryQueue
		for record in pending do
			table.insert(queue, record)
		end
		table.clear(pending)
		table.clear(writeSet)
		if #queue > 1 then
			table.sort(queue, deliveryOrder)
		end
		for _, record in queue do
			if not record.disposed then
				if record.kind == "effect" then
					runEffect(record)
				else
					if record.kind == "signal" then
						-- A signal write already stores its exact public value. Signals
						-- clears observers on invalidation; renew that subscription
						-- directly, without pulling the same value through a getter.
						record.source(record.invalidate)
					else
						record.value = readNode(record, record.watchScope)
					end
					notify(record)
				end
			end
		end
		table.clear(queue)
	end
	local flushBody: () -> ()
	flush = function()
		if flushing or txDepth > 0 or running > 0 or writing > 0 then
			return
		end
		flushing = true
		local ok, err = pcall(profile.span :: any, "react", flushBody)
		table.clear(deliveryQueue)
		flushing = false
		if not ok then
			fail(tostring(err))
		end
	end
	local function compactSettles()
		if not settlesDirty then
			return
		end
		settlesDirty = false
		local kept: { any } = {}
		for _, s in settles do
			if not s.disposed then
				table.insert(kept, s)
			end
		end
		settles = kept
	end

	--[[ A SETTLE CALLBACK IS NAMED THE SAME WAY A MEMO IS. Settle records
		hold a plain function, so the creation site of that function is the label —
		the same derivation `nodeName` performs, against a record instead of a node. ]]
	local function settleName(record: any): string
		if record.name == nil then
			local ok, source, line = pcall(debug.info :: any, record.fn, "sl")
			record.name = if ok and type(source) == "string"
				then `settle@{string.match(source, "[^/]+$") or source}:{tostring(line)}`
				else "settle"
		end
		return record.name
	end

	flushBody = function()
		local rounds = 0
		local capped = false
		--[[ WHICH SETTLE CALLBACK IS ACTUALLY NON-CONVERGENT (corrected after
			review).

			The first version kept only "the settle that wrote last in this flush"
			and quarantined it whenever the cap blew. That is wrong, and the header
			it carried ("an effect feedback loop never lets that happen and leaves
			this nil") was false: `overCap` is reached from TWO places — the
			propagate-to-quiescence loop and the post-settle-pass check — so a cap
			blown by an unrelated EFFECT runaway quarantined whichever settle had
			legitimately published earlier in the same flush. That is precisely the
			measure→publish→react shape the settle phase exists for, and the victim
			would be `renderer.luau`'s geometry-feedback solve or its disarm, killed
			for the rest of the surface's life by one cap hit anywhere.

			THE DISCRIMINATOR IS PASSES, NOT WRITES. A converging settle writes at
			most ONCE per flush — it publishes, the pass restarts, and on the restart
			it has nothing to do. A non-converging one writes on EVERY pass. So the
			count is per record per flush, and only a record above one is
			quarantined; an innocent publisher that wrote once is never touched, no
			matter what else blew the cap. ]]
		local settleWrites: { [any]: number } = {}
		local lastSettleWriter: any = nil
		-- one wording for both feedback shapes: an effect that keeps writing and
		-- a measure→publish cycle that will not settle are the same failure
		local function overCap(): boolean
			if rounds <= FEEDBACK_ROUND_CAP then
				return false
			end
			local dropped = 0
			for _ in writeSet do
				dropped += 1
			end
			local message =
				`Facet: flush exceeded the {FEEDBACK_ROUND_CAP}-round iteration cap (effect or settle feedback loop?); {dropped} pending signal write(s) discarded`
			--[[ ...AND THE CALLBACK THAT DROVE IT IS QUARANTINED. Without this
				the same non-converging callback is re-run to the full cap on EVERY
				later flush in the session: the cost is paid forever and the diagnostic
				is indistinguishable from the first one. Quarantine is the memo idiom —
				skipped, last state kept, one recorded error — and because the core
				cannot see a settle's inputs the way it sees a memo's deps, the reset is
				RE-REGISTRATION: dispose the handle and call `core:settle` again.

				ONE message, not two: the cap error is the diagnostic every consumer
				already greps for, and a second `fail` would overwrite it with a string
				that no longer says what happened. ]]
			if
				lastSettleWriter ~= nil
				and not lastSettleWriter.quarantined
				and (settleWrites[lastSettleWriter] or 0) > 1
			then
				lastSettleWriter.quarantined = true
				message ..= ` — settle callback '{settleName(lastSettleWriter)}' is QUARANTINED and will be ` .. `skipped until it is re-registered; a settle callback must converge, because it is re-run ` .. `until it writes nothing`
			end
			fail(message)
			writeSet = {}
			table.clear(pending)
			capped = true
			return true
		end
		while true do
			-- ---- PROPAGATE, to quiescence -------------------------------------
			while hasWork() do
				rounds += 1
				if overCap() then
					break
				end
				propagateRound()
			end
			if capped or #settles == 0 then
				break
			end
			-- ---- SETTLE -------------------------------------------------------
			local wrote = false
			-- `#settles` is read ONCE: a callback registering another settle joins
			-- the next pass, never the one iterating (same rule as an observer
			-- added mid-flush)
			for i = 1, #settles do
				local s = settles[i]
				if s ~= nil and not s.disposed and not s.quarantined then
					-- quarantined like every other user callback (§6.2): a throwing
					-- settle records lastError and must never unwind the flush loop
					-- and strand flushing=true
					local ok, err = pcall(s.fn)
					if not ok then
						fail(tostring(err))
					end
					if hasWork() then
						wrote = true
						lastSettleWriter = s
						settleWrites[s] = (settleWrites[s] or 0) + 1
						break
					end
				end
			end
			if not wrote then
				break
			end
			rounds += 1
			if overCap() then
				break
			end
		end
		compactSettles()
	end

	local function newNode(kind: string, eq: any): any
		seq += 1
		local node: any = {
			kind = kind,
			seq = seq,
			eq = eq or defaultEq,
			sources = {},
			deps = {},
			subs = {},
			observers = {},
			disposed = false,
		}
		node.connect = function(source)
			node.source = source
			return node.readScope(source, node)
		end
		if kind ~= "signal" then
			node.nextSources, node.nextDeps = {}, {}
			node.track = function(source, dep)
				local observer = node.trackScope(source)
				node.nextSources[source] = observer
				if dep then
					node.nextDeps[dep] = true
				end
				return observer
			end
			node.use = function(source)
				return source._read(node.track)
			end
		end
		return node
	end
	local function makeReadable(node: any): any
		local public: any = { kind = node.kind, _node = node }
		public._read = function(scope)
			return readNode(node, scope)
		end
		function public.get(_self)
			if node.kind == "signal" then
				return node.value
			end
			if not node.evaluating then
				return readNode(node, nil)
			end
			local ok, value = pcall(readNode, node, nil)
			if not ok then
				fail(tostring(value))
				return node.value
			end
			return value
		end
		function public.set(_self, value)
			assert(node.kind == "signal", "cannot set a memo")
			if #evalStack > 0 then
				error("Facet: writing state during memo evaluation is an error", 0)
			end
			if node.disposed then
				return
			end
			if safeEq(node, node.value, value) then
				return
			end
			node.value = value
			writeSet[node] = true
			writing += 1
			-- Signals treats a function as an updater; Core stores arbitrary T.
			node.write(if type(value) == "function"
				then function()
					return value
				end
				else value)
			writing -= 1
			flush()
		end
		function public.dispose(_self)
			if node.disposed then
				return
			end
			node.disposed = true
			detach(node)
			if node.source and node.invalidate then
				node.source(node.invalidate, true)
			end
			for sub in node.subs do
				if sub.kind ~= "memo" or sub.disposed then
					continue
				end
				local live = false
				for dep in sub.deps do
					if dep ~= node and not dep.disposed then
						live = true
						break
					end
				end
				if not live then
					sub.frozenBy = nodeName(node)
				end
				if node.source and sub.sources[node.source] then
					node.source(sub.sources[node.source], true)
					sub.sources[node.source] = nil
				end
			end
			table.clear(node.subs)
			for observer in node.observers do
				if not observer.disposed then
					observer.disposed = true
					counts.observers -= 1
				end
			end
			table.clear(node.observers)
			node.raw, node.write, node.compute, node.createComputed = nil, nil, nil, nil
			pending[node], writeSet[node] = nil, nil
			counts[if node.kind == "signal" then "signals" else "memos"] -= 1
		end
		return public
	end
	core = {
		name = "signals",
		signal = function(_self, initial: any, eq: any)
			counts.signals += 1
			local node = newNode("signal", eq)
			node.value = initial
			node.raw, node.write = Signals.createSignal(function()
				return initial
			end, function()
				return false
			end)
			return makeReadable(node)
		end,
		memo = function(_self, compute: any, eq: any)
			counts.memos += 1
			local node = newNode("memo", eq)
			node.compute = compute
			node.createComputed = function()
				return Signals.createComputed(function(scope)
					node.evaluating = true
					local result = evaluate(node, scope, compute, true)
					node.evaluating = false
					return result
				end, function(a, b)
					return safeEq(node, a, b)
				end)
			end
			node.raw = node.createComputed()
			return makeReadable(node)
		end,
		observe = function(_self, source: any, onChange: any)
			local node = source._node
			if node.disposed then
				return noop
			end
			local value = source:get()
			if node.invalidate == nil then
				node.invalidate = function()
					enqueue(node)
				end
				node.watchScope = function()
					return node.invalidate
				end
			end
			if node.evaluating then
				node.raw(function(rawSource)
					node.source = rawSource
					return node.invalidate
				end)
			else
				readNode(node, node.watchScope)
			end
			counts.observers += 1
			observerSeq += 1
			local observer = { fn = onChange, seq = observerSeq, lastSeen = value, disposed = false }
			node.observers[observer] = true
			return function()
				if observer.disposed then
					return
				end
				observer.disposed = true
				node.observers[observer] = nil
				counts.observers -= 1
				if next(node.observers) == nil then
					if node.source then
						node.source(node.invalidate, true)
					end
					pending[node] = nil
				end
			end
		end,
		effect = function(_self, run: any)
			counts.effects += 1
			local record = newNode("effect", nil)
			record.fn = run
			record.invalidate = function()
				enqueue(record)
			end
			record.effectScope = function()
				return record.invalidate
			end
			runEffect(record)
			flush()
			return function()
				if record.disposed then
					return
				end
				record.disposed = true
				detach(record)
				record.fn = nil
				pending[record] = nil
				counts.effects -= 1
			end
		end,
		settle = function(_self, run: any)
			counts.settles += 1
			local record = { fn = run, disposed = false }
			table.insert(settles, record)
			return function()
				if record.disposed then
					return
				end
				record.disposed = true
				settlesDirty = true
				counts.settles -= 1
				if not flushing then
					compactSettles()
				end
			end
		end,
		transaction = function(_self, body: any)
			txDepth += 1
			local ok, err = pcall(profile.span :: any, "mutate", body)
			txDepth -= 1
			flush()
			if not ok then
				error(err, 0)
			end
		end,
		flush = function(_self)
			flush()
		end,
		scope = function(_self, label: string?)
			return newScope(label)
		end,
		counters = function(_self)
			return table.clone(counts)
		end,
		lastError = function(_self)
			return lastError
		end,
	}
	return core
end
return factory :: contract.CoreFactory
