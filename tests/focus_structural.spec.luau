--!strict
-- Phase-1 verifier corrective tests (findings F1/F2):
-- F1: the focus ring follows structural changes — focusables mounted by When
--     join the ring; unmounting the focused control moves focus to a
--     surviving neighbor and Activate never routes to a dead path.
-- F2: confirm-before-ingest converges when the optimistic view is reconciled
--     on snapshot ingest (the documented wiring contract).

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src")
local fake_target = require("../tests/lib/fake_target")

describe("focus ring follows structure (F1)", function()
	local function world()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		return core, system, pres
	end

	it("a focusable inside When joins the ring on mount and leaves on unmount", function()
		local core, system, pres = world()
		local showExtra = core:signal(false)
		local activated: { string } = {}
		pres.present(
			Facet.UI.Screen({
				id = "S",
				children = {
					Facet.UI.Button({ id = "A", label = "a" }),
					Facet.UI.When({
						id = "W",
						condition = showExtra,
						thenView = function()
							return Facet.UI.Button({ id = "B", label = "b" })
						end,
					}),
					Facet.UI.Button({ id = "C", label = "c" }),
				},
			}),
			{
				onActivate = function(path)
					table.insert(activated, path)
				end,
			}
		)
		-- before: ring is A, C
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:get()).toBe("/S/C")
		-- mount B; refresh re-derives the ring: A, B, C
		showExtra:set(true)
		pres.refresh()
		system.deviceKey("Up", true)
		system.deviceKey("Up", false)
		expect(pres.focus.focused:get()).toBe("/S/W/then/B")
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		expect(activated[#activated]).toBe("/S/W/then/B")
		-- unmount B while it is focused: nearest survivor takes focus and
		-- Activate routes to a LIVE path
		showExtra:set(false)
		pres.refresh()
		expect(pres.focus.focused:get()).toBe("/S/C")
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		expect(activated[#activated]).toBe("/S/C")
	end)
end)

describe("confirm-before-ingest convergence (F2)", function()
	it("an optimistic view reconciled on snapshot ingest converges regardless of delivery order", function()
		local core = Facet.newCore()
		local snapshot = Facet.replication.snapshot(core, 1, { music = false })
		local draft = core:signal(false)
		local mutation = Facet.replication.mutation(core, {
			optimistic = {
				apply = function(payload)
					draft:set(payload.music)
				end,
				restore = function()
					draft:set(snapshot.binding:get().music)
				end,
			},
		})
		-- the documented wiring contract: the game re-reconciles the
		-- optimistic view whenever authoritative state ingests
		core:observe(snapshot.binding, function(data)
			if mutation.status:get() ~= "pending" then
				draft:set(data.music)
			end
		end)
		local envelope = mutation.send({ music = true }, snapshot.revision())
		expect(draft:get()).toBe(true)
		-- confirm arrives BEFORE the snapshot: restore() goes to stale truth
		mutation.confirm(envelope.requestId, "ok")
		expect(mutation.status:get()).toBe("confirmed")
		expect(draft:get()).toBe(false) -- stale, transiently
		-- the late snapshot ingest re-converges through the wiring contract
		snapshot.ingest(2, { music = true })
		expect(draft:get()).toBe(true) -- converged: no permanent divergence
	end)
end)
