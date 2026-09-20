--!strict
local harness = require("./lib/harness")
local t = require("./lib/testkit")
local factory = harness.coreFactory
local Compose = require("../src/vendor/compose/core")
local observeChange = require("../src/core/on_change")

t.describe("native Compose scheduling contracts", function()
	t.it("delivers in dependency registration order across separately created memos", function()
		local core = factory.new()
		local source = Compose.cell(0)
		local first = Compose.formula(function(use)
			return use(source)
		end)
		local second = Compose.formula(function(use)
			return use(source)
		end)
		local seen = {}
		observeChange(core.owner, second, function()
			table.insert(seen, 2)
		end)
		observeChange(core.owner, first, function()
			table.insert(seen, 1)
		end)
		source:set(1)
		source:set(2)
		t.expect(seen).toEqual({ 2, 1, 2, 1 })
	end)

	t.it("retains reached dependencies after a failed change in read sequence", function()
		local Graph = require("../src/vendor/compose/core/reactive/graph")
		local core = factory.new({ warn = function() end })
		local choose, a, b = Compose.cell(false), Compose.cell(1), Compose.cell(10)
		local broken = false
		local value = Compose.formula(function(use)
			local result = use(if use(choose) then b else a)
			if broken then
				error("changed read sequence")
			end
			return result
		end)
		t.expect(value:peek()).toBe(1)
		broken = true
		choose:set(true)
		--[[ THE FAILURE REACHES THE READER, and the EDGES are what survives it:
			Compose keeps the dependencies the failing run reached, so the node is
			still reachable from them and a later change can mark it stale. What it
			does not do is answer the previous value — a caller that wants the last
			good answer holds it (`layout/adaptive.luau`'s `fits` is the shipped
			example, and it is the helper's own job there, not the graph's). ]]
		t.expect(pcall(function()
			return value:peek()
		end)).toBe(false)
		t.expect(Graph.subscriberCount(a)).toBe(0)
		t.expect(Graph.subscriberCount(b)).toBe(1)
		broken = false
		b:set(20)
		t.expect(value:peek()).toBe(20)
		value:dispose()
		t.expect(Graph.subscriberCount(b)).toBe(0)
	end)
end)
