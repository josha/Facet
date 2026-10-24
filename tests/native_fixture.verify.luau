--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Native = require("./lib/native_engine")

return function(harness: Verify.Harness)
	harness:case("the unit fixture preserves reflected properties and access restrictions", {
		id = "native_fixture::reflection",
		run = function(test)
			local engine, fixture = Native.new()
			test:defer(function()
				fixture.close()
			end)
			local label = engine.new("TextLabel")
			Verify.expect(label.TextFits):toBe(false)
			Verify.expect(function()
				label.AbsoluteSize = engine.types.Vector2.new(120, 44)
			end):toThrow("read-only")
			engine.environment.poke(label, "AbsoluteSize", engine.types.Vector2.new(120, 44))
			Verify.expect(label.AbsoluteSize):toBe(engine.types.Vector2.new(120, 44))
			Verify.expect(function()
				label.Text = 42
			end):toThrow("requires String")
			Verify.expect(function()
				label.Font = engine.types.Enum.KeyCode.A
			end):toThrow("requires Enum.Font")
			local folder = engine.new("Folder")
			Verify.expect(folder.AbsoluteSize):toBeNil()
			Verify.expect(function()
				engine.environment.poke(folder, "AbsoluteSize", engine.types.Vector2.zero)
			end):toThrow()
		end,
	})
	harness:case("unit roots have no measured geometry until the case supplies it", {
		id = "native_fixture::unmeasured roots",
		run = function(test)
			local engine, fixture = Native.new()
			test:defer(function()
				fixture.close()
			end)
			for _, className in { "ScreenGui", "SurfaceGui" } do
				local root = engine.new(className)
				Verify.expect(root.AbsoluteSize):toBe(engine.types.Vector2.zero)
				Verify.expect(root.AbsolutePosition):toBe(engine.types.Vector2.zero)
				engine.environment.poke(root, "AbsoluteSize", engine.types.Vector2.new(800, 600))
				Verify.expect(root.AbsoluteSize):toBe(engine.types.Vector2.new(800, 600))
			end
		end,
	})
	harness:case("fixture construction leaves reflected creation restrictions intact", {
		id = "native_fixture::engine-owned construction",
		run = function(test)
			local engine, fixture = Native.new()
			test:defer(function()
				fixture.close()
			end)
			Verify.expect(function()
				engine.environment.createInstance("UserInputService")
			end):toThrow()
			Verify.expect(engine.new("UserInputService").ClassName):toBe("UserInputService")
			Verify.expect(function()
				engine.environment.createInstance("InputObject")
			end):toThrow()
			Verify.expect(engine.new("InputObject").ClassName):toBe("InputObject")
		end,
	})
end
