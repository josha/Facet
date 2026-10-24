--!strict
local FixtureRoblox = require("../tools/vendor/verify/src/roblox")

local Verify = require("../tools/vendor/verify/src/core")
local engineLib = require("./lib/native_engine")
local scrollTarget = require("../tools/play/engine/scroll_target")

return function(harness: Verify.Harness)
	harness:case("reveals a cell through the outer scroll viewport", function(t)
		local engine = engineLib.new()
		local V2 = engine.types.Vector2
		local root = engine.new("ScreenGui") :: ScreenGui
		t:defer(function()
			root:Destroy()
		end)
		local outer = engine.new("ScrollingFrame") :: ScrollingFrame
		outer.Parent = root
		local inner = engine.new("ScrollingFrame") :: ScrollingFrame
		inner.Parent = outer
		local cell = engine.new("TextButton") :: TextButton
		cell.Parent = inner
		type Geometry = {
			AbsolutePosition: Vector2,
			AbsoluteSize: Vector2,
			AbsoluteWindowSize: Vector2,
			AbsoluteCanvasSize: Vector2,
		}
		local outerGeometry = (outer :: unknown) :: Geometry
		local innerGeometry = (inner :: unknown) :: Geometry
		local cellGeometry = (cell :: unknown) :: Geometry
		engine.environment.poke(
			(outerGeometry :: unknown) :: FixtureRoblox.Instance,
			"AbsolutePosition",
			V2.new(16, 100)
		)
		engine.environment.poke(
			(outerGeometry :: unknown) :: FixtureRoblox.Instance,
			"AbsoluteWindowSize",
			V2.new(350, 550)
		)
		engine.environment.poke(
			(outerGeometry :: unknown) :: FixtureRoblox.Instance,
			"AbsoluteCanvasSize",
			V2.new(350, 100000)
		)
		engine.environment.poke(
			(innerGeometry :: unknown) :: FixtureRoblox.Instance,
			"AbsolutePosition",
			V2.new(32, 160)
		)
		engine.environment.poke(
			(innerGeometry :: unknown) :: FixtureRoblox.Instance,
			"AbsoluteWindowSize",
			V2.new(314, 99920)
		)
		engine.environment.poke(
			(innerGeometry :: unknown) :: FixtureRoblox.Instance,
			"AbsoluteCanvasSize",
			V2.new(314, 99920)
		)
		engine.environment.poke(
			(cellGeometry :: unknown) :: FixtureRoblox.Instance,
			"AbsolutePosition",
			V2.new(56, 2000)
		)
		engine.environment.poke((cellGeometry :: unknown) :: FixtureRoblox.Instance, "AbsoluteSize", V2.new(266, 44))
		local target, dx, dy = scrollTarget(cell, true)
		t:expect(target):toBe(outer)
		t:expect(dx):toBe(0)
		t:expect(dy):toBe(1402)
		target, dx, dy = scrollTarget(cell, false)
		t:expect(target == inner):toBe(true)
		t:expect(dx):toBe(0)
		t:expect(dy):toBe(0)
		engine.environment.poke(
			(innerGeometry :: unknown) :: FixtureRoblox.Instance,
			"AbsoluteWindowSize",
			V2.new(314, 400)
		)
		target, dx, dy = scrollTarget(cell, true)
		t:expect(target):toBe(inner)
		t:expect(dx):toBe(0)
		t:expect(dy):toBe(1492)
		inner.ScrollingEnabled = false
		target = scrollTarget(cell, true)
		t:expect(target):toBe(outer)
		outer.ScrollingEnabled = false
		target = scrollTarget(cell, true)
		t:expect(target):toBe(nil)
	end)
end
