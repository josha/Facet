--!strict

local fs = require("@std/fs")
local Audit = require("../../vendor/verify/src/roblox/ui-audit")
local HudView = require("../../studio/live/hud_view")
local Devices = require("../../play/host/devices")
local Files = require("./files")
local Encoding = require("./encoding")
local Play = require("../../play/host/play")
local QA = require("../../play/host/qa")
local Wire = require("../../vendor/verify/src/lute/wire")
local Json = require("./json")

export type Step = { tap: string?, wait: number? }

export type Screen = {
	device: string,
	label: string,
	png: string?,
	dump: string?,
	problem: string?,
	tap: string?,
	found: boolean?,
	target: string?,
}

export type Result = { screens: { Screen }, problem: string?, out: string, log: { string } }

export type Options = {
	project: string,
	devices: { string },
	steps: { Step },
	out: string,
	keep: boolean?,
	basePlace: string?,
}

export type Line = { text: string, y: number, x: number }

local Look = {}

function Look.presentationProblems(dump: Audit.Dump): { Audit.Violation }
	local problems: { Audit.Violation } = {}
	for _, element in dump.elements do
		if not element.visible or not element.selectionGroup or not string.match(element.path, "%.SheetPanel$") then
			continue
		end
		local root = dump.roots[element.root]
		local room = if root
			then root.rect
			else { x = 0, y = 0, width = dump.screen.width, height = dump.screen.height }
		local rect = element.rect
		if
			rect.width <= 0
			or rect.height <= 0
			or rect.x < room.x - 1
			or rect.y < room.y - 1
			or rect.x + rect.width > room.x + room.width + 1
			or rect.y + rect.height > room.y + room.height + 1
		then
			local problem: Audit.Violation = {
				rule = "modal-presentation",
				severity = "high",
				path = element.path,
				detail = "the Sheet has not entered the player viewport",
			}
			table.insert(problems, problem)
		end
	end
	return problems
end

Look.DEVICES = (function(): { string }
	local ids: { string } = {}
	for _, device in Devices.list do
		table.insert(ids, device.id)
	end
	return ids
end)()

function Look.parseSteps(taps: { string }, wait: number?): { Step }
	local steps: { Step } = {}
	for _, text in taps do
		table.insert(steps, { tap = text, wait = wait })
	end
	return steps
end

local function slug(text: string): string
	local lowered = string.lower((string.gsub(text, "[^%w]+", "-")))
	return string.sub((string.gsub(lowered, "^%-+", "")), 1, 24)
end

function Look.run(options: Options, open: ((Play.HostOptions) -> Play.Host)?): Result
	Encoding.normalize({ "src" })
	local out = Files.absolute(options.out)
	if Files.exists(out) then
		Files.remove(out)
	end
	local createHost: (Play.HostOptions) -> Play.Host = open or Play.open
	local host = createHost({
		workspace = Files.cwd(),
		outputs = out,
		captures = out .. "/captures",
		project = options.project,
		keep = options.keep,
		quiet = true,
		performance = false,
		reusePlay = true,
		basePlace = options.basePlace,
		requireInterface = true,
	})
	local result: Result = { screens = {}, problem = nil, out = out, log = host.lines }
	local timings = host.timings
	local built, problem = host.build()
	if not built then
		result.problem = problem
		return result
	end
	for _, device in options.devices do
		local entered, value = pcall(host.enter, device)
		if not entered then
			table.insert(result.screens, { device = device, label = "start", problem = tostring(value) })
			continue
		end
		local qa = value :: QA.QA
		local function shoot(
			label: string,
			failure: string?,
			tap: { text: string, found: boolean, target: string? }?,
			inline: unknown
		)
			local screen: Screen = { device = device, label = label, problem = failure }
			if tap ~= nil then
				screen.tap = tap.text
				screen.found = tap.found
				screen.target = tap.target
			end
			local started = os.clock()
			local captured, capture = pcall(function(): boolean
				qa:capture(label)
				return true
			end)
			timings.capture = (timings.capture or 0) + os.clock() - started
			if not captured then
				screen.problem = (screen.problem or "") .. " capture: " .. tostring(capture)
			end
			started = os.clock()
			local dumped, dump = pcall(function(): boolean
				if inline ~= nil then
					local text = QA.readDump(inline, function(command, fields)
						return qa:call(command, fields)
					end)
					Look.decode(text)
					local directory = Files.join(out, "dumps", device)
					Files.makeDirectory(directory)
					Files.write(Files.join(directory, label .. ".json"), text)
				else
					qa:dump(label)
				end
				return true
			end)
			timings.dump = (timings.dump or 0) + os.clock() - started
			if not dumped then
				screen.problem = (screen.problem or "") .. " dump: " .. tostring(dump)
			end
			local png = ("%s/captures/%s/%s.png"):format(out, device, label)
			local json = ("%s/dumps/%s/%s.json"):format(out, device, label)
			screen.png = if fs.exists(png) then png else nil
			screen.dump = if fs.exists(json) then json else nil
			table.insert(result.screens, screen)
		end
		shoot("1-start", qa.mountProblem)
		if qa.mountProblem ~= nil then
			continue
		end
		for index, step in options.steps do
			local started = os.clock()
			local failure: string? = nil
			local tapped: { text: string, found: boolean, target: string? }? = nil
			local text = step.tap
			local inline: unknown = nil
			if text ~= nil then
				local answered, response = pcall(qa.call, qa, "preview", {
					query = { text = text },
					mode = Devices.get(device).mode,
					wait = step.wait,
					device = device,
					input = Devices.get(device).input,
				})
				local fields: { [string]: unknown } = if answered and type(response) == "table"
					then response :: { [string]: unknown }
					else {}
				local tap: { [string]: unknown } = if type(fields.tap) == "table"
					then fields.tap :: { [string]: unknown }
					else { reason = tostring(response) }
				local info: { [string]: unknown } = if type(tap.info) == "table"
					then tap.info :: { [string]: unknown }
					else {}
				local ok = tap.tapped == true and tap.activated ~= false
				tapped = { text = text, found = ok, target = if ok then tostring(info.label or text) else nil }
				if not ok then
					failure = ("tap %q: %s"):format(text, tostring(tap.reason or "control did not respond"))
				end
				if fields.settled ~= true then
					failure = (failure or "") .. " interface did not settle"
				end
				inline = fields.dump
				if inline ~= nil then
					local presented, reason = pcall(function()
						local deadline = os.clock() + 20
						while true do
							local encoded = QA.readDump(inline, function(command, values)
								return qa:call(command, values)
							end)
							inline = encoded
							if #Look.presentationProblems(Look.decode(encoded)) == 0 then
								break
							end
							local remaining = deadline - os.clock()
							assert(remaining > 0, "Sheet presentation did not enter the player viewport")
							qa:call("perf", { action = "settle", quiet = 0.3, limit = remaining, compareLegacy = true })
							inline =
								qa:call("dump", { inline = true, device = device, input = Devices.get(device).input })
						end
					end)
					if not presented then
						failure = (failure or "") .. " presentation: " .. tostring(reason)
					end
				end
			elseif step.wait ~= nil then
				qa:sleep(step.wait)
			else
				local settled = qa:call("perf", { action = "settle", quiet = 0.1, limit = 20 })
				if type(settled) ~= "table" or (settled :: { [string]: unknown }).timedOut ~= false then
					failure = (failure or "") .. " interface did not settle"
				end
			end
			timings.tap = (timings.tap or 0) + os.clock() - started
			shoot(("%d-%s"):format(index + 1, slug(text or "wait")), failure, tapped, inline)
			if failure ~= nil then
				break
			end
		end
	end
	host.close()
	Files.write(Files.join(out, "timings.json"), Json.encode(timings))
	return result
end

function Look.tapLine(screen: Screen): string?
	local text = screen.tap
	if text == nil then
		return nil
	end
	if screen.found then
		return ("tap %q: tapped the control %q"):format(text, screen.target or text)
	end
	return ("tap %q: no control was tapped"):format(text)
end

function Look.tapSummary(screens: { Screen }): string?
	local found = 0
	local missed: { string } = {}
	for _, screen in screens do
		if screen.tap ~= nil then
			if screen.found then
				found += 1
			else
				table.insert(missed, ("%s %q"):format(screen.device, screen.tap :: string))
			end
		end
	end
	if found == 0 and #missed == 0 then
		return nil
	end
	if #missed == 0 then
		return ("taps: all %d found their control"):format(found)
	end
	return ("taps: %d found their control, %d did not: %s"):format(found, #missed, table.concat(missed, ", "))
end

function Look.decode(text: string): Audit.Dump
	return Audit.decode(Wire.parse(text))
end

function Look.load(path: string): Audit.Dump
	return Look.decode(Files.read(path))
end

function Look.sample(weak: boolean): string
	local dark = { r = 0.1, g = 0.1, b = 0.12 }
	local white = { r = 1, g = 1, b = 1 }
	local blue = { r = 0.2, g = 0.4, b = 0.9 }
	local elements: { string } = {}
	local function add(
		class: string,
		name: string,
		parent: number?,
		rect: { number },
		paint: typeof(dark),
		text: string?,
		bounds: { number }?,
		ink: typeof(dark)?
	)
		local index = #elements + 1
		local fields = {
			('"index":%d'):format(index),
			('"root":1,"class":"%s","path":"PlayerGui.Sample.%s"'):format(class, name),
			('"rect":{"x":%d,"y":%d,"width":%d,"height":%d}'):format(rect[1], rect[2], rect[3], rect[4]),
			('"background":{"color":{"r":%g,"g":%g,"b":%g},"transparency":0}'):format(paint.r, paint.g, paint.b),
		}
		if parent ~= nil then
			table.insert(fields, ('"parent":%d'):format(parent))
		end
		if class == "TextButton" then
			table.insert(fields, '"interactive":true,"selectable":true,"active":true')
		end
		if text ~= nil and bounds ~= nil and ink ~= nil then
			table.insert(
				fields,
				('"text":{"content":"%s","size":20,"bounds":{"width":%d,"height":%d},"fits":%s,"color":{"r":%g,"g":%g,"b":%g}}'):format(
					text,
					bounds[1],
					bounds[2],
					if bounds[1] <= rect[3] then "true" else "false",
					ink.r,
					ink.g,
					ink.b
				)
			)
		end
		table.insert(elements, "{" .. table.concat(fields, ",") .. "}")
	end
	add("Frame", "Panel", nil, { 660, 240, 600, 560 }, dark)
	add(
		"TextLabel",
		"Title",
		1,
		{ 680, 260, 560, 40 },
		dark,
		if weak then "Legendary Collection Bundle Of The Season" else "Shop",
		if weak then { 640, 24 } else { 60, 24 },
		white
	)
	for row, item in { "Iron Sword", "Crystal Blade", "Speed Coil" } do
		local y = 220 + row * 120
		add("TextLabel", item .. "Name", 1, { 680, y, 300, 30 }, dark, item, { 120, 24 }, white)
		add("TextLabel", item .. "Price", 1, { 680, y + 36, 300, 24 }, dark, "250 Coins", { 90, 20 }, white)
		add(
			"TextButton",
			item .. "Buy",
			1,
			{ 1100, y, 120, 48 },
			blue,
			"Buy",
			{ 40, 24 },
			if weak then { r = 0.25, g = 0.45, b = 0.9 } else white
		)
	end
	return table.concat({
		'{"schemaVersion":1,"truncated":false,',
		'"screen":{"width":1920,"height":1080,"scale":1,"device":"desktop","input":["mouse","keyboard"]},',
		'"roots":[{"index":1,"class":"ScreenGui","path":"PlayerGui.Sample","rect":{"x":0,"y":0,"width":1920,"height":1080}}],',
		'"elements":[',
		table.concat(elements, ","),
		"]}",
	})
end

function Look.outline(dump: Audit.Dump, limit: number): { string }
	local lines: { Line } = {}
	for _, element in dump.elements do
		if not element.visible or element.rect.width <= 0 or element.rect.height <= 0 then
			continue
		end
		local text = element.text
		local content = if text ~= nil then string.gsub(text.content, "%s+", " ") else ""
		if content == "" and not element.interactive then
			continue
		end
		local rect = element.rect
		local flags: { string } = {}
		if element.interactive then
			table.insert(flags, "button")
		end
		if element.selectable then
			table.insert(flags, "selectable")
		end
		if text ~= nil and text.fits == false then
			table.insert(flags, "TEXT DOES NOT FIT")
		end
		local screenSize = dump.screen
		if
			rect.x < 0
			or rect.y < 0
			or rect.x + rect.width > screenSize.width
			or rect.y + rect.height > screenSize.height
		then
			table.insert(flags, "OFFSCREEN")
		end
		table.insert(lines, {
			y = rect.y,
			x = rect.x,
			text = ("%-12s %-30s at %4d,%-4d %4dx%-4d %s"):format(
				element.class,
				'"' .. string.sub(content, 1, 28) .. '"',
				math.floor(rect.x),
				math.floor(rect.y),
				math.floor(rect.width),
				math.floor(rect.height),
				table.concat(flags, " ")
			),
		})
	end
	table.sort(lines, function(left: Line, right: Line): boolean
		if math.abs(left.y - right.y) > 4 then
			return left.y < right.y
		end
		return left.x < right.x
	end)
	local result: { string } = {}
	for index, line in lines do
		if index > limit then
			table.insert(result, ("... %d more"):format(#lines - limit))
			break
		end
		table.insert(result, line.text)
	end
	return result
end

function Look.audit(dump: Audit.Dump, device: string): Audit.Report
	local known = Devices.get(device)
	local report = Audit.analyze(dump, {
		touch = table.find(known.input, "touch") ~= nil,
		gamepad = table.find(known.input, "gamepad") ~= nil,
	})
	local problems = Look.presentationProblems(dump)
	for _, problem in problems do
		table.insert(report.violations, problem)
	end
	if #problems > 0 then
		local penalty = #problems * report.options.weights.high
		report.rules["modal-presentation"] = { count = #problems, severity = "high", penalty = penalty }
		report.score = math.max(0, report.score - penalty)
	end
	local zones: { HudView.Element } = {}
	for _, element in dump.elements do
		table.insert(zones, { path = element.path, rect = element.rect, visible = element.visible })
	end
	local covered = HudView.problems(zones)
	for _, problem in covered do
		table.insert(report.violations, problem)
	end
	if #covered > 0 then
		local penalty = #covered * report.options.weights.medium
		report.rules["hud-in-view"] = { count = #covered, severity = "medium", penalty = penalty }
		report.score = math.max(0, report.score - penalty)
	end
	return report
end

return Look
