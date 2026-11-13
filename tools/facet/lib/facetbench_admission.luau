--!strict

local Audit = require("../../vendor/verify/src/roblox/ui-audit")

export type Expectation = { visible: { string }?, absent: { string }?, modal: (boolean | "any")? }
export type Candidate = {
	id: string,
	arm: string,
	device: string,
	screen: string,
	image: string,
	dump: string?,
	attempt: number?,
	expect: Expectation?,
}
export type State = { visible: number, modal: boolean? }
export type Decision = {
	id: string,
	arm: string,
	device: string,
	screen: string,
	image: string,
	attempt: number,
	admitted: boolean,
	reasons: { string },
}
export type Pair =
	{ device: string, screen: string, admitted: boolean, captures: { [string]: string }, reason: string? }
export type Review = { decisions: { Decision }, pairs: { Pair } }

local STATES: { [string]: State } = {
	hub = { visible = 1, modal = false },
	race = { visible = 1, modal = false },
	shop = { visible = 1 },
	garage = { visible = 1 },
	livery = { visible = 1 },
	results = { visible = 1 },
	tutorial = { visible = 2 },
}

local ENGINE_GUIS: { [string]: boolean } = { TouchGui = true, Freecam = true, BubbleChat = true, Chat = true }

local function area(rect: Audit.Rect): number
	return math.max(0, rect.width) * math.max(0, rect.height)
end

local function shared(first: Audit.Rect, second: Audit.Rect): number
	local width = math.min(first.x + first.width, second.x + second.width) - math.max(first.x, second.x)
	local height = math.min(first.y + first.height, second.y + second.height) - math.max(first.y, second.y)
	return math.max(0, width) * math.max(0, height)
end

local function seen(dump: Audit.Dump, element: Audit.Element): boolean
	if not element.visible or area(element.rect) <= 0 then
		return false
	end
	local screen = { x = 0, y = 0, width = dump.screen.width, height = dump.screen.height }
	local on = shared(element.rect, screen)
	local clip = element.clip
	if clip ~= nil then
		on = math.min(on, shared(element.rect, clip))
	end
	return on >= 0.5 * area(element.rect)
end

local function shows(dump: Audit.Dump, query: string): boolean
	local wanted = string.lower(query)
	for _, element in dump.elements do
		local text = element.text
		if
			text ~= nil
			and text.transparency < 0.95
			and (element.opacity or 1) > 0.05
			and seen(dump, element)
			and string.find(string.lower(text.content), wanted, 1, true) ~= nil
		then
			return true
		end
	end
	return false
end

local function lineage(byIndex: { [number]: Audit.Element }, element: Audit.Element): { Audit.Element }
	local chain: { Audit.Element } = {}
	local parent = element.parent
	while parent ~= nil do
		local ancestor = byIndex[parent]
		if ancestor == nil then
			break
		end
		table.insert(chain, ancestor)
		parent = ancestor.parent
	end
	return chain
end

local function modal(dump: Audit.Dump): string?
	local byIndex: { [number]: Audit.Element } = {}
	local orders: { [number]: number } = {}
	for _, element in dump.elements do
		byIndex[element.index] = element
	end
	local engine: { [number]: boolean } = {}
	for _, root in dump.roots do
		orders[root.index] = root.displayOrder
		engine[root.index] = ENGINE_GUIS[string.match(root.path, "[^%.]+$") or ""] == true
	end
	local glass = dump.screen.width * dump.screen.height
	local screen = { x = 0, y = 0, width = dump.screen.width, height = dump.screen.height }
	local function over(upper: Audit.Element, lower: Audit.Element): boolean
		if upper.root ~= lower.root then
			return (orders[upper.root] or 0) > (orders[lower.root] or 0)
		end
		local upperChain, lowerChain = lineage(byIndex, upper), lineage(byIndex, lower)
		if table.find(upperChain, lower) ~= nil or table.find(lowerChain, upper) ~= nil then
			return false
		end
		local mine, theirs = lower, upper
		local held: Audit.Element? = nil
		for _, ancestor in lowerChain do
			if table.find(upperChain, ancestor) ~= nil then
				held = ancestor
				break
			end
			mine = ancestor
		end
		for _, ancestor in upperChain do
			if ancestor == held then
				break
			end
			theirs = ancestor
		end
		return mine.zIndex < theirs.zIndex or (mine.zIndex == theirs.zIndex and mine.order < theirs.order)
	end
	for _, layer in dump.elements do
		if
			not layer.visible
			or shared(layer.rect, screen) < 0.9 * glass
			or not (layer.active or layer.background.transparency < 0.95)
		then
			continue
		end
		for _, control in dump.elements do
			if
				control.interactive
				and control.index ~= layer.index
				and not engine[control.root]
				and seen(dump, control)
				and over(layer, control)
			then
				return layer.path
			end
		end
	end
	return nil
end

local function check(candidate: Candidate, dump: Audit.Dump?): { string }
	local reasons: { string } = {}
	local state = STATES[candidate.screen]
	if state == nil then
		return { ("%s is not a screen of the matched comparison"):format(candidate.screen) }
	end
	if dump == nil then
		return { "no interface dump was saved with the capture, so its state cannot be checked" }
	end
	local expect: Expectation = candidate.expect or {}
	local visible: { string } = expect.visible or {}
	if #visible < state.visible then
		table.insert(
			reasons,
			("the evaluator named %d text(s) that show this state; %s needs %d"):format(
				#visible,
				candidate.screen,
				state.visible
			)
		)
	end
	for _, query in visible do
		if not shows(dump, query) then
			table.insert(reasons, ("the expected text %q is not visible"):format(query))
		end
	end
	for _, query in expect.absent or {} do
		if shows(dump, query) then
			table.insert(reasons, ("the text %q is visible and this state excludes it"):format(query))
		end
	end
	local wanted: (boolean | "any")? = if expect.modal ~= nil then expect.modal else state.modal
	if wanted ~= nil and wanted ~= "any" then
		local open = modal(dump)
		if wanted == false and open ~= nil then
			table.insert(reasons, ("a layer covers the controls of the screen: %s"):format(open))
		elseif wanted == true and open == nil then
			table.insert(reasons, "the state expects an open modal and none covers the screen")
		end
	end
	return reasons
end

local function review(candidates: { Candidate }, load: (string) -> Audit.Dump?, arms: { string }): Review
	local decisions: { Decision } = {}
	local latest: { [string]: Decision } = {}
	local keys: { string } = {}
	local ids: { [string]: boolean } = {}
	for _, candidate in candidates do
		local dump: Audit.Dump? = nil
		local problem: string? = nil
		if candidate.dump ~= nil then
			local ok, loaded = pcall(load, candidate.dump)
			if ok then
				dump = loaded
			else
				problem = "the interface dump does not load: " .. tostring(loaded)
			end
		end
		local reasons = if problem then { problem } else check(candidate, dump)
		if ids[candidate.id] then
			table.insert(reasons, "another capture has this id; a rerun keeps the earlier attempt under its own id")
		end
		ids[candidate.id] = true
		local decision: Decision = {
			id = candidate.id,
			arm = candidate.arm,
			device = candidate.device,
			screen = candidate.screen,
			image = candidate.image,
			attempt = candidate.attempt or 1,
			admitted = #reasons == 0,
			reasons = reasons,
		}
		table.insert(decisions, decision)
		if decision.admitted then
			local key = ("%s/%s/%s"):format(candidate.device, candidate.screen, candidate.arm)
			local earlier = latest[key]
			if earlier == nil or decision.attempt >= earlier.attempt then
				latest[key] = decision
			end
		end
		local pairKey = ("%s/%s"):format(candidate.device, candidate.screen)
		if table.find(keys, pairKey) == nil then
			table.insert(keys, pairKey)
		end
	end
	table.sort(keys)
	local pairs: { Pair } = {}
	for _, key in keys do
		local device, screen = string.match(key, "^(.-)/(.*)$")
		local captures: { [string]: string } = {}
		local missing: { string } = {}
		for _, arm in arms do
			local found = latest[key .. "/" .. arm]
			if found then
				captures[arm] = found.id
			else
				table.insert(missing, arm)
			end
		end
		table.insert(pairs, {
			device = device or key,
			screen = screen or "",
			admitted = #missing == 0,
			captures = captures,
			reason = if #missing > 0
				then ("no admitted capture for %s; the pair is not compared"):format(table.concat(missing, ", "))
				else nil,
		})
	end
	return { decisions = decisions, pairs = pairs }
end

return table.freeze({ STATES = STATES, check = check, review = review, modal = modal, shows = shows })
