--!strict

local StructureTypes = require "../types"
local Children = require "../runtime/children"
local Support = require "./support"
local cellModule = require "../reactive/cell"
local keyedRows = require "./keyed-rows"

export type Render<V, K> = StructureTypes.KeyedRender<V, K>

export type Source<V> = StructureTypes.KeyedSource<V>

export type Options<V, K = V> = StructureTypes.KeyedOptions<V, K>

local UNREAD_INDEX = cellModule.cell(0)
local KNOWN_FIELDS: { [string]: true } = { from = true, key = true, render = true }

local function indicesTo(wanted: number, indices: { number }): { number }
	for index = #indices + 1, wanted do
		indices[index] = index
	end
	return indices
end

local function keyed<V, K>(options: Options<V, K>): Children.Directive
	local settings = Support.optionsOf(options, "keyed", "from = ..., key = ..., render = ...")
	Support.noUnknownFields(settings, "keyed", KNOWN_FIELDS)
	local render = Support.builderOf(settings.render, "keyed", "render")
	local arity, variadic = debug.info(render, "a")
	local readsIndex = variadic or arity >= 2
	local shared = if readsIndex then nil else UNREAD_INDEX
	if settings.key == nil then
		return keyedRows(settings.from, render, function(list: { V }, wanted: number, keys: { V }, indices: { number })
			table.move(list, 1, wanted, 1, keys)
			return if readsIndex then indicesTo(wanted, indices) else indices
		end, shared, nil)
	end
	local key = Support.builderOf(settings.key, "keyed", "key")
	return keyedRows(settings.from, render, function(list: { V }, wanted: number, keys: { K }, indices: { number })
		for index = 1, wanted do
			keys[index] = key(list[index], index)
		end
		return if readsIndex then indicesTo(wanted, indices) else indices
	end, shared, nil)
end

return keyed
