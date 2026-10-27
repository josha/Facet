--!strict
--!native

local Owners = require "../ownership/owner"
local Block = require "../runtime/block"
local Children = require "../runtime/children"
local Diagnostics = require "../diagnostics"
local Host = require "../host"
local Support = require "./support"
local Types = require "../reactive/types"
local longestIncreasingSubsequence = require "./lis"
local cellModule = require "../reactive/cell"

export type Render<V, K> = (value: Types.ReadOnlyValue<V>, index: Types.ReadOnlyValue<number>, key: K) -> Host.Node

type Entry<V> = {
	owner: Owners.Owner,
	nodes: { Host.Node },
	value: Types.Value<V>,
	index: Types.Value<number>,
}

local identity = require("../reactive/node").identityKey

export type Source<V> = Types.ReadOnlyValue<{ V }> | Types.Body<{ V }>

export type Options<V, K> = {
	from: Source<V>,
	key: ((value: V, index: number) -> K)?,
	render: Render<V, K>,
}

local UNREAD_INDEX = cellModule.cell(0)

local KNOWN_FIELDS: { [string]: true } = { from = true, key = true, render = true }

local function keyed<V, K>(options: Options<V, K>): Children.Directive
	local settings = Support.optionsOf(options, "keyed", "from = ..., key = ..., render = ...")
	Support.noUnknownFields(settings, "keyed", KNOWN_FIELDS)
	local source: Types.Body<{ V }> = Support.sourceOf(settings.from, "keyed", "from")
	local render: Render<V, K> = Support.builderOf(settings.render, "keyed", "render")
	local arity, variadic = debug.info(render, "a")
	local readsIndex = variadic or arity >= 2
	local keyOf = settings.key

	local key: (value: V, index: number) -> K
	if keyOf ~= nil then
		key = Support.builderOf(keyOf, "keyed", "key")
	else
		key = identity
	end

	return function(mountPoint: Children.MountPoint)
		local owner = Support.ownerFor "keyed"
		Support.mountPointOf(mountPoint, "keyed")
		local ordersChildren = mountPoint.ordersChildren
		local entries: { [K]: Entry<V> } = {}
		local order: { K } = {}
		local positionOf: { [K]: number } = {}

		local uniform = true
		local keys: { K } = {}
		local seen: { [K]: number } = {}
		local retainedPositions: { number } = {}
		local retainedTargets: { number } = {}
		local currentList: { V } = {}

		Owners.own(owner, function()
			for _, entry in entries do
				Block.releaseNodes(mountPoint, entry.nodes)
			end
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
				position += #entries[order[index]].nodes
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
			local position = if readsIndex then cellModule.cell(index) else UNREAD_INDEX
			local block = Block.mountBlock(mountPoint, owner, function(): { Host.Node }
				return { render(value, position, itemKey) }
			end, "keyed row", at, true)
			local nodes = block.nodes
			local size = #nodes
			if size ~= 1 then
				uniform = false
			end
			entries[itemKey] = { owner = block.owner, nodes = nodes, value = value, index = position }
			return size
		end

		Owners.watch(owner, function(use)
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
			for index = #keys, wanted + 1, -1 do
				keys[index] = nil
			end

			local prefix = 0
			local previousCount = #order
			while prefix < math.min(previousCount, wanted) and positionOf[keys[prefix + 1]] == prefix + 1 do
				prefix += 1
				local entry = entries[order[prefix]]
				entry.value:set(list[prefix])
				if readsIndex then
					entry.index:set(prefix)
				end
			end
			local oldEnd, newEnd = previousCount, wanted
			while oldEnd > prefix and newEnd > prefix and positionOf[keys[newEnd]] == oldEnd do
				local entry = entries[order[oldEnd]]
				entry.value:set(list[newEnd])
				if readsIndex then
					entry.index:set(newEnd)
				end
				oldEnd -= 1
				newEnd -= 1
			end
			if prefix == wanted and previousCount == wanted then
				return
			end

			local removedAny = false
			for index = oldEnd, prefix + 1, -1 do
				local existing = order[index]
				if seen[existing] == nil then
					local leaving = entries[existing]
					Block.releaseNodes(mountPoint, leaving.nodes)
					Owners.dispose(leaving.owner)
					entries[existing] = nil
					positionOf[existing] = nil
					removedAny = true
				end
			end
			if removedAny then
				local live = prefix
				local was = #order
				for index = prefix + 1, was do
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
			for index = prefix + 1, newEnd do
				local itemKey = keys[index]
				local entry = entries[itemKey]
				if entry ~= nil then
					entry.value:set(list[index])
					if readsIndex then
						entry.index:set(index)
					end
					local at = positionOf[itemKey]
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

			local middle = newEnd - prefix
			if ordered and retained == middle and not removedAny and previousCount == wanted then
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

			local failures: { string }? = nil
			if stays == nil then
				local live = prefix
				for index = prefix + 1, newEnd do
					local itemKey = keys[index]
					live += 1

					if entries[itemKey] == nil then
						local ok, err = pcall(mountRow, index, itemKey, startOf(live))
						if not ok then
							local collected: { string } = failures or {}
							failures = collected
							table.insert(collected, tostring(err))
							live -= 1
							continue
						end
						table.insert(order, live, itemKey)
						reindex(live, #order)
					elseif retained < middle and order[live] ~= itemKey then
						local from = positionOf[itemKey]
						table.remove(order, from)
						table.insert(order, live, itemKey)
						reindex(math.min(from, live), math.max(from, live))
					else
						order[live] = itemKey
						positionOf[itemKey] = live
					end
				end
				for index = #order, live + wanted - newEnd + 1, -1 do
					order[index] = nil
				end
			else
				local anchor: K? = keys[newEnd + 1]
				for index = newEnd, prefix + 1, -1 do
					local itemKey = keys[index]
					local entry = entries[itemKey]

					local anchorLive = if anchor ~= nil then positionOf[anchor] else #order + 1

					if entry == nil then
						local ok, err = pcall(mountRow, index, itemKey, startOf(anchorLive))
						if not ok then
							local collected: { string } = failures or {}
							failures = collected
							table.insert(collected, tostring(err))
							continue
						end
						table.insert(order, anchorLive, itemKey)
						reindex(anchorLive, #order)
					elseif not stays[itemKey] then
						local from = positionOf[itemKey]
						table.remove(order, from)
						local destination = if from < anchorLive then anchorLive - 1 else anchorLive
						table.insert(order, destination, itemKey)
						reindex(math.min(from, destination), math.max(from, destination))
						local at = startOf(destination)
						for offset, node in entry.nodes do
							mountPoint.moveTo(node, at + offset - 1)
						end
					end
					anchor = itemKey
				end
			end
			if failures ~= nil then
				if #failures == 1 then
					error(failures[1], 0)
				end
				error(
					("Compose: %d keyed row factories failed:\n  %s"):format(#failures, table.concat(failures, "\n  ")),
					0
				)
			end
		end)
	end
end

return keyed
