--!strict
-- LuauUI core contract (design §6, §17 Phase 0): the reactive-foundation
-- interface every candidate core (custom / fusion-adapter / imperative
-- baseline) implements identically. The public LuauUI API depends only on this
-- contract, so the Phase 0 rubric can swap implementations without API change.
-- Pure types; no code. Semantics the conformance suite enforces:
--   * writes outside a transaction flush synchronously; inside, at close;
--   * observers/effects see only post-flush (glitch-free) values, once per
--     flush in which their source changed;
--   * memo compute receives `use` for dependency access; dependency sets
--     replace atomically after successful evaluation;
--   * writing state during memo evaluation is an error;
--   * effect writes schedule a later flush round; a bounded iteration cap
--     turns feedback loops into errors;
--   * cycles are reported with their path; failed memos are quarantined;
--   * every resource is owned by a scope or disposed explicitly; disposal is
--     reverse-order and idempotent; counters return to baseline.

export type Unsubscribe = () -> ()

export type Signal<T> = {
	kind: "signal",
	get: (self: Signal<T>) -> T,
	set: (self: Signal<T>, value: T) -> (),
	dispose: (self: Signal<T>) -> (),
}

export type Memo<T> = {
	kind: "memo",
	get: (self: Memo<T>) -> T,
	dispose: (self: Memo<T>) -> (),
}

export type Readable<T> = Signal<T> | Memo<T>

-- `use` pulls a dependency's current value and registers the dependency for
-- the evaluation in progress.
export type Use = <T>(source: Readable<T>) -> T

export type Scope = {
	own: (self: Scope, resource: any) -> any,
	use: (self: Scope, resource: any) -> any,
	child: (self: Scope, label: string?) -> Scope,
	dispose: (self: Scope) -> (),
	isDisposed: (self: Scope) -> boolean,
}

export type Counters = {
	signals: number,
	memos: number,
	observers: number,
	effects: number,
	scopes: number,
}

export type Core = {
	name: string,
	signal: <T>(self: Core, initial: T, eq: ((T, T) -> boolean)?) -> Signal<T>,
	memo: <T>(self: Core, compute: (use: Use) -> T, eq: ((T, T) -> boolean)?) -> Memo<T>,
	-- observer: fires post-flush with the new value when source changed
	observe: <T>(self: Core, source: Readable<T>, onChange: (T) -> ()) -> Unsubscribe,
	-- effect: tracked run(use) immediately, re-runs post-commit on dep change
	effect: (self: Core, run: (use: Use) -> ()) -> Unsubscribe,
	transaction: (self: Core, body: () -> ()) -> (),
	flush: (self: Core) -> (),
	scope: (self: Core, label: string?) -> Scope,
	counters: (self: Core) -> Counters,
	-- diagnostics: last quarantined error string (cycle path, write-in-memo,
	-- compute error, feedback-loop cap), nil when healthy
	lastError: (self: Core) -> string?,
}

export type CoreFactory = {
	name: string,
	new: () -> Core,
	-- true when the implementation genuinely supports the semantic (rubric
	-- honesty: the suite still RUNS every check; this only annotates results)
	claims: {
		dynamicDependencies: boolean,
		cycleDetection: boolean,
		writeDuringMemoError: boolean,
	},
}

return nil
