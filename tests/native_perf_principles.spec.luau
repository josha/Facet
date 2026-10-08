--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type NumberCell = typeof(require("@repo/tools/typecheck/aliases").NumberCell)
	type BooleanCell = typeof(require("@repo/tools/typecheck/aliases").BooleanCell)
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local context = require("../src/ui/context")
	local Compose: ComposeModule = Facet.Compose
	local function world(count)
		local engine = engineLib.new({ recordCreated = false })
		local metrics = { writes = 0, creates = 0, destroys = 0, nodes = {} }
		local make, destroy = engine.new, engine.destroy
		engine.onWrite(function(self, key, value)
			metrics.writes += 1
			metrics.nodes[self] = true
		end)
		engine.new = function(className)
			local node = make(className)
			metrics.creates += 1
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
			return {
				writes = metrics.writes,
				creates = metrics.creates,
				destroys = metrics.destroys,
				nodes = metrics.nodes,
			}
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
				Verify.expect(#target:GetChildren()):toBe(0)
			end,
		}
	end

	verifyHarness:suite("native performance invariants", function()
		verifyHarness:case("shares ancestor visibility subscriptions until the last consumer leaves", {
			id = "native_perf_principles::native performance invariants::shares ancestor visibility subscriptions until the last consumer leaves",
			run = function()
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
				Verify.expect((engineLib.connections(node:GetPropertyChangedSignal("Visible")))):toBe(1)
				for index = 1, 39 do
					owners[index].dispose()
				end
				node.Visible = false
				Verify.expect((values[40]:peek())):toBe(false)
				Verify.expect((engineLib.connections(node:GetPropertyChangedSignal("Visible")))):toBe(1)
				owners[40].dispose()
				Verify.expect((engineLib.connections(node:GetPropertyChangedSignal("Visible")))):toBe(0)
				node.Visible = true
				local stop = Compose.createRootOwner(function()
					Verify.expect((ctx.observe.Visible(node):peek())):toBe(true)
				end, runtime.reactor)
				stop.dispose()
				Verify.expect((engineLib.connections(node:GetPropertyChangedSignal("Visible")))):toBe(0)
				runtime:dispose()
			end,
		})

		verifyHarness:case("idle heartbeat and identical state perform no native writes", {
			id = "native_perf_principles::native performance invariants::idle heartbeat and identical state perform no native writes",
			run = function()
				local state = world(400)
				state.items[2].value:set(55)
				local changed = state.delta(function()
					state.engine.heartbeat:Fire(1 / 60)
					state.items[2].value:set(55)
				end)
				Verify.expect(changed.writes):toBe(0)
				Verify.expect(changed.creates):toBe(0)
				Verify.expect(changed.destroys):toBe(0)
				state.dispose()
			end,
		})
		verifyHarness:case("toggle changes its row without mounting another node", {
			id = "native_perf_principles::native performance invariants::toggle changes its row without mounting another node",
			run = function()
				local state = world(400)
				local changed = state.delta(function()
					state.items[1].ready:set(true)
					state.engine.heartbeat:Fire(1 / 60)
				end)
				Verify.expect(changed.writes > 0 and changed.writes < 12):toBe(true)
				Verify.expect(changed.creates):toBe(0)
				Verify.expect(changed.destroys):toBe(0)
				state.dispose()
			end,
		})
	end)
end
