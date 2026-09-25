--!strict

export type EventKey = {
	composeKey: "event",
	name: string,
}

export type PropertyKey = {
	composeKey: "property",
	name: string,
}

export type GroupKey = {
	composeKey: "group",
	names: { string },
}

export type StaticValue = {
	composeValue: "static",
	value: unknown,
}

local eventKeys: { [string]: EventKey } = {}
local propertyKeys: { [string]: PropertyKey } = {}

local function event(name: string): EventKey
	local existing = eventKeys[name]
	if existing ~= nil then
		return existing
	end
	local created: EventKey = { composeKey = "event", name = name }
	table.freeze(created :: {})
	eventKeys[name] = created
	return created
end

local function property(name: string): PropertyKey
	local existing = propertyKeys[name]
	if existing ~= nil then
		return existing
	end
	local created: PropertyKey = { composeKey = "property", name = name }
	table.freeze(created :: {})
	propertyKeys[name] = created
	return created
end

local function group(names: { string }): GroupKey
	if #names == 0 then
		error("group needs at least one property name", 2)
	end
	local copied = table.create(#names) :: { string }
	for index, name in names do
		if type(name) ~= "string" then
			error(("group names must be strings; entry %d is %s"):format(index, typeof(name)), 2)
		end
		copied[index] = name
	end
	table.freeze(copied)
	local created: GroupKey = { composeKey = "group", names = copied }
	table.freeze(created :: {})
	return created
end

local function static(value: unknown): StaticValue
	local created: StaticValue = { composeValue = "static", value = value }
	table.freeze(created :: {})
	return created
end

export type Marker = {
	kind: "event" | "property" | "group",
	name: string,
	names: { string }?,
}

local function readKey(key: unknown): Marker?
	if type(key) ~= "table" then
		return nil
	end
	local marker = key :: { composeKey: unknown, name: unknown, names: unknown }
	local kind = marker.composeKey
	if kind == "event" then
		return { kind = "event", name = tostring(marker.name) }
	elseif kind == "property" then
		return { kind = "property", name = tostring(marker.name) }
	elseif kind == "group" then
		local names = marker.names :: { string }
		return { kind = "group", name = table.concat(names, "+"), names = names }
	end
	return nil
end

local function readStatic(value: unknown): (unknown, boolean)
	if type(value) ~= "table" then
		return nil, false
	end
	local marker = value :: { composeValue: unknown, value: unknown }
	if marker.composeValue ~= "static" then
		return nil, false
	end
	return marker.value, true
end

return {
	event = event,
	group = group,
	property = property,
	static = static,
	readKey = readKey,
	readStatic = readStatic,
}
