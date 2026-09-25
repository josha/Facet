--!strict

local AccumulatorModule = require "@self/accumulator"
local Active = require "@self/ownership/active"
local AnimationCodec = require "@self/animation/codec"
local AnimationEasing = require "@self/animation/easing"
local AnimationSpring = require "@self/animation/spring"
local AsyncBoundary = require "@self/async/boundary"
local AsyncShared = require "@self/async/shared"
local Diagnostics = require "@self/diagnostics"
local FocusScope = require "@self/focus-scope"
local Graph = require "@self/reactive/graph"
local Inspect = require "@self/ownership/inspect"
local InspectReport = require "@self/ownership/report"
local HostProtocol = require "@self/host"
local KeyedCacheModule = require "@self/keyed-cache"
local Keys = require "@self/runtime/keys"
local OwnerModule = require "@self/ownership/owner"
local PoolModule = require "@self/pool"
local Root = require "@self/ownership/root"
local RootScopeModule = require "@self/ownership/root-scope"
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
export type Readable<T> = Types.Readable<T>
export type Cell<T> = Types.Cell<T>
export type Formula<T> = Types.Formula<T>
export type Body<T> = Types.Body<T>
export type Source<T> = Types.Source<T>
export type Value<T> = Types.Value<T>
export type Equals<T> = Types.Equals<T>
export type Reactor = reactorModule.Reactor
export type AccumulatorOptions<T, E> = AccumulatorModule.Options<T, E>

export type Owner = OwnerModule.Owner
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

local function formula<T>(body: Types.Body<T>, equals: Types.Equals<T>?): Types.Formula<T>
	local value = formulaModule(body, equals)
	local owner = Active.current()
	if owner ~= nil then
		local dispose = value.dispose
		local release = owner.own(function()
			dispose(value)
		end)
		value.dispose = function(_self: Types.Formula<T>)
			release()
		end
	end
	return value
end

local function watch(body: (use: Types.Use) -> (), label: string?): Types.Dispose
	local owner = Active.current()
	if owner == nil then
		Diagnostics.raise("owner/no-active-owner", "watch ran with no owner to hold it", {
			contract = "a watch lives exactly as long as the owner that created it",
			fix = "call it inside a component, or use owner.watch(...) with an explicit owner",
		})
	end
	return (owner :: OwnerModule.Owner).watch(body, label)
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
			Diagnostics.raise("owner/uncleanable", "cleanup was given a table it cannot tear down", {
				actual = "table with neither destroy nor dispose",
				expected = "a function, or a table with a destroy or dispose method",
			})
		end
	else
		Diagnostics.raise("owner/uncleanable", "cleanup was given something it cannot tear down", {
			actual = Diagnostics.describe(value),
			expected = "a function, or a table with a destroy or dispose method",
		})
	end
	local holder = Active.current()
	if holder ~= nil and Inspect.isActive() then
		Inspect.cleanup(holder)
	end
	return Active.own(teardown, "cleanup")
end

local function sampleRead<T>(node: Types.Readable<T>): T
	if cellModule.isReadable(node) then
		return node:peek()
	end
	return Graph.notANode("the reader Compose.sample passes to a body", node)
end

local function sample<T>(source: Types.Source<T>): T
	if cellModule.isReadable(source) then
		return (source :: Types.Readable<T>):peek()
	end
	if type(source) ~= "function" then
		local actual = Diagnostics.describe(source)
		Diagnostics.raise("reactive/not-a-source", ("Compose.sample was given a %s it cannot read"):format(actual), {
			actual = actual,
			expected = "a cell, a formula, or a function taking `use`",
			contract = "sample reads a source's current value once, without recording a dependency",
			fix = "pass the cell or formula itself, or a body that reads one",
		})
	end
	local body = source :: Types.Body<T>
	return watchModule.sample(function(): T
		return body(sampleRead)
	end)
end

local withOwner = Active.withOwner

local function bindOwner<Args..., Rets...>(body: (Args...) -> Rets...): (Args...) -> Rets...
	if type(body) ~= "function" then
		Diagnostics.raise("owner/bind-body-not-a-function", "bindOwner expects the function to bind", {
			actual = Diagnostics.describe(body),
			expected = "a function to run later under the owner active now",
			contract = "bindOwner exists to carry one callback back into its owner; there is nothing else to bind",
		})
	end
	local owner = Active.current()
	if owner == nil then
		Diagnostics.raise("owner/no-active-owner", "bindOwner has no owner to bind to", {
			contract = "a bound callback re-enters the owner that created it, so there has to be one to capture",
			fix = "call Compose.bindOwner inside the component or mount whose owner the callback belongs to",
		})
	end
	return Active.bind(owner :: OwnerModule.Owner, body)
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
	sharedCell = cellModule.sharedCell,
	formula = formula,
	accumulator = AccumulatorModule,
	watch = watch,
	sample = sample,
	isReadable = cellModule.isReadable,
	reactor = reactorModule.create,

	createOwner = OwnerModule.createOwner,
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
	LayerStack = StructureLayerStack,
	MountBudget = StructureMountBudget,
	fragment = StructureFragment,
	portal = StructurePortal,

	createFocusScope = FocusScope,
	createPool = PoolModule,
	createKeyedCache = KeyedCacheModule,

	easing = AnimationEasing,
	registerCodec = AnimationCodec.register,
	registeredCodecs = AnimationCodec.registered,
	createSpringState = AnimationSpring.createState,
	stepSpring = AnimationSpring.step,
	springAtRest = AnimationSpring.atRest,
	springCoefficients = AnimationSpring.coefficients,

	createSharedResource = AsyncShared,
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
