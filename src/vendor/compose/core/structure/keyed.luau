--!strict
--!native

local StructureTypes = require "./types"
local Owners = require "../ownership/owner"
local Block = require "../runtime/block"
local Children = require "../runtime/children"
local Diagnostics = require "../diagnostics"
local Host = require "../host"
local Support = require "./support"
local Types = require "../reactive/types"
local longestIncreasingSubsequence = require "./lis"
local cellModule = require "../reactive/cell"

export type Render<V, K> = StructureTypes.KeyedRender<V, K>

type Entry<V, K> = {
	owner: Owners.Owner,
	nodes: { Host.Node },
	value: Types.Value<V>,
	index: Types.Value<number>,
	key: K,
	item: V,
	position: number,
	mark: number,
}

local identity = require("../reactive/node").identityKey

export type Source<V> = StructureTypes.KeyedSource<V>

export type Options<V, K> = StructureTypes.KeyedOptions<V, K>

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
		local entries: { [K]: Entry<V, K> } = {}
		local order: { Entry<V, K> } = {}
		local missing = ({} :: unknown) :: Entry<V, K>
		local matched: { Entry<V, K> } = {}

		local uniform = true
		local keys: { K } = {}
		local retainedPositions: { number } = {}
		local retainedTargets: { number } = {}
		local currentList: { V } = {}
		local base, count, epoch = 0, 0, 0

		Owners.own(owner, function()
			for _, entry in entries do
				Block.releaseNodes(mountPoint, entry.nodes)
			end
			table.clear(entries)
			table.clear(order)
			table.clear(matched)
			table.clear(keys)
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
				order[index].position = index
			end
			base = 0
		end

		local function startOf(liveIndex: number): number
			if uniform then
				return liveIndex
			end
			local position = 1
			for index = 1, liveIndex - 1 do
				position += #order[base + index].nodes
			end
			return position
		end

		local function reindex(from: number, to: number)
			for index = from, to do
				order[index].position = index
			end
		end

		local function setIndex(entry: Entry<V, K>, index: number)
			local cell = entry.index
			if ((cell :: unknown) :: Types.Node).value ~= index then
				cell:set(index)
			end
		end

		local function earlierIndexOf(itemKey: K, from: number, before: number): number
			for index = from, before - 1 do
				if rawequal(keys[index], itemKey) then
					return index
				end
			end
			return before
		end

		local function mountRow(index: number, itemKey: K, at: number): Entry<V, K>
			local item = currentList[index]
			local value = cellModule.cell(item)
			local position = if readsIndex then cellModule.cell(index) else UNREAD_INDEX
			local nodes, rowOwner = Block.mountRow(mountPoint, owner, render, value, position, itemKey, "keyed row", at)
			if #nodes ~= 1 then
				uniform = false
			end
			local entry: Entry<V, K> = {
				owner = rowOwner,
				nodes = nodes,
				value = value,
				index = position,
				key = itemKey,
				item = item,
				position = 0,
				mark = 0,
			}
			entries[itemKey] = entry
			return entry
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

		local function release(entry: Entry<V, K>)
			Block.releaseNodes(mountPoint, entry.nodes)
			Owners.dispose(entry.owner)
			entries[entry.key] = nil
			entry.position = 0
		end

		local function trimHead(list: { V }, wanted: number): boolean
			if count == 0 or wanted == 0 then
				return false
			end
			local head = entries[keys[1]]
			if head == nil then
				return false
			end
			local first = head.position
			local drop = first - base - 1
			local kept = count - drop
			if drop <= 0 or kept > wanted or wanted - kept > TRIM_TAIL then
				return false
			end
			for index = 2, kept do
				if order[first + index - 1].key ~= keys[index] then
					return false
				end
			end
			for index = kept + 1, wanted do
				local itemKey = keys[index]
				if entries[itemKey] ~= nil then
					return false
				end
				for earlier = kept + 1, index - 1 do
					if keys[earlier] == itemKey then
						return false
					end
				end
			end
			for at = base + 1, base + drop do
				release(order[at])
				order[at] = nil
			end
			base += drop
			count = kept
			for index = 1, kept do
				local entry = order[base + index]
				local item = list[index]
				if entry.item ~= item then
					entry.item = item
					entry.value:set(item)
				end
				if readsIndex then
					setIndex(entry, index)
				end
			end
			local failures: { string }? = nil
			for index = kept + 1, wanted do
				local itemKey = keys[index]
				local ok, made =
					pcall(mountRow, index, itemKey, if ordersChildren then startOf(count + 1) else count + 1)
				if ok then
					count += 1
					local at = base + count
					order[at] = made
					made.position = at
				else
					local collected: { string } = failures or {}
					failures = collected
					table.insert(collected, tostring(made))
				end
			end
			if base > count then
				normalize()
			end
			raiseFailures(failures)
			return true
		end

		local depth, passes = 0, 0
		local function reconcile(use: Types.Use)
			passes += 1
			local pass = passes
			local list = source(use)
			currentList = list
			local wanted = #list

			if keyOf == nil then
				table.move((list :: unknown) :: { K }, 1, wanted, 1, keys)
			else
				for index = 1, wanted do
					keys[index] = key(list[index], index)
				end
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
			while prefix < shared and rawequal(order[prefix + 1].key, keys[prefix + 1]) do
				prefix += 1
			end
			local oldEnd, newEnd = previousCount, wanted
			while oldEnd > prefix and newEnd > prefix and rawequal(order[oldEnd].key, keys[newEnd]) do
				oldEnd -= 1
				newEnd -= 1
			end
			local shift = newEnd - oldEnd

			epoch += 1
			local mark = epoch
			table.clear(matched)
			local laterIndex, laterEarlier = math.huge, 0
			local found = 0
			local fresh: { [K]: number }? = nil
			for index = prefix + 1, newEnd do
				local itemKey = keys[index]
				local entry = entries[itemKey]
				if entry ~= nil then
					if entry.mark == mark then
						duplicate(index, earlierIndexOf(itemKey, prefix + 1, index))
					end
					local at = entry.position
					if at <= prefix then
						duplicate(index, at)
					elseif at > oldEnd and at + shift < laterIndex then
						laterIndex, laterEarlier = at + shift, index
					end
					entry.mark = mark
					matched[index] = entry
					found += 1
				else
					local added = fresh or {}
					fresh = added
					local earlier = added[itemKey]
					if earlier ~= nil then
						duplicate(index, earlier)
					end
					added[itemKey] = index
					matched[index] = missing
				end
			end
			if laterEarlier ~= 0 then
				duplicate(laterIndex, laterEarlier)
			end

			for index = 1, prefix do
				local entry = order[index]
				local item = list[index]
				if entry.item ~= item then
					entry.item = item
					entry.value:set(item)
				end
			end
			for index = newEnd + 1, wanted do
				local entry = order[index - shift]
				matched[index] = entry
				local item = list[index]
				if entry.item ~= item then
					entry.item = item
					entry.value:set(item)
				end
				if readsIndex and shift ~= 0 then
					setIndex(entry, index)
				end
			end
			if prefix == wanted and previousCount == wanted then
				return
			end

			local removedAny = false
			if found < oldEnd - prefix then
				for index = prefix + 1, oldEnd do
					local existing = order[index]
					if existing.mark ~= mark then
						release(existing)
						removedAny = true
					end
				end
			end
			if fresh == nil and not ordersChildren then
				for index = prefix + 1, newEnd do
					local entry = matched[index]
					local item = list[index]
					if entry.item ~= item then
						entry.item = item
						entry.value:set(item)
					end
					if readsIndex then
						setIndex(entry, index)
					end
					order[index] = entry
					entry.position = index
				end
				if shift ~= 0 then
					for index = newEnd + 1, wanted do
						local entry = matched[index]
						order[index] = entry
						entry.position = index
					end
				end
				for index = #order, wanted + 1, -1 do
					order[index] = nil
				end
				count = wanted
				return
			end
			if removedAny then
				local live = prefix
				local was = #order
				for index = prefix + 1, was do
					local existing = order[index]
					if existing.position ~= 0 then
						live += 1
						order[live] = existing
						existing.position = live
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
				local entry = matched[index]
				if entry ~= missing then
					local item = list[index]
					if entry.item ~= item then
						entry.item = item
						entry.value:set(item)
					end
					if readsIndex then
						setIndex(entry, index)
					end
					local at = entry.position
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
					local entry = matched[index]
					if entry == missing then
						local ok, made = pcall(mountRow, index, keys[index], live + 1)
						if passes ~= pass then
							return
						end
						if not ok then
							local collected: { string } = failures or {}
							failures = collected
							table.insert(collected, tostring(made))
							continue
						end
						entry = made
					end
					live += 1
					order[live] = entry
					entry.position = live
				end
				for index = #order, live + 1, -1 do
					order[index] = nil
				end
			elseif stays == nil then
				local live = prefix
				for index = prefix + 1, newEnd do
					local entry = matched[index]
					live += 1

					if entry == missing then
						local ok, made = pcall(mountRow, index, keys[index], startOf(live))
						if passes ~= pass then
							return
						end
						if not ok then
							local collected: { string } = failures or {}
							failures = collected
							table.insert(collected, tostring(made))
							live -= 1
							continue
						end
						table.insert(order, live, made)
						reindex(live, #order)
					elseif retained < middle and order[live] ~= entry then
						local from = entry.position
						table.remove(order, from)
						table.insert(order, live, entry)
						reindex(math.min(from, live), math.max(from, live))
					else
						order[live] = entry
						entry.position = live
					end
				end
				for index = #order, live + wanted - newEnd + 1, -1 do
					order[index] = nil
				end
			else
				local following = matched[newEnd + 1]
				local anchor: Entry<V, K>? = if newEnd < wanted then following else nil
				local staying = 1
				for index = newEnd, prefix + 1, -1 do
					local entry = matched[index]

					local anchorLive = if anchor ~= nil then anchor.position else #order + 1

					if entry == missing then
						local ok, made = pcall(mountRow, index, keys[index], startOf(anchorLive))
						if passes ~= pass then
							return
						end
						if not ok then
							local collected: { string } = failures or {}
							failures = collected
							table.insert(collected, tostring(made))
							continue
						end
						table.insert(order, anchorLive, made)
						reindex(anchorLive, #order)
						entry = made
					elseif index ~= retainedTargets[stays[staying]] then
						local from = entry.position
						table.remove(order, from)
						local destination = if from < anchorLive then anchorLive - 1 else anchorLive
						table.insert(order, destination, entry)
						reindex(math.min(from, destination), math.max(from, destination))
						local at = startOf(destination)
						for offset, node in entry.nodes do
							mountPoint.moveTo(node, at + offset - 1)
						end
					else
						staying += 1
					end
					anchor = entry
				end
			end
			count = #order
			raiseFailures(failures)
		end
		Owners.watch(owner, function(use)
			depth += 1
			if depth == 1 then
				local ok, failure = pcall(function(): unknown
					reconcile(use)
					return nil
				end)
				depth -= 1
				if not ok then
					error(failure, 0)
				end
				return
			end
			local outerKeys, outerMatched = keys, matched
			keys, matched = {}, {}
			local ok, failure = pcall(function(): unknown
				reconcile(use)
				return nil
			end)
			keys, matched = outerKeys, outerMatched
			depth -= 1
			if not ok then
				error(failure, 0)
			end
		end)
	end
end

return keyed
