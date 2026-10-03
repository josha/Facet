--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
local nativeApp = require("./native_app")
return function(automatic: boolean)
	local world = nativeApp({ viewport = { w = 900, h = 900 } })
	local Compose: ComposeModule, Host = world.Compose, world.Host
	local tall = Compose.cell(false)
	local height = Compose.cell(4)
	local observed
	world.runtime.mount(function()
		local children = { Host.UIListLayout({}) :: unknown }
		for index = 1, 100 do
			local animated = world.runtime.tween(function(use: Use): number
				return if automatic then (if use(tall) then 6 else 4) else use(height)
			end, { seconds = 0.2 })
			observed = animated
			table.insert(
				children,
				Host.Frame({
					Name = `Row{index}`,
					Size = function(use: Use)
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
