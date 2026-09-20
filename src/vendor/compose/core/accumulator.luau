--!strict

local Active = require "./ownership/active"
local Diagnostics = require "./diagnostics"
local OwnerModule = require "./ownership/owner"
local Support = require "./structure/support"
local Types = require "./reactive/types"
local cellModule = require "./reactive/cell"
local userSpace = require "./reactive/userSpace"

export type Options<T, E> = {
	from: Types.Readable<E>,
	reduce: (previous: T, event: E) -> T,
	initial: Types.Initial<T>?,
	equals: Types.Equals<T>?,
}

local KNOWN_FIELDS: { [string]: true } = {
	from = true,
	reduce = true,
	initial = true,
	equals = true,
}

local function accumulator<T, E>(options: Options<T, E>): Types.Readable<T>
	local settings = Support.optionsOf(options, "accumulator", "from = ..., reduce = ..., initial = ...")
	Support.noUnknownFields(settings, "accumulator", KNOWN_FIELDS)

	local owner = Active.current()
	if owner == nil then
		Diagnostics.raise("accumulator/no-active-owner", "accumulator ran with no owner to hold it", {
			contract = "an accumulator subscribes to its source, and the subscription lives exactly "
				.. "as long as the owner that created it",
			fix = "create it inside a component or Compose.withOwner(owner, ...); a process-wide "
				.. "accumulator is one created in a root owner kept for the life of the process",
		})
	end

	local source = settings.from
	if not cellModule.isReadable(source) then
		Diagnostics.raise("accumulator/from-not-readable", "accumulator was given a source it cannot track", {
			actual = Diagnostics.describe(source),
			expected = "a cell or a formula",
			contract = "an accumulator tracks exactly one readable source and reduces each of its "
				.. "changes into its own state",
			fix = "pass the cell or formula that carries the events: from = castFired",
		})
	end

	local reduce = settings.reduce
	if type(reduce) ~= "function" then
		Diagnostics.raise("accumulator/reduce-not-a-function", "accumulator was given a reduce it cannot call", {
			actual = Diagnostics.describe(reduce),
			expected = "a function (previous, event) -> next",
			fix = "pass the reducer that merges one event into the running state",
		})
	end

	local state = cellModule.cell(settings.initial, settings.equals)

	local holder = owner :: OwnerModule.Owner
	holder.watchStatic(source, function(event: any)
		state:set(userSpace.call(reduce, state:peek(), event))
	end)

	return (state :: any) :: Types.Readable<T>
end

return accumulator
