--!strict

local favorites = {}

function favorites.new(opts: any)
	local Compose = opts.Compose
	local seed = opts.seed or 1
	local ids: { string } = opts.ids or {}

	local function seeded(): { [string]: boolean }
		local out: { [string]: boolean } = {}

		local stride = 2 + (seed - 1) % 3
		for i, id in ids do
			if i % stride == 1 then
				out[id] = true
			end
		end
		return out
	end

	local set = Compose.cell(seeded())

	local self = {}
	self.set = set

	function self.isFavorite(id: string): boolean
		return set:peek()[id] == true
	end

	function self.toggle(id: string): boolean
		local next = table.clone(set:peek())
		local nowOn = next[id] ~= true
		next[id] = if nowOn then true else nil
		set:set(next)
		return nowOn
	end

	function self.count(): number
		local n = 0
		for _ in set:peek() do
			n += 1
		end
		return n
	end

	function self.ids(): { string }
		local out: { string } = {}
		for id in set:peek() do
			table.insert(out, id)
		end
		table.sort(out)
		return out
	end

	function self.reset()
		set:set(seeded())
	end

	return self
end

return favorites
