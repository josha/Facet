--!strict
--!native

local Active = require "./ownership/active"
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
local RuntimeTypes = require "@self/types"
local Types = require "./reactive/types"
local Weak = require "./weak"

export type Node = Host.Node
type Dispose = Types.Dispose

local applying = Props.applying
local inspecting = Inspect.flag
local tracked = Nodes.tracked

export type Child = Node | Children.Directive

export type Directive = Children.Directive
export type MountPoint = Children.MountPoint
export type Props = Props.Props
export type SpringOptions = RuntimeTypes.SpringOptions
export type TimelineOptions = RuntimeTypes.TimelineOptions
export type Timeline = RuntimeTypes.Timeline
export type TweenOptions = RuntimeTypes.TweenOptions
export type RampOptions = RuntimeTypes.RampOptions
export type Ramp<T> = RuntimeTypes.Ramp<T>
export type Scheduler = RuntimeTypes.Scheduler
export type ObserveOptions = RuntimeTypes.ObserveOptions
export type ClockOptions = RuntimeTypes.ClockOptions
export type SettledOptions<T, R = unknown> = RuntimeTypes.SettledOptions<T, R>
export type SequenceOptions = RuntimeTypes.SequenceOptions
export type SequenceStep = RuntimeTypes.SequenceStep
export type Sequence = RuntimeTypes.Sequence

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

	connect: <Args...>(node: Node, event: string, handler: (Args...) -> ()) -> () -> (),

	adopt: (node: Node) -> Node,
	borrow: (node: Node) -> Node,

	spring: <T>(source: Types.Body<T>, options: SpringOptions?) -> Types.ReadOnlyValue<T>,

	tween: <T>(source: Types.Body<T>, options: TweenOptions?) -> Types.ReadOnlyValue<T>,
	timeline: (options: TimelineOptions?) -> Timeline,
	ramp: <T>(initial: T, options: RampOptions?) -> Ramp<T>,
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
	host = (
		setmetatable({}, {
			__index = function(_, key: string): unknown
				if key == "frames" then
					if supplied.frames ~= frameSource then
						frameSource = supplied.frames
						shared = if frameSource then (require "./frames")(frameSource, reactor) else nil
					end
					return shared
				end
				return ((supplied :: unknown) :: { [string]: unknown })[key]
			end,
		}) :: unknown
	) :: Host.Host
	local render = host.render

	local function requireOwner(operation: string): Owner.Owner
		local owner = Active.current()
		if owner == nil then
			error(
				Diagnostics.format(
					"owner/no-active-owner",
					("%s ran with no owner to register with"):format(operation),
					{
						contract = "nodes and bindings must belong to something that can release them",
						fix = "call it inside runtime.mount(component, target), or inside Compose.withOwner(owner, fn)",
					}
				),
				0
			)
		end
		return owner
	end

	local function destroyOwnedNode(node: Node)
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

	local pendingLabel: { [unknown]: string } = {}

	Weak.keys(pendingLabel)

	local function create(kind: string): Constructor
		if type(kind) ~= "string" then
			error(
				Diagnostics.format("mount/kind-not-a-string", "create expects a node kind", {
					actual = Diagnostics.describe(kind),
					expected = 'a string the host understands, e.g. "Frame"',
				}),
				0
			)
		end

		local operation = ("create(%q)"):format(kind)

		local function applyBuild(label: string?, props: Props.Props, node: Node, owner: Owner.Owner)
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

			local childCount = #props
			if childCount == 0 then
				return
			end

			applying.key = nil
			local list = Children.createList(host, node, supplied)
			local staticSlot = 0
			for index = 1, childCount do
				local child = props[index]
				local childType = type(child)
				if childType == "table" or childType == "userdata" then
					if staticSlot == 0 then
						staticSlot = Children.addSlot(list)
					end
					Children.insertStatic(list, staticSlot, child)
				elseif childType == "function" and pendingLabel[child] == nil then
					staticSlot = 0
					local slot = Children.addSlot(list);
					(child :: Children.Directive)(Children.mountPointFor(list, slot))
				elseif pendingLabel[child] ~= nil then
					error(
						Diagnostics.format(
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
						),
						0
					)
				else
					error(
						Diagnostics.format("mount/not-a-child", "a child is neither a node nor a directive", {
							kind = kind,
							index = index,
							actual = Diagnostics.describe(child),
							expected = "a node, or a directive such as show(...) or keyed(...)",
						}),
						0
					)
				end
			end
		end

		local function build(label: string?, props: Props.Props): Node
			if type(props) ~= "table" then
				error(
					Diagnostics.format("props/not-a-table", ("create(%q) expects a props table"):format(kind), {
						kind = kind,
						label = label,
						actual = Diagnostics.describe(props),
						expected = "a table of properties, with children in its array part",
					}),
					0
				)
			end

			local resolved, top = Active.resolve()
			local owner = if resolved ~= nil then resolved else requireOwner(operation)
			local mark = owner.head
			local heldMark = Owner.heldCount(owner)
			local node = render.createNode(kind)
			Nodes.markOwned(node)
			Owner.holdSubject(owner, destroyOwnedNode, node)
			if inspecting.active then
				Inspect.node(owner, node, "owned")
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
			end
		) :: Constructor
	end

	local function refuseAfterDispose(operation: string, label: string)
		if runtimeDisposed then
			error(
				Diagnostics.format("runtime/disposed", ("%s ran after runtime:dispose()"):format(operation), {
					component = label,
					contract = "a disposed runtime starts no new work",
					fix = "create a new runtime, or mount before disposing this one",
				}),
				0
			)
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
			error(
				Diagnostics.format("mount/target-not-a-node", "mount expects a host node to mount into", {
					component = label,
					actual = Diagnostics.describe(target),
					expected = "a node belonging to the host this runtime renders to",
				}),
				0
			)
		end
		refuseAfterDispose("mount", label)
		claimTarget(target)

		local parent = Active.current()
		local isTopLevel = parent == nil
		local owner = parent or Owner.createOwner(reactor)

		if isTopLevel and Inspect.isActive() then
			Inspect.mount(owner)
			Inspect.label(owner, label)
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

		local detach = Root.hold(function()
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
			error(
				Diagnostics.format("mount/target-not-a-node", "mountFragment expects a host node to mount into", {
					component = label,
					actual = Diagnostics.describe(target),
					expected = "a node belonging to the host this runtime renders to",
				}),
				0
			)
		end
		refuseAfterDispose("mountFragment", label)
		claimTarget(target)

		local parent = Active.current()
		local isTopLevel = parent == nil
		local owner = parent or Owner.createOwner(reactor)
		if isTopLevel and Inspect.isActive() then
			Inspect.mount(owner)
			Inspect.label(owner, label)
		end

		local blockOwner = Owner.createChild(owner)
		local roots: { Node } = {}
		local list = Children.createList(host, target)
		Owner.own(blockOwner, function()
			for index = #roots, 1, -1 do
				pcall(render.removeChild, target, roots[index])
			end
		end)

		local ok, err: unknown = pcall(function()
			local children = Active.withOwner(blockOwner, fragment)
			if type(children) ~= "table" then
				error(
					Diagnostics.format(
						"mount/not-a-child-list",
						"a fragment returned something that is not a list of children",
						{
							component = label,
							actual = Diagnostics.describe(children),
							expected = "an array of nodes and structural directives",
						}
					),
					0
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
					error(
						Diagnostics.format(
							"mount/constructor-not-applied",
							"a fragment child is a constructor that was never given props",
							{
								component = label,
								index = index,
								label = pendingLabel[child],
								fix = ("write Part %q { } -- an empty table is fine"):format(pendingLabel[child]),
							}
						),
						0
					)
				else
					error(
						Diagnostics.format("mount/not-a-child", "a fragment entry is neither a node nor a directive", {
							component = label,
							index = index,
							actual = Diagnostics.describe(child),
							expected = "a node, or a directive such as show(...) or keyed(...)",
						}),
						0
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
		local detach = Root.hold(function()
			releaseInOrder(Owner.disposer(blockOwner), Owner.disposer(owner))
		end)
		return orderAgainstTarget(target, detach), roots
	end

	local function decorate(node: Node, props: Props.Props): Node
		if type(node) ~= "table" and type(node) ~= "userdata" then
			error(
				Diagnostics.format("mount/not-a-node", "decorate expects an existing host node", {
					actual = Diagnostics.describe(node),
					expected = "a node belonging to the host this runtime renders to",
				}),
				0
			)
		end
		if type(props) ~= "table" then
			error(
				Diagnostics.format("props/not-a-table", "decorate expects a props table", {
					actual = Diagnostics.describe(props),
					expected = "a table of properties and event keys",
				}),
				0
			)
		end

		local parentOwner = requireOwner "decorate"
		local owner = Owner.createChild(parentOwner)

		local savedKey = applying.key
		applying.key = nil
		local ok, err: unknown = pcall(function()
			Active.withOwner(owner, function()
				Props.apply(supplied, node, props, owner)

				if #props > 0 then
					error(
						Diagnostics.format("props/decorate-has-children", "decorate cannot add children", {
							contract = "decorate only applies properties and events to an existing node",
							fix = "use a portal to mount children into a node Compose does not own",
						}),
						0
					)
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
			error(
				Diagnostics.format("mount/not-a-node", "connect expects an existing host node", {
					event = event,
					actual = Diagnostics.describe(node),
					expected = "a node belonging to the host this runtime renders to",
				}),
				0
			)
		end
		if type(handler) ~= "function" then
			error(
				Diagnostics.format("props/event-needs-handler", "connect expects a handler function", {
					event = event,
					actual = Diagnostics.describe(handler),
					expected = "a function",
				}),
				0
			)
		end

		local events = host.events
		if events == nil then
			error(
				Diagnostics.format("host/no-events", ("host %q cannot subscribe to events"):format(host.name), {
					event = event,
					contract = "subscribing requires the host events capability",
					fix = "implement host.events.connectEvent, or stop calling connect on this host",
				}),
				0
			)
		end

		local owner = requireOwner "connect"
		local unsubscribe = (events).connectEvent(node, event, handler)
		local detach = Owner.own(owner, unsubscribe)
		return detach
	end

	local function adopt(node: Node): Node
		local owner = requireOwner "adopt"
		if Nodes.custodyOf(node) == "owned" then
			error(
				Diagnostics.format("owner/already-owned", "adopt was given a node Compose already owns", {
					node = Host.describeNode(host, node),
					contract = "a node has exactly one owner; adopting a second time would destroy it twice",
					fix = "adopt only nodes created outside Compose",
				}),
				0
			)
		end
		Nodes.markAdopted(node)
		Owner.own(owner, function()
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

	local motion: RuntimeTypes.Motion? = nil
	local function motionOf(): RuntimeTypes.Motion
		local made = motion
		if made ~= nil then
			return made
		end
		local created = (require "./animation/motion").createMotion(host, requireOwner)
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

	local ramps: (<T>(initial: T, options: RampOptions?) -> Ramp<T>)? = nil
	local function ramp<T>(initial: T, options: RampOptions?): Ramp<T>
		local made = ramps
		if made ~= nil then
			return made(initial, options)
		end
		local created = (require "./animation/ramp").createRamps(motionOf().tween, requireOwner)
		ramps = created
		return created(initial, options)
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

	local function spring<T>(source: Types.Body<T>, options: SpringOptions?): Types.ReadOnlyValue<T>
		return motionOf().spring(source, options)
	end

	local function tween<T>(source: Types.Body<T>, options: TweenOptions?): Types.ReadOnlyValue<T>
		return motionOf().tween(source, options)
	end

	local function watch(_self: Runtime, body: (use: Types.Use) -> (), label: string?): Types.Dispose
		local active = Active.current()
		local owner = active or rootOwner
		return Owner.watch(owner, body, label)
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
