--!strict

local Verify = require("../tools/vendor/verify/src/core")
local Mount = require("../tools/play/engine/mount")
local MemoryReady = require("../tools/play/engine/memory_ready")
local Play = require("../tools/play/host/play")
local Output = require("../tools/facet/lib/verify_output")
local Files = require("../tools/facet/lib/files")
local Png = require("../tools/facet/lib/raster/png")
local QA = require("../tools/play/host/qa")
local Look = require("../tools/facet/lib/look")
local Run = require("../tools/facet/lib/run")

local function hud(): Mount.Snapshot
	return {
		root = { parent = "screen", path = "HUD", x = 0, y = 0, width = 400, height = 100 },
		fill = { parent = "root", path = "HUD.Fill", x = 0, y = 40, width = 10, height = 10 },
		text = { parent = "root", path = "HUD.Timer", x = 0, y = 0, width = 80, height = 20, text = "10" },
		neighbour = { parent = "root", path = "HUD.Shop", x = 80, y = 0, width = 80, height = 20, text = "Shop" },
	}
end

return function(harness: Verify.Harness)
	harness:case("GUI collector readiness stops at the first positive sample without retaining it", function(t)
		local now, calls = 0, 0
		local values = { 0, 0, 20, 10 }
		local readiness = MemoryReady.waitFor(true, function(): number?
			calls += 1
			return values[calls]
		end, function()
			return now
		end, function()
			now += 1
		end, 5)
		t:expect(readiness):toEqual({ ready = true, attempts = 3, elapsed = 2, tracking = true, timedOut = false })
		t:expect(calls):toBe(3)
		local scores: { [string]: number } = {}
		local idle: { [string]: unknown } = { memory = { guiMb = 0 }, memoryReadiness = readiness }
		local final: { [string]: unknown } = { memory = { guiMb = 10 } }
		local desktop: Play.DevicePerf = { returned = true, idle = idle, final = final, screens = {} }
		local perf: { [string]: Play.DevicePerf } = {}
		perf.desktop = desktop
		Play.perfScores(perf, scores)
		t:expect(scores["perf.desktop.guiReturnRatio"]):toBe(nil)
		t:expect(scores["perf.desktop.finalGuiMb"]):toBe(10)
	end)
	harness:case("disabled GUI tracking does not wait and zero samples time out", function(t)
		for _, tracking in { false, true } do
			local now, calls = 0, 0
			local readiness = MemoryReady.waitFor(tracking, function(): number?
				calls += 1
				return 0
			end, function()
				return now
			end, function()
				now += 1
			end, 2)
			t:expect(readiness):toEqual({
				ready = false,
				attempts = if tracking then 3 else 0,
				elapsed = if tracking then 2 else 0,
				tracking = tracking,
				timedOut = tracking,
			})
			t:expect(calls):toBe(if tracking then 3 else 0)
		end
	end)
	harness:case("post-return usage scores require a returned hub and positive memory samples", function(t)
		for _, returned in { false, true } do
			for _, value in { 0, 20 } do
				local scores: { [string]: number } = {}
				local final: { [string]: unknown } = { memory = { luaHeapKb = value, guiMb = value } }
				local desktop: Play.DevicePerf = { returned = returned, final = final, screens = {} }
				local perf: { [string]: Play.DevicePerf } = {}
				perf.desktop = desktop
				Play.perfScores(perf, scores)
				for _, name in { "finalHeapKb", "finalGuiMb" } do
					t:expect(scores["perf.desktop." .. name]):toBe(if returned and value > 0 then value else nil)
				end
			end
		end
		local scores: { [string]: number } = {}
		local perf: { [string]: Play.DevicePerf } = { desktop = { returned = true, screens = {} } }
		Play.perfScores(perf, scores)
		t:expect(scores["perf.desktop.finalHeapKb"]):toBe(nil)
		t:expect(scores["perf.desktop.finalGuiMb"]):toBe(nil)
	end)
	harness:case("saved report CLI queries need no project and preserve the saved bytes", function(t)
		local root = Files.temporaryDirectory("facet-report-query")
		t:defer(function()
			Files.remove(root)
		end)
		local report = "desktop 2-shop: high [text-fit] App.Shop: clipped\nconsole 3-close: problem: route failed\n"
		Files.write(Files.join(root, "report.txt"), report)
		local result = Run.capture({
			Run.lute(),
			"run",
			"tools/facet",
			"verify",
			"--report",
			"--out",
			root,
			"--device",
			"desktop",
			"--rule",
			"text-fit",
			"--step",
			"2-shop",
		})
		t:expect(result.ok):toBe(true)
		t:expect(string.find(result.stdout, "desktop/2-shop", 1, true) ~= nil):toBe(true)
		t:expect((string.find(result.stdout, "console", 1, true))):toBe(nil)
		t:expect(Files.read(Files.join(root, "report.txt"))):toBe(report)
	end)
	harness:case("readiness rejects an empty application root before dependent taps", function(t)
		t:expect(QA.interfaceMounted({ roots = 1, mounted = false }, true)):toBe(false)
		t:expect(QA.interfaceMounted({ roots = 0, mounted = false }, true)):toBe(false)
		t:expect(QA.interfaceMounted({ roots = 1, mounted = true }, true)):toBe(true)
		t:expect(QA.interfaceMounted({ roots = 1 }, false)):toBe(true)
		t:expect(QA.interfaceMounted(nil, true)):toBe(false)
	end)
	harness:case("report queries intersect filters keep capture IDs and page within a byte bound", function(t)
		local lines = {
			"screenshot C:/long/path/desktop/2-shop.png",
			"desktop 2-shop: high [text-fit] App.Shop: clipped",
			"console 2-shop: high [text-fit] App.Shop: clipped",
			"desktop 3-close: medium [target] App.Close: small",
		}
		local queried =
			table.concat(Output.query(lines, { device = "desktop", rule = "text-fit", step = "2-shop" }), "\n")
		t:expect(string.find(queried, "desktop/2-shop: high [text-fit]", 1, true) ~= nil):toBe(true)
		t:expect((string.find(queried, "console", 1, true))):toBe(nil)
		t:expect((string.find(queried, "C:/long", 1, true))):toBe(nil)
		t:expect(#Output.queries(lines, "artifacts/check")):toBe(3)
		for index = 1, 80 do
			table.insert(lines, `desktop 2-shop: high [text-fit] App.{index}: ` .. string.rep("x", 800))
		end
		local first = table.concat(Output.query(lines, { device = "desktop", rule = "text-fit" }), "\n")
		local second = table.concat(Output.query(lines, { device = "desktop", rule = "text-fit", page = 2 }), "\n")
		t:expect(#first < 4096 and #second < 4096):toBe(true)
		t:expect(first ~= second):toBe(true)
		t:expect(string.find(first, "--page 2", 1, true) ~= nil):toBe(true)
		t:expect(#Output.query(lines, { device = "tablet" })):toBe(1)
	end)
	harness:case(
		"mount and route failures retain one root capture and stop only the dependent device steps",
		function(t)
			local root = Files.temporaryDirectory("facet-look-stop")
			t:defer(function()
				Files.remove(root)
			end)
			local calls: { [string]: number } = {}
			local shots: { [string]: number } = {}
			local closed = false
			local result = Look.run({
				project = "unused",
				devices = { "desktop", "console", "tablet" },
				steps = Look.parseSteps({ "Shop", "Buy", "Close" }),
				out = root,
			}, function(options)
				t:expect(options.requireInterface):toBe(true)
				return {
					build = function()
						return true, nil
					end,
					enter = function(device)
						calls[device], shots[device] = 0, 0
						return (
							{
								mountProblem = if device == "desktop" then "interface did not mount" else nil,
								call = function()
									calls[device] += 1
									return {
										tap = {
											tapped = device ~= "console",
											reason = "no selection path reaches the control",
										},
										settled = true,
										dump = Look.sample(false),
									}
								end,
								capture = function()
									shots[device] += 1
								end,
								dump = function() end,
							} :: unknown
						) :: QA.QA
					end,
					close = function()
						closed = true
					end,
					measure = function() end,
					perf = {},
					lines = {},
					timings = {},
					shots = {},
					log = function() end,
				}
			end)
			t:expect(calls.desktop):toBe(0)
			t:expect(calls.console):toBe(1)
			t:expect(calls.tablet):toBe(3)
			t:expect(shots.desktop):toBe(1)
			t:expect(shots.console):toBe(2)
			t:expect(closed):toBe(true)
			local summary = table.concat(Output.summarize({ result.screens[1] }), "\n")
			t:expect(summary):toBe("desktop 1-start: problem: interface did not mount")
		end
	)
	harness:case("dump transfer keeps the first chunk and checks the complete byte count", function(t)
		local calls = 0
		local text = QA.readDump(
			{ token = "s1", count = 3, bytes = 6, first = "ab", automatic = true },
			function(command, value)
				calls += 1
				t:expect(command):toBe("chunk")
				local fields = value :: { [string]: unknown }
				t:expect(fields.token):toBe("s1")
				return if fields.index == 2 then "cd" else "ef"
			end
		)
		t:expect(text):toBe("abcdef")
		t:expect(calls):toBe(2)
		t:expect(QA.readDump("direct", function()
			error("unexpected call")
		end)):toBe("direct")
		local released = false
		local ok = pcall(QA.readDump, { token = "s1", count = 2, first = "ab", automatic = true }, function(command)
			if command == "release" then
				released = true
			end
			return nil
		end)
		t:expect(ok):toBe(false)
		t:expect(released):toBe(true)
		local complete = pcall(QA.readDump, { count = 1, first = "ab", bytes = 3, automatic = true }, function()
			return nil
		end)
		t:expect(complete):toBe(false)
	end)
	harness:case("capture summaries keep device order and project-relative directories", function(t)
		local screens = {}
		for _, device in { "desktop", "phone-portrait" } do
			for index = 1, 8 do
				table.insert(screens, {
					device = device,
					label = tostring(index),
					png = Files.join(Files.cwd(), "artifacts/facet-verify/live/captures", device, `{index}.png`),
				})
			end
		end
		local lines = Output.captures(screens)
		t:expect(#lines):toBe(2)
		t:expect(lines[1]):toBe("desktop: 8 captures in artifacts/facet-verify/live/captures/desktop")
		t:expect(lines[2]):toBe("phone-portrait: 8 captures in artifacts/facet-verify/live/captures/phone-portrait")
		t:expect(#screens):toBe(16)
		t:expect(Output.captures({ { device = "console", label = "start", problem = "failed" } })[1])
			:toBe("console: 0 captures")
	end)
	harness:case("duration estimates include all devices taps captures and explicit waits", function(t)
		t:expect(Output.estimate(5, 8, 2) > Output.estimate(5, 8, nil)):toBe(true)
		t:expect(Output.estimate(5, 8, nil) > Output.estimate(1, 8, nil)):toBe(true)
		t:expect(Output.estimate(5, 8, nil) > Output.estimate(5, 0, nil)):toBe(true)
	end)
	harness:case("fast capture PNGs preserve every channel and pixel", function(t)
		for channels = 1, 4 do
			local data = buffer.create(71 * 67 * channels)
			for index = 0, buffer.len(data) - 1 do
				buffer.writeu8(data, index, (index * 71) % 256)
			end
			local decoded = Png.decode(Png.encode({ width = 71, height = 67, channels = channels, data = data }, true))
			t:expect(decoded.width):toBe(71)
			t:expect(decoded.height):toBe(67)
			t:expect(decoded.channels):toBe(channels)
			t:expect(buffer.tostring(decoded.data)):toBe(buffer.tostring(data))
		end
	end)
	harness:case("short settle windows still restart when layout changes", function(t)
		local run = Mount.start(hud(), 0)
		Mount.step(run, hud(), 0.09, 0.1)
		t:expect(run.seconds):toBe(nil)
		local changed = hud()
		changed.neighbour.x = 90
		Mount.step(run, changed, 0.1, 0.1)
		Mount.step(run, changed, 0.19, 0.1)
		t:expect(run.seconds):toBe(nil)
		Mount.step(run, changed, 0.21, 0.1)
		t:expect(run.seconds):toBe(0.1)
	end)
	harness:case("a settle timeout cannot become a valid overhead score", function(t)
		local scores: { [string]: number } = {}
		local failedMount: { [string]: unknown } = {}
		failedMount.timedOut = true
		local completeMount: { [string]: unknown } = {}
		completeMount.timedOut = false
		local perf: { [string]: Play.DevicePerf } = {}
		perf.desktop = { screens = {} }
		perf.desktop.mountSeconds = 22
		perf.desktop.mount = failedMount
		perf["phone-portrait"] = { screens = {} }
		perf["phone-portrait"].mountSeconds = 3
		perf["phone-portrait"].mount = completeMount
		Play.perfScores(perf, scores)
		t:expect(scores["perf.desktop.mountSeconds"]):toBe(nil)
		t:expect(scores["perf.desktop.mountTimedOut"]):toBe(1)
		t:expect(scores["perf.phone-portrait.mountSeconds"]):toBe(3)
		t:expect(scores["perf.phone-portrait.mountTimedOut"]):toBe(0)
	end)
	harness:case("stable run restarts on structure and neighbour movement", function(t)
		local run = Mount.start(hud(), 0)
		Mount.step(run, hud(), 0.8, 1)
		t:expect(run.seconds):toBe(nil)
		local inserted = hud()
		inserted.corner = { parent = "fill", path = "HUD.Fill.Corner" }
		Mount.step(run, inserted, 0.9, 1)
		Mount.step(run, inserted, 1.8, 1)
		t:expect(run.seconds):toBe(nil)
		Mount.step(run, inserted, 2, 1)
		t:expect(run.seconds):toBe(0.9)
		local moving = Mount.start(hud(), 0)
		for frame = 1, 100 do
			local snapshot = hud()
			snapshot.text.text = tostring(frame)
			snapshot.text.width = 80 + frame
			snapshot.neighbour.x = 80 + frame
			Mount.step(moving, snapshot, frame / 10, 1)
			t:expect(moving.seconds):toBe(nil)
		end
	end)
	harness:case("live text and fill complete the same quiet run as a static HUD", function(t)
		for _, live in { false, true } do
			local run = Mount.start(hud(), 0)
			for frame = 1, 11 do
				local snapshot = hud()
				if live then
					snapshot.text.text = tostring(frame)
					snapshot.fill.width = 10 + frame
				end
				Mount.step(run, snapshot, frame / 10, 1)
			end
			t:expect(run.seconds):toBe(0)
		end
	end)
	harness:case("static HUD keeps a stable run", function(t)
		local changed, live = Mount.compare(hud(), hud())
		t:expect(changed):toBe(false)
		t:expect(#live):toBe(0)
	end)
	harness:case("growing progress fill does not restart a stable run", function(t)
		local before = hud()
		for width = 11, 100 do
			local after = hud()
			after.fill.width = width
			local changed, live = Mount.compare(before, after)
			t:expect(changed):toBe(false)
			t:expect(live[1].path):toBe("HUD.Fill")
			before = after
		end
	end)
	harness:case("ticking countdown excludes its text and own one-axis content sizing", function(t)
		local before, after = hud(), hud()
		after.text.text, after.text.width = "9", 70
		local changed, live = Mount.compare(before, after)
		t:expect(changed):toBe(false)
		t:expect(live[1].reason):toBe("text changed this frame")
		before = after
		after = hud()
		after.text.text, after.text.width = "9", 72
		t:expect((Mount.compare(before, after))):toBe(false)
		after.text.x = 1
		t:expect((Mount.compare(before, after))):toBe(true)
	end)
	harness:case("live counter moving a neighbour restarts the run", function(t)
		local before, after = hud(), hud()
		after.text.text, after.text.width, after.neighbour.x = "100", 100, 100
		local changed, live = Mount.compare(before, after)
		t:expect(changed):toBe(true)
		t:expect(#live):toBe(1)
	end)
	harness:case("structure additions removals replacements and reparenting restart", function(t)
		for _, mode in { "add", "remove", "replace", "reparent" } do
			local before, after = hud(), hud()
			if mode == "add" then
				after.corner = { parent = "fill", path = "HUD.Fill.Corner" }
			elseif mode == "remove" or mode == "replace" then
				local without: Mount.Snapshot = {}
				for key, node in after do
					if key ~= "fill" then
						without[key] = node
					end
				end
				if mode == "replace" then
					without.replacement = after.fill
				end
				after = without
			else
				after.fill.parent = "neighbour"
			end
			t:expect((Mount.compare(before, after))):toBe(true)
		end
	end)
	harness:case("parent reflow position motion and two-axis sizing still count", function(t)
		for _, mode in { "parent", "position", "both" } do
			local before, after = hud(), hud()
			if mode == "parent" then
				after.root.width = 410
			elseif mode == "position" then
				after.fill.x = 1
			else
				after.fill.width, after.fill.height = 11, 11
			end
			t:expect((Mount.compare(before, after))):toBe(true)
		end
		t:expect((Mount.compare({}, {}))):toBe(true)
	end)
end
