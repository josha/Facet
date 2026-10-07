--!strict
local Types = require("./types")
local ComposeTypes = require("../vendor/compose/core")

return function(
	ctx: Types.Context,
	panel: GuiObject,
	geometry: { Size: Types.Value<UDim2>?, AutomaticSize: Types.Value<Enum.AutomaticSize>? },
	scale: (ComposeTypes.Use) -> number,
	pivot: ((ComposeTypes.Use) -> Vector2)?
)
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local measured = ctx.layoutSize(panel)
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
					return Host.Frame "PresentationContent" {
						BackgroundTransparency = 1,
						Size = function(use: ComposeTypes.Use)
							local size = use(natural)
							local function inset(side: string, length: number): number
								local value = sides[side]
								return if value then value.Offset + value.Scale * length else 0
							end
							return D2.fromOffset(
								math.max(0, size.X - inset("Left", size.X) - inset("Right", size.X)),
								math.max(0, size.Y - inset("Top", size.Y) - inset("Bottom", size.Y))
							)
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
