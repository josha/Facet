--!strict
--!native

local createChosenIndices: (number, number?) -> { number } = table.create
local createStates: (number, Representation?) -> { Representation } = table.create

local StructureTypes = require "./types"
local Children = require "../runtime/children"
local Admission = require "../collection/admission"
local Diagnostics = require "../diagnostics"
local FramePump = require "../collection/frame-pump"
local Grid = require "../collection/grid"
local Relevance = require "../collection/relevance"
local Support = require "./support"
local Types = require "../reactive/types"
local cellModule = require "../reactive/cell"
local retain = require "../collection/retain"

export type Tier = StructureTypes.SpatialCollectionTier

export type Point = StructureTypes.SpatialCollectionPoint

export type Representation = StructureTypes.Representation

export type Budget = StructureTypes.SpatialCollectionBudget

export type Status = StructureTypes.SpatialCollectionStatus

export type Options<V, K> = StructureTypes.SpatialCollectionOptions<V, K>

local KNOWN_FIELDS: { [string]: true } = {
	from = true,
	key = true,
	position = true,
	origin = true,
	tiers = true,
	render = true,
	cellSize = true,
	hysteresis = true,
	importance = true,
	pinned = true,
	budget = true,
	status = true,
}

local KNOWN_BUDGET: { [string]: true } = { mountsPerFrame = true }

local function numberOr(value: unknown, fallback: number): number
	if value == nil then
		return fallback
	end
	if type(value) == "number" and value == value then
		return value
	end
	return fallback
end

local identity = require("../reactive/node").identityKey

local function spatialCollection<V, K>(options: Options<V, K>): Children.Directive
	local settings = Support.optionsOf(
		options,
		"SpatialCollection",
		"from = ..., position = ..., origin = ..., tiers = ..., render = ..."
	)
	Support.noUnknownFields(settings, "SpatialCollection", KNOWN_FIELDS)

	local source: Types.Body<{ V }> = Support.sourceOf(settings.from, "SpatialCollection", "from")
	local render = Support.builderOf(settings.render, "SpatialCollection", "render")
	local positionOf = Support.builderOf(settings.position, "SpatialCollection", "position")
	local originBody: Types.Body<Point> = Support.sourceOf(settings.origin, "SpatialCollection", "origin")

	local tiers = settings.tiers
	if type(tiers) ~= "table" then
		Diagnostics.raise("collection/no-tiers", "SpatialCollection was given no tier list", {
			primitive = "SpatialCollection",
			actual = Diagnostics.describe(tiers),
			expected = '{ { name = "full", radius = 100 }, ... }',
		})
	end
	Relevance.checkTiers(tiers, "SpatialCollection")
	local tierCount = #tiers
	local outerRadius = tiers[tierCount].radius

	local keyOf: (value: V, index: number) -> K
	if settings.key ~= nil then
		keyOf = Support.builderOf(settings.key, "SpatialCollection", "key")
	else
		keyOf = identity
	end

	local hysteresis = math.max(0, numberOr(settings.hysteresis, 0))
	local cellSize = numberOr(settings.cellSize, math.max(1, outerRadius))
	local importance = settings.importance
	if importance ~= nil then
		importance = Support.builderOf(importance, "SpatialCollection", "importance")
	end

	local pinnedBody: Types.Body<{ [K]: boolean }>? = nil
	if settings.pinned ~= nil then
		pinnedBody = Support.sourceOf(settings.pinned, "SpatialCollection", "pinned")
	end

	local budget: Budget = settings.budget or {}
	Support.noUnknownFields(budget, "SpatialCollection.budget", KNOWN_BUDGET)
	local mountsPerFrame = if budget.mountsPerFrame ~= nil
		then math.max(1, math.floor(numberOr(budget.mountsPerFrame, 1)))
		else nil

	local statusCell = if settings.status == nil
		then nil
		else Support.writableOf(settings.status, "SpatialCollection", "status")
	local simpleMovingPopulation = pinnedBody == nil and importance == nil and hysteresis == 0 and mountsPerFrame == nil

	return function(mountPoint: Children.MountPoint)
		local owner = Support.ownerFor "SpatialCollection"
		Support.mountPointOf(mountPoint, "SpatialCollection")
		local tick = cellModule.cell(0)
		local pump = FramePump(owner, mountPoint.host, tick, "SpatialCollection")

		local grid = Grid.create(cellSize)
		local builtFor: { V }? = nil
		local gridFor: { V }? = nil
		local allKeys: { K } = {}
		local indexOfKey: { [K]: number } = {}
		local largestImportance = 1
		local tierOf: { [K]: number } = {}
		local candidates: { number } = {}
		local seen: { [number]: boolean } = {}

		local function select(use: Types.Use, list: { V }): retain.Selection<V, Representation, K>
			local populationChanged = list ~= builtFor
			if populationChanged then
				local count = #list
				table.clear(allKeys)
				table.clear(indexOfKey)
				largestImportance = 1
				if builtFor == nil or not simpleMovingPopulation then
					for index = 1, count do
						local value = list[index]
						local key = keyOf(value, index)
						allKeys[index] = key
						if pinnedBody ~= nil then
							indexOfKey[key] = index
						end
						local importance = importance
						if importance ~= nil then
							local scale = math.max(0, numberOr(importance(value), 1))
							if scale > largestImportance then
								largestImportance = scale
							end
						end
					end
				end
				if builtFor == nil then
					Grid.build(grid, list, function(value: V): (number, number, number)
						local x, y, z = positionOf(value)
						return x, y, z or 0
					end)
					gridFor = list
				else
					gridFor = nil
				end
				builtFor = list
			elseif gridFor ~= list then
				if #allKeys ~= #list then
					for index = 1, #list do
						allKeys[index] = keyOf(list[index], index)
					end
				end
				Grid.build(grid, list, function(value: V): (number, number, number)
					local x, y, z = positionOf(value)
					return x, y, z or 0
				end)
				gridFor = list
			end

			use(tick)

			local origin = originBody(use)
			local ox, oy, oz = numberOr(origin.x, 0), numberOr(origin.y, 0), numberOr(origin.z, 0)
			local readPinned: Types.Body<{ [K]: boolean }>? = pinnedBody
			local pinned: { [K]: boolean }? = if readPinned ~= nil then readPinned(use) else nil

			local count = #list
			if simpleMovingPopulation and gridFor ~= list then
				local values: { V } = {}
				local keys: { K } = {}
				local states: { Representation } = {}
				local perTier = table.create(tierCount, 0)
				for index = 1, count do
					local value = list[index]
					local x, y, z = positionOf(value)
					local dx, dy, dz = x - ox, y - oy, (z or 0) - oz
					local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
					local tier = Relevance.tierFor(distance, nil, tiers, 0, 1)
					if tier ~= nil then
						local at = #values + 1
						values[at] = value
						keys[at] = keyOf(value, index)
						states[at] = {
							tier = tier,
							name = (tiers)[tier].name,
							distance = distance,
							pinned = false,
						}
						perTier[tier] += 1
					end
				end
				tierOf = {}
				if statusCell ~= nil then
					statusCell:set {
						total = count,
						retained = #values,
						queried = count,
						pending = 0,
						perTier = perTier,
						cells = 0,
					}
				end
				return { values = values, keys = keys, states = states }
			end

			local queried = 0
			table.clear(candidates)
			table.clear(seen)

			local maxRadius = outerRadius
			if importance ~= nil then
				maxRadius = outerRadius * largestImportance
			end
			maxRadius += hysteresis

			local cells = 0
			if gridFor == list then
				cells = Grid.query(grid, ox, oy, oz, maxRadius, function(index: number)
					if not seen[index] then
						seen[index] = true
						queried += 1
						candidates[#candidates + 1] = index
					end
				end)
			else
				queried = count
				for index = 1, count do
					seen[index] = true
					candidates[index] = index
				end
			end

			if pinned ~= nil then
				for key, isPinned in pinned do
					local index = indexOfKey[key]
					if isPinned and index ~= nil and not seen[index] then
						seen[index] = true
						candidates[#candidates + 1] = index
					end
				end
			end

			local keptIndices: { number } = {}
			local keptTiers: { number } = {}
			local keptDistance: { number } = {}
			local newIndices: { number } = {}
			local newTiers: { number } = {}
			local newDistance: { number } = {}

			table.sort(candidates)
			for _, index in candidates do
				local value = list[index]
				local x, y, z = positionOf(value)
				local dx, dy, dz = x - ox, y - oy, (z or 0) - oz
				local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
				local key = allKeys[index]
				local current = tierOf[key]
				local scale = if importance ~= nil then math.max(0, numberOr(importance(value), 1)) else 1

				local tier: number?
				if pinned ~= nil and pinned[key] then
					tier = Relevance.pinnedTier(distance, current, tiers, hysteresis, scale)
				else
					tier = Relevance.tierFor(distance, current, tiers, hysteresis, scale)
				end

				if tier ~= nil then
					if current ~= nil then
						keptIndices[#keptIndices + 1] = index
						keptTiers[#keptTiers + 1] = tier
						keptDistance[#keptDistance + 1] = distance
					else
						newIndices[#newIndices + 1] = index
						newTiers[#newTiers + 1] = tier
						newDistance[#newDistance + 1] = distance
					end
				end
			end

			local admission = Admission(#newIndices, mountsPerFrame, function(a: number, b: number): boolean
				if newTiers[a] ~= newTiers[b] then
					return newTiers[a] < newTiers[b]
				end
				if newDistance[a] ~= newDistance[b] then
					return newDistance[a] < newDistance[b]
				end
				return newIndices[a] < newIndices[b]
			end)
			local admitted, pending = admission.admitted, admission.pending
			if admission.order ~= nil then
				local order = admission.order
				local chosenIndices: { number } = createChosenIndices(admitted)
				local chosenTiers: { number } = createChosenIndices(admitted)
				local chosenDistance: { number } = createChosenIndices(admitted)
				for position = 1, admitted do
					local at = order[position]
					chosenIndices[position] = newIndices[at]
					chosenTiers[position] = newTiers[at]
					chosenDistance[position] = newDistance[at]
				end
				newIndices, newTiers, newDistance = chosenIndices, chosenTiers, chosenDistance
			end

			pump.update(pending > 0)

			local total = #keptIndices + #newIndices
			local values: { V } = table.create(total)
			local keys: { K } = table.create(total)
			local states: { Representation } = createStates(total)
			local perTier = table.create(tierCount, 0)
			local nextTier: { [K]: number } = {}

			local a, b = 1, 1
			for position = 1, total do
				local takeKept: boolean
				if a > #keptIndices then
					takeKept = false
				elseif b > #newIndices then
					takeKept = true
				else
					takeKept = keptIndices[a] < newIndices[b]
				end

				local index, tier, distance
				if takeKept then
					index, tier, distance = keptIndices[a], keptTiers[a], keptDistance[a]
					a += 1
				else
					index, tier, distance = newIndices[b], newTiers[b], newDistance[b]
					b += 1
				end

				local key = allKeys[index]
				values[position] = list[index]
				keys[position] = key
				states[position] = {
					tier = tier,
					name = (tiers)[tier].name,
					distance = distance,
					pinned = pinned ~= nil and pinned[key] == true,
				}
				perTier[tier] += 1
				nextTier[key] = tier
			end

			tierOf = nextTier

			if statusCell ~= nil then
				statusCell:set {
					total = count,
					retained = total,
					queried = queried,
					pending = pending,
					perTier = perTier,
					cells = cells,
				}
			end

			return { values = values, keys = keys, states = states }
		end

		local inner = retain {
			primitive = "SpatialCollection",
			source = source,
			select = select,
			render = render,
			equals = function(current: Representation, incoming: Representation): boolean
				return current.tier == incoming.tier
					and current.distance == incoming.distance
					and current.pinned == incoming.pinned
			end,
		}
		inner(mountPoint)
	end
end

return spatialCollection
