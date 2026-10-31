--!strict

local freeze: ({}) -> {} = table.freeze

local createCopied: (number, string?) -> { string } = table.create

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
	freeze(created)
	eventKeys[name] = created
	return created
end

local function property(name: string): PropertyKey
	local existing = propertyKeys[name]
	if existing ~= nil then
		return existing
	end
	local created: PropertyKey = { composeKey = "property", name = name }
	freeze(created)
	propertyKeys[name] = created
	return created
end

local function group(names: { string }): GroupKey
	if #names == 0 then
		error("group needs at least one property name", 2)
	end
	local copied: { string } = createCopied(#names)
	for index, name in names do
		if type(name) ~= "string" then
			error(("group names must be strings; entry %d is %s"):format(index, typeof(name)), 2)
		end
		copied[index] = name
	end
	freeze(copied)
	local created: GroupKey = { composeKey = "group", names = copied }
	freeze(created)
	return created
end

local function static(value: unknown): StaticValue
	local created: StaticValue = { composeValue = "static", value = value }
	freeze(created)
	return created
end

export type MarkerKind = "event" | "property" | "group"

local function readKey(key: unknown): (MarkerKind?, string, { string }?)
	if type(key) ~= "table" then
		return nil, "", nil
	end
	local marker = key :: { [string]: unknown }
	local kind = rawget(marker, "composeKey")
	if kind == "event" then
		return "event", tostring(rawget(marker, "name")), nil
	elseif kind == "property" then
		return "property", tostring(rawget(marker, "name")), nil
	elseif kind == "group" then
		local names = rawget(marker, "names") :: { string }
		return "group", table.concat(names, "+"), names
	end
	return nil, "", nil
end

local function readStatic(value: unknown): (unknown, boolean)
	if type(value) ~= "table" then
		return nil, false
	end
	local marker = value :: { [string]: unknown }
	if rawget(marker, "composeValue") ~= "static" then
		return nil, false
	end
	return rawget(marker, "value"), true
end

return {
	event = event,
	group = group,
	property = property,
	static = static,
	readKey = readKey,
	readStatic = readStatic,
}
