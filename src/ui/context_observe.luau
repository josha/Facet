--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local preferredInput = require("./preferred_input")
local observeGeometry = require("./geometry_observation")

export type Observation = {
	preview: { [string]: unknown },
	observeStyled: (Instance, string) -> ComposeTypes.Cell<unknown>,
}

return function(ctx: Shared.Context, config: Shared.Config, services: Shared.Services): Observation
	local Compose, runtime, Enum = ctx.Compose, ctx.runtime, ctx.types.Enum
	type SharedObservation = { cell: ComposeTypes.Cell<unknown>, users: number, stop: () -> () }
	local sharedObservations: { [Instance]: { [string]: SharedObservation } } = {}
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
	local geometryProperties = {
		AbsoluteSize = true,
		AbsolutePosition = true,
		AbsoluteContentSize = true,
		AbsoluteWindowSize = true,
		AbsoluteCanvasSize = true,
		TextBounds = true,
		TextFits = true,
	}
	local function observe(node: Instance, property: string): ComposeTypes.Cell<unknown>
		local observation = assert(runtime.host.observation, "Roblox property observation is required")
		if not geometryProperties[property] then
			local byProperty = sharedObservations[node]
			if byProperty == nil then
				byProperty = {}
				sharedObservations[node] = byProperty
			end
			local entry = byProperty[property]
			if entry == nil then
				local initial = observation.readProperty(node, property)
				if
					property == "SelectedObject"
					and config.userInputService
					and config.userInputService.PreferredInput == Enum.PreferredInput.Touch
				then
					(config.guiService :: GuiService).SelectedObject = nil
					initial = nil
				end
				local cell = Compose.cell(initial)
				local selection = property == "SelectedObject"
				local preferred = property == "PreferredInput" and node == config.userInputService
				local stopNudges: (() -> ())? = nil
				local function publish()
					local current = observation.readProperty(node, property)
					local keys = config.userInputService
					local gui = config.guiService
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
								if cell:peek() ~= observation.readProperty(node, property) then
									publish()
								end
							end)
						return
					end
					if stopNudges then
						stopNudges()
						stopNudges = nil
					end
					cell:set(current)
					if selection then
						for _, hook in ctx.selectionHooks :: { (unknown) -> () } do
							hook(current)
						end
					end
				end
				local stop = observation.observeProperty(node, property, publish)
				if preferred then
					local unobserve = stop
					stop = function()
						if stopNudges then
							stopNudges()
							stopNudges = nil
						end
						unobserve()
					end
				end
				local created: SharedObservation = {
					cell = cell,
					users = 0,
					stop = stop,
				}
				byProperty[property] = created
				entry = created
			end
			local held = entry :: SharedObservation
			Compose.cleanup(function()
				held.users -= 1
				if held.users == 0 then
					held.stop()
					if byProperty[property] == held then
						byProperty[property] = nil
					end
					if next(byProperty) == nil then
						sharedObservations[node] = nil
					end
				end
			end)
			held.users += 1
			return (previewed(property, held.cell) :: unknown) :: ComposeTypes.Cell<unknown>
		end
		return observeGeometry(
			Compose,
			runtime,
			node,
			property,
			if services.RunService then services.RunService.PreRender else nil
		)
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
