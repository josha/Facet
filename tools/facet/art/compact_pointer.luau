--!strict

local Common = require("./common")
local Raster = require("../lib/raster")

local Canvas = Raster.Canvas
local Field = Raster.Field
local Image = Raster.Image
local Resample = Raster.Resample

type Image = Raster.Image
type Field = Raster.Field
type Color = Raster.Color

local DIRECTORY = "assets/themes/compact-pointer"
local rgb = Common.rgb
local scale = Field.scale
local hairline = Common.hairline

local WHITE = rgb(255, 255, 255)
local PANEL_TOP = rgb(252, 252, 253)
local PANEL_BOT = rgb(242, 243, 246)
local BTN_TOP = rgb(255, 255, 255)
local BTN_BOT = rgb(236, 238, 243)
local HOV_TOP = rgb(252, 253, 255)
local HOV_BOT = rgb(228, 238, 252)
local HOV_LINE = rgb(142, 170, 214)
local PRS_TOP = rgb(210, 214, 222)
local PRS_BOT = rgb(228, 231, 238)
local LINE = rgb(178, 184, 195)
local LINE_SOFT = rgb(202, 207, 216)
local LINE_STRONG = rgb(150, 157, 171)
local DROP = rgb(120, 128, 143)
local WELL_TOP = rgb(238, 240, 245)
local WELL_BOT = rgb(255, 255, 255)
local TRACK_TOP = rgb(216, 220, 228)
local TRACK_BOT = rgb(236, 238, 243)
local ACCENT_TOP = rgb(90, 142, 226)
local ACCENT_BOT = rgb(52, 104, 200)
local ACCENT_LINE = rgb(40, 84, 168)

local function grad(width: number, height: number, entries: { { number | Color } }): Field
	return Field.vgrad(width, height, Common.stops(entries))
end

local function panel(): Image
	local w, h = 48, 48
	local c = Canvas.new(w, h)
	local box = { 0, 0, w - 1, h - 1 }
	local bm = Common.rrectMask(w, h, box, 6)
	Canvas.paint(c, grad(w, h, { { 0.0, PANEL_TOP }, { 1.0, PANEL_BOT } }), bm)
	Canvas.paint(c, LINE_SOFT, hairline(w, h, box, 6))
	Canvas.paint(c, WHITE, scale(hairline(w, h, { 1, 1, w - 2, h - 2 }, 5), 0.55))
	return Canvas.image(c)
end

local function button(state: string): Image
	local w, h = 32, 22
	local c = Canvas.new(w, h)
	local box = { 0, 0, w - 1, h - 2 }
	local bm = Common.rrectMask(w, h, box, 4)
	local top, bot, line
	if state == "default" then
		top, bot, line = BTN_TOP, BTN_BOT, LINE
	elseif state == "hover" then
		top, bot, line = HOV_TOP, HOV_BOT, HOV_LINE
	else
		top, bot, line = PRS_TOP, PRS_BOT, LINE_STRONG
	end
	if state ~= "pressed" then
		Canvas.paint(c, DROP, scale(Field.shift(bm, 0, 1), 0.16))
	end
	Canvas.paint(c, grad(w, h, { { 0.0, top }, { 1.0, bot } }), bm)
	if state == "pressed" then
		Canvas.paint(c, DROP, scale(Field.blur(Common.inset(bm, 2), 0.9), 0.35))
	else
		Canvas.paint(c, WHITE, scale(hairline(w, h, { 1, 1, w - 2, h - 3 }, 3), 0.55))
	end
	Canvas.paint(c, line, hairline(w, h, box, 4))
	return Canvas.image(c)
end

local function field(): Image
	local w, h = 32, 22
	local c = Canvas.new(w, h)
	local box = { 0, 0, w - 1, h - 1 }
	local bm = Common.rrectMask(w, h, box, 3)
	Canvas.paint(c, grad(w, h, { { 0.0, WELL_TOP }, { 0.30, WELL_BOT }, { 1.0, WHITE } }), bm)
	Canvas.paint(c, DROP, scale(Field.blur(Common.inset(bm, 2), 0.8), 0.30))
	Canvas.paint(c, LINE, hairline(w, h, box, 3))
	return Canvas.image(c)
end

local function barTrack(): Image
	local w, h = 48, 10
	local c = Canvas.new(w, h)
	local box = { 0, 0, w - 1, h - 1 }
	local bm = Common.rrectMask(w, h, box, 4)
	Canvas.paint(c, grad(w, h, { { 0.0, TRACK_TOP }, { 1.0, TRACK_BOT } }), bm)
	Canvas.paint(c, LINE_SOFT, hairline(w, h, box, 4))
	return Canvas.image(c)
end

local function uniformCenter(c: Raster.Canvas, border: number)
	local w = c.width
	local middle = w // 2
	for y = 0, c.height - 1 do
		for x = border, w - border - 1 do
			for channel = 1, 3 do
				Field.set(c.rgb, x, y, Field.at(c.rgb, middle, y, channel), channel)
			end
			Field.set(c.alpha, x, y, Field.at(c.alpha, middle, y))
		end
	end
end

local function barFill(): Image
	local w, h = 48, 8
	local c = Canvas.new(w, h)
	local box = { 0, 0, w - 1, h - 1 }
	local bm = Common.rrectMask(w, h, box, 3)
	Canvas.paint(c, grad(w, h, { { 0.0, ACCENT_TOP }, { 1.0, ACCENT_BOT } }), bm)
	Canvas.paint(c, WHITE, scale(hairline(w, h, { 0.5, 0.5, w - 1.5, h - 1.5 }, 2.5), 0.22))
	Canvas.paint(c, ACCENT_LINE, scale(hairline(w, h, box, 3), 0.55))
	uniformCenter(c, 3)
	return Canvas.image(c)
end

local function toggleTrack(state: string): Image
	local w, h = 36, 18
	local c = Canvas.new(w, h)
	local box = { 0, 0, w - 1, h - 1 }
	local bm = Common.rrectMask(w, h, box, 8)
	if state == "on" then
		Canvas.paint(c, grad(w, h, { { 0.0, ACCENT_TOP }, { 1.0, ACCENT_BOT } }), bm)
		Canvas.paint(c, WHITE, scale(hairline(w, h, { 1, 1, w - 2, h - 2 }, 7), 0.22))
		Canvas.paint(c, ACCENT_LINE, hairline(w, h, box, 8))
	else
		Canvas.paint(c, grad(w, h, { { 0.0, TRACK_TOP }, { 1.0, rgb(246, 247, 250) } }), bm)
		Canvas.paint(c, DROP, scale(Field.blur(Common.inset(bm, 2), 0.8), 0.28))
		Canvas.paint(c, LINE, hairline(w, h, box, 8))
	end
	return Canvas.image(c)
end

local function toggleKnob(): Image
	local s = 16
	local c = Canvas.new(s, s)
	local body = Common.mask(s, s)
	body:ellipse({ 0, 0, s - 2, s - 2 })
	local bm = body:arr()
	Canvas.paint(c, DROP, scale(Field.blur(Field.shift(bm, 0, 1), 0.9), 0.34))
	Canvas.paint(c, grad(s, s, { { 0.0, WHITE }, { 1.0, rgb(238, 240, 245) } }), bm)
	local inner = Common.mask(s, s)
	inner:ellipse({ 1, 1, s - 3, s - 3 })
	Canvas.paint(c, LINE, scale(Field.difference(bm, inner:arr()), 0.9))
	return Canvas.image(c)
end

local function stepperPlate(state: string): Image
	local w, h = 22, 22
	local c = Canvas.new(w, h)
	local box = { 0, 0, w - 1, h - 2 }
	local bm = Common.rrectMask(w, h, box, 4)
	if state == "default" then
		Canvas.paint(c, DROP, scale(Field.shift(bm, 0, 1), 0.16))
		Canvas.paint(c, grad(w, h, { { 0.0, BTN_TOP }, { 1.0, BTN_BOT } }), bm)
		Canvas.paint(c, WHITE, scale(hairline(w, h, { 1, 1, w - 2, h - 3 }, 3), 0.55))
		Canvas.paint(c, LINE, hairline(w, h, box, 4))
	else
		Canvas.paint(c, grad(w, h, { { 0.0, PRS_TOP }, { 1.0, PRS_BOT } }), bm)
		Canvas.paint(c, DROP, scale(Field.blur(Common.inset(bm, 2), 0.9), 0.38))
		Canvas.paint(c, LINE_STRONG, hairline(w, h, box, 4))
	end
	return Canvas.image(c)
end

local CompactPointer = {}

CompactPointer.name = "compact-pointer"
CompactPointer.summary = "compact-pointer theme package art"

function CompactPointer.generate(): { Common.Output }
	local items: { Common.Item } = {
		{
			name = "compact_panel.png",
			image = panel(),
			border = 12,
			previews = { { 180, 90 }, { 300, 160 }, { 420, 100 } },
		},
		{ name = "compact_button_default.png", image = button("default"), border = 8, previews = { { 90, 22 } } },
		{ name = "compact_button_hover.png", image = button("hover"), border = 8, previews = { { 90, 22 } } },
		{ name = "compact_button_pressed.png", image = button("pressed"), border = 8, previews = { { 90, 22 } } },
		{
			name = "compact_field.png",
			image = field(),
			border = 8,
			previews = { { 140, 22 }, { 240, 22 }, { 100, 44 } },
		},
		{
			name = "compact_bar_track.png",
			image = barTrack(),
			border = 4,
			previews = { { 90, 10 }, { 200, 10 }, { 320, 10 } },
		},
		{
			name = "compact_bar_fill.png",
			image = barFill(),
			border = 3,
			previews = { { 40, 8 }, { 140, 8 }, { 280, 8 } },
		},
		{
			name = "compact_toggle_track_off.png",
			image = toggleTrack("off"),
			border = 8,
			previews = { { 36, 18 }, { 48, 18 } },
		},
		{
			name = "compact_toggle_track_on.png",
			image = toggleTrack("on"),
			border = 8,
			previews = { { 36, 18 }, { 48, 18 } },
		},
		{ name = "compact_toggle_knob.png", image = toggleKnob() },
		{
			name = "compact_stepper_plate_default.png",
			image = stepperPlate("default"),
			border = 7,
			previews = { { 22, 22 }, { 34, 22 } },
		},
		{
			name = "compact_stepper_plate_pressed.png",
			image = stepperPlate("pressed"),
			border = 7,
			previews = { { 22, 22 }, { 34, 22 } },
		},
	}
	local outputs, by = Common.outputs(DIRECTORY, items)

	local sheet = Common.sheet("compact-pointer — 22px pointer scale, hairline borders, nine-slice stretch test")
	local LIGHT = { 223, 226, 233 }
	sheet:add("panel (48x48 b12) stretched", Common.stretch(by, { "compact_panel.png" }), LIGHT)
	sheet:add(
		"button default / hover / pressed @90x22 (32x22 b8 — same insets)",
		Common.stretch(by, { "compact_button_default.png", "compact_button_hover.png", "compact_button_pressed.png" }),
		LIGHT
	)
	sheet:add(
		"button default @ 48x22 / 220x22 / 90x44 — slice stress",
		Common.stretch(by, { "compact_button_default.png" }, { { 48, 22 }, { 220, 22 }, { 90, 44 } }),
		LIGHT
	)
	sheet:add("field (32x22 b8) stretched", Common.stretch(by, { "compact_field.png" }), LIGHT)
	sheet:add("bar track (48x10 b4) stretched", Common.stretch(by, { "compact_bar_track.png" }), LIGHT)
	sheet:add(
		"bar fill (48x8 b3) stretched — X-uniform centre",
		Common.stretch(by, { "compact_bar_fill.png" }),
		LIGHT
	)
	local track = by["compact_bar_track.png"].image
	local fill = by["compact_bar_fill.png"].image
	local assembled: { Image } = {}
	for _, pct in { 0.15, 0.55, 1.0 } do
		local bw = 260
		local comp = Image.new(bw, 10, 4)
		Image.alphaComposite(comp, Common.nineSlice(track, 4, bw, 10), 0, 0)
		local inner = bw - 2
		local full = Common.nineSlice(fill, 3, inner, 8)
		Image.alphaComposite(comp, Common.clipped(full, math.max(1, Raster.Numeric.trunc(inner * pct)), 8), 1, 1)
		table.insert(assembled, comp)
	end
	sheet:add("assembled progress: track + window-clipped fill (15/55/100%)", assembled, LIGHT)
	sheet:add(
		"toggle track off / on (36x18 b8) + knob (16x16)",
		Common.stretch(by, { "compact_toggle_track_off.png", "compact_toggle_track_on.png", "compact_toggle_knob.png" }),
		LIGHT
	)
	local switches: { Image } = {}
	for _, state in { "off", "on" } do
		local comp = Image.new(40, 18, 4)
		Image.alphaComposite(comp, Common.nineSlice(by[`compact_toggle_track_{state}.png`].image, 8, 40, 18), 0, 0)
		Image.alphaComposite(comp, by["compact_toggle_knob.png"].image, if state == "off" then 1 else 40 - 17, 1)
		table.insert(switches, comp)
	end
	sheet:add("assembled switch off / on (knob travel is solver-owned)", switches, LIGHT)
	sheet:add(
		"stepper plate default / pressed (22x22 b7)",
		Common.stretch(by, { "compact_stepper_plate_default.png", "compact_stepper_plate_pressed.png" }),
		LIGHT
	)
	local zoom: { Image } = {}
	for _, name in { "compact_button_default.png", "compact_button_pressed.png", "compact_field.png" } do
		local item = by[name]
		zoom[#zoom + 1] =
			Resample.resize(Common.nineSlice(item.image, item.border :: number, 90, 22), 270, 66, "nearest")
	end
	sheet:add("3x nearest zoom — button default / pressed / field (hairline check)", zoom, LIGHT)
	table.insert(outputs, { path = `{DIRECTORY}/source/preview/contact-sheet.png`, image = sheet:render() })
	return outputs
end

return CompactPointer :: Common.Target
