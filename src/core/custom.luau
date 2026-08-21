--!strict
-- Minimal custom reactive core: the SELECTED foundation (ADR-0002) of the
-- Phase 0 bake-off (design §3, §6, §17). Implements src/core/contract.luau:
-- transactional writes, glitch-free pull-based memo recomputation, dynamic
-- dependency swap, cycle + write-during-memo + feedback-cap diagnostics with
-- node quarantine, explicit scope ownership, and live counters.
-- Observer semantics: each observer tracks the last value it was notified
-- with (lastSeen) and fires only when the node's post-flush value differs by
-- the node's equality — this is what makes set-then-revert transactions and
-- unchanged recomputes fire-free (2026-07-19 verifier finding 1).
-- Depends only on the contract types; no engine or Lune APIs.

local contract = require("./contract")
local profile = require("./profile")
local scope_impl = require("./scope_impl")

type Use = contract.Use

-- Rounds are effect-write generations, not graph depth; 100 permits deep
-- legitimate effect chains while still catching true feedback loops. Hitting
-- the cap reports how many writes were discarded (verifier finding 5).
-- A settle PASS counts as a round too (see flushBody), so a measure→publish
-- cycle that will not converge is caught by the same bound and reported the
-- same way — never a hang, never a silent frame.
local FEEDBACK_ROUND_CAP = 100

type Node = {
	kind: string, -- "signal" | "memo"
	name: string?,
	seq: number?, -- creation order; gives flushBody a total order across nodes
	value: any,
	eq: (any, any) -> boolean,
	subs: { [any]: boolean }, -- dependent memos/effects
	observers: { [any]: boolean }, -- observer records {fn, seq, lastSeen, disposed}
	stale: boolean, -- memo only
	evaluating: boolean, -- memo only (cycle detection)
	failed: boolean, -- memo only
	compute: ((use: Use) -> any)?,
	deps: { [Node]: boolean }, -- memo only
	-- memo only: the name of a dep that was DISPOSED while this node was still
	-- subscribed to it, cleared by the next successful recompute
	frozenBy: string?,
	disposed: boolean,
}

-- NaN-safe default equality (NaN ~= NaN would refire on every equal write)
local function defaultEq(a: any, b: any): boolean
	return a == b or (a ~= a and b ~= b)
end

local Custom = {}

function Custom.new()
	local core: any
	local counts = { signals = 0, memos = 0, observers = 0, effects = 0, scopes = 0, settles = 0 }
	local txDepth = 0
	local flushing = false
	local writeSet: { [Node]: boolean } = {}
	local evalStack: { Node } = {}
	local evaluatingMemo = false
	local inEffectRun = false
	local lastError: string? = nil
	local observerSeq = 0
	-- settle callbacks, in REGISTRATION order (see flushBody's settle phase).
	-- Disposal marks rather than removes, so a callback disposing a sibling can
	-- never corrupt an iteration in flight; the list is compacted at the end of
	-- the flush that noticed.
	local settles: { any } = {}
	local settlesDirty = false

	local flush -- forward

	local function fail(message: string)
		lastError = message
	end

	-- scope diagnostics (double disposal, a quarantined cleanup error) come out
	-- of scope_impl already worded and land on the same channel every other
	-- quarantine uses
	local newScope = scope_impl.factory(counts, fail)

	-- user-supplied equality callbacks are quarantined like every other user
	-- callback (§6.2): a throwing eq records lastError and reads as "changed"
	-- so updates keep propagating — it must never unwind a writer or wedge
	-- the flush loop (phase-4 verifier F1/F4)
	local function safeEq(node: Node, a: any, b: any): boolean
		local ok, result = pcall(node.eq, a, b)
		if not ok then
			fail(`Facet: equality callback error quarantined: {tostring(result)}`)
			return false
		end
		return result == true
	end

	--[[ A NODE'S DIAGNOSTIC NAME (release-candidate review 2026-08-17).

		`Node.name` was declared in the type and written NOWHERE, so every cycle
		path printed `memo -> memo -> memo` and the one diagnostic that exists to
		tell you WHICH memos closed the loop told you nothing. The name is DERIVED
		rather than declared: a memo's compute function carries its own creation
		site, which is the label a reader can act on, and taking it from the
		function costs no widening of `core:memo`'s signature — no new public
		member to document, register, and keep in parity for a string only a
		failure ever reads.

		Derived LAZILY and cached on the node, because a diagnostic is rare and
		`debug.info` is not free: the healthy path pays one nil check. The source
		is trimmed to its last path segment so the path reads as `memo@custom
		.spec:214` rather than an absolute checkout path (a Roblox `debug.info`
		source has no `/` in it and passes through unchanged). ]]
	local function nodeName(node: Node): string
		local cached = node.name
		if cached ~= nil then
			return cached
		end
		-- A SIGNAL HAS NO COMPUTE TO READ A CREATION SITE OFF, so it is named by its
		-- creation ORDER instead — `signal#12`. The bare kind was what shipped, and
		-- the contract is "naming the disposed node": for a signal, which is
		-- every case that diagnostic actually reaches, "signal" names nothing at
		-- all. `seq` already exists (it is what gives a flush its total order), so
		-- this costs one concatenation on a path only a failure walks.
		local label = if node.seq ~= nil then `{node.kind}#{node.seq}` else node.kind
		local fn = node.compute
		if fn ~= nil then
			local ok, source, line = pcall(debug.info, fn, "sl")
			if ok and type(source) == "string" then
				label = `{node.kind}@{string.match(source, "[^/]+$") or source}:{tostring(line)}`
			end
		end
		node.name = label
		return label
	end

	--[[ THE FROZEN-VALUE REPORT, from every read path there is.

		Reported ONCE — this is a diagnostic, not a rate limiter, and the second
		read carries no information the first did not — and only for a node that
		genuinely has no live dep left (see the disposal site). Both the public
		`get` and the internal `use` call it, because a memo consumed only through
		another memo is the ordinary shape and was the case that stayed silent. ]]
	local function reportFrozen(node: Node)
		local frozenBy = node.frozenBy
		if frozenBy == nil then
			return
		end
		node.frozenBy = nil
		fail(
			`Facet: '{nodeName(node)}' can no longer update — '{frozenBy}', which it was subscribed to, `
				.. `was disposed while this node was still live; it will answer this value forever`
		)
	end

	-- pull: (re)compute a stale memo; returns current value. Never throws to
	-- the caller: compute errors, cycles, and illegal writes quarantine the
	-- node (failed=true, old value kept) and record lastError.
	local function pull(node: Node): any
		if node.kind ~= "memo" or node.disposed then
			return node.value
		end
		if node.evaluating then
			local path = {}
			for _, n in evalStack do
				table.insert(path, nodeName(n))
			end
			table.insert(path, nodeName(node))
			error(`Facet cycle: {table.concat(path, " -> ")}`, 0)
		end
		if not node.stale then
			return node.value
		end
		node.evaluating = true
		table.insert(evalStack, node)
		local wasEvaluatingMemo = evaluatingMemo
		evaluatingMemo = true
		local newDeps: { [Node]: boolean } = {}
		local use: Use = function(source: any): any
			local dep = source._node :: Node
			newDeps[dep] = true
			local value = pull(dep)
			-- the OTHER half: a frozen memo consumed only
			-- TRANSITIVELY — memos chaining into memos, the ordinary shape of a UI
			-- graph — never reached `public.get` and served stale data forever with
			-- `lastError` nil. A read is a read whoever makes it.
			if dep.frozenBy ~= nil then
				reportFrozen(dep)
			end
			return value
		end :: any
		local ok, result = pcall(node.compute :: any, use)
		evaluatingMemo = wasEvaluatingMemo
		table.remove(evalStack)
		node.evaluating = false
		if ok then
			-- atomic dependency swap on success only
			for dep in node.deps do
				dep.subs[node] = nil
			end
			node.deps = newDeps
			for dep in newDeps do
				dep.subs[node] = true
			end
			node.stale = false
			node.failed = false
			node.frozenBy = nil -- it recomputed, so it is not frozen
			node.value = result
		else
			node.failed = true
			fail(tostring(result))
			--[[ A FIRST-EVALUATION FAILURE USED TO BE PERMANENT.

				The dependency swap above is success-only, which is right for a memo
				that HAS succeeded once: its previous deps are the honest edge set and
				a failed attempt must not narrow them. But a memo whose FIRST
				evaluation throws has no previous deps, so the success-only swap left
				it with an empty dep set — nothing in the graph could ever mark it
				stale again, and with `stale = false` below it answered its cached
				`nil` for the rest of the session. Every shape that reaches this
				branch inherited it: a compute that throws, and an illegal
				write during a memo's first evaluation, which is a THROW out of
				`write` and therefore the same code path.

				So on a first-evaluation failure the node subscribes to the deps `use`
				DID reach before the throw: a change in any of them re-marks it stale
				and the next pull retries. And when the throw came before any `use` at
				all there is no edge that could ever invalidate it, so it stays STALE
				— the next pull recomputes unconditionally, which is the only retry
				available to a node with no inputs. ]]
			if next(node.deps) == nil then
				node.deps = newDeps
				for dep in newDeps do
					dep.subs[node] = true
				end
				node.stale = next(newDeps) == nil
			else
				node.stale = false -- avoid re-erroring every pull until next invalidation
			end
		end
		return node.value
	end

	-- effects re-run post-commit when a dependency changed
	local function runEffect(effect: any)
		if effect.disposed then
			return
		end
		-- writes from an effect body always land in the NEXT flush round, even
		-- during the registration run (before its deps are subscribed)
		local wasInEffectRun = inEffectRun
		inEffectRun = true
		local newDeps: { [Node]: boolean } = {}
		local use: Use = function(source: any): any
			local dep = source._node :: Node
			newDeps[dep] = true
			return pull(dep)
		end :: any
		local ok, err = pcall(effect.fn, use)
		for dep in effect.deps do
			dep.subs[effect] = nil
		end
		if effect.disposed then
			-- IT DISPOSED ITSELF DURING ITS OWN RUN, or the scope that owns it
			-- did. The dispose closure already unsubscribed the deps it could see, so
			-- re-subscribing the deps THIS run collected would strand a record in
			-- `dep.subs` that nothing will ever remove — the effect keeps being
			-- collected and re-run forever while `counters().effects` reads clean,
			-- which is the shape that makes the leak invisible.
			effect.deps = {}
		else
			effect.deps = newDeps
			for dep in newDeps do
				dep.subs[effect] = true
			end
		end
		inEffectRun = wasInEffectRun
		if not ok then
			fail(tostring(err))
		end
	end

	-- eager staleness so derived reads INSIDE an open transaction are fresh
	-- (verifier finding 2); observers/effects still wait for the flush
	local function markMemosStale(sub: any, seen: { [any]: boolean })
		if seen[sub] or sub.isEffect then
			return
		end
		seen[sub] = true
		sub.stale = true
		for downstream in sub.subs do
			markMemosStale(downstream, seen)
		end
	end

	local function write(node: Node, value: any)
		if evaluatingMemo then
			error("Facet: writing state during memo evaluation is an error", 0)
		end
		if safeEq(node, node.value, value) then
			return
		end
		node.value = value
		writeSet[node] = true
		local seen: { [any]: boolean } = {}
		for sub in node.subs do
			markMemosStale(sub, seen)
		end
		if not flushing and txDepth == 0 and not inEffectRun then
			flush()
		end
	end

	local function collect(sub: any, observerQueue: { any }, effectQueue: { any }, seen: { [any]: boolean })
		if seen[sub] then
			return
		end
		seen[sub] = true
		if sub.isEffect then
			table.insert(effectQueue, sub)
			return
		end
		local memo = sub :: Node
		memo.stale = true
		if next(memo.observers) ~= nil then
			table.insert(observerQueue, memo)
		end
		for downstream in memo.subs do
			collect(downstream, observerQueue, effectQueue, seen)
		end
	end

	-- fire observers of `node` whose lastSeen differs from the current value.
	-- Snapshot sorted by registration order: deterministic, and observers
	-- added or disposed by a callback never corrupt this iteration
	-- (verifier finding 6).
	local function notify(node: Node)
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

	-- the flush BODY, hoisted out of `flush` so the MicroProfiler scope wraps a
	-- named function rather than a closure allocated on every frame. Everything
	-- inside is already pcall-quarantined (nothing may unwind and strand
	-- `flushing = true`), so the span adds no new failure mode.
	local flushBody: () -> ()

	flush = function()
		if flushing then
			return
		end
		flushing = true
		-- MICROPROFILER PHASE `Facet/react` (roadmap Step 9): reactive propagation
		-- — the dirty walk, memo recomputes, observer notifies and effect runs that
		-- one batch of writes caused. This is the phase that grows superlinearly
		-- when a dependency graph is wrong, and it is invisible in a capture that
		-- only shows `$Script`.
		profile.span("react", flushBody)
		flushing = false
	end

	--[[ THE SETTLE PHASE (optimization-log L-31, 2026-08-14).

		THE SHAPE IT EXISTS FOR. A surface measures its own geometry and publishes
		a number derived from it back into the environment, which invalidates the
		measurement: a dock reserving space under a HUD, a keyboard-avoidance
		inset, a sticky header, a safe-area publisher. Before this phase existed,
		the terminal work (the layout solve) ran INSIDE observer dispatch — in the
		middle of propagation — so a surface committed to a layout before the
		flush had finished deciding what the environment was, and the consumer's
		derived write arrived a whole FRAME later and opened a second flush.
		Measured headless on the general two-surface shape
		(tools/lune/_probe_settle): 2 reactive flushes and 4 solves per geometry
		change against 1 and 2 without the round trip, plus one painted frame
		carrying the wrong number (the content surface's root rect read 655 when
		`env:batch` returned and 551 after the next refresh). The 2026-08-14
		device capture priced the same shape at ~4 of 7.12 solves per step.

		WHAT IT IS. Terminal work registers with `core:settle` and runs AFTER
		propagation quiesces, in registration order. A callback that writes ends
		the pass immediately: propagation drains, and the pass RESTARTS from the
		first callback — so every settle callback sees every other one's
		publication, which is the property that makes a measure→publish cycle
		converge instead of oscillating between two half-applied views. Passes
		repeat until one writes nothing.

		WHY THIS IS NOT A SECOND SCHEDULER. It runs inside `flush`, inside the
		`react` span, inside `flushing = true`: a top-level write still returns
		with all of its consequences applied, and a `core:transaction` opened by a
		settle callback still collapses into the flush already in progress
		(`flush()` no-ops while `flushing`, and the writes stay in `writeSet` for
		the loop below to drain). Nothing about glitch-freedom moves — settle
		callbacks are not observers, and observers still see only post-flush
		values.

		TERMINATION. A settle pass counts as a round against FEEDBACK_ROUND_CAP,
		so a cycle that will not converge is the same loud quarantined error an
		effect feedback loop already produced. The alternative — an unbounded
		loop, or silently dropping the last publication — is the one thing a
		layout phase must never do.

		THE OBLIGATION ON A CALLBACK. Because a pass restarts after any write, a
		settle callback runs more than once per flush and MUST be cheap and
		idempotent when it has nothing to do (the renderer's checks one boolean;
		the presenter's compares one solve counter). ]]
	-- ONE generation of propagation: the dirty walk, the memo recomputes, the
	-- observer notifies and the effect runs that the current `writeSet` causes.
	-- Hoisted out of `flushBody` (2026-08-14) only so the settle phase below can
	-- drain propagation from two places without duplicating it; the body is
	-- unchanged.
	local function propagateRound()
		local written = writeSet
		writeSet = {}
		local observerQueue: { any } = {}
		local effectQueue: { any } = {}
		local seen: { [any]: boolean } = {}
		for signal in written do
			if next(signal.observers) ~= nil then
				table.insert(observerQueue, signal)
			end
			for sub in signal.subs do
				collect(sub, observerQueue, effectQueue, seen)
			end
		end
		-- creation order, so a flush is reproducible run to run (see nodeSeq)
		table.sort(observerQueue, function(x: any, y: any): boolean
			return (x.seq or 0) < (y.seq or 0)
		end)
		for _, node in observerQueue do
			if node.kind == "memo" then
				local pullOk, pullErr = pcall(pull, node)
				if not pullOk then
					fail(tostring(pullErr))
				end
			end
			if not node.disposed then
				-- belt over safeEq: NOTHING inside notify may unwind the
				-- flush loop and strand flushing=true (phase-4 verifier F1)
				local notifyOk, notifyErr = pcall(notify, node)
				if not notifyOk then
					fail(tostring(notifyErr))
				end
			end
		end
		for _, effect in effectQueue do
			runEffect(effect)
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
			local ok, source, line = pcall(debug.info, record.fn, "sl")
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
			capped = true
			return true
		end
		while true do
			-- ---- PROPAGATE, to quiescence -------------------------------------
			while next(writeSet) ~= nil do
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
					if next(writeSet) ~= nil then
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

	local function makeReadable(node: Node)
		local public = { kind = node.kind, _node = node }
		function public.get(_self)
			if node.kind == "memo" and node.stale then
				local ok, err = pcall(pull, node)
				if not ok then
					fail(tostring(err))
				end
			end
			-- RR-7: a value that can never change again, being read
			reportFrozen(node)
			return node.value
		end
		function public.set(_self, value: any)
			assert(node.kind == "signal", "cannot set a memo")
			write(node, value)
		end
		function public.dispose(_self)
			if node.disposed then
				return
			end
			node.disposed = true
			for dep in node.deps do
				dep.subs[node] = nil
			end
			--[[ DISPOSAL IS ALSO A SEVERED EDGE. Clearing `subs` is correct —
				a disposed node must not keep its dependents alive — but every memo
				subscribed here is now frozen at whatever value it last held, with no
				diagnostic anywhere and no way to tell that state apart from "nothing
				changed".

				REPORTED WHEN IT IS READ, NOT WHEN IT IS SEVERED, and that is not a
				softening — it is the only wording that is TRUE. An ordinary teardown
				severs these edges constantly: a scope disposes what it owns in reverse
				order, and cross-scope order is not promised, so a dep going first is
				the normal case rather than the defect. Reporting at the disposal
				reddened twelve unrelated specs that assert a clean `lastError` after a
				surface tears down (measured, 2026-08-17) — a detector that fires on
				every correct teardown detects nothing.

				The defect is a memo that is READ after it stopped being able to
				update. So the freeze is recorded on the subscriber, cleared by the
				next successful recompute (a node with other live deps re-derives and
				was never frozen), and reported the first time somebody reads a value
				that can no longer change. A torn-down surface is never read again and
				stays silent. ]]
			--[[ ONLY A SUBSCRIBER THAT HAS NOTHING LEFT TO WAKE IT.

				The first version flagged EVERY subscriber, so a memo with other live
				deps — the ordinary shape — was declared frozen on any read taken
				before its next recompute, in a message that affirmatively says "it
				will answer this value forever" about a node that updates on the very
				next write. Worse, `fail()` is unconditional, so that false statement
				OVERWROTE a real earlier error.

				A memo is frozen when the edge that just went is its LAST one. Anything
				else still has a way to be invalidated, and is not frozen by any
				reading of the word. ]]
			local disposedName: string? = nil
			for sub in node.subs do
				if (sub :: any).isEffect or sub.disposed then
					continue
				end
				local live = 0
				for dep in (sub :: Node).deps do
					if dep ~= node and not dep.disposed then
						live += 1
					end
				end
				if live == 0 then
					if disposedName == nil then
						disposedName = nodeName(node)
					end
					(sub :: Node).frozenBy = disposedName
				end
			end
			node.subs = {}
			-- live observers die with their node: reclaim their registry slots
			-- and silence any snapshot still in flight; their unsubscribe
			-- becomes a no-op (phase-4 verifier F5/F6)
			for observer in node.observers do
				if not observer.disposed then
					observer.disposed = true
					counts.observers -= 1
				end
			end
			node.observers = {}
			if node.kind == "signal" then
				counts.signals -= 1
			else
				counts.memos -= 1
			end
		end
		return public
	end

	--[[ A TOTAL ORDER OVER A WHOLE FLUSH (RED-TEAM 2026-08-13). `notify` sorts a
		node's observers by their own seq, which gave a total order only while every
		consumer observed the SAME signal. Once consumers observe their own memos --
		which is exactly what the renderer's geometry coalescing does, one memo per
		surface -- the order across nodes is `flushBody`'s queue order, and that
		queue is built by iterating tables keyed by node REFERENCES. Hash order is
		not an order.

		Stamping each node at creation and sorting the queue by it restores the
		guarantee for OBSERVERS, at the cost of one sort of a small queue per
		flush. `effectQueue` is deliberately NOT sorted and effect records carry no
		seq, so effect order is not promised — `src/core/contract.luau` says so.
		There is exactly one `core:effect` in `src/` today, so nothing rests on it;
		if a second arrives, sort that queue too rather than assuming it inherited
		this (architecture gate F2, 2026-08-14). Creation order is the right key because it is the order the
		application built things in -- surfaces re-solve in mount order. ]]
	local nodeSeq = 0
	local function nextNodeSeq(): number
		nodeSeq += 1
		return nodeSeq
	end

	core = {
		name = "custom",

		signal = function(_self, initial: any, eq: ((any, any) -> boolean)?)
			counts.signals += 1
			local node: Node = {
				kind = "signal",
				seq = nextNodeSeq(),
				value = initial,
				eq = eq or defaultEq,
				subs = {},
				observers = {},
				stale = false,
				evaluating = false,
				failed = false,
				compute = nil,
				deps = {},
				frozenBy = nil,
				disposed = false,
			}
			return makeReadable(node)
		end,

		memo = function(_self, compute: (use: Use) -> any, eq: ((any, any) -> boolean)?)
			counts.memos += 1
			local node: Node = {
				kind = "memo",
				seq = nextNodeSeq(),
				value = nil,
				eq = eq or defaultEq,
				subs = {},
				observers = {},
				stale = true,
				evaluating = false,
				failed = false,
				compute = compute,
				deps = {},
				frozenBy = nil,
				disposed = false,
			}
			return makeReadable(node)
		end,

		observe = function(_self, source: any, onChange: (any) -> ())
			counts.observers += 1
			local node = source._node :: Node
			-- baseline the observer on the node's CURRENT value so only
			-- future changes fire (memos evaluate now if never computed)
			if node.kind == "memo" and node.stale then
				-- RR-10: a cycle thrown out of `pull` was swallowed here, so the one
				-- quarantine that has no other reporter (a cycle discovered by the
				-- FIRST observer's baseline read) never reached `core:lastError()`.
				local ok, err = pcall(pull, node)
				if not ok then
					node.failed = true
					fail(tostring(err))
				end
			end
			observerSeq += 1
			local observer = { fn = onChange, seq = observerSeq, lastSeen = node.value, disposed = false }
			node.observers[observer] = true
			return function()
				if observer.disposed then
					return
				end
				observer.disposed = true
				node.observers[observer] = nil
				counts.observers -= 1
			end
		end,

		effect = function(_self, run: (use: Use) -> ())
			counts.effects += 1
			local effect = { isEffect = true, fn = run, deps = {}, disposed = false }
			runEffect(effect)
			if not flushing and txDepth == 0 and next(writeSet) ~= nil then
				flush()
			end
			return function()
				if effect.disposed then
					return
				end
				effect.disposed = true
				for dep in effect.deps do
					dep.subs[effect] = nil
				end
				effect.deps = {}
				counts.effects -= 1
			end
		end,

		-- terminal work that must not run until the flush has stopped moving:
		-- see the settle-phase block above `flushBody` for the whole story
		settle = function(_self, run: () -> ())
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
				-- a disposal DURING a flush only marks; the list is compacted at
				-- the end of that flush, so an iteration in flight cannot be
				-- corrupted by a callback disposing itself or a sibling
				if not flushing then
					compactSettles()
				end
			end
		end,

		transaction = function(_self, body: () -> ())
			txDepth += 1
			-- MICROPROFILER PHASE `Facet/mutate` (roadmap Step 9): the batched
			-- MODEL change, separated from the propagation it causes. A profile that
			-- cannot tell "the game wrote 400 signals" from "the framework walked the
			-- dependency graph" cannot attribute the frame to either of them. The
			-- trailing flush stays OUTSIDE this scope on purpose — it is `react`.
			local ok, err = pcall(profile.span, "mutate", body)
			txDepth -= 1
			if txDepth == 0 then
				flush()
			end
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

		lastError = function(_self): string?
			return lastError
		end,
	}

	return core
end

local factory: contract.CoreFactory = {
	name = "custom",
	new = Custom.new,
	claims = {
		dynamicDependencies = true,
		cycleDetection = true,
		writeDuringMemoError = true,
	},
} :: any

return factory
