--!strict
local layoutKit = require("./layout_kit")
local Types = require("./types")
local Engine = require("./engine_types")
local Media = require("./media_types")
local Theme = require("./theme_types")
local ComposeTypes = require("../vendor/compose/core")
local bindThemes = require("./themes")
local help = require("./help")
local textReveal = require("./text_reveal")
local ControlTypes = require("./control_types")
local MediaProps = require("./media_props")
local MediaShared = require("./media_shared")

return function(ctx: Types.Context, UI: ControlTypes.Controls, shared: MediaShared.Shared)
	local Host, runtime, Compose = ctx.Host, ctx.runtime, ctx.Compose
	local themes = bindThemes(Compose)
	local lists = layoutKit.of(ctx)
	local types, read = ctx.types, ctx.read
	local E, D2, D, V2 = types.Enum, types.UDim2, types.UDim, types.Vector2
	local metric = ctx.metric
	local bind = shared.bind
	local function roleTag(value: string?): string
		local name = value or "body"
		assert(table.find(themes.TYPE_ROLES, name), "Facet Text invalid textRole")
		return "facet-type-" .. name
	end
	local function textRole(node: TextLabel, role: Types.Input<Media.TextRole>?): TextLabel
		if not Compose.isValue(role) and type(role) ~= "function" then
			node:AddTag(roleTag(role :: Media.TextRole?))
			return node
		end
		local live = role :: Types.Input<Media.TextRole>
		local previous: string?
		Compose.watch(function(use: ComposeTypes.Use)
			local tag = roleTag(read(live, use))
			if previous then
				node:RemoveTag(previous)
			end
			previous = tag
			node:AddTag(tag)
		end)
		return node
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
		for position, _ in utf8.codes(text) do
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
		"lines",
		"disclose",
		"reveal",
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
	UI.Text = ctx.construct("Text", function(spec: MediaProps.TextProps): TextLabel
		local fields = (spec :: unknown) :: { [string]: unknown }
		for _, retired in { "color", "font" } do
			if fields[retired] ~= nil then
				error(`Facet UI.Text: {retired} is style authority. Use role or textRole.`, 0)
			end
		end
		if fields.label ~= nil or spec.Text ~= nil then
			error("Facet UI.Text: set the text with text. Remove label and Text.", 0)
		end
		local source: Types.Input<string>? = spec.text
		if not Compose.isValue(source) and type(source) ~= "function" then
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
		local lines = spec.lines
		assert(
			lines == nil or (type(lines) == "number" and lines >= 1 and lines % 1 == 0),
			"Facet Text lines must be a whole number, 1 or more"
		)
		assert(lines == nil or not cut, "Facet Text lines cannot combine with a middle cut")
		assert(lines == nil or fit == nil, "Facet Text lines cannot combine with a fitted text size")
		assert(spec.reveal == nil or spec.reveal == "auto", "Facet Text reveal must be auto")
		assert(
			spec.reveal == nil or (lines == nil and not cut and spec.wrap ~= true and spec.TextWrapped ~= true),
			"Facet Text reveal needs one line that truncates at the end; remove wrap, lines or the middle cut"
		)
		local defaults: Engine.TextLabelNativeProps = {
			Text = if cut then read(source) or "" else bind(source, ""),
			AutoLocalize = if Compose.isValue(source) or type(source) == "function" then false else nil,
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
		if spec.TextWrapped == true or (spec.TextWrapped == nil and spec.wrap == true) then
			defaults.Size = D2.fromScale(1, 0)
			defaults.AutomaticSize = E.AutomaticSize.Y
		end
		if spec.direction ~= nil then
			defaults.TextDirection = DIRECTION[spec.direction]
		end
		if spec.tint ~= nil then
			defaults.TextColor3 = spec.tint :: Types.Input<Color3>
		end
		if spec.textAlign ~= nil then
			defaults.TextXAlignment = function(use: ComposeTypes.Use): Enum.TextXAlignment
				local align = read(spec.textAlign, use) or "start"
				return (assert(ALIGN[align], "Facet Text textAlign must be start, center or end"))
			end
		end
		if cut then
			defaults.Size = D2.fromScale(1, 0)
			defaults.AutomaticSize = E.AutomaticSize.Y
			defaults.TextWrapped = false
			defaults.TextTruncate = E.TextTruncate.None
		elseif
			truncate == "end"
			or spec.reveal
			or (spec.disclose == true and spec.wrap ~= true and spec.TextWrapped ~= true)
		then
			defaults.TextTruncate = E.TextTruncate.AtEnd
		end
		if lines then
			defaults.Size = D2.fromScale(1, 0)
			defaults.AutomaticSize = E.AutomaticSize.Y
			defaults.TextWrapped = true
			defaults.TextTruncate = E.TextTruncate.AtEnd
		end
		local roleSource: Types.Input<Media.TextRole>? = sizeRole or spec.textRole
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
		local label = textRole(ctx.text(ctx.props(spec, TEXT_KEYS, defaults), true), roleSource)
		if lines then
			local styledSize = ctx.observeStyled.TextSize(label)
			local styledLine = ctx.observeStyled.LineHeight(label)
			runtime.mount(function()
				return Host.UISizeConstraint({
					Name = "LineClamp",
					MaxSize = function(use: ComposeTypes.Use): Vector2
						local inset = label:FindFirstChildWhichIsA("UIPadding")
						local vertical = if inset then inset.PaddingTop.Offset + inset.PaddingBottom.Offset else 0
						return V2.new(math.huge, math.ceil(lines * use(styledSize) * use(styledLine)) + vertical)
					end,
				})
			end, label)
		end
		if cut then
			local measured = ctx.layoutSize(label)
			local insets = Compose.cell({ left = D.new(0, 0), right = D.new(0, 0) })
			local sideConnections: { RBXScriptConnection } = {}
			local function paddingChanged()
				for _, connection in sideConnections do
					connection:Disconnect()
				end
				table.clear(sideConnections)
				local inset = label:FindFirstChildWhichIsA("UIPadding")
				local function refresh()
					insets:set(
						if inset
							then { left = inset.PaddingLeft, right = inset.PaddingRight }
							else { left = D.new(0, 0), right = D.new(0, 0) }
					)
				end
				if inset then
					table.insert(sideConnections, inset:GetPropertyChangedSignal("PaddingLeft"):Connect(refresh))
					table.insert(sideConnections, inset:GetPropertyChangedSignal("PaddingRight"):Connect(refresh))
				end
				refresh()
			end
			runtime.connect(label, "ChildAdded", paddingChanged)
			runtime.connect(label, "ChildRemoved", paddingChanged)
			Compose.cleanup(function()
				for _, connection in sideConnections do
					connection:Disconnect()
				end
			end)
			paddingChanged()
			local width = Compose.formula(function(use: ComposeTypes.Use): number
				local box = use(measured).X
				local inset = use(insets)
				return math.max(
					0,
					box - inset.left.Scale * box - inset.left.Offset - inset.right.Scale * box - inset.right.Offset
				)
			end)
			local textSize = ctx.observe.TextSize(label)
			local face = ctx.observe.FontFace(label)
			local styledSize = ctx.observeStyled.TextSize(label)
			local styledFace = ctx.observeStyled.FontFace(label)
			Compose.watch(function(use: ComposeTypes.Use)
				local value = read(source, use) or ""
				use(textSize)
				use(face)
				use(styledSize)
				use(styledFace)
				label.Text = middle(label, value, use(width))
			end)
		end
		assert(spec.disclose == nil or type(spec.disclose) == "boolean", "Facet Text disclose must be a boolean")
		if spec.disclose or spec.reveal then
			local fits, painted = ctx.observe.TextFits(label), ctx.observe.Text(label)
			local shown = Compose.cell(false)
			help.attach(ctx, label, bind(source, ""), {
				name = "Disclosure",
				gate = function(use: ComposeTypes.Use): boolean
					return not use(fits) or (cut and use(painted) ~= (read(source, use) or ""))
				end,
				shown = shown,
			})
			if spec.reveal then
				textReveal(ctx, label, shown)
			end
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
	UI.Label = ctx.construct("Label", function(spec: MediaProps.LabelProps): Frame
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
end
