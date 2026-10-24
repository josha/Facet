--!strict

local fs = require("@std/fs")
local task = require("@std/task")

local Audit = require("../../../tools/vendor/verify/src/roblox/ui-audit")
local Capture = require("./capture")
local Devices = require("./devices")
local Lute = require("../../../tools/vendor/verify/src/lute")

export type Rect = { x: number, y: number, width: number, height: number }

export type Query = {
	text: string?,
	pattern: string?,
	exact: string?,
	role: string?,
	near: string?,
	index: number?,
	clipped: boolean?,
}

export type Info = {
	path: string,
	class: string,
	label: string,
	rect: Rect,
	selectable: boolean,
	interactable: boolean,
	button: boolean,
	score: number?,
}

export type Route = { found: boolean, path: { string }?, reason: string?, visited: number, target: string? }

export type Shot = {
	device: string,
	screen: string,
	path: string?,
	width: number,
	height: number,
	blank: boolean,
	attempts: number,
	detail: string?,
}

export type Context = {
	session: Lute.StudioSession,
	probe: string,
	outputs: string,
	captures: string,
	scratch: string,
	shots: { Shot },
	log: (string) -> (),
}

export type QA = {
	mountProblem: string?,
	device: Devices.Device,
	viewport: { width: number, height: number },
	call: (self: QA, command: string, fields: unknown?) -> unknown,
	admin: (self: QA, command: string, args: unknown?) -> unknown,
	find: (self: QA, query: Query, limit: number?) -> { Info },
	first: (self: QA, query: Query) -> Info?,
	waitFor: (self: QA, query: Query, seconds: number?) -> Info?,
	waitGone: (self: QA, query: Query, seconds: number?) -> boolean,
	texts: (self: QA) -> { string },
	hasText: (self: QA, pattern: string) -> string?,
	waitText: (self: QA, pattern: string, seconds: number?) -> string?,
	reveal: (self: QA, query: Query) -> boolean,
	reachable: (self: QA, query: Query) -> (boolean, string),
	tap: (self: QA, query: Query) -> (boolean, string),
	tapVisible: (self: QA, query: Query) -> (boolean, string, Info?),
	press: (self: QA, key: string) -> (boolean, string),
	typeText: (self: QA, query: Query, text: string, submit: boolean?) -> (boolean, string),
	slide: (self: QA, near: string, fraction: number) -> (boolean, string),
	selected: (self: QA) -> Info?,
	autoSelect: (self: QA) -> Info?,
	navigate: (self: QA, direction: string) -> Info?,
	activate: (self: QA) -> (),
	route: (self: QA, query: Query) -> Route,
	gamepadSelect: (self: QA, query: Query) -> (boolean, string),
	gamepadActivate: (self: QA, query: Query) -> (boolean, string),
	capture: (self: QA, screen: string) -> (),
	dump: (self: QA, screen: string) -> (),
	sleep: (self: QA, seconds: number) -> (),
	log: (self: QA, line: string) -> (),
}

local function record(value: unknown): { [string]: unknown }
	if type(value) == "table" then
		return value :: { [string]: unknown }
	end
	return {}
end

local function decode(text: string?): { [string]: unknown }
	if text == nil then
		error("the engine returned no text", 0)
	end
	local parsed, value: unknown = pcall(Lute.parse, text :: string)
	if not parsed or type(value) ~= "table" then
		error("the engine returned no JSON object: " .. string.sub(text :: string, 1, 300), 0)
	end
	return value :: { [string]: unknown }
end

local function infoOf(value: unknown): Info?
	if type(value) ~= "table" then
		return nil
	end
	local raw = value :: { [string]: unknown }
	local rect = record(raw.rect)
	return {
		path = tostring(raw.path),
		class = tostring(raw.class),
		label = tostring(raw.label),
		rect = {
			x = tonumber(rect.x) or 0,
			y = tonumber(rect.y) or 0,
			width = tonumber(rect.width) or 0,
			height = tonumber(rect.height) or 0,
		},
		selectable = raw.selectable == true,
		interactable = raw.interactable ~= false,
		button = raw.button == true,
		score = tonumber(raw.score),
	}
end

local function describe(query: Query): string
	return Lute.encode(query)
end

local function readDump(value: unknown, call: (string, unknown) -> unknown): string
	if type(value) == "string" then
		return value
	end
	local meta = record(value)
	local token = tostring(meta.token)
	local count = tonumber(meta.count) or 0
	assert(count >= 1, "the dump has no chunks")
	local pieces: { string } = {}
	if type(meta.first) == "string" then
		table.insert(pieces, meta.first)
	end
	local ok, problem = pcall(function()
		for index = #pieces + 1, count do
			local piece = call("chunk", { token = token, index = index })
			assert(type(piece) == "string", "a dump chunk is not text")
			table.insert(pieces, piece)
		end
	end)
	if meta.automatic ~= true or not ok then
		pcall(call, "release", { token = token })
	end
	assert(ok, tostring(problem))
	local text = table.concat(pieces)
	assert(meta.bytes == nil or #text == meta.bytes, "dump byte count differs")
	return text
end

local function create(context: Context, device: Devices.Device): QA
	local session = context.session
	local qa = {} :: QA
	qa.device = device
	qa.viewport = { width = 0, height = 0 }

	local function execute(datamodel: string, code: string): { [string]: unknown }
		local response = session.execute(datamodel, code)
		if not response.ok then
			error(
				("harness error: Studio %s call failed: %s (%s)"):format(
					datamodel,
					tostring(response.detail),
					response.delivery
				),
				0
			)
		end
		return decode(response.text)
	end

	function qa.call(_self: QA, command: string, fields: unknown?): unknown
		local request: { [string]: unknown } = {}
		for key, value in record(fields) do
			request[key] = value
		end
		request.command = command
		local code = ("return require(%s).call(%q)"):format(context.probe, Lute.encode(request))
		local reply = execute("Client", code)
		if reply.ok ~= true then
			error(("probe %s failed: %s"):format(command, tostring(reply.error)), 0)
		end
		if reply.raw ~= nil then
			return reply.raw
		end
		return reply.value
	end

	function qa.admin(_self: QA, command: string, args: unknown?): unknown
		local code = table.concat({
			"local HttpService = game:GetService('HttpService')",
			"local hook = game:GetService('ServerStorage'):WaitForChild('AdminCommands', 10)",
			"if hook == nil then return HttpService:JSONEncode({ ok = false, error = 'the game has no AdminCommands hook' }) end",
			("local ok, result = pcall(function() return hook:Invoke(%q, HttpService:JSONDecode(%q)) end)"):format(
				command,
				Lute.encode(if args ~= nil then args else {})
			),
			"if not ok then return HttpService:JSONEncode({ ok = false, error = tostring(result) }) end",
			"return HttpService:JSONEncode({ ok = true, value = result })",
		}, "\n")
		local reply = execute("Server", code)
		if reply.ok ~= true then
			error(("admin %s failed: %s"):format(command, tostring(reply.error)), 0)
		end
		return reply.value
	end

	function qa.find(self: QA, query: Query, limit: number?): { Info }
		local value = self:call("find", { query = query, limit = limit or 8 })
		local found: { Info } = {}
		if type(value) == "table" then
			for _, item in value :: { unknown } do
				local info = infoOf(item)
				if info ~= nil then
					table.insert(found, info)
				end
			end
		end
		return found
	end

	function qa.first(self: QA, query: Query): Info?
		return self:find(query, 1)[1]
	end

	function qa.waitFor(self: QA, query: Query, seconds: number?): Info?
		local deadline = os.clock() + (seconds or 5)
		repeat
			local found = self:first(query)
			if found ~= nil then
				return found
			end
			task.wait(0.25)
		until os.clock() >= deadline
		return nil
	end

	function qa.waitGone(self: QA, query: Query, seconds: number?): boolean
		local deadline = os.clock() + (seconds or 5)
		repeat
			if self:first(query) == nil then
				return true
			end
			task.wait(0.25)
		until os.clock() >= deadline
		return false
	end

	function qa.texts(self: QA): { string }
		local value = self:call("texts")
		local found: { string } = {}
		if type(value) == "table" then
			for _, item in value :: { unknown } do
				local text = record(item).text
				if type(text) == "string" then
					table.insert(found, text)
				end
			end
		end
		return found
	end

	function qa.hasText(self: QA, pattern: string): string?
		for _, text in self:texts() do
			local normal = string.lower((string.gsub(text, "%s+", " ")))
			if string.find(normal, pattern) ~= nil then
				return text
			end
		end
		return nil
	end

	function qa.waitText(self: QA, pattern: string, seconds: number?): string?
		local deadline = os.clock() + (seconds or 5)
		repeat
			local found = self:hasText(pattern)
			if found ~= nil then
				return found
			end
			task.wait(0.25)
		until os.clock() >= deadline
		return nil
	end

	function qa.reveal(self: QA, query: Query): boolean
		return record(self:call("reveal", { query = query, mode = self.device.mode })).revealed == true
	end

	function qa.reachable(self: QA, query: Query): (boolean, string)
		local value = record(self:call("reachable", { query = query }))
		return value.reachable == true, tostring(value.reason or "the target is not occluded")
	end

	function qa.tap(self: QA, query: Query): (boolean, string)
		if self.device.mode == "gamepad" then
			return self:gamepadActivate(query)
		end
		if not self:reveal(query) then
			return false, ("the matched control could not be revealed: %s"):format(describe(query))
		end
		local value = record(self:call("tap", { query = query }))
		if value.tapped ~= true then
			return false,
				("no visible control matches %s%s"):format(
					describe(query),
					if value.reason ~= nil then " (" .. tostring(value.reason) .. ")" else ""
				)
		end
		local info = infoOf(value.info)
		if value.activated == false then
			return false,
				("%q did not respond to %s tap(s)"):format(
					if info ~= nil then info.label else describe(query),
					tostring(value.attempts)
				)
		end
		return true, if info ~= nil then info.label else ""
	end

	function qa.tapVisible(self: QA, query: Query): (boolean, string, Info?)
		if self.device.mode == "gamepad" then
			return false, "visible-hit taps require mouse or touch input", nil
		end
		local reachable, detail = self:reachable(query)
		if not reachable then
			return false, detail, nil
		end
		local value = record(self:call("tap", { query = query }))
		local info = infoOf(value.info)
		if value.tapped ~= true or value.activated ~= true or info == nil then
			return false, tostring(value.reason or "the visible target did not activate"), info
		end
		return true, info.label, info
	end

	function qa.press(self: QA, key: string): (boolean, string)
		local value = record(self:call("key", { key = key }))
		return value.pressed == true, tostring(value.reason or "")
	end

	function qa.typeText(self: QA, query: Query, text: string, submit: boolean?): (boolean, string)
		if self.device.mode == "gamepad" then
			local selected, detail = self:gamepadSelect(query)
			if not selected then
				return false, detail
			end
		else
			self:reveal(query)
		end
		local value = record(self:call("type", {
			query = query,
			text = text,
			submit = submit == true,
			mode = self.device.mode,
		}))
		if value.typed ~= true then
			return false, tostring(value.reason)
		end
		return true, ""
	end

	function qa.slide(self: QA, near: string, fraction: number): (boolean, string)
		local value = record(self:call("slide", { near = near, to = fraction }))
		if value.slid == true then
			return true, ""
		end
		return false, tostring(value.reason)
	end

	function qa.selected(self: QA): Info?
		return infoOf(record(self:call("selected")).selected)
	end

	function qa.autoSelect(self: QA): Info?
		return infoOf(record(self:call("autoselect")).selected)
	end

	function qa.navigate(self: QA, direction: string): Info?
		return infoOf(record(self:call("navigate", { direction = direction })).selected)
	end

	function qa.activate(self: QA)
		self:call("activate")
	end

	function qa.route(self: QA, query: Query): Route
		local raw = record(self:call("path", { query = query }))
		local steps: { string }? = nil
		if type(raw.path) == "table" then
			local list: { string } = {}
			for _, item in raw.path :: { unknown } do
				table.insert(list, tostring(item))
			end
			steps = list
		end
		return {
			found = raw.found == true,
			path = steps,
			reason = if raw.reason ~= nil then tostring(raw.reason) else nil,
			visited = tonumber(raw.visited) or 0,
			target = if raw.target ~= nil then tostring(raw.target) else nil,
		}
	end

	function qa.gamepadSelect(self: QA, query: Query): (boolean, string)
		local problem = "no attempt"
		for _ = 1, 4 do
			local start = self:selected() or self:autoSelect()
			if start == nil then
				return false, "nothing on the screen can be selected with a gamepad"
			end
			if record(self:call("matches", { query = query })).matches == true then
				return true, start.label
			end
			local route = self:route(query)
			if not route.found or route.path == nil then
				return false,
					("gamepad navigation from %q cannot reach %s: %s"):format(
						start.label,
						describe(query),
						tostring(route.reason)
					)
			end
			for _, direction in route.path :: { string } do
				self:navigate(direction)
			end
			if record(self:call("matches", { query = query })).matches == true then
				local now = self:selected()
				return true, if now ~= nil then now.label else ""
			end
			local now = self:selected()
			problem = ("the replayed path stopped on %q"):format(if now ~= nil then now.label else "nothing")
		end
		return false, "gamepad navigation did not settle on the target: " .. problem
	end

	function qa.gamepadActivate(self: QA, query: Query): (boolean, string)
		local selected, detail = self:gamepadSelect(query)
		if not selected then
			return false, detail
		end
		self:activate()
		return true, detail
	end

	function qa.capture(self: QA, screen: string)
		local directory = context.captures .. "/" .. self.device.id
		fs.createDirectory(directory, { makeParents = true })
		local target = directory .. "/" .. screen .. ".png"
		if fs.exists(target) then
			fs.remove(target)
		end
		local shot: Shot = {
			device = self.device.id,
			screen = screen,
			path = nil,
			width = 0,
			height = 0,
			blank = false,
			attempts = 0,
			detail = nil,
		}
		fs.createDirectory(context.scratch, { makeParents = true })
		for attempt = 1, 3 do
			shot.attempts = attempt
			local stem = ("%s-%s-%d"):format(self.device.id, screen, attempt)
			local response = session.capture({ directory = context.scratch, stem = stem })
			local artifact = response.artifact
			if not response.ok or artifact == nil then
				shot.detail = "the capture failed: " .. tostring(response.detail)
			else
				local inspection, problem = Capture.convert(artifact.reference, target)
				if inspection == nil then
					shot.detail = problem
				else
					shot.width = inspection.width
					shot.height = inspection.height
					shot.blank = inspection.blank
					shot.detail = inspection.reason
					if not inspection.blank then
						shot.path = target
						break
					end
				end
			end
			task.wait(1)
		end
		if shot.path == nil then
			context.log(("qa: capture %s/%s was not kept: %s"):format(self.device.id, screen, tostring(shot.detail)))
		end
		table.insert(context.shots, shot)
	end

	function qa.dump(self: QA, screen: string)
		local text = readDump(
			self:call("dump", { device = self.device.id, input = self.device.input, inline = true }),
			function(command, fields)
				return self:call(command, fields)
			end
		)
		Audit.decode(Lute.parse(text))
		local directory = context.outputs .. "/dumps/" .. self.device.id
		fs.createDirectory(directory, { makeParents = true })
		fs.writeStringToFile(directory .. "/" .. screen .. ".json", text)
	end

	function qa.sleep(_self: QA, seconds: number)
		task.wait(seconds)
	end

	function qa.log(_self: QA, line: string)
		context.log(line)
	end

	return qa
end

local function viewportReady(value: unknown): boolean
	local fields = record(value)
	local viewport = record(fields.viewport)
	for _, name in { "width", "height", "screenWidth", "screenHeight" } do
		local size = viewport[name]
		if type(size) ~= "number" or not (size > 1 and size < math.huge) then
			return false
		end
	end
	return true
end

local function interfaceMounted(value: unknown, requireContent: boolean?): boolean
	if type(value) ~= "table" then
		return false
	end
	local fields = value :: { [string]: unknown }
	return (tonumber(fields.roots) or 0) > 0 and (not requireContent or fields.mounted ~= false)
end

return {
	viewportReady = viewportReady,
	interfaceMounted = interfaceMounted,
	create = create,
	describe = describe,
	readDump = readDump,
}
