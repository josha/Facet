--!strict
local Types = require("./types")
local ComposeTypes = require("../vendor/compose/core")
local decoration = require("./native_decoration")

local function materialize(
	ctx: Types.Context,
	panel: GuiObject,
	geometry: { Size: Types.Value<UDim2>?, AutomaticSize: Types.Value<Enum.AutomaticSize>? },
	scale: (ComposeTypes.Use) -> number,
	pivot: ((ComposeTypes.Use) -> Vector2)?,
	paintOnly: boolean?,
	supplied: ComposeTypes.Readable<Vector2>?
)
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	if paintOnly then
		local measured = supplied or ctx.layoutSize(panel)
		local natural = Compose.cell(V2.zero)
		local background = panel.BackgroundTransparency
		local function moving(use: ComposeTypes.Use): boolean
			return scale(use) ~= 1 and use(natural).X > 0 and use(natural).Y > 0
		end
		Compose.watch(function(use: ComposeTypes.Use)
			local size = use(measured)
			if scale(use) == 1 or natural:peek().X <= 0 or natural:peek().Y <= 0 then
				natural:set(size)
			end
		end)
		runtime.decorate(panel, {
			Size = function(use: ComposeTypes.Use): UDim2
				local size = use(natural)
				return if moving(use) then D2.fromOffset(size.X, size.Y) else ctx.read(geometry.Size, use)
			end,
			AutomaticSize = function(use: ComposeTypes.Use): Enum.AutomaticSize
				return if moving(use)
					then E.AutomaticSize.None
					else ctx.read(geometry.AutomaticSize, use) or E.AutomaticSize.None
			end,
			BackgroundTransparency = function(use: ComposeTypes.Use): number
				return if moving(use) then 1 else background
			end,
		})
		runtime.mountFragment(function()
			return {
				Compose.show(moving, function()
					local parent = panel:FindFirstChild("Fade") or panel
					local children = parent:GetChildren()
					local function origin(use: ComposeTypes.Use): Vector2
						return if pivot then pivot(use) else V2.new(0.5, 0.5)
					end
					local paint = Host.Frame "PresentationPaint" {
						BackgroundColor3 = ctx.observeStyled.BackgroundColor3(panel),
						BackgroundTransparency = background,
						BorderSizePixel = panel.BorderSizePixel,
						ClipsDescendants = true,
						Size = D2.fromScale(1, 1),
						AnchorPoint = origin,
						Position = function(use: ComposeTypes.Use): UDim2
							local at = origin(use)
							return D2.fromScale(at.X, at.Y)
						end,
					}
					local corner = panel:FindFirstChildWhichIsA("UICorner")
					if corner then
						runtime.mount(function()
							return Host.UICorner { CornerRadius = ctx.observeStyled.CornerRadius(corner) }
						end, paint)
					end
					local padding = panel:FindFirstChildWhichIsA("UIPadding")
					local observePadding = (
						ctx.observeStyled :: unknown
					) :: { [string]: (Instance) -> ComposeTypes.Cell<UDim> }
					if padding then
						runtime.mount(function()
							return Host.UIPadding {
								PaddingLeft = observePadding.PaddingLeft(padding),
								PaddingRight = observePadding.PaddingRight(padding),
								PaddingTop = ctx.observeStyled.PaddingTop(padding),
								PaddingBottom = ctx.observeStyled.PaddingBottom(padding),
							}
						end, paint)
					end
					local selected = if ctx.config.guiService then ctx.config.guiService.SelectedObject else nil
					for _, child in children do
						if
							(
								child:IsA("GuiObject")
								and not string.match(child.Name, "Boundary$")
								and child.Name ~= "ChromeShadow"
							) or child:IsA("UIGridStyleLayout")
						then
							(child :: Instance).Parent = paint
						end
					end
					local boundary = decoration(Compose, runtime, ctx.types, panel, paint)
					runtime.mount(function()
						return boundary
					end, parent)
					runtime.mount(function()
						return Host.UISizeConstraint "PresentationSlotBounds" { MinSize = natural, MaxSize = natural }
					end, panel)
					materialize(ctx, paint, { Size = D2.fromScale(1, 1) }, scale, pivot, false, natural)
					if selected and ctx.config.guiService then
						ctx.config.guiService.SelectedObject = selected
					end
					Compose.cleanup(function()
						local destination = boundary.Parent or panel
						for _, child in children do
							if child.Parent and child:IsDescendantOf(paint) then
								child.Parent = destination
							end
						end
						if selected and selected.Parent and ctx.config.guiService then
							ctx.config.guiService.SelectedObject = selected
						end
					end)
					return Compose.fragment(function()
						return {}
					end)
				end),
			}
		end, panel)
		return
	end
	local measured = supplied or ctx.layoutSize(panel)
	local clips = panel.ClipsDescendants
	local natural = Compose.cell(V2.zero)
	local function moving(use: ComposeTypes.Use): boolean
		return scale(use) ~= 1 and use(natural).X > 0 and use(natural).Y > 0
	end
	Compose.watch(function(use: ComposeTypes.Use)
		local size = use(measured)
		if scale(use) == 1 or natural:peek().X <= 0 or natural:peek().Y <= 0 then
			natural:set(size)
		end
	end)
	local function origin(use: ComposeTypes.Use): Vector2
		return if pivot then pivot(use) else V2.new(0.5, 0.5)
	end
	runtime.decorate(panel, {
		ClipsDescendants = function(use: ComposeTypes.Use)
			return clips or moving(use)
		end,
		Size = function(use: ComposeTypes.Use)
			local size = use(natural) * scale(use)
			return if moving(use) then D2.fromOffset(size.X, size.Y) else ctx.read(geometry.Size, use)
		end,
		AutomaticSize = function(use: ComposeTypes.Use)
			return if moving(use)
				then E.AutomaticSize.None
				else ctx.read(geometry.AutomaticSize, use) or E.AutomaticSize.None
		end,
	})
	local function keepSelection(move: () -> ())
		local gui = ctx.config.guiService
		local selected = if gui then gui.SelectedObject else nil
		move()
		if gui and selected and gui.SelectedObject ~= selected and selected:IsDescendantOf(panel) then
			gui.SelectedObject = selected
		end
	end
	runtime.mountFragment(function()
		return {
			Compose.show(moving, function()
				local suspended = {}
				local _, holder = runtime.mount(function()
					return Host.Folder "PresentationConstraints" {}
				end, panel)
				for _, child in panel:GetChildren() do
					if child:IsA("UISizeConstraint") then
						table.insert(suspended, child)
						child.Parent = holder :: Instance
					end
				end
				runtime.mount(function()
					local function extent(use: ComposeTypes.Use): Vector2
						return use(natural) * scale(use)
					end
					return Host.UISizeConstraint "PresentationBounds" { MinSize = extent, MaxSize = extent }
				end, panel)
				Compose.cleanup(function()
					for _, child in suspended do
						if child.Parent == holder then
							child.Parent = panel
						end
					end
				end)
				local parent = panel:FindFirstChild("Fade") or panel
				local children = parent:GetChildren()
				local padding = panel:FindFirstChildWhichIsA("UIPadding")
				local sides = {}
				if padding then
					for _, side in { "Left", "Right", "Top", "Bottom" } do
						sides[side] = padding:GetStyled("Padding" .. side) :: UDim
					end
				end
				local stop, made = runtime.mount(function()
					local function contentSize(use: ComposeTypes.Use): Vector2
						local size = use(natural)
						local function inset(side: string, length: number): number
							local value = sides[side]
							return if value then value.Offset + value.Scale * length else 0
						end
						return V2.new(
							math.max(0, size.X - inset("Left", size.X) - inset("Right", size.X)),
							math.max(0, size.Y - inset("Top", size.Y) - inset("Bottom", size.Y))
						)
					end
					return Host.Frame "PresentationContent" {
						Host.UISizeConstraint { MinSize = contentSize, MaxSize = contentSize },
						BackgroundTransparency = 1,
						Size = function(use: ComposeTypes.Use)
							local size = contentSize(use)
							return D2.fromOffset(size.X, size.Y)
						end,
						AnchorPoint = origin,
						Position = function(use: ComposeTypes.Use)
							local at = origin(use)
							return D2.fromScale(at.X, at.Y)
						end,
					}
				end, parent)
				local content = made :: Frame
				local function freeze(group: Instance)
					if not group:IsA("CanvasGroup") then
						return
					end
					local size, automatic = group.Size, group.AutomaticSize
					runtime.decorate(group, {
						Size = function(use: ComposeTypes.Use)
							return if moving(use) then content.Size else size
						end,
						AutomaticSize = function(use: ComposeTypes.Use)
							return if moving(use) then E.AutomaticSize.None else automatic
						end,
						AnchorPoint = origin,
						Position = function(use: ComposeTypes.Use)
							local at = origin(use)
							return D2.fromScale(at.X, at.Y)
						end,
					})
				end
				freeze(parent)
				runtime.connect(panel, "ChildAdded", function(child: Instance)
					if child.Name == "Fade" then
						freeze(child)
					end
				end)
				keepSelection(function()
					for _, child in children do
						if
							(
								child:IsA("GuiObject")
								and not string.match(child.Name, "Boundary$")
								and child.Name ~= "ChromeShadow"
							) or child:IsA("UIGridStyleLayout")
						then
							(child :: Instance).Parent = content
						end
					end
				end)
				Compose.cleanup(function()
					keepSelection(function()
						for _, child in content:GetChildren() do
							(child :: Instance).Parent = content.Parent
						end
					end)
					stop()
				end)
				return Compose.fragment(function()
					return {}
				end)
			end),
		}
	end, panel)
end

return materialize
