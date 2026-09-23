--!strict
local Types = require("./types")
local Engine = require("./engine_types")
local Media = require("./media_types")
local Theme = require("./theme_types")
local Compose = require("../vendor/compose/core")
local themes = require("./themes")
local pathShapes = require("./nav_path_shapes")
export type MediaControls = Media.MediaControls

return function(ctx: Types.Context, controls: Media.MediaControls?): Media.MediaControls
	local Host, runtime = ctx.Host, ctx.runtime
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
		return function(use: Compose.Use)
			local value = read(source, use)
			return if value == nil then fallback else value
		end
	end
	local function statusTag(node: GuiObject, source: Types.Value<Media.Status>?)
		local previous: string?
		Compose.watch(function(use: Compose.Use)
			local status = read(source, use) or "neutral"
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
	local function textRole(node: TextLabel, role: Types.Value<Media.TextRole>?): TextLabel
		if not Compose.isReadable(role) and type(role) ~= "function" then
			node:AddTag("facet-type-" .. (read(role) or "body"))
			return node
		end
		local previous: string?
		Compose.watch(function(use: Compose.Use)
			if previous then
				node:RemoveTag(previous)
			end
			previous = "facet-type-" .. (read(role, use) or "body")
			node:AddTag(previous :: string)
		end)
		return node
	end
	local function initials(name: string?): string
		local first: string?, last: string?
		for word in string.gmatch(name or "", "%S+") do
			first = first or word
			last = word
		end
		local function character(word: string): string
			return string.sub(word, 1, (utf8.offset(word, 2) or (#word + 1)) - 1)
		end
		return if first == nil
			then ""
			elseif first == last then character(first)
			else character(first) .. character(last :: string)
	end

	UI.Label = ctx.construct(function(spec: Media.LabelProps): GuiObject
		local keys = { "text", "label", "icon", "iconPosition", "textRole", "role", "gap" }
		local label = textRole(
			ctx.text(
				if spec.icon
					then { Text = bind(spec.text or spec.label or spec.Text, "") }
					else ctx.props(spec, keys, { Text = bind(spec.text or spec.label or spec.Text, "") })
			),
			spec.textRole
		)
		if spec.role == "secondary" then
			ctx.styled(label, "secondary")
		end
		if not spec.icon then
			return label
		end
		local icon = ctx.icon(spec.icon)
		local root = ctx.row(
			if spec.iconPosition == "trailing" then { label, icon } else { icon, label },
			(ctx.props(spec, keys) :: unknown) :: Engine.FrameNativeProps
		)
		if spec.gap then
			runtime.decorate(root:FindFirstChildWhichIsA("UIListLayout"), {
				Padding = function(use: Compose.Use)
					return D.new(0, read(spec.gap, use))
				end,
			})
		end
		return root
	end)

	UI.Badge = ctx.construct(function(spec: Media.BadgeProps): GuiObject
		local caption = Compose.formula(function(use: Compose.Use)
			local value = read(spec.label, use)
			assert(value == nil or type(value) == "string", "Facet Badge label must be a string")
			assert(
				(value ~= nil and value ~= "") or (spec.icon ~= nil and type(spec.name) == "string" and spec.name ~= ""),
				"Facet Badge requires meaningful text or a named icon"
			)
			return value or ""
		end)
		local native = ctx.props(
			spec,
			{ "label", "status", "icon", "iconPosition", "name", "appearance", "corners", "controlSize" },
			{
				Text = caption,
				Attributes = { AccessibleLabel = spec.name or caption },
				AutomaticSize = E.AutomaticSize.XY,
				Size = function(use: Compose.Use)
					return D2.fromOffset(0, controlSize(spec.controlSize, "iconSize", use) + 4)
				end,
			}
		)
		local node = ctx.styled(ctx.styled(Host.TextLabel(native), "text"), "badge")
		if spec.status then
			statusTag(node, spec.status)
		end
		local previousAppearance: string?
		Compose.watch(function(use: Compose.Use)
			local appearance = read(spec.appearance, use) or "standard"
			assert(
				appearance == "standard" or appearance == "status" or appearance == "utility",
				"Facet Badge invalid appearance"
			)
			if previousAppearance then
				node:RemoveTag(previousAppearance)
			end
			previousAppearance = "facet-badge-" .. appearance
			node:AddTag(previousAppearance :: string)
		end)
		if spec.appearance then
			runtime.mountFragment(function()
				return {
					Compose.show(function(use: Compose.Use)
						return read(spec.appearance, use) == "status"
					end, function()
						return UI.StatusIndicator({
							Name = "Status",
							status = spec.status,
							diameter = 10,
							Position = D2.new(0, 0, 0.5, 0),
							AnchorPoint = V2.new(0, 0.5),
						})
					end),
				}
			end, node)
		end
		if spec.corners then
			runtime.mount(function()
				local radius = read(spec.corners)
				if type(radius) == "string" then
					radius = ({ square = 0, rounded = 8, capsule = 999 })[radius]
				end
				assert(type(radius) == "number", "Facet Badge invalid corners")
				return ctx.corner(radius)
			end, node)
		end
		if spec.icon then
			local icon = ctx.icon(spec.icon)
			return ctx.styled(
				ctx.row(
					if spec.iconPosition == "trailing" then { node, icon } else { icon, node },
					{ Name = spec.Name or "Badge" }
				),
				"badge"
			)
		end
		return node
	end)

	UI.StatusIndicator = ctx.construct(function(spec: Media.StatusIndicatorProps): TextLabel
		local size = function(use: Compose.Use)
			return read(spec.diameter, use)
				or (
					if spec.controlSize
						then controlSize(spec.controlSize, "iconSize", use)
						else if spec.count ~= nil then 24 else 12
				)
		end
		local form = Compose.formula(function(use: Compose.Use)
			local value = read(spec.form, use) or "dot"
			assert(
				value == "dot" or value == "ring" or value == "square" or value == "dash",
				"Facet StatusIndicator invalid form"
			)
			return value
		end)
		local native = ctx.props(
			spec,
			{ "status", "form", "count", "max", "name", "diameter", "controlSize", "cutout" },
			{
				Size = function(use: Compose.Use)
					return D2.fromOffset(
						size(use),
						if use(form) == "dash" then math.max(3, size(use) / 3) else size(use)
					)
				end,
				Text = function(use: Compose.Use)
					local count = read(spec.count, use)
					if count == nil then
						return ""
					end
					assert(
						type(count) == "number" and count >= 0 and count < math.huge and count % 1 == 0,
						"Facet StatusIndicator count must be a nonnegative integer"
					)
					assert(
						use(form) == "dot" or use(form) == "square",
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
					CornerRadius = function(use: Compose.Use)
						return D.new(if use(form) == "square" then 0 else 1, 0)
					end,
				}) :: Compose.Child,
				Compose.show(function(use: Compose.Use)
					return use(form) == "ring"
				end, function()
					return ctx.styled(
						Host.Frame({
							Name = "Center",
							Size = D2.new(1, -4, 1, -4),
							Position = D2.fromOffset(2, 2),
							BorderSizePixel = 0,
							Host.UICorner({ CornerRadius = D.new(1, 0) }),
						}),
						"surface"
					)
				end),
			} :: Engine.TextLabelNativeProps
		)
		table.insert(
			native,
			Host.UIAspectRatioConstraint({
				AspectRatio = function(use: Compose.Use)
					return if use(form) == "dash" then 3 else 1
				end,
				AspectType = E.AspectType.FitWithinMaxSize,
			})
		)
		if spec.cutout then
			table.insert(
				native,
				ctx.styled(
					Host.UIStroke({
						Name = "Cutout",
						ApplyStrokeMode = E.ApplyStrokeMode.Border,
						BorderStrokePosition = E.BorderStrokePosition.Inner,
						Thickness = 1,
					}),
					"cutout"
				)
			)
		end
		local node = ctx.styled(ctx.styled(Host.TextLabel(native), "text"), "badge")
		statusTag(node, spec.status)
		return node
	end)

	UI.ProgressView = ctx.construct(function(spec: Media.ProgressViewProps): Frame
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
		local progress = Compose.formula(function(use: Compose.Use)
			if timeline then
				local phase = use(timeline.progress)
				return if read(ctx.config.reducedMotion, use) then math.floor(phase * 4) / 4 else phase
			end
			local minimum, maximum = read(spec.min, use) or 0, read(spec.max, use) or 1
			assert(maximum > minimum, "Facet ProgressView max must exceed min")
			return math.clamp(((read(spec.value, use) :: number) - minimum) / (maximum - minimum), 0, 1)
		end)
		local trail: Compose.Formula<number>?
		if spec.trail and not indeterminate then
			local clock = runtime.timeline({ delay = delay, duration = duration, autoplay = false })
			local previous = progress:peek()
			local origin, destination = Compose.cell(previous), Compose.cell(previous)
			trail = Compose.formula(function(use: Compose.Use)
				return use(origin) + (use(destination) - use(origin)) * use(clock.progress)
			end)
			Compose.watch(function(use: Compose.Use)
				local value = use(progress)
				if read(ctx.config.reducedMotion, use) or value >= previous then
					origin:set(value)
					destination:set(value)
					clock:seek(duration)
				else
					origin:set((trail :: Compose.Formula<number>):peek())
					destination:set(value)
					clock:restart()
				end
				previous = value
			end)
		end
		local readout: TextLabel?
		if spec.showValue or spec.endLabel then
			readout = ctx.text({
				Name = "Value",
				Text = function(use: Compose.Use)
					if spec.endLabel then
						return read(spec.endLabel, use)
					end
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
		local direction = Compose.formula(function(use: Compose.Use): Theme.FillDirection
			local package = read(ctx.config.theme, use)
			local recipe = if package then ((package.chrome or {}) :: { [string]: Theme.SkinLayer }).barFill else nil
			local value = (if recipe then recipe.direction or "ltr" else "ltr") :: Theme.FillDirection
			assert(({ ltr = true, rtl = true, ttb = true, btt = true })[value], "Facet progress invalid fill direction")
			return value :: Theme.FillDirection
		end)
		local function vertical(use: Compose.Use): boolean
			return use(direction) == "ttb" or use(direction) == "btt"
		end
		local function reversed(use: Compose.Use): boolean
			return use(direction) == "rtl" or use(direction) == "btt"
		end
		local content: GuiObject
		if presentation == "bar" then
			local track: Engine.FrameNativeProps = {
				Name = "Track",
				Size = function(use: Compose.Use)
					local thickness = read(spec.thickness, use) or metric("controls.progress.trackHeight", use)
					return if vertical(use) then D2.new(0, thickness, 1, 0) else D2.new(1, 0, 0, thickness)
				end,
				ClipsDescendants = false,
			}
			if trail then
				table.insert(
					track,
					ctx.styled(
						Host.Frame({
							Name = "Trail",
							BackgroundTransparency = 0.6,
							BorderSizePixel = 0,
							ZIndex = 0,
							Size = function(use: Compose.Use)
								local fraction = if read(ctx.config.reducedMotion, use)
									then use(progress)
									else math.max(use(trail :: Compose.Formula<number>), use(progress))
								return if vertical(use) then D2.fromScale(1, fraction) else D2.fromScale(fraction, 1)
							end,
							AnchorPoint = function(use: Compose.Use)
								return if reversed(use)
									then (if vertical(use) then V2.new(0, 1) else V2.new(1, 0))
									else V2.new(0, 0)
							end,
							Position = function(use: Compose.Use)
								return if reversed(use)
									then (if vertical(use) then D2.fromScale(0, 1) else D2.fromScale(1, 0))
									else D2.fromScale(0, 0)
							end,
						}),
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
							AnchorPoint = function(use: Compose.Use)
								return if reversed(use)
									then (if vertical(use) then V2.new(0, 1) else V2.new(1, 0))
									else V2.new(0, 0)
							end,
							BorderSizePixel = 0,
							Size = function(use: Compose.Use)
								local fraction = if indeterminate
									then 0.3
									else math.clamp(use(progress) * count - (index - 1), 0, 1)
								local gap = if count > 1 and fraction > 0 then -2 else 0
								return if vertical(use)
									then D2.new(1, 0, fraction / count, gap)
									else D2.new(fraction / count, gap, 1, 0)
							end,
							Position = function(use: Compose.Use)
								local position = if indeterminate
									then use(progress) * 1.3 - 0.3
									else (index - 1) / count
								if reversed(use) then
									position = 1 - position
								end
								return D2.fromScale(
									if vertical(use) then 0 else position,
									if vertical(use) then position else 0
								)
							end,
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
						Size = function(use: Compose.Use)
							local fraction = if indeterminate
								then 0.3
								else math.clamp(use(progress) * count - (fillIndex - 1), 0, 1)
							local scale = 1 / math.max(fraction, 0.000001)
							return if vertical(use) then D2.fromScale(1, scale) else D2.fromScale(scale, 1)
						end,
						AnchorPoint = function(use: Compose.Use)
							return if reversed(use)
								then (if vertical(use) then V2.new(0, 1) else V2.new(1, 0))
								else V2.new(0, 0)
						end,
						Position = function(use: Compose.Use)
							return if reversed(use)
								then (if vertical(use) then D2.fromScale(0, 1) else D2.fromScale(1, 0))
								else D2.fromScale(0, 0)
						end,
					})
				end
			end
			skin(content, "barCap", {
				direction = function(use: Compose.Use): Theme.FillDirection
					return use(direction) :: Theme.FillDirection
				end,
			})
			skin(content, "barCenter")
		else
			local diameter = function(use: Compose.Use)
				return read(spec.diameter, use)
					or (
						if spec.controlSize
							then controlSize(spec.controlSize, "height", use)
							else metric("controls.progress.circularSize", use)
					)
			end
			local native: Engine.FrameNativeProps = {
				Name = "Indicator",
				Size = function(use: Compose.Use)
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
								Size = function(use: Compose.Use)
									local thickness = read(spec.thickness, use)
										or metric("controls.progress.spinnerDotSize", use)
									return D2.fromOffset(thickness, thickness)
								end,
								BackgroundTransparency = function(use: Compose.Use)
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
				local thickness = function(use: Compose.Use)
					return read(spec.thickness, use) or metric("controls.progress.circularThickness", use)
				end
				for _, isTrack in { true, false } do
					local path = ctx.styled(
						Host.Path2D({
							Name = if isTrack then "RingTrack" else "RingFill",
							Thickness = thickness,
							Closed = false,
							ZIndex = if isTrack then 1 else 2,
							Visible = function(use: Compose.Use)
								return isTrack or indeterminate or use(progress) > 0
							end,
						}),
						if isTrack then "progress-ring-track" else "progress-ring-fill"
					)
					Compose.watch(function(use: Compose.Use)
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
				local centered = Compose.formula(function(use: Compose.Use)
					local measured, innerDiameter = use(bounds), diameter(use) * 0.6
					return measured.X <= innerDiameter and measured.Y <= innerDiameter
				end)
				runtime.decorate(content, { AnchorPoint = V2.new(0.5, 0), Position = D2.fromScale(0.5, 0) })
				runtime.decorate(readout, {
					AutomaticSize = E.AutomaticSize.XY,
					TextWrapped = false,
					TextXAlignment = E.TextXAlignment.Center,
					AnchorPoint = function(use: Compose.Use)
						return V2.new(0.5, if use(centered) then 0.5 else 0)
					end,
					Position = function(use: Compose.Use)
						return D2.new(0.5, 0, 0, if use(centered) then diameter(use) / 2 else diameter(use) + 8)
					end,
				})
				content = Host.Frame({
					Name = "Gauge",
					BackgroundTransparency = 1,
					ClipsDescendants = false,
					Size = function(use: Compose.Use)
						local pixels, measured = diameter(use), use(bounds)
						return D2.fromOffset(
							math.max(pixels, measured.X),
							pixels + (if use(centered) then 0 else measured.Y + 8)
						)
					end,
					content,
					readout,
				})
				readout = nil
			end
		end
		local children: { Compose.Child } = {}
		if spec.label then
			table.insert(children, UI.Label({ label = spec.label }))
		end
		table.insert(children, content)
		if readout then
			table.insert(children, readout)
		end
		return ctx.column(
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
				Size = function(use: Compose.Use)
					return if presentation == "bar"
						then (if vertical(use) then D2.fromOffset(24, 160) else D2.new(1, 0, 0, 0))
						else D2.fromOffset(0, 0)
				end,
				AutomaticSize = function(use: Compose.Use)
					return if presentation == "bar"
						then (if vertical(use) then E.AutomaticSize.None else E.AutomaticSize.Y)
						else E.AutomaticSize.XY
				end,
			})
		)
	end)

	local skeletonClock = Compose.createSharedResource(function()
		local clock = runtime.timeline({ duration = 1.4, repeats = math.huge })
		Compose.watch(function(use: Compose.Use)
			if read(ctx.config.reducedMotion, use) then
				clock:pause()
			else
				clock:play()
			end
		end)
		return clock
	end)
	UI.Skeleton = ctx.construct(function(spec: Media.SkeletonProps): Frame
		local form = spec.form or "box"
		assert(form == "box" or form == "circle" or form == "line", "Facet Skeleton invalid form")
		assert(spec.lines == nil or form == "line", "Facet Skeleton lines require line form")
		assert(spec.corners == nil or form ~= "circle", "Facet Skeleton circle owns its corners")
		local count = spec.lines or 1
		assert(count >= 1 and count % 1 == 0, "Facet Skeleton lines must be positive")
		local clock = skeletonClock()
		local rows: { Compose.Child } = {}
		for index = 1, count do
			local native: Engine.FrameNativeProps = {
				Name = "Placeholder" .. index,
				Size = function(use: Compose.Use)
					local pixels = controlSize(spec.controlSize, if form == "line" then "iconSize" else "height", use)
					return if form == "circle"
						then D2.fromOffset(pixels, pixels)
						else D2.new(if count > 1 and index == count then 0.6 else 1, 0, 0, pixels)
				end,
				Host.UIGradient({
					Name = "Shimmer",
					Enabled = function(use: Compose.Use)
						return not read(ctx.config.reducedMotion, use)
					end,
					Offset = function(use: Compose.Use)
						return V2.new(use(clock.progress) * 2 - 1, 0)
					end,
					Transparency = types.NumberSequence.new({
						types.NumberSequenceKeypoint.new(0, 0.4),
						types.NumberSequenceKeypoint.new(0.5, 0),
						types.NumberSequenceKeypoint.new(1, 0.4),
					}),
				}),
			}
			if form == "circle" then
				table.insert(native, Host.UICorner({ CornerRadius = D.new(1, 0) }))
			elseif spec.corners then
				table.insert(
					native,
					Host.UICorner({
						CornerRadius = function(use: Compose.Use)
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

	UI.AsyncImage = ctx.construct(function(spec: Media.AsyncImageProps): Frame
		local state: Compose.Cell<Media.ImageState> = Compose.cell("loading" :: Media.ImageState)
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
			ImageTransparency = function(use: Compose.Use)
				return if read(spec.dimmed, use) then 0.35 else 0
			end,
			Visible = function(use: Compose.Use)
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
				Visible = function(use: Compose.Use)
					return use(state) ~= "ready"
				end,
			}
			if spec.placeholder then
				table.insert(
					placeholder,
					Compose.show(function(use: Compose.Use)
						return use(state) ~= "ready"
					end, function()
						return spec.placeholder(state)
					end)
				)
			end
			if spec.failureLabel ~= nil then
				table.insert(
					placeholder,
					Compose.show(function(use: Compose.Use)
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
			Compose.watch(function(use: Compose.Use)
				state:set(read(resource.state or resource.status, use) :: Media.ImageState)
				loaded:set(read(resource.value, use) or "")
			end)
		else
			Compose.watch(function(use: Compose.Use)
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
			Compose.watch(function(use: Compose.Use)
				spec.onStatus(use(state) :: Media.ImageState, use(failure))
			end)
		end
		return root
	end)

	UI.Avatar = ctx.construct(function(spec: Media.AvatarProps): TextButton
		assert(spec.form == nil or spec.form == "standard" or spec.form == "icon", "Facet Avatar invalid form")
		local diameter = function(use: Compose.Use)
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
			Size = function(use: Compose.Use)
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
		local facts = Compose.formula(function(use: Compose.Use)
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
		end)
		runtime.decorate(root, {
			Attributes = {
				AccessibleLabel = function(use: Compose.Use): string
					return use(facts).label
				end,
			},
		})
		runtime.mount(function()
			return ctx.text({
				Name = "Initials",
				Size = D2.fromScale(1, 1),
				Text = function(use: Compose.Use)
					return initials(use(facts).name)
				end,
				TextXAlignment = E.TextXAlignment.Center,
			})
		end, root)
		if spec.image or spec.userId or spec.resource then
			runtime.mount(function()
				return UI.AsyncImage({
					imageProperties = { Host.UICorner({ CornerRadius = D.new(1, 0) }) },
					Name = "Portrait",
					loader = spec.loader,
					onStatus = spec.onStatus,
					resource = spec.resource,
					Size = D2.fromScale(1, 1),
					image = function(use: Compose.Use)
						return if spec.image
							then read(spec.image, use)
							else "rbxthumb://type=AvatarHeadShot&id="
								.. tostring(read(spec.userId, use))
								.. "&w=150&h=150"
					end,
					placeholder = function(_state: Compose.Readable<Media.ImageState>): Instance
						return Host.Frame({ BackgroundTransparency = 1, Size = D2.fromScale(1, 1) })
					end,
					Host.UICorner({ CornerRadius = D.new(1, 0) }),
				})
			end, root)
		end
		if spec.presence and spec.presenceMark ~= false and spec.form ~= "icon" then
			runtime.mount(function()
				return UI.StatusIndicator({
					Name = "Presence",
					diameter = 12,
					cutout = true,
					Visible = function(use: Compose.Use)
						return use(facts).presence ~= nil
					end,
					form = function(use: Compose.Use)
						return ({ online = "dot", away = "dash", busy = "square", offline = "ring" })[use(facts).presence]
							or "dot"
					end,
					AnchorPoint = V2.new(1, 1),
					Position = D2.fromScale(1, 1),
					status = function(use: Compose.Use)
						return ({ online = "success", away = "warning", busy = "error", offline = "neutral" })[read(
							spec.presence,
							use
						)] or "neutral"
					end,
				})
			end, root)
		end
		return root
	end)

	UI.AvatarGroup = ctx.construct(function(spec: Media.AvatarGroupProps): Frame
		local items = Compose.formula(function(use: Compose.Use)
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
		local maximum = spec.max or 4
		assert(maximum >= 1 and maximum % 1 == 0, "Facet AvatarGroup max must be positive")
		local size = function(use: Compose.Use)
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
			Size = function(use: Compose.Use)
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
				from = function(use: Compose.Use)
					local items = use(items)
					local visible: { Media.AvatarMember } = {}
					for index = 1, math.min(#items, maximum) do
						table.insert(visible, items[index])
					end
					return visible
				end,
				key = function(item: Media.AvatarMember)
					return item.id
				end,
				render = function(current: Compose.Readable<Media.AvatarMember>, index: Compose.Readable<number>)
					return UI.Avatar({
						resource = current:peek().resource,
						Name = function(use: Compose.Use)
							return use(current).id
						end,
						name = function(use: Compose.Use)
							return use(current).name
						end,
						image = function(use: Compose.Use)
							local item = use(current)
							return item.image
								or (
									if item.userId
										then "rbxthumb://type=AvatarHeadShot&id=" .. tostring(item.userId) .. "&w=150&h=150"
										else ""
								)
						end,
						presence = function(use: Compose.Use): Media.Presence?
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
			Compose.show(function(use: Compose.Use)
				return #use(items) > maximum
			end, function()
				return ctx.styled(
					Host.TextButton({
						Attributes = {
							AccessibleLabel = (function(use: Compose.Use): string
								local label = read(spec.overflowLabel, use)
								assert(
									label == nil or type(label) == "string",
									"Facet AvatarGroup overflowLabel must be a string"
								)
								return label or tostring(#use(items) - maximum) .. " more players"
							end) :: Engine.Value<Engine.AttributeValue?>,
						},
						Name = "Overflow",
						Size = function(use: Compose.Use)
							local pixels = size(use)
							return D2.fromOffset(pixels, pixels)
						end,
						LayoutOrder = maximum + 1,
						Text = function(use: Compose.Use)
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
		return Host.Frame(native)
	end)

	UI.Stage = ctx.construct(function(spec: Media.StageProps): ViewportFrame
		local world = Host.WorldModel({ Name = "World" })
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
			else Host.Camera({
				Name = "Camera",
				FieldOfView = bind(spec.fieldOfView, 45),
				CFrame = (spec.camera :: Types.Value<CFrame>?)
					or types.CFrame.lookAt(types.Vector3.new(0, 2, 8), types.Vector3.new(0, 0, 0)),
			})
		local native = ctx.props(
			spec,
			{ "content", "camera", "fieldOfView" },
			{
				Size = D2.fromOffset(240, 180),
				CurrentCamera = Compose.static(camera),
				world :: Compose.Child,
				if not externalCamera then camera else nil,
			} :: Engine.ViewportFrameNativeProps
		)
		local stage = ctx.styled(Host.ViewportFrame(native), "panel")
		if spec.content then
			local cleanup = spec.content(runtime, world)
			if type(cleanup) == "function" then
				Compose.cleanup(cleanup)
			end
		end
		return stage
	end)
	return UI
end
