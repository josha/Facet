--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local preferredInput = require("./preferred_input")

local GEOMETRY: { [string]: ComposeTypes.ObserveOptions } = {
	AbsoluteSize = { frame = true, poll = true },
	AbsolutePosition = { frame = true },
	AbsoluteContentSize = { frame = true },
	AbsoluteWindowSize = { frame = true, poll = true },
	AbsoluteCanvasSize = { frame = true },
	TextBounds = { frame = true, poll = true },
	TextFits = { frame = true },
}

export type Observation = {
	preview: { [string]: unknown },
	observeStyled: (Instance, string) -> ComposeTypes.Value<unknown>,
}

return function(ctx: Shared.Context, config: Shared.Config, services: Shared.Services): Observation
	local Compose, runtime, Enum = ctx.Compose, ctx.runtime, ctx.types.Enum
	local framed = services.RunService ~= nil and getfenv ~= nil and getfenv(0).game ~= nil
	local sharedObservations: { [Instance]: { [string]: ComposeTypes.AcquireSharedResource<ComposeTypes.Value<unknown>> } } =
		{}
	local preview: { [string]: unknown } = (config.environment or {}) :: { [string]: unknown }
	local PREVIEWED: { [string]: { key: string, enum: string? } } = {
		PreferredInput = { key = "preferredInput", enum = "PreferredInput" },
		TouchEnabled = { key = "touchEnabled" },
		MouseEnabled = { key = "mouseEnabled" },
		GamepadEnabled = { key = "gamepadEnabled" },
		KeyboardEnabled = { key = "keyboardEnabled" },
		PreferredTextSize = { key = "preferredTextSize", enum = "PreferredTextSize" },
		ViewportDisplaySize = { key = "displaySize", enum = "DisplaySize" },
	}
	local previewKeys: { [string]: boolean } = { viewportSize = true, viewingDistance = true, overscanInsets = true }
	for _, entry in PREVIEWED do
		previewKeys[entry.key] = true
	end
	for key in preview do
		assert(previewKeys[key], `Facet.controls: unknown environment option '{tostring(key)}'`)
	end
	local function previewed(
		property: string,
		engine: ComposeTypes.ReadOnlyValue<unknown>
	): ComposeTypes.ReadOnlyValue<unknown>
		local entry = PREVIEWED[property]
		local source = if entry then preview[entry.key] else nil
		if source == nil then
			return engine
		end
		local enumName = entry.enum
		return Compose.formula(function(use: ComposeTypes.Use): unknown
			local value = ctx.read(source, use)
			if value == nil then
				return use(engine)
			end
			if enumName and type(value) == "string" then
				local item = assert(
					((Enum :: unknown) :: { [string]: { FromName: (unknown, string) -> EnumItem? } })[enumName]:FromName(
						value
					),
					`Facet.controls: environment {entry.key} '{value}' is not a {enumName}`
				)
				return item
			end
			return value
		end)
	end
	local function observe(node: Instance, property: string): ComposeTypes.Value<unknown>
		local selection = property == "SelectedObject"
		local preferred = property == "PreferredInput" and node == config.userInputService
		if not selection and not preferred then
			return (
				previewed(
					property,
					runtime.observe(node, property, if framed then GEOMETRY[property] else nil)
				) :: unknown
			) :: ComposeTypes.Value<unknown>
		end
		local byProperty = sharedObservations[node]
		if byProperty == nil then
			byProperty = {}
			sharedObservations[node] = byProperty
		end
		local acquire = byProperty[property]
		if not acquire then
			acquire = Compose.createSharedResource(function(): (ComposeTypes.Value<unknown>, (() -> ())?)
				local cell: ComposeTypes.Value<unknown>? = nil
				local scope = Compose.createRootOwner(function()
					local observation = assert(runtime.host.observation)
					local source = if selection then nil else runtime.observe(node, property)
					local initial = if source then source:peek() else observation.readProperty(node, property)
					local value = Compose.cell(initial)
					local stopNudges: (() -> ())? = nil
					local function clearNudges()
						if stopNudges then
							stopNudges()
							stopNudges = nil
						end
					end
					local publish: (unknown, boolean?) -> ()
					publish = function(current: unknown, changed: boolean?)
						local keys, gui = config.userInputService, config.guiService
						if
							selection
							and gui
							and keys
							and keys.PreferredInput == Enum.PreferredInput.Touch
							and current ~= nil
						then
							gui.SelectedObject = nil
							current = nil
						elseif
							preferred
							and gui
							and current == Enum.PreferredInput.Touch
							and gui.SelectedObject ~= nil
						then
							gui.SelectedObject = nil
						end
						if
							preferred
							and preferredInput.withheld(
								node :: UserInputService,
								current,
								Enum.PreferredInput.KeyboardAndMouse
							)
						then
							stopNudges = stopNudges
								or preferredInput.nudges(node :: UserInputService, Enum, function()
									publish(assert(source):peek())
								end)
							return
						end
						clearNudges()
						value:set(current)
						if selection and changed ~= false then
							for _, hook in ctx.selectionHooks do
								hook(current)
							end
						end
					end
					if selection then
						Compose.cleanup(observation.observeProperty(node, property, function()
							publish(observation.readProperty(node, property))
						end))
						publish(initial, false)
					else
						Compose.watch(function(use: ComposeTypes.Use)
							publish(use(assert(source)))
						end)
					end
					Compose.cleanup(clearNudges)
					Compose.cleanup(function()
						byProperty[property] = nil
						if next(byProperty) == nil then
							sharedObservations[node] = nil
						end
					end)
					cell = value
				end, runtime.reactor)
				return assert(cell), scope.dispose
			end)
			byProperty[property] = acquire
		end
		return (previewed(property, assert(acquire)()) :: unknown) :: ComposeTypes.Value<unknown>
	end
	local function observers(watch: (Instance, string) -> ComposeTypes.Value<unknown>): Shared.Observe
		local bound: { [string]: (Instance) -> ComposeTypes.Value<unknown> } = {}
		setmetatable(bound, {
			__index = function(_, property: string): (Instance) -> ComposeTypes.Value<unknown>
				local read = function(node: Instance): ComposeTypes.Value<unknown>
					return watch(node, property)
				end
				bound[property] = read
				return read
			end,
		})
		return (bound :: unknown) :: Shared.Observe
	end
	ctx.selectionHooks = {}
	ctx.observe = observers(observe)
	ctx.observeNative = observers(function(node: Instance, property: string): ComposeTypes.Value<unknown>
		return (runtime.observe(node, property) :: unknown) :: ComposeTypes.Value<unknown>
	end)
	local function observeStyled(node: Instance, property: string): ComposeTypes.Value<unknown>
		local observation = assert(runtime.host.observation)
		local readStyled = assert(observation.readStyledProperty)
		local observeStyled = assert(observation.observeStyledProperty)
		local value = Compose.cell(readStyled(node, property))
		Compose.cleanup(observeStyled(node, property, function()
			value:set(readStyled(node, property))
		end))
		return value
	end
	ctx.observeStyled = observers(observeStyled)
	return { preview = preview, observeStyled = observeStyled }
end
