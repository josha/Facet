--!strict
local Types = require("./types")

type Listener = (string) -> ()
type Entry = { listeners: { [Listener]: boolean }, order: { Listener }, connection: RBXScriptConnection? }
local entries: { [Instance]: Entry } = setmetatable({}, { __mode = "k" })

return function(ctx: Types.Context, label: Instance, listener: Listener, onStop: (() -> ())?): () -> ()
	local entry = entries[label]
	if entry == nil then
		local created: Entry = { listeners = {}, order = {} }
		created.connection = label.Changed:Connect(function(property: string)
			local listeners = created.listeners
			for _, callback in created.order do
				if listeners[callback] then
					callback(property)
				end
			end
		end)
		entry = created
		entries[label] = entry
	end
	local held = entry
	if not held.listeners[listener] then
		held.listeners[listener] = true
		local order = table.clone(held.order)
		table.insert(order, listener)
		held.order = order
	end
	return ctx.Compose.cleanup(function()
		if held.listeners[listener] then
			held.listeners[listener] = nil
			local order: { Listener } = {}
			for _, callback in held.order do
				if callback ~= listener then
					table.insert(order, callback)
				end
			end
			held.order = order
		end
		if next(held.listeners) == nil then
			if held.connection then
				held.connection:Disconnect()
			end
			entries[label] = nil
		end
		if onStop then
			onStop()
		end
	end)
end
