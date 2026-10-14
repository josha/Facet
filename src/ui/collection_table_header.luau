--!strict
local activation = require("./activation")
local scrollLock = require("./scroll_lock")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local CollectionTypes = require("./collection_types")
local InputProps = require("./input_props")
local Metrics = require("./collection_table_metrics")
local Columns = require("./collection_table_columns")
return function<V, K>(
	ctx: Types.Context,
	UI: { Button: Types.Constructor<InputProps.ButtonProps, TextButton> },
	spec: CollectionTypes.TableShape<V, K>,
	sort: ComposeTypes.Cell<CollectionTypes.Sort?>,
	widths: ComposeTypes.Cell<{ [string]: number }>,
	headerMeasures: ComposeTypes.Cell<{ [string]: number }>,
	metrics: Metrics.Metrics,
	layout: Columns.Columns<V, K>
): ComposeTypes.Directive
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local read = ctx.read
	local readSource = ctx.readSource
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local input, preferredInput, recordHeight = metrics.input, metrics.preferredInput, metrics.recordHeight
	local minimumOf, columnFrame = layout.minimumOf, layout.columnFrame
	local function setWidths(value: { [string]: number }): ()
		if spec.onWidthsChange then
			spec.onWidthsChange(value)
		else
			widths:set(value)
		end
	end
	local headerCells = Compose.keyed({
		from = function(use: ComposeTypes.Use)
			return read(spec.columns, use)
		end,
		key = function(column: CollectionTypes.TableColumn<V, K>)
			return column.id
		end,
		render = function(
			current: ComposeTypes.Readable<CollectionTypes.TableColumn<V, K>>,
			index: ComposeTypes.Readable<number>
		)
			local column = current:peek()
			local buttonProps: InputProps.ButtonProps = {
				Name = "Sort",
				Size = D2.fromScale(1, 1),
				AutomaticSize = E.AutomaticSize.None,
				TextXAlignment = function(use: ComposeTypes.Use)
					local align = use(current).align or "start"
					return if align == "end"
						then E.TextXAlignment.Right
						elseif align == "center" then E.TextXAlignment.Center
						else E.TextXAlignment.Left
				end,
				label = function(use: ComposeTypes.Use): string
					local value, order = use(current), readSource(sort, use)
					local suffix = if order and order.column == value.id
						then (if order.direction == "descending" then " ↓" else " ↑")
						else ""
					return tostring(read(value.label or value.id, use)) .. suffix
				end,
				enabled = function(use: ComposeTypes.Use): boolean
					return use(current).sortable ~= false
				end,
				onActivate = function()
					if column.sortable == false then
						return
					end
					local order = readSource(sort)
					local descending = order and order.column == column.id and order.direction == "ascending"
					local nextSort: CollectionTypes.Sort = {
						column = column.id,
						direction = if descending then "descending" else "ascending",
					}
					if spec.onSortChange then
						spec.onSortChange(nextSort)
					else
						sort:set(nextSort)
					end
				end,
			}
			local button = ctx.styled(UI.Button(buttonProps), "TableHeading")
			local frame: Frame
			local resizeUnit: ComposeTypes.Readable<number>
			local grip: TextButton?
			local minimum = Compose.formula(function(use)
				local value = use(current)
				return if value.width ~= nil then value.minWidth or 48 else minimumOf(value)
			end)
			if column.resizable ~= false then
				local startingPosition, startingWidth = 0, 0
				local releaseScrollers: (() -> ())? = nil
				local function finishResize()
					if releaseScrollers then
						releaseScrollers()
						releaseScrollers = nil
					end
				end
				Compose.cleanup(finishResize)
				if input then
					runtime.connect(input, "WindowFocusReleased", finishResize)
				end
				local gripProps: Types.TextButtonProps = {
					Name = "Resize",
					Text = "",
					Attributes = {
						AccessibleLabel = (function(use: ComposeTypes.Use): string
							local value = use(current)
							return "Resize " .. tostring(read(value.label or value.id, use))
						end) :: Types.Value<Types.AttributeValue?>,
					},
					Selectable = function(use: ComposeTypes.Use)
						return not (preferredInput ~= nil and use(preferredInput) == E.PreferredInput.Gamepad)
					end,
					AnchorPoint = V2.new(0.5, 0),
					Position = D2.fromScale(1, 0),
					Size = function(use: ComposeTypes.Use)
						return D2.new(
							0,
							if preferredInput and use(preferredInput) == E.PreferredInput.Touch then 44 else 12,
							1,
							0
						)
					end,
					BackgroundTransparency = 1,
					ZIndex = 3,
					Host.UIDragDetector({
						Enabled = function(use: ComposeTypes.Use): boolean
							return not (preferredInput ~= nil and use(preferredInput) == E.PreferredInput.Gamepad)
						end,
						DragStyle = E.UIDragDetectorDragStyle.TranslateLine,
						DragAxis = V2.new(1, 0),
						ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
						DragStart = function(position)
							startingPosition, startingWidth = position.X, frame.AbsoluteSize.X / resizeUnit:peek()
							finishResize()
							releaseScrollers = scrollLock.holdOwnedAncestors(frame)
						end,
						DragContinue = function(position)
							local value = current:peek()
							local nextWidths = table.clone(readSource(widths))
							nextWidths[value.id] = math.clamp(
								startingWidth + (position.X - startingPosition) / resizeUnit:peek(),
								minimum:peek(),
								value.maxWidth or 1000000
							)
							setWidths(nextWidths)
						end,
						DragEnd = finishResize,
					}),
				}
				grip = Host.TextButton(gripProps)
			end
			frame = ctx.styled(columnFrame(current, index, button, grip), "TableHeader")
			runtime.decorate(frame, {
				ZIndex = function(use: ComposeTypes.Use)
					return #read(spec.columns, use) - use(index) + 1
				end,
			})
			resizeUnit = ctx.layoutUnit(frame)
			Compose.cleanup((runtime.mount(function()
				return ctx.styled(
					Host.Frame({
						Name = "ColumnDivider",
						AnchorPoint = V2.new(0, 0.5),
						Position = D2.fromScale(0, 0.5),
						Size = function(use: ComposeTypes.Use)
							return D2.new(0, ctx.metric("strokes.hairline", use), 0.6, 0)
						end,
						Visible = function(use: ComposeTypes.Use)
							return use(index) > 1
						end,
						ZIndex = 2,
					}),
					"divider"
				)
			end, frame)))
			recordHeight(headerMeasures, column.id, button, 16)
			if grip then
				local selected = Compose.cell(false)
				runtime.connect(grip, "SelectionGained", function()
					selected:set(true)
				end)
				runtime.connect(grip, "SelectionLost", function()
					selected:set(false)
				end)
				local function adjust(delta: number): ()
					local value = current:peek()
					local nextWidths = table.clone(readSource(widths))
					nextWidths[value.id] = math.clamp(
						(nextWidths[value.id] or frame.AbsoluteSize.X / resizeUnit:peek()) + delta,
						minimum:peek(),
						value.maxWidth or 1000000
					)
					setWidths(nextWidths)
				end
				ctx.action(grip, "NarrowColumn", { E.KeyCode.Left, E.KeyCode.DPadLeft }, selected, function()
					adjust(-8)
				end, { priority = 300, capture = true })
				ctx.action(grip, "WidenColumn", { E.KeyCode.Right, E.KeyCode.DPadRight }, selected, function()
					adjust(8)
				end, { priority = 300, capture = true })
				local heading = Compose.cell(false)
				runtime.connect(button, "SelectionGained", function()
					heading:set(true)
				end)
				runtime.connect(button, "SelectionLost", function()
					heading:set(false)
				end)
				local function engaged(use: ComposeTypes.Use): boolean
					return use(selected) or use(heading)
				end
				ctx.action(grip, "NarrowColumnKey", { E.KeyCode.Comma, E.KeyCode.ButtonL1 }, engaged, function()
					adjust(-8)
				end, { priority = 300 })
				ctx.action(grip, "WidenColumnKey", { E.KeyCode.Period, E.KeyCode.ButtonR1 }, engaged, function()
					adjust(8)
				end, { priority = 300 })
				ctx.action(
					grip,
					"SortColumn",
					{ E.KeyCode.Up, E.KeyCode.Down, E.KeyCode.DPadUp, E.KeyCode.DPadDown },
					selected,
					function()
						activation.trigger(button)
					end,
					{ priority = 300, capture = true }
				)
				ctx.action(grip, "ReleaseColumn", { E.KeyCode.Escape, E.KeyCode.ButtonB }, selected, function()
					local gui = ctx.config.guiService
					if gui then
						gui.SelectedObject = button
					end
				end, { priority = 300 })
			end
			return frame
		end,
	})
	return headerCells
end
