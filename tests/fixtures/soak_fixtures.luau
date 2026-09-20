--!strict
-- Soak fixture registry (design §16.1 "soak"): churn scenarios that must
-- return every tracked registry to baseline. Phase 1: presenter modal churn
-- and ForEach structural churn over the full headless slice.

local runner = require("../../tools/lune/registry_runner")
local Facet = require("../../src")
local fake_target = require("../lib/fake_target")
local Compose = require("../../src/vendor/compose/core")

-- arms every fixture's fake target's op log (T12, default off per ruling
-- A-11). `runner.Fixture.run` is a fixed `() -> any` the shared runner calls
-- with no arguments, so a per-fixture opt-in cannot travel through a call
-- site — this module-level flag is the pass-through instead.
local ARM_OPS = false

-- One application over a fake target: the shape every consumer boots.
local function world()
	local adapter = fake_target.new({ ops = ARM_OPS })
	local app = Facet.new({
		newAdapter = function()
			return adapter
		end,
		newInputSystem = function(core)
			return Facet.newActionSystem(core)
		end,
		bindEnv = function(env)
			env:set("viewportRect", { x = 0, y = 0, w = 640, h = 480 })
			env:set("reducedMotion", true)
			return function() end
		end,
		connectFrame = function()
			return function() end
		end,
	})
	return app, adapter
end

local fixtures: { runner.Fixture } = {
	{
		name = "modal-churn-200",
		requirement = "UI-LIFE-002",
		run = function()
			local app, adapter = world()
			local UI = app.controls
			app.mount(function()
				return UI.Screen("Base")({ UI.Button("B")({ label = "b" }) })
			end)
			local liveBaseline = adapter.liveCount()
			for _ = 1, 200 do
				local close = app.presentModal(function()
					return UI.Screen("M")({ UI.Button("Ok")({ label = "ok" }) })
				end)
				close()
			end
			if adapter.liveCount() ~= liveBaseline then
				error(`adapter nodes leaked: {liveBaseline} -> {adapter.liveCount()}`)
			end
			local held = adapter.liveCount()
			app.dispose()
			if adapter.liveCount() ~= 0 then
				error(`disposal left {adapter.liveCount()} adapter nodes`)
			end
			return { iterations = 200, adapterNodes = held }
		end,
	},
	{
		name = "foreach-structural-churn-100",
		requirement = "UI-RUNTIME-002",
		run = function()
			local app, adapter = world()
			local UI = app.controls
			local items = Compose.cell({ { id = "a" }, { id = "b" }, { id = "c" } })
			app.mount(function()
				return UI.Screen("S")({
					UI.ForEach({
						id = "List",
						items = items,
						key = "id",
						row = function(item)
							return UI.Text("Row-" .. item.id)({ text = item.id })
						end,
					}),
				})
			end)
			local liveBaseline = adapter.liveCount()
			for i = 1, 100 do
				-- rotate + replace: moves, adds, removes every iteration
				items:set({ { id = "b" }, { id = "c" }, { id = `n{i}` } })
				items:set({ { id = "a" }, { id = "b" }, { id = "c" } })
			end
			if adapter.liveCount() ~= liveBaseline then
				error(`adapter nodes leaked: {liveBaseline} -> {adapter.liveCount()}`)
			end
			app.dispose()
			if adapter.liveCount() ~= 0 then
				error(`disposal left {adapter.liveCount()} adapter nodes`)
			end
			return { iterations = 100, adapterNodes = liveBaseline }
		end,
	},
}

return fixtures
