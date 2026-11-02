--!strict

local Active = require "../ownership/active"
local Diagnostics = require "../diagnostics"
local Host = require "../host"
local Nodes = require "../ownership/nodes"
local Owner = require "../ownership/owner"
local Children = require "./children"
local Block = Children.block
local Types = require "../reactive/types"
local Props = require "./props"
local applying = Props.applying
local inspecting = Nodes.inspecting
type Node = Host.Node
type Dispose = Types.Dispose
type Fragment = () -> { read [number]: Host.Child? }

local function decorate(supplied: Host.Host, requireOwner: (string) -> Owner.Owner, node: Node, props: unknown): Node
	if type(node) ~= "table" and type(node) ~= "userdata" then
		return Diagnostics.raise("mount/not-a-node", "decorate expects an existing host node", {
			actual = Diagnostics.describe(node),
			expected = "a node belonging to the host this runtime renders to",
		})
	end
	if type(props) ~= "table" then
		return Diagnostics.raise("props/not-a-table", "decorate expects a props table", {
			actual = Diagnostics.describe(props),
			expected = "a table of properties and event keys",
		})
	end

	local parentOwner = requireOwner "decorate"
	local owner = Owner.createChild(parentOwner)

	local savedKey = applying.key
	applying.key = nil
	local ok, err: unknown = pcall(function()
		Active.withOwner(owner, function()
			Props.apply(supplied, node, props, owner)

			if #props > 0 then
				return Diagnostics.raise("props/decorate-has-children", "decorate cannot add children", {
					contract = "decorate only applies properties and events to an existing node",
					fix = "use a portal to mount children into a node Compose does not own",
				})
			end
			return nil
		end)
	end)

	local inFlight = applying.key
	applying.key = savedKey
	if not ok then
		Owner.dispose(owner)
		if inFlight ~= nil then
			error(("%s\n  while applying: decorate.%s"):format(tostring(err), tostring(inFlight)), 0)
		end
		error(err, 0)
	end

	return node
end

local function connect<Args...>(
	host: Host.Host,
	requireOwner: (string) -> Owner.Owner,
	node: Node,
	event: string,
	handler: (Args...) -> ()
): () -> ()
	if type(node) ~= "table" and type(node) ~= "userdata" then
		return Diagnostics.raise("mount/not-a-node", "connect expects an existing host node", {
			event = event,
			actual = Diagnostics.describe(node),
			expected = "a node belonging to the host this runtime renders to",
		})
	end
	if type(handler) ~= "function" then
		return Diagnostics.raise("props/event-needs-handler", "connect expects a handler function", {
			event = event,
			actual = Diagnostics.describe(handler),
			expected = "a function",
		})
	end

	local events = host.events
	if events == nil then
		return Diagnostics.raise("host/no-events", ("host %q cannot subscribe to events"):format(host.name), {
			event = event,
			contract = "subscribing requires the host events capability",
			fix = "implement host.events.connectEvent, or stop calling connect on this host",
		})
	end

	local owner = requireOwner "connect"
	local unsubscribe = (events).connectEvent(node, event, handler)
	local detach = Owner.own(owner, unsubscribe)
	return detach
end

local function adopt(
	host: Host.Host,
	requireOwner: (string) -> Owner.Owner,
	destroyOwnedNode: (unknown) -> (),
	inspector: () -> typeof(require "../ownership/inspect"),
	node: Node
): Node
	local owner = requireOwner "adopt"
	if Nodes.custodyOf(node) == "owned" then
		return Diagnostics.raise("owner/already-owned", "adopt was given a node Compose already owns", {
			node = Host.describeNode(host, node),
			contract = "a node has exactly one owner; adopting a second time would destroy it twice",
			fix = "adopt only nodes created outside Compose",
		})
	end
	Nodes.markAdopted(node)
	Owner.own(owner, function()
		destroyOwnedNode(node)
	end)
	if inspecting.active then
		inspector().node(owner, node, "adopted")
		Nodes.chargeToOwner(owner, node, "adopted")
	end
	return node
end

local function borrow(inspector: () -> typeof(require "../ownership/inspect"), node: Node): Node
	Nodes.markBorrowed(node)
	if inspecting.active then
		local holder = Active.current()
		if holder ~= nil then
			inspector().node(holder, node, "borrowed")
			Nodes.chargeToOwner(holder, node, "borrowed")
		end
	end
	return node
end

local function createFragmentMount(
	host: Host.Host,
	reactor: Types.Reactor,
	constructorKinds: { [unknown]: string },
	pendingLabel: { [unknown]: string },
	refuseAfterDispose: (string, string) -> (),
	claimTarget: (Node) -> (),
	releaseInOrder: (Types.Dispose, Types.Dispose) -> (),
	orderAgainstTarget: (Node, Types.Dispose) -> Types.Dispose,
	inspector: () -> typeof(require "../ownership/inspect")
)
	local render = host.render
	local function mountFragment(fragment: Fragment, target: Node): (Dispose, { Node })
		local label = Block.nameOf(fragment)
		if type(target) ~= "table" and type(target) ~= "userdata" then
			return Diagnostics.raise("mount/target-not-a-node", "mountFragment expects a host node to mount into", {
				component = label,
				actual = Diagnostics.describe(target),
				expected = "a node belonging to the host this runtime renders to",
			})
		end
		refuseAfterDispose("mountFragment", label)
		claimTarget(target)

		local parent = Active.current()
		local isTopLevel = parent == nil
		local owner = parent or Owner.createOwner(reactor)
		if isTopLevel and inspecting.active then
			inspector().mount(owner)
			inspector().label(owner, label)
		end

		local blockOwner = Owner.createChild(owner)
		local roots: { Node } = {}
		local list = Children.createList(host, target)
		Owner.own(blockOwner, function()
			local failures: { string } = {}
			for index = #roots, 1, -1 do
				local removed, failure: unknown = pcall(render.removeChild, target, roots[index])
				if not removed then
					table.insert(failures, tostring(failure))
				end
			end
			if #failures > 0 then
				error(table.concat(failures, "\n"), 0)
			end
		end)

		local ok, err: unknown = pcall(function()
			local children = Active.withOwner(blockOwner, fragment)
			if type(children) ~= "table" then
				return Diagnostics.raise(
					"mount/not-a-child-list",
					"a fragment returned something that is not a list of children",
					{
						component = label,
						actual = Diagnostics.describe(children),
						expected = "an array of nodes and structural directives",
					}
				)
			end
			for index, child in children do
				local slot = Children.addSlot(list)
				if type(child) == "function" and constructorKinds[child] == nil then
					Active.withOwner(blockOwner, function()
						child(Children.mountPointFor(list, slot))
					end)
				elseif type(child) == "table" or type(child) == "userdata" then
					Children.insertStatic(list, slot, child)
					table.insert(roots, child)
				elseif constructorKinds[child] ~= nil then
					return Diagnostics.raise(
						"mount/constructor-not-applied",
						"a fragment child is a constructor that was never given props",
						{
							component = label,
							index = index,
							childKind = constructorKinds[child],
							label = pendingLabel[child],
							fix = if pendingLabel[child] ~= nil
								then ("write %s %q {} -- an empty table is fine"):format(
									constructorKinds[child],
									pendingLabel[child]
								)
								else ("write %s {} -- an empty table is fine"):format(constructorKinds[child]),
						}
					)
				else
					return Diagnostics.raise(
						"mount/not-a-child",
						"a fragment entry is neither a node nor a directive",
						{
							component = label,
							index = index,
							actual = Diagnostics.describe(child),
							expected = "a node, or a directive such as show(...) or keyed(...)",
						}
					)
				end
			end
		end)
		if not ok then
			Owner.dispose(blockOwner)
			if isTopLevel then
				Owner.dispose(owner)
			end
			error(err, 0)
		end

		if not isTopLevel then
			return Owner.disposer(blockOwner), roots
		end
		local detach = Owner.holdRoot(function()
			releaseInOrder(Owner.disposer(blockOwner), Owner.disposer(owner))
		end)
		return orderAgainstTarget(target, detach), roots
	end

	return mountFragment
end

return {
	createFragmentMount = createFragmentMount,
	decorate = decorate,
	connect = connect,
	adopt = adopt,
	borrow = borrow,
}
