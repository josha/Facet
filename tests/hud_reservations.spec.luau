--!strict
local harness = require("./lib/harness")
local scenario_app = require("./lib/scenario_app")
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local world = require("./lib/harness_world")

t.describe("HUD reservations", function()
	t.it("coordinates independent surfaces and releases their measured space", function()
		local w = world.new()
		local owner = w.core.owner.createChild()
		local reserved = w.pres.reserveHud({ id = "Banner", edge = "top", scope = owner })
		reserved.update({ x = 0, y = 30, w = 390, h = 60 })
		local insets = Facet.layout.hudInsets({
			bounds = { x = 0, y = 50, w = 390, h = 500 },
			reservations = w.pres.hudReservations:peek(),
		})
		t.expect(insets.top).toBe(40)
		t.expect(insets.bottom).toBe(0)
		reserved.update({ x = 0, y = 30, w = 390, h = 80 })
		t.expect(#w.pres.hudReservations:peek()).toBe(1)
		owner:dispose()
		t.expect(#w.pres.hudReservations:peek()).toBe(0)
		reserved.dispose()
	end)
	t.it("toasts reserve space until their final exit and never claim focus", function()
		local w = world.new({ reducedMotion = true })
		w.present(harness.UI.Screen({ id = "S", children = { harness.UI.Button({ id = "B", label = "Play" }) } }))
		local focused = w.pres.focus.focused:peek()
		local toast = w.pres.presentToast(harness.UI.Text({ text = "Saved" }), { position = "bottom" })
		w.settle()
		local rows = w.pres.hudReservations:peek()
		t.expect(#rows).toBe(1)
		t.expect(rows[1].edge).toBe("bottom")
		t.expect(rows[1].rect.h > 0).toBe(true)
		t.expect(w.pres.focus.focused:peek()).toBe(focused)
		toast.dismiss()
		w.settle(10)
		t.expect(#w.pres.hudReservations:peek()).toBe(0)
	end)
	t.it("insets ignore outside reservations and never consume more than the box", function()
		local bounds = { x = 10, y = 20, w = 100, h = 80 }
		local insets = Facet.layout.hudInsets({
			bounds = bounds,
			reservations = {
				{ id = "Outside", edge = "top", rect = { x = 200, y = 0, w = 10, h = 80 } },
				{ id = "Bottom", edge = "bottom", rect = { x = 10, y = 75, w = 100, h = 25 } },
			},
		})
		t.expect(insets.top).toBe(0)
		t.expect(insets.bottom).toBe(25)
	end)
	t.it("refusing a disposed owner leaves the reservation ID reusable", function()
		local w = world.new()
		local scope = w.core.owner.createChild()
		scope:dispose()
		t.expect(pcall(function()
			w.pres.reserveHud({ id = "Banner", edge = "top", scope = scope })
		end)).toBe(false)
		local reservation = w.pres.reserveHud({ id = "Banner", edge = "top" })
		reservation.update({ x = 0, y = 0, w = 390, h = 30 })
		t.expect(#w.pres.hudReservations:peek()).toBe(1)
		reservation.dispose()
	end)

	t.it("an invalid toast does not retain its HUD reservation", function()
		local w = world.new()
		t.expect(pcall(function()
			w.pres.presentToast(harness.UI.Text({ text = "Invalid" }), { transition = "wrong" })
		end)).toBe(false)
		local toast = w.pres.presentToast(harness.UI.Text({ text = "Valid" }))
		w.settle()
		t.expect(#w.pres.hudReservations:peek()).toBe(1)
		toast.dismiss()
		w.settle(20)
	end)

	for _, input in { "Gamepad", "Keyboard", "Touch", "MouseKeyboard" } do
		t.it(input .. " can use HUD actions and recover focus after a notification", function()
			local w = world.new({
				viewport = { x = 0, y = 0, w = 1280, h = 800 },
				preferredInput = input,
				reducedMotion = true,
			})
			local built = require("../examples/gallery/scenarios/hud").build({
				Facet = Facet,
				app = scenario_app.over(w.core, w.pres),
				UI = (harness.libraryOf(w.core)),
				Compose = Facet.Compose,
				core = w.core,
				env = w.env,
				presenter = w.pres,
			})
			w.present(built.screen, built.present)
			w.settle(4)
			local function pathEnding(suffix)
				for _, path in w.adapter.paths() do
					local node = w.adapter.node(path)
					if path:sub(-#suffix) == suffix and node.rect and node.rect.w > 0 and node.rect.h > 0 then
						return path
					end
				end
				error("Missing " .. suffix)
			end
			local trigger = pathEnding("/R1")
			local function activate(path)
				if input == "Touch" or input == "MouseKeyboard" then
					local r = w.adapter.node(path).rect
					w.adapter.tap(path, {
						source = "pointer",
						pointer = if input == "Touch" then "touch" else "mouse",
						x = r.x + r.w / 2,
						y = r.y + r.h / 2,
					})
				else
					w.pres.focus.focusOn(path)
					w.press(if input == "Gamepad" then "ButtonA" else "Return")
				end
				w.settle(4)
			end
			activate(trigger)
			activate(pathEnding("/Item:damage"))
			t.expect(built.report().healthMeter.fraction < 0.84).toBe(true)
			activate(trigger)
			activate(pathEnding("/Item:heal"))
			t.expect(built.report().healthMeter.fraction).toBe(1)
			activate(trigger)
			activate(pathEnding("/Item:notice"))
			t.expect(w.pres.toastCounts().visible).toBe(1)
			t.expect(#w.pres.hudReservations:peek()).toBe(1)
			local notice = w.pres.hudReservations:peek()[1].rect
			local overlaps = require("../src/rect").overlaps
			for _, path in w.adapter.paths() do
				if path:match("^/HudScreen/Hud/[^/]+$") then
					local r = w.adapter.node(path).rect
					if r and r.w > 0 and r.h > 0 then
						t.expect(overlaps(r, notice)).toBe(false)
					end
				end
			end
			if input == "Gamepad" or input == "Keyboard" then
				t.expect(w.pres.focus.focused:peek()).toBe(trigger)
				activate(trigger)
				if input == "Gamepad" then
					w.press("ButtonB")
				else
					activate(pathEnding("/Item:close"))
				end
				w.settle(4)
				t.expect(w.pres.focus.focused:peek()).toBe(trigger)
			end
			w.pres.dismiss(w.handle)
			built.dispose()
			w.settle(10)
			t.expect(#w.pres.hudReservations:peek()).toBe(0)
		end)
	end

	for _, viewport in { { x = 0, y = 0, w = 390, h = 844 }, { x = 0, y = 0, w = 1920, h = 1080 } } do
		t.it("D-pad reaches HUD actions at width " .. viewport.w, function()
			local w = world.new({
				viewport = viewport,
				preferredInput = "Gamepad",
				capabilities = { gamepad = true },
				env = { preferredTextOffset = 14, viewingDistance = if viewport.w > 1000 then "ten-foot" else "near" },
				reducedMotion = true,
			})
			local built = require("../examples/gallery/scenarios/hud").build({
				Facet = Facet,
				app = scenario_app.over(w.core, w.pres),
				UI = (harness.libraryOf(w.core)),
				Compose = Facet.Compose,
				core = w.core,
				env = w.env,
				presenter = w.pres,
			})
			w.present(built.screen, built.present)
			w.settle(4)
			local visits, reached = {}, false
			for _ = 1, 1280 do
				local current = w.pres.focus.focused:peek()
				assert(current, "HUD lost focus")
				if current:match("/R1$") then
					reached = true
					break
				end
				local edges = visits[current] or {}
				visits[current] = edges
				local nextKey, count = nil, math.huge
				for _, key in { "DPadUp", "DPadDown", "DPadLeft", "DPadRight" } do
					if (edges[key] or 0) < count then
						nextKey, count = key, edges[key] or 0
					end
				end
				edges[nextKey] = count + 1
				w.press(nextKey)
			end
			t.expect(reached).toBe(true)
			local trigger = w.pres.focus.focused:peek()
			w.press("ButtonA")
			w.settle(4)
			t.expect(w.pres.focus.focused:peek():match("/Item:damage$") ~= nil).toBe(true)
			w.press("ButtonA")
			w.settle(4)
			t.expect(built.report().healthMeter.fraction < 0.84).toBe(true)
			t.expect(w.pres.focus.focused:peek()).toBe(trigger)
			w.pres.dismiss(w.handle)
			built.dispose()
		end)
	end
end)
