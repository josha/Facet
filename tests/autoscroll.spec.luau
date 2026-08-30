--!strict
-- Edge autoscroll, the pure model (row SF-L2). Every case
-- drives a SCRIPTED clock, so dwell, ramp, penetration, the canvas clamp and the
-- exit decay are exact numbers rather than "it felt about right". The model
-- scrolls nothing: it answers a delta and a state, and the host applies them.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local autoscroll = require("../src/input/autoscroll")

-- a 200-tall viewport at y=100, x∈[0,300): the top band is y∈[100,140), the
-- bottom band is y∈(260,300]
local HOST = { x = 0, y = 100, w = 300, h = 200 }
local MAX = 1000

local function driver(opts: any?)
	local model = autoscroll.new(opts)
	local now = 0
	local canvas = 0
	local api = {}
	function api.step(dt: number, x: number?, y: number?, maxScroll: number?)
		now += dt
		local step = model:step({
			now = now,
			pointerPos = if x ~= nil then { x = x, y = y :: number } else nil,
			hostRect = HOST,
			canvasPos = canvas,
			maxScroll = if maxScroll ~= nil then maxScroll else MAX,
		})
		canvas = math.clamp(canvas + step.delta, 0, if maxScroll ~= nil then maxScroll else MAX)
		return step
	end
	function api.canvas(): number
		return canvas
	end
	function api.model(): any
		return model
	end
	return api
end

describe("autoscroll: band membership is the POINTER point", function()
	it("the middle of the viewport is in no band", function()
		local d = driver()
		local step = d.step(0.016, 150, 200)
		expect(step.state).toBe("idle")
		expect(step.delta).toBe(0)
	end)

	it("the top band arms upward and the bottom band arms downward", function()
		local top = driver()
		top.step(0, 150, 110)
		top.step(0.35, 150, 110) -- past the 0.3 s dwell
		local step = top.step(0.2, 150, 110)
		expect(step.state).toBe("active")
		-- top band scrolls UP, so the canvas moves toward 0 (a negative delta);
		-- clamped to 0 here because the canvas starts there
		expect(step.delta <= 0).toBe(true)

		local bottom = driver()
		bottom.step(0, 150, 290)
		bottom.step(0.35, 150, 290)
		local down = bottom.step(0.2, 150, 290)
		expect(down.state).toBe("active")
		expect(down.delta > 0).toBe(true)
	end)

	it("a point outside the host horizontally is in no band", function()
		local d = driver()
		local step = d.step(0.4, 400, 110)
		expect(step.state).toBe("idle")
	end)

	it("bands never overlap: a host shorter than two bands splits at the midpoint", function()
		local model = autoscroll.new({ bandH = 40 })
		-- 50-tall host: each band is 25 deep, meeting exactly at the middle
		local short = { x = 0, y = 0, w = 100, h = 50 }
		local a =
			model:step({ now = 0, pointerPos = { x = 10, y = 24 }, hostRect = short, canvasPos = 0, maxScroll = 500 })
		expect(a.state).toBe("dwelling")
		expect(model:band()).toBe("top")
		local b = model:step({
			now = 0.01,
			pointerPos = { x = 10, y = 26 },
			hostRect = short,
			canvasPos = 0,
			maxScroll = 500,
		})
		expect(b.state).toBe("dwelling") -- crossing bands restarts the dwell
		expect(model:band()).toBe("bottom")
	end)
end)

describe("autoscroll: dwell is what makes a flick-through safe", function()
	it("does not move before the dwell elapses", function()
		local d = driver()
		expect(d.step(0, 150, 290).state).toBe("dwelling")
		expect(d.step(0.1, 150, 290).state).toBe("dwelling")
		expect(d.step(0.1, 150, 290).delta).toBe(0)
		expect(d.step(0.05, 150, 290).state).toBe("dwelling") -- 0.25 s: not yet
		expect(d.step(0.05, 150, 290).state).toBe("active") -- 0.30 s: armed
	end)

	it("jitter INSIDE the band accrues dwell; it never resets it", function()
		local d = driver()
		d.step(0, 150, 290)
		d.step(0.1, 152, 288)
		d.step(0.1, 148, 292)
		expect(d.step(0.1, 151, 289).state).toBe("active")
	end)

	it("a flick THROUGH the band never arms", function()
		local d = driver()
		expect(d.step(0, 150, 290).state).toBe("dwelling")
		expect(d.step(0.05, 150, 200).state).toBe("idle") -- left before dwelling out
		expect(d.step(0.5, 150, 200).state).toBe("idle") -- and time alone never arms it
	end)

	it("crossing to the other band restarts the dwell", function()
		local d = driver()
		d.step(0, 150, 290)
		d.step(0.25, 150, 290)
		expect(d.step(0.01, 150, 110).state).toBe("dwelling") -- crossed: back to zero
		expect(d.step(0.2, 150, 110).state).toBe("dwelling")
		expect(d.step(0.11, 150, 110).state).toBe("active")
	end)

	it("re-entering the band it just left re-pays the dwell", function()
		local d = driver()
		d.step(0, 150, 290)
		d.step(0.35, 150, 290)
		expect(d.model():state()).toBe("active")
		d.step(0.05, 150, 200) -- leave
		d.step(0.2, 150, 200) -- ...and settle out of the exit decay
		expect(d.step(0.01, 150, 290).state).toBe("dwelling")
	end)

	it("justArmed is true on exactly ONE frame per arming", function()
		local d = driver()
		d.step(0, 150, 290)
		expect(d.step(0.29, 150, 290).justArmed).toBe(false)
		expect(d.step(0.02, 150, 290).justArmed).toBe(true)
		expect(d.step(0.02, 150, 290).justArmed).toBe(false)
		expect(d.step(0.2, 150, 290).justArmed).toBe(false)
		-- ...and a fresh arming raises it again
		d.step(0.05, 150, 200)
		d.step(0.2, 150, 200)
		d.step(0.01, 150, 290)
		expect(d.step(0.35, 150, 290).justArmed).toBe(true)
	end)
end)

describe("autoscroll: speed is linear in penetration, behind a start ramp", function()
	it("deeper into the band is faster", function()
		local shallow = driver()
		shallow.step(0, 150, 262) -- barely inside the bottom band
		shallow.step(0.35, 150, 262)
		local shallowStep = shallow.step(1, 150, 262) -- ramp fully elapsed

		local deep = driver()
		deep.step(0, 150, 299) -- at the very edge
		deep.step(0.35, 150, 299)
		local deepStep = deep.step(1, 150, 299)

		expect(deepStep.delta > shallowStep.delta).toBe(true)
	end)

	it("the penetration mapping is v = vMin + (vMax - vMin) * p", function()
		local model = autoscroll.new({ dwellS = 0, rampS = 0, vMin = 100, vMax = 500, bandH = 40 })
		-- the midpoint of the bottom band = penetration 0.5 -> 300 px/s
		model:step({ now = 0, pointerPos = { x = 10, y = 280 }, hostRect = HOST, canvasPos = 0, maxScroll = MAX })
		local step =
			model:step({ now = 1, pointerPos = { x = 10, y = 280 }, hostRect = HOST, canvasPos = 0, maxScroll = MAX })
		expect(model:penetration()).toBe(0.5)
		expect(step.delta).toBe(300) -- 300 px/s over a 1 s frame
	end)

	it("the start ramp eases from zero over rampS, from the ARMING instant", function()
		local model = autoscroll.new({ dwellS = 0, rampS = 0.15, vMin = 100, vMax = 500, bandH = 40 })
		local function at(now: number, dt: number)
			return model:step({
				now = now,
				pointerPos = { x = 10, y = 299 },
				hostRect = HOST,
				canvasPos = 0,
				maxScroll = MAX,
			}).delta / dt
		end
		model:step({ now = 0, pointerPos = { x = 10, y = 299 }, hostRect = HOST, canvasPos = 0, maxScroll = MAX })
		local early = at(0.02, 0.02)
		local mid = at(0.08, 0.06)
		local full = at(0.30, 0.22)
		expect(early < mid).toBe(true)
		expect(mid < full).toBe(true)
		-- fully ramped: v(p) at p = 39/40 (the band is half-open at the very edge,
		-- so the deepest reachable point is one px inside) = 100 + 400*0.975
		expect(math.abs(full - 490) < 1).toBe(true)
	end)

	it("leaving while active decays to zero over exitEaseS instead of cutting", function()
		local d = driver()
		d.step(0, 150, 299)
		d.step(0.35, 150, 299)
		d.step(0.2, 150, 299) -- fully ramped
		local exiting = d.step(0.02, 150, 200)
		expect(exiting.state).toBe("exiting")
		expect(exiting.delta > 0).toBe(true) -- still coasting
		local done = d.step(0.1, 150, 200) -- past the 0.08 s decay
		expect(done.state).toBe("idle")
		expect(done.delta).toBe(0)
	end)

	--[[ D-11: the SAME 80 ms ease carries a DIRECT band cross. The shipped
		behaviour (`SponsorGesture:762-770`) applies the exit ease "uniformly to a
		direct band-cross too — reversing direction mid-ease reads better than a
		hard velocity flip", and the port must build the code behaviour. The state
		still restarts at "dwelling" (the cross IS a fresh intent); only the
		velocity coasts. ]]
	it("a DIRECT band cross coasts the old velocity out instead of cutting it (D-11)", function()
		local d = driver()
		d.step(0, 150, 299) -- deep in the bottom band
		d.step(0.35, 150, 299)
		local running = d.step(0.2, 150, 299) -- fully ramped, scrolling DOWN
		expect(running.state).toBe("active")
		expect(running.delta > 0).toBe(true)

		-- straight across to the top band: the dwell restarts, and the DOWNWARD
		-- velocity is still coasting out (positive delta) rather than snapping to 0
		local crossed = d.step(0.02, 150, 110)
		expect(crossed.state).toBe("dwelling")
		expect(crossed.delta > 0).toBe(true)

		-- ...and it is gone by the end of the 80 ms ease, still dwelling
		local settled = d.step(0.1, 150, 110)
		expect(settled.state).toBe("dwelling")
		expect(settled.delta).toBe(0)
	end)

	it("arming supersedes a coast rather than adding to it", function()
		local d = driver()
		d.step(0, 150, 299)
		d.step(0.35, 150, 299)
		d.step(0.2, 150, 299) -- fully ramped downward
		d.step(0.01, 150, 110) -- cross: coasting down while dwelling up
		-- arm the TOP band. The start ramp begins at zero, so the arming frame owes
		-- EXACTLY zero travel — a surviving downward coast would show up as a
		-- positive delta on the frame the upward scroll begins.
		local armed = d.step(0.3, 150, 110)
		expect(armed.state).toBe("active")
		expect(armed.delta).toBe(0)
		-- ...and from there it travels UP, the way the new band asks
		expect(d.step(0.05, 150, 110).delta < 0).toBe(true)
	end)

	it("leaving the band mid-coast keeps decaying instead of re-cutting", function()
		local d = driver()
		d.step(0, 150, 299)
		d.step(0.35, 150, 299)
		d.step(0.2, 150, 299)
		d.step(0.01, 150, 110) -- cross (coast live, state dwelling)
		local left = d.step(0.01, 150, 200) -- ...then leave both bands
		expect(left.state).toBe("exiting")
		expect(left.delta > 0).toBe(true)
		local done = d.step(0.1, 150, 200)
		expect(done.state).toBe("idle")
		expect(done.delta).toBe(0)
	end)
end)

describe("autoscroll: the ends of the world", function()
	it("clamps at the canvas end and STAYS armed (no re-paying the dwell)", function()
		local d = driver()
		d.step(0, 150, 299)
		d.step(0.35, 150, 299)
		for _ = 1, 20 do
			d.step(0.5, 150, 299) -- run it well past the end
		end
		expect(d.canvas()).toBe(MAX)
		local step = d.step(0.5, 150, 299)
		expect(step.delta).toBe(0)
		expect(step.state).toBe("active") -- clamped, not disarmed
	end)

	it("never scrolls past zero going the other way", function()
		local d = driver()
		d.step(0, 150, 110)
		d.step(0.35, 150, 110)
		local step = d.step(0.5, 150, 110)
		expect(step.delta).toBe(0) -- already at the top
		expect(d.canvas()).toBe(0)
	end)

	it("short content is INERT: bands never arm when there is nothing to scroll", function()
		local d = driver()
		expect(d.step(0, 150, 299, 0).state).toBe("idle")
		expect(d.step(0.5, 150, 299, 0).state).toBe("idle")
		expect(d.step(0.5, 150, 299, 0).delta).toBe(0)
	end)

	it("a nil pointer (no gesture) is the same as leaving the band", function()
		local d = driver()
		d.step(0, 150, 299)
		expect(d.step(0.35, 150, 299).state).toBe("active")
		local step = d.step(0.02, nil, nil)
		expect(step.state).toBe("exiting")
	end)

	it("reset returns it to idle and forgets the dwell", function()
		local d = driver()
		d.step(0, 150, 299)
		d.step(0.35, 150, 299)
		d.model():reset()
		expect(d.model():state()).toBe("idle")
		expect(d.step(0.01, 150, 299).state).toBe("dwelling")
	end)
end)

describe("autoscroll: the published defaults", function()
	it("ships the ratified numbers, and reports the tuning in force", function()
		local opts = autoscroll.new():options()
		expect(opts.bandH).toBe(40)
		expect(opts.dwellS).toBe(0.3)
		expect(opts.rampS).toBe(0.15)
		expect(opts.exitEaseS).toBe(0.08)
		expect(opts.vMin).toBe(100)
		expect(opts.vMax).toBe(500)
	end)

	it("portrait takes the taller band", function()
		expect(autoscroll.bandForViewport(800, 400)).toBe(40)
		expect(autoscroll.bandForViewport(400, 800)).toBe(44)
		expect(autoscroll.BAND_H.landscape).toBe(40)
		expect(autoscroll.BAND_H.portrait).toBe(44)
	end)

	it("garbage options fall back rather than producing a NaN delta", function()
		local model = autoscroll.new({ bandH = 0 / 0, dwellS = -5, vMin = 400, vMax = 100 })
		local opts = model:options()
		expect(opts.bandH).toBe(40)
		expect(opts.dwellS).toBe(0)
		expect(opts.vMax >= opts.vMin).toBe(true)
	end)
end)
