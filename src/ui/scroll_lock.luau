--!strict
local scrollLock = {}

type Layer = {
	stack: { Instance },
	held: { [ScrollingFrame]: boolean },
	connections: { RBXScriptConnection },
}

local layers = setmetatable({} :: { [Instance]: Layer }, { __mode = "k" })

local function within(node: Instance, ancestor: Instance): boolean
	local at: Instance? = node
	while at do
		if at == ancestor then
			return true
		end
		at = at.Parent
	end
	return false
end

local function exempt(state: Layer, node: Instance): boolean
	local count = #state.stack
	return count == 0 or within(node, state.stack[count])
end

local function hold(state: Layer, frame: ScrollingFrame)
	if state.held[frame] ~= nil then
		return
	end
	state.held[frame] = frame.ScrollingEnabled
	frame.ScrollingEnabled = false
end

local function free(state: Layer, frame: ScrollingFrame)
	local previous = state.held[frame]
	if previous == nil then
		return
	end
	state.held[frame] = nil
	frame.ScrollingEnabled = previous
end

local function refresh(layer: Instance, state: Layer)
	local held: { ScrollingFrame } = {}
	for frame in state.held do
		table.insert(held, frame)
	end
	for _, frame in held do
		if exempt(state, frame) or not within(frame, layer) then
			free(state, frame)
		end
	end
	if #state.stack == 0 then
		for _, connection in state.connections do
			connection:Disconnect()
		end
		table.clear(state.connections)
		if next(state.held) == nil then
			layers[layer] = nil
		end
		return
	end
	for _, node in layer:GetDescendants() do
		if node:IsA("ScrollingFrame") and not exempt(state, node) then
			hold(state, node)
		end
	end
	if #state.connections == 0 then
		table.insert(
			state.connections,
			layer.DescendantAdded:Connect(function(node: Instance)
				if node:IsA("ScrollingFrame") and #state.stack > 0 and not exempt(state, node) then
					hold(state, node)
				end
			end)
		)
		table.insert(
			state.connections,
			layer.DescendantRemoving:Connect(function(node: Instance)
				if node:IsA("ScrollingFrame") then
					free(state, node)
				end
			end)
		)
	end
end

function scrollLock.acquire(layer: Instance, root: Instance)
	local state = layers[layer]
	if state == nil then
		local created: Layer = { stack = {}, held = {}, connections = {} }
		layers[layer] = created
		state = created
	end
	local current = assert(state)
	if table.find(current.stack, root) then
		return
	end
	table.insert(current.stack, root)
	refresh(layer, current)
end

function scrollLock.release(layer: Instance, root: Instance)
	local state = layers[layer]
	if state == nil then
		return
	end
	local index = table.find(state.stack, root)
	if index == nil then
		return
	end
	table.remove(state.stack, index)
	refresh(layer, state)
end

return scrollLock
