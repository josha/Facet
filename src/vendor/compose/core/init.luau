--!strict

local Active = require "@self/ownership/active"
local AnimationCodec = require "@self/animation/codec"
local AnimationEasing = require "@self/animation/easing"
local AsyncShared = require "@self/async/shared"
local ContextModule = require "@self/context"
local Diagnostics = require "@self/diagnostics"
local Geometry = require "@self/geometry"
local FocusTypes = require "@self/focus-types"
local Graph = require "@self/reactive/graph"
local NodeCast = require "@self/reactive/node"
local Inspect = require "@self/ownership/inspect"
local HostProtocol = require "@self/host"
local Keys = require "@self/runtime/keys"
local Props = require "@self/runtime/props"
local OwnerModule = require "@self/ownership/owner"
local Root = require "@self/ownership/root"
local ResourceTypes = require "@self/resource-types"
local StructureTypes = require "@self/structure/types"
local RuntimeTypes = require "@self/runtime/types"
local RuntimeModule = require "@self/runtime"
local Types = require "@self/reactive/types"
local clock = require "@self/reactive/clock"
local cellModule = require "@self/reactive/cell"
local nodes = require "@self/ownership/nodes"
local formulaModule = require "@self/reactive/formula"
local reactorModule = require "@self/reactive/reactor"
local stats = require "@self/reactive/stats"
local watchModule = require "@self/reactive/watch"
local userSpace = require "@self/reactive/userSpace"

export type Dispose = Types.Dispose
export type Use = Types.Use
export type Body<T> = Types.Body<T>
export type Source<T> = Types.Source<T>
export type Value<T> = Types.Value<T>
export type ReadOnlyValue<T> = Types.ReadOnlyValue<T>
export type Input<T> = Types.Input<T>
export type Equals<T> = Types.Equals<T>
export type Reactor = reactorModule.Reactor
export type AccumulatorOptions<T, E> = Types.AccumulatorOptions<T, E>

export type Owner = OwnerModule.Owner
export type Context<T> = ContextModule.Context<T>
export type RootScope = ResourceTypes.RootScope
export type Custody = nodes.Custody

export type Node = HostProtocol.Node
export type Host = HostProtocol.Host
export type Renderer = HostProtocol.Renderer
export type Events = HostProtocol.Events
export type Observation = HostProtocol.Observation
export type Frames = HostProtocol.Frames
export type Naming = HostProtocol.Naming
export type KeyKind = HostProtocol.KeyKind
export type Unsubscribe = HostProtocol.Unsubscribe

export type Runtime = RuntimeModule.Runtime
export type Constructor = RuntimeModule.Constructor
export type Component = RuntimeModule.Component
export type Fragment = RuntimeModule.Fragment
export type Child = RuntimeModule.Child
export type Props = RuntimeModule.Props
export type Directive = RuntimeModule.Directive
export type PresenceOptions = StructureTypes.PresenceOptions
export type Exiting = StructureTypes.Exiting
export type MountPoint = RuntimeModule.MountPoint

export type FocusScope<K> = FocusTypes.FocusScope<K>
export type FocusScopeOptions<V, K> = FocusTypes.Options<V, K>
export type FocusDirection = FocusTypes.Direction
export type FocusRect = FocusTypes.FocusRect

export type Pool<T> = ResourceTypes.Pool<T>
export type PoolLease<T> = ResourceTypes.Lease<T>
export type PoolOptions<T> = ResourceTypes.PoolOptions<T>

export type KeyedCache<K, T> = ResourceTypes.KeyedCache<K, T>
export type KeyedCacheOptions<K, T> = ResourceTypes.KeyedCacheOptions<K, T>

export type Easing = AnimationEasing.Easing
export type Codec<T> = AnimationCodec.Codec<T>
export type SpringState = RuntimeTypes.SpringState
export type SpringOptions = RuntimeModule.SpringOptions
export type TweenOptions = RuntimeModule.TweenOptions
export type RampOptions = RuntimeModule.RampOptions
export type Ramp<T> = RuntimeModule.Ramp<T>
export type Scheduler = RuntimeModule.Scheduler
export type ObserveOptions = RuntimeModule.ObserveOptions
export type ClockOptions = RuntimeModule.ClockOptions
export type SettledOptions<T, R = unknown> = RuntimeModule.SettledOptions<T, R>
export type SequenceOptions = RuntimeModule.SequenceOptions
export type SequenceStep = RuntimeModule.SequenceStep
export type Sequence = RuntimeModule.Sequence
export type Slot = ResourceTypes.Slot

export type GeometrySize = Geometry.Size
export type GeometryInsets = Geometry.Insets
export type GeometryAnchor = Geometry.Anchor
export type GeometryFrame = Geometry.Frame
export type GeometryBounds = Geometry.Bounds
export type GeometryFitOptions = Geometry.FitOptions
export type GeometryClearOptions<R> = Geometry.ClearOptions<R>

export type SharedResourceFactory<T> = AsyncShared.Factory<T>
export type AcquireSharedResource<T> = AsyncShared.Acquire<T>

export type KeyedRender<V, K> = StructureTypes.KeyedRender<V, K>
export type IndexedRender<V> = StructureTypes.IndexedRender<V>

export type Placement = StructureTypes.Placement
export type OrderedCollectionMode = StructureTypes.OrderedCollectionMode
export type OrderedCollectionDirection = StructureTypes.OrderedCollectionDirection
export type OrderedCollectionLayoutKind = StructureTypes.OrderedCollectionLayoutKind
export type OrderedCollectionAlign = StructureTypes.OrderedCollectionAlign
export type OrderedCollectionLayout = StructureTypes.OrderedCollectionLayout
export type OrderedCollectionViewport = StructureTypes.OrderedCollectionViewport
export type OrderedCollectionStatus = StructureTypes.OrderedCollectionStatus
export type OrderedCollectionControls<K> = StructureTypes.OrderedCollectionControls<K>
export type OrderedCollectionOptions<V, K> = StructureTypes.OrderedCollectionOptions<V, K>
export type SpatialCollectionTier = StructureTypes.SpatialCollectionTier
export type SpatialCollectionPoint = StructureTypes.SpatialCollectionPoint
export type Representation = StructureTypes.Representation
export type SpatialCollectionBudget = StructureTypes.SpatialCollectionBudget
export type SpatialCollectionStatus = StructureTypes.SpatialCollectionStatus
export type SpatialCollectionOptions<V, K> = StructureTypes.SpatialCollectionOptions<V, K>
export type TileCollectionViewport = StructureTypes.TileCollectionViewport
export type TileCollectionSize = StructureTypes.TileCollectionSize
export type TileCollectionPlacement = StructureTypes.TileCollectionPlacement
export type TileCollectionOptions<V> = StructureTypes.TileCollectionOptions<V>
export type LayerStackRetention = StructureTypes.LayerStackRetention
export type LayerStackState = StructureTypes.LayerStackState
export type LayerStackOptions<V, K> = StructureTypes.LayerStackOptions<V, K>
export type MountBudgetStatus = StructureTypes.MountBudgetStatus
export type MountBudgetOptions<V, K> = StructureTypes.MountBudgetOptions<V, K>

export type WorkCounters = stats.Counters
export type Diagnostic = Diagnostics.Parsed
export type ProfileOptions = Types.ProfileOptions
export type ProfileReport = Types.ProfileReport
export type ProfileNode = Types.ProfileNodeRow
export type ProfileDrain = Types.ProfileDrainRow
export type ProfileData = Types.ProfileData
export type InspectOptions = Inspect.Options
export type InspectReport = Inspect.Report
export type InspectOwner = Inspect.OwnerReport
export type InspectNode = Inspect.NodeReport
export type InspectOwnedCounts = nodes.OwnedCounts
export type InspectData = Inspect.Data

local function once<T>(load: () -> T): () -> T
	local loaded: T? = nil
	return function(): T
		local value = loaded
		if value ~= nil then
			return value
		end
		local made = load()
		loaded = made
		return made
	end
end

type Builder = () -> HostProtocol.Node | Directive
type NodesBuilder = () -> { HostProtocol.Node }

local profileModule = once(function()
	return require "@self/reactive/profile"
end)
local rootScopeModule = once(function()
	return require "@self/ownership/root-scope"
end)
local springModule = once(function()
	return require "@self/animation/spring"
end)
local poolModule = once(function()
	return require "@self/pool"
end)
local keyedCacheModule = once(function()
	return require "@self/keyed-cache"
end)
local slotModule = once(function()
	return require "@self/slot"
end)
local accumulatorModule = once(function()
	return require "@self/accumulator"
end)
local selectorModule = once(function()
	return require "@self/selector"
end)
local boundaryModule = once(function()
	return require "@self/async/boundary"
end)
local focusScopeModule = once(function()
	return require "@self/focus-scope"
end)
local focusNeighborModule = once(function()
	return require "@self/focus-neighbor"
end)
local reportModule = once(function()
	return require "@self/ownership/report"
end)
local presenceModule = once(function()
	return require "@self/structure/presence"
end)
local showModule = once(function()
	return require "@self/structure/show"
end)
local switchModule = once(function()
	return require "@self/structure/switch"
end)
local keyedModule = once(function()
	return require "@self/structure/keyed"
end)
local indexesModule = once(function()
	return require "@self/structure/indexes"
end)
local orderedCollectionModule = once(function()
	return require "@self/structure/ordered-collection"
end)
local spatialCollectionModule = once(function()
	return require "@self/structure/spatial-collection"
end)
local tileCollectionModule = once(function()
	return require "@self/structure/tile-collection"
end)
local layerStackModule = once(function()
	return require "@self/structure/layer-stack"
end)
local mountBudgetModule = once(function()
	return require "@self/structure/mount-budget"
end)
local fragmentModule = once(function()
	return require "@self/structure/fragment"
end)
local portalModule = once(function()
	return require "@self/structure/portal"
end)

local function withRootOwner<T...>(body: (owner: OwnerModule.Owner) -> T..., reactor: Types.Reactor?): T...
	return rootScopeModule().withRootOwner(body, reactor)
end

local function createRootOwner(body: (owner: OwnerModule.Owner) -> (), reactor: Types.Reactor?): ResourceTypes.RootScope
	return rootScopeModule().createRootOwner(body, reactor)
end

local function createSpringState(position: { number }, arity: number): RuntimeTypes.SpringState
	return springModule().createState(position, arity)
end

local function stepSpring(
	state: RuntimeTypes.SpringState,
	target: { number },
	delta: number,
	period: number,
	damping: number
): number
	return springModule().step(state, target, delta, period, damping)
end

local function springAtRest(
	state: RuntimeTypes.SpringState,
	target: { number },
	reference: { number },
	tolerance: number
): boolean
	return springModule().atRest(state, target, reference, tolerance)
end

local function springCoefficients(period: number, damping: number): (number, number)
	return springModule().coefficients(period, damping)
end

local function createPool<T>(options: ResourceTypes.PoolOptions<T>): ResourceTypes.Pool<T>
	return poolModule()(options)
end

local function createKeyedCache<K, T>(options: ResourceTypes.KeyedCacheOptions<K, T>): ResourceTypes.KeyedCache<K, T>
	return keyedCacheModule()(options)
end

local function createSlot(explicit: OwnerModule.Owner?): ResourceTypes.Slot
	return slotModule()(explicit)
end

local function accumulator<T, E>(options: Types.AccumulatorOptions<T, E>): Types.ReadOnlyValue<T>
	return accumulatorModule()(options)
end

local function selector<K>(source: Types.ReadOnlyValue<K>): (K) -> Types.ReadOnlyValue<boolean>
	return selectorModule()(source)
end

local function boundary(
	builder: () -> HostProtocol.Node,
	fallback: (failure: unknown, retry: () -> ()) -> HostProtocol.Node
): Directive
	return boundaryModule()(builder, fallback)
end

local function createFocusScope<V, K>(options: FocusTypes.Options<V, K>): FocusTypes.FocusScope<K>
	return focusScopeModule()(options)
end

local function focusNeighbor(
	from: FocusTypes.FocusRect,
	candidates: { FocusTypes.FocusRect },
	direction: FocusTypes.Direction
): number?
	return focusNeighborModule()(from, candidates, direction)
end

local function presence<T>(
	condition: Types.Source<T>,
	builder: StructureTypes.PresenceBuilder,
	options: StructureTypes.PresenceOptions?
): Directive
	return presenceModule()(condition, builder, options)
end

local function show<T>(condition: Types.Source<T>, builder: Builder, fallback: Builder?): Directive
	return showModule()(condition, builder, fallback)
end

local function switch<K>(source: Types.Source<K>, branches: { [K]: Builder }, fallback: Builder?): Directive
	return switchModule()(source, branches, fallback)
end

local function keyed<V, K>(options: StructureTypes.KeyedOptions<V, K>): Directive
	return keyedModule()(options)
end

local function indexes<V>(source: Types.Source<{ V }>, render: StructureTypes.IndexedRender<V>): Directive
	return indexesModule()(source, render)
end

local function orderedCollection<V, K>(options: StructureTypes.OrderedCollectionOptions<V, K>): Directive
	return orderedCollectionModule()(options)
end

local function spatialCollection<V, K>(options: StructureTypes.SpatialCollectionOptions<V, K>): Directive
	return spatialCollectionModule()(options)
end

local function tileCollection<V>(options: StructureTypes.TileCollectionOptions<V>): Directive
	return tileCollectionModule()(options)
end

local function layerStack<V, K>(options: StructureTypes.LayerStackOptions<V, K>): Directive
	return layerStackModule()(options)
end

local function mountBudget<V, K>(options: StructureTypes.MountBudgetOptions<V, K>): Directive
	return mountBudgetModule()(options)
end

local function fragment(builder: NodesBuilder): Directive
	return fragmentModule()(builder)
end

local function portal(target: HostProtocol.Node, builder: NodesBuilder): Directive
	return portalModule()(target, builder)
end

local function inspectSnapshot(): Inspect.Report
	return reportModule().snapshot()
end

local function inspectOwner(subject: OwnerModule.Owner): Inspect.OwnerReport?
	return reportModule().owner(subject)
end

local function inspectOwned(subject: OwnerModule.Owner): nodes.OwnedCounts?
	return reportModule().owned(subject)
end

local function inspectNode(subject: HostProtocol.Node): Inspect.NodeReport
	return reportModule().node(subject)
end

local function inspectFormat(report: Inspect.Report): string
	return reportModule().format(report)
end

local function inspectData(report: Inspect.Report): Inspect.Data
	return reportModule().data(report)
end

local function formula<T>(body: Types.Body<T>, equals: Types.Equals<T>?): Types.Value<T>
	local value = formulaModule(body, equals)
	local owner = Active.current()
	if owner ~= nil then
		NodeCast.detachers[NodeCast.nodeOf(value)] = OwnerModule.own(owner, function()
			value:dispose()
		end)
	end
	return value
end

local function watch(body: (use: Types.Use) -> (), label: string?): Types.Dispose
	local owner = Active.current()
	if owner == nil then
		error(
			Diagnostics.format("owner/no-active-owner", "watch ran with no owner to hold it", {
				contract = "a watch lives exactly as long as the owner that created it",
				fix = "call it inside a component, or use OwnerModule.watch(owner, ...) with an explicit owner",
			}),
			0
		)
	end
	return OwnerModule.watch(owner, body, label)
end

local function cleanup(value: unknown): Types.Dispose
	local teardown: Types.Dispose
	if type(value) == "function" then
		teardown = value :: Types.Dispose
	elseif type(value) == "table" then
		local object = (value :: unknown) :: { destroy: unknown, dispose: unknown }
		if type(object.destroy) == "function" then
			teardown = function()
				(object.destroy :: (unknown) -> ())(object)
			end
		elseif type(object.dispose) == "function" then
			teardown = function()
				(object.dispose :: (unknown) -> ())(object)
			end
		else
			error(
				Diagnostics.format("owner/uncleanable", "cleanup was given a table it cannot tear down", {
					actual = "table with neither destroy nor dispose",
					expected = "a function, or a table with a destroy or dispose method",
				}),
				0
			)
		end
	else
		error(
			Diagnostics.format("owner/uncleanable", "cleanup was given something it cannot tear down", {
				actual = Diagnostics.describe(value),
				expected = "a function, or a table with a destroy or dispose method",
			}),
			0
		)
	end
	local holder = Active.current()
	if holder ~= nil and Inspect.isActive() then
		Inspect.cleanup(holder)
	end
	return Active.own(teardown, "cleanup")
end

local function sampleRead<T>(node: Types.ReadOnlyValue<T>): T
	if cellModule.isValue(node) then
		return node:peek()
	end
	return Graph.notANode("the reader Compose.sample passes to a body", node)
end

local function sample<T>(source: Types.Source<T>): T
	if cellModule.isValue(source) then
		return (source :: Types.ReadOnlyValue<T>):peek()
	end
	if type(source) ~= "function" then
		local actual = Diagnostics.describe(source)
		error(
			Diagnostics.format(
				"reactive/not-a-source",
				("Compose.sample was given a %s it cannot read"):format(actual),
				{
					actual = actual,
					expected = "a cell, a formula, or a function taking `use`",
					contract = "sample reads a source's current value once, without recording a dependency",
					fix = "pass the cell or formula itself, or a body that reads one",
				}
			),
			0
		)
	end
	local body = source
	return watchModule.sample(function(): T
		return body(sampleRead)
	end)
end

local withOwner = Active.withOwner

local function bindOwner<Args..., Rets...>(body: (Args...) -> Rets...): (Args...) -> Rets...
	if type(body) ~= "function" then
		error(
			Diagnostics.format("owner/bind-body-not-a-function", "bindOwner expects the function to bind", {
				actual = Diagnostics.describe(body),
				expected = "a function to run later under the owner active now",
				contract = "bindOwner exists to carry one callback back into its owner; there is nothing else to bind",
			}),
			0
		)
	end
	local owner = Active.current()
	if owner == nil then
		error(
			Diagnostics.format("owner/no-active-owner", "bindOwner has no owner to bind to", {
				contract = "a bound callback re-enters the owner that created it, so there has to be one to capture",
				fix = "call Compose.bindOwner inside the component or mount whose owner the callback belongs to",
			}),
			0
		)
	end
	return Active.bind(owner, body)
end

local function resetForTests()
	Active.resetForTests()
	Root.disposeAll()
	nodes.resetForTests()
	clock.reset()
	stats.reset()
end

local inspect = {
	start = Inspect.start,
	stop = Inspect.stop,
	active = Inspect.isActive,
	label = Inspect.label,
	snapshot = inspectSnapshot,
	owner = inspectOwner,
	owned = inspectOwned,
	node = inspectNode,
	format = inspectFormat,
	data = inspectData,
}

local profile = {
	start = function(now: () -> number, options: Types.ProfileOptions?)
		profileModule().start(now, options)
	end,
	stop = function(): Types.ProfileReport
		return profileModule().stop()
	end,
	label = function(node: unknown, name: string)
		profileModule().label(node, name)
	end,
	active = function(): boolean
		return profileModule().isActive()
	end,
	format = function(report: Types.ProfileReport, limit: number?): string
		return profileModule().format(report, limit)
	end,
	data = function(report: Types.ProfileReport): Types.ProfileData
		return profileModule().data(report)
	end,
}

return {
	cell = cellModule.cell,
	sharedCell = cellModule.cell,
	formula = formula,
	map = Props.map,
	accumulator = accumulator,
	selector = selector,
	watch = watch,
	sample = sample,
	isValue = cellModule.isValue,
	reactor = {
		create = reactorModule.create,
		batch = reactorModule.batch,
		settle = reactorModule.settle,
		pending = reactorModule.pending,
	},

	createOwner = OwnerModule.createOwner,
	owner = OwnerModule.api,
	withOwner = withOwner,
	bindOwner = bindOwner,
	withRootOwner = withRootOwner,
	createRootOwner = createRootOwner,
	currentOwner = Active.current,
	cleanup = cleanup,
	custodyOf = nodes.custodyOf,
	labelOf = nodes.labelOf,

	createRuntime = RuntimeModule.createRuntime,
	event = Keys.event,
	group = Keys.group,
	property = Keys.property,
	static = Keys.static,

	presence = presence,
	show = show,
	switch = switch,
	keyed = keyed,
	indexes = indexes,
	OrderedCollection = orderedCollection,
	SpatialCollection = spatialCollection,
	TileCollection = tileCollection,
	LayerStack = layerStack,
	MountBudget = mountBudget,
	fragment = fragment,
	portal = portal,

	createFocusScope = createFocusScope,
	focusNeighbor = focusNeighbor,
	createPool = createPool,
	createKeyedCache = createKeyedCache,
	createSlot = createSlot,
	geometry = Geometry,

	easing = AnimationEasing,
	registerCodec = AnimationCodec.register,
	registeredCodecs = AnimationCodec.registered,
	createSpringState = createSpringState,
	stepSpring = stepSpring,
	springAtRest = springAtRest,
	springCoefficients = springCoefficients,

	createSharedResource = AsyncShared,
	createContext = ContextModule,
	boundary = boundary,

	formatDiagnostic = Diagnostics.format,
	parseDiagnostic = Diagnostics.parse,
	setWorkCounters = stats.setEnabled,
	readWorkCounters = stats.read,
	resetWorkCounters = stats.reset,
	setYieldChecking = userSpace.setValidating,
	profile = profile,
	inspect = inspect,
	outstandingMounts = Root.size,

	__resetForTests = resetForTests,
}
