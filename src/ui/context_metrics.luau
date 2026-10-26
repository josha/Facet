--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local Theme = require("./theme_types")

export type Metrics = {
	metricAt: (unknown, string) -> number?,
	setDistance: ((ComposeTypes.Use?) -> boolean) -> (),
}

return function(ctx: Shared.Context, config: Shared.Config, themes: Theme.Themes): Metrics
	local Compose, types = ctx.Compose, ctx.types
	local environment = config.environment
	local defaultMetrics = themes.neutralPackage().metrics
	local function valueAt(value: unknown, path: string): unknown
		for key in string.gmatch(path, "[^.]+") do
			if type(value) ~= "table" then
				return nil
			end
			value = (value :: { [string]: unknown })[key]
		end
		return value
	end
	local function metricAt(value: unknown, path: string): number?
		local found = valueAt(value, path)
		return if type(found) == "number" and found == found and math.abs(found) ~= math.huge then found else nil
	end
	local distantMetrics = themes.forDistance(themes.neutralPackage(), "ten-foot").metrics
	local distance: (ComposeTypes.Use?) -> boolean = function()
		return false
	end
	function ctx.neutralMetrics(use: ComposeTypes.Use?): Theme.Metrics
		return if distance(use) then distantMetrics else defaultMetrics
	end
	function ctx.metric(path: string, use: ComposeTypes.Use?, authored: boolean?): number
		local package = ctx.read(config.theme, use)
		local value = assert(
			metricAt(if package then package.metrics else nil, path) or metricAt(ctx.neutralMetrics(use), path),
			`Facet numeric metric {path} is missing`
		)
		if authored ~= true and environment and string.match(path, "^typography%.[^.]+%.size$") then
			local chosen = ctx.read(environment.preferredTextSize, use)
			if chosen ~= nil then
				local ranks = { Medium = 0, Large = 1, Larger = 2, Largest = 3 }
				local function rank(item: unknown): number
					local name = if typeof(item) == "EnumItem" then (item :: EnumItem).Name else item
					return (ranks :: { [unknown]: number })[name] or 0
				end
				local native = if config.guiService then config.guiService.PreferredTextSize else nil
				return math.max(
					1,
					value + (rank(chosen) - rank(native)) * ctx.metric("controls.typography.preferredSizeStep", use)
				)
			end
		end
		return value
	end
	function ctx.phrase(
		key: string,
		source: string,
		args: { [string]: string | number },
		use: ComposeTypes.Use?
	): string
		local translator = ctx.read(config.translator, use)
		if translator then
			local ok, text = pcall(translator.FormatByKey, translator, key, args)
			if ok and type(text) == "string" and text ~= "" then
				return text
			end
		end
		return (
			string.gsub(source, "{(%w+)}", function(name: string): string
				local value = args[name]
				return if value == nil then `\{{name}\}` else tostring(value)
			end)
		)
	end
	local function motionName(path: string, use: ComposeTypes.Use?): string
		local package = ctx.read(config.theme, use)
		local found = valueAt(if package then package.metrics else nil, path)
		if type(found) ~= "string" then
			found = valueAt(ctx.neutralMetrics(use), path)
		end
		local name = assert(if type(found) == "string" then found else nil, `Facet motion name {path} is missing`)
		return name
	end
	function ctx.motionTiming(role: string, use: ComposeTypes.Use?): { enter: number, exit: number }
		return { enter = ctx.metric(`motion.{role}.enter`, use), exit = ctx.metric(`motion.{role}.exit`, use) }
	end
	function ctx.motionSpring(role: string, use: ComposeTypes.Use?): { period: number, damping: number }
		return {
			period = ctx.metric(`motion.springs.{role}.period`, use),
			damping = ctx.metric(`motion.springs.{role}.damping`, use),
		}
	end
	function ctx.motionEase(role: string, use: ComposeTypes.Use?): (number) -> number
		local name = motionName(`motion.easing.{role}`, use)
		local ease = assert(Compose.easing[name], `Facet motion easing {name} is not a Compose easing`)
		return ease
	end
	function ctx.motionStyle(role: string, use: ComposeTypes.Use?): Enum.EasingStyle
		local name = motionName(`motion.styles.{role}`, use)
		local style = assert(
			((types.Enum.EasingStyle :: unknown) :: { [string]: Enum.EasingStyle })[name],
			`Facet motion style {name} is not an EasingStyle`
		)
		return style
	end
	function ctx.controlSize(
		source: Shared.Input<Shared.ControlSize?>?,
		field: "height" | "paddingX" | "iconSize",
		use: ComposeTypes.Use?
	): number
		local requested = ctx.read(source, use)
		local rung = if requested == nil then "regular" else requested
		assert(
			rung == "xsmall" or rung == "compact" or rung == "regular" or rung == "large",
			"Facet controlSize must be xsmall, compact, regular or large"
		)
		if rung == "xsmall" then
			local package = ctx.read(config.theme, use)
			local authored = metricAt(if package then package.metrics else nil, "controlSizes.xsmall." .. field)
			if authored then
				return authored
			end
			local compact = ctx.metric("controlSizes.compact." .. field, use)
			return math.max(0, 2 * compact - ctx.metric("controlSizes.regular." .. field, use))
		end
		return ctx.metric("controlSizes." .. rung .. "." .. field, use)
	end
	return {
		metricAt = metricAt,
		setDistance = function(reader: (ComposeTypes.Use?) -> boolean)
			distance = reader
		end,
	}
end
