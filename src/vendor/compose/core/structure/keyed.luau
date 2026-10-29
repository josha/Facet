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
local TRIM_TAIL = 8

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
		local itemOf: { [K]: V } = {}

		local uniform = true
		local keys: { K } = {}
		local seen: { [K]: number } = {}
		local retainedPositions: { number } = {}
		local retainedTargets: { number } = {}
		local currentList: { V } = {}
		local base, count = 0, 0

		Owners.own(owner, function()
			for _, entry in entries do
				Block.releaseNodes(mountPoint, entry.nodes)
			end
			table.clear(entries)
			table.clear(order)
			table.clear(positionOf)
			table.clear(itemOf)
			table.clear(keys)
			table.clear(seen)
			table.clear(retainedPositions)
			table.clear(retainedTargets)
			currentList = {}
			base, count = 0, 0
		end)

		local function normalize()
			if base == 0 then
				return
			end
			table.move(order, base + 1, base + count, 1)
			for index = count + 1, base + count do
				order[index] = nil
			end
			for index = 1, count do
				positionOf[order[index]] = index
			end
			base = 0
		end

		local function startOf(liveIndex: number): number
			if uniform then
				return liveIndex
			end
			local position = 1
			for index = 1, liveIndex - 1 do
				position += #entries[order[base + index]].nodes
			end
			return position
		end

		local function reindex(from: number, to: number)
			for index = from, to do
				positionOf[order[index]] = index
			end
		end

		local function mountRow(index: number, itemKey: K, at: number): number
			local item = currentList[index]
			local value = cellModule.cell(item)
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
			itemOf[itemKey] = item
			return size
		end

		local function duplicate(index: number, earlier: number): never
			return Diagnostics.raise("structure/duplicate-key", "two items in a keyed collection share a key", {
				index = index,
				detail = ("the same key is also used at index %d"):format(earlier),
				contract = "keys identify rows across updates, so they must be unique within one update",
				fix = "pass a keyOf that returns a stable unique id, e.g. function(item) return item.id end",
			})
		end

		local function raiseFailures(failures: { string }?)
			if failures ~= nil then
				if #failures == 1 then
					error(failures[1], 0)
				end
				error(
					("Compose: %d keyed row factories failed:\n  %s"):format(#failures, table.concat(failures, "\n  ")),
					0
				)
			end
		end

		local function trimHead(list: { V }, wanted: number): boolean
			if count == 0 or wanted == 0 then
				return false
			end
			local first = positionOf[keys[1]]
			if first == nil then
				return false
			end
			local drop = first - base - 1
			local kept = count - drop
			if drop <= 0 or kept > wanted or wanted - kept > TRIM_TAIL then
				return false
			end
			for index = 2, kept do
				if order[first + index - 1] ~= keys[index] then
					return false
				end
			end
			for index = kept + 1, wanted do
				local itemKey = keys[index]
				if positionOf[itemKey] ~= nil then
					return false
				end
				for earlier = kept + 1, index - 1 do
					if keys[earlier] == itemKey then
						return false
					end
				end
			end
			for at = base + 1, base + drop do
				local leaving = order[at]
				local entry = entries[leaving]
				Block.releaseNodes(mountPoint, entry.nodes)
				Owners.dispose(entry.owner)
				entries[leaving] = nil
				positionOf[leaving] = nil
				itemOf[leaving] = nil
				order[at] = nil
			end
			base += drop
			count = kept
			for index = 1, kept do
				local itemKey = keys[index]
				local item = list[index]
				local entry = entries[itemKey]
				if itemOf[itemKey] ~= item then
					itemOf[itemKey] = item
					entry.value:set(item)
				end
				if readsIndex then
					entry.index:set(index)
				end
			end
			local failures: { string }? = nil
			for index = kept + 1, wanted do
				local itemKey = keys[index]
				local ok, err =
					pcall(mountRow, index, itemKey, if ordersChildren then startOf(count + 1) else count + 1)
				if ok then
					count += 1
					order[base + count] = itemKey
					positionOf[itemKey] = base + count
				else
					local collected: { string } = failures or {}
					failures = collected
					table.insert(collected, tostring(err))
				end
			end
			if base > count then
				normalize()
			end
			raiseFailures(failures)
			return true
		end

		Owners.watch(owner, function(use)
			local list = source(use)
			currentList = list
			local wanted = #list

			for index = 1, wanted do
				keys[index] = key(list[index], index)
			end
			for index = #keys, wanted + 1, -1 do
				keys[index] = nil
			end
			if trimHead(list, wanted) then
				return
			end
			normalize()

			local prefix = 0
			local previousCount = #order
			local shared = math.min(previousCount, wanted)
			while prefix < shared and positionOf[keys[prefix + 1]] == prefix + 1 do
				prefix += 1
			end
			local oldEnd, newEnd = previousCount, wanted
			while oldEnd > prefix and newEnd > prefix and positionOf[keys[newEnd]] == oldEnd do
				oldEnd -= 1
				newEnd -= 1
			end
			local shift = newEnd - oldEnd

			table.clear(seen)
			local laterIndex, laterEarlier = math.huge, 0
			for index = prefix + 1, newEnd do
				local itemKey = keys[index]
				local earlier = seen[itemKey]
				if earlier ~= nil then
					duplicate(index, earlier)
				end
				local at = positionOf[itemKey]
				if at ~= nil then
					if at <= prefix then
						duplicate(index, at)
					elseif at > oldEnd and at + shift < laterIndex then
						laterIndex, laterEarlier = at + shift, index
					end
				end
				seen[itemKey] = index
			end
			if laterEarlier ~= 0 then
				duplicate(laterIndex, laterEarlier)
			end

			for index = 1, prefix do
				local itemKey = keys[index]
				local item = list[index]
				if itemOf[itemKey] ~= item then
					itemOf[itemKey] = item
					entries[itemKey].value:set(item)
				end
			end
			for index = newEnd + 1, wanted do
				local itemKey = keys[index]
				local item = list[index]
				if itemOf[itemKey] ~= item then
					itemOf[itemKey] = item
					entries[itemKey].value:set(item)
				end
				if readsIndex and shift ~= 0 then
					entries[itemKey].index:set(index)
				end
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
					itemOf[existing] = nil
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
					local item = list[index]
					if itemOf[itemKey] ~= item then
						itemOf[itemKey] = item
						entry.value:set(item)
					end
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

			local stays: { number }? = nil
			if ordersChildren and not ordered then
				stays = longestIncreasingSubsequence(retainedPositions, retained)
			end

			local failures: { string }? = nil
			if not ordersChildren then
				local live = prefix
				for index = prefix + 1, wanted do
					local itemKey = keys[index]
					if entries[itemKey] == nil then
						local ok, err = pcall(mountRow, index, itemKey, live + 1)
						if not ok then
							local collected: { string } = failures or {}
							failures = collected
							table.insert(collected, tostring(err))
							continue
						end
					end
					live += 1
					order[live] = itemKey
					positionOf[itemKey] = live
				end
				for index = #order, live + 1, -1 do
					order[index] = nil
				end
			elseif stays == nil then
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
				local staying = 1
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
					elseif index ~= retainedTargets[stays[staying]] then
						local from = positionOf[itemKey]
						table.remove(order, from)
						local destination = if from < anchorLive then anchorLive - 1 else anchorLive
						table.insert(order, destination, itemKey)
						reindex(math.min(from, destination), math.max(from, destination))
						local at = startOf(destination)
						for offset, node in entry.nodes do
							mountPoint.moveTo(node, at + offset - 1)
						end
					else
						staying += 1
					end
					anchor = itemKey
				end
			end
			count = #order
			raiseFailures(failures)
		end)
	end
end

return keyed
