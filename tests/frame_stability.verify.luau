--!strict
local Verify = require("../tools/vendor/verify/src/core")
local stability = require("../tools/studio/live/frame_stability")

return function(harness: Verify.Harness)
	harness:case("frame stability catches a one-frame-late resize", function(t)
		local tracker = stability.new()
		stability.push(tracker, { { path = "Stage/Late", rect = { 0, 0, 100, 20 } } })
		stability.push(tracker, { { path = "Stage/Late", rect = { 0, 0, 101, 20 } } })
		t:expect(#tracker.faults):toBe(1)
		t:expect(tracker.faults[1].frame):toBe(2)
		t:expect(tracker.faults[1].delta[3]):toBe(1)
		for _ = 1, 30 do
			stability.push(tracker, { { path = "Stage/Late", rect = { 0, 0, 101, 20 } } })
		end
		t:expect(tracker.quiet):toBe(30)
		t:expect(#tracker.faults):toBe(1)
	end)
	harness:case("frame stability compares cumulative drift with first visibility and catches text changes", function(t)
		local tracker = stability.new()
		for _, x in { 0, 0.3, 0.6 } do
			stability.push(tracker, { { path = "Text", rect = { x, 0, 100, 20 }, text = { 40, 16 } } })
		end
		t:expect(#tracker.faults):toBe(1)
		stability.push(tracker, { { path = "Text", rect = { 0.6, 0, 100, 20 }, text = { 41, 16 } } })
		t:expect(#tracker.faults):toBe(2)
		t:expect(tracker.faults[2].textDelta):toEqual({ 1, 0 })
	end)
	harness:case("new state epochs permit input and include late appearing elements", function(t)
		local tracker = stability.new()
		stability.push(tracker, {})
		stability.push(tracker, { { path = "Panel", rect = { 8, 8, 200, 100 } } })
		stability.push(tracker, { { path = "Panel", rect = { 8.5, 8, 200, 100 } } })
		t:expect(#tracker.faults):toBe(0)
		t:expect(tracker.first.Panel.frame):toBe(2)
		t:expect(tracker.quiet):toBe(0)
	end)
end
