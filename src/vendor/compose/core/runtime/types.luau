--!strict

local Easing = require "../animation/easing"
local Types = require "../reactive/types"

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

export type Motion = {
	spring: <T>(source: Types.Body<T>, options: SpringOptions?) -> Types.ReadOnlyValue<T>,
	tween: <T>(source: Types.Body<T>, options: TweenOptions?) -> Types.ReadOnlyValue<T>,
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
