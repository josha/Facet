--!strict
--!native

local StructureTypes = require "../types"
local Owners = require "../ownership/owner"
local Block = require("../runtime/children").block
local Children = require "../runtime/children"
local Diagnostics = require "../diagnostics"
local Host = require "../host"
local Support = require "./support"
local Types = require "../reactive/types"
local longestIncreasingSubsequence = require "./lis"
local cellModule = require "../reactive/cell"

export type Render<V, K, S> = (value: Types.ReadOnlyValue<V>, second: Types.ReadOnlyValue<S>, key: K) -> Host.Node

export type Collect<V, K, S> = (list: { V }, wanted: number, keys: { K }, seconds: { S }) -> { S }

type Entry<V, K, S> = {
	owner: Owners.Owner,
	node: Host.Node,
	value: Types.Value<V>,
	second: Types.Value<S>,
	key: K,
	item: V,
	position: number,
	mark: number,
}

export type Source<V> = StructureTypes.KeyedSource<V>

local function keyedRows<V, K, S>(
	from: Source<V>,
	render: Render<V, K, S>,
	collect: Collect<V, K, S>,
	shared: Types.Value<S>?,
	equals: Types.Equals<S>?
): Children.Directive
	local source: Types.Body<{ V }> = Support.sourceOf(from, "keyed", "from")
	local tracks = shared == nil

	return function(mountPoint: Children.MountPoint)
		local owner = Support.ownerFor "keyed"
		Support.mountPointOf(mountPoint, "keyed")
		local ordersChildren = mountPoint.ordersChildren
		local entries: { [K]: Entry<V, K, S> } = {}
		local order: { Entry<V, K, S> } = {}
		local matched: { [number]: Entry<V, K, S>? } = {}

		local keys: { K } = {}
		local scratch: { S } = {}
		local seconds: { S } = scratch
		local stale: { number } = {}
		local retainedPositions: { number } = {}
		local retainedTargets: { number } = {}
		local base, count, epoch = 0, 0, 0

		Owners.own(owner, function()
			for _, entry in entries do
				Block.releaseNode(mountPoint, entry.node)
			end
			table.clear(entries)
			table.clear(order)
			table.clear(matched)
			table.clear(keys)
			table.clear(scratch)
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

		local function reindex(from: number, to: number)
			for index = from, to do
				order[index].position = index
			end
		end

		local function setSecond(entry: Entry<V, K, S>, index: number)
			local cell = entry.second
			local cached = cell.cache
			local wanted = seconds[index]
			if cached == nil or (cached.value ~= wanted and not (equals ~= nil and equals(cached.value, wanted))) then
				cell:set(wanted)
			end
		end

		local function mountRow(index: number, itemKey: K, at: number, item: V): Entry<V, K, S>
			local value = cellModule.cell(item)
			local position = if shared ~= nil then shared else cellModule.cell(seconds[index])
			local node, rowOwner = Block.mountRow(mountPoint, owner, render, value, position, itemKey, "keyed row", at)
			local entry: Entry<V, K, S> = {
				owner = rowOwner,
				node = node,
				value = value,
				second = position,
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

		local function release(entry: Entry<V, K, S>)
			Block.releaseNode(mountPoint, entry.node)
			Owners.dispose(entry.owner)
			entries[entry.key] = nil
			entry.position = 0
		end

		local function trimHead(list: { V }, wanted: number, found: number): boolean
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
			if drop <= 0 or kept > wanted or found ~= kept then
				return false
			end
			for index = 2, kept do
				if order[first + index - 1].key ~= keys[index] then
					return false
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
				if tracks then
					setSecond(entry, index)
				end
			end
			local failures: { string }? = nil
			for index = kept + 1, wanted do
				local itemKey = keys[index]
				local ok, made = pcall(mountRow, index, itemKey, count + 1, list[index])
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
			local wanted = #list
			seconds = collect(list, wanted, keys, scratch)
			for index = #keys, wanted + 1, -1 do
				keys[index] = nil
			end
			for index = #scratch, wanted + 1, -1 do
				scratch[index] = nil
			end

			local mark = epoch + 1
			epoch = mark + wanted
			table.clear(matched)
			local changed = 0
			local previousCount = count
			local rows, wantedKeys, wantedSeconds, offset = order, keys, seconds, base
			local prefix, staleCount = 0, 0
			local shared = math.min(previousCount, wanted)
			while prefix < shared do
				local entry = rows[offset + prefix + 1]
				if not rawequal(entry.key, wantedKeys[prefix + 1]) then
					break
				end
				prefix += 1
				entry.mark = mark + prefix
				local cached = if tracks then entry.second.cache else nil
				if
					entry.item ~= list[prefix]
					or (tracks and (cached == nil or cached.value ~= wantedSeconds[prefix]))
				then
					staleCount += 1
					stale[staleCount] = prefix
				end
			end
			local found = prefix
			local fresh: { [K]: number }? = nil
			local byKey, picked = entries, matched
			for index = prefix + 1, wanted do
				local item = list[index]
				local itemKey = wantedKeys[index]
				local entry = byKey[itemKey]
				if entry ~= nil then
					local at = entry.position - offset
					if entry.mark >= mark then
						duplicate(index, entry.mark - mark)
					end
					entry.mark = mark + index
					found += 1
					if ordersChildren then
						picked[index] = entry
					elseif
						at ~= index
						or entry.item ~= item
						or (tracks and (entry.second.cache == nil or entry.second.cache.value ~= wantedSeconds[index]))
					then
						changed += 1
						picked[changed] = entry
					end
				else
					local added = fresh or {}
					fresh = added
					local earlier = added[itemKey]
					if earlier ~= nil then
						duplicate(index, earlier)
					end
					added[itemKey] = index
				end
			end
			for at = 1, staleCount do
				local index = stale[at]
				local entry = order[base + index]
				local item = list[index]
				if entry.item ~= item then
					entry.item = item
					entry.value:set(item)
				end
				if tracks then
					setSecond(entry, index)
				end
			end
			if not ordersChildren and fresh == nil and wanted == previousCount then
				for at = 1, changed do
					local entry = assert(matched[at])
					local index = entry.mark - mark
					local item = list[index]
					if entry.item ~= item then
						entry.item = item
						entry.value:set(item)
					end
					if tracks then
						setSecond(entry, index)
					end
					order[base + index] = entry
					entry.position = base + index
				end
				return
			end
			if trimHead(list, wanted, found) then
				return
			end
			normalize()

			local oldEnd, newEnd = previousCount, wanted
			while oldEnd > prefix and newEnd > prefix and rawequal(rows[oldEnd].key, wantedKeys[newEnd]) do
				oldEnd -= 1
				newEnd -= 1
			end
			local shift = newEnd - oldEnd

			for index = newEnd + 1, wanted do
				local entry = order[index - shift]
				local item = list[index]
				if entry.item ~= item then
					entry.item = item
					entry.value:set(item)
				end
				if tracks then
					setSecond(entry, index)
				end
			end
			if prefix == wanted and previousCount == wanted then
				return
			end

			local removedAny = false
			if found < previousCount then
				for index = prefix + 1, oldEnd do
					local existing = order[index]
					if existing.mark < mark then
						release(existing)
						removedAny = true
					end
				end
			end
			if not ordersChildren then
				local live = prefix
				local failures: { string }? = nil
				for index = prefix + 1, wanted do
					local entry = entries[keys[index]]
					if entry == nil then
						local ok, made = pcall(mountRow, index, keys[index], live + 1, list[index])
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
					elseif index <= newEnd then
						local item = list[index]
						if entry.item ~= item then
							entry.item = item
							entry.value:set(item)
						end
						if tracks then
							setSecond(entry, index)
						end
					end
					live += 1
					local mounted = assert(entry)
					if mounted.position ~= live then
						order[live] = mounted
						mounted.position = live
					end
				end
				for index = #order, live + 1, -1 do
					order[index] = nil
				end
				count = live
				raiseFailures(failures)
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
				if entry ~= nil then
					local item = list[index]
					if entry.item ~= item then
						entry.item = item
						entry.value:set(item)
					end
					if tracks then
						setSecond(entry, index)
					end
					local at = entry.position
					retained += 1
					if at < previousPosition then
						ordered = false
					end
					previousPosition = at
					retainedPositions[retained] = at
					retainedTargets[retained] = index
				end
			end

			local middle = newEnd - prefix
			if ordered and retained == middle and not removedAny and previousCount == wanted then
				return
			end
			if not ordered and retained == middle and previousCount == wanted then
				local first, last = order[prefix + 1], order[newEnd]
				local index = prefix + 2
				if matched[prefix + 1] == last and matched[newEnd] == first then
					while index < newEnd and matched[index] == order[index] do
						index += 1
					end
					if index >= newEnd then
						order[prefix + 1], order[newEnd] = last, first
						last.position, first.position = prefix + 1, newEnd
						mountPoint.moveTo(last.node, prefix + 1)
						if middle > 2 then
							mountPoint.moveTo(first.node, newEnd)
						end
						return
					end
				end
			end

			local stays: { number }? = nil
			if not ordered then
				stays = longestIncreasingSubsequence(retainedPositions, retained)
			end

			local failures: { string }? = nil
			if stays == nil then
				local live = prefix
				for index = prefix + 1, newEnd do
					local entry = matched[index]
					live += 1

					if entry == nil then
						local ok, made = pcall(mountRow, index, keys[index], live, list[index])
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
				local anchor: Entry<V, K, S>? = if newEnd < wanted then following else nil
				local staying = 1
				for index = newEnd, prefix + 1, -1 do
					local entry = matched[index]

					local anchorLive = if anchor ~= nil then anchor.position else #order + 1

					if entry == nil then
						local ok, made = pcall(mountRow, index, keys[index], anchorLive, list[index])
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
						mountPoint.moveTo(entry.node, destination)
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
			local outerKeys, outerMatched, outerScratch, outerSeconds = keys, matched, scratch, seconds
			if depth > 1 then
				keys, matched, scratch = {}, {}, {}
			end
			local ok, failure: unknown = pcall(reconcile, use)
			keys, matched, scratch, seconds = outerKeys, outerMatched, outerScratch, outerSeconds
			depth -= 1
			if not ok then
				error(failure, 0)
			end
		end)
	end
end

return keyedRows
