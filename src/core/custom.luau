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
local scope_impl = require("./scope_impl")

type Use = contract.Use

-- Rounds are effect-write generations, not graph depth; 100 permits deep
-- legitimate effect chains while still catching true feedback loops. Hitting
-- the cap reports how many writes were discarded (verifier finding 5).
local FEEDBACK_ROUND_CAP = 100

type Node = {
	kind: string, -- "signal" | "memo"
	name: string?,
	value: any,
	eq: (any, any) -> boolean,
	subs: { [any]: boolean }, -- dependent memos/effects
	observers: { [any]: boolean }, -- observer records {fn, seq, lastSeen, disposed}
	stale: boolean, -- memo only
	evaluating: boolean, -- memo only (cycle detection)
	failed: boolean, -- memo only
	compute: ((use: Use) -> any)?,
	deps: { [Node]: boolean }, -- memo only
	disposed: boolean,
}

-- NaN-safe default equality (NaN ~= NaN would refire on every equal write)
local function defaultEq(a: any, b: any): boolean
	return a == b or (a ~= a and b ~= b)
end

local Custom = {}

function Custom.new()
	local core: any
	local counts = { signals = 0, memos = 0, observers = 0, effects = 0, scopes = 0 }
	local txDepth = 0
	local flushing = false
	local writeSet: { [Node]: boolean } = {}
	local evalStack: { Node } = {}
	local evaluatingMemo = false
	local inEffectRun = false
	local lastError: string? = nil
	local observerSeq = 0

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
			fail(`LuauUI: equality callback error quarantined: {tostring(result)}`)
			return false
		end
		return result == true
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
				table.insert(path, n.name or "memo")
			end
			table.insert(path, node.name or "memo")
			error(`LuauUI cycle: {table.concat(path, " -> ")}`, 0)
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
			return pull(dep)
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
			node.value = result
		else
			node.stale = false -- avoid re-erroring every pull until next invalidation
			node.failed = true
			fail(tostring(result))
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
		effect.deps = newDeps
		for dep in newDeps do
			dep.subs[effect] = true
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
			error("LuauUI: writing state during memo evaluation is an error", 0)
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

	flush = function()
		if flushing then
			return
		end
		flushing = true
		local rounds = 0
		while next(writeSet) ~= nil do
			rounds += 1
			if rounds > FEEDBACK_ROUND_CAP then
				local dropped = 0
				for _ in writeSet do
					dropped += 1
				end
				fail(
					`LuauUI: flush exceeded the {FEEDBACK_ROUND_CAP}-round iteration cap (effect feedback loop?); {dropped} pending signal write(s) discarded`
				)
				writeSet = {}
				break
			end
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
		flushing = false
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

	core = {
		name = "custom",

		signal = function(_self, initial: any, eq: ((any, any) -> boolean)?)
			counts.signals += 1
			local node: Node = {
				kind = "signal",
				value = initial,
				eq = eq or defaultEq,
				subs = {},
				observers = {},
				stale = false,
				evaluating = false,
				failed = false,
				compute = nil,
				deps = {},
				disposed = false,
			}
			return makeReadable(node)
		end,

		memo = function(_self, compute: (use: Use) -> any, eq: ((any, any) -> boolean)?)
			counts.memos += 1
			local node: Node = {
				kind = "memo",
				value = nil,
				eq = eq or defaultEq,
				subs = {},
				observers = {},
				stale = true,
				evaluating = false,
				failed = false,
				compute = compute,
				deps = {},
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
				local ok = pcall(pull, node)
				if not ok then
					node.failed = true
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

		transaction = function(_self, body: () -> ())
			txDepth += 1
			local ok, err = pcall(body)
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
