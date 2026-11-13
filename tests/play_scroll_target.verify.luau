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
		engine.environment.poke(FixtureRoblox.assertInstance(outerGeometry), "AbsolutePosition", V2.new(16, 100))
		engine.environment.poke(FixtureRoblox.assertInstance(outerGeometry), "AbsoluteWindowSize", V2.new(350, 550))
		engine.environment.poke(FixtureRoblox.assertInstance(outerGeometry), "AbsoluteCanvasSize", V2.new(350, 100000))
		engine.environment.poke(FixtureRoblox.assertInstance(innerGeometry), "AbsolutePosition", V2.new(32, 160))
		engine.environment.poke(FixtureRoblox.assertInstance(innerGeometry), "AbsoluteWindowSize", V2.new(314, 99920))
		engine.environment.poke(FixtureRoblox.assertInstance(innerGeometry), "AbsoluteCanvasSize", V2.new(314, 99920))
		engine.environment.poke(FixtureRoblox.assertInstance(cellGeometry), "AbsolutePosition", V2.new(56, 2000))
		engine.environment.poke(FixtureRoblox.assertInstance(cellGeometry), "AbsoluteSize", V2.new(266, 44))
		local target, dx, dy = scrollTarget(cell, true)
		t:expect(target):toBe(outer)
		t:expect(dx):toBe(0)
		t:expect(dy):toBe(1402)
		target, dx, dy = scrollTarget(cell, false)
		t:expect(target == inner):toBe(true)
		t:expect(dx):toBe(0)
		t:expect(dy):toBe(0)
		engine.environment.poke(FixtureRoblox.assertInstance(innerGeometry), "AbsoluteWindowSize", V2.new(314, 400))
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

	harness:case("a cell taller than its scroll viewport is brought to an edge and then left", function(t)
		local engine = engineLib.new()
		local V2 = engine.types.Vector2
		local root = engine.new("ScreenGui") :: ScreenGui
		t:defer(function()
			root:Destroy()
		end)
		local list = engine.new("ScrollingFrame") :: ScrollingFrame
		list.Parent = root
		local card = engine.new("TextButton") :: TextButton
		card.Parent = list
		local function place(node: Instance, property: string, value: unknown)
			engine.environment.poke(FixtureRoblox.assertInstance(node), property, value)
		end
		place(list, "AbsolutePosition", V2.new(16, 148))
		place(list, "AbsoluteWindowSize", V2.new(713, 167))
		place(list, "AbsoluteCanvasSize", V2.new(713, 902))
		place(card, "AbsoluteSize", V2.new(348, 290))
		place(card, "AbsolutePosition", V2.new(16, 240))
		local target, dx, dy = scrollTarget(card, true)
		t:expect(target):toBe(list)
		t:expect(dx):toBe(0)
		t:expect(dy):toBe(92)
		place(card, "AbsolutePosition", V2.new(16, 148))
		target, dx, dy = scrollTarget(card, false)
		t:expect(target):toBe(list)
		t:expect(dy):toBe(0)
		place(card, "AbsolutePosition", V2.new(16, 74))
		target, dx, dy = scrollTarget(card, false)
		t:expect(dy):toBe(0)
		place(card, "AbsolutePosition", V2.new(16, -60))
		target, dx, dy = scrollTarget(card, false)
		t:expect(dy):toBe(-85)
	end)
end
