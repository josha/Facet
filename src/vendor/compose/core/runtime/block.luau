--!strict

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
	dispose: Dispose,
}

local function nameOf(component: any): string
	if type(component) ~= "function" then
		return "<not a component>"
	end
	local name = debug.info(component, "n")
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

local function mountBlock(
	mountPoint: Children.MountPoint,
	parentOwner: Owner.Owner,
	produce: () -> { Node },
	label: string,
	at: number?
): Block
	local owner = parentOwner.createChild()

	local ok, producedOrError: any = pcall(Active.runWith1, owner, produce)
	if not ok then
		owner.dispose()
		error(producedOrError, 0)
	end
	local okNodes, builtOrError: any = pcall(requireNodes, producedOrError, label)
	if not okNodes then
		owner.dispose()
		error(builtOrError, 0)
	end
	local built: { Node } = builtOrError

	local inserted = 0
	local insertOk, insertErr: any = pcall(function()
		local base = if at ~= nil then at else mountPoint.count() + 1
		for index, node in built do
			mountPoint.insert(node, base + index - 1)
			inserted = index
		end
	end)
	if not insertOk then
		for index = inserted, 1, -1 do
			pcall(mountPoint.remove, built[index])
		end
		owner.dispose()
		error(insertErr, 0)
	end

	owner.own(function()
		for index = #built, 1, -1 do
			mountPoint.remove(built[index])
		end
		for _, node in built do
			Nodes.forget(node)
		end
	end)

	return { nodes = built, dispose = owner.dispose }
end

return {
	mountBlock = mountBlock,
	nameOf = nameOf,
	requireNodes = requireNodes,
}
