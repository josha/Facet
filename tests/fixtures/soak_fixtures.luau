--!strict
-- Soak fixture registry (design §16.1 "soak"): churn scenarios that must
-- return every tracked registry to baseline. Phase 1: presenter modal churn
-- and ForEach structural churn over the full headless slice.

local runner = require("../../tools/lune/registry_runner")
local Facet = require("../../src")
local fake_target = require("../lib/fake_target")

local fixtures: { runner.Fixture } = {
	{
		name = "modal-churn-200",
		requirement = "UI-LIFE-002",
		run = function()
			local core = Facet.newCore()
			local env = Facet.newEnvironment(core)
			local system = Facet.newActionSystem(core)
			local adapter = fake_target.new()
			local pres = Facet.newPresenter(core, env, adapter, system)
			pres.present(Facet.UI.Screen({
				id = "Base",
				children = { Facet.UI.Button({ id = "B", label = "b" }) },
			}))
			local baseline = core:counters()
			local liveBaseline = adapter.liveCount()
			for _ = 1, 200 do
				local modal = pres.presentModal(Facet.UI.Screen({
					id = "M",
					children = { Facet.UI.Button({ id = "Ok", label = "ok" }) },
				}))
				pres.dismiss(modal)
			end
			local after = core:counters()
			for k, v in baseline :: any do
				if (after :: any)[k] ~= v then
					error(`counter {k} leaked: {v} -> {(after :: any)[k]}`)
				end
			end
			if adapter.liveCount() ~= liveBaseline then
				error(`adapter nodes leaked: {liveBaseline} -> {adapter.liveCount()}`)
			end
			return { iterations = 200, counters = after, adapterNodes = adapter.liveCount() }
		end,
	},
	{
		name = "foreach-structural-churn-100",
		requirement = "UI-RUNTIME-002",
		run = function()
			local core = Facet.newCore()
			local items = core:signal({ { id = "a" }, { id = "b" }, { id = "c" } })
			local bp = Facet.UI.ForEach({
				id = "List",
				items = items,
				key = function(item)
					return item.id
				end,
				row = function(item)
					return Facet.UI.Text({ id = "Row-" .. item.id, text = item.id })
				end,
			})
			local baseline = core:counters()
			local root = Facet.mount(core, bp)
			for i = 1, 100 do
				-- rotate + replace: moves, adds, removes every iteration
				items:set({ { id = "b" }, { id = "c" }, { id = `n{i}` } })
				items:set({ { id = "a" }, { id = "b" }, { id = "c" } })
			end
			root.dispose()
			local after = core:counters()
			for k, v in baseline :: any do
				if (after :: any)[k] ~= v then
					error(`counter {k} leaked: {v} -> {(after :: any)[k]}`)
				end
			end
			return { iterations = 100, counters = after }
		end,
	},
}

return fixtures
