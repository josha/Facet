--!strict
--[[ UI.Vote — up/down/none over the caller's value through Picker's private
	submission seam (phase6 P6b). Cases read the MOUNTED selected paint and the
	caller's cell before, during and after each callback. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local world = require("./lib/world")
local Facet = require("../src") :: any
local Compose = Facet.Compose

local ROOT = "/S/Row/V"

local function mount(spec: any, extra: ((UI: any) -> { any })?): any
	local w = world.new({
		viewport = { x = 0, y = 0, w = 800, h = 400 },
		reducedMotion = true,
		capabilities = { mouse = true, keyboard = true, gamepad = true },
		hostOpts = { keyboardNavigation = true },
	})
	local UI = w.UI
	w.present(function()
		local children = { UI.Vote("V")(spec) }
		for _, node in (if extra then extra(UI) else {}) do
			table.insert(children, node)
		end
		return UI.Screen("S")({ UI.HStack("Row")({ gap = "s", table.unpack(children) }) })
	end)
	w.settle(3)
	return w
end

local SEGMENT = { up = "Opt1", down = "Opt2" }

local function option(w: any, side: string): string
	for _, p in w.adapter.paths() do
		if string.sub(p, 1, #ROOT) == ROOT and string.sub(p, -5) == `/{SEGMENT[side]}` then
			return p
		end
	end
	error(`no option {side}`)
end

-- the selected paint ON SCREEN: which segment the sliding bar sits under
local function painted(w: any): string?
	local bar: any = nil
	for _, p in w.adapter.paths() do
		if string.sub(p, 1, #ROOT) == ROOT and string.sub(p, -10) == "/Layer/Bar" then
			bar = w.adapter.node(p)
		end
	end
	if bar == nil or bar.rect == nil or bar.rect.w <= 0 or w.adapter.visibleOf(bar.path or "") == false then
		return nil
	end
	local cx = bar.rect.x + bar.rect.w / 2
	for side in SEGMENT do
		local r = w.adapter.node(option(w, side)).rect
		if cx >= r.x and cx <= r.x + r.w then
			return side
		end
	end
	return nil
end

describe("Vote: controlled proposals", function()
	it("accepts, swaps in one transition, and reselecting proposes none", function()
		local value = Compose.cell("none")
		local seen: { string } = {}
		local w: any
		w = mount({
			value = value,
			onChange = function(next: string)
				-- DURING the callback the caller still holds the old value and paint
				table.insert(seen, `{next}<{value:peek()},{painted(w) or "nil"}>`)
				value:set(next)
			end,
		})
		expect(painted(w)).toBeNil()
		w.adapter.tap(option(w, "up"))
		w.settle(2)
		expect(painted(w)).toBe("up")
		w.adapter.tap(option(w, "down"))
		w.settle(2)
		expect(painted(w)).toBe("down")
		w.adapter.tap(option(w, "down"))
		w.settle(2)
		expect(painted(w)).toBeNil()
		expect(table.concat(seen, " ")).toBe("up<none,nil> down<up,up> none<down,down>")
	end)

	it("a refused proposal never paints and never touches the caller's cell", function()
		local value = Compose.cell("up")
		local asked: { string } = {}
		local w = mount({
			value = value,
			onChange = function(next: string)
				table.insert(asked, next)
			end,
		})
		w.adapter.tap(option(w, "down"))
		w.settle(2)
		w.adapter.tap(option(w, "up"))
		w.settle(2)
		expect(table.concat(asked, ",")).toBe("down,none")
		expect(value:peek()).toBe("up")
		expect(painted(w)).toBe("up")
	end)

	it("keyboard and pad reach the strip and propose through the same path", function()
		local value = Compose.cell("none")
		local w = mount({
			value = value,
			onChange = function(next: string)
				value:set(next)
			end,
		})
		expect(w.pres.focus.focusOn(option(w, "down"))).toBe(true)
		w.press("ButtonA")
		w.settle(2)
		expect(value:peek()).toBe("down")
	end)

	it("a getter or formula value works; an invalid late value keeps the last legal paint", function()
		local source = Compose.cell("up")
		local w = mount({
			value = function(use)
				return use(source)
			end,
			onChange = function(next: string)
				source:set(next)
			end,
		})
		expect(painted(w)).toBe("up")
		source:set("sideways")
		w.settle(2)
		expect(painted(w)).toBe("up")
		expect(#w.record("V").api.diagnostics()).toBe(1)
		source:set("down")
		w.settle(2)
		expect(painted(w)).toBe("down")
	end)

	it("a callback that disposes the vote or throws leaves no stale state", function()
		local show = Compose.cell(true)
		local value = Compose.cell("none")
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 400 }, reducedMotion = true })
		local UI = w.UI
		w.present(function()
			return UI.Screen("S")({
				UI.When("Gate")({
					condition = show,
					thenView = function()
						return UI.Vote("V")({
							value = value,
							onChange = function(next: string)
								value:set(next)
								show:set(false)
							end,
						})
					end,
				}),
			})
		end)
		w.settle(3)
		local up: string? = nil
		for _, p in w.adapter.paths() do
			if string.sub(p, -5) == "/Opt1" then
				up = p
			end
		end
		w.adapter.tap(up :: string)
		w.settle(3)
		expect(value:peek()).toBe("up")
		expect(w.adapter.node("/S/Gate/then/V")).toBeNil()
	end)
end)

describe("Vote: read-only, disabled and composition", function()
	it("readOnly shows the choice with nothing to press or focus; disabled is ordinary disabled paint", function()
		local readOnly = Compose.cell(true)
		local enabled = Compose.cell(true)
		local w = mount({ value = "up", readOnly = readOnly, enabled = enabled, onChange = function() end })
		local up = option(w, "up")
		expect(w.adapter.node(up).onActivate).toBeNil()
		expect(w.pres.focus.focusOn(up)).toBe(false)
		expect(string.find(up, "/Plate/", 1, true) ~= nil).toBe(true)
		readOnly:set(false)
		w.settle(2)
		expect(w.pres.focus.focusOn(option(w, "up"))).toBe(true)
		enabled:set(false)
		w.settle(2)
		expect(w.pres.focus.focusOn(option(w, "down"))).toBe(false)
	end)

	it("a readOnly vote keeps the interactive strip's rung height", function()
		local heights = {}
		for _, readOnly in { false, true } do
			for _, rung in { "compact", "large" } do
				local w = mount({ value = "up", readOnly = readOnly, controlSize = rung, onChange = function() end })
				heights[`{readOnly}/{rung}`] = w.adapter.node(option(w, "up")).rect.h
			end
		end
		expect(heights["true/compact"]).toBe(heights["false/compact"])
		expect(heights["true/large"]).toBe(heights["false/large"])
		expect(heights["true/compact"] < heights["true/large"]).toBe(true)
	end)

	it("a readOnly vote without onChange refuses to become interactive", function()
		local readOnly = Compose.cell(true)
		local w = mount({ value = "down", readOnly = readOnly })
		readOnly:set(false)
		w.settle(2)
		expect(w.record("V").dump().readOnly).toBe(true)
		expect(#w.record("V").api.diagnostics()).toBe(1)
		local v = world.new()
		expect(pcall(function()
			v.scoped(function()
				return v.UI.Vote({ value = "none" })
			end)
		end)).toBe(false)
		-- the seam is private: a public Picker still refuses a borrowed readable
		expect(pcall(function()
			v.scoped(function()
				return v.UI.Picker({
					options = { { value = "a", label = "A" } },
					selected = Compose.formula(function()
						return "a"
					end),
				})
			end)
		end)).toBe(false)
	end)

	it("two votes beside a chip keep separate targets that never overlap, with a disclosed summary", function()
		local a, b = Compose.cell("up"), Compose.cell("none")
		local w = mount({
			value = a,
			summary = "99% liked",
			onChange = function(n: string)
				a:set(n)
			end,
		}, function(UI)
			return {
				UI.Vote("W")({
					value = b,
					controlSize = "compact",
					onChange = function(n: string)
						b:set(n)
					end,
				}),
				UI.Chip("Tag")({ label = "Racing", selected = Compose.cell(false) }),
			}
		end)
		local rects = {}
		for _, p in w.adapter.paths() do
			if string.match(p, "/Opt%d$") or string.sub(p, -4) == "/Tag" then
				-- the EFFECTIVE target: an expanded hit band where one is painted
				table.insert(rects, w.adapter.hitRectOf(p) or w.adapter.node(p).rect)
			end
		end
		expect(#rects).toBe(5)
		for i = 1, #rects do
			for j = i + 1, #rects do
				local r, s = rects[i], rects[j]
				local overlap = r.x < s.x + s.w - 0.5
					and s.x < r.x + r.w - 0.5
					and r.y < s.y + s.h - 0.5
					and s.y < r.y + r.h - 0.5
				expect(overlap).toBe(false)
			end
		end
		local summary = w.adapter.node(`{ROOT}/Summary`)
		expect(summary.props.text).toBe("99% liked")
		expect(b:peek()).toBe("none")
	end)
end)

describe("Vote: the gallery section", function()
	it("the Choices tab's vote repaints only from its caller's value, and its summary follows", function()
		local scenario = require("../examples/gallery/scenarios/selection_controls") :: any
		local w = world.new({ viewport = { x = 0, y = 0, w = 1000, h = 800 }, reducedMotion = true })
		local built =
			scenario.build({ Facet = Facet, UI = w.UI, Compose = Compose, app = w.app, core = w.core, env = w.env })
		w.present(built.screen)
		w.settle(3)
		local function at(suffix: string): string
			for _, p in w.adapter.paths() do
				if string.sub(p, -#suffix) == suffix then
					return p
				end
			end
			error(suffix)
		end
		local summary = at("/TrackVote/Summary")
		expect(w.adapter.node(summary).props.text).toBe("98% liked this")
		w.adapter.tap(at("/TrackVote/Mode/then/Choice/Indicator/Options/Opt1"))
		w.settle(2)
		expect(w.adapter.node(summary).props.text).toBe("You and 98% liked this")
		-- the read-only vote has nothing to press
		expect(w.adapter.node(at("/PastVote/Mode/else/Plate/Marks/Opt2")).onActivate).toBeNil()
	end)
end)

return nil
