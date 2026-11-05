--!strict

local Children = require "../runtime/children"
local Active = require "../ownership/active"
local Owners = require "../ownership/owner"
local Host = require "../host"
local Support = require "../structure/support"
local Types = require "../reactive/types"
local cellModule = require "../reactive/cell"
local keyed = require "../structure/keyed"

export type Render<V, S, K> = (value: Types.ReadOnlyValue<V>, state: Types.ReadOnlyValue<S>, key: K) -> Host.Node
export type Recycle<V, S, K> = (
	value: Types.ReadOnlyValue<V>,
	state: Types.ReadOnlyValue<S>,
	key: Types.ReadOnlyValue<K>
) -> Host.Node

export type Selection<V, S, K> = {
	values: { V },
	keys: { K },
	states: { S },
}

export type Options<V, S, K> = {
	primitive: string,
	source: Types.Body<{ V }>,
	select: (use: Types.Use, list: { V }) -> Selection<V, S, K>,
	render: Render<V, S, K>?,
	recycle: Recycle<V, S, K>?,
	equals: ((a: S, b: S) -> boolean)?,
}

local function retainKeyed<V, S, K>(options: Options<V, S, K>, render: Render<V, S, K>): Children.Directive
	local source = options.source
	local selectItems = options.select
	local equals = options.equals

	local states: { [K]: Types.Value<S> } = {}
	local keysAt: { K } = {}
	local pending: { [K]: S } = {}
	local present: { [K]: true } = {}

	local function slice(use: Types.Use): { V }
		local list = source(use)
		local selection = selectItems(use, list)
		local values, keys, itemStates = selection.values, selection.keys, selection.states
		local count = #values

		table.clear(present)
		table.clear(keysAt)
		for index = 1, count do
			local key = keys[index]
			keysAt[index] = key
			present[key] = true
			local held = states[key]
			if held ~= nil then
				held:set(itemStates[index])
			else
				pending[key] = itemStates[index]
			end
		end

		for key in states do
			if present[key] == nil then
				states[key] = nil
			end
		end

		return values
	end

	local function keyOfRetained(_value: V, index: number): K
		return keysAt[index]
	end

	local function renderRetained(value: Types.ReadOnlyValue<V>, _index: Types.ReadOnlyValue<number>, key: K): Host.Node
		local state = states[key]
		if state == nil then
			state = cellModule.cell(pending[key], equals)
			states[key] = state
			pending[key] = nil
		end
		return render(value, state, key)
	end

	return keyed<<V, K>> { from = slice, key = keyOfRetained, render = renderRetained }
end

local function retainSlots<V, S, K>(
	options: Options<V, S, K>,
	recycle: Recycle<V, S, K>,
	owner: Owners.Owner
): Children.Directive
	local source = options.source
	local selectItems = options.select
	local equals = options.equals

	local slotOf: { [K]: number } = {}
	local keyAt: { [number]: K } = {}
	local states: { [number]: Types.Value<S> } = {}
	local keyCells: { [number]: Types.Value<K> } = {}
	local valuesAt: { [number]: Types.Value<V> } = {}
	local rows: { [number]: { node: Host.Node, owner: Owners.Owner } } = {}
	local idle: { [number]: true } = {}
	local pendingStates: { [number]: S } = {}
	local pendingKeys: { [number]: K } = {}
	local slotsAt: { number } = {}
	local present: { [K]: true } = {}
	local free: { number } = {}
	local issued = 0

	local function slice(use: Types.Use): { V }
		local list = source(use)
		local selection = selectItems(use, list)
		local values, keys, itemStates = selection.values, selection.keys, selection.states
		local count = #values

		table.clear(present)
		for index = 1, count do
			present[keys[index]] = true
		end
		table.clear(free)
		for slot, key in keyAt do
			if present[key] == nil then
				keyAt[slot] = nil
				slotOf[key] = nil
				idle[slot] = true
			end
		end
		for slot in idle do
			table.insert(free, slot)
		end
		table.sort(free)

		table.clear(slotsAt)
		local reused = 0
		for index = 1, count do
			local key = keys[index]
			local slot = slotOf[key]
			if slot == nil then
				reused += 1
				slot = free[reused]
				if slot == nil then
					issued += 1
					slot = issued
				end
				slotOf[key] = slot
				keyAt[slot] = key
				idle[slot] = nil
			end
			slotsAt[index] = slot
			local held = states[slot]
			if held ~= nil then
				valuesAt[slot]:set(values[index])
				held:set(itemStates[index])
				local keyCell = keyCells[slot]
				if keyCell ~= nil then
					keyCell:set(key)
				end
			else
				pendingStates[slot] = itemStates[index]
				pendingKeys[slot] = key
			end
		end

		for index = reused + count + 1, #free do
			local slot = free[index]
			local row = rows[slot]
			rows[slot] = nil
			idle[slot] = nil
			valuesAt[slot] = nil
			states[slot] = nil
			keyCells[slot] = nil
			pendingStates[slot] = nil
			pendingKeys[slot] = nil
			if row ~= nil then
				Owners.dispose(row.owner)
			end
		end

		return values
	end

	local function slotOfRetained(_value: V, index: number): number
		return slotsAt[index]
	end

	local function renderSlot(
		value: Types.ReadOnlyValue<V>,
		_index: Types.ReadOnlyValue<number>,
		slot: number
	): Host.Node
		local existing = rows[slot]
		if existing ~= nil then
			return existing.node
		end
		local heldValue = cellModule.cell(value:peek())
		valuesAt[slot] = heldValue
		local state = states[slot]
		local keyCell = keyCells[slot]
		if state == nil or keyCell == nil then
			state = cellModule.cell(pendingStates[slot], equals)
			keyCell = cellModule.cell(pendingKeys[slot])
			states[slot] = state
			keyCells[slot] = keyCell
			pendingStates[slot] = nil
			pendingKeys[slot] = nil
		end
		local rowOwner = Owners.createChild(owner)
		local ok, node = pcall(Active.withOwner, rowOwner, function()
			return recycle(heldValue, state, keyCell)
		end)
		if not ok then
			Owners.dispose(rowOwner)
			error(node, 0)
		end
		rows[slot] = { node = node, owner = rowOwner }
		return node
	end

	return keyed<<V, number>> { from = slice, key = slotOfRetained, render = renderSlot }
end

local function retain<V, S, K>(options: Options<V, S, K>): Children.Directive
	local recycle = options.recycle
	local render = options.render
	return function(mountPoint: Children.MountPoint)
		Support.mountPointOf(mountPoint, options.primitive)
		local inner: Children.Directive
		if recycle then
			inner = retainSlots(options, recycle, Support.ownerFor(options.primitive))
		else
			assert(render ~= nil, "retain needs render or recycle")
			inner = retainKeyed(options, render)
		end
		inner(mountPoint)
	end
end

return retain
