--!strict

export type Dispose = () -> ()

export type Use = <T>(Readable<T>) -> T

export type Readable<T> = {
	peek: (self: Readable<T>) -> T,
}

export type Cell<T> = {
	peek: (self: Cell<T>) -> T,
	set: (self: Cell<T>, value: T) -> (),
	update: (self: Cell<T>, change: (previous: T) -> T) -> (),
}

export type Formula<T> = {
	dispose: (self: Formula<T>) -> (),
	peek: (self: Formula<T>) -> T,
}

export type Body<T> = (use: Use) -> T

export type Source<T> = Readable<T> | Body<T>

export type Equals<T> = (current: T, incoming: T) -> boolean

export type Initial<T> = (() -> T) | T

return {}
