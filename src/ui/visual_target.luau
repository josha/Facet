--!strict

local ComposeTypes = require("../vendor/compose/core")

local targets: { [Instance]: ComposeTypes.Value<GuiObject?> } = setmetatable({}, { __mode = "k" })

local function create(Compose: typeof(ComposeTypes), anchor: Instance)
	local target = Compose.cell<<GuiObject?>>(nil)
	targets[anchor] = target
	Compose.cleanup(function()
		target:set(nil)
		targets[anchor] = nil
	end)
end

local function bind(Compose: typeof(ComposeTypes), anchor: Instance?, visual: GuiObject)
	local target = if anchor then targets[anchor] else nil
	if target == nil then
		return
	end
	target:set(visual)
	Compose.cleanup(function()
		if target:peek() == visual then
			target:set(nil)
		end
	end)
end

local function resolve(built: unknown, use: ComposeTypes.Use): unknown
	if typeof(built) ~= "Instance" then
		return nil
	end
	local target = targets[built]
	return if target then use(target) else nil
end

return { create = create, bind = bind, resolve = resolve }
