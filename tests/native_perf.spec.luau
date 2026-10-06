--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)

	local scenarios = require("../bench/scenarios")
	local scenes = require("../bench/perf_scenes")
	local profiles = require("../bench/perf_profiles")
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local budgets = serde.decode("json", fs.readFile("bench/perf_budgets.json"))
	local registered = {}
	for _, scene in scenes do
		registered[scene.name] = scene
	end

	verifyHarness:suite("native benchmark workload contract", function()
		verifyHarness:case("keeps every controlled sampling cadence fixed to the historical inventory", {
			id = "native_perf::native benchmark workload contract::keeps every controlled sampling cadence fixed to the historical inventory",
			run = function()
				local audit = serde.decode("json", fs.readFile("bench/workload_fidelity.json"))
				Verify.expect(#audit.scenes):toBe(#scenes)
				for _, record in audit.scenes do
					local scene = assert(registered[record.name])
					Verify.expect(scene.samples):toBe(record.samples)
					Verify.expect(scene.warmup):toBe(record.warmup)
				end
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

		verifyHarness:case("preserves native focus and six-move drag delivery with original scroll cadence", {
			id = "native_perf::native benchmark workload contract::preserves native focus and six-move drag delivery with original scroll cadence",
			run = function()
				local scene = registered["scroll-focus-traversal"]
				local state = scene.setup(profiles.get("floorAndroid"))
				scene.run(state)
				Verify.expect(#state.workload.nodes):toBe(16)
				Verify.expect(state.workload.focusMoves):toBe(16)
				Verify.expect(state.workload.focused):toBe(state.workload.nodes[16])
				scene.teardown(state)
				scene = registered["native-scroll-drag"]
				state = scene.setup(profiles.get("floorAndroid"))
				scene.run(state)
				Verify.expect(#state.workload.nodes):toBe(30)
				Verify.expect(state.workload.dragMoves):toBe(6)
				Verify.expect(state.workload.drops):toBe(1)
				Verify.expect(state.workload.dropTarget):toBe("SlotB")
				Verify.expect(state.workload.scroll):toBe(37)
				Verify.expect(state.workload.lastDrag.X):toBe(190)
				scene.teardown(state)
			end,
		})

		verifyHarness:case("retains selected image cards across navigation events and sixty-frame settling", {
			id = "native_perf::native benchmark workload contract::retains selected image cards across navigation events and sixty-frame settling",
			run = function()
				for _, name in { "adaptive-navigation-images", "navigation-customization" } do
					local scene = registered[tostring(name)]
					local state = scene.setup(profiles.get("floorAndroid"))
					local w = state.workload
					Verify.expect(#w.nodes):toBe(24)
					Verify.expect((w.selected:peek())):toBe("garage")
					local first = w.nodes[1]
					local before = state.engine.clock()
					scene.run(state)
					Verify.expect(state.engine.clock() - before)
						:toBeCloseTo(if name == "adaptive-navigation-images" then 5 / 60 else 0, 1e-4)
					before = state.engine.clock()
					scene.afterRun(state)
					Verify.expect(state.engine.clock() - before):toBeCloseTo(1, 1e-4)
					Verify.expect(w.contentBuilds):toBe(1)
					Verify.expect(w.nodes[1]):toBe(first)
					Verify.expect((first:isDestroyed())):toBe(false)
					if name == "navigation-customization" then
						Verify.expect(w.customization:peek().order[2]):toBe("garage")
					end
					scene.teardown(state)
				end
			end,
		})

		verifyHarness:case("uses actual theme packages and preserves mounted fixture identities", {
			id = "native_perf::native benchmark workload contract::uses actual theme packages and preserves mounted fixture identities",
			run = function()
				for _, name in { "theme-swap-flat", "theme-swap-metrics", "theme-swap-assets" } do
					local scene = registered[tostring(name)]
					local state = scene.setup(profiles.get("floorAndroid"))
					local w, first = state.workload, state.workload.themeControls[2]
					Verify.expect(#w.themeControls):toBe(4)
					scene.run(state)
					Verify.expect((w.palette:peek())):toBe(w.packages[2])
					if name == "theme-swap-flat" then
						Verify.expect((w.themeName:peek())):toBe("Candlelight")
					end
					if name == "theme-swap-metrics" then
						Verify.expect(w.packages[2].metrics.controlSizes.regular.height):toBe(44)
					end
					if name == "theme-swap-assets" then
						local images = 0
						for _, node in state.target:GetDescendants() do
							if node.ClassName == "ImageLabel" and node.Image ~= "" then
								images += 1
							end
						end
						Verify.expect(images > 0):toBe(true)
					end
					scene.run(state)
					Verify.expect((w.palette:peek())):toBe(w.packages[1])
					Verify.expect(w.themeControls[2]):toBe(first)
					Verify.expect((first:isDestroyed())):toBe(false)
					scene.teardown(state)
				end
			end,
		})

		verifyHarness:case(
			"preserves motion population, scheduled control triggers and native intermediate properties",
			{
				id = "native_perf::native benchmark workload contract::preserves motion population, scheduled control triggers and native intermediate properties",
				run = function()
					local scene = registered["dense-motion"]
					local state = scene.setup(profiles.get("floorAndroid"))
					local w = state.workload
					Verify.expect(#w.rows:peek()):toBe(600)
					Verify.expect(#w.springs):toBe(24)
					for _ = 1, 40 do
						scene.run(state)
					end
					Verify.expect(w.rows:peek()[1].id):toBe("chip41")
					Verify.expect(w.beats >= 2):toBe(true)
					Verify.expect(w.beatCallbacks >= 8):toBe(true)
					Verify.expect(w.motionSteps):toBe(40)
					Verify.expect(math.abs(w.nodes[1].Position.Y.Scale) > 0):toBe(true)
					scene.teardown(state)
					scene = registered["control-motion"]
					state = scene.setup(profiles.get("floorAndroid"))
					w = state.workload
					for _ = 1, 60 do
						scene.run(state)
						scene.afterRun(state)
					end
					Verify.expect(#w.rows:peek()):toBe(30)
					Verify.expect(w.rekeys):toBe(2)
					Verify.expect(w.flips):toBe(3)
					Verify.expect(w.pulses):toBe(4)
					Verify.expect(w.pops):toBe(6)
					Verify.expect(w.staggerHeld):toBe(2)
					Verify.expect(w.flipsSeen > 0):toBe(true)
					Verify.expect(w.shakesSeen > 0):toBe(true)
					Verify.expect(w.popsSeen > 0):toBe(true)
					scene.teardown(state)
				end,
			}
		)

		verifyHarness:case("preserves transient frame cadence and stable text-size workload copy", {
			id = "native_perf::native benchmark workload contract::preserves transient frame cadence and stable text-size workload copy",
			run = function()
				for _, name in { "alert-present-dismiss", "picker-menu-open-close", "radial-menu-open-close" } do
					local scene = registered[tostring(name)]
					local state = scene.setup(profiles.get("floorAndroid"))
					local before = state.engine.clock()
					state.workload.presented:set(true)
					for _ = 1, 30 do
						state.frame()
					end
					local openCount = #state.target:GetDescendants()
					state.workload.presented:set(false)
					for _ = 1, 30 do
						state.frame()
					end
					assert(#state.target:GetDescendants() < openCount, name .. " did not release presented content")
					before = state.engine.clock()
					scene.run(state)
					Verify.expect(state.engine.clock() - before)
						:toBeCloseTo(if name == "radial-menu-open-close" then 4 / 60 else 2 / 60, 1e-4)
					Verify.expect((state.workload.presented:peek())):toBe(false)
					scene.teardown(state)
				end
				local scene = registered["locale-textsize-change"]
				local state = scene.setup(profiles.get("floorAndroid"))
				scene.run(state)
				Verify.expect((state.workload.locale:peek())):toBe("de-de")
				local labels = 0
				for _, node in state.target:GetDescendants() do
					if node.ClassName == "TextLabel" then
						labels += 1
						Verify.expect((string.sub(node.Text, 1, 10))):toBe("Menu item ")
						Verify.expect(node.TextSize):toBeCloseTo(20.8, 1e-4)
					end
				end
				Verify.expect(labels):toBe(8)
				scene.teardown(state)
			end,
		})
		verifyHarness:case("counts real transient surfaces and settles the radial exit outside the timed step", {
			id = "native_perf::native benchmark workload contract::counts real transient surfaces and settles the radial exit outside the timed step",
			run = function()
				for name, items in
					{ ["alert-present-dismiss"] = 3, ["picker-menu-open-close"] = 6, ["radial-menu-open-close"] = 6 }
				do
					local scene = registered[tostring(name)]
					local state = scene.setup(profiles.get("floorAndroid"))
					for _ = 1, 3 do
						scene.run(state)
						scene.afterRun(state)
					end
					local w = state.workload
					Verify.expect(w.opens):toBe(3)
					Verify.expect(w.surfaceItems):toBe(items)
					Verify.expect(w.settled):toBe(3)
					Verify.expect(w.closes):toBe(0)
					Verify.expect(w.settleFrames > 0):toBe(true)
					scene.teardown(state)
				end
				local scene = registered["dense-motion"]
				local state = scene.setup(profiles.get("floorAndroid"))
				for _ = 1, 4 do
					scene.run(state)
					scene.afterRun(state)
				end
				Verify.expect(state.workload.springsMoving):toBe(24)
				scene.teardown(state)
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
					button.Activated.fire()
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
						Verify.expect((node.AncestryChanged.count())):toBe(0)
						Verify.expect((node.Destroying.count())):toBe(0)
						node.AncestryChanged.fire(node, nil)
						node.Destroying.fire()
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

		verifyHarness:case("preserves every versioned controlled-performance workload", {
			id = "native_perf::native benchmark workload contract::preserves every versioned controlled-performance workload",
			run = function()
				local expected = 0
				for name, budget in budgets.scenes do
					Verify.expect(registered[name] ~= nil):toBe(true)
					Verify.expect(registered[name].requirement):toBe(budget.requirement)
					expected += 1
				end
				Verify.expect(#scenes):toBe(expected)
			end,
		})
		for _, scenario in scenarios do
			if scenario.name == "zz-yardstick-cpu" then
				continue
			end
			verifyHarness:case(`runs and tears down microbenchmark {scenario.name}`, {
				id = "native_perf::"
					.. "native benchmark workload contract"
					.. "::"
					.. `runs and tears down microbenchmark {scenario.name}`,
				run = function()
					local state = scenario.setup()
					local ok, err = pcall(function()
						scenario.run(state)
						scenario.run(state)
					end)
					if scenario.teardown then
						scenario.teardown(state)
					end
					assert(ok, err)
				end,
			})
		end
		for _, scene in scenes do
			verifyHarness:case(`runs and tears down controlled workload {scene.name}`, {
				id = "native_perf::"
					.. "native benchmark workload contract"
					.. "::"
					.. `runs and tears down controlled workload {scene.name}`,
				run = function()
					local state = scene.setup(profiles.get("floorAndroid"))
					local ok, err = pcall(function()
						scene.run(state)
						scene.run(state)
					end)
					scene.teardown(state)
					assert(ok, err)
				end,
			})
		end
	end)
end
