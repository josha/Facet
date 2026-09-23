--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local terminal = require("../examples/gallery/examples/outpost_terminal")
local scenario = require("../examples/gallery/scenarios/outpost_terminal")

local function mount(module, options, configure)
	local engine = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local target = engine.new("ScreenGui")
	local ctx = {
		Facet = Facet,
		Compose = Facet.Compose,
		runtime = runtime,
		Host = runtime.constructors,
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
	local stop, node = runtime.mount(function()
		built = module.build(ctx, options)
		return built.screen()
	end, target)
	return built, node, function()
		stop()
		runtime:dispose()
	end, ctx, engine
end

t.describe("native outpost terminal", function()
	t.it("keeps draft separate until the matching server verdict and ignores stale replies", function()
		local envelopes = {}
		local built, root, stop = mount(terminal, {
			send = function(envelope)
				table.insert(envelopes, envelope)
			end,
		})
		t.expect(root.ClassName).toBe("Frame")
		built.steps.engage(terminal.rules.START, 2)
		built.steps.setValue("door", 2)
		built.steps.setValue("beacon", 1)
		built.steps.setValue("workshop", 2)
		local sent = built.steps.apply()
		t.expect(sent.sent).toBe(true)
		t.expect(built.report().status).toBe("pending")
		t.expect(built.report().complete).toBe(false)
		t.expect(built.steps.apply().reason).toBe("pending")
		t.expect(built.steps.confirm(sent.requestId + 1, { revision = 3, allocation = sent.allocation })).toBe(false)
		t.expect(built.report().complete).toBe(false)
		built.steps.confirm(sent.requestId, { revision = 3, allocation = sent.allocation })
		t.expect(built.report().complete).toBe(true)
		t.expect(built.steps.ingest(2, terminal.rules.START)).toBe(false)
		t.expect(built.report().complete).toBe(true)
		built.steps.reset()
		t.expect(built.report().complete).toBe(true)
		local reset = envelopes[#envelopes]
		built.steps.exit("out-of-range")
		t.expect(built.steps.confirm(reset.requestId, { revision = 4, allocation = terminal.rules.START })).toBe(false)
		t.expect(built.report().exitReason).toBe("out-of-range")
		stop()
		t.expect(root.isDestroyed()).toBe(true)
	end)
	t.it("refuses over-budget drafts locally and preserves authority guards", function()
		local built, _, stop = mount(terminal, {
			send = function()
				error("illegal allocation was sent")
			end,
		})
		built.steps.engage()
		built.steps.setValue("beacon", 2)
		built.steps.setValue("workshop", 4)
		t.expect(built.steps.apply().reason).toBe("budget")
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
			t.expect(terminal.rules.authorize(invalid).ok).toBe(false)
		end
		t.expect(terminal.rules.authorize(request).ok).toBe(true)
		stop()
	end)
	t.it("mounts a real SurfaceGui on the caller runtime and owns cleanup", function()
		local built, _, stop, ctx = mount(scenario)
		local surface = ctx.inputTarget:FindFirstChild("OutpostSurface")
		t.expect(surface.ClassName).toBe("SurfaceGui")
		t.expect(surface.Face).toBe(ctx.types.Enum.NormalId.Back)
		t.expect(surface.CanvasSize.X).toBe(640)
		t.expect(surface.Active).toBe(false)
		t.expect(built.report().serverConnected).toBe(false)
		stop()
		t.expect(surface.isDestroyed()).toBe(true)
		t.expect(#ctx.inputTarget:GetChildren()).toBe(0)
	end)
	t.it("carries native remote verdicts and retires the surface when the console disappears", function()
		local sent, remote, console, heartbeat = {}, nil, nil, nil
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
		t.expect(sent[1].kind).toBe("open")
		remote.OnClientEvent.fire({
			kind = "session",
			token = "server-session",
			revision = 1,
			allocation = terminal.rules.START,
		})
		local surface = ctx.inputTarget:FindFirstChild("OutpostSurface")
		t.expect(surface.Active).toBe(true)
		t.expect(surface.Adornee).toBe(console)
		local request = built.steps.solve()
		t.expect(sent[#sent].kind).toBe("apply")
		t.expect(sent[#sent].token).toBe("server-session")
		t.expect(built.report().terminal.complete).toBe(false)
		remote.OnClientEvent.fire({
			kind = "verdict",
			requestId = request.requestId,
			ok = true,
			revision = 2,
			allocation = request.allocation,
		})
		t.expect(built.report().terminal.complete).toBe(true)
		console:Destroy()
		heartbeat.fire()
		t.expect(surface.Active).toBe(false)
		t.expect(built.report().lastExit).toBe("adornee-lost")
		stop()
		t.expect(sent[#sent].kind).toBe("close")
		t.expect(remote.OnClientEvent.count()).toBe(0)
		t.expect(heartbeat.count()).toBe(0)
	end)
	t.it("converges full snapshots across skipped revisions without losing independent drafts", function()
		local left, _, stopLeft = mount(terminal)
		local right, _, stopRight = mount(terminal)
		left.steps.engage(terminal.rules.START, 1)
		right.steps.engage(terminal.rules.START, 1)
		left.steps.setValue("door", 1)
		right.steps.setValue("door", 2)
		local answer = { door = 2, beacon = 1, workshop = 2 }
		for _, client in { left, right } do
			t.expect(client.steps.ingest(7, answer)).toBe(true)
			t.expect(client.steps.ingest(6, terminal.rules.START)).toBe(false)
			t.expect(client.steps.ingest(7, terminal.rules.START)).toBe(false)
			t.expect(client.report().complete).toBe(true)
			t.expect(client.steps.ingest(12, terminal.rules.START)).toBe(true)
			t.expect(client.report().revision).toBe(12)
			t.expect(client.report().complete).toBe(false)
		end
		t.expect(left.report().draft.door).toBe(1)
		t.expect(right.report().draft.door).toBe(2)
		left.steps.engage(answer, 15)
		t.expect(left.report().revision).toBe(15)
		t.expect(left.report().draft.beacon).toBe(1)
		stopLeft()
		stopRight()
	end)
	t.it("recovers rejected or failed sends and cancels an unanswered request before reengagement", function()
		local fail = true
		local built, _, stop = mount(terminal, {
			send = function()
				if fail then
					error("offline")
				end
			end,
		})
		built.steps.engage()
		t.expect(built.steps.apply().reason).toBe("transport")
		t.expect(built.report().status).toBe("rejected")
		fail = false
		local rejected = built.steps.apply()
		built.steps.reject(rejected.requestId, { code = "rate", message = terminal.rules.refusal("rate") })
		t.expect(built.report().message).toBe(terminal.rules.refusal("rate"))
		t.expect(built.steps.reject(rejected.requestId, {})).toBe(false)
		local lost = built.steps.apply()
		built.steps.exit("cancel")
		built.steps.engage()
		local retry = built.steps.apply()
		t.expect(retry.sent).toBe(true)
		t.expect(retry.requestId > lost.requestId).toBe(true)
		t.expect(
			built.steps.confirm(lost.requestId, { revision = 9, allocation = { door = 2, beacon = 1, workshop = 2 } })
		)
			.toBe(false)
		t.expect(built.report().status).toBe("pending")
		stop()
	end)
end)
