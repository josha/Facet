--!strict
--!native

local Diagnostics = require "../diagnostics"
local Active = require "../ownership/active"
local Host = require "../host"
local Nodes = require "../ownership/nodes"
local Owner = require "../ownership/owner"
local Dynamic = require "../dynamic"
local Types = require "../reactive/types"

type Node = Host.Node
type Dispose = Types.Dispose

export type ChildList = {
	host: Host.Host,
	direct: Host.Host,
	parent: Node,
	counts: { number },

	total: number,
}

export type MountPoint = Host.MountPoint

export type Directive = Host.Directive

local function createList(host: Host.Host, parent: Node, direct: Host.Host?): ChildList
	return { host = host, direct = direct or host, parent = parent, counts = {}, total = 0 }
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
			return Diagnostics.raise(
				"structure/position-out-of-range",
				"a directive asked for a position it cannot have",
				{
					index = within,
					expected = ("between 1 and %d"):format(held + 1),
					contract = "a slot-local position must be inside the slot, or exactly one past its end",
				}
			)
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
			return Diagnostics.raise(
				"structure/position-out-of-range",
				"a directive asked to move a node outside its slot",
				{
					index = at,
					expected = ("between 1 and %d"):format(held),
					contract = "a move must land inside the slot it started in",
				}
			)
		end
		moveChild(parent, node, baseOf(list, slot) + at)
	end

	local function remove(node: Node)
		render.removeChild(parent, node)
		list.counts[slot] -= 1
		list.total -= 1
	end

	local mountPoint: MountPoint = {
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
		)
	end

	return (
		setmetatable(mountPoint, {
			__index = function(_: unknown, key: string): never
				return refuse(tostring(key), "read")
			end,
			__newindex = function(_: unknown, key: string, _value: unknown): never
				return refuse(tostring(key), "assigned")
			end,
		})
	)
end

local function insertStatic(list: ChildList, slot: number, node: Node)
	list.direct.render.insertChild(list.parent, node, list.total + 1)
	list.counts[slot] += 1
	list.total += 1
end

local function wholeOf(host: Host.Host, parent: Node): MountPoint
	local list = createList(host, parent)
	local slot = addSlot(list)
	return mountPointFor(list, slot)
end

export type Block = {
	nodes: { Node },
	owner: Owner.Owner,
}

local function nameOf<A..., R...>(component: (A...) -> R...): string
	if type(component) ~= "function" then
		return "<not a component>"
	end
	local name = debug.info(component, "n")
	if name ~= "" then
		return name
	end
	return "<anonymous component>"
end

local function listOf(produced: unknown): { Node }?
	if type(produced) ~= "table" then
		return nil
	end
	return Dynamic.nodeList(produced)
end

local function requireNodes(produced: unknown, label: string): { Node }
	local nodes = listOf(produced)
	if nodes == nil then
		return Diagnostics.raise(
			"mount/not-a-node-list",
			"a component returned something that is not a list of nodes",
			{
				component = label,
				actual = Diagnostics.describe(produced),
				expected = "a node, or an array of nodes",
			}
		)
	end
	for index, node in nodes do
		local kind = type(node)
		if type(node) ~= "table" and type(node) ~= "userdata" then
			return Diagnostics.raise("mount/not-a-node", "a component returned something that is not a node", {
				component = label,
				index = index,
				actual = Diagnostics.describe(node),
				expected = "a node created through runtime.create, or adopted from the host",
				fix = if kind == "function"
					then 'if this is a named constructor, call it with a props table -- Part "Ground" {}'
					else nil,
			})
		end
	end
	return nodes
end

local function releaseNodes(mountPoint: MountPoint, nodes: { Node })
	for index = #nodes, 1, -1 do
		mountPoint.remove(nodes[index])
	end
	for _, node in nodes do
		Nodes.forget(node)
	end
end

local inserted = 0

local function insertAll(mountPoint: MountPoint, built: { Node }, at: number?)
	local base = if at ~= nil then at else mountPoint.count() + 1
	for index, node in built do
		mountPoint.insert(node, base + index - 1)
		inserted = index
	end
end

local function validNodes(produced: unknown): { Node }?
	local nodes = listOf(produced)
	if nodes == nil then
		return nil
	end
	for _, node in nodes do
		local kind = type(node)
		if kind ~= "table" and kind ~= "userdata" then
			return nil
		end
	end
	return nodes
end

local function place(
	mountPoint: MountPoint,
	owner: Owner.Owner,
	ok: boolean,
	produced: unknown,
	label: string,
	at: number?,
	detached: boolean?
): { Node }
	if not ok then
		Owner.dispose(owner)
		error(produced, 0)
	end
	local built = validNodes(produced)
	if built == nil then
		local _, failure = pcall(requireNodes, produced, label)
		Owner.dispose(owner)
		error(failure, 0)
	end

	local outer = inserted
	inserted = 0
	local insertOk, insertErr: unknown = pcall(insertAll, mountPoint, built, at)
	local count = inserted
	inserted = outer
	if not insertOk then
		for index = count, 1, -1 do
			pcall(mountPoint.remove, built[index])
		end
		Owner.dispose(owner)
		error(insertErr, 0)
	end

	if not detached then
		Owner.adopt(owner, function()
			releaseNodes(mountPoint, built)
		end)
	end
	return built
end

local function mountBlock(
	mountPoint: MountPoint,
	parentOwner: Owner.Owner,
	produce: () -> { read [number]: Node },
	label: string,
	at: number?,
	detached: boolean?
): Block
	local owner = Owner.createChild(parentOwner)
	local running = Active.push(owner)
	local ok, produced = pcall(produce)
	Active.pop(owner, running)
	return { nodes = place(mountPoint, owner, ok, produced, label, at, detached), owner = owner }
end

local function mountRow<A, B, C>(
	mountPoint: MountPoint,
	parentOwner: Owner.Owner,
	render: (A, B, C) -> Node,
	first: A,
	second: B,
	third: C,
	label: string,
	at: number?
): (Node, Owner.Owner)
	local owner = Owner.createChild(parentOwner)
	local running = Active.push(owner)
	local ok, produced = pcall(render, first, second, third)
	Active.pop(owner, running)
	if not ok then
		Owner.dispose(owner)
		error(produced, 0)
	end
	if type(produced) ~= "table" and type(produced) ~= "userdata" then
		Owner.dispose(owner)
		return Diagnostics.raise("mount/not-a-node", "a row returned something that is not a node", {
			component = label,
			index = 1,
			actual = Diagnostics.describe(produced),
			expected = "a node created through runtime.create, or adopted from the host",
		})
	end
	local inserted, failure = pcall(mountPoint.insert, produced, at)
	if not inserted then
		Owner.dispose(owner)
		error(failure, 0)
	end
	return produced, owner
end

local function releaseNode(mountPoint: MountPoint, node: Node)
	mountPoint.remove(node)
	Nodes.forget(node)
end

return {
	block = {
		mountBlock = mountBlock,
		mountRow = mountRow,
		releaseNode = releaseNode,
		releaseNodes = releaseNodes,
		nameOf = nameOf,
		requireNodes = requireNodes,
	},
	createList = createList,
	addSlot = addSlot,
	baseOf = baseOf,
	mountPointFor = mountPointFor,
	insertStatic = insertStatic,
	wholeOf = wholeOf,
}
