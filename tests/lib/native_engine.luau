--!strict

local Roblox = require("@lune/roblox")
local function signal()
	local listeners = {}
	return {
		Connect = function(_, callback)
			local token = {}
			listeners[token] = callback
			return {
				Disconnect = function()
					listeners[token] = nil
				end,
			}
		end,
		fire = function(...)
			if next(listeners) == nil then
				return
			end
			for _, callback in table.clone(listeners) do
				callback(...)
			end
		end,
		count = function()
			local count = 0
			for _ in listeners do
				count += 1
			end
			return count
		end,
	}
end
local function new(options: any?)
	local made = {}
	local defaultsByClass = {}
	local cloneRecords = setmetatable({}, { __mode = "k" })
	local events = {
		ChildAdded = true,
		ChildRemoved = true,
		Activated = true,
		Focused = true,
		ReturnPressedFromOnScreenKeyboard = true,
		Pressed = true,
		Released = true,
		StateChanged = true,
		TouchLongPress = true,
		AncestryChanged = true,
		Destroying = true,
		FocusLost = true,
		InputBegan = true,
		InputChanged = true,
		InputEnded = true,
		WindowFocusReleased = true,
		DragStart = true,
		DragContinue = true,
		DragEnd = true,
		MouseEnter = true,
		MouseLeave = true,
		SelectionGained = true,
		SelectionLost = true,
	}
	local function create(className)
		local cached = options and options.cacheDefaults == true
		local record = if cached then defaultsByClass[className] else nil
		if record == nil then
			record = {
				node = Roblox.Instance.new(if className == "UIShadow" then "Folder" else className),
				properties = {},
				ancestry = {},
			}
			if cached then
				defaultsByClass[className] = record
			end
		end
		local defaults = record.node
		local properties = {
			ClassName = className,
			Name = className,
			AbsoluteSize = Roblox.Vector2.zero,
			TextBounds = Roblox.Vector2.zero,
			AbsoluteContentSize = Roblox.Vector2.zero,
			AbsolutePosition = Roblox.Vector2.zero,
			AbsoluteWindowSize = Roblox.Vector2.zero,
			CanvasPosition = Roblox.Vector2.zero,
		}
		if className == "UIShadow" then
			properties.BlurRadius = Roblox.UDim.new(0, 12)
			properties.Color = Roblox.Color3.new(0, 0, 0)
			properties.Offset = Roblox.UDim2.new()
			properties.Spread = Roblox.UDim2.new()
			properties.Transparency = 0.5
			properties.ZIndex = -1
			properties.Enabled = true
		end
		local changed, signals, children = {}, {}, {}
		local node, destroyed, focused
		local tags, styleProperties, styleTransitions = {}, {}, {}
		local methods = {
			_fireSignal = function(_, name, ...)
				if signals[name] then
					signals[name].fire(...)
				end
			end,
			_fireAncestry = function()
				if signals.AncestryChanged then
					signals.AncestryChanged.fire(node, properties.Parent)
				end
				for _, child in table.clone(children) do
					child:_fireAncestry()
				end
			end,
			Clone = function()
				if node.Archivable == false then
					return nil
				end
				local copies = {}
				local function copyTree(original)
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
							copy[property] = copies[value] or value
						end
					end
					for _, tag in original:GetTags() do
						copy:AddTag(tag)
					end
					copy:SetProperties(original:GetProperties())
				end
				return result
			end,
			Play = function()
				properties.PlayCount = (properties.PlayCount or 0) + 1
			end,
			Stop = function()
				properties.StopCount = (properties.StopCount or 0) + 1
			end,
			SetWaveformKeys = function(_, keys)
				properties.WaveformKeys = keys
			end,
			GetStyled = function(_, property)
				return node[property]
			end,
			GetStyledPropertyChangedSignal = function(_, property)
				return node:GetPropertyChangedSignal(property)
			end,
			ResetPropertyToDefault = function(_, property)
				node[property] = defaults[property]
			end,
			SetControlPoints = function(_, points)
				properties.ControlPoints = table.clone(points)
			end,
			GetControlPoints = function()
				return properties.ControlPoints or {}
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
			IsDescendantOf = function(_, ancestor)
				local parent = node.Parent
				while parent do
					if parent == ancestor then
						return true
					end
					parent = parent.Parent
				end
				return false
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
			FindFirstChild = function(_, name, recursive)
				for _, child in children do
					if child.Name == name then
						return child
					end
				end
				if recursive then
					for _, child in children do
						local found = child:FindFirstChild(name, true)
						if found then
							return found
						end
					end
				end
				return nil
			end,
			FindFirstChildWhichIsA = function(_, name, recursive)
				for _, child in children do
					if child:IsA(name) then
						return child
					end
				end
				if recursive then
					for _, child in children do
						local found = child:FindFirstChildWhichIsA(name, true)
						if found then
							return found
						end
					end
				end
				return nil
			end,
			GetDescendants = function()
				local result = {}
				local function visit(parent)
					for _, child in parent:GetChildren() do
						table.insert(result, child)
						visit(child)
					end
				end
				visit(node)
				return result
			end,
			GetChildren = function()
				return table.clone(children)
			end,
			GetPropertyChangedSignal = function(_, key)
				changed[key] = changed[key] or signal()
				return changed[key]
			end,
			SetAttribute = function(_, key, value)
				properties["@" .. key] = value
			end,
			GetAttribute = function(_, key)
				return properties["@" .. key]
			end,
			IsA = function(_, name)
				if name == className or (className == "UIShadow" and name == "UIComponent") then
					return true
				end
				local result = record.ancestry[name]
				if result == nil then
					result = defaults:IsA(name)
					if cached then
						record.ancestry[name] = result
					end
				end
				return result
			end,
			Destroy = function()
				if destroyed then
					return
				end
				destroyed = true
				if signals.Destroying then
					signals.Destroying.fire()
				end
				node.Parent = nil
				for _, child in table.clone(children) do
					child:Destroy()
				end
				if not cached then
					defaults:Destroy()
				end
			end,
			isDestroyed = function()
				return destroyed == true
			end,
		}
		node = setmetatable({}, {
			__index = function(_, key)
				if methods[key] then
					return methods[key]
				end
				if events[key] then
					signals[key] = signals[key] or signal()
					return signals[key]
				end
				if properties[key] ~= nil then
					return properties[key]
				end
				if key == "Parent" then
					return nil
				end
				local known = record.properties[key]
				if known then
					return known.value
				end
				local ok, value = pcall(function()
					return defaults[key]
				end)
				if cached then
					record.properties[key] = { value = if ok then value else nil }
				end
				return if ok then value else nil
			end,
			__newindex = function(_, key, value)
				if className == "Path2D" then
					local valid = pcall(function()
						return defaults[key]
					end)
					assert(valid, `{key} is not a valid member of Path2D "{properties.Name}"`)
				end
				local previous = node[key]
				if previous == value then
					return
				end
				if key == "Parent" then
					if previous then
						local siblings = previous._children
						local index = table.find(siblings, node)
						if index then
							table.remove(siblings, index)
						end
					end
					if value then
						table.insert(value._children, node)
					end
				end
				properties[key] = value
				if key == "Parent" then
					if previous then
						previous:_fireSignal("ChildRemoved", node)
					end
					if value then
						value:_fireSignal("ChildAdded", node)
					end
					methods._fireAncestry()
				end
				if changed[key] then
					changed[key].fire()
				end
			end,
		})
		properties._children = children
		cloneRecords[node] = properties
		if not options or options.recordCreated ~= false then
			table.insert(made, node)
		end
		return node
	end
	local heartbeat = signal()
	local types = table.clone(Roblox)
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
	return {
		new = create,
		heartbeat = heartbeat,
		clock = os.clock,
		typeName = typeof,
		destroy = function(node)
			node:Destroy()
		end,
		propertyChanged = function(node, key)
			return node:GetPropertyChangedSignal(key)
		end,
		datatypes = {
			Vector2 = Roblox.Vector2.new,
			Vector3 = Roblox.Vector3.new,
			Color3 = Roblox.Color3.new,
			UDim = Roblox.UDim.new,
			UDim2 = Roblox.UDim2.new,
		},
		made = made,
		types = types,
	}
end
return { new = new }
