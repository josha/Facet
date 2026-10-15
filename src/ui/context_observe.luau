--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local preferredInput = require("./preferred_input")

export type Observation = {
	preview: { [string]: unknown },
	observeStyled: (Instance, string) -> ComposeTypes.Cell<unknown>,
}

return function(ctx: Shared.Context, config: Shared.Config, _services: Shared.Services): Observation
	local Compose, runtime, Enum = ctx.Compose, ctx.runtime, ctx.types.Enum
	local sharedObservations: { [Instance]: { [string]: ComposeTypes.AcquireSharedResource<ComposeTypes.Cell<unknown>> } } =
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
	local function previewed(property: string, engine: ComposeTypes.Readable<unknown>): ComposeTypes.Readable<unknown>
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
	local function observe(node: Instance, property: string): ComposeTypes.Cell<unknown>
		local selection = property == "SelectedObject"
		local preferred = property == "PreferredInput" and node == config.userInputService
		if not selection and not preferred then
			return (previewed(property, runtime.observe(node, property)) :: unknown) :: ComposeTypes.Cell<unknown>
		end
		local byProperty = sharedObservations[node]
		if byProperty == nil then
			byProperty = {}
			sharedObservations[node] = byProperty
		end
		local acquire = byProperty[property]
		if not acquire then
			acquire = Compose.createSharedResource(function(): (ComposeTypes.Cell<unknown>, (() -> ())?)
				local source = runtime.observe(node, property)
				local value = Compose.cell(source:peek())
				local stopNudges: (() -> ())? = nil
				local function clearNudges()
					if stopNudges then
						stopNudges()
						stopNudges = nil
					end
				end
				local publish: (unknown) -> ()
				publish = function(current: unknown)
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
					elseif preferred and gui and current == Enum.PreferredInput.Touch and gui.SelectedObject ~= nil then
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
								publish(source:peek())
							end)
						return
					end
					clearNudges()
					value:set(current)
					if selection then
						for _, hook in ctx.selectionHooks do
							hook(current)
						end
					end
				end
				Compose.watch(function(use: ComposeTypes.Use)
					publish(use(source))
				end)
				Compose.cleanup(clearNudges)
				Compose.cleanup(function()
					byProperty[property] = nil
					if next(byProperty) == nil then
						sharedObservations[node] = nil
					end
				end)
				return value, nil
			end)
			byProperty[property] = acquire
		end
		return (previewed(property, assert(acquire)()) :: unknown) :: ComposeTypes.Cell<unknown>
	end
	local function observers(watch: (Instance, string) -> ComposeTypes.Cell<unknown>): Shared.Observe
		local bound: { [string]: (Instance) -> ComposeTypes.Cell<unknown> } = {}
		setmetatable(bound, {
			__index = function(_, property: string): (Instance) -> ComposeTypes.Cell<unknown>
				local read = function(node: Instance): ComposeTypes.Cell<unknown>
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
	local function observeStyled(node: Instance, property: string): ComposeTypes.Cell<unknown>
		local initial: unknown = node:GetStyled(property)
		local value = Compose.cell(initial)
		local connection = node:GetStyledPropertyChangedSignal(property):Connect(function()
			local nextValue: unknown = node:GetStyled(property)
			value:set(nextValue)
		end)
		Compose.cleanup(function()
			connection:Disconnect()
		end)
		return value
	end
	ctx.observeStyled = observers(observeStyled)
	return { preview = preview, observeStyled = observeStyled }
end
