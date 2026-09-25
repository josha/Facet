--!strict
local richText = {}

local ENTITIES: { [string]: string } = {
	["&"] = "&amp;",
	["<"] = "&lt;",
	[">"] = "&gt;",
	['"'] = "&quot;",
	["'"] = "&apos;",
}

function richText.escape(words: string): string
	assert(type(words) == "string", "Facet richText.escape takes a string")
	return (string.gsub(words, "[&<>\"']", ENTITIES))
end

return table.freeze(richText)
