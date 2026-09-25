--!strict

local Active = require "./ownership/active"
local Animation = require "./animation/motion"
local TimelineModule = require "./animation/timeline"
local Block = require "@self/block"
local Children = require "@self/children"
local Diagnostics = require "./diagnostics"
local Host = require "./host"
local Inspect = require "./ownership/inspect"
local Nodes = require "./ownership/nodes"
local Owner = require "./ownership/owner"
local Reactor = require "./reactive/reactor"
local Props = require "@self/props"
local Root = require "./ownership/root"
local Types = require "./reactive/types"
local Weak = require "./weak"

export type Node = Host.Node
type Dispose = Types.Dispose

export type Child = Node | Children.Directive

export type Directive = Children.Directive
export type MountPoint = Children.MountPoint
export type Props = Props.Props
export type SpringOptions = Animation.SpringOptions
export type TimelineOptions = TimelineModule.Options
export type Timeline = TimelineModule.Timeline
export type TweenOptions = Animation.TweenOptions

export type Component = () -> Node

export type Fragment = () -> { Child }

export type Constructor = ((label: string) -> (props: Props.Props) -> Node) & ((props: {}) -> Node)

export type Runtime = {
	host: Host.Host,
	create: (kind: string) -> Constructor,
	constructors: { [string]: Constructor },
	mount: (component: Component, target: Node) -> (Dispose, Node),
	mountFragment: (fragment: Fragment, target: Node) -> (Dispose, { Node }),

	decorate: (node: Node, props: Props.Props) -> Node,

	connect: (node: Node, event: string, handler: (...any) -> ()) -> () -> (),

	adopt: (node: Node) -> Node,
	borrow: (node: Node) -> Node,

	spring: <T>(source: Types.Body<T>, options: Animation.SpringOptions?) -> Types.Readable<T>,

	tween: <T>(source: Types.Body<T>, options: Animation.TweenOptions?) -> Types.Readable<T>,
	timeline: (options: TimelineModule.Options?) -> TimelineModule.Timeline,

	reactor: Reactor.Reactor,

	watch: (self: Runtime, body: (use: Types.Use) -> (), label: string?) -> Types.Dispose,
	batch: <T...>(self: Runtime, body: () -> T...) -> T...,
	settle: (self: Runtime) -> (),
	pending: (self: Runtime) -> number,
	dispose: (self: Runtime) -> (),
}

local function createRuntime(host: Host.Host): Runtime
	local reactor = Reactor.create()

	local rootOwner = Owner.createOwner(reactor)
	local runtimeDisposed = false
	Host.validate(host)
	local render = host.render

	local function requireOwner(operation: string): Owner.Owner
		local owner = Active.current()
		if owner == nil then
			Diagnostics.raise("owner/no-active-owner", ("%s ran with no owner to register with"):format(operation), {
				contract = "nodes and bindings must belong to something that can release them",
				fix = "call it inside runtime.mount(component, target), or inside Compose.withOwner(owner, fn)",
			})
		end
		return owner :: Owner.Owner
	end

	local function destroyOwnedNode(node: Node)
		local ok, err: unknown = pcall(Nodes.releaseDependents, node)
		render.destroyNode(node)
		Nodes.forget(node)
		if not ok then
			error(err, 0)
		end
	end

	local pendingLabel = Weak.keys() :: { [unknown]: string }

	local function create(kind: string): Constructor
		if type(kind) ~= "string" then
			Diagnostics.raise("mount/kind-not-a-string", "create expects a node kind", {
				actual = Diagnostics.describe(kind),
				expected = 'a string the host understands, e.g. "Frame"',
			})
		end

		local operation = ("create(%q)"):format(kind)

		local inFlight: string? = nil
		local function onKey(key: string)
			inFlight = key
		end

		local function applyBuild(label: string?, props: Props.Props, node: Node, owner: Owner.Owner)
			if label ~= nil then
				Nodes.label(node, label)
				local naming = host.naming
				if naming ~= nil then
					inFlight = "<name>"
					naming.setName(node, label)
					inFlight = nil
				end
			end
			Props.apply(host, node, props, owner, onKey)

			local childCount = #props
			if childCount == 0 then
				return
			end

			inFlight = nil
			local list = Children.createList(host, node)
			for index = 1, childCount do
				local child = props[index]
				local slot = Children.addSlot(list)
				if type(child) == "function" and pendingLabel[child] == nil then
					(child :: Children.Directive)(Children.mountPointFor(list, slot))
				elseif type(child) == "table" or type(child) == "userdata" then
					Children.insertStatic(list, slot, child)
				elseif pendingLabel[child] ~= nil then
					Diagnostics.raise(
						"mount/constructor-not-applied",
						"a child is a constructor that was never given props",
						{
							kind = kind,
							index = index,
							label = pendingLabel[child],
							contract = ("%s %q is a constructor; it builds a node only once it is called with props"):format(
								kind,
								pendingLabel[child]
							),
							fix = ("write %s %q { } -- an empty table is fine"):format(kind, pendingLabel[child]),
						}
					)
				else
					Diagnostics.raise("mount/not-a-child", "a child is neither a node nor a directive", {
						kind = kind,
						index = index,
						actual = Diagnostics.describe(child),
						expected = "a node, or a directive such as show(...) or keyed(...)",
					})
				end
			end
		end

		local function build(label: string?, props: Props.Props): Node
			if type(props) ~= "table" then
				Diagnostics.raise("props/not-a-table", ("create(%q) expects a props table"):format(kind), {
					kind = kind,
					label = label,
					actual = Diagnostics.describe(props),
					expected = "a table of properties, with children in its array part",
				})
			end

			local owner = requireOwner(operation)
			local mark = owner.checkpoint()

			local node = render.createNode(kind)
			Nodes.markOwned(node)
			owner.own(function()
				destroyOwnedNode(node)
			end)
			if Inspect.isActive() then
				Inspect.node(owner, node, "owned")
				Nodes.chargeToOwner(owner, node, "owned")
			end

			local savedInFlight = inFlight
			inFlight = nil
			local ok, err: unknown = pcall(Active.runWith, owner, applyBuild, label, props, node, owner)
			if not ok then
				owner.rollbackTo(mark)
				local key = inFlight
				inFlight = savedInFlight
				if key ~= nil then
					error(("%s\n  while applying: %s.%s"):format(tostring(err), kind, tostring(key)), 0)
				end
				error(err, 0)
			end
			inFlight = savedInFlight

			return node
		end

		return (
			function(first: string | Props.Props): Node | (props: Props.Props) -> Node
				if type(first) == "string" then
					local labelled = function(props: Props.Props): Node
						return build(first, props)
					end
					pendingLabel[labelled] = first
					return labelled
				end
				return build(nil, first)
			end :: any
		) :: Constructor
	end

	local function refuseAfterDispose(operation: string, label: string)
		if runtimeDisposed then
			Diagnostics.raise("runtime/disposed", ("%s ran after runtime:dispose()"):format(operation), {
				component = label,
				contract = "a disposed runtime starts no new work",
				fix = "create a new runtime, or mount before disposing this one",
			})
		end
	end

	local function releaseInOrder(first: Dispose, second: Dispose)
		local firstOk, firstErr: unknown = pcall(first)
		local secondOk, secondErr: unknown = pcall(second)
		if not firstOk then
			error(firstErr, 0)
		end
		if not secondOk then
			error(secondErr, 0)
		end
	end

	local function claimTarget(target: Node)
		if not Nodes.isDestructible(target) then
			Nodes.markBorrowed(target)
		end
	end

	local function orderAgainstTarget(target: Node, detach: Dispose): Dispose
		if not Nodes.isDestructible(target) then
			return detach
		end
		local unlink = Nodes.attachDependent(target, detach)
		return function()
			unlink()
			detach()
		end
	end

	local function mountInto(produce: () -> { Node }, target: Node, label: string): (Dispose, { Node })
		if type(target) ~= "table" and type(target) ~= "userdata" then
			Diagnostics.raise("mount/target-not-a-node", "mount expects a host node to mount into", {
				component = label,
				actual = Diagnostics.describe(target),
				expected = "a node belonging to the host this runtime renders to",
			})
		end
		refuseAfterDispose("mount", label)
		claimTarget(target)

		local parent = Active.current()
		local isTopLevel = parent == nil
		local owner = if parent ~= nil then parent else Owner.createOwner(reactor)

		if isTopLevel and Inspect.isActive() then
			Inspect.mount(owner)
			Inspect.label(owner, label)
		end

		local mountPoint = Children.wholeOf(host, target)
		local ok, block = pcall(Block.mountBlock, mountPoint, owner, produce, label, nil)
		if not ok then
			if isTopLevel then
				owner.dispose()
			end
			error(block, 0)
		end

		if not isTopLevel then
			return block.dispose, block.nodes
		end

		local detach = Root.hold(function()
			releaseInOrder(block.dispose, owner.dispose)
		end)
		return orderAgainstTarget(target, detach), block.nodes
	end

	local function mount(component: Component, target: Node): (Dispose, Node)
		local label = Block.nameOf(component)
		local dispose, nodes = mountInto(function(): { Node }
			return { component() }
		end, target, label)
		return dispose, nodes[1]
	end

	local function mountFragment(fragment: Fragment, target: Node): (Dispose, { Node })
		local label = Block.nameOf(fragment)
		if type(target) ~= "table" and type(target) ~= "userdata" then
			Diagnostics.raise("mount/target-not-a-node", "mountFragment expects a host node to mount into", {
				component = label,
				actual = Diagnostics.describe(target),
				expected = "a node belonging to the host this runtime renders to",
			})
		end
		refuseAfterDispose("mountFragment", label)
		claimTarget(target)

		local parent = Active.current()
		local isTopLevel = parent == nil
		local owner = if parent ~= nil then parent else Owner.createOwner(reactor)
		if isTopLevel and Inspect.isActive() then
			Inspect.mount(owner)
			Inspect.label(owner, label)
		end

		local blockOwner = owner.createChild()
		local roots: { Node } = {}
		local list = Children.createList(host, target)
		blockOwner.own(function()
			for index = #roots, 1, -1 do
				pcall(render.removeChild, target, roots[index])
			end
		end)

		local ok, err: unknown = pcall(function()
			local children = Active.withOwner(blockOwner, fragment)
			if type(children) ~= "table" then
				Diagnostics.raise(
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
				if type(child) == "function" and pendingLabel[child] == nil then
					Active.withOwner(blockOwner, function()
						(child :: Children.Directive)(Children.mountPointFor(list, slot))
					end)
				elseif type(child) == "table" or type(child) == "userdata" then
					Children.insertStatic(list, slot, child)
					table.insert(roots, child)
				elseif pendingLabel[child] ~= nil then
					Diagnostics.raise(
						"mount/constructor-not-applied",
						"a fragment child is a constructor that was never given props",
						{
							component = label,
							index = index,
							label = pendingLabel[child],
							fix = ("write Part %q { } -- an empty table is fine"):format(pendingLabel[child]),
						}
					)
				else
					Diagnostics.raise("mount/not-a-child", "a fragment entry is neither a node nor a directive", {
						component = label,
						index = index,
						actual = Diagnostics.describe(child),
						expected = "a node, or a directive such as show(...) or keyed(...)",
					})
				end
			end
		end)
		if not ok then
			blockOwner.dispose()
			if isTopLevel then
				owner.dispose()
			end
			error(err, 0)
		end

		if not isTopLevel then
			return blockOwner.dispose, roots
		end
		local detach = Root.hold(function()
			releaseInOrder(blockOwner.dispose, owner.dispose)
		end)
		return orderAgainstTarget(target, detach), roots
	end

	local function decorate(node: Node, props: Props.Props): Node
		if type(node) ~= "table" and type(node) ~= "userdata" then
			Diagnostics.raise("mount/not-a-node", "decorate expects an existing host node", {
				actual = Diagnostics.describe(node),
				expected = "a node belonging to the host this runtime renders to",
			})
		end
		if type(props) ~= "table" then
			Diagnostics.raise("props/not-a-table", "decorate expects a props table", {
				actual = Diagnostics.describe(props),
				expected = "a table of properties and event keys",
			})
		end

		local parentOwner = requireOwner "decorate"
		local owner = parentOwner.createChild()

		local inFlight: string? = nil
		local ok, err: unknown = pcall(function()
			Active.withOwner(owner, function()
				Props.apply(host, node, props, owner, function(key: string)
					inFlight = key
				end)

				if #props > 0 then
					Diagnostics.raise("props/decorate-has-children", "decorate cannot add children", {
						contract = "decorate only applies properties and events to an existing node",
						fix = "use a portal to mount children into a node Compose does not own",
					})
				end
				return nil
			end)
		end)

		if not ok then
			owner.dispose()
			if inFlight ~= nil then
				error(("%s\n  while applying: decorate.%s"):format(tostring(err), tostring(inFlight)), 0)
			end
			error(err, 0)
		end

		return node
	end

	local function connect(node: Node, event: string, handler: (...any) -> ()): () -> ()
		if type(node) ~= "table" and type(node) ~= "userdata" then
			Diagnostics.raise("mount/not-a-node", "connect expects an existing host node", {
				event = event,
				actual = Diagnostics.describe(node),
				expected = "a node belonging to the host this runtime renders to",
			})
		end
		if type(handler) ~= "function" then
			Diagnostics.raise("props/event-needs-handler", "connect expects a handler function", {
				event = event,
				actual = Diagnostics.describe(handler),
				expected = "a function",
			})
		end

		local events = host.events
		if events == nil then
			Diagnostics.raise("host/no-events", ("host %q cannot subscribe to events"):format(host.name), {
				event = event,
				contract = "subscribing requires the host events capability",
				fix = "implement host.events.connectEvent, or stop calling connect on this host",
			})
		end

		local owner = requireOwner "connect"
		local unsubscribe = (events :: Host.Events).connectEvent(node, event, handler)
		local detach = owner.own(unsubscribe)
		return detach
	end

	local function adopt(node: Node): Node
		local owner = requireOwner "adopt"
		if Nodes.custodyOf(node) == "owned" then
			Diagnostics.raise("owner/already-owned", "adopt was given a node Compose already owns", {
				node = Host.describeNode(host, node),
				contract = "a node has exactly one owner; adopting a second time would destroy it twice",
				fix = "adopt only nodes created outside Compose",
			})
		end
		Nodes.markAdopted(node)
		owner.own(function()
			destroyOwnedNode(node)
		end)
		if Inspect.isActive() then
			Inspect.node(owner, node, "adopted")
			Nodes.chargeToOwner(owner, node, "adopted")
		end
		return node
	end

	local function borrow(node: Node): Node
		Nodes.markBorrowed(node)
		if Inspect.isActive() then
			local holder = Active.current()
			if holder ~= nil then
				Inspect.node(holder, node, "borrowed")
				Nodes.chargeToOwner(holder, node, "borrowed")
			end
		end
		return node
	end

	local motion = Animation.createMotion(host, requireOwner, reactor)
	local timelines = TimelineModule.createTimelines(host, requireOwner)

	local function watch(_self: Runtime, body: (use: Types.Use) -> (), label: string?): Types.Dispose
		local active = Active.current()
		local owner = if active ~= nil then active else rootOwner
		return owner.watch(body, label)
	end

	local constructors: { [string]: Constructor } = {}
	setmetatable(constructors :: { [string]: Constructor }, {
		__index = function(self: { [string]: Constructor }, kind: string): Constructor
			local constructor = create(kind)
			rawset(self, kind, constructor)
			return constructor
		end,
	})

	return {
		host = host,
		reactor = reactor,
		watch = watch,
		batch = function<T...>(_self: Runtime, body: () -> T...): T...
			return reactor:batch(body)
		end,
		settle = function(_self: Runtime)
			reactor:settle()
		end,
		pending = function(_self: Runtime): number
			return reactor:pending()
		end,
		dispose = function(_self: Runtime)
			runtimeDisposed = true
			rootOwner.dispose()
		end,
		connect = connect,
		create = create,
		constructors = constructors,
		decorate = decorate,
		mount = mount,
		mountFragment = mountFragment,
		adopt = adopt,
		borrow = borrow,
		spring = motion.spring,
		tween = motion.tween,
		timeline = timelines.timeline,
	}
end

return {
	createRuntime = createRuntime,
}
