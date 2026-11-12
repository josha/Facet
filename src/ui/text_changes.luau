--!strict
local Types = require("./types")

type Listener = (string) -> ()
type Entry = {
	connection: RBXScriptConnection?,
	listeners: { Listener },
	owners: { unknown },
	stops: { (() -> ()) | false },
}
local entries: { [Instance]: Entry } = setmetatable({}, { __mode = "k" })

local function removeAt(entry: Entry, index: number)
	local listeners, owners, stops = table.clone(entry.listeners), table.clone(entry.owners), table.clone(entry.stops)
	table.remove(listeners, index)
	table.remove(owners, index)
	table.remove(stops, index)
	entry.listeners, entry.owners, entry.stops = listeners, owners, stops
end

local function finish(label: Instance, entry: Entry)
	if #entry.listeners == 0 then
		local connection = entry.connection
		if connection then
			connection:Disconnect()
			entry.connection = nil
		end
		if entries[label] == entry then
			entries[label] = nil
		end
	end
end

local function stop(label: Instance, listener: Listener)
	local entry = entries[label]
	if entry == nil then
		return
	end
	local index = table.find(entry.listeners, listener)
	if index == nil then
		return
	end
	local onStop = entry.stops[index]
	removeAt(entry, index)
	finish(label, entry)
	if onStop then
		onStop()
	end
end

local function releaseOwner(label: Instance, entry: Entry, owner: unknown)
	local ran: { () -> () } = {}
	local index = #entry.owners
	while index >= 1 do
		if entry.owners[index] == owner then
			local onStop = entry.stops[index]
			removeAt(entry, index)
			if onStop then
				table.insert(ran, onStop)
			end
		end
		index -= 1
	end
	finish(label, entry)
	for position = #ran, 1, -1 do
		ran[position]()
	end
end

local function watch(ctx: Types.Context, label: Instance, listener: Listener, onStop: (() -> ())?)
	local Compose = ctx.Compose
	local entry = entries[label]
	if entry == nil then
		local created: Entry = { listeners = {}, owners = {}, stops = {} }
		created.connection = label.Changed:Connect(function(property: string)
			if property == "AbsolutePosition" then
				return
			end
			local snapshot = created.listeners
			for _, callback in snapshot do
				if created.listeners == snapshot or table.find(created.listeners, callback) then
					callback(property)
				end
			end
		end)
		entry = created
		entries[label] = entry
	end
	local held = entry
	if table.find(held.listeners, listener) then
		return
	end
	local owner: unknown = Compose.currentOwner()
	local registered = table.find(held.owners, owner) ~= nil
	local listeners, owners, stops = table.clone(held.listeners), table.clone(held.owners), table.clone(held.stops)
	table.insert(listeners, listener)
	table.insert(owners, owner)
	local ending: (() -> ()) | false = if onStop then onStop else false
	table.insert(stops, ending)
	held.listeners, held.owners, held.stops = listeners, owners, stops
	if not registered then
		Compose.cleanup(function()
			releaseOwner(label, held, owner)
		end)
	end
end

return table.freeze({ watch = watch, stop = stop })
