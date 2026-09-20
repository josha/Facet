--!strict
-- Rating configures the shared LevelPicker behavior with star glyphs.

local level_picker = require("./level_picker")
local specGuard = require("../spec_guard")

local rating = {}

local STAR_SIZE_ROLE = "small"

rating.FILLED = "★"
rating.EMPTY = "☆"

local specTypes = require("../spec_types/rating")
type NumberCell = specTypes.NumberCell
export type Spec<V = NumberCell> = specTypes.Spec<V>

local RATING_KEYS = specGuard.keySet({
	"allowZero",
	"count",
	"enabled",
	"env",
	"glyphs",
	"id",
	"onChange",
	"readOnly",
	"starSize",
	"value",
})

function rating.build(Facet: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("UI.Rating", spec, RATING_KEYS, "spec")
	local id = spec.id or "Rating"
	local count = if spec.count ~= nil then spec.count else 5
	level_picker.validate("UI.Rating", id, spec.value, count)

	local diagnostics: { string } = {}
	level_picker.diagnoseCount("UI.Rating", id, count, diagnostics)

	local api, facts = level_picker.compose(Facet, core, {
		constructor = "UI.Rating",
		names = { run = "Stars", mark = "Star" },
		id = id,
		value = spec.value,
		count = count,
		minValue = if spec.allowZero == false then 1 else 0,
		segment = "glyph",
		sizeRole = level_picker.sizeRole("UI.Rating", id, "starSize", spec.starSize or STAR_SIZE_ROLE),
		glyphs = if spec.glyphs ~= nil then spec.glyphs else { filled = rating.FILLED, empty = rating.EMPTY },
		images = nil,
		tint = {},
		targetFloor = false,
		readOnly = spec.readOnly == true,
		enabled = spec.enabled,
		env = spec.env,
		onChange = spec.onChange,
		diagnostics = diagnostics,
	})

	function api.dump()
		local out = facts()
		out.schema = "facet-rating-dump/1"
		return out
	end

	return api
end

return rating
