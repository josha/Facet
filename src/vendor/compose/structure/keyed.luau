--!strict
--!native

local Block = require "../runtime/block"
local Children = require "../runtime/children"
local Diagnostics = require "../diagnostics"
local Host = require "../host"
local Support = require "./support"
local Types = require "../reactive/types"
local longestIncreasingSubsequence = require "./lis"
local cellModule = require "../reactive/cell"

export type Render<V, K> = (value: Types.Readable<V>, index: Types.Readable<number>, key: K) -> Host.Node

type Entry<V, K> = {
	key: K,
	block: Block.Block,
	value: Types.Cell<V>,
	index: Types.Cell<number>,
	size: number,
}

local function identity<V>(value: V, _index: number): any
	return value
end

export type Source<V> = Types.Readable<{ V }> | Types.Body<{ V }>

export type Options<V, K> = {
	from: Source<V>,
	key: ((value: V, index: number) -> K)?,
	render: Render<V, K>,
}

local KNOWN_FIELDS: { [string]: true } = { from = true, key = true, render = true }

local function keyed<V, K>(options: Options<V, K>): Children.Directive
	local settings = Support.optionsOf(options, "keyed", "from = ..., key = ..., render = ...")
	Support.noUnknownFields(settings, "keyed", KNOWN_FIELDS)
	local source = Support.sourceOf(settings.from, "keyed", "from") :: Types.Body<{ V }>
	local render = Support.builderOf(settings.render, "keyed", "render") :: Render<V, K>
	local keyOf = settings.key
	if keyOf ~= nil and type(keyOf) ~= "function" then
		keyOf = Support.builderOf(keyOf, "keyed", "key")
	end

	local key: (value: V, index: number) -> K
	if keyOf ~= nil then
		key = keyOf
	else
		key = (identity :: any) :: (value: V, index: number) -> K
	end

	return function(mountPoint: Children.MountPoint)
		local owner = Support.ownerFor "keyed"
		Support.mountPointOf(mountPoint, "keyed")
		local ordersChildren = mountPoint.ordersChildren
		local entries: { [K]: Entry<V, K> } = {}
		local order: { K } = {}
		local positionOf: { [K]: number } = {}

		local uniform = true
		local keys: { K } = {}
		local seen: { [K]: number } = {}
		local retainedPositions: { number } = {}
		local retainedTargets: { number } = {}
		local currentList: { V } = {}

		owner.own(function()
			table.clear(entries)
			table.clear(order)
			table.clear(positionOf)
			table.clear(keys)
			table.clear(seen)
			table.clear(retainedPositions)
			table.clear(retainedTargets)
			currentList = {}
		end)

		local function startOf(liveIndex: number): number
			if uniform then
				return liveIndex
			end
			local position = 1
			for index = 1, liveIndex - 1 do
				position += entries[order[index]].size
			end
			return position
		end

		local function reindex(from: number, to: number)
			for index = from, to do
				positionOf[order[index]] = index
			end
		end

		local function mountRow(index: number, itemKey: K, at: number): number
			local value = cellModule.cell(currentList[index])
			local position = cellModule.cell(index)
			local block = Block.mountBlock(mountPoint, owner, function(): { Host.Node }
				return { render(value, position, itemKey) }
			end, "keyed row", at)
			local size = #block.nodes
			if size ~= 1 then
				uniform = false
			end
			entries[itemKey] = {
				key = itemKey,
				block = block,
				value = value,
				index = position,
				size = size,
			}
			return size
		end

		owner.watch(function(use)
			local list = source(use)
			currentList = list
			local wanted = #list

			table.clear(seen)
			for index = 1, wanted do
				local itemKey = key(list[index], index)
				if seen[itemKey] ~= nil then
					Diagnostics.raise("structure/duplicate-key", "two items in a keyed collection share a key", {
						index = index,
						detail = ("the same key is also used at index %d"):format(seen[itemKey]),
						contract = "keys identify rows across updates, so they must be unique within one update",
						fix = "pass a keyOf that returns a stable unique id, e.g. function(item) return item.id end",
					})
				end
				seen[itemKey] = index
				keys[index] = itemKey
			end

			local removedAny = false
			for index = #order, 1, -1 do
				local existing = order[index]
				if seen[existing] == nil then
					entries[existing].block.dispose()
					entries[existing] = nil
					positionOf[existing] = nil
					removedAny = true
				end
			end
			if removedAny then
				local live = 0
				local was = #order
				for index = 1, was do
					local existing = order[index]
					if entries[existing] ~= nil then
						live += 1
						order[live] = existing
						positionOf[existing] = live
					end
				end
				for index = was, live + 1, -1 do
					order[index] = nil
				end
			end

			local retained = 0
			local previousPosition = 0
			local ordered = true
			for index = 1, wanted do
				local entry = entries[keys[index]]
				if entry ~= nil then
					entry.value:set(list[index])
					entry.index:set(index)
					local at = positionOf[entry.key]
					retained += 1
					if at < previousPosition then
						ordered = false
					end
					previousPosition = at
					if ordersChildren then
						retainedPositions[retained] = at
						retainedTargets[retained] = index
					end
				end
			end

			if ordered and retained == wanted and not removedAny and order[wanted + 1] == nil then
				return
			end

			local stays: { [K]: true }? = nil
			if ordersChildren and not ordered then
				local staying = longestIncreasingSubsequence(retainedPositions, retained)
				local held: { [K]: true } = {}
				for offset = 1, retained do
					if staying[offset] then
						held[keys[retainedTargets[offset]]] = true
					end
				end
				stays = held
			end

			if stays == nil then
				local live = 0
				for index = 1, wanted do
					local itemKey = keys[index]
					live += 1

					if entries[itemKey] == nil then
						mountRow(index, itemKey, startOf(live))
					end
					order[live] = itemKey
					positionOf[itemKey] = live
				end
				for index = #order, live + 1, -1 do
					order[index] = nil
				end
			else
				for index = wanted, 1, -1 do
					local itemKey = keys[index]
					local entry = entries[itemKey]

					local anchorLive = if index < wanted then positionOf[keys[index + 1]] else #order + 1

					if entry == nil then
						mountRow(index, itemKey, startOf(anchorLive))
						table.insert(order, anchorLive, itemKey)
						reindex(anchorLive, #order)
					elseif not stays[itemKey] then
						local from = positionOf[itemKey]
						table.remove(order, from)
						local destination = if from < anchorLive then anchorLive - 1 else anchorLive
						table.insert(order, destination, itemKey)
						reindex(math.min(from, destination), math.max(from, destination))
						local at = startOf(destination)
						for offset, node in entry.block.nodes do
							mountPoint.moveTo(node, at + offset - 1)
						end
					end
				end
			end
		end)
	end
end

return keyed
