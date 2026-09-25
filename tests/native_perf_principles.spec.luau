--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose
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
	local runtime = Facet.Roblox.createRuntime(engine)
	local Host = runtime.constructors
	local UI = Facet.controls(runtime, { types = engine.types })
	local D2, V2 = engine.types.UDim2, engine.types.Vector2
	local target = engine.new("Folder")
	local items, list, status =
		{}, nil, Compose.cell({
			mode = "windowed",
			direction = "vertical",
			total = 0,
			retained = 0,
			first = 0,
			last = 0,
			firstRow = 0,
			lastRow = 0,
			rowCount = 0,
			extent = 0,
			following = false,
			measured = 0,
		})
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
			render = function(current)
				local item = current:peek()
				return Host.Frame({
					Size = D2.new(1, 0, 0, 56),
					Host.ImageLabel({ Image = "rbxassetid://0", Size = D2.fromOffset(40, 40) }),
					Host.TextLabel({
						Text = function(use)
							return tostring(use(item.value))
						end,
					}),
					UI.Toggle({ value = item.ready, label = "Ready" }),
				})
			end,
			Size = D2.fromScale(1, 1),
		})
		return Host.ScreenGui({ list })
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
		end)
		t.expect(changed.writes > 0 and changed.writes < 12).toBe(true)
		t.expect(changed.creates).toBe(0)
		t.expect(changed.destroys).toBe(0)
		state.dispose()
	end)
end)
