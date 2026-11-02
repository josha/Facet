--!strict

local sharedModule: typeof(require "@self/async/shared")? = nil
local geometryModule: typeof(require "@self/geometry")? = nil
local rootScopeModule: typeof(require "@self/ownership/root-scope")? = nil
local springModule: typeof(require "@self/animation/spring")? = nil
local poolModule: typeof(require "@self/pool")? = nil
local keyedCacheModule: typeof(require "@self/keyed-cache")? = nil
local slotModule: typeof(require "@self/slot")? = nil
local accumulatorModule: typeof(require "@self/accumulator")? = nil
local selectorModule: typeof(require "@self/selector")? = nil
local boundaryModule: typeof(require "@self/async/boundary")? = nil
local focusScopeModule: typeof(require "@self/focus-scope")? = nil
local focusNeighborModule: typeof(require "@self/focus-neighbor")? = nil
local presenceModule: typeof(require "@self/structure/presence")? = nil
local showModule: typeof(require "@self/structure/show")? = nil
local switchModule: typeof(require "@self/structure/switch")? = nil
local keyedModule: typeof(require "@self/structure/keyed")? = nil
local indexesModule: typeof(require "@self/structure/indexes")? = nil
local orderedCollectionModule: typeof(require "@self/structure/ordered-collection")? = nil
local spatialCollectionModule: typeof(require "@self/structure/spatial-collection")? = nil
local tileCollectionModule: typeof(require "@self/structure/tile-collection")? = nil
local layerStackModule: typeof(require "@self/structure/layer-stack")? = nil
local mountBudgetModule: typeof(require "@self/structure/mount-budget")? = nil
local fragmentModule: typeof(require "@self/structure/fragment")? = nil
local portalModule: typeof(require "@self/structure/portal")? = nil
local reportModule: typeof(require "@self/ownership/report")? = nil
local inspectModule: typeof(require "@self/ownership/inspect")? = nil
local profileModule: typeof(require "@self/reactive/profile")? = nil

local Active = require "@self/ownership/active"
local AnimationCodec = require "@self/animation/codec"
local AnimationEasing = require "@self/animation/easing"
local ContextModule = require "@self/context"
local Diagnostics = require "@self/diagnostics"
local Dynamic = require "@self/dynamic"
local Graph = require "@self/reactive/graph"
local HostProtocol = require "@self/host"
local Props = require "@self/runtime/props"
local OwnerModule = require "@self/ownership/owner"
local CoreTypes = require "@self/types"
local RuntimeModule = require "@self/runtime"
local Types = require "@self/reactive/types"
local cellModule = require "@self/reactive/cell"
local nodes = require "@self/ownership/nodes"
local formulaModule = require "@self/reactive/formula"
local reactorModule = require "@self/reactive/reactor"
local watchModule = require "@self/reactive/watch"
local Evaluation = require "@self/reactive/evaluation"
local stats = Evaluation.stats

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
export type RootScope = CoreTypes.RootScope
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
export type PresenceOptions = CoreTypes.PresenceOptions
export type Exiting = CoreTypes.Exiting
export type MountPoint = RuntimeModule.MountPoint

export type FocusScope<K> = CoreTypes.FocusScope<K>
export type FocusScopeOptions<V, K> = CoreTypes.FocusScopeOptions<V, K>
export type FocusDirection = CoreTypes.FocusDirection
export type FocusRect = CoreTypes.FocusRect

export type Pool<T> = CoreTypes.Pool<T>
export type PoolLease<T> = CoreTypes.Lease<T>
export type PoolOptions<T> = CoreTypes.PoolOptions<T>

export type KeyedCache<K, T> = CoreTypes.KeyedCache<K, T>
export type KeyedCacheOptions<K, T> = CoreTypes.KeyedCacheOptions<K, T>

export type Easing = AnimationEasing.Easing
export type Codec<T> = AnimationCodec.Codec<T>
export type Motion<T> = CoreTypes.Motion<T>
export type SpringState = CoreTypes.SpringState
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
export type Slot = CoreTypes.Slot

export type GeometrySize = Types.GeometrySize
export type GeometryInsets = Types.GeometryInsets
export type GeometryAnchor = Types.GeometryAnchor
export type GeometryFrame = Types.GeometryFrame
export type GeometryBounds = Types.GeometryBounds
export type GeometryFitOptions = Types.GeometryFitOptions
export type GeometryClearOptions<R> = Types.GeometryClearOptions<R>

export type SharedResourceFactory<T> = () -> (T, (() -> ())?)

export type KeyedRender<V, K> = CoreTypes.KeyedRender<V, K>
export type IndexedRender<V> = CoreTypes.IndexedRender<V>

export type Placement = CoreTypes.Placement
export type OrderedCollectionMode = CoreTypes.OrderedCollectionMode
export type OrderedCollectionDirection = CoreTypes.OrderedCollectionDirection
export type OrderedCollectionLayoutKind = CoreTypes.OrderedCollectionLayoutKind
export type OrderedCollectionAlign = CoreTypes.OrderedCollectionAlign
export type OrderedCollectionLayout = CoreTypes.OrderedCollectionLayout
export type OrderedCollectionViewport = CoreTypes.OrderedCollectionViewport
export type OrderedCollectionStatus = CoreTypes.OrderedCollectionStatus
export type OrderedCollectionControls<K> = CoreTypes.OrderedCollectionControls<K>
export type OrderedCollectionOptions<V, K> = CoreTypes.OrderedCollectionOptions<V, K>
export type SpatialCollectionTier = CoreTypes.SpatialCollectionTier
export type SpatialCollectionPoint = CoreTypes.SpatialCollectionPoint
export type Representation = CoreTypes.Representation
export type SpatialCollectionBudget = CoreTypes.SpatialCollectionBudget
export type SpatialCollectionStatus = CoreTypes.SpatialCollectionStatus
export type SpatialCollectionOptions<V, K> = CoreTypes.SpatialCollectionOptions<V, K>
export type TileCollectionViewport = CoreTypes.TileCollectionViewport
export type TileCollectionSize = CoreTypes.TileCollectionSize
export type TileCollectionPlacement = CoreTypes.TileCollectionPlacement
export type TileCollectionOptions<V> = CoreTypes.TileCollectionOptions<V>
export type LayerStackRetention = CoreTypes.LayerStackRetention
export type LayerStackState = CoreTypes.LayerStackState
export type LayerStackOptions<V, K> = CoreTypes.LayerStackOptions<V, K>
export type MountBudgetStatus = CoreTypes.MountBudgetStatus
export type MountBudgetOptions<V, K> = CoreTypes.MountBudgetOptions<V, K>

export type WorkCounters = Evaluation.Counters
export type Diagnostic = Diagnostics.Parsed
export type ProfileOptions = Types.ProfileOptions
export type ProfileReport = Types.ProfileReport
export type ProfileNode = Types.ProfileNodeRow
export type ProfileDrain = Types.ProfileDrainRow
export type ProfileData = Types.ProfileData
export type InspectOptions = Types.InspectOptions
export type InspectReport = Types.InspectReport
export type InspectOwner = Types.InspectOwnerReport
export type InspectNode = Types.InspectNodeReport
export type InspectOwnedCounts = nodes.OwnedCounts
export type InspectData = Types.InspectData

type Builder = () -> HostProtocol.Node | Directive
type NodesBuilder = () -> { read [number]: HostProtocol.Node }

export type AcquireSharedResource<T> = CoreTypes.AcquireSharedResource<T>

local function createSharedResource<T>(factory: SharedResourceFactory<T>): AcquireSharedResource<T>
	local loaded = sharedModule or require "@self/async/shared"
	sharedModule = loaded
	return loaded(factory)
end

local geometry = table.freeze {
	safeArea = function(
		viewport: Types.GeometrySize,
		insets: Types.GeometryInsets?,
		margin: number?
	): Types.GeometryFrame
		local loaded = geometryModule or require "@self/geometry"
		geometryModule = loaded
		return loaded.safeArea(viewport, insets, margin)
	end,
	fit = function(
		available: Types.GeometryBounds,
		desired: Types.GeometrySize,
		options: Types.GeometryFitOptions?
	): Types.GeometryFrame
		local loaded = geometryModule or require "@self/geometry"
		geometryModule = loaded
		return loaded.fit(available, desired, options)
	end,
	overlaps = function(a: Types.GeometryBounds, b: Types.GeometryBounds): boolean
		local loaded = geometryModule or require "@self/geometry"
		geometryModule = loaded
		return loaded.overlaps(a, b)
	end,
	contains = function(outer: Types.GeometryBounds, inner: Types.GeometryBounds): boolean
		local loaded = geometryModule or require "@self/geometry"
		geometryModule = loaded
		return loaded.contains(outer, inner)
	end,
	firstClear = function<T, R>(candidates: { T }, options: Types.GeometryClearOptions<R>?): (T?, number?)
		local loaded = geometryModule or require "@self/geometry"
		geometryModule = loaded
		return loaded.firstClear(candidates, options)
	end,
}

local function withRootOwner<T...>(body: (owner: OwnerModule.Owner) -> T..., reactor: Types.Reactor?): T...
	local loaded = rootScopeModule or require "@self/ownership/root-scope"
	rootScopeModule = loaded
	return loaded.withRootOwner(body, reactor)
end

local function createRootOwner(body: (owner: OwnerModule.Owner) -> (), reactor: Types.Reactor?): CoreTypes.RootScope
	local loaded = rootScopeModule or require "@self/ownership/root-scope"
	rootScopeModule = loaded
	return loaded.createRootOwner(body, reactor)
end

local function createSpringState(position: { number }, arity: number): CoreTypes.SpringState
	local loaded = springModule or require "@self/animation/spring"
	springModule = loaded
	return loaded.createState(position, arity)
end

local function stepSpring(
	state: CoreTypes.SpringState,
	target: { number },
	delta: number,
	period: number,
	damping: number
): number
	local loaded = springModule or require "@self/animation/spring"
	springModule = loaded
	return loaded.step(state, target, delta, period, damping)
end

local function springAtRest(
	state: CoreTypes.SpringState,
	target: { number },
	reference: { number },
	tolerance: number
): boolean
	local loaded = springModule or require "@self/animation/spring"
	springModule = loaded
	return loaded.atRest(state, target, reference, tolerance)
end

local function springCoefficients(period: number, damping: number): (number, number)
	local loaded = springModule or require "@self/animation/spring"
	springModule = loaded
	return loaded.coefficients(period, damping)
end

local function createPool<T>(options: CoreTypes.PoolOptions<T>): CoreTypes.Pool<T>
	local loaded = poolModule or require "@self/pool"
	poolModule = loaded
	return loaded(options)
end

local function createKeyedCache<K, T>(options: CoreTypes.KeyedCacheOptions<K, T>): CoreTypes.KeyedCache<K, T>
	local loaded = keyedCacheModule or require "@self/keyed-cache"
	keyedCacheModule = loaded
	return loaded(options)
end

local function createSlot(explicit: OwnerModule.Owner?): CoreTypes.Slot
	local loaded = slotModule or require "@self/slot"
	slotModule = loaded
	return loaded(explicit)
end

local function accumulator<T, E>(options: Types.AccumulatorOptions<T, E>): Types.ReadOnlyValue<T>
	local loaded = accumulatorModule or require "@self/accumulator"
	accumulatorModule = loaded
	return loaded(options)
end

local function selector<K>(source: Types.ReadOnlyValue<K>): (K) -> Types.ReadOnlyValue<boolean>
	local loaded = selectorModule or require "@self/selector"
	selectorModule = loaded
	return loaded(source)
end

local function boundary(
	builder: Builder,
	fallback: (failure: unknown, retry: () -> ()) -> HostProtocol.Node | Directive
): Directive
	local loaded = boundaryModule or require "@self/async/boundary"
	boundaryModule = loaded
	return loaded(builder, fallback)
end

local function createFocusScope<V, K>(options: CoreTypes.FocusScopeOptions<V, K>): CoreTypes.FocusScope<K>
	local loaded = focusScopeModule or require "@self/focus-scope"
	focusScopeModule = loaded
	return loaded(options)
end

local function focusNeighbor(
	from: CoreTypes.FocusRect,
	candidates: { CoreTypes.FocusRect },
	direction: CoreTypes.FocusDirection
): number?
	local loaded = focusNeighborModule or require "@self/focus-neighbor"
	focusNeighborModule = loaded
	return loaded(from, candidates, direction)
end

local function presence<T>(
	condition: Types.Source<T>,
	builder: CoreTypes.PresenceBuilder,
	options: CoreTypes.PresenceOptions?
): Directive
	local loaded = presenceModule or require "@self/structure/presence"
	presenceModule = loaded
	return loaded(condition, builder, options)
end

local function show<T>(condition: Types.Source<T>, builder: Builder, fallback: Builder?): Directive
	local loaded = showModule or require "@self/structure/show"
	showModule = loaded
	return loaded(condition, builder, fallback)
end

local function switch<K>(source: Types.Source<K>, branches: { [K]: Builder }, fallback: Builder?): Directive
	local loaded = switchModule or require "@self/structure/switch"
	switchModule = loaded
	return loaded(source, branches, fallback)
end

local function keyed<V, K>(options: CoreTypes.KeyedOptions<V, K>): Directive
	local loaded = keyedModule or require "@self/structure/keyed"
	keyedModule = loaded
	return loaded(options)
end

local function indexes<V>(source: Types.Source<{ V }>, render: CoreTypes.IndexedRender<V>): Directive
	local loaded = indexesModule or require "@self/structure/indexes"
	indexesModule = loaded
	return loaded(source, render)
end

local function orderedCollection<V, K>(options: CoreTypes.OrderedCollectionOptions<V, K>): Directive
	local loaded = orderedCollectionModule or require "@self/structure/ordered-collection"
	orderedCollectionModule = loaded
	return loaded(options)
end

local function spatialCollection<V, K>(options: CoreTypes.SpatialCollectionOptions<V, K>): Directive
	local loaded = spatialCollectionModule or require "@self/structure/spatial-collection"
	spatialCollectionModule = loaded
	return loaded(options)
end

local function tileCollection<V>(options: CoreTypes.TileCollectionOptions<V>): Directive
	local loaded = tileCollectionModule or require "@self/structure/tile-collection"
	tileCollectionModule = loaded
	return loaded(options)
end

local function layerStack<V, K>(options: CoreTypes.LayerStackOptions<V, K>): Directive
	local loaded = layerStackModule or require "@self/structure/layer-stack"
	layerStackModule = loaded
	return loaded(options)
end

local function mountBudget<V, K>(options: CoreTypes.MountBudgetOptions<V, K>): Directive
	local loaded = mountBudgetModule or require "@self/structure/mount-budget"
	mountBudgetModule = loaded
	return loaded(options)
end

local function fragment(builder: NodesBuilder): Directive
	local loaded = fragmentModule or require "@self/structure/fragment"
	fragmentModule = loaded
	return loaded(builder)
end

local function portal(target: HostProtocol.Node, builder: NodesBuilder): Directive
	local loaded = portalModule or require "@self/structure/portal"
	portalModule = loaded
	return loaded(target, builder)
end

local function inspectSnapshot(): Types.InspectReport
	local loaded = reportModule or require "@self/ownership/report"
	reportModule = loaded
	return loaded.snapshot()
end

local function inspectOwner(subject: OwnerModule.Owner): Types.InspectOwnerReport?
	local loaded = reportModule or require "@self/ownership/report"
	reportModule = loaded
	return loaded.owner(subject)
end

local function inspectOwned(subject: OwnerModule.Owner): nodes.OwnedCounts?
	local loaded = reportModule or require "@self/ownership/report"
	reportModule = loaded
	return loaded.owned(subject)
end

local function inspectNode(subject: HostProtocol.Node): Types.InspectNodeReport
	local loaded = reportModule or require "@self/ownership/report"
	reportModule = loaded
	return loaded.node(subject)
end

local function inspectFormat(report: Types.InspectReport): string
	local loaded = reportModule or require "@self/ownership/report"
	reportModule = loaded
	return loaded.format(report)
end

local function inspectData(report: Types.InspectReport): Types.InspectData
	local loaded = reportModule or require "@self/ownership/report"
	reportModule = loaded
	return loaded.data(report)
end

local function formula<T>(body: Types.Body<T>, equals: Types.Equals<T>?): Types.Value<T>
	local value = formulaModule(body, equals)
	local owner = Active.current()
	if owner ~= nil then
		Graph.detachers[Graph.nodeOf(value)] = OwnerModule.own(owner, function()
			value:dispose()
		end)
	end
	return value
end

local function watch(body: (use: Types.Use) -> (), label: string?): Types.Dispose
	local owner = Active.current()
	if owner == nil then
		return Diagnostics.raise("owner/no-active-owner", "watch ran with no owner to hold it", {
			contract = "a watch lives exactly as long as the owner that created it",
			fix = "call it inside a component, or use OwnerModule.watch(owner, ...) with an explicit owner",
		})
	end
	return OwnerModule.watch(owner, body, label)
end

local function cleanup(value: unknown): Types.Dispose
	local teardown: Types.Dispose
	if type(value) == "function" then
		teardown = function()
			Dynamic.invoke(value)
		end
	elseif type(value) == "table" then
		local object = value
		if type(Dynamic.read(object, "destroy")) == "function" then
			teardown = function()
				Dynamic.invoke(Dynamic.read(object, "destroy"), object)
			end
		elseif type(Dynamic.read(object, "dispose")) == "function" then
			teardown = function()
				Dynamic.invoke(Dynamic.read(object, "dispose"), object)
			end
		else
			return Diagnostics.raise("owner/uncleanable", "cleanup was given a table it cannot tear down", {
				actual = "table with neither destroy nor dispose",
				expected = "a function, or a table with a destroy or dispose method",
			})
		end
	else
		return Diagnostics.raise("owner/uncleanable", "cleanup was given something it cannot tear down", {
			actual = Diagnostics.describe(value),
			expected = "a function, or a table with a destroy or dispose method",
		})
	end
	local holder = Active.current()
	if holder ~= nil and nodes.inspecting.active then
		local loaded = inspectModule or require "@self/ownership/inspect"
		inspectModule = loaded
		loaded.cleanup(holder)
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
	if type(source) ~= "function" then
		if cellModule.isValue(source) then
			return source:peek()
		end
		local actual = Diagnostics.describe(source)
		return Diagnostics.raise(
			"reactive/not-a-source",
			("Compose.sample was given a %s it cannot read"):format(actual),
			{
				actual = actual,
				expected = "a cell, a formula, or a function taking `use`",
				contract = "sample reads a source's current value once, without recording a dependency",
				fix = "pass the cell or formula itself, or a body that reads one",
			}
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
		return Diagnostics.raise("owner/bind-body-not-a-function", "bindOwner expects the function to bind", {
			actual = Diagnostics.describe(body),
			expected = "a function to run later under the owner active now",
			contract = "bindOwner exists to carry one callback back into its owner; there is nothing else to bind",
		})
	end
	local owner = Active.current()
	if owner == nil then
		return Diagnostics.raise("owner/no-active-owner", "bindOwner has no owner to bind to", {
			contract = "a bound callback re-enters the owner that created it, so there has to be one to capture",
			fix = "call Compose.bindOwner inside the component or mount whose owner the callback belongs to",
		})
	end
	return Active.bind(owner, body)
end

local function resetForTests()
	Active.resetForTests()
	OwnerModule.disposeRoots()
	nodes.resetForTests()
	Graph.clock.now = 0
	stats.reset()
end

local inspect = {
	start = function(options: Types.InspectOptions?)
		local loaded = inspectModule or require "@self/ownership/inspect"
		inspectModule = loaded
		loaded.start(options)
	end,
	stop = function()
		local loaded = inspectModule or require "@self/ownership/inspect"
		inspectModule = loaded
		loaded.stop()
	end,
	active = function(): boolean
		return nodes.inspecting.active
	end,
	label = function(owner: Owner, name: string)
		local loaded = inspectModule or require "@self/ownership/inspect"
		inspectModule = loaded
		loaded.label(owner, name)
	end,
	snapshot = inspectSnapshot,
	owner = inspectOwner,
	owned = inspectOwned,
	node = inspectNode,
	format = inspectFormat,
	data = inspectData,
}

local profile = {
	start = function(now: () -> number, options: Types.ProfileOptions?)
		local loaded = profileModule or require "@self/reactive/profile"
		profileModule = loaded
		loaded.start(now, options)
	end,
	stop = function(): Types.ProfileReport
		local loaded = profileModule or require "@self/reactive/profile"
		profileModule = loaded
		return loaded.stop()
	end,
	label = function(node: unknown, name: string)
		local loaded = profileModule or require "@self/reactive/profile"
		profileModule = loaded
		loaded.label(node, name)
	end,
	active = function(): boolean
		local loaded = profileModule or require "@self/reactive/profile"
		profileModule = loaded
		return loaded.isActive()
	end,
	format = function(report: Types.ProfileReport, limit: number?): string
		local loaded = profileModule or require "@self/reactive/profile"
		profileModule = loaded
		return loaded.format(report, limit)
	end,
	data = function(report: Types.ProfileReport): Types.ProfileData
		local loaded = profileModule or require "@self/reactive/profile"
		profileModule = loaded
		return loaded.data(report)
	end,
}

return {
	cell = cellModule.cell,
	lazyCell = cellModule.lazyCell,
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
	event = Props.event,
	group = Props.group,
	property = Props.property,
	static = Props.static,

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
	geometry = geometry,

	easing = AnimationEasing,
	numberCodec = AnimationCodec.number,
	createSpringState = createSpringState,
	stepSpring = stepSpring,
	springAtRest = springAtRest,
	springCoefficients = springCoefficients,

	createSharedResource = createSharedResource,
	createContext = ContextModule,
	boundary = boundary,

	formatDiagnostic = Diagnostics.format,
	parseDiagnostic = Diagnostics.parse,
	setWorkCounters = stats.setEnabled,
	readWorkCounters = stats.read,
	resetWorkCounters = stats.reset,
	setYieldChecking = Evaluation.setValidating,
	profile = profile,
	inspect = inspect,
	outstandingMounts = OwnerModule.rootSize,

	__resetForTests = resetForTests,
}
