--!strict
export type Node = { id: string, branch: string, icon: string, cost: number, parent: string?, x: number, y: number }
export type State = { points: number, owned: { [string]: boolean }, selected: string }
local nodes: { Node } = {
	{ id = "origin", branch = "origin", icon = "star", cost = 0, x = 600, y = 690 },
	{ id = "spark", branch = "power", icon = "bolt", cost = 3, parent = "origin", x = 430, y = 580 },
	{ id = "flare", branch = "power", icon = "bolt", cost = 4, parent = "spark", x = 260, y = 470 },
	{ id = "nova", branch = "power", icon = "star", cost = 7, parent = "flare", x = 260, y = 270 },
	{ id = "echo", branch = "power", icon = "bolt", cost = 5, parent = "flare", x = 100, y = 370 },
	{ id = "aegis", branch = "guard", icon = "shield", cost = 3, parent = "origin", x = 600, y = 470 },
	{ id = "resolve", branch = "guard", icon = "shield", cost = 4, parent = "aegis", x = 600, y = 270 },
	{ id = "bastion", branch = "guard", icon = "shield", cost = 7, parent = "resolve", x = 450, y = 120 },
	{ id = "renewal", branch = "guard", icon = "heart", cost = 5, parent = "resolve", x = 750, y = 120 },
	{ id = "stride", branch = "discovery", icon = "wing", cost = 3, parent = "origin", x = 770, y = 580 },
	{ id = "wind", branch = "discovery", icon = "wing", cost = 4, parent = "stride", x = 940, y = 470 },
	{ id = "horizon", branch = "discovery", icon = "star", cost = 7, parent = "wind", x = 940, y = 270 },
	{ id = "fortune", branch = "discovery", icon = "diamond", cost = 5, parent = "wind", x = 1100, y = 370 },
}
local byId: { [string]: Node } = {}
for _, node in nodes do
	byId[node.id] = node
end
local model = { nodes = nodes, byId = byId }
function model.initial(): State
	return { points = 18, owned = { origin = true }, selected = "origin" }
end
function model.visible(state: State, node: Node): boolean
	if not node.parent or state.owned[node.parent] then
		return true
	end
	local parent = byId[node.parent]
	return parent.parent ~= nil and state.owned[parent.parent] == true
end
function model.status(state: State, node: Node): string
	if state.owned[node.id] then
		return "owned"
	end
	return if node.parent and not state.owned[node.parent] then "locked" else "available"
end
function model.purchase(state: State, id: string): (State, string)
	local node = byId[id]
	if not node or model.status(state, node) == "locked" then
		return state, "locked"
	end
	if state.owned[id] then
		return state, "owned"
	end
	if state.points < node.cost then
		return state, "insufficient"
	end
	local owned = table.clone(state.owned)
	owned[id] = true
	return { points = state.points - node.cost, owned = owned, selected = id }, "unlocked"
end
return model
