--!strict

local Children = require "../runtime/children"
local Host = require "../host"
local Support = require "../structure/support"
local Types = require "../reactive/types"
local cellModule = require "../reactive/cell"
local keyed = require "../structure/keyed"

export type Render<V, S, K> = (value: Types.Readable<V>, state: Types.Readable<S>, key: K) -> Host.Node
export type Recycle<V, S, K> = (
	value: Types.Readable<V>,
	state: Types.Readable<S>,
	key: Types.Readable<K>
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

	local states: { [K]: Types.Cell<S> } = {}
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

	local function renderRetained(value: Types.Readable<V>, _index: Types.Readable<number>, key: K): Host.Node
		local state = states[key]
		if state == nil then
			state = cellModule.cell(pending[key], equals)
			states[key] = state
			pending[key] = nil
		end
		return render(value, state :: Types.Cell<S>, key)
	end

	return keyed { from = slice, key = keyOfRetained, render = renderRetained }
end

local function retainSlots<V, S, K>(options: Options<V, S, K>, recycle: Recycle<V, S, K>): Children.Directive
	local source = options.source
	local selectItems = options.select
	local equals = options.equals

	local slotOf: { [K]: number } = {}
	local keyAt: { [number]: K } = {}
	local states: { [number]: Types.Cell<S> } = {}
	local keyCells: { [number]: Types.Cell<K> } = {}
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
				table.insert(free, slot)
			end
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
			end
			slotsAt[index] = slot
			local held = states[slot]
			if held ~= nil then
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

		for index = reused + 1, #free do
			local slot = free[index]
			states[slot] = nil
			keyCells[slot] = nil
		end

		return values
	end

	local function slotOfRetained(_value: V, index: number): number
		return slotsAt[index]
	end

	local function renderSlot(value: Types.Readable<V>, _index: Types.Readable<number>, slot: number): Host.Node
		local state = states[slot]
		local keyCell = keyCells[slot]
		if state == nil or keyCell == nil then
			state = cellModule.cell(pendingStates[slot], equals)
			keyCell = cellModule.cell(pendingKeys[slot] :: K)
			states[slot] = state
			keyCells[slot] = keyCell
			pendingStates[slot] = nil
			pendingKeys[slot] = nil
		end
		return recycle(value, state :: Types.Cell<S>, keyCell :: Types.Cell<K>)
	end

	return keyed { from = slice, key = slotOfRetained, render = renderSlot }
end

local function retain<V, S, K>(options: Options<V, S, K>): Children.Directive
	local recycle = options.recycle
	local render = options.render
	local inner: Children.Directive
	if recycle then
		inner = retainSlots(options, recycle)
	else
		assert(render ~= nil, "retain needs render or recycle")
		inner = retainKeyed(options, render)
	end
	return function(mountPoint: Children.MountPoint)
		Support.mountPointOf(mountPoint, options.primitive)
		inner(mountPoint)
	end
end

return retain
