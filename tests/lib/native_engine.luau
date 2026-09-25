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
local reflection = Roblox.getReflectionDatabase()
local NEWER_MEMBERS: { [string]: { [string]: boolean } } = {
	InputBinding = { PrimaryModifier = true, SecondaryModifier = true, DisplayName = true, DisplayImage = true },
	InputAction = { PreferredBinding = true },
}
local function isMember(className: string, key: string): boolean
	local newer = NEWER_MEMBERS[className]
	if newer and newer[key] then
		return true
	end
	local class = reflection:GetClass(className)
	if class == nil then
		return true
	end
	while class do
		if class.Properties[key] ~= nil then
			return true
		end
		class = if class.Superclass then reflection:GetClass(class.Superclass) else nil
	end
	return false
end
local function new(options: any?)
	local made = {}
	local rejectedSelections = {}
	local defaultsByClass = {}
	local membersByClass = {}
	local datatypes: { [string]: { [string]: string | false } } = {}
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
		TouchPan = true,
		AncestryChanged = true,
		DescendantAdded = true,
		DescendantRemoving = true,
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
			AbsoluteCanvasSize = Roblox.Vector2.zero,
			CanvasPosition = Roblox.Vector2.zero,
		}
		if className == "UICorner" then
			for _, corner in { "TopLeftRadius", "TopRightRadius", "BottomLeftRadius", "BottomRightRadius" } do
				properties[corner] = Roblox.UDim.new(0, 8)
			end
		end
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
			_hasSignal = function(_, name)
				return signals[name] ~= nil
			end,
			_fireAncestry = function()
				if signals.AncestryChanged then
					signals.AncestryChanged.fire(node, properties.Parent)
				end
				if children[1] ~= nil then
					for _, child in table.clone(children) do
						child:_fireAncestry()
					end
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
				local previous = properties["@" .. key]
				properties["@" .. key] = value
				if previous ~= value and changed["@" .. key] then
					changed["@" .. key].fire()
				end
			end,
			GetAttributeChangedSignal = function(_, key)
				changed["@" .. key] = changed["@" .. key] or signal()
				return changed["@" .. key]
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
				if children[1] ~= nil then
					for _, child in table.clone(children) do
						child:Destroy()
					end
				end
				if not cached then
					defaults:Destroy()
				end
			end,
			connectionCount = function()
				local count = 0
				for _, event in signals do
					count += event.count()
				end
				for _, event in changed do
					count += event.count()
				end
				return count
			end,
			isDestroyed = function()
				return destroyed == true
			end,
		}
		local function lineage(start, name)
			local listeners = {}
			local cursor = start
			while cursor do
				if cursor:_hasSignal(name) then
					table.insert(listeners, cursor)
				end
				cursor = cursor.Parent
			end
			if listeners[1] == nil then
				return
			end
			local subtree = node:GetDescendants()
			table.insert(subtree, 1, node)
			for _, listener in listeners do
				for _, member in subtree do
					listener:_fireSignal(name, member)
				end
			end
		end
		node = setmetatable({}, {
			__index = function(_, key)
				if methods[key] then
					return methods[key]
				end
				if events[key] then
					signals[key] = signals[key] or signal()
					return signals[key]
				end
				if key == "TextBounds" and options and options.measureText then
					return options.measureText(node)
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
				if
					type(key) == "string"
					and properties[key] == nil
					and not events[key]
					and string.sub(key, 1, 1) ~= "_"
					and string.sub(key, 1, 1) ~= "@"
					and not (options and options.lenientProperties == true)
				then
					local members = membersByClass[className]
					if members == nil then
						members = {}
						membersByClass[className] = members
					end
					local valid = members[key]
					if valid == nil then
						valid = pcall(function()
							return defaults[key]
						end) or isMember(className, key)
						members[key] = valid
					end
					local double = type(value) == "function" or (type(value) == "table" and value.Connect ~= nil)
					assert(valid or double, `{key} is not a valid member of {className} "{properties.Name}"`)
				end
				if value ~= nil and type(key) == "string" then
					local kinds = datatypes[className]
					if kinds == nil then
						kinds = {}
						datatypes[className] = kinds
					end
					local kind = kinds[key]
					if kind == nil then
						local ok, default = pcall(function()
							return defaults[key]
						end)
						local found = if ok then typeof(default) else ""
						kind = if found == "Color3"
								or found == "UDim2"
								or found == "UDim"
								or found == "Vector2"
							then found
							else false
						kinds[key] = kind
					end
					if kind then
						assert(
							typeof(value) == kind,
							`Unable to assign property {key}. {kind} expected, got {typeof(value)}`
						)
					end
				end
				local previous = node[key]
				if previous == value then
					return
				end
				if className == "GuiService" and key == "SelectedObject" and value ~= nil then
					local shown = value.Selectable ~= false
					local cursor = value
					while shown and cursor and cursor:IsA("GuiBase2d") do
						if cursor:IsA("GuiObject") and cursor.Visible == false then
							shown = false
						elseif cursor:IsA("LayerCollector") and cursor.Enabled == false then
							shown = false
						end
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
						if not ancestor then
							error(
								`Cannot set GuiService.SelectedObject to {value.Name} because it is not a descendant of a PlayerGui`
							)
						end
					end
				end
				if key == "Parent" and previous then
					lineage(previous, "DescendantRemoving")
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
						lineage(value, "DescendantAdded")
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
		census = function()
			assert(not options or options.recordCreated ~= false, "census requires recording all created instances")
			local live, connections = 0, heartbeat.count()
			for _, node in made do
				if not node:isDestroyed() then
					live += 1
				end
				connections += node:connectionCount()
			end
			return { live = live, connections = connections }
		end,
		made = made,
		rejectedSelections = rejectedSelections,
		types = types,
	}
end
return { new = new }
