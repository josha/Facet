--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local Theme = require("./theme_types")
local layoutKit = require("./layout_kit")
local textMeasure = require("./text_measure")

local function attachLayout(ctx: Shared.Context, label: TextLabel | TextButton)
	local Compose, runtime, types, Host = ctx.Compose, ctx.runtime, ctx.types, ctx.Host
	local Enum, services = types.Enum, ctx.config.services
	local writable = (label :: unknown) :: { FontFace: Font, TextSize: number, AutomaticSize: Enum.AutomaticSize }
	local previousFace: Font?, previousSize: number? = nil, nil
	local frames = services.RunService
	local pending: RBXScriptConnection? = nil
	local alive = true
	local refreshing = false
	local function reflow(metrics: boolean?)
		local automatic = label.AutomaticSize
		if automatic ~= Enum.AutomaticSize.None then
			refreshing = true
			local face, points = label:GetStyled("FontFace") :: Font, label:GetStyled("TextSize") :: number
			local resetFace, resetSize =
				metrics == true and label.FontFace ~= face, metrics == true and label.TextSize ~= points
			if resetFace then
				writable.FontFace = face
			end
			if resetSize then
				writable.TextSize = points
			end
			writable.AutomaticSize = Enum.AutomaticSize.None
			writable.AutomaticSize = automatic
			if resetFace then
				label:ResetPropertyToDefault("FontFace")
			end
			if resetSize then
				label:ResetPropertyToDefault("TextSize")
			end
			refreshing = false
		end
	end
	local function deferReflow()
		if
			pending == nil
			and frames
			and alive
			and not refreshing
			and label.AutomaticSize ~= Enum.AutomaticSize.None
		then
			local function nextFrame()
				if pending then
					pending:Disconnect()
					pending = nil
				end
				reflow(true)
			end
			pending = if frames.PreRender
				then frames.PreRender:Connect(nextFrame)
				else frames.Heartbeat:Connect(nextFrame)
		end
	end
	local function refreshMetrics()
		local face, points = label:GetStyled("FontFace") :: Font, label:GetStyled("TextSize") :: number
		if alive and (face ~= previousFace or points ~= previousSize) then
			local changed = previousFace ~= nil or previousSize ~= nil
			previousFace, previousSize = face, points
			reflow()
			if changed or label.FontFace ~= face or label.TextSize ~= points then
				deferReflow()
			end
		end
	end
	local revision = Compose.cell(0)
	local size, bounds = ctx.observe.AbsoluteSize(label), ctx.observe.TextBounds(label)
	local function invalidate()
		if not refreshing then
			revision:set(revision:peek() + 1)
		end
	end
	local function styleChanged()
		if not refreshing then
			refreshMetrics()
			invalidate()
		end
	end
	local styled = label.StyledPropertiesChanged:Connect(styleChanged)
	local changed = label.Changed:Connect(function(property: string)
		if property == "FontFace" or property == "TextSize" then
			styleChanged()
		elseif property == "Text" then
			invalidate()
			if previousSize ~= nil and label.TextSize ~= previousSize then
				deferReflow()
			end
		elseif
			property == "AutomaticSize"
			or property == "Size"
			or property == "TextWrapped"
			or property == "TextTruncate"
			or property == "LineHeight"
			or property == "RichText"
		then
			invalidate()
		end
	end)
	refreshMetrics()
	Compose.watch(function(use: ComposeTypes.Use)
		use(revision)
		local box, glyph, mode = use(size), use(bounds), label.AutomaticSize
		local freeX = mode == Enum.AutomaticSize.X or mode == Enum.AutomaticSize.XY
		local freeY = mode == Enum.AutomaticSize.Y or mode == Enum.AutomaticSize.XY
		if box.X > 0 and box.Y > 0 and ((freeX and glyph.X > box.X) or (freeY and glyph.Y > box.Y)) then
			deferReflow()
		end
	end)
	if label:FindFirstChildWhichIsA("UISizeConstraint") == nil then
		local overridden = Compose.cell(false)
		local floor: UISizeConstraint? = nil
		runtime.connect(label, "ChildAdded", function(child: Instance)
			if child ~= floor and child:IsA("UISizeConstraint") then
				overridden:set(true)
			end
		end)
		runtime.mountFragment(function()
			return {
				Compose.show(function(use: ComposeTypes.Use)
					use(revision)
					return not use(overridden)
						and (
							(
								label:GetStyled("TextWrapped") == false
								and label:GetStyled("TextTruncate") == Enum.TextTruncate.None
							) or (services.TextService ~= nil and label:GetStyled("TextWrapped") == true)
						)
				end, function()
					local nativeBounds = if services.TextService
						then textMeasure.natural(ctx, label, nil, revision)
						else nil
					local unit = ctx.layoutUnit(label, "TextBoundsUnit")
					local wrappedHeight = Compose.cell(0)
					local serial, last = 0, ""
					local active = true
					if services.TextService then
						Compose.cleanup(function()
							active = false
						end)
						Compose.watch(function(use: ComposeTypes.Use)
							use(revision)
							local mode = label.AutomaticSize
							if
								label:GetStyled("TextWrapped") ~= true
								or not (mode == Enum.AutomaticSize.Y or mode == Enum.AutomaticSize.XY)
							then
								serial += 1
								last = ""
								wrappedHeight:set(0)
								return
							end
							local wide = use(size).X / use(unit)
							local padding = label:FindFirstChildWhichIsA("UIPadding")
							if padding then
								local left = padding:GetStyled("PaddingLeft") :: UDim
								local right = padding:GetStyled("PaddingRight") :: UDim
								wide -= left.Offset + right.Offset + wide * (left.Scale + right.Scale)
							end
							local text = label.Text
							local font, points, spacing =
								label:GetStyled("FontFace") :: Font,
								label:GetStyled("TextSize") :: number,
								label:GetStyled("LineHeight") :: number
							local key =
								`{wide}|{text}|{points}|{spacing}|{font.Family}|{font.Weight.Name}|{font.Style.Name}`
							if wide <= 0 or text == "" or key == last then
								return
							end
							last = key
							serial += 1
							local ticket = serial
							local params = ((Host :: unknown) :: {
								[string]: (props: { [string]: unknown }) -> Instance,
							}).GetTextBoundsParams({
								Text = text,
								Font = font,
								Size = points,
								Width = wide,
								RichText = label.RichText,
							})
							local completed = textMeasure.begin(label)
							local function measure()
								local ok, measured = pcall(function()
									return (services.TextService :: TextService):GetTextBoundsAsync(
										params :: GetTextBoundsParams
									)
								end)
								if ok and active and alive and ticket == serial and measured.Y > 0 then
									local lineCount = math.max(1, math.round(measured.Y / points))
									local inset = label:FindFirstChildWhichIsA("UIPadding")
									local vertical = if inset
										then (inset:GetStyled("PaddingTop") :: UDim).Offset + (inset:GetStyled(
											"PaddingBottom"
										) :: UDim).Offset
										else 0
									wrappedHeight:set(
										math.ceil(measured.Y + (lineCount - 1) * points * (math.max(spacing, 1) - 1))
											+ vertical
									)
								end
								completed()
							end
							if task and task.spawn then
								task.spawn(measure)
							else
								measure()
							end
						end)
					end
					local constraint = Host.UISizeConstraint "TextBoundsFloor" {}
					floor = constraint
					Compose.cleanup(function()
						floor = nil
					end)
					runtime.decorate(constraint, {
						[Compose.group({ "MaxSize", "MinSize" })] = function(use: ComposeTypes.Use): (Vector2, Vector2)
							use(revision)
							local mode, glyph, authoredSize =
								label.AutomaticSize,
								if nativeBounds then use(nativeBounds) else use(bounds) / use(unit),
								label.Size
							local freeX = mode == Enum.AutomaticSize.X or mode == Enum.AutomaticSize.XY
							local freeY = mode == Enum.AutomaticSize.Y or mode == Enum.AutomaticSize.XY
							local free = label:GetStyled("TextWrapped") == false
								and label:GetStyled("TextTruncate") == Enum.TextTruncate.None
							freeX, freeY = freeX and free, freeY and free
							freeY = freeY and (nativeBounds == nil or label:GetStyled("LineHeight") == 1)
							local known = glyph.X < math.huge
							freeX, freeY = freeX and known, freeY and known
							local x, y =
								if nativeBounds then glyph.X else math.ceil(glyph.X),
								if nativeBounds then glyph.Y else math.ceil(glyph.Y)
							local maximum = types.Vector2.new(
								if freeX
										and glyph.X > 0
										and authoredSize.X.Scale == 0
									then math.max(x, authoredSize.X.Offset)
									else math.huge,
								if freeY
										and glyph.Y > 0
										and authoredSize.Y.Scale == 0
									then math.max(y, authoredSize.Y.Offset)
									else math.huge
							)
							return maximum,
								types.Vector2.new(if freeX then x else 0, if freeY then y else use(wrappedHeight))
						end,
					})
					return constraint
				end),
			}
		end, label)
	end
	Compose.cleanup(function()
		alive = false
		styled:Disconnect()
		changed:Disconnect()

		if pending then
			pending:Disconnect()
			pending = nil
		end
	end)
end

return function(
	ctx: Shared.Context,
	config: Shared.Config,
	services: Shared.Services,
	themes: Theme.Themes,
	live: (unknown) -> boolean
)
	local Compose, runtime, types, Host = ctx.Compose, ctx.runtime, ctx.types, ctx.Host
	local Enum = types.Enum
	local layout = layoutKit.attach((ctx :: unknown) :: Shared.Context)
	function ctx.textLayout(label: TextLabel | TextButton)
		attachLayout(ctx, label)
	end
	function ctx.padding(horizontal: number, vertical: number): UIPadding
		local sides: Shared.Sides = { top = vertical, right = horizontal, bottom = vertical, left = horizontal }
		return assert(layout.insets(sides))
	end
	function ctx.round(use: ComposeTypes.Use?, radius: UDim?): UDim
		return if ctx.metric("radii.pill", use) > 0 then radius or types.UDim.new(1, 0) else types.UDim.new(0, 0)
	end
	function ctx.corner(radius: number?): UICorner
		if radius == nil then
			return Host.UICorner({})
		end
		return Host.UICorner({
			CornerRadius = function(use: ComposeTypes.Use): UDim
				return ctx.round(use, types.UDim.new(0, radius))
			end,
		})
	end
	function ctx.layoutUnit(parent: GuiBase2d, name: string?): ComposeTypes.Readable<number>
		local _, probe = runtime.mount(function()
			return Host.Frame(name or "LayoutUnit")({ Size = types.UDim2.fromOffset(100, 1), Visible = false })
		end, parent)
		local size = ctx.observe.AbsoluteSize(probe :: GuiObject)
		return Compose.formula(function(use: ComposeTypes.Use): number
			local unit = (use(size) :: Vector2).X / 100
			return if unit > 0 then unit else 1
		end)
	end
	function ctx.layoutSize(node: GuiBase2d, unit: ComposeTypes.Readable<number>?): ComposeTypes.Readable<Vector2>
		local size, unit = ctx.observe.AbsoluteSize(node), unit or ctx.layoutUnit(node)
		return Compose.formula(function(use: ComposeTypes.Use): Vector2
			return (use(size) :: Vector2) / use(unit)
		end)
	end
	function ctx.layoutBounds(
		label: TextLabel | TextButton | TextBox,
		unit: ComposeTypes.Readable<number>?
	): ComposeTypes.Readable<Vector2>
		local bounds, unit = ctx.observe.TextBounds(label), unit or ctx.layoutUnit(label)
		return Compose.formula(function(use: ComposeTypes.Use): Vector2
			return (use(bounds) :: Vector2) / use(unit)
		end)
	end
	function ctx.text(properties: Shared.TextLabelNativeProps?): TextLabel
		local native: Shared.TextLabelNativeProps = {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			Size = types.UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			TextXAlignment = Enum.TextXAlignment.Left,
		}
		local fields = (native :: unknown) :: { [unknown]: unknown }
		for key, value in ((properties or {}) :: unknown) :: { [unknown]: unknown } do
			fields[key] = value
		end
		local label = ctx.styled(Host.TextLabel(native), "Text")

		if label.AutomaticSize == Enum.AutomaticSize.None then
			local attach = Compose.bindOwner(function()
				attachLayout(ctx, label)
			end)
			local stop: ComposeTypes.Dispose?
			stop = Compose.cleanup(assert(runtime.host.observation).observeProperty(label, "AutomaticSize", function()
				if label.AutomaticSize ~= Enum.AutomaticSize.None then
					local detach = stop
					stop = nil
					if detach then
						detach()
					end
					attach()
				end
			end))
		else
			attachLayout(ctx, label)
		end

		return label
	end
	function ctx.row(children: { ComposeTypes.Child }, properties: Shared.FrameNativeProps?): Frame
		return layout.stack(children, properties, { gap = 8 }, false)
	end
	function ctx.column(children: { ComposeTypes.Child }, properties: Shared.FrameNativeProps?): Frame
		return layout.stack(children, properties, { gap = 8 }, true)
	end
	function ctx.listRow(parts: Shared.ListRow): (Frame, Shared.Value<UDim2>, (GuiObject) -> ())
		for _, caption in parts.captions do
			if caption.Name == "Description" then
				caption:AddTag("facet-secondary")
			end
			if caption:IsA("TextLabel") then
				caption.Size = types.UDim2.fromScale(1, 0)
				caption.AutomaticSize = Enum.AutomaticSize.Y
				caption.TextWrapped = true
			end
		end
		local columns: { ComposeTypes.Child } = table.clone(parts.leading or {})
		table.insert(
			columns,
			ctx.column(parts.captions, {
				Name = "Captions",
				Size = types.UDim2.new(0, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIFlexItem({ FlexMode = Enum.UIFlexMode.Fill }) :: ComposeTypes.Child,
			})
		)
		table.move(parts.trailing or {}, 1, #(parts.trailing or {}), #columns + 1, columns)
		local content = ctx.row(columns, {
			Name = "Content",
			ZIndex = 1,
			Size = types.UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			AnchorPoint = if parts.described then types.Vector2.zero else types.Vector2.new(0, 0.5),
			Position = types.UDim2.fromScale(0, if parts.described then 0 else 0.5),
		})
		assert(content:FindFirstChildWhichIsA("UIListLayout")).VerticalAlignment = Enum.VerticalAlignment.Center
		local rung: Shared.Value<Shared.ControlSize?>? = parts.controlSize
		local function height(use: ComposeTypes.Use?): UDim2
			return types.UDim2.new(1, 0, 0, ctx.controlSize(rung, "height", use))
		end
		local size = if live(config.theme) or live(rung) then height else height()
		return content,
			size,
			function(node: GuiObject)
				node:AddTag("facet-list-row")
				local captions = assert(content:FindFirstChild("Captions")) :: GuiObject
				local wraps = node.AutomaticSize
				local function hug()
					local parent = node.Parent
					local automatic = if parent and parent:IsA("GuiObject") then parent.AutomaticSize else nil
					local hugging = automatic == Enum.AutomaticSize.X or automatic == Enum.AutomaticSize.XY
					local across = if hugging then Enum.AutomaticSize.XY else Enum.AutomaticSize.Y
					node.AutomaticSize = if hugging then Enum.AutomaticSize.XY else wraps
					content.AutomaticSize, captions.AutomaticSize = across, across
					for _, caption in parts.captions do
						if caption:IsA("TextLabel") then
							caption.Size = types.UDim2.fromScale(if hugging then 0 else 1, 0)
							caption.AutomaticSize = across
						end
					end
				end
				runtime.connect(node, "AncestryChanged", hug)
				hug()
				local function tagRung(use: ComposeTypes.Use?)
					local current = ctx.read(rung, use)
					for _, name in { "xsmall", "compact", "regular", "large" } do
						if current == name then
							node:AddTag("facet-size-" .. name)
						elseif node:HasTag("facet-size-" .. name) then
							node:RemoveTag("facet-size-" .. name)
						end
					end
				end
				if live(rung) then
					Compose.watch(tagRung)
				else
					tagRung()
				end
			end
	end
	function ctx.iconVaries(name: Shared.Value<string>?): boolean
		if name == nil then
			return false
		end
		if live(name) or live(config.theme) or live(config.icons) then
			return true
		end
		local requested = name :: string
		if requested == "" or string.match(requested, "^rbx") then
			return false
		end
		local package: Theme.IconRegistry = ctx.read(config.theme) or {}
		local overrides = ctx.read(config.icons)
		if overrides then
			package = table.clone(package)
			package.icons = overrides
		end
		local resting = themes.resolveIcon(package, requested, "default")
		return themes.resolveIcon(package, requested, "hover") ~= resting
			or themes.resolveIcon(package, requested, "pressed") ~= resting
			or themes.resolveIcon(package, requested, "selected") ~= resting
			or themes.resolveIcon(package, requested, "disabled") ~= resting
	end
	function ctx.icon(
		name: Shared.Value<string>,
		properties: Shared.ImageLabelNativeProps?,
		state: Shared.Value<Theme.SkinState>?
	): ImageLabel
		local function image(use: ComposeTypes.Use?): string
			local requested = ctx.read(name, use)
			if requested == "" then
				return ""
			end
			local package: Theme.IconRegistry = ctx.read(config.theme, use) or {}
			local overrides = ctx.read(config.icons, use)
			if overrides then
				package = table.clone(package)
				package.icons = overrides
			end
			local asset = if type(requested) == "string" and string.match(requested, "^rbx")
				then requested
				else themes.resolveIcon(package, requested, ctx.read(state, use))
			assert(type(asset) == "string", `Facet icon {tostring(requested)} requires an image asset`)
			return asset
		end
		local native: Shared.ImageLabelNativeProps = {
			Image = if live(name) or live(config.theme) or live(config.icons) or live(state) then image else image(),
			BackgroundTransparency = 1,
		}
		local function iconSize(use: ComposeTypes.Use?): UDim2
			local size = ctx.controlSize(config.controlSize, "iconSize", use)
			return types.UDim2.fromOffset(size, size)
		end
		local function resample(use: ComposeTypes.Use?): Enum.ResamplerMode
			local package = ctx.read(config.theme, use)
			return if package and package.identity.rendering == "pixel"
				then Enum.ResamplerMode.Pixelated
				else Enum.ResamplerMode.Default
		end
		local themeLive = live(config.theme)
		native.Size = if themeLive or live(config.controlSize) then iconSize else iconSize()
		if themeLive then
			native.ResampleMode = resample
		elseif resample() ~= Enum.ResamplerMode.Default then
			native.ResampleMode = resample()
		end
		local fields = (native :: unknown) :: { [unknown]: unknown }
		for key, value in ((properties or {}) :: unknown) :: { [unknown]: unknown } do
			fields[key] = value
		end
		return ctx.styled(Host.ImageLabel(native), "Icon")
	end
end
