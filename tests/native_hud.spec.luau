--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local hud = require("../examples/gallery/scenarios/hud")

local function mount(width, height)
	local engine = engineLib.new()
	local create = engine.new
	engine.new = function(className)
		local node = create(className)
		local metatable = getmetatable(node)
		local assign = metatable.__newindex
		metatable.__newindex = function(instance, property, value)
			if property == "Text" then
				assert(type(value) == "string", className .. ".Text requires a string")
			end
			assign(instance, property, value)
		end
		return node
	end
	local runtime = Facet.Roblox.createRuntime(engine)
	local viewport = Facet.Compose.cell({ width = width or 1079, height = height or 809 })
	local target = engine.new("ScreenGui")
	local ctx = {
		Facet = Facet,
		Compose = Facet.Compose,
		runtime = runtime,
		Host = runtime.constructors,
		UI = Facet.controls(runtime, { types = engine.types, viewport = viewport }),
		types = engine.types,
		viewport = viewport,
	}
	local built
	local stop, root = runtime.mount(function()
		built = hud.build(ctx)
		return built.screen()
	end, target)
	return built,
		root,
		function()
			stop()
			runtime.dispose()
			t.expect(#target:GetChildren()).toBe(0)
		end,
		viewport,
		engine
end

local function find(root, name)
	return root:FindFirstChild(name, true)
end

local function hasText(root, text)
	for _, node in root:GetDescendants() do
		if node.Text == text then
			return true
		end
	end
	return false
end

t.describe("native HUD", function()
	t.it("keeps native notification text valid while hidden shown and dismissed", function()
		local built, root, stop = mount()
		local notice = find(root, "Notice")
		local button = notice:FindFirstChildWhichIsA("TextButton")
		t.expect(notice.Visible).toBe(false)
		t.expect(button.Text).toBe("")
		built.steps.notify()
		t.expect(notice.Visible).toBe(true)
		t.expect(button.Text).toBe("Supplies delivered")
		button.Activated.fire()
		t.expect(notice.Visible).toBe(false)
		t.expect(button.Text).toBe("")
		stop()
	end)
	t.it("keeps complete task rewards, weapon ammunition, scores and telemetry", function()
		local built, root, stop = mount()
		for _, id in { "Tasks", "Clock", "Rail", "Health", "Actions", "Feed", "Readout", "Weapon" } do
			t.expect(built.report().forms[id]).toBe("full")
		end
		for _, text in
			{
				"Win a round",
				"Land 25 hits",
				"Open a crate",
				"+50",
				"+120",
				"+300",
				"24/90",
				"7/21",
				"--",
				"12  —  9",
				"60 FPS · 42 ms",
				"Ranger rifle",
			}
		do
			t.expect(hasText(root, text)).toBe(true)
		end
		for index, fraction in { 0.2, 0.4, 0.6 } do
			t.expect(find(find(root, "Task" .. index), "Fill1").Size.X.Scale).toBeCloseTo(fraction)
		end
		find(root, "Weapon2").Activated.fire()
		t.expect(built.model.selectedWeapon:peek()).toBe(2)
		find(root, "Shop").Activated.fire()
		t.expect(built.report().notice).toBe("Shop opened")
		stop()
	end)
	t.it("updates segmented health and full, compact and tiny numeric timer formats", function()
		local built, root, stop, viewport = mount()
		t.expect(find(root, "TimerText").Text).toBe("2:14")
		built.steps.takeDamage()
		t.expect(find(root, "HealthNum").Text).toBe("59")
		t.expect(find(find(root, "HealthBar"), "Fill4").Size.X.Scale).toBe(0)
		t.expect(find(find(root, "HealthBar"), "Trail") ~= nil).toBe(true)
		find(root, "Tick").Activated.fire()
		t.expect(find(root, "TimerText").Text).toBe("2:04")
		viewport:set({ width = 480, height = 360 })
		t.expect(find(root, "ClockCompact").Text).toBe("2m")
		viewport:set({ width = 320, height = 240 })
		t.expect(find(root, "ClockCompact").Text).toBe("2")
		built.steps.heal()
		t.expect(find(root, "HealthCompact").Text).toBe("100")
		stop()
	end)
	t.it("restores every resolution after repeated rotations and URL bar episodes", function()
		local sizes = {
			{ width = 1079, height = 809 },
			{ width = 360, height = 691 },
			{ width = 691, height = 360 },
			{ width = 320, height = 240 },
		}
		local built, root, stop, viewport = mount()
		for _, size in sizes do
			viewport:set(size)
			local fresh, _, stopFresh = mount(size.width, size.height)
			local expected = fresh.report().forms
			for _, other in sizes do
				viewport:set(other)
				built.steps.openUrlBar()
				built.steps.openOverflow()
				built.steps.closeOverflow()
				built.steps.closeUrlBar()
				viewport:set(size)
				t.expect(built.report().forms).toEqual(expected)
				find(root, "Overflow").Activated.fire()
				t.expect(built.report().overflowOpen).toBe(true)
				built.steps.closeOverflow()
			end
			stopFresh()
		end
		t.expect(find(root, "HudBody").LayoutOrder).toBe(5)
		t.expect(find(root, "BrowserChrome").Size.Y.Offset).toBe(64)
		stop()
	end)
	t.it("recovers whole simplified zones in overflow and shares their live model", function()
		local built, root, stop, viewport = mount(320, 240)
		find(root, "Overflow").Activated.fire()
		local body = find(root.Parent, "OverflowBody")
		t.expect(body.ClassName).toBe("ScrollingFrame")
		for _, text in
			{
				"Win a round",
				"Land 25 hits",
				"Open a crate",
				"+50",
				"+120",
				"+300",
				"24/90",
				"7/21",
				"--",
				"2:14",
				"12  —  9",
				"Ravi eliminated Mo",
				"60 FPS · 42 ms",
				"Ranger rifle",
			}
		do
			t.expect(hasText(body, text)).toBe(true)
		end
		built.steps.advanceTask(2, 0.8)
		t.expect(find(find(body, "Task2"), "Fill1").Size.X.Scale).toBeCloseTo(0.8)
		find(body, "Weapon3").Activated.fire()
		t.expect(built.model.selectedWeapon:peek()).toBe(3)
		viewport:set({ width = 1079, height = 809 })
		t.expect(#built.report().unshown).toBe(0)
		t.expect(find(root.Parent, "OverflowEmpty").Text).toBe(hud.copy.overflowEmpty)
		t.expect(find(find(root, "Task2"), "Fill1").Size.X.Scale).toBeCloseTo(0.8)
		viewport:set({ width = 320, height = 240 })
		t.expect(find(root.Parent, "OverflowEmpty")).toBe(nil)
		stop()
	end)
	t.it("uses native body bounds after chrome layout and disconnects on disposal", function()
		local built, root, stop, _, engine = mount()
		local body = find(root, "HudBody")
		body.AbsoluteSize = engine.types.Vector2.new(960, 620)
		local original = built.report().forms
		body.AbsoluteSize = engine.types.Vector2.new(300, 140)
		t.expect(built.report().forms.Tasks).toBe("hidden")
		t.expect(built.report().forms.Clock).toBe("tiny")
		body.AbsoluteSize = engine.types.Vector2.new(960, 620)
		t.expect(built.report().forms).toEqual(original)
		local signal = body:GetPropertyChangedSignal("AbsoluteSize")
		stop()
		t.expect(signal.count()).toBe(0)
	end)
end)
