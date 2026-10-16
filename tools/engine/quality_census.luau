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
	for _ = 1, 120 do
		state.frame()
	end
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
	return state.UI.Sheet "Closed" {
		isPresented = state.Compose.cell(false),
		title = "Shop",
		content = function()
			error("closed content must remain unbuilt")
		end,
	}
end)
sample("VStack", function(state)
	return state.UI.VStack "Stack" { width = "fill", gap = "s", padding = "m" }
end)
sample("HStack", function(state)
	return state.UI.HStack "Row" { width = "fill", gap = "s", wrap = true }
end)
sample("Badge", function(state)
	return state.UI.Badge "Category" { label = "Motors" }
end)
sample("ProgressView", function(state)
	return state.UI.ProgressView "Progress" { label = "Zone 1", value = state.Compose.cell(0.5) }
end)
sample("Screen", function(state)
	return state.UI.Screen "Root" {}
end)
sample("Composition-Region", function(state)
	return state.UI.Composition "HUD" {
		state.UI.Region "Top" { zone = "top", rank = 1, state.UI.VStack "Readouts" {} },
	}
end)
sample("VirtualGrid-part-row", function(state)
	local UI = state.UI
	local rows = { { id = "part", label = "Starter Motor", description = "A starter part for the next race." } }
	local node = UI.VirtualGrid "Parts" {
		from = rows,
		key = "id",
		minColumnWidth = 220,
		itemSize = 224,
		measure = true,
		Size = state.types.UDim2.fromOffset(315, 340),
		render = function(current)
			return UI.VStack "Part" {
				width = "fill",
				padding = "m",
				gap = "s",
				UI.Badge "Category" { label = "Motors" },
				UI.Text "Name" { text = current:peek().label, textRole = "heading", wrap = true },
				UI.Text "Description" { text = current:peek().description, textRole = "caption", wrap = true },
				UI.Button "Buy" { label = "Buy | 250 Coins", Size = state.types.UDim2.new(1, 0, 0, 0) },
			}
		end,
	}
	local geometry = (node :: unknown) :: { AbsoluteSize: Vector2, AbsoluteWindowSize: Vector2 }
	geometry.AbsoluteSize = state.types.Vector2.new(315, 340)
	geometry.AbsoluteWindowSize = state.types.Vector2.new(309, 340)
	return node
end)
