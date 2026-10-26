--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local CollectionTypes = require("./collection_types")
local CELL_PADDING = 16
export type Metrics = {
	cellPadding: number,
	input: UserInputService?,
	preferredInput: ComposeTypes.ReadOnlyValue<Enum.PreferredInput>?,
	touchRows: (ComposeTypes.Use) -> boolean,
	minimumRow: ComposeTypes.Value<number>,
	toolbarShown: (ComposeTypes.Use) -> boolean,
	toolbarHeight: ComposeTypes.Value<number>,
	headerHeight: ComposeTypes.Value<number>,
	topHeight: ComposeTypes.Value<number>,
	recordHeight: (ComposeTypes.Value<{ [string]: number }>, string, TextLabel | TextButton, number) -> (),
	textInsets: TextLabel,
	textInsetSize: ComposeTypes.Value<Vector2>,
}
return function<V, K>(
	ctx: Types.Context,
	spec: CollectionTypes.TableShape<V, K>,
	ownsToggle: boolean,
	unitScale: ComposeTypes.Value<number>,
	headerMeasures: ComposeTypes.Value<{ [string]: number }>
): Metrics
	local Compose = ctx.Compose
	local read = ctx.read
	local D2, E = ctx.types.UDim2, ctx.types.Enum
	local input = ctx.config.userInputService
	local preferredInput: ComposeTypes.ReadOnlyValue<Enum.PreferredInput>? = if input
		then ctx.observe.PreferredInput(input)
		else nil
	local tenFoot = ctx.tenFoot()
	local function touchRows(use: ComposeTypes.Use): boolean
		return preferredInput ~= nil and use(preferredInput) == E.PreferredInput.Touch
	end
	local function lineBox(use: ComposeTypes.Use): number
		return math.ceil(ctx.metric("typography.body.size", use) * ctx.metric("typography.body.lineHeight", use))
	end

	local minimumRow = Compose.formula(function(use: ComposeTypes.Use)
		if spec.itemSize ~= nil then
			return read(spec.itemSize, use)
		end
		if touchRows(use) then
			local lines = 1
			for _, column in read(spec.columns, use) do
				if column.render == nil and column.wrap ~= false then
					lines = 2
				end
			end
			return math.max(ctx.metric("targetSizes.minimum", use), lines * lineBox(use) + CELL_PADDING)
		end
		if tenFoot(use) then
			return math.max(ctx.controlSize("large", "height", use), lineBox(use) + CELL_PADDING)
		end
		local kind = if preferredInput then use(preferredInput) else nil
		return math.max(40, ctx.controlSize(nil, "height", use), if kind == E.PreferredInput.Gamepad then 44 else 0)
	end)
	local function coarse(use: ComposeTypes.Use): boolean
		local kind = if preferredInput then use(preferredInput) else nil
		return kind == E.PreferredInput.Touch or kind == E.PreferredInput.Gamepad
	end
	local mouse = if input then ctx.observe.MouseEnabled(input) else nil
	local keyboard = if input then ctx.observe.KeyboardEnabled(input) else nil
	local function toolbarShown(use: ComposeTypes.Use): boolean
		local keysOnly = spec.reorderable == true
			and keyboard ~= nil
			and use(keyboard) == true
			and mouse ~= nil
			and use(mouse) == false
		return ownsToggle and (coarse(use) or keysOnly)
	end
	local toolbarHeight = Compose.formula(function(use: ComposeTypes.Use)
		return if toolbarShown(use)
			then math.max(ctx.controlSize(nil, "height", use), 44) + ctx.metric("space.s", use)
			else 0
	end)
	local headerHeight = Compose.formula(function(use: ComposeTypes.Use)
		if spec.header == false then
			return 0
		end
		local size = read(spec.headerHeight, use) or 40
		if coarse(use) then
			size = math.max(size, 44)
		end
		for _, column in read(spec.columns, use) do
			size = math.max(size, use(headerMeasures)[column.id] or 0)
		end
		return size
	end)
	local topHeight = Compose.formula(function(use: ComposeTypes.Use)
		return use(toolbarHeight) + use(headerHeight)
	end)
	local function recordHeight(
		cell: ComposeTypes.Value<{ [string]: number }>,
		id: string,
		node: TextLabel | TextButton,
		extra: number
	): ()
		local observed: ComposeTypes.ReadOnlyValue<Vector2> = if node:IsA("TextLabel")
			then ctx.observe.TextBounds(node)
			else ctx.observe.TextBounds(node)
		local text = ctx.observe.Text(node)
		Compose.watch(function(use: ComposeTypes.Use)
			local bounds = use(observed)
			local height = bounds.Y / use(unitScale) + extra
			if (bounds.Y > 0 or use(text) == "") and cell:peek()[id] ~= height then
				local nextHeights = table.clone(cell:peek())
				nextHeights[id] = height
				cell:set(nextHeights)
			end
		end)
	end
	local textInsets = ctx.styled(
		ctx.text({
			Name = "CellTextInsets",
			Text = "",
			TextTransparency = 1,
			Interactable = false,
			TextWrapped = false,
			TextTruncate = E.TextTruncate.None,
			Size = D2.fromOffset(0, 0),
			AutomaticSize = E.AutomaticSize.XY,
		}),
		"TableValue"
	)
	local textInsetSize = ctx.observe.AbsoluteSize(textInsets)
	return {
		cellPadding = CELL_PADDING,
		input = input,
		preferredInput = preferredInput,
		touchRows = touchRows,
		minimumRow = minimumRow,
		toolbarShown = toolbarShown,
		toolbarHeight = toolbarHeight,
		headerHeight = headerHeight,
		topHeight = topHeight,
		recordHeight = recordHeight,
		textInsets = textInsets,
		textInsetSize = textInsetSize,
	}
end
