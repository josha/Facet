--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local terminal = require("../examples/gallery/examples/outpost_terminal")
	local scenario = require("../examples/gallery/scenarios/outpost_terminal")

	local function mount(module: any, options: { [string]: any }?, configure: ((any, engineLib.Engine) -> ())?)
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local target = engine.new("ScreenGui")
		local ctx = {
			Facet = Facet,
			Compose = Facet.Compose,
			runtime = runtime,
			Host = (runtime.constructors :: unknown) :: RobloxHost,
			UI = Facet.controls(runtime, { types = engine.types }),
			types = engine.types,
			inputTarget = engine.new("PlayerGui"),
			worldTarget = engine.new("Folder"),
			load = function()
				return terminal
			end,
		}
		if configure then
			configure(ctx, engine)
		end
		local built
		local stop, node: any = runtime.mount(function()
			built = module.build(ctx, options)
			return built.screen()
		end, target)
		return built, node, function()
			stop()
			runtime:dispose()
		end, ctx, engine
	end

	verifyHarness:suite("native outpost terminal", function()
		verifyHarness:case("keeps draft separate until the matching server verdict and ignores stale replies", {
			id = "native_outpost_terminal::native outpost terminal::keeps draft separate until the matching server verdict and ignores stale replies",
			run = function()
				local envelopes: { { [string]: any } } = {}
				local built, root, stop = mount(terminal, {
					send = function(envelope)
						table.insert(envelopes, envelope)
					end,
				})
				Verify.expect(root.ClassName):toBe("ScrollingFrame")
				built.steps.engage(terminal.rules.START, 2)
				built.steps.setValue("door", 2)
				built.steps.setValue("beacon", 1)
				built.steps.setValue("workshop", 2)
				local sent = built.steps.apply()
				Verify.expect(sent.sent):toBe(true)
				Verify.expect(built.report().status):toBe("pending")
				Verify.expect(built.report().complete):toBe(false)
				Verify.expect(built.steps.apply().reason):toBe("pending")
				Verify.expect((built.steps.confirm(sent.requestId + 1, { revision = 3, allocation = sent.allocation })))
					:toBe(false)
				Verify.expect(built.report().complete):toBe(false)
				built.steps.confirm(sent.requestId, { revision = 3, allocation = sent.allocation })
				Verify.expect(built.report().complete):toBe(true)
				Verify.expect((built.steps.ingest(2, terminal.rules.START))):toBe(false)
				Verify.expect(built.report().complete):toBe(true)
				built.steps.reset()
				Verify.expect(built.report().complete):toBe(true)
				local reset = envelopes[#envelopes]
				built.steps.exit("out-of-range")
				Verify.expect(
					(built.steps.confirm(reset.requestId, { revision = 4, allocation = terminal.rules.START }))
				)
					:toBe(false)
				Verify.expect(built.report().exitReason):toBe("out-of-range")
				stop()
				Verify.expect((root:isDestroyed())):toBe(true)
			end,
		})

		verifyHarness:case("mounts a real SurfaceGui on the caller runtime and owns cleanup", {
			id = "native_outpost_terminal::native outpost terminal::mounts a real SurfaceGui on the caller runtime and owns cleanup",
			run = function()
				local built, _, stop, ctx = mount(scenario)
				local surface = ctx.inputTarget:FindFirstChild("OutpostSurface")
				Verify.expect(surface.ClassName):toBe("SurfaceGui")
				Verify.expect(surface.Face):toBe(ctx.types.Enum.NormalId.Back)
				Verify.expect(surface.CanvasSize.X):toBe(640)
				Verify.expect(surface.Active):toBe(false)
				Verify.expect(built.report().serverConnected):toBe(false)
				stop()
				Verify.expect((surface:isDestroyed())):toBe(true)
				Verify.expect(#ctx.inputTarget:GetChildren()):toBe(0)
			end,
		})
		verifyHarness:case("carries native remote verdicts and retires the surface when the console disappears", {
			id = "native_outpost_terminal::native outpost terminal::carries native remote verdicts and retires the surface when the console disappears",
			run = function()
				local sent: { { [string]: any } } = {}
				local remote, console, heartbeat = nil, nil, nil
				local built, _, stop, ctx = mount(scenario, nil, function(context, engine)
					remote = engine.new("RemoteEvent")
					remote.FireServer = function(_, message)
						table.insert(sent, message)
					end
					context.outpostRemote = remote
					local outpost = engine.new("Model")
					outpost.Name = "Outpost"
					outpost.Parent = context.worldTarget
					console = engine.new("Part")
					console.Name = "Console"
					console.Parent = outpost
					local character = engine.new("Model")
					local root = engine.new("Part")
					root.Name = "HumanoidRootPart"
					root.Parent = character
					context.player = { Character = character }
					heartbeat = engine.heartbeat
					context.runService = { Heartbeat = heartbeat }
				end)
				Verify.expect(sent[1].kind):toBe("open")
				remote.OnClientEvent:Fire({
					kind = "session" :: "session",
					token = "server-session",
					revision = 1,
					allocation = terminal.rules.START,
				})
				local surface = ctx.inputTarget:FindFirstChild("OutpostSurface")
				Verify.expect(surface.Active):toBe(true)
				Verify.expect(surface.Adornee):toBe(console)
				local request = built.steps.solve()
				Verify.expect(sent[#sent].kind):toBe("apply")
				Verify.expect(sent[#sent].token):toBe("server-session")
				Verify.expect(built.report().terminal.complete):toBe(false)
				remote.OnClientEvent:Fire({
					kind = "verdict" :: "verdict",
					requestId = request.requestId,
					ok = true,
					revision = 2,
					allocation = request.allocation,
				})
				Verify.expect(built.report().terminal.complete):toBe(true)
				console:Destroy()
				heartbeat:Fire(0)
				Verify.expect(surface.Active):toBe(false)
				Verify.expect(built.report().lastExit):toBe("adornee-lost")
				stop()
				Verify.expect(sent[#sent].kind):toBe("close")
				Verify.expect((engineLib.connections(remote.OnClientEvent))):toBe(0)
				Verify.expect((engineLib.connections(heartbeat))):toBe(0)
			end,
		})
	end)
end
