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
	local created = table.freeze { composeKey = "event" :: "event", name = name }
	eventKeys[name] = created
	return created
end

local function property(name: string): PropertyKey
	local existing = propertyKeys[name]
	if existing ~= nil then
		return existing
	end
	local created = table.freeze { composeKey = "property" :: "property", name = name }
	propertyKeys[name] = created
	return created
end

local function group(names: { string }): GroupKey
	if #names == 0 then
		error("group needs at least one property name", 2)
	end
	local copied = table.create(#names)
	for index, name in names do
		if type(name) ~= "string" then
			error(("group names must be strings; entry %d is %s"):format(index, typeof(name)), 2)
		end
		copied[index] = name
	end
	return table.freeze { composeKey = "group" :: "group", names = table.freeze(copied) }
end

local function static(value: unknown): StaticValue
	return table.freeze { composeValue = "static" :: "static", value = value }
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
	local marker = (key :: unknown) :: { composeKey: unknown, name: unknown }
	local kind = marker.composeKey
	if kind == "event" then
		return { kind = "event", name = tostring(marker.name) }
	elseif kind == "property" then
		return { kind = "property", name = tostring(marker.name) }
	elseif kind == "group" then
		local names = (key :: any).names :: { string }
		return { kind = "group", name = table.concat(names, "+"), names = names }
	end
	return nil
end

local function readStatic(value: unknown): (unknown, boolean)
	if type(value) ~= "table" then
		return nil, false
	end
	local marker = (value :: unknown) :: { composeValue: unknown, value: unknown }
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
