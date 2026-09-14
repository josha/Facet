--!strict
-- A click stays a click until horizontal intent wins. The native adapter owns
-- hit testing, child capture, and lifetime; this recognizer owns only distance.
local mouseScroll = {}
function mouseScroll.new(origin, offset)
	local claimed, declined = false, false
	return {
		move = function(pos, maximum)
			if declined then
				return nil
			end
			local dx, dy = pos.x - origin.x, pos.y - origin.y
			if not claimed then
				if math.max(math.abs(dx), math.abs(dy)) < 6 then
					return nil
				end
				if math.abs(dy) >= math.abs(dx) then
					declined = true
					return nil
				end
				claimed = true
			end
			return math.clamp(offset - dx, 0, math.max(0, maximum))
		end,
	}
end
return mouseScroll
