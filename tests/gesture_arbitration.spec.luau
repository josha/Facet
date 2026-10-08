--!strict
local Verify = require("../tools/vendor/verify/src/core")
local arbitration = require("../src/ui/gesture_arbitration")
local engineLib = require("./lib/native_engine")

return function(harness: Verify.Harness)
	harness:suite("gesture ownership", function()
		harness:case("freezes the owner and the decision at the threshold", function()
			local engine = engineLib.new()
			local V2 = engine.types.Vector2
			local first: GuiObject = engine.new("Frame")
			local neighbour: GuiObject = engine.new("Frame")
			local pointer = ({} :: unknown) :: InputObject
			local arbiter = arbitration.new()
			Verify.expect(arbiter.begin(pointer, first, V2.zero, { pickup = "immediate" })):toBe(true)
			Verify.expect(arbiter.begin(pointer, neighbour, V2.new(5, 0), { pickup = "immediate" })):toBe(false)
			Verify.expect(arbiter.move(pointer, V2.new(5.99, 0))):toBe("pending")
			Verify.expect(arbiter.move(pointer, V2.new(6, 0))):toBe("drag")
			for frame = 1, 120 do
				Verify.expect(arbiter.move(pointer, V2.new(frame, -frame))):toBe("drag")
				Verify.expect(assert(arbiter.get(pointer)).owner):toBe(first)
				Verify.expect(arbiter.claim(pointer, first, "pan")):toBe(false)
			end
			local copy = assert(arbiter.get(pointer))
			copy.kind = "pan"
			Verify.expect(assert(arbiter.get(pointer)).kind):toBe("drag")
			Verify.expect(arbiter.finish(pointer, neighbour)):toBeNil()
			Verify.expect(arbiter.finish(pointer, first)):toBe("drag")
			Verify.expect(arbiter.get(pointer)):toBeNil()
		end)
		harness:case("early movement prevents long press and cannot become drag later", function()
			local engine = engineLib.new()
			local owner: GuiObject = engine.new("Frame")
			local pointer = ({} :: unknown) :: InputObject
			for _, scroll in { true, false } do
				local arbiter = arbitration.new()
				arbiter.begin(pointer, owner, engine.types.Vector2.zero, { pickup = "longPress", scroll = scroll })
				Verify.expect(arbiter.move(pointer, engine.types.Vector2.new(6, 0)))
					:toBe(if scroll then "scroll" else "pan")
				Verify.expect(arbiter.claim(pointer, owner, "drag")):toBe(false)
				Verify.expect(arbiter.move(pointer, engine.types.Vector2.zero)):toBe(if scroll then "scroll" else "pan")
			end
		end)
		harness:case("axis ties choose drag and cross-axis movement remains scroll", function()
			local engine = engineLib.new()
			local owner: GuiObject = engine.new("Frame")
			local pointer = ({} :: unknown) :: InputObject
			local axes: { "X" | "Y" } = { "X", "Y" }
			for _, axis in axes do
				local arbiter = arbitration.new()
				arbiter.begin(
					pointer,
					owner,
					engine.types.Vector2.zero,
					{ pickup = "immediate", axis = axis :: "X" | "Y", scroll = true }
				)
				Verify.expect(arbiter.move(pointer, engine.types.Vector2.new(6, 6))):toBe("drag")
				arbiter.finish(pointer, owner)
				arbiter.begin(
					pointer,
					owner,
					engine.types.Vector2.zero,
					{ pickup = "immediate", axis = axis :: "X" | "Y", scroll = true }
				)
				Verify.expect(
					arbiter.move(
						pointer,
						engine.types.Vector2.new(if axis == "X" then 1 else 8, if axis == "X" then 8 else 1)
					)
				):toBe("scroll")
				Verify.expect(arbiter.claim(pointer, owner, "drag")):toBe(false)
			end
		end)
		harness:case("one camera request at capture completes while later requests stay locked", function()
			local engine = engineLib.new()
			local surface: GuiObject = engine.new("Frame")
			local source: GuiObject = engine.new("Frame")
			source.Parent = surface
			local other: GuiObject = engine.new("Frame")
			local pointer = ({} :: unknown) :: InputObject
			local arbiter = arbitration.new()
			arbiter.begin(pointer, source, engine.types.Vector2.zero, { pickup = "immediate" })
			Verify.expect(arbiter.claimCamera(surface)):toBe(false)
			arbiter.move(pointer, engine.types.Vector2.new(6, 0))
			local allowed = false
			arbiter.capture(source, function()
				Verify.expect(arbiter.claimCamera(other)):toBe(false)
				allowed = arbiter.claimCamera(surface)
				Verify.expect(arbiter.claimCamera(surface)):toBe(false)
			end)
			for frame = 1, 120 do
				Verify.expect(allowed):toBe(true)
				Verify.expect(arbiter.claimCamera(surface)):toBe(false)
				Verify.expect(arbiter.claim(pointer, source, "pan")):toBe(false)
			end
			arbiter.finish(pointer, source)
			arbiter.capture(source, function()
				Verify.expect(arbiter.claimCamera(surface)):toBe(true)
			end)
			local ok = pcall(function()
				arbiter.capture(source, function()
					error("capture failure")
				end)
			end)
			Verify.expect(ok):toBe(false)
			Verify.expect(arbiter.claimCamera(surface)):toBe(false)
		end)
		harness:case("press, native long press, separate pointers and owner cancellation", function()
			local engine = engineLib.new()
			local owner: GuiObject = engine.new("Frame")
			local first = ({} :: unknown) :: InputObject
			local second = ({} :: unknown) :: InputObject
			local arbiter = arbitration.new()
			arbiter.begin(first, owner, engine.types.Vector2.zero, { pickup = "longPress" })
			arbiter.begin(second, owner, engine.types.Vector2.zero, {})
			Verify.expect(arbiter.claim(first, owner, "drag")):toBe(true)
			Verify.expect(arbiter.finish(second, owner)):toBe("press")
			Verify.expect(arbiter.finish(first, owner, true)):toBe("cancelled")
			arbiter.begin(first, owner, engine.types.Vector2.zero, {})
			Verify.expect(arbiter.claim(first, owner, "drag")):toBe(false)
			arbiter.cancelOwner(owner)
			Verify.expect(arbiter.get(first)):toBeNil()
		end)
	end)
end
