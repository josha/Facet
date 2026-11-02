--!strict

local Easing = require "./animation/easing"
local Host = require "./host"
local Owner = require "./ownership/owner"
local Types = require "./reactive/types"

export type AcquireSharedResource<T> = setmetatable<{
	read detached: () -> (T, () -> ()),
}, {
	read __call: (unknown) -> T,
}>

export type FocusDirection = "left" | "right" | "up" | "down"

export type FocusScopeOptions<V, K> = {
	from: Types.ReadOnlyValue<{ V }> | Types.Body<{ V }>,
	key: ((value: V, index: number) -> K)?,
	disabled: ((value: V, index: number) -> boolean)?,
	position: ((value: V, index: number) -> (number, number))?,
	wrap: boolean?,
	initial: K?,
	autoFocus: boolean?,
}

export type FocusScope<K> = {
	current: Types.ReadOnlyValue<K?>,
	focus: (key: K) -> boolean,
	clear: () -> (),
	next: () -> K?,
	previous: () -> K?,
	move: (direction: FocusDirection) -> K?,
	first: () -> K?,
	last: () -> K?,
	isFocused: (key: K) -> Types.ReadOnlyValue<boolean>,
}

export type FocusRect = { x: number, y: number, width: number, height: number }

export type Lease<T> = {
	value: T,
	release: () -> (),
}

export type Pool<T> = {
	acquire: () -> Lease<T>,
	idle: () -> number,
	active: () -> number,
}

export type PoolOptions<T> = {
	create: () -> T,
	destroy: (value: T) -> (),
	reset: ((value: T) -> ())?,
	maxRetained: number,
}

export type KeyedCache<K, T> = {
	get: (key: K) -> T,
	peek: (key: K) -> T?,
	evict: (key: K) -> (),
	size: () -> number,

	keys: () -> { K },
}

export type KeyedCacheOptions<K, T> = {
	build: (key: K) -> T,
	destroy: (value: T) -> (),
	maxRetained: number,

	touch: ((key: K, value: T) -> ())?,
}

export type Slot = {
	bind: (key: unknown, attach: (owner: Owner.Owner, release: () -> ()) -> ()) -> boolean,
	release: (key: unknown) -> boolean,
	current: () -> unknown,
	dispose: () -> (),
}

export type RootScope = {
	owner: Owner.Owner,

	dispose: Types.Dispose,
}

export type KeyedRender<V, K> = (value: Types.ReadOnlyValue<V>, index: Types.ReadOnlyValue<number>, key: K) -> Host.Node

export type KeyedSource<V> = Types.ReadOnlyValue<{ V }> | Types.Body<{ V }>

export type KeyedOptions<V, K = V> =
	{
		read from: KeyedSource<V>,
		read key: (value: V, index: number) -> K,
		read render: KeyedRender<V, K>,
	}
	| {
		read from: KeyedSource<V>,
		read key: nil?,
		read render: KeyedRender<V, V>,
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
	read exit: (nodes: { Host.Node }) -> Exiting,
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
	read offset: number,
	read size: number,
	read offsetRevision: number?,
}

export type OrderedCollectionMode = "all" | "windowed"

export type OrderedCollectionDirection = "vertical" | "horizontal"

export type OrderedCollectionLayoutKind = "list" | "grid"

export type OrderedCollectionAlign = "start" | "center" | "end"

export type OrderedCollectionLayout = {
	read kind: OrderedCollectionLayoutKind?,
	read columns: number?,
	read itemSize: number?,
	read gap: number?,
	read crossSize: number?,
	read crossGap: number?,
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
	read from: KeyedSource<V>,
	read key: ((value: V, index: number) -> K)?,
	read render: ((value: Types.ReadOnlyValue<V>, placement: Types.ReadOnlyValue<Placement>, key: K) -> Host.Node)?,
	read recycle: ((
		value: Types.ReadOnlyValue<V>,
		placement: Types.ReadOnlyValue<Placement>,
		key: Types.ReadOnlyValue<K>
	) -> Host.Node)?,
	read mode: OrderedCollectionMode?,
	read viewport: (Types.ReadOnlyValue<OrderedCollectionViewport> | Types.Body<OrderedCollectionViewport>)?,
	read direction: OrderedCollectionDirection?,
	read layout: (
		OrderedCollectionLayout | Types.ReadOnlyValue<OrderedCollectionLayout> | Types.Body<OrderedCollectionLayout>
	)?,
	read overscan: number?,
	read measured: (Types.ReadOnlyValue<{ [K]: number }> | Types.Body<{ [K]: number }>)?,
	read follow: ("end" | "none")?,
	read followThreshold: number?,
	read status: Types.Value<OrderedCollectionStatus>?,
	read controls: OrderedCollectionControls<K>?,
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
	read from: KeyedSource<V>,
	read key: ((value: V, index: number) -> K)?,
	read position: (value: V) -> (number, number, number?),
	read origin: Types.ReadOnlyValue<SpatialCollectionPoint> | Types.Body<SpatialCollectionPoint>,
	read tiers: { SpatialCollectionTier },
	read render: (
		value: Types.ReadOnlyValue<V>,
		representation: Types.ReadOnlyValue<Representation>,
		key: K
	) -> Host.Node,
	read cellSize: number?,
	read hysteresis: number?,
	read importance: ((value: V) -> number)?,
	read pinned: (Types.ReadOnlyValue<{ [K]: boolean }> | Types.Body<{ [K]: boolean }>)?,
	read budget: SpatialCollectionBudget?,
	read status: Types.Value<SpatialCollectionStatus>?,
}

export type TileCollectionViewport = { x: number, y: number, width: number, height: number }

export type TileCollectionSize = { width: number, height: number }

export type TileCollectionPlacement =
	{ column: number, row: number, x: number, y: number, width: number, height: number }

export type TileCollectionOptions<V> = {
	read viewport: Types.Source<TileCollectionViewport>,
	read tileSize: TileCollectionSize,
	read overscan: number?,
	read read: (use: Types.Use, column: number, row: number) -> V?,
	read render: (value: Types.ReadOnlyValue<V>, placement: TileCollectionPlacement) -> Host.Node,
}

export type LayerStackRetention = "all" | "top"

export type LayerStackState = {
	index: number,
	depthFromTop: number,
	top: boolean,
	covered: boolean,
}

export type LayerStackOptions<V, K> = {
	read from: KeyedSource<V>,
	read key: ((value: V, index: number) -> K)?,
	read render: (value: Types.ReadOnlyValue<V>, state: Types.ReadOnlyValue<LayerStackState>, key: K) -> Host.Node,
	read retention: LayerStackRetention?,
}

export type MountBudgetStatus = {
	total: number,
	mounted: number,
	pending: number,
}

export type MountBudgetOptions<V, K> = {
	read from: KeyedSource<V>,
	read key: ((value: V, index: number) -> K)?,
	read render: (value: Types.ReadOnlyValue<V>, index: Types.ReadOnlyValue<number>, key: K) -> Host.Node,
	read mountsPerFrame: number,
	read priority: ((value: V, index: number) -> number)?,
	read status: Types.Value<MountBudgetStatus>?,
}

export type SpringState = {
	position: { number },
	velocity: { number },
	arity: number,
}

export type ReducedMotion = Types.Value<boolean> | Types.Value<boolean> | Types.Source<boolean>

export type SpringOptions = {
	period: number?,
	damping: number?,
	tolerance: number?,
	reducedMotion: ReducedMotion?,
}

export type Duration = Types.Input<number>

export type TweenOptions = {
	seconds: Duration?,
	ease: Easing.Easing?,
	reducedMotion: ReducedMotion?,
}

export type Motion<T> = {
	spring: (source: Types.Body<T>, options: SpringOptions?) -> Types.ReadOnlyValue<T>,
	tween: (source: Types.Body<T>, options: TweenOptions?) -> Types.ReadOnlyValue<T>,
	ramp: (initial: T, options: RampOptions?) -> Ramp<T>,
}

export type TimelineDirection = "normal" | "alternate"

export type TimelineOptions = {
	duration: number?,
	delay: number?,
	repeats: number?,
	direction: TimelineDirection?,
	scale: number?,
	autoplay: boolean?,
}

export type Timeline = {
	progress: Types.ReadOnlyValue<number>,
	elapsed: Types.ReadOnlyValue<number>,
	moving: Types.ReadOnlyValue<boolean>,
	completed: Types.ReadOnlyValue<boolean>,
	play: (self: Timeline) -> (),
	pause: (self: Timeline) -> (),
	seek: (self: Timeline, seconds: number) -> (),
	restart: (self: Timeline) -> (),
	setScale: (self: Timeline, scale: number) -> (),
}

export type RampOptions = {
	ease: Easing.Easing?,
}

export type Ramp<T> = {
	value: Types.ReadOnlyValue<T>,
	retarget: (target: T, seconds: number) -> (),
}

export type Cancel = () -> boolean

export type Scheduler = {
	after: (seconds: number, body: () -> ()) -> Cancel,
	replace: (key: unknown, seconds: number, body: () -> ()) -> Cancel,
	cancel: (key: unknown) -> boolean,
	clear: () -> (),
	pending: () -> number,
	dispose: () -> (),
}

export type ObserveOptions = { frame: boolean?, poll: boolean?, styled: boolean? }

export type ClockOptions = { duration: number?, deadline: number?, start: number?, interval: number?, step: number? }

export type SettledOptions<T, R = unknown> = {
	sample: () -> T,
	frames: number?,
	equals: Types.Equals<T>?,
	restart: Types.Source<R>?,
	ready: (() -> boolean)?,
	timeout: number?,
}

export type SequenceStep = {
	wait: number?,
	run: (() -> ())?,
	onComplete: (() -> ())?,
	tween: { seconds: number, ease: Easing.Easing? }?,
	timeline: TimelineOptions?,
	sample: ((number) -> ())?,
	parallel: { SequenceStep }?,
	steps: { SequenceStep }?,
}

export type SequenceOptions = { steps: { SequenceStep }, reducedMotion: ReducedMotion?, autoplay: boolean? }

export type Sequence = {
	completed: Types.ReadOnlyValue<boolean>,
	running: Types.ReadOnlyValue<boolean>,
	play: () -> (),
	cancel: () -> (),
	finish: () -> (),
}

return {}
