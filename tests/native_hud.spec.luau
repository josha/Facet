--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local hud = require("../examples/gallery/scenarios/hud")

	local function mount(width: number?, height: number?)
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
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local viewport = Facet.Compose.cell({ width = width or 1079, height = height or 809 })
		local target = engine.new("ScreenGui")
		local ctx = {
			Facet = Facet,
			Compose = Facet.Compose,
			runtime = runtime,
			Host = (runtime.constructors :: unknown) :: RobloxHost,
			UI = Facet.controls(runtime, { types = engine.types, viewport = viewport }),
			types = engine.types,
			viewport = viewport,
		}
		local built
		local stop, root: any = runtime.mount(function()
			built = hud.build(ctx)
			return built.screen()
		end, target)
		return built,
			root,
			function()
				stop()
				runtime:dispose()
				Verify.expect(#target:GetChildren()):toBe(0)
			end,
			viewport,
			engine
	end

	local function find(root: any, name: string): any
		return root:FindFirstChild(name, true)
	end

	local measured = require("./lib/hud_measure")
	local measure, LANDSCAPE, PORTRAIT, TINY = measured.measure, measured.LANDSCAPE, measured.PORTRAIT, measured.TINY

	local function sink(root)
		return find(
			root,
			if find(root, "Actions"):GetAttribute("FacetForm") == 1 then "ActionMenu" else "ActionsCompact"
		)
	end

	local function hasText(root, text)
		for _, node in root:GetDescendants() do
			if node.Text == text then
				return true
			end
		end
		return false
	end

	verifyHarness:suite("native HUD", function()
		verifyHarness:case("keeps native notification text valid while hidden shown and dismissed", {
			id = "native_hud::native HUD::keeps native notification text valid while hidden shown and dismissed",
			run = function()
				local built, root, stop = mount()
				local notice = find(root, "Notice")
				local button = notice:FindFirstChildWhichIsA("TextButton")
				Verify.expect(notice.Visible):toBe(false)
				Verify.expect(button.Text):toBe("")
				built.steps.notify()
				Verify.expect(notice.Visible):toBe(true)
				Verify.expect(button.Text):toBe("Supplies delivered")
				button.Activated.fire()
				Verify.expect(notice.Visible):toBe(false)
				Verify.expect(button.Text):toBe("")
				stop()
			end,
		})
		verifyHarness:case("keeps complete task rewards, weapon ammunition, scores and telemetry", {
			id = "native_hud::native HUD::keeps complete task rewards, weapon ammunition, scores and telemetry",
			run = function()
				local built, root, stop, _, engine = mount()
				measure(root, engine, LANDSCAPE)
				for _, id in
					{ "Tasks", "Clock", "Rail", "Health", "Actions", "Feed", "Readout", "Weapon", "Rounds", "Strip" }
				do
					Verify.expect(`{id} {built.report().forms[id]}`):toBe(`{id} full`)
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
					Verify.expect((hasText(root, text))):toBe(true)
				end
				for index, fraction in { 0.2, 0.4, 0.6 } do
					Verify.expect(find(find(root, "Task" .. index), "Fill1").Size.X.Scale):toBeCloseTo(fraction, 1e-4)
				end
				find(root, "Weapon2").Activated.fire()
				Verify.expect((built.model.selectedWeapon:peek())):toBe(2)
				find(root, "Shop").Activated.fire()
				Verify.expect(built.report().notice):toBe("Shop opened")
				stop()
			end,
		})
		verifyHarness:case("updates segmented health and full, compact and tiny numeric timer formats", {
			id = "native_hud::native HUD::updates segmented health and full, compact and tiny numeric timer formats",
			run = function()
				local built, root, stop, _, engine = mount()
				Verify.expect(find(root, "TimerText").Text):toBe("2:14")
				built.steps.takeDamage()
				Verify.expect(find(root, "HealthNum").Text):toBe("59")
				Verify.expect(find(find(root, "HealthBar"), "Fill4").Size.X.Scale):toBe(0)
				Verify.expect(find(find(root, "HealthBar"), "Trail") ~= nil):toBe(true)
				built.steps.tickRound()
				Verify.expect(find(root, "TimerText").Text):toBe("2:04")
				Verify.expect(find(root, "ClockCompactText").Text):toBe("2:04")
				Verify.expect(find(root, "ClockShortText").Text):toBe("2m")
				measure(root, engine, { 150, 400 })
				Verify.expect(built.report().forms.Clock):toBe("short")
				Verify.expect(find(root, "ClockShort").Parent.Visible):toBe(true)
				Verify.expect(find(root, "ClockFull").Parent.Visible):toBe(false)
				built.steps.heal()
				Verify.expect(find(root, "HealthCompactText").Text):toBe("100")
				stop()
			end,
		})
		verifyHarness:case("restores every resolution after repeated rotations and URL bar episodes", {
			id = "native_hud::native HUD::restores every resolution after repeated rotations and URL bar episodes",
			run = function()
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
						Verify.expect(built.report().forms):toEqual(expected)
						sink(root).Activated.fire()
						Verify.expect(built.report().overflowOpen):toBe(true)
						built.steps.closeOverflow()
					end
				end
				Verify.expect(find(root, "HudBody").LayoutOrder):toBe(3)
				Verify.expect(find(root, "BrowserChrome").Size.Y.Offset):toBe(64)
				stop()
			end,
		})
		verifyHarness:case("recovers whole simplified zones in overflow and shares their live model", {
			id = "native_hud::native HUD::recovers whole simplified zones in overflow and shares their live model",
			run = function()
				local built, root, stop, _, engine = mount()
				measure(root, engine, TINY)
				Verify.expect(#built.report().unshown > 3):toBe(true)
				sink(root).Activated.fire()
				local body = find(root.Parent, "OverflowBody")
				Verify.expect(body.ClassName):toBe("ScrollingFrame")
				for _, id in built.report().unshown do
					Verify.expect(`{id} {body:FindFirstChild("Rich" .. id) ~= nil}`):toBe(`{id} true`)
				end
				for _, text in { "Win a round", "+120", "24/90", "7/21", "2:14", "12", "9" } do
					Verify.expect((hasText(body, text))):toBe(true)
				end
				built.steps.advanceTask(2, 0.8)
				Verify.expect(find(find(body, "Task2"), "Fill1").Size.X.Scale):toBeCloseTo(0.8, 1e-4)
				find(body, "Weapon3").Activated.fire()
				Verify.expect((built.model.selectedWeapon:peek())):toBe(3)
				measure(root, engine, { 1040, 640 })
				Verify.expect(#built.report().unshown):toBe(0)
				Verify.expect(find(root.Parent, "OverflowEmpty").Text):toBe(hud.copy.overflowEmpty)
				Verify.expect(find(find(root, "Task2"), "Fill1").Size.X.Scale):toBeCloseTo(0.8, 1e-4)
				measure(root, engine, TINY)
				Verify.expect((find(root.Parent, "OverflowEmpty"))):toBe(nil)
				stop()
			end,
		})
		verifyHarness:case("expands a collapsed zone in context, anchored at it, instead of the overflow sheet", {
			id = "native_hud::native HUD::expands a collapsed zone in context, anchored at it, instead of the overflow sheet",
			run = function()
				local built, root, stop, _, engine = mount()
				measure(root, engine, PORTRAIT)
				Verify.expect(built.report().forms.Tasks ~= "full" and built.report().forms.Tasks ~= "hidden")
					:toBe(true)
				find(find(root, "Tasks"), "Expand").Activated.fire()
				Verify.expect(built.report().overflowOpen):toBe(false)
				local modal = find(root.Parent, "ExpandModal")
				Verify.expect((modal:GetAttribute("FacetRoute"))):toBe("popover")
				Verify.expect((hasText(modal, hud.copy.tasksTitle))):toBe(true)
				Verify.expect((hasText(modal, "+300"))):toBe(true)
				measure(root, engine, { 1040, 640 })
				Verify.expect((find(root.Parent, "ExpandModal"))):toBe(nil)
				stop()
			end,
		})
		verifyHarness:case("uses native body bounds after chrome layout and disconnects on disposal", {
			id = "native_hud::native HUD::uses native body bounds after chrome layout and disconnects on disposal",
			run = function()
				local built, root, stop, _, engine = mount()
				measure(root, engine, { 1040, 640 })
				local original = built.report().forms
				measure(root, engine, TINY)
				Verify.expect(built.report().forms.Tasks):toBe("hidden")
				Verify.expect(built.report().forms.Clock):toBe("timer")
				measure(root, engine, { 1040, 640 })
				Verify.expect(built.report().forms):toEqual(original)
				local zones = find(root, "Zones")
				local signal = zones:GetPropertyChangedSignal("AbsoluteSize")
				stop()
				Verify.expect((signal.count())):toBe(0)
			end,
		})
	end)
end
