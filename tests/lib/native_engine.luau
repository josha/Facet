--!strict

local Roblox = require("@lune/roblox")
local VerifyRoblox = require("../../tools/vendor/verify/src/roblox")
local Shared = require("../../src/ui/types")
local ComposeRoblox = require("../../src/vendor/compose/roblox")
export type Signal<A... = ...unknown> = ComposeRoblox.Signal<A...> & {
	fire: (A...) -> (),
	count: () -> number,
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
	rejectedSelections: { any },
	census: () -> { live: number, connections: number },
}

local objects = setmetatable({}, { __mode = "kv" })
local facades = setmetatable({}, { __mode = "kv" })
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
	class.Properties = table.clone(original.Properties)
	for key, property in original.Properties do
		if property.Datatype == "ContentId" or property.Datatype == "BinaryString" then
			class.Properties[key] = {
				Name = property.Name,
				Datatype = "string",
				Scriptability = property.Scriptability,
				Tags = property.Tags,
			}
		end
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
	classes[name] =
		{ creatable = true, properties = properties, events = events, methods = if ui then ui.methods else nil }
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
local function defaultProperty(className: string, key: string): any
	local value = metadata[className].DefaultProperties[key]
	if value ~= nil then
		return value
	end
	local injected = classes[className].properties[key]
	if injected ~= nil and injected ~= false then
		return injected
	end
	if not nativeDefaults[className] then
		local ok, instance = pcall((Roblox.Instance.new :: unknown) :: (string) -> any, className)
		nativeDefaults[className] = if ok then instance else Roblox.Instance.new("Folder")
	end
	local ok, fallback = pcall(function()
		return nativeDefaults[className][key]
	end)
	return if ok then fallback else nil
end

local function new(options: any?): Engine
	local made: { any } = {}
	local rejectedSelections = {}
	local attributeValues = {}
	local attributeTokens = setmetatable({}, { __mode = "k" })
	local signalAdapters = setmetatable({}, { __mode = "kv" })
	local environment = VerifyRoblox.reflection.create({
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
	})
	local function raiseHandlerErrors()
		if #environment.errors > 0 then
			local message = table.concat(environment.errors, "\n")
			table.clear(environment.errors)
			error(message, 3)
		end
	end
	local wrap: (any) -> any
	local function unwrap(value: any): any
		return objects[value] or value
	end
	local function adaptSignal<A...>(actual: VerifyRoblox.Signal<A...>): any
		local existing = signalAdapters[actual]
		if existing then
			return existing
		end
		local connections = setmetatable({} :: { [VerifyRoblox.Connection]: boolean }, { __mode = "k" })
		local adapter = {
			Connect = function(_, callback)
				local connection = actual:Connect(function(...)
					local args = table.pack(...)
					for index = 1, args.n do
						args[index] = wrap(args[index])
					end
					callback(table.unpack(args, 1, args.n))
				end)
				connections[connection] = true
				return connection
			end,
			fire = function(...)
				local args = table.pack(...)
				for index = 1, args.n do
					args[index] = unwrap(args[index])
				end
				actual:Fire(table.unpack(args, 1, args.n))
				raiseHandlerErrors()
			end,
			count = function()
				local live = 0
				for connection in pairs(connections) do
					if connection.Connected then
						live += 1
					end
				end
				return live
			end,
		}
		signalAdapters[actual] = adapter
		return adapter
	end
	VerifyRoblox.uiFakes.attach(environment, {
		methods = {
			["UIPageLayout.JumpTo"] = function(object, page)
				assert(VerifyRoblox.isInstance(object), "page layout fake requires an instance")
				environment.poke(object :: VerifyRoblox.Instance, "CurrentPage", page)
			end,
		},
	})
	local function facade(actual: any): any
		local className = actual.ClassName
		local overrides: { [string]: any } = {}
		local nodeSignals: { [any]: boolean } = {}
		local function wrapMember(value: any): any
			local result = wrap(value)
			if type(result) == "table" and result.count then
				nodeSignals[result] = true
			end
			return result
		end
		local node: any
		local methods = {
			_fireSignal = function(_, name, ...)
				node[name].fire(...)
			end,
			SetAttribute = function(_, key, value)
				if type(value) == "table" and value.Time and value.EasingStyle then
					local token = attributeTokens[value]
					if not token then
						token = `FacetTweenInfo:{tostring(value)}`
						attributeTokens[value] = token
						attributeValues[token] = value
					end
					value = token
				end
				actual:SetAttribute(key, value)
				raiseHandlerErrors()
			end,
			GetAttribute = function(_, key)
				local value = actual:GetAttribute(key)
				return attributeValues[value] or value
			end,
			GetAttributes = function()
				local values = actual:GetAttributes()
				for key, value in values do
					values[key] = attributeValues[value] or value
				end
				return values
			end,
			Clone = function()
				local copy = actual:Clone()
				if not copy then
					return nil
				end
				local function copyUiState(source: any, target: any)
					wrap(target)
					if source:IsA("StyleRule") then
						target:SetProperties(source:GetProperties())
						target:SetPropertyTransitions(source:GetPropertyTransitions())
					elseif source:IsA("Path2D") then
						target:SetControlPoints(source:GetControlPoints())
					elseif source:IsA("ViewportFrame") then
						environment.poke(target, "CurrentCamera", nil)
					end
					local index = 0
					local children = target:GetChildren()
					for _, child in source:GetChildren() do
						if child.Archivable ~= false then
							index += 1
							copyUiState(child, children[index])
						end
					end
				end
				copyUiState(actual, copy)
				return wrap(copy)
			end,
			Play = function()
				node.PlayCount = (node.PlayCount or 0) + 1
			end,
			Stop = function()
				node.StopCount = (node.StopCount or 0) + 1
			end,
			SetWaveformKeys = function(_, keys)
				node.WaveformKeys = keys
			end,
			GetStyled = function(_, property)
				return node[property]
			end,
			GetStyledPropertyChangedSignal = function(_, property)
				if options and options.styleOnlySignals then
					return adaptSignal(environment.newSignal())
				end
				return node:GetPropertyChangedSignal(property)
			end,
			ResetPropertyToDefault = function(_, property)
				node[property] = defaultProperty(className, property)
			end,
			connectionCount = function()
				local count = 0
				for signal in nodeSignals do
					count += signal.count()
				end
				return count
			end,
			isDestroyed = function()
				return not environment.isAlive(actual)
			end,
		}
		node = setmetatable({}, {
			__index = function(_, key)
				if overrides[key] ~= nil then
					return overrides[key]
				end
				if methods[key] then
					return methods[key]
				end
				if key == "TextBounds" and options and options.measureText then
					return options.measureText(node)
				end
				if key == "TextFits" and options and options.textFits then
					local value = options.textFits(node)
					if value ~= nil then
						return value
					end
				end
				local ok, value = pcall(function()
					return ((actual :: unknown) :: { [string]: any })[key]
				end)
				if not ok then
					return nil
				end
				if type(value) == "function" then
					return function(_, ...)
						local args = table.pack(...)
						for index = 1, args.n do
							args[index] = unwrap(args[index])
						end
						local values: any =
							table.pack((value :: (...any) -> ...any)(actual, table.unpack(args, 1, args.n)))
						raiseHandlerErrors()
						for index = 1, values.n do
							local entry = values[index]
							if key == "GetChildren" or key == "GetDescendants" then
								local result = {}
								for i, child in entry do
									result[i] = wrap(child)
								end
								entry = result
							else
								entry = wrapMember(entry)
							end
							values[index] = entry
						end
						return table.unpack(values, 1, values.n)
					end
				end
				return wrapMember(if value == nil and key ~= "TextFits" then defaultProperty(className, key) else value)
			end,
			__newindex = function(_, key, value)
				if className == "GuiService" and key == "SelectedObject" and value then
					local cursor = value
					local shown = value.Selectable ~= false
					while shown and cursor and cursor:IsA("GuiBase2d") do
						shown = not (
							(cursor:IsA("GuiObject") and cursor.Visible == false)
							or (cursor:IsA("LayerCollector") and cursor.Enabled == false)
						)
						cursor = cursor.Parent
					end
					if not shown then
						table.insert(rejectedSelections, value)
						return
					end
					if options and options.selectionNeedsPlayerGui then
						local ancestor = value.Parent
						while ancestor and ancestor.ClassName ~= "PlayerGui" do
							ancestor = ancestor.Parent
						end
						assert(
							ancestor,
							`Cannot set GuiService.SelectedObject to {value.Name} because it is not a descendant of a PlayerGui`
						)
					end
				end
				if
					type(value) == "function"
					or (type(value) == "table" and value.Connect ~= nil)
					or string.sub(key, 1, 1) == "_"
				then
					overrides[key] = value
				elseif
					options
					and options.lenientProperties
					and key ~= "Parent"
					and metadata[className].Properties[key] == nil
					and classes[className].properties[key] == nil
				then
					overrides[key] = value
				else
					if key == "Parent" then
						actual.Parent = unwrap(value)
					else
						environment.poke(actual, key, unwrap(value))
					end
					raiseHandlerErrors()
				end
			end,
		})
		objects[node] = actual
		facades[actual] = node
		if not options or options.recordCreated ~= false then
			table.insert(made, node)
		end
		return node
	end
	local function create(className: string): any
		return facade(environment.createInstance(className))
	end
	function wrap(value: any): any
		if facades[value] then
			return facades[value]
		end
		if VerifyRoblox.isInstance(value) then
			return facade(value)
		end
		if type(value) == "table" and type(value.Connect) == "function" then
			return adaptSignal(value)
		end
		return value
	end
	local heartbeat = adaptSignal(environment.heartbeat)

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
	types.TweenInfo = {
		new = function(seconds, easingStyle, easingDirection, repeatCount, reverses, delayTime)
			return {
				Time = seconds or 1,
				EasingStyle = easingStyle or Roblox.Enum.EasingStyle.Quad,
				EasingDirection = easingDirection or Roblox.Enum.EasingDirection.Out,
				RepeatCount = repeatCount or 0,
				Reverses = reverses or false,
				DelayTime = delayTime or 0,
			}
		end,
	}
	types.FloatCurveKey = {
		new = function(time, value, interpolation)
			return { Time = time, Value = value, Interpolation = interpolation }
		end,
	}
	types.Path2DControlPoint = {
		new = function(position, leftTangent, rightTangent)
			return { Position = position, LeftTangent = leftTangent, RightTangent = rightTangent }
		end,
	}

	local engine: any = VerifyRoblox.environmentEngine(
		environment,
		(
				{ typeName = typeof, datatypes = Roblox } :: unknown
			) :: VerifyRoblox.EnvironmentEngineLibrary<any, any, any, any, any, any>
	)
	engine.new = create
	engine.heartbeat = heartbeat
	engine.clock = os.clock
	engine.census = function()
		assert(not options or options.recordCreated ~= false, "census requires recording all created instances")
		return { live = environment.liveObjects(), connections = environment.liveConnections() }
	end
	engine.made = made
	engine.rejectedSelections = rejectedSelections
	engine.types = types
	return engine :: Engine
end
return { new = new }
