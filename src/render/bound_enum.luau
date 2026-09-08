--!strict
-- Validates bound paint/style enum values against the blueprint schema.
-- One-way renderer seam: no surface state and no renderer dependency.
local schema = require("../blueprint_schema")

-- A CLOSED SET IS ONLY CLOSED IF THE REACTIVE DOOR IS SHUT TOO
-- (found live 2026-08-06, playing tutorial example 05).
--
-- `PropSpec.enum` exists because an enum prop used to accept any string and
-- silently do nothing for an unrecognised one — `surface = "panel"` tagged the
-- node with a selector no rule matched and painted nothing. But `schema.checkValue`
-- runs at CONSTRUCTION, over a STATIC value. The word game bound `surface` to a
-- memo returning "tileEmpty"/"tileCorrect"/…, never members of the surface enum,
-- and all thirty board tiles rendered at BackgroundTransparency = 1: the exact
-- defect the enum was added to remove, re-entering through the reactive door.
--
-- `tint` already had this rule (sheet_model.tintColor: "a bound tint is read long
-- after construction, so this is the only place a reactive one is ever checked").
--
-- SCOPE, STATED HONESTLY (architecture review M-1). This runs inside
-- `applyProp`/`applyStyleProp`, which are reached only for BINDING_PROPS and
-- STYLE_PROPS — the PAINT and SEMANTICS channels. It therefore guards
-- `surface`, `role`, `textAlign`, `scaleMode` and `shape`, and it does NOT
-- guard an enum prop the SOLVER consumes: `anchor`, `alignH`/`alignV`,
-- `overflow`, `align`, `reveal`, `axis`, `minColumnWidth`, `itemSizing`,
-- `focusVisual`. A bound `itemSizing = "unifrom"` still resolves silently as
-- `natural`. The complete seam is `mount.luau`'s binding write, which is where
-- every bound value of every channel lands; moving it there is the recorded
-- follow-up. Do not read this as "every enum prop" — it is not.
local function assertEnumValue(class: string, prop: string, value: any)
	if type(value) ~= "string" then
		return
	end
	local classSpec = schema.forClass(class)
	local spec = if classSpec ~= nil then (classSpec.props :: any)[prop] else nil
	if spec == nil or spec.enum == nil then
		return
	end
	for _, allowed in spec.enum do
		if value == allowed then
			return
		end
	end
	error(
		`Facet {class}.{prop}: '{value}' is not one of {table.concat(spec.enum, " | ")}. `
			.. "A bound value outside the closed set is not a state — it paints nothing.",
		0
	)
end

return assertEnumValue
