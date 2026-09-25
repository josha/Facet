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
	refusal: (control: string, spec: unknown) -> string?,
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
	local enums = if settings.types then settings.types.Enum else Enum
	local D2 = if settings.types then settings.types.UDim2 else UDim2
	local function styledCell<T>(node: Instance, property: string): ComposeTypes.Cell<T>
		local value = Compose.cell((node :: any):GetStyled(property))
		local connection = (node :: any):GetStyledPropertyChangedSignal(property):Connect(function()
			value:set((node :: any):GetStyled(property))
		end)
		Compose.cleanup(function()
			connection:Disconnect()
		end)
		return value
	end
	local function focusRing(playerGui: PlayerGui): Frame
		local services: { [string]: any } = (settings.services or {}) :: any
		local input: UserInputService? = settings.userInputService or services.UserInputService
		if input == nil then
			local game = getfenv(0).game
			input = if game then game:GetService("UserInputService") else nil
		end
		local keyed = Compose.cell(false)
		local function heard(event: InputObject)
			local kind = event.UserInputType
			if kind == enums.UserInputType.Keyboard or string.find(kind.Name, "^Gamepad") then
				keyed:set(true)
			elseif kind == enums.UserInputType.Touch or string.find(kind.Name, "^Mouse") then
				keyed:set(false)
			end
		end
		if input then
			local began = input.InputBegan:Connect(heard)
			local changed = input.InputChanged:Connect(heard)
			Compose.cleanup(function()
				began:Disconnect()
				changed:Disconnect()
			end)
		end
		local env = UI.environment()
		local corner = Host.UICorner({})
		local paint = Host.Frame({ Name = "FocusRingPaint", Visible = false, Size = D2.fromOffset(0, 0), corner })
		paint:AddTag("facet-focus-ring")
		local color: ComposeTypes.Cell<Color3> = styledCell(paint, "BackgroundColor3")
		local radius: ComposeTypes.Cell<UDim> = styledCell(corner, "CornerRadius")
		local ring = Host.Frame({
			Name = "FacetFocusRing",
			BackgroundTransparency = 1,
			Size = D2.fromScale(1, 1),
			Host.UICorner({ CornerRadius = radius }) :: ComposeTypes.Child,
			Host.UIStroke({
				ApplyStrokeMode = enums.ApplyStrokeMode.Border,
				BorderStrokePosition = enums.BorderStrokePosition.Inner,
				Color = color,
				Thickness = function(use: ComposeTypes.Use): number
					return if use(env.displaySize) == "Large" then 4 else 2
				end,
				Transparency = function(use: ComposeTypes.Use): number
					return if use(keyed) or use(env.effectiveInput) == "Gamepad" then 0 else 1
				end,
			}),
		})
		playerGui.SelectionImageObject = ring
		Compose.cleanup(function()
			if playerGui.SelectionImageObject == ring then
				(playerGui :: any).SelectionImageObject = nil
			end
		end)
		return paint
	end
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
				props.ZIndexBehavior = enums.ZIndexBehavior.Sibling
			end
			props[1] = sheet
			props[2] = Links.StyleLink({ StyleSheet = Compose.static(sheet) })
			props[3] = component()
			if target:IsA("PlayerGui") then
				props[4] = focusRing(target :: PlayerGui)
			end
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
	local function refusal(control: string, spec: unknown): string?
		assert(not disposed, "Facet app.refusal: the app is disposed")
		local construct = ((UI :: unknown) :: { [string]: (unknown) -> Instance })[control]
		if construct == nil then
			error(`Facet app.refusal: there is no control named '{tostring(control)}'`, 2)
		end
		local ok, failure = pcall(function()
			Compose.withRootOwner(function()
				Host.ScreenGui({ construct(spec) } :: Engine.ScreenGuiNativeProps)
			end)
		end)
		if ok then
			return nil
		end
		local text = tostring(failure)
		return string.match(text, "^[^\n]-:%d+: (.*)$") or text
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
	return freeze({ runtime = runtime, UI = UI, mount = mount, refusal = refusal, dispose = dispose })
end
