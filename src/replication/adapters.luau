--!strict
-- Client-side replicated-state adapters (design §4.2): ReplicatedSnapshot,
-- ReplicatedCollection, and Mutation over the core contract. Engine-free:
-- transport is game-owned; games feed ingest() from their replication layer.
-- Semantics enforced here (and by tests/replication.spec.luau):
--   * revisions are monotonically increasing; stale/duplicate ingests are
--     ignored and reported;
--   * a patch-stream gap requests a full resnapshot instead of applying;
--   * reconnect = resnapshot from any newer authoritative revision;
--   * mutations carry request IDs and expected revisions; status is
--     idle -> pending -> confirmed | rejected; optimistic presentation is
--     opt-in and reconciles on confirm / restores on reject;
--   * local pending state NEVER implies server success.

local contract = require("../core/contract")

local adapters = {}

-- The three factory return shapes, exported so a consumer can NAME what these
-- factories hand back (a typed helper, a stored field, a game-side wrapper).
-- Declared against the shipped truth, not an aspiration: `patch`/`data`/results
-- really are `any` today, and the published Readables really are core Signals.

export type Snapshot<T> = {
	binding: contract.Signal<T>,
	-- "applied" | "stale" | "duplicate"
	ingest: (newRevision: number, data: T) -> string,
	revision: () -> number,
}

export type Collection<K, V> = {
	binding: contract.Signal<{ [K]: V }>,
	-- "applied" | "stale" | "duplicate" | "gap"
	ingestPatch: (newRevision: number, patch: any) -> string,
	-- "applied" | "stale"
	ingestResnapshot: (newRevision: number, items: { [K]: V }) -> string,
	revision: () -> number,
}

-- what `send` hands back for the game transport to put on the wire
export type Envelope = {
	requestId: number,
	payload: any,
	expectedRevision: number?,
}

export type MutationOpts = {
	optimistic: {
		apply: (any) -> (),
		restore: () -> (),
	}?,
}

export type Mutation = {
	-- "idle" | "pending" | "confirmed" | "rejected"
	status: contract.Signal<string>,
	lastResult: contract.Signal<any>,
	send: (payload: any, expectedRevision: number?) -> Envelope,
	confirm: (requestId: number, result: any) -> (),
	reject: (requestId: number, reason: any) -> (),
	reset: () -> (),
}

-- ReplicatedSnapshot<T>: full-state semantic snapshots.
function adapters.snapshot(core: any, initialRevision: number, initialData: any)
	local revision = initialRevision
	local signal = core:signal(initialData)
	local self = {}
	self.binding = signal

	-- returns "applied" | "stale" | "duplicate"
	function self.ingest(newRevision: number, data: any): string
		if newRevision == revision then
			return "duplicate"
		end
		if newRevision < revision then
			return "stale"
		end
		revision = newRevision
		signal:set(data)
		return "applied"
	end

	function self.revision(): number
		return revision
	end

	return self
end

-- ReplicatedCollection<K, T>: keyed snapshots-or-patches with gap detection.
-- requestResnapshot(fromRevision) is the game replication hook; until the
-- resnapshot arrives, patches keep being refused so state never diverges.
function adapters.collection(
	core: any,
	initialRevision: number,
	initialItems: { [any]: any },
	requestResnapshot: (number) -> ()
)
	local revision = initialRevision
	local awaitingResnapshot = false
	local signal = core:signal(initialItems)
	local self = {}
	self.binding = signal

	-- patch = { set: {[k]: v}?, remove: {k}? } at exactly revision+1.
	-- returns "applied" | "stale" | "duplicate" | "gap"
	function self.ingestPatch(newRevision: number, patch: any): string
		if newRevision <= revision then
			return if newRevision == revision then "duplicate" else "stale"
		end
		if awaitingResnapshot or newRevision > revision + 1 then
			if not awaitingResnapshot then
				awaitingResnapshot = true
				-- QUARANTINED: the flag is latched BEFORE the hook so a
				-- successful request is asked exactly once — but a hook that
				-- THROWS never actually sent the request, and the latch would
				-- then guarantee it is never sent again (the collection dies on
				-- a transient remote error). Un-latch so the next patch retries.
				if not (pcall(requestResnapshot, revision)) then
					awaitingResnapshot = false
				end
			end
			return "gap"
		end
		local items = table.clone(signal:get())
		for k, v in (patch.set or {}) :: { [any]: any } do
			items[k] = v
		end
		for _, k in (patch.remove or {}) :: { any } do
			items[k] = nil
		end
		revision = newRevision
		signal:set(items)
		return "applied"
	end

	-- full authoritative state at a revision (gap recovery and reconnect).
	-- returns "applied" | "stale"
	--
	-- WHILE AWAITING, AN EQUAL REVISION IS A LEGAL RE-BASE. `requestResnapshot`
	-- is handed the CURRENT revision, so "nothing has changed since your gap" is
	-- answered at exactly that revision — the natural reply, and the one the
	-- guide promises re-bases cleanly. Refusing it as stale returned before the
	-- flag was cleared, and because a gap only asks `if not awaitingResnapshot`,
	-- no second request was ever made: the collection returned "gap" forever.
	-- Outside a gap the rule is unchanged (a resnapshot must be strictly newer).
	function self.ingestResnapshot(newRevision: number, items: { [any]: any }): string
		local acceptable = if awaitingResnapshot then newRevision >= revision else newRevision > revision
		if not acceptable then
			return "stale"
		end
		revision = newRevision
		awaitingResnapshot = false
		signal:set(table.clone(items))
		return "applied"
	end

	function self.revision(): number
		return revision
	end

	return self
end

-- Mutation<Request, Result>: typed client request with validated lifecycle.
-- opts.optimistic (optional): { apply: (Request) -> (), restore: () -> () }.
local nextRequestId = 0
function adapters.mutation(core: any, opts: { optimistic: { apply: (any) -> (), restore: () -> () }? }?)
	local status = core:signal("idle")
	local lastResult = core:signal(nil)
	local activeRequestId: number? = nil
	local self = {}
	self.status = status
	self.lastResult = lastResult

	-- returns the request envelope the game transport must send.
	-- expectedRevision rides the envelope for SERVER-side ordering validation
	-- (design §4.2); the client adapter does not interpret it.
	function self.send(payload: any, expectedRevision: number?)
		if status:get() == "pending" then
			error(
				"Facet mutation: send() while a request is pending (one in flight per Mutation; wait for confirm/reject)",
				0
			)
		end
		-- BOOKKEEPING FIRST, THEN THE USER CALLBACK. `apply` is the most
		-- consumer-authored code in this adapter; when it ran before the return
		-- and unquarantined, one bad line meant the caller never received the
		-- envelope — and confirm/reject/reset all match on the requestId only the
		-- envelope carries, so the mutation was permanently unrecoverable.
		nextRequestId += 1
		local envelope: Envelope = { requestId = nextRequestId, payload = payload, expectedRevision = expectedRevision }
		activeRequestId = envelope.requestId
		status:set("pending")
		if opts and opts.optimistic then
			-- QUARANTINED: a failed optimistic presentation degrades this send to
			-- an un-optimistic one (restore, also quarantined, puts the view back)
			-- and the request still goes out. The server verdict is unaffected.
			if not (pcall(opts.optimistic.apply, payload)) then
				pcall(opts.optimistic.restore)
			end
		end
		return envelope
	end

	-- idempotent: repeated confirmations/rejections of the same request are
	-- ignored, as are responses to superseded requests
	function self.confirm(requestId: number, result: any)
		if requestId ~= activeRequestId or status:get() ~= "pending" then
			return
		end
		core:transaction(function()
			if opts and opts.optimistic then
				-- reconcile: re-sync optimistic state from authoritative state
				-- AS OF NOW. If the confirm outruns its snapshot revision, this
				-- restores to stale truth — convergence then depends on the
				-- game reconciling again when the snapshot ingests (observe the
				-- snapshot binding and re-apply, as the gallery does). The
				-- adapter cannot reach arbitrary optimistic state on ingest;
				-- this wiring contract is tested in tests/replication.spec.luau
				-- (2026-07-19 phase-1 verifier finding F2).
				opts.optimistic.restore()
			end
			status:set("confirmed")
			lastResult:set(result)
		end)
	end

	function self.reject(requestId: number, reason: any)
		if requestId ~= activeRequestId or status:get() ~= "pending" then
			return
		end
		core:transaction(function()
			if opts and opts.optimistic then
				opts.optimistic.restore()
			end
			status:set("rejected")
			lastResult:set(reason)
		end)
	end

	-- RESET WORKS FROM ANY STATE, including the one a caller actually needs to
	-- escape: a request the server never answered. Guarding on `~= "pending"`
	-- made the obvious recovery verb a silent no-op exactly when recovery was
	-- the point. Abandoning a pending request rolls back its optimistic
	-- presentation (the request may still land server-side; local state must not
	-- keep claiming a success nobody confirmed), and clearing activeRequestId is
	-- what keeps a late confirm/reject for the abandoned id ignored.
	function self.reset()
		if status:get() == "pending" and opts and opts.optimistic then
			pcall(opts.optimistic.restore)
		end
		activeRequestId = nil
		status:set("idle")
	end

	return self
end

return adapters
