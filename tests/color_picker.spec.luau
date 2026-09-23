--!strict
--[[ UI.ColorPicker — a controlled colour well over the caller's Color3 (phase5
	P5a). Cases drive real routes (a tap on the well, a swatch, a drag on the
	plane, a field commit, the right stick, Cancel, a tap outside) and read the
	MOUNTED paint and the caller's value, never a callback's argument alone. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local world = require("./lib/world")
local Facet = require("../src") :: any
local colorValue = require("../src/controls/color_value")
local Compose = Facet.Compose
local Color3 = require("./lib/gui_value_shim").colorValues().Color3

local POINTER = { mouse = true, keyboard = true, touch = false, gamepad = false }
local TOUCH = { mouse = false, keyboard = false, touch = true, gamepad = false }
local PAD = { mouse = false, keyboard = false, touch = false, gamepad = true }

local function mount(spec: any, opts: any?): any
	local o = opts or {}
	local w = world.new({
		viewport = o.viewport or { x = 0, y = 0, w = 900, h = 900 },
		reducedMotion = true,
		capabilities = o.capabilities or POINTER,
		preferredInput = o.preferredInput,
		displaySize = o.displaySize,
		hostOpts = { keyboardNavigation = true },
	})
	local UI = w.UI
	w.present(function()
		return UI.Screen("S")({
			padding = 0,
			UI.VStack("Col")({ width = UI.fill(), UI.ColorPicker("P")(spec), UI.Button("Other")({ label = "Other" }) }),
		})
	end)
	w.settle(3)
	return w
end

-- a caller that accepts every proposal (or refuses every one)
local function caller(initial: any, accept: boolean?): (any, { any }, (any) -> ())
	local cell = Compose.cell(initial)
	local seen: { any } = {}
	return cell,
		seen,
		function(next: any)
			table.insert(seen, next)
			if accept ~= false then
				cell:set(next)
			end
		end
end

local function find(w: any, suffix: string): string?
	for _, p in w.adapter.paths() do
		if string.sub(p, -#suffix) == suffix then
			return p
		end
	end
	return nil
end

local function must(w: any, suffix: string): string
	local p = find(w, suffix)
	assert(p ~= nil, `nothing mounted at *{suffix}`)
	return p
end

local function hex(c: any): string
	return if c == nil then "nil" else colorValue.hex(c)
end

-- the colour the well's plate PAINTS (its direct tint), uppercase
local function painted(w: any, suffix: string): string?
	local n = w.adapter.node(must(w, suffix))
	local tint = n.props.tint
	if type(tint) ~= "table" or tint.direct == nil then
		return nil
	end
	return "#" .. string.upper(string.sub(tint.direct, 2))
end

local function open(w: any)
	w.adapter.tap(must(w, "/P/Well"), { source = "pointer", x = 10, y = 10 })
	w.settle(3)
end

-- type a whole new draft into a field, then Enter (the fake's buffer starts
-- from the shown text, so it is emptied first, as select-all would)
local function typeAndCommit(w: any, path: string, text: string)
	w.adapter.focusText(path)
	w.adapter.node(path).textBuffer = ""
	w.adapter.typeText(path, text)
	w.adapter.commitText(path)
	w.settle(2)
end

local function hueOf(w: any): number
	return math.floor(w.record("P").dump().hsv.h + 0.5)
end

describe("ColorPicker: colour values", function()
	it("parses #RGB, #RRGGBB and #RRGGBBAA (only with alpha) and formats engine bytes uppercase", function()
		local c, a, why = colorValue.parseHex("#abc", false)
		expect(hex(c)).toBe("#AABBCC")
		expect(a).toBeNil()
		c, a = colorValue.parseHex("ff000080", true)
		expect(hex(c)).toBe("#FF0000")
		expect(math.floor((a :: number) * 255 + 0.5)).toBe(128)
		c, _, why = colorValue.parseHex("#ff000080", false)
		expect(c).toBeNil()
		expect(why ~= nil).toBe(true)
		for _, bad in { "", "#12", "#GGGGGG", " #ABCDEF", "#abcdef " } do
			expect(`{bad}:{tostring(colorValue.parseHex(bad, true))}`).toBe(`{bad}:nil`)
		end
		-- the engine's own rounding (0.5 -> 128 -> "80"), measured in Studio
		expect(colorValue.hex(Color3.new(0.5, 0.5, 0.5))).toBe("#808080")
		expect(colorValue.hex(Color3.new(1, 0, 0), 0)).toBe("#FF000000")
	end)

	it("keeps a grey's hue (and a black's saturation) through the engine conversion", function()
		local h = colorValue.hsvOf(Color3.new(0.5, 0.5, 0.5), { h = 0.5, s = 0.7, v = 1 })
		expect(h.h).toBe(0.5)
		expect(h.s).toBe(0)
		local b = colorValue.hsvOf(Color3.new(0, 0, 0), { h = 0.25, s = 0.7, v = 1 })
		expect(`{b.h},{b.s},{b.v}`).toBe("0.25,0.7,0")
		expect(#colorValue.standard()).toBe(48)
		expect(#colorValue.brick()).toBe(128)
	end)

	it("a saturation round trip through the Sliders tab returns to the hue the player set", function()
		local set = Color3.fromHSV(200 / 360, 1, 1)
		local cell, _, change = caller(set)
		local w = mount({ value = cell, onChange = change, style = "inline", modes = { "sliders" } })
		expect(w.pres.focus.focusOn(must(w, "/Saturation/TrackHost/Track"))).toBe(true)
		for _ = 1, 100 do
			w.press("Left")
		end
		w.settle(2)
		expect(hex(cell:peek())).toBe("#FFFFFF")
		expect(hueOf(w)).toBe(200)
		for _ = 1, 100 do
			w.press("Right")
		end
		w.settle(2)
		expect(hueOf(w)).toBe(200)
		expect(hex(cell:peek())).toBe(hex(set))
		-- and through black: value to 0 keeps hue AND saturation
		expect(w.pres.focus.focusOn(must(w, "/Brightness/TrackHost/Track"))).toBe(true)
		for _ = 1, 100 do
			w.press("Left")
		end
		for _ = 1, 100 do
			w.press("Right")
		end
		w.settle(2)
		expect(hex(cell:peek())).toBe(hex(set))
	end)

	it("switching the readout twenty times never moves canonical, and a hex commit is the only write", function()
		local start = Color3.fromHSV(0.61, 0.37, 0.83)
		local cell, seen, change = caller(start)
		local w = mount({ value = cell, onChange = change, style = "inline", modes = { "sliders" } })
		local before = w.record("P").dump().hsv
		for _ = 1, 20 do
			for _, word in { "Opt2", "Opt3", "Opt1" } do
				w.adapter.tap(must(w, `/Format/Indicator/Options/{word}`))
				w.settle(1)
			end
		end
		local after = w.record("P").dump().hsv
		expect(`{after.h},{after.s},{after.v}`).toBe(`{before.h},{before.s},{before.v}`)
		expect(#seen).toBe(0)
		-- a typed hex commits; a bad one stays visible and commits nothing
		w.adapter.tap(must(w, "/Format/Indicator/Options/Opt3"))
		w.settle(2)
		local field = must(w, "/FieldHex/Input/Field")
		typeAndCommit(w, field, "#zz0")
		expect(#seen).toBe(0)
		expect(w.record("P").dump().hexError ~= "").toBe(true)
		expect(w.adapter.node(field).props.text).toBe("#zz0")
		typeAndCommit(w, field, "#0f0")
		expect(hex(cell:peek())).toBe("#00FF00")
		expect(w.record("P").dump().hexError).toBe("")
	end)
end)

describe("ColorPicker: the well and its panel", function()
	it("a bare well is its swatch, named by its value; a labelled one is a form row", function()
		local cell, _, change = caller(Color3.fromRGB(255, 0, 0))
		local w = mount({ value = cell, onChange = change })
		expect(w.record("P").dump().name).toBe("#FF0000")
		expect(find(w, "/P/Well/Row/Chevron")).toBeNil()
		expect(painted(w, "/P/Well/Row/Swatch/Plate")).toBe("#FF0000")
		local rect = w.adapter.node(must(w, "/P/Well")).rect
		expect(rect.w >= 44 and rect.h >= 44).toBe(true)
		local w2 = mount({ value = cell, onChange = change, label = "Kart body", hint = "On the track" })
		expect(w2.record("P").dump().name).toBe("Kart body, #FF0000")
		expect(find(w2, "/P/Well/Row/Chevron") ~= nil).toBe(true)
		expect(w2.adapter.node(must(w2, "/P/Well/Row/Value")).props.text).toBe("#FF0000")
	end)

	it("the well opens an anchored panel on a roomy pointer screen; a refused swatch never paints", function()
		local cell, seen, change = caller(Color3.fromRGB(255, 0, 0), false)
		local w = mount({ value = cell, onChange = change })
		open(w)
		expect(w.record("P").dump().route).toBe("popover")
		expect(w.record("P").dump().presented).toBe(true)
		local cells = w.record("P").dump().swatchPaths
		expect(#cells).toBe(48)
		local held = w.record("P").dump().hsv
		w.adapter.tap(cells[20])
		w.settle(2)
		expect(#seen).toBe(1)
		local after = w.record("P").dump().hsv
		expect(`{after.h},{after.s},{after.v}`).toBe(`{held.h},{held.s},{held.v}`)
		expect(hex(cell:peek())).toBe("#FF0000")
		expect(painted(w, "/P/Well/Row/Swatch/Plate")).toBe("#FF0000")
		expect(painted(w, "/Readout/Head/Preview/Plate")).toBe("#FF0000")
	end)

	it("a tall technique fits the room beside the well: the panel scrolls and never covers it", function()
		local cell, _, change = caller(Color3.fromRGB(255, 0, 0))
		local w = mount(
			{ value = cell, onChange = change, modes = { "swatches", "brick" } },
			{ viewport = { x = 0, y = 0, w = 900, h = 700 } }
		)
		open(w)
		w.adapter.tap(must(w, "/Modes/Indicator/Options/Opt2"))
		w.settle(3)
		local well = w.adapter.node(must(w, "/P/Well")).rect
		local surface = w.adapter.node(must(w, "/Popover-P/Layer/Surface")).rect
		expect(surface.y + surface.h <= 700).toBe(true)
		expect(surface.y >= well.y + well.h).toBe(true)
		expect(find(w, "/BrickGrid") ~= nil).toBe(true)
	end)

	it("an accepted swatch commits once, marks the cell, and the swatch grid walks in two dimensions", function()
		local cell, _, change = caller(Color3.fromRGB(255, 0, 0))
		local commits = {}
		local w = mount({
			value = cell,
			onChange = change,
			onCommit = function(c: any)
				table.insert(commits, hex(c))
			end,
		})
		open(w)
		local cells = w.record("P").dump().swatchPaths
		local columns = w.record("P").dump().columns
		expect(columns).toBe(8)
		w.adapter.tap(cells[3])
		w.settle(2)
		local chosen = hex(cell:peek())
		expect(table.concat(commits, ",")).toBe(chosen)
		expect(w.adapter.visibleOf(cells[3] .. "/Layers/Check")).toBe(true)
		w.pres.focus.setFocusOrigin("navigation")
		expect(w.pres.focus.focusOn(cells[3])).toBe(true)
		w.press("Down")
		w.settle(1)
		expect(w.pres.focus.focused:peek()).toBe(cells[3 + columns])
		w.press("Right")
		w.settle(1)
		expect(w.pres.focus.focused:peek()).toBe(cells[4 + columns])
	end)

	it("a short swatch list keeps square target cells, and the default grid stays a hue per column", function()
		local cell, _, change = caller(Color3.fromRGB(255, 196, 0))
		local w = mount({
			value = cell,
			onChange = change,
			swatches = { { color = Color3.fromRGB(255, 196, 0) }, { color = Color3.fromRGB(20, 20, 24) } },
		})
		open(w)
		for _, path in w.record("P").dump().swatchPaths do
			local r = w.adapter.node(path).rect
			expect(`{r.w}x{r.h}`).toBe("44x44")
		end
		-- the standard grid at seven columns: each column one hue down every step
		local seven = colorValue.standard(7)
		expect(#seven).toBe(42)
		for column = 1, 7 do
			local hues = {}
			for row = 0, 4 do
				local h = colorValue.hsvOf(seven[row * 7 + column].color).h
				hues[math.floor(h * 360 + 0.5)] = true
			end
			local distinct = 0
			for _ in hues do
				distinct += 1
			end
			expect(distinct).toBe(1)
		end
	end)

	it("without draft every change commits live and B or an outside tap only closes, keeping it", function()
		local startColor = Color3.fromRGB(10, 20, 30)
		local cell, _, change = caller(startColor)
		local reasons, commits = {}, {}
		local w = mount({
			value = cell,
			onChange = change,
			onCommit = function(c: any)
				table.insert(commits, hex(c))
			end,
			onDismiss = function(r: string)
				table.insert(reasons, r)
			end,
		})
		open(w)
		w.adapter.tap(w.record("P").dump().swatchPaths[5])
		w.settle(2)
		local picked = hex(cell:peek())
		expect(picked ~= hex(startColor)).toBe(true)
		w.press("ButtonB")
		w.settle(3)
		expect(w.record("P").dump().presented).toBe(false)
		-- the owner's last commit and the shown value agree: nothing was restored
		expect(hex(cell:peek())).toBe(picked)
		expect(table.concat(commits, ",")).toBe(picked)
		open(w)
		w.adapter.tap(w.record("P").dump().swatchPaths[6])
		w.settle(2)
		local kept = hex(cell:peek())
		w.adapter.tap(w.pres.topScrimPath() :: string, { x = 890, y = 890 })
		w.settle(3)
		expect(w.record("P").dump().presented).toBe(false)
		expect(hex(cell:peek())).toBe(kept)
		expect(table.concat(reasons, ",")).toBe("cancel,outside")
	end)

	it("draft: B and an outside tap discard, restoring the open-time colour; a caller write re-bases it", function()
		local startColor = Color3.fromRGB(10, 20, 30)
		local cell, seen, change = caller(startColor)
		local w = mount({ value = cell, onChange = change, draft = true })
		open(w)
		w.adapter.tap(w.record("P").dump().swatchPaths[5])
		w.settle(2)
		w.press("ButtonB")
		w.settle(3)
		expect(hex(cell:peek())).toBe(hex(startColor))
		expect(hex(seen[#seen])).toBe(hex(startColor))
		open(w)
		w.adapter.tap(w.record("P").dump().swatchPaths[6])
		w.settle(2)
		w.adapter.tap(w.pres.topScrimPath() :: string, { x = 890, y = 890 })
		w.settle(3)
		expect(hex(cell:peek())).toBe(hex(startColor))
		open(w)
		local server = Color3.fromRGB(200, 100, 50)
		cell:set(server)
		w.settle(2)
		w.adapter.tap(w.record("P").dump().swatchPaths[7])
		w.settle(2)
		w.press("ButtonB")
		w.settle(3)
		expect(hex(cell:peek())).toBe(hex(server))
	end)

	it("draft: gestures propose live but commit nothing; Apply commits once and Cancel restores", function()
		local startColor = Color3.fromRGB(10, 20, 30)
		local cell, _, change = caller(startColor)
		local commits = {}
		local w = mount({
			value = cell,
			onChange = change,
			draft = true,
			onCommit = function(c: any)
				table.insert(commits, hex(c))
			end,
		})
		open(w)
		-- Apply is the primary action: the accent, beside a plain Cancel
		expect(w.adapter.node(must(w, "/Actions/Apply")).props.surface).toBe("accent")
		expect(w.adapter.node(must(w, "/Actions/Cancel")).props.surface == "accent").toBe(false)
		w.adapter.tap(w.record("P").dump().swatchPaths[9])
		w.settle(2)
		expect(#commits).toBe(0)
		w.adapter.tap(must(w, "/Actions/Cancel"))
		w.settle(3)
		expect(hex(cell:peek())).toBe(hex(startColor))
		expect(#commits).toBe(0)
		open(w)
		w.adapter.tap(w.record("P").dump().swatchPaths[9])
		w.settle(2)
		w.adapter.tap(must(w, "/Actions/Apply"))
		w.settle(3)
		expect(table.concat(commits, ",")).toBe(hex(cell:peek()))
		expect(w.record("P").dump().presented).toBe(false)
	end)

	it(
		"opens as a hug sheet with Done on a compact touch screen, and a centred sheet at ten feet with the plane",
		function()
			local cell, _, change = caller(Color3.fromRGB(255, 0, 0))
			local w = mount(
				{ value = cell, onChange = change },
				{ capabilities = TOUCH, preferredInput = "Touch", viewport = { x = 0, y = 0, w = 390, h = 844 } }
			)
			w.adapter.tap(must(w, "/P/Well"))
			w.settle(3)
			expect(w.record("P").dump().route).toBe("sheet")
			expect(find(w, "/Actions/Done") ~= nil).toBe(true)
			-- one size: no inert Size control
			expect(w.adapter.visibleOf(must(w, "/Header/Size"))).toBe(false)
			-- a slow vertical drag on the plane moves brightness, never the sheet
			w.adapter.tap(must(w, "/Modes/Indicator/Options/Opt2"))
			w.settle(3)
			local sheetPanel = must(w, "/Popover-P/Layer/Panel")
			local top = w.adapter.node(sheetPanel).rect.y
			local surface = must(w, "/Plane/Surface")
			local r = w.adapter.node(surface).rect
			local v0 = w.record("P").dump().hsv.v
			w.adapter.pointerDown(surface, r.x + r.w / 2, r.y + r.h * 0.2, "touch")
			for step = 1, 10 do
				w.adapter.pointerMove(r.x + r.w / 2, r.y + r.h * (0.2 + step * 0.05))
				w.settle(1)
			end
			w.adapter.pointerUp(r.x + r.w / 2, r.y + r.h * 0.7)
			w.settle(2)
			expect(w.record("P").dump().hsv.v < v0 - 20).toBe(true)
			expect(w.adapter.node(sheetPanel).rect.y).toBe(top)
			-- the hug sheet re-measures above the on-screen keyboard
			w.env:set("keyboardOcclusionRect", { x = 0, y = 500, w = 390, h = 344 })
			w.settle(3)
			local lifted = w.adapter.node(sheetPanel).rect
			expect(lifted.y + lifted.h <= 500 + 0.5).toBe(true)
			w.env:set("keyboardOcclusionRect", nil)
			w.settle(3)
			-- three techniques stay a strip; four on a phone are a menu, never cut words
			expect(find(w, "/Modes/Indicator/Options/Opt3") ~= nil).toBe(true)
			local four = mount(
				{ value = cell, onChange = change, modes = { "swatches", "spectrum", "sliders", "brick" } },
				{ capabilities = TOUCH, preferredInput = "Touch", viewport = { x = 0, y = 0, w = 390, h = 844 } }
			)
			four.adapter.tap(must(four, "/P/Well"))
			four.settle(3)
			expect(find(four, "/Modes") ~= nil).toBe(true)
			expect(find(four, "/Modes/Indicator/Options/Opt1")).toBeNil()
			local tv = mount(
				{ value = cell, onChange = change, modes = { "spectrum", "swatches" } },
				{ capabilities = PAD, preferredInput = "Gamepad", displaySize = "Large" }
			)
			tv.pres.focus.focusOn(must(tv, "/P/Well"))
			tv.press("ButtonA")
			tv.settle(3)
			expect(tv.record("P").dump().route).toBe("sheet")
			expect(find(tv, "/Plane/Surface") ~= nil).toBe(true)
		end
	)
end)

describe("ColorPicker: the spectrum plane", function()
	local function spectrum(opts: any?): (any, any, { string })
		local cell, _, change = caller(Color3.fromHSV(0.5, 0.5, 0.5))
		local commits = {}
		local w = mount({
			value = cell,
			onChange = change,
			style = "inline",
			modes = { "spectrum" },
			onCommit = function(c: any)
				table.insert(commits, hex(c))
			end,
		}, opts)
		return w, cell, commits
	end

	it("a drag tracks 1:1 in saturation and value, keeps the hue, and commits once at release", function()
		local w, cell, commits = spectrum()
		local surface = must(w, "/Plane/Surface")
		local r = w.adapter.node(surface).rect
		w.adapter.pointerDown(surface, r.x + r.w * 0.25, r.y + r.h * 0.5)
		w.adapter.pointerMove(r.x + r.w * 0.75, r.y + r.h * 0.25)
		w.settle(1)
		local mid = w.record("P").dump().hsv
		expect(math.floor(mid.s + 0.5)).toBe(75)
		expect(math.floor(mid.v + 0.5)).toBe(75)
		expect(math.floor(mid.h + 0.5)).toBe(180)
		expect(#commits).toBe(0)
		w.adapter.pointerUp(r.x + r.w * 0.75, r.y + r.h * 0.25)
		w.settle(2)
		expect(#commits).toBe(1)
		expect(commits[1]).toBe(hex(cell:peek()))
		-- the ring sits where the colour is
		local ring = w.adapter.node(must(w, "/Marks/Ring")).rect
		expect(math.abs(ring.x + ring.w / 2 - (r.x + r.w * 0.75)) <= 1).toBe(true)
		-- at a corner the whole ring stays on the plane, where no edge clips it
		w.adapter.pointerDown(surface, r.x + r.w, r.y)
		w.adapter.pointerUp(r.x + r.w, r.y)
		w.settle(2)
		ring = w.adapter.node(must(w, "/Marks/Ring")).rect
		expect(ring.x + ring.w <= r.x + r.w and ring.y >= r.y).toBe(true)
	end)

	it("the native drag detector follows the plane through a tab round trip", function()
		local cell, _, change = caller(Color3.fromHSV(0.5, 0.5, 0.5))
		local w = mount({ value = cell, onChange = change, style = "inline", modes = { "spectrum", "sliders" } })
		local function driveTo(fx: number)
			local surface = must(w, "/Plane/Surface")
			local r = w.adapter.node(surface).rect
			w.adapter.driveDragStart(surface, { x = r.x + r.w * fx, y = r.y + r.h / 2 })
			w.adapter.driveDragEnd(surface, { x = r.x + r.w * fx, y = r.y + r.h / 2 })
			w.settle(2)
		end
		driveTo(0.2)
		expect(math.floor(w.record("P").dump().hsv.s + 0.5)).toBe(20)
		w.adapter.tap(must(w, "/Modes/Indicator/Options/Opt2"))
		w.settle(2)
		w.adapter.tap(must(w, "/Modes/Indicator/Options/Opt1"))
		w.settle(2)
		driveTo(0.8)
		expect(math.floor(w.record("P").dump().hsv.s + 0.5)).toBe(80)
	end)

	it("losing the pointer class mid-drag restores where the drag began", function()
		local w, cell = spectrum()
		local before = hex(cell:peek())
		local surface = must(w, "/Plane/Surface")
		local r = w.adapter.node(surface).rect
		w.adapter.pointerDown(surface, r.x + 5, r.y + 5)
		w.settle(1)
		expect(hex(cell:peek()) ~= before).toBe(true)
		w.env:set("capabilities", { keyboard = true, mouse = false, touch = false, gamepad = true })
		w.settle(2)
		expect(hex(cell:peek())).toBe(before)
	end)

	it("the right stick steers the plane only while it holds focus, and a live hint says so", function()
		local w, cell, commits = spectrum({ capabilities = PAD, preferredInput = "Gamepad" })
		local surface = must(w, "/Plane/Surface")
		local before = w.record("P").dump().hsv
		-- not focused: the stick is ignored
		w.pres.focus.setFocusOrigin("navigation")
		expect(w.pres.focus.focusOn("/S/Col/Other")).toBe(true)
		w.settle(1)
		w.system.deviceAxis("Thumbstick2", 1, 0)
		w.settle(10)
		w.system.deviceAxis("Thumbstick2", 0, 0)
		w.settle(1)
		expect(w.record("P").dump().hsv.s).toBe(before.s)
		expect(w.adapter.visibleOf(must(w, "/StickHint"))).toBe(false)
		expect(w.pres.focus.focusOn(surface)).toBe(true)
		w.settle(1)
		expect(w.adapter.visibleOf(must(w, "/StickHint"))).toBe(true)
		w.system.deviceAxis("Thumbstick2", 1, 0)
		w.settle(30)
		w.system.deviceAxis("Thumbstick2", 0, 0)
		w.settle(1)
		local after = w.record("P").dump().hsv
		expect(after.s > before.s + 10).toBe(true)
		expect(math.floor(after.v + 0.5)).toBe(math.floor(before.v + 0.5))
		expect(#commits).toBe(1)
		-- each stick session is released when it ends: the owner does not grow
		local held = w.record("P").dump().owned
		for _ = 1, 5 do
			w.system.deviceAxis("Thumbstick2", 0, 1)
			w.settle(2)
			w.system.deviceAxis("Thumbstick2", 0, 0)
			w.settle(1)
		end
		expect(w.record("P").dump().owned).toBe(held)
		expect(#commits).toBe(6)
		-- the left stick / D-pad still navigate away, and leaving mid-steer commits
		expect(w.pres.focus.focused:peek()).toBe(surface)
		w.system.deviceAxis("Thumbstick2", -1, 0)
		w.settle(2)
		w.press("DPadDown")
		w.settle(1)
		expect(w.pres.focus.focused:peek() ~= surface).toBe(true)
		expect(#commits).toBe(7)
		expect(commits[7]).toBe(hex(cell:peek()))
	end)
end)

describe("ColorPicker: the gallery tab", function()
	it("the Pickers scenario's committed line follows a commit, and a refusal changes nothing", function()
		local scenario = require("../examples/gallery/scenarios/pickers") :: any
		local w = world.new({ viewport = { x = 0, y = 0, w = 1000, h = 900 }, reducedMotion = true })
		local built = scenario.build({
			Facet = Facet,
			UI = w.UI,
			Compose = Compose,
			Color3 = Color3,
			app = w.app,
			core = w.core,
			env = w.env,
		})
		w.present(built.screen)
		w.settle(3)
		local line = must(w, "/Pickers/Committed")
		expect(w.adapter.node(line).props.text).toBe("Committed: nothing yet")
		-- the Trim row reads from the page's leading edge, like its neighbours
		expect(w.adapter.node(must(w, "/Pickers/Wells")).rect.x).toBe(w.adapter.node(line).rect.x)
		w.adapter.tap(must(w, "/Trim/Well"), { source = "pointer", x = 10, y = 10 })
		w.settle(3)
		local cells = w.record("Trim").dump().swatchPaths
		expect(#cells).toBe(4)
		w.adapter.tap(cells[4])
		w.settle(2)
		expect(w.adapter.node(line).props.text).toBe("Committed: #00AA8C")
		expect(painted(w, "/Trim/Well/Row/Swatch/Plate")).toBe("#00AA8C")
		w.adapter.tap(w.pres.topScrimPath() :: string, { x = 990, y = 890 })
		w.settle(3)
		w.adapter.tap(must(w, "/Pickers/Refuse"))
		w.settle(2)
		w.adapter.tap(must(w, "/Trim/Well"), { source = "pointer", x = 10, y = 10 })
		w.settle(3)
		w.adapter.tap(w.record("Trim").dump().swatchPaths[2])
		w.settle(2)
		expect(painted(w, "/Trim/Well/Row/Swatch/Plate")).toBe("#00AA8C")
		expect(w.adapter.node(line).props.text).toBe("Committed: #00AA8C")
	end)
end)

describe("ColorPicker: alpha, empty, disabled and refusals", function()
	it("alpha mounts opacity, writes #RRGGBBAA, and shows the checker under a translucent colour", function()
		local cell, _, change = caller(Color3.fromRGB(255, 0, 0))
		local a = Compose.cell(0.5)
		local w = mount({
			value = cell,
			onChange = change,
			alpha = a,
			onAlphaChange = function(n: number)
				a:set(n)
			end,
			label = "Tint",
		})
		expect(w.adapter.node(must(w, "/P/Well/Row/Value")).props.text).toBe("#FF000080")
		expect(w.adapter.visibleOf(must(w, "/P/Well/Row/Swatch/Checker"))).toBe(true)
		open(w)
		local track = must(w, "/Opacity/TrackHost/Track")
		expect(w.pres.focus.focusOn(track)).toBe(true)
		for _ = 1, 60 do
			w.press("Right")
		end
		w.settle(2)
		expect(a:peek()).toBe(1)
		expect(w.adapter.visibleOf(must(w, "/P/Well/Row/Swatch/Checker"))).toBe(false)
		-- the hex error names the alpha form the field shows
		w.adapter.tap(must(w, "/Format/Indicator/Options/Opt3"))
		w.settle(2)
		typeAndCommit(w, must(w, "/FieldHex/Input/Field"), "zz")
		expect(string.find(w.record("P").dump().hexError, "#RRGGBBAA", 1, true) ~= nil).toBe(true)
		local plain = mount({ value = cell, onChange = change })
		open(plain)
		expect(find(plain, "/Opacity/TrackHost/Track")).toBeNil()
	end)

	it("the Bricks tab names the chosen brick in a field above its grid", function()
		local cell, _, change = caller(Color3.fromRGB(255, 0, 0))
		local w = mount({ value = cell, onChange = change, style = "inline", modes = { "brick" } })
		w.adapter.tap(w.record("P").dump().swatchPaths[1])
		w.settle(2)
		local name = w.adapter.node(must(w, "/Brick/NameField/BrickName"))
		expect(name.props.text).toBe(w.record("P").dump().swatchPaths[1]:match("%[(.-)%]"))
		expect(name.rect.y < w.adapter.node(must(w, "/Brick/BrickGrid")).rect.y).toBe(true)
	end)

	it("the plane is two exact layers, the strips show what they select, and the thumbs are two-tone rings", function()
		local cell, _, change = caller(Color3.fromRGB(46, 125, 255))
		local a = Compose.cell(1)
		local w = mount({
			value = cell,
			onChange = change,
			style = "inline",
			modes = { "spectrum" },
			alpha = a,
			onAlphaChange = function(n: number)
				a:set(n)
			end,
		})
		-- saturation across (white -> the hue), value down (black fading in): no bands
		local hue = w.adapter.node(must(w, "/Plane/Field/Hue")).props.gradient
		expect(`{hue.rotation} {#hue.colors}`).toBe("0 2")
		local fade = w.adapter.node(must(w, "/Plane/Field/Value")).props.gradient
		expect(`{fade.rotation} {fade.transparency[1].v} -> {fade.transparency[2].v}`).toBe("90 1 -> 0")
		expect(find(w, "/Plane/Field/Band1")).toBeNil()
		-- the hue track is the rainbow and the alpha track the colour over a checker
		expect(find(w, "/Hue/TrackHost/Groove/Rail/HueStrip/Legs/Leg6") ~= nil).toBe(true)
		expect(find(w, "/Hue/TrackHost/Groove/Fill")).toBeNil()
		expect(painted(w, "/Opacity/TrackHost/Groove/Rail/AlphaStrip/Ramp")).toBe("#2E7DFF")
		expect(find(w, "/AlphaStrip/Checker/Top/C24") ~= nil).toBe(true)
		-- a white band between two dark hairlines, on the plane and on both strips
		local ring = w.adapter.node(must(w, "/Plane/Marks/Ring"))
		local band = w.adapter.node(must(w, "/Plane/Marks/Ring/Band"))
		local function level(stroke: any): number
			return stroke.color.r + stroke.color.g + stroke.color.b
		end
		expect(`{level(ring.props.stroke)} {level(band.props.stroke)}`).toBe("0 3")
		expect(`{ring.props.stroke.transparency} {band.props.stroke.transparency}`).toBe("0 0")
		expect(find(w, "/Hue/TrackHost/Groove/Thumb/Ring/Band") ~= nil).toBe(true)
		expect(find(w, "/Opacity/TrackHost/Groove/Thumb/Ring/Band") ~= nil).toBe(true)
	end)

	it("empty shows the placeholder and the crossed plate; disabled keeps its colour and does not open", function()
		local cell, _, change = caller(nil)
		local w = mount({ value = cell, onChange = change, allowEmpty = true, label = "Trim", placeholder = "None" })
		expect(w.adapter.node(must(w, "/P/Well/Row/Value")).props.text).toBe("None")
		expect(w.adapter.visibleOf(must(w, "/P/Well/Row/Swatch/Empty"))).toBe(true)
		local red, _, change2 = caller(Color3.fromRGB(255, 0, 0))
		local off = mount({ value = red, onChange = change2, enabled = false })
		expect(painted(off, "/P/Well/Row/Swatch/Plate")).toBe("#FF0000")
		open(off)
		expect(off.record("P").dump().presented).toBe(false)
	end)

	it("refuses a malformed contract at construction and quarantines a late bad value", function()
		local w = world.new({ reducedMotion = true })
		local function build(spec: any): string
			local ok, err = pcall(function()
				w.scoped(function()
					w.UI.ColorPicker(spec)
				end)
			end)
			return if ok then "ok" else tostring(err)
		end
		local red = Color3.fromRGB(255, 0, 0)
		local noop = function() end
		expect(string.find(build({ value = "red", onChange = noop }), "Color3", 1, true) ~= nil).toBe(true)
		expect(string.find(build({ value = red }), "onChange", 1, true) ~= nil).toBe(true)
		expect(string.find(build({ value = red, onChange = noop, alpha = 0.5 }), "onAlphaChange", 1, true) ~= nil).toBe(
			true
		)
		expect(string.find(build({ value = red, onChange = noop, modes = { "wheel" } }), "modes", 1, true) ~= nil).toBe(
			true
		)
		expect(string.find(build({ value = red, onChange = noop, swatches = { red, red } }), "repeats", 1, true) ~= nil).toBe(
			true
		)
		expect(
			string.find(
				build({ value = red, onChange = noop, swatches = { { color = red, lable = "Red" } } }),
				"lable",
				1,
				true
			) ~= nil
		).toBe(true)
		expect(
			string.find(
				build({ value = red, onChange = noop, style = "inline", isPresented = true }),
				"inline",
				1,
				true
			) ~= nil
		).toBe(true)
		expect(build({ value = red, onChange = noop, shape = "circle" }) ~= "ok").toBe(true)
		local source = Compose.cell(red :: any)
		local m = mount({
			value = function(use)
				return use(source)
			end,
			onChange = noop,
		})
		source:set("blue")
		m.settle(2)
		expect(painted(m, "/P/Well/Row/Swatch/Plate")).toBe("#FF0000")
		expect(#m.record("P").api.diagnostics()).toBe(1)
	end)
end)
