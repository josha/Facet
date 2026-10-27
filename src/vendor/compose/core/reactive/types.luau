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
	release: (() -> ())?,
	set: ((Node, unknown) -> ())?,
	resume: ((Node, unknown) -> ())?,
	coalesced: Node?,
	group: boolean?,
	source: Node?,
	fastKey: string?,
	fastNext: Node?,
	invalidate: ((Node) -> ())?,
	inherited: unknown?,
	child: unknown?,
	base: number?,
}

return {}
