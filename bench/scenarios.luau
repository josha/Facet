--!strict
type FrameProps = typeof(require("@repo/tools/typecheck/aliases").FrameProps)

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type FrameNativeProps = typeof(require("@repo/tools/typecheck/aliases").FrameNativeProps)
type ScreenGuiProps = typeof(require("@repo/tools/typecheck/aliases").ScreenGuiProps)
type Child = typeof(require("@repo/tools/typecheck/aliases").Child)
type RobloxTypes = typeof(require("@repo/tools/typecheck/aliases").RobloxTypes)
type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type OrderedControls = typeof(require("@repo/tools/typecheck/aliases").OrderedControls)
type ReadOnlyValue<T> = typeof(require("@repo/src/vendor/compose/core").accumulator<<T, number>>(nil :: never))
type Use = <T>(ReadOnlyValue<T>) -> T
local Facet = require("../src")
local VerifyRoblox = require("../tools/vendor/verify/src/roblox")
local Compose: ComposeModule = Facet.Compose
local nativeApp = require("./native_app")
local authoringMotion = require("./authoring_motion")
type RampState = {
	read Host: RobloxHost,
	read types: RobloxTypes,
	read runtime: ComposeRuntime,
	read target: Instance,
	read frame: (number?) -> (),
}
type BenchRow = { id: string, name: string }
type BenchSort = { column: string, direction: "ascending" | "descending" }

export type Scenario = {
	name: string,
	requirement: string,
	setup: () -> any,
	run: (any) -> (),
	teardown: ((any) -> ())?,
	samples: number?,
	warmup: number?,
}

local scenarios: { Scenario } = {}
local function add(
	name: string,
	setup: () -> any,
	run: (any) -> (),
	options: { requirement: string?, teardown: ((any) -> ())?, samples: number?, warmup: number? }?
)
	local scenario: Scenario = {
		name = name,
		requirement = if options and options.requirement then options.requirement else "UI-PERF-001",
		setup = setup,
		run = run,
		teardown = options and options.teardown,
		samples = options and options.samples,
		warmup = options and options.warmup,
	}
	scenario.name = name
	scenario.requirement = scenario.requirement or "UI-PERF-001"
	scenario.setup = setup
	scenario.run = run
	scenario.teardown = scenario.teardown or function(state)
		state.dispose()
	end
	table.insert(scenarios, scenario)
end

local function reactive(setup: ({ [string]: any }) -> ()): { [string]: any }
	local state: { [string]: any } = {}
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
		local rounded = Compose.formula(function(use: Use)
			return math.floor(use(state.speed))
		end)
		local label = Compose.formula(function(use: Use)
			return `{use(rounded)} sps`
		end)
		Compose.owner.watchStatic(state.owner, label, function()
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
	local owner = Compose.owner.createChild(state.owner)
	Compose.withOwner(owner, function()
		local draft, status = Compose.cell(false), Compose.cell("idle")
		local label = Compose.formula(function(use: Use)
			return `music: {use(draft) and "on" or "off"} ({use(status)})`
		end)
		Compose.owner.watchStatic(owner, label, function() end)
		draft:set(true)
		status:set("confirmed")
	end)
	Compose.owner.dispose(owner)
end, { requirement = "UI-LIFE-002" })

add("collection-mutation", function()
	return reactive(function(state)
		state.items, state.keys, state.n = {}, {}, 50
		state.apply = function(keys: { string })
			local wanted: { [string]: boolean } = {}
			for _, key in keys do
				wanted[key] = true
			end
			for key, owner in state.items do
				if not wanted[key] then
					Compose.owner.dispose(owner)
					state.items[key] = nil
				end
			end
			for _, key in keys do
				if state.items[key] == nil then
					local owner = Compose.owner.createChild(state.owner)
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

add("collection-selection-update", function()
	local world = nativeApp()
	local items: { BenchRow } = {}
	for index = 1, 2048 do
		items[index] = { id = `r{index}`, name = `Row {index}` }
	end
	local selection: Facet.Value<{ [string]: boolean }> = Compose.cell({ r1 = true })
	local Host = world.Host
	world.runtime.mount(function()
		local spec: Facet.KeyedCollectionSpec<BenchRow, string> = {
			from = items,
			key = "id",
			selection = selection,
			selectionMode = "single",
			itemSize = 40,
			render = function(current)
				return Host.TextLabel {
					Text = function(use: Use): string
						return use(current).name
					end,
				}
			end,
		}
		return world.UI.VirtualList(spec)
	end, world.target)
	world.frame()
	return { selection = selection, n = 0, frame = world.frame, dispose = world.dispose }
end, function(state)
	state.n += 1
	local key = `r{(state.n - 1) % 2048 + 1}`
	state.selection:set({ [key] = true })
	state.frame()
	assert(state.selection:peek()[key] == true, "valid selection was pruned")
end, { requirement = "UI-RUNTIME-002", samples = 500, warmup = 50 })

add("sparse-update-under-load", function()
	return reactive(function(state)
		state.signals, state.n = {}, 0
		for index = 1, 200 do
			local value = Compose.cell(index)
			local doubled = Compose.formula(function(use: Use)
				return use(value) * 2
			end)
			Compose.owner.watchStatic(state.owner, doubled, function() end)
			table.insert(state.signals, value)
		end
	end)
end, function(state)
	state.n += 1
	state.signals[1]:set(1000 + state.n)
end)

add("reserved-slot-record-update", function()
	local world = nativeApp()
	local items: { BenchRow } = {}
	local slots: { string } = {}
	for index = 1, 128 do
		items[index] = { id = `r{index}`, name = `Row {index}` }
		slots[index] = items[index].id
	end
	local rows = Compose.cell(items)
	local labels: { [string]: TextLabel } = {}
	local Host = world.Host
	world.runtime.mount(function()
		local spec: Facet.KeyedCollectionSpec<BenchRow, string> = {
			from = rows,
			key = "id",
			slots = slots,
			mode = "all",
			itemSize = 40,
			render = function(current, _placement, key)
				local label = Host.TextLabel {
					Text = function(use: Use): string
						return use(current).name
					end,
				}
				Compose.watch(function(use: Use)
					labels[if type(key) == "string" then key else use(key)] = label
				end)
				return label
			end,
		}
		return world.UI.VirtualList(spec)
	end, world.target)
	world.frame()
	return { rows = rows, labels = labels, n = 0, frame = world.frame, dispose = world.dispose }
end, function(state)
	state.n += 1
	local current: { BenchRow } = state.rows:peek()
	local rows = table.clone(current)
	local index = (state.n - 1) % #rows + 1
	local previous = rows[index]
	local name = `Updated {state.n}`
	rows[index] = { id = previous.id, name = name }
	state.rows:set(rows)
	state.frame()
	assert(state.labels[previous.id].Text == name, "reserved slot did not publish its updated record")
end, { requirement = "UI-RUNTIME-002", samples = 200, warmup = 20 })

add("mounted-slice-update-storm", function()
	local world = nativeApp()
	world.speed, world.n = Compose.cell(0), 0
	world.runtime.mount(function()
		return world.Host.ScreenGui {
			world.Host.TextLabel {
				Text = function(use: Use)
					return `{use(world.speed)} sps`
				end,
				TextSize = 18,
			},
			world.UI.Button { label = "Boost", onActivate = function() end },
		}
	end, world.target)
	return world
end, function(state)
	state.n += 1
	for index = 1, 50 do
		state.speed:set(state.n * 50 + index)
	end
	state.frame()
end)

local function rampTree(Host: RobloxHost, depth: number, index: number): GuiObject
	if depth == 0 then
		return Host.TextLabel { Name = `T{index}`, Text = "leaf" }
	end
	local children: { Name: string, [number]: Child } = { Name = `V{index}`, Host.UIListLayout {} }
	for child = 1, 3 do
		table.insert(children, rampTree(Host, depth - 1, child))
	end
	return Host.Frame((children :: unknown) :: FrameProps)
end
local rampSetup: () -> RampState = nativeApp
for _, inherited in { false, true } do
	add(if inherited then "mount-ramp-inherited" else "mount-ramp", rampSetup, function(state: RampState)
		local stop = state.runtime.mount(function(): ScreenGui
			local color = if inherited
				then state.types.Color3.fromRGB(119, 190, 255)
				else state.types.Color3.new(1, 1, 1)
			local group: CanvasGroup = state.Host.CanvasGroup {
				Interactable = not inherited,
				GroupColor3 = color,
				rampTree(state.Host, 7, 1),
			}
			return state.Host.ScreenGui { group }
		end, state.target)
		stop()
		state.frame()
		assert(#state.target:GetChildren() == 0, "mount ramp leaked a screen")
	end, { samples = 60, warmup = 5 })
end

local function tableState(resizing: boolean)
	local world = nativeApp({ viewport = { w = 800, h = 600 } })
	local items: { BenchRow } = {}
	for index = 1, 8 do
		items[index] = { id = `r{index}`, name = `Racer {index}` }
	end
	world.rows, world.selected, world.n = Compose.cell(items), Compose.cell({}), if resizing then 0 else 8
	world.widths = Compose.cell({ name = 600, n = 48 })
	world.runtime.mount(function()
		local columns: { Facet.TableColumn<BenchRow, string> } = {
			{
				id = "name",
				label = "Racer",
				minWidth = 80,
				resizable = true,
				render = function(current: ReadOnlyValue<BenchRow>): GuiObject
					return world.Host.TextLabel {
						TextSize = 14,
						Text = function(use: Use)
							return use(current).name
						end,
					}
				end,
			},
			{
				id = "n",
				label = "N",
				width = 48,
				render = function(current: ReadOnlyValue<BenchRow>): GuiObject
					return world.Host.TextLabel {
						TextSize = 14,
						Text = function(use: Use)
							return use(current).name
						end,
					}
				end,
			},
		}
		local spec: Facet.KeyedTableSpec<BenchRow, string> = {
			from = world.rows,
			key = function(item: BenchRow): string
				return item.id
			end,
			columns = columns,
			itemSize = 40,
			header = resizing == true,
			selectionMode = if resizing then "none" else "multiple",
			selection = world.selected,
			widths = world.widths,
		}
		local tableNode = world.UI.Table(spec)
		world.tableNode = tableNode
		return world.Host.ScreenGui { tableNode }
	end, world.target)
	world.engine.environment.poke(world.tableNode, "AbsoluteSize", world.types.Vector2.new(800, 600))
	for _, child in world.tableNode:GetChildren() do
		if child.Name == "Body" then
			world.engine.environment.poke(child, "AbsoluteWindowSize", world.types.Vector2.new(800, 600))
		end
	end
	world.frame()
	return world
end
add("table-mutation", function()
	return tableState(false)
end, function(state)
	state.n += 1
	local current: { BenchRow } = state.rows:peek()
	local items = table.clone(current)
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

local function sortableTable()
	local world = nativeApp()
	local items: { BenchRow } = {}
	for index = 1, 512 do
		items[index] = { id = `r{index}`, name = string.format("Racer %04d", index) }
	end
	local initialSort: BenchSort? = nil
	local sort: Facet.Value<BenchSort?> = Compose.cell(initialSort)
	local rows = Compose.cell(items)
	local controls: OrderedControls = {}
	local label: TextLabel? = nil
	local Host = world.Host
	world.runtime.mount(function()
		local columns: { Facet.TableColumn<BenchRow, string> } = {
			{
				id = "name",
				value = function(item: BenchRow): string
					return string.lower(item.name)
				end,
				render = function(current: ReadOnlyValue<BenchRow>): GuiObject
					local node = Host.TextLabel {
						Text = function(use: Use): string
							return use(current).name
						end,
					}
					if current:peek().id == "r1" then
						label = node
					end
					return node
				end,
			},
		}
		local spec: Facet.KeyedTableSpec<BenchRow, string> = {
			Name = "BenchTable",
			from = rows,
			key = function(item: BenchRow): string
				return item.id
			end,
			columns = columns,
			itemSize = 40,
			sort = sort,
			controls = controls,
		}
		return world.UI.Table(spec)
	end, world.target)
	local tableNode = assert(VerifyRoblox.assertInstance(world.target):FindFirstChild("BenchTable"))
	world.engine.environment.poke(
		assert(tableNode:FindFirstChild("Body")),
		"AbsoluteWindowSize",
		world.types.Vector2.new(800, 160)
	)
	world.frame()
	return {
		rows = rows,
		sort = sort,
		controls = controls,
		label = assert(label),
		n = 0,
		frame = world.frame,
		dispose = world.dispose,
	}
end

add("table-sort-values", sortableTable, function(state)
	state.n += 1
	local descending = state.n % 2 == 0
	state.sort:set({ column = "name", direction = if descending then "descending" else "ascending" })
	state.frame()
	assert(state.controls.indexOfKey("r1") == (if descending then 512 else 1), "table sort lost its row order")
end, { requirement = "UI-RUNTIME-002", samples = 500, warmup = 50 })

add("table-source-refresh", sortableTable, function(state)
	state.n += 1
	local current: { BenchRow } = state.rows:peek()
	local rows = table.clone(current)
	local name = `Racer {state.n}`
	rows[1] = { id = "r1", name = name }
	state.rows:set(rows)
	state.frame()
	assert(state.label.Text == name and state.controls.indexOfKey("r1") == 1, "table refresh lost its updated row")
end, { requirement = "UI-RUNTIME-002", samples = 500, warmup = 50 })

local function descendant(node: Instance, className: string): Instance?
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
	world.engine.environment.poke(world.drag.Parent.Parent, "AbsoluteSize", world.types.Vector2.new(600, 40))
	return world
end, function(state)
	state.n += 1
	local direction = if state.n % 2 == 0 then 1 else -1
	local initialWidth = state.widths:peek().name
	state.engine.environment.poke(state.drag.Parent.Parent, "AbsoluteSize", state.types.Vector2.new(initialWidth, 40))
	state.drag.DragStart:Fire(state.types.Vector2.new(600, 10))
	for index = 1, 8 do
		state.drag.DragContinue:Fire(state.types.Vector2.new(600 + direction * index * 5, 10))
		state.frame()
	end
	state.drag.DragEnd:Fire(state.types.Vector2.new(600 + direction * 40, 10))
	assert(state.widths:peek().name == initialWidth + direction * 40, "resize workload did not update its column")
	state.frame()
end)

add("billboard-nameplate-storm", function()
	local world = nativeApp()
	world.health, world.n = Compose.cell("100"), 0
	world.runtime.mount(function()
		return world.Host.BillboardGui {
			Size = world.types.UDim2.fromOffset(300, 96),
			world.Host.TextLabel { Text = "Racer", TextSize = 18 },
			world.Host.TextLabel { Text = world.health, TextSize = 14 },
		}
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
		return world.UI.TextInput {
			value = world.value,
			placeholder = "type",
			maxLength = 64,
			onChange = function() end,
		}
	end, world.target)
	world.field = field
	return world
end, function(state)
	state.field.Focused:Fire()
	local text = "The quick brown fox 0123"
	for index = 1, #text do
		state.field.Text = string.sub(text, 1, index)
	end
	state.frame()
	state.field.FocusLost:Fire(false, { KeyCode = state.types.Enum.KeyCode.Escape })
	assert(state.builds == 1 and not state.field:isDestroyed(), "typing rebuilt the field")
	state.value:set("")
	state.frame()
end)

add("outline-measured-update", function()
	local world = nativeApp()
	local items: { BenchRow } = {}
	local initial: { [string]: number } = {}
	for index = 1, 2048 do
		local key = `r{index}`
		items[index] = { id = key, name = `Row {index}` }
		initial[key] = 40
	end
	initial.r1 = 60
	local measured = Compose.cell(initial)
	local Host = world.Host
	world.runtime.mount(function()
		local spec: Facet.KeyedOutlineSpec<BenchRow, string> = {
			Name = "BenchOutline",
			from = items,
			key = "id",
			children = function(): { BenchRow }?
				return nil
			end,
			itemSize = 40,
			measured = measured,
			overscan = 0,
			render = function(current)
				return Host.TextLabel {
					Text = function(use: Use): string
						return use(current).name
					end,
				}
			end,
		}
		return world.UI.Outline(spec)
	end, world.target)
	local root = assert(VerifyRoblox.assertInstance(world.target):FindFirstChild("BenchOutline"))
	world.engine.environment.poke(root, "AbsoluteWindowSize", world.types.Vector2.new(800, 1205))
	world.frame()
	local row = assert(root:FindFirstChild("r1", true))
	local content = row:FindFirstChild("Content")
	assert(content ~= nil)
	local size = content.Size
	assert(typeof(size) == "UDim2")
	return {
		measured = measured,
		content = content,
		n = 0,
		frame = world.frame,
		dispose = world.dispose,
	}
end, function(state)
	state.n += 1
	local height = if state.n % 2 == 0 then 60 else 64
	local current: { [string]: number } = state.measured:peek()
	local sizes = table.clone(current)
	sizes.r1 = height
	state.measured:set(sizes)
	state.frame()
	local size = state.content.Size
	assert(typeof(size) == "UDim2" and size.Y.Offset == height, "outline content lost its measured height")
end, { requirement = "UI-RUNTIME-002", samples = 500, warmup = 50 })

add("timer-readout-storm", function()
	local world = nativeApp()
	local label: TextLabel? = nil
	world.runtime.mount(function()
		local children: ScreenGuiProps = {}
		for index = 1, 64 do
			local timer = world.UI.Timer { start = 0 }
			children[index] = timer
			if index == 1 then
				label = timer
			end
		end
		return world.Host.ScreenGui(children)
	end, world.target)
	world.frame()
	return {
		frame = world.frame,
		now = assert(world.runtime.host.frames).now,
		label = assert(label),
		dispose = world.dispose,
	}
end, function(state)
	for _ = 1, 6 do
		state.frame(1 / 60)
	end
	assert(state.label.Text == Facet.format.duration(state.now()), "timer readout did not follow its clock")
end, { requirement = "UI-PERF-001", samples = 500, warmup = 50 })

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
table.sort(scenarios, function(a: Scenario, b: Scenario)
	return a.name < b.name
end)
return scenarios
