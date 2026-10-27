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
	type Indicator = { key: K, paint: Paint }
	local owner = assert(Compose.currentOwner())
	local multiple = {}
	local rows: { [Indicator]: boolean } = {}
	local isOnly: ((K | {} | nil) -> ComposeTypes.ReadOnlyValue<boolean>)? = nil
	return function(key: ComposeTypes.ReadOnlyValue<K>, render: Paint)
		if isOnly == nil then
			isOnly = Compose.withOwner(owner, function()
				local function createSole(initial: K | {} | nil): ComposeTypes.Value<K | {} | nil>
					return Compose.cell(initial, rawequal)
				end
				local sole = createSole(nil)
				local selected = Compose.selector(sole)
				local wasMultiple = false
				Compose.owner.watchStatic(owner, selection, function(chosen)
					local result: K? = nil
					local many = false
					for candidate, on in chosen do
						if on then
							if result ~= nil then
								many = true
								break
							end
							result = candidate
						end
					end
					sole:set(if many then multiple else result)
					if many or wasMultiple then
						for row in rows do
							row.paint(if chosen[row.key] ~= true then "none" elseif many then "selected" else "only")
						end
					end
					wasMultiple = many
				end)
				return selected
			end)
		end
		local selected = assert(isOnly)
		local state: State? = nil
		local function paint(nextState: State)
			if nextState ~= state then
				state = nextState
				render(nextState)
			end
		end
		local row: Indicator = { key = key:peek(), paint = paint }
		rows[row] = true
		local rowOwner = assert(Compose.currentOwner())
		local stop: (() -> ())? = nil
		Compose.owner.watchStatic(rowOwner, key, function(now)
			row.key = now
			if stop then
				stop()
			end
			stop = Compose.owner.watchStatic(rowOwner, selected(now), function(only)
				paint(if only then "only" elseif selection:peek()[now] == true then "selected" else "none")
			end)
		end)
		Compose.cleanup(function()
			rows[row] = nil
		end)
	end
end
