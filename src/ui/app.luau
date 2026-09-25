--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local ControlTypes = require("./control_types")
local ThemeTypes = require("./theme_types")
local Engine = require("./engine_types")
local freeze = require("./freeze")

export type Component = () -> ComposeTypes.Child
export type AppOptions = {
	types: Types.RobloxTypes?,
	services: Types.Services?,
	guiService: GuiService?,
	userInputService: UserInputService?,
	inputParent: Instance?,
	overlayParent: Instance?,
	controlSize: Types.Value<Types.ControlSize>?,
	theme: Types.Value<ThemeTypes.ThemePackage>?,
	icons: Types.Value<{ [string]: ThemeTypes.IconEntry }>?,
	reducedMotion: Types.Value<boolean>?,
	pressHaptic: HapticEffect?,
	onError: ((unknown) -> ())?,
	runtime: Types.Runtime?,
	parent: Instance?,
	name: string?,
	screen: Engine.ScreenGuiNativeProps?,
	sheet: ThemeTypes.ThemeOptions?,
}
export type App = {
	runtime: Types.Runtime,
	UI: ControlTypes.Controls,
	mount: (component: Component, parent: Instance?) -> (() -> (), ScreenGui),
	dispose: () -> (),
}
type RobloxModule = { createRuntime: () -> Types.Runtime }
type StyleLinkHost = { StyleLink: ({ StyleSheet: unknown }) -> Instance }

local function playerGui(): Instance
	local game = getfenv(0).game
	local players = game and game:GetService("Players")
	local player = players and players.LocalPlayer
	if player == nil then
		error("Facet app.mount: there is no PlayerGui here. Give a parent to Facet.app or to app.mount.", 3)
	end
	return player:WaitForChild("PlayerGui")
end

return function(
	Compose: Types.ComposeModule,
	roblox: RobloxModule,
	controls: ControlTypes.Factory,
	themes: ThemeTypes.Themes,
	options: AppOptions?
): App
	local settings: AppOptions = options or {}
	local owned = settings.runtime == nil
	local runtime = settings.runtime or roblox.createRuntime()
	local UI = controls(Compose, runtime, (settings :: unknown) :: Types.Config)
	local Host = (runtime.constructors :: unknown) :: Engine.Host
	local Links = (runtime.constructors :: unknown) :: StyleLinkHost
	local stops: { () -> () } = {}
	local disposed = false
	local function mount(component: Component, parent: Instance?): (() -> (), ScreenGui)
		assert(not disposed, "Facet app.mount: the app is disposed")
		assert(type(component) == "function", "Facet app.mount: expected a component function")
		local target = parent or settings.parent or playerGui()
		local stop, root = runtime.mount(function(): ComposeTypes.Child
			local sheetOptions: ThemeTypes.ThemeOptions = table.clone(settings.sheet or {})
			if sheetOptions.types == nil then
				sheetOptions.types = settings.types
			end
			if sheetOptions.reducedMotion == nil then
				sheetOptions.reducedMotion = settings.reducedMotion
			end
			local sheet = themes.createStyleSheet(runtime, settings.theme, sheetOptions)
			local props: { [unknown]: unknown } = {}
			for key, value in ((settings.screen or {}) :: unknown) :: { [unknown]: unknown } do
				assert(type(key) == "string", "Facet app: screen takes native ScreenGui properties only")
				props[key] = value
			end
			props.Name = props.Name or settings.name or "Facet"
			if props.ResetOnSpawn == nil then
				props.ResetOnSpawn = false
			end
			if props.ZIndexBehavior == nil then
				local enums = if settings.types then settings.types.Enum else Enum
				props.ZIndexBehavior = enums.ZIndexBehavior.Sibling
			end
			props[1] = sheet
			props[2] = Links.StyleLink({ StyleSheet = Compose.static(sheet) })
			props[3] = component()
			return Host.ScreenGui((props :: unknown) :: Engine.ScreenGuiNativeProps)
		end, target)
		local stopped = false
		local function release()
			if not stopped then
				stopped = true
				local index = table.find(stops, release)
				if index then
					table.remove(stops, index)
				end
				stop()
			end
		end
		table.insert(stops, release)
		return release, (root :: unknown) :: ScreenGui
	end
	local function dispose()
		if disposed then
			return
		end
		disposed = true
		for index = #stops, 1, -1 do
			stops[index]()
		end
		if owned then
			runtime:dispose()
		end
	end
	return freeze({ runtime = runtime, UI = UI, mount = mount, dispose = dispose })
end
