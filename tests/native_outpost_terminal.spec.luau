--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
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
				Verify.expect((root.isDestroyed())):toBe(true)
			end,
		})
		verifyHarness:case("refuses over-budget drafts locally and preserves authority guards", {
			id = "native_outpost_terminal::native outpost terminal::refuses over-budget drafts locally and preserves authority guards",
			run = function()
				local built, _, stop = mount(terminal, {
					send = function()
						error("illegal allocation was sent")
					end,
				})
				built.steps.engage()
				built.steps.setValue("beacon", 2)
				built.steps.setValue("workshop", 4)
				Verify.expect(built.steps.apply().reason):toBe("budget")
				local request = {
					holderId = "a",
					senderId = "a",
					holderToken = "now",
					token = "now",
					distance = 4,
					allocation = { door = 2, beacon = 1, workshop = 2 },
				}
				for field, value in { token = "old", distance = 40, sinceLast = 0.01, senderId = "b" } do
					local invalid = table.clone(request)
					invalid[field] = value
					Verify.expect(terminal.rules.authorize(invalid).ok):toBe(false)
				end
				Verify.expect(terminal.rules.authorize(request).ok):toBe(true)
				stop()
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
				Verify.expect((surface.isDestroyed())):toBe(true)
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
					remote.OnClientEvent = engine.heartbeat
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
					local service = engineLib.new()
					heartbeat = service.heartbeat
					context.runService = { Heartbeat = heartbeat }
				end)
				Verify.expect(sent[1].kind):toBe("open")
				remote.OnClientEvent.fire({
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
				remote.OnClientEvent.fire({
					kind = "verdict" :: "verdict",
					requestId = request.requestId,
					ok = true,
					revision = 2,
					allocation = request.allocation,
				})
				Verify.expect(built.report().terminal.complete):toBe(true)
				console:Destroy()
				heartbeat.fire(0)
				Verify.expect(surface.Active):toBe(false)
				Verify.expect(built.report().lastExit):toBe("adornee-lost")
				stop()
				Verify.expect(sent[#sent].kind):toBe("close")
				Verify.expect((remote.OnClientEvent.count())):toBe(0)
				Verify.expect((heartbeat.count())):toBe(0)
			end,
		})
		verifyHarness:case("converges full snapshots across skipped revisions without losing independent drafts", {
			id = "native_outpost_terminal::native outpost terminal::converges full snapshots across skipped revisions without losing independent drafts",
			run = function()
				local left, _, stopLeft = mount(terminal)
				local right, _, stopRight = mount(terminal)
				left.steps.engage(terminal.rules.START, 1)
				right.steps.engage(terminal.rules.START, 1)
				left.steps.setValue("door", 1)
				right.steps.setValue("door", 2)
				local answer = { door = 2, beacon = 1, workshop = 2 }
				for _, client in { left, right } do
					Verify.expect((client.steps.ingest(7, answer))):toBe(true)
					Verify.expect((client.steps.ingest(6, terminal.rules.START))):toBe(false)
					Verify.expect((client.steps.ingest(7, terminal.rules.START))):toBe(false)
					Verify.expect(client.report().complete):toBe(true)
					Verify.expect((client.steps.ingest(12, terminal.rules.START))):toBe(true)
					Verify.expect(client.report().revision):toBe(12)
					Verify.expect(client.report().complete):toBe(false)
				end
				Verify.expect(left.report().draft.door):toBe(1)
				Verify.expect(right.report().draft.door):toBe(2)
				left.steps.engage(answer, 15)
				Verify.expect(left.report().revision):toBe(15)
				Verify.expect(left.report().draft.beacon):toBe(1)
				stopLeft()
				stopRight()
			end,
		})
		verifyHarness:case("recovers rejected or failed sends and cancels an unanswered request before reengagement", {
			id = "native_outpost_terminal::native outpost terminal::recovers rejected or failed sends and cancels an unanswered request before reengagement",
			run = function()
				local fail = true
				local built, _, stop = mount(terminal, {
					send = function()
						if fail then
							error("offline")
						end
					end,
				})
				built.steps.engage()
				Verify.expect(built.steps.apply().reason):toBe("transport")
				Verify.expect(built.report().status):toBe("rejected")
				fail = false
				local rejected = built.steps.apply()
				built.steps.reject(rejected.requestId, { code = "rate", message = terminal.rules.refusal("rate") })
				Verify.expect(built.report().message):toBe(terminal.rules.refusal("rate"))
				Verify.expect((built.steps.reject(rejected.requestId, {}))):toBe(false)
				local lost = built.steps.apply()
				built.steps.exit("cancel")
				built.steps.engage()
				local retry = built.steps.apply()
				Verify.expect(retry.sent):toBe(true)
				Verify.expect(retry.requestId > lost.requestId):toBe(true)
				Verify.expect(
					(
						built.steps.confirm(
							lost.requestId,
							{ revision = 9, allocation = { door = 2, beacon = 1, workshop = 2 } }
						)
					)
				):toBe(false)
				Verify.expect(built.report().status):toBe("pending")
				stop()
			end,
		})
	end)
end
