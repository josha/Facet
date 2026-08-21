--!strict
--[[ T15 probe (RR-12): what does ONE reactive flush allocate, and does it show?

	LUNE HAS NO FORCED COLLECTION (`collectgarbage` accepts only "count", and
	tools/lune/bench.luau's header records what a single gcinfo pair is worth
	here: a sign that flips and a magnitude that overstates ~17x). So heap NET is
	useless for an allocation RATE.

	The estimator instead: `gcinfo()` rises monotonically between collections, so
	sample it every WINDOW flushes and sum only the POSITIVE window deltas. A
	collection inside a window shows as a negative delta and is dropped, which
	makes this a LOWER BOUND on allocation — never an overstatement. The window is
	sized so one window's allocation is far above gcinfo's 1 KB quantum.

	Beside it, the per-flush TIME, which is what a frame actually pays. Throwaway.
]]
local Facet = require("../../src")

local WINDOW = 200

local function measure(label: string, setup: () -> (any, () -> ()), flushes: number)
	local state, doFlush = setup()
	for _ = 1, WINDOW * 2 do
		doFlush()
	end
	local allocKb = 0
	local last = gcinfo()
	local t0 = os.clock()
	for i = 1, flushes do
		doFlush()
		if i % WINDOW == 0 then
			local now = gcinfo()
			if now > last then
				allocKb += now - last
			end
			last = now
		end
	end
	local ms = (os.clock() - t0) * 1000 / flushes
	local bytes = allocKb * 1024 / flushes
	print(
		`{label}: >= {string.format("%.0f", bytes)} B/flush, {string.format("%.4f", ms)} ms/flush `
			.. `({flushes} flushes)`
	)
	local _ = state
	return bytes, ms
end

measure("bare signal, no subscriber", function()
	local core = Facet.newCore()
	local s = core:signal(0)
	local i = 0
	return core, function()
		i += 1
		s:set(i)
	end
end, 40000)

measure("1 signal + 1 observer", function()
	local core = Facet.newCore()
	local s = core:signal(0)
	core:observe(s, function() end)
	local i = 0
	return core, function()
		i += 1
		s:set(i)
	end
end, 40000)

for _, count in { 10, 50 } do
	measure(`{count} observed memos on one signal`, function()
		local core = Facet.newCore()
		local s = core:signal(0)
		for k = 1, count do
			local m = core:memo(function(use)
				return (use(s) :: number) + k
			end)
			core:observe(m, function() end)
		end
		local i = 0
		return core, function()
			i += 1
			s:set(i)
		end
	end, 20000)
end

measure("50-deep memo chain", function()
	local core = Facet.newCore()
	local s = core:signal(0)
	local node: any = s
	for _ = 1, 50 do
		local upstream = node
		node = core:memo(function(use)
			return (use(upstream) :: number) + 1
		end)
	end
	core:observe(node, function() end)
	local i = 0
	return core, function()
		i += 1
		s:set(i)
	end
end, 20000)

measure("transaction of 20 writes (ONE flush)", function()
	local core = Facet.newCore()
	local sigs = {}
	for _ = 1, 20 do
		local sg = core:signal(0)
		table.insert(sigs, sg)
		core:observe(sg, function() end)
	end
	local i = 0
	return core,
		function()
			i += 1
			core:transaction(function()
				for _, sg in sigs do
					sg:set(i)
				end
			end)
		end
end, 20000)
