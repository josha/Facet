--!strict

local QA = require("./qa")

local returns = { "close", "back", "cancel", "skip", "return" }

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

local function returned(qa: QA.QA, query: QA.Query): (boolean, string)
	if not root(qa) then
		return false, "the route is still on a child screen"
	end
	local opener = query
	if qa:first(query) == nil then
		local menu = overflow(qa)
		if menu == nil then
			return false, "the action has no visible opener or overflow route"
		end
		opener = menu
	end
	if qa.device.mode == "gamepad" then
		if not focused(qa, opener) then
			return false, "selection did not return to the hub opener"
		end
	end
	if opener == query then
		return qa:reveal(query), "the direct opener is reachable"
	end
	if not reveal(qa, query) then
		return false, "the action is missing from the overflow menu"
	end
	if qa.device.mode == "gamepad" then
		local reachable, detail = qa:gamepadSelect(query)
		if not reachable then
			return false, detail
		end
	end
	local closed = if qa.device.mode == "gamepad"
		then qa:press("Backspace")
		else qa:tap({ role = "button", exact = "close" })
	if not closed or not root(qa) or qa:first(opener) == nil then
		return false, "the overflow menu traps the player"
	end
	if qa.device.mode == "gamepad" then
		if not focused(qa, opener) then
			return false, "closing overflow did not restore hub focus"
		end
	end
	return true, "the action is reachable again through overflow"
end

return { reveal = reveal, tap = tap, returned = returned, overflow = overflow }
