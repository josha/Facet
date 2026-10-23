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
	harness:case("stable badge floors include changing native padding without clipping", function(t)
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
		local inset: UIPadding? = nil
		local stop = runtime.mount(function()
			local Host = (runtime.constructors :: unknown) :: RobloxHost
			local node = Host.TextLabel {
				Text = "88888",
				TextSize = 16,
				Size = engine.types.UDim2.fromOffset(0, 0),
				AutomaticSize = engine.types.Enum.AutomaticSize.XY,
			}
			label = node
			ctx.textLayout(node, true, true)
			inset = Host.UIPadding {
				PaddingLeft = engine.types.UDim.new(0, 8),
				PaddingRight = engine.types.UDim.new(0, 8),
				PaddingTop = engine.types.UDim.new(0, 3),
				PaddingBottom = engine.types.UDim.new(0, 3),
			}
			assert(inset).Parent = node
			return node
		end, engine.new("ScreenGui"))
		local node = assert(label)
		local floor = assert(node:FindFirstChild("TextBoundsFloor")) :: UISizeConstraint
		t:expect(floor.MinSize):toEqual(engine.types.Vector2.new(96, 22))
		node.Text = "12345"
		t:expect(floor.MinSize):toEqual(engine.types.Vector2.new(96, 22))
		assert(inset).PaddingLeft = engine.types.UDim.new(0, 12)
		t:expect(floor.MinSize):toEqual(engine.types.Vector2.new(100, 22))
		assert(inset).Parent = nil
		t:expect(floor.MinSize):toEqual(engine.types.Vector2.new(80, 16))
		stop()
		runtime:dispose()
		t:expect(engine.census().connections):toBe(0)
	end)
	harness:case(
		"mounted readout floors hold their widest value until the length changes and reset with font metrics",
		function(t)
			local engine = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local service = {
				GetTextBoundsAsync = function(_self: unknown, params: GetTextBoundsParams): Vector2
					local _, narrow = string.gsub(params.Text, "1", "")
					return engine.types.Vector2.new((#params.Text - narrow / 2) * params.Size, params.Size)
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
			local function mount()
				return runtime.mount(function()
					label = ctx.text({ Text = "1000", TextSize = 16 }, true)
					return label
				end, engine.new("ScreenGui"))
			end
			local stop = mount()
			local node = assert(label)
			local floor = assert(node:FindFirstChild("TextBoundsFloor")) :: UISizeConstraint
			t:expect(floor.MinSize.X):toBe(56)
			for _, sample in { { text = "1111", width = 56 }, { text = "9999", width = 64 }, { text = "1011", width = 64 } } do
				node.Text = sample.text
				t:expect(floor.MinSize.X):toBe(sample.width)
				t:expect(floor.MaxSize.X):toBe(sample.width)
			end
			node.Text = "9"
			t:expect(floor.MinSize.X):toBe(16)
			node.Text = "10000"
			t:expect(floor.MinSize.X):toBe(72)
			node.Text = "11111"
			t:expect(floor.MinSize.X):toBe(72)
			node.Text = "1"
			t:expect(floor.MinSize.X):toBe(8)
			node.TextSize = 12
			t:expect(floor.MinSize.X):toBe(6)
			node.TextWrapped = true
			node.Text = "xx"
			t:expect(floor.MinSize.X):toBe(0)
			node.TextWrapped = false
			t:expect(floor.MinSize.X):toBe(24)
			stop()
			stop = mount()
			t:expect((assert(assert(label):FindFirstChild("TextBoundsFloor")) :: UISizeConstraint).MinSize.X):toBe(56)
			stop()
			runtime:dispose()
			t:expect(engine.census().connections):toBe(0)
		end
	)
	harness:case("native metric floors do not schedule a reflow for each live readout", function(t)
		local engine = engineLib.new({
			getStyled = function(node: { [string]: unknown }, property: string): unknown
				return if property == "TextSize" then 24 else node[property]
			end,
		})
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
				services = {
					TextService = (service :: unknown) :: TextService,
					RunService = ({ Heartbeat = engine.heartbeat } :: unknown) :: RunService,
				},
			} :: Shared.Config
		)
		local label: TextLabel? = nil
		local stop = runtime.mount(function()
			label = ctx.text { Text = "Coins 100", TextSize = 16 }
			return label
		end, engine.new("ScreenGui"))
		engine.heartbeat:Fire(1 / 60)
		local node = assert(label)
		local writes = 0
		local connection = engine.onWrite(function(target: Instance, property: string, _value: unknown)
			if target == node and property == "AutomaticSize" then
				writes += 1
			end
		end)
		node.Text = "Coins 101"
		node.AbsoluteSize = engine.types.Vector2.new(216, 24)
		node.TextBounds = engine.types.Vector2.new(9000, 999)
		engine.heartbeat:Fire(1 / 60)
		t:expect(writes):toBe(0)
		t:expect((assert(node:FindFirstChild("TextBoundsFloor")) :: UISizeConstraint).MinSize.X):toBe(216)
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local stopOverride = runtime.mount(function()
			return Host.UISizeConstraint { Name = "Authored" }
		end, node)
		writes = 0
		node.Text = "Coins 102"
		engine.heartbeat:Fire(1 / 60)
		t:expect(writes):toBe(2)
		stopOverride()
		connection:Disconnect()
		stop()
		runtime:dispose()
		t:expect(engine.census().connections):toBe(0)
	end)
	harness:case("text updates retain the measured floor until replacement metrics arrive", function(t)
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local service = {
			GetTextBoundsAsync = function(_self: unknown, params: GetTextBoundsParams): Vector2
				return engine.types.Vector2.new(80, if params.Width > 0 then 32 else 16)
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
		local labels: { TextLabel } = {}
		local stop = runtime.mount(function()
			local Host = (runtime.constructors :: unknown) :: RobloxHost
			for _, wrapped in { false, true } do
				local label = ctx.text {
					Text = "Coins 100",
					TextWrapped = wrapped,
					TextSize = 16,
					Size = engine.types.UDim2.fromOffset(if wrapped then 120 else 0, 0),
					AutomaticSize = if wrapped
						then engine.types.Enum.AutomaticSize.Y
						else engine.types.Enum.AutomaticSize.XY,
				}
				label.AbsoluteSize = engine.types.Vector2.new(120, 32)
				table.insert(labels, label)
			end
			return Host.Frame { table.unpack(labels) }
		end, engine.new("ScreenGui"))
		local writes = 0
		local connection = engine.onWrite(function(node: Instance, property: string, _value: unknown)
			if node.Name == "TextBoundsFloor" and (property == "MinSize" or property == "MaxSize") then
				writes += 1
			end
		end)
		for _, label in labels do
			label.Text = "Coins 101"
		end
		t:expect(writes):toBe(0)
		connection:Disconnect()
		stop()
		runtime:dispose()
		t:expect(engine.census().connections):toBe(0)
	end)
	harness:case("wrapped glyph floors use native width and preserve fractional heights", function(t)
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
		local observeSize = ctx.observe.AbsoluteSize
		local stale = Facet.Compose.cell(engine.types.Vector2.zero)
		ctx.observe.AbsoluteSize = function(node: GuiBase2d)
			return if node.Name == "WrappedCaption" then stale else observeSize(node)
		end
		local mounted: TextLabel? = nil
		local stop = runtime.mount(function()
			local node = ctx.text {
				Name = "WrappedCaption",
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
		t:expect(stale:peek()):toBe(engine.types.Vector2.zero)
		stop()
		runtime:dispose()
		t:expect(engine.census().connections):toBe(0)
	end)
	harness:case("wrapped text and width share a frame before publishing a height floor", function(t)
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local words = Facet.Compose.cell("Small")
		local size = Facet.Compose.cell(engine.types.Vector2.new(80, 18))
		local observe = runtime.observe
		runtime.observe = function(node, property, options)
			if (node :: Instance).Name == "Wallet" then
				if property == "Text" then
					return words
				elseif property == "AbsoluteSize" then
					return size
				end
			end
			return observe(node, property, options)
		end
		local service = {
			GetTextBoundsAsync = function(_self: unknown, params: GetTextBoundsParams): Vector2
				local width = if params.Text == "Small" then 80 else 96
				return engine.types.Vector2.new(width, if params.Width > 0 and params.Width < width then 40 else 18)
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
			local node = ctx.text {
				Name = "Wallet",
				Text = "Small",
				TextWrapped = true,
				AutomaticSize = engine.types.Enum.AutomaticSize.XY,
			}
			label = node
			return node
		end, engine.new("ScreenGui"))
		local node = assert(label)
		local floor = assert(node:FindFirstChild("TextBoundsFloor")) :: UISizeConstraint
		local tall = 0
		engine.onWrite(function(target, property, value)
			if target == floor and property == "MinSize" and value.Y == 40 then
				tall += 1
			end
		end)
		node.Text = "Larger"
		t:expect(floor.MinSize.Y):toBe(18)
		runtime:batch(function()
			words:set("Larger")
			size:set(engine.types.Vector2.new(96, 18))
		end)
		t:expect(tall):toBe(0)
		t:expect(floor.MinSize.Y):toBe(18)
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
	harness:case("wrapped line spacing rounds its native height floor up", function(t)
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local service = {
			GetTextBoundsAsync = function(_self: unknown, params: GetTextBoundsParams): Vector2
				return engine.types.Vector2.new(219, if params.Width > 0 then 360 else 36)
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
			label = ctx.text {
				Text = "Wrapped body copy",
				TextSize = 36,
				LineHeight = 1.45,
				TextWrapped = true,
				Size = engine.types.UDim2.new(1, 0, 0, 0),
				AutomaticSize = engine.types.Enum.AutomaticSize.Y,
			}
			return label
		end, engine.new("ScreenGui"))
		local node = assert(label)
		node.AbsoluteSize = engine.types.Vector2.new(228, 20)
		local floor = assert(node:FindFirstChild("TextBoundsFloor")) :: UISizeConstraint
		t:expect(floor.MinSize.Y):toBe(506)
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

	harness:case("completed wrapped measurements tolerate a stale native fit flag", function(t)
		local engine = engineLib.new()
		local node = engine.new("TextLabel")
		node.Text = "Saved"
		node.TextWrapped = true
		node.AutomaticSize = engine.types.Enum.AutomaticSize.Y
		node.TextFits = false
		node.TextBounds = engine.types.Vector2.new(90, 14)
		node.AbsoluteSize = engine.types.Vector2.new(100, 14)
		t:expect(measure.ready(node)):toBe(false)
		local floor = engine.new("UISizeConstraint")
		floor.Name = "TextBoundsFloor"
		floor.MinSize = engine.types.Vector2.new(0, 14)
		floor.Parent = node
		t:expect(measure.ready(node)):toBe(true)
		local release = measure.hold(node)
		t:expect(measure.ready(node)):toBe(false)
		release()
		node.AbsoluteSize = engine.types.Vector2.new(100, 13)
		t:expect(measure.ready(node)):toBe(false)
		node.AbsoluteSize = engine.types.Vector2.new(80, 14)
		t:expect(measure.ready(node)):toBe(false)
		local unit = engine.new("Frame")
		unit.Name = "TextBoundsUnit"
		unit.AbsoluteSize = engine.types.Vector2.new(200, 2)
		unit.Parent = node
		node.TextBounds = engine.types.Vector2.new(180, 28)
		node.AbsoluteSize = engine.types.Vector2.new(200, 28)
		t:expect(measure.ready(node)):toBe(true)
		floor.MinSize = engine.types.Vector2.new(0, 28)
		t:expect(measure.ready(node)):toBe(false)
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
