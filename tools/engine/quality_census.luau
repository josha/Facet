--!strict

local Loader = require("../../tests/lib/loader")
local Json = require("../facet/lib/json")
local loader = Loader.new()
local nativeApp = loader.require("bench/native_app.luau") :: typeof(require("../../bench/native_app"))
type State = typeof(nativeApp())
local function sample(name: string, build: (State) -> Instance)
	local state = nativeApp()
	local baseline = state.engine.census()
	local started = os.clock()
	local stop, node = state.runtime.mount(function()
		return build(state)
	end, state.target)
	local elapsed = os.clock() - started
	local mounted = state.engine.census()
	local classes: { [string]: number } = { [(node :: Instance).ClassName] = 1 }
	for _, child in (node :: Instance):GetDescendants() do
		classes[child.ClassName] = (classes[child.ClassName] or 0) + 1
	end
	print(
		Json.encode({ name = name, classes = classes, instances = mounted.live - baseline.live, mountSeconds = elapsed })
	)
	stop()
	state.dispose()
end
sample("Theme", function(state)
	return state.Facet.themes.createStyleSheet(state.runtime, nil, { types = state.types })
end)
sample("Sheet-closed", function(state)
	return state.UI.Sheet({
		isPresented = state.Compose.cell(false),
		title = "Shop",
		content = function()
			error("closed content must remain unbuilt")
		end,
	})
end)
sample("VStack", function(state)
	return state.UI.VStack({ width = "fill", gap = "s", padding = "m" })
end)
sample("HStack", function(state)
	return state.UI.HStack({ width = "fill", gap = "s", wrap = true })
end)
sample("Badge", function(state)
	return state.UI.Badge({ label = "Motors" })
end)
sample("ProgressView", function(state)
	return state.UI.ProgressView({ label = "Zone 1", value = state.Compose.cell(0.5) })
end)
