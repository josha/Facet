--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

	type Census = { live: number, connections: number, owners: number, holding: number, mounts: number }

	local function owners(): (number, number)
		local report = Compose.inspect.snapshot()
		assert(report.active and report.droppedOwners == 0, "the owner census is incomplete")
		local count, holding = 0, 0
		local function walk(entry: any)
			if not entry.disposed and entry.holding > 0 then
				count += 1
				holding += entry.holding
			end
			for _, child in entry.children do
				walk(child)
			end
		end
		for _, entry in report.mounts do
			walk(entry)
		end
		for _, entry in report.detached do
			walk(entry)
		end
		return count, holding
	end

	local function census(engine: any): Census
		local now = engine.census()
		local count, holding = owners()
		return {
			live = now.live,
			connections = now.connections,
			owners = count,
			holding = holding,
			mounts = Compose.outstandingMounts(),
		}
	end

	local function same(before: Census, after: Census, label: string)
		for _, field in { "live", "connections", "owners", "holding", "mounts" } do
			local was, now = (before :: any)[field], (after :: any)[field]
			assert(was == now, `{label}: {field} {was} -> {now}`)
		end
	end

	local function inspected(body: () -> ())
		Compose.inspect.start({ maxOwners = 1000000, maxNodes = 1000000 })
		local ok, failure = pcall(function(): boolean
			body()
			return true
		end)
		Compose.inspect.stop()
		if not ok then
			error(failure, 0)
		end
	end

	verifyHarness:suite("native parity weak3 rows: declared mount ramp ceiling", function()
		verifyHarness:case(
			"returns the performance lab to its floor after every rung of a second ramp lap to 40000 rows",
			{
				id = "native_parity_weak3_rows::native parity weak3 rows: declared mount ramp ceiling::returns the performance lab to its floor after every rung of a second ramp lap to 40000 rows",
				tags = { "tier:release" },
				run = function()
					inspected(function()
						local lab = require("../examples/performance/lab/perf_lab") :: any
						local dataset = require("../examples/performance/lab/dataset") :: any
						Verify.expect(dataset.RAMP_STEPS):toEqual({ 100, 500, 2000, 10000, 40000 })
						Verify.expect(dataset.MAX_ROWS):toBe(40000)
						local modules = {
							sensory = require("../examples/performance/lab/sensory"),
							dataset = dataset,
							rows = require("../examples/performance/lab/rows"),
							capture = require("../examples/performance/lab/capture"),
							workloads = require("../examples/performance/lab/workloads"),
						}
						local engine = engineLib.new()
						local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
						local target = engine.new("Folder")
						local probe
						local world = {
							Facet = Facet,
							Compose = Compose,
							runtime = runtime,
							Host = (runtime.constructors :: unknown) :: RobloxHost,
							UI = Facet.controls(runtime, { types = engine.types } :: any),
							engine = engine,
							target = target,
							types = engine.types,
							viewport = { w = 800, h = 600 },
							heartbeat = engine.heartbeat,
							captureFacts = function()
								return {
									evidenceClass = "lune",
									capturedAtIso = "2026-09-24T00:00:00Z",
									sourceStamp = "test",
									placeName = "headless",
									viewport = "800x600",
									orientation = "landscape" :: "landscape",
									graphicsQualityLevel = "n/a",
									frameTarget = "n/a",
									studioVersion = "n/a",
									deviceLabel = "lune",
									thermalNote = "n/a",
								}
							end,
							probe = function(value)
								probe = value
							end,
						}
						local before = census(engine)
						local stop = runtime.mount(function()
							return world.Host.ScreenGui({ lab.build(world, modules) })
						end, target)
						local floor: Census? = nil
						local function lap(label: string)
							probe.ramp()
							for rung, rows in dataset.RAMP_STEPS do
								engine.heartbeat:Fire(1 / 60)
								Verify.expect(probe.state().rows):toBe(rows)
								if floor then
									same(floor, census(engine), `{label} rung {rung} ({rows} rows)`)
								end
							end
							Verify.expect(probe.state().queued):toBe(0)
							Verify.expect(probe.state().playing):toBe(false)
						end
						lap("warm")
						floor = census(engine)
						local captures = probe.state().captures
						lap("measured")
						Verify.expect(probe.state().captures):toBe(captures + #dataset.RAMP_STEPS)
						stop()
						runtime:dispose()
						Verify.expect(#target:GetChildren()):toBe(0)
						Verify.expect((engineLib.connections(engine.heartbeat))):toBe(0)
						same(before, census(engine), "lab teardown")
					end)
				end,
			}
		)
	end)
end
