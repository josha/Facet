--!strict

type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
local Facet = require("../../src")
local engineLib = require("./native_engine")

local alive = setmetatable({} :: { [any]: boolean }, { __mode = "k" })

local function mountAndDispose()
	local engine = engineLib.new()
	local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local UI = Facet.controls(
		runtime,
		{
			types = engine.types,
			services = { GuiService = gui },
			motionLevel = function(_use: any): "normal" | "limited" | "none"
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
for _ in (alive :: unknown) :: { [any]: boolean } do
	count += 1
end
print(`retained {count}`)

local motion = require("../../src/ui/motion")
local engine = engineLib.new()
local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
local gui = engine.new("GuiService")
local contexts = setmetatable({} :: { [any]: boolean }, { __mode = "k" })
for _ = 1, 50 do
	local stop = runtime.mount(function()
		local UI
		UI = Facet.controls(
			runtime,
			{
				types = engine.types,
				services = { GuiService = gui },
				motionLevel = function(_use: any): "normal" | "limited" | "none"
					return if UI ~= nil then "normal" else "none"
				end,
			} :: any
		)
		contexts[UI] = true
		return UI.VStack({ UI.Button "Save" { label = "Save" } })
	end, engine.new("ScreenGui"))
	stop()
end
for _ = 1, 3 do
	local cycle = setmetatable({ [{}] = true }, { __mode = "k" })
	while next(cycle) do
		table.clear(table.create(4096, {}))
	end
end
local live = 0
for _ in (contexts :: unknown) :: { [any]: boolean } do
	live += 1
end
print(`published {#motion.published(runtime)} contexts {live}`)
runtime:dispose()
