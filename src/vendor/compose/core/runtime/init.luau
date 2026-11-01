--!strict
--!native

local Codec = require "./animation/codec"
local Active = require "./ownership/active"
local Children = require "@self/children"
local Block = Children.block
local Diagnostics = require "./diagnostics"
local Dynamic = require "./dynamic"
local Host = require "./host"
local Nodes = require "./ownership/nodes"
local Owner = require "./ownership/owner"
local Reactor = require "./reactive/reactor"
local Props = require "@self/props"
local CoreTypes = require "./types"
local Types = require "./reactive/types"

local WEAK_KEYS = table.freeze { __mode = "k" }

export type Node = Host.Node
type Dispose = Types.Dispose

local applying = Props.applying
local inspecting = Nodes.inspecting

local inspectModule: typeof(require "./ownership/inspect")? = nil

local function inspector(): typeof(require "./ownership/inspect")
	local loaded = inspectModule
	if loaded ~= nil then
		return loaded
	end
	local required = require "./ownership/inspect"
	inspectModule = required
	return required
end
local tracked = Nodes.tracked

export type Child = Host.Child

export type Directive = Children.Directive
export type MountPoint = Children.MountPoint
export type Props = Props.Props
export type SpringOptions = CoreTypes.SpringOptions
export type TimelineOptions = CoreTypes.TimelineOptions
export type Timeline = CoreTypes.Timeline
export type TweenOptions = CoreTypes.TweenOptions
export type RampOptions = CoreTypes.RampOptions
export type Ramp<T> = CoreTypes.Ramp<T>
export type Scheduler = CoreTypes.Scheduler
export type ObserveOptions = CoreTypes.ObserveOptions
export type ClockOptions = CoreTypes.ClockOptions
export type SettledOptions<T, R = unknown> = CoreTypes.SettledOptions<T, R>
export type SequenceOptions = CoreTypes.SequenceOptions
export type SequenceStep = CoreTypes.SequenceStep
export type Sequence = CoreTypes.Sequence

export type Component = () -> Node

export type Fragment = () -> { read [number]: Child? }

local function propsReference(value: unknown)
	assert(type(value) == "table")
	return value
end

type ConstructorProps = typeof(propsReference(nil))

export type Constructor =
	((props: ConstructorProps, label: string?) -> Node)
	& ((label: string) -> (props: unknown) -> Node)

export type Runtime = {
	host: Host.Host,
	create: (kind: string) -> Constructor,
	constructors: { [string]: Constructor },
	mount: (component: Component, target: Node) -> (Dispose, Node),
	mountFragment: (fragment: Fragment, target: Node) -> (Dispose, { Node }),

	decorate: (node: Node, props: {}) -> Node,

	connect: <Args...>(node: Node, event: string, handler: (Args...) -> ()) -> () -> (),

	adopt: (node: Node) -> Node,
	borrow: (node: Node) -> Node,

	motion: <T>(codec: Codec.Codec<T>) -> CoreTypes.Motion<T>,
	spring: (source: Types.Body<number>, options: SpringOptions?) -> Types.ReadOnlyValue<number>,

	tween: (source: Types.Body<number>, options: TweenOptions?) -> Types.ReadOnlyValue<number>,
	timeline: (options: TimelineOptions?) -> Timeline,
	ramp: (initial: number, options: RampOptions?) -> Ramp<number>,
	scheduler: (owner: Owner.Owner?) -> Scheduler,
	observe: (node: Node, property: string, options: ObserveOptions?) -> Types.ReadOnlyValue<unknown>,
	settled: <T, R>(options: SettledOptions<T, R>) -> Types.ReadOnlyValue<boolean>,
	clock: (options: ClockOptions?) -> Types.ReadOnlyValue<number>,
	sequence: (options: SequenceOptions) -> Sequence,

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
	local supplied = host
	local frameSource: Host.Frames? = nil
	local shared: Host.Frames? = nil
	local scoped: Host.Host = table.clone(supplied)
	scoped.frames = nil
	setmetatable(scoped, {
		__index = function(_, key: string): Host.Frames?
			if key ~= "frames" then
				return nil
			end
			if supplied.frames ~= frameSource then
				frameSource = supplied.frames
				shared = if frameSource then (require "./frames")(frameSource, reactor) else nil
			end
			return shared
		end,
	})
	host = scoped
	local render = host.render

	local function requireOwner(operation: string): Owner.Owner
		local owner = Active.current()
		if owner == nil then
			return Diagnostics.raise(
				"owner/no-active-owner",
				("%s ran with no owner to register with"):format(operation),
				{
					contract = "nodes and bindings must belong to something that can release them",
					fix = "call it inside runtime.mount(component, target), or inside Compose.withOwner(owner, fn)",
				}
			)
		end
		return owner
	end

	local function destroyOwnedNode(subject: unknown)
		if type(subject) ~= "table" and type(subject) ~= "userdata" then
			return Diagnostics.raise("host/node-not-a-reference", "owned node is not a reference", {})
		end
		local node = subject
		Props.forget(node)
		if tracked.dependents == 0 then
			render.destroyNode(node)
			Nodes.forget(node)
			return
		end
		local ok, err: unknown = pcall(Nodes.releaseDependents, node)
		render.destroyNode(node)
		Nodes.forget(node)
		if not ok then
			error(err, 0)
		end
	end

	local constructorKinds: { [unknown]: string } = {}
	local pendingLabel: { [unknown]: string } = {}

	setmetatable(constructorKinds, WEAK_KEYS)
	setmetatable(pendingLabel, WEAK_KEYS)

	local function buildConstructor(kind: string)
		if type(kind) ~= "string" then
			return Diagnostics.raise("mount/kind-not-a-string", "create expects a node kind", {
				actual = Diagnostics.describe(kind),
				expected = 'a string the host understands, e.g. "Frame"',
			})
		end

		local operation = ("create(%q)"):format(kind)

		local function applyBuild(label: string?, props: unknown, node: Node, owner: Owner.Owner)
			assert(type(props) == "table")
			local entries = Dynamic.entries(props)
			if label ~= nil then
				Nodes.label(node, label)
				local naming = supplied.naming
				if naming ~= nil then
					applying.key = "<name>"
					naming.setName(node, label)
					applying.key = nil
				end
			end
			Props.apply(supplied, node, props, owner, true)

			local childCount = #entries
			if childCount == 0 then
				return
			end

			applying.key = nil
			local list = Children.createList(host, node, supplied)
			local staticSlot = 0
			for index = 1, childCount do
				local child = entries[index]
				if type(child) == "table" or type(child) == "userdata" then
					if staticSlot == 0 then
						staticSlot = Children.addSlot(list)
					end
					Children.insertStatic(list, staticSlot, child)
				elseif type(child) == "function" and constructorKinds[child] == nil then
					staticSlot = 0
					local slot = Children.addSlot(list)
					child(Children.mountPointFor(list, slot))
				elseif constructorKinds[child] ~= nil then
					return Diagnostics.raise(
						"mount/constructor-not-applied",
						"a child is a constructor that was never given props",
						{
							kind = kind,
							index = index,
							childKind = constructorKinds[child],
							label = pendingLabel[child],
							contract = "a constructor builds a node only once it is called with props",
							fix = if pendingLabel[child] ~= nil
								then ("write %s %q {} -- an empty table is fine"):format(
									constructorKinds[child],
									pendingLabel[child]
								)
								else ("write %s {} -- an empty table is fine"):format(constructorKinds[child]),
						}
					)
				else
					return Diagnostics.raise("mount/not-a-child", "a child is neither a node nor a directive", {
						kind = kind,
						index = index,
						actual = Diagnostics.describe(child),
						expected = "a node, or a directive such as show(...) or keyed(...)",
					})
				end
			end
		end

		local function build(label: string?, props: unknown): Node
			if type(props) ~= "table" then
				return Diagnostics.raise("props/not-a-table", ("create(%q) expects a props table"):format(kind), {
					kind = kind,
					label = label,
					actual = Diagnostics.describe(props),
					expected = "a table of properties, with children in its array part",
				})
			end

			local resolved, top = Active.resolve()
			local owner = if resolved ~= nil then resolved else requireOwner(operation)
			local mark = owner.head
			local heldMark = Owner.heldCount(owner)
			local node = render.createNode(kind)
			Nodes.markOwned(node)
			Owner.holdSubject(owner, destroyOwnedNode, node)
			if inspecting.active then
				inspector().node(owner, node, "owned")
				Nodes.chargeToOwner(owner, node, "owned")
			end

			local savedKey = applying.key
			applying.key = nil
			local running = if top then nil else Active.push(owner)
			local ok, err: unknown = pcall(applyBuild, label, props, node, owner)
			if running ~= nil then
				Active.pop(owner, running)
			end
			if not ok then
				Owner.rollbackTo(owner, mark)
				Owner.rollbackHeld(owner, heldMark)
				local key = applying.key
				applying.key = savedKey
				if key ~= nil then
					error(("%s\n  while applying: %s.%s"):format(tostring(err), kind, tostring(key)), 0)
				end
				error(err, 0)
			end
			applying.key = savedKey

			return node
		end

		local function constructor(props: unknown, label: string?): Node | ((props: unknown) -> Node)
			if type(props) == "string" then
				local function labelled(properties: unknown): Node
					return build(props, properties)
				end
				constructorKinds[labelled] = kind
				pendingLabel[labelled] = props
				return labelled
			end
			return build(label, props)
		end
		constructorKinds[constructor] = kind
		return constructor
	end

	local constructors: { [string]: Constructor } = {}
	setmetatable(constructors, {
		__index = function(self, kind: string)
			local constructor = buildConstructor(kind)
			rawset(self, kind, constructor)
			return constructor
		end,
	})

	local function create(kind: string): Constructor
		return constructors[kind]
	end

	local function refuseAfterDispose(operation: string, label: string)
		if runtimeDisposed then
			return Diagnostics.raise("runtime/disposed", ("%s ran after runtime:dispose()"):format(operation), {
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
			return Diagnostics.raise("mount/target-not-a-node", "mount expects a host node to mount into", {
				component = label,
				actual = Diagnostics.describe(target),
				expected = "a node belonging to the host this runtime renders to",
			})
		end
		refuseAfterDispose("mount", label)
		claimTarget(target)

		local parent = Active.current()
		local isTopLevel = parent == nil
		local owner = parent or Owner.createOwner(reactor)

		if isTopLevel and inspecting.active then
			inspector().mount(owner)
			inspector().label(owner, label)
		end

		local mountPoint = Children.wholeOf(host, target)
		local ok, block = pcall(Block.mountBlock, mountPoint, owner, produce, label, nil, false)
		if not ok then
			if isTopLevel then
				Owner.dispose(owner)
			end
			error(block, 0)
		end

		if not isTopLevel then
			return Owner.disposer(block.owner), block.nodes
		end

		local detach = Owner.holdRoot(function()
			releaseInOrder(Owner.disposer(block.owner), Owner.disposer(owner))
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

	local function decorate(node: Node, props: unknown): Node
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

	local function connect<Args...>(node: Node, event: string, handler: (Args...) -> ()): () -> ()
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

	local function adopt(node: Node): Node
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

	local function borrow(node: Node): Node
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

	local motion: CoreTypes.Motion<number>? = nil
	local function typedMotion<T>(codec: Codec.Codec<T>): CoreTypes.Motion<T>
		return (require "./animation/motion").createMotion(host, requireOwner, codec)
	end
	local function motionOf(): CoreTypes.Motion<number>
		local made = motion
		if made ~= nil then
			return made
		end
		local created = typedMotion(Codec.number)
		motion = created
		return created
	end

	local timelines: ((options: TimelineOptions?) -> Timeline)? = nil
	local function timeline(options: TimelineOptions?): Timeline
		local made = timelines
		if made ~= nil then
			return made(options)
		end
		local created = (require "./animation/timeline").createTimelines(host, requireOwner).timeline
		timelines = created
		return created(options)
	end

	local function ramp(initial: number, options: RampOptions?): Ramp<number>
		return motionOf().ramp(initial, options)
	end

	local schedulers: ((owner: Owner.Owner?) -> Scheduler)? = nil
	local function scheduler(owner: Owner.Owner?): Scheduler
		local made = schedulers
		if made ~= nil then
			return made(owner)
		end
		local created = (require "./scheduler").createSchedulers(host, requireOwner)
		schedulers = created
		return created(owner)
	end

	local observers: ((node: Node, property: string, options: ObserveOptions?) -> Types.ReadOnlyValue<unknown>)? = nil
	local function observe(node: Node, property: string, options: ObserveOptions?): Types.ReadOnlyValue<unknown>
		local made = observers
		if made ~= nil then
			return made(node, property, options)
		end
		local created = (require "@self/observe")(host, requireOwner, reactor)
		observers = created
		return created(node, property, options)
	end

	local settles: (<T, R>(options: SettledOptions<T, R>) -> Types.ReadOnlyValue<boolean>)? = nil
	local function settled<T, R>(options: SettledOptions<T, R>): Types.ReadOnlyValue<boolean>
		local made = settles
		if made ~= nil then
			return made(options)
		end
		local created = (require "@self/settled")(host, requireOwner)
		settles = created
		return created(options)
	end

	local clocks: ((options: ClockOptions?) -> Types.ReadOnlyValue<number>)? = nil
	local function clock(options: ClockOptions?): Types.ReadOnlyValue<number>
		local made = clocks
		if made ~= nil then
			return made(options)
		end
		local created = (require "@self/clock")(host, requireOwner)
		clocks = created
		return created(options)
	end

	local sequences: ((options: SequenceOptions) -> Sequence)? = nil
	local function sequence(options: SequenceOptions): Sequence
		local made = sequences
		if made ~= nil then
			return made(options)
		end
		local created = (require "@self/sequence")(timeline, requireOwner)
		sequences = created
		return created(options)
	end

	local function spring(source: Types.Body<number>, options: SpringOptions?): Types.ReadOnlyValue<number>
		return motionOf().spring(source, options)
	end

	local function tween(source: Types.Body<number>, options: TweenOptions?): Types.ReadOnlyValue<number>
		return motionOf().tween(source, options)
	end

	local function watch(_self: Runtime, body: (use: Types.Use) -> (), label: string?): Types.Dispose
		local active = Active.current()
		local owner = active or rootOwner
		return Owner.watch(owner, body, label)
	end

	return {
		host = supplied,
		reactor = reactor,
		watch = watch,
		batch = Reactor.batchMethod(reactor),
		settle = function(_self: Runtime)
			Reactor.settle(reactor)
		end,
		pending = function(_self: Runtime): number
			return Reactor.pending(reactor)
		end,
		dispose = function(_self: Runtime)
			runtimeDisposed = true
			Owner.dispose(rootOwner)
		end,
		connect = connect,
		create = create,
		constructors = constructors,
		decorate = decorate,
		mount = mount,
		mountFragment = mountFragment,
		adopt = adopt,
		borrow = borrow,
		motion = typedMotion,
		spring = spring,
		tween = tween,
		timeline = timeline,
		ramp = ramp,
		scheduler = scheduler,
		observe = observe,
		settled = settled,
		clock = clock,
		sequence = sequence,
	}
end

return {
	createRuntime = createRuntime,
}
