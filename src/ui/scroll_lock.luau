--!strict
local Types = require("./types")
local chain = require("./scroll_chain")
local scrollLock = {}

type Layer = {
	stack: { Instance },
	held: { [ScrollingFrame]: boolean },
	connections: { RBXScriptConnection },
}

type Hold = { count: number, saved: boolean, watch: RBXScriptConnection }

local layers = setmetatable({} :: { [Instance]: Layer }, { __mode = "k" })
local holds = setmetatable({} :: { [ScrollingFrame]: Hold }, { __mode = "k" })
local owned = setmetatable({} :: { [ScrollingFrame]: boolean }, { __mode = "k" })

local function take(frame: ScrollingFrame)
	local current = holds[frame]
	if current then
		current.count += 1
		return
	end
	local created: Hold = {
		count = 1,
		saved = frame.ScrollingEnabled,
		watch = frame:GetPropertyChangedSignal("ScrollingEnabled"):Connect(function()
			local held = holds[frame]
			if held and frame.ScrollingEnabled then
				held.saved = true
				frame.ScrollingEnabled = false
			end
		end),
	}
	holds[frame] = created
	frame.ScrollingEnabled = false
end

local function give(frame: ScrollingFrame)
	local current = holds[frame]
	if current == nil then
		return
	end
	current.count -= 1
	if current.count == 0 then
		holds[frame] = nil
		current.watch:Disconnect()
		frame.ScrollingEnabled = current.saved
	end
end

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
	if state.held[frame] then
		return
	end
	state.held[frame] = true
	take(frame)
end

local function free(state: Layer, frame: ScrollingFrame)
	if not state.held[frame] then
		return
	end
	state.held[frame] = nil
	give(frame)
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

function scrollLock.own(frame: ScrollingFrame, ctx: Types.Context?)
	owned[frame] = true
	if ctx then
		chain(ctx, frame, function(candidate: ScrollingFrame): boolean
			return owned[candidate] == true
		end, function(exhausted: ScrollingFrame): () -> ()
			take(exhausted)
			return function()
				give(exhausted)
			end
		end)
	end
end

function scrollLock.holdOwnedAncestors(node: Instance): () -> ()
	local held: { ScrollingFrame } = {}
	local at = node.Parent
	while at do
		if at:IsA("ScrollingFrame") and owned[at] then
			take(at)
			table.insert(held, at)
		end
		at = at.Parent
	end
	return function()
		for _, frame in held do
			give(frame)
		end
		table.clear(held)
	end
end

return scrollLock
