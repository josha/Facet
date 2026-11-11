--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Facet = require("../src")
local Types = require("../src/ui/types")
local geometrySignature = require("../src/ui/geometry_signature")
local textChanges = require("../src/ui/text_changes")
local engineLib = require("./lib/native_engine")

return function(harness: Verify.Harness)
	harness:case("a geometry signature keeps its version while the sampled values repeat", function()
		local engine = engineLib.new()
		local Vector2 = engine.types.Vector2
		local signature = geometrySignature()
		local function sample(x: number, shown: boolean, text: string?): number
			signature.push(Vector2.new(x, 10))
			signature.push(Vector2.new(40, 20))
			signature.push(shown)
			if text then
				signature.push(text)
			end
			return signature.finish()
		end
		local first = sample(4, true, "Play")
		Verify.expect(sample(4, true, "Play")):toBe(first)
		Verify.expect(sample(4, true, "Play")):toBe(first)
		local moved = sample(5, true, "Play")
		Verify.expect(moved ~= first):toBe(true)
		Verify.expect(sample(5, true, "Play")):toBe(moved)
		local hidden = sample(5, false, "Play")
		Verify.expect(hidden ~= moved):toBe(true)
		local renamed = sample(5, false, "Stop")
		Verify.expect(renamed ~= hidden):toBe(true)
		local shorter = sample(5, false, nil)
		Verify.expect(shorter ~= renamed):toBe(true)
		Verify.expect(sample(5, false, nil)):toBe(shorter)
		local longer = sample(5, false, "Stop")
		Verify.expect(longer ~= shorter):toBe(true)
	end)

	harness:case("a label change reaches each listener that was registered when it fired", function()
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local Compose = Facet.Compose
		local ctx = ({ Compose = Compose } :: unknown) :: Types.Context
		local label = engine.new("TextLabel")
		local seen: { string } = {}
		local stopSecond: (() -> ())? = nil
		local late = 0
		local owner = Compose.createOwner(runtime.reactor)
		Compose.withOwner(owner, function()
			textChanges(ctx, label, function(property: string)
				if property == "Text" then
					table.insert(seen, "first:" .. label.Text)
					if label.Text == "two" and stopSecond then
						stopSecond()
						stopSecond = nil
						Compose.withOwner(owner, function()
							textChanges(ctx, label, function(changed: string)
								if changed == "Text" then
									late += 1
								end
							end)
						end)
					end
				end
			end)
			stopSecond = textChanges(ctx, label, function(property: string)
				if property == "Text" then
					table.insert(seen, "second:" .. label.Text)
				end
			end)
		end)
		label.Text = "one"
		Verify.expect(seen):toEqual({ "first:one", "second:one" })
		label.Text = "two"
		Verify.expect(seen):toEqual({ "first:one", "second:one", "first:two" })
		Verify.expect(late):toBe(0)
		label.Text = "three"
		Verify.expect(seen):toEqual({ "first:one", "second:one", "first:two", "first:three" })
		Verify.expect(late):toBe(1)
		local connections = engine.environment.liveConnections()
		Compose.owner.dispose(owner)
		Verify.expect(engine.environment.liveConnections()):toBe(connections - 1)
		label.Text = "four"
		Verify.expect(#seen):toBe(4)
		Verify.expect(late):toBe(1)
		runtime:dispose()
	end)

	harness:case("a label that only moves reaches no text listener", function()
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local Compose = Facet.Compose
		local ctx = ({ Compose = Compose } :: unknown) :: Types.Context
		local Vector2 = engine.types.Vector2
		local label = engine.new("TextLabel")
		local seen: { string } = {}
		local owner = Compose.createOwner(runtime.reactor)
		Compose.withOwner(owner, function()
			textChanges(ctx, label, function(property: string)
				table.insert(seen, property)
			end)
		end)
		engine.environment.poke(label, "AbsolutePosition", Vector2.new(0, 40))
		engine.environment.poke(label, "AbsolutePosition", Vector2.new(0, 80))
		Verify.expect(seen):toEqual({})
		engine.environment.poke(label, "AbsoluteSize", Vector2.new(120, 20))
		Verify.expect(seen):toEqual({ "AbsoluteSize" })
		Compose.owner.dispose(owner)
		runtime:dispose()
	end)
end
