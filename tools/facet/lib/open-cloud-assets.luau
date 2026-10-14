--!strict

local json = require("@std/json")
local net = require("@std/net")
local task = require("@std/task")
local OpenCloud = require("../../vendor/verify/src/lute/open-cloud")

export type Exchange = OpenCloud.Exchange
export type Authorization = OpenCloud.Authorization

export type Purpose = "create" | "poll" | "read"

export type Request = {
	purpose: Purpose,
	method: "GET" | "POST",
	url: string,
	headers: { [string]: string },
	body: string?,
}

export type Transport = (request: Request) -> Exchange

export type Part = { name: string, value: string }
export type FilePart = { name: string, filename: string, contentType: string, data: string }

export type Created = {
	contentId: string,
	moderation: string,
	assetType: string?,
	operation: string,
	polls: number,
}

export type Options = {
	transport: Transport,
	authorize: ((Request) -> Authorization)?,
	pollAttempts: number?,
	pollSeconds: number?,
	sleep: ((seconds: number) -> ())?,
}

local API = "https://apis.roblox.com/assets/v1"

local Assets = {}

Assets.CREATE_URL = API .. "/assets"

function Assets.operationUrl(operation: string): string
	return ("%s/operations/%s"):format(API, operation)
end

function Assets.assetUrl(assetId: string): string
	return ("%s/assets/%s"):format(API, assetId)
end

function Assets.multipart(fields: { Part }, file: FilePart, boundary: string): (string, string)
	local parts: { string } = {}
	for _, field in fields do
		table.insert(parts, ("--%s\r\n"):format(boundary))
		table.insert(parts, ('Content-Disposition: form-data; name="%s"\r\n\r\n'):format(field.name))
		table.insert(parts, field.value .. "\r\n")
	end
	table.insert(parts, ("--%s\r\n"):format(boundary))
	table.insert(
		parts,
		('Content-Disposition: form-data; name="%s"; filename="%s"\r\n'):format(file.name, file.filename)
	)
	table.insert(parts, ("Content-Type: %s\r\n\r\n"):format(file.contentType))
	table.insert(parts, file.data .. "\r\n")
	table.insert(parts, ("--%s--\r\n"):format(boundary))
	return table.concat(parts), ("multipart/form-data; boundary=%s"):format(boundary)
end

function Assets.netTransport(apiKey: string): Transport
	return function(request: Request): Exchange
		local headers = table.clone(request.headers)
		headers["x-api-key"] = apiKey
		local metadata: net.Metadata = {
			method = request.method :: string,
			headers = headers,
			body = request.body,
		}
		local ok, response = pcall(net.request, request.url, metadata)
		if not ok then
			return { status = "unanswered", detail = tostring(response) }
		end
		return { status = "answered", httpStatus = response.status, body = response.body }
	end
end

local function decoded(exchange: Exchange): { [string]: unknown }?
	local ok, value: unknown = pcall(json.deserialize, exchange.body or "")
	if ok and type(value) == "table" then
		return value :: { [string]: unknown }
	end
	return nil
end

local function send(options: Options, request: Request): { [string]: unknown }
	if options.authorize ~= nil then
		local verdict = options.authorize(request)
		if not verdict.ok then
			error(("%s refused: %s"):format(request.purpose, verdict.reason or "not authorized"), 0)
		end
	end
	local exchange = options.transport(request)
	if exchange.status ~= "answered" then
		error(("%s %s: %s"):format(request.method, request.url, exchange.detail or exchange.status), 0)
	end
	local code = exchange.httpStatus or 0
	if code < 200 or code >= 300 then
		error(("HTTP %d from %s\n%s"):format(code, request.url, string.sub(exchange.body or "", 1, 2000)), 0)
	end
	local value = decoded(exchange)
	if value == nil then
		error(("%s answered without a JSON object"):format(request.url), 0)
	end
	return value
end

function Assets.createRequest(fields: { Part }, file: FilePart, boundary: string): Request
	local body, contentType = Assets.multipart(fields, file, boundary)
	return {
		purpose = "create",
		method = "POST",
		url = Assets.CREATE_URL,
		headers = { ["Content-Type"] = contentType },
		body = body,
	}
end

function Assets.create(options: Options, request: Request): Created
	local started = send(options, request)
	local found: string? = nil
	local id = started.operationId
	if type(id) == "string" and id ~= "" then
		found = id
	else
		local path = started.path
		if type(path) == "string" then
			found = string.match(path, "([^/]+)$")
		end
	end
	if found == nil or found == "" then
		error("the create call returned no operation id", 0)
	end
	local operation: string = found
	local attempts = options.pollAttempts or 40
	local interval = options.pollSeconds or 3.0
	local sleep = options.sleep or function(seconds: number)
		task.wait(seconds)
	end
	for attempt = 1, attempts do
		sleep(interval)
		local result = send(options, {
			purpose = "poll",
			method = "GET",
			url = Assets.operationUrl(operation),
			headers = {},
		})
		if result.done == true then
			local response: { [string]: unknown } = if type(result.response) == "table"
				then result.response :: { [string]: unknown }
				else {}
			local assetId = response.assetId
			if type(assetId) ~= "string" and type(assetId) ~= "number" then
				error(("operation %s finished with no assetId"):format(operation), 0)
			end
			local moderationResult = response.moderationResult
			local moderation = if type(moderationResult) == "table"
				then (moderationResult :: { [string]: unknown }).moderationState
				else nil
			if moderation == "Rejected" then
				error("moderation rejected the asset", 0)
			end
			local assetType = response.assetType
			if assetType ~= nil and assetType ~= "Image" then
				error(("the asset came back as %s, not Image"):format(tostring(assetType)), 0)
			end
			local created: Created = {
				contentId = "rbxassetid://" .. tostring(assetId),
				moderation = if type(moderation) == "string" then moderation :: string else "Unknown",
				assetType = if type(assetType) == "string" then assetType :: string else nil,
				operation = operation,
				polls = attempt,
			}
			return created
		end
	end
	error(("operation %s never completed"):format(operation), 0)
end

function Assets.read(options: Options, assetId: string): (string, string)
	local info = send(options, { purpose = "read", method = "GET", url = Assets.assetUrl(assetId), headers = {} })
	local moderationResult = info.moderationResult
	local state = if type(moderationResult) == "table"
		then (moderationResult :: { [string]: unknown }).moderationState
		else nil
	local kind = info.assetType
	local stateText: string = if type(state) == "string" then state :: string else "Unknown"
	local kindText: string = if type(kind) == "string" then kind :: string else "Unknown"
	return stateText, kindText
end

return table.freeze(Assets)
