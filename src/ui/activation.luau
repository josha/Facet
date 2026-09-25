--!strict
local activation = {}

type Listener = (...unknown) -> ()

local owned = setmetatable({} :: { [Instance]: { Listener } }, { __mode = "k" })

function activation.mark(node: Instance)
	if owned[node] == nil then
		owned[node] = {}
	end
end

function activation.marked(node: Instance): boolean
	return owned[node] ~= nil
end

function activation.listen(node: Instance, listener: Listener): () -> ()
	local list = owned[node]
	if list == nil then
		list = {}
		owned[node] = list
	end
	table.insert(list, listener)
	return function()
		local current = owned[node]
		if current then
			local index = table.find(current, listener)
			if index then
				table.remove(current, index)
			end
		end
	end
end

local activators = setmetatable({} :: { [Instance]: Listener }, { __mode = "k" })

function activation.provide(node: Instance, activate: Listener): () -> ()
	activators[node] = activate
	return function()
		if activators[node] == activate then
			activators[node] = nil
		end
	end
end

function activation.trigger(node: Instance, ...: unknown): boolean
	local activate = activators[node]
	if activate == nil then
		return false
	end
	activate(...)
	return true
end

function activation.notify(node: Instance, ...: unknown)
	local list = owned[node]
	if list == nil then
		return
	end
	for _, listener in table.clone(list) do
		listener(...)
	end
end

return activation
