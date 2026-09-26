--!strict
local reservations = {}

export type Edge = "top" | "bottom"
type Entry = { edge: Edge, y: number, h: number }

local layers = setmetatable({} :: { [Instance]: { [unknown]: Entry } }, { __mode = "k" })

local function publish(layer: Instance)
	local entries: { [unknown]: Entry } = layers[layer] or {}
	local height = if layer:IsA("GuiBase2d") then (layer :: GuiBase2d).AbsoluteSize.Y else 0
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
		local shown = candidate == layer or not candidate:IsA("LayerCollector") or (candidate :: LayerCollector).Enabled
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

return reservations
