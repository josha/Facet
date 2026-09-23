--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local glade = require("../examples/reference/p1_glade")
local cartwheel = require("../examples/reference/p2_cartwheel")
local sipworks = require("../examples/reference/p3_sipworks")
local foyer = require("../examples/reference/p4_foyer")
local function world(module)
	local engine = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local built
	local stop, node = runtime.mount(function()
		built = module.build({
			Facet = Facet,
			Compose = Facet.Compose,
			runtime = runtime,
			Host = runtime.constructors,
			UI = Facet.controls(runtime, { types = engine.types }),
			types = engine.types,
			viewport = Facet.Compose.cell({ width = 1000, height = 720 }),
		})
		return built.screen()
	end, engine.new("ScreenGui"))
	return built, node, function()
		stop()
		runtime:dispose()
	end
end
local function find(node, name)
	if node.Name == name then
		return node
	end
	for _, child in node:GetChildren() do
		local found = find(child, name)
		if found then
			return found
		end
	end
end
t.describe("native reference applications", function()
	t.it("keeps Glade care, inventory consumption and task completion", function()
		local built, root, stop = world(glade)
		t.expect(root.ClassName).toBe("Frame")
		built.steps.open("mossholm")
		built.steps.refill("mossholm")
		t.expect(built.steps.choose("mossholm", "bramble")).toBe(true)
		t.expect(built.model.complete:peek()).toBe(true)
		local before = built.model.commerce.satchelOf("starlight"):peek()
		built.steps.choose("mossholm", "starlight")
		t.expect(built.model.commerce.satchelOf("starlight"):peek()).toBe(before - 1)
		for _, id in { "favorites", "wisps", "flora", "keeper" } do
			built.model.section:set(id)
		end
		stop()
		t.expect(root.isDestroyed()).toBe(true)
	end)
	t.it("keeps Cartwheel brew commands, rejected purchase retry and guild validation", function()
		local built, root, stop = world(cartwheel)
		local brew = built.model.orders.brews:peek()[1]
		t.expect(built.steps.collect(brew.id)).toBe(true)
		built.steps.advance(0.3)
		t.expect(built.model.orders.statusOf(brew.id)).toBe("done")
		t.expect(built.model.stats.collectedBottles() > 0).toBe(true)
		built.steps.purchase("ledger")
		built.steps.advance(0.3)
		t.expect(built.model.entitlement.fullLedger:peek()).toBe(false)
		built.steps.purchase("ledger")
		built.steps.advance(0.3)
		t.expect(built.model.entitlement.fullLedger:peek()).toBe(true)
		built.steps.signup("NewKeepers", "test")
		built.steps.advance(0.3)
		t.expect(built.model.identity.signedIn:peek()).toBe(true)
		for _, id in { "brews", "workbench", "ledger", "chatter", "plazas" } do
			built.model.section:set(id)
		end
		built.steps.openBrew(brew.id)
		t.expect(find(root, "BrewDetail") ~= nil).toBe(true)
		stop()
	end)
	t.it("keeps Sipworks rejection, stamp earning, free pour and Blend Book unlock", function()
		local built, root, stop = world(sipworks)
		built.steps.order("amber-harvest", "paid")
		built.steps.advance(0.7)
		t.expect(built.model.task.phase:peek()).toBe("rejected")
		t.expect(built.model.rewards.unspent()).toBe(9)
		built.steps.order("amber-harvest", "paid")
		built.steps.advance(0.7)
		t.expect(built.model.task.phase:peek()).toBe("redeem")
		built.steps.redeem()
		built.steps.advance(0.7)
		t.expect(built.model.task.phase:peek()).toBe("done")
		t.expect(built.model.rewards.unspent()).toBe(0)
		built.steps.buyBook()
		built.steps.advance(0.7)
		t.expect(built.model.unlock.unlocked:peek()).toBe(false)
		built.steps.buyBook()
		built.steps.advance(0.7)
		t.expect(built.model.unlock.unlocked:peek()).toBe(true)
		for _, id in { "favorites", "rewards", "book" } do
			built.model.section:set(id)
		end
		built.steps.open("lantern-oolong")
		t.expect(find(root, "Blend") ~= nil).toBe(true)
		stop()
	end)
	t.it("keeps Foyer search, pending/rejected refresh, visit history and navigation", function()
		local built, root, stop = world(foyer)
		built.steps.search("moss")
		t.expect(find(root, "SearchResults") ~= nil).toBe(true)
		built.steps.reject("refresh", "err.feed.refresh.offline")
		built.steps.refresh()
		t.expect(built.model.services.refreshStatus:peek()).toBe("pending")
		built.steps.settle()
		t.expect(built.model.services.refreshStatus:peek()).toBe("rejected")
		built.steps.refresh()
		built.steps.settle()
		t.expect(built.report().page).toBe(1)
		built.steps.open("moss-kingdom")
		built.steps.visit("moss-kingdom")
		built.steps.settle()
		t.expect(built.report().continued["moss-kingdom"]).toBe(true)
		for _, id in { "crews", "forge", "mail", "you" } do
			built.model.destination:set(id)
		end
		stop()
	end)
end)
