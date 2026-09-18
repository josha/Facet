--!strict

local Children = require "../runtime/children"
local Diagnostics = require "../diagnostics"
local Host = require "../host"
local Support = require "./support"
local Types = require "../reactive/types"
local keyed = require "./keyed"
local retain = require "../collection/retain"

export type Retention = "all" | "top"

export type State = {
	index: number,
	depthFromTop: number,
	top: boolean,
	covered: boolean,
}

export type Options<V, K> = {
	from: keyed.Source<V>,
	key: ((value: V, index: number) -> K)?,
	render: (value: Types.Readable<V>, state: Types.Readable<State>, key: K) -> Host.Node,
	retention: Retention?,
}

local KNOWN_FIELDS: { [string]: true } = {
	from = true,
	key = true,
	render = true,
	retention = true,
}

local function identity<V>(value: V, _index: number): any
	return value
end

local function sameState(a: State, b: State): boolean
	return a.index == b.index and a.depthFromTop == b.depthFromTop and a.top == b.top and a.covered == b.covered
end

local function layerStack<V, K>(options: Options<V, K>): Children.Directive
	local settings = Support.optionsOf(options, "LayerStack", "from = ..., key = ..., render = ...")
	Support.noUnknownFields(settings, "LayerStack", KNOWN_FIELDS)
	local source = Support.sourceOf(settings.from, "LayerStack", "from") :: Types.Body<{ V }>
	local render =
		Support.builderOf(settings.render, "LayerStack", "render") :: (Types.Readable<V>, Types.Readable<State>, K) -> Host.Node
	local keyOf: (value: V, index: number) -> K = if settings.key == nil
		then (identity :: any) :: (value: V, index: number) -> K
		else Support.builderOf(settings.key, "LayerStack", "key")
	local retention: Retention = settings.retention or "all"
	if retention ~= "all" and retention ~= "top" then
		Diagnostics.raise("layer-stack/unknown-retention", "LayerStack was given a retention policy it does not have", {
			actual = Diagnostics.describe(retention),
			expected = '"all" or "top"',
		})
	end

	local function select(_use: Types.Use, list: { V }): retain.Selection<V, State, K>
		local total = #list
		local first = if retention == "top" then math.max(1, total) else 1
		local values: { V } = {}
		local keys: { K } = {}
		local states: { State } = {}
		for index = first, total do
			local at = #values + 1
			values[at] = list[index]
			keys[at] = keyOf(list[index], index)
			states[at] = {
				index = index,
				depthFromTop = total - index,
				top = index == total,
				covered = index < total,
			}
		end
		return { values = values, keys = keys, states = states }
	end

	return retain {
		primitive = "LayerStack",
		source = source,
		select = select,
		render = render,
		equals = sameState,
	}
end

return layerStack
