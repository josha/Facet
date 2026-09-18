--!strict
--!native

local Children = require "../runtime/children"
local Diagnostics = require "../diagnostics"
local Host = require "../host"
local Layout = require "../collection/layout"
local Support = require "./support"
local Types = require "../reactive/types"
local keyed = require "./keyed"
local retain = require "../collection/retain"

export type Viewport = {
	offset: number,
	size: number,
}

export type Mode = "all" | "windowed"
export type Direction = "vertical" | "horizontal"
export type LayoutKind = "list" | "grid"
export type Align = "start" | "center" | "end"

export type LayoutOptions = {
	kind: LayoutKind?,
	columns: number?,
	itemSize: number?,
	gap: number?,
	crossSize: number?,
	crossGap: number?,
}

export type Status = {
	mode: Mode,
	direction: Direction,
	total: number,
	retained: number,
	first: number,
	last: number,
	firstRow: number,
	lastRow: number,
	rowCount: number,
	extent: number,
	following: boolean,
	desiredOffset: number?,
	measured: number,
}

export type Controls<K> = {
	offsetOf: ((index: number, align: Align?, size: number?) -> number)?,
	indexOfKey: ((key: K) -> number?)?,
	placementOf: ((index: number) -> Layout.Placement)?,
}

export type Options<V, K> = {
	from: keyed.Source<V>,
	key: ((value: V, index: number) -> K)?,
	render: (value: Types.Readable<V>, placement: Types.Readable<Layout.Placement>, key: K) -> Host.Node,
	mode: Mode?,
	viewport: (Types.Readable<Viewport> | Types.Body<Viewport>)?,
	direction: Direction?,
	layout: LayoutOptions?,
	overscan: number?,
	measured: (Types.Readable<{ [K]: number }> | Types.Body<{ [K]: number }>)?,
	follow: ("end" | "none")?,
	followThreshold: number?,
	status: Types.Cell<Status>?,
	controls: Controls<K>?,
}

local KNOWN_FIELDS: { [string]: true } = {
	from = true,
	key = true,
	render = true,
	mode = true,
	viewport = true,
	direction = true,
	layout = true,
	overscan = true,
	measured = true,
	follow = true,
	followThreshold = true,
	status = true,
	controls = true,
}

local KNOWN_LAYOUT: { [string]: true } = {
	kind = true,
	columns = true,
	itemSize = true,
	gap = true,
	crossSize = true,
	crossGap = true,
}

local function numberOr(value: unknown, fallback: number): number
	if value == nil then
		return fallback
	end
	if type(value) == "number" and value == value then
		return value
	end
	return fallback
end

local function identity<V>(value: V, _index: number): any
	return value
end

local function orderedCollection<V, K>(options: Options<V, K>): Children.Directive
	local settings = Support.optionsOf(options, "OrderedCollection", "from = ..., render = ...")
	Support.noUnknownFields(settings, "OrderedCollection", KNOWN_FIELDS)

	local source = Support.sourceOf(settings.from, "OrderedCollection", "from") :: Types.Body<{ V }>
	local render =
		Support.builderOf(settings.render, "OrderedCollection", "render") :: (Types.Readable<V>, Types.Readable<Layout.Placement>, K) -> Host.Node

	local keyOf: (value: V, index: number) -> K
	if settings.key ~= nil then
		keyOf = Support.builderOf(settings.key, "OrderedCollection", "key") :: (value: V, index: number) -> K
	else
		keyOf = (identity :: any) :: (value: V, index: number) -> K
	end

	local mode: Mode = (settings.mode :: Mode?) or "all"
	if mode ~= "all" and mode ~= "windowed" then
		Diagnostics.raise("collection/unknown-mode", "OrderedCollection was given a mode it does not have", {
			primitive = "OrderedCollection",
			actual = Diagnostics.describe(settings.mode),
			expected = '"all" or "windowed"',
			contract = "the retention policy is explicit; there is no population at which one becomes the other",
		})
	end

	local direction: Direction = (settings.direction :: Direction?) or "vertical"
	if direction ~= "vertical" and direction ~= "horizontal" then
		Diagnostics.raise("collection/unknown-direction", "OrderedCollection was given a direction it does not have", {
			primitive = "OrderedCollection",
			actual = Diagnostics.describe(settings.direction),
			expected = '"vertical" or "horizontal"',
		})
	end

	local layoutOptions: LayoutOptions = settings.layout or {}
	Support.noUnknownFields(layoutOptions :: any, "OrderedCollection.layout", KNOWN_LAYOUT)
	local kind: LayoutKind = (layoutOptions.kind :: LayoutKind?) or "list"
	if kind ~= "list" and kind ~= "grid" then
		Diagnostics.raise("collection/unknown-layout", "OrderedCollection was given a layout kind it does not have", {
			primitive = "OrderedCollection",
			actual = Diagnostics.describe(layoutOptions.kind),
			expected = '"list" or "grid"',
		})
	end
	local columns = if kind == "grid" then math.max(1, math.floor(numberOr(layoutOptions.columns, 1))) else 1
	local itemSize = numberOr(layoutOptions.itemSize, 1)
	local gap = numberOr(layoutOptions.gap, 0)
	local crossSize = numberOr(layoutOptions.crossSize, 0)
	local crossGap = numberOr(layoutOptions.crossGap, 0)
	local overscan = math.max(0, math.floor(numberOr(settings.overscan, 0)))
	local followThreshold = numberOr(settings.followThreshold, 4)
	local followEnd = settings.follow == "end"

	local viewportBody: Types.Body<Viewport>? = nil
	if settings.viewport ~= nil then
		viewportBody = Support.sourceOf(settings.viewport, "OrderedCollection", "viewport") :: Types.Body<Viewport>
	elseif mode == "windowed" then
		Diagnostics.raise("collection/no-viewport", 'OrderedCollection mode = "windowed" needs a viewport', {
			primitive = "OrderedCollection",
			contract = "a windowed collection retains what the viewport covers, so it has to be told where it is",
			fix = 'pass viewport = a cell holding { offset = ..., size = ... }, or use mode = "all"',
		})
	end

	local measuredBody: Types.Body<{ [K]: number }>? = nil
	if settings.measured ~= nil then
		measuredBody =
			Support.sourceOf(settings.measured, "OrderedCollection", "measured") :: Types.Body<{ [K]: number }>
	end

	local statusCell = if settings.status == nil
		then nil
		else Support.writableOf(settings.status, "OrderedCollection", "status")
	local controls = settings.controls
	if controls ~= nil and type(controls) ~= "table" then
		Diagnostics.raise("collection/controls-not-a-table", "OrderedCollection cannot fill in these controls", {
			key = "controls",
			actual = Diagnostics.describe(controls),
			expected = "a table, which the collection fills in on mount",
			contract = "controls is an out-parameter: the collection writes its query functions into it",
			fix = "pass a table you keep -- local controls = {} -- and read controls.placementOf after mounting",
		})
	end

	local builtFor: { V }? = nil
	local indexMap: { [K]: number }? = nil
	local geometry = Layout.create {
		count = 0,
		columns = columns,
		rowSize = itemSize,
		gap = gap,
		crossSize = crossSize,
		crossGap = crossGap,
	}
	local applied: { [K]: number } = {}

	local appliedFrom: { [K]: number }? = nil
	local measuredCount = 0
	local following = followEnd
	local lastOffset: number? = nil
	local anchorKey: K? = nil
	local anchorOffset = 0
	local anchorIndex = 0
	local measurementsChanged = false

	local function keyIndex(): { [K]: number }
		local existing = indexMap
		if existing ~= nil then
			return existing
		end
		local list = builtFor :: { V }
		local map: { [K]: number } = {}
		for index = 1, #list do
			map[keyOf(list[index], index)] = index
		end
		indexMap = map
		return map
	end

	local function rebuild(list: { V })
		local count = #list
		indexMap = nil
		builtFor = list
		geometry = Layout.create {
			count = count,
			columns = columns,
			rowSize = itemSize,
			gap = gap,
			crossSize = crossSize,
			crossGap = crossGap,
		}
		measurementsChanged = true
	end

	local function applyMeasurements(sizes: { [K]: number })
		local map = keyIndex()
		for key in applied do
			local at = map[key]
			if sizes[key] == nil or at == nil then
				if at ~= nil then
					Layout.setItemSize(geometry, at, itemSize)
				end
				applied[key] = nil
			end
		end

		measuredCount = 0
		for key, size in sizes do
			local at = map[key]
			if at ~= nil then
				applied[key] = size
				Layout.setItemSize(geometry, at, size)
				measuredCount += 1
			end
		end
		measurementsChanged = false
	end

	if controls ~= nil then
		controls.indexOfKey = function(key: K): number?
			return keyIndex()[key]
		end
		controls.placementOf = function(index: number): Layout.Placement
			return Layout.placementOf(geometry, index)
		end
		controls.offsetOf = function(index: number, align: Align?, size: number?): number
			local placement = Layout.placementOf(geometry, index)
			local viewportSize = numberOr(size, 0)
			local extent = Layout.totalExtent(geometry)
			local target: number
			if align == "end" then
				target = placement.offset + placement.size - viewportSize
			elseif align == "center" then
				target = placement.offset + placement.size / 2 - viewportSize / 2
			else
				target = placement.offset
			end
			return math.clamp(target, 0, math.max(0, extent - viewportSize))
		end
	end

	local function select(use: Types.Use, list: { V }): retain.Selection<V, Layout.Placement, K>
		if list ~= builtFor then
			rebuild(list)
		end

		if measuredBody ~= nil then
			local sizes = measuredBody(use)
			if measurementsChanged or sizes ~= appliedFrom then
				appliedFrom = sizes
				applyMeasurements(sizes)
			end
		end

		local count = #list
		local extent = Layout.totalExtent(geometry)
		local range: Layout.Range
		local viewport: Viewport = { offset = 0, size = extent }
		if mode == "windowed" then
			local read = (viewportBody :: Types.Body<Viewport>)(use)
			viewport = {
				offset = numberOr(read.offset, 0),
				size = numberOr(read.size, 0),
			}
			range = Layout.rangeFor(geometry, viewport.offset, viewport.size, overscan)
		else
			range = {
				first = if count > 0 then 1 else 1,
				last = count,
				firstRow = if count > 0 then 1 else 0,
				lastRow = geometry.rowCount,
			}
		end

		local desiredOffset: number? = nil
		if followEnd and mode == "windowed" then
			if lastOffset == nil or viewport.offset ~= lastOffset then
				local distanceFromEnd = extent - (viewport.offset + viewport.size)
				following = distanceFromEnd <= followThreshold
			end
			if following then
				local target = math.max(0, extent - viewport.size)
				if target ~= viewport.offset then
					desiredOffset = target
				end
			end
		end

		if desiredOffset == nil and anchorKey ~= nil then
			local wanted = anchorKey :: K
			local at: number? = nil
			if anchorIndex >= 1 and anchorIndex <= count and keyOf(list[anchorIndex], anchorIndex) == wanted then
				at = anchorIndex
			else
				local SEARCH = 64
				for distance = 1, SEARCH do
					local before = anchorIndex - distance
					if before >= 1 and before <= count and keyOf(list[before], before) == wanted then
						at = before
						break
					end
					local after = anchorIndex + distance
					if after >= 1 and after <= count and keyOf(list[after], after) == wanted then
						at = after
						break
					end
				end
				if at == nil then
					at = keyIndex()[wanted]
				end
			end
			if at ~= nil then
				local moved = Layout.offsetOf(geometry, at) - anchorOffset
				if moved ~= 0 and mode == "windowed" then
					desiredOffset = math.max(0, viewport.offset + moved)
				end
			end
		end

		local values = table.create(math.max(0, range.last - range.first + 1))
		local keys = table.create(math.max(0, range.last - range.first + 1))
		local states = table.create(math.max(0, range.last - range.first + 1))
		local retained = 0
		for index = range.first, range.last do
			retained += 1
			values[retained] = list[index]
			keys[retained] = keyOf(list[index], index)
			states[retained] = Layout.placementOf(geometry, index)
		end

		lastOffset = viewport.offset

		if retained > 0 then
			anchorKey = keys[1]
			anchorOffset = states[1].offset
			anchorIndex = range.first
		else
			anchorKey = nil
			anchorOffset = 0
			anchorIndex = 0
		end

		if statusCell ~= nil then
			statusCell:set {
				mode = mode,
				direction = direction,
				total = count,
				retained = retained,
				first = range.first,
				last = range.last,
				firstRow = range.firstRow,
				lastRow = range.lastRow,
				rowCount = geometry.rowCount,
				extent = extent,
				following = following,
				desiredOffset = desiredOffset,
				measured = measuredCount,
			}
		end

		return { values = values, keys = keys, states = states }
	end

	return retain {
		primitive = "OrderedCollection",
		source = source,
		select = select,
		render = render,
		equals = function(current: Layout.Placement, incoming: Layout.Placement): boolean
			return current.index == incoming.index
				and current.row == incoming.row
				and current.column == incoming.column
				and current.offset == incoming.offset
				and current.size == incoming.size
				and current.crossOffset == incoming.crossOffset
				and current.crossSize == incoming.crossSize
		end,
	}
end

return orderedCollection
