--!strict
-- Scheduler fuzz case (design §15.2; UI-RUNTIME-001/003, UI-LIFE-002): builds
-- a random signal/memo graph mirrored by a pure model, drives it with random
-- writes, transactions (including set-then-revert), observer/effect churn,
-- and mid-run memo creation, then checks after every quiescent point:
--   * every memo :get() equals the model's expected value (glitch-free);
--   * observers fired only on real change (no consecutive equal values), and
--     their last fired value is the model value (set-then-revert fires 0);
--   * core:lastError() stays nil for these legal programs;
--   * full teardown returns every registry counter to the fresh-core baseline.
-- Legal programs only — illegal ops (cycles, writes-in-memo) are fault
-- injection's job (tests/faults.spec.luau).

local customCore = require("../../../src/core/custom")
local prng = require("../prng")

type Prng = prng.Prng

local scheduler_fuzzer = {}

type ModelNode = {
	kind: string, -- "signal" | "memo"
	readable: any,
	value: number?, -- signal only: model value
	deps: { number }?, -- memo only: indices into nodes
	constant: number?, -- memo only
	op: string?, -- memo only: "sum" | "diff" | "scaled"
	disposed: boolean,
}

local function expected(nodes: { ModelNode }, index: number): number
	local node = nodes[index]
	if node.kind == "signal" then
		return node.value :: number
	end
	local acc = node.constant :: number
	for position, dep in node.deps :: { number } do
		local v = expected(nodes, dep)
		if node.op == "diff" and position % 2 == 0 then
			acc -= v
		elseif node.op == "scaled" then
			acc += 2 * v
		else
			acc += v
		end
	end
	return acc
end

type Observer = {
	nodeIndex: number,
	fired: { number },
	unsubscribe: () -> (),
	live: boolean,
}

function scheduler_fuzzer.case(rng: Prng)
	local core = (customCore :: any).new()
	local baseline = core:counters()
	local nodes: { ModelNode } = {}
	local observers: { Observer } = {}
	local effects: { { dispose: () -> (), live: boolean } } = {}
	local effectLog: { number } = {}

	local function addSignal()
		local value = rng:range(-50, 50)
		local readable = core:signal(value)
		table.insert(nodes, { kind = "signal", readable = readable, value = value, disposed = false })
	end

	local function addMemo()
		if #nodes == 0 then
			return
		end
		local deps: { number } = {}
		local seen: { [number]: boolean } = {}
		for _ = 1, rng:range(1, math.min(3, #nodes)) do
			local dep = rng:range(1, #nodes)
			if not seen[dep] then
				seen[dep] = true
				table.insert(deps, dep)
			end
		end
		local constant = rng:range(-10, 10)
		local op = rng:pick({ "sum", "diff", "scaled" })
		local depReadables = {}
		for _, dep in deps do
			table.insert(depReadables, nodes[dep].readable)
		end
		local readable = core:memo(function(use)
			local acc = constant
			for position, depReadable in depReadables :: { any } do
				local v = use(depReadable)
				if op == "diff" and position % 2 == 0 then
					acc -= v
				elseif op == "scaled" then
					acc += 2 * v
				else
					acc += v
				end
			end
			return acc
		end)
		table.insert(
			nodes,
			{ kind = "memo", readable = readable, deps = deps, constant = constant, op = op, disposed = false }
		)
	end

	local function addObserver()
		local index = rng:range(1, #nodes)
		local observer: Observer = { nodeIndex = index, fired = {}, unsubscribe = nil :: any, live = true }
		observer.unsubscribe = core:observe(nodes[index].readable, function(value)
			table.insert(observer.fired, value)
		end)
		table.insert(observers, observer)
	end

	local function addEffect()
		local index = rng:range(1, #nodes)
		local readable = nodes[index].readable
		local handle = { dispose = nil :: any, live = true }
		handle.dispose = core:effect(function(use)
			table.insert(effectLog, use(readable))
		end)
		table.insert(effects, handle)
	end

	local function liveSignalIndices(): { number }
		local list = {}
		for i, node in nodes do
			if node.kind == "signal" and not node.disposed then
				table.insert(list, i)
			end
		end
		return list
	end

	local function checkInvariants(context: string)
		local coreError = core:lastError()
		if coreError ~= nil then
			error(`[{context}] core reported an internal error for a legal program: {coreError}`)
		end
		for i, node in nodes do
			if node.kind == "memo" and not node.disposed then
				local got = node.readable:get()
				local want = expected(nodes, i)
				if got ~= want then
					error(`[{context}] memo #{i} glitch: got {got}, model expects {want}`)
				end
			end
		end
		for oi, observer in observers do
			local fired = observer.fired
			for k = 2, #fired do
				if fired[k] == fired[k - 1] then
					error(`[{context}] observer #{oi} fired twice with equal value {fired[k]}`)
				end
			end
			if observer.live and #fired > 0 and not nodes[observer.nodeIndex].disposed then
				local want = expected(nodes, observer.nodeIndex)
				if fired[#fired] ~= want then
					error(`[{context}] observer #{oi} last fire {fired[#fired]} != model {want}`)
				end
			end
		end
	end

	-- seed graph: 1-4 signals, 0-5 memos, some observers
	for _ = 1, rng:range(1, 4) do
		addSignal()
	end
	for _ = 1, rng:range(0, 5) do
		if rng:bool(0.7) then
			addMemo()
		else
			addSignal()
		end
	end
	for _ = 1, rng:range(0, 3) do
		addObserver()
	end
	checkInvariants("after-build")

	-- drive: 5-30 random operations
	for step = 1, rng:range(5, 30) do
		local roll = rng:range(1, 100)
		if roll <= 30 then
			-- plain write (sometimes an equal write, which must fire nothing)
			local signals = liveSignalIndices()
			if #signals > 0 then
				local index = rng:pick(signals)
				local node = nodes[index]
				local value = if rng:bool(0.15) then node.value :: number else rng:range(-50, 50)
				node.value = value
				node.readable:set(value)
			end
		elseif roll <= 55 then
			-- transaction: several writes; sometimes revert one; read a memo mid-tx
			local signals = liveSignalIndices()
			if #signals > 0 then
				local revert = rng:bool(0.3)
				local midTxMemo: number? = nil
				for i, node in nodes do
					if node.kind == "memo" and not node.disposed and rng:bool(0.3) then
						midTxMemo = i
						break
					end
				end
				core:transaction(function()
					local touched: { { index: number, before: number } } = {}
					for _ = 1, rng:range(1, 3) do
						local index = rng:pick(signals)
						local node = nodes[index]
						table.insert(touched, { index = index, before = node.value :: number })
						local value = rng:range(-50, 50)
						node.value = value
						node.readable:set(value)
					end
					if midTxMemo ~= nil then
						-- reads inside an open transaction see fresh derived state
						local got = nodes[midTxMemo].readable:get()
						local want = expected(nodes, midTxMemo)
						if got ~= want then
							error(`mid-transaction memo read got {got}, model expects {want}`)
						end
					end
					if revert and #touched > 0 then
						local target = touched[#touched]
						nodes[target.index].value = target.before
						nodes[target.index].readable:set(target.before)
					end
				end)
			end
		elseif roll <= 65 then
			addMemo()
		elseif roll <= 75 then
			addObserver()
		elseif roll <= 82 then
			-- retire a random live observer
			for _, observer in observers do
				if observer.live then
					if rng:bool(0.5) then
						observer.unsubscribe()
						observer.live = false
						break
					end
				end
			end
		elseif roll <= 90 then
			addEffect()
		elseif roll <= 95 then
			for _, handle in effects do
				if handle.live then
					if rng:bool(0.5) then
						handle.dispose()
						handle.live = false
						break
					end
				end
			end
		else
			addSignal()
		end
		checkInvariants(`step-{step}`)
	end

	-- teardown in safe order: observers, effects, memos (reverse), signals
	for _, observer in observers do
		if observer.live then
			observer.unsubscribe()
			observer.live = false
		end
	end
	for _, handle in effects do
		if handle.live then
			handle.dispose()
			handle.live = false
		end
	end
	for i = #nodes, 1, -1 do
		if nodes[i].kind == "memo" then
			nodes[i].readable:dispose()
			nodes[i].disposed = true
		end
	end
	for i = #nodes, 1, -1 do
		if nodes[i].kind == "signal" then
			nodes[i].readable:dispose()
			nodes[i].disposed = true
		end
	end

	local after = core:counters()
	for key, value in baseline :: { [string]: number } do
		if after[key] ~= value then
			error(`registry '{key}' not at baseline after teardown: {after[key]} != {value}`)
		end
	end
	if core:lastError() ~= nil then
		error(`core error after teardown: {core:lastError()}`)
	end
end

return scheduler_fuzzer
