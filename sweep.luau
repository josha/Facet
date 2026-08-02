local fs = require("@lune/fs")
local serde = require("@lune/serde")
local LuauUI = require("./src") :: any
local sheet_model = require("./src/tokens/sheet_model")
local tokens = require("./src/tokens/tokens")
local themes = LuauUI.themes
local samples = serde.decode("json", fs.readFile("assets/themes/plate-samples.json")).samples
local NAMES = { "glossy_touch", "compact_pointer", "fantasy_ornate", "fantasy_parchment", "pixel_quest" }
local function n255(c) return string.format("rgb(%3d,%3d,%3d)", math.floor(c.r*255+0.5), math.floor(c.g*255+0.5), math.floor(c.b*255+0.5)) end
local function lerp(a, b, t) return { r = a.r + (b.r-a.r)*t, g = a.g + (b.g-a.g)*t, b = a.b + (b.b-a.b)*t } end
local function mul(a, b) return { r = a.r*b.r, g = a.g*b.g, b = a.b*b.b } end
local function s255(s) return { r = s.r/255, g = s.g/255, b = s.b/255 } end
local WHITE = { r = 1, g = 1, b = 1 }
for _, name in NAMES do
	local pkg = (require("./examples/themes/" .. name) :: any).build(themes)
	local s = samples[pkg.identity.id]
	for _, entry in pkg.style.themes do
		local c = entry.colors
		local x = entry.extra
		local tintAcc = lerp(c.accent, WHITE, 0.3)
		local tintSel = lerp(WHITE, c.accent, 0.35)
		if s.selected ~= nil then
			local plate = mul(s255(s.selected), tintSel)
			print(string.format("SEL  %-18s %-12s declared=%s art=%s d=%.3f | content %.2f onAccent %.2f",
				pkg.identity.id, entry.name, n255(x.controlSelected), n255(plate),
				math.sqrt((x.controlSelected.r-plate.r)^2+(x.controlSelected.g-plate.g)^2+(x.controlSelected.b-plate.b)^2),
				tokens.contrastRatio(c.content, plate), tokens.contrastRatio(c.onAccent, plate)))
		end
		if s.control ~= nil then
			local raw = s255(s.control)
			local plateAcc = mul(raw, tintAcc)
			local declAcc = mul(x.control, tintAcc)
			print(string.format("CTRL %-18s %-12s declared=%s art=%s d=%.3f | accentPlate art=%s onAccent %.2f content %.2f  ||  from declared: onAccent %.2f content %.2f",
				pkg.identity.id, entry.name, n255(x.control), n255(raw),
				math.sqrt((x.control.r-raw.r)^2+(x.control.g-raw.g)^2+(x.control.b-raw.b)^2),
				n255(plateAcc), tokens.contrastRatio(c.onAccent, plateAcc), tokens.contrastRatio(c.content, plateAcc),
				tokens.contrastRatio(c.onAccent, declAcc), tokens.contrastRatio(c.content, declAcc)))
		end
	end
end
