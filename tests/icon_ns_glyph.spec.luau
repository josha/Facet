--!strict
-- The NAMESPACED icon fallback rung (swiftui-reference-app-validation matrix,
-- 2026-08-08). api.md has promised since the circle button shipped that a
-- namespaced `ns:name` icon draws "the framework's own ASCII-safe glyph for
-- that name immediately, so the affordance is legible under every theme" — but
-- `package.iconGlyph` knew only the eleven table names, returned nil for every
-- ns name, and the renderer's `iconGlyph(icon) or props.label` fallback painted
-- the button's FULL accessible label into a 44px disc instead: three unfit-text
-- findings on the first Foyer matrix row. The rung now derives the floor for a
-- namespaced name: the first letter after the namespace, uppercased.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local themePackage = require("../src/themes/package") :: any

describe("namespaced icon ASCII floor", function()
	it("derives the glyph from the name after the namespace", function()
		expect(themePackage.iconGlyph("foyer:search")).toBe("S")
		expect(themePackage.iconGlyph("wardrobe:undo")).toBe("U")
		expect(themePackage.iconGlyph("ns:chevron-ish")).toBe("C")
	end)

	it("the derived glyph passes the safe-glyph rule", function()
		expect(themePackage.isSafeGlyph(themePackage.iconGlyph("foyer:bell"))).toBe(true)
	end)

	it("table names keep their curated glyphs (the derivation never shadows them)", function()
		expect(themePackage.iconGlyph("chevron.trailing")).toBe(">")
		expect(themePackage.iconGlyph("more")).toBe("...")
		expect(themePackage.iconGlyph("close")).toBe("x")
	end)

	it("a plain unknown name still resolves to nil (schema keeps it a construction error)", function()
		expect(themePackage.iconGlyph("bell")).toBeNil()
		expect(themePackage.iconGlyph("")).toBeNil()
	end)

	it("a namespace with no letter after the colon resolves to nil, never a broken char", function()
		expect(themePackage.iconGlyph("ns:")).toBeNil()
		expect(themePackage.iconGlyph("ns:123")).toBeNil()
	end)
end)
