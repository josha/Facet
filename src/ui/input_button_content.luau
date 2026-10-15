--!strict
local inputKit = require("./input_kit")
local InputTypes = require("./input_types")
local Shared = require("./types")
local ThemeTypes = require("./theme_types")
local InputProps = require("./input_props")
local ComposeTypes = require("../vendor/compose/core")

return function(
	ctx: Shared.Context,
	kit: inputKit.Kit,
	spec: InputProps.ButtonProps,
	p: InputProps.ButtonProps,
	iconState: ComposeTypes.Cell<ThemeTypes.SkinState>?,
	bounded: boolean,
	sized: (TextLabel | TextButton) -> ()
): (boolean, ((GuiObject) -> ())?)
	local runtime, Host, read = ctx.runtime, ctx.Host, ctx.read
	local D, D2, V2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local dynamic, hasText = kit.dynamic, kit.hasText
	local icon = ctx.icon
	local fillsGlyph = false
	local markRow: ((GuiObject) -> ())? = nil
	local function listRow(
		content: { ComposeTypes.Child },
		lead: number,
		captions: { GuiObject },
		described: boolean
	): Frame
		local frame, size, mark = ctx.listRow({
			leading = table.move(content, 1, lead, 1, {}),
			captions = captions,
			trailing = table.move(content, lead + 1, #content, 1, {}),
			described = described,
			controlSize = spec.controlSize,
		})
		if spec.Size == nil then
			p.Size = size
			p.AutomaticSize = spec.AutomaticSize or E.AutomaticSize.Y
		end
		markRow = mark
		return frame
	end
	local content: { ComposeTypes.Child } = {}
	local imageCard = spec.image ~= nil
	local hugs = false
	local rungIcon: Shared.Value<UDim2>? = nil
	if spec.controlSize ~= nil then
		local function iconSide(use: ComposeTypes.Use?): UDim2
			local side = ctx.controlSize(spec.controlSize, "iconSize", use)
			return D2.fromOffset(side, side)
		end
		rungIcon = if dynamic(ctx.config.theme) or dynamic(spec.controlSize) then iconSide else iconSide()
	end
	if imageCard then
		assert(
			type(spec.imageAspectRatio or 16 / 9) == "number" and (spec.imageAspectRatio or 16 / 9) > 0,
			"Facet.Button: imageAspectRatio must be positive"
		)
		local authored = spec.Size
		local fixed = dynamic(authored)
			or (authored ~= nil and ((authored :: UDim2).Y.Scale ~= 0 or (authored :: UDim2).Y.Offset ~= 0))
		p.Size = authored or D2.fromOffset(240, 0)
		p.AutomaticSize = spec.AutomaticSize or (if fixed then E.AutomaticSize.None else E.AutomaticSize.Y)
		hugs = spec.AutomaticSize == E.AutomaticSize.Y
			or spec.AutomaticSize == E.AutomaticSize.XY
			or (spec.AutomaticSize == nil and not fixed)
		local function radius(use: ComposeTypes.Use?): number
			return if read(spec.corners, use) == "square" then 0 else ctx.metric("radii.control", use)
		end
		local live = dynamic(ctx.config.theme) or dynamic(spec.corners)
		table.insert(
			content,
			Host.Frame "Media" {
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ClipsDescendants = true,
				Size = D2.fromScale(1, 0),
				Host.ImageLabel "Image" {
					Image = spec.image,
					BackgroundTransparency = 1,
					AnchorPoint = if hugs then nil else V2.new(0.5, 0.5),
					Position = if hugs then nil else D2.fromScale(0.5, 0.5),
					Size = if not hugs
						then D2.fromScale(1, 1)
						elseif live then function(use: ComposeTypes.Use)
							return D2.new(1, 0, 1, radius(use))
						end
						else D2.new(1, 0, 1, radius()),
					ScaleType = if spec.imageFraming == "fit" then E.ScaleType.Fit else E.ScaleType.Crop,
					Host.UICorner({
						CornerRadius = if live
							then function(use: ComposeTypes.Use)
								return D.new(0, radius(use))
							end
							else D.new(0, radius()),
					}),
					if hugs
						then nil
						else Host.UIAspectRatioConstraint({
							AspectRatio = spec.imageAspectRatio or 16 / 9,
							AspectType = E.AspectType.FitWithinMaxSize,
						}),
				},
				if hugs then nil else Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
			}
		)
		if hugs then
			local media = content[1] :: Frame
			local size = ctx.layoutSize(media)
			runtime.decorate(media, {
				Size = function(use: ComposeTypes.Use): UDim2
					return D2.new(1, 0, 0, use(size).X / (spec.imageAspectRatio or 16 / 9))
				end,
			})
		end
	end
	local row: InputTypes.Row = spec.row or {}
	local leading = spec.icon or row.icon
	if leading then
		table.insert(
			content,
			icon(leading, {
				Name = "LeadingIcon",
				Size = rungIcon,
				Visible = if dynamic(leading)
					then function(use: ComposeTypes.Use): boolean
						return read(leading, use) ~= ""
					end
					else nil,
			}, iconState)
		)
	end
	local label = row.title or spec.label or (if leading then nil else spec.name) or ""
	local description = row.description or spec.subtitle or spec.hint
	local stacked = bounded and description ~= nil and not spec.row and not imageCard
	local lead = #content
	local rowCaptions: { GuiObject } = {}
	local wordless = leading ~= nil and description == nil and not dynamic(label) and label == ""
	if not (spec.shape == "circle" and spec.icon) and not wordless then
		local function caption(name: string, text: Shared.Value<string>): TextLabel
			local live = dynamic(text)
			local function words(use: ComposeTypes.Use?): string
				return read(text, use) or ""
			end
			local function shown(use: ComposeTypes.Use?): boolean
				local value = read(text, use)
				return value ~= nil and value ~= ""
			end
			local made = ctx.text({
				Name = name,
				Text = if live then words else words(),
				Visible = if live then shown else shown(),
				Size = if imageCard or stacked then D2.new(1, 0, 0, 0) else D2.fromOffset(0, 0),
				AutomaticSize = if imageCard or stacked then E.AutomaticSize.Y else E.AutomaticSize.XY,
				TextWrapped = imageCard or stacked,
			})
			if name == "Title" then
				sized(made)
				if bounded then
					made.TextTruncate = E.TextTruncate.AtEnd
					runtime.mount(function()
						return Host.UIFlexItem({ FlexMode = E.UIFlexMode.Shrink })
					end, made)
				end
			end
			return made
		end
		if spec.row then
			rowCaptions = { caption("Title", label) }
			if description then
				table.insert(rowCaptions, caption("Description", description))
			end
		else
			local function secondary(): ComposeTypes.Child
				local text = assert(description)
				if not dynamic(text) then
					return if hasText(text) then caption("Description", text) else nil
				end
				local attached = false
				return ctx.Compose.show(function(use: ComposeTypes.Use): boolean
					attached = attached or hasText(text, use)
					return attached
				end, function()
					return caption("Description", text)
				end)
			end
			local captions = if description
				then ctx.column({ caption("Title", label), secondary() }, {
					Name = "Captions",
					Size = if imageCard then D2.new(1, 0, 0, 0) else D2.fromOffset(0, 0),
					AutomaticSize = if imageCard or stacked then E.AutomaticSize.Y else E.AutomaticSize.XY,
					(if stacked then Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }) else nil) :: ComposeTypes.Child,
				})
				else caption("Title", label)
			if imageCard then
				captions:AddTag("facet-button-media-body")
			end
			table.insert(content, captions)
		end
		if row.value ~= nil then
			local value = caption("Value", row.value)
			value:AddTag("facet-secondary")
			table.insert(content, value)
		end
	end
	if spec.row and spec.onActivate and not spec.trailingIcon then
		table.insert(content, icon("chevron.trailing", { Name = "Disclosure" }, iconState))
	end
	if spec.trailingIcon then
		table.insert(content, icon(spec.trailingIcon, { Name = "TrailingIcon", Size = rungIcon }, iconState))
	end
	local contentFrame = if imageCard
		then ctx.column(content, {
			Name = "Content",
			ZIndex = 1,
			Size = if hugs then D2.fromScale(1, 0) else D2.fromScale(1, 1),
			AutomaticSize = if hugs then E.AutomaticSize.Y else E.AutomaticSize.None,
			ClipsDescendants = true,
		})
		elseif spec.row then listRow(content, lead, rowCaptions, description ~= nil)
		elseif description then ctx.row(content, {
			Name = "Content",
			ZIndex = 1,
			AnchorPoint = function(use: ComposeTypes.Use)
				return if hasText(description, use) then V2.zero else V2.new(0, 0.5)
			end,
			Position = function(use: ComposeTypes.Use)
				return if hasText(description, use) then D2.fromScale(0, 0) else D2.fromScale(0, 0.5)
			end,
			Size = if stacked
				then D2.fromScale(1, 0)
				elseif spec.TextXAlignment == nil then nil
				else function(use: ComposeTypes.Use)
					return if hasText(description, use) then D2.fromOffset(0, 0) else D2.fromScale(1, 0)
				end,
			AutomaticSize = if stacked then E.AutomaticSize.Y else nil,
		})
		else ctx.row(content, {
			Name = "Content",
			ZIndex = 1,
			Size = D2.fromScale(1, 1),
			AutomaticSize = if bounded then E.AutomaticSize.None else nil,
		})
	if not imageCard then
		local layout = assert(contentFrame:FindFirstChildWhichIsA("UIListLayout"))
		layout.VerticalAlignment = E.VerticalAlignment.Center
		if not spec.row and (not description or spec.TextXAlignment ~= nil) then
			local alignment = spec.TextXAlignment
			if alignment == nil then
				layout.HorizontalAlignment = E.HorizontalAlignment.Center
			else
				runtime.decorate(layout, {
					HorizontalAlignment = function(use: ComposeTypes.Use): Enum.HorizontalAlignment
						local value = read(alignment, use)
						return if value == E.TextXAlignment.Left
							then E.HorizontalAlignment.Left
							elseif value == E.TextXAlignment.Right then E.HorizontalAlignment.Right
							else E.HorizontalAlignment.Center
					end,
				})
			end
		end
	end
	local glyph = if leading
			and not imageCard
			and not spec.row
			and not description
		then contentFrame:FindFirstChild("LeadingIcon")
		else nil
	if glyph and spec.AutomaticSize == E.AutomaticSize.None and label == "" then
		fillsGlyph = true
		contentFrame.AutomaticSize = E.AutomaticSize.None
		local box = ctx.observe.AbsoluteSize(contentFrame)
		runtime.mount(function()
			return Host.UISizeConstraint({
				MaxSize = function(use: ComposeTypes.Use): Vector2
					local room = use(box)
					local side = math.max(1, math.min(room.X, room.Y))
					return V2.new(side, side)
				end,
			})
		end, glyph)
	end
	p[#p + 1] = contentFrame
	return fillsGlyph, markRow
end
