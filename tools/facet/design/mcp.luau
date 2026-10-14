--!strict

local Contract = require("./contract")
local Registry = require("./registry")
local Schema = require("../lib/schema")
local Wire = require("./wire")

export type Session = {
	context: Registry.Context,
	initialized: boolean,
	protocol: string,
	fixedAuthor: boolean,
	client: string?,
	version: string,
}

export type Options = {
	root: string?,
	author: string?,
	schema: Schema.Schema?,
	version: string?,
}

local Mcp = {}

Mcp.PROTOCOLS = { "2025-06-18", "2025-03-26", "2024-11-05" }
Mcp.PARSE_ERROR = -32700
Mcp.INVALID_REQUEST = -32600
Mcp.METHOD_NOT_FOUND = -32601
Mcp.INVALID_PARAMS = -32602
Mcp.INTERNAL_ERROR = -32603

local INSTRUCTIONS = table.concat({
	"Facet Design edits Roblox UI view modules written with Facet. The Luau file is the design document.",
	"Call list_views to find view modules, then query_tree to read node ids.",
	"Change a file with one operation tool, or with apply for an atomic batch.",
	"Pass base (the hash from query_tree) to reject a change when the file changed in the meantime.",
	"undo and redo act only on your own history entries.",
	"Call docs with topic Editable subset for the supported source forms.",
}, " ")

function Mcp.session(options: Options): Session
	return {
		context = {
			author = options.author or "agent:mcp",
			root = options.root,
			schema = options.schema,
		},
		initialized = false,
		protocol = Mcp.PROTOCOLS[1],
		fixedAuthor = options.author ~= nil,
		version = options.version or "0.0.0",
	}
end

local function response(id: unknown, result: unknown): { [string]: unknown }
	return { jsonrpc = "2.0", id = id, result = result }
end

local function errorResponse(id: unknown, code: number, message: string): { [string]: unknown }
	return { jsonrpc = "2.0", id = if id == nil then Wire.null else id, error = { code = code, message = message } }
end

local function sanitizeClient(name: string): string
	local clean = string.gsub(string.lower(name), "[^%w_%-%.]", "-")
	if clean == "" then
		clean = "mcp"
	end
	return "agent:" .. string.sub(clean, 1, 48)
end

local DESTRUCTIVE: { [string]: boolean } = { remove = true, unwrap = true, unset_prop = true, apply = true }

function Mcp.toolList(): { unknown }
	local tools: { unknown } = {}
	for _, tool in Registry.list() do
		local schema = Contract.jsonSchema(tool.input)
		table.insert(tools, {
			name = tool.name,
			description = tool.summary,
			inputSchema = schema,
			annotations = {
				title = tool.name,
				readOnlyHint = tool.mutation == "none",
				destructiveHint = tool.mutation ~= "none" and DESTRUCTIVE[tool.name] == true,
				idempotentHint = tool.mutation == "none",
				openWorldHint = false,
			},
		})
	end
	return tools
end

local function params(message: { [string]: unknown }): { [string]: unknown }
	local value = message.params
	if type(value) == "table" then
		return value :: { [string]: unknown }
	end
	return {}
end

function Mcp.handleMessage(session: Session, message: unknown): { [string]: unknown }?
	if type(message) ~= "table" or not Wire.isObject(message) then
		return errorResponse(nil, Mcp.INVALID_REQUEST, "a JSON-RPC message must be an object")
	end
	local request = message :: { [string]: unknown }
	local id = request.id
	if id == Wire.null then
		id = nil
	end
	local method = request.method
	local isNotification = request.id == nil
	if request.jsonrpc ~= "2.0" or type(method) ~= "string" then
		if request.result ~= nil or request.error ~= nil then
			return nil
		end
		return errorResponse(id, Mcp.INVALID_REQUEST, "expected jsonrpc 2.0 and a method")
	end
	if id ~= nil and type(id) ~= "string" and type(id) ~= "number" then
		return errorResponse(nil, Mcp.INVALID_REQUEST, "id must be a string or a number")
	end
	local name = method :: string
	if isNotification then
		if name == "notifications/initialized" then
			session.initialized = true
		end
		return nil
	end
	local arguments = params(request)
	if name == "initialize" then
		local requested = arguments.protocolVersion
		if type(requested) == "string" and table.find(Mcp.PROTOCOLS, requested) then
			session.protocol = requested :: string
		else
			session.protocol = Mcp.PROTOCOLS[1]
		end
		local clientInfo = arguments.clientInfo
		local clientName = if type(clientInfo) == "table" then (clientInfo :: { [string]: unknown }).name else nil
		if type(clientName) == "string" then
			session.client = clientName :: string
			if not session.fixedAuthor then
				session.context.author = sanitizeClient(clientName :: string)
			end
		end
		return response(id, {
			protocolVersion = session.protocol,
			capabilities = { tools = { listChanged = false } },
			serverInfo = { name = "facet-design", title = "Facet Design", version = session.version },
			instructions = INSTRUCTIONS,
		})
	elseif name == "ping" then
		return response(id, Wire.emptyObject())
	elseif name == "tools/list" then
		return response(id, { tools = Mcp.toolList() })
	elseif name == "tools/call" then
		local toolName = arguments.name
		if type(toolName) ~= "string" then
			return errorResponse(id, Mcp.INVALID_PARAMS, "tools/call needs params.name")
		end
		local tool = Registry.get(toolName :: string)
		if tool == nil or tool.internal then
			return errorResponse(id, Mcp.INVALID_PARAMS, "unknown tool: " .. (toolName :: string))
		end
		local input = arguments.arguments
		if input ~= nil and (type(input) ~= "table" or (Wire.isArray(input) and next(input :: { unknown }) ~= nil)) then
			return errorResponse(id, Mcp.INVALID_PARAMS, "params.arguments must be an object")
		end
		local result, failure = Registry.call(session.context, toolName :: string, input or {})
		if result == nil then
			local problem = failure or { code = "internal", message = "the tool failed" }
			local payload = { error = { code = problem.code, message = problem.message } }
			return response(id, {
				content = { { type = "text", text = problem.code .. ": " .. problem.message } },
				structuredContent = payload,
				isError = true,
			})
		end
		local structured = Wire.object((result or {}) :: { [string]: Wire.Value })
		return response(id, {
			content = { { type = "text", text = Wire.encode(structured) } },
			structuredContent = structured,
			isError = false,
		})
	elseif name == "resources/list" then
		return response(id, { resources = {} })
	elseif name == "prompts/list" then
		return response(id, { prompts = {} })
	end
	return errorResponse(id, Mcp.METHOD_NOT_FOUND, "method not found: " .. name)
end

function Mcp.handle(session: Session, line: string): string?
	local trimmed = string.gsub(line, "^%s+", "")
	trimmed = string.gsub(trimmed, "%s+$", "")
	if trimmed == "" then
		return nil
	end
	local ok, decoded = Wire.decode(trimmed)
	if not ok then
		return Wire.encode(errorResponse(nil, Mcp.PARSE_ERROR, "parse error: " .. tostring(decoded)))
	end
	if type(decoded) == "table" and Wire.isArray(decoded) and #(decoded :: { unknown }) > 0 then
		local replies: { unknown } = {}
		for _, message in decoded :: { unknown } do
			local reply = Mcp.handleMessage(session, message)
			if reply then
				table.insert(replies, reply)
			end
		end
		if #replies == 0 then
			return nil
		end
		return Wire.encode(replies)
	end
	local reply = Mcp.handleMessage(session, decoded)
	if reply == nil then
		return nil
	end
	return Wire.encode(reply)
end

function Mcp.serve(session: Session, read: () -> string?, write: (string) -> ())
	local pending = ""
	while true do
		local chunk = read()
		if chunk == nil then
			break
		end
		pending ..= chunk :: string
		while true do
			local newline = string.find(pending, "\n", 1, true)
			if newline == nil then
				break
			end
			local line = string.sub(pending, 1, newline - 1)
			pending = string.sub(pending, newline + 1)
			local reply = Mcp.handle(session, line)
			if reply then
				write(reply .. "\n")
			end
		end
	end
	if string.find(pending, "%S") then
		local reply = Mcp.handle(session, pending)
		if reply then
			write(reply .. "\n")
		end
	end
end

return table.freeze(Mcp)
