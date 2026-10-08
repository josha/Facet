--!strict
local Types = require("./types")
local InputTypes = require("./input_types")
local activation = {}

export type EditAction = {
	id: string?,
	label: Types.ValueString,
	icon: Types.ValueString?,
	role: InputTypes.ButtonRole?,
	enabled: (Types.Use?) -> boolean,
	onActivate: () -> (),
}

local editors = setmetatable({} :: { [Instance]: EditAction }, { __mode = "k" })

function activation.provideEdit(node: Instance, action: EditAction): () -> ()
	editors[node] = action
	return function()
		editors[node] = nil
	end
end

function activation.edits(root: Instance): { EditAction }
	local result = {}
	if editors[root] then
		table.insert(result, editors[root])
	end
	for _, node in root:GetDescendants() do
		if editors[node] then
			table.insert(result, editors[node])
		end
	end
	return result
end

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

local interceptors = setmetatable({} :: { [Instance]: (unknown) -> boolean }, { __mode = "k" })

function activation.intercept(node: Instance, listener: (unknown) -> boolean): () -> ()
	interceptors[node] = listener
	return function()
		if interceptors[node] == listener then
			interceptors[node] = nil
		end
	end
end

function activation.intercepted(node: Instance, input: unknown): boolean
	local listener = interceptors[node]
	return listener ~= nil and listener(input)
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

local drags = setmetatable({} :: { [Instance]: (string, Vector2?) -> boolean }, { __mode = "k" })

function activation.provideDrag(node: Instance, listener: (string, Vector2?) -> boolean): () -> ()
	drags[node] = listener
	return function()
		drags[node] = nil
	end
end

function activation.drag(node: Instance?, phase: string, position: Vector2?): boolean
	while node do
		local listener = drags[node]
		if listener then
			return listener(phase, position)
		end
		node = node.Parent
	end
	return false
end

return activation
