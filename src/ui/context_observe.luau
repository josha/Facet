--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local preferredInput = require("./preferred_input")
local STYLED: ComposeTypes.ObserveOptions = { styled = true }

local GEOMETRY: { [string]: ComposeTypes.ObserveOptions } = {
	AbsoluteSize = { frame = true, poll = true },
	AbsolutePosition = { frame = true },
	AbsoluteContentSize = { frame = true },
	AbsoluteWindowSize = { frame = true, poll = true },
	AbsoluteCanvasSize = { frame = true },
	TextBounds = { frame = true, poll = true },
	TextFits = { frame = true },
}

local PREVIEWED: {
	[string]: {
		key: string,
		enum: ("PreferredInput" | "PreferredTextSize" | "DisplaySize")?,
		read: (Shared.EnvironmentPreview) -> unknown,
	},
} =
	{
		PreferredInput = {
			key = "preferredInput",
			enum = "PreferredInput",
			read = function(preview)
				return preview.preferredInput
			end,
		},
		TouchEnabled = {
			key = "touchEnabled",
			read = function(preview)
				return preview.touchEnabled
			end,
		},
		MouseEnabled = {
			key = "mouseEnabled",
			read = function(preview)
				return preview.mouseEnabled
			end,
		},
		GamepadEnabled = {
			key = "gamepadEnabled",
			read = function(preview)
				return preview.gamepadEnabled
			end,
		},
		KeyboardEnabled = {
			key = "keyboardEnabled",
			read = function(preview)
				return preview.keyboardEnabled
			end,
		},
		PreferredTextSize = {
			key = "preferredTextSize",
			enum = "PreferredTextSize",
			read = function(preview)
				return preview.preferredTextSize
			end,
		},
		ViewportDisplaySize = {
			key = "displaySize",
			enum = "DisplaySize",
			read = function(preview)
				return preview.displaySize
			end,
		},
	}
local previewKeys: { [string]: boolean } = { viewportSize = true, viewingDistance = true, overscanInsets = true }
for _, entry in PREVIEWED do
	previewKeys[entry.key] = true
end

local function validatePreview(preview: unknown)
	if preview == nil or preview == false then
		return
	end
	assert(type(preview) == "table", "Facet.controls: environment must be a table")
	for key in preview do
		assert(
			type(key) == "string" and previewKeys[key],
			`Facet.controls: unknown environment option '{tostring(key)}'`
		)
	end
end

export type Observation = {
	preview: Shared.EnvironmentPreview,
	observeStyled: (Instance, string) -> ComposeTypes.ReadOnlyValue<unknown>,
}

return function(ctx: Shared.Context, config: Shared.Config, services: Shared.Services): Observation
	local Compose, runtime, Enum = ctx.Compose, ctx.runtime, ctx.types.Enum
	local framed = services.RunService ~= nil and getfenv ~= nil and getfenv(0).game ~= nil
	local sharedObservations: { [Instance]: { [string]: ComposeTypes.AcquireSharedResource<ComposeTypes.Value<unknown>> } } =
		{}
	local preview: Shared.EnvironmentPreview = config.environment or {}
	validatePreview(config.environment)
	local function previewed(
		property: string,
		engine: ComposeTypes.ReadOnlyValue<unknown>
	): ComposeTypes.ReadOnlyValue<unknown>
		local entry = PREVIEWED[property]
		local source = if entry then entry.read(preview) else nil
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
					if enumName == "PreferredInput"
						then Enum.PreferredInput:FromName(value)
						elseif enumName == "PreferredTextSize" then Enum.PreferredTextSize:FromName(value)
						else Enum.DisplaySize:FromName(value),
					`Facet.controls: environment {entry.key} '{value}' is not a {enumName}`
				)
				return item
			end
			return value
		end)
	end
	local function observe(node: Instance, property: string): ComposeTypes.ReadOnlyValue<unknown>
		local selection = property == "SelectedObject"
		local preferred = property == "PreferredInput" and node == config.userInputService
		if not selection and not preferred then
			return previewed(property, runtime.observe(node, property, if framed then GEOMETRY[property] else nil))
		end
		local input = if preferred then config.userInputService else nil
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
						if input and preferredInput.withheld(input, current, Enum.PreferredInput.KeyboardAndMouse) then
							stopNudges = stopNudges
								or preferredInput.nudges(input, Enum, function()
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
		return previewed(property, assert(acquire)())
	end
	local function observers(watch: (Instance, string) -> ComposeTypes.ReadOnlyValue<unknown>): Shared.Observe
		local bound: { [string]: (Instance) -> ComposeTypes.ReadOnlyValue<unknown> } = {}
		setmetatable(bound, {
			__index = function(_, property: string): (Instance) -> ComposeTypes.ReadOnlyValue<unknown>
				local read = function(node: Instance): ComposeTypes.ReadOnlyValue<unknown>
					return watch(node, property)
				end
				bound[property] = read
				return read
			end,
		})
		return bound :: Shared.Observe
	end
	ctx.selectionHooks = {}
	ctx.observe = observers(observe)
	ctx.observeNative = observers(function(node: Instance, property: string): ComposeTypes.ReadOnlyValue<unknown>
		return runtime.observe(node, property)
	end)
	local function observeStyled(node: Instance, property: string): ComposeTypes.ReadOnlyValue<unknown>
		return runtime.observe(node, property, STYLED)
	end
	ctx.observeStyled = observers(observeStyled)
	return { preview = preview, observeStyled = observeStyled }
end
