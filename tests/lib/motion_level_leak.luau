--!strict
local Facet = require("../../src")
local engineLib = require("./native_engine")

local alive = setmetatable({}, { __mode = "k" })

local function mountAndDispose()
	local engine = engineLib.new({ cacheDefaults = true })
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local UI = Facet.controls(
		runtime,
		{
			types = engine.types,
			services = { GuiService = gui },
			motionLevel = function(_use: any): string
				return if runtime ~= nil then "normal" else "none"
			end,
		} :: any
	)
	local stop = runtime.mount(function()
		return UI.VStack({ UI.Button "Save" { label = "Save" } })
	end, engine.new("ScreenGui"))
	stop()
	runtime:dispose()
	alive[runtime] = true
end

for _ = 1, 50 do
	mountAndDispose()
end
for _ = 1, 3 do
	local cycle = setmetatable({ [{}] = true }, { __mode = "k" })
	while next(cycle) do
		table.clear(table.create(4096, {}))
	end
end
local count = 0
for _ in alive do
	count += 1
end
print(`retained {count}`)
