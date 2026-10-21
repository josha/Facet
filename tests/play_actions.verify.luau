--!strict

local Verify = require("../tools/vendor/verify/src/core")
local Actions = require("../tools/play/host/actions")
local QA = require("../tools/play/host/qa")
local Universal = require("../eval/tasks/racing-hub/hidden/universal")
local Play = require("../tools/play/host/play")
local Devices = require("../tools/play/host/devices")

local function fixture(
	mode: string,
	flat: boolean,
	menu: boolean,
	hidden: boolean,
	trap: boolean,
	menuLabel: string?,
	noAction: boolean?,
	dismissLabel: string?,
	actionLabel: string?
): QA.QA
	local page = "hub"
	local more = menuLabel or "More"
	local dismiss = dismissLabel or "Close"
	local action = actionLabel or "Quests"
	local selection = if flat then action else more
	local function info(words: string): QA.Info
		return {
			path = words,
			class = "TextButton",
			label = words,
			rect = { x = 0, y = 0, width = 100, height = 48 },
			selectable = true,
			interactable = true,
			button = true,
		}
	end
	local function find(query: QA.Query): QA.Info?
		for _, word in { action, more, dismiss } do
			local visible = if word == more
				then menu and page == "hub"
				elseif word == dismiss then page ~= "hub"
				else not hidden and (flat and page == "hub" or page == "menu")
			local matches = if query.pattern
				then string.find(string.lower(word), query.pattern) ~= nil
				else string.lower(word) == string.lower(query.exact or query.text or "")
			if visible and matches then
				return info(word)
			end
		end
		return nil
	end
	local function tap(query: QA.Query): (boolean, string)
		local found = find(query)
		if found == nil then
			return false, "missing"
		end
		if found.label == more then
			page = "menu"
			selection = dismiss
		elseif found.label == action then
			if not noAction then
				page = "action"
			end
			selection = dismiss
		elseif not trap then
			page = "hub"
			selection = if flat then action else more
		end
		return true, "activated"
	end
	return (
		{
			device = { mode = mode },
			first = function(_self: QA.QA, query: QA.Query): QA.Info?
				return find(query)
			end,
			waitFor = function(_self: QA.QA, query: QA.Query, _seconds: number?): QA.Info?
				return find(query)
			end,
			texts = function(_self: QA.QA): { string }
				local words = {}
				for _, label in { action, more, dismiss } do
					if find({ exact = string.lower(label) }) then
						table.insert(words, label)
					end
				end
				return words
			end,
			sleep = function(_self: QA.QA, _seconds: number) end,
			reveal = function(_self: QA.QA, query: QA.Query): boolean
				return find(query) ~= nil
			end,
			tap = function(_self: QA.QA, query: QA.Query): (boolean, string)
				return tap(query)
			end,
			press = function(_self: QA.QA, _key: string): (boolean, string)
				return tap({ exact = "close" })
			end,
			selected = function(_self: QA.QA): QA.Info?
				return info(selection)
			end,
			gamepadSelect = function(_self: QA.QA, query: QA.Query): (boolean, string)
				local found = find(query)
				if found then
					selection = found.label
				end
				return found ~= nil, "selection path"
			end,
			gamepadActivate = function(_self: QA.QA, query: QA.Query): (boolean, string)
				return tap(query)
			end,
		} :: unknown
	) :: QA.QA
end

return function(harness: Verify.Harness)
	for _, mode in { "mouse", "touch", "gamepad" } do
		for _, label in { "Home", "01  Overview" } do
			harness:case(
				mode .. " persistent " .. label .. " preserves root dismissal and checks actual reachability",
				function(t)
					local qa = fixture(mode, true, false, false, false)
					local template = assert(qa:first({ exact = "Quests" }))
					local open, child, covered, ambiguous = true, false, false, false
					local rootTaps, dismissTaps, hubTaps, hits, selections, coveredActivations = 0, 0, 0, 0, 0, 0
					local function find(query: QA.Query): QA.Info?
						for _, words in { label, "Shop", "×", "Back", "N / G • HUB", "Close" } do
							local visible = if words == "N / G • HUB"
								then not open
								elseif words == "Back" then covered and not ambiguous
								elseif words == "Close" then ambiguous
								else open
							local normalized = string.lower(words)
							local matches = if query.pattern
								then string.find(normalized, query.pattern) ~= nil
								else normalized == string.lower(query.exact or query.text or "")
							if visible and matches then
								local result = table.clone(template)
								result.label = words
								return result
							end
						end
						return nil
					end
					qa.first = function(_self: QA.QA, query: QA.Query): QA.Info?
						return find(query)
					end
					qa.reveal = function(_self: QA.QA, query: QA.Query): boolean
						return find(query) ~= nil
					end
					local function activate(query: QA.Query): (boolean, string)
						local target = find(query)
						if target == nil then
							return false, "missing"
						end
						if target.label == "Back" then
							covered = false
						elseif covered and mode ~= "gamepad" then
							return false, "control is covered"
						elseif target.label == label then
							if covered then
								coveredActivations += 1
								return true, "background gamepad activation"
							end
							rootTaps += 1
							child = false
						elseif target.label == "N / G • HUB" then
							hubTaps += 1
							open = true
						elseif target.label == "×" or target.label == "Close" then
							dismissTaps += 1
							open = false
						end
						return true, "activated"
					end
					qa.tap = function(_self: QA.QA, query: QA.Query): (boolean, string)
						return activate(query)
					end
					qa.reachable = function(_self: QA.QA, query: QA.Query): (boolean, string)
						hits += 1
						return find(query) ~= nil and not covered, "native hit result"
					end
					qa.gamepadActivate = qa.tap
					qa.gamepadSelect = function(_self: QA.QA, query: QA.Query): (boolean, string)
						selections += 1
						return find(query) ~= nil, "selection route"
					end
					qa.call = function(_self: QA.QA, _command: string, _fields: unknown?): unknown
						return { timedOut = false }
					end
					local navigation = Actions.captureRoot(qa)
					t:expect(assert(navigation.root).exact):toBe(label)
					child = true
					t:expect((Actions.returnToRoot(qa, navigation))):toBe(true)
					t:expect(child):toBe(false)
					t:expect(open):toBe(true)
					t:expect(dismissTaps):toBe(0)
					t:expect(rootTaps):toBe(1)
					local visibleFirst = qa.first
					local visibleReveal = qa.reveal
					local scrolledAway = true
					local scrolledTarget = label
					qa.first = function(self: QA.QA, query: QA.Query): QA.Info?
						if scrolledAway and query.exact == scrolledTarget then
							return nil
						end
						return visibleFirst(self, query)
					end
					qa.reveal = function(self: QA.QA, query: QA.Query): boolean
						if query.exact == scrolledTarget then
							scrolledAway = false
						end
						return visibleReveal(self, query)
					end
					t:expect((Actions.returnToRoot(qa, navigation))):toBe(true)
					t:expect(scrolledAway):toBe(false)
					t:expect(rootTaps):toBe(2)
					scrolledTarget = "Shop"
					scrolledAway = true
					t:expect((Actions.returned(qa, { exact = "Shop", role = "button" }, nil, navigation))):toBe(true)
					t:expect(scrolledAway):toBe(false)
					open = false
					t:expect((Actions.returnToRoot(qa, navigation))):toBe(true)
					t:expect(hubTaps):toBe(1)
					t:expect(rootTaps):toBe(3)
					covered = true
					t:expect((Actions.returned(qa, { exact = "Shop", role = "button" }, nil, navigation))):toBe(false)
					t:expect((Actions.returnToRoot(qa, navigation))):toBe(true)
					t:expect(rootTaps):toBe(4)
					t:expect(dismissTaps):toBe(0)
					t:expect((Actions.returned(qa, { exact = "Shop", role = "button" }, nil, navigation))):toBe(true)
					t:expect(hits > 0 and (if mode == "gamepad" then selections > 0 else selections == 0)):toBe(true)
					ambiguous = true
					local reserved = Actions.captureRoot(qa)
					covered = true
					local recovered, detail = Actions.returnToRoot(qa, reserved)
					t:expect(recovered):toBe(false)
					t:expect(string.find(detail, "ambiguous", 1, true) ~= nil):toBe(true)
					t:expect(dismissTaps):toBe(0)
					t:expect(coveredActivations):toBe(0)
				end
			)
		end
	end
	for _, mode in { "mouse", "touch", "gamepad" } do
		harness:case(mode .. " persistent navigation preserves the compact overflow return path", function(t)
			local qa = fixture(mode, false, true, false, false)
			qa.reachable = function(self: QA.QA, query: QA.Query): (boolean, string)
				return self:first(query) ~= nil, "native hit result"
			end
			local navigation: Actions.Navigation = {
				root = { role = "button", exact = "Home" },
				reserved = { ["×"] = true },
			}
			t:expect((Actions.returned(qa, { role = "button", exact = "Quests" }, nil, navigation))):toBe(true)
			t:expect(qa:first({ exact = "Close" })):toBe(nil)
			t:expect(qa:first({ exact = "More" }) ~= nil):toBe(true)
		end)
	end
	harness:case("QA reachability preserves a native occlusion rejection without activation", function(t)
		local qa = fixture("mouse", true, false, false, false)
		local query: QA.Query = { role = "button", text = "Shop" }
		local created = QA.create(
			(
					{
						session = {},
						probe = "probe",
						outputs = "out",
						captures = "captures",
						scratch = "scratch",
						shots = {},
						log = function(_message: string) end,
					} :: unknown
				) :: QA.Context,
			Devices.get("desktop")
		)
		created.call = function(_self: QA.QA, command: string, fields: unknown?): unknown
			t:expect(command):toBe("reachable")
			t:expect((fields :: { query: QA.Query }).query):toBe(query)
			return { reachable = false, reason = "covered by modal" }
		end
		local reachable, reason = created:reachable(query)
		t:expect(reachable):toBe(false)
		t:expect(reason):toBe("covered by modal")
		t:expect((Actions.returnToRoot(qa))):toBe(true)
	end)
	for _, device in { "desktop", "phone-portrait" } do
		harness:case(device .. " failed reveal never taps a different matching button", function(t)
			local qa = QA.create(
				(
						{
							session = {},
							probe = "probe",
							outputs = "out",
							captures = "captures",
							scratch = "scratch",
							shots = {},
							log = function(_message: string) end,
						} :: unknown
					) :: QA.Context,
				Devices.get(device)
			)
			local commands: { string } = {}
			local revealed = false
			qa.call = function(_self: QA.QA, command: string, _fields: unknown?): unknown
				table.insert(commands, command)
				if command == "reveal" then
					return { revealed = revealed }
				end
				return { tapped = true, activated = true }
			end
			local query: QA.Query = { role = "button", text = "Buy", near = "Selected item" }
			local tapped, reason = qa:tap(query)
			t:expect(tapped):toBe(false)
			t:expect(string.find(reason, "could not be revealed", 1, true) ~= nil):toBe(true)
			t:expect(commands):toEqual({ "reveal" })
			revealed = true
			t:expect((qa:tap(query))):toBe(true)
			t:expect(commands):toEqual({ "reveal", "reveal", "tap" })
		end)
	end
	for _, mode in { "mouse", "touch" } do
		harness:case(mode .. " input preparation sends no selection or key input", function(t)
			local qa = fixture(mode, true, false, false, false)
			qa.autoSelect = function(_self: QA.QA): QA.Info?
				error("unexpected selection", 0)
			end
			qa.press = function(_self: QA.QA, _key: string): (boolean, string)
				error("unexpected key", 0)
			end
			t:expect((Actions.prepareInput(qa))):toBe(true)
		end)
	end
	harness:case("gamepad preparation selects then sends one directional key without activation", function(t)
		local qa = fixture("gamepad", true, false, false, false)
		local selected, keys = false, 0
		qa.autoSelect = function(self: QA.QA): QA.Info?
			selected = true
			return self:first({ text = "Quests" })
		end
		qa.press = function(_self: QA.QA, key: string): (boolean, string)
			t:expect(selected):toBe(true)
			t:expect(key):toBe("Right")
			keys += 1
			return true, "direction sent"
		end
		t:expect((Actions.prepareInput(qa))):toBe(true)
		t:expect(keys):toBe(1)
		t:expect(qa:first({ text = "Quests" }) ~= nil):toBe(true)
	end)
	harness:case("gamepad preparation permits no selectable controls and propagates key failure", function(t)
		local qa = fixture("gamepad", true, false, false, false)
		local keys = 0
		qa.autoSelect = function(_self: QA.QA): QA.Info?
			return nil
		end
		qa.press = function(_self: QA.QA, _key: string): (boolean, string)
			keys += 1
			return false, "input blocked"
		end
		t:expect((Actions.prepareInput(qa))):toBe(true)
		t:expect(keys):toBe(0)
		qa.autoSelect = function(self: QA.QA): QA.Info?
			return self:first({ text = "Quests" })
		end
		local prepared, detail = Actions.prepareInput(qa)
		t:expect(prepared):toBe(false)
		t:expect(detail):toBe("input blocked")
		t:expect(keys):toBe(1)
	end)
	for _, mode in { "mouse", "gamepad" } do
		for _, outcome in { "recovered", "trapped", "missing" } do
			harness:case(
				mode .. " universal failure cleanup " .. outcome .. " preserves the original failure",
				function(t)
					local action = if mode == "gamepad" and outcome == "recovered" then "Boosts" else "Shop"
					local qa = fixture(mode, true, false, false, outcome == "trapped", nil, nil, "×", action)
					local taps, pads = 0, 0
					local tap, activate, first = qa.tap, qa.gamepadActivate, qa.first
					qa.tap = function(self: QA.QA, query: QA.Query): (boolean, string)
						if query.exact == "×" then
							taps += 1
						end
						return tap(self, query)
					end
					qa.gamepadActivate = function(self: QA.QA, query: QA.Query): (boolean, string)
						if query.exact == "×" then
							pads += 1
						end
						return activate(self, query)
					end
					qa.first = function(self: QA.QA, query: QA.Query): QA.Info?
						if outcome == "missing" and query.exact == "×" then
							return nil
						end
						if action == "Boosts" and string.lower(query.text or query.exact or "") == "shop" then
							local opener = first(self, { text = "Boosts" })
							if opener == nil then
								return nil
							end
							local shop = table.clone(opener)
							shop.label, shop.path = "Shop", "Shop"
							return shop
						end
						return first(self, query)
					end
					local reveal = qa.reveal
					qa.reveal = function(self: QA.QA, query: QA.Query): boolean
						if action == "Boosts" and string.lower(query.text or query.exact or "") == "shop" then
							return self:first(query) ~= nil
						end
						return reveal(self, query)
					end
					qa.dump = function(_self: QA.QA, _screen: string): ()
						error("original offscreen failure", 0)
					end
					qa.call = function(_self: QA.QA, _command: string, _fields: unknown?): unknown
						return { timedOut = false }
					end
					local route: Play.Case? = nil
					for _, candidate in Universal.scenario("racing-hub-slice").sessions[1].cases do
						if candidate.id == "universal/route-universal-" .. string.lower(action) then
							route = candidate
							break
						end
					end
					local chosen = assert(route)
					local host: Verify.CaseHost = {
						name = "universal-cleanup",
						capabilities = {},
						environment = {},
						now = os.clock,
						invoke = function(_request)
							error("unexpected host operation", 0)
						end,
					}
					local report = Verify.runCase({
						name = chosen.id,
						run = function(context)
							chosen.run(qa, context)
						end,
					}, host)
					local body, cleanup = false, false
					for _, failure in report.results[1].failures do
						body = body or string.find(failure.message, "original offscreen failure", 1, true) ~= nil
						cleanup = cleanup or failure.phase == "cleanup"
					end
					t:expect(body):toBe(true)
					t:expect(cleanup):toBe(outcome ~= "recovered")
					local attempts = if outcome == "missing" then 0 elseif outcome == "trapped" then 8 else 1
					t:expect(taps):toBe(if mode == "mouse" then attempts else 0)
					t:expect(pads):toBe(if mode == "gamepad" then attempts else 0)
					t:expect(qa:first({ role = "button", exact = "Close" })):toBe(nil)
					if action == "Boosts" then
						t:expect(assert(qa:selected()).label):toBe("Boosts")
						t:expect((Actions.returned(qa, { role = "button", text = "Shop" }))):toBe(false)
						t:expect((Actions.returned(qa, { role = "button", text = "Boosts" }))):toBe(true)
					end
				end
			)
		end
	end
	for _, mode in { "mouse", "touch", "gamepad" } do
		harness:case(mode .. " return rechecks an outgoing control that disappears before activation", function(t)
			local qa = fixture(mode, true, false, false, false)
			local target = qa:first({ exact = "quests" })
			local present, settles = true, 0
			qa.first = function(_self: QA.QA, query: QA.Query): QA.Info?
				return if present and query.exact == "Close" then target else nil
			end
			qa.tap = function(_self: QA.QA, _query: QA.Query): (boolean, string)
				present = false
				return false, "no visible element matches"
			end
			qa.gamepadActivate = qa.tap
			qa.call = function(_self: QA.QA, _command: string, _fields: unknown?): unknown
				settles += 1
				return { timedOut = false }
			end
			t:expect((Actions.returnToRoot(qa))):toBe(true)
			t:expect(settles):toBe(1)
		end)
	end
	harness:case("return fails when the queried control remains unactivatable", function(t)
		local qa = fixture("mouse", true, false, false, false)
		qa:tap({ exact = "quests" })
		qa.tap = function(_self: QA.QA, _query: QA.Query): (boolean, string)
			return false, "control is covered"
		end
		local returned, detail = Actions.returnToRoot(qa)
		t:expect(returned):toBe(false)
		t:expect(detail):toBe("control is covered")
	end)
	harness:case("return follows Back after an outgoing Close disappears", function(t)
		local qa = fixture("mouse", true, false, false, false)
		local target = qa:first({ exact = "quests" })
		local current, taps = "Close", {}
		qa.first = function(_self: QA.QA, query: QA.Query): QA.Info?
			return if query.exact == current then target else nil
		end
		qa.tap = function(_self: QA.QA, query: QA.Query): (boolean, string)
			table.insert(taps, query.exact)
			if current == "Close" then
				current = "Back"
				return false, "no visible element matches"
			end
			current = ""
			return true, "activated"
		end
		qa.call = function(_self: QA.QA, _command: string, _fields: unknown?): unknown
			return { timedOut = false }
		end
		t:expect((Actions.returnToRoot(qa))):toBe(true)
		t:expect(table.concat(taps, ",")):toBe("Close,Back")
	end)
	for _, timedOut in { false, true } do
		harness:case(
			if timedOut
				then "return fails when native settlement times out"
				else "return attempts are bounded for a trapping control",
			function(t)
				local qa = fixture("mouse", true, false, false, not timedOut)
				qa:tap({ exact = "quests" })
				local attempts = 0
				qa.call = function(_self: QA.QA, _command: string, _fields: unknown?): unknown
					attempts += 1
					return { timedOut = timedOut }
				end
				t:expect((Actions.returnToRoot(qa))):toBe(false)
				t:expect(attempts):toBe(if timedOut then 1 else 8)
			end
		)
	end
	harness:case("text visibility does not scroll or open overflow", function(t)
		local qa = fixture("mouse", false, true, false, false)
		local reveals = 0
		qa.reveal = function(_self: QA.QA, _query: QA.Query): boolean
			reveals += 1
			return true
		end
		t:expect(Actions.reveal(qa, { role = "text", exact = "hidden balance" })):toBe(false)
		t:expect(reveals):toBe(0)
		t:expect(qa:first({ exact = "close" })):toBe(nil)
	end)
	harness:case("an overflow action that leaves the menu unchanged fails", function(t)
		local qa = fixture("mouse", false, true, false, false, nil, true)
		t:expect((Actions.tap(qa, { role = "button", text = "quests" }))):toBe(false)
	end)
	harness:case("a missing return control cannot be supplied by opening overflow", function(t)
		local qa = fixture("mouse", false, true, false, false)
		t:expect(Actions.reveal(qa, { role = "button", exact = "close" })):toBe(false)
		t:expect(qa:first({ exact = "close" })):toBe(nil)
	end)
	harness:case("gamepad focus cannot alias a sibling with the same instance path", function(t)
		local qa = fixture("gamepad", false, true, false, false)
		local wrong = table.clone(qa:first({ exact = "more" }) :: QA.Info)
		wrong.label = "Shop"
		qa.selected = function(_self: QA.QA): QA.Info?
			return wrong
		end
		t:expect((Actions.returned(qa, { role = "button", text = "quests" }))):toBe(false)
	end)
	for _, label in { "Menu", "More actions", "More (3)", "Options" } do
		harness:case("discovers overflow named " .. label, function(t)
			local qa = fixture("mouse", false, true, false, false, label)
			t:expect((Actions.returned(qa, { role = "button", text = "quests" }))):toBe(true)
		end)
	end
	for _, mode in { "mouse", "touch", "gamepad" } do
		for _, flat in { true, false } do
			harness:case(mode .. (if flat then " flat dock" else " overflow menu"), function(t)
				local qa = fixture(mode, flat, not flat, false, false)
				local query: QA.Query = { role = "button", text = "quests" }
				t:expect((Actions.tap(qa, query))):toBe(true)
				t:expect((qa:tap({ exact = "close" }))):toBe(true)
				t:expect((Actions.returned(qa, query))):toBe(true)
				t:expect(qa:first({ exact = "close" })):toBe(nil)
			end)
		end
		harness:case(mode .. " hidden action without overflow fails", function(t)
			local qa = fixture(mode, false, false, true, false)
			local query: QA.Query = { role = "button", text = "quests" }
			t:expect(Actions.reveal(qa, query)):toBe(false)
			t:expect((Actions.returned(qa, query))):toBe(false)
		end)
		harness:case(mode .. " overflow without the action fails", function(t)
			local qa = fixture(mode, false, true, true, false)
			t:expect((Actions.returned(qa, { role = "button", text = "quests" }))):toBe(false)
		end)
		harness:case(mode .. " trapping overflow fails", function(t)
			local qa = fixture(mode, false, true, false, true)
			t:expect((Actions.returned(qa, { role = "button", text = "quests" }))):toBe(false)
		end)
		harness:case(mode .. " stale menu after action fails", function(t)
			local qa = fixture(mode, false, true, false, false)
			local query: QA.Query = { role = "button", text = "quests" }
			t:expect(Actions.reveal(qa, query)):toBe(true)
			t:expect((Actions.returned(qa, query))):toBe(false)
		end)
	end
end
