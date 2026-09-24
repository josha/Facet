--!strict
-- The label on a skinned control's tinted art: the plate colour a player sees and
-- the content colour that reads on it. Reads only a theme's colours/extra; writes
-- nothing. Moved out of `sheet_model` along the seam its source-cap row names.
local tokens = require("./tokens")

local art_contrast = {}

local FLOOR = 4.5 -- the contract's own 4.5:1 floor, as sheet_model gates it

--[[ A skinned control's art multiplied by `tint`. The art's colour as painted is
	the package's `extra.controlArt` (its sampled centre), else its flat `control`;
	another slot's art is `extra[art]` (`fieldArt`, `badgeArt`). Art that lets the
	panel through (`a` < 1, a badge seal) reads over the surface. ]]
function art_contrast.chromePlate(theme: any, tint: any, art: string?): { r: number, g: number, b: number }
	local x = theme.extra or {}
	local base = if art ~= nil and type(x[art]) == "table"
		then x[art]
		elseif type(x.controlArt) == "table" then x.controlArt
		elseif type(x.control) == "table" then x.control
		else theme.colors.surfaceStrong
	local a, s = base.a or 1, theme.colors.surface
	return {
		r = base.r * tint.r * a + s.r * (1 - a),
		g = base.g * tint.g * a + s.g * (1 - a),
		b = base.b * tint.b * a + s.b * (1 - a),
	}
end

-- `onAccent` when it clears the floor on the plate, else whichever reads better
function art_contrast.onChromeColor(theme: any, tint: any): { r: number, g: number, b: number }
	local c = theme.colors
	local plate = art_contrast.chromePlate(theme, tint)
	local on, content = tokens.contrastRatio(c.onAccent, plate), tokens.contrastRatio(c.content, plate)
	local pick = if on >= FLOOR or on >= content then c.onAccent else c.content
	return { r = pick.r, g = pick.g, b = pick.b }
end

--[[ ...and any other lifted label: the first of `picks` that clears the floor on
	its art, else whichever reads best. A plain button offers content first (every
	flat-art package keeps its label), then contentStrong and onAccent; a
	destructive one offers onDanger first. ]]
function art_contrast.readableOnChrome(
	theme: any,
	tint: any,
	picks: { any },
	art: string?
): { r: number, g: number, b: number }
	local plate = art_contrast.chromePlate(theme, tint, art)
	local best, bestRatio = picks[1], -1
	for _, pick in picks do
		local ratio = tokens.contrastRatio(pick, plate)
		if ratio >= FLOOR then
			return { r = pick.r, g = pick.g, b = pick.b }
		end
		if ratio > bestRatio then
			best, bestRatio = pick, ratio
		end
	end
	return { r = best.r, g = best.g, b = best.b }
end

return art_contrast
