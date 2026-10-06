--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local glade = require("../examples/reference/p1_glade")
	local cartwheel = require("../examples/reference/p2_cartwheel")
	local sipworks = require("../examples/reference/p3_sipworks")
	local foyer = require("../examples/reference/p4_foyer")
	local function world(module)
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local built
		local stop, node: any = runtime.mount(function()
			built = module.build({
				Facet = Facet,
				Compose = Facet.Compose,
				runtime = runtime,
				Host = (runtime.constructors :: unknown) :: RobloxHost,
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
	local function find(node: any, name: string): any
		if node.Name == name then
			return node
		end
		for _, child in node:GetChildren() do
			local found = find(child, name)
			if found then
				return found
			end
		end
		return nil
	end
	verifyHarness:suite("native reference applications", function()
		verifyHarness:case("keeps Glade care, inventory consumption and task completion", {
			id = "native_reference_apps::native reference applications::keeps Glade care, inventory consumption and task completion",
			run = function()
				local built, root, stop = world(glade)
				Verify.expect(root.ClassName):toBe("Frame")
				built.steps.open("mossholm")
				built.steps.refill("mossholm")
				Verify.expect((built.steps.choose("mossholm", "bramble"))):toBe(true)
				Verify.expect((built.model.complete:peek())):toBe(true)
				local before = built.model.commerce.satchelOf("starlight"):peek()
				built.steps.choose("mossholm", "starlight")
				Verify.expect((built.model.commerce.satchelOf("starlight"):peek())):toBe(before - 1)
				for _, id in { "favorites", "wisps", "flora", "keeper" } do
					built.model.section:set(id)
				end
				stop()
				Verify.expect((root.isDestroyed())):toBe(true)
			end,
		})
		verifyHarness:case("keeps Cartwheel brew commands, rejected purchase retry and guild validation", {
			id = "native_reference_apps::native reference applications::keeps Cartwheel brew commands, rejected purchase retry and guild validation",
			run = function()
				local built, root, stop = world(cartwheel)
				local brew = built.model.orders.brews:peek()[1]
				Verify.expect((built.steps.collect(brew.id))):toBe(true)
				built.steps.advance(0.3)
				Verify.expect((built.model.orders.statusOf(brew.id))):toBe("done")
				Verify.expect(built.model.stats.collectedBottles() > 0):toBe(true)
				built.steps.purchase("ledger")
				built.steps.advance(0.3)
				Verify.expect((built.model.entitlement.fullLedger:peek())):toBe(false)
				built.steps.purchase("ledger")
				built.steps.advance(0.3)
				Verify.expect((built.model.entitlement.fullLedger:peek())):toBe(true)
				built.steps.signup("NewKeepers", "test")
				built.steps.advance(0.3)
				Verify.expect((built.model.identity.signedIn:peek())):toBe(true)
				for _, id in { "brews", "workbench", "ledger", "chatter", "plazas" } do
					built.model.section:set(id)
				end
				built.steps.openBrew(brew.id)
				Verify.expect(find(root, "BrewDetail") ~= nil):toBe(true)
				stop()
			end,
		})
		verifyHarness:case("keeps Sipworks rejection, stamp earning, free pour and Blend Book unlock", {
			id = "native_reference_apps::native reference applications::keeps Sipworks rejection, stamp earning, free pour and Blend Book unlock",
			run = function()
				local built, root, stop = world(sipworks)
				built.steps.order("amber-harvest", "paid")
				built.steps.advance(0.7)
				Verify.expect((built.model.task.phase:peek())):toBe("rejected")
				Verify.expect((built.model.rewards.unspent())):toBe(9)
				built.steps.order("amber-harvest", "paid")
				built.steps.advance(0.7)
				Verify.expect((built.model.task.phase:peek())):toBe("redeem")
				built.steps.redeem()
				built.steps.advance(0.7)
				Verify.expect((built.model.task.phase:peek())):toBe("done")
				Verify.expect((built.model.rewards.unspent())):toBe(0)
				built.steps.buyBook()
				built.steps.advance(0.7)
				Verify.expect((built.model.unlock.unlocked:peek())):toBe(false)
				built.steps.buyBook()
				built.steps.advance(0.7)
				Verify.expect((built.model.unlock.unlocked:peek())):toBe(true)
				for _, id in { "favorites", "rewards", "book" } do
					built.model.section:set(id)
				end
				built.steps.open("lantern-oolong")
				Verify.expect(find(root, "Blend") ~= nil):toBe(true)
				stop()
			end,
		})
		verifyHarness:case("keeps Foyer search, pending/rejected refresh, visit history and navigation", {
			id = "native_reference_apps::native reference applications::keeps Foyer search, pending/rejected refresh, visit history and navigation",
			run = function()
				local built, root, stop = world(foyer)
				built.steps.search("moss")
				Verify.expect(find(root, "SearchResults") ~= nil):toBe(true)
				built.steps.reject("refresh", "err.feed.refresh.offline")
				built.steps.refresh()
				Verify.expect((built.model.services.refreshStatus:peek())):toBe("pending")
				built.steps.settle()
				Verify.expect((built.model.services.refreshStatus:peek())):toBe("rejected")
				built.steps.refresh()
				built.steps.settle()
				Verify.expect(built.report().page):toBe(1)
				built.steps.open("moss-kingdom")
				built.steps.visit("moss-kingdom")
				built.steps.settle()
				Verify.expect(built.report().continued["moss-kingdom"]):toBe(true)
				for _, id in { "crews", "forge", "mail", "you" } do
					built.model.destination:set(id)
				end
				stop()
			end,
		})
		verifyHarness:case("keeps each notice line inside the screen width with a fixed box", {
			id = "native_reference_apps::native reference applications::keeps each notice line inside the screen width with a fixed box",
			run = function()
				local modules: { any } = { glade, cartwheel, sipworks, foyer }
				for _, module in modules do
					local _, root, stop = world(module)
					local notice
					for _, node in root:GetDescendants() do
						if
							node.ClassName == "TextLabel"
							and node.Position.Y.Offset == -60
							and node.Position.X.Offset == 16
						then
							notice = node
						end
					end
					Verify.expect(notice ~= nil):toBe(true)
					Verify.expect(notice.Size.X.Scale):toBe(1)
					Verify.expect(notice.Size.X.Offset):toBe(-32)
					Verify.expect(notice.AutomaticSize.Name):toBe("None")
					stop()
				end
			end,
		})
	end)
end
