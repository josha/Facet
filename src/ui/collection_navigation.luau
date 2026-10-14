--!strict
local policy = require("./collection_policy")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local State = require("./collection_state")
return function<V, K>(
	ctx: Types.Context,
	view: State.View<V, K>,
	root: ScrollingFrame,
	focusScope: ComposeTypes.FocusScope<K>,
	eligible: (ComposeTypes.Use) -> boolean
): ()
	local read = ctx.read
	local E = ctx.types.Enum
	local spec, kind, keyOf, horizontal = view.spec, view.kind, view.keyOf, view.horizontal
	local extendSelection = view.extendSelection
	local directions: { { name: string, direction: ComposeTypes.FocusDirection, keys: { Enum.KeyCode } } } = {
		{ name = "Left", direction = "left", keys = { E.KeyCode.Left, E.KeyCode.DPadLeft } },
		{ name = "Right", direction = "right", keys = { E.KeyCode.Right, E.KeyCode.DPadRight } },
		{ name = "Up", direction = "up", keys = { E.KeyCode.Up, E.KeyCode.DPadUp } },
		{ name = "Down", direction = "down", keys = { E.KeyCode.Down, E.KeyCode.DPadDown } },
	}
	local function atEdge(key: K, step: number): boolean
		local rows = read(spec.from)
		local at: number? = nil
		for index, item in rows do
			if keyOf(item, index) == key then
				at = index
				break
			end
		end
		if at == nil then
			return false
		end
		local index = at + step
		while index >= 1 and index <= #rows do
			if not policy.disabled(spec.disabled, rows[index]) then
				return false
			end
			index += step
		end
		return true
	end
	local function wrapStep(direction: ComposeTypes.FocusDirection): number
		local along = if kind == "grid"
			then true
			elseif horizontal then direction == "left" or direction == "right"
			else direction == "up" or direction == "down"
		if not along then
			return 0
		end
		return if direction == "right" or direction == "down" then 1 else -1
	end
	for _, binding in directions do
		local along = binding.direction == (if horizontal then "left" else "up")
			or binding.direction == (if horizontal then "right" else "down")
		local function enabled(use: ComposeTypes.Use): boolean
			return (along or kind == "grid") and eligible(use)
		end
		ctx.action(root, "Collection" .. binding.name, binding.keys, enabled, function()
			local before = focusScope.current:peek()
			local after = focusScope.move(binding.direction)
			if kind == "grid" and spec.wrapFocus and before ~= nil and after == before then
				local rows = read(spec.from)
				local columns = math.max(1, math.floor(read(spec.columns or 1)))
				local at: number? = nil
				for index, item in rows do
					if keyOf(item, index) == before then
						at = index
						break
					end
				end
				if at ~= nil then
					local column = (at - 1) % columns
					local rowStart = at - column
					local rowEnd = math.min(rowStart + columns - 1, #rows)
					local target = if binding.direction == "right"
						then rowStart
						elseif binding.direction == "left" then rowEnd
						elseif binding.direction == "down" then column + 1
						else column + 1 + math.floor((#rows - 1 - column) / columns) * columns
					if target ~= at and rows[target] ~= nil then
						focusScope.focus(keyOf(rows[target], target))
					end
				end
				return
			end
			local step = if spec.wrapFocus and before ~= nil and after == before then wrapStep(binding.direction) else 0
			if step ~= 0 and not atEdge(assert(before), step) then
				step = 0
			end
			if step > 0 then
				focusScope.next()
			elseif step < 0 then
				focusScope.previous()
			end
			local landed = focusScope.current:peek()
			if landed ~= nil then
				extendSelection(before, landed)
			end
		end, { priority = 200 })
	end
	local function jump(move: () -> ()): () -> ()
		return function()
			local before = focusScope.current:peek()
			move()
			local landed = focusScope.current:peek()
			if landed ~= nil then
				extendSelection(before, landed)
			end
		end
	end
	ctx.action(root, "CollectionFirst", { E.KeyCode.Home }, eligible, jump(focusScope.first), { priority = 200 })
	ctx.action(root, "CollectionLast", { E.KeyCode.End }, eligible, jump(focusScope.last), { priority = 200 })
end
