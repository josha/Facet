--!strict

local data = require("../content/data")
local rng = require("./rng")

local ambient_service = {}

export type Opts = { seed: number? }
export type Weather = {
	samples: { number },
	bands: { { from: number, to: number } },
	marks: { { at: number, kind: string } },
	damp: boolean,
	cloud: number,
}

local SAMPLES = 25

function ambient_service.new(opts: Opts)
	local seed: number = opts.seed or 1
	local self = {}
	local cache: { [string]: Weather } = {}

	local function build(plazaId: string): Weather
		local plaza = data.plazaById(plazaId)
		local random = rng.new(seed * 13 + (if plaza == nil then 0 else plaza.seed))
		local samples: { number } = {}

		for index = 1, SAMPLES do
			local t = (index - 1) / (SAMPLES - 1)
			local arc = math.sin(t * math.pi)
			local jitter = (random.next() - 0.5) * 0.22
			table.insert(samples, math.clamp(arc * 0.9 + jitter, 0.02, 1))
		end

		local lanternOut = 0.18 + random.next() * 0.04
		local lanternLit = 0.78 + random.next() * 0.04

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

	function self.forPlaza(plazaId: string): Weather
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

	function self.recommendedPlaza(): data.Plaza
		for _, plaza in data.plazas do
			if not self.hasDampSpell(plaza.id) then
				return plaza
			end
		end
		return data.plazas[1]
	end

	function self.dump(): { plazas: { { id: string, damp: boolean, cloud: number } }, recommended: string, samples: number }
		local out: { { id: string, damp: boolean, cloud: number } } = {}
		for _, plaza in data.plazas do
			local entry = self.forPlaza(plaza.id)
			table.insert(out, { id = plaza.id, damp = entry.damp, cloud = entry.cloud })
		end
		return { plazas = out, recommended = self.recommendedPlaza().id, samples = SAMPLES }
	end

	return self
end

return table.freeze(ambient_service)
