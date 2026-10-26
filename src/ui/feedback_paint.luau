--!strict
local Types = require("./types")
local ComposeTypes = require("../vendor/compose/core")
local decoration = require("./native_decoration")

return function(
	ctx: Types.Context,
	node: GuiObject,
	scale: UIScale,
	geometry: { Size: Types.Input<UDim2>?, AutomaticSize: Types.Input<Enum.AutomaticSize>?, reflow: boolean? }
)
	local Compose, runtime, Host = ctx.Compose, ctx.runtime, ctx.Host
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local size, automatic = node.Size, node.AutomaticSize
	local measured = ctx.layoutSize(node, ctx.layoutUnit(node, "FeedbackUnit"))
	local measurement = node:FindFirstChild("FeedbackUnit")
	local factor = ctx.observe.Scale(scale)
	local natural = Compose.cell(V2.zero)
	local painted: ComposeTypes.ReadOnlyValue<Vector2>? = nil
	local dressed = Compose.cell(false)
	local function axes(use: ComposeTypes.Use): (boolean, boolean)
		local value = ctx.read(geometry.AutomaticSize, use) or automatic
		return value == E.AutomaticSize.X or value == E.AutomaticSize.XY,
			value == E.AutomaticSize.Y or value == E.AutomaticSize.XY
	end
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
			local base = ctx.read(geometry.Size, use) or size
			if not moving(use) then
				return base
			end
			local rest = use(natural)
			if not geometry.reflow then
				return D2.fromOffset(math.ceil(rest.X), math.ceil(rest.Y))
			end
			local observed = if painted and use(dressed) then use(painted) else rest
			local extent = V2.new(math.max(observed.X, rest.X), math.max(observed.Y, rest.Y))
			local x, y = axes(use)
			return D2.new(
				if x then 0 else base.X.Scale,
				if x then math.ceil(math.max(base.X.Offset, extent.X)) else base.X.Offset,
				if y then 0 else base.Y.Scale,
				if y then math.ceil(math.max(base.Y.Offset, extent.Y)) else base.Y.Offset
			)
		end,
		AutomaticSize = function(use: ComposeTypes.Use): Enum.AutomaticSize
			return if moving(use) then E.AutomaticSize.None else ctx.read(geometry.AutomaticSize, use) or automatic
		end,
	})
	Compose.cleanup(function()
		node.Size = ctx.read(geometry.Size) or size
		node.AutomaticSize = ctx.read(geometry.AutomaticSize) or automatic
	end)
	local paintProps: Types.TextLabelNativeProps = {
		Name = "FeedbackPaint",
		Size = if geometry.reflow
			then function(use: ComposeTypes.Use): UDim2
				local x, y = axes(use)
				return D2.fromScale(if x then 0 else 1, if y then 0 else 1)
			end
			else D2.fromScale(1, 1),
		AnchorPoint = V2.new(0.5, 0.5),
		Position = D2.fromScale(0.5, 0.5),
		AutomaticSize = if geometry.reflow then geometry.AutomaticSize or automatic else E.AutomaticSize.None,
		Visible = false,
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
	if geometry.reflow then
		painted = ctx.layoutSize(paint)
	end
	local boundary = decoration(Compose, runtime, ctx.types, node, paint, { immediate = true })
	runtime.mount(function()
		return if geometry.reflow then Host.Folder "FeedbackLayer" { boundary } else boundary
	end, node)
	runtime.mountFragment(function()
		return {
			Compose.show(moving, function()
				local worn: { [string]: boolean } = {}
				Compose.watch(function(use: ComposeTypes.Use)
					use(factor)
					local current: { [string]: boolean } = {}
					for _, tag in node:GetTags() do
						current[tag] = true
						if not worn[tag] then
							paint:AddTag(tag)
						end
					end
					for tag in worn do
						if not current[tag] then
							paint:RemoveTag(tag)
						end
					end
					worn = current
				end)
				Compose.cleanup(function()
					for tag in worn do
						paint:RemoveTag(tag)
					end
				end)
				local unmount: (() -> ())? = nil
				local function dress()
					paint.Visible = true
					dressed:set(true)
					unmount = runtime.mountFragment(function()
						local children = node:GetChildren()
						local selected = if ctx.config.guiService then ctx.config.guiService.SelectedObject else nil
						for _, child in children do
							if
								child ~= boundary
								and child ~= measurement
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
						) :: { [string]: (Instance) -> ComposeTypes.Value<UDim> }
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
							local currentSelection = if ctx.config.guiService
								then ctx.config.guiService.SelectedObject
								else nil
							for _, child in children do
								if child.Parent == paint then
									child.Parent = node
								end
							end
							if currentSelection and ctx.config.guiService then
								ctx.config.guiService.SelectedObject = currentSelection
							end
						end)
						return { Host.UIGradient "FeedbackMask" { Transparency = ctx.types.NumberSequence.new(1) } }
					end, node)
				end
				local frames = ctx.config.services.RunService
				local connection: RBXScriptConnection? = nil
				if frames then
					connection = frames.Heartbeat:Connect(function()
						if connection then
							connection:Disconnect()
							connection = nil
						end
						dress()
					end)
				else
					dress()
				end
				Compose.cleanup(function()
					if connection then
						connection:Disconnect()
					end
					if unmount then
						unmount()
					end
					paint.Visible = false
					dressed:set(false)
				end)
				return Compose.fragment(function()
					return {}
				end)
			end),
		}
	end, node)
end
