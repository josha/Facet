--!strict

local Lifecycle = require "./lifecycle"
local Wait = require "./wait"

export type Probe = { ready: boolean, lost: boolean?, observed: unknown? }

export type Ops = Lifecycle.Ops & {
	join: (name: string) -> Lifecycle.Returned,
	probe: (name: string, remainingSeconds: number) -> Probe,
	leave: (name: string) -> Lifecycle.Returned,
}

export type Spec = {
	name: string,
	actors: { string },
	resources: { string }?,
	deadlineSeconds: number,
	pollSeconds: number,
	body: Lifecycle.Body,
}

local function names(count: number, prefix: string?): { string }
	assert(count >= 1 and count % 1 == 0, "actor count must be a positive integer")
	local out: { string } = {}
	for index = 1, count do
		table.insert(out, ("%s-%d"):format(prefix or "client", index))
	end
	return out
end

local function run(spec: Spec, ops: Ops): Lifecycle.Result
	local seen: { [string]: boolean } = {}
	for _, actor in spec.actors do
		assert(actor ~= "" and not seen[actor], "actor names must be unique and not empty")
		seen[actor] = true
	end
	local joined: { string } = {}
	local held: { { name: string, handle: any } } = {}

	local function release(): { string }
		local problems: { string } = {}
		for index = #held, 1, -1 do
			local entry = held[index]
			local called, released = pcall(function(): Lifecycle.Returned?
				if ops.release == nil then
					return { ok = false, detail = "release_unavailable" }
				end
				return (ops.release :: (any, string) -> Lifecycle.Returned?)(entry.handle, entry.name)
			end)
			if not called then
				table.insert(problems, ("resource %s: %s"):format(entry.name, tostring(released)))
			elseif type(released) == "table" and released.ok == false then
				table.insert(problems, ("resource %s: %s"):format(entry.name, released.detail or "release refused"))
			end
		end
		held = {}
		return problems
	end

	local lifecycleOps: Lifecycle.Ops = table.clone(ops) :: any
	lifecycleOps.start = function(): Lifecycle.Returned
		local resources: { string } = spec.resources or {}
		for _, resource in resources do
			if ops.acquire == nil then
				return { ok = false, reason = "resource_unavailable", detail = resource .. ": acquire_unavailable" }
			end
			local acquired = Wait.waitUntil({
				name = "resource " .. resource,
				deadlineSeconds = spec.deadlineSeconds,
				pollSeconds = spec.pollSeconds,
				probe = function(): (boolean, unknown, string?)
					local handle, why = (ops.acquire :: (string) -> (any?, string?))(resource)
					if handle ~= nil then
						table.insert(held, { name = resource, handle = handle })
					end
					return handle ~= nil, why
				end,
			}, { now = ops.now, sleep = ops.sleep or function() end, cancelled = ops.interrupted })
			if not acquired.ok then
				return { ok = false, reason = "resource_unavailable", detail = acquired.detail }
			end
		end
		for _, actor in spec.actors do
			table.insert(joined, actor)
			local entered = ops.join(actor)
			if not entered.ok then
				return {
					ok = false,
					reason = "actor_join_failed",
					detail = ("%s: %s"):format(actor, entered.detail or "refused"),
				}
			end
		end
		local pending: { [string]: boolean } = {}
		for _, actor in spec.actors do
			pending[actor] = true
		end
		local lost: string? = nil
		local waited = Wait.waitUntil({
			name = "actors ready",
			deadlineSeconds = spec.deadlineSeconds,
			pollSeconds = spec.pollSeconds,
			probe = function(remaining: number): (boolean, unknown, string?)
				local states: { [string]: unknown } = {}
				for _, actor in spec.actors do
					if pending[actor] then
						local state = ops.probe(actor, remaining)
						states[actor] = state.observed
						if state.lost == true then
							lost = actor
							return false,
								states,
								("actor %s lost; last observed: %s"):format(actor, tostring(state.observed))
						end
						if state.ready then
							pending[actor] = nil
						end
					end
				end
				return next(pending) == nil, states
			end,
			describe = function(observed: unknown): string
				local rows: { string } = {}
				for _, actor in spec.actors do
					if pending[actor] then
						table.insert(rows, ("%s=%s"):format(actor, tostring((observed :: any or {})[actor])))
					end
				end
				return if #rows == 0 then "all ready" else table.concat(rows, ", ")
			end,
		}, { now = ops.now, sleep = ops.sleep or function() end, cancelled = ops.interrupted })
		if waited.ok then
			return { ok = true }
		end
		return {
			ok = false,
			reason = if lost ~= nil
				then "actor_lost"
				elseif waited.reason == "timeout" then "actors_not_ready"
				else waited.reason,
			timedOut = waited.reason == "timeout",
			detail = waited.detail,
		}
	end
	lifecycleOps.stop = function(): Lifecycle.Returned
		local problems: { string } = {}
		for index = #joined, 1, -1 do
			local actor = joined[index]
			local called, left = pcall(ops.leave, actor)
			if not called then
				table.insert(problems, ("%s: %s"):format(actor, tostring(left)))
			elseif not left.ok then
				table.insert(problems, ("%s: %s"):format(actor, left.detail or "leave refused"))
			end
		end
		joined = {}
		for _, problem in release() do
			table.insert(problems, problem)
		end
		if #problems > 0 then
			return { ok = false, reason = "actor_cleanup_failed", detail = table.concat(problems, "; ") }
		end
		return { ok = true }
	end
	return Lifecycle.run({ name = spec.name, start = { id = "actors" }, body = spec.body }, lifecycleOps)
end

return {
	names = names,
	run = run,
}
