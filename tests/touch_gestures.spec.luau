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

	-- SEAM-3 second half: the engine hands the callback REAL `Vector2`s, which are
	-- USERDATA, not tables. A reader that only accepted tables returned an empty
	-- positions list for every real touch while every headless test (which passes
	-- `{X=,Y=}` tables) stayed green — the same "headless shape is not the engine
	-- shape" class as SF-M9. `engineVec` stands in for a Vector2: userdata with
	-- numeric X/Y.
	local function engineVec(x: number, y: number): any
		local proxy = newproxy(true)
		local mt = getmetatable(proxy) :: any
		mt.__index = function(_, key)
			if key == "X" then
				return x
			elseif key == "Y" then
				return y
			end
			return nil
		end
		return proxy
	end

	it("reads ENGINE Vector2 userdata, not only {X=,Y=} tables (SEAM-3)", function()
		local g = touch.normalize("TouchPan", { { engineVec(10, 20) }, engineVec(3, -4), engineVec(1, 2), "Change" })
		expect(#g.positions).toBe(1)
		expect(g.positions[1].x).toBe(10)
		expect(g.positions[1].y).toBe(20)
		expect((g.totalTranslation :: any).x).toBe(3)
		expect((g.totalTranslation :: any).y).toBe(-4)
		expect((g.velocity :: any).y).toBe(2)
	end)

	it("reads a real EnumItem's Name (userdata state / swipe direction)", function()
		local function enumItem(name: string): any
			local proxy = newproxy(true)
			local mt = getmetatable(proxy) :: any
			mt.__index = function(_, key)
				return if key == "Name" then name else nil
			end
			return proxy
		end
		-- the adapter forwards the engine's arguments UNTOUCHED, so `state` arrives
		-- as Enum.UserInputState and `direction` as Enum.SwipeDirection
		expect(touch.normalize("TouchPan", { {}, nil, nil, enumItem("Begin") }).state).toBe("began")
		expect(touch.normalize("TouchSwipe", { enumItem("Right"), 1 }).direction).toBe("Right")
	end)

	it("a value object with no numeric X/Y is still not a position (no invention)", function()
		local opaque = newproxy(true) -- no __index: reading .X errors
		local g = touch.normalize("TouchTap", { { opaque, 7, "nope" } })
		expect(#g.positions).toBe(0)
	end)
end)

-- SEAM-3: the ONLY production caller of `normalize` is the ScreenTarget's
-- `setTouchGestureHandlers`, and it cannot load headless (it reaches engine
-- globals at load), so its SOURCE is the contract — the same instrument the
-- prop-parity check uses on the same file. A named-key call there is invisible
-- to every other test in this suite: the fake target only stores the sink, and
-- the specs above hand `normalize` an already-correct array.
describe("the live ScreenTarget calls normalize POSITIONALLY (SEAM-3)", function()
	local fs = require("@lune/fs")
	local liveSource = fs.readFile("src/client/screen_target.luau")

	it("passes the engine's argument list in order, for all six gesture kinds", function()
		local expected = {
			tap = "{ positions }",
			longPress = "{ positions, state }",
			pan = "{ positions, totalTranslation, velocity, state }",
			pinch = "{ positions, scale, velocity, state }",
			rotate = "{ positions, rotation, velocity, state }",
			swipe = "{ direction, numberOfTouches }",
		}
		for kind, args in expected do
			local call = `normalize("{kind}", {args})`
			if string.find(liveSource, call, 1, true) == nil then
				error(`screen_target does not call {call} — the engine's positional args are the contract`, 0)
			end
		end
	end)

	it("passes no NAMED-key table (a[1]..a[4] nil = every gesture normalizes empty)", function()
		-- the exact defect shape: `normalize("<kind>", { positions = ...`
		expect(string.find(liveSource, 'normalize("tap", { positions =', 1, true)).toBe(nil)
		for _, key in { "positions =", "totalTranslation =", "scale =", "rotation =", "direction =" } do
			local at = string.find(liveSource, key, 1, true)
			while at ~= nil do
				-- no occurrence of a named gesture key may sit inside a normalize call
				local windowStart = math.max(1, at - 200)
				local window = string.sub(liveSource, windowStart, at)
				expect(string.find(window, "touch_gestures.normalize(", 1, true)).toBe(nil)
				at = string.find(liveSource, key, at + 1, true)
			end
		end
	end)
end)

describe("touch_gestures.newArbiter (corrections §2)", function()
	-- SEAM-4: an accepted-and-ignored option is the silent-failure class. The
	-- arbitration policy (RANK) is fixed today, so the only honest answer to
	-- `newArbiter({ rank = ... })` is a construction-time refusal that says so.
	it("refuses a non-empty opts table: options are RESERVED, none exist yet (SEAM-4)", function()
		local ok, err = pcall(function()
			return touch.newArbiter({ rank = { pinch = 9 } } :: any)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "newArbiter", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "reserved", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "rank", 1, true) ~= nil).toBe(true) -- names what was passed
	end)

	it("nil and an EMPTY opts table stay legal (the reserved shape is the signature)", function()
		expect(touch.newArbiter() ~= nil).toBe(true)
		expect(touch.newArbiter(nil) ~= nil).toBe(true)
		expect(touch.newArbiter({}) ~= nil).toBe(true)
	end)

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
