--!strict
-- Image paint geometry, independent of layout and of the engine target.
local framing = {}
local keys = { width = true, height = true, mode = true, focusX = true, focusY = true, scale = true }
local modes = { crop = true, fill = true, fit = true, stretch = true, none = true }
local function finite(v: any): boolean
	return type(v) == "number" and v == v and math.abs(v) < math.huge
end
function framing.check(v: any): (boolean, string?)
	if type(v) ~= "table" then
		return false, "imageFraming needs a table"
	end
	for key in v do
		if not keys[key] then
			return false, `unknown imageFraming field '{key}'`
		end
	end
	for _, key in { "width", "height" } do
		if not finite(v[key]) or v[key] <= 0 then
			return false, `imageFraming.{key} must be positive finite source pixels`
		end
	end
	for _, key in { "focusX", "focusY" } do
		if v[key] ~= nil and (not finite(v[key]) or v[key] < 0 or v[key] > 1) then
			return false, `imageFraming.{key} must be in 0..1`
		end
	end
	if v.scale ~= nil and (not finite(v.scale) or v.scale <= 0) then
		return false, "imageFraming.scale must be positive and finite"
	end
	if v.mode ~= nil and not modes[v.mode] then
		return false, "imageFraming.mode must be crop, fill, fit, stretch or none"
	end
	return true
end
function framing.resolve(spec: any, width: number, height: number): any
	local ok, why = framing.check(spec)
	assert(ok, why)
	local sw, sh = spec.width, spec.height
	local w, h = math.max(0, width), math.max(0, height)
	local mode = spec.mode or "crop"
	local sx, sy = 1, 1
	if w == 0 or h == 0 then
		return { source = { x = 0, y = 0, w = sw, h = sh }, destination = { x = 0, y = 0, w = 0, h = 0 } }
	end
	if mode == "stretch" then
		sx, sy = w / sw, h / sh
	elseif mode == "fit" then
		sx = math.min(w / sw, h / sh)
		sy = sx
	elseif mode ~= "none" then
		sx = math.max(w / sw, h / sh)
		sy = sx
	end
	sx *= spec.scale or 1
	sy *= spec.scale or 1
	local cw, ch = math.min(sw, w / sx), math.min(sh, h / sy)
	local dw, dh = cw * sx, ch * sy
	return {
		source = {
			x = math.clamp((spec.focusX or 0.5) * sw - cw / 2, 0, sw - cw),
			y = math.clamp((spec.focusY or 0.5) * sh - ch / 2, 0, sh - ch),
			w = cw,
			h = ch,
		},
		destination = { x = (w - dw) / 2, y = (h - dh) / 2, w = dw, h = dh },
	}
end
return framing
