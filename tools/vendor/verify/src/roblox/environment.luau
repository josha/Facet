--!strict

local Datatypes = require "./datatypes"
local Scheduler = require "./scheduler"

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, handler: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
}

export type ClassSpec = {
	super: string?,
	creatable: boolean?,
	properties: { [string]: any }?,
	events: { string }?,
	methods: { [string]: any }?,
}

export type Limits = {
	attributeNameLength: number?,
	attributeStringLength: number?,
}

export type Options = {
	classes: { [string]: ClassSpec }?,
	builtins: boolean?,
	fakes: { [string]: (self: any, ...any) -> ...any }?,
	limits: Limits?,
}

export type Operation = "create" | "setProperty" | "setAttribute" | "setParent" | "destroy"

export type Environment = {
	root: any,
	heartbeat: Signal,
	scheduler: Scheduler.Scheduler,
	task: {
		spawn: (callback: any, ...any) -> thread,
		defer: (callback: any, ...any) -> thread,
		delay: (seconds: number, callback: any, ...any) -> thread,
		wait: (seconds: number?) -> number,
		cancel: (thread: thread) -> (),
	},
	errors: { string },
	defineClass: (className: string, spec: ClassSpec) -> (),
	fake: (member: string, handler: (self: any, ...any) -> ...any) -> (),
	createInstance: (className: string, props: { [any]: any }?) -> any,
	snapshot: (object: any) -> any,
	newSignal: () -> Signal,
	step: (seconds: number) -> (),
	now: () -> number,
	childrenOf: (object: any) -> { any },
	parentOf: (object: any) -> any,
	propertyOf: (object: any, key: string) -> any,
	attributeOf: (object: any, name: string) -> any,
	isAlive: (object: any) -> boolean,
	liveObjects: () -> number,
	liveConnections: () -> number,
	poke: (object: any, key: string, value: any) -> (),
	fire: (object: any, event: string, ...any) -> (),
	failNext: (operation: Operation, times: number?) -> (),
	clearFailures: () -> (),
}

type Resolved = {
	creatable: boolean,
	properties: { [string]: any },
	events: { [string]: true },
	methods: { [string]: any },
}

type State = {
	className: string,
	class: Resolved,
	values: { [string]: any },
	children: { any },
	parent: any,
	attributes: { [string]: any },
	signals: { [string]: any },
	destroyed: boolean,
}

local ATTRIBUTE_NAME_LIMIT = 100

local UNIVERSAL_EVENTS: { string } =
	{ "Changed", "ChildAdded", "ChildRemoved", "Destroying", "AttributeChanged", "DescendantAdded" }

local BASIC_CLASSES: { [string]: ClassSpec } = {
	Instance = { creatable = false },
	Folder = { super = "Instance" },
	Model = { super = "Instance", properties = { PrimaryPart = false } },
	Configuration = { super = "Instance" },
	BasePart = {
		super = "Instance",
		creatable = false,
		properties = { Transparency = 0, Anchored = false, CanCollide = true },
		events = { "Touched", "TouchEnded" },
	},
	Part = { super = "BasePart" },
	MeshPart = { super = "BasePart" },
	GuiObject = {
		super = "Instance",
		creatable = false,
		properties = {
			Visible = true,
			BackgroundTransparency = 0,
			BackgroundColor3 = Datatypes.Color3.new(1, 1, 1),
			LayoutOrder = 0,
			ZIndex = 1,
			Size = Datatypes.UDim2.new(0, 0, 0, 0),
			Position = Datatypes.UDim2.new(0, 0, 0, 0),
			AnchorPoint = Datatypes.Vector2.new(0, 0),
			Active = false,
			ClipsDescendants = false,
		},
		events = { "InputBegan", "InputEnded", "MouseEnter", "MouseLeave" },
	},
	Frame = { super = "GuiObject" },
	CanvasGroup = { super = "GuiObject", properties = { GroupTransparency = 0 } },
	ScrollingFrame = {
		super = "GuiObject",
		properties = {
			CanvasSize = Datatypes.UDim2.new(0, 0, 0, 0),
			CanvasPosition = Datatypes.Vector2.new(0, 0),
			ScrollingEnabled = true,
			ScrollBarThickness = 12,
		},
	},
	TextBox = {
		super = "GuiObject",
		properties = { Text = "", PlaceholderText = "", ClearTextOnFocus = true },
		events = { "Focused", "FocusLost" },
	},
	UIListLayout = {
		super = "Instance",
		properties = { Padding = Datatypes.UDim.new(0, 0), SortOrder = false, FillDirection = false },
	},
	UIPadding = {
		super = "Instance",
		properties = {
			PaddingLeft = Datatypes.UDim.new(0, 0),
			PaddingRight = Datatypes.UDim.new(0, 0),
			PaddingTop = Datatypes.UDim.new(0, 0),
			PaddingBottom = Datatypes.UDim.new(0, 0),
		},
	},
	TextLabel = { super = "GuiObject", properties = { Text = "" } },
	TextButton = {
		super = "GuiObject",
		properties = { Text = "" },
		events = { "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up" },
	},
	ImageLabel = { super = "GuiObject", properties = { Image = "" } },
	ImageButton = {
		super = "GuiObject",
		properties = { Image = "" },
		events = { "Activated", "MouseButton1Click" },
	},
	ScreenGui = { super = "Instance", properties = { Enabled = true } },
	Humanoid = { super = "Instance", properties = { Health = 100, MaxHealth = 100 } },
	Animation = { super = "Instance", properties = { AnimationId = "" } },
	AnimationTrack = {
		super = "Instance",
		properties = { Animation = false, IsPlaying = false, Speed = 1, Weight = 1, TimePosition = 0, Looped = false },
		events = { "Stopped", "Ended", "DidLoop", "KeyframeReached" },
	},
}

local function create(options: Options?): Environment
	local settings: Options = options or {}
	local limits: Limits = settings.limits or {}
	local specs: { [string]: ClassSpec } = {}
	local fakes: { [string]: (self: any, ...any) -> ...any } = {}
	local initialFakes: { [string]: (self: any, ...any) -> ...any } = settings.fakes or {}
	for member, handler in initialFakes do
		fakes[member] = handler
	end
	local resolved: { [string]: Resolved } = {}
	local failures: { [string]: number } = {}
	local errors: { string } = {}
	local scheduler = Scheduler.create()
	local connections = 0
	local alive = 0

	local environment: any = {}
	local newObject: (className: string, props: { [any]: any }?, isRoot: boolean) -> any

	local function defineClass(className: string, spec: ClassSpec)
		if type(className) ~= "string" or className == "" then
			error("class name must be a non-empty string", 2)
		end
		if specs[className] ~= nil then
			error(("class %q is already defined"):format(className), 2)
		end
		specs[className] = spec
		table.clear(resolved)
	end

	if settings.builtins ~= false then
		for className, spec in BASIC_CLASSES do
			specs[className] = spec
		end
	end
	local extraClasses: { [string]: ClassSpec } = settings.classes or {}
	for className, spec in extraClasses do
		specs[className] = spec
	end

	local function resolve(className: string): Resolved?
		local cached = resolved[className]
		if cached ~= nil then
			return cached
		end
		local spec = specs[className]
		if spec == nil then
			return nil
		end
		local parent: Resolved? = if spec.super ~= nil then resolve(spec.super) else nil
		if spec.super ~= nil and parent == nil then
			error(("class %q extends undefined class %q"):format(className, spec.super), 3)
		end
		local result: Resolved = {
			creatable = if spec.creatable ~= nil then spec.creatable else true,
			properties = if parent ~= nil then table.clone(parent.properties) else { Name = false },
			events = if parent ~= nil then table.clone(parent.events) else {},
			methods = if parent ~= nil then table.clone(parent.methods) else {},
		}
		if parent == nil then
			for _, event in UNIVERSAL_EVENTS do
				result.events[event] = true
			end
		end
		local declared: { [string]: any } = spec.properties or {}
		for key, default in declared do
			result.properties[key] = default
		end
		local declaredEvents: { string } = spec.events or {}
		for _, event in declaredEvents do
			result.events[event] = true
		end
		local declaredMethods: { [string]: any } = spec.methods or {}
		for key, method in declaredMethods do
			result.methods[key] = method
		end
		resolved[className] = result
		return result
	end

	local function isA(className: string, target: string): boolean
		local walk: string? = className
		while walk ~= nil do
			if walk == target then
				return true
			end
			local spec = specs[walk]
			walk = if spec ~= nil then spec.super else nil
		end
		return false
	end

	local function inject(operation: Operation)
		local remaining = failures[operation]
		if remaining ~= nil and remaining > 0 then
			failures[operation] = remaining - 1
			error(("environment: injected failure in %s"):format(operation), 0)
		end
	end

	local function newSignal(): Signal
		local live: { { handler: (...any) -> (), connected: boolean } } = {}
		local signal: any = {}
		function signal:Connect(handler: (...any) -> ()): Connection
			local record = { handler = handler, connected = true }
			table.insert(live, record)
			connections += 1
			local connection: any = { Connected = true }
			function connection:Disconnect()
				if not record.connected then
					return
				end
				record.connected = false
				connection.Connected = false
				connections -= 1
				local index = table.find(live, record)
				if index ~= nil then
					table.remove(live, index)
				end
			end
			return connection :: Connection
		end
		function signal:Fire(...: any)
			for _, record in table.clone(live) do
				if record.connected then
					local ok, thrown: any = pcall(record.handler, ...)
					if not ok then
						table.insert(errors, tostring(thrown))
					end
				end
			end
		end
		function signal:DisconnectAll()
			for _, record in table.clone(live) do
				if record.connected then
					record.connected = false
					connections -= 1
				end
			end
			table.clear(live)
		end
		return signal :: Signal
	end

	local function stateOf(object: any): State
		return rawget(object, "__state") :: State
	end

	local function isObject(value: any): boolean
		return type(value) == "table" and rawget(value, "__state") ~= nil
	end

	local function signalFor(state: State, key: string): any
		local existing = state.signals[key]
		if existing == nil then
			existing = newSignal()
			state.signals[key] = existing
		end
		return existing
	end

	local function describe(state: State): string
		return ("%s %q"):format(state.className, tostring(state.values.Name))
	end

	local function memberError(state: State, key: string): never
		error(("%s is not a valid member of %s"):format(key, describe(state)), 3)
	end

	local function changed(object: any, state: State, property: string)
		signalFor(state, "prop:" .. property):Fire()
		signalFor(state, "Changed"):Fire(property)
	end

	local function detach(object: any, state: State)
		local parent = state.parent
		if parent == nil then
			return
		end
		local siblings = stateOf(parent).children
		local index = table.find(siblings, object)
		if index ~= nil then
			table.remove(siblings, index)
		end
		state.parent = nil
		signalFor(stateOf(parent), "ChildRemoved"):Fire(object)
	end

	local function setParent(object: any, state: State, parent: any)
		inject "setParent"
		if state.destroyed then
			error(("The Parent property of %s is locked"):format(describe(state)), 4)
		end
		if parent ~= nil and not isObject(parent) then
			error(("Parent of %s must be an Instance of this environment"):format(describe(state)), 4)
		end
		local walk = parent
		while walk ~= nil do
			if walk == object then
				error(("Attempt to set %s as its own ancestor"):format(describe(state)), 4)
			end
			walk = stateOf(walk).parent
		end
		if state.parent == parent then
			return
		end
		detach(object, state)
		if parent ~= nil then
			state.parent = parent
			table.insert(stateOf(parent).children, object)
			signalFor(stateOf(parent), "ChildAdded"):Fire(object)
			local ancestor = parent
			while ancestor ~= nil do
				signalFor(stateOf(ancestor), "DescendantAdded"):Fire(object)
				ancestor = stateOf(ancestor).parent
			end
		end
		changed(object, state, "Parent")
	end

	local function destroy(object: any, state: State)
		if state.destroyed then
			return
		end
		inject "destroy"
		signalFor(state, "Destroying"):Fire()
		for _, child in table.clone(state.children) do
			destroy(child, stateOf(child))
		end
		detach(object, state)
		state.destroyed = true
		alive -= 1
		for _, signal in state.signals do
			signal:DisconnectAll()
		end
	end

	local function validAttribute(name: any, value: any)
		local nameLimit = limits.attributeNameLength or ATTRIBUTE_NAME_LIMIT
		if type(name) ~= "string" or name == "" or string.match(name, "^[%w_]+$") == nil then
			error("attribute names must be non-empty alphanumeric or underscore strings", 4)
		end
		if #name > nameLimit then
			error(("attribute name %q is longer than %d characters"):format(name, nameLimit), 4)
		end
		if string.sub(name, 1, 3) == "RBX" then
			error("attribute names must not start with RBX", 4)
		end
		local kind = type(value)
		if kind == "table" or kind == "function" or kind == "thread" then
			error(("attribute %q cannot hold a %s"):format(name, kind), 4)
		end
		if kind == "string" and limits.attributeStringLength ~= nil and #value > limits.attributeStringLength then
			error(("attribute %q string is longer than %d characters"):format(name, limits.attributeStringLength), 4)
		end
	end

	local function memberMethod(object: any, state: State, key: string): ((...any) -> ...any)?
		local method = state.class.methods[key]
		if method == nil then
			return nil
		end
		local implementation: any = if method == true then fakes[state.className .. "." .. key] else method
		if implementation == nil then
			local walk: string? = specs[state.className].super
			while implementation == nil and walk ~= nil do
				implementation = fakes[walk .. "." .. key]
				local spec = specs[walk]
				walk = if spec ~= nil then spec.super else nil
			end
		end
		if implementation == nil then
			error(
				("unsupported_method: %s.%s is declared but has no simulation or configured fake"):format(
					state.className,
					key
				),
				3
			)
		end
		return function(_self: any, ...: any): ...any
			return implementation(object, ...)
		end
	end

	local function universal(object: any, state: State, key: string): ((...any) -> ...any)?
		if key == "Destroy" then
			return function()
				destroy(object, state)
			end
		elseif key == "ClearAllChildren" then
			return function()
				for _, child in table.clone(state.children) do
					destroy(child, stateOf(child))
				end
			end
		elseif key == "GetChildren" then
			return function()
				return table.clone(state.children)
			end
		elseif key == "GetDescendants" then
			return function()
				local out: { any } = {}
				local function walk(parent: any)
					for _, child in stateOf(parent).children do
						table.insert(out, child)
						walk(child)
					end
				end
				walk(object)
				return out
			end
		elseif key == "FindFirstChild" then
			return function(_self: any, name: string, recursive: boolean?): any
				local function search(parent: any): any
					for _, child in stateOf(parent).children do
						if stateOf(child).values.Name == name then
							return child
						end
					end
					if recursive == true then
						for _, child in stateOf(parent).children do
							local found = search(child)
							if found ~= nil then
								return found
							end
						end
					end
					return nil
				end
				return search(object)
			end
		elseif key == "FindFirstChildOfClass" or key == "FindFirstChildWhichIsA" then
			return function(_self: any, className: string): any
				for _, child in state.children do
					local childClass = stateOf(child).className
					if childClass == className or (key == "FindFirstChildWhichIsA" and isA(childClass, className)) then
						return child
					end
				end
				return nil
			end
		elseif key == "FindFirstAncestor" then
			return function(_self: any, name: string): any
				local walk = state.parent
				while walk ~= nil do
					if stateOf(walk).values.Name == name then
						return walk
					end
					walk = stateOf(walk).parent
				end
				return nil
			end
		elseif key == "GetFullName" then
			return function(): string
				local parts: { string } = {}
				local walk: any = object
				while walk ~= nil and walk ~= environment.root do
					table.insert(parts, 1, tostring(stateOf(walk).values.Name))
					walk = stateOf(walk).parent
				end
				return table.concat(parts, ".")
			end
		elseif key == "IsA" then
			return function(_self: any, className: string): boolean
				return isA(state.className, className)
			end
		elseif key == "IsDescendantOf" then
			return function(_self: any, ancestor: any): boolean
				local walk = state.parent
				while walk ~= nil do
					if walk == ancestor then
						return true
					end
					walk = stateOf(walk).parent
				end
				return false
			end
		elseif key == "IsAncestorOf" then
			return function(_self: any, descendant: any): boolean
				local walk = stateOf(descendant).parent
				while walk ~= nil do
					if walk == object then
						return true
					end
					walk = stateOf(walk).parent
				end
				return false
			end
		elseif key == "SetAttribute" then
			return function(_self: any, name: string, value: any)
				inject "setAttribute"
				validAttribute(name, value)
				if state.attributes[name] == value then
					return
				end
				state.attributes[name] = value
				signalFor(state, "attr:" .. name):Fire()
				signalFor(state, "AttributeChanged"):Fire(name)
			end
		elseif key == "GetAttribute" then
			return function(_self: any, name: string): any
				return state.attributes[name]
			end
		elseif key == "GetAttributes" then
			return function(): { [string]: any }
				return table.clone(state.attributes)
			end
		elseif key == "GetPropertyChangedSignal" then
			return function(_self: any, property: string): Signal
				if state.class.properties[property] == nil and property ~= "Parent" then
					memberError(state, property)
				end
				return signalFor(state, "prop:" .. property)
			end
		elseif key == "GetAttributeChangedSignal" then
			return function(_self: any, name: string): Signal
				return signalFor(state, "attr:" .. name)
			end
		end
		return nil
	end

	local objectMetatable: any = {
		__index = function(object: any, key: string): any
			local state = stateOf(object)
			if key == "ClassName" then
				return state.className
			elseif key == "Parent" then
				return state.parent
			end
			if state.class.events[key] then
				return signalFor(state, key)
			end
			local builtin = universal(object, state, key)
			if builtin ~= nil then
				return builtin
			end
			local method = memberMethod(object, state, key)
			if method ~= nil then
				return method
			end
			if state.class.properties[key] == nil then
				memberError(state, key)
			end
			return state.values[key]
		end,
		__newindex = function(object: any, key: string, value: any)
			local state = stateOf(object)
			if key == "Parent" then
				setParent(object, state, value)
				return
			end
			if state.class.properties[key] == nil then
				memberError(state, key)
			end
			inject "setProperty"
			if state.values[key] == value then
				return
			end
			state.values[key] = value
			changed(object, state, key)
		end,
	}

	function newObject(className: string, props: { [any]: any }?, isRoot: boolean): any
		local class = resolve(className)
		if class == nil then
			error(("Unable to create an Instance of type %q"):format(className), 3)
		end
		if not class.creatable and not isRoot then
			error(("Unable to create an Instance of type %q"):format(className), 3)
		end
		inject "create"
		local values: { [string]: any } = {}
		for key, default in class.properties do
			values[key] = if default == false then nil else default
		end
		values.Name = className
		local object: any = setmetatable({} :: { [string]: any }, objectMetatable)
		rawset(
			object,
			"__state",
			{
				className = className,
				class = class,
				values = values,
				children = {},
				parent = nil,
				attributes = {},
				signals = {},
				destroyed = false,
			} :: State
		)
		if not isRoot then
			alive += 1
		end
		local initial: { [any]: any } = props or {}
		for key, value in initial do
			if type(key) == "string" and key ~= "Parent" then
				object[key] = value
			end
		end
		for index = 1, #initial do
			local child = initial[index]
			if isObject(child) then
				child.Parent = object
			end
		end
		if props ~= nil and props.Parent ~= nil then
			object.Parent = props.Parent
		end
		return object
	end

	if settings.builtins ~= false then
		specs.Animator = {
			super = "Instance",
			methods = {
				LoadAnimation = function(_self: any, animation: any): any
					return newObject("AnimationTrack", { Animation = animation }, false)
				end,
			},
		}
		local track = table.clone(specs.AnimationTrack)
		specs.AnimationTrack = track
		track.methods = {
			Play = function(self: any, _fade: number?, _weight: number?, speed: number?)
				self.IsPlaying = true
				self.TimePosition = 0
				if speed ~= nil then
					self.Speed = speed
				end
			end,
			Stop = function(self: any)
				if not self.IsPlaying then
					return
				end
				self.IsPlaying = false
				self.Stopped:Fire()
				self.Ended:Fire()
			end,
			AdjustSpeed = function(self: any, speed: number)
				self.Speed = speed
			end,
			AdjustWeight = function(self: any, weight: number)
				self.Weight = weight
			end,
		}
		table.clear(resolved)
	end

	local heartbeat = newSignal()
	local root: any = nil
	if specs.Folder ~= nil then
		root = newObject("Folder", nil, true)
	else
		defineClass("Folder", { super = if specs.Instance ~= nil then "Instance" else nil })
		root = newObject("Folder", nil, true)
	end

	environment.root = root
	environment.heartbeat = heartbeat
	environment.scheduler = scheduler
	environment.task = {
		spawn = scheduler.spawn,
		defer = scheduler.defer,
		delay = scheduler.delay,
		wait = scheduler.wait,
		cancel = scheduler.cancel,
	}
	environment.errors = errors
	environment.defineClass = defineClass
	environment.fake = function(member: string, handler: (self: any, ...any) -> ...any)
		fakes[member] = handler
	end
	environment.createInstance = function(className: string, props: { [any]: any }?): any
		return newObject(className, props, false)
	end
	environment.newSignal = newSignal
	environment.step = function(seconds: number)
		scheduler.advance(seconds)
		scheduler.drain(100000)
		heartbeat:Fire(seconds)
	end
	environment.now = scheduler.clock
	environment.childrenOf = function(object: any): { any }
		return table.clone(stateOf(object).children)
	end
	environment.parentOf = function(object: any): any
		return stateOf(object).parent
	end
	environment.propertyOf = function(object: any, key: string): any
		return stateOf(object).values[key]
	end
	environment.attributeOf = function(object: any, name: string): any
		return stateOf(object).attributes[name]
	end
	environment.isAlive = function(object: any): boolean
		return not stateOf(object).destroyed
	end
	environment.liveObjects = function(): number
		return alive
	end
	environment.liveConnections = function(): number
		return connections
	end
	environment.poke = function(object: any, key: string, value: any)
		local state = stateOf(object)
		if state.class.properties[key] == nil then
			memberError(state, key)
		end
		if state.values[key] == value then
			return
		end
		state.values[key] = value
		changed(object, state, key)
	end
	environment.fire = function(object: any, event: string, ...: any)
		local state = stateOf(object)
		if not state.class.events[event] then
			memberError(state, event)
		end
		signalFor(state, event):Fire(...)
	end
	environment.snapshot = function(object: any): any
		local function walk(current: any): any
			local state = stateOf(current)
			local properties: { [string]: any } = {}
			for key, value in state.values do
				if key ~= "Name" then
					properties[key] = value
				end
			end
			local children: { any } = {}
			for _, child in state.children do
				table.insert(children, walk(child))
			end
			return {
				className = state.className,
				name = state.values.Name,
				properties = properties,
				attributes = table.clone(state.attributes),
				children = children,
			}
		end
		return walk(object)
	end
	environment.failNext = function(operation: Operation, times: number?)
		failures[operation] = (failures[operation] or 0) + (times or 1)
	end
	environment.clearFailures = function()
		table.clear(failures)
	end
	return environment :: Environment
end

local function isInstance(value: any): boolean
	return type(value) == "table" and rawget(value, "__state") ~= nil
end

local function typeName(value: any): string
	if isInstance(value) then
		return "Instance"
	end
	return Datatypes.typeName(value) or typeof(value)
end

return {
	create = create,
	isInstance = isInstance,
	typeName = typeName,
	BASIC_CLASSES = BASIC_CLASSES,
}
