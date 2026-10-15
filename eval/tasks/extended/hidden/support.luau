--!strict

local Play = require("../../../../tools/play/host/play")
local fs = require("@std/fs")
local process = require("@std/process")
local Check = require("../../../../tools/play/host/check")
local QA = require("../../../../tools/play/host/qa")
local Core = require("../../../../tools/vendor/verify/src/core")
local Audit = require("../../../../tools/vendor/verify/src/roblox/ui-audit")
local Lute = require("../../../../tools/vendor/verify/src/lute")
local function state(qa: QA.QA, command: string?, args: unknown?): unknown
	return qa:admin("extended", { command = command or "state", args = args })
end
local function tap(qa: QA.QA, context: Core.Context, words: string, near: string?)
	Check.tap(qa, context, { role = "button", exact = string.lower(words), near = near }, words)
end
local function target(qa: QA.QA, context: Core.Context, words: string): QA.Info
	qa:reveal({ role = "button", exact = string.lower(words) })
	local found = Check.visible(qa, context, { role = "button", exact = string.lower(words) }, words)
	local r = found.rect
	Check.that(
		context,
		r.x >= 0 and r.y >= 0 and r.x + r.width <= qa.viewport.width + 1 and r.y + r.height <= qa.viewport.height + 1,
		words .. " fits the viewport"
	)
	if qa.device.mode == "touch" then
		Check.that(context, r.width >= 44 and r.height >= 44, words .. " has a touch target")
	elseif qa.device.mode == "gamepad" then
		local ok, detail = qa:gamepadSelect({ role = "button", exact = string.lower(words) })
		Check.that(context, ok, detail)
	end
	return found
end
local function capture(qa: QA.QA, context: Core.Context, screen: string)
	qa:dump(screen)
	qa:capture(screen)
	local output: string? = nil
	for index, word in process.args do
		if word == "--outputs" then
			output = process.args[index + 1]
		end
	end
	if output ~= nil then
		local dump = Audit.decode(
			Lute.parse(fs.readFileToString(output .. "/dumps/" .. qa.device.id .. "/" .. screen .. ".json"))
		)
		for _, element in dump.elements do
			if element.visible and element.text ~= nil and element.text.content ~= "" then
				local text = element.text
				Check.that(context, text.fits ~= false, "visible text fits: " .. text.content)
			end
		end
	end
end
local function back(qa: QA.QA, context: Core.Context, opener: string)
	if qa.device.mode == "gamepad" then
		local ok, detail = qa:press("Backspace")
		Check.that(context, ok, detail)
		local selected = qa:selected()
		Check.that(
			context,
			selected ~= nil and string.lower(selected.label) == string.lower(opener),
			"Back restores " .. opener .. " selection"
		)
	else
		tap(qa, context, "Close")
	end
end
local function extend(base: Play.Scenario, added: { Play.Case }): Play.Scenario
	local scenario: Play.Scenario = { sessions = {} }
	for _, session in base.sessions do
		local cases = table.clone(session.cases)
		for _, case in added do
			table.insert(cases, case)
		end
		table.insert(scenario.sessions, { device = session.device, cases = cases })
	end
	return scenario
end
return { state = state, tap = tap, target = target, capture = capture, back = back, extend = extend }
