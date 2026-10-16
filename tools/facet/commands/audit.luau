--!strict

local json = require("@std/json")
local Case = require("../lib/case")
local Cli = require("../lib/cli")
local Audit = require("../../vendor/verify/src/roblox/ui-audit")
local Look = require("../lib/look")

local USAGE = [[usage: lute run tools/facet audit [--device ID]... [--tap TEXT]... [--wait SECONDS]
                                  [--project FILE] [--out DIR] [--keep] [--all]
                                  [--dump FILE --device ID] [--json]

Plays the place in a disposable Roblox Studio on each device, like preview, and
runs the interface audit on each screen. The audit reads the engine geometry and
properties and reports:

  high    text that does not fit or that an ancestor clips, low text contrast,
          controls or text past the screen edge
  medium  content past the safe area, touch targets under 44 points, controls
          that overlap, controls that a gamepad cannot reach, hidden focus
  low     broken selection links, too many text sizes or spacing values

Each rule prints its fix once per run. Every screen keeps its score and findings.

  --device ID     desktop, phone-portrait, phone-landscape, tablet or console.
                  Repeat it. The default is desktop, phone-portrait and console.
  --tap TEXT      Tap the control that shows TEXT, then audit the next screen.
  --all           Print low-severity findings too.
  --dump FILE     Audit a saved dump for one --device only. No Studio starts.

The other options are the same as for preview. The exit code is 1 when a
screen has a high-severity finding.]]

local SEVERITY_RANK: { [string]: number } = { high = 1, medium = 2, low = 3 }

local FIXES: { [string]: string } = {
	["text-truncated"] = 'The text does not fit its element. Give the Text control wrap = true, or more room (a stack with width = "fill", a larger panel), or a shorter label. Do not set TextScaled.',
	["text-clipped"] = 'A parent with ClipsDescendants cuts the text. Let the container grow (AutomaticSize or height = "hug") or put the content in a ScrollView.',
	["contrast-low"] = "The text color is too close to its background. Use a textRole and the theme surfaces instead of literal colors, or an appearance that the theme pairs with readable text.",
	["offscreen"] = 'The element extends past the screen. Use width = "fill" with maxWidth, an adaptive control, or a ScrollView for long content.',
	["outside-safe-area"] = "The element is under the notch or the home bar. Put HUD content in UI.Composition regions or a UI.Screen, which keep the safe insets.",
	["touch-target-small"] = "A control is smaller than 44 points on a touch device. Use a Facet control with a controlSize (the target floor keeps 44 points on touch), or a larger Size.",
	["interactive-overlap"] = "Two controls overlap and neither contains the other, so a tap can hit the wrong one. Lay them out in a stack or a grid instead of absolute positions.",
	["gamepad-unreachable"] = "A gamepad cannot select this control. Use Facet controls (they are Selectable), keep each panel inside one Sheet, Dialog or Popover, and do not set Selectable = false on a control that the player uses.",
	["focus-hidden"] = "On a gamepad device the selected control shows no focus. Keep the app focus ring (app.mount adds UI.focusRing) and do not replace SelectionImageObject with an invisible object.",
	["selection-link-broken"] = "A NextSelection link names a hidden or unselectable control. Remove the manual NextSelection links; the controls and the engine selection find the neighbors.",
	["press-feedback-missing"] = "A button shows no hover or press state. Use UI.Button, which the theme styles for each state.",
	["type-scale"] = "The screen uses many text sizes. Use textRole (title, heading, body, caption, label) instead of literal TextSize values.",
	["spacing-scale"] = "The screen uses many spacing values. Use the gap and padding steps (xs, s, m, l, xl) instead of pixel values.",
	["instance-count"] = "The screen has many interface instances. Use VirtualList or VirtualGrid for long collections, so that only visible rows mount.",
}

local function report(
	device: string,
	label: string,
	loaded: Audit.Dump,
	all: boolean,
	fixes: { [string]: boolean }?
): (string, boolean, number)
	local result = Look.audit(loaded, device)
	local texts: { [string]: string } = {}
	for _, element in loaded.elements do
		local text = element.text
		if text ~= nil and text.content ~= "" and texts[element.path] == nil then
			texts[element.path] = string.sub((string.gsub(text.content, "%s+", " ")), 1, 40)
		end
	end
	local groups: { [string]: { Audit.Violation } } = {}
	local order: { string } = {}
	local high = false
	for _, violation in result.violations do
		if violation.severity == "high" then
			high = true
		end
		if groups[violation.rule] == nil then
			groups[violation.rule] = {}
			table.insert(order, violation.rule)
		end
		table.insert(groups[violation.rule], violation)
	end
	table.sort(order, function(left: string, right: string): boolean
		local a = SEVERITY_RANK[groups[left][1].severity] or 4
		local b = SEVERITY_RANK[groups[right][1].severity] or 4
		if a ~= b then
			return a < b
		end
		return left < right
	end)
	local lines = { ("%s %s: score %d"):format(device, label, math.floor(result.score)) }
	for _, rule in order do
		local group = groups[rule]
		local severity = group[1].severity
		if severity == "low" and not all then
			continue
		end
		local fix = if fixes ~= nil and fixes[rule] then "" else FIXES[rule] or ""
		table.insert(lines, ("  %s %s (%d)%s"):format(severity, rule, #group, if fix == "" then "" else ": " .. fix))
		if fixes ~= nil then
			fixes[rule] = true
		end
		for index, violation in group do
			if index > 3 then
				table.insert(lines, ("      ... %d more"):format(#group - 3))
				break
			end
			local name = string.match(violation.path, "([^%.]+%.[^%.]+)$") or violation.path
			table.insert(
				lines,
				("      %s%s: %s"):format(
					name,
					if texts[violation.path] then (' "%s"'):format(texts[violation.path]) else "",
					violation.detail
				)
			)
		end
	end
	if #lines == 1 then
		table.insert(lines, "  no finding")
	end
	return table.concat(lines, "\n"), high, result.score
end

local function run(invocation: Cli.Invocation): number
	local unknown = Cli.unknownFlags(invocation, { "device", "tap", "wait", "project", "out", "keep", "dump", "all" })
	if unknown ~= nil or #invocation.positional > 0 then
		if unknown ~= nil then
			print("facet audit: unknown flags " .. unknown)
		end
		print(USAGE)
		return 2
	end
	local devices: { string } = invocation.repeated.device or { "desktop", "phone-portrait", "console" }
	for _, device in devices do
		if table.find(Look.DEVICES, device) == nil then
			print(("facet audit: unknown device %s; use %s"):format(device, table.concat(Look.DEVICES, ", ")))
			return 2
		end
	end
	local all = Cli.switch(invocation, "all")
	local saved = Cli.flag(invocation, "dump")
	if saved ~= nil then
		if #devices ~= 1 or invocation.repeated.device == nil then
			print("facet audit: --dump needs exactly one --device")
			return 2
		end
		local loaded = Look.load(saved)
		local text, high = report(devices[1], saved, loaded, all)
		Cli.emit(invocation, (Look.audit(loaded, devices[1]) :: unknown) :: json.Value, text)
		return if high then 1 else 0
	end
	local result = Look.run({
		project = Cli.flag(invocation, "project") or "default.project.json",
		devices = devices,
		steps = Look.parseSteps(invocation.repeated.tap or {}, tonumber(Cli.flag(invocation, "wait") or "")),
		out = Cli.flag(invocation, "out") or "artifacts/facet-audit",
		keep = Cli.switch(invocation, "keep"),
	})
	if result.problem ~= nil then
		print("facet audit: " .. (result.problem :: string))
		return 1
	end
	local texts: { string } = {}
	local scores: { json.Value } = {}
	local failed = false
	local fixes: { [string]: boolean } = {}
	for _, screen in result.screens do
		if screen.dump == nil then
			table.insert(texts, ("%s %s: no dump: %s"):format(screen.device, screen.label, tostring(screen.problem)))
			failed = true
			continue
		end
		local text, high, score = report(screen.device, screen.label, Look.load(screen.dump :: string), all, fixes)
		if screen.problem ~= nil then
			text ..= "\n  problem: " .. (screen.problem :: string)
		end
		table.insert(texts, text)
		local entry: json.Value = { device = screen.device, label = screen.label, score = score, high = high }
		table.insert(scores, entry)
		failed = failed or high
	end
	local value: json.Value = { out = result.out, screens = scores }
	Cli.emit(invocation, value, table.concat(texts, "\n\n"))
	return if failed then 1 else 0
end

local function cases(): { Case.Case }
	return {
		{
			name = "repeated audit rules keep their findings and scores but print their fix once",
			run = function()
				local fixes: { [string]: boolean } = {}
				local loaded = Look.decode(Look.sample(true))
				local first, firstHigh, firstScore = report("desktop", "first", loaded, true, fixes)
				local second, secondHigh, secondScore = report("desktop", "second", loaded, true, fixes)
				local _, rules = string.gsub(first, "\n  [a-z]+ [a-z%-]+ %(%d+%)", "")
				local _, repeated = string.gsub(second, "\n  [a-z]+ [a-z%-]+ %(%d+%)", "")
				return Case.first(
					Case.expect(rules > 0 and rules == repeated, "findings were lost"),
					Case.equal(firstHigh, secondHigh, "high severity"),
					Case.equal(firstScore, secondScore, "score"),
					Case.expect(#second < #first, "the fixes were repeated")
				)
			end,
		},
		{
			name = "a saved dump is audited for its device without Studio",
			run = function()
				local text, _, score = report("desktop", "shop", Look.decode(Look.sample(false)), true)
				return Case.first(
					Case.expect(string.find(text, "desktop shop: score", 1, true) ~= nil, "the header is missing"),
					Case.expect(score >= 0 and score <= 100, "the score is out of range")
				)
			end,
		},
		{
			name = "the weak reference reports findings that the strong reference does not",
			run = function()
				local _, _, strong = report("desktop", "shop", Look.decode(Look.sample(false)), true)
				local weakText, _, weak = report("desktop", "shop", Look.decode(Look.sample(true)), true)
				return Case.first(
					Case.expect(weak < strong, ("weak %d is not below strong %d"):format(weak, strong)),
					Case.expect(
						string.find(weakText, "no finding", 1, true) == nil,
						"the weak reference has no finding"
					)
				)
			end,
		},
		{
			name = "low findings are hidden unless --all is given",
			run = function()
				local quiet = report("desktop", "shop", Look.decode(Look.sample(true)), false)
				local loud = report("desktop", "shop", Look.decode(Look.sample(true)), true)
				return Case.expect(#loud >= #quiet, "the full report is shorter than the quiet one")
			end,
		},
	}
end

local command: Cli.Command = {
	name = "audit",
	summary = "Play the place in Studio on each device and report interface problems on each screen.",
	usage = USAGE,
	values = { "device", "tap", "wait", "project", "out", "dump" },
	cases = cases,
	run = run,
}

return command
