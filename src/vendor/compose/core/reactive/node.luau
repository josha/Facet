--!strict
--!native

local Types = require "./types"
local Weak = require "../weak"

type Node = Types.Node
type Value<T> = Types.Value<T>
type Equals<T> = Types.Equals<T>

local classes: { [unknown]: true } = {}
local detachers: { [Node]: () -> () } = {}
Weak.keys(detachers)
local metatableOf = (getmetatable :: unknown) :: (unknown) -> unknown

local function adopt(class: {})
	classes[class] = true
end

local function make<T>(node: Node, class: {}): Value<T>
	setmetatable(node, class)
	return (node :: unknown) :: Value<T>
end

local function classify(node: Node, class: {})
	setmetatable(node, class)
end

local function asNode(candidate: unknown): Node?
	if type(candidate) == "table" and classes[metatableOf(candidate)] then
		return (candidate :: unknown) :: Node
	end
	return nil
end

local function isNode(candidate: unknown): boolean
	return type(candidate) == "table" and classes[metatableOf(candidate)] == true
end

local function releaser(value: unknown): (subject: unknown) -> ()
	return (value :: unknown) :: (subject: unknown) -> ()
end

local function heldEdge(subject: unknown): Node
	return (subject :: unknown) :: Node
end

local function nodeOf<T>(value: Types.ReadOnlyValue<T>): Node
	return (value :: unknown) :: Node
end

local function read<T>(value: Types.ReadOnlyValue<T>): T
	return (((value :: unknown) :: Node).value :: unknown) :: T
end

local function eraseEquals<T>(equals: Equals<T>): (current: unknown, incoming: unknown) -> boolean
	return (equals :: unknown) :: (current: unknown, incoming: unknown) -> boolean
end

local function split<T>(initial: (() -> T) | T): (((use: Types.Use) -> unknown)?, unknown)
	if type(initial) == "function" then
		return (initial :: unknown) :: (use: Types.Use) -> unknown, nil
	end
	return nil, initial
end

local function eraseListener<T>(body: (value: T) -> ()): (value: unknown) -> ()
	return (body :: unknown) :: (value: unknown) -> ()
end

local function identityKey<V, K>(value: V, _index: number): K
	return (value :: unknown) :: K
end

return {
	detachers = detachers,
	releaser = releaser,
	heldEdge = heldEdge,
	isNode = isNode,
	adopt = adopt,
	classify = classify,
	make = make,
	asNode = asNode,
	nodeOf = nodeOf,
	read = read,
	eraseEquals = eraseEquals,
	eraseListener = eraseListener,
	split = split,
	identityKey = identityKey,
}
