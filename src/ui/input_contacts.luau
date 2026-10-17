--!strict
local Types = require("./types")

return function(ctx: Types.Context, root: GuiObject, onBegin: () -> (), onEnd: (boolean) -> ())
	local runtime, E = ctx.runtime, ctx.types.Enum
	local held: { [InputObject]: boolean } = {}
	local listening: { [GuiObject]: boolean } = {}
	setmetatable(listening, { __mode = "k" })
	local function begin(value: InputObject)
		if value.UserInputType ~= E.UserInputType.Touch and value.UserInputType ~= E.UserInputType.MouseButton1 then
			return
		end
		if not held[value] then
			local first = next(held) == nil
			held[value] = true
			if first then
				onBegin()
			end
		end
	end
	local function finish(value: InputObject)
		if held[value] then
			held[value] = nil
			if next(held) == nil then
				onEnd(value.UserInputState == E.UserInputState.Cancel)
			end
		end
	end
	local function listen(node: Instance)
		if node:IsA("GuiObject") and not listening[node] then
			listening[node] = true
			runtime.connect(node, "InputBegan", begin)
		end
	end
	listen(root)
	for _, node in root:GetDescendants() do
		listen(node)
	end
	runtime.connect(root, "DescendantAdded", listen)
	runtime.connect(root, "InputEnded", finish)
	local input = ctx.config.userInputService
	if input then
		runtime.connect(input, "InputEnded", finish)
		runtime.connect(input, "WindowFocusReleased", function()
			if next(held) ~= nil then
				table.clear(held)
				onEnd(true)
			end
		end)
	end
end
