--!strict

local Verify = require("../tools/vendor/verify/src/core")
local Actions = require("../tools/play/host/actions")
local QA = require("../tools/play/host/qa")

local function fixture(
	mode: string,
	flat: boolean,
	menu: boolean,
	hidden: boolean,
	trap: boolean,
	menuLabel: string?,
	noAction: boolean?
): QA.QA
	local page = "hub"
	local more = menuLabel or "More"
	local selection = if flat then "Quests" else more
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
		for _, word in { "Quests", more, "Close" } do
			local visible = if word == more
				then menu and page == "hub"
				elseif word == "Close" then page ~= "hub"
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
			selection = "Close"
		elseif found.label == "Quests" then
			if not noAction then
				page = "action"
			end
			selection = "Close"
		elseif not trap then
			page = "hub"
			selection = if flat then "Quests" else more
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
				for _, label in { "Quests", more, "Close" } do
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
		} :: unknown
	) :: QA.QA
end

return function(harness: Verify.Harness)
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
