--!strict

local process = require("@std/process")
local Loader = require("../../tests/lib/loader")
local Json = require("../facet/lib/json")
local Files = require("../facet/lib/files")

local loader = Loader.new()
local nativeApp = loader.require("bench/native_app.luau") :: typeof(require("../../bench/native_app"))
type State = typeof(nativeApp())
type Counts = { instances: number, connections: number, holdings: number }
type Sample = {
	name: string,
	active: Counts,
	idle: Counts,
	teardown: Counts,
	classes: { [string]: number },
	tree: { string },
}

local samples: { Sample } = {}
local function fire(node: Instance, event: string)
	local signals = (node :: unknown) :: { [string]: { Fire: (unknown) -> () } }
	signals[event]:Fire()
end
local function sample(name: string, build: (State) -> Instance, activate: ((Instance) -> ())?)
	local state = nativeApp()
	local Compose, runtime, Host = state.Compose, state.runtime, state.Host
	Compose.inspect.start({ maxOwners = math.huge, maxNodes = math.huge })
	local function census(): Counts
		local native = state.engine.census()
		local snapshot = Compose.inspect.snapshot()
		assert(snapshot.droppedOwners == 0 and snapshot.droppedNodes == 0)
		local holdings = 0
		for _, roots in { snapshot.mounts, snapshot.detached } do
			for _, root in roots do
				holdings += root.totalHolding
			end
		end
		return { instances = native.live, connections = native.connections, holdings = holdings }
	end
	local screen: ScreenGui
	runtime.mount(function()
		screen = Host.ScreenGui({})
		return screen
	end, state.target)
	local baseline = census()
	local stop, node = runtime.mount(function()
		return build(state)
	end, screen)
	if activate then
		activate(node :: Instance)
	end
	local function delta(): Counts
		local counts = census()
		return {
			instances = counts.instances - baseline.instances,
			connections = counts.connections - baseline.connections,
			holdings = counts.holdings - baseline.holdings,
		}
	end
	local active = delta()
	for _ = 1, 120 do
		state.frame()
	end
	local idle = delta()
	local classes: { [string]: number } = {}
	local tree: { string } = {}
	for _, child in screen:GetDescendants() do
		classes[child.ClassName] = (classes[child.ClassName] or 0) + 1
		local probe = (child :: unknown) :: { connectionCount: (Instance) -> number }
		table.insert(
			tree,
			child:GetFullName() .. " (" .. child.ClassName .. ") " .. tostring(probe.connectionCount(child))
		)
	end
	stop()
	state.dispose()
	local teardown = census()
	table.insert(
		samples,
		{ name = name, active = active, idle = idle, teardown = teardown, classes = classes, tree = tree }
	)
	Compose.inspect.stop()
end

sample("Button", function(state)
	return state.UI.Button({ label = "Save", onActivate = function() end })
end)
sample("Button-bounded", function(state)
	return state.UI.Button({ label = "Save", Size = state.types.UDim2.fromOffset(160, 40), onActivate = function() end })
end)
sample("Button-focused", function(state)
	return state.UI.Button({ label = "Save", onActivate = function() end })
end, function(node)
	fire(node, "SelectionGained")
end)
sample("Text", function(state)
	return state.UI.Text({ text = "Inventory" })
end)
sample("Text-fixed", function(state)
	return state.UI.Text({
		text = "Inventory",
		Size = state.types.UDim2.fromOffset(160, 40),
		AutomaticSize = state.types.Enum.AutomaticSize.None,
	})
end)
sample("TextInput", function(state)
	return state.UI.TextInput({ value = state.Compose.cell("Player") })
end)
sample("TextInput-focused", function(state)
	return state.UI.TextInput({ value = state.Compose.cell("Player") })
end, function(node)
	(node :: TextBox):CaptureFocus()
end)
sample("Toggle", function(state)
	return state.UI.Toggle({ label = "Music", value = state.Compose.cell(true) })
end)
sample("Slider", function(state)
	return state.UI.Slider({ value = state.Compose.cell(0.5), min = 0, max = 1 })
end)
sample("Picker", function(state)
	return state.UI.Picker({
		selected = state.Compose.cell("normal"),
		options = { { value = "easy", label = "Easy" }, { value = "normal", label = "Normal" } },
		style = "menu",
	})
end)
sample("Picker-open", function(state)
	return state.UI.Picker({
		selected = state.Compose.cell("normal"),
		options = { { value = "easy", label = "Easy" }, { value = "normal", label = "Normal" } },
		style = "menu",
	})
end, function(node)
	fire(assert(node:FindFirstChild("Trigger", true)), "Activated")
end)
for count = 1, 2 do
	sample(`Menu-{count}-rows`, function(state)
		local items = {}
		for index = 1, count do
			items[index] = { id = tostring(index), label = "Action", onSelect = function() end }
		end
		return state.UI.Menu({ label = "Actions", items = items })
	end, function(node)
		fire(assert(node:FindFirstChild("Trigger")), "Activated")
	end)
end
sample("Sheet", function(state)
	return state.UI.Sheet({
		isPresented = state.Compose.cell(true),
		title = "Details",
		content = function()
			return state.UI.Text({ text = "Race details" })
		end,
	})
end)
sample("Dialog", function(state)
	return state.UI.Dialog({
		isPresented = state.Compose.cell(true),
		title = "Leave?",
		content = function()
			return state.UI.Text({ text = "Your lap will not count." })
		end,
		actions = { { id = "stay", label = "Stay", role = "cancel", onActivate = function() end } },
	})
end)
sample("Card", function(state)
	return state.UI.Card({ title = "Course", image = "rbxassetid://1" })
end)
sample("Card-actions", function(state)
	return state.UI.Card({
		title = "Course",
		image = "rbxassetid://1",
		caption = "Friends playing",
		primaryAction = { label = "Play", onActivate = function() end },
	})
end)
for count = 1, 2 do
	sample(`VirtualList-{count}-rows`, function(state)
		local rows = {}
		for index = 1, count do
			rows[index] = { id = tostring(index), label = "Row" }
		end
		local node = state.UI.VirtualList({
			from = rows,
			key = "id",
			itemSize = 40,
			Size = state.types.UDim2.fromOffset(300, 200),
			render = function(current)
				return state.UI.Button({ label = current:peek().label, onActivate = function() end })
			end,
		})
		local geometry = (node :: unknown) :: { AbsoluteSize: Vector2, AbsoluteWindowSize: Vector2 }
		geometry.AbsoluteSize = state.types.Vector2.new(300, 200)
		geometry.AbsoluteWindowSize = state.types.Vector2.new(300, 200)
		return node
	end)
end

local path = process.args[2] or "artifacts/perf-footprint.json"
Files.write(path, Json.encode({ schema = "facet-perf-footprint/1", samples = samples }, { indent = 2 }))
print("| Control | Instances | Connections | Holdings |")
print("|---|---:|---:|---:|")
for _, row in samples do
	print(`| {row.name} | {row.idle.instances} | {row.idle.connections} | {row.idle.holdings} |`)
end
