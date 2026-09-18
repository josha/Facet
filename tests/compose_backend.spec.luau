--!strict
local t = require("./lib/testkit")
local factory = require("../src/core/compose")
local suite = require("./conformance/suite")

t.describe("Compose backend core conformance", function()
	for _, check in suite do
		t.it(check.name, function()
			local ok, note = check.run(factory.new({ warn = function() end }))
			if not ok then
				print(note)
			end
			t.expect(ok).toBe(true)
		end)
	end
end)

t.describe("native Compose scheduling contracts", function()
	t.it("delivers in dependency registration order across separately created memos", function()
		local core = factory.new()
		local source = core:signal(0)
		local first = core:memo(function(use)
			return use(source)
		end)
		local second = core:memo(function(use)
			return use(source)
		end)
		local seen = {}
		core:observe(second, function()
			table.insert(seen, 2)
		end)
		core:observe(first, function()
			table.insert(seen, 1)
		end)
		source:set(1)
		source:set(2)
		t.expect(seen).toEqual({ 2, 1, 2, 1 })
	end)

	t.it("retains reached dependencies after a failed change in read sequence", function()
		local Graph = require("../src/vendor/compose/reactive/graph")
		local core = factory.new({ warn = function() end })
		local choose, a, b = core:signal(false), core:signal(1), core:signal(10)
		local broken = false
		local value = core:memo(function(use)
			local result = use(if use(choose) then b else a)
			if broken then
				error("changed read sequence")
			end
			return result
		end)
		t.expect(value:get()).toBe(1)
		broken = true
		choose:set(true)
		t.expect(value:get()).toBe(1)
		t.expect(Graph.subscriberCount(a)).toBe(0)
		t.expect(Graph.subscriberCount(b)).toBe(1)
		broken = false
		b:set(20)
		t.expect(value:get()).toBe(20)
		value:dispose()
		t.expect(Graph.subscriberCount(b)).toBe(0)
	end)
end)
