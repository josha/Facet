--!strict

local Roblox = require("@lune/roblox")
local VerifyRoblox = require("../../tools/vendor/verify/src/roblox")
local Shared = require("../../src/ui/types")
local ComposeRoblox = require("../../src/vendor/compose/roblox")
export type Signal<A... = ...unknown> = ComposeRoblox.Signal<A...> & {
	Fire: (self: any, A...) -> (),
}
export type Engine = {
	new: (string) -> any,
	clock: () -> number,
	typeName: (any) -> string,
	destroy: (any) -> (),
	propertyChanged: (any, string) -> Signal<()>,
	datatypes: typeof(((nil :: unknown) :: ComposeRoblox.Engine).datatypes),
	readCFrame: typeof(((nil :: unknown) :: ComposeRoblox.Engine).readCFrame),
	heartbeat: Signal<number>,
	types: Shared.RobloxTypes,
	made: { any },
	rejectedSelections: () -> { any },
	census: () -> { live: number, connections: number },
	onWrite: ((any, string, any) -> ()) -> any,
}

local reflection = Roblox.getReflectionDatabase()
local eventNames = {
	"Activated",
	"Focused",
	"ReturnPressedFromOnScreenKeyboard",
	"Pressed",
	"Released",
	"StateChanged",
	"TouchLongPress",
	"TouchPan",
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
local doubles: { [string]: any } = {
	isDestroyed = function(object)
		return owner(function(environment)
			return not environment.isAlive(object)
		end)
	end,
	connectionCount = function(object)
		return owner(function(environment)
			return environment.connectionsOfInstance(object)
		end)
	end,
	_fireSignal = function(object, name, ...)
		object[name]:Fire(...)
	end,
	Play = function(object)
		object.PlayCount = (object.PlayCount or 0) + 1
	end,
	Stop = function(object)
		object.StopCount = (object.StopCount or 0) + 1
	end,
	SetWaveformKeys = function(object, keys)
		object.WaveformKeys = keys
	end,
}
local metadata: { [string]: any } = {}
local classes: { [string]: any } = {}
local names = reflection:GetClassNames()
table.insert(names, "UIShadow")
for _, name in names do
	local original = assert(reflection:GetClass(if name == "UIShadow" then "UIComponent" else name))
	local class: any = { Name = original.Name, Superclass = original.Superclass, Tags = original.Tags }
	class.Name = name
	class.Superclass = if name == "UIShadow" then "UIComponent" else original.Superclass
	class.Properties = {}
	for key, property in original.Properties do
		local opaque = property.Datatype == "ContentId" or property.Datatype == "BinaryString"
		class.Properties[key] = {
			Name = property.Name,
			Datatype = if opaque then "string" else property.Datatype,
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
		properties[key] = Roblox.Vector2.zero
		class.DefaultProperties[key] = Roblox.Vector2.zero
	end
	for _, key in
		{
			"PlayCount",
			"StopCount",
			"WaveformKeys",
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
	if name == "UICorner" then
		for _, key in { "TopLeftRadius", "TopRightRadius", "BottomLeftRadius", "BottomRightRadius" } do
			properties[key] = Roblox.UDim.new(0, 8)
			class.DefaultProperties[key] = properties[key]
		end
	elseif name == "GuiService" then
		class.Properties.PreferredTransparency = nil
		class.DefaultProperties.PreferredTransparency = nil
		properties.PreferredTransparency = 1
		properties.GuiNavigationEnabled = true
		properties.AutoSelectGuiEnabled = true
		class.DefaultProperties.GuiNavigationEnabled = true
		class.DefaultProperties.AutoSelectGuiEnabled = true
	elseif name == "UIShadow" then
		properties = {
			BlurRadius = Roblox.UDim.new(0, 12),
			Color = Roblox.Color3.new(),
			Offset = Roblox.UDim2.new(),
			Spread = Roblox.UDim2.new(),
			Transparency = 0.5,
			ZIndex = -1,
			Enabled = true,
		}
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
		methods[member] = method
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
local nativeDefaults: { [string]: any } = {}
local resolved: { [string]: { [string]: any } } = {}
local ABSENT = table.freeze({})
local function defaultProperty(className: string, key: string): any
	local known = resolved[className]
	if not known then
		known = {}
		resolved[className] = known
	end
	local cached = known[key]
	if cached ~= nil then
		return if cached == ABSENT then nil else cached
	end
	local value = metadata[className].DefaultProperties[key]
	local injected = classes[className].properties[key]
	if value == nil and injected ~= nil and injected ~= false then
		value = injected
	end
	if value == nil then
		if not nativeDefaults[className] then
			local ok, instance = pcall((Roblox.Instance.new :: unknown) :: (string) -> any, className)
			nativeDefaults[className] = if ok then instance else Roblox.Instance.new("Folder")
		end
		local ok, fallback = pcall(function()
			return nativeDefaults[className][key]
		end)
		value = if ok then fallback else nil
	end
	known[key] = if value == nil then ABSENT else value
	return value
end

local function connections(signal: any): number
	return owner(function(environment)
		return environment.connectionsOf(signal)
	end)
end

local function new(options: any?): Engine
	local settings = options or {}
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
		["UIPageLayout.JumpTo"] = function(object, page)
			environment.poke(object, "CurrentPage", page)
		end,
	}
	if settings.styleOnlySignals then
		methods["GuiObject.GetStyledPropertyChangedSignal"] = function()
			return environment.newSignal()
		end
	end
	local bridge = VerifyRoblox.fixtureBridge({
		database = database,
		typeName = function(value: any)
			if type(value) == "table" then
				local source = rawget(value, "SourceType")
				if source and source.Name == "Uri" and type(rawget(value, "Uri")) == "string" then
					return "Content"
				end
			end
			return typeof(value)
		end,
		enumType = function(value)
			return tostring((value :: any).EnumType)
		end,
		classes = classes,
		library = (
				{ typeName = typeof, datatypes = Roblox } :: unknown
			) :: VerifyRoblox.EnvironmentEngineLibrary<any, any, any, any, any, any>,
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
	local made: { any } = {}
	if settings.recordCreated ~= false then
		environment.onCreate(function(object)
			table.insert(made, object)
		end)
	end
	environment.onClone(function(_, copy)
		if copy:IsA("ViewportFrame") then
			environment.poke(copy, "CurrentCamera", nil)
		end
	end)

	local types: any = table.clone(Roblox)
	types.BrickColor = setmetatable({
		palette = function(index: number): any
			return Roblox.BrickColor.palette(index + 1)
		end,
	}, { __index = Roblox.BrickColor })
	local enumTypes = {}
	types.Enum = setmetatable({}, {
		__index = function(_, name)
			if enumTypes[name] then
				return enumTypes[name]
			end
			local original = Roblox.Enum[name]
			if type(original) == "function" then
				return function(_, ...)
					return original(Roblox.Enum, ...)
				end
			end
			local items = original:GetEnumItems()
			local byName, byValue = {}, {}
			for _, item in items do
				byName[item.Name], byValue[item.Value] = item, item
			end
			local proxy = setmetatable({
				FromName = function(_, itemName)
					return byName[itemName]
				end,
				FromValue = function(_, value)
					return byValue[value]
				end,
				GetEnumItems = function()
					return table.clone(items)
				end,
			}, {
				__index = function(_, key)
					return original[key]
				end,
				__tostring = function()
					return tostring(original)
				end,
			})
			enumTypes[name] = proxy
			return proxy
		end,
	})
	types.TweenInfo = VerifyRoblox.datatypes.TweenInfo
	types.FloatCurveKey = VerifyRoblox.datatypes.FloatCurveKey
	types.Path2DControlPoint = VerifyRoblox.datatypes.Path2DControlPoint

	local engine: any = bridge.engine
	engine.clock = os.clock
	engine.census = function()
		assert(settings.recordCreated ~= false, "census requires recording all created instances")
		local accounting = bridge.accounting()
		return { live = accounting.objects, connections = accounting.connections }
	end
	engine.made = made
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
	engine.types = types
	return engine :: Engine
end
return { new = new, connections = connections }
