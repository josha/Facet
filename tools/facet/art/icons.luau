--!strict

local Common = require("./common")
local Raster = require("../lib/raster")

local Draw = Raster.Draw
local Image = Raster.Image
local Numeric = Raster.Numeric
local Resample = Raster.Resample

type Image = Raster.Image

local SIZE = 128
local SS = 8
local INK = { 240, 240, 242, 255 }
local CLEAR = { 0, 0, 0, 0 }
local STROKE = 13
local DIRECTORY = "assets/icons"

local function canvas(): Image
	return Image.new(SIZE * SS, SIZE * SS, 4)
end

local function dot(image: Image, x: number, y: number, r: number)
	local cx, cy, cr = x * SS, y * SS, r * SS
	Draw.ellipse(image, { cx - cr, cy - cr, cx + cr, cy + cr }, INK)
end

local function stroke(image: Image, points: { number }, width: number?)
	local w = width or STROKE
	local scaled = table.create(#points, 0)
	for index, value in points do
		scaled[index] = value * SS
	end
	Draw.line(image, scaled, INK, Numeric.trunc(w * SS))
	for index = 1, #points, 2 do
		dot(image, points[index], points[index + 1], w / 2)
	end
end

local function poly(image: Image, points: { number })
	local scaled = table.create(#points, 0)
	for index, value in points do
		scaled[index] = value * SS
	end
	Draw.polygon(image, scaled, INK)
end

local function ring(image: Image, cx: number, cy: number, r: number, width: number?)
	local w = width or STROKE
	Draw.ellipse(image, { (cx - r) * SS, (cy - r) * SS, (cx + r) * SS, (cy + r) * SS }, nil, INK, Numeric.trunc(w * SS))
end

local function outlineBox(image: Image, box: { number }, radius: number, width: number)
	Draw.roundedRectangle(
		image,
		{ box[1] * SS, box[2] * SS, box[3] * SS, box[4] * SS },
		radius * SS,
		nil,
		INK,
		width * SS
	)
end

local CHEVRONS: { [string]: { number } } = {
	left = { 80, 26, 46, 64, 80, 102 },
	right = { 48, 26, 82, 64, 48, 102 },
	up = { 26, 80, 64, 46, 102, 80 },
	down = { 26, 48, 64, 82, 102, 48 },
}

local function chevron(direction: string): () -> Image
	return function(): Image
		local image = canvas()
		stroke(image, CHEVRONS[direction])
		return image
	end
end

local function check(): Image
	local image = canvas()
	stroke(image, { 28, 68, 52, 92, 100, 38 })
	return image
end

local function thumbUp(): Image
	local image = canvas()
	Draw.roundedRectangle(image, { 14 * SS, 58 * SS, 34 * SS, 110 * SS }, 6 * SS, INK)
	Draw.roundedRectangle(image, { 40 * SS, 56 * SS, 112 * SS, 110 * SS }, 14 * SS, INK)
	for _, gy in { 70, 83, 96 } do
		Draw.rectangle(image, { 80 * SS, (gy - 2.5) * SS, 112 * SS, (gy + 2.5) * SS }, CLEAR)
	end
	stroke(image, { 58, 64, 67, 32 }, 26)
	return image
end

local ICONS: { { name: string, draw: () -> Image } } = {
	{
		name = "facet_icon_view_grid",
		draw = function(): Image
			local image = canvas()
			for _, x in { 20, 72 } do
				for _, y in { 20, 72 } do
					outlineBox(image, { x, y, x + 36, y + 36 }, 6, 8)
				end
			end
			return image
		end,
	},
	{
		name = "facet_icon_view_list",
		draw = function(): Image
			local image = canvas()
			for _, y in { 28, 64, 100 } do
				dot(image, 24, y, 7)
				stroke(image, { 48, y, 106, y }, 8)
			end
			return image
		end,
	},
	{
		name = "facet_icon_view_table",
		draw = function(): Image
			local image = canvas()
			outlineBox(image, { 18, 20, 110, 108 }, 6, 8)
			stroke(image, { 52, 24, 52, 104 }, 7)
			for _, y in { 48, 78 } do
				stroke(image, { 22, y, 106, y }, 7)
			end
			return image
		end,
	},
	{ name = "facet_icon_chevron_left", draw = chevron("left") },
	{ name = "facet_icon_chevron_right", draw = chevron("right") },
	{ name = "facet_icon_chevron_up", draw = chevron("up") },
	{ name = "facet_icon_chevron_down", draw = chevron("down") },
	{
		name = "facet_icon_chevron_up_down",
		draw = function(): Image
			local image = canvas()
			stroke(image, { 36, 52, 64, 26, 92, 52 })
			stroke(image, { 36, 76, 64, 102, 92, 76 })
			return image
		end,
	},
	{ name = "facet_icon_check", draw = check },
	{
		name = "facet_icon_close",
		draw = function(): Image
			local image = canvas()
			stroke(image, { 34, 34, 94, 94 })
			stroke(image, { 94, 34, 34, 94 })
			return image
		end,
	},
	{
		name = "facet_icon_plus",
		draw = function(): Image
			local image = canvas()
			stroke(image, { 64, 28, 64, 100 })
			stroke(image, { 28, 64, 100, 64 })
			return image
		end,
	},
	{
		name = "facet_icon_minus",
		draw = function(): Image
			local image = canvas()
			stroke(image, { 28, 64, 100, 64 })
			return image
		end,
	},
	{
		name = "facet_icon_menu",
		draw = function(): Image
			local image = canvas()
			for _, y in { 40, 64, 88 } do
				stroke(image, { 28, y, 100, y })
			end
			return image
		end,
	},
	{
		name = "facet_icon_more",
		draw = function(): Image
			local image = canvas()
			for _, x in { 34, 64, 94 } do
				dot(image, x, 64, STROKE / 2 + 1)
			end
			return image
		end,
	},
	{
		name = "facet_icon_edit",
		draw = function(): Image
			local image = canvas()
			poly(image, { 26, 102, 34, 74, 54, 94 })
			poly(image, { 38, 70, 82, 26, 102, 46, 58, 90 })
			poly(image, { 86, 22, 96, 12, 116, 32, 106, 42 })
			return image
		end,
	},
	{
		name = "facet_icon_trash",
		draw = function(): Image
			local image = canvas()
			stroke(image, { 54, 40, 54, 28, 74, 28, 74, 40 })
			stroke(image, { 28, 40, 100, 40 })
			stroke(image, { 36, 44, 42, 100, 86, 100, 92, 44 })
			return image
		end,
	},
	{
		name = "facet_icon_flag",
		draw = function(): Image
			local image = canvas()
			stroke(image, { 34, 26, 34, 102 })
			poly(image, { 34, 30, 98, 46, 34, 62 })
			return image
		end,
	},
	{
		name = "facet_icon_search",
		draw = function(): Image
			local image = canvas()
			Draw.ellipse(image, { 22 * SS, 22 * SS, 88 * SS, 88 * SS }, nil, INK, STROKE * SS)
			stroke(image, { 81, 81, 103, 103 })
			return image
		end,
	},
	{
		name = "facet_icon_settings",
		draw = function(): Image
			local image = canvas()
			local body = 34.0
			ring(image, 64, 64, body, 20)
			local rootR, tipR = body, 54.0
			local rootHalf, tipHalf = 12.0, 9.0
			for index = 0, 7 do
				local angle = math.pi / 4 * index
				local cos, sin = math.cos(angle), math.sin(angle)
				local nx, ny = -sin, cos
				poly(image, {
					64 + cos * rootR + nx * rootHalf,
					64 + sin * rootR + ny * rootHalf,
					64 + cos * tipR + nx * tipHalf,
					64 + sin * tipR + ny * tipHalf,
					64 + cos * tipR - nx * tipHalf,
					64 + sin * tipR - ny * tipHalf,
					64 + cos * rootR - nx * rootHalf,
					64 + sin * rootR - ny * rootHalf,
				})
			end
			Draw.ellipse(image, { (64 - 17) * SS, (64 - 17) * SS, (64 + 17) * SS, (64 + 17) * SS }, CLEAR)
			return image
		end,
	},
	{
		name = "facet_icon_radio_off",
		draw = function(): Image
			local image = canvas()
			ring(image, 64, 64, 40)
			return image
		end,
	},
	{
		name = "facet_icon_radio_on",
		draw = function(): Image
			local image = canvas()
			ring(image, 64, 64, 40)
			dot(image, 64, 64, 15)
			return image
		end,
	},
	{
		name = "facet_icon_check_off",
		draw = function(): Image
			local image = canvas()
			outlineBox(image, { 24, 24, 104, 104 }, 22, STROKE)
			return image
		end,
	},
	{
		name = "facet_icon_info",
		draw = function(): Image
			local image = canvas()
			ring(image, 64, 64, 40)
			dot(image, 64, 46, 7)
			stroke(image, { 64, 62, 64, 82 }, 13)
			return image
		end,
	},
	{ name = "facet_icon_success", draw = check },
	{
		name = "facet_icon_warning",
		draw = function(): Image
			local image = canvas()
			stroke(image, { 64, 18, 108, 108, 20, 108, 64, 18 }, 13)
			stroke(image, { 64, 56, 64, 80 }, 11)
			dot(image, 64, 92, 5)
			return image
		end,
	},
	{
		name = "facet_icon_error",
		draw = function(): Image
			local image = canvas()
			ring(image, 64, 64, 40)
			stroke(image, { 52, 52, 76, 76 }, 13)
			stroke(image, { 76, 52, 52, 76 }, 13)
			return image
		end,
	},
	{
		name = "facet_icon_calendar",
		draw = function(): Image
			local image = canvas()
			outlineBox(image, { 18, 40, 110, 108 }, 12, STROKE)
			stroke(image, { 24, 60, 104, 60 }, 10)
			stroke(image, { 40, 24, 40, 44 }, 11)
			stroke(image, { 88, 24, 88, 44 }, 11)
			return image
		end,
	},
	{
		name = "facet_icon_clock",
		draw = function(): Image
			local image = canvas()
			ring(image, 64, 64, 40)
			stroke(image, { 64, 64, 64, 44 }, 11)
			stroke(image, { 64, 64, 76, 50 }, 11)
			return image
		end,
	},
	{ name = "facet_icon_thumb_up", draw = thumbUp },
	{
		name = "facet_icon_thumb_down",
		draw = function(): Image
			return Image.flipTopBottom(thumbUp())
		end,
	},
	{
		name = "facet_icon_person",
		draw = function(): Image
			local image = canvas()
			dot(image, 64, 44, 18)
			Draw.pieslice(image, { 24 * SS, 66 * SS, 104 * SS, 142 * SS }, 180, 360, INK)
			return image
		end,
	},
	{
		name = "facet_icon_chevron_first",
		draw = function(): Image
			local image = canvas()
			stroke(image, { 26, 24, 26, 104 }, STROKE)
			poly(image, { 90, 24, 90, 104, 42, 64 })
			return image
		end,
	},
	{
		name = "facet_icon_chevron_last",
		draw = function(): Image
			local image = canvas()
			poly(image, { 38, 24, 38, 104, 86, 64 })
			stroke(image, { 102, 24, 102, 104 }, STROKE)
			return image
		end,
	},
}

local function contactSheet(built: { [string]: Image }): Image
	local rungs = { 16, 20, 24, 48 }
	local pad = 12
	local tallest = 48
	local cellHeight = tallest + pad
	local names: { string } = {}
	for name in built do
		table.insert(names, name)
	end
	table.sort(names)
	local width = pad
	for _, rung in rungs do
		width += rung + pad
	end
	local sheet = Image.new(width, cellHeight * #names + pad, 4, { 96, 100, 108, 255 })
	for row, name in names do
		local x = pad
		local y = (row - 1) * cellHeight + pad
		for _, rung in rungs do
			Image.alphaComposite(
				sheet,
				Resample.resize(built[name], rung, rung, "lanczos"),
				x,
				y + (tallest - rung) // 2
			)
			x += rung + pad
		end
	end
	return sheet
end

local Icons = {}

Icons.name = "icons"
Icons.summary = "Facet standard icon set"

function Icons.generate(): { Common.Output }
	local outputs: { Common.Output } = {}
	local built: { [string]: Image } = {}
	for _, icon in ICONS do
		local image = Resample.resize(icon.draw(), SIZE, SIZE, "lanczos")
		built[icon.name] = image
		table.insert(outputs, { path = `{DIRECTORY}/{icon.name}.png`, image = image })
	end
	table.insert(outputs, { path = `{DIRECTORY}/source/preview/contact-sheet.png`, image = contactSheet(built) })
	return outputs
end

return Icons :: Common.Target
