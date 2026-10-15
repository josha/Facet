--!strict
local Verify = require("../tools/vendor/verify/src/core")
local stability = require("../tools/studio/live/frame_stability")
local clipping = require("../tools/studio/live/text_clipping")
local engineLib = require("./lib/native_engine")
local Lute = require("../tools/vendor/verify/src/lute")

local function inspector(engine: engineLib.Engine): typeof(clipping)
	return (
		Lute.loader
			.new({ globals = { Vector2 = engine.types.Vector2, Enum = engine.types.Enum } })
			.require("tools/studio/live/text_clipping") :: unknown
	) :: typeof(clipping)
end

return function(harness: Verify.Harness)
	harness:case("deliberate ellipsis permits text overflow but retains ancestor clipping checks", function(t)
		local engine = engineLib.new()
		local clipping = inspector(engine)
		local root = engine.new("Frame")
		root.AbsoluteSize = engine.types.Vector2.new(100, 100)
		root.ClipsDescendants = true
		local label = engine.new("TextLabel")
		label.Parent = root
		label.Text = "Deliberately truncated caption"
		label.AbsoluteSize = engine.types.Vector2.new(80, 20)
		label.TextBounds = engine.types.Vector2.new(200, 20)
		label.TextFits = false
		label.TextTruncate = engine.types.Enum.TextTruncate.AtEnd
		t:expect(#clipping.inspect(root)):toBe(0)
		label.TextTruncate = engine.types.Enum.TextTruncate.None
		t:expect(clipping.inspect(root)[1].reason):toBe("TextFits is false")
		label.TextTruncate = engine.types.Enum.TextTruncate.AtEnd
		label.AbsolutePosition = engine.types.Vector2.new(40, 0)
		local faults = clipping.inspect(root)
		t:expect(#faults):toBe(1)
		t:expect(faults[1].ancestor):toBe(root:GetFullName())
		root:Destroy()
	end)
	harness:case("scroll viewport clipping permits partial rows but retains text and other ancestor faults", function(t)
		local engine = engineLib.new()
		local clipping = inspector(engine)
		local root = engine.new("Frame")
		root.AbsoluteSize = engine.types.Vector2.new(200, 200)
		root.ClipsDescendants = true
		local scroll = engine.new("ScrollingFrame")
		scroll.Parent = root
		scroll.AbsoluteSize = engine.types.Vector2.new(100, 100)
		scroll.ClipsDescendants = true
		local group = engine.new("CanvasGroup")
		group.Parent = scroll
		group.AbsoluteSize = engine.types.Vector2.new(200, 200)
		local label = engine.new("TextLabel")
		label.Parent = group
		label.Text = "Partly visible row"
		label.TextFits = true
		label.AbsolutePosition = engine.types.Vector2.new(0, 90)
		label.AbsoluteSize = engine.types.Vector2.new(80, 20)
		t:expect(#clipping.inspect(root)):toBe(0)
		label.TextFits = false
		t:expect(clipping.inspect(root)[1].reason):toBe("TextFits is false")
		label.TextFits = true
		root.AbsoluteSize = engine.types.Vector2.new(100, 100)
		t:expect(#clipping.inspect(root)):toBe(0)
		group.AbsoluteSize = engine.types.Vector2.new(100, 100)
		t:expect(clipping.inspect(root)[1].ancestor):toBe(group:GetFullName())
		root.AbsoluteSize = engine.types.Vector2.new(100, 95)
		local faults = clipping.inspect(root)
		t:expect(#faults):toBe(2)
		t:expect(faults[1].ancestor):toBe(group:GetFullName())
		t:expect(faults[2].ancestor):toBe(root:GetFullName())
		root:Destroy()
	end)
	harness:case("explicit state changes start a new baseline and retain earlier faults", function(t)
		local tracker = stability.new()
		stability.push(tracker, { { path = "Value", rect = { 0, 0, 100, 20 } } })
		stability.push(tracker, { { path = "Value", rect = { 0, 0, 101, 20 } } })
		stability.stateChange(tracker)
		stability.push(tracker, { { path = "Value", rect = { 0, 0, 120, 20 } } })
		t:expect(#tracker.faults):toBe(1)
		stability.push(tracker, { { path = "Value", rect = { 0, 0, 121, 20 } } })
		t:expect(#tracker.faults):toBe(2)
		t:expect(tracker.faults[2].firstFrame):toBe(3)
	end)
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
