--!strict

local Lute = require("../../tools/vendor/verify/src/lute")
local VerifyRoblox = require("../../tools/vendor/verify/src/roblox")
local Shared = require("../../src/ui/types")
local ComposeRoblox = require("../../src/vendor/compose/roblox")
export type Signal<A... = ...unknown> = ComposeRoblox.Signal<A...> & {
	Fire: (self: any, A...) -> (),
}
export type Engine = {
	environment: VerifyRoblox.Environment,
	new: (string) -> any,
	clock: () -> number,
	typeName: (any) -> string,
	destroy: (any) -> (),
	propertyChanged: (any, string) -> Signal<()>,
	datatypes: typeof(((nil :: unknown) :: ComposeRoblox.Engine).datatypes),
	readCFrame: typeof(((nil :: unknown) :: ComposeRoblox.Engine).readCFrame),
	heartbeat: Signal<number>,
	types: Shared.RobloxTypes,
	rejectedSelections: () -> { any },
	census: () -> { live: number, connections: number },
	onWrite: ((any, string, any) -> ()) -> any,
}
export type Options = {
	measureText: ((any) -> any)?,
	textFits: ((any) -> any)?,
	getStyled: ((any, string) -> any)?,
	styleOnlySignals: boolean?,
	selectionNeedsPlayerGui: boolean?,
	lenientProperties: boolean?,
}

local SNAPSHOT = "tests/fixtures/roblox-reflection.json"

local snapshot = Lute.fixture.load(SNAPSHOT)
local library = VerifyRoblox.reflectionSnapshot.library(snapshot)
local typeName = VerifyRoblox.typeName
local datatypes: { [string]: unknown } = table.clone((library :: unknown) :: { [string]: unknown })
datatypes.typeof = typeName
local types = (table.freeze(datatypes) :: unknown) :: Shared.RobloxTypes
local Vector2 = library.Vector2

local eventNames = {
	"StyledPropertiesChanged",
	"Activated",
	"Focused",
	"ReturnPressedFromOnScreenKeyboard",
	"Pressed",
	"Released",
	"StateChanged",
	"TouchLongPress",
	"TouchPan",
	"TouchSwipe",
	"TouchPinch",
	"TextBoxFocused",
	"TextBoxFocusReleased",
	"FocusLost",
	"InputBegan",
	"InputChanged",
	"InputEnded",
	"LastInputTypeChanged",
	"WindowFocusReleased",
	"WindowFocused",
	"DragStart",
	"DragContinue",
	"DragEnd",
	"MouseEnter",
	"MouseLeave",
	"MouseMoved",
	"MouseButton1Down",
	"SelectionGained",
	"SelectionLost",
	"OnClientEvent",
}
local environments: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local function owner(probe: (any) -> any): any
	for environment in environments do
		local ok, value = pcall(probe, environment)
		if ok then
			return value
		end
	end
	error("the value was not created by a native engine fixture", 3)
end
local localization: { [unknown]: { { Key: string, Source: string, Values: { [string]: string } } } } = {}
setmetatable(localization, { __mode = "k" })
local doubles: { [string]: any } = {
	SetEntries = function(object: unknown, entries: { { Key: string, Source: string, Values: { [string]: string } } })
		localization[object] = entries
	end,
	GetTranslator = function(object: unknown, locale: string)
		return {
			FormatByKey = function(_self: unknown, key: string, arguments: { [string]: unknown }): string
				for _, entry in assert(localization[object]) do
					if entry.Key == key then
						return (
							string.gsub(
								entry.Values[locale] or entry.Source,
								"{([%w_]+)}",
								function(name: string): string
									return tostring(arguments[name])
								end
							)
						)
					end
				end
				error("Unknown localization key: " .. key)
			end,
		}
	end,

	isDestroyed = function(object)
		return owner(function(environment)
			return not environment.isAlive(object)
		end)
	end,
	GetMouseLocation = function()
		return Vector2.new(-1, -1)
	end,
	GetGuiInset = function()
		return Vector2.zero, Vector2.zero
	end,
	IsKeyDown = function()
		return false
	end,
	GetGuiObjectsAtPosition = function()
		return {}
	end,
}
local instanceMethods = table.clone(assert(VerifyRoblox.uiFakes.classes.Instance.methods))
for name, method in doubles do
	instanceMethods[name] = method
end
local classes: { [string]: VerifyRoblox.EnvironmentClass } = {}
classes.Instance = { events = eventNames, methods = instanceMethods }
classes.GuiService = {
	properties = {
		PreferredTransparency = 1,
		GuiNavigationEnabled = true,
		AutoSelectGuiEnabled = true,
		TouchControlsEnabled = true,
	} :: { [string]: unknown },
	methods = { GetGuiInset = doubles.GetGuiInset, GetGuiObjectsAtPosition = doubles.GetGuiObjectsAtPosition },
}
local function defaultProperty(_className: string, key: string): unknown
	return if key == "AbsoluteSize"
			or key == "AbsolutePosition"
			or key == "AbsoluteContentSize"
		then Vector2.zero
		else nil
end

local function connections(signal: any): number
	return owner(function(environment)
		return environment.connectionsOf(signal)
	end)
end

local function new(options: Options?): (Engine, VerifyRoblox.FixtureBridge)
	local settings: Options = options or {}
	local environment: VerifyRoblox.Environment
	local computed: { [string]: any } = {}
	for _, class in { "TextLabel", "TextButton", "TextBox" } do
		if settings.measureText then
			computed[class .. ".TextBounds"] = { get = settings.measureText, writable = true }
		end
		if settings.textFits then
			computed[class .. ".TextFits"] = { get = settings.textFits, writable = true }
		end
	end
	local methods: { [string]: any } = {
		["Instance.GetStyled"] = function(object: VerifyRoblox.Instance, property: string): unknown
			return object[property]
		end,
		["Instance.GetStyledPropertyChangedSignal"] = function(object: VerifyRoblox.Instance, property: string)
			return object:GetPropertyChangedSignal(property)
		end,
		["UIPageLayout.JumpTo"] = function(object, page)
			environment.poke(object, "CurrentPage", page)
		end,
	}
	if settings.getStyled then
		methods["Instance.GetStyled"] = settings.getStyled
	end
	if settings.styleOnlySignals then
		methods["GuiObject.GetStyledPropertyChangedSignal"] = function()
			return environment.newSignal()
		end
	end
	local bridge = Lute.fixture.bridge(snapshot, {
		classes = classes,
		defaultProperty = defaultProperty,
		handlerErrors = "raise",
		functionDoubles = true,
		undeclaredReads = "nil",
		undeclaredWrites = settings.lenientProperties == true,
		computed = computed,
		ui = {
			selection = "ignore",
			requirePlayerGui = settings.selectionNeedsPlayerGui == true,
			methods = methods,
		},
	})
	environment = bridge.environment
	environments[environment] = true
	environment.onClone(function(_, copy)
		if copy:IsA("ViewportFrame") then
			environment.poke(copy, "CurrentCamera", nil)
		end
	end)

	local engine: any = bridge.engine
	engine.new = function(className: string)
		local object = environment.createEngineInstance(className)
		if object:IsA("GuiBase2d") then
			environment.poke(object, "AbsoluteSize", Vector2.zero)
			environment.poke(object, "AbsolutePosition", Vector2.zero)
		end
		return object
	end
	engine.environment = environment
	engine.census = function()
		local accounting = bridge.accounting()
		return { live = accounting.objects, connections = accounting.connections }
	end
	engine.rejectedSelections = function(): { any }
		local targets = {}
		for _, rejection in assert(bridge.ui).rejectedSelections() do
			table.insert(targets, rejection.target)
		end
		return targets
	end
	engine.onWrite = function(listener: (any, string, any) -> ())
		return bridge.observe(function(event: any)
			if event.operation == "setProperty" or event.operation == "setParent" then
				listener(event.object, event.member or "Parent", event.value)
			end
		end)
	end
	engine.types = table.clone(types)
	return engine :: Engine, bridge
end
return { new = new, connections = connections, types = types }
