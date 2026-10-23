--!strict

local Common = require("./common")
local Raster = require("../lib/raster")

local Draw = Raster.Draw
local Image = Raster.Image
local Numeric = Raster.Numeric
local Resample = Raster.Resample

type Image = Raster.Image
type Rgb = { number }

local DIRECTORY = "assets/themes/pixel-quest"
local PIXEL_UNIT = 4

local INK: Rgb = { 0x16, 0x12, 0x1F }
local SHADE: Rgb = { 0x3A, 0x2C, 0x4F }
local WOOD_D: Rgb = { 0x6B, 0x43, 0x26 }
local WOOD: Rgb = { 0xA8, 0x72, 0x2F }
local TAN: Rgb = { 0xD7, 0xA8, 0x60 }
local CREAM: Rgb = { 0xF4, 0xE6, 0xC0 }
local RED_D: Rgb = { 0x7A, 0x1F, 0x22 }
local RED: Rgb = { 0xC8, 0x40, 0x2F }
local RED_L: Rgb = { 0xE8, 0x73, 0x5A }
local GRN_D: Rgb = { 0x2F, 0x6B, 0x2A }
local GRN: Rgb = { 0x4F, 0xA8, 0x3F }
local GRN_L: Rgb = { 0x8E, 0xDE, 0x6A }
local GLYPH: Rgb = { 0xF0, 0xF0, 0xF0 }
local CLEAR: Rgb = {}

local PALETTE: { Rgb } = { INK, SHADE, WOOD_D, WOOD, TAN, CREAM, RED_D, RED, RED_L, GRN_D, GRN, GRN_L }

type Grid = {
	width: number,
	height: number,
	image: Image,
	set: (self: Grid, x: number, y: number, color: Rgb) -> (),
	rect: (self: Grid, x0: number, y0: number, x1: number, y1: number, color: Rgb) -> (),
	outline: (self: Grid, x0: number, y0: number, x1: number, y1: number, color: Rgb) -> (),
	hline: (self: Grid, x0: number, x1: number, y: number, color: Rgb) -> (),
	vline: (self: Grid, x: number, y0: number, y1: number, color: Rgb) -> (),
	bitmap: (self: Grid, rows: { string }, mapping: { [string]: Rgb }) -> (),
	render: (self: Grid) -> Image,
}

local function grid(width: number, height: number): Grid
	local self = { width = width, height = height, image = Image.new(width, height, 4) }

	function self.set(this: Grid, x: number, y: number, color: Rgb)
		if x >= 0 and x < this.width and y >= 0 and y < this.height then
			local offset = (y * this.width + x) * 4
			if #color == 0 then
				buffer.writeu32(this.image.data, offset, 0)
			else
				buffer.writeu8(this.image.data, offset, color[1])
				buffer.writeu8(this.image.data, offset + 1, color[2])
				buffer.writeu8(this.image.data, offset + 2, color[3])
				buffer.writeu8(this.image.data, offset + 3, 255)
			end
		end
	end

	function self.rect(this: Grid, x0: number, y0: number, x1: number, y1: number, color: Rgb)
		for y = y0, y1 do
			for x = x0, x1 do
				this:set(x, y, color)
			end
		end
	end

	function self.outline(this: Grid, x0: number, y0: number, x1: number, y1: number, color: Rgb)
		for x = x0, x1 do
			this:set(x, y0, color)
			this:set(x, y1, color)
		end
		for y = y0, y1 do
			this:set(x0, y, color)
			this:set(x1, y, color)
		end
	end

	function self.hline(this: Grid, x0: number, x1: number, y: number, color: Rgb)
		for x = x0, x1 do
			this:set(x, y, color)
		end
	end

	function self.vline(this: Grid, x: number, y0: number, y1: number, color: Rgb)
		for y = y0, y1 do
			this:set(x, y, color)
		end
	end

	function self.bitmap(this: Grid, rows: { string }, mapping: { [string]: Rgb })
		for y, line in rows do
			for x = 1, #line do
				local color = mapping[string.sub(line, x, x)]
				if color ~= nil then
					this:set(x - 1, y - 1, color)
				end
			end
		end
	end

	function self.render(this: Grid): Image
		return Resample.resize(this.image, this.width * PIXEL_UNIT, this.height * PIXEL_UNIT, "nearest")
	end

	return self :: Grid
end

local function dilate(rows: { string }): { { number } }
	local h, w = #rows, #rows[1]
	local seen: { [number]: boolean } = {}
	local out: { { number } } = {}
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			if string.sub(rows[y + 1], x + 1, x + 1) == "#" then
				for dy = -1, 1 do
					for dx = -1, 1 do
						local nx, ny = x + dx, y + dy
						if
							nx >= 0
							and nx < w
							and ny >= 0
							and ny < h
							and string.sub(rows[ny + 1], nx + 1, nx + 1) ~= "#"
						then
							local key = ny * w + nx
							if not seen[key] then
								seen[key] = true
								table.insert(out, { nx, ny })
							end
						end
					end
				end
			end
		end
	end
	return out
end

local function plate(state: string): Grid
	local p = grid(9, 9)
	if state == "default" then
		p:rect(0, 0, 8, 8, WOOD)
		p:outline(0, 0, 8, 8, INK)
		p:hline(1, 7, 1, TAN)
		p:vline(1, 1, 7, TAN)
		p:hline(1, 7, 7, WOOD_D)
		p:vline(7, 1, 7, WOOD_D)
		for _, rivet in { { 2, 2 }, { 6, 2 }, { 2, 6 }, { 6, 6 } } do
			p:set(rivet[1], rivet[2], TAN)
		end
	else
		p:rect(0, 0, 8, 8, TAN)
		p:outline(0, 0, 8, 8, INK)
		p:outline(1, 1, 7, 7, CREAM)
		p:hline(2, 6, 2, CREAM)
		p:vline(2, 2, 6, CREAM)
		p:hline(2, 6, 6, WOOD)
		p:vline(6, 2, 6, WOOD)
		for _, rivet in { { 2, 2 }, { 6, 2 }, { 2, 6 }, { 6, 6 } } do
			p:set(rivet[1], rivet[2], RED)
		end
		for _, corner in { { 0, 0 }, { 8, 0 }, { 0, 8 }, { 8, 8 } } do
			p:set(corner[1], corner[2], CLEAR)
		end
	end
	return p
end

local function plateOrnament(): Grid
	local p = grid(6, 6)
	p:bitmap({
		"..##..",
		".#LL#.",
		"#LRRL#",
		"#RRRD#",
		".#DD#.",
		"..##..",
	}, { ["#"] = INK, L = RED_L, R = RED, D = RED_D })
	return p
end

local function panel(): Grid
	local p = grid(13, 13)
	p:rect(0, 0, 12, 12, SHADE)
	p:outline(0, 0, 12, 12, INK)
	p:outline(1, 1, 11, 11, TAN)
	p:outline(2, 2, 10, 10, WOOD)
	p:outline(3, 3, 9, 9, WOOD_D)
	p:outline(4, 4, 8, 8, INK)
	p:rect(5, 5, 7, 7, SHADE)
	for _, rivet in { { 2, 2 }, { 10, 2 }, { 2, 10 }, { 10, 10 } } do
		p:set(rivet[1], rivet[2], CREAM)
	end
	return p
end

local function fieldPlate(): Grid
	local p = grid(9, 9)
	p:rect(0, 0, 8, 8, SHADE)
	p:outline(0, 0, 8, 8, INK)
	p:hline(1, 7, 1, WOOD_D)
	p:vline(1, 1, 7, WOOD_D)
	p:hline(1, 7, 7, TAN)
	p:vline(7, 1, 7, TAN)
	p:rect(2, 2, 6, 6, SHADE)
	return p
end

local function barTrack(): Grid
	local p = grid(5, 8)
	for y, color in { INK, WOOD_D, SHADE, SHADE, SHADE, SHADE, TAN, INK } do
		p:hline(0, 4, y - 1, color)
	end
	p:vline(0, 0, 7, INK)
	p:vline(4, 0, 7, INK)
	return p
end

local function barFill(): Grid
	local p = grid(3, 4)
	for y, color in { RED_L, RED, RED, RED_D } do
		p:hline(0, 2, y - 1, color)
	end
	return p
end

local function barCapHeart(): Grid
	local body = {
		"..........",
		"..##..##..",
		".########.",
		".########.",
		".########.",
		"..######..",
		"...####...",
		"....##....",
		"..........",
		"..........",
	}
	local p = grid(10, 10)
	for _, cell in dilate(body) do
		p:set(cell[1], cell[2], INK)
	end
	for y, line in body do
		for x = 1, #line do
			if string.sub(line, x, x) == "#" then
				local row = y - 1
				local color = if row <= 2 then RED_L elseif row >= 6 then RED_D else RED
				p:set(x - 1, row, color)
			end
		end
	end
	p:set(2, 2, CREAM)
	p:set(3, 2, CREAM)
	return p
end

local function toggleTrack(state: string): Grid
	local p = grid(7, 8)
	local rows: { Rgb } = if state == "on"
		then { INK, GRN_L, GRN, GRN, GRN, GRN, GRN_D, INK }
		else { INK, INK, SHADE, SHADE, SHADE, SHADE, WOOD_D, INK }
	for y, color in rows do
		p:hline(0, 6, y - 1, color)
	end
	p:vline(0, 0, 7, INK)
	p:vline(6, 0, 7, INK)
	for _, corner in { { 0, 0 }, { 6, 0 }, { 0, 7 }, { 6, 7 } } do
		p:set(corner[1], corner[2], CLEAR)
	end
	return p
end

local function toggleKnob(): Grid
	local p = grid(6, 6)
	p:rect(0, 0, 5, 5, CREAM)
	p:outline(0, 0, 5, 5, INK)
	p:hline(1, 4, 4, TAN)
	p:vline(4, 1, 4, TAN)
	p:set(1, 1, CREAM)
	for _, corner in { { 0, 0 }, { 5, 0 }, { 0, 5 }, { 5, 5 } } do
		p:set(corner[1], corner[2], CLEAR)
	end
	return p
end

local function stepperPlate(state: string): Grid
	local p = grid(7, 7)
	if state == "default" then
		p:rect(0, 0, 6, 6, WOOD)
		p:outline(0, 0, 6, 6, INK)
		p:hline(1, 5, 1, TAN)
		p:vline(1, 1, 5, TAN)
		p:hline(1, 5, 5, WOOD_D)
		p:vline(5, 1, 5, WOOD_D)
		p:rect(2, 2, 4, 4, WOOD)
	else
		p:rect(0, 0, 6, 6, WOOD_D)
		p:outline(0, 0, 6, 6, INK)
		p:hline(1, 5, 1, SHADE)
		p:vline(1, 1, 5, SHADE)
		p:hline(1, 5, 5, WOOD)
		p:vline(5, 1, 5, WOOD)
		p:rect(2, 2, 4, 4, WOOD_D)
	end
	return p
end

local ICON_BITMAPS: { [string]: { string } } = {
	chevron_right = { ".##.....", "..##....", "...##...", "....##..", "....##..", "...##...", "..##....", ".##....." },
	chevron_down = { "........", "#......#", "##....##", ".##..##.", "..####..", "...##...", "........", "........" },
	plus = { "........", "...##...", "...##...", ".######.", ".######.", "...##...", "...##...", "........" },
	minus = { "........", "........", "........", ".######.", ".######.", "........", "........", "........" },
	check = { "........", "......##", ".....##.", "#...##..", "##.##...", ".####...", "..##....", "........" },
	cross = { "##....##", ".##..##.", "..####..", "...##...", "...##...", "..####..", ".##..##.", "##....##" },
	chevron_left = { ".....##.", "....##..", "...##...", "..##....", "..##....", "...##...", "....##..", ".....##." },
	chevron_up = { "........", "........", "...##...", "..####..", ".##..##.", "##....##", "#......#", "........" },
	chevron_up_down = {
		"...##...",
		"..####..",
		".##..##.",
		"........",
		"........",
		".##..##.",
		"..####..",
		"...##...",
	},
	more = { "........", "........", "........", "##.##.##", "##.##.##", "........", "........", "........" },
	edit = { "......##", ".....###", "....###.", "...###..", "..###...", ".###....", "##......", "#......." },
	radio_off = { "..####..", ".##..##.", "##....##", "#......#", "#......#", "##....##", ".##..##.", "..####.." },
	radio_on = { "..####..", ".##..##.", "##....##", "#..##..#", "#..##..#", "##....##", ".##..##.", "..####.." },
	check_off = { "########", "#......#", "#......#", "#......#", "#......#", "#......#", "#......#", "########" },
}

local ICON_ORDER = {
	"chevron_right",
	"chevron_down",
	"plus",
	"minus",
	"check",
	"cross",
	"chevron_left",
	"chevron_up",
	"chevron_up_down",
	"more",
	"edit",
	"radio_off",
	"radio_on",
	"check_off",
}

local PixelQuest = {}

PixelQuest.name = "pixel-quest"
PixelQuest.summary = "pixel-quest theme package art"

function PixelQuest.generate(): { Common.Output }
	local u = PIXEL_UNIT
	local items: { Common.Item } = {
		{ name = "pixel_panel_tail.png", image = Common.panelTail(panel():render(), 64, 24, 24, u) },
		{
			name = "pixel_plate_default.png",
			image = plate("default"):render(),
			border = 4 * u,
			previews = { { 160, 48 }, { 240, 48 }, { 128, 96 } },
		},
		{
			name = "pixel_plate_selected.png",
			image = plate("selected"):render(),
			border = 4 * u,
			previews = { { 160, 48 }, { 240, 48 }, { 128, 96 } },
		},
		{ name = "pixel_plate_ornament.png", image = plateOrnament():render() },
		{ name = "pixel_blank.png", image = grid(6, 6):render() },
		{
			name = "pixel_panel.png",
			image = panel():render(),
			border = 6 * u,
			previews = { { 160, 120 }, { 280, 176 }, { 400, 128 } },
		},
		{
			name = "pixel_field.png",
			image = fieldPlate():render(),
			border = 4 * u,
			previews = { { 160, 48 }, { 280, 48 }, { 128, 96 } },
		},
		{
			name = "pixel_bar_track.png",
			image = barTrack():render(),
			border = 2 * u,
			previews = { { 120, 32 }, { 240, 32 }, { 360, 32 } },
		},
		{
			name = "pixel_bar_fill.png",
			image = barFill():render(),
			border = 1 * u,
			previews = { { 48, 16 }, { 160, 16 }, { 320, 16 } },
		},
		{ name = "pixel_bar_cap_heart.png", image = barCapHeart():render() },
		{
			name = "pixel_toggle_track_off.png",
			image = toggleTrack("off"):render(),
			border = 3 * u,
			previews = { { 64, 32 }, { 96, 32 } },
		},
		{
			name = "pixel_toggle_track_on.png",
			image = toggleTrack("on"):render(),
			border = 3 * u,
			previews = { { 64, 32 }, { 96, 32 } },
		},
		{ name = "pixel_toggle_knob.png", image = toggleKnob():render() },
		{
			name = "pixel_stepper_plate_default.png",
			image = stepperPlate("default"):render(),
			border = 3 * u,
			previews = { { 32, 32 }, { 48, 32 } },
		},
		{
			name = "pixel_stepper_plate_pressed.png",
			image = stepperPlate("pressed"):render(),
			border = 3 * u,
			previews = { { 32, 32 }, { 48, 32 } },
		},
	}
	for _, name in ICON_ORDER do
		local icon = grid(8, 8)
		icon:bitmap(ICON_BITMAPS[name], { ["#"] = GLYPH })
		table.insert(items, { name = `pixel_icon_{name}.png`, image = icon:render() })
	end
	local outputs, by = Common.outputs(DIRECTORY, items)

	local sheet = Common.sheet("pixel-quest — pixelUnit 4, nine-slice stretch test (NEAREST everywhere)")
	local function row(label: string, names: { string })
		sheet:add(label, Common.stretch(by, names, nil, "nearest"))
	end
	row("plate default @160x48 / 240x48 / 128x96 (36x36 b16)", { "pixel_plate_default.png" })
	row("plate SELECTED — different construction, same 4dp insets", { "pixel_plate_selected.png" })
	local ornament = by["pixel_plate_ornament.png"].image
	local composed = Image.new(240, 48, 4)
	Image.alphaComposite(composed, Common.nineSlice(by["pixel_plate_selected.png"].image, 16, 240, 48, "nearest"), 0, 0)
	for _, position in { { -4, -4 }, { 240 - 20, -4 }, { -4, 48 - 20 }, { 240 - 20, 48 - 20 } } do
		Image.alphaComposite(composed, ornament, position[1], position[2])
	end
	sheet:add("selected plate + ornament as a `corners` layer (240x48)", { composed })
	row("panel (52x52 b24) stretched", { "pixel_panel.png" })
	row("field (36x36 b16) stretched", { "pixel_field.png" })
	row("bar track (20x32 b8) stretched", { "pixel_bar_track.png" })
	row("bar fill (12x16 b4) stretched — uniform along X", { "pixel_bar_fill.png" })
	local track = by["pixel_bar_track.png"].image
	local fill = by["pixel_bar_fill.png"].image
	local heart = by["pixel_bar_cap_heart.png"].image
	local assembled: { Image } = {}
	for _, pct in { 0.12, 0.5, 1.0 } do
		local bw, bh = 320, 40
		local comp = Image.new(bw, bh, 4)
		Image.alphaComposite(comp, Common.nineSlice(track, 8, bw - 40, 32, "nearest"), 36, 4)
		local inner = bw - 40 - 16
		local full = Common.nineSlice(fill, 4, inner, 16, "nearest")
		local shown = math.max(4, Numeric.trunc(inner * pct) // 4 * 4)
		Image.alphaComposite(comp, Common.clipped(full, shown, 16), 44, 12)
		Image.alphaComposite(comp, heart, 0, 0)
		table.insert(assembled, comp)
	end
	sheet:add("assembled HP bar: heart cap + track + window-clipped fill (12/50/100%)", assembled)
	row(
		"toggle track off / on (28x32 b12) + knob (24x24)",
		{ "pixel_toggle_track_off.png", "pixel_toggle_track_on.png", "pixel_toggle_knob.png" }
	)
	row(
		"stepper plate default / pressed (28x28 b12)",
		{ "pixel_stepper_plate_default.png", "pixel_stepper_plate_pressed.png" }
	)
	local icons: { Image } = {}
	for _, name in ICON_ORDER do
		table.insert(icons, by[`pixel_icon_{name}.png`].image)
	end
	sheet:add("icons 32x32 near-white (the framework's whole icon vocabulary)", icons)
	local strip = Image.new(#PALETTE * 40, 40, 4, { 0, 0, 0, 255 })
	for index, color in PALETTE do
		local x = (index - 1) * 40
		Draw.rectangle(strip, { x, 0, x + 39, 39 }, { color[1], color[2], color[3], 255 })
	end
	sheet:add("palette: INK SHADE WOOD_D WOOD TAN CREAM | RED_D RED RED_L | GRN_D GRN GRN_L", { strip })
	table.insert(outputs, { path = `{DIRECTORY}/source/preview/contact-sheet.png`, image = sheet:render() })
	return outputs
end

return PixelQuest :: Common.Target
