--!strict
local Types = require("./types")
local ComposeTypes = require("../vendor/compose/core")
local decoration = require("./native_decoration")

return function(
	ctx: Types.Context,
	node: GuiObject,
	scale: UIScale,
	geometry: { Size: Types.Value<UDim2>?, AutomaticSize: Types.Value<Enum.AutomaticSize>? }
)
	local Compose, runtime, Host = ctx.Compose, ctx.runtime, ctx.Host
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local size, automatic = node.Size, node.AutomaticSize
	local measured = ctx.layoutSize(node, ctx.layoutUnit(node, "FeedbackUnit"))
	local factor = ctx.observe.Scale(scale)
	local natural = Compose.cell(V2.zero)
	local function moving(use: ComposeTypes.Use): boolean
		return use(factor) ~= 1 and use(natural).X > 0 and use(natural).Y > 0
	end
	Compose.watch(function(use: ComposeTypes.Use)
		local extent = use(measured)
		if use(factor) == 1 then
			natural:set(extent)
		end
	end)
	runtime.decorate(node, {
		Size = function(use: ComposeTypes.Use): UDim2
			local extent = use(natural)
			return if moving(use) then D2.fromOffset(extent.X, extent.Y) else ctx.read(geometry.Size, use) or size
		end,
		AutomaticSize = function(use: ComposeTypes.Use): Enum.AutomaticSize
			return if moving(use) then E.AutomaticSize.None else ctx.read(geometry.AutomaticSize, use) or automatic
		end,
	})
	local paintProps: Types.TextLabelNativeProps = {
		Name = "FeedbackPaint",
		Size = D2.fromScale(1, 1),
		AnchorPoint = V2.new(0.5, 0.5),
		Position = D2.fromScale(0.5, 0.5),
		AutomaticSize = E.AutomaticSize.None,
		Visible = moving,
		Text = "",
		scale,
	}
	for _, property in { "BackgroundColor3", "BackgroundTransparency", "BorderColor3", "BorderSizePixel", "ZIndex" } do
		((paintProps :: unknown) :: { [string]: unknown })[property] = (
			(ctx.observeStyled :: unknown) :: { [string]: (Instance) -> unknown }
		)[property](node)
	end
	if node:IsA("TextButton") or node:IsA("TextBox") then
		for _, property in
			{
				"Text",
				"TextColor3",
				"TextTransparency",
				"TextStrokeColor3",
				"TextStrokeTransparency",
				"FontFace",
				"TextSize",
				"TextXAlignment",
				"TextYAlignment",
				"TextWrapped",
				"RichText",
				"TextScaled",
				"TextTruncate",
				"LineHeight",
			}
		do
			((paintProps :: unknown) :: { [string]: unknown })[property] = (
				(ctx.observeStyled :: unknown) :: { [string]: (Instance) -> unknown }
			)[property](node)
		end
	end
	local paint = Host.TextLabel(paintProps)
	local boundary = decoration(Compose, runtime, ctx.types, node, paint)
	runtime.mount(function()
		return boundary
	end, node)
	runtime.mountFragment(function()
		return {
			Compose.show(moving, function()
				local children = node:GetChildren()
				local selected = if ctx.config.guiService then ctx.config.guiService.SelectedObject else nil
				for _, child in children do
					if
						child ~= boundary
						and (
							child:IsA("GuiObject")
							or child:IsA("UIGridStyleLayout")
							or child:IsA("UICorner")
							or child:IsA("UIStroke")
							or child:IsA("UIGradient")
							or child:IsA("UIShadow")
						)
					then
						(child :: Instance).Parent = paint
					end
				end
				if selected and ctx.config.guiService then
					ctx.config.guiService.SelectedObject = selected
				end
				local padding = node:FindFirstChildWhichIsA("UIPadding")
				local observePadding = (
					ctx.observeStyled :: unknown
				) :: { [string]: (Instance) -> ComposeTypes.Cell<UDim> }
				if padding then
					runtime.mount(function()
						return Host.UIPadding({
							PaddingLeft = observePadding["PaddingLeft"](padding),
							PaddingRight = observePadding["PaddingRight"](padding),
							PaddingTop = observePadding["PaddingTop"](padding),
							PaddingBottom = observePadding["PaddingBottom"](padding),
						})
					end, paint)
				end
				Compose.cleanup(function()
					for _, child in children do
						if child.Parent == paint then
							child.Parent = node
						end
					end
					if selected and ctx.config.guiService then
						ctx.config.guiService.SelectedObject = selected
					end
				end)
				return Host.UIGradient "FeedbackMask" { Transparency = ctx.types.NumberSequence.new(1) }
			end),
		}
	end, node)
end
