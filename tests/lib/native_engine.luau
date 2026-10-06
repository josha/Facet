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

local reflection = Roblox.getReflectionDatabase()
local defaultsByClass: { [string]: any } = {}
local defaultsByProperty: { [string]: { [string]: any } } = {}

local function new(options: any?): Engine
	local made: { any } = {}
	local rejectedSelections = {}
	local attributeValues = {}
	local attributeTokens = setmetatable({}, { __mode = "k" })
	local cloneRecords = setmetatable({}, { __mode = "k" })
	local classes: { [string]: any } = {}
	local objects = setmetatable({}, { __mode = "k" })
	local facades = setmetatable({}, { __mode = "kv" })
	local signalAdapters = setmetatable({}, { __mode = "kv" })
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

	local observed = {
		"AbsoluteSize",
		"TextBounds",
		"AbsoluteContentSize",
		"AbsolutePosition",
		"AbsoluteWindowSize",
		"AbsoluteCanvasSize",
		"CanvasPosition",
	}
	local shadow: { [string]: any } = {
		BlurRadius = Roblox.UDim.new(0, 12),
		Color = Roblox.Color3.new(0, 0, 0),
		Offset = Roblox.UDim2.new(),
		Spread = Roblox.UDim2.new(),
		Transparency = 0.5,
		ZIndex = -1,
		Enabled = true,
	}
	local function nativeDefaults(className: string): any
		local cached = defaultsByClass[className]
		if not cached then
			local ok, instance = pcall(function()
				return Roblox.Instance.new(if className == "UIShadow" then "Folder" else className)
			end)
			cached = if ok then instance else Roblox.Instance.new("Folder")
			defaultsByClass[className] = cached
		end
		return cached
	end
	local function defaultProperty(className: string, key: string, fallback: any): any
		if table.find(observed, key) then
			return Roblox.Vector2.zero
		end
		if className == "UICorner" and string.match(key, "Radius$") then
			return Roblox.UDim.new(0, 8)
		end
		if className == "UIShadow" and shadow[key] ~= nil then
			return shadow[key]
		end
		local values = defaultsByProperty[className]
		if not values then
			values = {}
			defaultsByProperty[className] = values
		end
		local cached = values[key]
		if not cached then
			local ok, value = pcall(function()
				return nativeDefaults(className)[key]
			end)
			cached = { ok, value }
			values[key] = cached
		end
		return if cached[1] then cached[2] else fallback
	end
	local environment = VerifyRoblox.testEnvironment({
		builtins = false,
		defaultProperty = defaultProperty,
		validateProperty = function(className, key, value)
			if value == nil then
				return
			end
			local kind = typeof(defaultProperty(className, key, nil))
			if table.find({ "Color3", "UDim2", "UDim", "Vector2" }, kind) then
				assert(typeof(value) == kind, `Unable to assign property {key}. {kind} expected, got {typeof(value)}`)
			end
		end,
	})
	local function raiseHandlerErrors()
		if #environment.errors > 0 then
			local message = table.concat(environment.errors, "\n")
			table.clear(environment.errors)
			error(message, 3)
		end
	end
	local function defineClass(className: string)
		if classes[className] then
			return
		end
		local metadata: any = reflection:GetClass(if className == "UIShadow" then "UIComponent" else className)
		local parent: string? = if className == "UIShadow"
			then "UIComponent"
			elseif metadata then metadata.Superclass
			else nil
		if parent then
			defineClass(parent)
		end
		local properties: { [string]: any } = {}
		local cursor = metadata
		while cursor do
			for key in cursor.Properties do
				properties[key] = false
			end
			cursor = if cursor.Superclass then reflection:GetClass(cursor.Superclass) else nil
		end
		for _, key in observed do
			properties[key] = false
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
		if className == "UICorner" then
			for _, key in { "TopLeftRadius", "TopRightRadius", "BottomLeftRadius", "BottomRightRadius" } do
				properties[key] = false
			end
		elseif className == "UIShadow" then
			for key in shadow do
				properties[key] = false
			end
		end
		local spec = { super = parent, properties = properties, events = eventNames }
		classes[className] = spec
		environment.defineClass(className, spec, { replace = className == "Folder" })
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
	local create: (string) -> any
	function create(className: string): any
		defineClass(className)
		local actual = environment.createInstance(className)
		local overrides: { [string]: any } = {}
		local tags, styleProperties, styleTransitions = {}, {}, {}
		local focused = false
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
			FindFirstChildWhichIsA = function(_, name, recursive)
				for _, child in if recursive then node:GetDescendants() else node:GetChildren() do
					if child:IsA(name) then
						return child
					end
				end
				return nil
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
			FindFirstAncestorWhichIsA = function(_, name)
				local parent = node.Parent
				while parent do
					if parent:IsA(name) then
						return parent
					end
					parent = parent.Parent
				end
				return nil
			end,
			Clone = function()
				if node.Archivable == false then
					return nil
				end
				local copies = {}
				local function copyTree(original: any): any
					local copy = create(original.ClassName)
					copies[original] = copy
					for _, child in original:GetChildren() do
						if child.Archivable ~= false then
							copyTree(child).Parent = copy
						end
					end
					return copy
				end
				local result = copyTree(node)
				for original, copy in copies do
					for property, value in cloneRecords[original] do
						if
							property ~= "Parent"
							and property ~= "_children"
							and property ~= "ClassName"
							and not (original.ClassName == "ViewportFrame" and property == "CurrentCamera")
						then
							if original.ClassName == "Path2D" and property == "ControlPoints" then
								copy:SetControlPoints(value)
							else
								copy[property] = copies[value] or value
							end
						end
					end
					for _, tag in original:GetTags() do
						copy:AddTag(tag)
					end
					copy:SetProperties(original:GetProperties())
					for name, value in original:GetAttributes() do
						copy:SetAttribute(name, value)
					end
				end
				return result
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
				node[property] = defaultProperty(className, property, nil)
			end,
			SetControlPoints = function(_, points)
				node.ControlPoints = table.clone(points)
			end,
			GetControlPoints = function()
				return node.ControlPoints or {}
			end,
			JumpTo = function(_, page)
				node.CurrentPage = page
			end,
			AddTag = function(_, tag)
				tags[tag] = true
			end,
			RemoveTag = function(_, tag)
				tags[tag] = nil
			end,
			HasTag = function(_, tag)
				return tags[tag] == true
			end,
			GetTags = function()
				local result = {}
				for tag in tags do
					table.insert(result, tag)
				end
				return result
			end,
			SetPropertyTransitions = function(_, values)
				styleTransitions = table.clone(values)
			end,
			GetPropertyTransitions = function()
				return table.clone(styleTransitions)
			end,
			SetProperties = function(_, values)
				styleProperties = table.clone(values)
			end,
			GetProperties = function()
				return table.clone(styleProperties)
			end,
			IsFocused = function()
				return focused == true
			end,
			CaptureFocus = function()
				focused = true
				node.Focused.fire()
			end,
			ReleaseFocus = function(_, enter)
				if focused then
					focused = false
					node.FocusLost.fire(enter == true)
				end
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
				return wrapMember(value)
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
				elseif key ~= "Parent" and classes[className].properties[key] == nil then
					assert(
						options and options.lenientProperties,
						`{key} is not a valid member of {className} "{node.Name}"`
					)
					overrides[key] = value
				else
					actual[key] = unwrap(value)
					raiseHandlerErrors()
				end
				cloneRecords[node][key] = value
			end,
		})
		cloneRecords[node] = { Name = className }
		objects[node] = actual
		facades[actual] = node
		if not options or options.recordCreated ~= false then
			table.insert(made, node)
		end
		return node
	end
	function wrap(value: any): any
		if facades[value] then
			return facades[value]
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

	return (
		{
			new = create,
			readCFrame = nil,
			heartbeat = heartbeat,
			clock = os.clock,
			typeName = typeof,
			destroy = function(node: any)
				node:Destroy()
			end,
			propertyChanged = function(node: any, key: string)
				return node:GetPropertyChangedSignal(key)
			end,
			datatypes = {
				CFrame = nil,
				Vector2 = Roblox.Vector2.new,
				Vector3 = Roblox.Vector3.new,
				Color3 = Roblox.Color3.new,
				UDim = Roblox.UDim.new,
				UDim2 = Roblox.UDim2.new,
			},
			census = function()
				assert(not options or options.recordCreated ~= false, "census requires recording all created instances")
				return { live = environment.liveObjects(), connections = environment.liveConnections() }
			end,
			made = made,
			rejectedSelections = rejectedSelections,
			types = types :: Shared.RobloxTypes,
		} :: unknown
	) :: Engine
end
return { new = new }
