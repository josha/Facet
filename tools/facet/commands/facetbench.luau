--!strict

local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Bench = require("../lib/facetbench")
local Lute = require("../../vendor/verify/src/lute")
local process = require("@std/process")
local Play = require("../../play/host/play")

return {
	name = "facetbench",
	summary = "Derive the extended hub contract and validation sources.",
	usage = "usage: lute run tools/facet facetbench prepare | render PROJECT OUTPUT | mount WORKSPACE OUTPUT",
	run = function(invocation: Cli.Invocation): number
		if invocation.positional[1] == "mount" then
			local output = assert(invocation.positional[3], "expected output directory")
			local host = Play.open({
				workspace = Files.absolute((assert(invocation.positional[2], "expected workspace"))),
				outputs = Files.absolute(output .. "/checks"),
				captures = Files.absolute(output .. "/captures"),
				compareMount = true,
			})
			local ok, problem = pcall(function()
				local built, detail = host.build()
				assert(built, detail)
				for _, device in { "desktop", "phone-portrait" } do
					local qa = host.enter(device)
					qa:capture("mounted-hub")
				end
			end)
			host.close()
			Files.write(output .. "/perf.json", Lute.encode(host.perf))
			Files.write(output .. "/play.log", table.concat(host.lines, "\n") .. "\n")
			assert(ok, tostring(problem))
			return 0
		end
		if invocation.positional[1] == "render" then
			local project = assert(invocation.positional[2], "expected project")
			local output = assert(invocation.positional[3], "expected output directory")
			Files.makeDirectory(output)
			local place = Files.absolute(output .. "/render.rbxlx")
			local built = process.run({ "rojo", "build", project, "-o", place })
			assert(built.ok, built.stdout .. built.stderr)
			local opened, problem =
				Lute.studio.launch({ place = place, directory = output .. "/studio", runSeconds = 180 })
			assert(opened, problem)
			local owner = opened :: Lute.StudioLaunched
			local ok, result = pcall(function(): string
				local started = owner.session.play(true)
				assert(started.ok, started.detail)
				local response = owner.session.execute(
					"Client",
					[[
local frames = 0
local connection = game:GetService('RunService').RenderStepped:Connect(function() frames += 1 end)
task.wait(3)
connection:Disconnect()
local camera = workspace.CurrentCamera
assert(camera and camera.ViewportSize.X > 1 and camera.ViewportSize.Y > 1, 'camera viewport is not rendered')
assert(frames > 1, 'rendered frames did not advance')
return game:GetService('HttpService'):JSONEncode({ width = camera.ViewportSize.X, height = camera.ViewportSize.Y, frames = frames })
]]
				)
				assert(response.ok, response.detail)
				return response.text or ""
			end)
			local closed = owner.close()
			Files.write(output .. "/render.txt", tostring(result))
			assert(ok, tostring(result))
			assert(#closed.survivors == 0, "render Studio survived cleanup")
			print("facetbench render: " .. tostring(result))
			return 0
		end
		assert(invocation.positional[1] == "prepare", "expected prepare")
		Bench.prepare(Files.cwd())
		print("facetbench: prepared extended contract, fixture tasks, follow-ups and type project")
		return 0
	end,
} :: Cli.Command
