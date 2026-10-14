--!strict

local Hash = require("./hash")

export type Part = {
	name: string,
	value: string,
	filename: string?,
	contentType: string?,
}

local Multipart = {}

local sequence = 0

function Multipart.boundary(): string
	sequence += 1
	local seed = ("%s-%d-%d"):format(tostring(os.clock()), os.time(), sequence)
	return "----FacetPackage" .. string.sub(Hash.sha256(seed), 1, 24)
end

function Multipart.encode(parts: { Part }, boundary: string?): (string, string)
	local marker = boundary or Multipart.boundary()
	local pieces: { string } = {}
	for _, part in parts do
		table.insert(pieces, "--" .. marker .. "\r\n")
		if part.filename ~= nil then
			table.insert(
				pieces,
				('Content-Disposition: form-data; name="%s"; filename="%s"\r\n'):format(part.name, part.filename)
			)
			table.insert(pieces, ("Content-Type: %s\r\n\r\n"):format(part.contentType or "application/octet-stream"))
		else
			table.insert(pieces, ('Content-Disposition: form-data; name="%s"\r\n\r\n'):format(part.name))
		end
		table.insert(pieces, part.value)
		table.insert(pieces, "\r\n")
	end
	table.insert(pieces, "--" .. marker .. "--\r\n")
	return table.concat(pieces), "multipart/form-data; boundary=" .. marker
end

return table.freeze(Multipart)
