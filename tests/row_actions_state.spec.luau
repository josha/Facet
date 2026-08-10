local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local state = require("../src/input/row_actions_state")

describe("row_actions_state", function()
	local function mk(over)
		local opts = {
			rowWidth = 320,
			leadingWidth = 80,
			trailingWidth = 160,
			fullSwipeLeading = false,
			fullSwipeTrailing = true,
		}
		for k, v in over or {} do
			opts[k] = v
		end
		return state.new(opts)
	end

	it("axis verdict stays pending under the lock radius", function()
		local s = mk()
		expect(s.axisVerdict(5, 4)).toBe("pending")
		expect(s.axisVerdict(9, 2)).toBe("horizontal")
		expect(s.axisVerdict(2, 9)).toBe("vertical")
	end)

	it("ties go vertical (scroll wins ambiguity)", function()
		expect(mk().axisVerdict(9, 9)).toBe("vertical")
	end)

	it("drag tracks linearly inside the tray", function()
		local s = mk()
		expect(s.clampDrag(-100)).toBe(-100) -- within trailing tray (160)
		expect(s.clampDrag(60)).toBe(60) -- within leading tray (80)
	end)

	it("rubber-bands past a non-fullSwipe tray", function()
		local s = mk()
		-- leading: fullSwipe off, tray 80; 40px past compresses by 0.55
		expect(s.clampDrag(120)).toBeCloseTo(80 + 40 * 0.55, 3)
	end)

	it("tracks the finger past a fullSwipe tray", function()
		local s = mk()
		expect(s.clampDrag(-240)).toBe(-240) -- trailing has fullSwipe
	end)

	it("an absent edge rubber-bands from zero", function()
		local s = mk({ leadingWidth = 0 })
		expect(s.clampDrag(50)).toBeCloseTo(50 * 0.55, 3)
		local v = s.settle(27, 0)
		expect(v.target).toBe(0)
		expect(v.edge).toBe(nil)
	end)

	it("settles open at half tray width", function()
		local s = mk()
		local v = s.settle(-81, 0) -- 160 * 0.5 = 80
		expect(v.target).toBe(-160)
		expect(v.edge).toBe("trailing")
		expect(v.commit).toBe(false)
	end)

	it("settles closed under half tray width", function()
		local v = mk().settle(-79, 0)
		expect(v.target).toBe(0)
		expect(v.commit).toBe(false)
	end)

	it("velocity projects the release (flick opens from a short drag)", function()
		-- 40px + (-600 px/s * 0.08s) = -88 → open
		local v = mk().settle(-40, -600)
		expect(v.target).toBe(-160)
		expect(v.edge).toBe("trailing")
	end)

	it("commits on full swipe past 60% of row width", function()
		local v = mk().settle(-200, 0) -- 320 * 0.6 = 192
		expect(v.commit).toBe(true)
		expect(v.edge).toBe("trailing")
	end)

	it("never commits when fullSwipe is off for that edge", function()
		local v = mk().settle(300, 0) -- leading, fullSwipe off
		expect(v.commit).toBe(false)
		expect(v.target).toBe(80)
		expect(v.edge).toBe("leading")
	end)
end)
