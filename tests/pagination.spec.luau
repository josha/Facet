--!strict
--[[ UI.Pagination — controlled page selection with a bounded window (phase6
	P6b). Every case reads the MOUNTED row (the dump is built from the entries the
	row mounts) and the caller's cell, never a number it just set. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local world = require("./lib/world")
local Facet = require("../src") :: any
local Compose = Facet.Compose
local pagination = require("../src/controls/pagination")

local ROOT = "/S/Page/P"

local function mount(spec: any, opts: any?): any
	local o = opts or {}
	local w = world.new({
		viewport = { x = 0, y = 0, w = o.w or 800, h = 400 },
		reducedMotion = true,
		capabilities = { mouse = true, keyboard = true, gamepad = true },
		hostOpts = { keyboardNavigation = true },
		env = o.env,
	})
	local UI = w.UI
	w.present(function()
		return UI.Screen("S")({
			UI.VStack("Page")({
				width = if o.hug then nil else UI.fill(),
				gap = "s",
				UI.Button("Before")({ label = "Before" }),
				UI.Pagination("P")(spec),
				UI.Button("After")({ label = "After" }),
			}),
		})
	end)
	w.settle(3)
	return w
end

local function controlled(initial: number, extra: any?): (any, any, { number })
	local page = Compose.cell(initial)
	local asked: { number } = {}
	local spec: any = {
		page = page,
		onChange = function(next: number)
			table.insert(asked, next)
			page:set(next)
		end,
	}
	for k, v in extra or {} do
		spec[k] = v
	end
	return spec, page, asked
end

local function text(w: any): string
	return w.record("P").dump().text
end

local function path(w: any, suffix: string): string
	for _, p in w.adapter.paths() do
		if string.sub(p, 1, #ROOT) == ROOT and string.sub(p, -#suffix) == suffix then
			return p
		end
	end
	error(`no mounted path ending {suffix}`)
end

describe("Pagination: the window", function()
	it("the seven-slot pattern near each edge and in the middle; a gap of one shows the page", function()
		local function row(current: number, count: number): string
			local out = {}
			local prev = nil
			for _, e in pagination.window(current, count, 1, 1) do
				if prev ~= nil and e.page > prev + 1 then
					table.insert(out, "…")
				end
				table.insert(out, tostring(e.page))
				prev = e.page
			end
			return table.concat(out, " ")
		end
		expect(row(1, 10)).toBe("1 2 3 4 5 … 10")
		expect(row(5, 10)).toBe("1 … 4 5 6 … 10")
		expect(row(10, 10)).toBe("1 … 6 7 8 9 10")
		expect(row(4, 10)).toBe("1 2 3 4 5 … 10")
		expect(row(3, 7)).toBe("1 2 3 4 5 6 7")
		expect(row(1, 1)).toBe("1")
		-- bounded work at the largest safe count, and exact arithmetic near it
		local huge = 9007199254740991
		expect(#pagination.window(huge - 3, huge, 20, 20) <= 83).toBe(true)
		expect(row(huge, huge)).toBe(`1 … {huge - 4} {huge - 3} {huge - 2} {huge - 1} {huge}`)
	end)

	it("mounts the window, marks the current page and proposes without writing", function()
		local page = Compose.cell(5)
		local asked: { number } = {}
		local w = mount({
			page = page,
			pageCount = 10,
			onChange = function(n: number)
				table.insert(asked, n)
			end,
		})
		expect(text(w)).toBe("previous 1 … 4 [5] 6 … 10 next")
		w.adapter.tap(path(w, "/Page-6"))
		w.adapter.tap(path(w, "/Next"))
		w.adapter.tap(path(w, "/Page-5"))
		w.settle(2)
		-- two proposals, the current page proposes nothing, and a refusal paints nothing
		expect(table.concat(asked, ",")).toBe("6,6")
		expect(page:peek()).toBe(5)
		expect(text(w)).toBe("previous 1 … 4 [5] 6 … 10 next")
		expect(w.adapter.node(path(w, "/Page-5")).props.selected).toBe(true)
	end)

	it("keeps overlapping page nodes when the window moves", function()
		local spec, page = controlled(5, { pageCount = 20 })
		local w = mount(spec)
		local six = w.adapter.node(path(w, "/Page-6"))
		page:set(6)
		w.settle(2)
		expect(text(w)).toBe("previous 1 … 5 [6] 7 … 20 next")
		expect(w.adapter.node(path(w, "/Page-6"))).toBe(six)
	end)
end)

describe("Pagination: counts and values", function()
	it("zero pages is inert context; one page has no enabled navigation", function()
		local count = Compose.cell(0)
		local spec, _, asked = controlled(1, { pageCount = count })
		local w = mount(spec)
		expect(text(w)).toBe("No pages")
		count:set(1)
		w.settle(2)
		expect(text(w)).toBe("previous [1] next")
		w.adapter.tap(path(w, "/Previous"))
		w.adapter.tap(path(w, "/Next"))
		expect(#asked).toBe(0)
		expect(w.pres.focus.focusOn(path(w, "/Next"))).toBe(false)
	end)

	it("an unknown count follows its flags, shows the page label and never a last page", function()
		local more = Compose.cell(true)
		local spec, _, asked = controlled(3, { hasNext = more, hasPrevious = true, showFirstLast = true })
		local w = mount(spec)
		expect(text(w)).toBe("first previous Page 3 next")
		w.adapter.tap(path(w, "/Next"))
		w.adapter.tap(path(w, "/First"))
		expect(table.concat(asked, ",")).toBe("4,1")
		more:set(false)
		w.settle(2)
		w.adapter.tap(path(w, "/Next"))
		expect(#asked).toBe(2)
	end)

	it("an outside page is shown clamped with a diagnostic and never written back", function()
		local spec, page, asked = controlled(40, { pageCount = 12 })
		local w = mount(spec)
		expect(w.record("P").dump().current).toBe(12)
		expect(page:peek()).toBe(40)
		expect(#asked).toBe(0)
		expect(#w.record("P").api.diagnostics() >= 1).toBe(true)
	end)

	it("refuses malformed construction and keeps the last legal value for a late one", function()
		local w = world.new()
		local UI = w.UI
		local bad = {
			{ page = 1.5, onChange = print },
			{ page = 0 / 0, onChange = print },
			{ page = math.huge, onChange = print },
			{ page = 1 },
			{ page = 1, onChange = print, pageCount = -1 },
			{ page = 1, onChange = print, siblingCount = 21 },
			{ page = 1, onChange = print, form = "dots" },
			{ page = 1, onChange = print, direction = "up" },
			{ page = 1, onChange = print, extra = true },
			-- the window narrows to its offer; a hugging box has none of its own
			{ page = 1, onChange = print, width = UI.hug() },
		}
		for _, spec in bad do
			expect(pcall(function()
				w.scoped(function()
					return UI.Pagination(spec)
				end)
			end)).toBe(false)
		end
		local spec, page = controlled(3, { pageCount = 10 })
		local m = mount(spec)
		page:set(2.5)
		m.settle(2)
		expect(m.record("P").dump().current).toBe(3)
		page:set(4)
		m.settle(2)
		expect(m.record("P").dump().current).toBe(4)
	end)
end)

describe("Pagination: fit, direction and focus", function()
	it(
		"four-digit pages keep full targets; narrow room drops the farthest boundary page, then neighbours, then labels",
		function()
			local spec = controlled(5000, { pageCount = 9999 })
			local wide = mount(spec, { w = 800 })
			expect(text(wide)).toBe("previous 1 … 4999 [5000] 5001 … 9999 next")
			local page = wide.adapter.node(path(wide, "/Page-5000")).rect
			expect(page.w >= 44).toBe(true)
			local mid = mount(controlled(5000, { pageCount = 9999 }), { w = 330 })
			expect(text(mid)).toBe("previous 4999 [5000] 5001 next")
			local tight = mount(controlled(5000, { pageCount = 9999 }), { w = 190 })
			expect(text(tight)).toBe("previous [5000] next")
			local tiny = mount(controlled(5000, { pageCount = 9999 }), { w = 120 })
			expect(text(tiny)).toBe("previous Page 5000 of 9999 next")
		end
	)

	-- G2: a hugging parent's width is the row the control drew, not an offer
	it("a hugging parent settles on the same window a filling one shows at that width", function()
		for _, w in { 800, 330, 190 } do
			local filled = text(mount(controlled(5000, { pageCount = 9999 }), { w = w }))
			local hugged = text(mount(controlled(5000, { pageCount = 9999 }), { w = w, hug = true }))
			expect(`{w}:{hugged}`).toBe(`{w}:{filled}`)
		end
	end)

	it("rtl reverses the row once and keeps previous/next meaning", function()
		local spec, _, asked = controlled(5, { pageCount = 10, direction = "rtl" })
		local w = mount(spec)
		expect(text(w)).toBe("next 10 … 6 [5] 4 … 1 previous")
		local nextRect = w.adapter.node(path(w, "/Next")).rect
		local prevRect = w.adapter.node(path(w, "/Previous")).rect
		expect(nextRect.x < prevRect.x).toBe(true)
		w.adapter.tap(path(w, "/Next"))
		expect(asked[1]).toBe(6)
	end)

	it("is reached from its neighbours, and a vanished focused page leaves focus inside", function()
		local spec, page = controlled(5, { pageCount = 20 })
		local w = mount(spec)
		expect(w.pres.focus.focusOn("/S/Page/Before")).toBe(true)
		w.pres.focus.setFocusOrigin("navigation")
		w.press("Down")
		local first = w.pres.focus.focused:peek() or ""
		expect(string.sub(first, 1, #ROOT)).toBe(ROOT)
		expect(w.pres.focus.focusOn(path(w, "/Page-4"))).toBe(true)
		page:set(9)
		w.settle(3)
		-- recovered onto the current page, the nearest legal one
		expect(w.pres.focus.focused:peek()).toBe(path(w, "/Page-9"))
	end)

	it("an arrow that disables at an edge hands focus to the current page", function()
		for _, case in
			{
				{ from = 9, arrow = "/Next", lands = "/Page-10" },
				{ from = 2, arrow = "/Previous", lands = "/Page-1" },
				{ from = 3, arrow = "/First", lands = "/Page-1" },
				{ from = 7, arrow = "/Last", lands = "/Page-10" },
			}
		do
			local spec = controlled(case.from, { pageCount = 10, showFirstLast = true })
			local w = mount(spec)
			expect(w.pres.focus.focusOn(path(w, case.arrow))).toBe(true)
			w.pres.focus.setFocusOrigin("navigation")
			w.press("Return")
			w.settle(4)
			expect(w.pres.focus.focused:peek()).toBe(path(w, case.lands))
		end
	end)

	it("page buttons and arrows reserve the target floor: no two hit bands overlap", function()
		local w = mount(controlled(5, { pageCount = 200, showFirstLast = true }))
		local rects = {}
		for _, p in w.adapter.paths() do
			local node = w.adapter.node(p)
			if string.sub(p, 1, #ROOT) == ROOT and node.class == "Button" then
				table.insert(rects, w.adapter.hitRectOf(p) or node.rect)
			end
		end
		expect(#rects).toBe(9)
		for i = 1, #rects do
			for j = i + 1, #rects do
				local r, q = rects[i], rects[j]
				expect(r.x < q.x + q.w - 0.5 and q.x < r.x + r.w - 0.5).toBe(false)
			end
		end
	end)

	it("a page is a small plate centred in a target-wide slot (owner: the big button look is out)", function()
		local w = mount(controlled(5, { pageCount = 10 }))
		local page = w.adapter.node(path(w, "/Page-5")).rect
		local slot = w.adapter.node(path(w, "/Slot-5")).rect
		expect(page.w < 44).toBe(true)
		expect(slot.w >= 44).toBe(true)
		expect(math.abs((page.x + page.w / 2) - (slot.x + slot.w / 2)) <= 1).toBe(true)
		local hit = w.adapter.hitRectOf(path(w, "/Page-5")) or page
		expect(hit.x >= slot.x - 0.5 and hit.x + hit.w <= slot.x + slot.w + 0.5).toBe(true)
	end)

	it("the arrows hold still while the label grows a digit, ltr and rtl, known and unknown (owner)", function()
		for _, case in
			{
				{ extra = { pageCount = 12, form = "label" }, from = 9, to = 10 },
				{ extra = { pageCount = 12, form = "label", direction = "rtl" }, from = 9, to = 10 },
				{ extra = { hasNext = true, hasPrevious = true }, from = 9, to = 10 },
				{ extra = { hasNext = true, hasPrevious = true, direction = "rtl" }, from = 99, to = 100 },
			}
		do
			local spec, page = controlled(case.from, case.extra)
			local w = mount(spec)
			local function arrows(): string
				local n, p = w.adapter.node(path(w, "/Next")).rect, w.adapter.node(path(w, "/Previous")).rect
				return `{n.x},{p.x}`
			end
			local before = arrows()
			page:set(case.to)
			w.settle(3)
			local where = `{case.extra.direction or "ltr"} {case.extra.pageCount or "?"} {case.to}`
			expect(`{where} {arrows()}`).toBe(`{where} {before}`)
		end
	end)

	it("count to zero leaves no internal stop and focus returns to a live neighbour", function()
		local count = Compose.cell(3)
		local spec = controlled(2, { pageCount = count })
		local w = mount(spec)
		expect(w.pres.focus.focusOn(path(w, "/Page-3"))).toBe(true)
		count:set(0)
		w.settle(3)
		local now = w.pres.focus.focused:peek() or ""
		expect(now == "/S/Page/Before" or now == "/S/Page/After").toBe(true)
	end)

	it("a callback that changes the count or disposes the control is safe", function()
		local show = Compose.cell(true)
		local count = Compose.cell(10)
		local page = Compose.cell(2)
		local asked = 0
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 400 }, reducedMotion = true })
		local UI = w.UI
		w.present(function()
			return UI.Screen("S")({
				UI.When("Gate")({
					condition = show,
					thenView = function()
						return UI.Pagination("P")({
							page = page,
							pageCount = count,
							onChange = function(n: number)
								asked += 1
								count:set(3)
								page:set(n)
								show:set(false)
							end,
						})
					end,
				}),
			})
		end)
		w.settle(3)
		w.adapter.tap("/S/Gate/then/P/Row/Items/[next]/Next")
		w.settle(3)
		expect(asked).toBe(1)
		expect(w.adapter.node("/S/Gate/then/P")).toBeNil()
	end)
end)

describe("Pagination: the gallery tab", function()
	it("the Paging scenario's results context follows an accepted page, and a refusal changes nothing", function()
		local scenario = require("../examples/gallery/scenarios/paging") :: any
		local w = world.new({ viewport = { x = 0, y = 0, w = 1000, h = 800 }, reducedMotion = true })
		local built =
			scenario.build({ Facet = Facet, UI = w.UI, Compose = Compose, app = w.app, core = w.core, env = w.env })
		w.present(built.screen)
		w.settle(3)
		local function find(suffix: string): string
			for _, p in w.adapter.paths() do
				if string.sub(p, -#suffix) == suffix then
					return p
				end
			end
			error(suffix)
		end
		local context = find("/ResultsContext")
		expect(w.adapter.node(context).props.text).toBe("Showing results 81–100 of 4000")
		w.adapter.tap(find("/Results/Row/Items/[next]/Next"))
		w.settle(2)
		expect(w.adapter.node(context).props.text).toBe("Showing results 101–120 of 4000")
		w.adapter.tap(find("/Paging/Refuse"))
		w.settle(2)
		w.adapter.tap(find("/Results/Row/Items/[next]/Next"))
		w.settle(2)
		expect(w.adapter.node(context).props.text).toBe("Showing results 101–120 of 4000")
	end)
end)

return nil
