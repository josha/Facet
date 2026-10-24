--!strict
local Verify = require("../../vendor/verify/src/core")

local json = require("@std/json")
local Cli = require("../lib/cli")
local Look = require("../lib/look")

local USAGE = [[usage: lute run tools/facet preview [--device ID]... [--tap TEXT]... [--wait SECONDS]
                                    [--project FILE] [--out DIR] [--keep] [--outline] [--dump FILE] [--json]

Builds the place with Rojo, plays it in a disposable Roblox Studio on each
device, and saves a screenshot and an interface dump of each screen. It prints
the screenshot paths and whether each tap found its control. Add --outline for
visible text and controls with their screen rectangles. Look at the screenshots
to judge the layout.

Use preview to look at a screen. It is not a flow test: the controls own their
input on each device, and audit checks every device. The outline is the
summary of a dump, so you do not need to read the dump files.

  --device ID     desktop, phone-portrait, phone-landscape, tablet or console.
                  Repeat it for more devices. The default is desktop and
                  phone-portrait.
  --tap TEXT      After the first screen, tap the control that shows TEXT and
                  save the next screen. Repeat it for a path, for example
                  --tap Shop --tap Buy.
  --wait SECONDS  The wait after each tap. The default is 1.5.
  --project FILE  The Rojo project. The default is default.project.json.
  --out DIR       Where the screenshots and dumps go. The default is
                  artifacts/facet-preview.
  --keep          Keep Studio open after the run.
  --outline       Also print text and control rectangles (up to 40 per screen).
  --dump FILE     Print the outline of a saved dump only. No Studio starts.

Studio must be installed and signed in. Each run takes about one minute for
each device.]]

local function outlineText(
	device: string,
	label: string,
	png: string?,
	dump: string?,
	problem: string?,
	tap: string?
): string
	local lines = { ("%s %s"):format(device, label) }
	if tap ~= nil then
		table.insert(lines, "  " .. tap)
	end
	if png ~= nil then
		table.insert(lines, "  screenshot " .. png)
	end
	if problem ~= nil then
		table.insert(lines, "  problem: " .. problem)
	end
	if dump ~= nil then
		for _, line in Look.outline(Look.load(dump), 40) do
			table.insert(lines, "  " .. line)
		end
	end
	return table.concat(lines, "\n")
end

local function run(invocation: Cli.Invocation): number
	local unknown =
		Cli.unknownFlags(invocation, { "device", "tap", "wait", "project", "out", "keep", "dump", "outline" })
	if unknown ~= nil or #invocation.positional > 0 then
		if unknown ~= nil then
			print("facet preview: unknown flags " .. unknown)
		end
		print(USAGE)
		return 2
	end
	local saved = Cli.flag(invocation, "dump")
	if saved ~= nil then
		print(outlineText("dump", saved, nil, saved, nil))
		return 0
	end
	local devices: { string } = invocation.repeated.device or { "desktop", "phone-portrait" }
	for _, device in devices do
		if table.find(Look.DEVICES, device) == nil then
			print(("facet preview: unknown device %s; use %s"):format(device, table.concat(Look.DEVICES, ", ")))
			return 2
		end
	end
	local wait = tonumber(Cli.flag(invocation, "wait") or "")
	local result = Look.run({
		project = Cli.flag(invocation, "project") or "default.project.json",
		devices = devices,
		steps = Look.parseSteps(invocation.repeated.tap or {}, wait),
		out = Cli.flag(invocation, "out") or "artifacts/facet-preview",
		keep = Cli.switch(invocation, "keep"),
	})
	if result.problem ~= nil then
		print("facet preview: " .. (result.problem :: string))
		return 1
	end
	local texts: { string } = {}
	local shots: { json.Value } = {}
	local failed = false
	for _, screen in result.screens do
		table.insert(
			texts,
			outlineText(
				screen.device,
				screen.label,
				screen.png,
				if Cli.switch(invocation, "outline") then screen.dump else nil,
				screen.problem,
				Look.tapLine(screen)
			)
		)
		local shot: json.Value = {
			device = screen.device,
			label = screen.label,
			png = screen.png,
			problem = screen.problem,
			tap = screen.tap,
			found = screen.found,
		}
		table.insert(shots, shot)
		failed = failed or screen.problem ~= nil
	end
	local summary = Look.tapSummary(result.screens)
	if summary ~= nil then
		table.insert(texts, summary)
	end
	local value: json.Value = { out = result.out, screens = shots, taps = summary }
	Cli.emit(invocation, value, table.concat(texts, "\n\n"))
	return if failed then 1 else 0
end

local function register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "the outline lists visible text and controls from top to bottom with their rectangles", {
		id = prefix .. "the outline lists visible text and controls from top to bottom with their rectangles",
		run = function(test: Verify.Context)
			local lines = Look.outline(Look.decode(Look.sample(false)), 200)
			local joined = table.concat(lines, "\n")
			local firstY = tonumber(string.match(lines[1] or "", "at%s+%-?%d+,(%-?%d+)"))
			local lastY = tonumber(string.match(lines[#lines] or "", "at%s+%-?%d+,(%-?%d+)"))
			Verify.expect(#lines > 5):toBeTrueWith("the outline is nearly empty")
			Verify.expect(string.find(joined, "button", 1, true) ~= nil)
				:toBeTrueWith("no control is marked as a button")
			Verify.expect(firstY ~= nil and lastY ~= nil and firstY <= lastY)
				:toBeTrueWith("the lines are not in screen order")
		end,
	})
	harness:case(prefix .. "the outline stops at its limit and says how many lines it left out", {
		id = prefix .. "the outline stops at its limit and says how many lines it left out",
		run = function(test: Verify.Context)
			local lines = Look.outline(Look.decode(Look.sample(false)), 3)
			Verify.expect(#lines):toBe(4)
			Verify.expect(string.find(lines[4], "more", 1, true) ~= nil)
				:toBeTrueWith("the last line does not count the rest")
		end,
	})
	harness:case(
		prefix .. "each tapped screen says whether its tap found a control, and the summary names the misses",
		{
			id = prefix .. "each tapped screen says whether its tap found a control, and the summary names the misses",
			run = function(test: Verify.Context)
				local screens: { Look.Screen } = {
					{ device = "desktop", label = "1-start" },
					{ device = "desktop", label = "2-shop", tap = "Shop", found = true, target = "Shop" },
					{ device = "desktop", label = "3-buy", tap = "Buy", found = false, problem = "tap" },
				}
				Verify.expect(Look.tapLine(screens[1])):toBe(nil)
				Verify.expect(Look.tapLine(screens[2])):toBe('tap "Shop": tapped the control "Shop"')
				Verify.expect(Look.tapLine(screens[3])):toBe('tap "Buy": no control was tapped')
				Verify.expect(Look.tapSummary(screens)):toBe('taps: 1 found their control, 1 did not: desktop "Buy"')
				Verify.expect(Look.tapSummary({ screens[1] })):toBe(nil)
			end,
		}
	)
	harness:case(prefix .. "taps become steps that wait after each tap", {
		id = prefix .. "taps become steps that wait after each tap",
		run = function(test: Verify.Context)
			local steps = Look.parseSteps({ "Shop", "Buy" }, 2)
			Verify.expect(#steps):toBe(2)
			Verify.expect(steps[2].tap):toBe("Buy")
			Verify.expect(steps[1].wait):toBe(2)
		end,
	})
end

local command: Cli.Command = {
	name = "preview",
	summary = "Play the place in Studio on each device and save screenshots and an outline of each screen.",
	usage = USAGE,
	values = { "device", "tap", "wait", "project", "out", "dump" },
	register = register,
	run = run,
}

return command
