--!strict
local t = require("./lib/testkit")
local factory = require("../src/core/compose")

-- Inspect retained ownership without depending on the list representation or
-- on a collector cycle. Scope methods/closures are shared and excluded.
local function reachable(root: any): { [any]: boolean }
	local seen = {}
	local pending = { root }
	while #pending > 0 do
		local value = table.remove(pending)
		if type(value) == "table" and not seen[value] then
			seen[value] = true
			for _, child in value do
				table.insert(pending, child)
			end
		end
	end
	return seen
end

t.describe("scope ownership", function()
	t.it("removing first, middle and last children preserves mixed cleanup order", function()
		local core = factory.new()
		local parent = core:scope("parent")
		local order = {}
		local children = {}
		for i = 1, 5 do
			children[i] = parent:child(tostring(i))
			children[i]:own(function()
				table.insert(order, tostring(i))
			end)
			if i == 1 then
				parent:own(function()
					table.insert(order, "function")
				end)
			elseif i == 3 then
				parent:own({
					dispose = function()
						table.insert(order, "object")
					end,
				})
			end
		end
		for _, i in { 3, 1, 5 } do
			children[i]:dispose()
		end
		t.expect(core:counters().scopes).toBe(3)
		parent:dispose()
		t.expect(order).toEqual({ "3", "1", "5", "4", "object", "2", "function" })
		t.expect(core:counters().scopes).toBe(0)
		t.expect(core:lastError()).toBeNil()
	end)

	t.it("a cleanup can remove adjacent and distant siblings while the parent drains", function()
		local core = factory.new({ warn = function() end })
		local parent = core:scope()
		local order = {}
		local children = {}
		for i = 1, 4 do
			children[i] = parent:child()
			children[i]:own(function()
				table.insert(order, i)
			end)
		end
		parent:own(function()
			children[4]:dispose()
			children[1]:dispose()
			error("cleanup boom")
		end)
		parent:dispose()
		t.expect(order).toEqual({ 4, 1, 3, 2 })
		t.expect(core:counters().scopes).toBe(0)
		t.expect(string.find(tostring(core:lastError()), "cleanup boom", 1, true) ~= nil).toBe(true)
		t.expect(string.find(tostring(core:lastError()), "double disposal", 1, true)).toBeNil()
	end)

	t.it("a child cleanup may dispose its parent without releasing anything twice", function()
		local core = factory.new()
		local parent = core:scope()
		local child = parent:child()
		local order = {}
		child:own(function()
			table.insert(order, "child start")
			parent:dispose()
			table.insert(order, "child end")
		end)
		parent:own(function()
			table.insert(order, "parent")
		end)
		child:dispose()
		t.expect(order).toEqual({ "child start", "parent", "child end" })
		t.expect(core:counters().scopes).toBe(0)
		t.expect(core:lastError()).toBeNil()
	end)

	t.it("churn retains only live ownership and an emptied parent can be reused", function()
		local core = factory.new()
		local parent = core:scope()
		local initial = reachable(parent)
		local ownedBefore = parent.native.size()
		local releases = 0
		for _ = 1, 1000 do
			local child = parent:child()
			child:own(function()
				releases += 1
			end)
			child:dispose()
			t.expect(parent.native.size()).toBe(ownedBefore)
			t.expect(child.native.size()).toBe(0)
			t.expect(reachable(child)[parent]).toBeNil()
		end
		for value in reachable(parent) do
			t.expect(initial[value]).toBe(true)
		end
		local last = parent:child()
		last:own(function()
			releases += 1
		end)
		parent:dispose()
		t.expect(releases).toBe(1001)
		t.expect(reachable(parent)[last]).toBeNil()
		t.expect(core:counters().scopes).toBe(0)
		t.expect(core:lastError()).toBeNil()
	end)
end)
