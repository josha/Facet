--!strict
-- Replication fuzz case (design §15.2; UI-REPL-001/002): a model server owns
-- a keyed collection and advances its revision; a hostile network delays,
-- duplicates, reorders, and permanently drops patch messages before the
-- client adapter ingests them. Gap recovery goes through the adapter's
-- requestResnapshot hook, serviced by the model server with its CURRENT
-- state (like a real transport). The case ends with a reconnect-style full
-- resnapshot, after which the client MUST equal the authoritative state.
-- Also drives Mutation lifecycles: out-of-order/duplicate/wrong-id
-- confirmations are ignored, status transitions stay legal, optimistic
-- presentation restores on resolution, and send-while-pending is refused.

local customCore = require("../../../src/core/custom")
local adapters = require("../../../src/replication/adapters")
local prng = require("../prng")

type Prng = prng.Prng

local replication_fuzzer = {}

local KEYS = { "a", "b", "c", "d" }

local function serialize(items: { [string]: any }): string
	local keys = {}
	for k in items do
		table.insert(keys, k)
	end
	table.sort(keys)
	local parts = {}
	for _, k in keys do
		table.insert(parts, `{k}={tostring(items[k])}`)
	end
	return table.concat(parts, ",")
end

type Message = { kind: string, rev: number, patch: any?, items: { [string]: any }? }

function replication_fuzzer.case(rng: Prng)
	local core = (customCore :: any).new()

	-- model server
	local serverRev = rng:range(1, 5)
	local serverItems: { [string]: number } = {}
	for _, k in KEYS do
		if rng:bool(0.7) then
			serverItems[k] = rng:range(0, 99)
		end
	end

	-- hostile network: pending messages, random delivery order
	local network: { Message } = {}
	local resnapshotRequests = 0

	local collection = adapters.collection(core, serverRev, table.clone(serverItems), function(_fromRev: number)
		resnapshotRequests += 1
		-- server services the request with its CURRENT authoritative state
		table.insert(network, { kind = "resnap", rev = serverRev, items = table.clone(serverItems) })
	end)

	local lastClientRev = collection.revision()

	local function deliver(message: Message)
		local before = collection.revision()
		local result: string
		if message.kind == "patch" then
			result = collection.ingestPatch(message.rev, message.patch)
			if message.rev <= before then
				assert(
					result == (if message.rev == before then "duplicate" else "stale"),
					`patch rev {message.rev} at client rev {before} returned {result}`
				)
			else
				assert(result == "applied" or result == "gap", `patch rev {message.rev} returned {result}`)
			end
		else
			result = collection.ingestResnapshot(message.rev, message.items :: { [string]: any })
			assert(
				result == (if message.rev <= before then "stale" else "applied"),
				`resnapshot rev {message.rev} at client rev {before} returned {result}`
			)
		end
		local after = collection.revision()
		assert(after >= before, `client revision went backwards: {before} -> {after}`)
		lastClientRev = after
	end

	local function deliverSome()
		local budget = rng:range(0, math.min(3, #network))
		for _ = 1, budget do
			if #network == 0 then
				break
			end
			local index = rng:range(1, #network)
			local message = network[index]
			if rng:bool(0.15) and message.kind == "patch" then
				-- permanent drop: later patches will read as a gap
				table.remove(network, index)
			else
				if rng:bool(0.2) then
					-- duplicate: deliver now AND leave a copy queued
					deliver(message)
				else
					table.remove(network, index)
					deliver(message)
				end
			end
		end
	end

	-- mutation under test: optimistic presentation over a client signal
	local base = rng:range(0, 9)
	local presentation = core:signal(base)
	local mutation = adapters.mutation(core, {
		optimistic = {
			apply = function(payload: any)
				presentation:set(payload)
			end,
			restore = function()
				presentation:set(base)
			end,
		},
	})
	local activeEnvelope: any = nil
	local resolvedStatuses: { string } = {}

	local function legalStatus(s: string): boolean
		return s == "idle" or s == "pending" or s == "confirmed" or s == "rejected"
	end

	-- drive: server mutations, deliveries, and mutation traffic interleaved
	for _ = 1, rng:range(4, 15) do
		local roll = rng:range(1, 100)
		if roll <= 45 then
			-- server-side change -> patch on the wire
			serverRev += 1
			local key = rng:pick(KEYS)
			if rng:bool(0.75) then
				local value = rng:range(0, 99)
				serverItems[key] = value
				table.insert(network, { kind = "patch", rev = serverRev, patch = { set = { [key] = value } } })
			else
				serverItems[key] = nil
				table.insert(network, { kind = "patch", rev = serverRev, patch = { remove = { key } } })
			end
		elseif roll <= 55 then
			-- spontaneous server resnapshot
			serverRev += 1
			table.insert(network, { kind = "resnap", rev = serverRev, items = table.clone(serverItems) })
		elseif roll <= 80 then
			deliverSome()
		elseif roll <= 90 then
			-- client mutation traffic
			local status = mutation.status:get()
			assert(legalStatus(status), `illegal mutation status {status}`)
			if status == "pending" then
				-- one in flight: a second send must be refused
				local ok = pcall(function()
					mutation.send(rng:range(0, 9))
				end)
				assert(not ok, "send() while pending must error")
				-- resolve it (sometimes after a wrong-id/duplicate attempt)
				if rng:bool(0.4) then
					mutation.confirm((activeEnvelope.requestId :: number) + 1000, "wrong-id")
					assert(mutation.status:get() == "pending", "wrong-id confirm must be ignored")
				end
				if rng:bool(0.5) then
					mutation.confirm(activeEnvelope.requestId, "ok")
					mutation.confirm(activeEnvelope.requestId, "dup") -- idempotent
					assert(mutation.status:get() == "confirmed", "confirm did not land")
				else
					mutation.reject(activeEnvelope.requestId, "no")
					mutation.reject(activeEnvelope.requestId, "dup")
					assert(mutation.status:get() == "rejected", "reject did not land")
				end
				table.insert(resolvedStatuses, mutation.status:get())
				assert(presentation:get() == base, "optimistic presentation must restore on resolution")
				mutation.reset()
				assert(mutation.status:get() == "idle", "reset after resolution must return to idle")
			else
				local payload = rng:range(10, 99)
				activeEnvelope = mutation.send(payload, lastClientRev)
				assert(mutation.status:get() == "pending", "send must move status to pending")
				assert(presentation:get() == payload, "optimistic apply must show the payload")
				assert(
					activeEnvelope.requestId ~= nil and activeEnvelope.expectedRevision == lastClientRev,
					"envelope must carry requestId and expectedRevision"
				)
			end
		else
			-- idle tick: nothing on the wire this step
			deliverSome()
		end
	end

	-- leave no mutation pending (pending never implies success — resolve it)
	if mutation.status:get() == "pending" then
		mutation.reject(activeEnvelope.requestId, "teardown")
		assert(mutation.status:get() == "rejected", "teardown reject did not land")
		assert(presentation:get() == base, "optimistic presentation must restore on teardown reject")
	end

	-- quiesce the network (random order), then reconnect-style resnapshot
	while #network > 0 do
		local index = rng:range(1, #network)
		local message = table.remove(network, index) :: Message
		deliver(message)
	end
	serverRev += 1
	deliver({ kind = "resnap", rev = serverRev, items = table.clone(serverItems) })
	while #network > 0 do -- a gap during quiesce may have queued one more resnapshot
		local message = table.remove(network, 1) :: Message
		deliver(message)
	end

	-- convergence: client == authoritative
	local clientItems = collection.binding:get()
	if serialize(clientItems) ~= serialize(serverItems) then
		error(`client diverged: client=[{serialize(clientItems)}] server=[{serialize(serverItems)}]`)
	end
	assert(collection.revision() == serverRev, `client rev {collection.revision()} != server rev {serverRev}`)
	assert(core:lastError() == nil, `core error during replication fuzz: {tostring(core:lastError())}`)
end

return replication_fuzzer
