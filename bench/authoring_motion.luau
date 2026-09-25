--!strict
local nativeApp = require("./native_app")
return function(automatic: boolean)
	local world = nativeApp({ viewport = { w = 900, h = 900 } })
	local Compose, Host = world.Compose, world.Host
	local tall = Compose.cell(false)
	local height = Compose.cell(4)
	local observed
	world.runtime.mount(function()
		local children = { Host.UIListLayout({}) }
		for index = 1, 100 do
			local source = if automatic
				then function(use)
					return if use(tall) then 6 else 4
				end
				else height
			local animated = world.runtime.tween(
				if automatic
					then source
					else function(use)
						return use(source)
					end,
				{ seconds = 0.2 }
			)
			observed = animated
			table.insert(
				children,
				Host.Frame({
					Name = `Row{index}`,
					Size = function(use)
						return world.types.UDim2.new(1, 0, 0, use(animated))
					end,
				})
			)
		end
		return Host.Frame(children)
	end, world.target)
	local iteration = 0
	return {
		run = function()
			iteration += 1
			if automatic then
				tall:set(not tall:peek())
			else
				height:set(if iteration % 2 == 1 then 6 else 4)
			end
			world.frame()
			assert(observed:peek() > 4 and observed:peek() < 6, "motion workload did not animate")
		end,
		dispose = world.dispose,
	}
end
