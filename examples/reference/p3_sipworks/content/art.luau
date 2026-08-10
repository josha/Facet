--!strict
-- Sipworks art — the proof's own picture seam.
--
-- WHY THERE ARE NO ASSET IDS HERE, STATED PLAINLY. The tutorial gallery already
-- paid for the alternative: the match-3 example shipped invented ids
-- ("rbxassetid://100000000n") and every tile drew NOTHING on a real client
-- (examples/gallery/examples/assets.luau). Art production is not in this
-- package's scope, so inventing ids would ship exactly that blank screen into
-- the reference proof the audit is about.
--
-- So a Sipworks art slot is a MONOGRAM PLATE: a themable tinted box carrying
-- the blend's or botanical's initials. It is original, it is legible in every
-- package (the tint is a theme ROLE blend, never a colour literal), it reads at
-- ten feet, and it needs no upload. The seam is one field: give an entry an
-- `image` and `views/parts.artPlate` paints a real `UI.Image{ scaleMode =
-- "crop" }` in the same box instead — dropping real art in later is a content
-- edit and nothing else.

local blends = require("./blends")
local botanicals = require("./botanicals")

local art = {}

export type Art = { mark: string, role: string, blend: number, image: string? }

-- The tint ladder. Theme ROLES, cycled deterministically by declaration index,
-- so the shelf reads as a set rather than a rainbow and a package swap moves
-- every plate together.
local ROLES = { "accent", "control", "contentSecondary", "surfaceStrong", "controlSelected" }
local BLENDS = { 0.85, 0.55, 0.35, 0.7, 0.45 }

-- monogram(title): up to two initials, ASCII only — the same rule the framework
-- follows for its own icon fallbacks, because ASCII is the one range every
-- shipped font is guaranteed to draw.
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

-- the stamp seal: one mark, one role. A stamped seal is the accent at full
-- strength; the unstamped ring is a hairline-stroked plate with no mark at all,
-- so the two states differ in FORM and not only in hue.
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
