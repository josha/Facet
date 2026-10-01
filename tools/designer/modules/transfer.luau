--!strict

local savedLibrary = require("./saved_library")

local transfer = {}
local limit = 900000

function transfer.encode(value: any, encode: (any) -> string): string
	assert(type(value) == "table", "Choose a Facet design")
	local clean = savedLibrary.validate({ draft = value }).draft
	local text = encode({ format = "facet-design-file/1", design = clean })
	assert(#text <= limit, "Design file exceeds 900 KB")
	return text
end

function transfer.decode(text: string, decode: (string) -> any): any
	assert(type(text) == "string" and #text <= limit, "Design file exceeds 900 KB")
	local envelope = decode(text)
	assert(type(envelope) == "table" and envelope.format == "facet-design-file/1", "Choose a Facet Design file")
	assert(type(envelope.design) == "table", "Design file has no design")
	return savedLibrary.validate({ draft = envelope.design }).draft
end

return transfer
