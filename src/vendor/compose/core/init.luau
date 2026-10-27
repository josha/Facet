--!strict

local AccumulatorModule = require "@self/accumulator"
local SelectorModule = require "@self/selector"
local Active = require "@self/ownership/active"
local AnimationCodec = require "@self/animation/codec"
local AnimationEasing = require "@self/animation/easing"
local AnimationSpring = require "@self/animation/spring"
local AsyncBoundary = require "@self/async/boundary"
local AsyncShared = require "@self/async/shared"
local ContextModule = require "@self/context"
local Diagnostics = require "@self/diagnostics"
local FocusScope = require "@self/focus-scope"
local Geometry = require "@self/geometry"
local FocusNeighbor = require "@self/focus-neighbor"
local Graph = require "@self/reactive/graph"
local NodeCast = require "@self/reactive/node"
local Inspect = require "@self/ownership/inspect"
local InspectReport = require "@self/ownership/report"
local HostProtocol = require "@self/host"
local KeyedCacheModule = require "@self/keyed-cache"
local Keys = require "@self/runtime/keys"
local Props = require "@self/runtime/props"
local OwnerModule = require "@self/ownership/owner"
local PoolModule = require "@self/pool"
local Root = require "@self/ownership/root"
local RootScopeModule = require "@self/ownership/root-scope"
local SlotModule = require "@self/slot"
local RuntimeModule = require "@self/runtime"
local StructureFragment = require "@self/structure/fragment"
local StructureIndexes = require "@self/structure/indexes"
local StructureKeyed = require "@self/structure/keyed"
local StructureLayerStack = require "@self/structure/layer-stack"
local StructureLayout = require "@self/collection/layout"
local StructurePortal = require "@self/structure/portal"
local StructurePresence = require "@self/structure/presence"
local StructureOrderedCollection = require "@self/structure/ordered-collection"
local StructureMountBudget = require "@self/structure/mount-budget"
local StructureShow = require "@self/structure/show"
local StructureSpatialCollection = require "@self/structure/spatial-collection"
local StructureTileCollection = require "@self/structure/tile-collection"
local StructureSwitch = require "@self/structure/switch"
local Types = require "@self/reactive/types"
local clock = require "@self/reactive/clock"
local cellModule = require "@self/reactive/cell"
local nodes = require "@self/ownership/nodes"
local profileModule = require "@self/reactive/profile"
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
export type AccumulatorOptions<T, E> = AccumulatorModule.Options<T, E>

export type Owner = OwnerModule.Owner
export type Context<T> = ContextModule.Context<T>
export type RootScope = RootScopeModule.RootScope
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
export type PresenceOptions = StructurePresence.Options
export type Exiting = StructurePresence.Exiting
export type MountPoint = RuntimeModule.MountPoint

export type FocusScope<K> = FocusScope.FocusScope<K>
export type FocusScopeOptions<V, K> = FocusScope.Options<V, K>
export type FocusDirection = FocusScope.Direction
export type FocusRect = FocusNeighbor.FocusRect

export type Pool<T> = PoolModule.Pool<T>
export type PoolLease<T> = PoolModule.Lease<T>
export type PoolOptions<T> = PoolModule.Options<T>

export type KeyedCache<K, T> = KeyedCacheModule.Cache<K, T>
export type KeyedCacheOptions<K, T> = KeyedCacheModule.Options<K, T>

export type Easing = AnimationEasing.Easing
export type Codec<T> = AnimationCodec.Codec<T>
export type SpringState = AnimationSpring.State
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
export type Slot = SlotModule.Slot

export type GeometrySize = Geometry.Size
export type GeometryInsets = Geometry.Insets
export type GeometryAnchor = Geometry.Anchor
export type GeometryFrame = Geometry.Frame
export type GeometryBounds = Geometry.Bounds
export type GeometryFitOptions = Geometry.FitOptions
export type GeometryClearOptions<R> = Geometry.ClearOptions<R>

export type SharedResourceFactory<T> = AsyncShared.Factory<T>
export type AcquireSharedResource<T> = AsyncShared.Acquire<T>

export type KeyedRender<V, K> = StructureKeyed.Render<V, K>
export type IndexedRender<V> = StructureIndexes.Render<V>

export type Placement = StructureLayout.Placement
export type OrderedCollectionMode = StructureOrderedCollection.Mode
export type OrderedCollectionDirection = StructureOrderedCollection.Direction
export type OrderedCollectionLayoutKind = StructureOrderedCollection.LayoutKind
export type OrderedCollectionAlign = StructureOrderedCollection.Align
export type OrderedCollectionLayout = StructureOrderedCollection.LayoutOptions
export type OrderedCollectionViewport = StructureOrderedCollection.Viewport
export type OrderedCollectionStatus = StructureOrderedCollection.Status
export type OrderedCollectionControls<K> = StructureOrderedCollection.Controls<K>
export type OrderedCollectionOptions<V, K> = StructureOrderedCollection.Options<V, K>
export type SpatialCollectionTier = StructureSpatialCollection.Tier
export type SpatialCollectionPoint = StructureSpatialCollection.Point
export type Representation = StructureSpatialCollection.Representation
export type SpatialCollectionBudget = StructureSpatialCollection.Budget
export type SpatialCollectionStatus = StructureSpatialCollection.Status
export type SpatialCollectionOptions<V, K> = StructureSpatialCollection.Options<V, K>
export type TileCollectionViewport = StructureTileCollection.Viewport
export type TileCollectionSize = StructureTileCollection.Size
export type TileCollectionPlacement = StructureTileCollection.Placement
export type TileCollectionOptions<V> = StructureTileCollection.Options<V>
export type LayerStackRetention = StructureLayerStack.Retention
export type LayerStackState = StructureLayerStack.State
export type LayerStackOptions<V, K> = StructureLayerStack.Options<V, K>
export type MountBudgetStatus = StructureMountBudget.Status
export type MountBudgetOptions<V, K> = StructureMountBudget.Options<V, K>

export type WorkCounters = stats.Counters
export type Diagnostic = Diagnostics.Parsed
export type ProfileOptions = profileModule.Options
export type ProfileReport = profileModule.Report
export type ProfileNode = profileModule.NodeRow
export type ProfileDrain = profileModule.DrainRow
export type ProfileData = profileModule.Data
export type InspectOptions = Inspect.Options
export type InspectReport = Inspect.Report
export type InspectOwner = Inspect.OwnerReport
export type InspectNode = Inspect.NodeReport
export type InspectOwnedCounts = InspectReport.OwnedCounts
export type InspectData = InspectReport.Data

local function formula<T>(body: Types.Body<T>, equals: Types.Equals<T>?): Types.Value<T>
	local value = formulaModule(body, equals)
	local owner = Active.current()
	if owner ~= nil then
		NodeCast.nodeOf(value).release = OwnerModule.own(owner, function()
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
	snapshot = InspectReport.snapshot,
	owner = InspectReport.owner,
	owned = InspectReport.owned,
	node = InspectReport.node,
	format = InspectReport.format,
	data = InspectReport.data,
}

local profile = {
	start = profileModule.start,
	stop = profileModule.stop,
	label = profileModule.label,
	active = profileModule.isActive,
	format = profileModule.format,
	data = profileModule.data,
}

return {
	cell = cellModule.cell,
	sharedCell = cellModule.cell,
	formula = formula,
	map = Props.map,
	accumulator = AccumulatorModule,
	selector = SelectorModule,
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
	withRootOwner = RootScopeModule.withRootOwner,
	createRootOwner = RootScopeModule.createRootOwner,
	currentOwner = Active.current,
	cleanup = cleanup,
	custodyOf = nodes.custodyOf,
	labelOf = nodes.labelOf,

	createRuntime = RuntimeModule.createRuntime,
	event = Keys.event,
	group = Keys.group,
	property = Keys.property,
	static = Keys.static,

	presence = StructurePresence,
	show = StructureShow,
	switch = StructureSwitch,
	keyed = StructureKeyed,
	indexes = StructureIndexes,
	OrderedCollection = StructureOrderedCollection,
	SpatialCollection = StructureSpatialCollection,
	TileCollection = StructureTileCollection,
	LayerStack = StructureLayerStack,
	MountBudget = StructureMountBudget,
	fragment = StructureFragment,
	portal = StructurePortal,

	createFocusScope = FocusScope,
	focusNeighbor = FocusNeighbor,
	createPool = PoolModule,
	createKeyedCache = KeyedCacheModule,
	createSlot = SlotModule,
	geometry = Geometry,

	easing = AnimationEasing,
	registerCodec = AnimationCodec.register,
	registeredCodecs = AnimationCodec.registered,
	createSpringState = AnimationSpring.createState,
	stepSpring = AnimationSpring.step,
	springAtRest = AnimationSpring.atRest,
	springCoefficients = AnimationSpring.coefficients,

	createSharedResource = AsyncShared,
	createContext = ContextModule,
	boundary = AsyncBoundary,

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
