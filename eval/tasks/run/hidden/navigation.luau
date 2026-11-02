--!strict

local fs = require("@std/fs")
local process = require("@std/process")
local Audit = require("../../../../tools/vendor/verify/src/roblox/ui-audit")
local Core = require("../../../../tools/vendor/verify/src/core")
local Lute = require("../../../../tools/vendor/verify/src/lute")
local Actions = require("../../../../tools/play/host/actions")
local Check = require("../../../../tools/play/host/check")
local Play = require("../../../../tools/play/host/play")
local QA = require("../../../../tools/play/host/qa")
local Space = require("../../../../tools/play/host/space")

local routes = {
	{ "shop", "Shop", "Store" },
	{ "garage", "Garage", "Karts" },
	{ "inventory", "Inventory", "Parts" },
	{ "drivers", "Drivers", "Driver" },
	{ "crates", "Crates", "Crate" },
	{ "daily-rewards", "Daily Rewards", "Daily", "Rewards" },
	{ "codes", "Codes", "Redeem" },
	{ "settings", "Settings", "Options" },
	{ "boosts", "Boosts", "Boost" },
	{ "quests", "Quests", "Missions" },
	{ "offer", "Offer", "Offers" },
	{ "play", "Play", "Race" },
	{ "livery", "Livery", "Customize" },
	{ "track-vote", "Track Vote", "Vote" },
	{ "quick-chat", "Quick Chat", "Chat" },
	{ "upgrades", "Upgrades", "Upgrade" },
	{ "party", "Party", "Friends" },
	{ "tutorial", "Tutorial", "Help" },
}

local function signature(qa: QA.QA): string
	local values = qa:texts()
	for index, value in values do
		values[index] = string.gsub(string.lower(value), "%d+", "#")
	end
	table.sort(values)
	return table.concat(values, "\n")
end

local function stability(qa: QA.QA, context: Core.Context, screen: string)
	local actions: { [string]: boolean } = {}
	for _, action in qa:find({ role = "button" }, 1000) do
		if action.interactable then
			actions[action.path] = true
		end
	end
	qa:call("frameStability", { action = "begin" })
	context:defer(function()
		qa:call("frameStability", { action = "end" })
	end)
	qa:sleep(2)
	local observed = qa:call("frameStability", { action = "end" })
	context:attach(screen .. "-idle-geometry", "application/json", Lute.encode(observed))
	Check.that(context, Check.number(observed, "frames") >= 30, "idle geometry has at least 30 rendered frames")
	local faults = Check.field(observed, "faults")
	assert(type(faults) == "table", "idle geometry needs native observations")
	for _, fault in faults :: { unknown } do
		local path = Check.field(fault, "path")
		assert(type(path) == "string", "idle geometry needs an object path")
		local object = string.gsub(path, "#%d+$", "")
		Check.that(context, actions[object] ~= true, "idle action geometry moved: " .. object)
	end
end

local function observe(qa: QA.QA, context: Core.Context, screen: string)
	qa:dump(screen)
	qa:capture("navigation-" .. screen)
	local output: string? = nil
	for index, word in process.args do
		if word == "--outputs" then
			output = process.args[index + 1]
		end
	end
	assert(output, "navigation observation needs --outputs")
	local dump =
		Audit.decode(Lute.parse(fs.readFileToString(output .. "/dumps/" .. qa.device.id .. "/" .. screen .. ".json")))
	local audit = Audit.analyze(dump, { touch = qa.device.mode == "touch", gamepad = qa.device.mode == "gamepad" })
	context:attach(screen .. "-audit", "application/json", Lute.encode(audit))
	for _, rule in
		{
			"text-truncated",
			"text-clipped",
			"contrast-low",
			"offscreen",
			"outside-safe-area",
			"touch-target-small",
			"interactive-overlap",
			"focus-hidden",
		}
	do
		local summary = audit.rules[rule]
		Check.that(context, summary == nil or summary.count == 0, screen .. ": " .. rule)
	end
	Check.that(context, Space.textClear(dump), "text does not overlap")
	Check.that(context, Space.safeContent(dump), "content clears core UI and cutouts")
	Check.that(context, Space.visibleScrimsCover(dump), "visible scrims cover the screen")
	Check.that(context, Space.selectionValid(dump), "selection is valid")
	for _, element in dump.elements do
		if element.visible and element.text ~= nil and element.text.content ~= "" then
			Check.that(context, element.text.size >= 14, "visible text has a readable size")
		end
	end
	if qa.device.mode == "touch" then
		local controls = qa:call("touchControls")
		Check.that(context, Check.field(controls, "available") == true, "native touch controls are observable")
		local raw = Check.field(controls, "rectangles")
		assert(type(raw) == "table", "native touch rectangles are required")
		local rectangles: { Space.TouchRect } = {}
		for _, item in raw :: { unknown } do
			local path = Check.field(item, "path")
			table.insert(rectangles, {
				path = if type(path) == "string" then path else nil,
				x = Check.number(item, "rect", "x"),
				y = Check.number(item, "rect", "y"),
				width = Check.number(item, "rect", "width"),
				height = Check.number(item, "rect", "height"),
			})
		end
		context:attach(screen .. "-touch-controls", "application/json", Lute.encode(controls))
		Check.that(context, Space.touchControlsClear(dump, rectangles), "content clears actual touch controls")
	end
end

local scenario: Play.Scenario = { sessions = {} }
for _, device in { "desktop", "phone-portrait", "phone-landscape", "tablet", "console" } do
	local cases: { Play.Case } = {}
	for _, route in routes do
		local screen = route[1]
		table.insert(cases, {
			id = "navigation/" .. screen,
			tier = "universal" :: "universal",
			screen = screen,
			shot = "navigation-" .. screen,
			run = function(qa, context)
				local root = Actions.captureRoot(qa)
				context:defer(function()
					local recovered, detail = Actions.returnToRoot(qa, root)
					Check.that(context, recovered, "return after " .. screen .. ": " .. detail)
				end)
				local target: QA.Query? = nil
				for index = 2, #route do
					local candidate: QA.Query = { role = "button", text = string.lower(route[index]) }
					if Actions.reveal(qa, candidate) then
						target = candidate
						break
					end
				end
				Check.that(context, target ~= nil, "a player can discover " .. screen)
				local before = signature(qa)
				Check.tap(qa, context, target :: QA.Query, "open " .. screen)
				local settled = qa:call("perf", { action = "settle", quiet = 0.1, limit = 20 })
				Check.that(context, Check.field(settled, "timedOut") == false, screen .. " settles")
				Check.that(
					context,
					signature(qa) ~= before,
					screen .. " changes visible content beyond a running counter"
				)
				stability(qa, context, screen)
				observe(qa, context, screen)
				local returned, detail = Actions.returnToRoot(qa, root)
				Check.that(context, returned, "return from " .. screen .. ": " .. detail)
				local reachable, reason = Actions.returned(qa, target :: QA.Query, nil, root)
				Check.that(context, reachable, "restore the opener: " .. reason)
			end,
		})
	end
	table.insert(scenario.sessions, { device = device, cases = cases })
end

Play.main(scenario, debug.info(1, "s"))
