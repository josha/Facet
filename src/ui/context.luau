--!strict
local ComposeTypes = require("../vendor/compose/core")
local bindThemes = require("./themes")
local Shared = require("./types")
local selection = require("./selection")
local resolveConfig = require("./context_config")
local installConstruct = require("./context_construct")
local installMetrics = require("./context_metrics")
local installObservation = require("./context_observe")
local installEnvironment = require("./context_environment")
local installContent = require("./context_content")
local installNative = require("./context_native")
local installActions = require("./context_actions")

return function(Compose: Shared.ComposeModule, runtime: ComposeTypes.Runtime, options: Shared.Config?): Shared.Context
	local config, types, services = resolveConfig(Compose, runtime, options)
	local Host = (runtime.constructors :: unknown) :: Shared.Host
	local themes = bindThemes(Compose)
	local fields = {
		runtime = runtime,
		Host = Host,
		Compose = Compose,
		types = types,
		config = config :: Shared.ResolvedConfig,
		metrics = { textSize = 16, controlHeight = 36, gap = 8, cornerRadius = 8 },
		overlayHosts = setmetatable({}, { __mode = "k" }),
	}
	local ctx = (fields :: unknown) :: Shared.Context
	local track = installConstruct(ctx)
	local function read<T>(value: T | ComposeTypes.Source<T>, use: ComposeTypes.Use?): T
		if Compose.isReadable(value) then
			local source = value :: ComposeTypes.Readable<T>
			return if use then use(source) else source:peek()
		elseif type(value) == "function" then
			local body = value :: ComposeTypes.Body<T>
			return body(use or function<U>(source: ComposeTypes.Readable<U>): U
				return source:peek()
			end)
		end
		return value :: T
	end
	ctx.read = (read :: unknown) :: Shared.Read
	ctx.readSource = function<T>(source: ComposeTypes.Readable<T>, use: ComposeTypes.Use?): T
		return if use then use(source) else source:peek()
	end
	local function live(value: unknown): boolean
		return Compose.isReadable(value) or type(value) == "function"
	end
	local themeMetrics = installMetrics(ctx, config, themes)
	local observation = installObservation(ctx, config, services)
	installEnvironment(ctx, config, themes, observation.preview, themeMetrics.metricAt, themeMetrics.setDistance, live)
	installContent(ctx, config, services, themes, live)
	installNative(ctx, config, services, themes, observation.observeStyled)
	installActions(ctx, config)
	local selected: selection.Selection
	function ctx.responder(root: Instance, options: Shared.ResponderOptions?): Shared.Responder
		return selected.responder(root, options)
	end
	function ctx.spaceActivates(node: Instance): (ComposeTypes.Use) -> boolean
		return selected.spaceActivates(node)
	end
	selected = selection(ctx)
	track(selected.track)
	return ctx
end
