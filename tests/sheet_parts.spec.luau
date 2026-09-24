--!strict
--[[ UI.Sheet parts: a pinned header region, one body-only scroller, pinned
	actions, a sticky or scrolling hero, and one keyboard-safe room. Every case
	asserts what is mounted and where, and scrolls through the adapter. ]]
local harness = require("./lib/harness")
local t = require("./lib/testkit")
local world = require("./lib/harness_world")
local fake = require("./lib/fake_target")
local Compose = require("../src/vendor/compose/core")
local UI = harness.UI

local PANEL = "/Sheet/Layer/Panel"
local COLUMN = `{PANEL}/Room/Column`
local LONG = string.rep("A long line of body copy that wraps across the sheet. ", 40)

local function mount(extra: any?, o: any?): (any, any, any)
	local opts = o or {}
	local w = world.new({
		viewport = { x = 0, y = 0, w = opts.w or 800, h = opts.h or 600 },
		reducedMotion = true,
		env = opts.facts,
		newAdapter = function()
			local a = fake.new()
			a.scrollBarThickness = fake.SCROLL_BAR_RESERVE
			return a
		end,
	})
	local detent = Compose.cell(opts.detent or "large")
	local spec: any = {
		id = "Sheet",
		title = "Race details",
		detent = detent,
		content = UI.Text({ id = "Copy", text = LONG, width = UI.fill() }),
	}
	for k, v in extra or {} do
		spec[k] = v
	end
	local control = harness.Controls.Sheet(w.core, spec)
	w.present(UI.Screen({ id = "Base", children = { UI.Button({ id = "Open", label = "Open" }) } }))
	control.present(w.pres)
	w.settle(3)
	return w, control, detent
end

local function rect(w: any, path: string): any
	local node = w.adapter.node(path)
	assert(node ~= nil, `no node at {path}`)
	return node.rect
end

local function find(w: any, suffix: string): string?
	for _, path in w.adapter.paths() do
		if string.sub(path, -#suffix) == suffix then
			return path
		end
	end
	return nil
end

local function inside(inner: any, outer: any): boolean
	return inner.x >= outer.x - 0.5
		and inner.y >= outer.y - 0.5
		and inner.x + inner.w <= outer.x + outer.w + 0.5
		and inner.y + inner.h <= outer.y + outer.h + 0.5
end

local function overlaps(a: any, b: any): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local noop = function() end

t.describe("Sheet parts", function()
	t.it("default parts: pinned title and utilities, one body scroller (the panel no longer scrolls)", function()
		local w, c = mount()
		t.expect(w.adapter.node(PANEL).class).toBe("VStack")
		t.expect(w.adapter.node(`{COLUMN}/Body`).class).toBe("ScrollView")
		t.expect(w.adapter.node(`{COLUMN}/Title`) ~= nil).toBe(true)
		t.expect(w.adapter.node(`{COLUMN}/Header/Size`) ~= nil).toBe(true)
		t.expect(w.adapter.node(`{COLUMN}/Header/Close`) ~= nil).toBe(true)
		local body, copy = rect(w, `{COLUMN}/Body`), rect(w, `{COLUMN}/Body/Copy`)
		t.expect(copy.h > body.h).toBe(true)
		local title = rect(w, `{COLUMN}/Title`)
		w.adapter.setScrollPosition(w.adapter.node(`{COLUMN}/Body`), { x = 0, y = 200 })
		w.settle(2)
		t.expect(rect(w, `{COLUMN}/Title`).y).toBe(title.y)
		t.expect(w.adapter.node(`{COLUMN}/Body`).scrollPosition.y).toBe(200) -- the body canvas overflows
		c.dispose()
	end)

	t.it("contentInset none drops only the body padding", function()
		local w, c = mount()
		local standard = rect(w, `{COLUMN}/Body/Copy`).x - rect(w, `{COLUMN}/Body`).x
		c.dispose()
		w, c = mount({ contentInset = "none" })
		local none = rect(w, `{COLUMN}/Body/Copy`).x - rect(w, `{COLUMN}/Body`).x
		t.expect(standard > 0).toBe(true)
		t.expect(none).toBe(0)
		t.expect(rect(w, PANEL).w > 0).toBe(true)
		c.dispose()
	end)

	t.it("a header blueprint replaces the title; header=false removes it; utilities stay", function()
		local w, c = mount({
			header = UI.HStack({ id = "Custom", width = UI.fill(), children = { UI.Text({ text = "Lobby" }) } }),
		})
		t.expect(w.adapter.node(`{COLUMN}/Title`)).toBeNil()
		t.expect(w.adapter.node(`{COLUMN}/Custom`) ~= nil).toBe(true)
		t.expect(w.adapter.node(`{COLUMN}/Header/Size`) ~= nil).toBe(true)
		t.expect(w.adapter.node(`{COLUMN}/Header/Close`) ~= nil).toBe(true)
		c.dispose()
		w, c = mount({ header = false })
		t.expect(w.adapter.node(`{COLUMN}/Title`)).toBeNil()
		t.expect(w.adapter.node(`{COLUMN}/Header/Close`) ~= nil).toBe(true)
		c.dispose()
	end)

	t.it("pinned actions stay reachable over a long body; Cancel runs the cancel action", function()
		local pressed = {}
		local function log(name: string): () -> ()
			return function()
				table.insert(pressed, name)
			end
		end
		local w, c = mount({
			actions = {
				{ id = "Later", label = "Later", role = "cancel", onActivate = log("Later") },
				{ id = "Join", label = "Join race", role = "default", onActivate = log("Join") },
			},
		})
		local panel = rect(w, PANEL)
		local join = assert(find(w, "/Join"), "Join is mounted")
		t.expect(inside(rect(w, join), panel)).toBe(true)
		local before = rect(w, join).y
		w.adapter.setScrollPosition(w.adapter.node(`{COLUMN}/Body`), { x = 0, y = 300 })
		w.settle(2)
		t.expect(rect(w, join).y).toBe(before)
		w.adapter.tap(join)
		w.settle(2)
		t.expect(pressed).toEqual({ "Join" })
		t.expect(c.dump().presented).toBe(true) -- actions never close by themselves
		w.press("ButtonB")
		t.expect(pressed).toEqual({ "Join", "Later" })
		t.expect(c.dump().presented).toBe(true)
		c.dispose()
	end)

	t.it("a room too small for the pinned regions unpins them into one scroller", function()
		local noop = function() end
		local w, c = mount({
			actionLayout = "stacked",
			actions = {
				{ id = "One", label = "One", onActivate = noop },
				{ id = "Two", label = "Two", onActivate = noop },
				{ id = "Three", label = "Three", onActivate = noop },
			},
		}, { detent = "medium" })
		local room = w.adapter.node(`{PANEL}/Room`)
		t.expect(room.props.scrollEnabled).toBe(true)
		-- the last action lies inside the room's scrollable canvas, and a pad
		-- walking to it brings it into view
		local three = assert(find(w, "/Three"), "Three")
		for _ = 1, 12 do
			if w.pres.focus.focused:peek() == three then
				break
			end
			w.press("DPadDown")
			w.settle(1)
		end
		t.expect(w.pres.focus.focused:peek()).toBe(three)
		local scrolled = (w.adapter.node(`{PANEL}/Room`).scrollPosition or { y = 0 }).y
		local r, box = rect(w, three), room.rect
		t.expect(r.y - scrolled + r.h <= box.y + box.h + 1).toBe(true)
		-- the same sheet at its large detent keeps everything pinned
		c.dispose()
		w = mount({ actions = { { id = "One", label = "One", onActivate = noop } } })
		t.expect(w.adapter.node(`{PANEL}/Room`).props.scrollEnabled).toBe(false)
	end)

	t.it("a sticky image hero stays pinned; header=false puts Close and Size over it", function()
		local w, c = mount({
			header = false,
			hero = { image = "rbxassetid://1", height = 160, sticky = true },
		})
		local hero = assert(find(w, "/Hero"), "hero mounted")
		local close = assert(find(w, "/Close"), "close mounted")
		local size = assert(find(w, "/Size"), "size mounted")
		t.expect(inside(rect(w, close), rect(w, hero))).toBe(true)
		t.expect(inside(rect(w, size), rect(w, hero))).toBe(true)
		t.expect(rect(w, close).h >= 44).toBe(true)
		t.expect(w.adapter.node(`{COLUMN}/Header`)).toBeNil() -- no empty header strip
		local y = rect(w, hero).y
		local body = assert(find(w, "/Body"), "body")
		w.adapter.setScrollPosition(w.adapter.node(body), { x = 0, y = 200 })
		w.settle(2)
		t.expect(rect(w, hero).y).toBe(y)
		w.adapter.tap(close)
		w.settle(2)
		t.expect(c.dump().presented).toBe(false)
		c.dispose()
	end)

	t.it("a scrolling content hero reserves the utility strip; utilities stay pinned", function()
		local w, c = mount({
			header = false,
			hero = {
				height = 200,
				content = UI.VStack({
					id = "Art",
					width = UI.fill(),
					children = { UI.Button({ id = "Top", label = "Top of hero" }) },
				}),
			},
		})
		local close = assert(find(w, "/Close"), "close")
		local size = assert(find(w, "/Size"), "size")
		local top = assert(find(w, "/Art/Top"), "hero content")
		t.expect(overlaps(rect(w, top), rect(w, close))).toBe(false)
		t.expect(overlaps(rect(w, top), rect(w, size))).toBe(false)
		local closeY = rect(w, close).y
		local heroPath = assert(find(w, "/Hero"), "hero")
		local body = assert(find(w, "/Body"), "body")
		t.expect(string.find(heroPath, "/Body/Hero", 1, true) ~= nil).toBe(true) -- scrolls with the body
		w.adapter.setScrollPosition(w.adapter.node(body), { x = 0, y = 120 })
		w.settle(2)
		t.expect(w.adapter.node(body).scrollPosition.y).toBe(120)
		t.expect(rect(w, close).y).toBe(closeY)
		c.dispose()
	end)

	t.it("a non-sticky hero spans the panel width without the body inset", function()
		local w, c = mount({ hero = { image = "rbxassetid://1", aspectRatio = 16 / 9 } })
		local hero = rect(w, assert(find(w, "/Hero"), "hero"))
		local copy = rect(w, assert(find(w, "/Copy"), "copy"))
		t.expect(hero.x < copy.x).toBe(true)
		t.expect(math.abs(hero.h - hero.w * 9 / 16) < 1).toBe(true)
		c.dispose()
	end)

	t.it("the keyboard takes its room from the one safe rectangle", function()
		local w, c = mount({ actions = { { id = "Go", label = "Go", onActivate = noop } } })
		local tall = rect(w, PANEL).h
		w.env:set("keyboardOcclusionRect", { x = 0, y = 350, w = 800, h = 250 })
		w.settle(3)
		local panel = rect(w, PANEL)
		t.expect(panel.h < tall).toBe(true)
		t.expect(panel.y + panel.h <= 350 + 0.5).toBe(true)
		t.expect(inside(rect(w, assert(find(w, "/Go"), "Go")), panel)).toBe(true)
		t.expect(inside(rect(w, `{COLUMN}/Header/Close`), panel)).toBe(true)
		w.env:set("keyboardOcclusionRect", nil)
		w.settle(3)
		t.expect(rect(w, PANEL).h).toBe(tall)
		c.dispose()
	end)

	t.it("refuses malformed header, hero, actions and inset before mounting", function()
		local w = world.new()
		for _, change in
			{
				{ header = true },
				{ header = "Title" },
				{ contentInset = "wide" },
				{ hero = { image = "rbxassetid://1", content = UI.Text({ text = "x" }), height = 10 } },
				{ hero = { height = 10 } },
				{ hero = { content = UI.Text({ text = "x" }), height = 10, scaleMode = "fit" } },
				{ hero = { image = "rbxassetid://1", height = 10, sticky = "yes" } },
				{ actions = { { id = "A", label = "A" } } },
				{
					actions = {
						{ id = "A", label = "A", role = "default", onActivate = noop },
						{
							id = "B",
							label = "B",
							role = "default",
							onActivate = noop,
						},
					},
				},
				{ actionLayout = "grid" },
			}
		do
			local spec: any = { title = "Details", detent = Compose.cell("medium"), content = UI.Text({ text = "C" }) }
			for k, v in change do
				spec[k] = v
			end
			t.expect(pcall(function()
				harness.Controls.Sheet(w.core, spec)
			end)).toBe(false)
		end
	end)

	-- ===== hug detents, ordering and late values ============================
	local function natural(w: any): number
		local body = w.adapter.node(`{COLUMN}/Body`)
		local top, bottom = math.huge, -math.huge
		for _, path in w.adapter.paths() do
			local parent = string.match(path, "^(.*)/[^/]+$")
			if parent == body.path then
				local r = w.adapter.node(path).rect
				top, bottom = math.min(top, r.y), math.max(bottom, r.y + r.h)
			end
		end
		return bottom - top
	end
	t.it("hug fits the whole body plus the pinned regions, and follows live copy both ways", function()
		local copy = Compose.cell("Two short lines.")
		local builds = 0
		local w, c = mount({
			detents = { "hug", "large" },
			content = function()
				builds += 1
				-- a fixed width: a hugging panel's width follows its content, which
				-- is not what this case measures
				return UI.Text({ id = "Copy", text = copy, width = { type = "fixed", px = 420 } })
			end,
			actions = { { id = "Go", label = "Go", onActivate = noop } },
		}, { detent = "hug" })
		local body = w.adapter.node(`{COLUMN}/Body`)
		local short = rect(w, PANEL).h
		t.expect(short < 600).toBe(true)
		t.expect(body.rect.h >= natural(w) - 0.5).toBe(true)
		w.adapter.setScrollPosition(body, { x = 0, y = 40 })
		t.expect(body.scrollPosition.y).toBe(0) -- nothing clipped: no canvas to scroll
		copy:set(string.rep("Longer copy that wraps onto several lines. ", 8))
		w.settle(4)
		local tall = rect(w, PANEL).h
		t.expect(tall > short).toBe(true)
		t.expect(w.adapter.node(`{COLUMN}/Body`).rect.h >= natural(w) - 0.5).toBe(true)
		copy:set("Two short lines.")
		w.settle(4)
		t.expect(rect(w, PANEL).h).toBe(short)
		-- larger text re-measures without rebuilding the content
		w.env:set("preferredTextOffset", 10)
		w.settle(4)
		t.expect(rect(w, PANEL).h > short).toBe(true)
		t.expect(w.adapter.node(`{COLUMN}/Body`).rect.h >= natural(w) - 0.5).toBe(true)
		t.expect(builds).toBe(1)
		c.dispose()
	end)
	t.it("hug clamps to the safe room and keeps the minimum floor", function()
		local w, c = mount({ detents = { "hug" } }, { detent = "hug" })
		t.expect(rect(w, PANEL).h).toBe(600)
		c.dispose()
		w, c = mount({ detents = { "hug" }, content = UI.Text({ id = "Copy", text = "x" }) }, { detent = "hug" })
		t.expect(rect(w, PANEL).h >= 4 * 44 + 2 * 16).toBe(true)
		c.dispose()
	end)
	t.it("coinciding heights keep the declared id; Size cycles distinct ids; ties keep the current", function()
		local w, c, d = mount({
			detents = { { id = "a", height = 300 }, { id = "b", height = 300 }, "large" },
		}, { detent = "b" })
		t.expect(d:peek()).toBe("b")
		t.expect(rect(w, PANEL).h).toBe(300)
		local seen = {}
		for _ = 1, 3 do
			w.adapter.tap(`{COLUMN}/Header/Size`)
			w.settle(2)
			table.insert(seen, d:peek())
		end
		t.expect(seen).toEqual({ "large", "a", "b" })
		-- a release that lands on the shared height keeps the current id
		local drag = `{PANEL}/Drag/Handle`
		local r = rect(w, drag)
		w.adapter.pointerDown(drag, r.x + 10, r.y + 10, "touch")
		w.adapter.pointerMove(r.x + 10, r.y + 12)
		w.adapter.pointerUp(r.x + 10, r.y + 12)
		w.settle(3)
		t.expect(d:peek()).toBe("b")
		c.dispose()
	end)
	t.it("an invalid late detent keeps the last geometry and a valid one recovers", function()
		local w, c, d = mount(nil, { detent = "medium" })
		local before = rect(w, PANEL).h
		pcall(function()
			d:set("bogus")
		end)
		w.settle(3)
		t.expect(rect(w, PANEL).h).toBe(before)
		d:set("large")
		w.settle(3)
		t.expect(rect(w, PANEL).h).toBe(600)
		c.dispose()
	end)
	t.it("refuses a malformed hug entry", function()
		local w = world.new()
		for _, detents in { { "hug", "hug" }, { { id = "hug", fraction = 0.5 }, "hug" }, { "Hug" } } do
			t.expect(pcall(function()
				harness.Controls.Sheet(w.core, {
					title = "D",
					detent = Compose.cell("hug"),
					detents = detents,
					content = UI.Text({ text = "C" }),
				})
			end)).toBe(false)
		end
	end)

	-- ===== lifetime around callbacks and failed builds =======================
	t.it("action callbacks that throw, close or dispose leave no stale surface", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 }, reducedMotion = true })
		local baseline = w.core.owner.size()
		local shown = Compose.cell(false)
		local control: any = nil
		control = harness.Controls.Sheet(w.core, {
			id = "Sheet",
			title = "T",
			detent = Compose.cell("large"),
			isPresented = shown,
			presenter = w.pres,
			content = UI.Text({ text = "Body" }),
			actions = {
				{
					id = "Boom",
					label = "Boom",
					onActivate = function()
						error("caller bug")
					end,
				},
				{
					id = "Finish",
					label = "Done",
					onActivate = function()
						shown:set(false)
						shown:set(true) -- reopen inside the callback
					end,
				},
				{
					id = "Drop",
					label = "Drop",
					onActivate = function()
						control.dispose()
					end,
				},
			},
		})
		shown:set(true)
		w.settle(3)
		t.expect((pcall(w.adapter.tap, assert(find(w, "/Boom"), "Boom")))).toBe(false) -- raised, not swallowed
		w.settle(2)
		t.expect(control.dump().presented).toBe(true)
		w.adapter.tap(assert(find(w, "/Finish"), "Done"))
		w.settle(3)
		t.expect(control.dump().presented).toBe(true)
		t.expect(shown:peek()).toBe(true)
		w.adapter.tap(assert(find(w, "/Drop"), "Drop"))
		w.settle(3)
		t.expect(w.adapter.node(PANEL)).toBeNil()
		t.expect(shown:peek()).toBe(false)
		t.expect(w.core.owner.size()).toEqual(baseline)
	end)
	-- header and hero content are blueprints, built before the sheet sees them;
	-- the content builder is the one part that runs at present time
	t.it("a failing content build does not leave a surface behind", function()
		for _, broken in
			{
				{
					content = function()
						error("content failed")
					end,
				},
			}
		do
			local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 }, reducedMotion = true })
			local spec: any =
				{ id = "Sheet", title = "T", detent = Compose.cell("medium"), content = UI.Text({ text = "B" }) }
			for k, v in broken do
				spec[k] = v
			end
			local ok, control = pcall(harness.Controls.Sheet, w.core, spec)
			if ok then
				pcall(control.present, w.pres)
				w.settle(3)
				control.dispose()
				w.settle(3)
			end
			t.expect(w.adapter.node(PANEL)).toBeNil()
		end
	end)
end)
