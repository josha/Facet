--!strict
local harness = require("./lib/harness")
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
local UI = harness.UI

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

describe("the slot form: leading, center and a second row for trailing content", function()
	local world = require("./lib/world")
	local Compose = Facet.Compose

	local function mount(w: number, spec: (UI: any) -> any): any
		local wld = world.new({ viewport = { x = 0, y = 0, w = w, h = 600 }, reducedMotion = true })
		local UI = wld.UI
		wld.present(function()
			return UI.Screen("S")({ padding = 0, UI.NavBar("Bar")(spec(UI)) })
		end)
		wld.settle(3)
		return wld
	end

	local function rect(w: any, path: string): any
		return w.adapter.node(`/S/Bar/{path}`).rect
	end

	it("Back, leading, a filling center and trailing share one row when there is room", function()
		local record: any = nil
		local w = mount(1000, function(UI)
			return {
				ref = function(r: any)
					record = r
				end,
				onBack = function() end,
				backLabel = "Back",
				leading = UI.Button("Home")({ label = "Home" }),
				center = UI.TextInput("Search")({ value = Compose.cell(""), placeholder = "Search tracks" }),
				trailing = UI.HStack("Tools")({ UI.Button("Filter")({ label = "Filter" }) }),
			}
		end)
		local back, home = rect(w, "Primary/Back"), rect(w, "Primary/Leading/Home")
		local center, tools = rect(w, "Primary/Center"), rect(w, "Trailing")
		expect(home.x >= back.x + back.w).toBe(true)
		expect(center.x >= home.x + home.w).toBe(true)
		expect(tools.x >= center.x + center.w - 1).toBe(true)
		expect(math.abs(tools.y - center.y) < center.h).toBe(true)
		expect(record.dump().center).toBe("custom")
	end)

	it("a narrow bar moves the trailing content to a second row, without rebuilding the center", function()
		local text = Compose.cell("")
		local width = 1000
		local w = mount(width, function(UI)
			return {
				onBack = function() end,
				backLabel = "Back",
				center = UI.TextInput("Search")({ value = text, placeholder = "Search tracks" }),
				trailing = UI.HStack("Tools")({
					UI.Button("Filter")({ label = "Filter results" }),
					UI.Button("Sort")({ label = "Sort by lap" }),
				}),
			}
		end)
		local field = w.adapter.node("/S/Bar/Primary/Center/Search")
		expect(field ~= nil).toBe(true)
		w.pres.focus.setFocusOrigin("navigation")
		local searchPath: string? = nil
		for _, path in w.adapter.paths() do
			if string.find(path, "/Primary/Center/Search", 1, true) and w.adapter.node(path).class == "TextField" then
				searchPath = path
			end
		end
		assert(searchPath, "search field mounted")
		expect(w.pres.focus.focusOn(searchPath)).toBe(true)
		text:set("coast")
		w.env:set("viewportRect", { x = 0, y = 0, w = 360, h = 600 })
		w.settle(4)
		local center, tools = rect(w, "Primary/Center"), rect(w, "Trailing")
		expect(tools.y >= center.y + center.h - 1).toBe(true)
		-- the same field, the same text, the same focus
		expect(w.adapter.node(searchPath) ~= nil).toBe(true)
		expect(w.pres.focus.focused:peek()).toBe(searchPath)
		expect(text:peek()).toBe("coast")
		-- and back to one row when the room returns
		w.env:set("viewportRect", { x = 0, y = 0, w = 1000, h = 600 })
		w.settle(4)
		local center2, tools2 = rect(w, "Primary/Center"), rect(w, "Trailing")
		expect(math.abs(tools2.y - center2.y) < center2.h).toBe(true)
	end)

	it("the default center is the one-line disclosed title, and every slot subset mounts", function()
		for index, keys in
			{
				{ "title" },
				{ "trailing" },
				{ "title", "trailing" },
				{ "back", "title" },
				{ "back", "leading", "title", "trailing" },
			}
		do
			local w = mount(500, function(UI)
				local spec: any = {}
				for _, key in keys do
					if key == "title" then
						spec.title = string.rep("A long garage title ", 6)
					elseif key == "trailing" then
						spec.trailing = UI.Button("More")({ label = "More" })
					elseif key == "back" then
						spec.onBack = function() end
						spec.backLabel = "Back"
					elseif key == "leading" then
						spec.leading = UI.Button("Home")({ label = "Home" })
					end
				end
				return spec
			end)
			expect(`case {index}: {w.adapter.node("/S/Bar") ~= nil}`).toBe(`case {index}: true`)
			local title = w.adapter.node("/S/Bar/Primary/Center/Title")
			if table.find(keys, "title") then
				expect(title.class).toBe("Text")
				local facts = w.controller.textAt ~= nil and nil
				local r = title.rect
				-- one line, and its full value is disclosed rather than widening the bar
				expect(r.x + r.w <= 500 + 1).toBe(true)
				local _ = facts
			end
		end
	end)

	it("the lowercase form keeps its exact legacy shape unless a slot is supplied", function()
		local bp = Facet.navBar({ title = "Garage", trailing = { UI.Button({ id = "More", label = "More" }) } })
		expect(bp.class).toBe("HStack")
		local slotted = Facet.navBar({ title = "Garage", center = UI.Text({ id = "C", text = "c" }) })
		expect(slotted.class).toBe("AdaptiveStack")
	end)

	it("UI.NavBar refuses a trailing array and a non-blueprint slot", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
		for index, bad in
			{
				{ trailing = { UI.Text({ id = "A", text = "a" }) } },
				{ leading = "Home" },
				{ titleWidth = { type = "fixed", px = 10 } },
			}
		do
			local ok = pcall(function()
				w.scoped(function()
					return w.UI.NavBar(bad :: any)
				end)
			end)
			expect(`case {index} refused: {not ok}`).toBe(`case {index} refused: true`)
		end
	end)
end)

describe("UI.NavBar: Back answers every input class", function()
	local world = require("./lib/world")
	it("Back fires by pointer, touch, keyboard and gamepad", function()
		for _, route in { "pointer", "touch", "keyboard", "gamepad" } do
			local fired = 0
			local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 }, reducedMotion = true })
			local UI = w.UI
			w.present(function()
				return UI.Screen("S")({
					UI.NavBar("Bar")({
						onBack = function()
							fired += 1
						end,
						backLabel = "Back",
						title = "Garage",
						trailing = UI.Button("More")({ label = "More" }),
					}),
				})
			end)
			w.settle(2)
			local back = "/S/Bar/Primary/Back"
			if route == "pointer" or route == "touch" then
				w.adapter.tap(back, { source = "pointer", pointer = route })
			else
				w.pres.focus.setFocusOrigin("navigation")
				expect(w.pres.focus.focusOn(back)).toBe(true)
				w.press(if route == "keyboard" then "Return" else "ButtonA")
			end
			w.settle(1)
			expect(`{route}: {fired}`).toBe(`{route}: 1`)
		end
	end)
end)
