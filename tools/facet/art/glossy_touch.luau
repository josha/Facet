--!strict

local Common = require("./common")
local Raster = require("../lib/raster")

local Canvas = Raster.Canvas
local Field = Raster.Field
local Image = Raster.Image
local Numeric = Raster.Numeric

type Image = Raster.Image
type Field = Raster.Field
type Color = Raster.Color
type Canvas = Raster.Canvas

local DIRECTORY = "assets/themes/glossy-touch"
local rgb = Common.rgb
local scale = Field.scale

local WHITE = rgb(255, 255, 255)
local PANEL_TOP = rgb(250, 251, 253)
local PANEL_BOT = rgb(222, 227, 236)
local EDGE = rgb(132, 141, 158)
local EDGE_SOFT = rgb(172, 180, 196)
local SHADOW = rgb(52, 60, 76)
local WELL_TOP = rgb(198, 205, 217)
local WELL_BOT = rgb(252, 253, 255)

type Ramp = { Color }

local CHROME: Ramp = { rgb(253, 253, 255), rgb(224, 230, 240), rgb(186, 195, 212), rgb(233, 237, 244) }
local CHROME_DOWN: Ramp = { rgb(178, 187, 204), rgb(160, 170, 189), rgb(140, 151, 172), rgb(168, 178, 196) }
local BLUE: Ramp = { rgb(146, 202, 255), rgb(56, 142, 242), rgb(20, 92, 206), rgb(66, 152, 240) }
local BLUE_DEEP: Ramp = { rgb(66, 150, 238), rgb(32, 108, 216), rgb(14, 72, 172), rgb(34, 110, 208) }
local KNOB: Ramp = { rgb(255, 255, 255), rgb(246, 248, 252), rgb(206, 213, 226), rgb(238, 242, 248) }
local BLUE_GEL: Ramp = { rgb(150, 208, 255), rgb(48, 136, 240), rgb(14, 78, 190), rgb(48, 132, 226) }
local BLUE_MID = rgb(46, 128, 232)
local BLUE_BOT = rgb(20, 84, 188)

local function grad(width: number, height: number, entries: { { number | Color } }): Field
	return Field.vgrad(width, height, Common.stops(entries))
end

local function ring(width: number, height: number, box: { number }, radius: number): Field
	local mask = Common.mask(width, height)
	mask:rring(box, radius, 1)
	return mask:arr()
end

local function gel(c: Canvas, mask: Field, ramp: Ramp, split: number?, sheen: number?, rim: boolean?)
	local splitAt = split or 0.48
	local sheenAmount = sheen or 0.30
	local top, mid, low, bot = ramp[1], ramp[2], ramp[3], ramp[4]
	local w, h = mask.width, mask.height
	local e = 1.0 / math.max(2, h)
	Canvas.paint(c, grad(w, h, { { 0.0, top }, { splitAt - e, mid }, { splitAt, low }, { 1.0, bot } }), mask)
	if sheenAmount > 0 then
		local k = math.max(1, Numeric.roundHalfEven(h * splitAt))
		local ramp1 = Numeric.linspace(1.0, 0.12, k)
		local lens = Field.generate(w, h, 1, function(_x: number, y: number): number
			return if y < k then ramp1[y + 1] else 0.0
		end)
		Canvas.paint(c, WHITE, scale(Field.product(lens, mask), sheenAmount))
	end
	if rim ~= false then
		Canvas.paint(c, WHITE, scale(Common.inset(mask, 1), 0.7))
	end
end

local function uniformCenter(c: Canvas, border: number)
	local middle = c.width // 2
	for y = 0, c.height - 1 do
		for x = border, c.width - border - 1 do
			for channel = 1, 3 do
				Field.set(c.rgb, x, y, Field.at(c.rgb, middle, y, channel), channel)
			end
			Field.set(c.alpha, x, y, Field.at(c.alpha, middle, y))
		end
	end
end

local function panel(): Image
	local w, h = 96, 96
	local c = Canvas.new(w, h)
	local body = Common.mask(w, h)
	body:rrect({ 2, 2, w - 3, h - 4 }, 14)
	local bm = body:arr()
	Canvas.paint(c, SHADOW, scale(Field.blur(Field.shift(bm, 0, 2), 2.2), 0.28))
	Canvas.paint(c, grad(w, h, { { 0.0, PANEL_TOP }, { 1.0, PANEL_BOT } }), bm)
	Canvas.paint(c, EDGE_SOFT, scale(ring(w, h, { 2, 2, w - 3, h - 4 }, 14), 0.9))
	Canvas.paint(c, WHITE, scale(ring(w, h, { 3, 3, w - 4, h - 5 }, 13), 0.75))
	return Canvas.image(c)
end

local function button(state: string): Image
	local w, h = 64, 44
	local c = Canvas.new(w, h)
	local body = Common.mask(w, h)
	body:rrect({ 1, 1, w - 2, h - 3 }, 10)
	local bm = body:arr()
	if state == "default" then
		Canvas.paint(c, SHADOW, scale(Field.blur(Field.shift(bm, 0, 2), 1.8), 0.30))
		gel(c, bm, CHROME, nil, 0.34)
	else
		Canvas.paint(c, SHADOW, scale(Field.blur(bm, 1.2), 0.18))
		gel(c, bm, CHROME_DOWN, 0.34, 0.06, false)
		Canvas.paint(c, SHADOW, scale(Field.blur(Common.inset(bm, 3), 1.6), 0.55))
	end
	Canvas.paint(c, EDGE, scale(ring(w, h, { 1, 1, w - 2, h - 3 }, 10), if state == "default" then 0.95 else 1.0))
	return Canvas.image(c)
end

local function field(): Image
	local w, h = 64, 44
	local c = Canvas.new(w, h)
	local body = Common.mask(w, h)
	body:rrect({ 1, 1, w - 2, h - 2 }, 10)
	local bm = body:arr()
	Canvas.paint(c, grad(w, h, { { 0.0, WELL_TOP }, { 0.35, WELL_BOT }, { 1.0, WHITE } }), bm)
	Canvas.paint(c, SHADOW, scale(Field.blur(Common.inset(bm, 4), 2.0), 0.42))
	Canvas.paint(c, EDGE, scale(ring(w, h, { 1, 1, w - 2, h - 2 }, 10), 0.9))
	Canvas.paint(c, WHITE, scale(Common.inset(bm, -2), 0.6))
	return Canvas.image(c)
end

local function barTrack(): Image
	local w, h = 96, 24
	local c = Canvas.new(w, h)
	local body = Common.mask(w, h)
	body:rrect({ 0, 0, w - 1, h - 1 }, 10)
	local bm = body:arr()
	Canvas.paint(
		c,
		grad(w, h, {
			{ 0.0, rgb(138, 148, 166) },
			{ 0.30, rgb(180, 189, 205) },
			{ 0.72, rgb(219, 225, 236) },
			{ 1.0, rgb(245, 248, 252) },
		}),
		bm
	)
	Canvas.paint(c, SHADOW, scale(Field.blur(Common.inset(bm, 4), 1.5), 0.55))
	Canvas.paint(c, WHITE, scale(Common.inset(bm, -2), 0.72))
	Canvas.paint(c, EDGE, scale(ring(w, h, { 0, 0, w - 1, h - 1 }, 10), 1.0))
	return Canvas.image(c)
end

local function barFill(): Image
	local w, h = 96, 24
	local c = Canvas.new(w, h)
	local body = Common.mask(w, h)
	body:rrect({ 0, 0, w - 1, h - 1 }, 9)
	local bm = body:arr()
	gel(c, bm, BLUE_GEL, 0.44, 0.40)
	Canvas.paint(c, BLUE_BOT, scale(Common.inset(bm, -3), 0.45))
	Canvas.paint(c, BLUE_BOT, scale(ring(w, h, { 0, 0, w - 1, h - 1 }, 9), 0.85))
	uniformCenter(c, 8)
	return Canvas.image(c)
end

local function stripeTile(): Image
	local s = 24
	local c = Canvas.new(s, s)
	local period = 8
	local bright = Common.mask(s, s)
	local shade = Common.mask(s, s)
	for k = -4, 6 do
		local off = k * period
		bright:poly({ off, 0, off + 3, 0, off + 3 + s, s, off + s, s })
		shade:poly({ off - 2, 0, off, 0, off + s, s, off - 2 + s, s })
	end
	Canvas.paint(c, SHADOW, scale(shade:arr(), 0.30))
	Canvas.paint(c, WHITE, scale(bright:arr(), 0.55))
	return Canvas.image(c)
end

local function toggleTrack(state: string): Image
	local w, h = 72, 32
	local c = Canvas.new(w, h)
	local body = Common.mask(w, h)
	body:rrect({ 0, 0, w - 1, h - 1 }, 15)
	local bm = body:arr()
	if state == "on" then
		gel(c, bm, BLUE, nil, 0.22)
		Canvas.paint(c, BLUE_BOT, scale(ring(w, h, { 0, 0, w - 1, h - 1 }, 15), 0.7))
	else
		Canvas.paint(
			c,
			grad(w, h, { { 0.0, rgb(198, 204, 216) }, { 0.4, rgb(232, 236, 243) }, { 1.0, rgb(250, 251, 253) } }),
			bm
		)
		Canvas.paint(c, SHADOW, scale(Field.blur(Common.inset(bm, 4), 2.0), 0.45))
		Canvas.paint(c, EDGE_SOFT, scale(ring(w, h, { 0, 0, w - 1, h - 1 }, 15), 0.95))
	end
	return Canvas.image(c)
end

local function toggleKnob(): Image
	local s = 30
	local c = Canvas.new(s, s)
	local body = Common.mask(s, s)
	body:ellipse({ 1, 0, s - 2, s - 3 })
	local bm = body:arr()
	Canvas.paint(c, SHADOW, scale(Field.blur(Field.shift(bm, 0, 2), 1.8), 0.42))
	gel(c, bm, KNOB, nil, 0.30)
	local outer = Common.mask(s, s)
	outer:ellipse({ 1, 0, s - 2, s - 3 })
	local inner = Common.mask(s, s)
	inner:ellipse({ 2, 1, s - 3, s - 4 })
	Canvas.paint(c, EDGE, scale(Field.difference(outer:arr(), inner:arr()), 0.85))
	return Canvas.image(c)
end

local function stepperPlate(state: string): Image
	local w, h = 44, 44
	local c = Canvas.new(w, h)
	local body = Common.mask(w, h)
	body:rrect({ 1, 1, w - 2, h - 3 }, 9)
	local bm = body:arr()
	if state == "default" then
		Canvas.paint(c, SHADOW, scale(Field.blur(Field.shift(bm, 0, 2), 1.6), 0.26))
		gel(c, bm, CHROME, nil, 0.34)
	else
		gel(c, bm, BLUE_DEEP, 0.34, 0.08, false)
		Canvas.paint(c, SHADOW, scale(Field.blur(Common.inset(bm, 3), 1.6), 0.45))
	end
	Canvas.paint(c, if state == "default" then EDGE else BLUE_BOT, scale(ring(w, h, { 1, 1, w - 2, h - 3 }, 9), 0.95))
	return Canvas.image(c)
end

local function selection(state: string): Image
	local w, h = 72, 44
	local c = Canvas.new(w, h)
	local body = Common.mask(w, h)
	body:rrect({ 2, 2, w - 3, h - 3 }, 12)
	local bm = body:arr()
	if state == "default" then
		Canvas.paint(c, grad(w, h, { { 0.0, rgb(252, 253, 255) }, { 1.0, rgb(238, 241, 246) } }), scale(bm, 0.96))
		Canvas.paint(c, EDGE_SOFT, scale(ring(w, h, { 2, 2, w - 3, h - 3 }, 12), 0.8))
		return Canvas.image(c)
	end
	Canvas.paint(c, BLUE_MID, scale(Field.blur(bm, 4.0), 0.55))
	gel(c, bm, BLUE, nil, 0.26)
	Canvas.paint(c, BLUE_BOT, scale(ring(w, h, { 2, 2, w - 3, h - 3 }, 12), 0.85))
	Canvas.paint(c, WHITE, scale(ring(w, h, { 4, 4, w - 5, h - 5 }, 10), 0.55))
	return Canvas.image(c)
end

local GlossyTouch = {}

GlossyTouch.name = "glossy-touch"
GlossyTouch.summary = "glossy-touch theme package art"

function GlossyTouch.generate(): { Common.Output }
	local items: { Common.Item } = {
		{
			name = "glossy_panel.png",
			image = panel(),
			border = 28,
			previews = { { 220, 120 }, { 360, 200 }, { 520, 132 } },
		},
		{ name = "glossy_button_default.png", image = button("default"), border = 16, previews = { { 140, 44 } } },
		{ name = "glossy_button_pressed.png", image = button("pressed"), border = 16, previews = { { 140, 44 } } },
		{
			name = "glossy_field.png",
			image = field(),
			border = 16,
			previews = { { 180, 44 }, { 300, 44 }, { 140, 72 } },
		},
		{
			name = "glossy_bar_track.png",
			image = barTrack(),
			border = 10,
			previews = { { 120, 24 }, { 260, 24 }, { 400, 24 } },
		},
		{
			name = "glossy_bar_fill.png",
			image = barFill(),
			border = 8,
			previews = { { 60, 24 }, { 180, 24 }, { 340, 24 } },
		},
		{ name = "glossy_stripe_tile.png", image = stripeTile() },
		{
			name = "glossy_toggle_track_off.png",
			image = toggleTrack("off"),
			border = 14,
			previews = { { 72, 32 }, { 96, 32 } },
		},
		{
			name = "glossy_toggle_track_on.png",
			image = toggleTrack("on"),
			border = 14,
			previews = { { 72, 32 }, { 96, 32 } },
		},
		{ name = "glossy_toggle_knob.png", image = toggleKnob() },
		{
			name = "glossy_stepper_plate_default.png",
			image = stepperPlate("default"),
			border = 14,
			previews = { { 44, 44 }, { 72, 44 } },
		},
		{
			name = "glossy_stepper_plate_pressed.png",
			image = stepperPlate("pressed"),
			border = 14,
			previews = { { 44, 44 }, { 72, 44 } },
		},
		{
			name = "glossy_selection_default.png",
			image = selection("default"),
			border = 18,
			previews = { { 220, 44 } },
		},
		{
			name = "glossy_selection_selected.png",
			image = selection("selected"),
			border = 18,
			previews = { { 220, 44 } },
		},
	}
	local outputs, by = Common.outputs(DIRECTORY, items)

	local sheet = Common.sheet("glossy-touch — 44px touch scale, nine-slice stretch test")
	local function row(label: string, names: { string }, sizes: { { number } }?, backdrop: { number }?)
		sheet:add(label, Common.stretch(by, names, sizes), backdrop)
	end
	row("panel (96x96 b28) stretched", { "glossy_panel.png" })
	row(
		"button default / pressed @140x44 (64x44 b16 — same insets, different art)",
		{ "glossy_button_default.png", "glossy_button_pressed.png" }
	)
	row(
		"button default @ 88x44 / 300x44 / 140x88 — slice stress",
		{ "glossy_button_default.png" },
		{ { 88, 44 }, { 300, 44 }, { 140, 88 } }
	)
	row("field (64x44 b16) stretched", { "glossy_field.png" })
	row("bar track (96x24 b10) stretched", { "glossy_bar_track.png" })
	row("bar fill (96x24 b8) stretched — X-uniform centre", { "glossy_bar_fill.png" })
	local track = by["glossy_bar_track.png"].image
	local fill = by["glossy_bar_fill.png"].image
	local stripe = by["glossy_stripe_tile.png"].image
	local striped: { Image } = {}
	for _, pct in { 0.2, 0.6, 1.0 } do
		local bw, bh = 320, 24
		local comp = Image.new(bw, bh, 4)
		local stretched = Common.nineSlice(track, 10, bw, bh)
		local layer = Image.new(bw, bh, 4)
		for tx = 0, bw - 1, 24 do
			for ty = 0, bh - 1, 24 do
				Image.alphaComposite(
					layer,
					Image.crop(stripe, 0, 0, math.min(24, bw - tx), math.min(24, bh - ty)),
					tx,
					ty
				)
			end
		end
		local masked = Image.composite(layer, Image.new(bw, bh, 4), Image.band(stretched, 4))
		Image.alphaComposite(stretched, masked, 0, 0)
		Image.alphaComposite(comp, stretched, 0, 0)
		local full = Common.nineSlice(fill, 8, bw, bh)
		Image.alphaComposite(comp, Common.clipped(full, math.max(1, Numeric.trunc(bw * pct)), bh), 0, 0)
		table.insert(striped, comp)
	end
	sheet:add("striped progress AS SHIPPED: striped trough + gel fill over it, clipped 20/60/100%", striped)
	local tiled = Image.new(240, 72, 4)
	for yy = 0, 2 do
		for xx = 0, 9 do
			Image.alphaComposite(tiled, stripe, xx * 24, yy * 24)
		end
	end
	sheet:add("stripe tile 24x24 — TILED 10x3 on transparency (seam check)", { tiled }, { 46, 128, 232 })
	row(
		"toggle track off / on (72x32 b14) + knob (30x30)",
		{ "glossy_toggle_track_off.png", "glossy_toggle_track_on.png", "glossy_toggle_knob.png" }
	)
	local switches: { Image } = {}
	for _, state in { "off", "on" } do
		local comp = Image.new(84, 32, 4)
		Image.alphaComposite(comp, Common.nineSlice(by[`glossy_toggle_track_{state}.png`].image, 14, 84, 32), 0, 0)
		Image.alphaComposite(comp, by["glossy_toggle_knob.png"].image, if state == "off" then 1 else 84 - 31, 1)
		table.insert(switches, comp)
	end
	sheet:add("assembled switch off / on (knob travel is solver-owned)", switches)
	row(
		"stepper plate default / pressed (44x44 b14)",
		{ "glossy_stepper_plate_default.png", "glossy_stepper_plate_pressed.png" }
	)
	row(
		"selection default / selected @220x44 (72x44 b18) — glow plate",
		{ "glossy_selection_default.png", "glossy_selection_selected.png" }
	)
	table.insert(outputs, { path = `{DIRECTORY}/source/preview/contact-sheet.png`, image = sheet:render() })
	return outputs
end

return GlossyTouch :: Common.Target
