--!strict
-- FavoritesService (spec §3): a `Set<blendId>` and one toggle command.
-- Production is a DataStore write per the responsibility ledger; here it is a
-- signal holding an immutable snapshot, so a toggle is a real change the core
-- can see rather than a mutation nothing observes.
--
-- The starting set comes from the SEED, not from a hardcoded list, so a reset
-- reproduces it byte for byte and the empty state is reachable by unfavoriting
-- through the on-screen hearts alone.

local favorites = {}

function favorites.new(opts: any)
	local core = opts.core
	local scope = opts.scope
	local seed = opts.seed or 1
	local ids: { string } = opts.ids or {}

	local function seeded(): { [string]: boolean }
		local out: { [string]: boolean } = {}
		-- every (seed)th blend in declaration order starts favorited; seed 1 is
		-- "all of them", which is never what a fixture wants, so the stride
		-- starts at two
		local stride = 2 + (seed - 1) % 3
		for i, id in ids do
			if i % stride == 1 then
				out[id] = true
			end
		end
		return out
	end

	local set = core:signal(seeded())
	scope:own(function()
		set:dispose()
	end)

	local self = {}
	self.set = set

	function self.isFavorite(id: string): boolean
		return set:get()[id] == true
	end

	function self.toggle(id: string): boolean
		local next = table.clone(set:get())
		local nowOn = next[id] ~= true
		next[id] = if nowOn then true else nil
		set:set(next)
		return nowOn
	end

	function self.count(): number
		local n = 0
		for _ in set:get() do
			n += 1
		end
		return n
	end

	-- sorted, so a dump is stable
	function self.ids(): { string }
		local out: { string } = {}
		for id in set:get() do
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
