--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local EngineTypes = require("./engine_types")
local CollectionTypes = require("./collection_types")
local State = require("./collection_state")
export type Slot<V, K> = { key: K, item: V? }
export type Slots<V, K> = {
	source: ComposeTypes.Value<{ Slot<V, K> }>,
	wrap: (
		(ComposeTypes.ReadOnlyValue<V>, ComposeTypes.ReadOnlyValue<ComposeTypes.Placement>, K) -> GuiObject
	) -> (ComposeTypes.ReadOnlyValue<Slot<V, K>>, ComposeTypes.ReadOnlyValue<ComposeTypes.Placement>, K) -> GuiObject,
}
return function<V, K>(ctx: Types.Context, view: State.View<V, K>): Slots<V, K>
	local Compose, Host = ctx.Compose, ctx.Host
	local read = ctx.read
	local D2 = ctx.types.UDim2
	local spec, source, keyOf, horizontal = view.spec, view.source, view.keyOf, view.horizontal
	local slotNodes: { [K]: GuiObject } = {}
	if spec.slotControls then
		assert(spec.slots ~= nil, "Facet collection slotControls requires slots")
		spec.slotControls.nodeOfKey = function(key: K): GuiObject?
			return slotNodes[key]
		end
		Compose.cleanup(function()
			(spec.slotControls :: CollectionTypes.SlotControls<K>).nodeOfKey = nil
		end)
	end
	type SlotRecord = { key: K, item: V? }
	local itemsByKey: ComposeTypes.ReadOnlyValue<{ [K]: V }>? = if spec.slots ~= nil
		then Compose.formula(function(use: ComposeTypes.Use): { [K]: V }
			local items: { [K]: V } = {}
			for index, item in source(use) do
				items[keyOf(item, index)] = item
			end
			return items
		end)
		else nil
	local slotSource = Compose.formula(function(use: ComposeTypes.Use): { SlotRecord }
		local result: { SlotRecord } = {}
		local rows = source(use)
		if itemsByKey == nil then
			for index, item in rows do
				table.insert(result, { key = keyOf(item, index), item = item })
			end
			return result
		end
		local items = use(itemsByKey)
		local included: { [K]: boolean } = {}
		for _, key in read(spec.slots or {}, use) do
			assert(not included[key], "Facet collection slots must have unique keys")
			included[key] = true
			table.insert(result, { key = key, item = items[key] })
		end
		for index, item in rows do
			local key = keyOf(item, index)
			if not included[key] then
				table.insert(result, { key = key, item = item })
			end
		end
		return result
	end, function(before: { SlotRecord }?, after: { SlotRecord }): boolean
		if before == nil or spec.slots == nil or #before ~= #after then
			return false
		end
		for index, entry in before do
			if entry.key ~= after[index].key then
				return false
			end
		end
		return true
	end)
	local function withSlots(renderItem: (
		ComposeTypes.ReadOnlyValue<V>,
		ComposeTypes.ReadOnlyValue<ComposeTypes.Placement>,
		K
	) -> GuiObject)
		return function(
			record: ComposeTypes.ReadOnlyValue<SlotRecord>,
			placement: ComposeTypes.ReadOnlyValue<ComposeTypes.Placement>,
			key: K
		)
			if spec.slots == nil then
				return renderItem(
					Compose.formula(function(use: ComposeTypes.Use): V
						return assert(use(record).item)
					end),
					placement,
					key
				)
			end
			local index = assert(itemsByKey)
			local itemForKey = Compose.formula(function(use: ComposeTypes.Use): V?
				return use(index)[key]
			end)
			local last = record:peek().item
			local current = Compose.formula(function(use: ComposeTypes.Use): V
				local item = use(itemForKey)
				if item ~= nil then
					last = item
				end
				return assert(last)
			end)
			local recess: GuiObject = ctx.styled(
				Host.Frame "ReservedSlot" {
					Visible = function(use: ComposeTypes.Use): boolean
						return use(itemForKey) == nil
					end,
					Interactable = false,
					Selectable = false,
					Size = D2.fromScale(1, 1),
				},
				"fill"
			)
			local shown: ComposeTypes.Value<UDim2?> = Compose.cell(nil :: UDim2?)
			local attributes: EngineTypes.Attributes = { FacetReservedKey = tostring(key) }
			local anchor = Host.Frame "SlotAnchor" {
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Selectable = false,
				Attributes = attributes,
				Position = function(use: ComposeTypes.Use): UDim2
					local item = use(shown)
					if item then
						return item
					end
					local at = use(placement)
					return if horizontal
						then D2.fromOffset(at.offset, at.crossOffset)
						else D2.fromOffset(at.crossOffset, at.offset)
				end,
				Size = function(use: ComposeTypes.Use): UDim2
					local at = use(placement)
					return if horizontal
						then D2.fromOffset(at.size, at.crossSize)
						else D2.fromOffset(at.crossSize, at.size)
				end,
				recess,
			}
			slotNodes[key] = anchor
			Compose.cleanup(function()
				if slotNodes[key] == anchor then
					slotNodes[key] = nil
				end
			end)
			local shellProps: Types.FrameProps = {
				Name = "Slot",
				BackgroundTransparency = 1,
				Size = D2.fromScale(1, 1),
				Compose.show(function(use: ComposeTypes.Use): boolean
					return use(itemForKey) ~= nil
				end, function()
					local rendered = renderItem(current, placement, key)
					local position = ctx.observe.Position(rendered)
					Compose.watch(function(use: ComposeTypes.Use)
						shown:set(use(position))
					end)
					Compose.cleanup(function()
						shown:set(nil)
					end)
					return rendered
				end),
				anchor,
			}
			return Host.Frame(shellProps)
		end
	end
	return { source = slotSource, wrap = withSlots }
end
