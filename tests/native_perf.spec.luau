--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)

	local scenarios = require("../bench/scenarios")
	local scenes = require("../bench/perf_scenes")
	local profiles = require("../bench/perf_profiles")
	local registered = {}
	for _, scene in scenes do
		registered[scene.name] = scene
	end

	verifyHarness:suite("native benchmark workload contract", function()
		verifyHarness:case("keeps every controlled sampling cadence fixed to the historical inventory", {
			id = "native_perf::native benchmark workload contract::keeps every controlled sampling cadence fixed to the historical inventory",
			run = function()
				local sampling = {
					{ name = "hud-binding-storm", samples = 240, warmup = 60 },
					{ name = "settings-churn", samples = 240, warmup = 60 },
					{ name = "scroll-focus-traversal", samples = 240, warmup = 60 },
					{ name = "collection-mutation", samples = 240, warmup = 60 },
					{ name = "animation-interruption", samples = 240, warmup = 60 },
					{ name = "locale-textsize-change", samples = 240, warmup = 60 },
					{ name = "async-image-burst", samples = 240, warmup = 60 },
					{ name = "shadow-storm", samples = 240, warmup = 60 },
					{ name = "virtual-list-scroll", samples = 160, warmup = 40 },
					{ name = "native-scroll-drag", samples = 160, warmup = 40 },
					{ name = "dense-hud", samples = 160, warmup = 40 },
					{ name = "stylesheet-state-churn", samples = 160, warmup = 40 },
					{ name = "async-image-grid", samples = 120, warmup = 30 },
					{ name = "screen-lifecycle-churn", samples = 120, warmup = 30 },
					{ name = "theme-swap-flat", samples = 160, warmup = 40 },
					{ name = "theme-swap-metrics", samples = 160, warmup = 40 },
					{ name = "dense-motion", samples = 160, warmup = 40 },
					{ name = "control-motion", samples = 160, warmup = 40 },
					{ name = "theme-swap-assets", samples = 160, warmup = 40 },
					{ name = "lab-dense-scroll", samples = 120, warmup = 30 },
					{ name = "lab-collection-churn", samples = 100, warmup = 25 },
					{ name = "adaptive-navigation-images", samples = 120, warmup = 20 },
					{ name = "navigation-customization", samples = 120, warmup = 20 },
					{ name = "alert-present-dismiss", samples = 120, warmup = 30 },
					{ name = "picker-menu-open-close", samples = 120, warmup = 30 },
					{ name = "picker-segmented-textsize", samples = 120, warmup = 30 },
					{ name = "radial-menu-open-close", samples = 120, warmup = 30 },
				}
				Verify.expect(#sampling):toBe(#scenes)
				for _, record in sampling do
					local scene = assert(registered[record.name])
					Verify.expect(scene.samples):toBe(record.samples)
					Verify.expect(scene.warmup):toBe(record.warmup)
				end
			end,
		})

		verifyHarness:case("counts segment controls instead of hidden caption measurements", {
			id = "native_perf::native benchmark workload contract::counts segment controls instead of hidden caption measurements",
			run = function()
				local scene = registered["picker-segmented-textsize"]
				local state = scene.setup(profiles.get("floorAndroid"))
				local ok, err = pcall(function()
					local hidden = 0
					for _, node in state.target:GetDescendants() do
						if
							node.ClassName == "TextLabel"
							and node.Name == "CaptionMeasure"
							and node.TextTransparency == 1
							and not node.Interactable
						then
							hidden += 1
						end
					end
					Verify.expect(hidden):toBe(3)
					local measurement = assert(scene.extras(state).segmented)
					Verify.expect(measurement.segments):toBe(3)
					Verify.expect(measurement.textSizeBefore ~= nil):toBe(true)
					Verify.expect(measurement.textSizeAfter ~= measurement.textSizeBefore):toBe(true)
				end)
				scene.teardown(state)
				assert(ok, err)
			end,
		})

		verifyHarness:case("preserves binding counts, one-hot style mutation and exact collection records", {
			id = "native_perf::native benchmark workload contract::preserves binding counts, one-hot style mutation and exact collection records",
			run = function()
				local function check(name, callback)
					local scene = registered[tostring(name)]
					local state = scene.setup(profiles.get("floorAndroid"))
					callback(state.workload, function()
						return scene.run(state)
					end, state)
					scene.teardown(state)
				end
				check("hud-binding-storm", function(w, step, state)
					local writes = 0
					local connection = state.target
						:FindFirstChildWhichIsA("TextLabel", true)
						:GetPropertyChangedSignal("Text")
						:Connect(function()
							writes += 1
						end)
					step()
					Verify.expect((w.speed:peek())):toBe(100)
					Verify.expect(writes):toBe(50)
					connection:Disconnect()
				end)
				check("stylesheet-state-churn", function(w, step)
					Verify.expect(#w.observed):toBe(40)
					Verify.expect((w.observed[1]:peek())):toBe(true)
					step()
					for index, cell in w.observed do
						Verify.expect((cell:peek())):toBe(index == 2)
					end
					Verify.expect(w.tagCount > 0):toBe(true)
				end)
				check("collection-mutation", function(w, step)
					Verify.expect(#w.rows:peek()):toBe(8)
					step()
					Verify.expect(w.rows:peek()[1].id):toBe("r9")
					Verify.expect(w.rows:peek()[1].name):toBe("Racer 9")
					Verify.expect(w.selected:peek().r9):toBe(true)
					step()
					Verify.expect(w.rows:peek()[2].id):toBe("r10")
					Verify.expect(w.selected:peek().r9):toBe(true)
				end)
				check("animation-interruption", function(w, step, state)
					step()
					step()
					Verify.expect((w.value:peek())):toBeCloseTo(1 - 0.65 ^ 6, 1e-4)
					Verify.expect((state.engine.clock())):toBeCloseTo(12 / 60, 1e-4)
				end)
			end,
		})

		verifyHarness:case("preserves twelve plain burst images and retained async-grid owners", {
			id = "native_perf::native benchmark workload contract::preserves twelve plain burst images and retained async-grid owners",
			run = function()
				for _, name in { "async-image-burst", "async-image-grid" } do
					local scene = registered[tostring(name)]
					local state = scene.setup(profiles.get("floorAndroid"))
					local w = state.workload
					scene.run(state)
					Verify.expect(#w.images):toBe(12)
					Verify.expect(w.async.completed):toBe(4)
					if name == "async-image-grid" then
						Verify.expect(w.close ~= nil):toBe(true)
						Verify.expect(#w.requests):toBe(8)
						Verify.expect((w.images[1]:peek())):toBe("rbxthumb://gen=1&id=1")
					else
						Verify.expect((w.images[12]:peek())):toBe("rbxassetid://112")
						local count = 0
						for _, node in state.target:GetDescendants() do
							if node.ClassName == "ImageLabel" then
								count += 1
							end
						end
						Verify.expect(count):toBe(12)
					end
					scene.run(state)
					Verify.expect(w.async.completed):toBe(8)
					Verify.expect(w.async.dropped):toBe(8)
					if name == "async-image-burst" then
						Verify.expect(w.async.stale):toBe(8)
					end
					scene.teardown(state)
				end
			end,
		})

		verifyHarness:case("measures a dense HUD activation through its committed native text", {
			id = "native_perf::native benchmark workload contract::measures a dense HUD activation through its committed native text",
			run = function()
				local scene = registered["dense-hud"]
				local state = scene.setup(profiles.get("floorAndroid"))
				Verify.expect(#state.workload.observed):toBe(8)
				local phases = scene.run(state)
				Verify.expect(phases.inputToVisible > 0):toBe(true)
				Verify.expect(state.workload.boostText.Text):toBe("Boost x1")
				for _, button in state.workload.nodes do
					button.Activated:Fire()
				end
				Verify.expect((state.workload.boosts:peek())):toBe(5)
				Verify.expect(state.workload.boostText.Text):toBe("Boost x5")
				local extras = scene.extras(state)
				Verify.expect(extras.activationCount):toBe(5)
				Verify.expect(extras.activationText):toBe("Boost x5")
				scene.teardown(state)
			end,
		})

		verifyHarness:case("retains default async placeholders while custom content follows loading ownership", {
			id = "native_perf::native benchmark workload contract::retains default async placeholders while custom content follows loading ownership",
			run = function()
				local world = require("../bench/native_app")()
				local Compose: ComposeModule = world.Compose
				local source, requests = Compose.cell("one"), {}
				local built, disposed = 0, 0
				local function loader(content, resolve, reject)
					requests[content] = { resolve = resolve, reject = reject }
				end
				local _, root: any = world.runtime.mount(function()
					return world.UI.AsyncImage({ source = source, loader = loader, failureLabel = "Unavailable" })
				end, world.target)
				local placeholder, image = root:FindFirstChild("Placeholder"), root:FindFirstChild("Image")
				Verify.expect((placeholder:HasTag("facet-skeleton"))):toBe(true)
				requests.one.resolve("one")
				Verify.expect(placeholder.Visible):toBe(false)
				Verify.expect(image.Visible):toBe(true)
				source:set("two")
				Verify.expect(placeholder.Visible):toBe(true)
				Verify.expect(image.Visible):toBe(false)
				requests.two.reject("missing")
				Verify.expect(placeholder:FindFirstChildWhichIsA("TextLabel").Text):toBe("Unavailable")
				source:set("three")
				requests.three.resolve("three")
				Verify.expect((root:FindFirstChild("Placeholder"))):toBe(placeholder)
				Verify.expect((root:FindFirstChild("Image"))):toBe(image)
				Verify.expect((placeholder:FindFirstChildWhichIsA("TextLabel"))):toBe(nil)
				local customSource = Compose.cell("custom-one")
				world.runtime.mount(function()
					return world.UI.AsyncImage({
						source = customSource,
						loader = loader,
						placeholder = function(): Instance
							built += 1
							Compose.cleanup(function()
								disposed += 1
							end)
							return world.Host.Frame "Custom" {}
						end,
					})
				end, world.target)
				Verify.expect(built):toBe(1)
				requests["custom-one"].resolve("custom-one")
				Verify.expect(disposed):toBe(1)
				customSource:set("custom-two")
				Verify.expect(built):toBe(2)
				world.dispose()
				Verify.expect(disposed):toBe(2)
				Verify.expect((placeholder:isDestroyed())):toBe(true)
			end,
		})

		verifyHarness:case("retains one hundred idle native shadows and still applies direct mutations", {
			id = "native_perf::native benchmark workload contract::retains one hundred idle native shadows and still applies direct mutations",
			run = function()
				local scene = registered["shadow-storm"]
				local state = scene.setup(profiles.get("floorAndroid"))
				local shadows = {}
				for _, node in state.target:GetDescendants() do
					if node.ClassName == "UIShadow" then
						table.insert(shadows, node)
					end
				end
				Verify.expect(#shadows):toBe(100)
				local changes = 0
				local connection = shadows[1]:GetPropertyChangedSignal("Transparency"):Connect(function()
					changes += 1
				end)
				for _ = 1, 3 do
					scene.run(state)
				end
				Verify.expect((state.engine.clock())):toBeCloseTo(3 / 60, 1e-4)
				Verify.expect(changes):toBe(0)
				for _, value in state.workload.observed do
					value:set(0.25)
				end
				Verify.expect(changes):toBe(1)
				for _, shadow in shadows do
					Verify.expect(shadow.Transparency):toBe(0.25)
					Verify.expect(shadow.Parent.BackgroundTransparency):toBe(0.25)
				end
				connection:Disconnect()
				scene.teardown(state)
				for _, shadow in shadows do
					Verify.expect((shadow:isDestroyed())):toBe(true)
				end
			end,
		})

		verifyHarness:case("preserves subscribed ancestry ordering and cleanup after unobserved moves", {
			id = "native_perf::native benchmark workload contract::preserves subscribed ancestry ordering and cleanup after unobserved moves",
			run = function()
				for _, recordCreated in { false, true } do
					local engine = require("./lib/native_engine").new({ recordCreated = recordCreated })
					local first, second, root: any, child, leaf =
						engine.new("Folder"),
						engine.new("Folder"),
						engine.new("Frame"),
						engine.new("Frame"),
						engine.new("TextLabel")
					first.Name, second.Name, root.Name, child.Name, leaf.Name =
						"First", "Second", "Root", "Child", "Leaf"
					root.Parent, child.Parent, leaf.Parent = first, root, child
					root.Parent = second
					root.Parent = first
					local log, connections = {}, {}
					local childEvents = {}
					local removed = first.ChildRemoved:Connect(function(node)
						Verify.expect(node.Parent):toBe(second)
						table.insert(childEvents, "removed")
					end)
					local added = second.ChildAdded:Connect(function(node)
						Verify.expect(node.Parent):toBe(second)
						table.insert(childEvents, "added")
					end)
					for _, node in { root, child, leaf } do
						table.insert(
							connections,
							node.AncestryChanged:Connect(function(changed, parent)
								Verify.expect(changed == node or node:IsDescendantOf(changed)):toBe(true)
								Verify.expect(parent):toBe(changed.Parent)
								table.insert(log, `A:{changed.Name}:{if parent then parent.Name else "nil"}`)
							end)
						)
						table.insert(
							connections,
							node.Destroying:Connect(function()
								table.insert(log, `D:{node.Name}:{if node.Parent then node.Parent.Name else "nil"}`)
							end)
						)
					end
					root.Parent = second
					Verify.expect((table.concat(childEvents, "|"))):toBe("removed|added")
					removed:Disconnect()
					added:Disconnect()
					Verify.expect((table.concat(log, "|"))):toBe("A:Root:Second|A:Root:Second|A:Root:Second")
					table.clear(log)
					connections[3]:Disconnect()
					root:Destroy()
					Verify.expect((table.concat(log, "|")))
						:toBe("D:Root:Second|A:Root:nil|A:Root:nil|D:Child:Root|A:Child:nil|D:Leaf:Child|A:Leaf:nil")
					for _, connection in connections do
						connection:Disconnect()
					end
					table.clear(log)
					for _, node in { root, child, leaf } do
						Verify.expect((require("./lib/native_engine").connections(node.AncestryChanged))):toBe(0)
						Verify.expect((require("./lib/native_engine").connections(node.Destroying))):toBe(0)
						node.AncestryChanged:Fire(node, nil)
						node.Destroying:Fire()
					end
					Verify.expect(#log):toBe(0)
					first:Destroy()
					second:Destroy()
				end
			end,
		})

		verifyHarness:case("keeps cached reflection defaults independent across native fixture instances", {
			id = "native_perf::native benchmark workload contract::keeps cached reflection defaults independent across native fixture instances",
			run = function()
				local engine = require("./lib/native_engine").new({ recordCreated = false })
				local first, second = engine.new("TextLabel"), engine.new("TextLabel")
				local initial = second.Text
				first.Text = "Changed"
				Verify.expect(second.Text):toBe(initial)
				Verify.expect((first:IsA("GuiObject"))):toBe(true)
				Verify.expect((second:IsA("TextButton"))):toBe(false)
				first:Destroy()
				local third = engine.new("TextLabel")
				Verify.expect(third.Text):toBe(initial)
				Verify.expect((third:IsA("GuiObject"))):toBe(true)
				Verify.expect((second:isDestroyed())):toBe(false)
				second:Destroy()
				third:Destroy()
				Verify.expect(#engine.made):toBe(0)
			end,
		})

		for _, scenario in scenarios do
			if scenario.name == "zz-yardstick-cpu" then
				continue
			end
		end
		for _, scene in scenes do
		end
	end)
end
