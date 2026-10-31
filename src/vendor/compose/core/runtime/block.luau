--!strict
--!native

local Active = require "../ownership/active"
local Children = require "./children"
local Diagnostics = require "../diagnostics"
local Host = require "../host"
local Nodes = require "../ownership/nodes"
local Owner = require "../ownership/owner"
local Types = require "../reactive/types"

type Node = Host.Node
type Dispose = Types.Dispose

export type Block = {
	nodes: { Node },
	owner: Owner.Owner,
}

local function nameOf(component: unknown): string
	if type(component) ~= "function" then
		return "<not a component>"
	end
	local name = debug.info(component :: (...unknown) -> ...unknown, "n")
	if name ~= "" then
		return name
	end
	return "<anonymous component>"
end

local function requireNodes(produced: { Node }, label: string): { Node }
	if type(produced) ~= "table" then
		Diagnostics.raise("mount/not-a-node-list", "a component returned something that is not a list of nodes", {
			component = label,
			actual = Diagnostics.describe(produced),
			expected = "a node, or an array of nodes",
		})
	end
	for index, node in produced do
		local kind = type(node)
		if kind ~= "table" and kind ~= "userdata" then
			Diagnostics.raise("mount/not-a-node", "a component returned something that is not a node", {
				component = label,
				index = index,
				actual = Diagnostics.describe(node),
				expected = "a node created through runtime.create, or adopted from the host",
				fix = if kind == "function"
					then 'if this is a named constructor, call it with a props table -- Part "Ground" { }'
					else nil,
			})
		end
	end
	return produced
end

local function releaseNodes(mountPoint: Children.MountPoint, nodes: { Node })
	for index = #nodes, 1, -1 do
		mountPoint.remove(nodes[index])
	end
	for _, node in nodes do
		Nodes.forget(node)
	end
end

local inserted = 0

local function insertAll(mountPoint: Children.MountPoint, built: { Node }, at: number?)
	local base = if at ~= nil then at else mountPoint.count() + 1
	for index, node in built do
		mountPoint.insert(node, base + index - 1)
		inserted = index
	end
end

local function validNodes(produced: unknown): boolean
	if type(produced) ~= "table" then
		return false
	end
	for _, node in produced :: { unknown } do
		local kind = type(node)
		if kind ~= "table" and kind ~= "userdata" then
			return false
		end
	end
	return true
end

local function place(
	mountPoint: Children.MountPoint,
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
	if not validNodes(produced) then
		local _, failure = pcall(requireNodes, produced :: { Node }, label)
		Owner.dispose(owner)
		error(failure, 0)
	end
	local built = produced :: { Node }

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
	mountPoint: Children.MountPoint,
	parentOwner: Owner.Owner,
	produce: () -> { Node },
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

local function single<A, B, C>(render: (A, B, C) -> Node, first: A, second: B, third: C): { Node }
	return { render(first, second, third) }
end

local function mountRow<A, B, C>(
	mountPoint: Children.MountPoint,
	parentOwner: Owner.Owner,
	render: (A, B, C) -> Node,
	first: A,
	second: B,
	third: C,
	label: string,
	at: number?
): ({ Node }, Owner.Owner)
	local owner = Owner.createChild(parentOwner)
	local running = Active.push(owner)
	local ok, produced = pcall(single, render, first, second, third)
	Active.pop(owner, running)
	return place(mountPoint, owner, ok, produced, label, at, true), owner
end

return {
	mountBlock = mountBlock,
	mountRow = mountRow,
	releaseNodes = releaseNodes,
	nameOf = nameOf,
	requireNodes = requireNodes,
}
