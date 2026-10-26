--!strict
local InputTypes = require("./input_types")
local Shared = require("./types")
local ComposeTypes = require("../vendor/compose/core")

export type Adjust = {
	vertical: boolean?,
	once: boolean?,
	guard: boolean?,
	arrows: ((ComposeTypes.Use, number) -> boolean)?,
	extra: (((ComposeTypes.Use) -> boolean) -> ())?,
}
export type EnabledSource = InputTypes.EnabledOptions | InputTypes.NumberInputOptions | InputTypes.LevelOptions | {
	value: Shared.Input<number>,
	onChange: ((number) -> ())?,
}
export type RepeatHeld = (
	{ onFrame: ((number) -> ()) -> () -> () },
	number,
	number,
	() -> boolean,
	() -> ()
) -> () -> ()
export type Adjustment = (
	GuiObject,
	InputTypes.AdjustmentState,
	(number) -> (),
	(() -> ())?,
	number?,
	number?,
	Adjust?
) -> ()
type Base = {
	attributes: (Instance, Shared.Attributes) -> Instance,
	enabled: (EnabledSource, ComposeTypes.Use?) -> boolean,
	stopEnabled: (EnabledSource, ComposeTypes.Use?) -> boolean,
	repeatHeld: RepeatHeld,
	repeatDelay: number,
	repeatInterval: number,
}

local STICK_PRESS, STICK_RELEASE, STICK_DOMINANCE = 0.5, 0.35, 1.2

return function(ctx: Shared.Context, base: Base): Adjustment
	local runtime, Compose, read = ctx.runtime, ctx.Compose, ctx.read
	local E = ctx.types.Enum
	local attributes, enabled, stopEnabled, repeatHeld =
		base.attributes, base.enabled, base.stopEnabled, base.repeatHeld
	local function adjustment(
		node: GuiObject,
		spec: InputTypes.AdjustmentState,
		apply: (number) -> (),
		cancel: (() -> ())?,
		minimum: number?,
		maximum: number?,
		options: Adjust?
	): ()
		local adjust: Adjust = options or {}
		node:AddTag("facet-adjustable")
		runtime.connect(node, "SelectionGained", function() end)
		attributes(node, {
			disabled = function(use: ComposeTypes.Use): boolean
				return not stopEnabled((spec :: unknown) :: InputTypes.EnabledOptions, use)
			end,
		})
		if minimum ~= nil and maximum ~= nil then
			node:SetAttribute("axis", if adjust.vertical then "vertical" else "horizontal")
		end
		local landing = false
		local function arrowHeld(): boolean
			local input = ctx.config.services.UserInputService
			if input == nil then
				return false
			end
			local probe = (input :: unknown) :: {
				IsKeyDown: ((UserInputService, Enum.KeyCode) -> boolean)?,
				IsGamepadButtonDown: ((UserInputService, Enum.UserInputType, Enum.KeyCode) -> boolean)?,
			}
			for _, key in { E.KeyCode.Up, E.KeyCode.Down, E.KeyCode.Left, E.KeyCode.Right } do
				if probe.IsKeyDown and input:IsKeyDown(key) then
					return true
				end
			end
			if probe.IsGamepadButtonDown then
				for _, pad in ctx.navigationGamepads() do
					for _, key in { E.KeyCode.DPadUp, E.KeyCode.DPadDown, E.KeyCode.DPadLeft, E.KeyCode.DPadRight } do
						if input:IsGamepadButtonDown(pad, key) then
							return true
						end
					end
				end
			end
			return false
		end
		local function stickHeld(): boolean
			local service = ctx.config.services.UserInputService
			local probe = (
				service :: unknown
			) :: { GetGamepadState: ((UserInputService, Enum.UserInputType) -> { InputObject })? }
			if service == nil or probe.GetGamepadState == nil then
				return false
			end
			for _, pad in ctx.navigationGamepads() do
				for _, state in service:GetGamepadState(pad) do
					if state.KeyCode == E.KeyCode.Thumbstick1 and state.Position.Magnitude >= STICK_PRESS then
						return true
					end
				end
			end
			return false
		end
		local guiService = ctx.config.services.GuiService
		local target = guiService and guiService.SelectedObject
		local selected = Compose.cell(target ~= nil and target == node)
		if guiService then
			local nativeSelection = ctx.observe.SelectedObject(guiService)
			Compose.watch(function(use: ComposeTypes.Use)
				local target = use(nativeSelection)
				local inside = target ~= nil and target == node
				if selected:peek() and not inside and cancel then
					cancel()
				end
				if inside and not selected:peek() and adjust.guard then
					landing = arrowHeld()
				end
				selected:set(inside)
			end)
		else
			runtime.connect(node, "SelectionGained", function()
				selected:set(true)
			end)
			runtime.connect(node, "SelectionLost", function()
				selected:set(false)
				if cancel then
					cancel()
				end
			end)
		end
		local active = function(use: ComposeTypes.Use)
			return read(selected, use) and enabled(spec, use)
		end
		runtime.mountFragment(function()
			return {
				Compose.show(active, function()
					local held: unknown = nil
					local stopFrame: (() -> ())?
					local function stopRepeat()
						held = nil
						if stopFrame then
							stopFrame()
							stopFrame = nil
						end
					end
					Compose.cleanup(stopRepeat)
					Compose.watch(function(use: ComposeTypes.Use)
						if not active(use) or not ctx.available(node, use) then
							stopRepeat()
						end
					end)
					local function peekUse<T>(source: ComposeTypes.ReadOnlyValue<T>): T
						return ctx.readSource(source)
					end
					local function movable(direction: number): () -> boolean
						return function(): boolean
							if not active(peekUse) then
								return false
							end
							if adjust.arrows then
								return adjust.arrows(peekUse, direction)
							end
							if minimum == nil or maximum == nil then
								return true
							end
							local value = read(((spec :: unknown) :: { value: Shared.ValueNumber }).value)
							return if direction < 0 then value > minimum else value < maximum
						end
					end
					local function start(token: unknown, direction: number, holding: () -> boolean)
						stopRepeat()
						local can = movable(direction)
						if not can() then
							return
						end
						apply(direction)
						held = token
						if runtime.host.frames and not adjust.once then
							local timing = (spec :: unknown) :: { repeatDelay: number?, repeatInterval: number? }
							stopFrame = repeatHeld(
								runtime.host.frames,
								timing.repeatDelay or base.repeatDelay,
								timing.repeatInterval or base.repeatInterval,
								function(): boolean
									if held ~= token or not can() or not ctx.available(node) or not holding() then
										stopRepeat()
										return false
									end
									return true
								end,
								function()
									apply(direction)
								end
							)
						end
					end
					local function steers(direction: number): (ComposeTypes.Use) -> boolean
						return function(use: ComposeTypes.Use): boolean
							if not active(use) then
								return false
							end
							if adjust.arrows then
								return adjust.arrows(use, direction)
							end
							if minimum == nil or maximum == nil then
								return true
							end
							local value = read(((spec :: unknown) :: { value: Shared.ValueNumber }).value, use)
							return if direction < 0 then value > minimum else value < maximum
						end
					end
					local function bind(name: string, keys: Shared.ActionBindings, direction: number, arrow: boolean?)
						local action: InputAction
						action = ctx.action(node, name, keys, if arrow then steers(direction) else active, function()
							if arrow and landing then
								return
							end
							local probe = (action :: unknown) :: { GetState: ((InputAction) -> unknown)? }
							local state = probe.GetState
							local engaged = state ~= nil and state(action) == true
							start(action, direction, function(): boolean
								return not engaged or (state :: (InputAction) -> unknown)(action) == true
							end)
						end, {
							priority = 250,
							capture = true,
							onReleased = function()
								if arrow then
									landing = false
								end
								if held == (action :: unknown) then
									stopRepeat()
								end
							end,
						})
					end
					bind("Decrease", { E.KeyCode.Comma, E.KeyCode.ButtonL1 }, -1)
					bind("Increase", { E.KeyCode.Period, E.KeyCode.ButtonR1 }, 1)
					if minimum ~= nil and maximum ~= nil then
						for _, direction in { -1, 1 } do
							local keys = if adjust.vertical
								then (if direction < 0
									then { E.KeyCode.Down, E.KeyCode.DPadDown }
									else { E.KeyCode.Up, E.KeyCode.DPadUp })
								else (if direction < 0
									then { E.KeyCode.Left, E.KeyCode.DPadLeft }
									else { E.KeyCode.Right, E.KeyCode.DPadRight })
							bind(if direction < 0 then "DecreaseArrow" else "IncreaseArrow", keys, direction, true)
						end
						local leaning = 0
						local settling = stickHeld()
						local stickInput = ctx.config.services.UserInputService
						local function lean(event: InputObject, ended: boolean)
							if
								event.KeyCode ~= E.KeyCode.Thumbstick1
								or not table.find(ctx.navigationGamepads(), event.UserInputType)
							then
								return
							end
							local x, y = if ended then 0 else event.Position.X, if ended then 0 else event.Position.Y
							local along = if adjust.vertical then y else x
							local across = math.abs(if adjust.vertical then x else y)
							local reach = math.abs(along)
							local sign = if along > 0 then 1 else -1
							if settling then
								settling = reach >= STICK_RELEASE and reach >= across
								return
							end
							local direction = if leaning == sign
									and reach >= STICK_RELEASE
									and reach >= across
								then sign
								elseif reach >= STICK_PRESS and reach > across * STICK_DOMINANCE then sign
								else 0
							if direction == leaning then
								return
							end
							leaning = direction
							if direction == 0 then
								if held == "stick" then
									stopRepeat()
								end
							elseif ctx.available(node) then
								start("stick", direction, function(): boolean
									return leaning == direction
								end)
							end
						end
						if stickInput then
							runtime.connect(stickInput, "InputChanged", function(event: InputObject)
								lean(event, false)
							end)
							runtime.connect(stickInput, "InputEnded", function(event: InputObject)
								lean(event, true)
							end)
						end
					end
					if adjust.extra then
						adjust.extra(active)
					end
					if cancel then
						ctx.action(
							node,
							"Cancel",
							{ E.KeyCode.Escape, E.KeyCode.ButtonB },
							active,
							cancel,
							{ priority = 100 }
						)
					end
					return Compose.fragment(function()
						return {}
					end)
				end),
			}
		end, node)
	end
	return adjustment
end
