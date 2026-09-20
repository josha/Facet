--!strict
local harness = require("./lib/harness")
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local testWorld = require("./lib/harness_world")
local Compose = require("../src/vendor/compose/core")
local UI = harness.UI
local function world(build)
	local w = testWorld.new({ viewport = { x = 0, y = 0, w = 400, h = 600 }, ops = true })
	w.present(build(w.core))
	return w.core, w.env, w.adapter, w.pres, w.handle
end
local function settle(pres)
	for _ = 1, 180 do
		pres.tick(1 / 60)
	end
end
local function fixed(n)
	return { type = "fixed", px = n }
end

t.describe("declarative animation", function()
	t.it("coordinates layout on ordinary updates and coalesces consecutive writes", function()
		local height
		local _, _, adapter, pres, handle = world(function(core)
			height = Compose.cell(fixed(50))
			return UI.Screen({
				id = "S",
				padding = 0,
				gap = 0,
				animation = { layout = "container" },
				UI.Box({ id = "A", height = height }),
				UI.Box({ id = "B", height = fixed(30) }),
			})
		end)
		local before = adapter.node("/S/B").rect.y
		height:set(fixed(100))
		height:set(fixed(150))
		pres.refresh()
		t.expect(adapter.node("/S/B").rect.y).toBe(before + 100)
		t.expect(adapter.node("/S/B").presentedPosition.y).toBe(before)
		t.expect(pres.motionClock:activeCount()).toBe(1)
		pres.tick(1 / 60)
		local mid = adapter.node("/S/B").presentedPosition.y
		t.expect(mid > before and mid < before + 100).toBe(true)
		height:set(fixed(70))
		pres.refresh()
		t.expect(math.abs(adapter.node("/S/B").presentedPosition.y - mid) < 0.001).toBe(true)
		settle(pres)
		t.expect(pres.animationRecordCount()).toBe(0)
		t.expect(pres.motionClock:activeCount()).toBe(0)
		pres.dismiss(handle)
	end)
	t.it("keeps paint independent of layout and allows different property presets", function()
		local scale, opacity
		Facet.motion.registerCurve("authoringFade", { duration = 0.12, style = "linear" })
		local _, _, adapter, pres, handle = world(function(core)
			scale, opacity = Compose.cell(1), Compose.cell(1)
			return UI.Screen({
				id = "S",
				UI.Box({
					id = "A",
					scale = scale,
					opacity = opacity,
					animation = {
						scale = "object",
						opacity = "authoringFade",
					},
				}),
			})
		end)
		local stats = handle.controller.stats()
		scale:set(1.5)
		opacity:set(0.3)
		pres.refresh()
		t.expect(handle.controller.stats().solves).toBe(stats.solves)
		t.expect(adapter.node("/S/A").props.transform.scale).toBe(1)
		t.expect(adapter.node("/S/A").props.transparency).toBe(0)
		pres.tick(0.06)
		t.expect(adapter.node("/S/A").props.transform.scale > 1).toBe(true)
		t.expect(math.abs(adapter.node("/S/A").props.transparency - 0.35) < 0.001).toBe(true)
		local mid = adapter.node("/S/A").props.transform.scale
		scale:set(1.1)
		pres.refresh()
		t.expect(adapter.node("/S/A").props.transform.scale).toBe(mid)
		settle(pres)
		t.expect(math.abs(adapter.node("/S/A").props.transform.scale - 1.1) < 0.001).toBe(true)
		t.expect(pres.motionClock:activeCount()).toBe(0)
		pres.dismiss(handle)
	end)
	t.it("explicit false overrides withAnimation while local rules keep their preset", function()
		local scale, opacity
		local _, _, adapter, pres = world(function(core)
			scale, opacity = Compose.cell(1), Compose.cell(1)
			return UI.Screen({
				id = "S",
				UI.Box({
					id = "A",
					scale = scale,
					opacity = opacity,
					animation = { scale = "object", opacity = false },
				}),
			})
		end)
		pres.withAnimation("container", function()
			scale:set(1.5)
			opacity:set(0.4)
		end)
		t.expect(adapter.node("/S/A").props.transform.scale).toBe(1)
		t.expect(adapter.node("/S/A").props.transparency).toBe(0.6)
		settle(pres)
	end)
	t.it("reduced motion and viewport changes do not start layout flights", function()
		local height
		local _, env, _, pres = world(function(core)
			height = Compose.cell(fixed(50))
			return UI.Screen({
				id = "S",
				animation = { layout = "container" },
				UI.Box({ height = height }),
				UI.Text({ text = "Footer" }),
			})
		end)
		env:set("reducedMotion", true)
		height:set(fixed(100))
		pres.refresh()
		t.expect(pres.animationRecordCount()).toBe(0)
		env:set("reducedMotion", false)
		env:set("viewportRect", { x = 0, y = 0, w = 500, h = 700 })
		pres.refresh()
		t.expect(pres.animationRecordCount()).toBe(0)
		height:set(fixed(150))
		pres.refresh()
		t.expect(pres.animationRecordCount() > 0).toBe(true)
		env:set("viewportRect", { x = 0, y = 0, w = 600, h = 800 })
		pres.refresh()
		t.expect(pres.animationRecordCount()).toBe(0)
	end)
	t.it("starts branch state only at mount and cleans up direct children after exit", function()
		local open, alive = nil, 0
		local function Child()
			alive += 1
			Facet.Compose.cleanup(function()
				alive -= 1
			end)
			return UI.ZStack({ id = "Details", canvasGroup = true, height = fixed(80), UI.Text({ text = "Details" }) })
		end
		local _, _, _, pres, handle = world(function(core)
			open = Compose.cell(false)
			return UI.Screen({
				id = "S",
				animation = { layout = "container" },
				UI.When({ id = "Gate", condition = open, transition = { enter = "fade" }, thenView = Child }),
				UI.Text({ text = "Footer" }),
			})
		end)
		local function write(value: boolean)
			open:set(value)
		end
		t.expect(alive).toBe(0)
		write(true)
		pres.refresh()
		t.expect(alive).toBe(1)
		settle(pres)
		write(false)
		pres.refresh()
		settle(pres)
		pres.refresh()
		t.expect(alive).toBe(0)
		pres.dismiss(handle)
		t.expect(pres.motionClock:activeCount()).toBe(0)
	end)
	t.it("disposes active property motion with the surface", function()
		local scale
		local core, _, _, pres, handle = world(function(c)
			scale = Compose.cell(1)
			return UI.Screen({ id = "S", UI.Box({ scale = scale, animation = { scale = "object" } }) })
		end)
		local before = core.owner.size()
		scale:set(1.5)
		pres.refresh()
		t.expect(core.owner.size() > before).toBe(true)
		pres.dismiss(handle)
		settle(pres)
		t.expect(pres.motionClock:activeCount()).toBe(0)
		t.expect(core.owner.size() <= before).toBe(true)
	end)
end)

t.describe("coordination boundaries", function()
	t.it("gives nested groups independent presets without double-moving children", function()
		local outer, inner
		local _, _, adapter, pres = world(function(core)
			outer, inner = Compose.cell(fixed(30)), Compose.cell(fixed(40))
			return UI.Screen({
				id = "S",
				padding = 0,
				gap = 0,
				animation = { layout = "container" },
				UI.Box({ id = "Before", height = outer }),
				UI.VStack({
					id = "Inner",
					gap = 0,
					animation = { layout = "object" },
					UI.Box({ id = "Header", height = inner }),
					UI.Box({ id = "Body", height = fixed(20) }),
				}),
				UI.Box({ id = "After", height = fixed(20) }),
			})
		end)
		local before = adapter.node("/S/Inner/Body").presentedPosition.y
		outer:set(fixed(80))
		inner:set(fixed(100))
		pres.refresh()
		t.expect(adapter.node("/S/Inner/Body").presentedPosition.y).toBe(before)
		t.expect(pres.motionClock:activeCount()).toBe(2)
		settle(pres)
		local body = adapter.node("/S/Inner/Body")
		t.expect(body.presentedPosition.y).toBe(body.rect.y)
		t.expect(pres.animationRecordCount()).toBe(0)
	end)
	t.it("does not wrap motion-driven layout in another animation", function()
		local animated, target
		local w = testWorld.new({ viewport = { x = 0, y = 0, w = 400, h = 600 }, ops = true })
		local pres = w.pres
		target = Compose.cell(30)
		animated = pres.motionClock:animate(target, "object")
		w.present(UI.Screen({
			id = "S",
			animation = { layout = "container" },
			UI.Box({
				height = Compose.formula(function(use)
					return fixed(use(animated))
				end),
			}),
			UI.Text({ text = "After" }),
		}))
		local function write(value: number)
			target:set(value)
		end
		write(100)
		pres.refresh()
		for _ = 1, 60 do
			pres.tick(1 / 60)
			pres.refresh()
			t.expect(pres.animationRecordCount()).toBe(0)
		end
		t.expect(animated:peek()).toBe(100)
	end)
	t.it("cleans motion when reduced motion is enabled during a flight", function()
		local scale
		local _, env, adapter, pres = world(function(core)
			scale = Compose.cell(1)
			return UI.Screen({ id = "S", UI.Box({ id = "A", scale = scale, animation = { scale = "object" } }) })
		end)
		scale:set(1.5)
		pres.refresh()
		pres.tick(1 / 60)
		env:set("reducedMotion", true)
		pres.refresh()
		t.expect(adapter.node("/S/A").props.transform.scale).toBe(1.5)
		t.expect(pres.motionClock:activeCount()).toBe(0)
	end)
	t.it("runs the actual showcase through branches, reorder and purchases", function()
		local module = require("../examples/gallery/scenarios/component_motion")
		local w = testWorld.new({ viewport = { x = 0, y = 0, w = 800, h = 700 } })
		local core, env, presenter = w.core, w.env, w.pres
		local built = module.build({
			Facet = Facet,
			UI = (harness.libraryOf(core)),
			Compose = Facet.Compose,
			core = core,
			env = env,
			presenter = presenter,
		})
		local handle = presenter.present(built.screen)
		presenter.refresh()
		t.expect(built.report().balance).toBe(100)
		built.steps.toggle()
		presenter.refresh()
		t.expect(presenter.animationRecordCount() > 0).toBe(true)
		built.steps.reverse()
		presenter.refresh()
		t.expect(built.report().first).toBe("beacon")
		built.steps.buy()
		presenter.refresh()
		t.expect(built.report().balance).toBe(60)
		built.steps.buy()
		presenter.refresh()
		built.steps.buy()
		presenter.refresh()
		t.expect(built.report().balance).toBe(20)
		t.expect(built.report().affordable).toBe(false)
		settle(presenter)
		presenter.refresh()
		t.expect(core.lastError()).toBe(nil)
		presenter.dismiss(handle)
		settle(presenter)
		t.expect(presenter.motionClock:activeCount()).toBe(0)
	end)
end)
