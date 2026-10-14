--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local Inputs = require("./input_types")
local InputProps = require("./input_props")
local Kit = require("./color_picker_kit")
local PickerState = require("./color_picker_state")

type Use = ComposeTypes.Use
type Hsv = Kit.Hsv
export type Sliders = {
	channelSlider: (
		string,
		string,
		number,
		(Hsv) -> number,
		(Hsv, number) -> Hsv,
		(() -> Instance)?,
		((Inputs.SliderKnob) -> Instance)?
	) -> Frame,
	bubble: ((Use) -> Color3, (Use) -> boolean, Shared.FrameNativeProps) -> Frame,
	ringKnob: ((Inputs.SliderKnob) -> (Use) -> Color3) -> (Inputs.SliderKnob) -> Instance,
	hueSlider: () -> Frame,
	slidersView: () -> Frame,
	opacitySlider: () -> Frame,
}

local RING, BUBBLE, SPACE = Kit.RING, Kit.BUBBLE, Kit.SPACE
local STRIP = 12
local CHECKER_CELLS = 24

return function(ctx: Shared.Context, UI: Kit.Deps, kit: Kit.Kit, state: PickerState.State): Sliders
	local Host, runtime = ctx.Host, ctx.runtime
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local color, ring, WHITE, LIGHT, DARK = kit.color, kit.ring, kit.WHITE, kit.LIGHT, kit.DARK
	local held, alphaHeld, canon = state.held, state.alphaHeld, state.canon
	local interactive, propose, proposeAlpha, commit, touch =
		state.interactive, state.propose, state.proposeAlpha, state.commit, state.touch

	local function channelSlider(
		name: string,
		words: string,
		max: number,
		get: (Hsv) -> number,
		with: (Hsv, number) -> Hsv,
		track: (() -> Instance)?,
		knob: ((Inputs.SliderKnob) -> Instance)?
	): Frame
		local props: InputProps.SliderProps = {
			Name = name,
			label = words,
			value = function(use: Use): number
				return get(use(canon)) * max
			end,
			min = 0,
			max = max,
			step = 1,
			enabled = function(use: Use): boolean
				return interactive(use)
			end,
			format = function(n: number): string
				return tostring(math.floor(n + 0.5))
			end,
			trackContent = track,
			thumbContent = knob,
			onChange = function(n: number)
				propose(with(canon:peek(), n / max))
			end,
			onCommit = function()
				commit()
			end,
		}
		local node = UI.Slider(props)
		local found = node:FindFirstChild("Track", true)
		if found then
			found:SetAttribute("AccessibleLabel", words)
		end
		return node
	end
	local function bubble(paint: (Use) -> Color3, shown: (Use) -> boolean, place: Shared.FrameNativeProps): Frame
		local props: Shared.FrameNativeProps = {
			Name = "Bubble",
			Size = D2.fromOffset(BUBBLE, BUBBLE),
			BorderSizePixel = 0,
			ZIndex = 6,
			BackgroundColor3 = paint,
			Visible = function(use: Use)
				return touch(use) and shown(use)
			end,
			ctx.corner(BUBBLE) :: Shared.Child,
			Host.UIStroke({ Color = WHITE, Thickness = 2, Transparency = 0 }),
		}
		for key, value in (place :: unknown) :: { [string]: unknown } do
			((props :: unknown) :: { [string]: unknown })[key] = value
		end
		return Host.Frame(props)
	end
	local function ringKnob(paint: (Inputs.SliderKnob) -> (Use) -> Color3): (Inputs.SliderKnob) -> Instance
		return function(info: Inputs.SliderKnob): Instance
			return Host.Frame "Mark" {
				Size = D2.fromOffset(RING, RING),
				BackgroundTransparency = 1,
				ring("Ring"),
				bubble(paint(info), function(use: Use)
					return use(info.dragging)
				end, {
					AnchorPoint = V2.new(0.5, 1),
					Position = D2.new(0.5, 0, 0, -SPACE),
				}),
			}
		end
	end
	local function hueStrip(): Instance
		local points: { ColorSequenceKeypoint } = {}
		for index = 0, 6 do
			table.insert(
				points,
				ctx.types.ColorSequenceKeypoint.new(index / 6, color.toColor({ h = (index % 6) / 6, s = 1, v = 1 }))
			)
		end
		return Host.Frame "HueStrip" {
			AnchorPoint = V2.new(0.5, 0.5),
			Position = D2.fromScale(0.5, 0.5),
			Size = D2.new(1, 0, 0, STRIP),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ctx.corner(STRIP) :: Shared.Child,
			Host.UIGradient "Rainbow" { Color = ctx.types.ColorSequence.new(points), Rotation = 0 },
		}
	end
	local function alphaStrip(): Instance
		local rows: { Shared.Child } = {}
		for row = 1, 2 do
			local cells: { Shared.Child } = {}
			for index = 1, CHECKER_CELLS do
				table.insert(
					cells,
					Host.Frame(`C{index}`)({
						Size = D2.fromScale(1 / CHECKER_CELLS, 1),
						BorderSizePixel = 0,
						LayoutOrder = index,
						BackgroundColor3 = if (index + row) % 2 == 0 then LIGHT else DARK,
					})
				)
			end
			local props: Shared.FrameNativeProps = {
				Name = if row == 1 then "Top" else "Bottom",
				Size = D2.fromScale(1, 0.5),
				Position = D2.fromScale(0, (row - 1) / 2),
				BackgroundTransparency = 1,
				Host.UIListLayout({
					FillDirection = E.FillDirection.Horizontal,
					SortOrder = E.SortOrder.LayoutOrder,
				}),
			}
			for _, cell in cells do
				props[#props + 1] = cell
			end
			table.insert(rows, Host.Frame(props))
		end
		local checker: Shared.FrameNativeProps = {
			Name = "Checker",
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
		}
		for _, row in rows do
			checker[#checker + 1] = row
		end
		return Host.Frame "AlphaStrip" {
			AnchorPoint = V2.new(0.5, 0.5),
			Position = D2.fromScale(0.5, 0.5),
			Size = D2.new(1, 0, 0, STRIP),
			BackgroundTransparency = 1,
			Host.Frame(checker),
			Host.Frame "Ramp" {
				Size = D2.fromScale(1, 1),
				BorderSizePixel = 0,
				BackgroundColor3 = function(use: Use)
					return use(held) or color.toColor(use(canon))
				end,
				Host.UIGradient({
					Transparency = ctx.types.NumberSequence.new({
						ctx.types.NumberSequenceKeypoint.new(0, 1),
						ctx.types.NumberSequenceKeypoint.new(1, 0),
					}),
					Rotation = 0,
				}),
			},
		}
	end
	local function hueSlider(): Frame
		return channelSlider(
			"Hue",
			"Hue",
			360,
			function(c: Hsv): number
				return c.h
			end,
			function(c: Hsv, f: number): Hsv
				return { h = f, s = c.s, v = c.v }
			end,
			hueStrip,
			ringKnob(function(info: Inputs.SliderKnob): (Use) -> Color3
				return function(use: Use): Color3
					return color.toColor({ h = use(info.value) / 360, s = 1, v = 1 })
				end
			end)
		)
	end

	local function slidersView(): Frame
		local sliders = {
			hueSlider(),
			channelSlider("Saturation", "Saturation", 100, function(c: Hsv): number
				return c.s
			end, function(c: Hsv, f: number): Hsv
				return { h = c.h, s = f, v = c.v }
			end),
			channelSlider("Brightness", "Brightness", 100, function(c: Hsv): number
				return c.v
			end, function(c: Hsv, f: number): Hsv
				return { h = c.h, s = c.s, v = f }
			end),
		}
		local labels: { TextLabel } = {}
		local bounds: { ComposeTypes.Readable<Vector2> } = {}
		for _, slider in sliders do
			local label = slider:FindFirstChild("Label") :: TextLabel
			table.insert(labels, label)
			table.insert(bounds, ctx.observe.TextBounds(label))
		end
		for _, label in labels do
			local padding = label:FindFirstChildWhichIsA("UIPadding")
			local inset = if padding then padding.PaddingLeft.Offset + padding.PaddingRight.Offset else 0
			runtime.decorate(label, {
				Size = function(use: Use)
					local widest = 0
					for _, size in bounds do
						widest = math.max(widest, use(size).X)
					end
					return D2.fromOffset(math.ceil(widest) + inset, 0)
				end,
			})
		end
		return ctx.column(sliders, { Name = "Sliders", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
	end

	local function opacitySlider(): Frame
		local opacity: InputProps.SliderProps = {
			Name = "Opacity",
			label = "Opacity",
			LayoutOrder = 4,
			value = function(use: Use): number
				return use(alphaHeld) * 100
			end,
			min = 0,
			max = 100,
			step = 1,
			enabled = function(use: Use): boolean
				return interactive(use)
			end,
			format = function(n: number): string
				return `{math.floor(n + 0.5)}%`
			end,
			trackContent = alphaStrip,
			thumbContent = ringKnob(function(): (Use) -> Color3
				return function(use: Use): Color3
					return use(held) or color.toColor(use(canon))
				end
			end),
			onChange = function(n: number)
				proposeAlpha(n / 100)
			end,
			onCommit = function()
				commit()
			end,
		}
		local slider = UI.Slider(opacity)
		local track = slider:FindFirstChild("Track", true)
		if track then
			track:SetAttribute("AccessibleLabel", "Opacity")
		end
		return slider
	end

	return {
		channelSlider = channelSlider,
		bubble = bubble,
		ringKnob = ringKnob,
		hueSlider = hueSlider,
		slidersView = slidersView,
		opacitySlider = opacitySlider,
	}
end
