--!strict
local t = require("./lib/testkit")
local world = require("./lib/world")
local Compose = require("../src").Compose
local skeleton = require("../src/controls/skeleton")
local function fixed(px)
	return { type = "fixed", px = px }
end
local function rect(w, path)
	return assert(w.adapter.node(path), path).rect
end
local function band(w, id)
	for _, path in w.adapter.paths() do
		if string.find(path, "/" .. id .. "/", 1, true) and string.sub(path, -5) == "/Band" then
			return rect(w, path)
		end
	end
	return nil
end
-- world owns applications even on assertion failure; its earlier finalizer runs first.
t.afterEach(function()
	t.expect(skeleton.liveDrivers()).toBe(0)
end)
t.describe("Skeleton", function()
	t.it("paints three inert forms and a paragraph with a sixty-percent final line", function()
		local w = world.new()
		local UI = w.UI
		w.present(function()
			return UI.Screen("S")({
				padding = 0,
				gap = 0,
				UI.Skeleton("Box")({ form = "box" }),
				UI.Skeleton("Circle")({ form = "circle" }),
				UI.Skeleton("Lines")({ form = "line", lines = 3 }),
			})
		end)
		t.expect(rect(w, "/S/Box").h).toBe(44)
		t.expect(rect(w, "/S/Circle").w).toBe(44)
		t.expect(rect(w, "/S/Circle").h).toBe(44)
		t.expect(rect(w, "/S/Lines/Line1").h).toBe(20)
		t.expect(rect(w, "/S/Lines/Line3").w).toBe(math.floor(rect(w, "/S/Lines/Line1").w * 0.6))
		t.expect(#w.handle.focusOrder().traversal).toBe(0)
		for _, path in w.adapter.paths() do
			local node = w.adapter.node(path)
			if string.sub(path, -6) == "/Plate" then
				t.expect(node.props.surface).toBeNil()
				t.expect(node.props.tint.role).toBe("control")
			end
		end
	end)
	t.it("resolves relative circle width once and derives its other axis", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 400, h = 200 } })
		local UI = w.UI
		local width = Compose.cell({ type = "percent", fraction = 0.5 })
		w.present(function()
			return UI.Screen("S")({
				padding = 0,
				UI.ZStack("Offer")({
					width = fixed(400),
					height = fixed(200),
					UI.Skeleton("Circle")({ form = "circle", width = width }),
				}),
			})
		end)
		t.expect(rect(w, "/S/Offer/Circle").w).toBe(200)
		t.expect(rect(w, "/S/Offer/Circle").h).toBe(200)
		width:set({ type = "percent", fraction = 0.25 })
		w.pres.refresh()
		t.expect(rect(w, "/S/Offer/Circle").w).toBe(100)
		t.expect(rect(w, "/S/Offer/Circle").h).toBe(100)
	end)
	t.it("paragraph bars fill one resolved relative width before the final sixty percent", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 400, h = 300 } })
		local UI = w.UI
		w.present(function()
			return UI.Screen("S")({
				padding = 0,
				UI.Skeleton("Copy")({ form = "line", lines = 3, width = { type = "percent", fraction = 0.5 } }),
			})
		end)
		t.expect(rect(w, "/S/Copy").w).toBe(200)
		t.expect(rect(w, "/S/Copy/Line1").w).toBe(200)
		t.expect(rect(w, "/S/Copy/Line3").w).toBe(120)
	end)
	t.it("keeps one driver alive after the first acquiring branch disappears", function()
		local w = world.new()
		local UI = w.UI
		local first = Compose.cell(true)
		local second = Compose.cell(true)
		w.present(function()
			return UI.Screen("S")({
				UI.When("First")({
					condition = first,
					thenView = function()
						return UI.Skeleton("A")({ form = "box" })
					end,
				}),
				UI.When("Second")({
					condition = second,
					thenView = function()
						return UI.Skeleton("B")({ form = "box" })
					end,
				}),
			})
		end)
		t.expect(skeleton.liveDrivers()).toBe(1)
		t.expect(w.pres.motionClock:activeCount()).toBe(1)
		first:set(false)
		w.pres.refresh()
		local before = band(w, "B").x
		w.tick(0.15)
		w.pres.refresh()
		t.expect(band(w, "B").x > before).toBe(true)
		t.expect(skeleton.liveDrivers()).toBe(1)
		second:set(false)
		w.pres.refresh()
		t.expect(w.pres.motionClock:activeCount()).toBe(0)
		t.expect(skeleton.liveDrivers()).toBe(0)
		for _ = 1, 4 do
			second:set(true)
			w.pres.refresh()
			t.expect(w.pres.motionClock:activeCount()).toBe(1)
			second:set(false)
			w.pres.refresh()
			t.expect(skeleton.liveDrivers()).toBe(0)
		end
	end)
	t.it("shares a clock without sharing between applications and detaches immediately", function()
		local a, b = world.new(), world.new()
		for _, w in { a, b } do
			local UI = w.UI
			w.present(function()
				return UI.Screen("S")({ UI.Skeleton("A")({ form = "box" }), UI.Skeleton("B")({ form = "line" }) })
			end)
			t.expect(w.pres.motionClock:activeCount()).toBe(1)
		end
		t.expect(skeleton.liveDrivers()).toBe(2)
		a.app.dispose()
		t.expect(skeleton.liveDrivers()).toBe(1)
		t.expect(b.pres.motionClock:activeCount()).toBe(1)
		b.app.dispose()
		t.expect(skeleton.liveDrivers()).toBe(0)
	end)
	t.it("removes the sweep under reduced motion and resumes without replacing its plate", function()
		local w = world.new()
		local UI = w.UI
		local record
		w.present(function()
			return UI.Screen("S")({
				UI.Skeleton("A")({
					form = "box",
					ref = function(value)
						record = value
					end,
				}),
			})
		end)
		local plate = w.adapter.node("/S/A/Plate")
		w.env:set("reducedMotion", true)
		w.pres.refresh()
		t.expect(band(w, "A")).toBeNil()
		t.expect(record.dump().animating).toBe(false)
		t.expect(w.pres.motionClock:activeCount()).toBe(0)
		w.env:set("reducedMotion", false)
		w.pres.refresh()
		t.expect(band(w, "A") ~= nil).toBe(true)
		t.expect(w.adapter.node("/S/A/Plate")).toBe(plate)
		t.expect(w.pres.motionClock:activeCount()).toBe(1)
	end)
	t.it("reducing motion before the render drain never recursively restarts a settled sweep", function()
		local w = world.new()
		local UI = w.UI
		w.present(function()
			return UI.Screen("S")({ UI.Skeleton("A")({ form = "box" }) })
		end)
		w.tick(1.1)
		w.app.runtime.reactor:batch(function()
			w.env:set("reducedMotion", true)
			w.pres.tick(0.2)
		end)
		t.expect(w.pres.motionClock:lastError()).toBeNil()
		t.expect(w.pres.motionClock:activeCount()).toBe(0)
		w.pres.refresh()
		t.expect(band(w, "A")).toBeNil()
		w.env:set("reducedMotion", false)
		w.pres.refresh()
		local before = band(w, "A").x
		w.tick(0.15)
		w.pres.refresh()
		t.expect(band(w, "A").x > before).toBe(true)
		t.expect(w.pres.motionClock:lastError()).toBeNil()
	end)
	t.it("owns a native rounded mask only while a circle sweep is mounted", function()
		local w = world.new()
		local UI = w.UI
		w.present(function()
			return UI.Screen("S")({ UI.Skeleton("A")({ form = "circle" }) })
		end)
		local path = "/S/A/Shimmer/then/Mask"
		local mask = assert(w.adapter.node(path))
		t.expect(mask.canvasGroupInstance.className).toBe("CanvasGroup")
		t.expect(mask.props.shape).toBe("circle")
		t.expect(assert(w.adapter.node("/S/A/Plate")).props.shape).toBe("circle")
		t.expect(mask.rect).toEqual(rect(w, "/S/A"))
		t.expect(w.adapter.node(path .. "/Sweep/Band") ~= nil).toBe(true)
		w.env:set("reducedMotion", true)
		w.pres.refresh()
		t.expect(w.adapter.node(path)).toBeNil()
		t.expect(w.adapter.node("/S/A/Plate") ~= nil).toBe(true)
	end)
	t.it("contains every moving band at fractional widths through full cycles", function()
		local w = world.new()
		local UI = w.UI
		local width = Compose.cell(fixed(390))
		w.present(function()
			return UI.Screen("S")({ padding = 0, UI.Skeleton("A")({ form = "box", width = width }) })
		end)
		for _, px in { 390, 101, 43.5, 0.5 } do
			width:set(fixed(px))
			w.pres.refresh()
			for _ = 1, 80 do
				w.tick(0.02)
				w.pres.refresh()
				local p, b = rect(w, "/S/A"), band(w, "A")
				t.expect(b.x >= p.x).toBe(true)
				t.expect(b.x + b.w <= p.x + p.w + 0.001).toBe(true)
			end
		end
	end)
	t.it("validates every bound rung before geometry changes and recovers to regular", function()
		local w = world.new()
		local UI = w.UI
		local rung = Compose.cell("compact")
		w.present(function()
			return UI.Screen("S")({
				UI.Skeleton("A")({
					form = "circle",
					controlSize = function(use)
						return use(rung)
					end,
				}),
			})
		end)
		t.expect(rect(w, "/S/A").w).toBe(36)
		pcall(function()
			rung:set("wrong")
		end)
		w.pres.refresh()
		t.expect(rect(w, "/S/A").w).toBe(36)
		rung:set("large")
		w.pres.refresh()
		t.expect(rect(w, "/S/A").w).toBe(56)
		rung:set(nil)
		w.pres.refresh()
		t.expect(rect(w, "/S/A").w).toBe(44)
	end)
	t.it("obeys parent alignment in both one-line and paragraph forms", function()
		local w = world.new()
		local UI = w.UI
		w.present(function()
			return UI.Screen("S")({
				padding = 0,
				UI.VStack("Col")({
					width = UI.fill(),
					align = "center",
					UI.Skeleton("One")({ form = "line", width = fixed(120) }),
					UI.Skeleton("Many")({ form = "line", lines = 3, width = fixed(120) }),
				}),
			})
		end)
		t.expect(rect(w, "/S/Col/One").x).toBe(rect(w, "/S/Col/Many").x)
	end)
	t.it("refuses malformed form-specific declarations without retaining a driver", function()
		local w = world.new()
		local UI = w.UI
		for _, spec in
			{
				{},
				{ form = "wrong" },
				{ form = "box", lines = 2 },
				{ form = "line", lines = 0 },
				{ form = "line", lines = 1.5 },
				{ form = "circle", height = fixed(44) },
				{ form = "circle", corners = "pill" },
				{ form = "box", controlSize = "wrong" },
				{ form = "box", surprise = true },
			}
		do
			t.expect(pcall(function()
				w.scoped(function()
					UI.Skeleton(spec)
				end)
			end)).toBe(false)
			t.expect(skeleton.liveDrivers()).toBe(0)
		end
	end)
	t.it("releases a held shared driver after later primitive construction refuses", function()
		local w = world.new()
		t.expect(pcall(function()
			w.present(function()
				return w.UI.Screen("S")({ w.UI.Skeleton("Bad")({ form = "box", width = { type = "unknown" } }) })
			end)
		end)).toBe(false)
		t.expect(skeleton.liveDrivers()).toBe(0)
		t.expect(w.pres.motionClock:activeCount()).toBe(0)
		t.expect(#w.adapter.paths()).toBe(0)
		w.present(function()
			return w.UI.Screen("Good")({ w.UI.Skeleton("A")({ form = "box" }) })
		end)
		t.expect(skeleton.liveDrivers()).toBe(1)
	end)
	t.it("releases a held shared driver when initial layout refuses a resolved metric", function()
		local snapshot = require("../src/themes/snapshot")
		local metrics = table.clone(snapshot.neutral())
		metrics.targetSizes = table.clone(metrics.targetSizes)
		metrics.targetSizes.minimum = -1
		local w = world.new({ themeMetrics = metrics })
		local ok, err = pcall(function()
			w.present(function()
				return w.UI.Screen("S")({
					w.UI.Skeleton("Bad")({ form = "box", width = { type = "fill", min = "targetSizes.minimum" } }),
				})
			end)
		end)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "fill min must resolve", 1, true) ~= nil).toBe(true)
		t.expect(skeleton.liveDrivers()).toBe(0)
		t.expect(w.pres.motionClock:activeCount()).toBe(0)
		t.expect(w.adapter.liveCount()).toBe(0)
		t.expect(w.adapter.rootCount()).toBe(0)
		w.env:set("themeMetrics", snapshot.neutral())
		w.present(function()
			return w.UI.Screen("Good")({ w.UI.Skeleton("A")({ form = "box" }) })
		end)
		t.expect(skeleton.liveDrivers()).toBe(1)
	end)
	t.it("keeps an informational plate when no clock is supplied", function()
		local w = world.new()
		local UI = w.UI
		w.present(function()
			local result = skeleton.build(
				{ UI = select(2, require("./lib/harness").libraryOf(w.core)) },
				w.core,
				{ id = "Static", form = "circle" }
			)
			return UI.Screen("S")({ result.blueprint })
		end)
		t.expect(rect(w, "/S/Static").w).toBe(44)
		t.expect(band(w, "Static")).toBeNil()
		t.expect(skeleton.liveDrivers()).toBe(0)
	end)
end)

t.describe("Skeleton gallery", function()
	t.it("reports solved mounted silhouettes, motion, branch changes and teardown", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 900 } })
		local built = require("../examples/gallery/scenarios/skeleton").build({
			Facet = require("../src"),
			UI = w.UI,
			Compose = Compose,
			env = w.env,
			presenter = w.pres,
		})
		t.expect(built.report()).toBeNil()
		w.present(built.screen)
		t.expect(built.report().box.h).toBe(44)
		t.expect(built.report().circle.w).toBe(44)
		t.expect(built.report().animating).toBe(true)
		t.expect(built.steps.removeFirst().box).toBeNil()
		t.expect(built.report().animating).toBe(true)
		t.expect(built.steps.reduced().animating).toBe(false)
		t.expect(built.steps.full().animating).toBe(true)
		t.expect(w.adapter.driveActivate("/Skeleton/Content/SkeletonRecipe/Commands/Ready")).toBe(true)
		w.settle()
		t.expect(built.report().loading).toBe(false)
		t.expect(skeleton.liveDrivers()).toBe(0)
		t.expect(built.steps.loading().circle.w).toBe(44)
		w.close()
		t.expect(built.report()).toBeNil()
		t.expect(skeleton.liveDrivers()).toBe(0)
	end)
end)
