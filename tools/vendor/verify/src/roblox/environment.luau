--!strict

local Datatypes = require "./datatypes"
local Scheduler = require "./scheduler"

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<A... = ...unknown> = {
	Connect: (self: Signal<A...>, handler: (A...) -> ()) -> Connection,
	Fire: (self: Signal<A...>, A...) -> (),
	DisconnectAll: (self: Signal<A...>) -> (),
}

export type Method<A... = ...unknown, R... = ...unknown> = (A...) -> R...
export type Instance = {
	[string]: unknown,
	ClassName: string,
	Name: unknown,
	Parent: Instance?,
	Destroy: (Instance) -> (),
	Clone: (Instance) -> Instance?,
	AddTag: (Instance, string) -> (),
	RemoveTag: (Instance, string) -> (),
	HasTag: (Instance, string) -> boolean,
	GetTags: (Instance) -> { string },
	ClearAllChildren: (Instance) -> (),
	GetChildren: (Instance) -> { Instance },
	GetDescendants: (Instance) -> { Instance },
	FindFirstChild: (Instance, string, boolean?) -> Instance?,
	FindFirstChildOfClass: (Instance, string) -> Instance?,
	FindFirstChildWhichIsA: (Instance, string, boolean?) -> Instance?,
	FindFirstAncestorOfClass: (Instance, string) -> Instance?,
	FindFirstAncestorWhichIsA: (Instance, string) -> Instance?,
	FindFirstAncestor: (Instance, string) -> Instance?,
	GetFullName: (Instance) -> string,
	IsA: (Instance, string) -> boolean,
	IsDescendantOf: (Instance, Instance) -> boolean,
	IsAncestorOf: (Instance, Instance) -> boolean,
	SetAttribute: (Instance, string, unknown) -> (),
	GetAttribute: (Instance, string) -> unknown,
	GetAttributes: (Instance) -> { [string]: unknown },
	GetPropertyChangedSignal: (Instance, string) -> Signal<()>,
	GetAttributeChangedSignal: (Instance, string) -> Signal<()>,
	Changed: Signal<string>,
	ChildAdded: Signal<Instance>,
	ChildRemoved: Signal<Instance>,
	DescendantAdded: Signal<Instance>,
	DescendantRemoving: Signal<Instance>,
	AncestryChanged: Signal<Instance, Instance?>,
	Destroying: Signal<()>,
	AttributeChanged: Signal<string>,
}
export type Snapshot = {
	className: string,
	name: unknown,
	properties: { [string]: unknown },
	attributes: { [string]: unknown },
	children: { Snapshot },
}

export type ClassSpec<P = { [string]: unknown }, M = { [string]: unknown }> = {
	super: string?,
	creatable: boolean?,
	properties: P?,
	events: { string }?,
	methods: M?,
}

export type DefineOptions = {
	replace: boolean?,
}

export type Limits = {
	attributeNameLength: number?,
	attributeStringLength: number?,
}

export type Options<P = { [string]: unknown }, M = { [string]: unknown }, F = { [string]: unknown }> = {
	defaultProperty: ((className: string, property: string, fallback: unknown) -> unknown)?,
	validateProperty: ((className: string, property: string, value: unknown, operation: "set" | "poke") -> ())?,
	classes: { [string]: ClassSpec<P, M> }?,
	builtins: boolean?,
	fakes: F?,
	limits: Limits?,
}

export type Operation = "create" | "setProperty" | "setAttribute" | "setParent" | "destroy"

export type Event = {
	operation: Operation,
	subject: string,
	member: string?,
	injected: boolean,
}

export type CloneHook = (source: Instance, copy: Instance, remap: (Instance) -> Instance) -> ()

export type Environment = {
	root: Instance,
	heartbeat: Signal<number>,
	scheduler: Scheduler.Scheduler,
	task: {
		spawn: <A..., R...>(callback: Scheduler.Task<A..., R...>, A...) -> thread,
		defer: <A..., R...>(callback: Scheduler.Task<A..., R...>, A...) -> thread,
		delay: <A..., R...>(seconds: number, callback: Scheduler.Task<A..., R...>, A...) -> thread,
		wait: (seconds: number?) -> number,
		cancel: (thread: thread) -> (),
	},
	errors: { string },
	defineClass: <P, M>(className: string, spec: ClassSpec<P, M>, options: DefineOptions?) -> (),
	fake: <A..., R...>(member: string, handler: (Instance, A...) -> R...) -> (),
	createInstance: (className: string, props: { [unknown]: unknown }?) -> Instance,
	snapshot: (object: Instance) -> Snapshot,
	newSignal: <A...>() -> Signal<A...>,
	step: (seconds: number) -> (),
	now: () -> number,
	childrenOf: (object: Instance) -> { Instance },
	parentOf: (object: Instance) -> Instance?,
	propertyOf: (object: Instance, key: string) -> unknown,
	attributeOf: (object: Instance, name: string) -> unknown,
	isAlive: (object: Instance) -> boolean,
	liveObjects: () -> number,
	liveConnections: () -> number,
	poke: (object: Instance, key: string, value: unknown) -> (),
	fire: (object: Instance, event: string, ...unknown) -> (),
	failNext: (operation: Operation, times: number?) -> (),
	clearFailures: () -> (),
	pendingFailures: () -> number,
	observe: (listener: (event: Event) -> ()) -> Connection,
	onClone: (hook: CloneHook) -> Connection,
}

type Resolved = {
	creatable: boolean,
	properties: { [string]: unknown },
	events: { [string]: true },
	methods: { [string]: unknown },
}

type State = {
	className: string,
	class: Resolved,
	values: { [string]: unknown },
	children: { Instance },
	parent: Instance?,
	attributes: { [string]: unknown },
	tags: { [string]: boolean },
	signals: { [string]: Signal },
	destroyed: boolean,
	destroying: boolean,
	removing: boolean,
}

local ATTRIBUTE_NAME_LIMIT = 100

local UNIVERSAL_EVENTS: { string } = {
	"Changed",
	"ChildAdded",
	"ChildRemoved",
	"Destroying",
	"AttributeChanged",
	"DescendantAdded",
	"DescendantRemoving",
	"AncestryChanged",
}

local BASIC_CLASSES = (
	{
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
			properties = {
				Animation = false,
				IsPlaying = false,
				Speed = 1,
				Weight = 1,
				TimePosition = 0,
				Looped = false,
			},
			events = { "Stopped", "Ended", "DidLoop", "KeyframeReached" },
		},
	} :: unknown
) :: { [string]: ClassSpec }

local function create<P, M, F>(options: Options<P, M, F>?): Environment
	local settings: Options = ((options or {}) :: unknown) :: Options
	local limits: Limits = settings.limits or {}
	local specs: { [string]: ClassSpec } = {}
	local fakes: { [string]: unknown } = {}
	local initialFakes: { [string]: unknown } = settings.fakes or {}
	for member, handler in initialFakes do
		fakes[member] = handler
	end
	local resolved: { [string]: Resolved } = {}
	local failures: { [string]: number } = {}
	local errors: { string } = {}
	local scheduler = Scheduler.create()
	local connections = 0
	local alive = 0

	local environment = {} :: Environment
	local newObject: (className: string, props: { [unknown]: unknown }?, isRoot: boolean) -> Instance

	local function defineClass<P, M>(className: string, spec: ClassSpec<P, M>, defineOptions: DefineOptions?)
		if type(className) ~= "string" or className == "" then
			error("class name must be a non-empty string", 2)
		end
		if specs[className] ~= nil and not (defineOptions ~= nil and defineOptions.replace == true) then
			error(("class %q is already defined"):format(className), 2)
		end
		specs[className] = (spec :: unknown) :: ClassSpec
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
			properties = if parent ~= nil then table.clone(parent.properties) else { Name = false, Archivable = true },
			events = if parent ~= nil then table.clone(parent.events) else {},
			methods = if parent ~= nil then table.clone(parent.methods) else {},
		}
		if parent == nil then
			for _, event in UNIVERSAL_EVENTS do
				result.events[event] = true
			end
		end
		local declared: { [string]: unknown } = spec.properties or {}
		for key, default in declared do
			result.properties[key] = default
		end
		local declaredEvents: { string } = spec.events or {}
		for _, event in declaredEvents do
			result.events[event] = true
		end
		local declaredMethods: { [string]: unknown } = spec.methods or {}
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

	local observers: { { listener: (event: Event) -> (), connected: boolean } } = {}
	local cloneHooks: { { hook: CloneHook, connected: boolean } } = {}

	local function inject(operation: Operation, subject: string, member: string?)
		local remaining = failures[operation]
		local failing = remaining ~= nil and remaining > 0
		for _, observer in table.clone(observers) do
			if observer.connected then
				observer.listener { operation = operation, subject = subject, member = member, injected = failing }
			end
		end
		if failing then
			failures[operation] = (remaining :: number) - 1
			error(("environment: injected failure in %s"):format(operation), 0)
		end
	end

	local function newSignal<A...>(): Signal<A...>
		local live: { { handler: (A...) -> (), connected: boolean, connection: Connection } } = {}
		local signal = {} :: Signal<A...>
		function signal:Connect(handler: (A...) -> ()): Connection
			local connection = { Connected = true } :: Connection
			local record = { handler = handler, connected = true, connection = connection }
			table.insert(live, record)
			connections += 1
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
		function signal:Fire(...: A...)
			for _, record in table.clone(live) do
				if record.connected then
					local ok, thrown: unknown = pcall(record.handler, ...)
					if not ok then
						table.insert(errors, tostring(thrown))
					end
				end
			end
		end
		function signal:DisconnectAll()
			for _, record in table.clone(live) do
				record.connection:Disconnect()
			end
			table.clear(live)
		end
		return signal :: Signal<A...>
	end

	local function stateOf(object: Instance): State
		return rawget((object :: unknown) :: { [string]: unknown }, "__state") :: State
	end

	local function isObject(value: unknown): boolean
		return type(value) == "table" and rawget(value :: { [string]: unknown }, "__state") ~= nil
	end

	local function signalFor(state: State, key: string): Signal
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

	local function changed(object: Instance, state: State, property: string)
		signalFor(state, "prop:" .. property):Fire()
		signalFor(state, "Changed"):Fire(property)
	end

	local function subtree(object: Instance): { Instance }
		local objects: { Instance } = {}
		local function visit(current: Instance)
			table.insert(objects, current)
			for _, child in stateOf(current).children do
				visit(child)
			end
		end
		visit(object)
		return objects
	end

	local function ancestors(parent: Instance?): { Instance }
		local objects: { Instance } = {}
		local walk = parent
		while walk ~= nil do
			table.insert(objects, walk)
			walk = stateOf(walk).parent
		end
		return objects
	end

	local function move(object: Instance, state: State, parent: Instance?)
		local previous = state.parent
		if previous == parent then
			return
		end
		local objects = subtree(object)
		local before = ancestors(previous)
		local after = ancestors(parent)
		for _, descendant in objects do
			stateOf(descendant).removing = true
		end
		for _, descendant in objects do
			for _, ancestor in before do
				if table.find(after, ancestor) == nil then
					signalFor(stateOf(ancestor), "DescendantRemoving"):Fire(descendant)
				end
			end
		end
		if previous ~= nil then
			local siblings = stateOf(previous).children
			local index = table.find(siblings, object)
			if index ~= nil then
				table.remove(siblings, index)
			end
		end
		state.parent = parent
		if parent ~= nil then
			table.insert(stateOf(parent).children, object)
		end
		for _, descendant in objects do
			stateOf(descendant).removing = false
		end
		if previous ~= nil then
			signalFor(stateOf(previous), "ChildRemoved"):Fire(object)
		end
		if parent ~= nil then
			signalFor(stateOf(parent), "ChildAdded"):Fire(object)
		end
		for _, descendant in objects do
			for _, ancestor in after do
				if table.find(before, ancestor) == nil then
					signalFor(stateOf(ancestor), "DescendantAdded"):Fire(descendant)
				end
			end
		end
		changed(object, state, "Parent")
		for _, descendant in objects do
			signalFor(stateOf(descendant), "AncestryChanged"):Fire(object, parent)
		end
	end

	local function setParent(object: Instance, state: State, parent: Instance?)
		inject("setParent", describe(state))
		if state.destroyed or state.destroying or state.removing then
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
		if settings.validateProperty ~= nil then
			settings.validateProperty(state.className, "Parent", parent, "set")
		end
		move(object, state, parent)
	end

	local function destroy(object: Instance, state: State)
		if state.destroyed or state.destroying then
			return
		end
		if state.removing then
			error(("The Parent property of %s is locked"):format(describe(state)), 4)
		end
		inject("destroy", describe(state))
		state.destroying = true
		signalFor(state, "Destroying"):Fire()
		move(object, state, nil)
		for _, child in table.clone(state.children) do
			destroy(child, stateOf(child))
		end
		state.destroyed = true
		alive -= 1
		for _, signal in state.signals do
			signal:DisconnectAll()
		end
	end

	local function validAttribute(name: unknown, value: unknown)
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
		if
			type(value) == "string"
			and limits.attributeStringLength ~= nil
			and #value > limits.attributeStringLength
		then
			error(("attribute %q string is longer than %d characters"):format(name, limits.attributeStringLength), 4)
		end
	end

	local function memberMethod(object: Instance, state: State, key: string): unknown
		local method = state.class.methods[key]
		if method == nil then
			return nil
		end
		local implementation: unknown = if method == true then fakes[state.className .. "." .. key] else method
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
		return function(_self: Instance, ...: unknown): ...unknown
			return (implementation :: Method)(object, ...)
		end
	end

	local function universal(object: Instance, state: State, key: string): unknown
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
				local out: { Instance } = {}
				local function walk(parent: Instance)
					for _, child in stateOf(parent).children do
						table.insert(out, child)
						walk(child)
					end
				end
				walk(object)
				return out
			end
		elseif key == "FindFirstChild" then
			return function(_self: Instance, name: string, recursive: boolean?): unknown
				local function search(parent: Instance): Instance?
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
			return function(_self: Instance, className: string, recursive: boolean?): Instance?
				local function search(parent: Instance): Instance?
					for _, child in stateOf(parent).children do
						local childClass = stateOf(child).className
						if
							childClass == className or (key == "FindFirstChildWhichIsA" and isA(childClass, className))
						then
							return child
						end
					end
					if key == "FindFirstChildWhichIsA" and recursive == true then
						for _, child in stateOf(parent).children do
							local found = search(child)
							if found then
								return found
							end
						end
					end
					return nil
				end
				return search(object)
			end
		elseif
			key == "FindFirstAncestor"
			or key == "FindFirstAncestorOfClass"
			or key == "FindFirstAncestorWhichIsA"
		then
			return function(_self: Instance, name: string): Instance?
				local walk = state.parent
				while walk ~= nil do
					local candidate = stateOf(walk)
					if
						(key == "FindFirstAncestor" and candidate.values.Name == name)
						or (key == "FindFirstAncestorOfClass" and candidate.className == name)
						or (key == "FindFirstAncestorWhichIsA" and isA(candidate.className, name))
					then
						return walk
					end
					walk = candidate.parent
				end
				return nil
			end
		elseif key == "Clone" then
			return function(): Instance?
				if state.values.Archivable == false then
					return nil
				end
				local copies: { [Instance]: Instance } = {}
				local function copyTree(original: Instance): Instance
					local source = stateOf(original)
					local copy = newObject(source.className, nil, false)
					copies[original] = copy
					for _, child in source.children do
						if stateOf(child).values.Archivable ~= false then
							local childCopy = copyTree(child)
							move(childCopy, stateOf(childCopy), copy)
						end
					end
					return copy
				end
				local ok, result = pcall(function(): Instance
					local rootCopy = copyTree(object)
					for original, copy in copies do
						local source, target = stateOf(original), stateOf(copy)
						for property, value in source.values do
							target.values[property] = if isObject(value)
								then copies[value :: Instance] or value
								else value
						end
						target.attributes = table.clone(source.attributes)
						target.tags = table.clone(source.tags)
					end
					local function remap(value: Instance): Instance
						return copies[value] or value
					end
					for original, copy in copies do
						for _, entry in table.clone(cloneHooks) do
							if entry.connected then
								entry.hook(original, copy, remap)
							end
						end
					end
					return rootCopy
				end)
				if not ok then
					for _, copy in copies do
						destroy(copy, stateOf(copy))
					end
					error(result, 0)
				end
				return result
			end
		elseif key == "AddTag" or key == "RemoveTag" or key == "HasTag" then
			return function(_self: Instance, tag: string): boolean?
				assert(type(tag) == "string", "tag must be a string")
				if key == "HasTag" then
					return state.tags[tag] == true
				end
				if key == "AddTag" then
					state.tags[tag] = true
				else
					state.tags[tag] = nil
				end
				return nil
			end
		elseif key == "GetTags" then
			return function(): { string }
				local tags: { string } = {}
				for tag in state.tags do
					table.insert(tags, tag)
				end
				table.sort(tags)
				return tags
			end
		elseif key == "GetFullName" then
			return function(): string
				local parts: { string } = {}
				local walk: Instance? = object
				while walk ~= nil and walk ~= environment.root do
					table.insert(parts, 1, tostring(stateOf(walk).values.Name))
					walk = stateOf(walk).parent
				end
				return table.concat(parts, ".")
			end
		elseif key == "IsA" then
			return function(_self: Instance, className: string): boolean
				return isA(state.className, className)
			end
		elseif key == "IsDescendantOf" then
			return function(_self: Instance, ancestor: unknown): boolean
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
			return function(_self: Instance, descendant: unknown): boolean
				local walk = stateOf(descendant :: Instance).parent
				while walk ~= nil do
					if walk == object then
						return true
					end
					walk = stateOf(walk).parent
				end
				return false
			end
		elseif key == "SetAttribute" then
			return function(_self: Instance, name: string, value: unknown)
				inject("setAttribute", describe(state), name)
				validAttribute(name, value)
				if state.attributes[name] == value then
					return
				end
				state.attributes[name] = value
				signalFor(state, "attr:" .. name):Fire()
				signalFor(state, "AttributeChanged"):Fire(name)
			end
		elseif key == "GetAttribute" then
			return function(_self: Instance, name: string): unknown
				return state.attributes[name]
			end
		elseif key == "GetAttributes" then
			return function(): { [string]: unknown }
				return table.clone(state.attributes)
			end
		elseif key == "GetPropertyChangedSignal" then
			return function(_self: Instance, property: string): Signal
				if state.class.properties[property] == nil and property ~= "Parent" then
					memberError(state, property)
				end
				return signalFor(state, "prop:" .. property)
			end
		elseif key == "GetAttributeChangedSignal" then
			return function(_self: Instance, name: string): Signal
				return signalFor(state, "attr:" .. name)
			end
		end
		return nil
	end

	local objectMetatable = {
		__index = function(object: Instance, key: string): unknown
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
			if state.class.properties[key] ~= nil then
				return state.values[key]
			end
			for _, child in state.children do
				if stateOf(child).values.Name == key then
					return child
				end
			end
			memberError(state, key)
			return nil
		end,
		__newindex = function(object: Instance, key: string, value: unknown)
			local state = stateOf(object)
			if key == "Parent" then
				setParent(object, state, value :: Instance?)
				return
			end
			if state.class.properties[key] == nil then
				memberError(state, key)
			end
			inject("setProperty", describe(state), key)
			if settings.validateProperty ~= nil then
				settings.validateProperty(state.className, key, value, "set")
			end
			if state.values[key] == value then
				return
			end
			state.values[key] = value
			changed(object, state, key)
		end,
	}

	function newObject(className: string, props: { [unknown]: unknown }?, isRoot: boolean): Instance
		local class = resolve(className)
		if class == nil then
			error(("Unable to create an Instance of type %q"):format(className), 3)
		end
		if not class.creatable and not isRoot then
			error(("Unable to create an Instance of type %q"):format(className), 3)
		end
		inject("create", className)
		local values: { [string]: unknown } = {}
		for key, default in class.properties do
			local fallback = if key == "Name" then className elseif default == false then nil else default
			values[key] = if settings.defaultProperty ~= nil
				then settings.defaultProperty(className, key, fallback)
				else fallback
		end
		local object = (setmetatable({} :: { [string]: unknown }, objectMetatable) :: unknown) :: Instance
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
				tags = {},
				signals = {},
				destroyed = false,
				destroying = false,
				removing = false,
			} :: State
		)
		if not isRoot then
			alive += 1
		end
		local initial: { [unknown]: unknown } = props or {}
		for key, value in initial do
			if type(key) == "string" and key ~= "Parent" then
				object[key] = value
			end
		end
		for index = 1, #initial do
			local child = initial[index]
			if isObject(child) then
				((child :: unknown) :: Instance).Parent = object
			end
		end
		if props ~= nil and props.Parent ~= nil then
			object.Parent = props.Parent :: Instance
		end
		return object
	end

	if settings.builtins ~= false then
		specs.Animator = (
			{
				super = "Instance",
				methods = {
					LoadAnimation = function(_self: Instance, animation: unknown): unknown
						return newObject("AnimationTrack", { Animation = animation }, false)
					end,
				},
			} :: unknown
		) :: ClassSpec
		local track = table.clone(specs.AnimationTrack)
		specs.AnimationTrack = track
		track.methods = (
			{
				Play = function(self: Instance, _fade: number?, _weight: number?, speed: number?)
					self.IsPlaying = true
					self.TimePosition = 0
					if speed ~= nil then
						self.Speed = speed
					end
				end,
				Stop = function(self: Instance)
					if not self.IsPlaying then
						return
					end
					self.IsPlaying = false
					local stopped = self.Stopped :: Signal<()>
					local ended = self.Ended :: Signal<()>
					stopped:Fire()
					ended:Fire()
				end,
				AdjustSpeed = function(self: Instance, speed: number)
					self.Speed = speed
				end,
				AdjustWeight = function(self: Instance, weight: number)
					self.Weight = weight
				end,
			} :: unknown
		) :: { [string]: unknown }
		table.clear(resolved)
	end

	local heartbeat: Signal<number> = newSignal()
	local root: Instance
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
	environment.fake = function<A..., R...>(member: string, handler: (Instance, A...) -> R...)
		fakes[member] = handler
	end
	environment.createInstance = function(className: string, props: { [unknown]: unknown }?): Instance
		return newObject(className, props, false)
	end
	environment.newSignal = newSignal
	environment.step = function(seconds: number)
		scheduler.advance(seconds)
		scheduler.drain(100000)
		heartbeat:Fire(seconds)
	end
	environment.now = scheduler.clock
	environment.childrenOf = function(object: Instance): { Instance }
		return table.clone(stateOf(object).children)
	end
	environment.parentOf = function(object: Instance): Instance?
		return stateOf(object).parent
	end
	environment.propertyOf = function(object: Instance, key: string): unknown
		return stateOf(object).values[key]
	end
	environment.attributeOf = function(object: Instance, name: string): unknown
		return stateOf(object).attributes[name]
	end
	environment.isAlive = function(object: Instance): boolean
		return not stateOf(object).destroyed
	end
	environment.liveObjects = function(): number
		return alive
	end
	environment.liveConnections = function(): number
		return connections
	end
	environment.poke = function(object: Instance, key: string, value: unknown)
		local state = stateOf(object)
		if state.class.properties[key] == nil then
			memberError(state, key)
		end
		if settings.validateProperty ~= nil then
			settings.validateProperty(state.className, key, value, "poke")
		end
		if state.values[key] == value then
			return
		end
		state.values[key] = value
		changed(object, state, key)
	end
	environment.fire = function(object: Instance, event: string, ...: unknown)
		local state = stateOf(object)
		if not state.class.events[event] then
			memberError(state, event)
		end
		signalFor(state, event):Fire(...)
	end
	environment.snapshot = function(object: Instance): Snapshot
		local function walk(current: Instance): Snapshot
			local state = stateOf(current)
			local properties: { [string]: unknown } = {}
			for key, value in state.values do
				if key ~= "Name" then
					properties[key] = value
				end
			end
			local children: { Snapshot } = {}
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
	environment.pendingFailures = function(): number
		local total = 0
		for _, remaining in failures do
			total += remaining
		end
		return total
	end
	environment.observe = function(listener: (event: Event) -> ()): Connection
		local entry = { listener = listener, connected = true }
		table.insert(observers, entry)
		local connection = { Connected = true } :: Connection
		function connection:Disconnect()
			entry.connected = false
			connection.Connected = false
			local index = table.find(observers, entry)
			if index ~= nil then
				table.remove(observers, index)
			end
		end
		return connection
	end
	environment.onClone = function(hook: CloneHook): Connection
		local entry = { hook = hook, connected = true }
		table.insert(cloneHooks, entry)
		local connection = { Connected = true } :: Connection
		function connection:Disconnect()
			entry.connected = false
			connection.Connected = false
			local index = table.find(cloneHooks, entry)
			if index ~= nil then
				table.remove(cloneHooks, index)
			end
		end
		return connection
	end
	return environment :: Environment
end

local function isInstance(value: unknown): boolean
	return type(value) == "table" and rawget(value :: { [string]: unknown }, "__state") ~= nil
end

local function typeName(value: unknown): string
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
