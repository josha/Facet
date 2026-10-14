--!strict

local net = require("@std/net")
local task = require("@std/task")
local Json = require("./json")

export type Exchange = {
	status: "answered" | "unsent" | "unanswered",
	httpStatus: number?,
	body: string?,
	detail: string?,
}

export type Request = {
	method: string,
	url: string,
	headers: { [string]: string },
	body: string?,
}

export type Transport = (request: Request) -> Exchange

export type Clock = {
	now: () -> number,
	sleep: (seconds: number) -> (),
}

export type Canned = {
	method: string,
	fragment: string,
	status: number,
	payload: unknown,
}

export type Call = {
	method: string,
	url: string,
	bodyBytes: number,
}

export type Fake = {
	transport: Transport,
	calls: { Call },
}

local Assets = {}

Assets.BASE = "https://apis.roblox.com/assets"

function Assets.network(request: Request): Exchange
	local metadata: net.Metadata = {
		method = request.method,
		body = request.body,
		headers = request.headers,
	}
	local launched, response = pcall(net.request, request.url, metadata)
	if not launched then
		return { status = "unanswered", detail = tostring(response) }
	end
	local answer = response :: net.Response
	return { status = "answered", httpStatus = answer.status, body = answer.body }
end

function Assets.realClock(): Clock
	return {
		now = os.clock,
		sleep = function(seconds: number)
			task.wait(seconds)
		end,
	}
end

function Assets.fake(script: { Canned }): Fake
	local remaining = table.clone(script)
	local calls: { Call } = {}
	local function transport(request: Request): Exchange
		table.insert(calls, { method = request.method, url = request.url, bodyBytes = #(request.body or "") })
		for index, canned in remaining do
			if canned.method == request.method and string.find(request.url, canned.fragment, 1, true) ~= nil then
				table.remove(remaining, index)
				return { status = "answered", httpStatus = canned.status, body = Json.encode(canned.payload) }
			end
		end
		error(("fake transport: nothing canned for %s %s"):format(request.method, request.url), 0)
	end
	return { transport = transport, calls = calls }
end

function Assets.call(
	transport: Transport,
	method: string,
	path: string,
	apiKey: string,
	body: string?,
	contentType: string?
): (number, Json.Object)
	local url = Assets.BASE .. path
	local headers: { [string]: string } = { ["x-api-key"] = apiKey, Accept = "application/json" }
	if contentType ~= nil then
		headers["Content-Type"] = contentType
	end
	local exchange = transport({ method = method, url = url, headers = headers, body = body })
	local status = exchange.httpStatus
	if exchange.status ~= "answered" or status == nil then
		error(("package: network failure calling %s %s: %s"):format(method, url, exchange.detail or exchange.status), 0)
	end
	local text = exchange.body or ""
	local decoded = Json.tryDecode(text)
	local object = Json.asObject(decoded)
	if object == nil then
		local raw = Json.object()
		Json.set(raw, "raw", string.sub(text, 1, 512))
		return status, raw
	end
	return status, object
end

function Assets.poll(
	transport: Transport,
	operationPath: string,
	apiKey: string,
	clock: Clock,
	say: (string) -> (),
	timeout: number?
): (number, Json.Object)
	local limit = timeout or 600
	local segments = string.split(operationPath, "/")
	local operation = segments[#segments]
	local deadline = clock.now() + limit
	local delay = 1
	while clock.now() < deadline do
		local status, payload = Assets.call(transport, "GET", "/v1/operations/" .. operation, apiKey)
		if status ~= 200 then
			return status, payload
		end
		local done = Json.field(payload, "done")
		if done ~= nil and done ~= false then
			return status, payload
		end
		say(("  operation %s: not done, retrying in %.0fs"):format(operation, delay))
		clock.sleep(delay)
		delay = math.min(delay * 2, 15)
	end
	local message = Json.object()
	Json.set(message, "message", ("operation %s did not complete within %ds"):format(operation, limit))
	local failure = Json.object()
	Json.set(failure, "error", message)
	return 408, failure
end

return table.freeze(Assets)
