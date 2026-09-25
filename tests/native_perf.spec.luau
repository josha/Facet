--!strict
local t = require("./lib/testkit")
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

t.describe("native benchmark workload contract", function()
	t.it("keeps every controlled sampling cadence fixed to the historical inventory", function()
		local audit = serde.decode("json", fs.readFile("bench/workload_fidelity.json"))
		t.expect(#audit.scenes).toBe(#scenes)
		for _, record in audit.scenes do
			local scene = assert(registered[record.name])
			t.expect(scene.samples).toBe(record.samples)
			t.expect(scene.warmup).toBe(record.warmup)
		end
	end)

	t.it("preserves binding counts, one-hot style mutation and exact collection records", function()
		local function check(name, callback)
			local scene = registered[name]
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
			t.expect(w.speed:peek()).toBe(100)
			t.expect(writes).toBe(50)
			connection:Disconnect()
		end)
		check("stylesheet-state-churn", function(w, step)
			t.expect(#w.observed).toBe(40)
			t.expect(w.observed[1]:peek()).toBe(true)
			step()
			for index, cell in w.observed do
				t.expect(cell:peek()).toBe(index == 2)
			end
			t.expect(w.tagCount > 0).toBe(true)
		end)
		check("collection-mutation", function(w, step)
			t.expect(#w.rows:peek()).toBe(8)
			step()
			t.expect(w.rows:peek()[1].id).toBe("r9")
			t.expect(w.rows:peek()[1].name).toBe("Racer 9")
			t.expect(w.selected:peek().r9).toBe(true)
			step()
			t.expect(w.rows:peek()[2].id).toBe("r10")
			t.expect(w.selected:peek().r9).toBe(true)
		end)
		check("animation-interruption", function(w, step, state)
			step()
			step()
			t.expect(w.value:peek()).toBeCloseTo(1 - 0.65 ^ 6)
			t.expect(state.engine.clock()).toBeCloseTo(12 / 60)
		end)
	end)

	t.it("preserves twelve plain burst images and retained async-grid owners", function()
		for _, name in { "async-image-burst", "async-image-grid" } do
			local scene = registered[name]
			local state = scene.setup(profiles.get("floorAndroid"))
			local w = state.workload
			scene.run(state)
			t.expect(#w.images).toBe(12)
			t.expect(w.async.completed).toBe(4)
			if name == "async-image-grid" then
				t.expect(w.close ~= nil).toBe(true)
				t.expect(#w.requests).toBe(8)
				t.expect(w.images[1]:peek()).toBe("rbxthumb://gen=1&id=1")
			else
				t.expect(w.images[12]:peek()).toBe("rbxassetid://112")
				local count = 0
				for _, node in state.target:GetDescendants() do
					if node.ClassName == "ImageLabel" then
						count += 1
					end
				end
				t.expect(count).toBe(12)
			end
			scene.run(state)
			t.expect(w.async.completed).toBe(8)
			t.expect(w.async.dropped).toBe(8)
			if name == "async-image-burst" then
				t.expect(w.async.stale).toBe(8)
			end
			scene.teardown(state)
		end
	end)

	t.it("preserves native focus and six-move drag delivery with original scroll cadence", function()
		local scene = registered["scroll-focus-traversal"]
		local state = scene.setup(profiles.get("floorAndroid"))
		scene.run(state)
		t.expect(#state.workload.nodes).toBe(16)
		t.expect(state.workload.focusMoves).toBe(16)
		t.expect(state.workload.focused).toBe(state.workload.nodes[16])
		scene.teardown(state)
		scene = registered["native-scroll-drag"]
		state = scene.setup(profiles.get("floorAndroid"))
		scene.run(state)
		t.expect(#state.workload.nodes).toBe(30)
		t.expect(state.workload.dragMoves).toBe(6)
		t.expect(state.workload.drops).toBe(1)
		t.expect(state.workload.dropTarget).toBe("SlotB")
		t.expect(state.workload.scroll).toBe(37)
		t.expect(state.workload.lastDrag.X).toBe(190)
		scene.teardown(state)
	end)

	t.it("retains selected image cards across navigation events and sixty-frame settling", function()
		for _, name in { "adaptive-navigation-images", "navigation-customization" } do
			local scene = registered[name]
			local state = scene.setup(profiles.get("floorAndroid"))
			local w = state.workload
			t.expect(#w.nodes).toBe(24)
			t.expect(w.selected:peek()).toBe("garage")
			local first = w.nodes[1]
			local before = state.engine.clock()
			scene.run(state)
			t.expect(state.engine.clock() - before)
				.toBeCloseTo(if name == "adaptive-navigation-images" then 5 / 60 else 0)
			before = state.engine.clock()
			scene.afterRun(state)
			t.expect(state.engine.clock() - before).toBeCloseTo(1)
			t.expect(w.contentBuilds).toBe(1)
			t.expect(w.nodes[1]).toBe(first)
			t.expect(first:isDestroyed()).toBe(false)
			if name == "navigation-customization" then
				t.expect(w.customization:peek().order[2]).toBe("garage")
			end
			scene.teardown(state)
		end
	end)

	t.it("uses actual theme packages and preserves mounted fixture identities", function()
		for _, name in { "theme-swap-flat", "theme-swap-metrics", "theme-swap-assets" } do
			local scene = registered[name]
			local state = scene.setup(profiles.get("floorAndroid"))
			local w, first = state.workload, state.workload.themeControls[2]
			t.expect(#w.themeControls).toBe(4)
			scene.run(state)
			t.expect(w.palette:peek()).toBe(w.packages[2])
			if name == "theme-swap-flat" then
				t.expect(w.themeName:peek()).toBe("Candlelight")
			end
			if name == "theme-swap-metrics" then
				t.expect(w.packages[2].metrics.controlSizes.regular.height).toBe(44)
			end
			if name == "theme-swap-assets" then
				local images = 0
				for _, node in state.target:GetDescendants() do
					if node.ClassName == "ImageLabel" and node.Image ~= "" then
						images += 1
					end
				end
				t.expect(images > 0).toBe(true)
			end
			scene.run(state)
			t.expect(w.palette:peek()).toBe(w.packages[1])
			t.expect(w.themeControls[2]).toBe(first)
			t.expect(first:isDestroyed()).toBe(false)
			scene.teardown(state)
		end
	end)

	t.it("preserves motion population, scheduled control triggers and native intermediate properties", function()
		local scene = registered["dense-motion"]
		local state = scene.setup(profiles.get("floorAndroid"))
		local w = state.workload
		t.expect(#w.rows:peek()).toBe(600)
		t.expect(#w.springs).toBe(24)
		for _ = 1, 40 do
			scene.run(state)
		end
		t.expect(w.rows:peek()[1].id).toBe("chip41")
		t.expect(w.beats >= 2).toBe(true)
		t.expect(w.beatCallbacks >= 8).toBe(true)
		t.expect(w.motionSteps).toBe(40)
		t.expect(math.abs(w.nodes[1].Position.Y.Scale) > 0).toBe(true)
		scene.teardown(state)
		scene = registered["control-motion"]
		state = scene.setup(profiles.get("floorAndroid"))
		w = state.workload
		for _ = 1, 60 do
			scene.run(state)
			scene.afterRun(state)
		end
		t.expect(#w.rows:peek()).toBe(30)
		t.expect(w.rekeys).toBe(2)
		t.expect(w.flips).toBe(3)
		t.expect(w.pulses).toBe(4)
		t.expect(w.pops).toBe(6)
		t.expect(w.staggerHeld).toBe(2)
		t.expect(w.flipsSeen > 0).toBe(true)
		t.expect(w.shakesSeen > 0).toBe(true)
		t.expect(w.popsSeen > 0).toBe(true)
		scene.teardown(state)
	end)

	t.it("preserves transient frame cadence and stable text-size workload copy", function()
		for _, name in { "alert-present-dismiss", "picker-menu-open-close", "radial-menu-open-close" } do
			local scene = registered[name]
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
			t.expect(state.engine.clock() - before)
				.toBeCloseTo(if name == "radial-menu-open-close" then 4 / 60 else 2 / 60)
			t.expect(state.workload.presented:peek()).toBe(false)
			scene.teardown(state)
		end
		local scene = registered["locale-textsize-change"]
		local state = scene.setup(profiles.get("floorAndroid"))
		scene.run(state)
		t.expect(state.workload.locale:peek()).toBe("de-de")
		local labels = 0
		for _, node in state.target:GetDescendants() do
			if node.ClassName == "TextLabel" then
				labels += 1
				t.expect(string.sub(node.Text, 1, 10)).toBe("Menu item ")
				t.expect(node.TextSize).toBeCloseTo(20.8)
			end
		end
		t.expect(labels).toBe(8)
		scene.teardown(state)
	end)
	t.it("counts real transient surfaces and settles the radial exit outside the timed step", function()
		for name, items in
			{ ["alert-present-dismiss"] = 3, ["picker-menu-open-close"] = 6, ["radial-menu-open-close"] = 6 }
		do
			local scene = registered[name]
			local state = scene.setup(profiles.get("floorAndroid"))
			for _ = 1, 3 do
				scene.run(state)
				scene.afterRun(state)
			end
			local w = state.workload
			t.expect(w.opens).toBe(3)
			t.expect(w.surfaceItems).toBe(items)
			t.expect(w.settled).toBe(3)
			t.expect(w.closes).toBe(0)
			t.expect(w.settleFrames > 0).toBe(true)
			scene.teardown(state)
		end
		local scene = registered["dense-motion"]
		local state = scene.setup(profiles.get("floorAndroid"))
		for _ = 1, 4 do
			scene.run(state)
			scene.afterRun(state)
		end
		t.expect(state.workload.springsMoving).toBe(24)
		scene.teardown(state)
	end)
	t.it("measures a dense HUD activation through its committed native text", function()
		local scene = registered["dense-hud"]
		local state = scene.setup(profiles.get("floorAndroid"))
		t.expect(#state.workload.observed).toBe(8)
		local phases = scene.run(state)
		t.expect(phases.inputToVisible > 0).toBe(true)
		t.expect(state.workload.boostText.Text).toBe("Boost x1")
		for _, button in state.workload.nodes do
			button.Activated.fire()
		end
		t.expect(state.workload.boosts:peek()).toBe(5)
		t.expect(state.workload.boostText.Text).toBe("Boost x5")
		local extras = scene.extras(state)
		t.expect(extras.activationCount).toBe(5)
		t.expect(extras.activationText).toBe("Boost x5")
		scene.teardown(state)
	end)

	t.it("retains default async placeholders while custom content follows loading ownership", function()
		local world = require("../bench/native_app")()
		local Compose = world.Compose
		local source, requests = Compose.cell("one"), {}
		local built, disposed = 0, 0
		local function loader(content, resolve, reject)
			requests[content] = { resolve = resolve, reject = reject }
		end
		local _, root = world.runtime.mount(function()
			return world.UI.AsyncImage({ source = source, loader = loader, failureLabel = "Unavailable" })
		end, world.target)
		local placeholder, image = root:FindFirstChild("Placeholder"), root:FindFirstChild("Image")
		t.expect(placeholder:HasTag("facet-skeleton")).toBe(true)
		requests.one.resolve("one")
		t.expect(placeholder.Visible).toBe(false)
		t.expect(image.Visible).toBe(true)
		source:set("two")
		t.expect(placeholder.Visible).toBe(true)
		t.expect(image.Visible).toBe(false)
		requests.two.reject("missing")
		t.expect(placeholder:FindFirstChildWhichIsA("TextLabel").Text).toBe("Unavailable")
		source:set("three")
		requests.three.resolve("three")
		t.expect(root:FindFirstChild("Placeholder")).toBe(placeholder)
		t.expect(root:FindFirstChild("Image")).toBe(image)
		t.expect(placeholder:FindFirstChildWhichIsA("TextLabel")).toBe(nil)
		local customSource = Compose.cell("custom-one")
		world.runtime.mount(function()
			return world.UI.AsyncImage({
				source = customSource,
				loader = loader,
				placeholder = function()
					built += 1
					Compose.cleanup(function()
						disposed += 1
					end)
					return world.Host.Frame "Custom" {}
				end,
			})
		end, world.target)
		t.expect(built).toBe(1)
		requests["custom-one"].resolve("custom-one")
		t.expect(disposed).toBe(1)
		customSource:set("custom-two")
		t.expect(built).toBe(2)
		world.dispose()
		t.expect(disposed).toBe(2)
		t.expect(placeholder:isDestroyed()).toBe(true)
	end)

	t.it("retains one hundred idle native shadows and still applies direct mutations", function()
		local scene = registered["shadow-storm"]
		local state = scene.setup(profiles.get("floorAndroid"))
		local shadows = {}
		for _, node in state.target:GetDescendants() do
			if node.ClassName == "UIShadow" then
				table.insert(shadows, node)
			end
		end
		t.expect(#shadows).toBe(100)
		local changes = 0
		local connection = shadows[1]:GetPropertyChangedSignal("Transparency"):Connect(function()
			changes += 1
		end)
		for _ = 1, 3 do
			scene.run(state)
		end
		t.expect(state.engine.clock()).toBeCloseTo(3 / 60)
		t.expect(changes).toBe(0)
		for _, value in state.workload.observed do
			value:set(0.25)
		end
		t.expect(changes).toBe(1)
		for _, shadow in shadows do
			t.expect(shadow.Transparency).toBe(0.25)
			t.expect(shadow.Parent.BackgroundTransparency).toBe(0.25)
		end
		connection:Disconnect()
		scene.teardown(state)
		for _, shadow in shadows do
			t.expect(shadow:isDestroyed()).toBe(true)
		end
	end)

	t.it("preserves subscribed ancestry ordering and cleanup after unobserved moves", function()
		for _, cached in { false, true } do
			local engine = require("./lib/native_engine").new({ cacheDefaults = cached, recordCreated = false })
			local first, second, root, child, leaf =
				engine.new("Folder"),
				engine.new("Folder"),
				engine.new("Frame"),
				engine.new("Frame"),
				engine.new("TextLabel")
			first.Name, second.Name, root.Name, child.Name, leaf.Name = "First", "Second", "Root", "Child", "Leaf"
			root.Parent, child.Parent, leaf.Parent = first, root, child
			root.Parent = second
			root.Parent = first
			local log, connections = {}, {}
			local childEvents = {}
			local removed = first.ChildRemoved:Connect(function(node)
				t.expect(node.Parent).toBe(second)
				table.insert(childEvents, "removed")
			end)
			local added = second.ChildAdded:Connect(function(node)
				t.expect(node.Parent).toBe(second)
				table.insert(childEvents, "added")
			end)
			for _, node in { root, child, leaf } do
				table.insert(
					connections,
					node.AncestryChanged:Connect(function(changed, parent)
						t.expect(changed).toBe(node)
						t.expect(parent).toBe(node.Parent)
						table.insert(log, `A:{node.Name}:{if parent then parent.Name else "nil"}`)
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
			t.expect(table.concat(childEvents, "|")).toBe("removed|added")
			removed:Disconnect()
			added:Disconnect()
			t.expect(table.concat(log, "|")).toBe("A:Root:Second|A:Child:Root|A:Leaf:Child")
			table.clear(log)
			connections[3]:Disconnect()
			root:Destroy()
			t.expect(table.concat(log, "|"))
				.toBe("D:Root:Second|A:Root:nil|A:Leaf:Child|D:Child:Root|A:Leaf:Child|D:Leaf:Child|A:Leaf:nil")
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(log)
			for _, node in { root, child, leaf } do
				t.expect(node.AncestryChanged.count()).toBe(0)
				t.expect(node.Destroying.count()).toBe(0)
				node.AncestryChanged.fire(node, nil)
				node.Destroying.fire()
			end
			t.expect(#log).toBe(0)
			first:Destroy()
			second:Destroy()
		end
	end)

	t.it("keeps cached reflection defaults independent across native fixture instances", function()
		local engine = require("./lib/native_engine").new({ cacheDefaults = true, recordCreated = false })
		local first, second = engine.new("TextLabel"), engine.new("TextLabel")
		local initial = second.Text
		first.Text = "Changed"
		t.expect(second.Text).toBe(initial)
		t.expect(first:IsA("GuiObject")).toBe(true)
		t.expect(second:IsA("TextButton")).toBe(false)
		first:Destroy()
		local third = engine.new("TextLabel")
		t.expect(third.Text).toBe(initial)
		t.expect(third:IsA("GuiObject")).toBe(true)
		t.expect(second:isDestroyed()).toBe(false)
		second:Destroy()
		third:Destroy()
		t.expect(#engine.made).toBe(0)
	end)

	t.it("preserves every versioned controlled-performance workload", function()
		local expected = 0
		for name, budget in budgets.scenes do
			t.expect(registered[name] ~= nil).toBe(true)
			t.expect(registered[name].requirement).toBe(budget.requirement)
			expected += 1
		end
		t.expect(#scenes).toBe(expected)
	end)
	for _, scenario in scenarios do
		if scenario.name == "zz-yardstick-cpu" then
			continue
		end
		t.it(`runs and tears down microbenchmark {scenario.name}`, function()
			local state = scenario.setup()
			local ok, err = pcall(function()
				scenario.run(state)
				scenario.run(state)
			end)
			if scenario.teardown then
				scenario.teardown(state)
			end
			assert(ok, err)
		end)
	end
	for _, scene in scenes do
		t.it(`runs and tears down controlled workload {scene.name}`, function()
			local state = scene.setup(profiles.get("floorAndroid"))
			local ok, err = pcall(function()
				scene.run(state)
				scene.run(state)
			end)
			scene.teardown(state)
			assert(ok, err)
		end)
	end
end)
