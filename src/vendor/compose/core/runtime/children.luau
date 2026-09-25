--!strict

local Diagnostics = require "../diagnostics"
local Host = require "../host"

type Node = Host.Node

export type ChildList = {
	host: Host.Host,
	parent: Node,
	counts: { number },

	total: number,
}

export type MountPoint = {
	parent: Node,
	insert: (node: Node, at: number?) -> (),
	moveTo: (node: Node, at: number) -> (),

	ordersChildren: boolean,
	remove: (node: Node) -> (),
	count: () -> number,
	host: Host.Host,
}

export type Directive = (MountPoint) -> ()

local function createList(host: Host.Host, parent: Node): ChildList
	return { host = host, parent = parent, counts = {}, total = 0 }
end

local function addSlot(list: ChildList): number
	local index = #list.counts + 1
	list.counts[index] = 0
	return index
end

local function baseOf(list: ChildList, slot: number): number
	local base = 0
	local counts = list.counts
	for index = 1, slot - 1 do
		base += counts[index]
	end
	return base
end

local function mountPointFor(list: ChildList, slot: number): MountPoint
	local host = list.host
	local render = host.render

	local moveChild = render.moveChild
	local parent = list.parent

	local function count(): number
		return list.counts[slot]
	end

	local function insert(node: Node, at: number?)
		local held = list.counts[slot]
		local within = if at ~= nil then at else held + 1
		if within < 1 or within > held + 1 then
			Diagnostics.raise("structure/position-out-of-range", "a directive asked for a position it cannot have", {
				index = within,
				expected = ("between 1 and %d"):format(held + 1),
				contract = "a slot-local position must be inside the slot, or exactly one past its end",
			})
		end
		render.insertChild(parent, node, baseOf(list, slot) + within)
		list.counts[slot] = held + 1
		list.total += 1
	end

	local function moveTo(node: Node, at: number)
		if moveChild == nil then
			return
		end
		local held = list.counts[slot]
		if at < 1 or at > held then
			Diagnostics.raise("structure/position-out-of-range", "a directive asked to move a node outside its slot", {
				index = at,
				expected = ("between 1 and %d"):format(held),
				contract = "a move must land inside the slot it started in",
			})
		end
		moveChild(parent, node, baseOf(list, slot) + at)
	end

	local function remove(node: Node)
		render.removeChild(parent, node)
		list.counts[slot] -= 1
		list.total -= 1
	end

	local mountPoint = {
		parent = parent,
		host = host,
		insert = insert,
		moveTo = moveTo,
		ordersChildren = moveChild ~= nil,
		remove = remove,
		count = count,
	}

	local function refuse(key: string, how: string): never
		return Diagnostics.raise(
			"structure/not-a-mount-point",
			("a directive %s %q on its mount point"):format(how, key),
			{
				key = key,
				contract = "a child written as a function is a directive, and receives a mount point, "
					.. "not the parent node",
				fix = "use insert, moveTo, remove, count, parent, or host; to reach the parent node itself, "
					.. "read mountPoint.parent",
			}
		) :: never
	end

	return (
		setmetatable(mountPoint, {
			__index = function(_: unknown, key: string): never
				return refuse(tostring(key), "read")
			end,
			__newindex = function(_: unknown, key: string, _value: unknown): never
				return refuse(tostring(key), "assigned")
			end,
		}) :: any
	) :: MountPoint
end

local function insertStatic(list: ChildList, slot: number, node: Node)
	list.host.render.insertChild(list.parent, node, list.total + 1)
	list.counts[slot] += 1
	list.total += 1
end

local function wholeOf(host: Host.Host, parent: Node): MountPoint
	local list = createList(host, parent)
	local slot = addSlot(list)
	return mountPointFor(list, slot)
end

return {
	createList = createList,
	addSlot = addSlot,
	baseOf = baseOf,
	mountPointFor = mountPointFor,
	insertStatic = insertStatic,
	wholeOf = wholeOf,
}
