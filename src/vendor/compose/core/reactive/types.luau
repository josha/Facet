--!strict
local Owners = require "../ownership/types"

export type Owner = Owners.Owner<Reactor>

export type Dispose = () -> ()

export type Cache<T> = { read cache: { read value: T }? }

export type ReadOnlyValue<T> = Cache<T> & {
	read cache: { read value: T }?,
	read peek: <S>(self: Cache<S>) -> S,
}

export type Value<T> = Cache<T> & {
	read cache: { read value: T }?,
	read peek: <S>(self: Cache<S>) -> S,
	read coalescing: number?,
	read set: (self: Value<T>, value: T) -> (),
	read update: (self: Value<T>, change: (previous: T) -> T) -> (),
	read dispose: (self: Value<T>) -> (),
}

export type Use = <T>(ReadOnlyValue<T>) -> T

export type Body<T> = (use: Use) -> T

export type Source<T> = ReadOnlyValue<T> | Body<T>

export type Input<T> = T | Source<T>

export type Equals<T> = (current: T, incoming: T) -> boolean

export type AccumulatorOptions<T, E> = {
	read from: ReadOnlyValue<E>,
	read reduce: (previous: T, event: E) -> T,
	read initial: T,
	read equals: Equals<T>?,
}

export type ProfileOptions = {
	read maxNodes: number?,
	read maxDrains: number?,
}

export type ProfileNodeRow = {
	id: number,
	kind: string,
	label: string?,
	writes: number,
	writesSuppressed: number,
	recomputations: number,
	recomputationsSuppressed: number,
	runs: number,
	schedules: number,
	schedulesCoalesced: number,
	hostWrites: number,
	peakFanOut: number,

	wakes: { [number]: number },
}

export type ProfileDrainRow = {
	runs: number,
	seconds: number,
	cause: string?,
}

export type ProfileReport = {
	active: boolean,
	seconds: number,
	nodes: { ProfileNodeRow },
	drains: { ProfileDrainRow },

	droppedRecords: number,
	totals: { [string]: number },
}

export type ProfileWakeData = {
	to: number,
	count: number,
}

export type ProfileNodeData = {
	id: number,
	kind: string,
	label: string?,
	name: string,
	writes: number,
	writesSuppressed: number,
	recomputations: number,
	recomputationsPublished: number,
	runs: number,
	schedules: number,
	schedulesCoalesced: number,
	hostWrites: number,
	peakFanOut: number,
	wakes: { ProfileWakeData },
}

export type ProfileDrainData = {
	runs: number,
	seconds: number,
	cause: string?,
}

export type ProfileData = {
	schemaVersion: number,
	active: boolean,
	seconds: number,
	droppedRecords: number,
	totals: { [string]: number },
	nodes: { ProfileNodeData },
	drains: { ProfileDrainData },
}

export type Reactor = {
	queue: { Node },
	count: number,
	cursor: number,
	batching: boolean,
	errors: { string }?,
	abandoned: boolean,
}

export type Node = NodeData<unknown> & { read peek: (<S>(Cache<S>) -> S)? }

export type NodeData<T> = {
	[number]: Node?,
	version: number?,
	value: unknown,
	cache: { read value: T }?,
	first: Node?,
	refresh: ((Node) -> ())?,
	body: Body<unknown>?,
	initial: (() -> unknown)?,
	equals: unknown,
	state: number?,
	reads: number?,
	run: ((Node) -> ())?,
	runIn: (({ consumer: Node?, order: number }, Node) -> ())?,
	effect: ((use: Use) -> ())?,
	listener: ((unknown, Node?) -> ())?,
	listenerGroup: boolean?,
	subject: {}?,
	transform: ((unknown) -> unknown)?,
	written: unknown,
	queued: boolean?,
	released: boolean?,
	retry: boolean?,
	reactor: Reactor?,
	coalescing: number?,
	coalesced: Node?,
	group: boolean?,
	source: Node?,
	fastKey: string?,
	fastNext: Node?,
	invalidate: ((Node) -> ())?,
	cutoff: ((Node) -> ())?,
	inherited: Owner?,
	child: Owner?,
	base: number?,
}

export type InspectOptions = {
	maxOwners: number?,
	maxNodes: number?,
}

export type InspectOwnerReport = {
	id: number,
	label: string?,
	holding: number,
	disposed: boolean,
	owned: number,
	adopted: number,
	borrowed: number,
	watches: number,
	cleanups: number,
	children: { InspectOwnerReport },
	totalHolding: number,
	totalOwned: number,
	totalAdopted: number,
	totalBorrowed: number,
	totalWatches: number,
	totalCleanups: number,
	descendants: number,
	unclassified: number,
}

export type InspectNodeReport = {
	custody: string,
	label: string?,
	ownerId: number?,
	ownerLabel: string?,
	because: string,
}

export type InspectReport = {
	active: boolean,
	mounts: { InspectOwnerReport },
	detached: { InspectOwnerReport },
	outstandingMounts: number,

	trackedNodes: number,
	pending: number,
	droppedOwners: number,
	droppedNodes: number,
}

export type InspectData = {
	schemaVersion: number,
	active: boolean,
	outstandingMounts: number,
	trackedNodes: number,
	pending: number,
	droppedOwners: number,
	droppedNodes: number,
	mounts: { InspectOwnerReport },
	detached: { InspectOwnerReport },
}

export type GeometrySize = { width: number, height: number }
export type GeometryInsets = { left: number?, top: number?, right: number?, bottom: number? }
export type GeometryAnchor = { x: number, y: number }
export type GeometryFrame = { left: number, top: number, right: number, bottom: number, width: number, height: number }
export type GeometryBounds = { left: number, top: number, right: number, bottom: number }
export type GeometryFitOptions = { min: GeometrySize?, max: GeometrySize?, anchor: GeometryAnchor? }
export type GeometryClearOptions<R> = { within: unknown?, reserved: { R }? }

return {}
