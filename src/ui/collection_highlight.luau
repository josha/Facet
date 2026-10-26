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
	local rows: { [K]: { [Paint]: boolean } } = {}
	local previous: CollectionTypes.Selection<K> = {}
	local previousOnly: K? = nil
	local function only(chosen: CollectionTypes.Selection<K>): K?
		local result: K? = nil
		for key, selected in chosen do
			if selected then
				if result ~= nil then
					return nil
				end
				result = key
			end
		end
		return result
	end
	local function paint(key: K, state: State)
		local indicators = rows[key]
		if indicators then
			for indicator in indicators do
				indicator(state)
			end
		end
	end
	Compose.watch(function(use: ComposeTypes.Use)
		local chosen = table.clone(use(selection))
		local sole = only(chosen)
		for key, selected in previous do
			if selected and chosen[key] ~= true then
				paint(key, "none")
			end
		end
		for key, selected in chosen do
			if selected and (previous[key] ~= true or (key == sole) ~= (key == previousOnly)) then
				paint(key, if key == sole then "only" else "selected")
			end
		end
		previous, previousOnly = chosen, sole
	end)
	return function(key: ComposeTypes.ReadOnlyValue<K>, render: Paint)
		local held: K? = nil
		local function forget()
			if held ~= nil then
				local indicators = rows[held]
				if indicators then
					indicators[render] = nil
					if next(indicators) == nil then
						rows[held] = nil
					end
				end
			end
		end
		Compose.watch(function(use: ComposeTypes.Use)
			local now = use(key)
			forget()
			held = now
			local indicators = rows[now] or {}
			rows[now] = indicators
			indicators[render] = true
			local chosen = selection:peek()
			render(if chosen[now] ~= true then "none" elseif now == only(chosen) then "only" else "selected")
		end)
		Compose.cleanup(forget)
	end
end
