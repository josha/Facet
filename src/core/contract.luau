--!strict
-- Facet core contract (design §6, §17 Phase 0): the reactive-foundation
-- interface every candidate core implements identically — the shipped custom
-- core (`src/core/custom.luau`, the one the bake-off selected) and the retained
-- imperative baseline kept as a development fixture at
-- `bench/cores/imperative.luau`. The public Facet API depends only on this
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
--   * within one flush, OBSERVERS are notified in node CREATION order — a total
--     order across nodes, not merely within one node. Consumers that each watch
--     their OWN memo (the renderer's per-surface geometry memo is the shipped
--     case) would otherwise be notified in table-hash order, which varies run to
--     run; a surface's re-solve order is part of what makes a frame
--     reproducible. NOTE this is stated for observers only: effect ordering is
--     NOT yet promised (architecture gate F2, 2026-08-14);
--   * a transaction is a GROUPING, not a rollback — a body that throws leaves
--     writes made before the throw published, and the error is re-raised after
--     the flush. And a transaction body MUST NOT YIELD: the transaction stays
--     open across the yield, so every observer in the session waits and any
--     unrelated write made meanwhile is held with it. Neither is enforced;
--   * a flush SETTLES before it ends. `settle` registers terminal work — the
--     expensive, externally-visible half of a change (the shipped case is a
--     surface's layout solve and the geometry it feeds back to its consumer).
--     Settle callbacks run after propagation quiesces, in REGISTRATION order;
--     a callback that writes ends the pass, propagation drains, and the pass
--     RESTARTS from the first callback, so every settle callback observes every
--     other one's publication. Passes repeat until one writes nothing, and a
--     settle pass counts against the same bounded iteration cap — a
--     measure→publish cycle that will not converge is the same loud error an
--     effect feedback loop is, never a hang and never a silent frame. Two
--     obligations follow: a callback MUST be cheap and idempotent when it has
--     nothing to do (it runs once per pass), and it must not assume it is the
--     only writer. Settle is NOT an observer: it receives no value, it is not
--     part of glitch-freedom, and it runs inside the flush — so a top-level
--     write still returns with all of its consequences applied
--     (optimization-log L-31, 2026-08-14);
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
	-- live `settle` registrations. Counted for the same reason every other
	-- registry is: an un-disposed settle callback is a live reference held by
	-- the core after its owner is gone, and the neutrality suites are the
	-- tripwire that catches it.
	settles: number,
}

export type Core = {
	name: string,
	signal: <T>(self: Core, initial: T, eq: ((T, T) -> boolean)?) -> Signal<T>,
	memo: <T>(self: Core, compute: (use: Use) -> T, eq: ((T, T) -> boolean)?) -> Memo<T>,
	-- observer: fires post-flush with the new value when source changed
	observe: <T>(self: Core, source: Readable<T>, onChange: (T) -> ()) -> Unsubscribe,
	-- effect: tracked run(use) immediately, re-runs post-commit on dep change
	effect: (self: Core, run: (use: Use) -> ()) -> Unsubscribe,
	-- settle: untracked terminal work, run after propagation quiesces and
	-- re-run until the flush stops moving (see the semantics list above)
	settle: (self: Core, run: () -> ()) -> Unsubscribe,
	transaction: (self: Core, body: () -> ()) -> (),
	flush: (self: Core) -> (),
	scope: (self: Core, label: string?) -> Scope,
	counters: (self: Core) -> Counters,
	-- diagnostics: last quarantined error string (cycle path, write-in-memo,
	-- compute error, feedback-loop cap). STICKY: nil until the first quarantined
	-- error, and never cleared afterwards — it reports "something was contained
	-- at some point in this core's life", not "this core is unhealthy right now".
	-- There is no take/clear verb, so a health assertion built on it must be
	-- scoped to a freshly-built core (the library's own tests are).
	lastError: (self: Core) -> string?,
}

export type CoreFactory = {
	name: string,
	-- `opts.warn` (director ruling 2026-08-23, task-fix2 item 6): every
	-- quarantined write now calls it — real `warn()` by default, injectable so
	-- a spec asserting a quarantine fired need not print past the suite's own
	-- PASS/FAIL lines. Optional and additive: a factory that ignores it is
	-- still a valid `CoreFactory` (Luau's structural typing lets a `() -> Core`
	-- satisfy this).
	new: (opts: { warn: ((string) -> ())? }?) -> Core,
	-- true when the implementation genuinely supports the semantic (rubric
	-- honesty: the suite still RUNS every check; this only annotates results)
	claims: {
		dynamicDependencies: boolean,
		cycleDetection: boolean,
		writeDuringMemoError: boolean,
	},
}

return nil
