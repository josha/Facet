--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Facet = require("../src")
local context = require("../src/ui/context")
local measure = require("../src/ui/text_measure")
local engineLib = require("./lib/native_engine")
local Shared = require("../src/ui/types")
local ComposeTypes = require("../src/vendor/compose/core")
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

return function(harness: Verify.Harness)
	harness:case("wrapped glyph floors preserve fractional native heights", function(t)
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local height = 47.2
		local service = {
			GetTextBoundsAsync = function(_self: unknown, params: GetTextBoundsParams): Vector2
				return engine.types.Vector2.new(80, if params.Width > 0 then height else 16)
			end,
		}
		local ctx = context(
			Facet.Compose,
			runtime,
			{
				types = engine.types,
				services = { TextService = (service :: unknown) :: TextService },
			} :: Shared.Config
		)
		local mounted: TextLabel? = nil
		local stop = runtime.mount(function()
			local node = ctx.text {
				Text = "Wrapped caption",
				TextSize = 16,
				TextWrapped = true,
				Size = engine.types.UDim2.fromOffset(120, 0),
				AutomaticSize = engine.types.Enum.AutomaticSize.Y,
			}
			mounted = node
			return node
		end, engine.new("ScreenGui"))
		local node = assert(mounted)
		node.AbsoluteSize = engine.types.Vector2.new(120, height)
		local floor = assert(node:FindFirstChild("TextBoundsFloor")) :: UISizeConstraint
		t:expect(floor.MinSize.Y):toBe(engine.types.Vector2.new(0, height).Y)
		height = 19.2
		node.Text = "Short"
		t:expect(floor.MinSize.Y):toBe(engine.types.Vector2.new(0, height).Y)
		stop()
		runtime:dispose()
		t:expect(engine.census().connections):toBe(0)
	end)
	harness:case("text readiness retains every outstanding measurement", function(t)
		local engine = engineLib.new()
		local label = engine.new("TextLabel")
		local first, second = measure.hold(label), measure.hold(label)
		t:expect(measure.ready(label)):toBe(false)
		first()
		first()
		t:expect(measure.ready(label)):toBe(false)
		second()
		t:expect(measure.ready(label)):toBe(true)
	end)
	harness:case("glyph constraints use font metrics while rendered bounds and the unit probe lag", function(t)
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local service = {
			GetTextBoundsAsync = function(_self: unknown, params: GetTextBoundsParams): Vector2
				return engine.types.Vector2.new(#params.Text * params.Size, params.Size)
			end,
		}
		local ctx = context(
			Facet.Compose,
			runtime,
			{
				types = engine.types,
				services = { TextService = (service :: unknown) :: TextService },
			} :: Shared.Config
		)
		local label: TextLabel? = nil
		local stop = runtime.mount(function()
			local node = ctx.text { Text = "Saved", TextSize = 16 }
			label = node
			return node
		end, engine.new("ScreenGui"))
		local node = assert(label)
		local floor = assert(node:FindFirstChild("TextBoundsFloor")) :: UISizeConstraint
		local unit = assert(node:FindFirstChild("TextBoundsUnit")) :: Frame
		t:expect(floor.MinSize):toEqual(engine.types.Vector2.new(80, 16))
		node.TextBounds = engine.types.Vector2.new(9000, 999)
		unit.AbsoluteSize = engine.types.Vector2.new(50, 0.5)
		t:expect(floor.MinSize):toEqual(engine.types.Vector2.new(80, 16))
		t:expect(floor.MaxSize):toEqual(engine.types.Vector2.new(80, 16))
		node.TextSize = 24
		t:expect(floor.MinSize):toEqual(engine.types.Vector2.new(120, 24))
		node.LineHeight = 1.5
		t:expect(floor.MaxSize.Y):toBe(math.huge)
		stop()
		runtime:dispose()
		t:expect(engine.census().connections):toBe(0)
	end)
	harness:case("wrapped text height is pending until its native measurement completes", function(t)
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local calls, blocked = 0, 0
		local label: TextLabel? = nil
		local service = {
			GetTextBoundsAsync = function(_self: unknown, params: GetTextBoundsParams): Vector2
				if params.Width == 0 then
					return engine.types.Vector2.new(#params.Text * params.Size, params.Size)
				end
				calls += 1
				if label and not measure.ready(label) then
					blocked += 1
				end
				t:expect(params.Width > 0):toBe(true)
				return engine.types.Vector2.new(90, 144)
			end,
		}
		local ctx = context(
			Facet.Compose,
			runtime,
			{
				types = engine.types,
				services = { TextService = (service :: unknown) :: TextService },
			} :: Shared.Config
		)
		local stop = runtime.mount(function()
			label = ctx.text {
				Text = "Wrapped body copy",
				TextWrapped = true,
				Size = engine.types.UDim2.new(1, 0, 0, 0),
				AutomaticSize = engine.types.Enum.AutomaticSize.Y,
			}
			return label
		end, engine.new("ScreenGui"))
		local node = assert(label)
		node.TextFits = false
		node.AbsoluteSize = engine.types.Vector2.new(100, 20)
		t:expect(calls > 0):toBe(true)
		t:expect(blocked):toBe(calls)
		t:expect(measure.ready(node)):toBe(false)
		node.AbsoluteSize = engine.types.Vector2.new(100, 144)
		node.TextFits = true
		t:expect(measure.ready(node)):toBe(true)
		stop()
		runtime:dispose()
	end)

	harness:case("natural text metrics use native font inputs and ignore rendered geometry", function(t)
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local calls, blocked = 0, 0
		local label: TextLabel? = nil
		local service = {
			GetTextBoundsAsync = function(_self: unknown, params: GetTextBoundsParams): Vector2
				calls += 1
				if label and not measure.ready(label) then
					blocked += 1
				end
				t:expect(params.Width):toBe(0)
				return engine.types.Vector2.new(#params.Text * params.Size, params.Size)
			end,
		}
		local ctx = context(
			Facet.Compose,
			runtime,
			{
				types = engine.types,
				services = { TextService = (service :: unknown) :: TextService },
			} :: Shared.Config
		)
		local result: ComposeTypes.Readable<Vector2>? = nil
		local stop = runtime.mount(function()
			local Host = (runtime.constructors :: unknown) :: RobloxHost
			local node = Host.TextLabel { Text = "Saved", TextSize = 16 }
			label = node
			result = measure.natural(ctx, node)
			t:expect(measure.natural(ctx, node)):toBe(result)
			return node
		end, engine.new("ScreenGui"))
		local node = assert(label)
		local metrics = assert(result)
		t:expect(metrics:peek().X):toBe(80)
		t:expect(blocked):toBe(calls)
		t:expect(measure.ready(node)):toBe(true)
		local before = calls
		node.TextBounds = engine.types.Vector2.new(9000, 999)
		node.AbsoluteSize = engine.types.Vector2.new(200, 50)
		t:expect(calls):toBe(before)
		t:expect(metrics:peek().X):toBe(80)
		node.Text = "Updated"
		t:expect(metrics:peek().X):toBe(112)
		stop()
		runtime:dispose()
		t:expect(measure.ready(node)):toBe(true)
	end)
end
