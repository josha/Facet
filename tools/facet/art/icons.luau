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

local function dot(image: Image, x: number, y: number, r: number, ink: { number }?)
	local cx, cy, cr = x * SS, y * SS, r * SS
	Draw.ellipse(image, { cx - cr, cy - cr, cx + cr, cy + cr }, ink or INK)
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

local function poly(image: Image, points: { number }, ink: { number }?)
	local scaled = table.create(#points, 0)
	for index, value in points do
		scaled[index] = value * SS
	end
	Draw.polygon(image, scaled, ink or INK)
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

local function solidBox(image: Image, box: { number }, radius: number, ink: { number }?)
	Draw.roundedRectangle(image, { box[1] * SS, box[2] * SS, box[3] * SS, box[4] * SS }, radius * SS, ink or INK)
end

local function arc(image: Image, cx: number, cy: number, r: number, from: number, to: number, width: number?)
	local w = width or STROKE
	local outer = r + w / 2
	Draw.arc(
		image,
		{ (cx - outer) * SS, (cy - outer) * SS, (cx + outer) * SS, (cy + outer) * SS },
		from,
		to,
		INK,
		Numeric.trunc(w * SS)
	)
	for _, angle in { from, to } do
		local radians = math.rad(angle)
		dot(image, cx + math.cos(radians) * r, cy + math.sin(radians) * r, w / 2)
	end
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
	{
		name = "facet_icon_star",
		draw = function(): Image
			local image = canvas()
			local points: { number } = {}
			for index = 0, 9 do
				local radius = if index % 2 == 0 then 52 else 24
				local angle = math.pi / 5 * index - math.pi / 2
				table.insert(points, 64 + math.cos(angle) * radius)
				table.insert(points, 69 + math.sin(angle) * radius)
			end
			poly(image, points)
			return image
		end,
	},
	{
		name = "facet_icon_heart",
		draw = function(): Image
			local image = canvas()
			dot(image, 44, 47, 24)
			dot(image, 84, 47, 24)
			poly(image, { 26, 63, 64, 106, 102, 63, 84, 47, 44, 47 })
			return image
		end,
	},
	{
		name = "facet_icon_chat",
		draw = function(): Image
			local image = canvas()
			outlineBox(image, { 18, 22, 110, 90 }, 20, STROKE)
			poly(image, { 34, 84, 30, 108, 60, 84 })
			return image
		end,
	},
	{
		name = "facet_icon_gift",
		draw = function(): Image
			local image = canvas()
			stroke(image, { 62, 42, 44, 22, 34, 36, 62, 42 }, 10)
			stroke(image, { 66, 42, 84, 22, 94, 36, 66, 42 }, 10)
			solidBox(image, { 18, 42, 110, 62 }, 6)
			outlineBox(image, { 26, 56, 102, 110 }, 8, STROKE)
			stroke(image, { 64, 62, 64, 100 })
			return image
		end,
	},
	{
		name = "facet_icon_coin",
		draw = function(): Image
			local image = canvas()
			dot(image, 64, 64, 46)
			Draw.ellipse(image, { 30 * SS, 30 * SS, 98 * SS, 98 * SS }, nil, CLEAR, 8 * SS)
			Draw.line(image, { 64 * SS, 48 * SS, 64 * SS, 80 * SS }, CLEAR, 9 * SS)
			return image
		end,
	},
	{
		name = "facet_icon_gem",
		draw = function(): Image
			local image = canvas()
			poly(image, { 38, 24, 90, 24, 112, 50, 64, 108, 16, 50 })
			Draw.line(image, { 16 * SS, 50 * SS, 112 * SS, 50 * SS }, CLEAR, 7 * SS)
			return image
		end,
	},
	{
		name = "facet_icon_bag",
		draw = function(): Image
			local image = canvas()
			arc(image, 64, 44, 18, 180, 360, 11)
			outlineBox(image, { 22, 44, 106, 110 }, 10, STROKE)
			arc(image, 64, 64, 14, 0, 180, 10)
			return image
		end,
	},
	{
		name = "facet_icon_trophy",
		draw = function(): Image
			local image = canvas()
			arc(image, 34, 42, 12, 90, 270, 10)
			arc(image, 94, 42, 12, 270, 450, 10)
			Draw.rectangle(image, { 34 * SS, 20 * SS, 94 * SS, 46 * SS }, INK)
			Draw.pieslice(image, { 34 * SS, 16 * SS, 94 * SS, 76 * SS }, 0, 180, INK)
			Draw.rectangle(image, { 57 * SS, 72 * SS, 71 * SS, 94 * SS }, INK)
			solidBox(image, { 38, 92, 90, 108 }, 5)
			return image
		end,
	},
	{
		name = "facet_icon_crown",
		draw = function(): Image
			local image = canvas()
			poly(image, { 22, 44, 44, 70, 64, 32, 84, 70, 106, 44, 98, 100, 30, 100 })
			for _, tip in { { 22, 42 }, { 64, 30 }, { 106, 42 } } do
				dot(image, tip[1], tip[2], 8)
			end
			return image
		end,
	},
	{
		name = "facet_icon_lock",
		draw = function(): Image
			local image = canvas()
			arc(image, 64, 46, 20, 180, 360)
			stroke(image, { 44, 46, 44, 60 })
			stroke(image, { 84, 46, 84, 60 })
			solidBox(image, { 24, 56, 104, 110 }, 12)
			dot(image, 64, 78, 8, CLEAR)
			Draw.rectangle(image, { 60 * SS, 78 * SS, 68 * SS, 94 * SS }, CLEAR)
			return image
		end,
	},
	{
		name = "facet_icon_bolt",
		draw = function(): Image
			local image = canvas()
			poly(image, { 58, 16, 92, 16, 74, 54, 100, 54, 50, 112, 62, 72, 30, 72 })
			return image
		end,
	},
	{
		name = "facet_icon_wrench",
		draw = function(): Image
			local image = canvas()
			stroke(image, { 84, 44, 32, 96 }, 22)
			dot(image, 84, 44, 26)
			poly(image, { 79, 36, 106, 9, 119, 22, 92, 49 }, CLEAR)
			return image
		end,
	},
	{
		name = "facet_icon_timer",
		draw = function(): Image
			local image = canvas()
			ring(image, 64, 70, 40)
			stroke(image, { 52, 16, 76, 16 }, 11)
			stroke(image, { 64, 16, 64, 32 }, 11)
			stroke(image, { 94, 34, 100, 28 }, 10)
			stroke(image, { 64, 70, 76, 54 }, 11)
			return image
		end,
	},
	{
		name = "facet_icon_car",
		draw = function(): Image
			local image = canvas()
			poly(image, { 30, 60, 46, 30, 82, 30, 100, 60 })
			solidBox(image, { 14, 56, 114, 90 }, 14)
			poly(image, { 42, 56, 52, 38, 62, 38, 62, 56 }, CLEAR)
			poly(image, { 68, 56, 68, 38, 78, 38, 90, 56 }, CLEAR)
			dot(image, 40, 90, 18, CLEAR)
			dot(image, 88, 90, 18, CLEAR)
			dot(image, 40, 90, 12)
			dot(image, 88, 90, 12)
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
