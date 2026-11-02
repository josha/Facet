--!strict

local Diagnostics = require "./diagnostics"

type Failure = { summary: string, contract: string, fix: string? }

local failures: { [string]: Failure } = {
	["not-a-host"] = {
		summary = "createRuntime expects a host table",
		contract = "a host implements the protocol in src/core/host.luau",
	},
	unnamed = {
		summary = "a host must name itself",
		contract = "host.name appears in every diagnostic Compose raises about this host",
		fix = 'set host.name, e.g. "roblox"',
	},
	["no-renderer"] = {
		summary = "host %q has no render capability",
		contract = "render is the one required capability",
	},
	["incomplete-renderer"] = {
		summary = "host %q is missing render.%s",
		contract = "every method in Renderer is required",
	},
	["incomplete-events"] = {
		summary = "host %q declares events without connectEvent",
		contract = "a declared capability must be complete",
		fix = "either implement connectEvent or omit host.events entirely",
	},
	["incomplete-observation"] = {
		summary = "host %q declares observation but does not implement it",
		contract = "observation requires both readProperty and observeProperty",
		fix = "either implement both or omit host.observation entirely",
	},
	["incomplete-styled-observation"] = {
		summary = "styled observation requires both host methods",
		contract = "readStyledProperty and observeStyledProperty must be supplied together",
	},
	["incomplete-naming"] = {
		summary = "host %q declares naming but does not implement it",
		contract = "naming requires setName",
		fix = "either implement setName or omit host.naming entirely",
	},
	["incomplete-frames"] = {
		summary = "host %q declares frames but does not implement it",
		contract = "frames requires both onFrame and now",
		fix = "either implement both or omit host.frames entirely",
	},
}

return function(code: string, name: string?, actual: unknown?, method: string?)
	local failure = failures[code]
	local summary = failure.summary
	if name ~= nil then
		summary = summary:format(name, method)
	end
	local fields: Diagnostics.Fields = {
		contract = failure.contract,
		fix = failure.fix,
		actual = if code == "not-a-host" or code == "incomplete-renderer" then Diagnostics.describe(actual) else nil,
		expected = if code == "incomplete-renderer" then "a function" else nil,
	}
	return Diagnostics.raise("host/" .. code, summary, fields)
end
