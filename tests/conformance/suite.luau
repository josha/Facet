--!strict
-- Scheduler/lifetime conformance suite (design §17 Phase 0): ONE list of
-- checks run identically against every core candidate. Each check returns
-- (ok: boolean, note: string?). Checks never write files; the CLI and spec
-- wrappers aggregate results. Requirements cited per check.

local contract = require("../../src/core/contract")
type Core = contract.Core
type CoreFactory = contract.CoreFactory

export type Check = {
	name: string,
	requirement: string,
	run: (core: Core) -> (boolean, string?),
}

local function eq(a: any, b: any): (boolean, string?)
	if a == b then
		return true, nil
	end
	return false, `expected {tostring(b)}, got {tostring(a)}`
end

local checks: { Check } = {
	{
		name = "signal-read-write",
		requirement = "UI-RUNTIME-003",
		run = function(core)
			local s = core:signal(1)
			s:set(2)
			return eq(s:get(), 2)
		end,
	},
	{
		name = "memo-derives-and-updates",
		requirement = "UI-RUNTIME-003",
		run = function(core)
			local s = core:signal(2)
			local m = core:memo(function(use)
				return use(s) * 10
			end)
			if m:get() ~= 20 then
				return false, `initial memo value {m:get()}`
			end
			s:set(3)
			return eq(m:get(), 30)
		end,
	},
	{
		name = "transaction-batches-observer-to-one-fire",
		requirement = "UI-RUNTIME-003",
		run = function(core)
			local a = core:signal(1)
			local fires = 0
			local last: number? = nil
			core:observe(a, function(v)
				fires += 1
				last = v
			end)
			core:transaction(function()
				a:set(2)
				a:set(3)
			end)
			if fires ~= 1 then
				return false, `observer fired {fires} times for one transaction`
			end
			return eq(last, 3)
		end,
	},
	{
		name = "glitch-free-diamond",
		requirement = "UI-RUNTIME-003",
		run = function(core)
			-- a -> b, a -> c, d(b, c): an observer of d must never see a state
			-- where b reflects the new write but c the old one.
			local a = core:signal(1)
			local b = core:memo(function(use)
				return use(a) + 1
			end)
			local c = core:memo(function(use)
				return use(a) * 10
			end)
			local d = core:memo(function(use)
				return { sum = use(b) + use(c), fromB = use(b), fromC = use(c) }
			end)
			local observed: { { sum: number, fromB: number, fromC: number } } = {}
			core:observe(d, function(v)
				table.insert(observed, v)
			end)
			a:set(5)
			if #observed ~= 1 then
				return false, `observer of d fired {#observed} times for one write`
			end
			local v = observed[1]
			if v.fromB ~= 6 or v.fromC ~= 50 then
				return false, `glitched view: b={v.fromB} c={v.fromC}`
			end
			return true, nil
		end,
	},
	{
		name = "equal-write-skipped",
		requirement = "UI-RUNTIME-001",
		run = function(core)
			local s = core:signal(7)
			local fires = 0
			core:observe(s, function()
				fires += 1
			end)
			s:set(7)
			return eq(fires, 0)
		end,
	},
	{
		name = "custom-equality-respected",
		requirement = "UI-RUNTIME-001",
		run = function(core)
			local s = core:signal({ x = 1 }, function(a, b)
				return a.x == b.x
			end)
			local fires = 0
			core:observe(s, function()
				fires += 1
			end)
			s:set({ x = 1 })
			if fires ~= 0 then
				return false, "eq-equal table write fired observer"
			end
			s:set({ x = 2 })
			return eq(fires, 1)
		end,
	},
	{
		name = "dynamic-dependencies-swap-atomically",
		requirement = "UI-RUNTIME-003",
		run = function(core)
			local flag = core:signal(true)
			local x = core:signal(1)
			local y = core:signal(100)
			local computes = 0
			local m = core:memo(function(use)
				computes += 1
				return if use(flag) then use(x) else use(y)
			end)
			core:observe(m, function() end)
			if m:get() ~= 1 then
				return false, "initial branch wrong"
			end
			flag:set(false)
			if m:get() ~= 100 then
				return false, "post-swap branch wrong"
			end
			local before = computes
			x:set(2) -- no longer a dependency: must not recompute
			core:flush()
			if computes ~= before then
				return false, `stale dependency recomputed (computes {computes} vs {before})`
			end
			y:set(200)
			return eq(m:get(), 200)
		end,
	},
	{
		name = "cycle-reported-not-hung",
		requirement = "UI-RUNTIME-003",
		run = function(core)
			local s = core:signal(1)
			local forward: any = nil
			local m1 = core:memo(function(use)
				return use(s) + (forward ~= nil and use(forward) or 0)
			end)
			local m2 = core:memo(function(use)
				return use(m1)
			end)
			forward = m2
			-- force evaluation of the now-cyclic graph; must error/quarantine,
			-- not hang or crash the scheduler
			local _ = m1:get()
			s:set(2)
			core:flush()
			if core:lastError() == nil then
				return false, "cycle produced no diagnostic"
			end
			-- scheduler survives: unrelated state still works
			local t = core:signal(5)
			t:set(6)
			return eq(t:get(), 6)
		end,
	},
	{
		name = "write-during-memo-is-error",
		requirement = "UI-RUNTIME-003",
		run = function(core)
			local s = core:signal(1)
			local victim = core:signal(0)
			local m = core:memo(function(use)
				victim:set(99) -- illegal
				return use(s)
			end)
			local _ = m:get()
			core:flush()
			if core:lastError() == nil then
				return false, "write during memo evaluation not diagnosed"
			end
			return true, nil
		end,
	},
	{
		name = "effect-runs-post-commit-and-writes-schedule-later-round",
		requirement = "UI-RUNTIME-003",
		run = function(core)
			local a = core:signal(1)
			local b = core:signal(0)
			local order: { string } = {}
			core:observe(a, function()
				table.insert(order, "observer")
			end)
			core:effect(function(use)
				local v = use(a)
				if v == 2 and b:get() ~= v then
					b:set(v) -- effect write: must land in a later round, not recurse
				end
			end)
			a:set(2)
			core:flush()
			if b:get() ~= 2 then
				return false, `effect write lost (b={b:get()})`
			end
			if core:lastError() ~= nil then
				return false, `unexpected error: {core:lastError()}`
			end
			return true, nil
		end,
	},
	{
		name = "feedback-loop-hits-iteration-cap",
		requirement = "UI-RUNTIME-003",
		run = function(core)
			local a = core:signal(0)
			core:effect(function(use)
				local v = use(a)
				if v < 1000 then
					a:set(v + 1) -- unbounded feedback
				end
			end)
			a:set(1)
			core:flush()
			if core:lastError() == nil then
				return false, "runaway effect loop not capped/diagnosed"
			end
			return true, nil
		end,
	},
	{
		--[[ THE SETTLE PHASE (contract "a flush SETTLES before it ends";
			optimization-log L-31, 2026-08-14). The shipped consumer is a
			measure→publish cycle: a surface solves, measures itself, and publishes
			a number derived from that measurement back into the environment, where
			another surface consumes it. Before the phase existed the publication
			landed a FRAME later and opened a second flush — 2 flushes and 4 solves
			per geometry change where 1 and 2 would do.

			This case is that cycle in miniature, with no UI in it: `produce`
			settles by writing what it "measured", `consume` settles by recording
			what it saw. The property is that ONE top-level write leaves the whole
			cycle settled — `consume` must have seen the published value by the time
			`set` returns, not on some later flush. ]]
		name = "settle-runs-after-propagation-and-converges-in-one-flush",
		requirement = "UI-RUNTIME-003",
		run = function(core)
			local viewport = core:signal(100)
			local published = core:signal(0)
			local seen: { number } = {}
			local produced = 0
			-- the PRODUCER: measures the viewport, publishes a derived number
			core:settle(function()
				local want = viewport:get() // 10
				if published:get() ~= want then
					produced += 1
					published:set(want)
				end
			end)
			-- the CONSUMER: terminal work that must see the settled publication
			core:settle(function()
				local v = published:get()
				if seen[#seen] ~= v then
					table.insert(seen, v)
				end
			end)
			viewport:set(250)
			if published:get() ~= 25 then
				return false, `producer never settled (published={published:get()})`
			end
			-- the whole point: the consumer saw the SETTLED value inside the flush
			-- the write opened, not a frame later
			if seen[#seen] ~= 25 then
				return false, `consumer did not see the published value in the same flush (saw {tostring(seen[#seen])})`
			end
			-- ...and it converged: the producer published once, not once per pass
			if produced ~= 1 then
				return false, `producer published {produced} times for one change (should converge to 1)`
			end
			if core:lastError() ~= nil then
				return false, `unexpected error: {core:lastError()}`
			end
			return true, nil
		end,
	},
	{
		--[[ A SETTLE CALLBACK NEVER OBSERVES A HALF-PROPAGATED GRAPH. The contract
			says a callback that writes ENDS the pass — propagation drains and the
			pass restarts — and that clause is the difference between "every settle
			callback sees every publication" and "whichever callbacks happen to be
			registered after the writer see it".

			A memo read cannot tell the two apart (a stale memo recomputes on
			`get`), so the discriminator has to be something only propagation
			produces: an OBSERVER firing. Without the drain the consumer runs in the
			same pass as the write and reads 0 notifications; with it, the pass
			restarts and the consumer reads 1. Written this way because the first
			version of this case used a memo and passed with the drain removed. ]]
		name = "settle-callbacks-never-see-a-half-propagated-graph",
		requirement = "UI-RUNTIME-003",
		run = function(core)
			local base = core:signal(0)
			local notified = 0
			core:observe(base, function()
				notified += 1
			end)
			local sawNotified = -1
			core:settle(function()
				if base:get() < 5 then
					base:set(5)
				end
			end)
			core:settle(function()
				if sawNotified < 0 then
					sawNotified = notified
				end
			end)
			core:flush()
			if base:get() ~= 5 then
				return false, `producer never ran (base={base:get()})`
			end
			if sawNotified ~= 1 then
				return false,
					`consumer ran against a half-propagated graph: saw {sawNotified} observer notifications, expected 1`
			end
			return true, nil
		end,
	},
	{
		--[[ The negative control for the case above. Convergence is only a
			guarantee if non-convergence is an ERROR: an unbounded settle loop
			would hang the frame, and silently dropping the last publication would
			paint a number nothing settled. Same bound, same diagnosis as an effect
			feedback loop. ]]
		name = "settle-that-never-converges-hits-the-iteration-cap",
		requirement = "UI-RUNTIME-003",
		run = function(core)
			local s = core:signal(0)
			local passes = 0
			core:settle(function()
				passes += 1
				s:set(passes) -- a publication that always moves: never settles
			end)
			s:set(-1)
			core:flush()
			if passes <= 1 then
				return false, `settle phase never re-ran (passes={passes})`
			end
			if passes > 500 then
				return false, `settle phase ran unbounded ({passes} passes)`
			end
			if core:lastError() == nil then
				return false, "runaway settle loop not capped/diagnosed"
			end
			return true, nil
		end,
	},
	{
		--[[ A settle registration is a live reference the core holds to its
			registrant. Un-disposed, it outlives the surface it belongs to and
			keeps running — which is why it is COUNTED, and why the neutrality
			suites (tests/lib/fault_scenarios.luau assertBaseline) can see it. ]]
		name = "settle-unsubscribe-is-idempotent-and-counter-neutral",
		requirement = "UI-LIFE-002",
		run = function(core)
			local baseline = (core:counters() :: any).settles
			local ran = 0
			local scope = core:scope("settle")
			local stop = scope:own(core:settle(function()
				ran += 1
			end))
			if (core:counters() :: any).settles ~= baseline + 1 then
				return false, "settle registration not counted"
			end
			core:flush()
			if ran == 0 then
				return false, "settle callback never ran"
			end
			local after = ran
			scope:dispose()
			stop() -- second disposal: must be a no-op, never a double-decrement
			if (core:counters() :: any).settles ~= baseline then
				return false, `settle counter off after dispose: {(core:counters() :: any).settles} vs {baseline}`
			end
			core:flush()
			if ran ~= after then
				return false, "a disposed settle callback still ran"
			end
			return true, nil
		end,
	},
	{
		name = "memo-error-quarantined",
		requirement = "UI-RUNTIME-003",
		run = function(core)
			local s = core:signal(1)
			local bad = core:memo(function(use)
				if use(s) > 1 then
					error("boom")
				end
				return use(s)
			end)
			local good = core:memo(function(use)
				return use(s) * 2
			end)
			core:observe(bad, function() end)
			core:observe(good, function() end)
			s:set(5)
			core:flush()
			if good:get() ~= 10 then
				return false, "healthy memo corrupted by sibling failure"
			end
			if core:lastError() == nil then
				return false, "memo error not surfaced diagnostically"
			end
			return true, nil
		end,
	},
	{
		name = "scope-dispose-reverse-order-idempotent",
		requirement = "UI-LIFE-001",
		run = function(core)
			local scope = core:scope("root")
			local order: { string } = {}
			scope:own(function()
				table.insert(order, "first-owned")
			end)
			scope:own(function()
				table.insert(order, "second-owned")
			end)
			scope:dispose()
			scope:dispose() -- idempotent
			if #order ~= 2 then
				return false, `disposed {#order} resources`
			end
			if order[1] ~= "second-owned" or order[2] ~= "first-owned" then
				return false, "not reverse order: " .. table.concat(order, ",")
			end
			return eq(scope:isDisposed(), true)
		end,
	},
	{
		name = "child-scope-disposed-with-parent-borrowed-not-disposed",
		requirement = "UI-LIFE-001",
		run = function(core)
			local parent = core:scope("parent")
			local child = parent:child("child")
			local shared = core:signal(1)
			child:use(shared) -- borrowed: must survive child disposal
			local childDisposed = false
			child:own(function()
				childDisposed = true
			end)
			parent:dispose()
			if not childDisposed then
				return false, "child not disposed with parent"
			end
			if not child:isDisposed() then
				return false, "child scope not marked disposed"
			end
			shared:set(2)
			return eq(shared:get(), 2)
		end,
	},
	{
		name = "memory-neutral-churn",
		requirement = "UI-LIFE-002",
		run = function(core)
			local baseline = core:counters()
			for _ = 1, 100 do
				local scope = core:scope("churn")
				local s = scope:own(core:signal(1))
				local m = scope:own(core:memo(function(use)
					return use(s) + 1
				end))
				scope:own(core:observe(m, function() end))
				scope:own(core:effect(function(use)
					local _ = use(s)
				end))
				s:set(2)
				core:flush()
				scope:dispose()
			end
			local after = core:counters()
			for k, v in baseline :: any do
				if (after :: any)[k] ~= v then
					return false, `counter {k}: baseline {v}, after churn {(after :: any)[k]}`
				end
			end
			return true, nil
		end,
	},
	{
		-- 2026-07-19 verifier finding 1: an intermediate memo that recomputed
		-- while unobserved must not spuriously fire a later-attached observer
		-- on an unchanged recompute
		name = "no-spurious-fire-on-unchanged-recompute",
		requirement = "UI-RUNTIME-001",
		run = function(core)
			local a = core:signal(0)
			local b = core:memo(function(use)
				return math.floor(use(a) / 10)
			end)
			local c = core:memo(function(use)
				return use(b) * 1
			end)
			core:observe(c, function() end)
			a:set(10) -- b: 0 -> 1 while b itself is unobserved
			local bFires = 0
			core:observe(b, function()
				bFires += 1
			end)
			a:set(11) -- floor(11/10) == 1: b does NOT change
			core:flush()
			return eq(bFires, 0)
		end,
	},
	{
		-- verifier finding 2: no partially propagated graph observable, even
		-- to code reading derived state inside an open transaction
		name = "mid-transaction-derived-reads-fresh",
		requirement = "UI-RUNTIME-003",
		run = function(core)
			local a = core:signal(1)
			local m = core:memo(function(use)
				return use(a) * 10
			end)
			local seenInside: number? = nil
			core:transaction(function()
				a:set(5)
				seenInside = m:get()
			end)
			return eq(seenInside, 50)
		end,
	},
	{
		name = "transaction-revert-produces-no-fire",
		requirement = "UI-RUNTIME-003",
		run = function(core)
			local a = core:signal(1)
			local fires = 0
			core:observe(a, function()
				fires += 1
			end)
			core:transaction(function()
				a:set(2)
				a:set(1) -- net no change across the transaction
			end)
			return eq(fires, 0)
		end,
	},
	{
		-- type-appropriate equality (§6.2): NaN-holding signals must not
		-- refire on every equal write
		name = "nan-equal-write-skipped",
		requirement = "UI-RUNTIME-001",
		run = function(core)
			local s = core:signal(0 / 0)
			local fires = 0
			core:observe(s, function()
				fires += 1
			end)
			s:set(0 / 0)
			core:flush()
			return eq(fires, 0)
		end,
	},
	{
		-- RR-7-R1: the scope semantics the Sponsor stage CHANGED were pinned
		-- against the default core only. Every candidate shares
		-- `src/core/scope_impl.luau`, so the contract belongs here, where all
		-- three run it: a throwing cleanup is quarantined (its siblings still
		-- release), the reverse walk survives finding an already-disposed child
		-- in `owned`, and the scope counter returns to baseline through both.
		--
		-- The "early child" half USED to be written as `child:dispose()` before
		-- the parent's, which pins nothing (verifier RT-3): an early-disposed
		-- child DEREGISTERS itself from `parent.owned`, so the reverse walk never
		-- meets it and the `if not resource.disposed` guard in scope_impl is never
		-- consulted. Deleting that guard outright left the whole suite green.
		-- The live case is a cleanup closure that disposes a SIBLING child while
		-- the parent is mid-walk: the child is still in `owned` when the walk
		-- reaches it, so the guard is what keeps that from being reported as a
		-- double disposal. That is the shape pinned below.
		name = "scope-cleanup-quarantined-and-early-child-is-not-a-double-dispose",
		requirement = "UI-LIFE-001",
		run = function(core)
			local baseline = core:counters().scopes
			local scope = core:scope("q")
			local released: { string } = {}
			scope:own(function()
				table.insert(released, "first") -- runs LAST (reverse order)
			end)
			-- created BEFORE the closure that disposes it, so the reverse walk
			-- reaches the closure first and finds the child already disposed
			-- while it is still in `owned` — the guard's only live path
			local child = scope:child("early")
			scope:own(function()
				child:dispose()
			end)
			scope:own(function()
				error("cleanup boom")
			end)
			scope:own(function()
				table.insert(released, "last") -- runs FIRST
			end)
			scope:dispose()
			if released[1] ~= "last" or released[2] ~= "first" then
				return false, `healthy cleanups did not both run in reverse order: {table.concat(released, ",")}`
			end
			if core:counters().scopes ~= baseline then
				return false, `scope counter {core:counters().scopes}, baseline {baseline}`
			end
			if string.find(tostring(core:lastError()), "double disposal", 1, true) ~= nil then
				return false, "the walk reported an already-disposed child as a double disposal"
			end
			return true, nil
		end,
	},
	{
		-- §6.3: double disposal is idempotent AND detected (verifier finding 3)
		name = "double-dispose-detected",
		requirement = "UI-LIFE-001",
		run = function(core)
			local scope = core:scope("dd")
			scope:dispose()
			scope:dispose()
			if core:lastError() == nil then
				return false, "second dispose produced no diagnostic"
			end
			return true, nil
		end,
	},
	{
		-- verifier finding 6: observer set mutation during notification —
		-- a sibling disposed mid-flush must not fire; iteration stays sound
		name = "observer-disposed-by-sibling-does-not-fire",
		requirement = "UI-LIFE-001",
		run = function(core)
			local s = core:signal(1)
			local aFired, bFired = 0, 0
			local unsubB
			core:observe(s, function()
				aFired += 1
				if unsubB then
					unsubB()
				end
			end)
			unsubB = core:observe(s, function()
				bFired += 1
			end)
			s:set(2)
			core:flush()
			if aFired ~= 1 then
				return false, `a fired {aFired}`
			end
			return eq(bFired, 0)
		end,
	},
	{
		-- verifier finding 6: an observer added during notification must not
		-- receive the in-progress flush; it fires on the NEXT change
		name = "observer-added-mid-flush-fires-next-flush-only",
		requirement = "UI-RUNTIME-003",
		run = function(core)
			local s = core:signal(1)
			local lateFired = 0
			local added = false
			core:observe(s, function()
				if not added then
					added = true
					core:observe(s, function()
						lateFired += 1
					end)
				end
			end)
			s:set(2)
			core:flush()
			if lateFired ~= 0 then
				return false, `late observer fired {lateFired} in its registration flush`
			end
			s:set(3)
			core:flush()
			return eq(lateFired, 1)
		end,
	},
	{
		name = "disposed-observer-never-fires",
		requirement = "UI-LIFE-001",
		run = function(core)
			local s = core:signal(1)
			local fires = 0
			local unsub = core:observe(s, function()
				fires += 1
			end)
			unsub()
			s:set(2)
			core:flush()
			return eq(fires, 0)
		end,
	},
}

return checks
