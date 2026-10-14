--!strict
--!native

local FieldModule = require("./field")
local ImageModule = require("./image")
local Numeric = require("./numeric")

type Field = FieldModule.Field
type Color = FieldModule.Color
type Image = ImageModule.Image

export type Canvas = {
	width: number,
	height: number,
	rgb: Field,
	alpha: Field,
}

local Canvas = {}

function Canvas.new(width: number, height: number): Canvas
	return {
		width = width,
		height = height,
		rgb = FieldModule.new(width, height, 3),
		alpha = FieldModule.new(width, height, 1),
	}
end

function Canvas.paint(canvas: Canvas, color: Color | Field, alpha: Field)
	local width, height = canvas.width, canvas.height
	local rgb = canvas.rgb.data
	local destination = canvas.alpha.data
	local source = alpha.data
	local constant: Color? = nil
	local field: Field? = nil
	if (color :: Field).data ~= nil then
		field = color :: Field
	else
		constant = color :: Color
	end
	for pixel = 0, width * height - 1 do
		local sa = Numeric.clamp(buffer.readf64(source, pixel * 8), 0, 1)
		local da = buffer.readf64(destination, pixel * 8)
		local rest = 1 - sa
		local outA = sa + da * rest
		for channel = 0, 2 do
			local value
			if outA > 1e-6 then
				local src = if field ~= nil
					then buffer.readf64(field.data, (pixel * 3 + channel) * 8)
					else (constant :: Color)[channel + 1]
				local current = buffer.readf64(rgb, (pixel * 3 + channel) * 8)
				value = (src * sa + current * da * rest) / math.max(outA, 1e-6)
			else
				value = 0.0
			end
			buffer.writef64(rgb, (pixel * 3 + channel) * 8, value)
		end
		buffer.writef64(destination, pixel * 8, outA)
	end
end

function Canvas.image(canvas: Canvas): Image
	local color = FieldModule.toBytes(canvas.rgb)
	local alpha = FieldModule.toBytes(canvas.alpha)
	local out = ImageModule.new(canvas.width, canvas.height, 4)
	for pixel = 0, canvas.width * canvas.height - 1 do
		buffer.copy(out.data, pixel * 4, color.data, pixel * 3, 3)
		buffer.writeu8(out.data, pixel * 4 + 3, buffer.readu8(alpha.data, pixel))
	end
	return out
end

return table.freeze(Canvas)
