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
local inputRead = require("./input_read")
local sourceRead = require("./source_read")

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
	runtime:watch(function()
		ctx.lifetime = assert(Compose.currentOwner())
	end)
	local track = installConstruct(ctx)
	ctx.read = inputRead(Compose.isValue)
	ctx.readSource = sourceRead
	local function live(value: unknown): boolean
		return Compose.isValue(value) or type(value) == "function"
	end
	local themeMetrics = installMetrics(ctx, config, themes)
	local observation = installObservation(ctx, config, services)
	installEnvironment(ctx, config, themes, observation.preview, themeMetrics.metricAt, themeMetrics.setDistance)
	installContent(ctx, config, services, themes, live)
	installNative(ctx, config, services, themes, observation.observeStyled)
	installActions(ctx, config)
	local selected = selection(ctx)
	ctx.responder, ctx.spaceActivates = selected.responder, selected.spaceActivates
	track(selected.track)
	return ctx
end
