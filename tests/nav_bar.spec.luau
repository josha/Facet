--!strict
-- `Facet.navBar` — the presenter-side surface-chrome seam (registry item 13;
-- W3-D). Pure blueprint assembly: no core, no scope, no presenter,
-- so this spec inspects the returned Blueprint table directly rather than
-- mounting one — the same "cheapest instrument that can see the claim" rule
-- `tests/blueprint*.spec.luau` already uses for other pure constructors.
--
-- The four migrated sites (`examples/reference/p1_glade/ui/detail.luau`,
-- `p2_cartwheel/screens/shell.luau`, `p3_sipworks/views/detail.luau`,
-- `p3_sipworks/views/book.luau`) are exercised end-to-end by
-- `tests/reference/*_spec.luau` and the full-catalogue mount sweeps; this
-- file is the construct's own direct coverage.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local UI = Facet.UI

local function childIds(bp: any): { string }
	local out: { string } = {}
	for _, child in bp.children or {} do
		table.insert(out, child.id)
	end
	return out
end

describe("Facet.navBar: shape", function()
	it("defaults to id 'NavBar', gap 's', full width, and a bare Spacer with nothing declared", function()
		local bp = Facet.navBar({})
		expect(bp.class).toBe("HStack")
		expect(bp.id).toBe("NavBar")
		expect(bp.props.gap).toBe("s")
		expect(bp.props.align).toBe("center")
		expect(bp.props.width.type).toBe("fill")
		expect(childIds(bp)).toEqual({ "Push" })
	end)

	it("takes the caller's own id, gap and padding", function()
		local bp = Facet.navBar({ id = "TopBar", gap = "m", padding = "s" })
		expect(bp.id).toBe("TopBar")
		expect(bp.props.gap).toBe("m")
		expect(bp.props.padding).toBe("s")
	end)
end)

describe("Facet.navBar: Back — refuse, don't guess", function()
	it("onBack = nil renders no Back button at all", function()
		local bp = Facet.navBar({ title = "X" })
		for _, child in bp.children do
			expect(child.id == "Back").toBe(false)
		end
	end)

	it("onBack given draws the framework's own chevron icon, never a hand-typed glyph", function()
		local fired = { n = 0 }
		local onBack = function()
			fired.n += 1
		end
		local bp = Facet.navBar({ onBack = onBack, backLabel = "Back" })
		local back = bp.children[1]
		expect(back.id).toBe("Back")
		expect(back.class).toBe("Button")
		expect(back.props.label).toBe("Back")
		expect(back.props.compactLabel.icon).toBe("chevron.leading")
		-- ALWAYS compact, never a degrade candidate — see nav_bar.luau's own
		-- comment: without `prefer`, the ladder's "full label when it fits"
		-- rung measured a real 7px overflow at large text + pseudo-locale
		expect(back.props.compactLabel.prefer).toBe(true)
		-- the exact callback rides through untouched — this construct invents no
		-- verb of its own, it only wires the one it was handed
		back.props.onActivate()
		expect(fired.n).toBe(1)
	end)

	it("Back is always first when present", function()
		local bp = Facet.navBar({
			onBack = function() end,
			backLabel = "Back",
			title = "T",
			trailing = { UI.Button({ id = "Fav", label = "Fav" }) },
		})
		expect(childIds(bp)).toEqual({ "Back", "Title", "Push", "Fav" })
	end)
end)

describe("Facet.navBar: Title — bounded identity text, or none", function()
	it("title = nil renders no Title node (the site with none)", function()
		local bp = Facet.navBar({ onBack = function() end, backLabel = "Back" })
		for _, child in bp.children do
			expect(child.id == "Title").toBe(false)
		end
	end)

	it('title truncates into its disclosure by default ("title" size)', function()
		local bp = Facet.navBar({ title = "A Glade Name" })
		local title = bp.children[1]
		expect(title.id).toBe("Title")
		expect(title.class).toBe("Text")
		expect(title.props.text).toBe("A Glade Name")
		expect(title.props.textSize).toBe("title")
		expect(title.props.lineLimit).toBe(1)
		expect(title.props.disclose).toBe(true)
		-- no width unless the caller supplies one — two of the four migrated
		-- sites never set one, and this construct invents no new default
		expect(title.props.width).toBeNil()
	end)

	it("titleSize and titleWidth pass through verbatim (the sipworks book site's own dim)", function()
		local dim = { type = "hug", min = 10, max = 100 }
		local bp = Facet.navBar({ title = "Recipe", titleSize = "heading", titleWidth = dim })
		local title = bp.children[1]
		expect(title.props.textSize).toBe("heading")
		expect(title.props.width).toBe(dim)
	end)
end)

describe("Facet.navBar: trailing actions and the spacer", function()
	it("a Spacer always separates the leading segment from trailing content", function()
		local bp = Facet.navBar({ title = "T" })
		expect(childIds(bp)).toEqual({ "Title", "Push" })
	end)

	it("trailing nodes are appended after the spacer, in order, unmodified", function()
		local fav = UI.Button({ id = "Fav", label = "Favourite" })
		local extra = UI.Button({ id = "Extra", label = "Extra" })
		local bp = Facet.navBar({ trailing = { fav, extra } })
		expect(childIds(bp)).toEqual({ "Push", "Fav", "Extra" })
		-- the exact blueprint reference rides through, never rebuilt
		expect(bp.children[2]).toBe(fav)
		expect(bp.children[3]).toBe(extra)
	end)

	it("an empty trailing table behaves exactly like omitting it", function()
		local withEmpty = Facet.navBar({ title = "T", trailing = {} })
		local withNil = Facet.navBar({ title = "T" })
		expect(childIds(withEmpty)).toEqual(childIds(withNil))
	end)
end)

describe("Facet.navBar: closed-key spec (constitution §4)", function()
	it("refuses an unknown key rather than silently ignoring it", function()
		local ok, err = pcall(function()
			Facet.navBar({ tittle = "typo" } :: any)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "tittle", 1, true) ~= nil).toBe(true)
	end)
end)
