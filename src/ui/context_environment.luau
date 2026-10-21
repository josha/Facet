--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local Theme = require("./theme_types")
local adaptive = require("./adaptive")

return function(
	ctx: Shared.Context,
	config: Shared.Config,
	themes: Theme.Themes,
	preview: { [string]: unknown },
	metricAt: (unknown, string) -> number?,
	setDistance: ((ComposeTypes.Use?) -> boolean) -> ()
)
	local Compose = ctx.Compose
	function ctx.pointerOnly(): (ComposeTypes.Use?) -> boolean
		local input = config.userInputService
		if input == nil then
			return function()
				return false
			end
		end
		local mouse, touch, gamepad =
			ctx.observe.MouseEnabled(input), ctx.observe.TouchEnabled(input), ctx.observe.GamepadEnabled(input)
		return function(use: ComposeTypes.Use?): boolean
			return ctx.readSource(mouse, use) == true
				and ctx.readSource(touch, use) ~= true
				and ctx.readSource(gamepad, use) ~= true
		end
	end
	function ctx.viewingDistance(use: ComposeTypes.Use?): adaptive.ViewingDistance
		local value = ctx.read(preview.viewingDistance, use)
		assert(
			value == nil or value == "automatic" or value == "near" or value == "ten-foot",
			"Facet environment viewingDistance must be automatic, near or ten-foot"
		)
		return (value or "automatic") :: adaptive.ViewingDistance
	end
	function ctx.tenFoot(): (ComposeTypes.Use?) -> boolean
		local gui, input = config.guiService, config.userInputService
		local interface = false
		if gui then
			local ok, answer = pcall(function()
				return (gui :: GuiService):IsTenFootInterface()
			end)
			interface = ok and answer == true
		end
		local watchable = function(service: Instance?): boolean
			return service ~= nil and service.GetPropertyChangedSignal ~= nil
		end
		local display = if watchable(gui) then ctx.observe.ViewportDisplaySize(gui :: GuiService) else nil
		local mouse = if watchable(input) then ctx.observe.MouseEnabled(input :: UserInputService) else nil
		local touch = if watchable(input) then ctx.observe.TouchEnabled(input :: UserInputService) else nil
		return function(use: ComposeTypes.Use?): boolean
			local size = if display then ctx.readSource(display, use) else nil
			return adaptive.isTenFoot({
				viewingDistance = ctx.viewingDistance(use),
				tenFootInterface = interface,
				displaySize = if typeof(size) == "EnumItem" then (size :: EnumItem).Name else nil,
				mouse = if mouse then ctx.readSource(mouse, use) == true else false,
				touch = if touch then ctx.readSource(touch, use) == true else false,
			})
		end
	end
	local authored = config.theme
	ctx.runtime:watch(function()
		local distant = Compose.formula(ctx.tenFoot())
		local function distance(use: ComposeTypes.Use?): boolean
			return ctx.readSource(distant, use)
		end
		setDistance(distance)
		if authored ~= nil then
			config.theme = Compose.formula(function(use: ComposeTypes.Use): Theme.ThemePackage
				return themes.forDistance(ctx.read(authored, use), if distance(use) then "ten-foot" else "near")
			end)
		end
	end)
	function ctx.hitFloor(): (ComposeTypes.Use?) -> number
		local pointerOnly = ctx.pointerOnly()
		return function(use: ComposeTypes.Use?): number
			local minimum = ctx.metric("targetSizes.minimum", use)
			local package = ctx.read(config.theme, use)
			local pointer = metricAt(if package then package.metrics else nil, "targetSizes.pointer")
			if pointer == nil or pointer >= minimum or not pointerOnly(use) then
				return minimum
			end
			return pointer
		end
	end
	function ctx.effectiveInput(): (ComposeTypes.Use?) -> "Touch" | "Gamepad" | "KeyboardAndMouse"
		local input = config.userInputService
		local function watch(property: string): ComposeTypes.Readable<unknown>?
			if input == nil then
				return nil
			end
			local ok, value = pcall(
				({
					PreferredInput = ctx.observe.PreferredInput,
					MouseEnabled = ctx.observe.MouseEnabled,
					TouchEnabled = ctx.observe.TouchEnabled,
					GamepadEnabled = ctx.observe.GamepadEnabled,
				} :: { [string]: (UserInputService) -> ComposeTypes.Readable<unknown> })[property],
				input
			)
			return if ok then value else nil
		end
		local preferred, mouse, touch, gamepad =
			watch("PreferredInput"), watch("MouseEnabled"), watch("TouchEnabled"), watch("GamepadEnabled")
		local function on(source: ComposeTypes.Readable<unknown>?, use: ComposeTypes.Use?): boolean
			return source ~= nil and ctx.readSource(source, use) == true
		end
		return function(use: ComposeTypes.Use?): "Touch" | "Gamepad" | "KeyboardAndMouse"
			local report = if preferred then ctx.readSource(preferred, use) else nil
			local name = if typeof(report) == "EnumItem" then (report :: EnumItem).Name else report
			if name == "Touch" or name == "Gamepad" then
				return name
			elseif on(mouse, use) then
				return "KeyboardAndMouse"
			elseif on(touch, use) then
				return "Touch"
			elseif on(gamepad, use) then
				return "Gamepad"
			end
			return "KeyboardAndMouse"
		end
	end
	function ctx.thumbFloor(target: ComposeTypes.Readable<number>): (ComposeTypes.Use?) -> number
		local input = config.userInputService
		if input == nil then
			return function()
				return 0
			end
		end
		local touch = ctx.observe.TouchEnabled(input)
		local floor = ctx.touchFloor()
		return function(use: ComposeTypes.Use?): number
			if ctx.readSource(touch, use) ~= true then
				return floor(use)
			end
			return if use then use(target) else target:peek()
		end
	end
	function ctx.touchFloor(): (ComposeTypes.Use?) -> number
		local input = config.userInputService
		if input == nil then
			return function()
				return 0
			end
		end
		local touch, gamepad = ctx.observe.TouchEnabled(input), ctx.observe.GamepadEnabled(input)
		return function(use: ComposeTypes.Use?): number
			if ctx.readSource(touch, use) ~= true and ctx.readSource(gamepad, use) ~= true then
				return 0
			end
			return ctx.metric("targetSizes.minimum", use)
		end
	end
end
