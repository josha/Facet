--!strict
-- Retained imperative baseline: candidate C of the Phase 0 bake-off (design
-- §3, §17). Models the pattern the games use today (pure model recompute +
-- diffed apply): signals with observer lists, and "memos" recomputed IN
-- CREATION ORDER on every commit (recompute-the-model), with eq suppression
-- for unchanged values. No dependency tracking, no laziness, no cycle or
-- write-during-memo detection — deliberately, so the rubric measures what the
-- simple approach actually gives up (update cost, dynamic-dep skips,
-- diagnostics) and keeps (glitch-freedom via ordered recompute, batching).

local contract = require("./contract")
local scope_impl = require("./scope_impl")

type Use = contract.Use

local COMMIT_ROUND_CAP = 20

local function defaultEq(a: any, b: any): boolean
	return a == b
end

local Imperative = {}

function Imperative.new()
	local counts = { signals = 0, memos = 0, observers = 0, effects = 0, scopes = 0 }
	local lastError: string? = nil
	local newScope = scope_impl.factory(counts, function(message: string)
		lastError = message
	end)
	local txDepth = 0
	local committing = false
	local dirty = false
	local memos: { any } = {} -- creation order; recompute-all per commit
	local signals: { any } = {}
	local effects: { any } = {}
	local commit

	local function fail(message: string)
		lastError = message
	end

	-- use() just reads: no tracking in the baseline
	local useRead: Use = function(source: any)
		return source:get()
	end :: any

	local function fireObservers(node: any)
		for observer in node.observers do
			if not observer.disposed then
				observer.fn(node.value)
			end
		end
	end

	commit = function()
		if committing then
			return
		end
		committing = true
		local rounds = 0
		while dirty do
			rounds += 1
			if rounds > COMMIT_ROUND_CAP then
				fail(`imperative: commit exceeded {COMMIT_ROUND_CAP} rounds (effect feedback loop?)`)
				dirty = false
				break
			end
			dirty = false
			-- 1. recompute every live memo in creation order
			for _, memo in memos do
				if not memo.disposed then
					local ok, result = pcall(memo.compute, useRead)
					if ok then
						if not memo.eq(memo.value, result) then
							memo.value = result
							memo.changed = true
						end
					else
						fail(tostring(result))
					end
				end
			end
			-- 2. fire observers of changed nodes: signals flagged at write,
			-- then memos, so derived views observe after their sources
			for _, signal in signals do
				if signal.changed and not signal.disposed then
					signal.changed = false
					fireObservers(signal)
				end
			end
			for _, memo in memos do
				if memo.changed and not memo.disposed then
					memo.changed = false
					fireObservers(memo)
				end
			end
			-- 3. run every live effect (baseline has no dep tracking); their
			-- writes set `dirty` and run another round
			for _, effect in effects do
				if not effect.disposed then
					local ok, err = pcall(effect.fn, useRead)
					if not ok then
						fail(tostring(err))
					end
				end
			end
		end
		committing = false
	end

	local core: any = {
		name = "imperative",

		signal = function(_self, initial: any, eq: ((any, any) -> boolean)?)
			counts.signals += 1
			local node: any = {
				kind = "signal",
				value = initial,
				eq = eq or defaultEq,
				observers = {},
				disposed = false,
			}
			function node.get(_s)
				return node.value
			end
			function node.set(_s, value: any)
				if node.eq(node.value, value) then
					return
				end
				node.value = value
				node.changed = true
				dirty = true
				if committing or txDepth > 0 then
					return
				end
				commit()
			end
			function node.dispose(_s)
				if node.disposed then
					return
				end
				node.disposed = true
				node.observers = {}
				counts.signals -= 1
			end
			table.insert(signals, node)
			return node
		end,

		memo = function(_self, compute: (use: Use) -> any, eq: ((any, any) -> boolean)?)
			counts.memos += 1
			local node: any = {
				kind = "memo",
				value = nil,
				eq = eq or defaultEq,
				compute = compute,
				observers = {},
				changed = false,
				disposed = false,
			}
			local ok, result = pcall(compute, useRead)
			if ok then
				node.value = result
			else
				fail(tostring(result))
			end
			function node.get(_s)
				-- pull-recompute so reads outside commits stay fresh
				local ok2, result2 = pcall(node.compute, useRead)
				if ok2 then
					if not node.eq(node.value, result2) then
						node.value = result2
					end
				else
					fail(tostring(result2))
				end
				return node.value
			end
			function node.dispose(_s)
				if node.disposed then
					return
				end
				node.disposed = true
				node.observers = {}
				counts.memos -= 1
			end
			table.insert(memos, node)
			return node
		end,

		observe = function(_self, source: any, onChange: (any) -> ())
			counts.observers += 1
			local observer = { fn = onChange, disposed = false }
			source.observers[observer] = true
			return function()
				if observer.disposed then
					return
				end
				observer.disposed = true
				source.observers[observer] = nil
				counts.observers -= 1
			end
		end,

		effect = function(_self, run: (use: Use) -> ())
			counts.effects += 1
			local effect = { fn = run, disposed = false }
			-- register BEFORE the first run so a registration-time write that
			-- triggers a commit still reaches this effect under the round cap
			table.insert(effects, effect)
			local ok, err = pcall(run, useRead)
			if not ok then
				fail(tostring(err))
			end
			if dirty and not committing and txDepth == 0 then
				commit()
			end
			return function()
				if effect.disposed then
					return
				end
				effect.disposed = true
				counts.effects -= 1
			end
		end,

		transaction = function(_self, body: () -> ())
			txDepth += 1
			local ok, err = pcall(body)
			txDepth -= 1
			if txDepth == 0 and dirty then
				commit()
			end
			if not ok then
				error(err, 0)
			end
		end,

		flush = function(_self)
			if dirty then
				commit()
			end
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
	name = "imperative",
	new = Imperative.new,
	claims = {
		dynamicDependencies = false,
		cycleDetection = false,
		writeDuringMemoError = false,
	},
} :: any

return factory
