--!strict
--!native

local Host = require "./host"
local Types = require "./reactive/types"

local function identity<T>(value: T): T
	return value
end

local erasure: { [string]: <T>(unknown) -> T } = {}
setmetatable(erasure, {
	__index = function()
		return identity
	end,
})
local erase = erasure.value

local function invoke(target: (...unknown) -> ...unknown, ...: unknown): ...unknown
	return target(...)
end

local function read(object: { [unknown]: unknown }, key: unknown): unknown
	return object[key]
end

local function write(object: { [unknown]: unknown }, key: unknown, value: unknown)
	object[key] = value
end

local dynamicRaw = erase<<(object: unknown, key: unknown) -> unknown>>(rawget)
local dynamicInvoke = erase<<(target: unknown, ...unknown) -> ...unknown>>(invoke)
local dynamicRead = erase<<(object: unknown, key: unknown) -> unknown>>(read)
local dynamicWrite = erase<<(object: unknown, key: unknown, value: unknown) -> ()>>(write)
local entries = erase<<(props: unknown) -> { [number]: Host.Child? }>>(identity)
local props = erase<<(source: unknown) -> Host.PropTable>>(identity)
local handler = erase<<(callback: Host.PropFunction) -> (...unknown) -> ()>>(identity)
local listener = erase<<(callback: unknown) -> (unknown) -> ()>>(identity)
local node = erase<<(subject: unknown) -> Types.Node>>(identity)
local valueNode = erase<<(subject: unknown) -> Types.Node & Types.ReadOnlyValue<unknown>>>(identity)
local nodeList = erase<<(produced: unknown) -> { Host.Node }>>(identity)

local function cache(target: Types.Node, value: unknown)
	target.value = value
	if target.cache == nil then
		target.cache = target
	end
end

return {
	nodeList = nodeList,
	node = node,
	valueNode = valueNode,
	entries = entries,
	handler = handler,
	listener = listener,
	props = props,
	invoke = dynamicInvoke,
	raw = dynamicRaw,
	read = dynamicRead,
	write = dynamicWrite,
	cache = cache,
}
