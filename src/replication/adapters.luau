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

local adapters = {}

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
				requestResnapshot(revision)
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

	-- full authoritative state at a revision (gap recovery and reconnect)
	function self.ingestResnapshot(newRevision: number, items: { [any]: any }): string
		if newRevision <= revision then
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
				"LuauUI mutation: send() while a request is pending (one in flight per Mutation; wait for confirm/reject)",
				0
			)
		end
		nextRequestId += 1
		activeRequestId = nextRequestId
		status:set("pending")
		if opts and opts.optimistic then
			opts.optimistic.apply(payload)
		end
		return { requestId = nextRequestId, payload = payload, expectedRevision = expectedRevision }
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

	function self.reset()
		if status:get() ~= "pending" then
			activeRequestId = nil
			status:set("idle")
		end
	end

	return self
end

return adapters
