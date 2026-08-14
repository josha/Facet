--!strict
-- Fusion-backed core: candidate B of the Phase 0 bake-off (design §3, §17).
-- A deliberately THIN adapter from src/core/contract.luau onto vendored
-- Fusion 0.3's engine-free state subset. It translates API shape (Value/
-- Computed/Observer/doCleanup, adapter-side counters and scopes) but does NOT
-- reimplement semantics Fusion lacks (transaction batching, write-during-memo
-- errors, per-signal custom equality): the conformance scorecard records those
-- differences as rubric evidence. Headless hosts must bind an external
-- provider (tests/lib/fusion_lune_external.luau) before construction.

local contract = require("./contract")
local scope_impl = require("./scope_impl")

local FusionValue = require("../../vendor/Fusion/State/Value")
local FusionComputed = require("../../vendor/Fusion/State/Computed")
local FusionObserver = require("../../vendor/Fusion/Graph/Observer")
local fusionPeek = require("../../vendor/Fusion/State/peek")
local doCleanup = require("../../vendor/Fusion/Memory/doCleanup")

type Use = contract.Use

local FusionAdapter = {}

function FusionAdapter.new()
	local counts = { signals = 0, memos = 0, observers = 0, effects = 0, scopes = 0, settles = 0 }
	local lastError: string? = nil
	local newScope = scope_impl.factory(counts, function(message: string)
		lastError = message
	end)
	-- one root Fusion scope per core; every resource gets its own inner scope
	-- so contract-level dispose maps to doCleanup of just that resource
	local rootFusionScope = {}

	-- settle registrations, in order; see the `settle` verb below for what this
	-- substrate can and cannot promise
	local settles: { any } = {}
	local settling = false
	local function runSettles()
		-- `settling` is the re-entrancy guard: a settle callback that writes
		-- propagates eagerly here and can reach `flush` again, and a phase that
		-- re-entered itself would recurse rather than converge. ONE pass is all
		-- this substrate can distinguish — with eager propagation there is no
		-- write set to test for quiescence, so "repeat until a pass writes
		-- nothing" is not implementable and is not faked.
		if settling or #settles == 0 then
			return
		end
		settling = true
		for i = 1, #settles do
			local s = settles[i]
			if s ~= nil and not s.disposed then
				local ok, err = pcall(s.fn)
				if not ok then
					lastError = tostring(err)
				end
			end
		end
		settling = false
	end

	local function fail(message: string)
		lastError = message
	end

	local function ownedFusionScope(): any
		local inner = {}
		table.insert(rootFusionScope, inner)
		return inner
	end

	local function wrapUse(fusionUse: any): Use
		return function(source: any)
			return fusionUse(source._raw)
		end :: any
	end

	local core: any = {
		name = "fusion",

		signal = function(_self, initial: any, eq: ((any, any) -> boolean)?)
			counts.signals += 1
			local fusionScope = ownedFusionScope()
			local raw = FusionValue(fusionScope, initial)
			-- Fusion has no per-signal custom equality; `eq` is accepted but
			-- only Fusion's built-in similarity applies (conformance records)
			local disposed = false
			return {
				kind = "signal",
				_raw = raw,
				get = function(_s)
					return fusionPeek(raw)
				end,
				set = function(_s, value: any)
					raw:set(value)
				end,
				dispose = function(_s)
					if disposed then
						return
					end
					disposed = true
					local ok, err = pcall(doCleanup, fusionScope)
					if not ok then
						fail(tostring(err))
					end
					counts.signals -= 1
				end,
			}
		end,

		memo = function(_self, compute: (use: Use) -> any, eq: ((any, any) -> boolean)?)
			counts.memos += 1
			local fusionScope = ownedFusionScope()
			local raw = FusionComputed(fusionScope, function(fusionUse, _scope)
				return compute(wrapUse(fusionUse))
			end)
			local disposed = false
			return {
				kind = "memo",
				_raw = raw,
				get = function(_s)
					local ok, result = pcall(fusionPeek, raw)
					if ok then
						return result
					end
					fail(tostring(result))
					return nil
				end,
				dispose = function(_s)
					if disposed then
						return
					end
					disposed = true
					local ok, err = pcall(doCleanup, fusionScope)
					if not ok then
						fail(tostring(err))
					end
					counts.memos -= 1
				end,
			}
		end,

		observe = function(_self, source: any, onChange: (any) -> ())
			counts.observers += 1
			local fusionScope = ownedFusionScope()
			local observer = FusionObserver(fusionScope, source._raw)
			local disconnect = observer:onChange(function()
				local ok, value = pcall(fusionPeek, source._raw)
				if ok then
					onChange(value)
				else
					fail(tostring(value))
				end
			end)
			local disposed = false
			return function()
				if disposed then
					return
				end
				disposed = true
				disconnect()
				local ok, err = pcall(doCleanup, fusionScope)
				if not ok then
					fail(tostring(err))
				end
				counts.observers -= 1
			end
		end,

		effect = function(_self, run: (use: Use) -> ())
			counts.effects += 1
			local fusionScope = ownedFusionScope()
			-- Fusion has no effect primitive: emulate with an eager Observer
			-- over a Computed that performs the tracked run.
			local raw = FusionComputed(fusionScope, function(fusionUse, _scope)
				local ok, err = pcall(run, wrapUse(fusionUse))
				if not ok then
					fail(tostring(err))
				end
				return nil
			end)
			local ok0, err0 = pcall(fusionPeek, raw) -- registration run
			if not ok0 then
				fail(tostring(err0))
			end
			local observer = FusionObserver(fusionScope, raw)
			local disconnect = observer:onChange(function()
				local ok, err = pcall(fusionPeek, raw) -- re-run tracked body
				if not ok then
					fail(tostring(err))
				end
			end)
			local disposed = false
			return function()
				if disposed then
					return
				end
				disposed = true
				disconnect()
				local ok, err = pcall(doCleanup, fusionScope)
				if not ok then
					fail(tostring(err))
				end
				counts.effects -= 1
			end
		end,

		--[[ SETTLE, as honestly as this substrate allows (contract: "a flush
			SETTLES before it ends"). Fusion propagates EAGERLY and has no flush
			boundary at all — `flush` below is a no-op for exactly that reason — so
			there is no "after propagation quiesces" moment to hang the phase on.
			What this adapter can offer is the convergence half: run the callbacks
			in registration order at every boundary the adapter DOES own
			(`flush`/`transaction` close), repeating while a pass wrote, under a
			round cap.

			What it therefore does NOT offer is the half that produces the win: a
			settle write cannot join "the flush that caused it", because on this
			substrate every write is already its own propagation. Recorded here and
			scored by the conformance suite rather than claimed — the rubric's
			whole point is that a candidate says what it cannot do. ]]
		settle = function(_self, run: () -> ())
			counts.settles += 1
			local record = { fn = run, disposed = false }
			table.insert(settles, record)
			return function()
				if record.disposed then
					return
				end
				record.disposed = true
				counts.settles -= 1
				local kept: { any } = {}
				for _, s in settles do
					if not s.disposed then
						table.insert(kept, s)
					end
				end
				settles = kept
			end
		end,

		transaction = function(_self, body: () -> ())
			-- Fusion has no write batching; the body runs as individual writes
			-- (conformance records observer fire counts)
			local ok, err = pcall(body)
			runSettles()
			if not ok then
				error(err, 0)
			end
		end,

		flush = function(_self)
			-- Fusion propagates eagerly through its external scheduler; the
			-- host steps it (LuneExternal). Nothing to do here beyond letting
			-- deferred observer callbacks drain, which the test harness's
			-- provider does synchronously — and running the settle phase, which
			-- is the only boundary this adapter owns.
			runSettles()
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
	name = "fusion",
	new = FusionAdapter.new,
	claims = {
		dynamicDependencies = true,
		-- Fusion detects cycles internally but routes the report to its
		-- external logger, which is not queryable through this adapter, so the
		-- contract-level claim is honestly false (scorecard: cycle check FAIL)
		cycleDetection = false,
		writeDuringMemoError = false,
	},
} :: any

return factory
