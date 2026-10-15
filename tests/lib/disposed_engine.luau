--!strict

type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
local Facet = require("../../src")
local engineLib = require("./native_engine")

local alive = setmetatable({}, { __mode = "k" })

local function mountAndDispose()
	local engine = engineLib.new()
	local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local UI = Facet.controls(runtime, {
		types = engine.types,
		services = { GuiService = gui },
		motionLevel = "none",
	})
	local stop = runtime.mount(function()
		return UI.VStack({
			UI.Button "Save" { label = "Save", help = { body = "Saves your setup" } },
		})
	end, engine.new("ScreenGui"))
	stop()
	runtime:dispose()
	alive[engine] = true
end

mountAndDispose()
for _ = 1, 2 do
	local cycle = setmetatable({ [{}] = true }, { __mode = "k" })
	while next(cycle) do
		table.clear(table.create(4096, {}))
	end
end
print(if next(alive) == nil then "collected" else "retained")
