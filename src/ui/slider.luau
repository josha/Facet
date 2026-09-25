--!strict
local valueModel = require("./input_value")
local InputTypes = require("./input_types")
local Shared = require("./types")
local ComposeTypes = require("../vendor/compose/core")

type Spec = InputTypes.SliderImplementationProps
type Range = InputTypes.SliderRange
type Thumb = InputTypes.SliderThumb
type NumberSpec = { value: Shared.Value<number>, onChange: ((number) -> ())? }
export type Adjust = {
	vertical: boolean?,
	guard: boolean?,
	arrows: ((ComposeTypes.Use, number) -> boolean)?,
	extra: (((ComposeTypes.Use) -> boolean) -> ())?,
}
export type Helpers = {
	enabled: (Spec | NumberSpec, ComposeTypes.Use?) -> boolean,
	writable: (unknown) -> boolean,
	attributes: (Instance, Shared.Attributes) -> Instance,
	valueAttributes: (GuiObject, NumberSpec, valueModel.Model) -> (),
	adjustment: (GuiObject, NumberSpec, (number) -> (), (() -> ())?, number, number, Adjust?) -> (),
	paintedPart: (Shared.FrameProps, Shared.Value<string>?, string, string) -> Frame,
}

local SLIDER_KEYS = {
	"value",
	"min",
	"max",
	"step",
	"format",
	"enabled",
	"onChange",
	"onCommit",
	"label",
	"tapToPosition",
	"row",
	"thumbImage",
	"trackImage",
	"axis",
	"range",
	"minGap",
	"thumb",
	"thumbContent",
	"trackContent",
	"rotation",
	"controlSize",
}
local THICKNESS: { [string]: number } = { xsmall = 3, compact = 4, regular = 6, large = 8 }
local KNOB = 24

local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

return function(ctx: Shared.Context, UI: InputTypes.InputControls, h: Helpers): ()
	local runtime, Host, Compose, read = ctx.runtime, ctx.Host, ctx.Compose, ctx.read
	local D, D2, V2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local function dynamic(source: unknown): boolean
		return Compose.isReadable(source) or type(source) == "function"
	end
	local function construction(spec: Spec)
		for _, key in { "axis", "range", "minGap", "thumb", "tapToPosition" } do
			local source = (spec :: { [unknown]: unknown })[key]
			if dynamic(source) then
				error(`Facet UI.Slider: {key} is decided at construction; pass a plain value`, 0)
			end
		end
		assert(spec.axis == nil or spec.axis == "x" or spec.axis == "y", "Facet UI.Slider: axis must be x or y")
		assert(
			spec.thumb == nil or spec.thumb == "always" or spec.thumb == "auto" or spec.thumb == "none",
			"Facet UI.Slider: thumb must be always | auto | none"
		)
		assert(spec.range == nil or type(spec.range) == "boolean", "Facet UI.Slider: range must be a boolean")
		assert(
			spec.thumbContent == nil or type(spec.thumbContent) == "function",
			"Facet UI.Slider: thumbContent must be a function"
		)
		assert(
			spec.trackContent == nil or type(spec.trackContent) == "function",
			"Facet UI.Slider: trackContent must be a function"
		)
		if spec.thumbContent and spec.thumbImage then
			error("Facet UI.Slider: thumbImage and thumbContent both draw the handle; pass one", 0)
		end
		if spec.trackContent and spec.trackImage then
			error("Facet UI.Slider: trackImage and trackContent both draw the track; pass one", 0)
		end
		if spec.controlSize ~= nil then
			ctx.controlSize(spec.controlSize, "height")
		end
	end
	local function thickness(spec: Spec, use: ComposeTypes.Use?): number
		local rung = read(spec.controlSize, use)
		return THICKNESS[rung or "regular"] or THICKNESS.regular
	end
	local function unrotate(track: GuiObject, position: Vector2 | Vector3, degrees: number): (number, number)
		local size, at = track.AbsoluteSize, track.AbsolutePosition
		local cx, cy = at.X + size.X / 2, at.Y + size.Y / 2
		local dx, dy = position.X - cx, position.Y - cy
		if degrees % 360 ~= 0 then
			local a = -math.rad(degrees)
			dx, dy = dx * math.cos(a) - dy * math.sin(a), dx * math.sin(a) + dy * math.cos(a)
		end
		return dx + size.X / 2, dy + size.Y / 2
	end
	local function travelAt(
		track: GuiObject,
		position: Vector2 | Vector3,
		vertical: boolean,
		degrees: number
	): (number, number)
		local size = track.AbsoluteSize
		local x, y = unrotate(track, position, degrees)
		if vertical then
			return size.Y - y, size.Y
		end
		return x, size.X
	end
	local function fractionAt(point: number, length: number, side: number): number?
		local travel = length - side
		if length <= 0 then
			return nil
		end
		return if travel > 0 then (point - side / 2) / travel else 0.5
	end
	local function knob(
		spec: Spec,
		name: string,
		thumb: Thumb,
		value: (ComposeTypes.Use?) -> number,
		fraction: (ComposeTypes.Use?) -> number,
		dragging: ComposeTypes.Readable<boolean>,
		shown: (ComposeTypes.Use) -> boolean,
		vertical: boolean,
		target: boolean,
		extent: ComposeTypes.Cell<number>
	): Frame
		local knobSize = function(use: ComposeTypes.Use?): number
			if spec.controlSize == nil then
				return KNOB
			end
			local icon = ctx.controlSize(spec.controlSize, "iconSize", use)
			return math.max(8, KNOB + icon - ctx.controlSize("regular", "iconSize", use))
		end
		local knobBox = function(use: ComposeTypes.Use): UDim2
			local side = knobSize(use)
			return D2.fromOffset(side, side)
		end
		local knobFloor = function(use: ComposeTypes.Use): Vector2
			local side = knobSize(use)
			return V2.new(side, side)
		end
		local size = if target then 44 else KNOB
		local native: Shared.FrameNativeProps = {
			Name = name,
			AnchorPoint = V2.new(0.5, 0.5),
			Position = function(use: ComposeTypes.Use)
				local f, side = fraction(use), use(extent)
				return if vertical then D2.new(0.5, 0, 1 - f, (f - 0.5) * side) else D2.new(f, (0.5 - f) * side, 0.5, 0)
			end,
			Size = D2.fromOffset(size, size),
			ZIndex = 3,
		}
		local function measure(art: GuiObject): ()
			if spec.thumb == "none" then
				return
			end
			local measured = ctx.observe(art, "AbsoluteSize")
			Compose.watch(function(use: ComposeTypes.Use)
				local box = use(measured) :: Vector2
				local side = if vertical then box.Y else box.X
				extent:set(if side > 0 then side else knobSize(use))
			end)
		end
		local content = spec.thumbContent
		if not target and not content then
			local part = h.paintedPart({
				Name = name,
				AnchorPoint = V2.new(0.5, 0.5),
				Position = native.Position,
				Size = knobBox,
				Visible = shown,
				ZIndex = 3,
				Host.UICorner({ CornerRadius = D.new(0.5, 0) }),
			}, spec.thumbImage, "slider-thumb", "sliderThumb")
			measure(part)
			return part
		end
		local mark: GuiObject
		if content then
			local built = content({
				thumb = thumb,
				value = Compose.formula(function(use: ComposeTypes.Use)
					return value(use)
				end),
				fraction = Compose.formula(function(use: ComposeTypes.Use)
					return fraction(use)
				end),
				dragging = dragging,
				enabled = Compose.formula(function(use: ComposeTypes.Use)
					return h.enabled(spec, use)
				end),
			})
			mark = Host.Frame({
				Name = "Knob",
				BackgroundTransparency = 1,
				AnchorPoint = V2.new(0.5, 0.5),
				Position = D2.fromScale(0.5, 0.5),
				Size = D2.fromOffset(0, 0),
				AutomaticSize = E.AutomaticSize.XY,
				Visible = shown,
				Host.UISizeConstraint({ MinSize = knobFloor }) :: ComposeTypes.Child,
				Host.UIListLayout({
					HorizontalAlignment = E.HorizontalAlignment.Center,
					VerticalAlignment = E.VerticalAlignment.Center,
				}) :: ComposeTypes.Child,
				built :: ComposeTypes.Child,
			})
		else
			mark = h.paintedPart({
				Name = "Knob",
				AnchorPoint = V2.new(0.5, 0.5),
				Position = D2.fromScale(0.5, 0.5),
				Size = knobBox,
				Visible = shown,
				Host.UICorner({ CornerRadius = D.new(0.5, 0) }),
			}, spec.thumbImage, "slider-thumb", "sliderThumb")
		end
		measure(if content then mark:FindFirstChildWhichIsA("GuiObject") or mark else mark)
		if not target then
			native.BackgroundTransparency = 1
			native.Size = D2.fromOffset(0, 0)
			native.AutomaticSize = E.AutomaticSize.XY
			table.insert(native, Host.UISizeConstraint({ MinSize = knobFloor }))
			table.insert(native, mark)
			return Host.Frame(native)
		end
		native.BackgroundTransparency = 1
		native.Selectable = function(use: ComposeTypes.Use)
			return h.enabled(spec, use)
		end
		table.insert(native, mark)
		return Host.Frame(native)
	end

	local slider = ctx.construct("Slider", function(spec: Spec): Frame
		construction(spec)
		local isRange = spec.range == true
		local vertical = spec.axis == "y"
		local mode = spec.thumb or "always"
		local model = valueModel(spec :: valueModel.Options, read)
		local gap = spec.minGap or 0
		assert(
			spec.minGap == nil or (finite(spec.minGap) and gap >= 0 and gap <= model.max - model.min),
			"Facet UI.Slider: minGap must be a number from 0 to the width of the range"
		)
		local function problem(pair: unknown): string?
			if type(pair) ~= "table" then
				return "a range value is { lower, upper }"
			end
			local fields = pair :: { [string]: unknown }
			local lower, upper = fields.lower, fields.upper
			if not finite(lower) or not finite(upper) then
				return "a range value has finite lower and upper numbers"
			end
			local low, high = lower :: number, upper :: number
			if low > high then
				return `lower {low} is above upper {high}`
			end
			if high - low < gap - 1e-9 then
				return `the pair {low}-{high} is narrower than minGap {gap}`
			end
			return nil
		end
		if isRange then
			local initial = read(spec.value :: Shared.Value<Range>)
			local why = problem(initial)
			if why then
				error(`Facet UI.Slider: {why}`, 0)
			end
			assert(
				h.writable(spec.value) or type(spec.onChange) == "function",
				"Facet.Slider: editing a read-only value requires onChange"
			)
		else
			assert(type(read(spec.value)) == "number", "Facet.Slider: value must resolve to a number")
			assert(
				h.writable(spec.value) or type(spec.onChange) == "function",
				"Facet.Slider: editing a read-only value requires onChange"
			)
		end
		local input = ctx.config.services.UserInputService
		local preferred = if input then ctx.observe(input, "PreferredInput") else Compose.cell(nil)
		local degrees = function(use: ComposeTypes.Use?): number
			local turn = read(spec.rotation, use)
			assert(turn == nil or finite(turn), "Facet UI.Slider: rotation must be a finite number of degrees")
			return turn or 0
		end
		local track: Frame
		local extents: { [Thumb]: ComposeTypes.Cell<number> } = {}
		local function extent(thumb: Thumb): ()
			extents[thumb] = Compose.cell(if mode == "none" then 0 else KNOB)
		end
		if isRange then
			extent("lower")
			extent("upper")
		else
			extent("value")
		end
		local function extentOf(thumb: Thumb): ComposeTypes.Cell<number>
			return assert(extents[thumb])
		end
		local dragging = Compose.cell(false)
		local hovered = Compose.cell(false)
		local selectedInside = Compose.cell(false)
		local function shown(use: ComposeTypes.Use): boolean
			if mode == "none" then
				return false
			end
			if mode == "always" then
				return true
			end
			return use(hovered) or use(selectedInside) or use(dragging) or use(preferred) == E.PreferredInput.Touch
		end
		local diagnostics: { string } = {}
		local last: Range? = if isRange then table.clone(read(spec.value :: Shared.Value<Range>)) else nil
		local legal = Compose.cell(last)
		if isRange then
			Compose.watch(function(use: ComposeTypes.Use)
				local pair = read(spec.value :: Shared.Value<Range>, use)
				local why = problem(pair)
				if why then
					if diagnostics[#diagnostics] ~= why then
						table.insert(diagnostics, why)
						if #diagnostics > 16 then
							table.remove(diagnostics, 1)
						end
					end
					return
				end
				legal:set({ lower = pair.lower, upper = pair.upper })
			end)
		end
		local function pair(use: ComposeTypes.Use?): Range
			return assert(read(legal, use))
		end
		local function single(use: ComposeTypes.Use?): number
			return read(spec.value :: Shared.Value<number>, use)
		end
		local detent = ctx.config.pressHaptic
		local function proposeSingle(value: number): boolean
			if not h.enabled(spec) then
				return false
			end
			local nextValue = model.quantize(value)
			if single() == nextValue then
				return false
			end
			if spec.onChange then
				spec.onChange(nextValue)
			else
				(spec.value :: ComposeTypes.Cell<number>):set(nextValue)
			end
			local moved = single() == nextValue
			if moved and detent and spec.step ~= nil then
				detent:Play()
			end
			return moved
		end
		local function proposePair(nextPair: Range, thumb: Thumb): boolean
			if not h.enabled(spec) then
				return false
			end
			local current = pair()
			if current.lower == nextPair.lower and current.upper == nextPair.upper then
				return false
			end
			if spec.onChange then
				spec.onChange({ lower = nextPair.lower, upper = nextPair.upper }, { thumb = thumb })
			else
				(spec.value :: ComposeTypes.Cell<Range>):set({ lower = nextPair.lower, upper = nextPair.upper })
			end
			if detent and spec.step ~= nil then
				detent:Play()
			end
			return true
		end
		local function moveThumb(thumb: Thumb, value: number): boolean
			local current = pair()
			local nextPair = { lower = current.lower, upper = current.upper }
			if thumb == "lower" then
				nextPair.lower = math.min(model.quantize(value), current.upper - gap)
				nextPair.lower = math.max(nextPair.lower, model.min)
			else
				nextPair.upper = math.max(model.quantize(value), current.lower + gap)
				nextPair.upper = math.min(nextPair.upper, model.max)
			end
			return proposePair(nextPair, thumb)
		end
		local function commit(thumb: Thumb)
			local onCommit = spec.onCommit
			if onCommit then
				if isRange then
					local current = pair()
					onCommit({ lower = current.lower, upper = current.upper }, { thumb = thumb })
				else
					onCommit(single())
				end
			end
		end

		local gesture: { thumb: Thumb, snapshot: unknown }? = nil
		local function cancel()
			local active = gesture
			if active == nil then
				return
			end
			gesture = nil
			dragging:set(false)
			if isRange then
				local snapshot = active.snapshot :: Range
				proposePair({ lower = snapshot.lower, upper = snapshot.upper }, active.thumb)
			else
				local snapshot = active.snapshot :: number
				if single() ~= snapshot then
					if spec.onChange then
						spec.onChange(snapshot)
					else
						(spec.value :: ComposeTypes.Cell<number>):set(snapshot)
					end
				end
			end
		end
		local function begin(thumb: Thumb)
			gesture = { thumb = thumb, snapshot = if isRange then table.clone(pair()) else single() }
			dragging:set(true)
		end
		local function drive(position: Vector2 | Vector3)
			local active = gesture
			if active == nil then
				return
			end
			local point, length = travelAt(track, position, vertical, degrees())
			local f = fractionAt(point, length, extentOf(active.thumb):peek())
			if f == nil then
				return
			end
			local value = model.min + math.clamp(f, 0, 1) * (model.max - model.min)
			if isRange then
				moveThumb(active.thumb, value)
			else
				proposeSingle(value)
			end
		end
		local function finish()
			local active = gesture
			if active == nil then
				return
			end
			gesture = nil
			dragging:set(false)
			commit(active.thumb)
		end
		local function nearest(position: Vector2 | Vector3): Thumb
			local point, length = travelAt(track, position, vertical, degrees())
			local current = pair()
			local function centre(thumb: Thumb): number
				local side = extentOf(thumb):peek()
				local value = if thumb == "lower" then current.lower else current.upper
				return side / 2 + model.fraction(value) * math.max(0, length - side)
			end
			local low, high = centre("lower"), centre("upper")
			if current.lower == current.upper then
				if point < low then
					return "lower"
				elseif point > high then
					return "upper"
				end
				return if current.lower <= model.min then "upper" else "lower"
			end
			return if math.abs(point - low) <= math.abs(point - high) then "lower" else "upper"
		end
		local detector = Host.UIDragDetector "Drag" {
			ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
			Enabled = function(use: ComposeTypes.Use)
				return h.enabled(spec, use)
			end,
			DragStart = function(position)
				if not h.enabled(spec) then
					return
				end
				begin(if isRange then nearest(position) else "value")
				if spec.tapToPosition ~= false then
					drive(position)
				end
			end,
			DragContinue = function(position)
				drive(position)
			end,
			DragEnd = finish,
		}
		local function fraction(value: number): number
			return model.fraction(value)
		end
		local thin = function(use: ComposeTypes.Use)
			return thickness(spec, use)
		end
		local trackChildren: { ComposeTypes.Child } = {}
		if spec.trackContent then
			local content = spec.trackContent()
			table.insert(
				trackChildren,
				Host.Frame({
					Name = "TrackContent",
					BackgroundTransparency = 1,
					AnchorPoint = V2.new(0.5, 0.5),
					Position = D2.fromScale(0.5, 0.5),
					Size = D2.fromScale(1, 1),
					content :: ComposeTypes.Child,
				})
			)
		else
			table.insert(
				trackChildren,
				h.paintedPart({
					Name = "Rail",
					Size = function(use: ComposeTypes.Use)
						return if vertical then D2.new(0, thin(use), 1, 0) else D2.new(1, 0, 0, thin(use))
					end,
					Position = D2.fromScale(if vertical then 0.5 else 0, 0.5),
					AnchorPoint = V2.new(if vertical then 0.5 else 0, 0.5),
					ctx.corner(3),
				}, spec.trackImage, "slider-rail", "sliderTrack")
			)
			local fill = ctx.styled(
				Host.Frame "Fill" {
					Size = function(use: ComposeTypes.Use)
						local low, high, lowShift, highShift
						if isRange then
							local current = pair(use)
							low, high = fraction(current.lower), fraction(current.upper)
							lowShift = (0.5 - low) * use(extentOf("lower"))
							highShift = (0.5 - high) * use(extentOf("upper"))
						else
							low, high, lowShift = 0, fraction(single(use)), 0
							highShift = (0.5 - high) * use(extentOf("value"))
						end
						return if vertical
							then D2.new(0, thin(use), high - low, highShift - lowShift)
							else D2.new(high - low, highShift - lowShift, 0, thin(use))
					end,
					Position = function(use: ComposeTypes.Use)
						local low = if isRange then fraction(pair(use).lower) else 0
						local shift = if isRange then (0.5 - low) * use(extentOf("lower")) else 0
						return if vertical then D2.new(0.5, 0, 1 - low, -shift) else D2.new(low, shift, 0.5, 0)
					end,
					AnchorPoint = V2.new(if vertical then 0.5 else 0, if vertical then 1 else 0.5),
					ctx.corner(3),
				},
				"slider-fill"
			)
			ctx.skin(fill, "barFill")
			table.insert(trackChildren, fill)
		end
		local handles: { [Thumb]: Frame } = {}
		if isRange then
			for index = 1, 2 do
				local thumb: Thumb = if index == 1 then "lower" else "upper"
				local handle = knob(
					spec,
					if thumb == "lower" then "HandleLower" else "HandleUpper",
					thumb,
					function(use)
						local current = pair(use)
						return if thumb == "lower" then current.lower else current.upper
					end,
					function(use)
						local current = pair(use)
						return fraction(if thumb == "lower" then current.lower else current.upper)
					end,
					dragging,
					shown,
					vertical,
					true,
					extentOf(thumb)
				)
				runtime.mountFragment(function()
					return {
						Host.UIDragDetector "Drag" {
							ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
							Enabled = function(use: ComposeTypes.Use)
								return h.enabled(spec, use)
							end,
							DragStart = function()
								if h.enabled(spec) then
									begin(thumb)
								end
							end,
							DragContinue = function(position)
								drive(position)
							end,
							DragEnd = finish,
						},
					}
				end, handle)
				handles[thumb] = handle
				table.insert(trackChildren, handle)
			end
		else
			table.insert(
				trackChildren,
				knob(spec, "Thumb", "value", function(use)
					return single(use)
				end, function(use)
					return fraction(single(use))
				end, dragging, shown, vertical, false, extentOf("value"))
			)
		end
		table.insert(trackChildren, detector)
		table.insert(trackChildren, Host.UISizeConstraint({ MinSize = V2.new(44, 44) }))
		local trackProps: Shared.FrameNativeProps = {
			Name = "Track",
			Size = if vertical then D2.new(0, 44, 1, 0) else D2.new(1, 0, 0, 44),
			BackgroundTransparency = 1,
			Rotation = if spec.rotation ~= nil
				then function(use: ComposeTypes.Use)
					return degrees(use)
				end
				else nil,
			Selectable = if isRange
				then false
				else function(use: ComposeTypes.Use)
					return h.enabled(spec, use)
				end,
		}
		for _, child in trackChildren do
			table.insert(trackProps, child)
		end
		track = ctx.styled(Host.Frame(trackProps), "slider-track")
		local state = ctx.observe(track, "GuiState")
		Compose.watch(function(use: ComposeTypes.Use)
			hovered:set(use(state) == E.GuiState.Hover)
		end)
		local trackLabel = (if spec.row then spec.row.title else nil) or spec.label
		if trackLabel ~= nil then
			h.attributes(track, {
				AccessibleLabel = (function(use: ComposeTypes.Use): string
					return read(trackLabel, use) or ""
				end) :: Shared.Value<Shared.AttributeValue?>,
			})
		end
		local gui = ctx.config.services.GuiService
		local selection = if gui then ctx.observe(gui, "SelectedObject") else nil
		if selection then
			local observed = selection
			Compose.watch(function(use: ComposeTypes.Use)
				local target = use(observed) :: Instance?
				selectedInside:set(target ~= nil and (target == track or target:IsDescendantOf(track)))
			end)
		end
		if input then
			local first = true
			Compose.watch(function(use: ComposeTypes.Use)
				use(preferred)
				if not first then
					cancel()
				end
				first = false
			end)
		end
		Compose.watch(function(use: ComposeTypes.Use)
			if not h.enabled(spec, use) then
				cancel()
			end
		end)
		if isRange then
			for index = 1, 2 do
				local thumb: Thumb = if index == 1 then "lower" else "upper"
				local handle = handles[thumb]
				local engaged = Compose.cell(false)
				local proxy: NumberSpec = {
					value = function(use: ComposeTypes.Use)
						local current = pair(use)
						return if thumb == "lower" then current.lower else current.upper
					end,
					onChange = function() end,
				}
				local function gamepad(use: ComposeTypes.Use?): boolean
					return read(preferred, use) == E.PreferredInput.Gamepad
				end
				h.adjustment(
					handle,
					proxy,
					function(direction)
						local current = pair()
						local base = if thumb == "lower" then current.lower else current.upper
						if moveThumb(thumb, model.stepped(base, direction)) then
							commit(thumb)
						end
					end,
					function()
						cancel()
						engaged:set(false)
					end,
					model.min,
					model.max,
					{
						vertical = vertical,
						guard = true,
						arrows = function(use: ComposeTypes.Use)
							return not gamepad(use) or use(engaged)
						end,
						extra = function(active)
							ctx.action(handle, "Engage", { E.KeyCode.ButtonA }, function(use: ComposeTypes.Use)
								return active(use) and gamepad(use) and not use(engaged)
							end, function()
								engaged:set(true)
							end, { priority = 100 })
						end,
					}
				)
				if selection then
					local observed = selection
					Compose.watch(function(use: ComposeTypes.Use)
						if use(observed) ~= handle then
							engaged:set(false)
						end
					end)
				end
				h.attributes(handle, {
					AccessibleLabel = function(use: ComposeTypes.Use): string
						local named = read(spec.label, use)
						local side = if thumb == "lower" then "lower" else "upper"
						return if named and named ~= "" then `{named} {side}` else `Range {side}`
					end,
					value = function(use: ComposeTypes.Use): number
						return read(proxy.value, use)
					end,
					minimum = model.min,
					maximum = model.max,
				})
			end
		else
			h.adjustment(track, (spec :: unknown) :: NumberSpec, function(direction)
				if proposeSingle(model.stepped(single(), direction)) then
					commit("value")
				end
			end, cancel, model.min, model.max, { vertical = vertical, guard = true })
		end
		local readout = ctx.text({
			Name = "Value",
			Text = function(use: ComposeTypes.Use)
				if isRange then
					local current = pair(use)
					return `{model.format(current.lower)} – {model.format(current.upper)}`
				end
				return model.format(single(use))
			end,
		})
		if not spec.row and not vertical then
			runtime.decorate(readout, {
				Size = D2.fromOffset(44, 0),
				AutomaticSize = E.AutomaticSize.XY,
				TextXAlignment = E.TextXAlignment.Right,
			})
		end
		local parts: { ComposeTypes.Child } = {}
		if spec.row then
			local row = spec.row
			local header = { readout }
			if spec.label or row.title then
				table.insert(
					header,
					1,
					ctx.text({
						Name = "Label",
						Text = row.title or spec.label,
						Size = D2.fromOffset(0, 0),
						AutomaticSize = E.AutomaticSize.Y,
						TextWrapped = true,
						Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
					})
				)
			end
			table.insert(
				parts,
				ctx.row(header, { Name = "Header", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
			)
			if row.description then
				table.insert(
					parts,
					ctx.text({
						Name = "Description",
						Text = row.description,
						Size = D2.new(1, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.Y,
						TextWrapped = true,
					})
				)
			end
			table.insert(parts, track)
		else
			if spec.label then
				table.insert(
					parts,
					ctx.text({
						Name = "Label",
						Text = spec.label,
						TextTruncate = E.TextTruncate.AtEnd,
						Host.UIFlexItem({ FlexMode = E.UIFlexMode.Shrink }) :: ComposeTypes.Child,
						Host.UIPadding({ PaddingRight = ctx.types.UDim.new(0, KNOB / 2 + 8) }) :: ComposeTypes.Child,
					})
				)
			end
			if not vertical then
				runtime.decorate(track, { Size = D2.fromOffset(0, 44) })
			end
			runtime.mount(function()
				return Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill })
			end, track)
			table.insert(parts, track)
			table.insert(parts, readout)
		end
		local native = ctx.props(spec, SLIDER_KEYS, {
			Size = if vertical then D2.new(0, 0, 1, 0) else D2.new(1, 0, 0, 0),
			AutomaticSize = if vertical then E.AutomaticSize.X else E.AutomaticSize.Y,
		})
		local node: Frame
		if spec.row and not vertical then
			local body = ctx.column(parts, {
				Name = "Body",
				Size = D2.new(0, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
			})
			local columns: { ComposeTypes.Child } = { body, Host.UIPadding({}) }
			if spec.row.icon then
				table.insert(columns, 1, ctx.icon(spec.row.icon, { Name = "LeadingIcon" }))
			end
			node = ctx.styled(ctx.row(columns, native), "slider")
			assert(node:FindFirstChildWhichIsA("UIListLayout")).VerticalAlignment = E.VerticalAlignment.Top
			node:AddTag("facet-slider-settings")
		else
			node =
				ctx.styled(if spec.row or vertical then ctx.column(parts, native) else ctx.row(parts, native), "slider")
		end
		if vertical then
			local layout = assert(node:FindFirstChildWhichIsA("UIListLayout"))
			layout.HorizontalAlignment = E.HorizontalAlignment.Center
		elseif not spec.row then
			assert(node:FindFirstChildWhichIsA("UIListLayout")).VerticalAlignment = E.VerticalAlignment.Center
		end
		if isRange then
			h.attributes(node, {
				lower = function(use: ComposeTypes.Use)
					return pair(use).lower
				end,
				upper = function(use: ComposeTypes.Use)
					return pair(use).upper
				end,
				minimum = model.min,
				maximum = model.max,
				semanticValue = function(use: ComposeTypes.Use)
					local current = pair(use)
					return `{model.format(current.lower)} to {model.format(current.upper)} of {model.min} to {model.max}`
				end,
				diagnostics = function(use: ComposeTypes.Use)
					use(legal)
					read(spec.value :: Shared.Value<Range>, use)
					return table.concat(diagnostics, "\n")
				end,
			})
		else
			h.valueAttributes(node, (spec :: unknown) :: NumberSpec, model)
		end
		Compose.cleanup(cancel)
		return node
	end)
	UI.Slider = (slider :: unknown) :: typeof(UI.Slider)
end
