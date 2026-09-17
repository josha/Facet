--!strict
-- Identical retained trees: explicit transaction animation vs declarative groups.
local Facet = require("../src") :: any
local fake = require("../tests/lib/fake_target")
local UI = Facet.View
return function(automatic: boolean)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 900, h = 900 })
	local pres = Facet.newPresenter(core, env, fake.new(), Facet.newActionSystem(core))
	local tall = core:signal(false)
	local height = core:memo(function(use)
		return { type = "fixed", px = if use(tall) then 6 else 4 }
	end)
	local rows = {}
	for i = 1, 100 do
		table.insert(
			rows,
			UI.Box({
				id = `Row{i}`,
				width = UI.fill(),
				height = height,
			})
		)
	end
	local handle = pres.present(UI.Screen({
		id = "MotionBench",
		gap = 0,
		padding = 0,
		animation = if automatic then { layout = "container" } else nil,
		children = rows,
	}))
	pres.refresh()
	return {
		run = function()
			if automatic then
				tall:set(not tall:get())
				pres.refresh()
			else
				pres.withAnimation("container", function()
					tall:set(not tall:get())
				end)
			end
			pres.tick(1 / 60)
			assert(pres.animationRecordCount() > 0, "fixture must actually animate")
		end,
		dispose = function()
			pres.dismiss(handle)
			height:dispose()
			tall:dispose()
		end,
	}
end
