--!strict
local dragPointer = require("./drag_pointer")
local inputKit = require("./input_kit")
local InputTypes = require("./input_types")
local Shared = require("./types")
local ControlTypes = require("./control_types")
local InputProps = require("./input_props")
local ComposeTypes = require("../vendor/compose/core")

type LevelSpec = Shared.TextButtonProps & inputKit.ValueState<number> & InputTypes.LevelOptions & {
	segment: ("bar" | "glyph" | "image")?,
	segmentSize: InputTypes.LevelSize?,
	starSize: InputTypes.LevelSize?,
	glyphs: InputTypes.Glyphs?,
	images: InputTypes.Images?,
	tint: InputTypes.Tint?,
}

return function(ctx: Shared.Context, UI: ControlTypes.Controls, kit: inputKit.Kit): ()
	local runtime, Host, Compose = ctx.runtime, ctx.Host, ctx.Compose
	local read = ctx.read
	local D, D2, V2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local enabled, changed = kit.enabled, kit.changed
	local function level(source: InputProps.RatingProps | InputProps.LevelPickerProps, rating: boolean): TextButton
		local spec = (source :: Shared.TextButtonProps) :: LevelSpec
		kit.requireValue(spec, "number", if rating then "Rating" else "LevelPicker")
		local count = spec.count or 5
		assert(
			type(count) == "number" and count > 0 and count % 1 == 0 and count < math.huge,
			"Facet.LevelPicker: count must be a positive integer"
		)
		local minimum = if spec.allowZero == false then 1 else 0
		local segment = if rating then "glyph" else spec.segment or "bar"
		assert(table.find({ "bar", "glyph", "image" }, segment), "Facet.LevelPicker: invalid segment")
		assert(segment == "glyph" or spec.glyphs == nil, "Facet.LevelPicker: glyphs require glyph segments")
		assert(segment == "image" or spec.images == nil, "Facet.LevelPicker: images require image segments")
		local markSizes: { [string]: number } = { small = 20, medium = 28, large = 36 }
		local markSize =
			assert(markSizes[spec.starSize or spec.segmentSize or "small"], "Facet.LevelPicker: invalid size")
		local glyphs: InputTypes.Glyphs = spec.glyphs or { filled = "★", empty = "☆" }
		local function interactive(use)
			return enabled(spec, use) and spec.readOnly ~= true
		end
		local function apply(value)
			if interactive() then
				changed(spec, math.clamp(value, minimum, count))
			end
		end
		local room, drawn = Compose.cell(math.huge), Compose.cell(math.huge)
		local markExtent = Compose.formula(function(use: ComposeTypes.Use): number
			local width = math.min(use(room), use(drawn))
			return math.min(markSize, math.max(1, math.floor((width - math.max(0, count - 1) * 2) / count)))
		end)
		local marks: { ComposeTypes.Child } = {}
		for index = 1, count do
			local filled = function(use: ComposeTypes.Use)
				return read(spec.value, use) >= index
			end
			local name = `Level{index}`
			local size = function(use: ComposeTypes.Use): UDim2
				return D2.fromOffset(use(markExtent), use(markExtent))
			end
			local mark: GuiObject
			local paint: "TextColor3" | "ImageColor3" | "BackgroundColor3"
			if segment == "glyph" then
				mark, paint =
					ctx.text({
						Name = name,
						Size = size,
						BackgroundTransparency = 1,
						Selectable = false,
						TextSize = markExtent,
						TextXAlignment = E.TextXAlignment.Center,
						Text = function(use: ComposeTypes.Use)
							return if filled(use) then glyphs.filled else glyphs.empty
						end,
					}), "TextColor3"
			elseif segment == "image" then
				local images = spec.images
				assert(
					images and images.filled and images.empty,
					"Facet.LevelPicker: image segments require filled and empty images"
				)
				mark, paint =
					Host.ImageLabel({
						Name = name,
						Size = size,
						BackgroundTransparency = 1,
						Selectable = false,
						Image = function(use: ComposeTypes.Use)
							return if filled(use) then images.filled else images.empty
						end,
					}), "ImageColor3"
			else
				mark, paint =
					ctx.styled(
						Host.Frame(name)({
							Size = function(use: ComposeTypes.Use): UDim2
								return D2.fromOffset(use(markExtent), math.round(use(markExtent) * (0.3 + 0.7 * index / count)))
							end,
							Selectable = false,
							ctx.corner(2),
						}),
						"level-segment"
					), "BackgroundColor3"
				local bar = mark
				Compose.watch(function(use: ComposeTypes.Use)
					if filled(use) then
						bar:AddTag("facet-level-on")
					elseif bar:HasTag("facet-level-on") then
						bar:RemoveTag("facet-level-on")
					end
				end)
			end
			if spec.tint then
				Compose.watch(function(use: ComposeTypes.Use)
					local color = read(if filled(use) then spec.tint.filled else spec.tint.empty, use)
					if color ~= nil then
						if mark:IsA("TextLabel") then
							mark.TextColor3 = color
						elseif mark:IsA("ImageLabel") then
							mark.ImageColor3 = color
						else
							(mark :: Frame).BackgroundColor3 = color
						end
					else
						mark:ResetPropertyToDefault(paint)
					end
				end)
			end
			table.insert(marks, mark)
		end
		local contentProps: Shared.FrameNativeProps = {
			Name = "Marks",
			Size = D2.fromOffset(0, 0),
			AutomaticSize = E.AutomaticSize.XY,
			BackgroundTransparency = 1,
			AnchorPoint = V2.new(0.5, 0.5),
			Position = D2.fromScale(0.5, 0.5),
			kit.lists.list({ gap = 2, align = "end" }, false),
		}
		for index, mark in marks do
			runtime.decorate(mark, { LayoutOrder = index })
			contentProps[#contentProps + 1] = mark
		end
		local markContent = Host.Frame(contentProps)

		local effectiveInput = ctx.effectiveInput()
		local function spacing(use: ComposeTypes.Use, width: number): number
			local reach = if effectiveInput(use) == "Touch" then ctx.metric("targetSizes.minimum", use) else 0
			local extent = use(markExtent)
			if extent < markSize then
				return 2
			end
			local fits = if count > 1 then math.floor((width - count * extent) / (count - 1)) else math.huge
			return math.max(2, math.min(reach - extent, fits))
		end
		local function gap(use: ComposeTypes.Use): number
			return spacing(use, use(room))
		end
		runtime.decorate(assert(markContent:FindFirstChildWhichIsA("UIListLayout")), {
			Padding = function(use: ComposeTypes.Use): UDim
				return D.new(0, math.min(gap(use), spacing(use, use(drawn))))
			end,
		})

		local root: TextButton
		local dragging: boolean?
		local snapshot: number?
		local suppressActivation: boolean?
		local dragOrigin: Vector2?
		local moved = false
		local target: number?
		local function valueAt(position: Vector2 | Vector3): number
			local width = markContent.AbsoluteSize.X
			local origin = markContent.AbsolutePosition.X
			if width <= 0 then
				width, origin = root.AbsoluteSize.X, root.AbsolutePosition.X
			end
			if width <= 0 then
				return read(spec.value)
			end
			return math.clamp(math.floor((position.X - origin) / width * count) + 1, 1, count)
		end
		local function cancel()
			if dragging then
				dragging = false
				suppressActivation = true
				changed(spec, assert(snapshot))
			end
		end
		local p = ctx.props(
			spec,
			{
				"value",
				"count",
				"allowZero",
				"enabled",
				"readOnly",
				"glyphs",
				"images",
				"tint",
				"segment",
				"starSize",
				"segmentSize",
				"onChange",
			},
			{
				PressHapticEffect = if spec.PressHapticEffect == nil and ctx.haptic(true)
					then Compose.static(ctx.haptic(true))
					else nil,
				Text = "",
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Size = function(use: ComposeTypes.Use): UDim2
					return D2.fromOffset(count * markSize + math.max(0, count - 1) * gap(use), math.max(44, markSize))
				end,
				Selectable = interactive,
				Interactable = interactive,
				markContent :: ComposeTypes.Child,
				Host.UIFlexItem({ FlexMode = E.UIFlexMode.Shrink }),
				Host.UIDragDetector "Scrub" {
					ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
					Enabled = interactive,
					DragStart = function(position)
						if interactive() then
							dragging, snapshot = true, read(spec.value)
							dragOrigin = dragPointer(ctx, position)
							moved = false
							target = valueAt(assert(dragOrigin))
							apply(assert(target))
						end
					end,
					DragContinue = function(position)
						if dragging then
							local point = dragPointer(ctx, position)
							moved = moved or point ~= dragOrigin
							target = valueAt(point)
							apply(assert(target))
						end
					end,
					DragEnd = function()
						if dragging then
							dragging = false
							suppressActivation = true
							if not moved and target == snapshot and minimum == 0 then
								apply(0)
							end
						end
					end,
				},
			} :: Shared.TextButtonNativeProps
		)
		p.Activated = function(input: InputObject, clickCount: number)
			if suppressActivation then
				suppressActivation = false
				return
			end
			if input and input.Position then
				local value = valueAt(input.Position)
				apply(if value == read(spec.value) and minimum == 0 then 0 else value)
			else
				apply(if read(spec.value) == count then minimum else (read(spec.value) :: number) + 1)
			end
			if spec.Activated then
				spec.Activated(input, clickCount)
			end
		end
		root = ctx.styled(Host.TextButton(p), if rating then "rating" else "level-picker")
		local parent = ctx.observe.Parent(root)
		local unit = ctx.layoutUnit(root)
		local holderSize = Compose.cell(0)
		local observation = runtime.host.observation
		local stopHolder: (() -> ())? = nil
		Compose.watch(function(use: ComposeTypes.Use)
			local holder = use(parent) :: Instance?
			if stopHolder then
				stopHolder()
				stopHolder = nil
			end
			local fixed = holder
				and holder:IsA("GuiObject")
				and holder.AutomaticSize ~= E.AutomaticSize.X
				and holder.AutomaticSize ~= E.AutomaticSize.XY
			if fixed and observation then
				local frame = holder :: GuiObject
				local function measure()
					holderSize:set(frame.AbsoluteSize.X)
				end
				stopHolder = observation.observeProperty(frame, "AbsoluteSize", measure)
				measure()
			else
				holderSize:set(0)
			end
		end)
		Compose.cleanup(function()
			if stopHolder then
				stopHolder()
			end
		end)
		local own = ctx.observe.AbsoluteSize(root)
		Compose.watch(function(use: ComposeTypes.Use)
			local width, scale = use(holderSize), use(unit)
			room:set(if width > 0 and scale > 0 then width / scale else math.huge)
			local box = use(own).X
			drawn:set(if box > 0 and scale > 0 then box / scale else math.huge)
		end)
		local function published(use: ComposeTypes.Use): number
			return math.clamp(read(spec.value, use), minimum, count)
		end
		kit.attributes(root, {
			value = published,
			minimum = minimum,
			maximum = count,
			semanticValue = function(use: ComposeTypes.Use)
				return `{published(use)} of {minimum} to {count}`
			end,
		})
		runtime.connect(root, "InputBegan", function()
			suppressActivation = false
		end)
		kit.adjustment(root, spec, function(direction)
			apply((read(spec.value) :: number) + direction)
		end, cancel, minimum, count)
		Compose.watch(function(use: ComposeTypes.Use)
			if not interactive(use) then
				cancel()
			end
		end)
		local input = ctx.config.services.UserInputService
		if input then
			local preference = ctx.observe.PreferredInput(input)
			Compose.watch(function(use: ComposeTypes.Use)
				if use(preference) == E.PreferredInput.Gamepad then
					cancel()
				end
			end)
		end
		return root
	end

	UI.Rating = ctx.construct("Rating", function(spec: InputProps.RatingProps): TextButton
		return level(spec, true)
	end)
	UI.LevelPicker = ctx.construct("LevelPicker", function(spec: InputProps.LevelPickerProps): TextButton
		return level(spec, false)
	end)
end
