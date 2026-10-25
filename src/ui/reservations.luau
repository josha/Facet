--!strict
local reservations = {}

export type Edge = "top" | "bottom"
export type Contest = { token: Instance, zone: string }
type Entry = { edge: Edge, y: number, h: number }
type Zones = { [string]: boolean }

local layers = setmetatable({} :: { [Instance]: { [unknown]: Entry } }, { __mode = "k" })
local claims = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [Instance]: { [Instance]: Zones } }
local noted = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [Instance]: { [Instance]: Zones } }

local function publish(layer: Instance)
	local entries: { [unknown]: Entry } = layers[layer] or {}
	local height = if layer:IsA("GuiBase2d") then layer.AbsoluteSize.Y else 0
	local top, bottom = 0, 0
	for _, entry in entries do
		if entry.edge == "top" then
			top = math.max(top, entry.y + entry.h)
		else
			bottom = math.max(bottom, height - entry.y)
		end
	end
	layer:SetAttribute("FacetInsetTop", top)
	layer:SetAttribute("FacetInsetBottom", bottom)
end

function reservations.set(layer: Instance, token: unknown, edge: Edge, y: number?, h: number?)
	local entries = layers[layer]
	if entries == nil then
		entries = {}
		layers[layer] = entries
	end
	local list = assert(entries)
	if y == nil or h == nil or h <= 0 then
		list[token] = nil
	else
		list[token] = { edge = edge, y = y, h = h }
	end
	publish(layer)
end

function reservations.reserved(layer: GuiBase2d, edge: Edge, skip: { [unknown]: boolean }?): number
	local parent = layer.Parent
	local candidates: { Instance } = if parent then parent:GetChildren() else { layer }
	local top, bottom = layer.AbsolutePosition.Y, layer.AbsolutePosition.Y + layer.AbsoluteSize.Y
	local reserved = 0
	for _, candidate in candidates do
		local entries = layers[candidate]
		local shown = candidate == layer or not candidate:IsA("LayerCollector") or candidate.Enabled
		if entries and shown and candidate:IsA("GuiBase2d") then
			local origin = (candidate :: GuiBase2d).AbsolutePosition.Y
			for token, entry in entries do
				if entry.edge == edge and not (skip and skip[token]) then
					reserved = math.max(
						reserved,
						if edge == "top" then origin + entry.y + entry.h - top else bottom - origin - entry.y
					)
				end
			end
		end
	end
	return reserved
end

function reservations.clear(layer: Instance, token: unknown)
	local entries = layers[layer]
	if entries and entries[token] then
		entries[token] = nil
		publish(layer)
	end
end

function reservations.setZones(layer: Instance, token: Instance, zones: Zones): boolean
	local held = claims[layer]
	if held == nil then
		held = {}
		claims[layer] = held
	end
	local list = assert(held)
	local before = list[token]
	local same = before ~= nil
	if before then
		for zone in before do
			same = same and zones[zone] == true
		end
		for zone in zones do
			same = same and before[zone] == true
		end
	end
	list[token] = zones
	return not same
end

function reservations.clearZones(layer: Instance, token: Instance)
	local held = claims[layer]
	if held then
		held[token] = nil
		if next(held) == nil then
			claims[layer] = nil
		end
	end
end

function reservations.contests(layer: Instance, token: Instance): { Contest }
	local found: { Contest } = {}
	local held = claims[layer]
	local mine = if held then held[token] else nil
	if mine == nil or next(mine) == nil then
		return found
	end
	local parent = layer.Parent
	local seen = noted[token]
	for candidate, entries in claims do
		local shared = candidate == layer or (parent ~= nil and candidate.Parent == parent)
		local shown = candidate == layer or not candidate:IsA("LayerCollector") or candidate.Enabled
		if shared and shown then
			for other, zones in entries do
				local told = if seen then seen[other] else nil
				if other ~= token then
					for zone in mine do
						if zones[zone] and not (told and told[zone]) then
							table.insert(found, { token = other, zone = zone })
						end
					end
				end
			end
		end
	end
	return found
end

function reservations.note(token: Instance, other: Instance, zone: string)
	for _, pair in { { token, other }, { other, token } } do
		local from, to = pair[1], pair[2]
		local byOther = noted[from]
		if byOther == nil then
			byOther = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [Instance]: Zones }
			noted[from] = byOther
		end
		local list = assert(byOther)
		local zones = list[to] or {}
		zones[zone] = true
		list[to] = zones
	end
end

return reservations
