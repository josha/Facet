--!strict

local Verify = require("../tools/vendor/verify/src/core")
local Workloads = require("../bench/comparison")
local Parity = require("../bench/comparison/parity")
local Types = require("../bench/comparison/types")
local S = require("../bench/comparison/support")
local NativeApp = require("../bench/native_app")
local createHighlight = require("../src/ui/collection_highlight")
local Facet = require("../src")

local function workload(id: string): Types.Workload
	for _, candidate in Workloads do
		if candidate.id == id then
			return candidate
		end
	end
	error("No workload: " .. id)
end

return function(harness: Verify.Harness)
	harness:suite("Facet versus bare", function()
		for _, workload in Workloads do
			harness:case(workload.id, {
				id = "native_bench_comparison::" .. workload.id,
				run = function()
					Parity(workload)
				end,
			})
		end
		harness:case("collection highlights follow multiple selection and recycled keys until disposal", {
			id = "native_bench_comparison::collection highlights follow multiple selection and recycled keys until disposal",
			run = function()
				local world = NativeApp()
				local Compose = world.Compose
				local initial: { [number]: boolean } = { [1] = true }
				local chosen = Compose.cell(initial)
				local key = Compose.cell(1)
				local state = ""
				local calls = 0
				local root = Compose.createRootOwner(function()
					createHighlight(Compose, chosen, true)(key, function(value)
						calls += 1
						state = value
					end)
				end)
				Verify.expect(state):toBe("only")
				chosen:set({ [1] = true, [2] = true })
				Verify.expect(state):toBe("selected")
				chosen:set({ [2] = true })
				Verify.expect(state):toBe("none")
				key:set(2)
				Verify.expect(state):toBe("only")
				chosen:set({ [1] = true })
				Verify.expect(state):toBe("none")
				Verify.expect(calls):toBe(5)
				local edited = chosen:peek()
				edited[1] = nil
				edited[2] = true
				chosen:set(table.clone(edited))
				Verify.expect(state):toBe("only")
				Verify.expect(calls):toBe(6)
				root.dispose()
				chosen:set({ [1] = true })
				Verify.expect(calls):toBe(6)
				world.dispose()
			end,
		})
		harness:case("selection effects run only for changed row indicators", {
			id = "native_bench_comparison::selection effects run only for changed row indicators",
			run = function()
				local world = NativeApp()
				local scene = workload("inventory-100").prepare(world, "facet")
				world.Compose.profile.start(os.clock)
				scene.step(1)
				local profile = world.Compose.profile.stop()
				Verify.expect(profile.totals.runs < 20):toBe(true)
				Verify.expect(profile.totals.schedules < 20):toBe(true)
				Verify.expect(assert(S.find(world, "1"):FindFirstChild("Content")):HasTag("facet-selected")):toBe(false)
				Verify.expect(assert(S.find(world, "2"):FindFirstChild("Content")):HasTag("facet-selected")):toBe(true)
				scene.stop()
				world.dispose()
			end,
		})
		for _, subject in
			{
				{ id = "badges-30-300-updates", member = "Visible" },
				{ id = "theme-swap-200", member = "Size" },
				{ id = "theme-swap-200", member = "CellSize" },
			}
		do
			local name = subject.id .. " does not rewrite unchanged " .. subject.member
			harness:case(name, {
				id = "native_bench_comparison::" .. name,
				run = function()
					local world = NativeApp()
					local scene = workload(subject.id).prepare(world, "facet")
					local writes = 0
					local observer = world.engine.environment.observe(function(event)
						if event.operation == "setProperty" and event.member == subject.member then
							writes += 1
						end
					end)
					scene.step(1)
					observer:Disconnect()
					Verify.expect(writes):toBe(0)
					scene.stop()
					world.dispose()
				end,
			})
		end
		harness:case("shared metrics follow height changes after the first screen is disposed", {
			id = "native_bench_comparison::shared metrics follow height changes after the first screen is disposed",
			run = function()
				local world = NativeApp()
				local theme = world.Compose.cell(Facet.themes.neutralPackage())
				local UI = Facet.controls(world.runtime, { types = world.types, theme = theme })
				local function mount(): () -> ()
					return S.mount(world, "facet", function()
						return UI.Grid "Metrics" { columns = 1, UI.Button "Action" { label = "Continue" } }
					end, function() end)
				end
				local stop = mount()
				for _, height in { 48, 56 } do
					local package = Facet.themes.neutralPackage()
					package.metrics.controlSizes.regular.height = height
					theme:set(package)
					local size = S.find(world, "Action").Size
					Verify.expect(typeof(size)):toBe("UDim2")
					Verify.expect(S.find(world, "Action").Size):toBe(world.types.UDim2.fromOffset(0, height))
					local layout = assert(S.find(world, "Metrics"):FindFirstChildWhichIsA("UIGridLayout"))
					Verify.expect(layout.CellSize):toBe(world.types.UDim2.new(1, 0, 0, height))
					stop()
					stop = mount()
				end
				stop()
				world.dispose()
			end,
		})
		harness:case("appending a keyed row keeps retained sibling orders", {
			id = "native_bench_comparison::appending a keyed row keeps retained sibling orders",
			run = function()
				local world = NativeApp()
				local scene = workload("chat-append-500").prepare(world, "facet")
				scene.step(1)
				local first = S.find(world, "Chat"):FindFirstChildWhichIsA("TextLabel", true)
				Verify.expect(first ~= nil):toBe(true)
				local writes = 0
				local observer = world.engine.environment.observe(function(event)
					if event.object == first and event.operation == "setProperty" and event.member == "LayoutOrder" then
						writes += 1
					end
				end)
				scene.step(2)
				observer:Disconnect()
				Verify.expect(writes):toBe(0)
				scene.stop()
				world.dispose()
			end,
		})
		harness:case("custom table cells retain content for a key and release it when the key changes", {
			id = "native_bench_comparison::custom table cells retain content for a key and release it when the key changes",
			run = function()
				type Item = { id: number, label: string }
				local world = NativeApp()
				local initial: { Item } = { { id = 1, label = "One" } }
				local source = world.Compose.cell(initial)
				local released = 0
				local columns: { Facet.TableColumn<Item, number> } = {
					{
						id = "label",
						label = "Label",
						render = function(current, _placement, key)
							world.Compose.cleanup(function()
								released += 1
							end)
							return world.UI.Text("Cell" .. key:peek()) {
								text = function(use: Facet.Use): string
									return use(current).label
								end,
							}
						end,
					},
				}
				local stop = S.mount(world, "facet", function()
					local spec: Facet.KeyedTableSpec<Item, number> = {
						from = source,
						key = function(item)
							return item.id
						end,
						columns = columns,
						mode = "all",
					}
					return world.UI.Table "Cells"(spec)
				end, function() end)
				local first = S.find(world, "Cell1")
				source:set({ { id = 1, label = "Updated" } })
				Verify.expect(S.find(world, "Cell1")):toBe(first)
				Verify.expect(first.Text):toBe("Updated")
				Verify.expect(released):toBe(0)
				source:set({ { id = 2, label = "Two" } })
				Verify.expect(world.engine.environment.isAlive(first)):toBe(false)
				Verify.expect(S.find(world, "Cell2").Text):toBe("Two")
				Verify.expect(released):toBe(1)
				stop()
				Verify.expect(released):toBe(2)
				world.dispose()
			end,
		})
		harness:case("parity rejects a hidden matching item", {
			id = "native_bench_comparison::parity rejects a hidden matching item",
			run = function()
				local source: Types.Workload? = nil
				for _, workload in Workloads do
					if workload.id == "shop-filter-200" then
						source = workload
						break
					end
				end
				local subject = assert(source)
				local broken: Types.Workload = {
					id = subject.id,
					iterations = subject.iterations,
					what = subject.what,
					prepare = function(world: Types.World, lane: Types.Lane): Types.Scene
						local scene = subject.prepare(world, lane)
						return {
							step = function(index: number)
								scene.step(index)
								if lane == "facet" then
									S.find(world, "Item1").Visible = false
								end
							end,
							snapshot = scene.snapshot,
							stop = scene.stop,
						}
					end,
				}
				Verify.expect(function()
					Parity(broken)
				end):toThrow("differs at checkpoint 1")
			end,
		})
	end)
end
