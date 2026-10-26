--!strict
local Shared = require("./types")
local ComposeTypes = require("../vendor/compose/core")

type Held = { box: TextBox, height: ComposeTypes.Value<number>, stop: () -> () }
local held: { [ComposeTypes.Runtime]: Held } = {}
setmetatable(held, { __mode = "k" })
local keyboard = {}

local function release(runtime: ComposeTypes.Runtime, current: Held)
	if held[runtime] == current then
		held[runtime] = nil
	end
	current.height:set(0)
	current.stop()
end

function keyboard.capture(
	ctx: Shared.Context,
	service: UserInputService?,
	box: TextBox,
	press: InputObject?,
	owner: ComposeTypes.Owner
)
	if service == nil or press == nil or service.OnScreenKeyboardVisible ~= true then
		return
	end
	local E = ctx.types.Enum
	if press.UserInputType ~= E.UserInputType.Touch and press.UserInputType ~= E.UserInputType.MouseButton1 then
		return
	end
	if press.UserInputState ~= E.UserInputState.Begin and press.UserInputState ~= E.UserInputState.Change then
		return
	end
	local extent: unknown = service.OnScreenKeyboardSize
	if typeof(extent) ~= "Vector2" then
		return
	end
	local height = extent.Y
	if height <= 0 or ComposeTypes.owner.isDisposed(owner) then
		return
	end
	local prior = held[ctx.runtime]
	if prior then
		release(ctx.runtime, prior)
	end
	local current: Held = { box = box, height = ctx.Compose.cell(height), stop = function() end }
	held[ctx.runtime] = current
	current.stop = ComposeTypes.owner.watch(owner, function(use: ComposeTypes.Use)
		local state = use(ctx.runtime.observe(press, "UserInputState", { frame = true }))
		if state == E.UserInputState.End or state == E.UserInputState.Cancel then
			release(ctx.runtime, current)
		end
	end, "keyboard-clearance")
end

function keyboard.release(ctx: Shared.Context, box: TextBox)
	local current = held[ctx.runtime]
	if current and current.box == box then
		release(ctx.runtime, current)
	end
end

function keyboard.reader(ctx: Shared.Context, service: UserInputService?): (ComposeTypes.Use) -> number
	if service == nil or not service.GetPropertyChangedSignal then
		return function(): number
			return 0
		end
	end
	local visible = ctx.observe.OnScreenKeyboardVisible(service)
	local size = ctx.observe.OnScreenKeyboardSize(service)
	return function(use: ComposeTypes.Use): number
		if use(visible) == true then
			local extent: unknown = use(size)
			if typeof(extent) == "Vector2" and extent.Y > 0 then
				return extent.Y
			end
		end
		local current = held[ctx.runtime]
		if current == nil then
			return 0
		end
		return use(current.height)
	end
end

return keyboard
