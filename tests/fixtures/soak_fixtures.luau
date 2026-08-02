--!strict
-- Soak fixture registry (design §16.1 "soak"): churn scenarios that must
-- return every tracked registry to baseline. Phase 1: presenter modal churn
-- and ForEach structural churn over the full headless slice.

local runner = require("../../tools/lune/registry_runner")
local LuauUI = require("../../src")
local fake_target = require("../lib/fake_target")

local fixtures: { runner.Fixture } = {
	{
		name = "modal-churn-200",
		requirement = "UI-LIFE-002",
		run = function()
			local core = LuauUI.newCore()
			local env = LuauUI.newEnvironment(core)
			local system = LuauUI.newActionSystem(core)
			local adapter = fake_target.new()
			local pres = LuauUI.newPresenter(core, env, adapter, system)
			pres.present(LuauUI.UI.Screen({
				id = "Base",
				children = { LuauUI.UI.Button({ id = "B", label = "b" }) },
			}))
			local baseline = core:counters()
			local liveBaseline = adapter.liveCount()
			for _ = 1, 200 do
				local modal = pres.presentModal(LuauUI.UI.Screen({
					id = "M",
					children = { LuauUI.UI.Button({ id = "Ok", label = "ok" }) },
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
			local core = LuauUI.newCore()
			local items = core:signal({ { id = "a" }, { id = "b" }, { id = "c" } })
			local bp = LuauUI.UI.ForEach({
				id = "List",
				items = items,
				key = function(item)
					return item.id
				end,
				row = function(item)
					return LuauUI.UI.Text({ id = "Row-" .. item.id, text = item.id })
				end,
			})
			local baseline = core:counters()
			local root = LuauUI.mount(core, bp)
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
