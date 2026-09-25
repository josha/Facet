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

function reservations.clear(layer: Instance, token: unknown)
	local entries = layers[layer]
	if entries and entries[token] then
		entries[token] = nil
		publish(layer)
	end
end

return reservations
