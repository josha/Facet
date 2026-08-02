--!strict
-- Replication-boundary spike tests (design §4.2, §17 Phase 0 exit gate):
-- stale/duplicate/gap/reject convergence, and TWO independent client
-- environments rendering the same semantic snapshot with independent
-- client-local presentation state.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local adapters = require("../src/replication/adapters")

describe("ReplicatedSnapshot", function()
	it("applies newer, ignores stale and duplicate revisions", function()
		local core = customFactory.new()
		local snap = adapters.snapshot(core, 1, { coins = 10 })
		expect(snap.ingest(3, { coins = 30 })).toBe("applied")
		expect(snap.ingest(2, { coins = 20 })).toBe("stale")
		expect(snap.ingest(3, { coins = 999 })).toBe("duplicate")
		expect(snap.binding:get().coins).toBe(30)
		expect(snap.revision()).toBe(3)
	end)
end)

describe("ReplicatedCollection", function()
	it("applies in-order patches, ignores stale/dup", function()
		local core = customFactory.new()
		local resnapshotRequests = {}
		local col = adapters.collection(core, 1, { a = 1 }, function(fromRev)
			table.insert(resnapshotRequests, fromRev)
		end)
		expect(col.ingestPatch(2, { set = { b = 2 } })).toBe("applied")
		expect(col.ingestPatch(2, { set = { b = 99 } })).toBe("duplicate")
		expect(col.ingestPatch(1, { set = { a = 99 } })).toBe("stale")
		expect(col.binding:get().a).toBe(1)
		expect(col.binding:get().b).toBe(2)
		expect(#resnapshotRequests).toBe(0)
	end)

	it("gap requests one resnapshot, refuses patches until it lands, then converges", function()
		local core = customFactory.new()
		local resnapshotRequests = {}
		local col = adapters.collection(core, 1, { a = 1 }, function(fromRev)
			table.insert(resnapshotRequests, fromRev)
		end)
		expect(col.ingestPatch(4, { set = { d = 4 } })).toBe("gap")
		expect(#resnapshotRequests).toBe(1)
		-- further patches (even in-order-looking ones) refused while awaiting
		expect(col.ingestPatch(2, { set = { b = 2 } })).toBe("gap")
		expect(#resnapshotRequests).toBe(1)
		expect(col.binding:get().d).toBe(nil)
		expect(col.ingestResnapshot(5, { a = 1, b = 2, c = 3, d = 4 })).toBe("applied")
		expect(col.binding:get().d).toBe(4)
		expect(col.revision()).toBe(5)
		-- stream resumes after the resnapshot revision
		expect(col.ingestPatch(6, { remove = { "a" } })).toBe("applied")
		expect(col.binding:get().a).toBe(nil)
	end)

	it("reconnect = resnapshot from any newer authoritative revision", function()
		local core = customFactory.new()
		local col = adapters.collection(core, 7, { x = 1 }, function() end)
		expect(col.ingestResnapshot(12, { y = 2 })).toBe("applied")
		expect(col.binding:get().x).toBe(nil)
		expect(col.binding:get().y).toBe(2)
	end)

	-- F-8. `requestResnapshot(fromRevision)` is handed the CURRENT revision, so
	-- "nothing has changed since your gap" answers at exactly that revision. The
	-- old guard refused it as "stale" and returned BEFORE clearing the flag, so
	-- the collection asked once, was answered correctly, and then refused every
	-- patch for the rest of the session with no way back.
	it("a resnapshot at the CURRENT revision re-bases while awaiting, instead of wedging", function()
		local core = customFactory.new()
		local asked = {}
		local col = adapters.collection(core, 4, { a = 1 }, function(fromRev)
			table.insert(asked, fromRev)
		end)
		expect(col.ingestPatch(9, { set = { z = 9 } })).toBe("gap")
		expect(asked[1]).toBe(4) -- the hook is handed the current revision
		-- the server answers at exactly that revision: nothing changed
		expect(col.ingestResnapshot(4, { a = 1, b = 2 })).toBe("applied")
		expect(col.revision()).toBe(4)
		expect(col.binding:get().b).toBe(2)
		-- and the stream resumes from there
		expect(col.ingestPatch(5, { set = { c = 3 } })).toBe("applied")
		expect(col.binding:get().c).toBe(3)
		expect(#asked).toBe(1)
	end)

	it("an equal-revision resnapshot is still stale when no gap is outstanding", function()
		local core = customFactory.new()
		local col = adapters.collection(core, 4, { a = 1 }, function() end)
		expect(col.ingestResnapshot(4, { b = 2 })).toBe("stale")
		expect(col.ingestResnapshot(3, { b = 2 })).toBe("stale")
		expect(col.binding:get().a).toBe(1)
		expect(col.binding:get().b).toBe(nil)
	end)

	-- F-10. The flag was latched BEFORE the unquarantined hook call, so a
	-- throwing transport turned a recoverable gap into a dead collection: the
	-- request was never made, and `if not awaitingResnapshot` meant it never
	-- would be.
	it("a throwing requestResnapshot does not latch the gap — the next patch asks again", function()
		local core = customFactory.new()
		local asked = 0
		local explode = true
		local col = adapters.collection(core, 1, { a = 1 }, function()
			asked += 1
			if explode then
				error("remote is down")
			end
		end)
		expect(col.ingestPatch(5, { set = { e = 5 } })).toBe("gap")
		expect(asked).toBe(1)
		explode = false
		-- the second patch RE-INVOKES the hook rather than sitting on a latched flag
		expect(col.ingestPatch(6, { set = { f = 6 } })).toBe("gap")
		expect(asked).toBe(2)
		expect(col.ingestResnapshot(6, { a = 1, e = 5, f = 6 })).toBe("applied")
		expect(col.ingestPatch(7, { set = { g = 7 } })).toBe("applied")
	end)
end)

describe("Mutation", function()
	it("optimistic apply reconciles on confirm via authoritative ingest", function()
		local core = customFactory.new()
		local snap = adapters.snapshot(core, 1, { music = false })
		local draft = core:signal(false)
		local mutation = adapters.mutation(core, {
			optimistic = {
				apply = function(payload)
					draft:set(payload.music)
				end,
				restore = function()
					draft:set(snap.binding:get().music)
				end,
			},
		})
		local envelope = mutation.send({ music = true }, snap.revision())
		expect(mutation.status:get()).toBe("pending")
		expect(draft:get()).toBe(true) -- optimistic
		-- pending never implies success: authoritative state still old
		expect(snap.binding:get().music).toBe(false)
		-- server validates, replicates, confirms
		snap.ingest(2, { music = true })
		mutation.confirm(envelope.requestId, "ok")
		expect(mutation.status:get()).toBe("confirmed")
		expect(snap.binding:get().music).toBe(true)
	end)

	it("rejection restores optimistic state; duplicate responses are idempotent", function()
		local core = customFactory.new()
		local snap = adapters.snapshot(core, 1, { music = false })
		local draft = core:signal(false)
		local mutation = adapters.mutation(core, {
			optimistic = {
				apply = function(payload)
					draft:set(payload.music)
				end,
				restore = function()
					draft:set(snap.binding:get().music)
				end,
			},
		})
		local envelope = mutation.send({ music = true }, snap.revision())
		expect(draft:get()).toBe(true)
		mutation.reject(envelope.requestId, "rate-limited")
		expect(mutation.status:get()).toBe("rejected")
		expect(draft:get()).toBe(false) -- restored
		mutation.reject(envelope.requestId, "again") -- idempotent
		mutation.confirm(envelope.requestId, "late-confirm") -- superseded: ignored
		expect(mutation.status:get()).toBe("rejected")
		-- no permanent pending/divergent state: reusable after reset
		mutation.reset()
		expect(mutation.status:get()).toBe("idle")
	end)

	it("confirm racing ahead of the snapshot cannot leave permanent divergence", function()
		local core = customFactory.new()
		local snap = adapters.snapshot(core, 1, { music = false })
		local draft = core:signal(false)
		local mutation = adapters.mutation(core, {
			optimistic = {
				apply = function(payload)
					draft:set(payload.music)
				end,
				restore = function()
					draft:set(snap.binding:get().music)
				end,
			},
		})
		local envelope = mutation.send({ music = true }, snap.revision())
		expect(draft:get()).toBe(true)
		-- confirm arrives BEFORE the authoritative snapshot: optimistic state
		-- re-syncs to current authoritative truth (old value) instead of
		-- diverging forever with status=confirmed
		mutation.confirm(envelope.requestId, "ok")
		expect(mutation.status:get()).toBe("confirmed")
		expect(draft:get()).toBe(false)
		-- the snapshot lands later; game reconciliation reapplies it
		snap.ingest(2, { music = true })
		draft:set(snap.binding:get().music)
		expect(draft:get()).toBe(true)
	end)

	it("send while pending is a structured error, not silent corruption", function()
		local core = customFactory.new()
		local mutation = adapters.mutation(core, nil)
		mutation.send({ v = 1 }, nil)
		local ok, err = pcall(function()
			mutation.send({ v = 2 }, nil)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "one in flight") ~= nil).toBe(true)
		expect(mutation.status:get()).toBe("pending")
	end)

	it("the envelope carries requestId and expectedRevision for server validation", function()
		local core = customFactory.new()
		local mutation = adapters.mutation(core, nil)
		local envelope = mutation.send({ v = 1 }, 7)
		expect(envelope.expectedRevision).toBe(7)
		expect(type(envelope.requestId)).toBe("number")
	end)

	-- F-9. `apply` is the most consumer-authored code in the adapter. It used to
	-- run AFTER the pending bookkeeping and BEFORE the return, unquarantined: one
	-- bad line and the caller never received the envelope, so it never learned
	-- the requestId that confirm/reject/reset all match on. The mutation was
	-- unrecoverable.
	it("a throwing optimistic apply still returns the envelope and leaves the mutation usable", function()
		local core = customFactory.new()
		local draft = core:signal("clean")
		local restores = 0
		local mutation = adapters.mutation(core, {
			optimistic = {
				apply = function()
					error("bad draft code")
				end,
				restore = function()
					restores += 1
					draft:set("clean")
				end,
			},
		})
		local envelope = mutation.send({ v = 1 }, 3)
		expect(type(envelope) == "table").toBe(true)
		expect(type(envelope.requestId)).toBe("number")
		expect(envelope.expectedRevision).toBe(3)
		expect(mutation.status:get()).toBe("pending")
		-- the failed apply already restored, un-optimistically, and the terminal
		-- verdict still lands on the id the caller now holds
		expect(restores).toBe(1)
		mutation.reject(envelope.requestId, "server said no")
		expect(mutation.status:get()).toBe("rejected")
		expect(restores).toBe(2)
		expect(draft:get()).toBe("clean")
		mutation.reset()
		expect(mutation.status:get()).toBe("idle")
		expect(type(mutation.send({ v = 2 }, nil).requestId)).toBe("number")
	end)

	-- F-11. `reset()` guarded on `status ~= "pending"`, so the one state a caller
	-- needs to escape was the one state it refused to touch.
	it("reset() escapes a stuck pending request, restores, and the stale id stays ignored", function()
		local core = customFactory.new()
		local draft = core:signal(false)
		local mutation = adapters.mutation(core, {
			optimistic = {
				apply = function(payload)
					draft:set(payload.on)
				end,
				restore = function()
					draft:set(false)
				end,
			},
		})
		local stuck = mutation.send({ on = true }, nil)
		expect(mutation.status:get()).toBe("pending")
		expect(draft:get()).toBe(true)
		-- the server never answers; the client escapes
		mutation.reset()
		expect(mutation.status:get()).toBe("idle")
		expect(draft:get()).toBe(false) -- optimistic presentation rolled back
		-- a late answer to the abandoned request is ignored in both directions
		mutation.confirm(stuck.requestId, "late ok")
		expect(mutation.status:get()).toBe("idle")
		mutation.reject(stuck.requestId, "late no")
		expect(mutation.status:get()).toBe("idle")
		-- and the mutation is reusable
		local fresh = mutation.send({ on = true }, nil)
		expect(fresh.requestId ~= stuck.requestId).toBe(true)
		expect(mutation.status:get()).toBe("pending")
		mutation.confirm(fresh.requestId, "ok")
		expect(mutation.status:get()).toBe("confirmed")
		-- reset from a terminal state keeps working exactly as it always did
		mutation.reset()
		expect(mutation.status:get()).toBe("idle")
	end)

	it("a throwing restore cannot unwind reset() either", function()
		local core = customFactory.new()
		local mutation = adapters.mutation(core, {
			optimistic = {
				apply = function() end,
				restore = function()
					error("bad restore")
				end,
			},
		})
		mutation.send({ v = 1 }, nil)
		mutation.reset()
		expect(mutation.status:get()).toBe("idle")
	end)
end)

describe("two clients, one semantic snapshot", function()
	it("independent environments and presentation state converge on the same semantics", function()
		-- the server-side event log (semantic state only — no layout, no
		-- device facts, design §4.1)
		local serverEvents = {
			{ rev = 2, data = { lap = 1, coins = 5 } },
			{ rev = 3, data = { lap = 2, coins = 8 } },
			{ rev = 4, data = { lap = 3, coins = 12 } },
		}

		local function makeClient(viewportWidth: number)
			local core = customFactory.new()
			local snap = adapters.snapshot(core, 1, { lap = 0, coins = 0 })
			-- client-local presentation state: never replicated
			local focusedControl = core:signal("none")
			-- device-appropriate derived view (per-client adaptation)
			local hudText = core:memo(function(use)
				local s = use(snap.binding)
				return if viewportWidth < 500 then `L{s.lap} C{s.coins}` else `Lap {s.lap} — Coins {s.coins}`
			end)
			return { core = core, snap = snap, focused = focusedControl, hudText = hudText }
		end

		local phone = makeClient(390)
		local desktop = makeClient(1920)

		-- phone receives the log in order; desktop sees duplicate + stale +
		-- out-of-order-with-recovery (snapshots: newer always applies)
		for _, e in serverEvents do
			phone.snap.ingest(e.rev, e.data)
		end
		desktop.snap.ingest(2, serverEvents[1].data)
		desktop.snap.ingest(2, serverEvents[1].data) -- duplicate
		desktop.snap.ingest(4, serverEvents[3].data) -- arrives early
		desktop.snap.ingest(3, serverEvents[2].data) -- stale: ignored

		-- independent presentation state
		phone.focused:set("SettingsButton")
		desktop.focused:set("none")

		-- semantic convergence
		expect(phone.snap.revision()).toBe(4)
		expect(desktop.snap.revision()).toBe(4)
		expect(phone.snap.binding:get().coins).toBe(12)
		expect(desktop.snap.binding:get().coins).toBe(12)
		-- device-appropriate, different renderings of the SAME state
		expect(phone.hudText:get()).toBe("L3 C12")
		expect(desktop.hudText:get()).toBe("Lap 3 — Coins 12")
		-- no presentation leakage between clients
		expect(phone.focused:get()).toBe("SettingsButton")
		expect(desktop.focused:get()).toBe("none")
	end)
end)
