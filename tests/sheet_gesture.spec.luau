--!strict
--[[ UI.Sheet gestures, headless: the Grip handle, the panel's native drag
	detector and the engine's touch-pan stream, all through the adapter seams a
	device drives. A scripted clock makes every flick replay exactly. The OS
	gesture itself (a real UIDragDetector, a real TouchPan) is native evidence. ]]
local harness = require("./lib/harness")
local t = require("./lib/testkit")
local world = require("./lib/harness_world")
local fake = require("./lib/fake_target")
local Compose = require("../src/vendor/compose/core")
local UI = harness.UI

local PANEL = "/Sheet/Layer/Panel"
local GRIP = `{PANEL}/Drag/Handle`
local LONG = string.rep("A long line of body copy that wraps across the sheet. ", 40)

local function mount(extra: any?, o: any?): any
	local opts = o or {}
	local clock = { now = 0 }
	local w = world.new({
		viewport = { x = 0, y = 0, w = 800, h = 600 },
		reducedMotion = opts.reducedMotion ~= false,
		capabilities = opts.capabilities,
		presenterOpts = {
			now = function()
				return clock.now
			end,
		},
		newAdapter = function()
			local a = fake.new()
			a.scrollBarThickness = fake.SCROLL_BAR_RESERVE
			return a
		end,
	})
	local detent = Compose.cell(opts.detent or "medium")
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
	return { w = w, c = control, d = detent, clock = clock }
end

local function h(s: any): number
	return s.w.adapter.node(PANEL).rect.h
end

-- a Grip drag in timed steps: { dy, dt } pairs
local function gripDrag(s: any, steps: { { number } }, kind: string?, finish: boolean?)
	local r = s.w.adapter.node(GRIP).rect
	local x, y = r.x + r.w / 2, r.y + r.h / 2
	s.w.adapter.pointerDown(GRIP, x, y, kind or "touch")
	for _, step in steps do
		s.clock.now += step[2]
		y += step[1]
		s.w.adapter.pointerMove(x, y)
	end
	if finish ~= false then
		s.w.adapter.pointerUp(x, y)
		s.w.settle(3)
	end
end

local function pan(s: any, path: string, state: string, ty: number, fingers: number?)
	local node = s.w.adapter.node(path)
	assert(node ~= nil and node.touchGestures ~= nil, `no pan observer on {path}`)
	local positions = {}
	for i = 1, fingers or 1 do
		table.insert(positions, { x = 100 * i, y = 300 + ty })
	end
	node.touchGestures({
		kind = "pan",
		state = state,
		positions = positions,
		totalTranslation = { x = 0, y = ty },
		velocity = { x = 0, y = 0 },
	})
end

t.describe("Sheet gestures", function()
	t.it("a fast flick projects past the nearest detent; a slow drag does not", function()
		local s = mount()
		gripDrag(s, { { -40, 0.01 }, { -40, 0.01 } })
		t.expect(s.d:peek()).toBe("large") -- 380 + 8000*0.15
		s.c.dispose()
		s = mount()
		gripDrag(s, { { -40, 0.5 }, { -40, 0.5 } })
		t.expect(s.d:peek()).toBe("medium") -- 380, slow
		s.c.dispose()
	end)

	t.it("a hold after motion does not fling", function()
		local s = mount()
		local r = s.w.adapter.node(GRIP).rect
		local x, y = r.x + 10, r.y + 10
		s.w.adapter.pointerDown(GRIP, x, y, "touch")
		s.clock.now += 0.01
		s.w.adapter.pointerMove(x, y - 80)
		s.clock.now += 0.6 -- held still
		s.w.adapter.pointerUp(x, y - 80)
		s.w.settle(3)
		t.expect(s.d:peek()).toBe("medium")
		s.c.dispose()
	end)

	t.it("losing the active class cancels even while the other direct class remains", function()
		local s = mount(nil, { capabilities = { mouse = true, touch = true, keyboard = true } })
		gripDrag(s, { { -150, 0.1 } }, "touch", false)
		t.expect(s.c.dump().dragging).toBe(true)
		s.w.env:set("capabilities", { mouse = true, keyboard = true })
		s.w.settle(3)
		t.expect(s.c.dump().dragging).toBe(false)
		t.expect(s.d:peek()).toBe("medium")
		t.expect(h(s)).toBe(300)
		s.c.dispose()
	end)

	t.it("an unrelated class change carries the drag", function()
		local s = mount(nil, { capabilities = { mouse = true, touch = true, keyboard = true } })
		gripDrag(s, { { -150, 0.1 } }, "touch", false)
		s.w.env:set("capabilities", { mouse = true, touch = true, keyboard = true, gamepad = true })
		s.w.settle(1)
		t.expect(s.c.dump().dragging).toBe(true)
		t.expect(math.abs(h(s) - 450) < 1).toBe(true)
		s.c.dispose()
	end)

	t.it("an external detent change during a drag wins and drops the stale session", function()
		local s = mount()
		gripDrag(s, { { -100, 0.1 } }, "touch", false)
		s.d:set("large")
		s.w.settle(3)
		t.expect(s.c.dump().dragging).toBe(false)
		t.expect(s.d:peek()).toBe("large")
		t.expect(h(s)).toBe(600)
		s.c.dispose()
	end)

	t.it("the panel's native detector acquires only past the pointer slop", function()
		local s = mount()
		local panel = s.w.adapter.node(PANEL)
		t.expect(panel.dragDetector ~= nil).toBe(true)
		local y = panel.rect.y + 60
		s.w.adapter.driveDragStart(PANEL, { x = 400, y = y })
		s.clock.now += 0.05
		s.w.adapter.driveDragContinue(PANEL, { x = 400, y = y - 4 }, { x = 0, y = -4 })
		s.w.settle(1)
		t.expect(h(s)).toBe(300)
		t.expect(s.c.dump().dragging).toBe(false)
		s.clock.now += 0.5
		s.w.adapter.driveDragContinue(PANEL, { x = 400, y = y - 250 }, { x = 0, y = -250 })
		s.w.settle(1)
		t.expect(s.c.dump().dragging).toBe(true)
		s.clock.now += 0.5
		s.w.adapter.driveDragEnd(PANEL, { x = 400, y = y - 250 })
		s.w.settle(3)
		t.expect(s.d:peek()).toBe("large")
		s.c.dispose()
	end)

	t.it("a touch pan on the panel drives the sheet; a second stream cannot take it over", function()
		local s = mount()
		pan(s, PANEL, "began", 0)
		s.clock.now += 0.3
		pan(s, PANEL, "changed", -200)
		s.w.settle(1)
		t.expect(math.abs(h(s) - (300 + 200 - 14)) < 1.5).toBe(true) -- from the slop point
		-- the Grip cannot start a second session while the pan owns it
		local r = s.w.adapter.node(GRIP).rect
		s.w.adapter.pointerDown(GRIP, r.x + 5, r.y + 5, "touch")
		s.w.adapter.pointerMove(r.x + 5, r.y + 300)
		s.w.adapter.pointerUp(r.x + 5, r.y + 300)
		t.expect(s.c.dump().dragging).toBe(true)
		s.clock.now += 0.3
		pan(s, PANEL, "ended", -200)
		s.w.settle(3)
		t.expect(s.d:peek()).toBe("large")
		s.c.dispose()
	end)

	t.it("default scrollPolicy never hands a body pan to the sheet, even at offset zero", function()
		local s = mount()
		local body = s.w.adapter.node(`{PANEL}/Room/Column/Body`)
		t.expect(body.touchGestures).toBeNil()
		t.expect(body.props.scrollEnabled ~= false).toBe(true)
		s.c.dispose()
	end)

	t.it(
		"atLargestDetent: below the tallest the body yields its pan; at the tallest only a top downward pan",
		function()
			local s = mount({ scrollPolicy = "atLargestDetent" })
			local BODY = `{PANEL}/Room/Column/Body`
			t.expect(s.w.adapter.node(BODY).props.scrollEnabled).toBe(false)
			pan(s, BODY, "began", 0)
			s.clock.now += 0.3
			pan(s, BODY, "changed", -250)
			s.clock.now += 0.3
			pan(s, BODY, "ended", -250)
			s.w.settle(3)
			t.expect(s.d:peek()).toBe("large")
			t.expect(s.w.adapter.node(BODY).props.scrollEnabled ~= false).toBe(true)
			-- at the tallest, an upward pan is the scroller's
			pan(s, BODY, "began", 0)
			pan(s, BODY, "changed", -100)
			t.expect(s.c.dump().dragging).toBe(false)
			pan(s, BODY, "ended", -100)
			-- mid-scroll: native scroll keeps the whole gesture
			s.w.adapter.setScrollPosition(s.w.adapter.node(BODY), { x = 0, y = 80 })
			pan(s, BODY, "began", 0)
			pan(s, BODY, "changed", 200)
			t.expect(s.c.dump().dragging).toBe(false)
			pan(s, BODY, "ended", 200)
			-- at the top, downward: the sheet shrinks
			s.w.adapter.setScrollPosition(s.w.adapter.node(BODY), { x = 0, y = 0 })
			pan(s, BODY, "began", 0)
			s.clock.now += 0.3
			pan(s, BODY, "changed", 250)
			s.w.settle(1)
			t.expect(s.c.dump().dragging).toBe(true)
			t.expect(s.w.adapter.node(BODY).props.scrollEnabled).toBe(false) -- never two scrollers
			s.clock.now += 0.3
			pan(s, BODY, "ended", 250)
			s.w.settle(3)
			t.expect(s.d:peek()).toBe("medium")
			s.c.dispose()
		end
	)

	t.it("resistance holds a dismissal-disabled sheet near its lowest detent", function()
		local s = mount({ interactiveDismissDisabled = true })
		gripDrag(s, { { 400, 0.5 } }, "touch", false)
		s.w.settle(1)
		t.expect(h(s) >= 300 - 44 and h(s) < 300).toBe(true)
		local r = s.w.adapter.node(GRIP).rect
		s.w.adapter.pointerUp(r.x, r.y)
		s.w.settle(3)
		t.expect(s.c.dump().presented).toBe(true)
		t.expect(h(s)).toBe(300)
		s.c.dispose()
	end)

	t.it("a flick hands its speed to the settle spring; reduced motion snaps", function()
		local s = mount(nil, { reducedMotion = false })
		gripDrag(s, { { -40, 0.01 }, { -40, 0.01 } })
		s.w.tick(1 / 60)
		local early = h(s)
		t.expect(early > 380 and early < 600).toBe(true)
		s.w.settle(120)
		t.expect(h(s)).toBe(600)
		s.c.dispose()
		s = mount()
		gripDrag(s, { { -40, 0.01 }, { -40, 0.01 } })
		t.expect(h(s)).toBe(600)
		s.c.dispose()
	end)

	t.it("disposal mid-drag releases the session and returns to baseline", function()
		local s = mount()
		local baseline = nil
		gripDrag(s, { { -100, 0.1 } }, "touch", false)
		pan(s, PANEL, "began", 0)
		s.c.dispose()
		s.w.settle(3)
		t.expect(s.w.adapter.node(PANEL)).toBeNil()
		t.expect(s.w.core.lastError()).toBe(baseline)
	end)
end)
