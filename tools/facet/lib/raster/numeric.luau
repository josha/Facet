--!strict
--!native

local scratch = buffer.create(4)

local Numeric = {}

function Numeric.f32(value: number): number
	buffer.writef32(scratch, 0, value)
	return buffer.readf32(scratch, 0)
end

function Numeric.trunc(value: number): number
	if value >= 0 then
		return math.floor(value)
	end
	return math.ceil(value)
end

function Numeric.roundHalfEven(value: number): number
	local floor = math.floor(value)
	local fraction = value - floor
	if fraction > 0.5 then
		return floor + 1
	elseif fraction < 0.5 then
		return floor
	elseif floor % 2 == 0 then
		return floor
	end
	return floor + 1
end

function Numeric.roundHalfAway(value: number): number
	local magnitude = math.abs(value)
	local floor = math.floor(magnitude)
	local rounded = if magnitude - floor >= 0.5 then floor + 1 else floor
	return if value < 0 then -rounded else rounded
end

function Numeric.roundUp(value: number): number
	if value >= 0 then
		return math.floor(value + 0.5)
	end
	return -math.floor(math.abs(value) + 0.5)
end

function Numeric.roundDown(value: number): number
	if value >= 0 then
		return math.ceil(value - 0.5)
	end
	return -math.ceil(math.abs(value) - 0.5)
end

function Numeric.roundUpF32(value: number): number
	if value >= 0 then
		return math.floor(Numeric.f32(value + 0.5))
	end
	return -math.floor(Numeric.f32(math.abs(value) + 0.5))
end

function Numeric.roundDownF32(value: number): number
	if value >= 0 then
		return math.ceil(Numeric.f32(value - 0.5))
	end
	return -math.ceil(Numeric.f32(math.abs(value) - 0.5))
end

function Numeric.floorMod(value: number, modulus: number): number
	local remainder = math.fmod(value, modulus)
	if remainder ~= 0 and (remainder < 0) ~= (modulus < 0) then
		remainder += modulus
	end
	if remainder == 0 then
		return 0
	end
	return remainder
end

function Numeric.clamp(value: number, low: number, high: number): number
	if value < low then
		return low
	elseif value > high then
		return high
	end
	return value
end

function Numeric.mul32(a: number, b: number): number
	local low = a * bit32.band(b, 0xFFFF)
	local high = (a * bit32.rshift(b, 16)) % 65536
	return (low + high * 65536) % 4294967296
end

function Numeric.pairwiseSum(values: buffer, offset: number, count: number, stride: number): number
	if count < 8 then
		local total = 0.0
		for index = 0, count - 1 do
			total += buffer.readf64(values, offset + index * stride * 8)
		end
		return total
	elseif count <= 128 then
		local r0 = buffer.readf64(values, offset)
		local r1 = buffer.readf64(values, offset + stride * 8)
		local r2 = buffer.readf64(values, offset + 2 * stride * 8)
		local r3 = buffer.readf64(values, offset + 3 * stride * 8)
		local r4 = buffer.readf64(values, offset + 4 * stride * 8)
		local r5 = buffer.readf64(values, offset + 5 * stride * 8)
		local r6 = buffer.readf64(values, offset + 6 * stride * 8)
		local r7 = buffer.readf64(values, offset + 7 * stride * 8)
		local index = 8
		local limit = count - count % 8
		while index < limit do
			local base = offset + index * stride * 8
			r0 += buffer.readf64(values, base)
			r1 += buffer.readf64(values, base + stride * 8)
			r2 += buffer.readf64(values, base + 2 * stride * 8)
			r3 += buffer.readf64(values, base + 3 * stride * 8)
			r4 += buffer.readf64(values, base + 4 * stride * 8)
			r5 += buffer.readf64(values, base + 5 * stride * 8)
			r6 += buffer.readf64(values, base + 6 * stride * 8)
			r7 += buffer.readf64(values, base + 7 * stride * 8)
			index += 8
		end
		local total = ((r0 + r1) + (r2 + r3)) + ((r4 + r5) + (r6 + r7))
		while index < count do
			total += buffer.readf64(values, offset + index * stride * 8)
			index += 1
		end
		return total
	end
	local half = count // 2
	half -= half % 8
	return Numeric.pairwiseSum(values, offset, half, stride)
		+ Numeric.pairwiseSum(values, offset + half * stride * 8, count - half, stride)
end

function Numeric.linspace(start: number, stop: number, count: number, endpoint: boolean?): { number }
	local includeEnd = endpoint ~= false
	local divisions = if includeEnd then count - 1 else count
	local values = table.create(count, 0)
	if divisions > 0 then
		local step = (stop - start) / divisions
		for index = 0, count - 1 do
			values[index + 1] = index * step + start
		end
	else
		for index = 0, count - 1 do
			values[index + 1] = index * (stop - start) + start
		end
	end
	if includeEnd and count > 1 then
		values[count] = stop
	end
	return values
end

function Numeric.interp(query: { number }, xs: { number }, ys: { number }): { number }
	local count = #xs
	local precomputed = count <= #query
	local slopes = table.create(count - 1, 0)
	for index = 1, count - 1 do
		if precomputed then
			local inverse = 1.0 / (xs[index + 1] - xs[index])
			slopes[index] = (ys[index + 1] - ys[index]) * inverse
		else
			slopes[index] = (ys[index + 1] - ys[index]) / (xs[index + 1] - xs[index])
		end
	end
	local out = table.create(#query, 0)
	for position, x in query do
		if x < xs[1] then
			out[position] = ys[1]
		elseif x > xs[count] then
			out[position] = ys[count]
		else
			local index = 1
			while index < count and xs[index + 1] <= x do
				index += 1
			end
			if index == count or xs[index] == x then
				out[position] = ys[index]
			else
				out[position] = slopes[index] * (x - xs[index]) + ys[index]
			end
		end
	end
	return out
end

return table.freeze(Numeric)
