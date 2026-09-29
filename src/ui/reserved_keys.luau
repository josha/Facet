--!strict
local Shared = require("./types")

type Handler = Shared.ReservedKeyHandler
type Dispatcher = {
	handlers: { Handler },
	order: { [Handler]: number },
	count: number,
	began: RBXScriptConnection?,
	ending: { [string]: RBXScriptConnection },
	keyCodes: { [string]: Enum.KeyCode },
}

local KEYS = table.freeze({ Tab = true, Escape = true })
local MODIFIERS = table.freeze({
	"LeftControl",
	"RightControl",
	"LeftAlt",
	"RightAlt",
	"LeftMeta",
	"RightMeta",
	"LeftSuper",
	"RightSuper",
})

local dispatchers: { [UserInputService]: Dispatcher } = setmetatable({}, { __mode = "k" }) :: any

local function holds(handler: Handler, selected: Instance?): boolean
	local node = handler.node
	return node ~= nil and selected ~= nil and (selected == node or selected:IsDescendantOf(node))
end

local function dispatch(input: UserInputService, dispatcher: Dispatcher, event: InputObject): ()
	local name = if event.KeyCode then event.KeyCode.Name else nil
	if name == nil or not KEYS[name] then
		return
	end
	local probe = (input :: unknown) :: {
		GetFocusedTextBox: ((UserInputService) -> TextBox?)?,
		IsKeyDown: ((UserInputService, Enum.KeyCode) -> boolean)?,
	}
	if not dispatcher.ending[name] then
		local code = event.KeyCode
		local connection: RBXScriptConnection
		connection = input.InputEnded:Connect(function(ended: InputObject)
			if ended.KeyCode == code then
				connection:Disconnect()
				dispatcher.ending[name] = nil
				for _, handler in table.clone(dispatcher.handlers) do
					if handler.keys[name] then
						handler.release()
					end
				end
			end
		end)
		dispatcher.ending[name] = connection
	end
	if probe.IsKeyDown then
		for _, modifier in MODIFIERS do
			local key = dispatcher.keyCodes[modifier]
			if key and input:IsKeyDown(key) then
				return
			end
		end
	end
	local box = if probe.GetFocusedTextBox then input:GetFocusedTextBox() else nil
	local ordered = table.clone(dispatcher.handlers)
	local selected: { [Handler]: boolean } = {}
	for _, handler in ordered do
		local gui = handler.gui
		selected[handler] = holds(handler, if gui then gui.SelectedObject else nil)
	end
	table.sort(ordered, function(a: Handler, b: Handler): boolean
		if a.priority ~= b.priority then
			return a.priority > b.priority
		end
		if selected[a] ~= selected[b] then
			return selected[a]
		end
		return dispatcher.order[a] > dispatcher.order[b]
	end)
	for _, handler in ordered do
		local gui = handler.gui
		local menuOpen = name == "Escape" and gui ~= nil and (gui :: any).MenuIsOpen == true
		local typing = box ~= nil and not (handler.editing ~= nil and handler.editing(box))
		if handler.keys[name] and not menuOpen and not typing and handler.enabled() then
			handler.press()
			if handler.sink then
				return
			end
		end
	end
end

local function add(input: UserInputService, keyCodes: { [string]: Enum.KeyCode }, handler: Handler): () -> ()
	local dispatcher = dispatchers[input]
	if dispatcher == nil then
		local created: Dispatcher =
			{ handlers = {}, order = {}, count = 0, began = nil, ending = {}, keyCodes = keyCodes }
		dispatcher = created
		dispatchers[input] = created
	end
	local current = dispatcher :: Dispatcher
	current.count += 1
	current.order[handler] = current.count
	table.insert(current.handlers, handler)
	if current.began == nil then
		current.began = input.InputBegan:Connect(function(event: InputObject)
			dispatch(input, current, event)
		end)
	end
	return function()
		local index = table.find(current.handlers, handler)
		if index then
			table.remove(current.handlers, index)
		end
		current.order[handler] = nil
		if #current.handlers == 0 then
			if current.began then
				current.began:Disconnect()
				current.began = nil
			end
			for _, connection in current.ending do
				connection:Disconnect()
			end
			table.clear(current.ending)
		end
	end
end

return table.freeze({ KEYS = KEYS, add = add })
