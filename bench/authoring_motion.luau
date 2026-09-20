--!strict
-- Identical retained trees: explicit transaction animation vs declarative groups.
local nativeApp = require("./native_app")
return function(automatic: boolean)
	local world = nativeApp({ viewport = { x = 0, y = 0, w = 900, h = 900 } })
	local UI, Compose, pres = world.UI, world.Compose, world.pres
	local tall = Compose.cell(false)
	local height = Compose.formula(function(use)
		return { type = "fixed", px = if use(tall) then 6 else 4 }
	end)
	world.app.mount(function()
		local props: { [any]: any } = {
			gap = 0,
			padding = 0,
			animation = if automatic then { layout = "container" } else nil,
		}
		for i = 1, 100 do
			table.insert(props, UI.Box(`Row{i}`)({ width = UI.fill(), height = height }))
		end
		return UI.Screen("MotionBench")(props)
	end)
	pres.refresh()
	return {
		run = function()
			if automatic then
				tall:set(not tall:peek())
				pres.refresh()
			else
				pres.withAnimation("container", function()
					tall:set(not tall:peek())
				end)
			end
			pres.tick(1 / 60)
			assert(pres.animationRecordCount() > 0, "fixture must actually animate")
		end,
		dispose = function()
			world.app.dispose()
			height:dispose()
		end,
	}
end
