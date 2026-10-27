--!strict
local layoutKit = require("./layout_kit")
local Types = require("./types")
local Engine = require("./engine_types")
local Media = require("./media_types")
local ComposeTypes = require("../vendor/compose/core")
local decoration = require("./native_decoration")
local ControlTypes = require("./control_types")
local MediaProps = require("./media_props")
local MediaShared = require("./media_shared")

return function(ctx: Types.Context, UI: ControlTypes.Controls, shared: MediaShared.Shared)
	local Host, runtime, Compose = ctx.Host, ctx.runtime, ctx.Compose
	local lists = layoutKit.of(ctx)
	local types, read = ctx.types, ctx.read
	local E, D2, D, V2 = types.Enum, types.UDim2, types.UDim, types.Vector2
	local metric, controlSize = ctx.metric, ctx.controlSize
	local skin = shared.skin
	local function dynamic(value: unknown): boolean
		return Compose.isValue(value) or type(value) == "function"
	end
	local function statusTag(node: GuiObject, source: Types.Input<Media.Status>?)
		local previous: string?
		local function apply(use: ComposeTypes.Use?)
			local requested = read(source, use)
			local status = if requested == nil then "neutral" else requested
			assert(
				({
					neutral = true,
					info = true,
					success = true,
					warning = true,
					error = true,
					accent = true,
					voice = true,
					contrast = true,
				})[status],
				"Facet: invalid status"
			)
			if previous then
				node:RemoveTag(previous)
			end
			previous = "facet-status-" .. status
			node:AddTag(previous :: string)
		end
		if dynamic(source) then
			Compose.watch(apply)
		else
			apply()
		end
	end

	UI.Badge = ctx.construct("Badge", function(spec: MediaProps.BadgeProps): GuiObject
		assert(
			spec.iconPosition == nil or spec.iconPosition == "leading" or spec.iconPosition == "trailing",
			"Facet Badge invalid iconPosition"
		)
		local named = spec.icon ~= nil and type(spec.name) == "string" and spec.name ~= ""
		local function caption(use: ComposeTypes.Use?): string
			local value = read(spec.label, use)
			assert(value == nil or type(value) == "string", "Facet Badge label must be a string")
			return value or ""
		end
		local function height(use: ComposeTypes.Use?): UDim2
			return D2.fromOffset(0, controlSize(spec.controlSize, "iconSize", use) + 4)
		end
		local captionValue = if dynamic(spec.label) then Compose.formula(caption) else nil
		local label: Types.Input<string> = if captionValue then captionValue else caption()
		local size: Types.Input<UDim2> = if dynamic(ctx.config.theme) or dynamic(spec.controlSize)
			then height
			else height()
		assert(
			named or type(spec.label) == "function" or Compose.isValue(spec.label) or caption() ~= "",
			"Facet Badge requires meaningful text or a named icon"
		)
		local native = ctx.props(
			spec,
			{ "label", "status", "icon", "iconPosition", "name", "appearance", "corners", "controlSize", "Visible" },
			{
				Text = label,
				Attributes = { AccessibleLabel = spec.name or label },
				AutoLocalize = if dynamic(spec.label) then false else nil,
				AutomaticSize = E.AutomaticSize.XY,
				Size = size,
			}
		)
		local node = ctx.styled(Host.TextLabel(native), "text")
		if spec.icon == nil then
			Host.UIPadding({}).Parent = node
		end
		ctx.textLayout(node, true, true)
		local pill: GuiObject = node
		if spec.icon then
			node.Name = "Label"
			node.BackgroundTransparency = 1
			node.Size = D2.fromOffset(0, 0)
			local icon = ctx.icon(spec.icon, {
				Size = function(use: ComposeTypes.Use)
					local pixels = math.floor(controlSize(spec.controlSize, "iconSize", use) * 0.7 + 0.5)
					return D2.fromOffset(pixels, pixels)
				end,
			})
			local leading = spec.iconPosition ~= "trailing"
			icon.LayoutOrder = if leading then 1 else 2
			node.LayoutOrder = if leading then 2 else 1
			pill = Host.Frame({
				Name = spec.Name or "Badge",
				AutomaticSize = E.AutomaticSize.XY,
				Size = size,
				lists.list({ gap = 4, align = "center" }, false) :: ComposeTypes.Child,
				icon :: ComposeTypes.Child,
				node :: ComposeTypes.Child,
			})
		end
		local function visible(use: ComposeTypes.Use?): boolean
			return read(spec.Visible, use) ~= false
				and (named or (if captionValue then read(captionValue, use) else caption(use)) ~= "")
		end
		runtime.decorate(pill, {
			Visible = if dynamic(spec.Visible) or dynamic(spec.label) then Compose.formula(visible) else visible(),
		})
		ctx.styled(pill, "badge")
		if spec.status ~= nil then
			statusTag(pill, spec.status)
		end
		local previousAppearance: string?
		local function appearanceTag(use: ComposeTypes.Use?)
			local appearance = read(spec.appearance, use) or "standard"
			assert(
				appearance == "standard" or appearance == "status" or appearance == "utility",
				"Facet Badge invalid appearance"
			)
			if previousAppearance then
				pill:RemoveTag(previousAppearance)
			end
			previousAppearance = "facet-badge-" .. appearance
			pill:AddTag(previousAppearance :: string)
		end
		if dynamic(spec.appearance) then
			Compose.watch(appearanceTag)
		else
			appearanceTag()
		end
		if spec.appearance then
			runtime.mountFragment(function()
				return {
					Compose.show(function(use: ComposeTypes.Use)
						return read(spec.appearance, use) == "status"
					end, function()
						return UI.StatusIndicator "Status" {
							status = spec.status,
							diameter = 8,
							LayoutOrder = -1,
							Position = D2.new(0, -14, 0.5, 0),
							AnchorPoint = V2.new(0, 0.5),
						}
					end),
				}
			end, pill)
		end
		if spec.corners then
			runtime.mount(function()
				return Host.UICorner({
					CornerRadius = function(use: ComposeTypes.Use)
						local radius = read(spec.corners, use)
						if type(radius) == "string" then
							radius = ({
								square = 0,
								rounded = metric("radii.control", use),
								capsule = metric("radii.pill", use),
							})[radius]
						end
						assert(type(radius) == "number", "Facet Badge invalid corners")
						return D.new(0, radius)
					end,
				})
			end, pill)
		end
		skin(pill, "badge")
		if (pill :: Instance) == (node :: Instance) and ctx.config.theme ~= nil then
			local function needsCaption(use: ComposeTypes.Use?): boolean
				local package = read(ctx.config.theme, use)
				local recipe = package and package.chrome and package.chrome.badge
				return recipe ~= nil and recipe.kind ~= "native" and recipe.kind ~= "none"
			end
			local function lifted()
				Compose.cleanup(function()
					node:RemoveTag("facet-badge-captioned")
				end)
				local label = ctx.styled(
					ctx.text({
						Name = "Label",
						Size = D2.fromScale(1, 1),
						AutomaticSize = E.AutomaticSize.None,
						ZIndex = 1,
						Text = ctx.observe.Text(node),
						TextColor3 = ctx.observeStyled.TextColor3(node),
						FontFace = ctx.observeStyled.FontFace(node),
						TextSize = ctx.observeStyled.TextSize(node),
						TextXAlignment = ctx.observeStyled.TextXAlignment(node),
						TextYAlignment = ctx.observeStyled.TextYAlignment(node),
					}),
					"badge-caption"
				)
				local boundary = decoration(Compose, runtime, types, node, label, { inset = true })
				Compose.watch(function(use: ComposeTypes.Use)
					local visible = needsCaption(use)
					boundary.Visible = visible
					if visible then
						node:AddTag("facet-badge-captioned")
					else
						node:RemoveTag("facet-badge-captioned")
					end
				end)
				return boundary
			end
			if Compose.isValue(ctx.config.theme) or type(ctx.config.theme) == "function" then
				local attached = false
				runtime.mountFragment(function()
					return {
						Compose.show(function(use: ComposeTypes.Use)
							attached = attached or needsCaption(use)
							return attached
						end, lifted),
					}
				end, node)
			elseif needsCaption() then
				runtime.mount(lifted, node)
			end
		end
		return pill
	end)

	UI.StatusIndicator = ctx.construct("StatusIndicator", function(spec: MediaProps.StatusIndicatorProps): TextLabel
		local size = function(use: ComposeTypes.Use)
			return read(spec.diameter, use)
				or (
					if spec.controlSize
						then controlSize(spec.controlSize, "iconSize", use)
						else if spec.count ~= nil then 24 else 12
				)
		end
		local function form(use: ComposeTypes.Use): "dot" | "ring" | "square" | "dash"
			local value = read(spec.form, use) or "dot"
			assert(
				value == "dot" or value == "ring" or value == "square" or value == "dash",
				"Facet StatusIndicator invalid form"
			)
			return value
		end
		local native = ctx.props(
			spec,
			{ "status", "form", "count", "max", "name", "diameter", "controlSize", "cutout" },
			{
				Attributes = if spec.name ~= nil
					then ({ AccessibleLabel = spec.name } :: unknown) :: Engine.Attributes
					else nil,
				Size = function(use: ComposeTypes.Use)
					return D2.fromOffset(
						if spec.count ~= nil then 0 else size(use),
						if form(use) == "dash" then math.max(3, size(use) / 3) else size(use)
					)
				end,
				AutomaticSize = if spec.count ~= nil
					then (if spec.Size == nil then E.AutomaticSize.XY else E.AutomaticSize.X)
					else nil,
				Text = function(use: ComposeTypes.Use)
					local count = read(spec.count, use)
					if count == nil then
						return ""
					end
					assert(
						type(count) == "number" and count >= 0 and count < math.huge and count % 1 == 0,
						"Facet StatusIndicator count must be a nonnegative integer"
					)
					assert(
						form(use) == "dot" or form(use) == "square",
						"Facet StatusIndicator count requires dot or square"
					)
					assert(
						spec.max == nil
							or (
								type(spec.max) == "number"
								and spec.max >= 0
								and spec.max < math.huge
								and spec.max % 1 == 0
							),
						"Facet StatusIndicator max must be a nonnegative integer"
					)
					return if count > (spec.max or 99) then tostring(spec.max or 99) .. "+" else tostring(count)
				end,
				TextXAlignment = E.TextXAlignment.Center,
				Host.UICorner({
					CornerRadius = function(use: ComposeTypes.Use)
						return if form(use) == "square" then D.new(0, 0) else ctx.round(use)
					end,
				}) :: ComposeTypes.Child,
				Compose.show(function(use: ComposeTypes.Use)
					return form(use) == "ring"
				end, function()
					return ctx.styled(
						Host.UIStroke "Ring" {
							ApplyStrokeMode = E.ApplyStrokeMode.Border,
							BorderStrokePosition = E.BorderStrokePosition.Inner,
							Thickness = function(use: ComposeTypes.Use)
								return math.max(2, math.floor(size(use) / 6 + 0.5))
							end,
						},
						"status-ring"
					)
				end),
			} :: Engine.TextLabelNativeProps
		)
		if spec.count ~= nil and spec.Size == nil then
			native[#native + 1] = Host.UISizeConstraint({
				MinSize = function(use: ComposeTypes.Use)
					return V2.new(size(use), size(use))
				end,
			})
		elseif spec.count == nil then
			native[#native + 1] = Host.UIAspectRatioConstraint({
				AspectRatio = function(use: ComposeTypes.Use)
					return if form(use) == "dash" then 3 else 1
				end,
				AspectType = E.AspectType.FitWithinMaxSize,
			})
		end
		if spec.cutout then
			native[#native + 1] = ctx.styled(
				Host.UIStroke "Cutout" {
					ApplyStrokeMode = E.ApplyStrokeMode.Border,
					BorderStrokePosition = E.BorderStrokePosition.Inner,
					Thickness = 1,
				},
				"cutout"
			)
		end
		if spec.count ~= nil and spec.Size ~= nil then
			native[#native + 1] = Host.Frame "CountWidthFloor" {
				BackgroundTransparency = 1,
				Size = function(use: ComposeTypes.Use): UDim2
					local package = read(ctx.config.theme, use)
					local recipe = if package and package.chrome then package.chrome.badge else nil
					local insets = if recipe then recipe.contentInsets else nil
					local horizontal = math.max(8, if insets then insets.left or 0 else 0)
						+ math.max(8, if insets then insets.right or 0 else 0)
					local vertical = math.max(3, if insets then insets.top or 0 else 0)
						+ math.max(3, if insets then insets.bottom or 0 else 0)
					return D2.new(0, 100000, 1, vertical - horizontal)
				end,
				Host.UIAspectRatioConstraint {
					AspectRatio = 1,
					AspectType = E.AspectType.FitWithinMaxSize,
					DominantAxis = E.DominantAxis.Height,
				},
			}
			native[#native + 1] = Host.UIListLayout { HorizontalAlignment = E.HorizontalAlignment.Center }
		end
		local node = ctx.styled(Host.TextLabel(native), "text")
		ctx.styled(node, "badge")
		statusTag(node, spec.status)
		Compose.watch(function(use: ComposeTypes.Use)
			if form(use) == "ring" then
				node:AddTag("facet-status-hollow")
			elseif node:HasTag("facet-status-hollow") then
				node:RemoveTag("facet-status-hollow")
			end
		end)
		return node
	end)
end
