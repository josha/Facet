--!strict

local blends = require("./blends")
local botanicals = require("./botanicals")

local art = {}

export type Art = { mark: string, role: string, blend: number, image: string? }

local ROLES = { "accent", "control", "contentSecondary", "surfaceStrong", "controlSelected" }
local BLENDS = { 0.85, 0.55, 0.35, 0.7, 0.45 }

local function monogram(title: string): string
	local initials = ""
	for word in string.gmatch(title, "[%a']+") do
		initials ..= string.upper(string.sub(word, 1, 1))
		if #initials >= 2 then
			break
		end
	end
	if initials == "" then
		initials = "?"
	end
	return initials
end

local entries: { [string]: Art } = {}

local function register(key: string, title: string, index: number)
	entries[key] = {
		mark = monogram(title),
		role = ROLES[((index - 1) % #ROLES) + 1],
		blend = BLENDS[((index - 1) % #BLENDS) + 1],
		image = nil,
	}
end

for i, blend in blends.list do
	register("blend:" .. blend.id, blend.title, i)
end
for i, botanical in botanicals.list do
	register("botanical:" .. botanical.id, botanical.name, i + 2)
end

art.SEAL_MARK = "*"
art.SEAL_ROLE = "accent"

function art.of(kind: string, id: string): Art
	local hit = entries[kind .. ":" .. id]
	if hit ~= nil then
		return hit
	end
	return { mark = "?", role = "surfaceStrong", blend = 0.5, image = nil }
end

art.entries = entries
art.monogram = monogram

return art
