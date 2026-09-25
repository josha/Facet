--!strict
local Facet = require("../src")
local Compose = Facet.Compose
local nativeApp = require("./native_app")
local authoringMotion = require("./authoring_motion")

export type Scenario = {
	name: string,
	requirement: string,
	setup: () -> any,
	run: (any) -> (),
	teardown: ((any) -> ())?,
	samples: number?,
	warmup: number?,
}

local scenarios = {}
local function add(name, setup, run, options)
	local scenario = options or {}
	scenario.name = name
	scenario.requirement = scenario.requirement or "UI-PERF-001"
	scenario.setup = setup
	scenario.run = run
	scenario.teardown = scenario.teardown or function(state)
		state.dispose()
	end
	table.insert(scenarios, scenario)
end

local function reactive(setup)
	local state = {}
	local root = Compose.createRootOwner(function(owner)
		state.owner = owner
		setup(state)
	end)
	state.dispose = root.dispose
	return state
end

add("hud-binding-storm", function()
	return reactive(function(state)
		state.speed, state.n, state.renders = Compose.cell(0), 0, 0
		local rounded = Compose.formula(function(use)
			return math.floor(use(state.speed))
		end)
		local label = Compose.formula(function(use)
			return `{use(rounded)} sps`
		end)
		state.owner.watchStatic(label, function()
			state.renders += 1
		end)
	end)
end, function(state)
	state.n += 1
	for index = 1, 100 do
		state.speed:set(state.n * 100 + index)
	end
end)

add("settings-churn", function()
	return reactive(function() end)
end, function(state)
	local owner = state.owner.createChild()
	Compose.withOwner(owner, function()
		local draft, status = Compose.cell(false), Compose.cell("idle")
		local label = Compose.formula(function(use)
			return `music: {use(draft) and "on" or "off"} ({use(status)})`
		end)
		owner.watchStatic(label, function() end)
		draft:set(true)
		status:set("confirmed")
	end)
	owner.dispose()
end, { requirement = "UI-LIFE-002" })

add("collection-mutation", function()
	return reactive(function(state)
		state.items, state.keys, state.n = {}, {}, 50
		state.apply = function(keys)
			local wanted = {}
			for _, key in keys do
				wanted[key] = true
			end
			for key, owner in state.items do
				if not wanted[key] then
					owner.dispose()
					state.items[key] = nil
				end
			end
			for _, key in keys do
				if state.items[key] == nil then
					local owner = state.owner.createChild()
					Compose.withOwner(owner, function()
						Compose.cell(key)
					end)
					state.items[key] = owner
				end
			end
		end
		for index = 1, 50 do
			state.keys[index] = `item-{index}`
		end
		state.apply(state.keys)
	end)
end, function(state)
	local keys = state.keys
	table.insert(keys, table.remove(keys, 1))
	state.n += 1
	keys[#keys] = `item-{state.n}`
	state.apply(keys)
end, { requirement = "UI-RUNTIME-002" })

add("sparse-update-under-load", function()
	return reactive(function(state)
		state.signals, state.n = {}, 0
		for index = 1, 200 do
			local value = Compose.cell(index)
			local doubled = Compose.formula(function(use)
				return use(value) * 2
			end)
			state.owner.watchStatic(doubled, function() end)
			table.insert(state.signals, value)
		end
	end)
end, function(state)
	state.n += 1
	state.signals[1]:set(1000 + state.n)
end)

add("mounted-slice-update-storm", function()
	local world = nativeApp()
	world.speed, world.n = Compose.cell(0), 0
	world.runtime.mount(function()
		return world.Host.ScreenGui({
			world.Host.TextLabel({
				Text = function(use)
					return `{use(world.speed)} sps`
				end,
				TextSize = 18,
			}),
			world.UI.Button({ label = "Boost", onActivate = function() end }),
		})
	end, world.target)
	return world
end, function(state)
	state.n += 1
	for index = 1, 50 do
		state.speed:set(state.n * 50 + index)
	end
	state.frame()
end)

local function rampTree(Host, depth, index)
	if depth == 0 then
		return Host.TextLabel({ Name = `T{index}`, Text = "leaf" })
	end
	local children = { Name = `V{index}`, Host.UIListLayout({}) }
	for child = 1, 3 do
		table.insert(children, rampTree(Host, depth - 1, child))
	end
	return Host.Frame(children)
end
for _, inherited in { false, true } do
	add(if inherited then "mount-ramp-inherited" else "mount-ramp", nativeApp, function(state)
		local stop = state.runtime.mount(function()
			return state.Host.ScreenGui({
				state.Host.CanvasGroup({
					Interactable = not inherited,
					GroupColor3 = if inherited
						then state.types.Color3.fromRGB(119, 190, 255)
						else state.types.Color3.new(1, 1, 1),
					rampTree(state.Host, 7, 1),
				}),
			})
		end, state.target)
		stop()
		state.frame()
		assert(#state.target:GetChildren() == 0, "mount ramp leaked a screen")
	end, { samples = 120, warmup = 5 })
end

local function tableState(resizing)
	local world = nativeApp({ viewport = { w = 800, h = 600 } })
	local items = {}
	for index = 1, 8 do
		items[index] = { id = `r{index}`, name = `Racer {index}` }
	end
	world.rows, world.selected, world.n = Compose.cell(items), Compose.cell({}), if resizing then 0 else 8
	world.widths = Compose.cell({ name = 600, n = 48 })
	world.runtime.mount(function()
		local tableNode = world.UI.Table({
			from = world.rows,
			key = function(item)
				return item.id
			end,
			columns = {
				{
					id = "name",
					label = "Racer",
					minWidth = 80,
					resizable = true,
					render = function(current)
						return world.Host.TextLabel({
							TextSize = 14,
							Text = function(use)
								return use(current).name
							end,
						})
					end,
				},
				{
					id = "n",
					label = "N",
					width = 48,
					render = function(current)
						return world.Host.TextLabel({
							TextSize = 14,
							Text = function(use)
								return use(current).name
							end,
						})
					end,
				},
			},
			itemSize = 40,
			header = resizing == true,
			selectionMode = if resizing then "none" else "multi",
			selection = world.selected,
			widths = world.widths,
		})
		world.tableNode = tableNode
		return world.Host.ScreenGui({ tableNode })
	end, world.target)
	world.tableNode.AbsoluteSize = world.types.Vector2.new(800, 600)
	for _, child in world.tableNode:GetChildren() do
		if child.Name == "Body" then
			child.AbsoluteWindowSize = world.types.Vector2.new(800, 600)
		end
	end
	world.frame()
	return world
end
add("table-mutation", function()
	return tableState(false)
end, function(state)
	state.n += 1
	local items = table.clone(state.rows:peek())
	local key = `r{state.n}`
	items[((state.n - 1) % 8) + 1] = { id = key, name = `Racer {state.n}` }
	state.rows:set(items)
	state.selected:update(function(previous)
		local next = table.clone(previous)
		next[key] = if next[key] then nil else true
		return next
	end)
	state.frame()
end)

local function descendant(node, className)
	for _, child in node:GetChildren() do
		if child.ClassName == className then
			return child
		end
		local found = descendant(child, className)
		if found then
			return found
		end
	end
	return nil
end
add("table-resize-drag", function()
	local world = tableState(true)
	world.drag = assert(descendant(world.tableNode, "UIDragDetector"), "Table resize detector is missing")
	world.drag.Parent.Parent.AbsoluteSize = world.types.Vector2.new(600, 40)
	return world
end, function(state)
	state.n += 1
	local direction = if state.n % 2 == 0 then 1 else -1
	local initialWidth = state.widths:peek().name
	state.drag.Parent.Parent.AbsoluteSize = state.types.Vector2.new(initialWidth, 40)
	state.drag.DragStart.fire(state.types.Vector2.new(600, 10))
	for index = 1, 8 do
		state.drag.DragContinue.fire(state.types.Vector2.new(600 + direction * index * 5, 10))
		state.frame()
	end
	state.drag.DragEnd.fire(state.types.Vector2.new(600 + direction * 40, 10))
	assert(state.widths:peek().name == initialWidth + direction * 40, "resize workload did not update its column")
	state.frame()
end)

add("billboard-nameplate-storm", function()
	local world = nativeApp()
	world.health, world.n = Compose.cell("100"), 0
	world.runtime.mount(function()
		return world.Host.BillboardGui({
			Size = world.types.UDim2.fromOffset(300, 96),
			world.Host.TextLabel({ Text = "Racer", TextSize = 18 }),
			world.Host.TextLabel({ Text = world.health, TextSize = 14 }),
		})
	end, world.target)
	return world
end, function(state)
	state.n += 1
	for index = 1, 50 do
		state.health:set(tostring((state.n * 50 + index) % 100))
	end
	state.frame()
end)

add("textinput-typing-storm", function()
	local world = nativeApp()
	world.value, world.builds = Compose.cell(""), 0
	local _, field = world.runtime.mount(function()
		world.builds += 1
		return world.UI.TextInput({
			value = world.value,
			placeholder = "type",
			maxLength = 64,
			onChange = function() end,
		})
	end, world.target)
	world.field = field
	return world
end, function(state)
	state.field.Focused.fire()
	local text = "The quick brown fox 0123"
	for index = 1, #text do
		state.field.Text = string.sub(text, 1, index)
	end
	state.frame()
	state.field.FocusLost.fire(false, { KeyCode = state.types.Enum.KeyCode.Escape })
	assert(state.builds == 1 and not state.field.isDestroyed(), "typing rebuilt the field")
	state.value:set("")
	state.frame()
end)

add("zz-yardstick-cpu", function()
	return { buf = table.create(256, 0), dispose = function() end }
end, function(state)
	local buf, acc = state.buf, 0.0
	for _ = 1, 200 do
		for index = 1, 256 do
			acc += (index * 1.000173) / 3.7
			local remainder = index % 7
			if remainder == 0 then
				acc -= 0.5
			elseif remainder == 3 then
				acc += 0.25
			end
			buf[index] = buf[index] * 0.5 + acc
		end
		acc %= 1000000
	end
	buf[1] = if acc > 0 then 1.0 else -1.0
end)
for _, automatic in { false, true } do
	add(if automatic then "motion-declarative" else "motion-explicit", function()
		return authoringMotion(automatic)
	end, function(state)
		state.run()
	end)
end
table.sort(scenarios, function(a, b)
	return a.name < b.name
end)
return scenarios
