--!strict
-- CatalogService (spec §3) — blends, botanicals, and every fact DERIVED from a
-- blend's measured quantities. Pure: no signals, no clock, no engine. In
-- production this is a static content module or a backend catalog
-- (responsibility ledger).
--
-- The derivation is the point. A blend states its measures once; leaf mass,
-- caffeine, steep time and the per-botanical brew facts all come out of them,
-- so a card can be "scaled to this blend's measured quantity" (spec §7) without
-- a second table to keep in sync.

local blends = require("../content/blends")
local botanicals = require("../content/botanicals")

local catalog = {}

local function round(value: number, places: number): number
	local factor = 10 ^ (places or 0)
	return math.floor(value * factor + 0.5) / factor
end

function catalog.new()
	local self = {}

	self.blends = blends.list
	self.botanicals = botanicals.list
	self.WATER_ID = botanicals.WATER_ID

	function self.blend(id: string): any
		return blends.byId[id]
	end

	function self.botanical(id: string): any
		return botanicals.byId[id]
	end

	-- grams of ONE measure. `ml` is water (and water is never leaf), so it
	-- weighs nothing toward the pot's leaf mass.
	function self.gramsOf(measure: any): number
		local botanical = botanicals.byId[measure.botanicalId]
		if botanical == nil or botanical.water then
			return 0
		end
		if measure.unit == "g" then
			return measure.value
		end
		if measure.unit == "tsp" then
			return measure.value * botanical.gramsPerTsp
		end
		return 0
	end

	function self.caffeineOf(measure: any): number
		local botanical = botanicals.byId[measure.botanicalId]
		if botanical == nil then
			return 0
		end
		return self.gramsOf(measure) * botanical.caffeinePerGram
	end

	-- the three whole-blend derivations
	function self.caffeineMg(blendId: string): number
		local blend = blends.byId[blendId]
		if blend == nil then
			return 0
		end
		local total = 0
		for _, measure in blend.measures do
			total += self.caffeineOf(measure)
		end
		return math.floor(total + 0.5)
	end

	function self.leafGrams(blendId: string): number
		local blend = blends.byId[blendId]
		if blend == nil then
			return 0
		end
		local total = 0
		for _, measure in blend.measures do
			total += self.gramsOf(measure)
		end
		return round(total, 1)
	end

	function self.steepMinutes(blendId: string): number
		local blend = blends.byId[blendId]
		if blend == nil then
			return 0
		end
		local longest = 0
		for _, measure in blend.measures do
			local botanical = botanicals.byId[measure.botanicalId]
			if botanical ~= nil and not botanical.water then
				longest = math.max(longest, botanical.steepMinutes)
			end
		end
		return longest
	end

	-- the botanical ids a MENU surface may show: never the filler
	function self.tileBotanicals(blendId: string): { string }
		local blend = blends.byId[blendId]
		local out: { string } = {}
		if blend == nil then
			return out
		end
		for _, measure in blend.measures do
			local botanical = botanicals.byId[measure.botanicalId]
			if botanical ~= nil and not botanical.water then
				table.insert(out, botanical.id)
			end
		end
		return out
	end

	-- ...and the ones a RECIPE shows, water included
	function self.recipeMeasures(blendId: string): { any }
		local blend = blends.byId[blendId]
		return if blend ~= nil then blend.measures else {}
	end

	function self.measureFor(blendId: string, botanicalId: string): any
		local blend = blends.byId[blendId]
		if blend == nil then
			return nil
		end
		for _, measure in blend.measures do
			if measure.botanicalId == botanicalId then
				return measure
			end
		end
		return nil
	end

	-- THE FACTS FACE (spec §7): four measured rows, every one of them this
	-- blend's own quantity of this botanical rather than a shelf average.
	function self.factsFor(blendId: string, botanicalId: string): { { key: string, kind: string, value: number } }
		local botanical = botanicals.byId[botanicalId]
		local measure = self.measureFor(blendId, botanicalId)
		if botanical == nil or measure == nil then
			return {}
		end
		return {
			{ key = "facts.leaf", kind = "grams", value = round(self.gramsOf(measure), 1) },
			{ key = "facts.caffeine", kind = "mg", value = math.floor(self.caffeineOf(measure) + 0.5) },
			{ key = "facts.steep", kind = "minutes", value = botanical.steepMinutes },
			{ key = "facts.warmth", kind = "warmth", value = botanical.warmth },
		}
	end

	-- the recipe-gated set (spec §2: three free recipes, twelve behind the book)
	function self.isFreeRecipe(blendId: string): boolean
		local blend = blends.byId[blendId]
		return blend ~= nil and blend.free == true
	end

	-- SEARCH. `localize(kind, id, text)` is handed in so the match runs against
	-- what the player can actually READ — a pseudo-localized menu has to be
	-- searchable in its own locale, and a match against the source string would
	-- silently be a match against a language nobody is looking at.
	function self.matches(blendId: string, query: string, localize: (string, string, string) -> string): boolean
		local blend = blends.byId[blendId]
		if blend == nil then
			return false
		end
		local needle = string.lower(query)
		if needle == "" then
			return true
		end
		if string.find(string.lower(localize("blend", blend.id, blend.title)), needle, 1, true) ~= nil then
			return true
		end
		for _, botanicalId in self.tileBotanicals(blendId) do
			local botanical = botanicals.byId[botanicalId]
			if
				botanical ~= nil
				and string.find(string.lower(localize("botanical", botanical.id, botanical.name)), needle, 1, true)
					~= nil
			then
				return true
			end
		end
		return false
	end

	-- botanical-name suggestions: never the filler, never an exact repeat of
	-- what is already typed, capped at six rows (spec §6)
	function self.suggestions(query: string, localize: (string, string, string) -> string, cap: number): { string }
		local out: { string } = {}
		local needle = string.lower(query)
		if needle == "" then
			return out
		end
		for _, botanical in botanicals.list do
			if botanical.water then
				continue
			end
			local name = localize("botanical", botanical.id, botanical.name)
			local lowered = string.lower(name)
			if lowered ~= needle and string.find(lowered, needle, 1, true) ~= nil then
				table.insert(out, botanical.id)
				if #out >= cap then
					break
				end
			end
		end
		return out
	end

	return self
end

return catalog
