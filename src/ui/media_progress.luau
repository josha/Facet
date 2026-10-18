--!strict
local reducedMotion = require("./motion").reduced
local Types = require("./types")
local Engine = require("./engine_types")
local Theme = require("./theme_types")
local ComposeTypes = require("../vendor/compose/core")
local pathShapes = require("./nav_path_shapes")
local ControlTypes = require("./control_types")
local MediaProps = require("./media_props")
local MediaShared = require("./media_shared")

return function(ctx: Types.Context, UI: ControlTypes.Controls, shared: MediaShared.Shared)
	local Host, runtime, Compose = ctx.Host, ctx.runtime, ctx.Compose
	local types, read = ctx.types, ctx.read
	local E, D2, V2 = types.Enum, types.UDim2, types.Vector2
	local metric, controlSize = ctx.metric, ctx.controlSize
	local skin = shared.skin
	UI.ProgressView = ctx.construct("ProgressView", function(spec: MediaProps.ProgressViewProps): Frame
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
		assert(
			presentation == "bar" or spec.controlSize == nil or spec.diameter == nil,
			"Facet ProgressView: give diameter or controlSize, not both (a ring's rung is its diameter)"
		)
		assert(
			spec.endLabel == nil or type(read(spec.endLabel)) == "string",
			"Facet ProgressView endLabel must be a string"
		)
		local count = spec.segments or 1
		assert(
			type(count) == "number" and count >= 1 and count < math.huge and count % 1 == 0,
			"Facet ProgressView segments must be a positive integer"
		)
		local delay: number, duration: number =
			ctx.metric("motion.durations.trailDelay"), ctx.metric("motion.durations.trailSettle")
		if spec.trail then
			assert(type(spec.trail) == "table", "Facet ProgressView trail must be a table")
			delay, duration = spec.trail.delay or delay, spec.trail.duration or duration
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
		local timeline = if indeterminate
			then runtime.timeline({ duration = ctx.metric("motion.durations.progressLoop"), repeats = math.huge })
			else nil
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
			}, true)
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
			}, true)
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
			local function thickness(use: ComposeTypes.Use): number
				local rung = read(spec.controlSize, use)
				return read(spec.thickness, use)
					or (
						if rung == "xsmall" or rung == "compact"
							then metric("space.xs", use)
							else metric("controls.progress.trackHeight", use)
					)
			end

			local measured = Compose.cell(V2.zero)
			local function ornament(slot: string, use: ComposeTypes.Use): (number, number)
				local package = read(ctx.config.theme, use)
				local recipe = if package then ((package.chrome or {}) :: { [string]: Theme.SkinLayer })[slot] else nil
				if recipe == nil or recipe.kind == "native" or recipe.kind == "none" then
					return 1, 0
				end
				local size = if type(recipe.size) == "table" then recipe.size else { w = 16, h = 16 }
				local along, cross = size.w, size.h
				if vertical(use) then
					along, cross = cross, along
				end
				local pixels, box = thickness(use), use(measured)
				local length, depth = if vertical(use) then box.Y else box.X, if vertical(use) then box.X else box.Y
				local fit = math.min(1, pixels / cross)
				if depth > 0 then
					fit = math.min(fit, length * pixels / depth / 4 / along)
				end
				return if fit < 0.5 then 0 else fit, if fit < 0.5 then 0 else math.round(along * fit)
			end
			local track: Engine.FrameNativeProps = {
				Name = "Track",
				Size = fixed(function(use: ComposeTypes.Use)
					local pixels = thickness(use)
					return if vertical(use) then D2.new(0, pixels, 1, 0) else D2.new(1, 0, 0, pixels)
				end),
				ClipsDescendants = false,
			}
			if trail then
				track[#track + 1] = ctx.styled(
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
			end
			for index = 1, count do
				track[#track + 1] = ctx.styled(
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
			end
			local clipped: Engine.FrameNativeProps = {
				Name = "FillClip",

				Size = function(use: ComposeTypes.Use)
					local _, cap = ornament("barCap", use)
					return if vertical(use) then D2.new(1, 0, 1, -2 * cap) else D2.new(1, -2 * cap, 1, 0)
				end,
				Position = function(use: ComposeTypes.Use)
					local _, cap = ornament("barCap", use)
					return if vertical(use) then D2.fromOffset(0, cap) else D2.fromOffset(cap, 0)
				end,
				BackgroundTransparency = 1,
				ClipsDescendants = true,
			}
			for _, child in ipairs((track :: unknown) :: { unknown }) do
				clipped[#clipped + 1] = child
			end
			for index = #track, 1, -1 do
				table.remove((track :: unknown) :: { unknown }, index)
			end
			track[#track + 1] = Host.Frame(clipped)
			content = skin(ctx.styled(Host.Frame(track), "track"), "barTrack")
			local trackSize = ctx.layoutSize(content)
			Compose.watch(function(use: ComposeTypes.Use)
				measured:set(use(trackSize))
			end)
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
				fit = function(use: ComposeTypes.Use): number
					return (ornament("barCap", use))
				end,
				ZIndex = 2,
			})
			skin(content, "barCenter", {
				fit = function(use: ComposeTypes.Use): number
					return (ornament("barCenter", use))
				end,
				ZIndex = 2,
			})
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
					native[#native + 1] = ctx.styled(
						Host.Frame("Segment" .. index)({
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
							Host.UICorner({ CornerRadius = ctx.round }),
						}),
						"fill"
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
					native[#native + 1] = path
				end
			end
			content = Host.Frame(native)
			if readout and presentation == "circular" then
				local bounds = ctx.observe.TextBounds(readout)
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
			root:AddTag("facet-progress-indeterminate")
			ctx.playWhileShown(timeline, root)
		end
		return root
	end)
end
