--!strict

export type Dispose = () -> ()

export type ReadOnlyValue<T> = {
	peek: (self: ReadOnlyValue<T>) -> T,
}

export type Value<T> = ReadOnlyValue<T> & {
	set: (self: Value<T>, value: T) -> (),
	update: (self: Value<T>, change: (previous: T) -> T) -> (),
	dispose: (self: Value<T>) -> (),
}

export type Use = <T>(ReadOnlyValue<T>) -> T

export type Body<T> = (use: Use) -> T

export type Source<T> = ReadOnlyValue<T> | Body<T>

export type Input<T> = T | Source<T>

export type Equals<T> = (current: T, incoming: T) -> boolean

export type AccumulatorOptions<T, E> = {
	from: ReadOnlyValue<E>,
	reduce: (previous: T, event: E) -> T,
	initial: T,
	equals: Equals<T>?,
}

export type ProfileOptions = {
	maxNodes: number?,
	maxDrains: number?,
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

export type Node = {
	[number]: Node?,
	version: number?,
	value: unknown,
	first: Node?,
	refresh: ((Node) -> ())?,
	body: ((use: Use) -> unknown)?,
	equals: ((current: unknown, incoming: unknown) -> boolean)?,
	state: number?,
	reads: number?,
	run: ((Node) -> ())?,
	runIn: (({ consumer: Node?, order: number }, Node) -> ())?,
	effect: ((use: Use) -> ())?,
	listener: ((value: unknown) -> ())?,
	queued: boolean?,
	released: boolean?,
	retry: boolean?,
	reactor: Reactor?,
	set: ((Node, unknown) -> ())?,
	resume: ((Node, unknown) -> ())?,
	coalesced: Node?,
	group: boolean?,
	source: Node?,
	fastKey: string?,
	fastNext: Node?,
	invalidate: ((Node) -> ())?,
	cutoff: ((Node) -> ())?,
	inherited: unknown?,
	child: unknown?,
	base: number?,
}

return {}
