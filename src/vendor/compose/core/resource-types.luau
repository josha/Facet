--!strict

local Owner = require "./ownership/owner"
local Types = require "./reactive/types"

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

return {}
