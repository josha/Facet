--!strict
-- The extracted checker keeps the bound paint/style contract and error text.
local t = require("./lib/testkit")
local check = require("../src/render/bound_enum")
local schema = require("../src/blueprint_schema")
t.describe("bound enum seam", function()
	t.it("accepts each declared Box surface and rejects a foreign value exactly", function()
		local spec = (schema.forClass("Box") :: any).props.surface
		for _, value in spec.enum do
			t.expect(pcall(check, "Box", "surface", value)).toBe(true)
		end
		local ok, message = pcall(check, "Box", "surface", "INVALID")
		t.expect(ok).toBe(false)
		t.expect(message).toBe(
			"Facet Box.surface: 'INVALID' is not one of "
				.. table.concat(spec.enum, " | ")
				.. ". A bound value outside the closed set is not a state — it paints nothing."
		)
	end)
	t.it("leaves absent, non-string and non-enum values to their owners", function()
		t.expect(pcall(check, "Box", "surface", nil)).toBe(true)
		t.expect(pcall(check, "Box", "surface", 4)).toBe(true)
		t.expect(pcall(check, "Box", "id", "value")).toBe(true)
		t.expect(pcall(check, "Unknown", "surface", "value")).toBe(true)
	end)
end)
