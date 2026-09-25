--!strict
local layoutKit = require("./layout_kit")
local reducedMotion = require("./motion")
local Types = require("./types")
local Engine = require("./engine_types")
local Media = require("./media_types")
local Theme = require("./theme_types")
local ComposeTypes = require("../vendor/compose/core")
local bindThemes = require("./themes")
local pathShapes = require("./nav_path_shapes")
export type MediaControls = Media.MediaControls

local SETTLE_SECONDS = 0.15
local VISIBLE_FRACTION = 0.5

return function(ctx: Types.Context, controls: Media.MediaControls?): Media.MediaControls
	local Host, runtime, Compose = ctx.Host, ctx.runtime, ctx.Compose
	local themes = bindThemes(Compose)
	local lists = layoutKit.of(ctx)
	local types, read = ctx.types, ctx.read
	local E, D2, D, V2 = types.Enum, types.UDim2, types.UDim, types.Vector2
	local UI: Media.MediaControls = controls or ({} :: Media.MediaControls)
	local function skin(node: GuiObject, slot: string, options: Theme.SkinOptions?): GuiObject
		local package = ctx.config.theme
		if not Compose.isReadable(package) and type(package) ~= "function" then
			local resolved = read(package)
			local recipe = if resolved then (resolved.chrome or {})[slot] else nil
			if recipe == nil or ((recipe.kind == "native" or recipe.kind == "none") and recipe.shadow == nil) then
				return node
			end
		end
		local settings: Theme.SkinOptions = options or {}
		settings.types, settings.target = types, node
		runtime.mount(function()
			return themes.skin(runtime, ctx.config.theme, slot, settings)
		end, node)
		return node
	end
	local metric, controlSize = ctx.metric, ctx.controlSize
	local function bind<T>(source: Types.Value<T>?, fallback: T): Types.Value<T>
		if not Compose.isReadable(source) and type(source) ~= "function" then
			return if source == nil then fallback else source :: T
		end
		return function(use: ComposeTypes.Use)
			local value = read(source, use)
			return if value == nil then fallback else value
		end
	end
	local function statusTag(node: GuiObject, source: Types.Value<Media.Status>?)
		local previous: string?
		Compose.watch(function(use: ComposeTypes.Use)
			local requested = read(source, use)
			local status = if requested == nil then "neutral" else requested
			assert(
				({ neutral = true, info = true, success = true, warning = true, error = true, accent = true })[status],
				"Facet: invalid status"
			)
			if previous then
				node:RemoveTag(previous)
			end
			previous = "facet-status-" .. status
			node:AddTag(previous :: string)
		end)
	end
	local function roleTag(value: string?): string
		local name = value or "body"
		assert(table.find(themes.TYPE_ROLES, name), "Facet Text invalid textRole")
		return "facet-type-" .. name
	end
	local function textRole(node: TextLabel, role: Types.Value<Media.TextRole>?): TextLabel
		if not Compose.isReadable(role) and type(role) ~= "function" then
			node:AddTag(roleTag(read(role)))
			return node
		end
		local previous: string?
		Compose.watch(function(use: ComposeTypes.Use)
			local tag = roleTag(read(role, use))
			if previous then
				node:RemoveTag(previous)
			end
			previous = tag
			node:AddTag(tag)
		end)
		return node
	end
	local function initials(name: string?): string
		local first: string?, last: string?, count = nil, nil, 0
		for word in string.gmatch(name or "", "%S+") do
			first = first or word
			last = word
			count += 1
		end
		local function character(word: string): string
			return string.sub(word, 1, (utf8.offset(word, 2) or (#word + 1)) - 1)
		end
		return if first == nil
			then ""
			elseif count == 1 then character(first)
			else character(first) .. character(last :: string)
	end

	local ELLIPSIS = "\u{2026}"
	local function middle(label: TextLabel, text: string, width: number): string
		local function fits(candidate: string): boolean
			label.Text = candidate
			return label.TextBounds.X <= width
		end
		if text == "" or width <= 0 or fits(text) then
			return text
		end
		local offsets: { number } = {}
		for position in utf8.codes(text) do
			table.insert(offsets, position)
		end
		local total = #offsets
		local function form(keep: number): string
			if keep <= 0 then
				return ELLIPSIS
			end
			local head = math.ceil(keep / 2)
			local tail = keep - head
			local headEnd = if offsets[head + 1] ~= nil then offsets[head + 1] - 1 else #text
			return string.sub(text, 1, headEnd)
				.. ELLIPSIS
				.. (if tail > 0 then string.sub(text, offsets[total - tail + 1]) else "")
		end
		local low, high, best = 0, total - 1, 0
		while low <= high do
			local keep = (low + high) // 2
			if fits(form(keep)) then
				best = keep
				low = keep + 1
			else
				high = keep - 1
			end
		end
		return form(best)
	end
	local function fitOf(value: Media.TextFit?): { cap: Media.TextFitBound?, floor: Media.TextFitBound? }?
		if value == nil then
			return nil
		end
		if value == "fit" then
			return {}
		end
		local refusal =
			'Facet Text textSize must be a size, a type role, "fit" or { fit = { cap = size, floor = size } }'
		assert(type(value) == "table" and type(value.fit) == "table", refusal)
		local band = value.fit
		for key in band :: { [unknown]: unknown } do
			assert(key == "cap" or key == "floor", "Facet Text textSize fit takes only cap and floor")
		end
		for _, bound in { band.cap, band.floor } do
			assert(
				bound == nil
					or (type(bound) == "number" and bound > 0)
					or (type(bound) == "string" and table.find(themes.TYPE_ROLES, bound) ~= nil),
				"Facet Text textSize fit cap and floor must be a positive size or a type role"
			)
		end
		return band
	end

	local TEXT_KEYS = {
		"text",
		"textRole",
		"role",
		"truncate",
		"textSize",
		"textAlign",
		"wrap",
		"rich",
		"direction",
		"tint",
	}
	local ALIGN: { [string]: Enum.TextXAlignment } = {
		start = E.TextXAlignment.Left,
		center = E.TextXAlignment.Center,
		["end"] = E.TextXAlignment.Right,
	}
	local DIRECTION: { [string]: Enum.TextDirection } = {
		auto = E.TextDirection.Auto,
		ltr = E.TextDirection.LeftToRight,
		rtl = E.TextDirection.RightToLeft,
	}
	UI.Text = ctx.construct("Text", function(spec: Media.TextProps): TextLabel
		local fields = (spec :: unknown) :: { [string]: unknown }
		for _, retired in { "color", "font" } do
			if fields[retired] ~= nil then
				error(`Facet UI.Text: {retired} is style authority. Use role or textRole.`, 0)
			end
		end
		if fields.label ~= nil or spec.Text ~= nil then
			error("Facet UI.Text: set the text with text. Remove label and Text.", 0)
		end
		local source: Types.Value<string>? = spec.text
		if not Compose.isReadable(source) and type(source) ~= "function" then
			assert(type(source) == "string", "Facet UI.Text requires text")
		end
		local truncate = spec.truncate
		assert(
			truncate == nil or truncate == "end" or truncate == "middle",
			"Facet Text truncate must be end or middle"
		)
		local cut = truncate == "middle"
		local rich = spec.rich == true or spec.RichText == true
		assert(spec.rich == nil or type(spec.rich) == "boolean", "Facet Text rich must be a boolean")
		assert(not cut or not rich, "Facet Text cannot cut rich text in the middle")
		assert(
			not cut or (spec.TextWrapped ~= true and spec.wrap ~= true),
			"Facet Text middle truncation needs one line; remove wrap"
		)
		assert(
			spec.direction == nil or DIRECTION[spec.direction] ~= nil,
			"Facet Text direction must be auto, ltr or rtl"
		)
		local size = spec.textSize
		local pixels: number? = if type(size) == "number" then size else nil
		assert(pixels == nil or (pixels > 0 and pixels < math.huge), "Facet Text textSize must be a positive size")
		local sizeRole: Media.TextRole? = nil
		if type(size) == "string" and size ~= "fit" then
			assert(
				table.find(themes.TYPE_ROLES, size) ~= nil,
				`Facet Text textSize "{size}" is not a type role; use one of {table.concat(themes.TYPE_ROLES, ", ")}`
			)
			sizeRole = size :: Media.TextRole
		end
		assert(
			sizeRole == nil or spec.textRole == nil,
			"Facet Text: set the type role one time, with textSize or textRole"
		)
		local fit = if pixels == nil and sizeRole == nil then fitOf(size :: Media.TextFit?) else nil
		local defaults: Engine.TextLabelNativeProps = {
			Text = if cut then read(source) or "" else bind(source, ""),
		}
		if rich then
			defaults.RichText = true
		end
		if pixels then
			defaults.TextSize = pixels
		end
		if spec.wrap ~= nil then
			defaults.TextWrapped = spec.wrap
		end
		if spec.direction ~= nil then
			defaults.TextDirection = DIRECTION[spec.direction]
		end
		if spec.tint ~= nil then
			defaults.TextColor3 = spec.tint :: Types.Value<Color3>
		end
		if spec.textAlign ~= nil then
			defaults.TextXAlignment = function(use: ComposeTypes.Use): Enum.TextXAlignment
				local align = read(spec.textAlign, use) or "start"
				return assert(ALIGN[align], "Facet Text textAlign must be start, center or end")
			end
		end
		if cut then
			defaults.Size = D2.fromScale(1, 0)
			defaults.AutomaticSize = E.AutomaticSize.Y
			defaults.TextWrapped = false
			defaults.TextTruncate = E.TextTruncate.None
		elseif truncate == "end" then
			defaults.TextTruncate = E.TextTruncate.AtEnd
		end
		local roleSource: Types.Value<Media.TextRole>? = sizeRole or spec.textRole
		if fit then
			local function scale(bound: Media.TextFitBound, use: ComposeTypes.Use): number
				return math.round(
					if type(bound) == "string" then metric("typography." .. bound .. ".size", use) else bound
				)
			end
			defaults.TextScaled = true
			defaults.Size = D2.fromScale(1, 1)
			defaults.AutomaticSize = E.AutomaticSize.None
			defaults[1] = Host.UITextSizeConstraint({
				MaxTextSize = function(use: ComposeTypes.Use): number
					return scale(fit.cap or read(roleSource, use) or "body", use)
				end,
				MinTextSize = function(use: ComposeTypes.Use): number
					return scale(fit.floor or "caption", use)
				end,
			})
		end
		local label = textRole(ctx.text(ctx.props(spec, TEXT_KEYS, defaults)), roleSource)
		if cut then
			local measured = ctx.observe(label, "AbsoluteSize")
			local width = Compose.formula(function(use: ComposeTypes.Use): number
				return use(measured).X
			end)
			local textSize = ctx.observe(label, "TextSize")
			local face = ctx.observe(label, "FontFace")
			local styledSize = ctx.observeStyled(label, "TextSize")
			local styledFace = ctx.observeStyled(label, "FontFace")
			Compose.watch(function(use: ComposeTypes.Use)
				local value = read(source, use) or ""
				use(textSize)
				use(face)
				use(styledSize)
				use(styledFace)
				label.Text = middle(label, value, use(width))
			end)
		end
		if spec.role ~= nil then
			Compose.watch(function(use: ComposeTypes.Use)
				local role = read(spec.role, use)
				assert(
					role == nil or role == "secondary" or role == "content",
					"Facet Text role must be secondary or content"
				)
				if role == "secondary" then
					label:AddTag("facet-secondary")
				elseif label:HasTag("facet-secondary") then
					label:RemoveTag("facet-secondary")
				end
			end)
		end
		return label
	end)

	local PRESENTATIONS = { titleAndIcon = true, titleOnly = true, iconOnly = true }
	UI.Label = ctx.construct("Label", function(spec: Media.LabelProps): Frame
		local fields = (spec :: unknown) :: { [string]: unknown }
		if fields.text ~= nil or fields.label ~= nil then
			error("Facet UI.Label: a Label is an icon and a title. Use title, or use UI.Text for plain text.", 0)
		end
		local initial = read(spec.title)
		assert(
			type(initial) == "string" and initial ~= "",
			"Facet UI.Label: title is required and must not be empty. It is the accessible name in every presentation."
		)
		local presentation = spec.presentation or "titleAndIcon"
		if not PRESENTATIONS[presentation] then
			error(`Facet UI.Label: unknown presentation '{presentation}'. Use iconOnly | titleAndIcon | titleOnly.`, 0)
		end
		assert(
			spec.iconPosition == nil or spec.iconPosition == "leading" or spec.iconPosition == "trailing",
			"Facet UI.Label: iconPosition must be leading or trailing"
		)
		local effective = if spec.icon == nil then "titleOnly" else presentation
		local icon = spec.icon
		if type(icon) == "string" and not string.match(icon, "^rbx") then
			local package: Theme.IconRegistry = read(ctx.config.theme) or {}
			local overrides = read(ctx.config.icons)
			if overrides then
				package = table.clone(package)
				package.icons = overrides
			end
			local known = themes.resolveIcon(package, icon)
			assert(known ~= nil, `Facet UI.Label: unknown icon '{icon}'.`)
		end
		local children: { ComposeTypes.Child } = {}
		if effective ~= "titleOnly" then
			local iconSize = spec.iconSize
			local iconProps: Engine.ImageLabelNativeProps = { Name = "Icon" }
			if iconSize ~= nil then
				assert(
					(type(iconSize) == "number" and iconSize > 0) or type(iconSize) == "string",
					"Facet UI.Label: iconSize must be a positive number or a theme metric name"
				)
				iconProps.Size = function(use: ComposeTypes.Use): UDim2
					local pixels = if type(iconSize) == "number" then iconSize else metric(iconSize, use)
					return D2.fromOffset(pixels, pixels)
				end
			end
			table.insert(children, ctx.icon(icon :: string, iconProps))
		end
		if effective ~= "iconOnly" then
			local titleSize: Media.TextSize = spec.textSize or "body"
			table.insert(children, UI.Text("Title")({ text = spec.title, textSize = titleSize }))
		end
		if spec.iconPosition == "trailing" then
			local reversed: { ComposeTypes.Child } = {}
			for index = #children, 1, -1 do
				table.insert(reversed, children[index])
			end
			children = reversed
		end
		local keys = { "title", "icon", "presentation", "iconSize", "textSize", "gap", "iconPosition" }
		local root =
			ctx.row(children, (ctx.props(spec, keys, { Name = "Label" }) :: unknown) :: Engine.FrameNativeProps)
		local layout = assert(root:FindFirstChildWhichIsA("UIListLayout"))
		layout.VerticalAlignment = E.VerticalAlignment.Center
		if spec.gap ~= nil then
			runtime.decorate(layout, {
				Padding = function(use: ComposeTypes.Use)
					return D.new(0, lists.spacing(spec.gap, use))
				end,
			})
		end
		root:SetAttribute("FacetPresentation", effective)
		Compose.watch(function(use: ComposeTypes.Use)
			root:SetAttribute("AccessibleLabel", read(spec.title, use))
		end)
		return root
	end)

	UI.Image = ctx.construct("Image", function(spec: Media.ImageProps): ImageLabel
		local keys = { "image", "tint", "scaleMode", "tileSize", "sliceCenter", "sliceScale", "resample", "shape" }
		local declared = read(spec.scaleMode)
		local live = Compose.isReadable(spec.scaleMode) or type(spec.scaleMode) == "function"
		assert(
			not live or (spec.tileSize == nil and spec.sliceCenter == nil),
			"Facet UI.Image: tile and slice are static; author scaleMode as a word with its geometry"
		)
		if declared == "tile" then
			local tile = spec.tileSize
			assert(
				type(tile) == "table"
					and type(tile.width) == "number"
					and type(tile.height) == "number"
					and tile.width > 0
					and tile.height > 0
					and tile.width % 1 == 0
					and tile.height % 1 == 0,
				"Facet UI.Image: scaleMode tile requires tileSize = { width, height } in whole pixels above zero"
			)
		else
			assert(spec.tileSize == nil, "Facet UI.Image: tileSize requires scaleMode tile")
		end
		if declared == "slice" then
			local rect = spec.sliceCenter
			assert(
				type(rect) == "table"
					and type(rect.x0) == "number"
					and type(rect.y0) == "number"
					and type(rect.x1) == "number"
					and type(rect.y1) == "number"
					and rect.x1 > rect.x0
					and rect.y1 > rect.y0,
				"Facet UI.Image: scaleMode slice requires sliceCenter = { x0, y0, x1, y1 } in source pixels"
			)
			assert(
				spec.sliceScale == nil or (type(spec.sliceScale) == "number" and spec.sliceScale > 0),
				"Facet UI.Image: sliceScale must be above zero"
			)
		else
			assert(spec.sliceCenter == nil, "Facet UI.Image: sliceCenter requires scaleMode slice")
			assert(spec.sliceScale == nil, "Facet UI.Image: sliceScale requires scaleMode slice")
		end
		assert(
			spec.shape == nil or spec.shape == "rect" or spec.shape == "circle",
			"Facet UI.Image: shape must be rect or circle"
		)
		assert(
			spec.shape ~= "circle" or declared ~= "slice",
			"Facet UI.Image: a circle cannot slice; use fit, fill, crop, stretch or tile"
		)
		local modes: { [string]: Enum.ScaleType } = {
			fit = E.ScaleType.Fit,
			fill = E.ScaleType.Crop,
			crop = E.ScaleType.Crop,
			stretch = E.ScaleType.Stretch,
			tile = E.ScaleType.Tile,
			slice = E.ScaleType.Slice,
		}
		local defaults: Engine.ImageLabelNativeProps = {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = bind(spec.image, ""),
			Size = function(use: ComposeTypes.Use): UDim2
				local side = controlSize(nil, "height", use)
				return D2.fromOffset(side, side)
			end,
		}
		if spec.tint ~= nil then
			defaults.ImageColor3 = spec.tint :: Types.Value<Color3>
		end
		if spec.scaleMode ~= nil then
			defaults.ScaleType = function(use: ComposeTypes.Use): Enum.ScaleType
				local mode = read(spec.scaleMode, use)
				assert(
					not live or (mode ~= "tile" and mode ~= "slice"),
					"Facet UI.Image: a bound scaleMode cannot be tile or slice, which need static geometry"
				)
				return assert(
					modes[mode or "stretch"],
					"Facet UI.Image: scaleMode must be fit, fill, crop, stretch, tile or slice"
				)
			end
		end
		if spec.tileSize ~= nil then
			defaults.TileSize = D2.fromOffset(spec.tileSize.width, spec.tileSize.height)
		end
		if spec.sliceCenter ~= nil then
			local rect = spec.sliceCenter
			defaults.SliceCenter = types.Rect.new(rect.x0, rect.y0, rect.x1, rect.y1)
			defaults.SliceScale = spec.sliceScale or 1
		end
		if spec.resample ~= nil then
			defaults.ResampleMode = function(use: ComposeTypes.Use): Enum.ResamplerMode
				local mode = read(spec.resample, use) or "default"
				assert(
					mode == "default" or mode == "pixelated",
					"Facet UI.Image: resample must be default or pixelated"
				)
				return if mode == "pixelated" then E.ResamplerMode.Pixelated else E.ResamplerMode.Default
			end
		end
		if spec.shape == "circle" then
			table.insert(defaults, Host.UICorner({ CornerRadius = D.new(0.5, 0) }))
			table.insert(defaults, Host.UIAspectRatioConstraint({ AspectRatio = 1 }))
		end
		return Host.ImageLabel(ctx.props(spec, keys, defaults))
	end)

	UI.Badge = ctx.construct("Badge", function(spec: Media.BadgeProps): GuiObject
		assert(
			spec.iconPosition == nil or spec.iconPosition == "leading" or spec.iconPosition == "trailing",
			"Facet Badge invalid iconPosition"
		)
		local function caption(use: ComposeTypes.Use): string
			local value = read(spec.label, use)
			assert(value == nil or type(value) == "string", "Facet Badge label must be a string")
			assert(
				(value ~= nil and value ~= "") or (spec.icon ~= nil and type(spec.name) == "string" and spec.name ~= ""),
				"Facet Badge requires meaningful text or a named icon"
			)
			return value or ""
		end
		local native = ctx.props(
			spec,
			{ "label", "status", "icon", "iconPosition", "name", "appearance", "corners", "controlSize" },
			{
				Text = caption,
				Attributes = { AccessibleLabel = spec.name or caption },
				AutomaticSize = E.AutomaticSize.XY,
				Size = function(use: ComposeTypes.Use)
					return D2.fromOffset(0, controlSize(spec.controlSize, "iconSize", use) + 4)
				end,
			}
		)
		local node = ctx.styled(Host.TextLabel(native), "text")
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
				Size = function(use: ComposeTypes.Use)
					return D2.fromOffset(0, controlSize(spec.controlSize, "iconSize", use) + 4)
				end,
				lists.list({ gap = 4, align = "center" }, false) :: ComposeTypes.Child,
				icon :: ComposeTypes.Child,
				node :: ComposeTypes.Child,
			})
		end
		ctx.styled(pill, "badge")
		if spec.status ~= nil then
			statusTag(pill, spec.status)
		end
		local previousAppearance: string?
		Compose.watch(function(use: ComposeTypes.Use)
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
		end)
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
		return pill
	end)

	UI.StatusIndicator = ctx.construct("StatusIndicator", function(spec: Media.StatusIndicatorProps): TextLabel
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
				Attributes = if spec.name ~= nil then { AccessibleLabel = spec.name } :: Engine.Attributes else nil,
				Size = function(use: ComposeTypes.Use)
					return D2.fromOffset(
						if spec.count ~= nil then 0 else size(use),
						if form(use) == "dash" then math.max(3, size(use) / 3) else size(use)
					)
				end,
				AutomaticSize = if spec.count ~= nil then E.AutomaticSize.X else nil,
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
						return D.new(if form(use) == "square" then 0 else 1, 0)
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
			table.insert(
				native,
				Host.UISizeConstraint({
					MinSize = function(use: ComposeTypes.Use)
						return V2.new(size(use), size(use))
					end,
				})
			)
		elseif spec.count == nil then
			table.insert(
				native,
				Host.UIAspectRatioConstraint({
					AspectRatio = function(use: ComposeTypes.Use)
						return if form(use) == "dash" then 3 else 1
					end,
					AspectType = E.AspectType.FitWithinMaxSize,
				})
			)
		end
		if spec.cutout then
			table.insert(
				native,
				ctx.styled(
					Host.UIStroke "Cutout" {
						ApplyStrokeMode = E.ApplyStrokeMode.Border,
						BorderStrokePosition = E.BorderStrokePosition.Inner,
						Thickness = 1,
					},
					"cutout"
				)
			)
		end
		local node = ctx.styled(ctx.styled(Host.TextLabel(native), "text"), "badge")
		statusTag(node, spec.status)
		if spec.count ~= nil and spec.Size ~= nil then
			local absolute: ComposeTypes.Readable<Vector2> = ctx.observe(node, "AbsoluteSize")
			runtime.mount(function()
				return Host.UISizeConstraint({
					MinSize = function(use: ComposeTypes.Use)
						return V2.new(use(absolute).Y, 0)
					end,
				})
			end, node)
		end
		Compose.watch(function(use: ComposeTypes.Use)
			if form(use) == "ring" then
				node:AddTag("facet-status-hollow")
			elseif node:HasTag("facet-status-hollow") then
				node:RemoveTag("facet-status-hollow")
			end
		end)
		return node
	end)

	UI.ProgressView = ctx.construct("ProgressView", function(spec: Media.ProgressViewProps): Frame
		local motionReduced = reducedMotion(ctx)
		local presentation = spec.presentation or "bar"
		assert(
			presentation == "bar" or presentation == "circular" or presentation == "spinner",
			"Facet ProgressView presentation must be bar, circular or spinner"
		)
		assert(spec.segments == nil or presentation == "bar", "Facet ProgressView segments require bar presentation")
		assert(
			spec.diameter == nil or presentation ~= "bar",
			"Facet ProgressView diameter requires a circular presentation"
		)
		assert(
			presentation ~= "bar" or spec.controlSize == nil or spec.thickness == nil,
			"Facet ProgressView: give thickness or controlSize, not both (a bar's rung is its track thickness)"
		)
		local count = spec.segments or 1
		assert(
			type(count) == "number" and count >= 1 and count < math.huge and count % 1 == 0,
			"Facet ProgressView segments must be a positive integer"
		)
		local delay: number, duration: number = 0.3, 0.35
		if spec.trail then
			assert(type(spec.trail) == "table", "Facet ProgressView trail must be a table")
			delay, duration = spec.trail.delay or 0.3, spec.trail.duration or 0.35
			assert(
				type(delay) == "number"
					and delay >= 0
					and delay < math.huge
					and type(duration) == "number"
					and duration > 0
					and duration < math.huge,
				"Facet ProgressView trail delay/duration invalid"
			)
		end
		local indeterminate = spec.value == nil
		local timeline = if indeterminate then runtime.timeline({ duration = 1, repeats = math.huge }) else nil
		local progress = Compose.formula(function(use: ComposeTypes.Use)
			if timeline then
				local phase = use(timeline.progress)
				return if motionReduced(use) then math.floor(phase * 4) / 4 else phase
			end
			local minimum, maximum = read(spec.min, use) or 0, read(spec.max, use) or 1
			assert(maximum > minimum, "Facet ProgressView max must exceed min")
			return math.clamp(((read(spec.value, use) :: number) - minimum) / (maximum - minimum), 0, 1)
		end)
		local trail: ComposeTypes.Formula<number>?
		if spec.trail and not indeterminate then
			local clock = runtime.timeline({ delay = delay, duration = duration, autoplay = false })
			local previous = progress:peek()
			local origin, destination = Compose.cell(previous), Compose.cell(previous)
			trail = Compose.formula(function(use: ComposeTypes.Use)
				return use(origin) + (use(destination) - use(origin)) * use(clock.progress)
			end)
			Compose.watch(function(use: ComposeTypes.Use)
				local value = use(progress)
				if motionReduced(use) or value >= previous then
					origin:set(value)
					destination:set(value)
					clock:seek(duration)
				else
					origin:set((trail :: ComposeTypes.Formula<number>):peek())
					destination:set(value)
					clock:restart()
				end
				previous = value
			end)
		end
		local readout: TextLabel?
		local ending: TextLabel? = if spec.endLabel
			then ctx.text({
				Name = "EndLabel",
				Text = function(use: ComposeTypes.Use)
					return read(spec.endLabel, use) or ""
				end,
			})
			else nil
		if spec.showValue then
			readout = ctx.text({
				Name = "Value",
				Text = function(use: ComposeTypes.Use)
					if indeterminate then
						return "Loading"
					end
					local value = read(spec.value, use)
					return if spec.format
						then spec.format(value :: number)
						else tostring(math.floor(use(progress) * 100 + 0.5)) .. "%"
				end,
			})
		end
		local direction = Compose.formula(function(use: ComposeTypes.Use): Theme.FillDirection
			local package = read(ctx.config.theme, use)
			local recipe = if package then ((package.chrome or {}) :: { [string]: Theme.SkinLayer }).barFill else nil
			local value = (if recipe then recipe.direction or "ltr" else "ltr") :: Theme.FillDirection
			assert(({ ltr = true, rtl = true, ttb = true, btt = true })[value], "Facet progress invalid fill direction")
			return value :: Theme.FillDirection
		end)
		local function dynamic(source: unknown): boolean
			return Compose.isReadable(source) or type(source) == "function"
		end
		local settled = not (
			indeterminate
			or trail ~= nil
			or dynamic(spec.value)
			or dynamic(spec.min)
			or dynamic(spec.max)
			or dynamic(spec.controlSize)
			or dynamic(spec.thickness)
			or dynamic(ctx.config.theme)
		)
		local function fixed<T>(body: (ComposeTypes.Use) -> T): Types.Value<T>
			if not settled then
				return body
			end
			return body(function<U>(source: ComposeTypes.Readable<U>): U
				return source:peek()
			end)
		end
		local function vertical(use: ComposeTypes.Use): boolean
			return use(direction) == "ttb" or use(direction) == "btt"
		end
		local function reversed(use: ComposeTypes.Use): boolean
			return use(direction) == "rtl" or use(direction) == "btt"
		end
		local content: GuiObject
		if presentation == "bar" then
			local track: Engine.FrameNativeProps = {
				Name = "Track",
				Size = fixed(function(use: ComposeTypes.Use)
					local rung = read(spec.controlSize, use)
					local thickness = read(spec.thickness, use)
						or (
							if rung == "xsmall" or rung == "compact"
								then metric("space.xs", use)
								else metric("controls.progress.trackHeight", use)
						)
					return if vertical(use) then D2.new(0, thickness, 1, 0) else D2.new(1, 0, 0, thickness)
				end),
				ClipsDescendants = false,
			}
			if trail then
				table.insert(
					track,
					ctx.styled(
						Host.Frame "Trail" {
							BackgroundTransparency = 0.6,
							BorderSizePixel = 0,
							ZIndex = 0,
							Size = function(use: ComposeTypes.Use)
								local fraction = if motionReduced(use)
									then use(progress)
									else math.max(use(trail :: ComposeTypes.Formula<number>), use(progress))
								return if vertical(use) then D2.fromScale(1, fraction) else D2.fromScale(fraction, 1)
							end,
							AnchorPoint = function(use: ComposeTypes.Use)
								return if reversed(use)
									then (if vertical(use) then V2.new(0, 1) else V2.new(1, 0))
									else V2.new(0, 0)
							end,
							Position = function(use: ComposeTypes.Use)
								return if reversed(use)
									then (if vertical(use) then D2.fromScale(0, 1) else D2.fromScale(1, 0))
									else D2.fromScale(0, 0)
							end,
						},
						"fill"
					)
				)
			end
			for index = 1, count do
				table.insert(
					track,
					ctx.styled(
						Host.Frame({
							Name = "Fill" .. index,
							ClipsDescendants = true,
							AnchorPoint = fixed(function(use: ComposeTypes.Use)
								return if reversed(use)
									then (if vertical(use) then V2.new(0, 1) else V2.new(1, 0))
									else V2.new(0, 0)
							end),
							BorderSizePixel = 0,
							Size = fixed(function(use: ComposeTypes.Use)
								local fraction = if indeterminate
									then 0.3
									else math.clamp(use(progress) * count - (index - 1), 0, 1)
								local gap = if count > 1 and fraction > 0 then -2 else 0
								return if vertical(use)
									then D2.new(1, 0, fraction / count, gap)
									else D2.new(fraction / count, gap, 1, 0)
							end),
							Position = fixed(function(use: ComposeTypes.Use)
								local position = if indeterminate
									then (if motionReduced(use) then use(progress) * 0.7 else use(progress) * 1.3 - 0.3)
									else (index - 1) / count
								if reversed(use) then
									position = 1 - position
								end
								return D2.fromScale(
									if vertical(use) then 0 else position,
									if vertical(use) then position else 0
								)
							end),
						}),
						"fill"
					)
				)
			end
			local clipped: Engine.FrameNativeProps =
				{ Name = "FillClip", Size = D2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true }
			for _, child in ipairs(track) do
				table.insert(clipped, child)
			end
			for index = #track, 1, -1 do
				table.remove(track, index)
			end
			table.insert(track, Host.Frame(clipped))
			content = skin(ctx.styled(Host.Frame(track), "track"), "barTrack")
			for _, fill in content:GetDescendants() do
				if string.match(fill.Name, "^Fill%d+$") then
					local fillIndex = tonumber(string.match(fill.Name, "%d+$")) :: number
					skin(fill :: Frame, "barFill", {
						Size = function(use: ComposeTypes.Use)
							local fraction = if indeterminate
								then 0.3
								else math.clamp(use(progress) * count - (fillIndex - 1), 0, 1)
							local scale = 1 / math.max(fraction, 0.000001)
							return if vertical(use) then D2.fromScale(1, scale) else D2.fromScale(scale, 1)
						end,
						AnchorPoint = function(use: ComposeTypes.Use)
							return if reversed(use)
								then (if vertical(use) then V2.new(0, 1) else V2.new(1, 0))
								else V2.new(0, 0)
						end,
						Position = function(use: ComposeTypes.Use)
							return if reversed(use)
								then (if vertical(use) then D2.fromScale(0, 1) else D2.fromScale(1, 0))
								else D2.fromScale(0, 0)
						end,
					})
				end
			end
			skin(content, "barCap", {
				direction = function(use: ComposeTypes.Use): Theme.FillDirection
					return use(direction) :: Theme.FillDirection
				end,
			})
			skin(content, "barCenter")
		else
			local diameter = function(use: ComposeTypes.Use)
				return read(spec.diameter, use)
					or (
						if spec.controlSize
							then controlSize(spec.controlSize, "height", use)
							else metric("controls.progress.circularSize", use)
					)
			end
			local native: Engine.FrameNativeProps = {
				Name = "Indicator",
				Size = function(use: ComposeTypes.Use)
					local pixels = diameter(use)
					return D2.fromOffset(pixels, pixels)
				end,
				BackgroundTransparency = 1,
			}
			if presentation == "spinner" then
				local count = 8
				for index = 1, count do
					local angle = (index - 1) / count * math.pi * 2 - math.pi / 2
					table.insert(
						native,
						ctx.styled(
							Host.Frame({
								Name = "Segment" .. index,
								AnchorPoint = V2.new(0.5, 0.5),
								BorderSizePixel = 0,
								Position = D2.fromScale(0.5 + math.cos(angle) * 0.4, 0.5 + math.sin(angle) * 0.4),
								Size = function(use: ComposeTypes.Use)
									local thickness = read(spec.thickness, use)
										or metric("controls.progress.spinnerDotSize", use)
									return D2.fromOffset(thickness, thickness)
								end,
								BackgroundTransparency = function(use: ComposeTypes.Use)
									local value = use(progress)
									if not indeterminate then
										return if index / count <= value then 0 else 0.85
									end
									return ((index / count - value) % 1) * 0.85
								end,
								Host.UICorner({ CornerRadius = D.new(1, 0) }),
							}),
							"fill"
						)
					)
				end
			else
				local thickness = function(use: ComposeTypes.Use)
					return read(spec.thickness, use)
						or math.max(
							metric("controls.progress.circularThickness", use),
							math.round(diameter(use) * 0.08)
						)
				end
				for _, isTrack in { true, false } do
					local path = ctx.styled(
						Host.Path2D({
							Name = if isTrack then "RingTrack" else "RingFill",
							Thickness = thickness,
							Closed = false,
							ZIndex = if isTrack then 1 else 2,
							Visible = function(use: ComposeTypes.Use)
								return isTrack or indeterminate or use(progress) > 0
							end,
						}),
						if isTrack then "progress-ring-track" else "progress-ring-fill"
					)
					Compose.watch(function(use: ComposeTypes.Use)
						local pixels = diameter(use)
						assert(pixels > 0, "Facet ProgressView diameter must be positive")
						local radius = math.max(0, 1 - thickness(use) / pixels)
						local points: { pathShapes.PathPoint } = if isTrack
							then pathShapes.ring({ radius = radius })
							else pathShapes.arc(
								if indeterminate then use(progress) * 360 else 0,
								if indeterminate then 90 else use(progress) * 360,
								{ radius = radius }
							)
						local nativePoints: { Path2DControlPoint } = {}
						for _, point in points do
							table.insert(
								nativePoints,
								types.Path2DControlPoint.new(
									D2.fromScale(point.x, point.y),
									D2.fromScale(point.inX, point.inY),
									D2.fromScale(point.outX, point.outY)
								)
							)
						end
						path:SetControlPoints(nativePoints)
					end)
					table.insert(native, path)
				end
			end
			content = Host.Frame(native)
			if readout and presentation == "circular" then
				local bounds = ctx.observe(readout, "TextBounds")
				local centered = Compose.formula(function(use: ComposeTypes.Use)
					local measured, innerDiameter = use(bounds), diameter(use) * 0.6
					return measured.X <= innerDiameter and measured.Y <= innerDiameter
				end)
				runtime.decorate(content, { AnchorPoint = V2.new(0.5, 0), Position = D2.fromScale(0.5, 0) })
				runtime.decorate(readout, {
					AutomaticSize = E.AutomaticSize.XY,
					TextWrapped = false,
					TextXAlignment = E.TextXAlignment.Center,
					AnchorPoint = function(use: ComposeTypes.Use)
						return V2.new(0.5, if use(centered) then 0.5 else 0)
					end,
					Position = function(use: ComposeTypes.Use)
						return D2.new(0.5, 0, 0, if use(centered) then diameter(use) / 2 else diameter(use) + 8)
					end,
				})
				content = Host.Frame "Gauge" {
					BackgroundTransparency = 1,
					ClipsDescendants = false,
					Size = function(use: ComposeTypes.Use)
						local pixels, measured = diameter(use), use(bounds)
						return D2.fromOffset(
							math.max(pixels, measured.X),
							pixels + (if use(centered) then 0 else measured.Y + 8)
						)
					end,
					content,
					readout,
				}
				readout = nil
			end
		end
		local children: { ComposeTypes.Child } = {}
		local trailing: { ComposeTypes.Child } = {}
		if readout then
			table.insert(trailing, readout)
		end
		if ending then
			table.insert(trailing, ending)
		end
		if presentation == "bar" and spec.label and #trailing > 0 then
			local header: { ComposeTypes.Child } = {
				UI.Text({
					text = spec.label,
					LayoutOrder = 1,
					Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
				}),
			}
			for _, node in trailing do
				table.insert(header, node)
			end
			table.insert(
				children,
				ctx.row(header, { Name = "Header", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
			)
			trailing = {}
		elseif spec.label then
			table.insert(children, UI.Text({ text = spec.label }))
		end
		table.insert(children, content)
		for _, node in trailing do
			table.insert(children, node)
		end
		local root = ctx.column(
			children,
			ctx.props(spec, {
				"value",
				"min",
				"max",
				"presentation",
				"label",
				"endLabel",
				"showValue",
				"format",
				"diameter",
				"thickness",
				"segments",
				"trail",
				"controlSize",
			}, {
				Size = fixed(function(use: ComposeTypes.Use)
					return if presentation == "bar"
						then (if vertical(use) then D2.fromOffset(24, 160) else D2.new(1, 0, 0, 0))
						else D2.fromOffset(0, 0)
				end),
				AutomaticSize = fixed(function(use: ComposeTypes.Use)
					return if presentation == "bar"
						then (if vertical(use) then E.AutomaticSize.None else E.AutomaticSize.Y)
						else E.AutomaticSize.XY
				end),
			})
		)
		if timeline then
			ctx.playWhileShown(timeline, root)
		end
		return root
	end)

	local skeletonClock = Compose.createSharedResource(function()
		local clock = runtime.timeline({ duration = 1.4, repeats = math.huge })
		local motionReduced = reducedMotion(ctx)
		Compose.watch(function(use: ComposeTypes.Use)
			if motionReduced(use) then
				clock:pause()
			else
				clock:play()
			end
		end)
		return clock
	end)
	UI.Skeleton = ctx.construct("Skeleton", function(spec: Media.SkeletonProps): Frame
		local form = spec.form or "box"
		assert(form == "box" or form == "circle" or form == "line", "Facet Skeleton invalid form")
		assert(spec.lines == nil or form == "line", "Facet Skeleton lines require line form")
		assert(spec.corners == nil or form ~= "circle", "Facet Skeleton circle owns its corners")
		local count = spec.lines or 1
		assert(count >= 1 and count % 1 == 0, "Facet Skeleton lines must be positive")
		local clock = skeletonClock()
		local motionReduced = reducedMotion(ctx)
		local rows: { ComposeTypes.Child } = {}
		for index = 1, count do
			local native: Engine.FrameNativeProps = {
				Name = "Placeholder" .. index,
				Size = function(use: ComposeTypes.Use)
					local pixels = controlSize(spec.controlSize, if form == "line" then "iconSize" else "height", use)
					return if form == "circle"
						then D2.fromOffset(pixels, pixels)
						else D2.new(if count > 1 and index == count then 0.6 else 1, 0, 0, pixels)
				end,
				Host.UIGradient "Shimmer" {
					Enabled = function(use: ComposeTypes.Use)
						return not motionReduced(use)
					end,
					Offset = function(use: ComposeTypes.Use)
						return V2.new(use(clock.progress) * 2 - 1, 0)
					end,
					Transparency = types.NumberSequence.new({
						types.NumberSequenceKeypoint.new(0, 0.4),
						types.NumberSequenceKeypoint.new(0.5, 0),
						types.NumberSequenceKeypoint.new(1, 0.4),
					}),
				},
			}
			if form == "circle" then
				table.insert(native, Host.UICorner({ CornerRadius = D.new(1, 0) }))
			elseif spec.corners then
				table.insert(
					native,
					Host.UICorner({
						CornerRadius = function(use: ComposeTypes.Use)
							local value = read(spec.corners, use)
							if value == "pill" then
								return D.new(1, 0)
							end
							if value == "square" then
								return D.new(0, 0)
							end
							if value == "rounded" then
								return D.new(0, metric("radii.control", use))
							end
							assert(type(value) == "number" and value >= 0, "Facet Skeleton invalid corners")
							return D.new(0, value)
						end,
					})
				)
			end
			table.insert(rows, ctx.styled(Host.Frame(native), "skeleton"))
		end
		return ctx.column(
			rows,
			ctx.props(
				spec,
				{ "form", "lines", "controlSize", "corners" },
				{ Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y }
			)
		)
	end)

	UI.AsyncImage = ctx.construct("AsyncImage", function(spec: Media.AsyncImageProps): Frame
		local state: ComposeTypes.Cell<Media.ImageState> = Compose.cell("loading" :: Media.ImageState)
		local loaded = Compose.cell("")
		local failure = Compose.cell(nil :: unknown)
		local root = Host.Frame(ctx.props(spec, {
			"image",
			"source",
			"resource",
			"loader",
			"onStatus",
			"failureLabel",
			"placeholder",
			"dimmed",
			"imageProperties",
		}, { BackgroundTransparency = 1, Size = D2.fromOffset(48, 48) }))
		local imageOptions: Engine.ImageLabelProps = ctx.props(spec.imageProperties or {}, {}, {
			Name = "Image",
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = loaded,
			ImageTransparency = function(use: ComposeTypes.Use)
				return if read(spec.dimmed, use) then 0.35 else 0
			end,
			Visible = function(use: ComposeTypes.Use)
				return use(state) == "ready"
			end,
		})
		local image = Host.ImageLabel(imageOptions)
		runtime.mount(function()
			return image
		end, root)
		runtime.mount(function()
			local placeholder: Engine.FrameNativeProps = {
				Name = "Placeholder",
				Size = D2.fromScale(1, 1),
				BackgroundTransparency = if spec.placeholder then 1 else 0,
				Visible = function(use: ComposeTypes.Use)
					return use(state) ~= "ready"
				end,
			}
			if spec.placeholder then
				table.insert(
					placeholder,
					Compose.show(function(use: ComposeTypes.Use)
						return use(state) ~= "ready"
					end, function()
						return spec.placeholder(state)
					end)
				)
			end
			if spec.failureLabel ~= nil then
				table.insert(
					placeholder,
					Compose.show(function(use: ComposeTypes.Use)
						return use(state) == "failed"
					end, function()
						return ctx.text({ Text = bind(spec.failureLabel, ""), Size = D2.fromScale(1, 1) })
					end)
				)
			end
			local node = Host.Frame(placeholder)
			return if spec.placeholder then node else ctx.styled(node, "skeleton")
		end, root)
		local generation, cancel: (() -> ())? = 0, nil
		Compose.cleanup(function()
			generation += 1
			if cancel then
				cancel()
			end
		end)
		if spec.resource then
			local resource = spec.resource()
			Compose.watch(function(use: ComposeTypes.Use)
				state:set(read(resource.state or resource.status, use) :: Media.ImageState)
				loaded:set(read(resource.value, use) or "")
			end)
		else
			Compose.watch(function(use: ComposeTypes.Use)
				local source = read(spec.source or spec.image, use) or ""
				generation += 1
				local ticket = generation
				if cancel then
					cancel()
					cancel = nil
				end
				state:set("loading")
				failure:set(nil)
				loaded:set(source)
				local function resolve(value: string?)
					if ticket == generation then
						loaded:set(value or source)
						state:set("ready")
					end
				end
				local function reject(reason: unknown)
					if ticket == generation then
						failure:set(reason)
						state:set("failed")
					end
				end
				if source == "" then
					reject("empty content")
				elseif spec.loader then
					local ok, teardown = pcall(spec.loader, source, resolve, reject)
					if ok then
						cancel = teardown
					elseif ticket == generation then
						reject(teardown)
					end
				elseif ctx.config.services and ctx.config.services.ContentProvider and task then
					local contentProvider = ctx.config.services.ContentProvider
					local thread = task.defer(function()
						local succeeded, reason = pcall(function()
							contentProvider:PreloadAsync({ image }, function(_, fetchStatus)
								if fetchStatus == E.AssetFetchStatus.Success then
									resolve(source)
								else
									reject(tostring(fetchStatus))
								end
							end)
						end)
						if not succeeded then
							reject(reason)
						end
					end)
					cancel = function()
						if coroutine.status(thread) ~= "dead" then
							task.cancel(thread)
						end
					end
				else
					resolve(source)
				end
			end)
		end
		if spec.onStatus then
			Compose.watch(function(use: ComposeTypes.Use)
				spec.onStatus(use(state) :: Media.ImageState, use(failure))
			end)
		end
		return root
	end)

	UI.Avatar = ctx.construct("Avatar", function(spec: Media.AvatarProps): TextButton
		assert(spec.form == nil or spec.form == "standard" or spec.form == "icon", "Facet Avatar invalid form")
		local diameter = function(use: ComposeTypes.Use)
			return read(spec.diameter, use)
				or controlSize(spec.controlSize, if spec.form == "icon" then "iconSize" else "height", use)
		end
		local native = ctx.props(spec, {
			"name",
			"image",
			"userId",
			"presence",
			"presenceLabel",
			"diameter",
			"onActivate",
			"form",
			"controlSize",
			"backplate",
			"presenceMark",
			"loader",
			"onStatus",
			"resource",
		}, {
			Size = function(use: ComposeTypes.Use)
				local pixels = diameter(use)
				return D2.fromOffset(pixels, pixels)
			end,
			Text = "",
			AutoButtonColor = false,
			Selectable = spec.onActivate ~= nil,
			Host.UICorner({ CornerRadius = D.new(1, 0) }),
		})
		if spec.onActivate then
			native.Activated = spec.onActivate
		end
		local root = ctx.styled(Host.TextButton(native), "avatar")
		if spec.backplate then
			ctx.styled(root, "accent")
		end
		local function facts(use: ComposeTypes.Use)
			local name, presence = read(spec.name, use), read(spec.presence, use)
			assert(type(name) == "string" and name ~= "", "Facet Avatar name must be nonempty")
			assert(
				presence == nil or ({ online = true, away = true, busy = true, offline = true })[presence],
				"Facet Avatar invalid presence"
			)
			return {
				name = name,
				presence = presence,
				label = if presence then name .. ", " .. (read(spec.presenceLabel, use) or presence) else name,
			}
		end
		runtime.decorate(root, {
			Attributes = {
				AccessibleLabel = function(use: ComposeTypes.Use): string
					return facts(use).label
				end,
			},
		})
		local pictured = Compose.cell(false)
		runtime.mount(function()
			return ctx.text({
				Name = "Initials",
				Visible = function(use: ComposeTypes.Use)
					return not use(pictured)
				end,
				Size = D2.fromScale(1, 1),
				Text = function(use: ComposeTypes.Use)
					return initials(facts(use).name)
				end,
				TextSize = function(use: ComposeTypes.Use)
					return math.max(8, math.floor(diameter(use) * 0.4 + 0.5))
				end,
				TextXAlignment = E.TextXAlignment.Center,
				TextYAlignment = E.TextYAlignment.Center,
			})
		end, root)
		if spec.image or spec.userId or spec.resource then
			runtime.mount(function()
				return UI.AsyncImage({
					imageProperties = { Host.UICorner({ CornerRadius = D.new(1, 0) }) },
					Name = "Portrait",
					loader = spec.loader,
					onStatus = function(state: Media.ImageState, failure: unknown)
						pictured:set(state == "ready")
						if spec.onStatus then
							spec.onStatus(state, failure)
						end
					end,
					resource = spec.resource,
					Size = D2.fromScale(1, 1),
					image = function(use: ComposeTypes.Use)
						return if spec.image
							then read(spec.image, use)
							else "rbxthumb://type=AvatarHeadShot&id="
								.. tostring(read(spec.userId, use))
								.. "&w=150&h=150"
					end,
					placeholder = function(_state: ComposeTypes.Readable<Media.ImageState>): Instance
						return Host.Frame({ BackgroundTransparency = 1, Size = D2.fromScale(1, 1) })
					end,
					Host.UICorner({ CornerRadius = D.new(1, 0) }),
				})
			end, root)
		end
		if spec.presence and spec.presenceMark ~= false and spec.form ~= "icon" then
			runtime.mount(function()
				return UI.StatusIndicator "Presence" {
					diameter = 12,
					cutout = true,
					Visible = function(use: ComposeTypes.Use)
						return facts(use).presence ~= nil
					end,
					form = function(use: ComposeTypes.Use)
						return ({ online = "dot", away = "dash", busy = "square", offline = "ring" })[facts(use).presence]
							or "dot"
					end,
					AnchorPoint = V2.new(1, 1),
					Position = D2.fromScale(1, 1),
					status = function(use: ComposeTypes.Use)
						return ({ online = "success", away = "warning", busy = "error", offline = "neutral" })[read(
							spec.presence,
							use
						)] or "neutral"
					end,
				}
			end, root)
		end
		return root
	end)

	UI.AvatarGroup = ctx.construct("AvatarGroup", function(spec: Media.AvatarGroupProps): Frame
		local items = Compose.formula(function(use: ComposeTypes.Use)
			local members = read(spec.items, use)
			assert(type(members) == "table", "Facet AvatarGroup items must be an array")
			local seen: { [string]: boolean }, count = {}, 0
			for key, member in members do
				assert(
					type(key) == "number" and key >= 1 and key % 1 == 0 and key <= #members,
					"Facet AvatarGroup items must be dense"
				)
				assert(
					type(member) == "table" and type(member.id) == "string" and member.id ~= "" and not seen[member.id],
					"Facet AvatarGroup needs unique nonempty ids"
				)
				assert(type(member.name) == "string" and member.name ~= "", "Facet AvatarGroup needs member names")
				seen[member.id] = true
				count += 1
			end
			assert(count == #members, "Facet AvatarGroup items must be dense")
			return members
		end)
		assert(
			spec.layout == nil or spec.layout == "stacked" or spec.layout == "spread",
			"Facet AvatarGroup invalid layout"
		)
		assert(
			spec.overflow == nil or spec.overflow == "count" or spec.overflow == "ellipsis",
			"Facet AvatarGroup invalid overflow"
		)
		assert(spec.form == nil or spec.form == "standard" or spec.form == "icon", "Facet AvatarGroup invalid form")
		assert(
			spec.onOverflow == nil or type(spec.onOverflow) == "function",
			"Facet AvatarGroup onOverflow must be a function"
		)
		local maximum = spec.max or 4
		assert(maximum >= 1 and maximum % 1 == 0, "Facet AvatarGroup max must be positive")
		local size = function(use: ComposeTypes.Use)
			return read(spec.diameter, use)
				or controlSize(spec.controlSize, if spec.form == "icon" then "iconSize" else "height", use)
		end
		local spacing = if spec.layout == "spread" then 8 else -10
		local native = ctx.props(spec, {
			"items",
			"max",
			"diameter",
			"layout",
			"onOverflow",
			"overflow",
			"controlSize",
			"form",
			"overflowLabel",
		}, {
			BackgroundTransparency = 1,
			Size = function(use: ComposeTypes.Use)
				return D2.fromOffset(0, size(use))
			end,
			AutomaticSize = E.AutomaticSize.X,
			Host.UIListLayout({
				FillDirection = E.FillDirection.Horizontal,
				Padding = D.new(0, spacing),
				SortOrder = E.SortOrder.LayoutOrder,
			}),
		})
		table.insert(
			native,
			Compose.keyed({
				from = function(use: ComposeTypes.Use)
					local items = use(items)
					local visible: { Media.AvatarMember } = {}
					for index = 1, math.min(#items, maximum) do
						table.insert(visible, items[index])
					end
					return visible
				end,
				key = function(item: Media.AvatarMember)
					return if item.resource then item.id .. "\0" .. tostring(item.resource) else item.id
				end,
				render = function(
					current: ComposeTypes.Readable<Media.AvatarMember>,
					index: ComposeTypes.Readable<number>
				)
					return UI.Avatar({
						resource = current:peek().resource,
						Name = function(use: ComposeTypes.Use)
							return use(current).id
						end,
						name = function(use: ComposeTypes.Use)
							return use(current).name
						end,
						image = function(use: ComposeTypes.Use)
							local item = use(current)
							return item.image
								or (
									if item.userId
										then "rbxthumb://type=AvatarHeadShot&id=" .. tostring(item.userId) .. "&w=150&h=150"
										else ""
								)
						end,
						presence = function(use: ComposeTypes.Use): Media.Presence?
							return use(current).presence :: Media.Presence?
						end,
						diameter = size,
						presenceMark = spec.layout == "spread",
						LayoutOrder = index,
					})
				end,
			})
		)
		table.insert(
			native,
			Compose.show(function(use: ComposeTypes.Use)
				return #use(items) > maximum
			end, function()
				return ctx.styled(
					Host.TextButton({
						Attributes = {
							AccessibleLabel = (function(use: ComposeTypes.Use): string
								local label = read(spec.overflowLabel, use)
								assert(
									label == nil or type(label) == "string",
									"Facet AvatarGroup overflowLabel must be a string"
								)
								return label or tostring(#use(items) - maximum) .. " more players"
							end) :: Engine.Value<Engine.AttributeValue?>,
						},
						Name = "Overflow",
						Size = function(use: ComposeTypes.Use)
							local pixels = size(use)
							return D2.fromOffset(pixels, pixels)
						end,
						LayoutOrder = maximum + 1,
						Text = function(use: ComposeTypes.Use)
							return if spec.overflow == "ellipsis" then "…" else "+" .. tostring(#use(items) - maximum)
						end,
						Selectable = spec.onOverflow ~= nil,
						AutoButtonColor = false,
						Activated = spec.onOverflow or function() end,
						Host.UICorner({ CornerRadius = D.new(1, 0) }),
					}),
					"button"
				)
			end)
		)
		local group = Host.Frame(native)
		if spec.layout ~= "spread" then
			ctx.styled(group, "avatar-stack")
		end
		return group
	end)

	local frames = runtime.host.frames
	local pending: { () -> () } = {}
	local stopQueue: (() -> ())? = nil
	local function enqueue(job: () -> ())
		table.insert(pending, job)
		if stopQueue == nil and frames then
			stopQueue = frames.onFrame(function()
				local next = table.remove(pending, 1)
				if next then
					next()
				end
				if #pending == 0 and stopQueue then
					stopQueue()
					stopQueue = nil
				end
			end)
		end
	end
	local function stageLive(stage: ViewportFrame): (ComposeTypes.Readable<boolean>, ComposeTypes.Readable<boolean>)
		local owner = assert(Compose.currentOwner())
		local moving = Compose.cell(false)
		local visible = Compose.cell(true)
		local position = ctx.observe(stage, "AbsolutePosition")
		local size = ctx.observe(stage, "AbsoluteSize")
		local current: ScrollingFrame? = nil
		local tracking: ComposeTypes.Owner? = nil
		local function track(frame: ScrollingFrame)
			local canvas = ctx.observe(frame, "CanvasPosition")
			local origin = ctx.observe(frame, "AbsolutePosition")
			local window = ctx.observe(frame, "AbsoluteWindowSize")
			local last = canvas:peek()
			local lastMove = -math.huge
			local stopWatch: (() -> ())? = nil
			local function halt()
				if stopWatch then
					stopWatch()
					stopWatch = nil
				end
			end
			Compose.watch(function(use: ComposeTypes.Use)
				local value = use(canvas)
				if value == last or frames == nil then
					return
				end
				last = value
				lastMove = frames.now()
				moving:set(true)
				if stopWatch == nil then
					stopWatch = frames.onFrame(function()
						if frames.now() - lastMove >= SETTLE_SECONDS then
							halt()
							moving:set(false)
						end
					end)
				end
			end)
			Compose.cleanup(halt)
			Compose.watch(function(use: ComposeTypes.Use)
				local at, extent = use(position), use(size)
				local top, box = use(origin), use(window)
				if extent.X <= 0 or extent.Y <= 0 or box.X <= 0 or box.Y <= 0 then
					visible:set(false)
					return
				end
				local width = math.min(at.X + extent.X, top.X + box.X) - math.max(at.X, top.X)
				local height = math.min(at.Y + extent.Y, top.Y + box.Y) - math.max(at.Y, top.Y)
				if width <= 0 or height <= 0 then
					visible:set(false)
					return
				end
				local shown = width * height / (extent.X * extent.Y)
				visible:set(shown >= VISIBLE_FRACTION or height >= box.Y * VISIBLE_FRACTION)
			end)
		end
		local function locate()
			if owner.isDisposed() then
				return
			end
			local found: ScrollingFrame? = nil
			local at = stage.Parent
			while at do
				if at:IsA("ScrollingFrame") then
					found = at
					break
				end
				if at:IsA("LayerCollector") then
					break
				end
				at = at.Parent
			end
			if found == current and tracking ~= nil then
				return
			end
			current = found
			if tracking then
				tracking.dispose()
				tracking = nil
			end
			moving:set(false)
			visible:set(true)
			if found then
				local child = owner.createChild()
				tracking = child
				Compose.withOwner(child, function()
					track(found)
				end)
			end
		end
		runtime.connect(stage, "AncestryChanged", locate)
		locate()
		return Compose.formula(function(use: ComposeTypes.Use): boolean
			return use(visible) and not use(moving)
		end),
			visible
	end

	UI.Stage = ctx.construct("Stage", function(spec: Media.StageProps): ViewportFrame
		local world = Host.WorldModel "World" {}
		local externalCamera = spec.camera
			and (
				typeof(spec.camera) == "Instance"
				or (
					type(spec.camera) == "table"
					and type(((spec.camera :: unknown) :: { IsA: unknown }).IsA) == "function"
					and ((spec.camera :: unknown) :: Camera):IsA("Camera")
				)
			)
		local camera = if externalCamera
			then spec.camera :: Camera
			else Host.Camera "Camera" {
				FieldOfView = bind(spec.fieldOfView, 45),
				CFrame = (spec.camera :: Types.Value<CFrame>?)
					or types.CFrame.lookAt(types.Vector3.new(0, 2, 8), types.Vector3.new(0, 0, 0)),
			}
		local native = ctx.props(
			spec,
			{ "content", "camera", "fieldOfView", "lazy" },
			{
				Size = D2.fromOffset(240, 180),
				CurrentCamera = Compose.static(camera),
				world :: ComposeTypes.Child,
				if not externalCamera then camera else nil,
			} :: Engine.ViewportFrameNativeProps
		)
		local stage = ctx.styled(Host.ViewportFrame(native), "panel")
		local live, shown = stageLive(stage)
		stage:SetAttribute("FacetLive", live:peek())
		Compose.watch(function(use: ComposeTypes.Use)
			stage:SetAttribute("FacetLive", use(live))
		end)
		if spec.content then
			local content = spec.content
			local owner = assert(Compose.currentOwner())
			local built = false
			local function build()
				if built or owner.isDisposed() then
					return
				end
				built = true
				Compose.withOwner(owner, function()
					local cleanup = content(runtime, world, live)
					if type(cleanup) == "function" then
						Compose.cleanup(cleanup)
					end
				end)
				stage:SetAttribute("FacetBuilt", true)
			end
			stage:SetAttribute("FacetBuilt", false)
			if spec.lazy ~= true or frames == nil then
				build()
			else
				local queued = false
				local function attempt()
					queued = false
					if not owner.isDisposed() and shown:peek() then
						build()
					end
				end
				Compose.watch(function(use: ComposeTypes.Use)
					if use(shown) and not built and not queued then
						queued = true
						enqueue(attempt)
					end
				end)
			end
		end
		return stage
	end)
	return UI
end
