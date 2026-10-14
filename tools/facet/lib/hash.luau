--!strict

local crypto = require("@lute/crypto")

local Hash = {}

local function hex(digest: buffer): string
	local parts = table.create(buffer.len(digest))
	for index = 0, buffer.len(digest) - 1 do
		parts[index + 1] = string.format("%02x", buffer.readu8(digest, index))
	end
	return table.concat(parts)
end

function Hash.sha256(message: string): string
	return hex(crypto.digest(crypto.hash.sha256, message))
end

function Hash.sha1(message: string): string
	return hex(crypto.digest(crypto.hash.sha1, message))
end

function Hash.sha256Text(message: string): string
	local normalized = string.gsub(message, "\r\n", "\n")
	return Hash.sha256(normalized)
end

return table.freeze(Hash)
