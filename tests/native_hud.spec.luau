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
			runtime:dispose()
			t.expect(#target:GetChildren()).toBe(0)
		end,
		viewport,
		engine
end

local function find(root, name)
	return root:FindFirstChild(name, true)
end

local measured = require("./lib/hud_measure")
local measure, LANDSCAPE, PORTRAIT, TINY = measured.measure, measured.LANDSCAPE, measured.PORTRAIT, measured.TINY

local function sink(root)
	local row = find(root, "Overflow")
	return if row.Parent.Parent.Visible then row else find(root, "OverflowColumn")
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
		local built, root, stop, _, engine = mount()
		measure(root, engine, LANDSCAPE)
		for _, id in { "Tasks", "Clock", "Rail", "Health", "Actions", "Feed", "Readout", "Weapon", "Rounds", "Strip" } do
			t.expect(`{id} {built.report().forms[id]}`).toBe(`{id} full`)
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
				"12",
				"9",
				"60 FPS · 42 ms",
				"Ranger rifle",
				"Ravi eliminated Mo",
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
		local built, root, stop, _, engine = mount()
		t.expect(find(root, "TimerText").Text).toBe("2:14")
		built.steps.takeDamage()
		t.expect(find(root, "HealthNum").Text).toBe("59")
		t.expect(find(find(root, "HealthBar"), "Fill4").Size.X.Scale).toBe(0)
		t.expect(find(find(root, "HealthBar"), "Trail") ~= nil).toBe(true)
		built.steps.tickRound()
		t.expect(find(root, "TimerText").Text).toBe("2:04")
		t.expect(find(root, "ClockCompactText").Text).toBe("2:04")
		t.expect(find(root, "ClockShortText").Text).toBe("2m")
		measure(root, engine, { 150, 400 })
		t.expect(built.report().forms.Clock).toBe("short")
		t.expect(find(root, "ClockShort").Parent.Visible).toBe(true)
		t.expect(find(root, "ClockFull").Parent.Visible).toBe(false)
		built.steps.heal()
		t.expect(find(root, "HealthCompactText").Text).toBe("100")
		stop()
	end)
	t.it("restores every resolution after repeated rotations and URL bar episodes", function()
		local boxes = { LANDSCAPE, PORTRAIT, TINY, { 1040, 640 } }
		local built, root, stop, _, engine = mount()
		for _, box in boxes do
			local fresh, freshRoot, stopFresh, _, freshEngine = mount()
			measure(freshRoot, freshEngine, box)
			local expected = fresh.report().forms
			stopFresh()
			for _, other in boxes do
				measure(root, engine, other)
				built.steps.openUrlBar()
				built.steps.openOverflow()
				built.steps.closeOverflow()
				built.steps.closeUrlBar()
				measure(root, engine, box)
				t.expect(built.report().forms).toEqual(expected)
				sink(root).Activated.fire()
				t.expect(built.report().overflowOpen).toBe(true)
				built.steps.closeOverflow()
			end
		end
		t.expect(find(root, "HudBody").LayoutOrder).toBe(3)
		t.expect(find(root, "BrowserChrome").Size.Y.Offset).toBe(64)
		stop()
	end)
	t.it("recovers whole simplified zones in overflow and shares their live model", function()
		local built, root, stop, _, engine = mount()
		measure(root, engine, TINY)
		t.expect(#built.report().unshown > 3).toBe(true)
		sink(root).Activated.fire()
		local body = find(root.Parent, "OverflowBody")
		t.expect(body.ClassName).toBe("ScrollingFrame")
		for _, id in built.report().unshown do
			t.expect(`{id} {body:FindFirstChild("Rich" .. id) ~= nil}`).toBe(`{id} true`)
		end
		for _, text in { "Win a round", "+120", "24/90", "7/21", "2:14", "12", "9" } do
			t.expect(hasText(body, text)).toBe(true)
		end
		built.steps.advanceTask(2, 0.8)
		t.expect(find(find(body, "Task2"), "Fill1").Size.X.Scale).toBeCloseTo(0.8)
		find(body, "Weapon3").Activated.fire()
		t.expect(built.model.selectedWeapon:peek()).toBe(3)
		measure(root, engine, { 1040, 640 })
		t.expect(#built.report().unshown).toBe(0)
		t.expect(find(root.Parent, "OverflowEmpty").Text).toBe(hud.copy.overflowEmpty)
		t.expect(find(find(root, "Task2"), "Fill1").Size.X.Scale).toBeCloseTo(0.8)
		measure(root, engine, TINY)
		t.expect(find(root.Parent, "OverflowEmpty")).toBe(nil)
		stop()
	end)
	t.it("expands a collapsed zone in context, anchored at it, instead of the overflow sheet", function()
		local built, root, stop, _, engine = mount()
		measure(root, engine, PORTRAIT)
		t.expect(built.report().forms.Tasks ~= "full" and built.report().forms.Tasks ~= "hidden").toBe(true)
		find(find(root, "Tasks"), "Expand").Activated.fire()
		t.expect(built.report().overflowOpen).toBe(false)
		local modal = find(root.Parent, "ExpandModal")
		t.expect(modal:GetAttribute("FacetRoute")).toBe("popover")
		t.expect(hasText(modal, hud.copy.tasksTitle)).toBe(true)
		t.expect(hasText(modal, "+300")).toBe(true)
		measure(root, engine, { 1040, 640 })
		t.expect(find(root.Parent, "ExpandModal")).toBe(nil)
		stop()
	end)
	t.it("uses native body bounds after chrome layout and disconnects on disposal", function()
		local built, root, stop, _, engine = mount()
		measure(root, engine, { 1040, 640 })
		local original = built.report().forms
		measure(root, engine, TINY)
		t.expect(built.report().forms.Tasks).toBe("hidden")
		t.expect(built.report().forms.Clock).toBe("timer")
		measure(root, engine, { 1040, 640 })
		t.expect(built.report().forms).toEqual(original)
		local zones = find(root, "Zones")
		local signal = zones:GetPropertyChangedSignal("AbsoluteSize")
		stop()
		t.expect(signal.count()).toBe(0)
	end)
end)
