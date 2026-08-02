--!strict
-- Touch gesture normalization + arbitration tests (corrections addendum §2). The
-- engine recognizes gestures; we normalize its positional callback args into
-- stable value objects (tolerating missing optional fields) and arbitrate which
-- stream owns the interaction. Deterministic — no engine, no DataModel.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local touch = require("../src/input/touch_gestures")

-- test Vector2-likes in BOTH the engine {X=,Y=} and lower-case {x=,y=} shapes
local function V(x: number, y: number)
	return { X = x, Y = y }
end

describe("touch_gestures.normalize (corrections §2)", function()
	it("normalizes a tap: instantaneous, positions extracted, state 'none'", function()
		local g = touch.normalize("TouchTap", { { V(10, 20) } })
		expect(g.kind).toBe("tap")
		expect(g.state).toBe("none")
		expect(g.positions[1].x).toBe(10)
		expect(g.positions[1].y).toBe(20)
	end)

	it("normalizes a longPress and maps UserInputState names to lifecycle states", function()
		expect(touch.normalize("TouchLongPress", { { V(1, 1) }, "Begin" }).state).toBe("began")
		expect(touch.normalize("TouchLongPress", { { V(1, 1) }, "Change" }).state).toBe("changed")
		expect(touch.normalize("TouchLongPress", { { V(1, 1) }, "End" }).state).toBe("ended")
	end)

	it("accepts Enum-like { Name = ... } state values", function()
		local g = touch.normalize("TouchLongPress", { { V(1, 1) }, { Name = "Begin" } })
		expect(g.state).toBe("began")
	end)

	it("normalizes a pan: Vector2 velocity + totalTranslation + state", function()
		local g = touch.normalize("TouchPan", { { V(5, 5) }, V(12, -3), V(4, 0), "Change" })
		expect(g.kind).toBe("pan")
		expect(g.state).toBe("changed")
		expect((g.totalTranslation :: any).x).toBe(12)
		expect((g.totalTranslation :: any).y).toBe(-3)
		expect((g.velocity :: any).x).toBe(4) -- pan velocity is a Vector2
	end)

	it("normalizes a pinch: scalar velocity + scale", function()
		local g = touch.normalize("TouchPinch", { { V(0, 0), V(10, 0) }, 1.5, 0.2, "Change" })
		expect(g.kind).toBe("pinch")
		expect(g.scale).toBe(1.5)
		expect(g.velocity).toBe(0.2) -- pinch velocity is a scalar number
		expect(#g.positions).toBe(2)
	end)

	it("normalizes a rotate: rotation + scalar velocity", function()
		local g = touch.normalize("TouchRotate", { { V(0, 0), V(10, 0) }, 45, -1.1, "End" })
		expect(g.kind).toBe("rotate")
		expect(g.rotation).toBe(45)
		expect(g.velocity).toBe(-1.1)
		expect(g.state).toBe("ended")
	end)

	it("normalizes a swipe: direction name, no positions, state 'none'", function()
		local g = touch.normalize("TouchSwipe", { { Name = "Right" }, 1 })
		expect(g.kind).toBe("swipe")
		expect(g.direction).toBe("Right")
		expect(g.state).toBe("none")
		expect(#g.positions).toBe(0)
	end)

	it("tolerates missing optional fields without erroring", function()
		-- a pan callback with only positions: no translation/velocity/state
		local g = touch.normalize("TouchPan", { { V(1, 1) } })
		expect(g.state).toBe("none")
		expect(g.totalTranslation).toBe(nil)
		expect(g.velocity).toBe(nil)
		-- entirely empty args
		local empty = touch.normalize("TouchTap", nil)
		expect(#empty.positions).toBe(0)
		-- unknown state name collapses to "none"
		expect(touch.normalize("TouchPinch", { {}, 1, 0, "Cancel" }).state).toBe("none")
	end)

	it("accepts short kind names too", function()
		expect(touch.normalize("pan", { { V(1, 1) }, V(0, 0), V(0, 0), "Begin" }).kind).toBe("pan")
	end)
end)

describe("touch_gestures.newArbiter (corrections §2)", function()
	it("pinch preempts pan: two-finger intent takes ownership", function()
		local arb = touch.newArbiter()
		expect(arb:feed(touch.normalize("TouchPan", { {}, V(0, 0), V(0, 0), "Begin" }))).toBe("own")
		expect(arb:owner()).toBe("pan")
		-- pinch begins alongside: it preempts the pan
		expect(arb:feed(touch.normalize("TouchPinch", { {}, 1, 0, "Begin" }))).toBe("own")
		expect(arb:owner()).toBe("pinch")
		-- the pan's next frame is now preempted
		expect(arb:feed(touch.normalize("TouchPan", { {}, V(1, 1), V(0, 0), "Change" }))).toBe("preempted")
	end)

	it("rotate also preempts pan", function()
		local arb = touch.newArbiter()
		arb:feed(touch.normalize("TouchPan", { {}, V(0, 0), V(0, 0), "Begin" }))
		expect(arb:feed(touch.normalize("TouchRotate", { {}, 10, 0, "Begin" }))).toBe("own")
		expect(arb:owner()).toBe("rotate")
	end)

	it("a began longPress preempts tap", function()
		local arb = touch.newArbiter()
		expect(arb:feed(touch.normalize("TouchLongPress", { {}, "Begin" }))).toBe("own")
		-- an instantaneous tap is suppressed while the longPress owns
		expect(arb:feed(touch.normalize("TouchTap", { {} }))).toBe("preempted")
	end)

	it("swipe and tap are instantaneous and never own on their own", function()
		local arb = touch.newArbiter()
		expect(arb:feed(touch.normalize("TouchTap", { {} }))).toBe("pass")
		expect(arb:owner()).toBe(nil)
		expect(arb:feed(touch.normalize("TouchSwipe", { { Name = "Left" } }))).toBe("pass")
		expect(arb:owner()).toBe(nil)
	end)

	it("ownership releases on the owning gesture's 'ended' frame", function()
		local arb = touch.newArbiter()
		arb:feed(touch.normalize("TouchPinch", { {}, 1, 0, "Begin" }))
		expect(arb:owner()).toBe("pinch")
		expect(arb:feed(touch.normalize("TouchPinch", { {}, 1.2, 0, "End" }))).toBe("own")
		expect(arb:owner()).toBe(nil) -- freed
		-- a fresh pan can now own
		expect(arb:feed(touch.normalize("TouchPan", { {}, V(0, 0), V(0, 0), "Begin" }))).toBe("own")
		expect(arb:owner()).toBe("pan")
	end)
end)
