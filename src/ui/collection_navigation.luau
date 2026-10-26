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
	local Compose = ctx.Compose
	local E = ctx.types.Enum
	local spec, kind, keyOf, horizontal = view.spec, view.kind, view.keyOf, view.horizontal
	local extendSelection = view.extendSelection
	local tree = view.tree
	local function current(): { V }
		return view.source(function<T>(readable: ComposeTypes.ReadOnlyValue<T>): T
			return readable:peek()
		end)
	end
	local function usable(item: V, index: number): boolean
		return not (tree ~= nil and not tree.visible(keyOf(item, index))) and not policy.disabled(spec.disabled, item)
	end
	local directions: { { name: string, direction: ComposeTypes.FocusDirection, keys: { Enum.KeyCode } } } = {
		{ name = "Left", direction = "left", keys = { E.KeyCode.Left, E.KeyCode.DPadLeft } },
		{ name = "Right", direction = "right", keys = { E.KeyCode.Right, E.KeyCode.DPadRight } },
		{ name = "Up", direction = "up", keys = { E.KeyCode.Up, E.KeyCode.DPadUp } },
		{ name = "Down", direction = "down", keys = { E.KeyCode.Down, E.KeyCode.DPadDown } },
	}
	local function atEdge(key: K, step: number): boolean
		local rows = current()
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
			if usable(rows[index], index) then
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
				local rows = current()
				local columns = view.gridColumns(nil, math.max(0, view.cross:peek() - 2 * view.crossEdge()))
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
	local controls = view.controls
	local function page(step: number): () -> ()
		return function()
			local placementOf, indexOfKey = controls.placementOf, controls.indexOfKey
			local before = focusScope.current:peek()
			if before == nil or placementOf == nil or indexOfKey == nil then
				return
			end
			local at = indexOfKey(before)
			local rows = current()
			if at == nil or rows[at] == nil then
				return
			end
			local here = placementOf(at)
			local reach = math.max(view.viewport:peek().size, here.size)
			local target: number?, last: number? = nil, nil
			local index = at + step
			while index >= 1 and index <= #rows do
				local there = placementOf(index)
				local distance = if step > 0
					then there.offset + there.size - here.offset
					else here.offset + here.size - there.offset
				if distance > reach and (target ~= nil or distance > 2 * reach) then
					break
				end
				if usable(rows[index], index) then
					last = index
					if there.column == here.column then
						target = index
						if distance > reach then
							break
						end
					end
				end
				index += step
			end
			local edge = if step > 0 then #rows else 1
			if
				target == nil
				and last ~= nil
				and placementOf(last).row == placementOf(edge).row
				and placementOf(last).row ~= here.row
			then
				target = last
			end
			if target ~= nil then
				focusScope.focus(keyOf(rows[target], target))
				local landed = focusScope.current:peek()
				if landed ~= nil then
					extendSelection(before, landed)
				end
			end
		end
	end
	local owner = assert(Compose.currentOwner(), "collection navigation requires a Compose owner")
	local function armPaging()
		view.armPaging = nil
		Compose.withOwner(ComposeTypes.owner.createChild(owner), function()
			ctx.action(
				root,
				"CollectionPageDown",
				{ E.KeyCode.PageDown, E.KeyCode.ButtonR2 },
				eligible,
				page(1),
				{ priority = 200 }
			)
			ctx.action(
				root,
				"CollectionPageUp",
				{ E.KeyCode.PageUp, E.KeyCode.ButtonL2 },
				eligible,
				page(-1),
				{ priority = 200 }
			)
		end)
	end
	view.armPaging = armPaging
	if focusScope.current:peek() ~= nil then
		armPaging()
	end
	ctx.action(root, "CollectionFirst", { E.KeyCode.Home }, eligible, jump(focusScope.first), { priority = 200 })
	ctx.action(root, "CollectionLast", { E.KeyCode.End }, eligible, jump(focusScope.last), { priority = 200 })
end
