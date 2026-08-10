--!strict
-- AmbientService — the "sky charge" the Skyglow card draws (spec §3).
--
-- The reference read a real weather service; a Roblox experience has no host
-- equivalent for one, so this is a deterministic ambient sim and the capability
-- ledger says exactly that. Twenty-five normalized samples per plaza, the
-- lantern-hour ranges (the night bands), the two boundary marks, and the
-- "damp spell" fact the plaza recommendation reads.
local data = require("../content/data")
local rng = require("./rng")

local ambient_service = {}

local SAMPLES = 25

function ambient_service.new(opts: any): any
	local seed: number = opts.seed or 1
	local self: any = {}
	local cache: { [string]: any } = {}

	local function build(plazaId: string): any
		local plaza = data.plazaById(plazaId)
		local random = rng.new(seed * 13 + (if plaza == nil then 0 else plaza.seed))
		local samples: { number } = {}
		-- a day arc: low at both ends, high in the middle, with seeded weather
		for index = 1, SAMPLES do
			local t = (index - 1) / (SAMPLES - 1)
			local arc = math.sin(t * math.pi)
			local jitter = (random.next() - 0.5) * 0.22
			table.insert(samples, math.clamp(arc * 0.9 + jitter, 0.02, 1))
		end
		-- lantern hours: the two ends of the day, as FRACTIONS of the plot
		local lanternOut = 0.18 + random.next() * 0.04
		local lanternLit = 0.78 + random.next() * 0.04
		-- A DAMP SPELL IS A TRADING-HOURS FACT: three consecutive low samples
		-- BETWEEN the lantern hours. Reading the whole day would call every plaza
		-- damp — the arc starts and ends near zero by construction (dawn and
		-- dusk), so the ends carry no information about whether to pitch there.
		local damp = false
		local run = 0
		for index = 7, SAMPLES - 6 do
			run = if samples[index] < 0.5 then run + 1 else 0
			if run >= 3 then
				damp = true
				break
			end
		end
		return {
			samples = samples,
			bands = { { from = 0, to = lanternOut }, { from = lanternLit, to = 1 } },
			marks = { { at = lanternOut, kind = "out" }, { at = lanternLit, kind = "lit" } },
			damp = damp,
			cloud = math.floor((1 - samples[math.ceil(SAMPLES / 2)]) * 100),
		}
	end

	function self.forPlaza(plazaId: string): any
		local cached = cache[plazaId]
		if cached == nil then
			cached = build(plazaId)
			cache[plazaId] = cached
		end
		return cached
	end

	function self.samples(plazaId: string): { number }
		return self.forPlaza(plazaId).samples
	end

	function self.hasDampSpell(plazaId: string): boolean
		return self.forPlaza(plazaId).damp
	end

	-- the recommendation: the first plaza whose series shows no damp spell (the
	-- deterministic analog of the reference's rain rule)
	function self.recommendedPlaza(): any
		for _, plaza in data.plazas :: any do
			if not self.hasDampSpell(plaza.id) then
				return plaza
			end
		end
		return (data.plazas :: any)[1]
	end

	function self.dump(): any
		local out = {}
		for _, plaza in data.plazas :: any do
			local entry = self.forPlaza(plaza.id)
			table.insert(out, { id = plaza.id, damp = entry.damp, cloud = entry.cloud })
		end
		return { plazas = out, recommended = self.recommendedPlaza().id, samples = SAMPLES }
	end

	return self
end

return table.freeze(ambient_service)
