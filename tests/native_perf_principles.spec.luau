--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type NumberCell = typeof(require("@repo/tools/typecheck/aliases").NumberCell)
type BooleanCell = typeof(require("@repo/tools/typecheck/aliases").BooleanCell)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local context = require("../src/ui/context")
local Compose: ComposeModule = Facet.Compose
local function world(count)
	local engine = engineLib.new({ recordCreated = false })
	local metrics = { writes = 0, creates = 0, destroys = 0, nodes = {} }
	local make, destroy = engine.new, engine.destroy
	engine.new = function(className)
		local node = make(className)
		metrics.creates += 1
		local meta = getmetatable(node)
		local write = meta.__newindex
		meta.__newindex = function(self, key, value)
			metrics.writes += 1
			metrics.nodes[self] = true
			write(self, key, value)
		end
		return node
	end
	engine.destroy = function(node)
		metrics.destroys += 1
		destroy(node)
	end
	local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
	local Host = (runtime.constructors :: unknown) :: RobloxHost
	local UI = Facet.controls(runtime, { types = engine.types })
	local D2, V2 = engine.types.UDim2, engine.types.Vector2
	local target = engine.new("Folder")
	type Item = {
		id: string,
		value: NumberCell,
		ready: BooleanCell,
	}
	local items: { Item } = {}
	local list
	local status = require("./lib/cells").collectionStatus()
	for index = 1, count do
		items[index] = { id = tostring(index), value = Compose.cell(index), ready = Compose.cell(false) }
	end
	local stop = runtime.mount(function()
		list = UI.VirtualList({
			from = items,
			key = function(item)
				return item.id
			end,
			itemSize = 56,
			status = status,
			render = function(current: Readable<Item>): GuiObject
				local item = current:peek()
				return Host.Frame({
					Size = D2.new(1, 0, 0, 56),
					Host.ImageLabel({ Image = "rbxassetid://0", Size = D2.fromOffset(40, 40) }) :: unknown,
					Host.TextLabel({
						Text = function(use: Use)
							return tostring(use(item.value))
						end,
					}),
					UI.Toggle({ value = item.ready, label = "Ready" }),
				})
			end,
			Size = D2.fromScale(1, 1),
		})
		return Host.ScreenGui({ list :: unknown })
	end, target)
	list.AbsoluteSize = V2.new(480, 640)
	list.AbsoluteWindowSize = V2.new(480, 640)
	local function delta(action)
		metrics.writes, metrics.creates, metrics.destroys, metrics.nodes = 0, 0, 0, {}
		action()
		return { writes = metrics.writes, creates = metrics.creates, destroys = metrics.destroys, nodes = metrics.nodes }
	end
	return {
		items = items,
		list = list,
		status = status,
		engine = engine,
		delta = delta,
		dispose = function()
			stop()
			runtime:dispose()
			t.expect(#target:GetChildren()).toBe(0)
		end,
	}
end

t.describe("native performance invariants", function()
	t.it("shares ancestor visibility subscriptions until the last consumer leaves", function()
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local ctx = context(Compose, runtime, { types = engine.types })
		local node = engine.new("Frame")
		local owners, values = {}, {}
		for index = 1, 40 do
			owners[index] = Compose.createRootOwner(function()
				values[index] = ctx.observe.Visible(node)
			end, runtime.reactor)
		end
		t.expect(node:GetPropertyChangedSignal("Visible").count()).toBe(1)
		for index = 1, 39 do
			owners[index].dispose()
		end
		node.Visible = false
		t.expect(values[40]:peek()).toBe(false)
		t.expect(node:GetPropertyChangedSignal("Visible").count()).toBe(1)
		owners[40].dispose()
		t.expect(node:GetPropertyChangedSignal("Visible").count()).toBe(0)
		node.Visible = true
		local stop = Compose.createRootOwner(function()
			t.expect(ctx.observe.Visible(node):peek()).toBe(true)
		end, runtime.reactor)
		stop.dispose()
		t.expect(node:GetPropertyChangedSignal("Visible").count()).toBe(0)
		runtime:dispose()
	end)

	t.it("one bound value writes one native property at100800and3200rows", function()
		for _, count in { 100, 800, 3200 } do
			local state = world(count)
			local changed = state.delta(function()
				state.items[3].value:set(4242)
			end)
			t.expect(changed.writes).toBe(1)
			t.expect(changed.creates).toBe(0)
			t.expect(changed.destroys).toBe(0)
			state.dispose()
		end
	end)
	t.it("scroll mountwork is independent of logical list size", function()
		local baseline
		for _, count in { 100, 800, 3200 } do
			local state = world(count)
			local changed = state.delta(function()
				state.list.CanvasPosition = state.engine.types.Vector2.new(0, 137)
			end)
			t.expect(state.status:peek().retained < 20).toBe(true)
			if baseline then
				t.expect(changed.creates).toBe(baseline.creates)
				t.expect(changed.writes).toBe(baseline.writes)
				t.expect(changed.destroys).toBe(baseline.destroys)
			end
			baseline = changed
			state.dispose()
		end
	end)
	t.it("idle heartbeat and identical state perform no native writes", function()
		local state = world(400)
		state.items[2].value:set(55)
		local changed = state.delta(function()
			state.engine.heartbeat.fire(1 / 60)
			state.items[2].value:set(55)
		end)
		t.expect(changed.writes).toBe(0)
		t.expect(changed.creates).toBe(0)
		t.expect(changed.destroys).toBe(0)
		state.dispose()
	end)
	t.it("toggle changes its row without mounting another node", function()
		local state = world(400)
		local changed = state.delta(function()
			state.items[1].ready:set(true)
			state.engine.heartbeat.fire(1 / 60)
		end)
		t.expect(changed.writes > 0 and changed.writes < 12).toBe(true)
		t.expect(changed.creates).toBe(0)
		t.expect(changed.destroys).toBe(0)
		state.dispose()
	end)
end)
