--!strict

local Types = require "./reactive/types"

export type Direction = "left" | "right" | "up" | "down"

export type Options<V, K> = {
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
	move: (direction: Direction) -> K?,
	first: () -> K?,
	last: () -> K?,
	isFocused: (key: K) -> Types.ReadOnlyValue<boolean>,
}

export type FocusRect = { x: number, y: number, width: number, height: number }

return {}
