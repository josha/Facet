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
local reflection = VerifyRoblox.reflectionSnapshot.database(snapshot)
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
local metadata: { [string]: any } = {}
local classes: { [string]: any } = {}
local names = reflection:GetClassNames()
for _, name in names do
	local original = assert(reflection:GetClass(name))
	local class: any = { Name = name, Superclass = original.Superclass, Tags = original.Tags }
	class.Properties = {}
	for key, property in original.Properties do
		local opaque = property.Datatype == "ContentId" or property.Datatype == "BinaryString"
		class.Properties[key] = {
			Name = property.Name,
			Datatype = if opaque then "String" else property.Datatype,
			Scriptability = "ReadWrite",
			Tags = {},
		}
	end
	class.DefaultProperties = table.clone(original.DefaultProperties)
	local properties: { [string]: any } = {}
	if class.Properties.TextFits then
		class.Properties.TextFits = nil
		properties.TextFits = false
	end
	for _, key in
		{
			"AbsoluteSize",
			"TextBounds",
			"AbsoluteContentSize",
			"AbsolutePosition",
			"AbsoluteWindowSize",
			"AbsoluteCanvasSize",
			"CanvasPosition",
		}
	do
		properties[key] = Vector2.zero
		class.DefaultProperties[key] = Vector2.zero
	end
	for _, key in
		{
			"ControlPoints",
			"PrimaryModifier",
			"SecondaryModifier",
			"DisplayName",
			"DisplayImage",
			"PreferredBinding",
		}
	do
		properties[key] = false
	end
	if name == "GuiService" then
		class.Properties.PreferredTransparency = nil
		class.DefaultProperties.PreferredTransparency = nil
		properties.PreferredTransparency = 1
		properties.GuiNavigationEnabled = true
		properties.AutoSelectGuiEnabled = true
		properties.TouchControlsEnabled = true
		class.DefaultProperties.GuiNavigationEnabled = true
		class.DefaultProperties.AutoSelectGuiEnabled = true
		class.DefaultProperties.TouchControlsEnabled = true
	end
	local ui = VerifyRoblox.uiFakes.classes[name]
	local events = table.clone(eventNames)
	if ui and ui.events then
		for _, event in ui.events do
			table.insert(events, event)
		end
	end
	local methods = table.clone(doubles)
	for member, method in (if ui and ui.methods then ui.methods else {}) :: { [string]: any } do
		if method ~= true or methods[member] == nil then
			methods[member] = method
		end
	end
	classes[name] = { creatable = true, properties = properties, events = events, methods = methods }
	metadata[name] = class
end
local database = {
	GetClassNames = function()
		return names
	end,
	GetClass = function(_, name)
		return metadata[name]
	end,
}
local function defaultProperty(className: string, key: string): any
	local injected = classes[className].properties[key]
	return if injected == false then nil else injected
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
	local bridge = VerifyRoblox.fixtureBridge({
		database = database,
		typeName = typeName,
		enumType = library.enumType,
		classes = classes,
		library = VerifyRoblox.reflectionSnapshot.engineLibrary(library),
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
