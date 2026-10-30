--!strict

local Host = require "../host"
local Types = require "../reactive/types"

export type KeyedRender<V, K> = (value: Types.ReadOnlyValue<V>, index: Types.ReadOnlyValue<number>, key: K) -> Host.Node

export type KeyedSource<V> = Types.ReadOnlyValue<{ V }> | Types.Body<{ V }>

export type KeyedOptions<V, K> = {
	from: KeyedSource<V>,
	key: ((value: V, index: number) -> K)?,
	render: KeyedRender<V, K>,
}

export type IndexedRender<V> = (value: Types.ReadOnlyValue<V>, index: number) -> Host.Node

export type PresencePhase = {
	exiting: Types.ReadOnlyValue<boolean>,
}

export type PresenceBuilder = (phase: PresencePhase) -> Host.Node | { Host.Node }

export type Exiting = {
	completed: Types.ReadOnlyValue<boolean>,
}

export type PresenceOptions = {
	exit: (nodes: { Host.Node }) -> Exiting,
}

export type Placement = {
	index: number,
	row: number,
	column: number,
	offset: number,
	size: number,
	crossOffset: number,
	crossSize: number,
}

export type OrderedCollectionViewport = {
	offset: number,
	size: number,
	offsetRevision: number?,
}

export type OrderedCollectionMode = "all" | "windowed"

export type OrderedCollectionDirection = "vertical" | "horizontal"

export type OrderedCollectionLayoutKind = "list" | "grid"

export type OrderedCollectionAlign = "start" | "center" | "end"

export type OrderedCollectionLayout = {
	kind: OrderedCollectionLayoutKind?,
	columns: number?,
	itemSize: number?,
	gap: number?,
	crossSize: number?,
	crossGap: number?,
}

export type OrderedCollectionStatus = {
	mode: OrderedCollectionMode,
	direction: OrderedCollectionDirection,
	total: number,
	retained: number,
	first: number,
	last: number,
	firstRow: number,
	lastRow: number,
	rowCount: number,
	extent: number,
	following: boolean,
	desiredOffset: number?,
	measured: number,
}

export type OrderedCollectionControls<K> = {
	offsetOf: ((index: number, align: OrderedCollectionAlign?, size: number?) -> number)?,
	indexOfKey: ((key: K) -> number?)?,
	placementOf: ((index: number) -> Placement)?,
}

export type OrderedCollectionOptions<V, K> = {
	from: KeyedSource<V>,
	key: ((value: V, index: number) -> K)?,
	render: ((value: Types.ReadOnlyValue<V>, placement: Types.ReadOnlyValue<Placement>, key: K) -> Host.Node)?,
	recycle: ((
		value: Types.ReadOnlyValue<V>,
		placement: Types.ReadOnlyValue<Placement>,
		key: Types.ReadOnlyValue<K>
	) -> Host.Node)?,
	mode: OrderedCollectionMode?,
	viewport: (Types.ReadOnlyValue<OrderedCollectionViewport> | Types.Body<OrderedCollectionViewport>)?,
	direction: OrderedCollectionDirection?,
	layout: (
		OrderedCollectionLayout | Types.ReadOnlyValue<OrderedCollectionLayout> | Types.Body<OrderedCollectionLayout>
	)?,
	overscan: number?,
	measured: (Types.ReadOnlyValue<{ [K]: number }> | Types.Body<{ [K]: number }>)?,
	follow: ("end" | "none")?,
	followThreshold: number?,
	status: Types.Value<OrderedCollectionStatus>?,
	controls: OrderedCollectionControls<K>?,
}

export type SpatialCollectionTier = {
	name: string,
	radius: number,
}

export type SpatialCollectionPoint = {
	x: number,
	y: number,
	z: number?,
}

export type Representation = {
	tier: number,
	name: string,
	distance: number,
	pinned: boolean,
}

export type SpatialCollectionBudget = {
	mountsPerFrame: number?,
}

export type SpatialCollectionStatus = {
	total: number,
	retained: number,
	queried: number,
	pending: number,
	perTier: { number },
	cells: number,
}

export type SpatialCollectionOptions<V, K> = {
	from: KeyedSource<V>,
	key: ((value: V, index: number) -> K)?,
	position: (value: V) -> (number, number, number?),
	origin: Types.ReadOnlyValue<SpatialCollectionPoint> | Types.Body<SpatialCollectionPoint>,
	tiers: { SpatialCollectionTier },
	render: (value: Types.ReadOnlyValue<V>, representation: Types.ReadOnlyValue<Representation>, key: K) -> Host.Node,
	cellSize: number?,
	hysteresis: number?,
	importance: ((value: V) -> number)?,
	pinned: (Types.ReadOnlyValue<{ [K]: boolean }> | Types.Body<{ [K]: boolean }>)?,
	budget: SpatialCollectionBudget?,
	status: Types.Value<SpatialCollectionStatus>?,
}

export type TileCollectionViewport = { x: number, y: number, width: number, height: number }

export type TileCollectionSize = { width: number, height: number }

export type TileCollectionPlacement =
	{ column: number, row: number, x: number, y: number, width: number, height: number }

export type TileCollectionOptions<V> = {
	viewport: Types.Source<TileCollectionViewport>,
	tileSize: TileCollectionSize,
	overscan: number?,
	read: (use: Types.Use, column: number, row: number) -> V?,
	render: (value: Types.ReadOnlyValue<V>, placement: TileCollectionPlacement) -> Host.Node,
}

export type LayerStackRetention = "all" | "top"

export type LayerStackState = {
	index: number,
	depthFromTop: number,
	top: boolean,
	covered: boolean,
}

export type LayerStackOptions<V, K> = {
	from: KeyedSource<V>,
	key: ((value: V, index: number) -> K)?,
	render: (value: Types.ReadOnlyValue<V>, state: Types.ReadOnlyValue<LayerStackState>, key: K) -> Host.Node,
	retention: LayerStackRetention?,
}

export type MountBudgetStatus = {
	total: number,
	mounted: number,
	pending: number,
}

export type MountBudgetOptions<V, K> = {
	from: KeyedSource<V>,
	key: ((value: V, index: number) -> K)?,
	render: (value: Types.ReadOnlyValue<V>, index: Types.ReadOnlyValue<number>, key: K) -> Host.Node,
	mountsPerFrame: number,
	priority: ((value: V, index: number) -> number)?,
	status: Types.Value<MountBudgetStatus>?,
}

return {}
