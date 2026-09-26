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

-- A press that became a drag never activates: the drag consumes its input object until the frame after it ends.
-- Roblox reuses one mouse InputObject for every click, so the mark must not outlive that press.
local consumed = setmetatable({} :: { [unknown]: boolean }, { __mode = "k" })

function activation.consume(input: unknown)
	if input ~= nil then
		consumed[input] = true
	end
end

function activation.release(input: unknown)
	if input ~= nil then
		consumed[input] = nil
	end
end

function activation.consumed(input: unknown): boolean
	return input ~= nil and consumed[input] == true
end

local pressers = setmetatable({} :: { [Instance]: (InputObject) -> () }, { __mode = "k" })

function activation.providePress(node: Instance, press: (InputObject) -> ()): () -> ()
	pressers[node] = press
	return function()
		if pressers[node] == press then
			pressers[node] = nil
		end
	end
end

function activation.press(node: Instance, input: InputObject)
	local press = pressers[node]
	if press then
		press(input)
	end
end

return activation
