--!strict

local Core = require("../../vendor/verify/src/core")

export type Generation = { ok: boolean, file: string?, bytes: number?, at: number? }
export type Upload = { ok: boolean, tool: string?, assetId: string?, loaded: boolean?, at: number? }
export type Record = {
	agent: string,
	tools: { string },
	generation: Generation?,
	upload: Upload?,
	authorStart: number?,
}

local GENERATION = "image-generation"
local UPLOAD = "asset-upload"
local UPLOAD_TOOLS = { "upload_image", "open_cloud_invoke" }

local function generates(adapter: string, arguments: { string }): boolean
	if adapter ~= "codex" then
		return false
	end
	for index, argument in arguments do
		if argument == "--disable" and arguments[index + 1] == "image_generation" then
			return false
		end
	end
	return true
end

local function generation(record: Record): { string }
	local issues: { string } = {}
	local made = record.generation
	if made == nil then
		return { "no image generation was tried before the author clock" }
	end
	if not made.ok then
		table.insert(issues, "the image generator did not return an image")
	end
	if made.file == nil or (made.bytes or 0) <= 0 then
		table.insert(issues, "the generated image has no file or no bytes")
	end
	return issues
end

local function upload(record: Record): { string }
	local issues: { string } = {}
	local offered: { string } = {}
	for _, name in UPLOAD_TOOLS do
		if table.find(record.tools, name) ~= nil then
			table.insert(offered, name)
		end
	end
	if #offered == 0 then
		table.insert(
			issues,
			("the author's Studio tools have no upload route; they need %s. Tools: %s"):format(
				table.concat(UPLOAD_TOOLS, " or "),
				if #record.tools > 0 then table.concat(record.tools, ", ") else "none recorded"
			)
		)
	end
	local sent = record.upload
	if sent == nil then
		table.insert(issues, "no upload was tried before the author clock")
		return issues
	end
	if sent.tool == nil or table.find(offered, sent.tool) == nil then
		table.insert(
			issues,
			("the upload used %s, which is not a tool that the author has"):format(sent.tool or "no named tool")
		)
	end
	if not sent.ok or sent.assetId == nil or sent.assetId == "" then
		table.insert(issues, "the upload returned no asset id")
	end
	if sent.loaded ~= true then
		table.insert(issues, "the uploaded asset was not seen loaded in the owned Studio")
	end
	return issues
end

local function order(record: Record, required: { string }): { string }
	local start = record.authorStart
	if start == nil then
		return {}
	end
	local issues: { string } = {}
	local function before(name: string, at: number?)
		if at == nil or at >= start then
			table.insert(issues, ("%s was not complete before the author clock started"):format(name))
		end
	end
	if table.find(required, GENERATION) ~= nil then
		local made = record.generation
		before(GENERATION, if made then made.at else nil)
	end
	if table.find(required, UPLOAD) ~= nil then
		local sent = record.upload
		before(UPLOAD, if sent then sent.at else nil)
	end
	return issues
end

local function cases(record: Record?, required: { string }): { Core.NamedCase }
	local function case(id: string, find: (Record) -> { string }): Core.NamedCase
		return {
			id = id,
			name = id,
			run = function(t: Core.Context)
				if record == nil then
					t:expect(false):toBeTrueWith("preflight/images.json is missing: the routes were not tried")
					return
				end
				local issues = find(record)
				t:expect(#issues == 0):toBeTrueWith(table.concat(issues, "; "))
			end,
		}
	end
	local list: { Core.NamedCase } = {}
	if table.find(required, GENERATION) ~= nil then
		table.insert(list, case("preflight/" .. GENERATION, generation))
	end
	if table.find(required, UPLOAD) ~= nil then
		table.insert(list, case("preflight/" .. UPLOAD, upload))
	end
	if #list > 0 then
		table.insert(
			list,
			case("preflight/before-clock", function(found: Record): { string }
				return order(found, required)
			end)
		)
	else
		table.insert(list, {
			id = "preflight/none-required",
			name = "preflight/none-required",
			run = function() end,
		})
	end
	return list
end

return table.freeze({
	GENERATION = GENERATION,
	UPLOAD = UPLOAD,
	UPLOAD_TOOLS = UPLOAD_TOOLS,
	generates = generates,
	generation = generation,
	upload = upload,
	order = order,
	cases = cases,
})
