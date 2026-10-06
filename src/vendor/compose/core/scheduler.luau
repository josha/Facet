--!strict

local Active = require "./ownership/active"
local Diagnostics = require "./diagnostics"
local Owner = require "./ownership/owner"
local Timeline = require "./animation/timeline"

export type Cancel = () -> boolean

export type Scheduler = {
	after: (seconds: number, body: () -> ()) -> Cancel,
	replace: (key: unknown, seconds: number, body: () -> ()) -> Cancel,
	cancel: (key: unknown) -> boolean,
	clear: () -> (),
	pending: () -> number,
	dispose: () -> (),
}

type Entry = {
	due: number,
	sequence: number,
	key: unknown,
	body: () -> (),
	live: boolean,
}

local function noop(): boolean
	return false
end

local function checkDelay(seconds: unknown)
	if type(seconds) ~= "number" or seconds ~= seconds or seconds < 0 or seconds == math.huge then
		Diagnostics.raise("scheduler/invalid-delay", "a scheduled task needs a finite delay of zero or more seconds", {
			actual = Diagnostics.describe(seconds),
			expected = "seconds, e.g. 0.25; zero runs on the next frame",
		})
	end
end

local function checkBody(body: unknown)
	if type(body) ~= "function" then
		Diagnostics.raise("scheduler/invalid-body", "a scheduled task needs a function to run", {
			actual = Diagnostics.describe(body),
			expected = "a function taking no arguments",
		})
	end
end

local function checkKey(key: unknown)
	if key == nil or key ~= key then
		Diagnostics.raise("scheduler/invalid-key", "a replacement key must be a value other than nil or NaN", {
			actual = Diagnostics.describe(key),
			expected = "a string, number, boolean or table identifying the work",
		})
	end
end

local function createSchedulers(
	timeline: (options: Timeline.Options?) -> Timeline.Timeline,
	requireOwner: (operation: string) -> Owner.Owner
): (owner: Owner.Owner?) -> Scheduler
	return function(explicit: Owner.Owner?): Scheduler
		local parent: Owner.Owner
		if explicit ~= nil then
			if type(explicit) ~= "table" or type(explicit.createChild) ~= "function" then
				Diagnostics.raise("scheduler/invalid-owner", "a scheduler can only be bound to an owner", {
					actual = Diagnostics.describe(explicit),
					expected = "an owner from Compose.createOwner or owner.createChild",
				})
			end
			parent = explicit
		else
			parent = requireOwner "scheduler"
		end

		local scope = parent.createChild()
		local entries: { [Entry]: true } = {}
		local keyed: { [unknown]: Entry } = {}
		local count = 0
		local sequence = 0
		local clock: Timeline.Timeline

		local created, failure: unknown = pcall(function()
			Active.withOwner(scope, function()
				clock = timeline { duration = 1, repeats = math.huge, autoplay = false }
			end)
		end)
		if not created then
			pcall(scope.dispose)
			error(failure, 0)
		end

		local function retire(entry: Entry): boolean
			if not entry.live then
				return false
			end
			entry.live = false
			entries[entry] = nil
			count -= 1
			if entry.key ~= nil and keyed[entry.key] == entry then
				keyed[entry.key] = nil
			end
			if count == 0 then
				clock:pause()
			end
			return true
		end

		local function drain(now: number)
			local due: { Entry } = {}
			for entry in entries do
				if entry.due <= now then
					table.insert(due, entry)
				end
			end
			if #due == 0 then
				return
			end
			table.sort(due, function(a: Entry, b: Entry): boolean
				if a.due ~= b.due then
					return a.due < b.due
				end
				return a.sequence < b.sequence
			end)
			local failures: { unknown } = {}
			for _, entry in due do
				if entry.live then
					retire(entry)
					local ok, problem: unknown = pcall(function()
						Active.withOwner(scope, entry.body)
						return nil
					end)
					if not ok then
						table.insert(failures, problem)
					end
				end
			end
			Owner.raiseAll(failures)
		end

		scope.own(function()
			for entry in entries do
				entry.live = false
			end
			table.clear(entries)
			table.clear(keyed)
			count = 0
		end)
		scope.watchStatic(clock.elapsed, drain)

		local function schedule(key: unknown, seconds: number, body: () -> ()): Cancel
			checkDelay(seconds)
			checkBody(body)
			if scope.isDisposed() then
				return noop
			end
			if key ~= nil then
				local prior = keyed[key]
				if prior ~= nil then
					retire(prior)
				end
			end
			sequence += 1
			local entry: Entry = {
				due = clock.elapsed:peek() + seconds,
				sequence = sequence,
				key = key,
				body = body,
				live = true,
			}
			entries[entry] = true
			if key ~= nil then
				keyed[key] = entry
			end
			count += 1
			if count == 1 then
				clock:play()
			end
			return function(): boolean
				return retire(entry)
			end
		end

		return {
			after = function(seconds: number, body: () -> ()): Cancel
				return schedule(nil, seconds, body)
			end,
			replace = function(key: unknown, seconds: number, body: () -> ()): Cancel
				checkKey(key)
				return schedule(key, seconds, body)
			end,
			cancel = function(key: unknown): boolean
				local entry = keyed[key]
				return entry ~= nil and retire(entry)
			end,
			clear = function()
				local live: { Entry } = {}
				for entry in entries do
					table.insert(live, entry)
				end
				for _, entry in live do
					retire(entry)
				end
			end,
			pending = function(): number
				return count
			end,
			dispose = scope.dispose,
		}
	end
end

return {
	createSchedulers = createSchedulers,
}
