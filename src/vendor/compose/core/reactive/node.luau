--!strict
--!native

local Types = require "./types"
local Weak = require "../weak"
local Dynamic = require "../dynamic"
type Node = Types.Node
local detachers: { [Node]: () -> () } = {}
Weak.keys(detachers)

local classes: { [unknown]: boolean } = {}

local metatableOf: (subject: unknown) -> unknown = getmetatable

local function asNode(subject: unknown): Node?
	if classes[metatableOf(subject)] ~= nil then
		return Dynamic.node(subject)
	end
	return nil
end

local function adopt(class: {})
	classes[class] = Dynamic.read(class, "peek") ~= nil
end

local function classify(node: Node, class: {})
	setmetatable(node, class)
end

local function nodeOf<T>(value: Types.Cache<T>): Node
	return value
end

local function uninitialized(): never
	return error("Compose value has not initialized", 0)
end

local function readCached<T>(value: Types.Cache<T>): T
	local cached = value.cache
	if cached == nil then
		return uninitialized()
	end
	return cached.value
end

local function readCache<T>(value: Types.Cache<T>): T
	local node: Node = value
	local refresh = node.refresh
	if refresh ~= nil then
		refresh(node)
	end
	return readCached(value)
end

local function read<T>(value: Types.ReadOnlyValue<T>): T
	return value:peek()
end

local function isNode(subject: unknown): boolean
	return classes[metatableOf(subject)] == true
end

local function asValueNode(subject: unknown): Node?
	if classes[metatableOf(subject)] == true then
		return Dynamic.valueNode(subject)
	end
	return nil
end

local function asValue(subject: unknown): Types.ReadOnlyValue<unknown>?
	if classes[metatableOf(subject)] == true then
		return Dynamic.valueNode(subject)
	end
	return nil
end

local function identityKey<V>(value: V, _index: number): V
	return value
end

return {
	detachers = detachers,
	isNode = isNode,
	adopt = adopt,
	classify = classify,
	asNode = asNode,
	nodeOf = nodeOf,
	read = read,
	readCache = readCache,
	readCached = readCached,
	asValue = asValue,
	asValueNode = asValueNode,
	identityKey = identityKey,
}
