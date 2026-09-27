--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local ControlTypes = require("./control_types")
local ThemeTypes = require("./theme_types")
local Engine = require("./engine_types")
local Overlay = require("./overlay_types")
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
	environment: Types.EnvironmentPreview?,
	keyboardNavigation: boolean?,
	pressHaptic: (HapticEffect | Types.HapticKind)?,
	onError: ((unknown) -> ())?,
	runtime: Types.Runtime?,
	parent: Instance?,
	name: string?,
	screen: Engine.ScreenGuiNativeProps?,
	sheet: ThemeTypes.ThemeOptions?,
	focusRing: boolean?,
}
export type AnchoredOptions = {
	source: Overlay.PopoverSource,
	edge: Overlay.Edge?,
	align: Overlay.Align?,
	gap: number?,
	crossOffset: number?,
	tail: boolean?,
	maxWidth: number?,
	maxHeight: number?,
	modal: boolean?,
	cancelPolicy: ("dismiss" | "none")?,
	onDismiss: ((Overlay.PopoverDismissReason) -> ())?,
}
export type ToastOptions = {
	key: string?,
	priority: number?,
	duration: number?,
	readFloor: number?,
	position: ("top" | "bottom")?,
	width: ("fill" | "hug")?,
	fade: boolean?,
	onDismiss: ((Overlay.ToastDismissReason) -> ())?,
}
export type Toast = { id: number, dismiss: () -> boolean }
export type App = {
	runtime: Types.Runtime,
	UI: ControlTypes.Controls,
	mount: (component: Component, parent: Instance?) -> (() -> (), ScreenGui),
	refusal: (control: string, spec: unknown) -> string?,
	presentAnchored: (
		component: (ControlTypes.Controls) -> Instance,
		options: AnchoredOptions
	) -> (() -> (), ScreenGui),
	presentToast: (component: (ControlTypes.Controls) -> Instance, options: ToastOptions?) -> Toast,
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
			if sheetOptions.tenFoot == nil then
				sheetOptions.tenFoot = UI.environment().isTenFoot
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
			if target:IsA("PlayerGui") and settings.focusRing ~= false then
				props[4] = UI.focusRing(target :: PlayerGui)
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
	local function presentAnchored(
		component: (ControlTypes.Controls) -> Instance,
		options: AnchoredOptions
	): (() -> (), ScreenGui)
		assert(type(component) == "function", "Facet app.presentAnchored: expected a component function")
		assert(
			type(options) == "table" and options.source ~= nil,
			"Facet app.presentAnchored: options.source is required"
		)
		local open = Compose.cell(true)
		local release: () -> () = function() end
		local released = false
		local spec: { [string]: unknown } = {}
		for key, value in (options :: unknown) :: { [string]: unknown } do
			spec[key] = value
		end
		spec.compact = "popover"
		spec.isPresented = open
		spec.onPresentedChange = function(value: boolean)
			open:set(value)
		end
		spec.onDismiss = function(reason: Overlay.PopoverDismissReason)
			if options.onDismiss then
				options.onDismiss(reason)
			end
			if not released then
				released = true
				release()
			end
		end
		spec.content = function(): Instance
			return component(UI)
		end
		local stop, screen = mount(function(): ComposeTypes.Child
			return UI.Popover "Anchored"((spec :: unknown) :: Overlay.PopoverSpec)
		end)
		release = stop
		local function close()
			if not released then
				released = true
				stop()
			end
		end
		return close, screen
	end
	local toasts = 0
	local toastLayer: ScreenGui? = nil
	local function presentToast(component: (ControlTypes.Controls) -> Instance, options: ToastOptions?): Toast
		assert(type(component) == "function", "Facet app.presentToast: expected a component function")
		local spec: { [string]: unknown } = {}
		for key, value in ((options or {}) :: unknown) :: { [string]: unknown } do
			spec[key] = value
		end
		local stop: () -> () = function() end
		local live = true
		local function finish()
			if live then
				live = false
				stop()
			end
		end
		spec.onDismiss = function(reason: Overlay.ToastDismissReason)
			if options and options.onDismiss then
				options.onDismiss(reason)
			end
			finish()
		end
		spec.content = function(): Instance
			return component(UI)
		end
		toasts += 1
		local id = toasts
		if toastLayer == nil or toastLayer.Parent == nil then
			local _, layer = mount(function(): ComposeTypes.Child
				return Host.Folder({ Name = "Toasts" })
			end)
			layer.Name = (settings.name or "Facet") .. "Toasts"
			toastLayer = layer
		end
		stop = runtime.mountFragment(function(): { ComposeTypes.Child }
			return { UI.Toast(`Toast{id}`)((spec :: unknown) :: Overlay.ToastSpec) }
		end, assert(toastLayer))
		if not live then
			stop()
		end
		return freeze({
			id = id,
			dismiss = function(): boolean
				local was = live
				finish()
				return was
			end,
		})
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
	return freeze({
		runtime = runtime,
		UI = UI,
		mount = mount,
		refusal = refusal,
		presentAnchored = presentAnchored,
		presentToast = presentToast,
		dispose = dispose,
	})
end
