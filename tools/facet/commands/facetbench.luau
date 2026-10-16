--!strict

local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Bench = require("../lib/facetbench")
local Lute = require("../../vendor/verify/src/lute")
local Play = require("../../play/host/play")

return {
	name = "facetbench",
	summary = "Derive the extended hub contract and validation sources.",
	usage = "usage: lute run tools/facet facetbench prepare | render PROJECT OUTPUT | inspect-hud PLACE OUTPUT | mount WORKSPACE OUTPUT",
	run = function(invocation: Cli.Invocation): number
		if invocation.positional[1] == "inspect-hud" then
			require("./facetbench_hud")(
				assert(invocation.positional[2], "expected place"),
				assert(invocation.positional[3], "expected output directory")
			)
			return 0
		end
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
			local absoluteProject = Files.absolute(project)
			local host = Play.open({
				workspace = Files.parent(absoluteProject),
				project = Files.name(absoluteProject),
				outputs = Files.absolute(output .. "/checks"),
				captures = Files.absolute(output .. "/captures"),
				performance = false,
			})
			local ok, problem = pcall(function()
				local built, detail = host.build()
				assert(built, detail)
				for _, device in { "desktop", "phone-portrait", "phone-landscape", "tablet", "console" } do
					local qa = host.enter(device)
					qa:capture("hub")
					qa:dump("hub")
					local opened = if device == "console"
						then qa:gamepadActivate({ exact = "More", role = "button" })
						else qa:tap({ exact = "More", role = "button" })
					assert(opened, "More did not open")
					qa:capture("more")
					assert(qa:tap({ exact = "Close", role = "button" }))
				end
			end)
			host.close()
			Files.write(output .. "/play.log", table.concat(host.lines, "\n") .. "\n")
			Files.write(output .. "/captures.json", Lute.encode(host.shots))
			assert(ok, tostring(problem))
			return 0
		end
		assert(invocation.positional[1] == "prepare", "expected prepare")
		Bench.prepare(Files.cwd())
		print("facetbench: prepared extended contract, fixture tasks, follow-ups and type project")
		return 0
	end,
} :: Cli.Command
