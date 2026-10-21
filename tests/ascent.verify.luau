--!strict
local Verify = require("../tools/vendor/verify/src/core")
local model = require("../examples/gallery/examples/skill_tree/model")
local copy = require("../examples/gallery/examples/skill_tree/copy")

return function(harness: Verify.Harness)
	harness:case("Ascent reveals the next frontier only after an accepted purchase", function(t)
		local initial = model.initial()
		t:expect(model.visible(initial, model.byId.flare)):toBe(true)
		t:expect(model.visible(initial, model.byId.nova)):toBe(false)
		local locked, rejected = model.purchase(initial, "flare")
		t:expect(locked):toBe(initial)
		t:expect(rejected):toBe("locked")
		local unlocked, accepted = model.purchase(initial, "spark")
		t:expect(accepted):toBe("unlocked")
		t:expect(unlocked.points):toBe(15)
		t:expect(initial.points):toBe(18)
		t:expect(model.visible(unlocked, model.byId.nova)):toBe(true)
		t:expect(model.status(unlocked, model.byId.flare)):toBe("available")
		local repeated = model.purchase(unlocked, "spark")
		t:expect(repeated):toBe(unlocked)
	end)
	harness:case("Ascent rejects insufficient funds without changing owned upgrades", function(t)
		local state = model.initial()
		for _, id in { "spark", "flare", "nova", "aegis" } do
			local nextState, result = model.purchase(state, id)
			t:expect(result):toBe("unlocked")
			state = nextState
		end
		t:expect(state.points):toBe(1)
		local rejected, reason = model.purchase(state, "resolve")
		t:expect(rejected):toBe(state)
		t:expect(reason):toBe("insufficient")
		t:expect(state.owned.resolve == true):toBe(false)
	end)
	harness:case("Ascent has connected unique nodes and localized player copy", function(t)
		local ids: { [string]: boolean } = {}
		for _, node in model.nodes do
			t:expect(ids[node.id] == true):toBe(false)
			ids[node.id] = true
			t:expect(type(copy[node.id .. "Name"])):toBe("string")
			t:expect(type(copy[node.id .. "Benefit"])):toBe("string")
			t:expect(type(copy[node.branch])):toBe("string")
			if node.parent then
				t:expect(ids[node.parent]):toBe(true)
				t:expect(node.cost > 0):toBe(true)
			end
		end
	end)
end
