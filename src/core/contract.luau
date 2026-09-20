--!strict
-- Facet's reactive types, which are Compose's. State is a cell, derivation is a
-- formula, a tracked read goes through `use`, and a lifetime is a Compose
-- owner. Facet defines no reactive type of its own.
--
-- Semantics, as the pinned runtime provides them:
--   * a write outside a batch settles synchronously; inside one, at its close;
--   * a watch sees only post-drain (glitch-free) values;
--   * a formula body receives `use`; its dependency set re-tracks each run;
--   * delivery follows Compose's dependency-registration FIFO. A drain is
--     limited to 1,000,000 watch runs; an abandoned watch needs disposal and
--     re-registration to resume;
--   * a batch is a GROUPING, not a rollback — a body that throws leaves the
--     writes made before the throw published, and the error is re-raised after
--     the drain. A batch body MUST NOT YIELD: the batch stays open across the
--     yield and every watch in the session waits with it. Neither is enforced;
--   * a drain SETTLES before it ends. `core.settlePass` registers terminal work
--     — the expensive, externally visible half of a change, which in Facet is a
--     surface's layout solve and the geometry it feeds back to its consumer.
--     Settle callbacks run after propagation quiesces, in REGISTRATION order; a
--     callback that writes ends the pass, propagation drains, and the pass
--     RESTARTS from the first callback, so every callback observes every other
--     one's publication. Passes repeat until one writes nothing, under a
--     100-pass cap — a measure -> publish cycle that will not converge is a loud
--     error, never a hang and never a silent frame. Two obligations follow: a
--     callback MUST be cheap and idempotent when it has nothing to do, and it
--     must not assume it is the only writer. Settle is NOT a watch: it receives
--     no value and it runs inside the drain, so a top-level write still returns
--     with all of its consequences applied (optimization-log L-31, 2026-08-14);
--   * every resource is owned by an owner or disposed explicitly; disposal is
--     reverse-order and idempotent.

local Compose = require("../vendor/compose/core")
local settle_pass = require("../render/settle_pass")

export type Unsubscribe = () -> ()

export type Cell<T> = Compose.Cell<T>
export type Formula<T> = Compose.Formula<T>
-- STRUCTURAL ON PURPOSE. Compose types each method's `self` as its own table, so
-- a `Compose.Cell<T>` does not convert to a `Compose.Readable<T>` and a spec
-- field typed `Readable<T>` would refuse the cell every author passes it. What a
-- control needs from a readable is `peek`, and that is all this asks for. Cell
-- and Formula are NAMED as well: an overloaded constructor checks its argument
-- without an expected type, and there only an exact union member matches.
export type Readable<T> = { peek: (self: any) -> T } | Compose.Cell<T> | Compose.Formula<T>
export type Owner = Compose.Owner

-- `use` pulls a dependency's current value and registers the dependency for
-- the evaluation in progress.
export type Use = Compose.Use

--[[ The per-application service bag (`core/services.luau`). It carries NO
	reactive API: every verb below is Compose's, reached through `reactor` and
	`owner`. What Facet adds is the error boundary and the layout settle pass. ]]
export type Core = {
	name: string,
	-- the Compose runtime a surface's nodes are mounted into
	scene: any,
	reactor: Compose.Reactor,
	-- the application's root owner, already guarded by the boundary below
	owner: Compose.Owner,
	boundary: { report: (unknown) -> () },
	-- apply this application's boundary to an owner Facet did not create as a
	-- child of `owner` (a mount root, a control's detached owner)
	guard: (Compose.Owner) -> Compose.Owner,
	report: (unknown) -> (),
	--[[ diagnostics: the last contained failure. STICKY — nil until the first
		one, and never cleared, so it reports "something was contained at some
		point in this core's life", not "this core is unhealthy right now". There
		is no take/clear verb, so a health assertion built on it must be scoped to
		a freshly built core (the library's own tests are). ]]
	lastError: () -> string?,
	settlePass: settle_pass.Pass,
}

return nil
