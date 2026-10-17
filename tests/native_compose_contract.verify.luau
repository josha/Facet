--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	type Owner = typeof(require("@repo/tools/typecheck/aliases").Owner)
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Facet = require("../src")
	local Roblox = require("../src/vendor/compose/roblox")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

	verifyHarness:case("holds the native size that passed readiness when an observation is deferred", {
		id = "native_compose_contract::holds the native size that passed readiness when an observation is deferred",
		run = function()
			local context = require("../src/ui/context")
			local presence = require("../src/ui/nav_overlay_presence")
			local engine = require("./lib/native_engine").new()
			local runtime: ComposeRuntime = Roblox.createRuntime((engine :: unknown) :: Roblox.Engine)
			local cached = Compose.cell(engine.types.Vector2.new(280, 120))
			local ready = Compose.cell(false)
			local progress = 0
			local held: Readable<Vector2>? = nil
			local stop, mounted = runtime.mount(function()
				local ctx = context(Compose, runtime, { types = engine.types })
				local panel = ctx.Host.Frame {}
				ctx.observe.AbsoluteSize = function()
					return cached
				end
				local sizes = presence(ctx).atRest(function(): number
					return progress
				end, ready, { panel })
				held = sizes[1]
				return panel
			end, engine.new("ScreenGui"))
			local geometry = (mounted :: unknown) :: { AbsoluteSize: Vector2 }
			geometry.AbsoluteSize = engine.types.Vector2.new(280, 140)
			for _ = 1, 3 do
				engine.heartbeat:Fire(1 / 60)
			end
			Verify.expect(ready:peek()):toBe(true)
			Verify.expect(cached:peek()):toBe(engine.types.Vector2.new(280, 120))
			Verify.expect(assert(held):peek()):toBe(engine.types.Vector2.new(280, 140))
			progress = 1
			cached:set(engine.types.Vector2.new(270, 130))
			Verify.expect(assert(held):peek()):toBe(engine.types.Vector2.new(280, 140))
			geometry.AbsoluteSize = engine.types.Vector2.new(280, 160)
			Verify.expect(assert(held):peek()):toBe(engine.types.Vector2.new(280, 160))
			cached:set(engine.types.Vector2.new(280, 160))
			Verify.expect(assert(held):peek()):toBe(engine.types.Vector2.new(280, 160))
			stop()
			runtime:dispose()
		end,
	})

	verifyHarness:case("reserves native styled padding before materializing content", {
		id = "native_compose_contract::reserves native styled padding before materializing content",
		run = function()
			local context = require("../src/ui/context")
			local materialize = require("../src/ui/materialize")
			local engine = engineLib.new()
			local runtime: ComposeRuntime = Roblox.createRuntime((engine :: unknown) :: Roblox.Engine)
			local scale = Compose.cell(1)
			local stop, mounted = runtime.mount(function()
				local ctx = context(Compose, runtime, { types = engine.types })
				local panel = ctx.Host.Frame { ctx.Host.Frame "Copy" {} }
				materialize(ctx, panel, {
					Size = engine.types.UDim2.fromOffset(280, 120),
					AutomaticSize = engine.types.Enum.AutomaticSize.None,
				}, function(use)
					return use(scale)
				end, nil, false, Compose.cell(engine.types.Vector2.new(280, 120)))
				return panel
			end, engine.new("ScreenGui"))
			local panel = (mounted :: unknown) :: Frame
			local padding = assert(panel:FindFirstChildWhichIsA("UIPadding")) :: UIPadding
			padding.PaddingLeft, padding.PaddingRight = engine.types.UDim.new(0, 16), engine.types.UDim.new(0, 16)
			padding.PaddingTop, padding.PaddingBottom = engine.types.UDim.new(0, 8), engine.types.UDim.new(0, 8)
			scale:set(0.9)
			local content = assert(panel:FindFirstChild("PresentationContent")) :: Frame
			Verify.expect(content.Size):toBe(engine.types.UDim2.fromOffset(248, 104))
			Verify.expect(content:FindFirstChild("Copy") ~= nil):toBe(true)
			scale:set(1)
			Verify.expect(panel:FindFirstChildWhichIsA("UIPadding")):toBe(padding)
			Verify.expect(panel:FindFirstChild("Copy") ~= nil):toBe(true)
			stop()
			runtime:dispose()
		end,
	})

	verifyHarness:case("restores a fade group's geometry after temporary materialization", {
		id = "native_compose_contract::restores a fade group's geometry after temporary materialization",
		run = function()
			local context = require("../src/ui/context")
			local materialize = require("../src/ui/materialize")
			local engine = engineLib.new()
			local runtime: ComposeRuntime = Roblox.createRuntime((engine :: unknown) :: Roblox.Engine)
			local scale = Compose.cell(1)
			local group: CanvasGroup? = nil
			local stop = runtime.mount(function()
				local ctx = context(Compose, runtime, { types = engine.types })
				local fade = ctx.Host.CanvasGroup "Fade" {
					Size = engine.types.UDim2.fromScale(1, 1),
					AutomaticSize = engine.types.Enum.AutomaticSize.Y,
					ctx.Host.Frame "Copy" {},
				}
				group = fade
				local panel = ctx.Host.Frame {}
				fade.Parent = panel
				materialize(ctx, panel, {
					Size = engine.types.UDim2.fromOffset(280, 120),
					AutomaticSize = engine.types.Enum.AutomaticSize.None,
				}, function(use)
					return use(scale)
				end, function()
					return engine.types.Vector2.new(0.25, 0.5)
				end, false, Compose.cell(engine.types.Vector2.new(280, 120)))
				return panel
			end, engine.new("ScreenGui"))
			local fade = assert(group)
			local size, automatic, anchor, position = fade.Size, fade.AutomaticSize, fade.AnchorPoint, fade.Position
			scale:set(0.9)
			Verify.expect(fade.AnchorPoint):toBe(engine.types.Vector2.new(0.25, 0.5))
			scale:set(1)
			Verify.expect(fade.Size):toBe(size)
			Verify.expect(fade.AutomaticSize):toBe(automatic)
			Verify.expect(fade.AnchorPoint):toBe(anchor)
			Verify.expect(fade.Position):toBe(position)
			Verify.expect(fade:FindFirstChild("Copy") ~= nil):toBe(true)
			Verify.expect(fade:FindFirstChild("PresentationContent")):toBeNil()
			stop()
			runtime:dispose()
		end,
	})

	verifyHarness:suite("native Compose integration contract", function()
		verifyHarness:case("starts ready motion with the next frame delta", {
			id = "native_compose_contract::native Compose integration contract::starts ready motion with the next frame delta",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime((engine :: unknown) :: Roblox.Engine)
				local amount: Readable<number> = Compose.cell(0)
				local stop = runtime.mount(function()
					runtime.timeline { duration = 1 }
					local ready = runtime.settled {
						sample = function(): number
							return 1
						end,
					}
					amount = runtime.tween(function(use): number
						return if use(ready) then 1 else 0
					end, {
						seconds = 0.1,
						ease = function(t: number): number
							return t
						end,
					})
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({})
				end, engine.new("ScreenGui"))
				engine.heartbeat:Fire(0.1)
				Verify.expect(amount:peek()):toBe(0)
				engine.heartbeat:Fire(0.1)
				Verify.expect(amount:peek()):toBe(0)
				engine.heartbeat:Fire(0.05)
				Verify.expect(amount:peek()):toBeCloseTo(0.5, 6)
				engine.heartbeat:Fire(0.05)
				Verify.expect(amount:peek()):toBe(1)
				stop()
				runtime:dispose()
			end,
		})
		verifyHarness:case("disposes child watches with their parent and tolerates repeated disposal", {
			id = "native_compose_contract::native Compose integration contract::disposes child watches with their parent and tolerates repeated disposal",
			run = function()
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime((engine :: unknown) :: Roblox.Engine)
				local source, calls, cleanups = Compose.cell(0), 0, 0
				local child: Owner? = nil
				local unwatch: (() -> ())? = nil
				local stop = runtime.mount(function()
					local owner = assert(Compose.currentOwner()).createChild()
					child = owner
					unwatch = owner.watch(function(use: Use)
						use(source)
						calls += 1
					end)
					Compose.withOwner(owner, function()
						Compose.cleanup(function()
							cleanups += 1
						end)
					end)
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({})
				end, engine.new("ScreenGui"))
				source:set(1)
				assert(calls == 2)
				local owned, stopWatch = assert(child), assert(unwatch)
				stop()
				stop()
				stopWatch()
				stopWatch()
				owned.dispose()
				assert(owned.isDisposed() and cleanups == 1, "cleanup was skipped or repeated")
				source:set(2)
				assert(calls == 2, "child watch survived parent")
				runtime:dispose()
			end,
		})
	end)
end
