--!strict

local Children = require "../runtime/children"
local Host = require "../host"
local Support = require "../structure/support"
local Types = require "../reactive/types"
local cellModule = require "../reactive/cell"
local keyed = require "../structure/keyed"

export type Render<V, S, K> = (value: Types.Readable<V>, state: Types.Readable<S>, key: K) -> Host.Node

export type Selection<V, S, K> = {
	values: { V },
	keys: { K },
	states: { S },
}

export type Options<V, S, K> = {
	primitive: string,
	source: Types.Body<{ V }>,
	select: (use: Types.Use, list: { V }) -> Selection<V, S, K>,
	render: Render<V, S, K>,
	equals: ((a: S, b: S) -> boolean)?,
}

local function retain<V, S, K>(options: Options<V, S, K>): Children.Directive
	local source = options.source
	local selectItems = options.select
	local render = options.render
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

	local inner = keyed { from = slice, key = keyOfRetained, render = renderRetained }
	return function(mountPoint: Children.MountPoint)
		Support.mountPointOf(mountPoint, options.primitive)
		inner(mountPoint)
	end
end

return retain
