--!strict
type Child = typeof(require("@repo/tools/typecheck/aliases").Child)
local Loader = require("../../tests/lib/loader")
local loader = Loader.new()
local Facet = (loader.require("src") :: unknown) :: typeof(require("../../src"))
local worlds = (
	loader.require("tests/lib/content_world.luau") :: unknown
) :: typeof(require("../../tests/lib/content_world"))

type Costs = { instances: number, connections: number, frameWrites: number, frameUs: number }
local FRAMES = 12000

local function measure(grouped: boolean): Costs
	local world = worlds.new(function(UI, Host, engine)
		local children: { Child } =
			{ UI.Image { image = "rbxassetid://1" }, UI.Text { text = "Audio" }, UI.Button { label = "Apply" } }
		return if grouped
			then UI.Group {
				width = 400,
				height = 80,
				groupTransparency = Facet.Compose.cell(0.4),
				table.unpack(children),
			}
			else Host.Frame { Size = engine.types.UDim2.fromOffset(400, 80), table.unpack(children) }
	end, { motionLevel = "none" })
	local counts = world.engine.census()
	local writes = 0
	local observed = world.engine.onWrite(function()
		writes += 1
	end)
	local started = os.clock()
	for _ = 1, FRAMES do
		world.engine.heartbeat:Fire(1 / 60)
	end
	local elapsed = os.clock() - started
	observed:Disconnect()
	world.stop()
	assert(world.engine.census().connections == 0, "group cost scene leaked connections")
	return {
		instances = counts.live,
		connections = counts.connections,
		frameWrites = writes,
		frameUs = elapsed * 1000000 / FRAMES,
	}
end

for round = 1, 7 do
	local plain, group = measure(false), measure(true)
	assert(group.instances == plain.instances, "group adds native instances")
	assert(group.connections == plain.connections, "group adds native connections")
	assert(group.frameWrites == 0 and plain.frameWrites == 0, "idle containers write properties")
	print(
		`round {round}: plain {plain.instances} instances, {plain.connections} connections, {plain.frameWrites} writes, {string.format(
			"%.3f",
			plain.frameUs
		)} us/frame; group {group.instances} instances, {group.connections} connections, {group.frameWrites} writes, {string.format(
			"%.3f",
			group.frameUs
		)} us/frame`
	)
end
print(`native engine double: {FRAMES} idle Heartbeats per sample; CPU dispatch only; GPU compositing is unmeasured`)
