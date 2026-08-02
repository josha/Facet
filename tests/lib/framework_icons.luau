--!strict
-- How many `Icon — <name>` rules the framework's OWN icon set contributes to a
-- package's sheet.
--
-- The compact-label stage put framework art BELOW a package's `icons` map and
-- ABOVE the ASCII glyph, so a package that declares nothing still draws
-- pictures — and `ImageColor3` is sheet-owned, so every one of those names needs
-- its tint rule or the art paints pure white. That is a real cost several specs
-- used to assert was zero, and it belongs in ONE place: hardcoding 11 in five
-- files would rot the first time a name is added to the set.
local standard_icons = require("../../src/themes/standard_icons")

-- names the framework ships REAL art for (an entry with no content id resolves
-- to the glyph and therefore earns no rule), minus any the caller declares
-- itself and will get its own rule for.
return function(declared: { [string]: boolean }?): number
	local n = 0
	for name, entry in standard_icons.ART :: any do
		if type(entry.contentId) == "string" and entry.contentId ~= "" then
			if declared == nil or declared[name] ~= true then
				n += 1
			end
		end
	end
	return n
end
