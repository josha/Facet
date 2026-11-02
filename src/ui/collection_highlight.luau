--!strict

local ComposeTypes = require("../vendor/compose/core")
local CollectionTypes = require("./collection_types")

export type State = "none" | "selected" | "only"
export type Paint = (State) -> ()
export type Bind<K> = (ComposeTypes.ReadOnlyValue<K>, Paint) -> ()

return function<K>(
	Compose: typeof(ComposeTypes),
	selection: ComposeTypes.ReadOnlyValue<CollectionTypes.Selection<K>>,
	active: boolean
): Bind<K>
	if not active then
		return function(_key: ComposeTypes.ReadOnlyValue<K>, paint: Paint)
			paint("none")
		end
	end
	type Indicator = { key: K, paint: Paint, state: State? }
	local owner = assert(Compose.currentOwner())
	local rows: { [K]: { [Indicator]: boolean } } = {}
	local chosen: CollectionTypes.Selection<K> = {}
	local single: K? = nil
	local many = false
	local started = false
	local function stateFor(key: K): State
		return if chosen[key] then (if many then "selected" else "only") else "none"
	end
	local function paint(row: Indicator, state: State)
		if row.state ~= state then
			row.state = state
			row.paint(state)
		end
	end
	local function notify(key: K, state: State, failures: { string }?): { string }?
		local bucket = rows[key]
		if bucket then
			for row in bucket do
				local ok, problem: unknown = pcall(paint, row, state)
				if not ok then
					local messages = failures or {}
					table.insert(messages, tostring(problem))
					failures = messages
				end
			end
		end
		return failures
	end
	local function remove(row: Indicator)
		local bucket = rows[row.key]
		if bucket then
			bucket[row] = nil
			if next(bucket) == nil then
				rows[row.key] = nil
			end
		end
	end
	return function(key: ComposeTypes.ReadOnlyValue<K>, render: Paint)
		if not started then
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
		local row: Indicator = { key = key:peek(), paint = render }
		local rowOwner = assert(Compose.currentOwner())
		Compose.owner.watchStatic(rowOwner, key, function(now)
			remove(row)
			row.key = now
			local bucket = rows[now]
			if bucket == nil then
				bucket = {}
				rows[now] = bucket
			end
			bucket[row] = true
			paint(row, stateFor(now))
		end)
		Compose.cleanup(function()
			remove(row)
		end)
	end
end
