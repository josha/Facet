--!strict

local QA = require("./qa")

local returns = { "close", "back", "cancel", "skip", "return" }

export type Navigation = { root: QA.Query?, reserved: { [string]: boolean } }

local function semanticRoot(qa: QA.QA, words: { string }): QA.Query?
	for _, word in words do
		local query: QA.Query = { role = "button", pattern = "%f[%a]" .. word .. "%s*$" }
		local found = qa:first(query)
		if found ~= nil then
			return { role = "button", exact = found.label }
		end
	end
	return nil
end

local function captureRoot(qa: QA.QA): Navigation
	local reserved: { [string]: boolean } = {}
	for _, word in { "Close", "Back", "Cancel", "Skip", "Return", "×" } do
		if qa:first({ role = "button", exact = word }) ~= nil then
			reserved[string.lower(word)] = true
		end
	end
	return { root = semanticRoot(qa, { "home", "overview" }), reserved = reserved }
end

local function available(qa: QA.QA, query: QA.Query): (boolean, string)
	if not qa:reveal(query) then
		return false, "the navigation action cannot be revealed"
	end
	local reachable, detail = qa:reachable(query)
	if not reachable then
		return false, detail
	end
	if qa.device.mode == "gamepad" then
		return qa:gamepadSelect(query)
	end
	return true, detail
end

local function prepareInput(qa: QA.QA): (boolean, string)
	if qa.device.mode ~= "gamepad" then
		return true, "no gamepad preparation needed"
	end
	if qa:autoSelect() == nil then
		return true, "no selectable control"
	end
	return qa:press("Right")
end

local function focused(qa: QA.QA, query: QA.Query): boolean
	local selected, target = qa:selected(), qa:first(query)
	if selected == nil or target == nil or selected.path ~= target.path then
		return false
	end
	local label = string.lower((string.gsub(selected.label, "%s+", " ")))
	if query.exact and label ~= string.lower(query.exact) then
		return false
	end
	if query.text and not string.find(label, string.lower(query.text), 1, true) then
		return false
	end
	if query.pattern and not string.find(label, query.pattern) then
		return false
	end
	return selected.rect.x == target.rect.x and selected.rect.y == target.rect.y
end

local function overflow(qa: QA.QA): QA.Query?
	for _, word in { "more", "menu", "options" } do
		local query: QA.Query = { role = "button", pattern = "^" .. word .. "%f[%W]" }
		if qa:first(query) ~= nil then
			return query
		end
	end
	return nil
end

local function root(qa: QA.QA): boolean
	for _, word in returns do
		if qa:first({ role = "button", exact = word }) ~= nil then
			return false
		end
	end
	return true
end

local function locate(qa: QA.QA, query: QA.Query): (boolean, boolean)
	if qa:reveal(query) and qa:first(query) ~= nil then
		return true, false
	end
	if query.role ~= "button" then
		return false, false
	end
	for _, word in returns do
		if string.lower(query.exact or query.text or "") == word or query.pattern == "^" .. word .. "$" then
			return false, false
		end
	end
	local menu = overflow(qa)
	if menu == nil then
		return false, false
	end
	local opened = qa:tap(menu)
	return opened and qa:reveal(query) and qa:first(query) ~= nil, opened
end

local function reveal(qa: QA.QA, query: QA.Query): boolean
	if query.role ~= "button" then
		return qa:first(query) ~= nil
	end
	local found = locate(qa, query)
	return found
end

local function signature(qa: QA.QA): string
	local texts = qa:texts()
	for index, words in texts do
		texts[index] = string.gsub(string.lower(words), "%d+", "#")
	end
	table.sort(texts)
	return table.concat(texts, "\n")
end

local function tap(qa: QA.QA, query: QA.Query): (boolean, string)
	local _, throughOverflow = locate(qa, query)
	local before = if throughOverflow then signature(qa) else nil
	local wide = table.clone(query)
	wide.clipped = true
	qa:waitFor(wide, 4)
	local ok, detail = qa:tap(query)
	if not ok or before == nil then
		return ok, detail
	end
	local deadline = os.clock() + 4
	for _ = 1, 20 do
		if signature(qa) ~= before then
			return true, detail
		end
		if os.clock() >= deadline then
			break
		end
		qa:sleep(0.1)
	end
	return false, "the overflow action did not open a panel"
end

local function returned(qa: QA.QA, query: QA.Query, requireFocus: boolean?, navigation: Navigation?): (boolean, string)
	local persistent = navigation ~= nil and navigation.root ~= nil
	if not persistent and not root(qa) then
		return false, "the route is still on a child screen"
	end
	local opener = query
	if qa:first(query) == nil and not (persistent and qa:reveal(query)) then
		local menu = overflow(qa)
		if menu == nil then
			return false, "the action has no visible opener or overflow route"
		end
		opener = menu
	end
	if not persistent and qa.device.mode == "gamepad" and requireFocus ~= false then
		if not focused(qa, opener) then
			return false, "selection did not return to the hub opener"
		end
	end
	if opener == query then
		if persistent then
			return available(qa, query)
		end
		return qa:reveal(query), "the direct opener is reachable"
	end
	if not reveal(qa, query) then
		return false, "the action is missing from the overflow menu"
	end
	if persistent then
		local reachable, detail = available(qa, query)
		if not reachable then
			return false, detail
		end
	elseif qa.device.mode == "gamepad" then
		local reachable, detail = qa:gamepadSelect(query)
		if not reachable then
			return false, detail
		end
	end
	if navigation ~= nil and navigation.root ~= nil and navigation.reserved.close then
		return false, "the menu return label is shared with the initial root; recovery is ambiguous"
	end
	local closed = if qa.device.mode == "gamepad"
		then qa:press("Backspace")
		else qa:tap({ role = "button", exact = "close" })
	if not closed or (not persistent and not root(qa)) or qa:first(opener) == nil then
		return false, "the overflow menu traps the player"
	end
	if persistent then
		return available(qa, opener)
	end
	if qa.device.mode == "gamepad" and requireFocus ~= false then
		if not focused(qa, opener) then
			return false, "closing overflow did not restore hub focus"
		end
	end
	return true, "the action is reachable again through overflow"
end

local function returnToRoot(qa: QA.QA, navigation: Navigation?): (boolean, string)
	for _ = 1, 8 do
		if navigation ~= nil and navigation.root ~= nil then
			local initial = navigation.root
			local target: QA.Query? = navigation.root
			local ready = available(qa, initial)
			if not ready and qa:first(initial) == nil then
				target = semanticRoot(qa, { "hub" })
				ready = target ~= nil and available(qa, target)
			end
			if target ~= nil and ready then
				local activated = qa:tap(target)
				if activated then
					local settled = qa:call("perf", { action = "settle", quiet = 0.1, limit = 20 })
					if type(settled) ~= "table" or (settled :: { [string]: unknown }).timedOut ~= false then
						return false, "root navigation did not settle"
					end
					if target ~= navigation.root then
						continue
					end
					return available(qa, navigation.root)
				end
			end
		end
		local query: QA.Query? = nil
		local reserved = false
		for _, word in { "Close", "Back", "Cancel", "Skip", "Return", "×" } do
			local candidate: QA.Query = { exact = word, role = "button" }
			if qa:first(candidate) ~= nil then
				if navigation ~= nil and navigation.reserved[string.lower(word)] then
					reserved = true
					continue
				end
				query = candidate
				break
			end
		end
		if query == nil then
			if reserved then
				return false, "a return label is shared with the initial root; recovery is ambiguous"
			end
			if navigation ~= nil and navigation.root ~= nil then
				return false, "the captured root navigation is not reachable"
			end
			return true, "return controls are absent"
		end
		local activated, detail
		if qa.device.mode == "gamepad" then
			activated, detail = qa:gamepadActivate(query)
		else
			activated, detail = qa:tap(query)
		end
		if not activated and qa:first(query) ~= nil then
			return false, detail
		end
		local settled = qa:call("perf", { action = "settle", quiet = 0.1, limit = 20 })
		if type(settled) ~= "table" or (settled :: { [string]: unknown }).timedOut ~= false then
			return false, "return control did not settle"
		end
	end
	return false, "return controls remain after eight attempts"
end

return {
	captureRoot = captureRoot,
	prepareInput = prepareInput,
	reveal = reveal,
	tap = tap,
	returned = returned,
	overflow = overflow,
	returnToRoot = returnToRoot,
}
