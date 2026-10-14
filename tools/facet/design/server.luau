--!strict

local fs = require("@std/fs")
local net = require("@lute/net")
local task = require("@std/task")
local Document = require("./document")
local Registry = require("./registry")
local Schema = require("../lib/schema")
local Wire = require("./wire")
local Workspace = require("./workspace")

export type Watched = {
	key: string,
	path: string,
	hash: string,
	stamp: string,
	valid: boolean,
	error: string?,
	doc: Document.Document?,
	source: string,
}

export type Presence = { node: string?, selection: { string }? }

export type Client = {
	id: string,
	name: string,
	kind: string,
	author: string,
	files: { [string]: boolean },
	presence: { [string]: Presence },
}

export type Job = () -> ()

export type Hub = {
	root: string,
	schema: Schema.Schema?,
	files: { [string]: Watched },
	clients: { [string]: Client },
	order: { string },
	queue: { Job },
	writing: boolean,
	sequence: number,
	send: (clientId: string, text: string) -> (),
	roots: { string },
	version: string,
}

export type Options = {
	root: string,
	roots: { string }?,
	schema: Schema.Schema?,
	send: (clientId: string, text: string) -> (),
	version: string?,
}

local Server = {}

Server.PROTOCOL = 1

local function relative(hub: Hub, path: string): string
	local normalized = string.gsub(path, "\\", "/")
	local root = hub.root
	if string.sub(normalized, 1, #root + 1) == root .. "/" then
		return string.sub(normalized, #root + 2)
	end
	if string.sub(normalized, 1, 2) == "./" then
		return string.sub(normalized, 3)
	end
	return normalized
end

local function absolute(hub: Hub, key: string): string
	if string.sub(key, 1, 1) == "/" or string.match(key, "^%a:/") then
		return key
	end
	return hub.root .. "/" .. key
end

local function stampOf(path: string): string?
	local ok, meta = pcall(fs.metadata, path)
	if not ok then
		return nil
	end
	local info = meta :: fs.FileMetadata
	return tostring(info.modified) .. ":" .. tostring(info.size)
end

local function emit(hub: Hub, clientId: string, message: { [string]: unknown })
	hub.send(clientId, Wire.encode(message))
end

local function broadcast(hub: Hub, file: string, message: { [string]: unknown }, except: string?)
	local text = Wire.encode(message)
	for _, clientId in hub.order do
		local client = hub.clients[clientId]
		if client and client.files[file] and clientId ~= except then
			hub.send(clientId, text)
		end
	end
end

local function track(hub: Hub, key: string): Watched?
	local existing = hub.files[key]
	if existing then
		return existing
	end
	local path = absolute(hub, key)
	if not fs.exists(path) then
		return nil
	end
	local source = fs.readFileToString(path)
	local doc = Document.parse(source, hub.schema)
	if doc.root == nil and doc.error == nil then
		return nil
	end
	local watched: Watched = {
		key = key,
		path = path,
		hash = Workspace.hash(source),
		stamp = stampOf(path) or "",
		valid = doc.error == nil and doc.root ~= nil,
		error = doc.error,
		doc = doc,
		source = source,
	}
	hub.files[key] = watched
	return watched
end

function Server.hub(options: Options): Hub
	local hub: Hub = {
		root = string.gsub(options.root, "\\", "/"),
		schema = options.schema,
		files = {},
		clients = {},
		order = {},
		queue = {},
		writing = false,
		sequence = 0,
		send = options.send,
		roots = options.roots or { options.root },
		version = options.version or "0.0.0",
	}
	for _, path in Workspace.discover(hub.roots) do
		track(hub, relative(hub, path))
	end
	return hub
end

local function fileList(hub: Hub): { unknown }
	local keys: { string } = {}
	for key in hub.files do
		table.insert(keys, key)
	end
	table.sort(keys)
	local list: { unknown } = {}
	for _, key in keys do
		local watched = hub.files[key]
		table.insert(list, { file = key, hash = watched.hash, valid = watched.valid })
	end
	return list
end

local function presenceList(hub: Hub, file: string): { unknown }
	local list: { unknown } = {}
	for _, clientId in hub.order do
		local client = hub.clients[clientId]
		local presence = if client then client.presence[file] else nil
		if client and presence then
			table.insert(list, {
				client = { id = client.id, name = client.name, kind = client.kind, author = client.author },
				node = presence.node,
				selection = presence.selection,
			})
		end
	end
	return list
end

local function snapshot(hub: Hub, watched: Watched): { [string]: unknown }
	local doc = watched.doc
	return {
		type = "snapshot",
		file = watched.key,
		hash = watched.hash,
		valid = watched.valid,
		error = watched.error,
		source = watched.source,
		tree = if doc then Document.json(doc) else nil,
		presence = presenceList(hub, watched.key),
	}
end

local function refresh(hub: Hub, watched: Watched, source: string, doc: Document.Document?)
	watched.source = source
	watched.hash = Workspace.hash(source)
	watched.stamp = stampOf(watched.path) or watched.stamp
	local parsed = doc or Document.parse(source, hub.schema)
	watched.valid = parsed.error == nil and parsed.root ~= nil
	watched.error = parsed.error or (if parsed.root == nil then table.concat(parsed.problems, "; ") else nil)
	watched.doc = parsed
end

local function update(
	hub: Hub,
	watched: Watched,
	previous: string,
	author: string,
	origin: string?,
	details: { [string]: unknown }
)
	local message: { [string]: unknown } = {
		type = "update",
		file = watched.key,
		hash = watched.hash,
		previous = previous,
		author = author,
		origin = origin,
		valid = watched.valid,
		error = watched.error,
		source = watched.source,
		tree = if watched.doc then Document.json(watched.doc :: Document.Document) else nil,
	}
	for key, value in details do
		message[key] = value
	end
	broadcast(hub, watched.key, message)
end

local function runQueue(hub: Hub)
	if hub.writing then
		return
	end
	hub.writing = true
	while #hub.queue > 0 do
		local job = table.remove(hub.queue, 1) :: Job
		xpcall(job, function(problem: unknown)
			print("facet design serve: a write failed: " .. tostring(problem))
		end)
	end
	hub.writing = false
end

function Server.enqueue(hub: Hub, job: Job)
	table.insert(hub.queue, job)
	runQueue(hub)
end

local function failureMessage(
	request: unknown,
	file: string,
	failure: Workspace.Failure,
	watched: Watched?
): { [string]: unknown }
	return {
		type = "rejected",
		request = request,
		file = file,
		error = { code = failure.code, message = failure.message },
		hash = if watched then watched.hash else nil,
	}
end

local function afterWrite(
	hub: Hub,
	client: Client?,
	watched: Watched,
	applied: Workspace.Applied,
	request: unknown,
	details: { [string]: unknown }
)
	local previous = watched.hash
	refresh(hub, watched, applied.source, applied.doc)
	if client then
		emit(hub, client.id, {
			type = "applied",
			request = request,
			file = watched.key,
			hash = applied.hash,
			previous = applied.previous,
			changed = applied.changed,
			entry = applied.entry,
			results = applied.results,
		})
	end
	if applied.changed then
		local extra = table.clone(details)
		extra.entry = applied.entry
		extra.touched = applied.touched
		update(
			hub,
			watched,
			previous,
			if client then client.author else "server",
			if client then client.id else nil,
			extra
		)
	end
end

local function writeJob(hub: Hub, client: Client, message: { [string]: unknown }, kind: string)
	local file = message.file
	local request = message.request
	if type(file) ~= "string" then
		emit(hub, client.id, { type = "error", request = request, message = kind .. " needs file" })
		return
	end
	local key = relative(hub, file :: string)
	Server.enqueue(hub, function()
		local watched = track(hub, key)
		if watched == nil then
			emit(
				hub,
				client.id,
				failureMessage(request, key, { code = "not_found", message = "not a view module: " .. key }, nil)
			)
			return
		end
		local found = watched :: Watched
		local base = message.base
		if kind == "apply" and type(base) ~= "string" then
			emit(
				hub,
				client.id,
				failureMessage(request, key, {
					code = "invalid",
					message = "apply needs base, the hash of the snapshot the client edited",
				}, found)
			)
			return
		end
		local options: Workspace.Options = {
			author = client.author,
			base = if type(base) == "string" then base else nil,
			entry = if type(message.entry) == "number" then message.entry :: number else nil,
		}
		local applied: Workspace.Applied?
		local failure: Workspace.Failure?
		if kind == "apply" then
			applied, failure = Workspace.apply(found.path, message.ops, options, hub.schema)
		elseif kind == "undo" then
			applied, failure = Workspace.undo(found.path, options, hub.schema)
		else
			applied, failure = Workspace.redo(found.path, options, hub.schema)
		end
		if applied == nil then
			emit(
				hub,
				client.id,
				failureMessage(request, key, failure or { code = "internal", message = "failed" }, found)
			)
			return
		end
		afterWrite(hub, client, found, applied :: Workspace.Applied, request, {
			kind = kind,
			ops = if kind == "apply" then message.ops else nil,
		})
	end)
end

local function toolJob(hub: Hub, client: Client, message: { [string]: unknown })
	local name = message.name
	local request = message.request
	if type(name) ~= "string" then
		emit(hub, client.id, { type = "error", request = request, message = "tool needs name" })
		return
	end
	local tool = Registry.get(name :: string)
	if tool == nil or tool.internal then
		emit(hub, client.id, {
			type = "result",
			request = request,
			ok = false,
			error = { code = "not_found", message = "unknown tool " .. tostring(name) },
		})
		return
	end
	local input: { [string]: unknown } = if type(message.input) == "table"
		then message.input :: { [string]: unknown }
		else {}
	local context: Registry.Context = { author = client.author, root = hub.root, schema = hub.schema }
	local function run()
		local before: { [string]: string } = {}
		local file = input.file
		local key = if type(file) == "string" then relative(hub, file :: string) else nil
		if key then
			local watched = track(hub, key)
			if watched then
				before[key] = watched.hash
			end
		end
		local result, failure = Registry.call(context, name :: string, input)
		if result == nil then
			local problem = failure or { code = "internal", message = "failed" }
			emit(hub, client.id, {
				type = "result",
				request = request,
				ok = false,
				error = { code = problem.code, message = problem.message },
			})
			return
		end
		emit(hub, client.id, { type = "result", request = request, ok = true, result = result })
		if key and tool.mutation == "document" then
			local watched = hub.files[key]
			if watched then
				local source = fs.readFileToString(watched.path)
				if Workspace.hash(source) ~= before[key] then
					local previous = watched.hash
					refresh(hub, watched, source, nil)
					update(hub, watched, previous, client.author, client.id, { kind = "tool", tool = name })
				end
			end
		elseif key and tool.mutation == "comments" then
			broadcast(hub, key, { type = "comments", file = key, author = client.author, tool = name, result = result })
		end
	end
	if tool.mutation == "none" then
		run()
	else
		Server.enqueue(hub, run)
	end
end

local KINDS: { [string]: boolean } = { plugin = true, agent = true, human = true, cli = true }

function Server.connect(hub: Hub, clientId: string)
	hub.sequence += 1
	local client: Client = {
		id = clientId,
		name = "client" .. hub.sequence,
		kind = "human",
		author = "human:client" .. hub.sequence,
		files = {},
		presence = {},
	}
	hub.clients[clientId] = client
	table.insert(hub.order, clientId)
end

function Server.disconnect(hub: Hub, clientId: string)
	local client = hub.clients[clientId]
	if client == nil then
		return
	end
	hub.clients[clientId] = nil
	local index = table.find(hub.order, clientId)
	if index then
		table.remove(hub.order, index)
	end
	for file in client.presence do
		broadcast(hub, file, {
			type = "presence",
			file = file,
			client = { id = client.id, name = client.name, kind = client.kind, author = client.author },
			left = true,
		})
	end
end

function Server.receive(hub: Hub, clientId: string, text: string)
	local client = hub.clients[clientId]
	if client == nil then
		return
	end
	local ok, decoded = Wire.decode(text)
	if not ok or type(decoded) ~= "table" then
		emit(hub, clientId, { type = "error", message = "messages must be JSON objects" })
		return
	end
	local message = decoded :: { [string]: unknown }
	local kind = message.type
	if kind == "hello" then
		local info = message.client
		local name = if type(info) == "table" then (info :: { [string]: unknown }).name else nil
		local clientKind = if type(info) == "table" then (info :: { [string]: unknown }).kind else nil
		if type(name) == "string" and string.match(name :: string, "^[%w_%-%.]+$") and #(name :: string) <= 48 then
			client.name = name :: string
		end
		if type(clientKind) == "string" and KINDS[clientKind :: string] then
			client.kind = clientKind :: string
		end
		client.author = client.kind .. ":" .. client.name
		local author = message.author
		if type(author) == "string" and Workspace.checkAuthor(author :: string) == nil then
			client.author = author :: string
		end
		emit(hub, clientId, {
			type = "welcome",
			protocol = Server.PROTOCOL,
			version = hub.version,
			client = { id = client.id, name = client.name, kind = client.kind, author = client.author },
			files = fileList(hub),
		})
	elseif kind == "files" then
		emit(hub, clientId, { type = "files", files = fileList(hub) })
	elseif kind == "subscribe" then
		local file = message.file
		if type(file) ~= "string" then
			emit(hub, clientId, { type = "error", message = "subscribe needs file" })
			return
		end
		local key = relative(hub, file :: string)
		local watched = track(hub, key)
		if watched == nil then
			emit(hub, clientId, { type = "error", file = key, message = "not a view module: " .. key })
			return
		end
		client.files[key] = true
		emit(hub, clientId, snapshot(hub, watched :: Watched))
	elseif kind == "unsubscribe" then
		local file = message.file
		if type(file) == "string" then
			client.files[relative(hub, file :: string)] = nil
		end
	elseif kind == "presence" then
		local file = message.file
		if type(file) ~= "string" then
			return
		end
		local key = relative(hub, file :: string)
		local node = message.node
		local selection: { string } = {}
		for _, id in Wire.list(message.selection) do
			if type(id) == "string" and #selection < 64 then
				table.insert(selection, id :: string)
			end
		end
		client.presence[key] = { node = if type(node) == "string" then node :: string else nil, selection = selection }
		broadcast(hub, key, {
			type = "presence",
			file = key,
			client = { id = client.id, name = client.name, kind = client.kind, author = client.author },
			node = if type(node) == "string" then node else nil,
			selection = selection,
		}, clientId)
	elseif kind == "apply" or kind == "undo" or kind == "redo" then
		writeJob(hub, client, message, kind :: string)
	elseif kind == "tool" then
		toolJob(hub, client, message)
	elseif kind == "ping" then
		emit(hub, clientId, { type = "pong", request = message.request })
	else
		emit(hub, clientId, { type = "error", message = "unknown message type " .. tostring(kind) })
	end
end

function Server.poll(hub: Hub, rescan: boolean?)
	if rescan then
		for _, path in Workspace.discover(hub.roots) do
			track(hub, relative(hub, path))
		end
	end
	if hub.writing then
		return
	end
	for key, watched in hub.files do
		local stamp = stampOf(watched.path)
		if stamp == nil then
			continue
		end
		if stamp == watched.stamp then
			continue
		end
		local ok, source = pcall(fs.readFileToString, watched.path)
		if not ok then
			continue
		end
		local text = source :: string
		watched.stamp = stamp :: string
		if Workspace.hash(text) == watched.hash then
			continue
		end
		local previous = watched.hash
		refresh(hub, watched, text, nil)
		update(hub, watched, previous, "external", nil, { kind = "external" })
		if not watched.valid then
			broadcast(hub, key, { type = "invalid", file = key, hash = watched.hash, error = watched.error })
		end
	end
end

local function contentType(body: string): { [string]: string }
	return { ["content-type"] = "application/json; charset=utf-8", ["cache-control"] = "no-store" }
end

local function json(status: number, value: unknown): net.ServerResponse
	local body = Wire.encode(value)
	return { status = status, body = body, headers = contentType(body) }
end

function Server.http(hub: Hub, request: net.ReceivedRequest): net.ServerResponse
	local path = request.path
	if request.method == "GET" and (path == "/" or path == "/status") then
		local clients = 0
		for _ in hub.clients do
			clients += 1
		end
		return json(200, {
			name = "facet-design",
			version = hub.version,
			protocol = Server.PROTOCOL,
			clients = clients,
			files = fileList(hub),
		})
	elseif request.method == "GET" and path == "/files" then
		return json(200, { files = fileList(hub) })
	elseif request.method == "GET" and (path == "/tree" or path == "/source") then
		local file = request.query.file
		if file == nil then
			return json(400, { error = { code = "invalid", message = "add ?file=<path>" } })
		end
		local watched = track(hub, relative(hub, file))
		if watched == nil then
			return json(404, { error = { code = "not_found", message = "not a view module: " .. file } })
		end
		if path == "/source" then
			return {
				status = 200,
				body = (watched :: Watched).source,
				headers = { ["content-type"] = "text/plain; charset=utf-8" },
			}
		end
		return json(200, snapshot(hub, watched :: Watched))
	elseif request.method == "GET" and path == "/tools" then
		local tools: { unknown } = {}
		for _, tool in Registry.list() do
			table.insert(tools, Registry.describe(tool))
		end
		return json(200, { tools = tools })
	elseif request.method == "POST" and string.sub(path, 1, 6) == "/tool/" then
		local name = string.sub(path, 7)
		local ok, input = Wire.decode(if request.body == "" then "{}" else request.body)
		if not ok then
			return json(400, { error = { code = "invalid", message = "the body must be JSON" } })
		end
		local author = request.headers["x-facet-author"] or "http:client"
		if Workspace.checkAuthor(author) then
			return json(400, { error = { code = "invalid", message = "x-facet-author is not a valid author" } })
		end
		local clientId = "http-" .. tostring(os.clock())
		local responseBody: { [string]: unknown }? = nil
		local client: Client =
			{ id = clientId, name = "http", kind = "cli", author = author, files = {}, presence = {} }
		local send = hub.send
		hub.send = function(target: string, text: string)
			if target == clientId then
				local decoded, value = Wire.decode(text)
				if decoded then
					responseBody = value :: { [string]: unknown }
				end
			else
				send(target, text)
			end
		end
		toolJob(hub, client, { type = "tool", name = name, input = input, request = "http" })
		hub.send = send
		local body = responseBody or { ok = false, error = { code = "internal", message = "no result" } }
		return json(if body.ok then 200 else 400, body)
	end
	return json(404, { error = { code = "not_found", message = "unknown path " .. path } })
end

export type Running = { hub: Hub, server: net.Server, stop: () -> () }

function Server.start(options: {
	root: string,
	roots: { string }?,
	hostname: string?,
	port: number?,
	schema: Schema.Schema?,
	interval: number?,
	version: string?,
}): Running
	local sockets: { [string]: net.ServerWebSocket } = {}
	local ids: { [net.ServerWebSocket]: string } = {}
	local counter = 0
	local hub = Server.hub({
		root = options.root,
		roots = options.roots,
		schema = options.schema,
		version = options.version,
		send = function(clientId: string, text: string)
			local socket = sockets[clientId]
			if socket then
				pcall(function()
					socket:send(text)
				end)
			end
		end,
	})
	local server = net.server.serve({
		hostname = options.hostname or "127.0.0.1",
		port = options.port or 7878,
		handler = function(request: net.ReceivedRequest, running: net.Server): net.ServerResponse?
			if request.path == "/ws" then
				if running:upgrade(request) then
					return nil
				end
				return json(400, { error = { code = "invalid", message = "expected a WebSocket upgrade" } })
			end
			return Server.http(hub, request)
		end,
		websocket = {
			open = function(socket: net.ServerWebSocket)
				counter += 1
				local clientId = "c" .. counter
				sockets[clientId] = socket
				ids[socket] = clientId
				Server.connect(hub, clientId)
			end,
			message = function(socket: net.ServerWebSocket, message: string | buffer)
				local clientId = ids[socket]
				if clientId then
					local text = if type(message) == "string" then message else buffer.tostring(message)
					Server.receive(hub, clientId, text)
				end
			end,
			close = function(socket: net.ServerWebSocket, _code: number, _reason: string)
				local clientId = ids[socket]
				if clientId then
					ids[socket] = nil
					sockets[clientId] = nil
					Server.disconnect(hub, clientId)
				end
			end,
		},
	})
	local running = true
	local interval = options.interval or 0.5
	local poller = task.spawn(function()
		local ticks = 0
		while running do
			task.wait(interval)
			if not running then
				break
			end
			ticks += 1
			xpcall(Server.poll, function(problem: unknown)
				print("facet design serve: polling failed: " .. tostring(problem))
			end, hub, ticks % 20 == 0)
		end
	end)
	return {
		hub = hub,
		server = server,
		stop = function()
			running = false
			pcall(task.cancel, poller)
			for _, socket in sockets do
				pcall(function()
					socket:close()
				end)
			end
			server.close()
		end,
	}
end

return table.freeze(Server)
