--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local CollectionTypes = require("./collection_types")
local Metrics = require("./collection_table_metrics")
export type Columns<V, K> = {
	viewportWidth: ComposeTypes.Cell<number>,
	fillWidth: ComposeTypes.Cell<number>,
	setPrimaryMeasure: (K, TextLabel, number, number) -> (),
	minimumOf: (CollectionTypes.TableColumn<V, K>) -> number,
	collapsed: ComposeTypes.Formula<{ [string]: boolean }>,
	disclosureWidth: ComposeTypes.Formula<number>,
	disclosureShare: ComposeTypes.Formula<number>,
	narrowest: ComposeTypes.Formula<number>,
	textWrap: (CollectionTypes.TableColumn<V, K>, ComposeTypes.Use) -> boolean,
	columnFrame: (
		ComposeTypes.Readable<CollectionTypes.TableColumn<V, K>>,
		ComposeTypes.Readable<number>,
		GuiObject,
		GuiObject?,
		GuiObject?
	) -> Frame,
}
return function<V, K>(
	ctx: Types.Context,
	spec: CollectionTypes.TableShape<V, K>,
	widths: ComposeTypes.Cell<{ [string]: number }>,
	truncatedRows: ComposeTypes.Cell<{ [K]: { [string]: boolean } }>,
	metrics: Metrics.Metrics,
	rows: ComposeTypes.Readable<{ V }>,
	keyOf: (V, number) -> K,
	field: (V, CollectionTypes.TableColumn<V, K>) -> unknown,
	unitScale: ComposeTypes.Readable<number>
): Columns<V, K>
	local Compose, Host = ctx.Compose, ctx.Host
	local read = ctx.read
	local readSource = ctx.readSource
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local viewportWidth = Compose.cell(0)
	local fillWidth = Compose.cell(0)
	local primaryNatural = Compose.cell(0)
	local primaryMeasures: { [K]: number? } = {}
	local primaryCounts: { [number]: number? } = {}
	local textCache: ComposeTypes.KeyedCache<string, { width: number }> = Compose.createKeyedCache {
		maxRetained = 512,
		build = function(_: string): { width: number }
			return { width = 0 }
		end,
		destroy = function(_: { width: number }) end,
	}
	local font = ctx.observeStyled.FontFace(metrics.textInsets)
	local points = ctx.observeStyled.TextSize(metrics.textInsets)
	local function typography(face: Font, size: number, scale: number): string
		return `{face.Family}:{face.Weight.Value}:{face.Style.Value}:{size}:{scale}`
	end
	local function contentKey(text: string, style: string): string
		return `{#text}:{text}:{style}`
	end
	local function setPrimaryMeasure(key: K, width: number?)
		local before = primaryMeasures[key]
		if before == width then
			return
		end
		if before then
			local count = (primaryCounts[before] or 0) - 1
			primaryCounts[before] = if count > 0 then count else nil
		end
		primaryMeasures[key] = width
		if width then
			primaryCounts[width] = (primaryCounts[width] or 0) + 1
		end
		local largest = primaryNatural:peek()
		if width and width > largest then
			primaryNatural:set(width)
		elseif before == largest and primaryCounts[largest] == nil then
			largest = 0
			for measured in primaryCounts do
				largest = math.max(largest, measured)
			end
			primaryNatural:set(largest)
		end
	end
	local function minimumOf(column: CollectionTypes.TableColumn<V, K>): number
		return column.minWidth or 48
	end
	Compose.watch(function(use: ComposeTypes.Use)
		local columns = read(spec.columns, use)
		local primary = columns[1]
		local style = typography(use(font), use(points), use(unitScale))
		local padding = metrics.textInsets:FindFirstChildWhichIsA("UIPadding")
		local inset = if padding
			then (padding:GetStyled("PaddingLeft") :: UDim).Offset + (padding:GetStyled("PaddingRight") :: UDim).Offset
			else math.max(metrics.cellPadding, use(metrics.textInsetSize).X / use(unitScale))
		local current = use(rows)
		if textCache.size() == 0 then
			return
		end
		local valid: { [K]: boolean } = {}
		for index, item in current do
			local key = keyOf(item, index)
			valid[key] = true
			local value = if primary then field(item, primary) else nil
			local text = if value == nil then "" else tostring(value)
			local cached = if primary
					and primary.render == nil
					and primary.editor == nil
				then textCache.peek(contentKey(text, style))
				else nil
			setPrimaryMeasure(key, if cached then cached.width + inset else nil)
		end
		for key in primaryMeasures do
			if not valid[key] then
				setPrimaryMeasure(key, nil)
			end
		end
	end)
	local function boundedWidth(column: CollectionTypes.TableColumn<V, K>, width: number): number
		return math.clamp(width, minimumOf(column), column.maxWidth or 1000000)
	end
	local collapsed = Compose.formula(function(use: ComposeTypes.Use)
		local columns, offer, resized = read(spec.columns, use), use(viewportWidth), readSource(widths, use)
		local hidden: { [string]: boolean } = {}
		local candidates: { { id: string, width: number, priority: number } } = {}
		local needed = 0
		for index, column in columns do
			local fixed = resized[column.id] or column.width
			local width = boundedWidth(column, fixed or minimumOf(column))
			needed += if index == 1 and fixed == nil
				then boundedWidth(column, math.max(width, use(primaryNatural)))
				else width
			if index > 1 and type(column.priority) == "number" then
				table.insert(candidates, { id = column.id, width = width, priority = column.priority })
			end
		end
		table.sort(candidates, function(a, b)
			return a.priority > b.priority
		end)
		if offer > 0 then
			for _, candidate in candidates do
				if needed <= offer then
					break
				end
				if next(hidden) == nil then
					offer -= 48
				end
				hidden[candidate.id] = true
				needed -= candidate.width
			end
		end
		return hidden
	end, function(current: { [string]: boolean }?, incoming: { [string]: boolean }): boolean
		if current == nil then
			return false
		end
		for id, hidden in current do
			if incoming[id] ~= hidden then
				return false
			end
		end
		for id, hidden in incoming do
			if current[id] ~= hidden then
				return false
			end
		end
		return true
	end)
	local disclosureWidth = Compose.formula(function(use: ComposeTypes.Use)
		if next(use(collapsed)) ~= nil then
			return 48
		end
		for _, value in use(truncatedRows) do
			if next(value) ~= nil then
				return 48
			end
		end
		return 0
	end)
	local disclosureShare = Compose.formula(function(use: ComposeTypes.Use): number
		if next(use(collapsed)) ~= nil then
			return 0
		end
		local hidden, resized, flexible = use(collapsed), readSource(widths, use), 0
		for _, column in read(spec.columns, use) do
			if not hidden[column.id] and resized[column.id] == nil and column.width == nil then
				flexible += 1
			end
		end
		return if flexible > 0 then use(disclosureWidth) / flexible else 0
	end)
	local narrowest = Compose.formula(function(use: ComposeTypes.Use): number
		local hidden, resized, total = use(collapsed), readSource(widths, use), 0
		for _, column in read(spec.columns, use) do
			if not hidden[column.id] then
				total += boundedWidth(column, resized[column.id] or column.width or minimumOf(column))
			end
		end
		return total
	end)
	local function columnWidth(
		current: ComposeTypes.Readable<CollectionTypes.TableColumn<V, K>>,
		use: ComposeTypes.Use
	): number?
		local column = use(current)
		local fixed = readSource(widths, use)[column.id] or column.width
		return if fixed ~= nil then boundedWidth(column, fixed) else nil
	end
	local allocatedWidths = Compose.formula(function(use: ComposeTypes.Use): { [string]: number }
		local filled = use(fillWidth)
		local offer = if filled > 0 then filled else use(viewportWidth)
		if offer <= 0 then
			return {}
		end
		local result: { [string]: number } = {}
		local flexible: { CollectionTypes.TableColumn<V, K> } = {}
		local lower, columns, hidden, resized = 0, read(spec.columns, use), use(collapsed), readSource(widths, use)
		for _, column in columns do
			if not hidden[column.id] then
				local fixed = resized[column.id] or column.width
				local width = boundedWidth(column, fixed or minimumOf(column))
				result[column.id] = width
				lower += width
				if fixed == nil then
					table.insert(flexible, column)
				end
			end
		end
		local remaining = math.floor(math.max(0, offer - use(disclosureWidth) - lower))
		local primary = columns[1]
		if primary and result[primary.id] and resized[primary.id] == nil and primary.width == nil then
			local extra = math.floor(
				math.min(
					remaining,
					math.max(0, math.min(primary.maxWidth or math.huge, use(primaryNatural)) - result[primary.id])
				)
			)
			result[primary.id] += extra
			remaining -= extra
		end
		while remaining > 0 and #flexible > 0 do
			local weight = 0
			for _, column in flexible do
				weight += 1 / (1 + math.max(0, if type(column.priority) == "number" then column.priority else 0))
			end
			local spent, nextFlexible = 0, {}
			for _, column in flexible do
				local share = remaining
					/ weight
					/ (1 + math.max(0, if type(column.priority) == "number" then column.priority else 0))
				local extra =
					math.floor(math.min(share, math.max(0, (column.maxWidth or math.huge) - result[column.id])))
				result[column.id] += extra
				spent += extra
				if result[column.id] < (column.maxWidth or math.huge) then
					table.insert(nextFlexible, column)
				end
			end
			if spent <= 0 then
				for _, column in nextFlexible do
					if result[column.id] + 1 <= (column.maxWidth or math.huge) then
						result[column.id] += 1
						spent = 1
						break
					end
				end
				if spent <= 0 then
					break
				end
			end
			remaining -= spent
			flexible = nextFlexible
		end
		return result
	end)
	local function textWrap(column: CollectionTypes.TableColumn<V, K>, use: ComposeTypes.Use): boolean
		local value = column.wrap
		assert(value == nil or type(value) == "boolean", "Facet.Table column.wrap must be a boolean")
		return if value == nil then metrics.touchRows(use) else value
	end
	local function columnFrame(
		current: ComposeTypes.Readable<CollectionTypes.TableColumn<V, K>>,
		index: ComposeTypes.Readable<number>,
		content: GuiObject,
		extra: GuiObject?,
		more: GuiObject?
	): Frame
		local nativeProps: Types.FrameProps = {
			Name = current:peek().id,
			Visible = function(use: ComposeTypes.Use)
				return not use(collapsed)[use(current).id]
			end,
			LayoutOrder = index,
			BackgroundTransparency = 1,
			Size = function(use: ComposeTypes.Use)
				return D2.new(0, use(allocatedWidths)[use(current).id] or columnWidth(current, use) or 0, 1, 0)
			end,
			Host.UISizeConstraint({
				MinSize = function(use: ComposeTypes.Use)
					return V2.new(minimumOf(use(current)), 0)
				end,
				MaxSize = function(use: ComposeTypes.Use)
					return V2.new(
						math.min(use(allocatedWidths)[use(current).id] or 1000000, use(current).maxWidth or 1000000),
						1000000
					)
				end,
			}) :: ComposeTypes.Child,
			Host.UIFlexItem({
				FlexMode = function(use: ComposeTypes.Use)
					return if columnWidth(current, use) == nil then E.UIFlexMode.Fill else E.UIFlexMode.None
				end,
			}),
			content,
			extra,
			more,
		}
		return Host.Frame(nativeProps)
	end
	return {
		viewportWidth = viewportWidth,
		fillWidth = fillWidth,
		setPrimaryMeasure = function(key: K, label: TextLabel, width: number, inset: number)
			if width <= 0 then
				return
			end
			local style =
				typography(label:GetStyled("FontFace") :: Font, label:GetStyled("TextSize") :: number, unitScale:peek())
			textCache.get(contentKey(label.Text, style)).width = width
			if style == typography(font:peek(), points:peek(), unitScale:peek()) then
				setPrimaryMeasure(key, width + inset)
			end
		end,
		minimumOf = minimumOf,
		collapsed = collapsed,
		disclosureWidth = disclosureWidth,
		disclosureShare = disclosureShare,
		narrowest = narrowest,
		textWrap = textWrap,
		columnFrame = columnFrame,
	}
end
