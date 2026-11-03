--!strict

local ComposeTypes = require("../vendor/compose/core")
local CollectionTypes = require("./collection_types")

export type State = "none" | "selected" | "only"
export type Paint<S> = (S, State, State?) -> ()
export type Highlight<K, S> = {
	track: (S, K) -> (),
	move: (S, K) -> (),
	forget: (S) -> (),
	bind: (ComposeTypes.ReadOnlyValue<K>, S) -> (),
}

return function<K, S>(
	Compose: typeof(ComposeTypes),
	selection: ComposeTypes.ReadOnlyValue<CollectionTypes.Selection<K>>,
	active: boolean,
	render: Paint<S>
): Highlight<K, S>
	if not active then
		local function track(subject: S, _key: K)
			render(subject, "none", nil)
		end
		local function ignore() end
		return {
			track = track,
			move = ignore,
			forget = ignore,
			bind = function(key: ComposeTypes.ReadOnlyValue<K>, subject: S)
				track(subject, key:peek())
			end,
		}
	end
	local owner = assert(Compose.currentOwner())
	local rows: { [K]: { [S]: boolean } } = {}
	local keys: { [S]: K } = {}
	local states: { [S]: State } = {}
	local chosen: CollectionTypes.Selection<K> = {}
	local single: K? = nil
	local many = false
	local started = false
	local function stateFor(key: K): State
		return if chosen[key] then (if many then "selected" else "only") else "none"
	end
	local function paint(subject: S, state: State)
		local previous = states[subject]
		if previous ~= state then
			states[subject] = state
			render(subject, state, previous)
		end
	end
	local function notify(key: K, state: State, failures: { string }?): { string }?
		local bucket = rows[key]
		if bucket then
			for subject in bucket do
				local ok, problem: unknown = pcall(paint, subject, state)
				if not ok then
					local messages = failures or {}
					table.insert(messages, tostring(problem))
					failures = messages
				end
			end
		end
		return failures
	end
	local function remove(subject: S)
		local key = keys[subject]
		if key == nil then
			return
		end
		local bucket = rows[key]
		if bucket then
			bucket[subject] = nil
			if next(bucket) == nil then
				rows[key] = nil
			end
		end
	end
	local function start()
		started = true
		Compose.owner.watchStatic(owner, selection, function(incoming)
			local first: K? = nil
			local multiple = false
			for candidate, on in incoming do
				if on then
					if first ~= nil then
						multiple = true
						break
					end
					first = candidate
				end
			end
			local previous, wasMany = single, many
			chosen, single, many = incoming, first, multiple
			local failures: { string }? = nil
			if wasMany or multiple then
				for candidate in rows do
					failures = notify(candidate, stateFor(candidate), failures)
				end
			else
				if previous ~= nil then
					failures = notify(previous, stateFor(previous), failures)
				end
				if first ~= nil and not rawequal(first, previous) then
					local winner = first :: K
					failures = notify(winner, stateFor(winner), failures)
				end
			end
			if failures then
				error(table.concat(failures, "\n"), 0)
			end
		end)
	end
	local function move(subject: S, key: K)
		remove(subject)
		keys[subject] = key
		local bucket = rows[key]
		if bucket == nil then
			bucket = {}
			rows[key] = bucket
		end
		bucket[subject] = true
		paint(subject, stateFor(key))
	end
	local function track(subject: S, key: K)
		if not started then
			start()
		end
		move(subject, key)
	end
	local function forget(subject: S)
		remove(subject)
		keys[subject] = nil
		states[subject] = nil
	end
	return {
		track = track,
		move = function(subject: S, key: K)
			if keys[subject] ~= nil then
				move(subject, key)
			end
		end,
		forget = forget,
		bind = function(key: ComposeTypes.ReadOnlyValue<K>, subject: S)
			if not started then
				start()
			end
			Compose.owner.watchStatic(assert(Compose.currentOwner()), key, function(now)
				move(subject, now)
			end)
			Compose.cleanup(function()
				forget(subject)
			end)
		end,
	}
end
