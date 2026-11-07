--!strict
local Types = require("./types")

type Listener = (string) -> ()
type Entry = { listeners: { [Listener]: boolean }, connection: RBXScriptConnection }
local entries: { [Instance]: Entry } = setmetatable({}, { __mode = "k" })

return function(ctx: Types.Context, label: Instance, listener: Listener): () -> ()
	local entry = entries[label]
	if entry == nil then
		local listeners: { [Listener]: boolean } = {}
		entry = {
			listeners = listeners,
			connection = label.Changed:Connect(function(property: string)
				local due = table.clone(listeners)
				for callback in due do
					if listeners[callback] then
						callback(property)
					end
				end
			end),
		}
		entries[label] = entry
	end
	local held = entry
	held.listeners[listener] = true
	return ctx.Compose.cleanup(function()
		held.listeners[listener] = nil
		if next(held.listeners) == nil then
			held.connection:Disconnect()
			entries[label] = nil
		end
	end)
end
