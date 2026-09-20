--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local Graph = require("../src/vendor/compose/core/reactive/graph")

t.describe("native Compose lifetime and recovery", function()
	t.it("detaches the final direct listener, including repeated subscribe cycles", function()
		local owner = Compose.createOwner(Compose.reactor())
		local source = Compose.cell(0)
		for _ = 1, 5 do
			local stop = owner.watchStatic(source, function() end)
			t.expect(Graph.subscriberCount(source)).toBe(1)
			stop()
			t.expect(Graph.subscriberCount(source)).toBe(0)
		end
		owner.dispose()
	end)

	t.it("reads after self-disposal do not resurrect dependency edges", function()
		local owner = Compose.createOwner(Compose.reactor())
		local source, later = Compose.cell(0), Compose.cell(10)
		local runs = 0
		local stop
		stop = owner.watch(function(use)
			runs += 1
			if use(source) == 1 then
				stop()
				use(later)
			end
		end)
		source:set(1)
		t.expect(Graph.subscriberCount(source)).toBe(0)
		t.expect(Graph.subscriberCount(later)).toBe(0)
		later:set(20)
		t.expect(runs).toBe(2)
		owner.dispose()
	end)

	t.it("a watch abandoned at the native drain cap wakes on the next write", function()
		local reactor = Compose.reactor()
		local owner = Compose.createOwner(reactor)
		local source = Compose.cell(0)
		local looping = false
		local seen = -1
		local stop = owner.watch(function(use)
			seen = use(source)
			if looping then
				source:set(seen + 1)
			end
		end)
		looping = true
		local ok = pcall(function()
			source:set(1)
		end)
		t.expect(ok).toBe(false)
		t.expect(reactor:pending()).toBe(0)
		-- The same subscription wakes after feedback stops; no replacement watch.
		looping = false
		source:set(-2)
		t.expect(seen).toBe(-2)
		owner.dispose()
		t.expect(Graph.subscriberCount(source)).toBe(0)
	end)
end)
return t
