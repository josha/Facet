--!strict
local pointerDragOf = require("./pointer_drag")
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local Nav = require("./navigation_types")
local InputProps = require("./input_props")
local Kit = require("./color_picker_kit")
local PickerState = require("./color_picker_state")
local Sliders = require("./color_picker_sliders")

type Use = ComposeTypes.Use
type Hsv = Kit.Hsv

local CELL, SPACE, RING, BUBBLE = Kit.CELL, Kit.SPACE, Kit.RING, Kit.BUBBLE
local STICK_SPEED, DEADZONE = 0.6, 0.2

return function(
	ctx: Shared.Context,
	UI: Kit.Deps,
	surfaces: Nav.Surfaces,
	kit: Kit.Kit,
	state: PickerState.State,
	sliders: Sliders.Sliders
): () -> Frame
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local color, ring, WHITE = kit.color, kit.ring, kit.WHITE
	local held, canon, selected = state.held, state.canon, state.selected
	local interactive, mayEdit, propose, commit, touch, gamepad =
		state.interactive, state.mayEdit, state.propose, state.commit, state.touch, state.gamepad
	local bubble, hueSlider = sliders.bubble, sliders.hueSlider

	local function planeView(): Frame
		local pointerInput = pointerDragOf(ctx)
		local hueChannel = Compose.formula(function(use: Use): number
			return use(canon).h
		end)
		local dragging = Compose.cell(false)
		local dragStart: Hsv? = nil
		local surface: Frame
		local plane: Frame
		local planeSize: ComposeTypes.ReadOnlyValue<Vector2>
		local function fractions(position: Vector2): (number?, number?)
			local at, size = surface.AbsolutePosition, surface.AbsoluteSize
			if size.X <= 0 or size.Y <= 0 then
				return nil, nil
			end
			return math.clamp((position.X - at.X) / size.X, 0, 1), math.clamp((position.Y - at.Y) / size.Y, 0, 1)
		end
		local function setFrom(position: Vector2)
			local fx, fy = fractions(position)
			if fx == nil or fy == nil then
				return
			end
			local now = canon:peek()
			propose({ h = now.h, s = fx, v = 1 - fy })
		end
		local function beginDrag(position: Vector2)
			if not mayEdit() or (gamepad() and ctx.readSource(selected) == (surface :: GuiObject?)) then
				return
			end
			if not dragging:peek() then
				dragStart = canon:peek()
				dragging:set(true)
			end
			setFrom(position)
		end
		local function endDrag()
			if not dragging:peek() then
				return
			end
			dragging:set(false)
			dragStart = nil
			commit()
		end
		local function cancelDrag()
			if not dragging:peek() then
				return
			end
			dragging:set(false)
			local start = dragStart
			dragStart = nil
			if start ~= nil then
				propose(start)
			end
		end
		local first = true
		Compose.watch(function(use: Use)
			use(state.preferred)
			if not first then
				cancelDrag()
			end
			first = false
		end)
		Compose.watch(function(use: Use)
			if not interactive(use) then
				cancelDrag()
			end
		end)
		local function spot(use: Use, size: number): (number, number)
			local extent = use(planeSize)
			local c = use(canon)
			local x, y = c.s * extent.X, (1 - c.v) * extent.Y
			return math.clamp(x, size / 2, math.max(size / 2, extent.X - size / 2)),
				math.clamp(y, size / 2, math.max(size / 2, extent.Y - size / 2))
		end
		local mark = ring("Ring")
		surface = Host.Frame "Surface" {
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 5,
			Selectable = function(use: Use)
				return interactive(use)
			end,
			Host.UIDragDetector "Drag" {
				ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
				Enabled = function(use: Use)
					return interactive(use) and pointerInput(use)
				end,
				DragStart = beginDrag,
				DragContinue = function(position: Vector2)
					if dragging:peek() then
						setFrom(position)
					end
				end,
				DragEnd = endDrag,
			},
		}
		surface:SetAttribute("AccessibleLabel", "Saturation and brightness")
		runtime.connect(surface, "SelectionGained", function() end)
		plane = Host.Frame "Plane" {
			Size = D2.new(1, 0, 0, 4 * CELL),
			BackgroundTransparency = 1,
			Host.Frame "Field" {
				Size = D2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Host.Frame "Hue" {
					Size = D2.fromScale(1, 1),
					BorderSizePixel = 0,
					BackgroundColor3 = WHITE,
					Host.UIGradient "Gradient" {
						Rotation = 0,
						Color = function(use: Use)
							local hue = color.toColor({ h = use(hueChannel), s = 1, v = 1 })
							return ctx.types.ColorSequence.new({
								ctx.types.ColorSequenceKeypoint.new(0, WHITE),
								ctx.types.ColorSequenceKeypoint.new(1, hue),
							})
						end,
					},
				},
				Host.Frame "Value" {
					Size = D2.fromScale(1, 1),
					BorderSizePixel = 0,
					BackgroundColor3 = kit.BLACK,
					Host.UIGradient "Gradient" {
						Rotation = 90,
						Transparency = ctx.types.NumberSequence.new({
							ctx.types.NumberSequenceKeypoint.new(0, 1),
							ctx.types.NumberSequenceKeypoint.new(1, 0),
						}),
					},
				},
			},
			surface,
		}
		planeSize = ctx.observe.AbsoluteSize(plane)
		runtime.decorate(mark, {
			AnchorPoint = V2.new(0.5, 0.5),
			ZIndex = 4,
			Visible = function(use: Use)
				return use(held) ~= nil
			end,
			Position = function(use: Use)
				local extent = use(planeSize)
				if extent.X <= 0 then
					local c = use(canon)
					return D2.fromScale(c.s, 1 - c.v)
				end
				local x, y = spot(use, RING)
				return D2.fromOffset(x, y)
			end,
		})
		surfaces.attach(plane, {
			mark,
			surfaces.overlay(plane, function(use: Use): boolean
				return touch(use) and use(dragging)
			end, function(): Frame
				local layer = assert(surfaces.parent(plane))
				local at, origin = ctx.observe.AbsolutePosition(plane), ctx.observe.AbsolutePosition(layer)
				local bounds = ctx.observe.AbsoluteSize(layer)
				local unit, layerUnit = ctx.layoutUnit(plane), ctx.layoutUnit(layer)
				local preview = bubble(function(use: Use): Color3
					return color.toColor(use(canon))
				end, function(use: Use): boolean
					return use(dragging)
				end, {
					AnchorPoint = V2.new(0.5, 1),
					ZIndex = 102,
					Position = function(use: Use)
						local scale = use(unit)
						local extent = use(planeSize)
						local x, y = spot(use, RING * scale)
						local half = BUBBLE / 2 * scale
						local offset = use(at) - use(origin)
						local above = offset.Y + y - (RING / 2 + SPACE) * scale
						local screen = use(bounds)
						if screen.Y > 0 and above < BUBBLE * scale then
							local side = (RING / 2 + SPACE + BUBBLE / 2) * scale
							local across = offset.X + x
							local beside = if across + side + half <= screen.X then across + side else across - side
							return D2.fromOffset(
								math.clamp(beside, half, math.max(half, screen.X - half)) / use(layerUnit),
								math.clamp(offset.Y + y + half, 2 * half, math.max(2 * half, screen.Y)) / use(layerUnit)
							)
						end
						return D2.fromOffset(
							(offset.X + math.clamp(x, half, math.max(half, extent.X - half))) / use(layerUnit),
							above / use(layerUnit)
						)
					end,
				})
				surfaces.attach(preview, {
					Host.UIScale {
						Scale = function(use: Use): number
							return use(unit) / use(layerUnit)
						end,
					},
				})
				return preview
			end),
		})
		local function planeSelected(use: Use?): boolean
			return (ctx.readSource(selected, use) :: Instance?) == (surface :: Instance)
		end
		local stick = V2.zero
		local stopFrames: (() -> ())? = nil
		local function endSession()
			local stop = stopFrames
			if stop then
				stopFrames = nil
				stop()
				commit()
			end
		end
		local function steer(dt: number)
			if dt <= 0 then
				return
			end
			if not planeSelected() or not mayEdit() then
				endSession()
				return
			end
			local now = canon:peek()
			propose({
				h = now.h,
				s = math.clamp(now.s + stick.X * STICK_SPEED * dt, 0, 1),
				v = math.clamp(now.v + stick.Y * STICK_SPEED * dt, 0, 1),
			})
		end
		local steerAction = ctx.action(surface, "ColorPlaneSteer", { E.KeyCode.Thumbstick2 }, function(use: Use)
			return planeSelected(use) and interactive(use)
		end, function() end, { priority = 2200 })
		runtime.decorate(steerAction, {
			Type = E.InputActionType.Direction2D,
			StateChanged = function(value: unknown)
				if typeof(value) ~= "Vector2" then
					return
				end
				local direction = value :: Vector2
				if direction.Magnitude < DEADZONE then
					stick = V2.zero
					endSession()
					return
				end
				stick = direction
				if stopFrames == nil then
					stopFrames = assert(runtime.host.frames).onFrame(steer)
				end
			end,
		})
		Compose.watch(function(use: Use)
			if not planeSelected(use) then
				stick = V2.zero
				endSession()
			end
		end)
		Compose.cleanup(function()
			local stop = stopFrames
			stopFrames = nil
			if stop then
				stop()
			end
		end)
		local hintProps: InputProps.ShortcutHintKeysProps =
			{ Name = "StickKey", keys = { { "Right Stick" } }, controlSize = "compact" }
		local hint = ctx.row({
			UI.ShortcutHint(hintProps),
			ctx.styled(ctx.text({ Name = "Words", Text = "Move saturation and brightness" }), "type-caption"),
		}, {
			Name = "StickHint",
			Visible = function(use: Use)
				return gamepad(use) and planeSelected(use)
			end,
		})
		return ctx.column({ plane, hint, hueSlider() }, {
			Name = "Spectrum",
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
		})
	end

	return planeView
end
