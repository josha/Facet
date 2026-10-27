--!strict

local Verify = require("../tools/vendor/verify/src/core")
local Workloads = require("../bench/comparison")
local Parity = require("../bench/comparison/parity")
local Types = require("../bench/comparison/types")
local S = require("../bench/comparison/support")
local NativeApp = require("../bench/native_app")
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
