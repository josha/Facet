--!strict

local Active = require "./ownership/active"
local Diagnostics = require "./diagnostics"
local Owner = require "./ownership/owner"
local Types = require "./reactive/types"
local cellModule = require "./reactive/cell"
local formula = require "./reactive/formula"
local Support = require "./structure/support"

export type Options<V, K> = {
	from: Types.Readable<{ V }> | Types.Body<{ V }>,
	key: ((value: V, index: number) -> K)?,
	disabled: ((value: V, index: number) -> boolean)?,
	position: ((value: V, index: number) -> (number, number))?,
	wrap: boolean?,
	initial: K?,
	autoFocus: boolean?,
}

export type FocusScope<K> = {
	current: Types.Readable<K?>,
	focus: (key: K) -> boolean,
	clear: () -> (),
	next: () -> K?,
	previous: () -> K?,
	move: (direction: Direction) -> K?,
	first: () -> K?,
	last: () -> K?,
	isFocused: (key: K) -> Types.Readable<boolean>,
}

export type Direction = "left" | "right" | "up" | "down"

local KNOWN_FIELDS: { [string]: true } = {
	from = true,
	key = true,
	disabled = true,
	position = true,
	wrap = true,
	initial = true,
	autoFocus = true,
}

local function identity<V>(value: V, _index: number): V
	return value
end

local function createFocusScope<V, K>(options: Options<V, K>): FocusScope<K>
	local settings = Support.optionsOf(options, "createFocusScope", "from = ..., key = ...")
	Support.noUnknownFields(settings, "createFocusScope", KNOWN_FIELDS)
	local owner = Active.current()
	if owner == nil then
		Diagnostics.raise("focus-scope/no-active-owner", "createFocusScope ran outside an owner", {
			contract = "a focus scope lives exactly as long as the component or owner that created it",
			fix = "create it inside a component or Compose.withOwner(owner, ...)",
		})
	end
	local source = Support.sourceOf(settings.from, "createFocusScope", "from") :: Types.Body<{ V }>
	local keyOf: (value: V, index: number) -> K = if settings.key == nil
		then (identity :: any) :: (value: V, index: number) -> K
		else Support.builderOf(settings.key, "createFocusScope", "key")
	local disabled: ((value: V, index: number) -> boolean)? = if settings.disabled == nil
		then nil
		else Support.builderOf(settings.disabled, "createFocusScope", "disabled")
	local positionOf: ((value: V, index: number) -> (number, number))? = if settings.position == nil
		then nil
		else Support.builderOf(settings.position, "createFocusScope", "position")
	local wrap = settings.wrap == true
	local autoFocus = settings.autoFocus == true
	local initial: K? = settings.initial
	local current: Types.Cell<K?> = cellModule.cell(initial)
	local order: { K } = {}
	local positions: { [K]: number } = {}
	local points: { [K]: { x: number, y: number } } = {}
	local alive = true
	local holder = owner :: Owner.Owner

	holder.own(function()
		alive = false
		table.clear(order)
		table.clear(positions)
		table.clear(points)
	end)
	holder.watch(function(use)
		local list = source(use)
		table.clear(order)
		table.clear(positions)
		table.clear(points)
		for index, value in list do
			if disabled == nil or not (disabled :: (V, number) -> boolean)(value, index) then
				local key = keyOf(value, index)
				if positions[key] ~= nil then
					Diagnostics.raise("focus-scope/duplicate-key", "createFocusScope encountered the same key twice", {
						index = index,
						contract = "focus candidates have stable unique keys",
					})
				end
				order[#order + 1] = key
				positions[key] = #order
				if positionOf ~= nil then
					local x, y = (positionOf :: (V, number) -> (number, number))(value, index)
					if
						type(x) ~= "number"
						or type(y) ~= "number"
						or x ~= x
						or y ~= y
						or math.abs(x) == math.huge
						or math.abs(y) == math.huge
					then
						Diagnostics.raise(
							"focus-scope/invalid-position",
							"createFocusScope.position returned invalid coordinates",
							{
								index = index,
								expected = "two finite numbers",
							}
						)
					end
					points[key] = { x = x, y = y }
				end
			end
		end
		local selected = current:peek()
		if selected ~= nil and positions[selected] == nil then
			current:set(if autoFocus then order[1] else nil)
		elseif selected == nil and autoFocus then
			current:set(order[1])
		end
	end)

	local function ensureAlive(): boolean
		return alive
	end

	local function focus(key: K): boolean
		if not ensureAlive() or positions[key] == nil then
			return false
		end
		current:set(key)
		return true
	end

	local function clear()
		if ensureAlive() then
			current:set(nil)
		end
	end

	local function choose(index: number): K?
		if not ensureAlive() or #order == 0 then
			return nil
		end
		local target = index
		if wrap then
			target = ((target - 1) % #order) + 1
		else
			target = math.clamp(target, 1, #order)
		end
		local key = order[target]
		current:set(key)
		return key
	end

	local function first(): K?
		return choose(1)
	end

	local function last(): K?
		return choose(#order)
	end

	local function move(delta: number): K?
		local selected = current:peek()
		if selected == nil then
			return if delta > 0 then first() else last()
		end
		return choose((positions[selected] or 1) + delta)
	end

	local function moveDirection(direction: Direction): K?
		if direction ~= "left" and direction ~= "right" and direction ~= "up" and direction ~= "down" then
			Diagnostics.raise("focus-scope/unknown-direction", "focus movement needs a known direction", {
				actual = Diagnostics.describe(direction),
				expected = '"left", "right", "up", or "down"',
			})
		end
		if positionOf == nil then
			Diagnostics.raise("focus-scope/no-positions", "directional focus movement needs candidate positions", {
				fix = "pass position = function(item) return item.x, item.y end, or use next/previous",
			})
		end
		local selected = current:peek()
		if selected == nil or points[selected] == nil then
			return first()
		end
		local origin = points[selected]
		local best: K? = nil
		local bestScore = math.huge
		for _, key in order do
			if key ~= selected then
				local point = points[key]
				local dx, dy = point.x - origin.x, point.y - origin.y
				local primary, cross: number
				if direction == "left" then
					primary, cross = -dx, math.abs(dy)
				elseif direction == "right" then
					primary, cross = dx, math.abs(dy)
				elseif direction == "up" then
					primary, cross = -dy, math.abs(dx)
				else
					primary, cross = dy, math.abs(dx)
				end
				if primary > 0 then
					local score = primary + cross * 2
					if score < bestScore then
						best, bestScore = key, score
					end
				end
			end
		end
		if best ~= nil then
			current:set(best)
			return best
		end
		return selected
	end

	local function isFocused(key: K): Types.Readable<boolean>
		local value = formula(function(use)
			return use(current) == key
		end)
		holder.own(function()
			value:dispose()
		end)
		return value
	end

	return {
		current = current,
		focus = focus,
		clear = clear,
		next = function()
			return move(1)
		end,
		previous = function()
			return move(-1)
		end,
		move = moveDirection,
		first = first,
		last = last,
		isFocused = isFocused,
	}
end

return createFocusScope
