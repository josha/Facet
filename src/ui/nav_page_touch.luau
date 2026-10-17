--!strict
local Types = require("./types")
local gestureOf = require("./gesture_service")
local scrollLock = require("./scroll_lock")

return function(ctx: Types.Context, pages: Frame, onBegin: (InputObject) -> (), onEnd: (InputObject) -> ())
	local input = ctx.config.userInputService
	if not input then
		return
	end
	local runtime, Compose = ctx.runtime, ctx.Compose
	local E, V2 = ctx.types.Enum, ctx.types.Vector2
	local arbiter = gestureOf(ctx)
	local later = runtime.scheduler()
	local pointer: InputObject? = nil
	local release: (() -> ())? = nil
	local listening: { [GuiObject]: boolean } = {}
	setmetatable(listening, { __mode = "k" })
	local function unlock()
		if release then
			release()
			release = nil
		end
	end
	local function begin(value: InputObject)
		if value.UserInputType ~= E.UserInputType.Touch or pointer then
			return
		end
		local position = V2.new(value.Position.X, value.Position.Y)
		if arbiter.begin(value, pages, position, { pickup = "immediate", axis = "X", scroll = true }) then
			later.cancel("release")
			unlock()
			pointer = value
			onBegin(value)
		end
	end
	local function listen(node: Instance)
		if node:IsA("GuiObject") and not listening[node] then
			listening[node] = true
			runtime.connect(node, "InputBegan", begin)
		end
	end
	listen(pages)
	for _, node in pages:GetDescendants() do
		listen(node)
	end
	runtime.connect(pages, "DescendantAdded", listen)
	runtime.connect(input, "InputChanged", function(value: InputObject)
		if value ~= pointer then
			return
		end
		local kind = arbiter.move(value, V2.new(value.Position.X, value.Position.Y))
		if kind == "drag" and not release then
			release = scrollLock.holdInputAncestors(pages)
		end
	end)
	local function finish(value: InputObject)
		if value ~= pointer then
			return
		end
		arbiter.finish(value, pages, value.UserInputState == E.UserInputState.Cancel)
		pointer = nil
		onEnd(value)
		later.replace("release", 0, unlock)
	end
	runtime.connect(input, "InputEnded", finish)
	runtime.connect(input, "WindowFocusReleased", function()
		if pointer then
			finish(pointer)
		end
		unlock()
	end)
	Compose.cleanup(function()
		arbiter.cancelOwner(pages)
		unlock()
	end)
end
