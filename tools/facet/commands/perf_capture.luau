--!strict

local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Json = require("../lib/json")
local Play = require("../../play/host/play")

return function(invocation: Cli.Invocation): number
	local workspace = Cli.flag(invocation, "workspace")
	local output = Cli.flag(invocation, "out")
	if workspace == nil or output == nil then
		print(
			"usage: lute run tools/facet perf capture --workspace DIR --out DIR [--devices desktop,phone-portrait] [--tap TEXT]..."
		)
		return 2
	end
	local out = Files.absolute(output)
	local host = Play.open({ workspace = Files.absolute(workspace), outputs = out, captures = out .. "/captures" })
	local ok, problem = pcall(function()
		local built, failure = host.build()
		assert(built, failure)
		for _, device in string.split(Cli.flag(invocation, "devices") or "desktop,phone-portrait", ",") do
			local qa = host.enter(device)
			Files.write(
				out .. "/" .. device .. "-geometry.json",
				Json.encode(qa:call("perf", { action = "geometry", seconds = 2 }))
			)
			qa:dump("mounted")
			for index, text in invocation.repeated.tap or {} do
				host.measure(device, tostring(index) .. "-" .. text, function()
					local tapped, detail = qa:tap({ text = text })
					assert(tapped, detail)
					qa:sleep(2)
					qa:dump(tostring(index) .. "-" .. text)
					qa:capture(tostring(index) .. "-" .. text)
				end)
			end
		end
	end)
	host.close()
	Files.write(out .. "/perf.json", Json.encode(host.perf))
	Files.write(out .. "/play.log", table.concat(host.lines, "\n"))
	if not ok then
		print(tostring(problem))
		return 1
	end
	print("perf capture: " .. out .. "/perf.json")
	return 0
end
