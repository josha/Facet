--!strict
-- Shared closed size/appearance words, theme-metric dimensions, and reserved hit footprints.
-- Bindings use Compose tracking; callers retain their model values.
local guard = require("../spec_guard")
local selection = require("../selection_model")
local contract = require("../class_contract")
local surfaceEnv = require("../env/surface_env")
local themeSnapshot = require("../themes/snapshot")

local vocabulary = {}

-- THE THREE RUNGS, in ladder order. The names are the theme's own
-- (`metrics.controlSizes`), so a package that retunes its ladder retunes every
-- control that names a rung, and no control carries a fourth word for a size the
-- theme cannot answer.
vocabulary.SIZES = table.freeze({ "compact", "regular", "large" })
local SIZE_SET = guard.keySet(vocabulary.SIZES)

-- The corner silhouettes an author may ask for locally. `nil` is the theme's own
-- control radius, which is what every control shipped before this key drew.
-- `square` is the CORNER treatment (radius 0), never a 1:1 box — the 1:1 disc is
-- the long-shipped `UI.Button{ shape = "circle" }` and stays exactly that.
vocabulary.CORNERS = table.freeze({ "pill", "square" })
local CORNER_SET = guard.keySet(vocabulary.CORNERS)
-- `UI.corners` takes a radius token or a literal, so "square" is the number 0 and
-- "pill" is the published token every pill in this library already names.
local CORNER_RADIUS: { [string]: any } = { pill = "pill", square = 0 }

-- The one surface a control may say it is drawn OVER. A single word today; it is
-- a closed set rather than a boolean because "over what" is the question a second
-- treatment would answer, and a boolean cannot grow one.
vocabulary.OVER = table.freeze({ "media" })
local OVER_SET = guard.keySet(vocabulary.OVER)

local function names(set: { string }): string
	return table.concat(set, " | ")
end

--[[ REFUSE, DON'T GUESS (constitution §4): an unknown word is an authoring
	mistake, and a control that quietly ignored it would paint the default forever
	with nothing ever saying a word. Each refusal names the control, the key and
	the full legal set — a closed set is only useful if the error prints it. ]]
local function assertWord(control: string, key: string, value: any, set: { [string]: boolean }, all: { string })
	if value == nil then
		return
	end
	if type(value) ~= "string" or not set[value] then
		error(`Facet {control}: \`{key}\` must be {names(all)} (got {typeof(value)} '{tostring(value)}')`, 0)
	end
end

-- assertSize(control, value): the rung a control was handed, static or live. A
-- READABLE is checked at its current value — the same reading every other
-- reactive enum in this library gets, because a getter can only be asked now.
function vocabulary.assertSize(control: string, value: any)
	assertWord(control, "controlSize", selection.read(value), SIZE_SET, vocabulary.SIZES)
end

-- assertAppearance(control, value, allowed, set): the emphasis words are per
-- FAMILY — a Button has five, a Chip has two — so the legal vocabulary arrives
-- from the control rather than living here. This module owns the KEY, never one
-- family's words. Both the ordered list (for the message) and the SET (for the
-- check) come from the caller, which builds each once at module scope: a keySet
-- built here would allocate and freeze a throwaway table on every control built,
-- and a two-hundred-chip list is two hundred of them.
function vocabulary.assertAppearance(control: string, value: any, allowed: { string }, set: { [string]: boolean })
	assertWord(control, "appearance", selection.read(value), set, allowed)
end

function vocabulary.assertCorners(control: string, value: any)
	assertWord(control, "corners", value, CORNER_SET, vocabulary.CORNERS)
end

function vocabulary.assertOver(control: string, value: any)
	assertWord(control, "over", value, OVER_SET, vocabulary.OVER)
end

-- metricPath(rung, field) -> "controlSizes.<rung>.<field>" | nil. The NAME, not a
-- number: see the header for why a control never resolves it itself.
function vocabulary.metricPath(rung: any, field: string): string?
	return if type(rung) == "string" and SIZE_SET[rung] then `controlSizes.{rung}.{field}` else nil
end

--[[ heightFor(rung) -> Dim?  The plate this rung paints, as a FLOOR.

	THE SHRINK COMES FROM THE PADDING, NOT FROM A CAP, and the pairing is the whole
	trick. A control's resting height today is its content plus the theme's button
	padding on both sides (20 + 12 + 12 = 44 at Facet Neutral), so a floor alone
	would leave `compact` exactly where it was and "smaller" would silently mean
	"the same". `paddingFor` below therefore spends the ladder's inset HORIZONTALLY
	and zeroes it vertically, which drops the measured height to the content, and
	this floor then lifts it back to the rung — 36, 44, 56.

	A FIXED dim was tried first and refused. It shrinks correctly and then cannot
	GROW, and two real things need it to: the player's text preference (a theme
	metric does not move with the type ramp, the label inside it does) and a
	package whose control chrome carries decorative insets — measured on the
	overflow sweep, where a selected compact chip under a package with a 4px
	selection border had nowhere to put it at the largest preference on a ten-foot
	display, and the theme's own border was given back rather than drawn. A floor
	takes both in its stride and still paints below the touch target, which is the
	only shrink the rung actually promises. ]]
function vocabulary.heightFor(rung: any): any
	local path = vocabulary.metricPath(rung, "height")
	return if path ~= nil then { type = "minMax", min = path } else nil
end

--[[ paddingFor(rung) -> Sides?  The ladder's inset, spent horizontally and zeroed
	vertically — see `heightFor` for why the vertical zero is what makes a rung
	smaller at all. The ladder publishes `paddingX` and a height; it publishes no
	vertical inset, and inventing one here would be this module deciding a number
	the theme did not. ]]
function vocabulary.paddingFor(rung: any): any
	local path = vocabulary.metricPath(rung, "paddingX")
	return if path ~= nil then { left = path, right = path, top = 0, bottom = 0 } else nil
end

-- iconSizeFor(rung) -> metric name?  The square a leading/trailing mark draws in.
function vocabulary.iconSizeFor(rung: any): any
	return vocabulary.metricPath(rung, "iconSize")
end

-- cornerRadiusFor(word) -> the `UI.corners` argument, or nil for "leave the
-- theme's own control radius alone".
function vocabulary.cornerRadiusFor(word: any): any
	return if type(word) == "string" then CORNER_RADIUS[word] else nil
end

-- The effective hit floor as a bound minMax Dim: the larger of the class floor
-- and the theme minimum. Returns the Dim function and the env it reads.
function vocabulary.hitFloor(core: any, id: string): ((any) -> any, any)
	local env = surfaceEnv.resolve("UI.Button", id, core, nil, "a sized control must reserve its effective hit floor")
	return function(use)
		return { type = "minMax", min = contract.effectiveHitFloor("Button", use(env:get("themeMetrics"))) }
	end,
		env
end

-- Reserve both axes at the larger of the class floor and theme minimum.
-- The plate keeps its id and authored dimensions; fill also belongs on the wrapper.
-- `height` negotiates exactly as `width` does, for a control whose value runs down
-- the page (a vertical Slider); absent, both axes floor as before.
function vocabulary.reserveTarget(UI: any, core: any, id: string, plate: any, width: any, height: any?): any
	local floor, env = vocabulary.hitFloor(core, id)
	-- A fixed sub-floor plate contributes its own extent to this minimum.
	-- Fill belongs on the wrapper too, so the control still takes its offer.
	local function reserve(dim: any)
		return function(use)
			local authored = selection.read(dim, use)
			if authored and authored.type == "fill" then
				local metrics = use(env:get("themeMetrics"))
				local reserved = table.clone(authored)
				reserved.min = math.max(
					themeSnapshot.resolveTotal(metrics, authored.min or 0),
					contract.effectiveHitFloor("Button", metrics)
				)
				return reserved
			end
			return floor(use)
		end
	end
	return UI.ZStack({
		id = id .. "+target",
		width = reserve(width),
		height = reserve(height),
		alignH = "center",
		alignV = "center",
		children = { plate },
	})
end

-- Map a static word once; let the native property binding own a tracked derivation.
function vocabulary.derive(value: any, map: (any) -> any): any
	if value == nil then
		return nil
	end
	if selection.isSource(value) then
		return function(use)
			return map(selection.read(value, use))
		end
	end
	return map(value)
end

-- Validate before the mapped property publishes: each family owns its words.
function vocabulary.deriveSize(control: string, value: any, map: (any) -> any): any
	return vocabulary.derive(value, function(rung)
		assertWord(control, "controlSize", rung, SIZE_SET, vocabulary.SIZES)
		return map(rung)
	end)
end

function vocabulary.deriveAppearance(control: string, value: any, allowed: { string }, set: { [string]: boolean }): any
	return vocabulary.derive(value, function(word)
		assertWord(control, "appearance", word, set, allowed)
		return word
	end)
end

return vocabulary
