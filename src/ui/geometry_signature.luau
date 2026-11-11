--!strict
export type Signature = {
	push: (value: unknown) -> (),
	finish: () -> number,
}

return function(): Signature
	local held: { unknown } = {}
	local count, at, version = 0, 0, 0
	local moved = false
	return {
		push = function(value: unknown)
			at += 1
			if held[at] ~= value then
				held[at] = value
				moved = true
			end
		end,
		finish = function(): number
			if at ~= count then
				for index = count, at + 1, -1 do
					held[index] = nil
				end
				count = at
				moved = true
			end
			if moved then
				version += 1
			end
			at, moved = 0, false
			return version
		end,
	}
end
